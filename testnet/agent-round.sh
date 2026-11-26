#!/usr/bin/env bash
# =====================================================================
# Plinko Royale — AI-agent play proof (BSC TESTNET, chain 97)
#
# Plays one full round using ONLY contract calls + views (cast), with
# no frontend and no human in the loop:
#   discover round -> approve -> enter -> (events) -> draw -> poll word
#   -> settle -> verify payouts/conservation -> withdraw.
#
# Testnet only. Keys are read from testnet/keys/ into shell variables
# and never printed. Addresses derived from keys are verified before use.
# =====================================================================
set -u

RPC=https://data-seed-prebsc-1-s1.bnbchain.org:8545
GAME=0x4f65C6db7ECA6E81B7fb139D0d539b5ae2E1d614
TOKEN=0x17356908F432eD7F2a4b378F19b5c869b872e21E
DEAD=0x000000000000000000000000000000000000dEaD
FEERECIP=0x627Ce1AEda3f4B8f2f63E6051Ddd1304fc533c87
CAST=$HOME/.foundry/bin/cast
LEGACY="--legacy --gas-price 100000000"
KEYS=$HOME/workspace/plinko-royale/testnet/keys

STAKE_P1=2000000000000000000000000   # contoh stake P1: 2,000,000 AGC x 1e18 (= TIER_5 kontrak)
STAKE_P2=5000000000000000000000000   # contoh stake P2: 5,000,000 AGC x 1e18 (= TIER_6 kontrak)
SEED1=0x00000000000000000000000000000000000000000000000000000000000000a1
SEED2=0x00000000000000000000000000000000000000000000000000000000000000a2

# --- keys (never printed) ---------------------------------------------
DK=$(grep -oiE '0x[0-9a-f]{64}' "$KEYS/deployer.txt" | head -1)
P1K=$(grep -oiE '0x[0-9a-f]{64}' "$KEYS/player1.txt" | head -1)
P2K=$(grep -oiE '0x[0-9a-f]{64}' "$KEYS/player2.txt" | head -1)
DADDR=$($CAST wallet address --private-key "$DK")
P1=$($CAST wallet address --private-key "$P1K")
P2=$($CAST wallet address --private-key "$P2K")
echo "keeper/deployer: $DADDR"
echo "player1:         $P1"
echo "player2:         $P2"
[ "$DADDR" = "0x5aC2E2c437506B5F34Dd231c89078f03fEb0A6ee" ] || { echo "deployer key mismatch"; exit 1; }
[ "$P1" = "0x882A3B4e3A2A54b5CfC5A31706E8b40907778197" ] || { echo "player1 key mismatch"; exit 1; }
[ "$P2" = "0x66f82b1270F8F4b5ccF767Ad1aA24881F156E5Cc" ] || { echo "player2 key mismatch"; exit 1; }

call() { $CAST call --rpc-url "$RPC" "$@" | awk '{print $1}'; }
send() { # send <privkey> <label> <cast send args...>
  local pk=$1 label=$2; shift 2
  local out hash
  out=$($CAST send --rpc-url "$RPC" --private-key "$pk" $LEGACY "$@" 2>&1)
  hash=$(echo "$out" | grep -i '^transactionHash' | awk '{print $2}')
  if [ -z "$hash" ]; then echo "FAILED: $label"; echo "$out" | tail -5; exit 1; fi
  echo "$label tx: $hash"
  LAST_TX=$hash
}

# --- 1. discover the open round (views only) ---------------------------
while :; do
  read -r RID OPENS CLOSES <<< "$($CAST call $GAME 'currentRound()(uint256,uint64,uint64)' --rpc-url $RPC | awk '{print $1}' | tr '\n' ' ')"
  NOW=$($CAST block latest --rpc-url $RPC | awk '/^timestamp/{print $2}')
  LEFT=$((CLOSES - NOW))
  echo "round $RID opens=$OPENS closes=$CLOSES now=$NOW left=${LEFT}s"
  [ "$LEFT" -ge 120 ] && break
  echo "too late in this round; waiting for the next one..."
  sleep $((LEFT + 6))
done

# --- 2. pre-round balances (for delta verification) --------------------
DEAD_BEFORE=$(call $TOKEN 'balanceOf(address)(uint256)' $DEAD)
FEE_BEFORE=$(call $TOKEN 'balanceOf(address)(uint256)' $FEERECIP)
GB1_BEFORE=$(call $GAME 'balanceOf(address)(uint256)' $P1)
GB2_BEFORE=$(call $GAME 'balanceOf(address)(uint256)' $P2)
echo "pre: dead=$DEAD_BEFORE feeRecip=$FEE_BEFORE gameBal1=$GB1_BEFORE gameBal2=$GB2_BEFORE"

# --- 3. approve + enter --------------------------------------------------
# NOTE: bash [ ] cannot compare uint256-sized integers (64-bit overflow);
# compare via python3. (First run of this script failed exactly here:
# the allowance check silently errored, approve was skipped, and enter
# reverted with "allowance too low" — a clean revert, but a failed round.)
needs_approve() { python3 -c "import sys; sys.exit(0 if int(sys.argv[1]) < int(sys.argv[2]) else 1)" "$1" "$2"; }

ALLOW1=$(call $TOKEN 'allowance(address,address)(uint256)' $P1 $GAME)
if needs_approve "$ALLOW1" "$STAKE_P1"; then send "$P1K" "P1 approve" $TOKEN 'approve(address,uint256)' $GAME $STAKE_P1; fi
send "$P1K" "P1 enter 2jt" $GAME 'enter(uint256,uint256,bytes32)' $RID $STAKE_P1 $SEED1

ALLOW2=$(call $TOKEN 'allowance(address,address)(uint256)' $P2 $GAME)
if needs_approve "$ALLOW2" "$STAKE_P2"; then send "$P2K" "P2 approve" $TOKEN 'approve(address,uint256)' $GAME $STAKE_P2; fi
send "$P2K" "P2 enter 5jt" $GAME 'enter(uint256,uint256,bytes32)' $RID $STAKE_P2 $SEED2

# --- 4. discover players via the playersOf view (audit L-6 fix; ----------
# --- no eth_getLogs needed anymore) ---------------------------------------
echo "playersOf($RID):"
$CAST call $GAME 'playersOf(uint256)(address[])' $RID --rpc-url $RPC

DETAIL=$($CAST call $GAME 'roundDetail(uint256)(uint8,uint64,uint64,uint256,uint256,uint256,uint256,uint256,uint256)' $RID --rpc-url $RPC | awk '{print $1}')
echo "roundDetail (phase opens closes pot players reqId burned fee dust):"; echo "$DETAIL"

# --- 5. wait for close, then draw ----------------------------------------
while :; do
  NOW=$($CAST block latest --rpc-url $RPC | awk '/^timestamp/{print $2}')
  [ "$NOW" -gt "$CLOSES" ] && break
  echo "waiting for close... now=$NOW closes=$CLOSES"; sleep 10
done
FEE=$(call $GAME 'drawFee(uint256)(uint256)' 100000000)
VALUE=$((FEE * 2))
echo "drawFee(0.1gwei)=$FEE wei; sending value=$VALUE (excess refunded by contract)"
send "$DK" "keeper draw" $GAME 'draw(uint256)' $RID --value $VALUE

# --- 6. poll for the VRF word ---------------------------------------------
WORD=0
for i in $(seq 1 36); do
  WORD=$(call $GAME 'randomWordOf(uint256)(uint256)' $RID)
  [ "$WORD" != "0" ] && break
  echo "waiting for VRF word... ($i)"; sleep 10
done
[ "$WORD" != "0" ] || { echo "VRF word did not arrive in 6 minutes"; exit 1; }
echo "VRF word: $WORD"

# --- 7. settle --------------------------------------------------------------
send "$DK" "keeper settle" $GAME 'settle(uint256)' $RID

# --- 8. read results + verify ----------------------------------------------
read -r PHASE _O _C POT PCOUNT _REQ BURNED FEEPAID DUST <<< "$($CAST call $GAME 'roundDetail(uint256)(uint8,uint64,uint64,uint256,uint256,uint256,uint256,uint256,uint256)' $RID --rpc-url $RPC | awk '{print $1}' | tr '\n' ' ')"
read -r STAKE1 PAY1 SLOT1 <<< "$($CAST call $GAME 'result(uint256,address)(uint256,uint256,uint8)' $RID $P1 --rpc-url $RPC | awk '{print $1}' | tr '\n' ' ')"
read -r STAKE2 PAY2 SLOT2 <<< "$($CAST call $GAME 'result(uint256,address)(uint256,uint256,uint8)' $RID $P2 --rpc-url $RPC | awk '{print $1}' | tr '\n' ' ')"
GB1_AFTER=$(call $GAME 'balanceOf(address)(uint256)' $P1)
GB2_AFTER=$(call $GAME 'balanceOf(address)(uint256)' $P2)
DEAD_AFTER=$(call $TOKEN 'balanceOf(address)(uint256)' $DEAD)
FEE_AFTER=$(call $TOKEN 'balanceOf(address)(uint256)' $FEERECIP)

# recompute slots locally from the public word (cast keccak)
slot_of() { # word round player seed
  local enc hash top
  enc=$($CAST abi-encode 'x(uint256,uint256,address,bytes32)' "$1" "$2" "$3" "$4")
  hash=$($CAST keccak "$enc")
  top=${hash:2:2}
  python3 -c "print(bin(int('$top',16)).count('1'))"
}
CALC_SLOT1=$(slot_of "$WORD" "$RID" "$P1" "$SEED1")
CALC_SLOT2=$(slot_of "$WORD" "$RID" "$P2" "$SEED2")

echo "phase=$PHASE pot=$POT players=$PCOUNT burned=$BURNED feePaid=$FEEPAID dust=$DUST"
echo "P1: stake=$STAKE1 payout=$PAY1 slot(onchain)=$SLOT1 slot(recomputed)=$CALC_SLOT1"
echo "P2: stake=$STAKE2 payout=$PAY2 slot(onchain)=$SLOT2 slot(recomputed)=$CALC_SLOT2"

python3 - "$POT" "$PAY1" "$PAY2" "$BURNED" "$FEEPAID" "$DUST" "$GB1_BEFORE" "$GB1_AFTER" "$GB2_BEFORE" "$GB2_AFTER" "$DEAD_BEFORE" "$DEAD_AFTER" "$FEE_BEFORE" "$FEE_AFTER" "$SLOT1" "$CALC_SLOT1" "$SLOT2" "$CALC_SLOT2" <<'PYEOF'
import sys
pot,pay1,pay2,burn,fee,dust,gb1b,gb1a,gb2b,gb2a,db,da,fb,fa,s1,cs1,s2,cs2 = map(int, sys.argv[1:])
ok = True
def chk(name, cond):
    global ok
    print(("PASS" if cond else "FAIL"), name)
    ok = ok and cond
chk("conservation payouts+burn+fee+dust == pot", pay1+pay2+burn+fee+dust == pot)
chk("burn == floor(pot*30/10000)", burn == pot*30//10000)
chk("fee  == floor(pot*30/10000)", fee == pot*30//10000)
chk("P1 game-balance delta == payout1", gb1a-gb1b == pay1)
chk("P2 game-balance delta == payout2", gb2a-gb2b == pay2)
chk("dead balance delta == burn", da-db == burn)
chk("feeRecipient delta == fee", fa-fb == fee)
chk("dust < players", dust < 2)
chk("slot1 matches recomputation", s1 == cs1)
chk("slot2 matches recomputation", s2 == cs2)
print("ALL CHECKS PASSED" if ok else "SOME CHECKS FAILED")
sys.exit(0 if ok else 1)
PYEOF
[ $? -eq 0 ] || exit 1

# --- 9. withdraw -------------------------------------------------------------
WALLET1_BEFORE=$(call $TOKEN 'balanceOf(address)(uint256)' $P1)
send "$P1K" "P1 withdraw" $GAME 'withdraw(uint256)' $GB1_AFTER
WALLET1_AFTER=$(call $TOKEN 'balanceOf(address)(uint256)' $P1)
GB1_FINAL=$(call $GAME 'balanceOf(address)(uint256)' $P1)
echo "P1 wallet token: $WALLET1_BEFORE -> $WALLET1_AFTER (game balance now $GB1_FINAL)"
python3 -c "
import sys
b,a,g,w = $WALLET1_BEFORE, $WALLET1_AFTER, $GB1_FINAL, $GB1_AFTER
assert a-b == w and g == 0, 'withdraw mismatch'
print('PASS withdraw: wallet delta == withdrawn amount, game balance 0')"

echo "=== AGENT ROUND $RID COMPLETE ==="
