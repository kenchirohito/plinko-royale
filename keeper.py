#!/usr/bin/env python3
"""Plinko Royale keeper — BSC TESTNET (chain 97) only.

Watches PlinkoRoyale rounds and performs the permissionless housekeeping
anyone may do, so demo rounds do not stall waiting for a human click:

  phase 1 (AwaitingDraw, >=2 players)  -> draw(roundId) with VRF fee
  phase 2 (AwaitingRandom, word set)   -> settle(roundId)
  refund conditions met                -> refund(roundId)

Safety model (read this before running):
- DRY-RUN BY DEFAULT. Without --live this script only READS the chain
  and prints what it *would* send. No key is loaded in dry-run mode.
- --live loads a TESTNET-ONLY key from --key-file (default:
  testnet/keys/deployer.txt, the same file agent-round.sh uses). The key
  is never printed or logged. Never point this at a mainnet key: the
  script refuses to send unless the RPC reports chain ID 97.
- The keeper wallet must be an EOA (or a contract with receive()):
  draw() refunds excess VRF fee in the same tx (audit L-3).
- Every send uses legacy txs (--legacy), required on BSC testnet.
  Gas price is fetched from the RPC each pass (eth_gasPrice, floored at
  0.1 gwei) instead of hardcoded, so the same script shape works on
  mainnet where a fixed 0.1 gwei could stall in the mempool
  (external audit MEDIUM-2).
- The scan window covers the last 21 rounds (current_id-20 .. current),
  wider than the 1-hour refund timeouts (12 rounds), so timeout refunds
  are actually reachable (external audit MEDIUM-2). Refund timing uses
  the contract's drawRequestedAtOf view — exact, no keeper-side guess.
- State (last attempt per round+action, first-seen time per round) is
  kept in keeper-state.json next to this file so restarts do not
  double-send. Delete the state file to reset.

Usage:
  python3 keeper.py --once            # one read-only pass (dry-run)
  python3 keeper.py --once --live     # one pass, sends if needed
  python3 keeper.py --loop --live     # poll every 15s (VPS / tmux)
  python3 keeper.py --once --live --no-refund   # never refund

Cron alternative (every minute, one pass):
  * * * * * cd ~/workspace/plinko-royale && python3 keeper.py --once --live >> keeper.log 2>&1

Costs on testnet: draw pays the Chainlink VRF fee (~0.00003 tBNB at
0.1 gwei in the verified rounds; excess is refunded) + gas. Keep the
keeper wallet topped up with tBNB from the faucet. On mainnet this same
shape applies, but the fee is real BNB — fund the keeper from the
operational fee, use a dedicated low-balance EOA, and re-verify the
VRF wrapper address first (see llms-plinko.txt, "Mainnet").
"""

import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

# --- constants (testnet; see llms-plinko.txt) -------------------------------
GAME = "0x4f65C6db7ECA6E81B7fb139D0d539b5ae2E1d614"
RPCS = [
    "https://data-seed-prebsc-1-s1.bnbchain.org:8545",
    "https://bsc-testnet-rpc.publicnode.com",
]
EXPECTED_CHAIN_ID = 97
CAST = str(Path.home() / ".foundry" / "bin" / "cast")
GAS_PRICE_FLOOR_WEI = 100_000_000  # 0.1 gwei floor; actual price fetched per pass
SCAN_BACK_ROUNDS = 20  # > 1h of rounds (12), so timeout refunds are reachable
STATE_FILE = Path(__file__).with_name("keeper-state.json")
DEFAULT_KEY_FILE = Path(__file__).with_name("testnet") / "keys" / "deployer.txt"

PHASE_NAMES = {0: "Open", 1: "AwaitingDraw", 2: "AwaitingRandom", 3: "Settled", 4: "Refunded"}
DRAW_TIMEOUT = 3600
RANDOM_TIMEOUT = 3600
ATTEMPT_COOLDOWN_S = 120


def log(msg: str) -> None:
    ts = time.strftime("%Y-%m-%d %H:%M:%S %z", time.localtime())
    print(f"[{ts}] {msg}", flush=True)


def run_cast(args: list[str], rpc: str) -> str:
    """Run cast with one RPC; return stdout or raise RuntimeError."""
    cmd = [CAST] + args + ["--rpc-url", rpc]
    out = subprocess.run(cmd, capture_output=True, text=True, timeout=60)
    if out.returncode != 0:
        raise RuntimeError((out.stderr or out.stdout).strip()[:300])
    return out.stdout


def call(rpc: str, sig: str, *args: str) -> list[str]:
    """eth_call via cast; returns first token of each output line.

    cast prints one return value per line, sometimes followed by a
    human annotation like [1e18]; the first whitespace token is the
    raw value (same convention as agent-round.sh's awk '{print $1}').
    """
    raw = run_cast(["call", GAME, sig, *args], rpc)
    vals = []
    for line in raw.strip().splitlines():
        line = line.strip()
        if line:
            vals.append(line.split()[0])
    return vals


def pick_rpc() -> str:
    """First RPC that answers chain-id == 97; refuse anything else."""
    errors = []
    for rpc in RPCS:
        try:
            cid = run_cast(["chain-id"], rpc).strip().split()[0]
            if int(cid) == EXPECTED_CHAIN_ID:
                return rpc
            errors.append(f"{rpc}: chain-id {cid} != {EXPECTED_CHAIN_ID}")
        except Exception as e:  # noqa: BLE001 - report and try next RPC
            errors.append(f"{rpc}: {e}")
    raise SystemExit("No usable BSC testnet RPC:\n" + "\n".join(errors))


def load_key(key_file: Path) -> str:
    text = key_file.read_text()
    m = re.search(r"0x[0-9a-fA-F]{64}", text)
    if not m:
        raise SystemExit(f"No private key found in {key_file}")
    return m.group(0)


def load_state() -> dict:
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text())
        except json.JSONDecodeError:
            log("WARN keeper-state.json unreadable; starting fresh")
    return {"attempts": {}, "first_seen": {}}


def save_state(state: dict) -> None:
    STATE_FILE.write_text(json.dumps(state, indent=2))


def send(rpc: str, key: str, label: str, sig: str, *args: str,
         value: int = 0, gas_price: int = GAS_PRICE_FLOOR_WEI) -> str | None:
    """cast send; returns tx hash or None. Never logs the key."""
    cmd = ["send", "--private-key", key, "--legacy", "--gas-price", str(gas_price), GAME, sig, *args]
    if value:
        cmd += ["--value", str(value)]
    try:
        out = run_cast(cmd, rpc)
    except RuntimeError as e:
        log(f"FAIL {label}: {e}")
        return None
    m = re.search(r"transactionHash\s+(0x[0-9a-fA-F]{64})", out)
    tx = m.group(1) if m else "?"
    log(f"OK   {label} tx={tx}")
    return tx


def round_detail(rpc: str, rid: int) -> dict:
    v = call(
        rpc,
        "roundDetail(uint256)(uint8,uint64,uint64,uint256,uint256,uint256,uint256,uint256,uint256)",
        str(rid),
    )
    keys = ["phase", "opensAt", "closesAt", "totalStaked", "playerCount",
            "requestId", "burned", "feePaid", "dust"]
    return {k: int(x) for k, x in zip(keys, v)}


def fetch_gas_price(rpc: str) -> int:
    """Current gas price from the RPC, floored (external audit MEDIUM-2)."""
    try:
        gp = int(run_cast(["gas-price"], rpc).strip().split()[0])
        return max(gp, GAS_PRICE_FLOOR_WEI)
    except Exception as e:  # noqa: BLE001 - fall back to the floor
        log(f"WARN gas-price fetch failed ({e}); using floor {GAS_PRICE_FLOOR_WEI}")
        return GAS_PRICE_FLOOR_WEI


def one_pass(rpc: str, live: bool, key: str | None, allow_refund: bool, state: dict) -> None:
    cur = call(rpc, "currentRound()(uint256,uint64,uint64)")
    current_id, _opens, _closes = (int(x) for x in cur[:3])
    now = int(time.time())
    gas_price = fetch_gas_price(rpc)
    log(f"currentRound={current_id} mode={'LIVE' if live else 'DRY-RUN'} gasPrice={gas_price}")

    # Prune state for rounds far behind the scan window.
    for bucket in ("attempts", "first_seen"):
        for k in list(state.get(bucket, {})):
            try:
                if int(k.split(":")[0]) < current_id - SCAN_BACK_ROUNDS - 10:
                    del state[bucket][k]
            except ValueError:
                pass

    # Scan the last SCAN_BACK_ROUNDS+1 rounds: a round that just closed
    # still needs draw/settle while the next one is already open, and the
    # 1-hour refund timeouts only become reachable 12 rounds later — the
    # window must be wider than that (external audit MEDIUM-2).
    for rid in range(max(0, current_id - SCAN_BACK_ROUNDS), current_id + 1):
        d = round_detail(rpc, rid)
        phase = d["phase"]
        players = d["playerCount"]
        state["first_seen"].setdefault(str(rid), now)
        log(f"round {rid}: phase={phase}({PHASE_NAMES.get(phase, '?')}) "
            f"players={players} pot={d['totalStaked']} closesAt={d['closesAt']}")

        action = None
        value = 0
        if phase == 1 and players >= 2:
            fee = int(call(rpc, "drawFee(uint256)(uint256)", str(gas_price))[0])
            value = fee * 150 // 100  # +50% buffer; contract refunds excess
            action = ("draw", f"draw({rid}) fee={fee} sending={value}")
        elif phase == 2:
            received = call(rpc, "wordReceivedOf(uint256)(bool)", str(rid))[0] == "true"
            if received:
                action = ("settle", f"settle({rid}) word arrived")
            elif allow_refund:
                dra = int(call(rpc, "drawRequestedAtOf(uint256)(uint256)", str(rid))[0])
                if dra > 0 and now > dra + RANDOM_TIMEOUT:
                    action = ("refund", f"refund({rid}) no word since drawRequestedAt={dra} (>{RANDOM_TIMEOUT}s)")
                else:
                    log(f"round {rid}: waiting for VRF word (drawRequestedAt={dra})")
            else:
                log(f"round {rid}: waiting for VRF word")
        elif phase == 1 and allow_refund and (players < 2 or now > d["closesAt"] + DRAW_TIMEOUT):
            action = ("refund", f"refund({rid}) players={players}")

        if action is None:
            continue
        name, desc = action
        attempt_key = f"{rid}:{name}"
        last = int(state["attempts"].get(attempt_key, 0))
        if now - last < ATTEMPT_COOLDOWN_S:
            log(f"round {rid}: skip {name} (attempted {now - last}s ago, cooldown {ATTEMPT_COOLDOWN_S}s)")
            continue
        if not live:
            log(f"DRY-RUN would {desc}")
            continue
        assert key is not None  # guaranteed by main() when live
        state["attempts"][attempt_key] = now
        save_state(state)
        if name == "draw":
            send(rpc, key, desc, "draw(uint256)", str(rid), value=value, gas_price=gas_price)
        elif name == "settle":
            send(rpc, key, desc, "settle(uint256)", str(rid), gas_price=gas_price)
        else:
            send(rpc, key, desc, "refund(uint256)", str(rid), gas_price=gas_price)

    save_state(state)


def main() -> int:
    ap = argparse.ArgumentParser(description="Plinko Royale testnet keeper (dry-run by default)")
    ap.add_argument("--once", action="store_true", help="single pass then exit (default)")
    ap.add_argument("--loop", action="store_true", help="poll forever")
    ap.add_argument("--interval", type=int, default=15, help="loop poll seconds (default 15)")
    ap.add_argument("--live", action="store_true", help="actually send txs (requires key file)")
    ap.add_argument("--key-file", type=Path, default=DEFAULT_KEY_FILE,
                    help="TESTNET key file (default: testnet/keys/deployer.txt)")
    ap.add_argument("--no-refund", action="store_true", help="never call refund()")
    args = ap.parse_args()

    rpc = pick_rpc()
    log(f"RPC ok (chain 97): {rpc}")
    log(f"GAME={GAME}")

    key = None
    if args.live:
        key = load_key(args.key_file)
        addr = subprocess.run([CAST, "wallet", "address", "--private-key", key],
                              capture_output=True, text=True, timeout=30).stdout.strip()
        bal = run_cast(["balance", addr], rpc).strip().split()[0]
        log(f"keeper wallet {addr} balance={bal} wei tBNB (testnet)")
        if int(bal) == 0:
            log("WARN keeper balance is 0 — top up tBNB from the faucet or sends will fail")

    state = load_state()
    allow_refund = not args.no_refund
    if args.loop:
        log(f"loop mode, every {args.interval}s — Ctrl-C to stop")
        while True:
            try:
                one_pass(rpc, args.live, key, allow_refund, state)
            except Exception as e:  # noqa: BLE001 - keeper must survive RPC hiccups
                log(f"ERROR pass failed: {e}")
            time.sleep(args.interval)
    else:
        one_pass(rpc, args.live, key, allow_refund, state)
    return 0


if __name__ == "__main__":
    sys.exit(main())
