# Plinko Royale — BSC Testnet Deployment Report

**Status: COMPLETE.** One full round played and verified end-to-end on BSC
testnet (chain ID 97) on 2026-11-26. Testnet only — no mainnet, no real
funds, no user wallets touched.

**Current deployment (2026-11-26, external-audit fixes redeploy):**
`0x8643ab8Fe68aBC315aC7D38b5518e6cc3644F0a7` — see "External-audit fixes
redeployment" at the bottom, including verification round #1 on this
contract. All earlier deployments below (`0x9F48…f79c`, `0x20Aa…fa2`,
`0x66d8…3d49`) are superseded; their records are kept for history only.
Do not use them.

## Addresses

| Role | Address |
| --- | --- |
| PlinkoRoyale (game, current) | [`0x8643ab8Fe68aBC315aC7D38b5518e6cc3644F0a7`](https://testnet.bscscan.com/address/0x8643ab8Fe68aBC315aC7D38b5518e6cc3644F0a7) |
| PlinkoRoyale (superseded deploys, do not use) | `0x9F485aF31008f9678F43b4f9f81cD11C7216f79c`, `0x20Aa35C4441F05f5435c812308A6620536B54fa2`, `0x66d8e0d61f3b89d1962bfef0cd19be767a2a3d49` |
| MockAGC (test token) | [`0x17356908F432eD7F2a4b378F19b5c869b872e21E`](https://testnet.bscscan.com/address/0x17356908F432eD7F2a4b378F19b5c869b872e21E) |
| Deployer / keeper | `0x5aC2E2c437506B5F34Dd231c89078f03fEb0A6ee` |
| Player 1 | `0x882A3B4e3A2A54b5CfC5A31706E8b40907778197` |
| Player 2 | `0x66f82b1270F8F4b5ccF767Ad1aA24881F156E5Cc` |
| Fee recipient (owner-provided) | `0x627Ce1AEda3f4B8f2f63E6051Ddd1304fc533c87` |
| Chainlink VRF v2.5 wrapper | `0x471506e6ADED0b9811D05B8cAc8Db25eE839Ac94` |
| Dead (burn) address | `0x000000000000000000000000000000000000dEaD` |

Keys for deployer/players live in `keys/` (TESTNET-ONLY — see `keys/README.md`).

## Deployment transactions

| Step | Tx |
| --- | --- |
| Fund Player 1 (0.05 tBNB) | [`0xffc2973d…d10570`](https://testnet.bscscan.com/tx/0xffc2973d715b1672d92e002087520053c67f2c69b94e1f9128d231bd45d10570) |
| Fund Player 2 (0.05 tBNB) | [`0x67f18213…68031f`](https://testnet.bscscan.com/tx/0x67f18213715aae79b42b162fc4fd39b15199d67ca6e8df0f9967917e6e68031f) |
| Deploy MockAGC | [`0x3b94dfaf…ac42e5b4`](https://testnet.bscscan.com/tx/0x3b94dfafc6837ef8fe46a05cb3f3c1bd4716fe70fb6b11e891f27ac6ac42e5b4) |
| Mint 100M to Player 1 | [`0xa6d5bbba…207a6b`](https://testnet.bscscan.com/tx/0xa6d5bbba28b245895ff9d2d368a8ffb9f1906f24cc5925ec5dba45574c207a6b) |
| Mint 100M to Player 2 | [`0xbc4a8f41…c696`](https://testnet.bscscan.com/tx/0xbc4a8f4144999bc19da14a5e410e818aa66564b17227f868c513bc59c2f8c696) |
| Deploy PlinkoRoyale | [`0xa9e7cf7e…ca`](https://testnet.bscscan.com/tx/0xa9e7cf7e0806a19daf05b0b080bb6595bb526a11816c9d6a0c7e6938d77974ca) |

Constructor args: `(MockAGC, 0x627Ce1AEda3f4B8f2f63E6051Ddd1304fc533c87, VRF wrapper)`.
Source verification was submitted to Sourcify (job
`b6906820-b564-4694-be98-2e27257fafda`); the status API returned errors when
checked, so verification is **submitted but unconfirmed** — check
[sourcify.dev](https://sourcify.dev) for chain 97 + the game address.

## Round 0 — played and verified

Round 0 opened at deploy (genesis 1795631232) and closed 300s later
(1795631532). Both players entered before close.

| Step | Tx |
| --- | --- |
| P1 approve 2M | [`0x561c37d0…80096`](https://testnet.bscscan.com/tx/0x561c37d07b3d3a17b8095c1c69759b524d7cfe426f5e635b7821824586d80096) |
| P1 enter 2M tier | [`0xd7bfa13b…01e`](https://testnet.bscscan.com/tx/0xd7bfa13bf01108538057c174c13a873cf33ff904c913ad7456dfb125b06fb01e) |
| P2 approve 5M | [`0x1ee4b814…bf9d`](https://testnet.bscscan.com/tx/0x1ee4b81429f03fb8a4f187729624772df69d461c4fda5a882b710965e9c5bf9d) |
| P2 enter 5M tier | [`0x441ab483…50c`](https://testnet.bscscan.com/tx/0x441ab4839c970ec8518ea9a81309b7fb3cf526d69b6be5e8410e5d73d207e50c) |
| draw(0) — VRF request | [`0x68104795…156`](https://testnet.bscscan.com/tx/0x68104795ddeb8b2b0a8f48db1db4b4521d7ca64c4c4b8ee20b707119a2fb9156) |
| settle(0) | [`0xe789a99e…485`](https://testnet.bscscan.com/tx/0xe789a99e6ed618f673a916bdbcf7226805ecae9ecd16669cc0e07a6780351485) |
| P1 withdraw | [`0x940a1188…751`](https://testnet.bscscan.com/tx/0x940a1188ff73036e00fcf7b8880d44629b87814478cd332544e1ac9cd27cc751) |

- VRF requestId: `0xe568349f6afc5095276676e9eaa5b6855da01b1f44b35bc46d72d247bae1da71`
- VRF word: `85129142575267451587640012385831039963758769747413219241318816626492363351701`
  (fulfilled within ~1 minute of the request)
- VRF fee paid: ≈0.0000333 tBNB (0.001 sent, excess refunded by `draw()`)

### Settlement numbers (mock AGC, 18 decimals)

| Item | Amount |
| --- | --- |
| Pot (2M + 5M) | 7,000,000 |
| Burn 0.5% → dead address | 35,000 |
| Operational fee 0.5% → fee recipient | 35,000 |
| Payout pool (99%) | 6,930,000 |
| Player 1 — stake 2M, slot 1 (3.0×) | payout 4,376,842.105263157894736842 |
| Player 2 — stake 5M, slot 3 (0.7×) | payout 2,553,157.894736842105263157 |
| Dust (flooring residue, stays in contract) | 1 wei |

Conservation verified on-chain:
payouts (6,929,999.999…) + burn (35,000) + fee (35,000) + dust (1 wei)
= pot (7,000,000) exactly. In-game balances matched `result()` for both
players; dead-address and fee-recipient token balances each increased by
exactly 35,000.

Player 1 withdrew the full payout: wallet went 98,000,000 →
102,376,842.105… mock AGC, in-game balance 0. Contract retains Player 2's
unwithdrawn payout + 1 wei dust (2,553,157.894…158).

## Final tBNB balances

- Deployer: ≈0.8996 tBNB (started 1.0)
- Player 1: ≈0.04997 tBNB
- Player 2: ≈0.04998 tBNB

Total spent ≈0.1004 tBNB, almost all of it the 0.1 tBNB distributed to
players; actual gas + VRF fees were ≈0.0004 tBNB at the 0.1 gwei testnet
gas price.

## Notes / gotchas found

- BSC testnet rejects type-2 txs with a 1-wei tip cap ("gas tip cap 1,
  minimum needed 100000000"). Use **legacy transactions**
  (`--legacy --gas-price 100000000`) with cast/forge on chain 97.
- RPC used: `https://data-seed-prebsc-1-s1.bnbchain.org:8545/`.
- Rounds run on a fixed 300s grid from deploy time; round 1 was already
  open when this report was written. Anyone can enter the current round
  with mock AGC from the open `mint()` faucet on MockAGC.

## How to repeat / continue

1. Keys are in `keys/`; export a key in-shell without printing it:
   `DK=$(grep -oiE '0x[0-9a-f]{64}' keys/deployer.txt | head -1)`
2. Check the open round:
   `cast call <GAME> 'currentRound()(uint256,uint64,uint64)' --rpc-url <RPC>`
3. Mint test tokens: `cast send <TOKEN> 'mint(address,uint256)' <YOU> <AMT> …`
4. Approve + `enter(roundId, amount, clientSeed)` (tiers: 2M/5M/10M ×1e18).
5. After close: `drawFee(100000000)` → `draw(roundId)` with value ≥ fee →
   wait for `randomWordOf(roundId)` ≠ 0 → `settle(roundId)` → `withdraw(amount)`.
6. All sends need `--legacy --gas-price 100000000` on this testnet.

## Next steps (not done here)

- Confirm Sourcify verification status; optionally verify on BscScan testnet.
- Point a frontend at the testnet contract for a playable demo. *(Done —
  see `frontend/`; live at https://plinko-royale-testnet-kenchiro.vercel.app.
  Frontend updated for the redeployed contract on 2026-11-26; Vercel
  redeploy pending owner approval at time of writing.)*
- Mainnet still requires: independent audit, a carefully chosen permanent
  fee-recipient address (immutable), real AGC token address, and VRF
  wrapper re-verification on mainnet.

---

## Redeployment — 2026-11-26 (audit M-1 fix, owner-approved)

The owner approved applying the M-1 fix ("Terapkan batas 500 pemain").
Changes vs the first deployment, all in `contracts/PlinkoRoyale.sol`:

- `MAX_PLAYERS = 500` — the 501st entry in a round reverts "round full"
  (settle/refund loops can never exceed the block gas limit).
- `refund()` gained the `nonReentrant` guard (audit L-4).
- New `playersOf(roundId)` view (audit L-6) — entrant list via plain
  `eth_call`, no `eth_getLogs` needed.
- Full Foundry suite: **49/49 tests pass** (27 original + 20 adversarial
  + `testRoundFullAtMaxPlayers` + `testPlayersOf`).

| Item | Value |
| --- | --- |
| New PlinkoRoyale | [`0x20Aa35C4441F05f5435c812308A6620536B54fa2`](https://testnet.bscscan.com/address/0x20Aa35C4441F05f5435c812308A6620536B54fa2) |
| Deploy tx | [`0xa7ac47db…fd89d4`](https://testnet.bscscan.com/tx/0xa7ac47dbcc336c2d1e8a30513a1b83d3af3f9477db3bb338e305f590a8fd89d4) |
| Deploy block | 144883915 |
| Constructor args | `(MockAGC 0x1735…e21E, feeRecipient 0x627C…3c87, VRF wrapper 0x4715…Ac94)` — same as before |
| Sourcify | **exact_match** (creation + runtime), verified 2026-11-26T00:29:20Z, job `fd4b4295-c3fd-4bd1-bea9-e5f8a0216714` |

### Verification round 0 on the new contract (played via `agent-round.sh`, cast only)

| Step | Tx |
| --- | --- |
| P1 approve 2M | [`0x2e601f9b…2eb`](https://testnet.bscscan.com/tx/0x2e601f9b028f4bdc8c38d6859c7c153080ae7d3939893d87b7b22bae6dee42eb) |
| P1 enter 2M tier | [`0x9157aa02…563`](https://testnet.bscscan.com/tx/0x9157aa02ea96bda3a698430ab77e8e71924d8b53da1e22969fa85e8fb7ddb563) |
| P2 approve 5M | [`0x4b20ce8c…d6ad`](https://testnet.bscscan.com/tx/0x4b20ce8c003808cd18b15e0042b4d346538c827c5bfdf04c4280f099848fd6ad) |
| P2 enter 5M tier | [`0x0bf5bc25…e50c`](https://testnet.bscscan.com/tx/0x0bf5bc25bee692c91ba22beea1d2ee1957205011e0a6e3a309dc99db5c390b38) |
| draw(0) — VRF request | [`0x501979c7…6fe`](https://testnet.bscscan.com/tx/0x501979c7d12fb93dfa50fc2c938db95927fa2a3d817ad97c69db4494277bc6fe) |
| settle(0) | [`0x754c4aa5…5b5`](https://testnet.bscscan.com/tx/0x754c4aa5d8c68b6fdce9830cfcb54c57e285db8ef3e99a4a30802f91f46805b5) |
| P1 withdraw | [`0xd4c1a2bb…4b6`](https://testnet.bscscan.com/tx/0xd4c1a2bb8ef5a687749c949a13cce75e0ddbebb34fb34a783eaf35782a5594b6) |

- `playersOf(0)` returned both entrants in entry order (L-6 view works
  on-chain; the agent script now uses it instead of event scanning).
- VRF word: `49925044361392591281882111201768343887088071928556600148098809826444259435002`
  (fulfilled on first poll, <10s after draw)
- Settlement: pot 7,000,000; burn 35,000 → dead; fee 35,000 → fee
  recipient; Player 1 slot 4 (0.4×) payout 350,886.0759…; Player 2
  slot 7 (3.0×) payout 6,579,113.9240…; dust 1 wei.
- All script checks passed: conservation exact, burn/fee deltas exact,
  locally recomputed slots match on-chain, P1 withdraw exact.
- Deployer balance after redeploy + round: ≈0.899 tBNB (deploy ≈2.23M
  gas at 0.1 gwei).

---

## Fee model change — 2026-11-26 (redeployed)

The owner approved lowering the fee model from **0.5% burn + 0.5%
operational fee (1% total)** to **0.3% burn + 0.3% operational fee
(0.6% total)** ("turunin dulu kaya BR") to match AGC Battle Royale's
~0.625% expected edge. Source changes applied 2026-11-26:

- `contracts/PlinkoRoyale.sol`: `BURN_BPS` 50 → 30, `FEE_BPS` 50 → 30
  (settlement math is generic in the constants; comments updated).
- Foundry tests: worked-example expectations recomputed (e.g. example 1
  burn/fee 95,000 → 57,000 on a 19M pot; example 3 wei-exact payouts
  updated, dust 1 → 2 wei); the two dust-sensitive adversarial
  assertions now read burned/feePaid/dust from `roundDetail` instead
  of assuming dust == 1.
- `verify.py` + `PROTOTYPE.html`: constants 50 → 30 bps, text updated.
- Docs: DESIGN.md (formula, worked examples, decisions), CONTRACT.md,
  llms-plinko.txt, frontend text, `agent-round.sh` checks (50 → 30).
- Proposal PDFs intentionally NOT touched (owner: proposals later).

Expected numbers for the standard verification round (2M + 5M,
pot 7,000,000): burn **21,000** → dead, fee **21,000** → fee recipient,
payoutPool **6,958,000** (99.4%).

**Redeployed 2026-11-26:** `forge test` 49/49 passed and `verify.py`
20,000 rounds passed under the new constants. New contract:
[`0x66d8e0d61f3b89d1962bfef0cd19be767a2a3d49`](https://testnet.bscscan.com/address/0x66d8e0d61f3b89d1962bfef0cd19be767a2a3d49)
(deploy tx `0x701ec835970e8a5d40d5d97c3da0507f2b5f8cf0b15ee55e51b11d32ca217849`,
block 144917807, same constructor args; Sourcify verification submitted,
job `44142a92-f2b1-48b7-b617-7d182409a5e7`; on-chain `burnBps()`/
`feeBps()` = 30). The previous deployment
`0x20Aa35C4441F05f5435c812308A6620536B54fa2` (0.5% + 0.5%) is superseded.

---

## External-audit fixes redeployment — 2026-11-26

An independent model audit (Gemini, report summarized in
`../EXTERNAL-AUDIT-GEMINI.md`) found the contract core safe
(Critical 0, High 0) with 2 Medium (frontend/keeper), 6 Low, 2 Info.
All findings were fixed the same day at the owner's order:

- **Contract (LOW-1 + INFO-2):** `roundDetail()` phase boundary changed
  from `block.timestamp > closesAt` to `>=` (at the closing second the
  round already reports AwaitingDraw); NatSpec gas estimate corrected
  (~37.5k gas/player, 500-cap ~18.7M). Two views added:
  `wordReceivedOf(roundId)` (settle gating independent of word value)
  and `drawRequestedAtOf(roundId)` (exact random-timeout refund anchor;
  completes internal-audit L-6's second half without changing the
  `roundDetail` tuple). Two new tests; suite now **51/51**.
- **Frontend (MEDIUM-1, LOW-2..6, INFO-1):** `entryOf` reads batched
  through Multicall3 (one eth_call per refresh); settled-round results
  computed locally from the on-chain word (no per-player `result()`
  calls); `draw()` sends an explicit matching `gasPrice` with a 150%
  fee buffer; ethers CDN pinned with SRI; error text HTML-escaped;
  settle animation uses a {roundId, word} snapshot and marks played
  only after the animating check; settle gated on `wordReceivedOf`;
  refund gated exactly (phase 1: closesAt + 1h; phase 2:
  drawRequestedAt + 1h); RPC rotation destroys the old provider
  (`staticNetwork: true`).
- **Keeper (MEDIUM-2):** scan window widened to the last 21 rounds
  (covers the 1-hour refund timeouts), gas price fetched per pass
  (floored at 0.1 gwei), settle gated on `wordReceivedOf`, refund
  timed exactly via `drawRequestedAtOf`.

**Redeployed 2026-11-26:** new contract
[`0x8643ab8Fe68aBC315aC7D38b5518e6cc3644F0a7`](https://testnet.bscscan.com/address/0x8643ab8Fe68aBC315aC7D38b5518e6cc3644F0a7)
(deploy tx `0xe78e420947de36c94aeff4137a86470e63d0b46e963eed2a637995b9511cea19`,
block 144931878, same constructor args; Sourcify verification submitted,
job `4e41fc5d-6eb3-49b5-8285-c79a6aea6c7f`; on-chain `burnBps()`/`feeBps()`
= 30, `MAX_PLAYERS()` = 500, new views respond). The previous deployment
`0x66d8e0d61f3b89d1962bfef0cd19be767a2a3d49` is superseded. Frontend,
keeper, llms-plinko.txt, agent-round.sh, and stress-test.py all point
at the new address.

### Verification round #1 on the new contract (2026-11-26, reported ~13:42 WIB)

Played with 5 bots on `0x8643…F0a7` after the redeploy above; the fixed
keeper drew and settled the round itself (and auto-refunded the empty
round #0). All checks passed:

- Pot 24,000,000 test AGC; burn **72,000** → dead address and
  operational fee **72,000** → fee recipient (exactly 0.3% / 0.3%).
- Conservation exact; every player's slot and payout matched local
  recomputation from the VRF word.
- Frontend live-verified in the same pass: the locally computed round #1
  results table matched on-chain (0.01 display difference only, from
  2-decimal truncation), no errors, and the sequential ball animation
  landed in the correct slots.

(Tx hashes for this round were not recorded in this report; figures are
from the verification report delivered to the owner 2026-11-26 ~13:42
WIB.)

---

## 7-tier stake ladder redeployment — 2026-11-26

At the owner's order, the stake tiers now mirror AGC Battle Royale's
updated ladder: **100K / 300K / 500K / 1M / 2M / 5M / 10M AGC**
(previously 2M / 5M / 10M). Contract changes: `TIER_1..TIER_7`
constants, `stakeTiers()` returns `uint256[7]`, `enter()` accepts any
of the seven. Settlement math, fees (0.3% + 0.3%), and round duration
(5 minutes) are unchanged. One new test (`testSevenStakeTiers`):
suite now **52/52**.

**Redeployed 2026-11-26:** new contract
[`0x4f65C6db7ECA6E81B7fb139D0d539b5ae2E1d614`](https://testnet.bscscan.com/address/0x4f65C6db7ECA6E81B7fb139D0d539b5ae2E1d614)
(deploy tx `0x6347b589102df1aa81492da34e9471a9d1a4a1ce0681082e3f8556a7a821eeac`,
block 144955838, same constructor args; Sourcify exact_match,
matchId 59988487; on-chain `stakeTiers()` = the 7 values,
`burnBps()`/`feeBps()` = 30, `MAX_PLAYERS()` = 500). The previous
deployment `0x8643ab8Fe68aBC315aC7D38b5518e6cc3644F0a7` is superseded.
Frontend (ABI `uint256[7]`, new address, deploy block), keeper,
llms-plinko.txt, agent-round.sh, stress-test.py, and all docs point
at the new address and tier ladder.

### Verification round on the 7-tier contract (2026-11-26, reported ~17:04 WIB)

Played with 5 bots entering at mixed tiers (100K, 300K, 1M, 2M, 10M)
on `0x4f65…d614`. All checks passed:

- Pot 13,400,000 test AGC; burn **40,200** → dead address and
  operational fee **40,200** → fee recipient (exactly 0.3% / 0.3%).
- Every player's payout matched local recomputation; the small tiers
  (100K/300K) entered and settled correctly.
- Frontend live points at the new contract; the update was pushed to
  GitHub (github.com/kenchirohito/plinko-royale).

Round duration stays 5 minutes (Battle Royale's 3-minute rounds were
not adopted — owner's call pending).

---

## 1-minute rounds redeployment — 2026-11-26

At the owner's order, rounds now run every **1 minute**
(`ROUND_DURATION` 300 → 60; Battle Royale moved to 3 minutes, the
owner chose 1). Settlement math, fees (0.3% + 0.3%), tiers (7), and
the 1-hour draw/random timeouts are unchanged. Keeper scan window
widened to 70 rounds so the 1-hour timeout refunds stay reachable at
60 rounds/hour. Suite still **52/52** (one assertion updated to
`closesAt == genesis + 60`).

**Redeployed 2026-11-26:** new contract
[`0x5133d3a7b0AAb6dFb3c40b824741FA4A776Bc3EF`](https://testnet.bscscan.com/address/0x5133d3a7b0AAb6dFb3c40b824741FA4A776Bc3EF)
(deploy tx `0xab117d3931966bb2e6f7591dc19eb54605518fd19b539f77a5deccc854dd4d79`,
block 144976141, same constructor args; Sourcify submitted,
job `fb96a824-6a08-4e7a-9db6-c25cbabe7b54`; on-chain
`ROUND_DURATION()` = 60, round 0 opens/closes exactly 60s apart).
The previous deployment `0x4f65C6db7ECA6E81B7fb139D0d539b5ae2E1d614`
is superseded. Frontend (new address, deploy block, 1-minute text),
keeper (new address, 70-round scan), llms-plinko.txt, agent-round.sh,
stress-test.py, and all docs point at the new contract.
Verification round #1 on the 1-minute contract PASSED the same
evening: 5 bots entered within a single 60-second window (tiers
100K/500K/1M/5M/10M, pot 16,600,000 test AGC), keeper drew and
settled, burn and operational fee exactly 49,800 each, conservation
exact, every slot/payout matched local recomputation from the VRF
word.
