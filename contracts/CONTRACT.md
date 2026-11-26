# Plinko Royale — Contract Guide

Plain-language guide to `PlinkoRoyale.sol`: what it does, what to fill in at
deploy time, what it costs to run, what its limits are, and the exact next
steps for a BSC testnet deployment. The game rules themselves are in
`../DESIGN.md`; this file is about the contract.

**Status: written, tested, and deployed to BSC testnet** (chain 97) at
`0x5133d3a7b0AAb6dFb3c40b824741FA4A776Bc3EF` (2026-11-26, external-audit
fixes; see `../testnet/TESTNET-REPORT.md`). 52 Foundry tests pass,
including exact payout checks against `verify.py`'s worked examples and
a 2,000-run fuzz test.

---

## 1. What this contract is

One Solidity file (solc 0.8.28, no imports, ~9.6 KB deployed) that runs the
whole game on-chain:

- Players stake AGC into 1-minute rounds.
- After a round closes, one Chainlink VRF random word decides every player's
  Plinko slot.
- The pot is split by score: **0.3% burned, 0.3% to a fixed fee address,
  99.4% to the players**.
- Winnings land in an in-game balance; players withdraw when they like.

There is **no owner and no admin**. Nobody — not even the deployer — can
change the fees, move the fee address, pause the game, or touch player
funds after deployment. Every parameter is a constant or is set once in the
constructor. If a bug is ever found, the fix is a new deployment, not a patch.

## 2. How a round works, step by step

Rounds run on a fixed clock: round 0 opens the moment the contract is
deployed, and a new round opens every 60 seconds after that. Nobody has to
"start" a round.

1. **Enter** — `enter(roundId, amount, clientSeed)`. Amount must be exactly
   one of the seven tiers: 100K, 300K, 500K, 1M, 2M, 5M, or 10M AGC
   (mirrors AGC Battle Royale's stake ladder). One entry per address per round. The stake is pulled
   from the player's wallet (they approve the contract first, as usual).
   `clientSeed` is optional extra randomness from the player; it cannot bias
   the outcome because the deciding random word does not exist yet.
2. **Draw** — after the round closes, anyone calls `draw(roundId)` and pays
   the Chainlink VRF fee in BNB (quote it first with `drawFee(gasPrice)`).
   Normally a small keeper bot does this seconds after close. Any excess BNB
   is refunded in the same transaction. Nobody is paid for drawing.
3. **Fulfill** — Chainlink calls back with one random word. The contract
   only stores it (cheap, always fits the gas budget).
4. **Settle** — anyone calls `settle(roundId)`. Each player's slot is derived
   from the word, payouts are credited to in-game balances, 0.3% of the pot
   is sent to the dead address (burned) and 0.3% to the fee address.
5. **Withdraw** — `withdraw(amount)` moves in-game balance to the wallet.

Refunds (full stake back, no burn, no fee) happen automatically via
`refund(roundId)` when: fewer than 2 players entered, or nobody drew within
1 hour of close, or the random word never arrived within 1 hour of the draw.
Once a word has arrived, a round can only settle — and since `settle` is
permissionless, funds can never be stuck waiting for a specific person.

## 3. Where the money goes

For a settled round with pot P:

| Slice | Amount | Goes to |
|---|---|---|
| Burn | floor(P × 0.3%) | dead address `0x0000…dEaD` |
| Fee | floor(P × 0.3%) | the immutable fee recipient |
| Payouts | the other 99.4%, split by score | players' in-game balances |
| Dust | flooring residue, < 1 wei-unit per player | stays in the contract |

Score = stake × slot multiplier (11.6× at the edges down to 0.4× in the
center). The multiplier table's expected value is exactly 1.0, so the only
house take is the transparent 0.6%. Conservation is exact:
payouts + burn + fee + dust = pot, for every round, proven in `verify.py`
(20,000 simulated rounds) and re-proven against this contract in the tests.

At any moment, the tokens held by the contract equal: all in-game balances
+ all stakes in unfinished rounds + accumulated dust. Nothing else can be
in there, and there is no function that can move tokens anywhere else.

## 4. Why it cannot be rigged

- Entries close **before** the random word exists. Nobody knows the outcome
  while staking.
- The word comes from Chainlink VRF; its proof is verified by Chainlink's
  coordinator before delivery. The contract accepts words only from the
  wrapper address fixed at deployment.
- Every slot is a public formula of (word, roundId, player, clientSeed).
  After a round, anyone can recompute every slot and every payout and check
  them against `result(roundId, player)`.
- No admin keys, no pause, no parameter setters, no upgrade path.

## 5. Constructor parameters (fill these in at deploy)

| Parameter | What it is | Value |
|---|---|---|
| `token_` | The stake token (AGC) | Mainnet AGC: `0x63dea5aCdbE1F27c968907D08610A5f0A0284bA6`. On testnet, deploy a mock ERC20 first (see §8). |
| `feeRecipient_` | Address receiving the 0.3% fee, forever | **Choose carefully — it can never be changed.** Use a wallet whose key the owner controls. |
| `wrapper_` | Chainlink VRF v2.5 wrapper (direct funding) | `0x471506e6ADED0b9811D05B8cAc8Db25eE839Ac94` for both BSC mainnet and BSC testnet, per Chainlink's current docs (checked 2026-11-26). **Re-verify at deploy time** on docs.chain.link/vrf/v2-5/supported-networks. |

Everything else is hard-coded: 300-second rounds, tiers
100K/300K/500K/1M/2M/5M/10M AGC,
**max 500 players per round** (`MAX_PLAYERS`, audit M-1 fix),
0.3% + 0.3% fees (lowered from 0.5% + 0.5% on 2026-11-26, owner-approved,
to match AGC Battle Royale's ~0.625% expected edge), multipliers, 1-hour timeouts, VRF callback gas limit
100,000, 3 request confirmations, 1 word per round.

## 6. Gas notes (measured with Foundry, solc 0.8.28, optimizer 200 runs)

| Action | Gas | Notes |
|---|---|---|
| Deploy | ~2.14M | One-time. Runtime size 9,553 bytes (limit 24,576). |
| `enter` | ~136k–188k | First entry in a round costs most (fresh storage). |
| `draw` | ~163k–170k | Plus the VRF fee in BNB (quoted by `drawFee`). |
| VRF callback | fits in 100k | Stores one word + event. The mock enforces the exact-gas call in tests. |
| `settle` | ~38–39k per player | 100 players = 3.93M gas; 300 players = 11.38M gas; 500 (cap) ≈ 18.7M gas. |
| `refund` | ~32k per player (measured in audit) | Credits balances, no token transfers. 500 (cap) ≈ 16.1M gas. |
| `withdraw` | ~27k–52k | One storage write + one ERC20 transfer. |

Settlement is a single loop that credits every player in one transaction
(the same shape as Battle Royale). Entries are capped at **500 per round**
(`MAX_PLAYERS`, audit finding M-1): the 501st entry reverts with
"round full". At ~39k gas per player a full 500-player round settles in
~18.7M gas — far below even a 30M-gas block, so a round's pot can never
lock for gas reasons. (Before the cap, ~800–3,700 players could have
exceeded the block limit.) Slots and payouts are not stored per player
(views recompute them), which is what keeps the per-player cost this low.

## 7. Decisions made where the design sketch left a choice

1. **No `agent` flag in the `Entered` event.** The sketch (§7) had one, but
   deriving "is an Agent ID holder" trustlessly needs an external registry
   call inside `enter()`, adding a failure mode to the game's most basic
   function. Indexers/frontends can join the event with registry data
   off-chain. Rules and payouts are identical for agents and humans.
2. **Stakes are pulled from the wallet only.** §6 mentioned taking stakes
   from in-game balance first (Battle Royale behavior). One code path is
   simpler to audit; players withdraw winnings before re-staking.
3. **The client seed is always part of the slot hash** (zero when unused),
   unifying §5.1/§5.2 into a single formula.
4. **"AwaitingDraw" is derived from the clock**, not stored. `roundDetail`
   reports it as phase 1 exactly as the sketch specifies.
5. **Settlement is one loop, not two-step claims.** The sketch has no claim
   function and credits payouts at settlement (Battle Royale pattern).
   Entries are capped at 500 per round (`MAX_PLAYERS`, audit M-1), which
   keeps the loop far below the block gas limit; see §6.
6. **`result()` also returns the slot** (the sketch returned only stake and
   payout), and `randomWordOf()` / `playersOf()` views were added so anyone
   can recompute slots and list a round's entrants without digging through
   event logs (audit L-6).
7. **`enter()` verifies the exact amount received.** AGC is not expected to
   tax transfers to this contract (Battle Royale makes the same assumption),
   but if it ever did, entry reverts cleanly instead of corrupting accounts.
8. **Round timing is a fixed grid from deployment** (no "start round"
   transaction, no keeper needed to open rounds).

Nothing in DESIGN.md turned out to be unimplementable as written; items 1–2
above are deliberate simplifications of sketch details, documented here and
in the code.

## 8. Known limitations (read before mainnet)

- **No fixes after deploy.** No admin means no patching. Audit first; a bug
  means redeploying and asking players to withdraw from the old contract
  (their balances stay withdrawable there forever).
- **The fee address is forever.** If its key is lost, fees keep flowing
  there. Pick it like it matters, because it does.
- **Dust accumulates** in the contract (< 1 wei-unit per player per round —
  fractions of a cent per year at realistic volume). There is no sweep
  function, by design.
- **Keeper liveness.** If nobody calls `draw` for 1 hour, the round refunds.
  If nobody calls `settle` after the word arrives, payouts wait until
  somebody does (anyone can; players have every incentive to). Run a keeper.
- **The draw caller must be able to receive BNB** (excess fee refund). A
  normal wallet works; a contract keeper needs a `receive()` function.
- **VRF dependency.** If Chainlink's wrapper/coordinator is down for over an
  hour, affected rounds refund in full. No funds are lost, just a dead round.
- **Token assumptions.** The contract assumes AGC is a plain ERC20 (returns
  bool, no transfer hooks, no tax to/from this contract, no pause/blacklist
  that would freeze game funds). If AGC ever paused transfers, `settle` and
  `withdraw` would revert until unpaused (refunds only credit balances, so
  they keep working). Verify AGC's behavior once more before mainnet.
- **Timestamps.** Round boundaries use `block.timestamp`; BSC validator
  drift is seconds, immaterial against 1-minute rounds and 1-hour timeouts.
- **One entry per address** does not stop one person using many addresses
  (same as Battle Royale). Fixed tiers bound how much that can matter.

## 9. Next steps: BSC testnet deployment

Nothing below has been done yet — this is the checklist for when the owner
says go.

1. **Get testnet BNB** for a throwaway deployer wallet (BNB Chain testnet
   faucet: bnbchain.org/en/testnet-faucet, or faucets.chain.link/bnb-chain-testnet).
2. **Deploy a mock stake token** on testnet (AGC itself is mainnet-only).
   `test/mocks/MockAGC.sol` works: deploy it, mint test balances.
3. **Deploy PlinkoRoyale** with (mock token, fee recipient, testnet wrapper
   `0x471506e6ADED0b9811D05B8cAc8Db25eE839Ac94` — re-verify the wrapper
   address on Chainlink's supported-networks page first).
   Example with Foundry:
   `forge create PlinkoRoyale --rpc-url <bsc-testnet-rpc> --private-key <deployer-key> --constructor-args <token> <feeRecipient> <wrapper>`
4. **Verify the contract** on testnet BscScan (solc 0.8.28, optimizer on,
   200 runs, single file — no imports to flatten).
5. **Play one full round** with 2+ test wallets: approve, enter, wait for
   close, `drawFee` → `draw`, wait for `RandomFulfilled`, `settle`, check
   `result` against a hand recomputation, `withdraw`.
6. **Stand up the keeper**: a small script (VPS or automation service) that
   watches `currentRound()`/`roundDetail()`, calls `draw` right after close
   with `drawFee(currentGasPrice)` plus a small buffer, then `settle` after
   fulfillment. Fund it with testnet BNB.
7. **Then, before any mainnet talk**: independent audit of this exact file,
   re-verify AGC token behavior and the mainnet wrapper address, choose the
   permanent fee recipient, and repeat steps 3–6 on mainnet with real AGC
   (`0x63dea5aCdbE1F27c968907D08610A5f0A0284bA6`).

## 10. Running the tests

```
cd contracts
forge test            # 52 tests: lifecycle, worked examples, refunds, fuzz
forge test --fuzz-runs 2000 --match-test testFuzzConservation
forge build --sizes   # contract size check
```

Test files: `test/PlinkoRoyale.t.sol` (suite), `test/mocks/MockAGC.sol`
(ERC20 stand-in with optional transfer tax), `test/mocks/MockVRFWrapper.sol`
(wrapper stand-in that enforces the real extraArgs encoding and exact-gas
callback). The worked-example tests force exact Plinko slots via client-seed
search and assert wei-exact payouts computed by `verify.py`.
