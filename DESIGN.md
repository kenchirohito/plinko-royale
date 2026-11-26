# Plinko Royale — Design Document

A PvP Plinko game for the AGC (Agentic Coin) ecosystem, modeled on AGC Battle
Royale's proven pattern: **players pay each other, the contract never needs a
bankroll**. Losers fund winners; the only house take is 0.6% of every pot
(0.3% burned + 0.3% operational fee, both transparent constants). Stake tiers are
fixed, rounds are short, randomness is provably fair (Chainlink VRF, §5), and
the whole game is playable by AI agents through plain contract calls.

**Status: prototype only.** Nothing here is deployed. No transactions, no
wallet interaction. The settlement logic in this document is implemented
identically in `verify.py` (proof) and `PROTOTYPE.html` (playable demo).

---

## 1. The board

- 8 rows of pegs → **9 landing slots** (numbered 0–8, left to right).
- A ball bounces left or right at each peg with 50/50 probability.
- The slot a ball lands in = number of right turns = binomial(8, ½).
- Slot probability: `P(slot k) = C(8,k) / 256`.

| Slot | C(8,k) | Probability | Multiplier | ×100 (integer) | p × m |
|-----:|-------:|------------:|-----------:|---------------:|------:|
| 0 | 1  | 0.3906%  | 11.6 | 1160 | 0.0453125 |
| 1 | 8  | 3.1250%  | 3.0  | 300  | 0.0937500 |
| 2 | 28 | 10.9375% | 1.4  | 140  | 0.1531250 |
| 3 | 56 | 21.8750% | 0.7  | 70   | 0.1531250 |
| 4 | 70 | 27.3438% | 0.4  | 40   | 0.1093750 |
| 5 | 56 | 21.8750% | 0.7  | 70   | 0.1531250 |
| 6 | 28 | 10.9375% | 1.4  | 140  | 0.1531250 |
| 7 | 8  | 3.1250%  | 3.0  | 300  | 0.0937500 |
| 8 | 1  | 0.3906%  | 11.6 | 1160 | 0.0453125 |

**Expected multiplier** = Σ C(8,k)·M_k / (256·100), where M is the ×100 table:

```
1·1160 + 8·300 + 28·140 + 56·70 + 70·40 + 56·70 + 28·140 + 8·300 + 1·1160
= 25,600        →        EV = 25,600 / 25,600 = 1.0000 exactly
```

So a ball's multiplier is **fair before the burn**: expected value exactly 1.
The minimum multiplier is 0.4 (> 0), which guarantees the payout denominator
can never be zero (see §3). Edges pay 11.6× score but hit only 0.39% of the
time; the center pays 0.4× and hits 27.3% of the time.

> Note: the multiplier is a **score weight**, not a direct payout multiple.
> Actual payout is your share of the pot (§3). In a round where everyone
> stakes the same amount, each player's expected payout is exactly
> 0.994 × stake (minus a sub-1-AGC-per-player flooring share) — i.e. the only
> expected loss is the 0.6% house edge (0.3% burn + 0.3% operational fee).

---

## 2. Round flow

1. **Open** (5 minutes, mirroring Battle Royale): each player stakes one fixed
   tier — **100,000 / 300,000 / 500,000 / 1,000,000 / 2,000,000 / 5,000,000 /
   10,000,000 AGC** (the same ladder as Battle Royale) — and is entered for one
   ball drop. One entry per address per round (keeps it simple; no raising).
   **At most 500 entries per round** (`MAX_PLAYERS`): the 501st entry reverts
   with "round full" and the player simply joins the next round. The cap is a
   safety bound from measured gas (~37.5k gas/player to settle, ~32.2k to
   refund), so a full round always fits in one block transaction (audit M-1).
2. **Close**: entries lock. If fewer than 2 players entered, the round is
   **refunded in full, no burn, no fee** (same rule as Battle Royale).
3. **Draw**: a keeper calls `draw(roundId)`; Chainlink VRF returns one random
   word for the round (§5).
4. **Settle**: each player's slot is derived from the word, scores and payouts
   are computed (§3), 0.3% of the pot is burned and 0.3% goes to the
   operational-fee recipient, payouts are credited as in-game balance.
5. **Withdraw**: players withdraw in-game balance to their wallet at any time
   (same pattern as Battle Royale).

---

## 3. Payout formula (integer math only)

All money math is integer arithmetic. Multipliers are stored ×100
(11.6 → 1160) and fees are in basis points, so no floating point ever
touches money.

```
pot        = Σ stake_i
burn       = floor(pot × 30 / 10000)        // 0.3% burned
fee        = floor(pot × 30 / 10000)        // 0.3% operational fee
payoutPool = pot − burn − fee               // 99.4% of pot
score_i    = stake_i × MULT_X100[slot_i]
payout_i   = floor(payoutPool × score_i / Σ score_j)
dust       = payoutPool − Σ payout_i
```

Total house edge = 0.6% of pot per round (30 bps burn + 30 bps operational fee),
both hard-coded constants. (Changed 2026-11-26, owner-approved, from
0.5% + 0.5% = 1% to 0.3% + 0.3% = 0.6% to match AGC Battle Royale's
~0.625% expected edge.) The burn goes to the dead address
`0x000000000000000000000000000000000000dEaD`; the fee goes to an immutable
fee-recipient address (§7). Neither can be changed after deployment.

**Conservation:** `Σ payout_i + burn + fee + dust = pot` exactly, by
construction. Dust is flooring residue that stays in the contract: each
payout `floor` loses < 1 AGC, so `dust < number_of_players`. The two bps
floors each under-collect by < 1 AGC vs exact 0.3% (≤ 2 AGC total); that
residue flows into `payoutPool` and is paid to players. So the total
flooring deviation from exact rational accounting is bounded by
< 1 AGC per player + ≤ 2 AGC from the two bps floors, of which only the
< 1-per-player part remains in the contract as dust (never paid out, never
burned; a production contract would sweep it into the next round's pot or
leave it — either is safe because it is accounted).

**Why division by zero is impossible:** every stake is > 0 (tiers are
positive constants) and every multiplier is > 0 (min 40), so
`Σ score_j > 0` whenever the round has ≥ 2 players — and rounds with < 2
players take the refund path and never reach the division.

### Worked example 1 — mixed tiers, mixed slots

4 players: A stakes 2M (slot 4, 0.4×), B stakes 2M (slot 0, 11.6×),
C stakes 5M (slot 2, 1.4×), D stakes 10M (slot 3, 0.7×).

```
pot        = 19,000,000
burn       = floor(19,000,000 × 30/10000) = 57,000
fee        = floor(19,000,000 × 30/10000) = 57,000
payoutPool = 18,886,000
scores     = A: 2M×40 = 80,000,000
             B: 2M×1160 = 2,320,000,000
             C: 5M×140 = 700,000,000
             D: 10M×70 = 700,000,000
Σ scores   = 3,800,000,000
payouts    = A: 397,600      (staked 2M  → −1,602,400)
             B: 11,530,400   (staked 2M  → +9,530,400)
             C: 3,479,000    (staked 5M  → −1,521,000)
             D: 3,479,000    (staked 10M → −6,521,000)
dust       = 0
check      = 397,600 + 11,530,400 + 3,479,000 + 3,479,000 + 57,000 + 57,000 = 19,000,000 ✓
```

### Worked example 2 — everyone lands the same slot (tie)

3 players, stakes 2M / 5M / 10M, all land slot 4 (0.4×). Equal multipliers
cancel out, so the split is purely proportional to stake:

```
pot = 17,000,000   burn = 51,000   fee = 51,000   payoutPool = 16,898,000
payouts = 1,988,000 / 4,970,000 / 9,940,000   (each = 0.994 × stake)   dust = 0
```

Ties need **no special handling** — proportional split handles them naturally.

### Worked example 3 — flooring dust

3 players, 2M each: A lands slot 0 (11.6×), B and C land slot 4 (0.4×).

```
pot = 6,000,000   burn = 18,000   fee = 18,000   payoutPool = 5,964,000
scores = A: 2,320,000,000   B: 80,000,000   C: 80,000,000   Σ = 2,480,000,000
payout A = floor(5,964,000 × 2,320,000,000 / 2,480,000,000) = 5,579,225
payout B = floor(5,964,000 ×    80,000,000 / 2,480,000,000) =   192,387
payout C = floor(5,964,000 ×    80,000,000 / 2,480,000,000) =   192,387
dust = 5,964,000 − 5,579,225 − 192,387 − 192,387 = 1 AGC  (stays in contract)
check = 5,579,225 + 192,387 + 192,387 + 18,000 + 18,000 + 1 = 6,000,000 ✓
```

---

## 4. Edge cases

| Case | Behavior | Why |
|---|---|---|
| 0 players | Nothing happens; no pot, no burn, no fee. | Trivially safe. |
| 1 player | **Full refund, no burn, no fee.** | Mirrors Battle Royale's "<2 rooms → refund" rule. A solo player must never lose to the house edge with nobody to play against. |
| ≥2 players, all same slot | Proportional-to-stake split; everyone gets 0.994 × stake. | Equal multipliers cancel (§3, example 2). |
| ≥2 players, any slots | Normal settlement. Denominator > 0 always. | Min multiplier 0.4 > 0 and stakes > 0. |
| 501st entry in a round | **Reverts "round full"**; player loses nothing but gas, joins the next round. | Safety cap (`MAX_PLAYERS = 500`, audit M-1): settle/refund loop over all players in one tx, so an unbounded round could exceed the block gas limit and lock its pot. 500 players ≈ 18.7M/16.1M gas, far below any block limit. |
| Ties for "best slot" | No special case. | Payout is proportional to score, not winner-take-all. |
| Nobody calls `draw` | Refund after a timeout (1 hour, mirroring Battle Royale). | Prevents funds being locked forever. |
| VRF word never arrives | Refund after timeout (1 hour after draw request). | Same safety net as Battle Royale. |
| Flooring dust | Stays in contract, bounded by < 1 AGC per player per round. | Accounted in conservation identity; never negative, never created from nothing. |

---

## 5. Provably fair randomness

**Production choice: one Chainlink VRF v2.5 word per round** (same wrapper
model Battle Royale uses), with per-player slots derived deterministically
from that single word.

### 5.1 Slot derivation (exact spec)

```
hash_i     = keccak256(abi.encode(word, roundId, player_i))
pathBits_i = uint8(uint256(hash_i) >> 248)   // first (most significant) 8 bits
slot_i     = popcount(pathBits_i)            // 0..8
```

Each of the 8 bits is one peg bounce (0 = left, 1 = right). Keccak256 output
bits are computationally indistinguishable from independent fair coins, so
the number of 1-bits in 8 bits follows exactly the binomial distribution:
`P(slot = k) = C(8,k) / 256` — identical to the physical board's peg
probabilities in §1. No modulo bias: 8 bits map onto 9 slots by counting,
not by `mod 9`, so every slot keeps its exact binomial weight.

### 5.2 Optional client seed

A player may pass a `clientSeed` (any `bytes32`) in the enter call. The
derivation then becomes:

```
hash_i = keccak256(abi.encode(word, roundId, player_i, clientSeed_i))
```

The client seed is **optional** (zero if omitted) and **does not change the
fairness guarantees**: the VRF word is unknown to everyone — players,
operator, and keeper alike — until after entries close, so no choice of
client seed can bias a slot toward a better outcome. It only lets a player
contribute their own entropy, Stake-style, for extra assurance.

### 5.3 Draw flow and phase machine

Rounds move through the same phases as Battle Royale:

| Phase | Meaning | Exit |
|---|---|---|
| `Open` | Entries accepted (5 minutes). | Round time ends → `AwaitingDraw` (or refund if < 2 players). |
| `AwaitingDraw` | Closed, ≥ 2 players, waiting for `draw(roundId)`. | Anyone calls `draw` (keeper normally does, seconds after close, paying the VRF fee in BNB) → `AwaitingRandom`. If nobody draws within **1 hour** of close → `Refunded`. |
| `AwaitingRandom` | VRF request sent (`requestId` stored on the round). | VRF callback delivers the word → settle → `Settled`. If the word never arrives within **1 hour** of the request → `Refunded`. |
| `Settled` | Slots derived, payouts credited, burn + fee taken. | Final. |
| `Refunded` | Every stake returned in full, no burn, no fee. | Final. |

The keeper has no special rights: `draw` is permissionless, nobody is paid
for drawing, and the VRF fee is quoted by `drawFee(gasPriceWei)` exactly as
in Battle Royale (excess fee refunded in the same transaction).

### 5.4 Why players can trust it (and how it differs from Stake/BC.Game)

- **The proof is verified by the contract itself.** Chainlink VRF returns
  the random word together with a cryptographic proof; the wrapper/contract
  verifies that proof on-chain before the word is accepted. A forged or
  substituted word cannot pass.
- **Nobody knows the outcome in advance.** Entries close *before* the word
  exists. The operator cannot pick a favorable word, cannot re-roll, and
  cannot front-run entries after seeing randomness.
- **Anyone can recompute everything.** Once the word is on-chain, every
  player's slot is a pure function of `(word, roundId, player[, clientSeed])`
  — all public. Any player or agent can re-derive all slots and re-run the
  §3 payout formula to verify settlement to the last AGC.
- **Contrast with Stake/BC.Game commit-reveal:** there, the house publishes
  `hash(serverSeed)` before betting and reveals the seed later, so the house
  cannot *change* outcomes after the fact — but the house **knows every
  outcome in advance** (it holds the seed), and verification depends on
  trusting the house's published verifier. With VRF, no party knows the
  outcome before the draw, and verification is enforced by the contract,
  not by the operator's website.

Why one word per round (not one per player):
- **Cost**: one VRF request per round regardless of player count; the keeper
  pays once, exactly like Battle Royale.
- **Verifiability**: one public word settles the whole round (§5.4).

The prototype uses a seeded PRNG (`mulberry32`) in place of VRF, with the
same derivation shape: seed → per-player 8-bit path → popcount → slot.

---

## 6. Agent playability

AGC is an agent coin, so the game is designed to be played by AI agents
through plain contract calls, mirroring Battle Royale's `bet / draw /
withdraw` pattern:

| Step | Call | Notes |
|---|---|---|
| Read round | `currentRound() → (roundId, opensAt, closesAt)` | One read tells the agent everything about timing. |
| Read board | `roundDetail(roundId) → (phase, totalStaked, playerCount, entries…)` | Live pot and entries are public, like Battle Royale's room totals. |
| Enter | `enter(roundId, amount, clientSeed)` | `amount` must be one of the 7 tiers; `clientSeed` is optional entropy (§5.2, zero if omitted). Stake is pulled from the player's wallet via `transferFrom` (approve the game contract first); in-game balance is NOT used for entries. One entry per address per round. |
| Draw | `draw(roundId)` + VRF fee in BNB | Normally the project keeper; any address may call it. Nobody is paid for drawing. |
| Read result | `result(roundId, player) → (staked, payout, slot)` | Full audit trail per player. |
| Withdraw | `withdraw(amount)` | Moves in-game balance to wallet. |

An agent guide file (`llms-plinko.txt`, modeled on `llms-arena.txt`) would
ship with the game: contract addresses, selectors, the exact integer payout
formula, and worked examples — so any agent can verify payouts independently
before staking. The `isAgent(player)` flag (Agent ID holder or not) can be
carried in the entry event exactly as Battle Royale does; rules and payouts
are identical for agents and humans.

---

## 7. Contract sketch (ABI-level, not production code)

> **Update (2026-11-26):** the production contract lives at
> `contracts/PlinkoRoyale.sol` and is deployed on BSC testnet
> (`0x4f65C6db7ECA6E81B7fb139D0d539b5ae2E1d614`, redeployed 2026-11-26
> with the 0.6% fee model below; the earlier `0x20Aa35C4…` deployment
> ran 1%). It follows this sketch
> with two additions from the internal audit: a `MAX_PLAYERS = 500`
> constant enforced in `enter()` (M-1) and a `playersOf(roundId)` view
> returning the entrant list (L-6). Also on 2026-11-26 the owner approved
> lowering the fee model from 0.5% burn + 0.5% operational fee (1% total)
> to **0.3% burn + 0.3% operational fee (0.6% total)** to match AGC Battle
> Royale's ~0.625% expected edge; the constants in the production source
> are `BURN_BPS = 30` / `FEE_BPS = 30` (the sketch below still shows the
> original 50/50 values). The sketch below is kept as the
> original design record.

```solidity
// SPDX-License-Identifier: MIT
// SKETCH ONLY — for design review. Not audited, not deployed.

interface IPlinkoRoyale {
    // --- constants (immutable, no owner, no admin, no pause — like Battle Royale)
    function stakeTiers() external pure returns (uint256[7] memory); // 100K..10M
    function multipliersX100() external pure returns (uint16[9] memory);
    function burnBps() external pure returns (uint256);              // 50 (0.5%)
    function feeBps() external pure returns (uint256);               // 50 (0.5%)
    function feeRecipient() external view returns (address);         // immutable, set at deploy
    function deadAddress() external pure returns (address);          // 0x0000...dEaD
    function wrapper() external view returns (address);              // Chainlink VRF v2.5 wrapper

    // --- reads
    function currentRound() external view returns (uint256 id, uint64 opensAt, uint64 closesAt);
    function roundDetail(uint256 roundId) external view returns (
        uint8 phase,          // 0 Open, 1 AwaitingDraw, 2 AwaitingRandom, 3 Settled, 4 Refunded
        uint64 opensAt, uint64 closesAt,
        uint256 totalStaked, uint256 playerCount,
        uint256 requestId,    // VRF request id (0 until drawn)
        uint256 burned, uint256 feePaid, uint256 dust
    );
    function entryOf(uint256 roundId, address player) external view
        returns (uint256 stake, bytes32 clientSeed, uint8 slot, uint256 payout);
    function balanceOf(address player) external view returns (uint256); // in-game balance
    function result(uint256 roundId, address player) external view
        returns (uint256 staked, uint256 payout, uint8 slot);
    function wordReceivedOf(uint256 roundId) external view returns (bool); // VRF fulfilled?
    function drawRequestedAtOf(uint256 roundId) external view returns (uint256); // refund anchor

    // --- writes
    function enter(uint256 roundId, uint256 amount, bytes32 clientSeed) external; // amount in tiers; clientSeed optional (0 ok)
    function draw(uint256 roundId) external payable;            // pays VRF fee
    function drawFee(uint256 gasPriceWei) external view returns (uint256);
    function withdraw(uint256 amount) external;

    // --- events
    event Entered(uint256 indexed roundId, address indexed player, uint256 amount, bytes32 clientSeed);
    event DrawRequested(uint256 indexed roundId, uint256 requestId);
    event Settled(uint256 indexed roundId, uint256 pot, uint256 burned, uint256 feePaid, uint256 dust);
    event Refunded(uint256 indexed roundId, uint256 pot);
    event Withdrawn(address indexed player, uint256 amount);
}
```

Settlement pseudocode (the part that must be exactly right — this is the same
logic as `verify.py::settle_round`):

```
function settle(roundId, word):
    players = entries[roundId]
    if players.length < 2: refundAll(roundId); return
    for each player:
        slot_i = popcount(uint8(uint256(keccak256(abi.encode(word, roundId, player_i, clientSeed_i))) >> 248))
    pot = Σ stake
    burn = pot * 50 / 10000                  // integer floor, 0.5%
    fee  = pot * 50 / 10000                  // integer floor, 0.5%
    payoutPool = pot - burn - fee
    totalScore = Σ stake_i * MULT[slot_i]    // > 0 guaranteed
    for each player:
        payout_i = payoutPool * score_i / totalScore   // integer floor
        balance[player] += payout_i
    dust = payoutPool - Σ payout_i           // stays in contract
    transfer(deadAddress, burn)              // 0x0000...dEaD
    transfer(feeRecipient, fee)              // immutable address
```

Safety properties an auditor should check (all proven in `verify.py`):
1. `Σ payouts + burn + fee + dust == pot` for every round.
2. No payout is negative or exceeds the pot.
3. Division by zero is unreachable (min multiplier > 0, stakes > 0, ≥2 players).
4. <2 players ⇒ full refund, zero burn, zero fee.
5. Dust per round < number of players (payout flooring bound); total
   flooring deviation from exact rational accounting < players + 2
   (the two bps floors each under-collect by < 1 AGC, paid to players
   via payoutPool).

---

## 8. Verification results

`verify.py` (stdlib only, integer math) ran **20,000 randomized rounds**
(2–50 players, random tiers, binomial ball drops; every 97th round forced to
0–1 players to exercise the refund rule) plus 7 deterministic edge cases.
Every round asserted: exact conservation (payouts + burn + fee + dust = pot),
non-negative payouts, no division by zero, correct burn and fee amounts,
dust within the flooring bound, and correct refund behavior.

```
Plinko Royale verification — seed 20261126
  randomized rounds simulated : 20,000
  deterministic edge cases    : 7
  refund rounds (<2 players)  : 207
  all-same-slot rounds        : 96
  total pot simulated         : 2,917,917,000,000 AGC
  total burned (0.5%)         : 14,586,575,000 AGC
  total operational fee (0.5%)    : 14,586,575,000 AGC
  total dust (flooring)       : 246,682 AGC
  max dust in one round       : 45 AGC
  ALL ASSERTIONS PASSED: conservation exact, no negatives,
  no division by zero, refund rule correct.
```

> Note: the run above was produced under the original 0.5% + 0.5% fee
> model. `verify.py` now uses 30/30 bps (0.3% + 0.3%); re-run it to
> refresh these totals (the assertions themselves are fee-model
> agnostic — they check burn/fee against the constants).

Reproduce: `python3 verify.py 20000 20261126`

The BigInt settlement in `PROTOTYPE.html` was additionally cross-checked
against `verify.py` on 509 cases (the 3 worked examples above, 6 edge
cases, 500 randomized rounds) — outputs identical, including burn, fee,
and dust.

---

## 9. Design decisions (and why)

1. **PvP pot, no bankroll** — the contract can never be drained by winners;
   it only redistributes. This is the property that makes Battle Royale safe
   for a small project, and Plinko Royale keeps it.
2. **Proportional-to-score split** (not winner-take-all) — every player gets
   *something* back unless their score share is tiny; ties need no rules;
   variance is lower than BR's all-or-nothing room kill, which suits a
   casual Plinko feel.
3. **EV of multiplier = exactly 1.0** — the table is fair before fees, so
   the *only* house take is the transparent 0.6% (0.3% burn + 0.3% operational
   fee), both hard-coded constants. No hidden edge.
4. **Fixed stake tiers** — anti-whale, mirrors Battle Royale, and bounds
   every number in the system (max pot with N players is known in advance).
5. **One entry per address per round** — simpler than BR's raise/add model;
   fewer states to audit. (Can be relaxed later; settlement math is unchanged.)
6. **One VRF word per round** — cheapest verifiable randomness; slots derived
   by hash, recomputable by anyone. Provably fair in the strong sense: the
   VRF proof is verified by the contract and nobody knows the outcome
   before the draw (§5.4) — unlike casino commit-reveal, where the house
   holds the seed and knows outcomes in advance.
7. **Dust stays in contract** — simplest correct choice; bounded and
   accounted. A production version may sweep dust into the next pot.
8. **Operational fee with immutable recipient** — the 0.3% fee funds operations
   (e.g. the VRF keeper's BNB costs) but the recipient address is fixed at
   deploy with no admin function to change it, same trust model as Battle
   Royale's ownerless contract. The burn half keeps the deflationary sink
   that AGC holders already track.
9. **Optional client seed** — players may contribute their own entropy
   (Stake-style) without weakening fairness, since the VRF word remains
   unknown to everyone until after close (§5.2).
