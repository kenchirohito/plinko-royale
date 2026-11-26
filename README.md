# Plinko Royale

A PvP Plinko game for the AGC (Agentic Coin) ecosystem on BSC.

Players stake fixed tiers (100K / 300K / 500K / 1M / 2M / 5M / 10M AGC,
mirroring Battle Royale) into a shared pot each
1-minute round. One Chainlink VRF random word per round decides every
player's Plinko slot (8 peg rows, 9 slots, multipliers 0.4x–11.6x with
expected value exactly 1.0), and the pot is split proportionally to
score (stake × multiplier). There is no house and no bankroll: players
pay each other, so the game cannot go bankrupt and nobody can rig the
outcome.

- 0.3% of every pot is burned, 0.3% goes to a fixed operational-fee
  address (VRF fees, keeper, hosting, maintenance), 99.4% is paid to
  players. Total edge 0.6%, disclosed up front and locked in code.
- The contract has **no owner, no admin, no pause, no setters, no
  upgrade path**. Fee recipient and stake token are immutable.
- Every slot and payout is recomputable from public on-chain data.
- AI agents can play with plain contract calls — see
  [`llms-plinko.txt`](llms-plinko.txt).

## Status

**BSC testnet only. Not on mainnet.** A formal independent audit,
a permanent fee-recipient decision, and testnet→mainnet config
migration are still outstanding before any mainnet launch.

| | |
|---|---|
| Game contract (testnet, chain 97) | `0x5133d3a7b0AAb6dFb3c40b824741FA4A776Bc3EF` |
| Stake token (testnet) | MockAGC `0x17356908F432eD7F2a4b378F19b5c869b872e21E` (open faucet mint) |
| VRF wrapper | Chainlink VRF v2.5 `0x471506e6ADED0b9811D05B8cAc8Db25eE839Ac94` |
| Frontend (testnet demo) | https://plinko-royale-testnet-kenchiro.vercel.app |

## Layout

- [`DESIGN.md`](DESIGN.md) — game design, economics, fairness model
- [`contracts/`](contracts/) — `PlinkoRoyale.sol` (single file, zero
  imports, solc 0.8.28) + Foundry tests (52 passing, incl. a
  2,000-run conservation fuzz). Run `forge install` then `forge test`
  (forge-std is a submodule, not vendored).
- [`frontend/`](frontend/) — single-file testnet frontend (ethers v6)
- [`keeper.py`](keeper.py) — permissionless draw/settle/refund keeper
- [`verify.py`](verify.py) — reference settlement math (20,000-round
  conservation check)
- [`PROTOTYPE.html`](PROTOTYPE.html) — playable offline prototype
- [`llms-plinko.txt`](llms-plinko.txt) — agent play guide
- [`AUDIT-REPORT.md`](AUDIT-REPORT.md) — internal audit + follow-ups
- [`EXTERNAL-AUDIT-GEMINI.md`](EXTERNAL-AUDIT-GEMINI.md) — external
  model audit summary (all findings fixed; see `AUDIT-REPORT.md` §11)
- [`testnet/`](testnet/) — deployment reports, stress test, agent
  round script

## Fairness in one paragraph

Entries close before the VRF word exists. Each player's slot is
`popcount` of the top 8 bits of
`keccak256(abi.encode(word, roundId, player, clientSeed))`, which is
exactly binomial C(8,k)/256. Settlement is integer math:
`payout_i = floor(payoutPool × score_i / Σ scores)`, with
`sum(payouts) + burn + fee + dust = pot` to the wei. Rounds with fewer
than 2 players, no draw within 1 hour, or no VRF word within 1 hour
of the draw are fully refunded.
