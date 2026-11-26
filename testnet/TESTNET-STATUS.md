# Plinko Royale — BSC Testnet Deployment Status

**Status: COMPLETE.** Updated 2026-11-26. Full details in
[TESTNET-REPORT.md](TESTNET-REPORT.md).

> **Redeployed 2026-11-26** (latest) with 1-minute rounds
> (`ROUND_DURATION` 300 → 60; includes the 7-tier stake ladder
> mirroring Battle Royale, the earlier external-audit fixes,
> 500-player cap, `playersOf`, and the 0.3%+0.3% fee model):
> current contract is
> `0x5133d3a7b0AAb6dFb3c40b824741FA4A776Bc3EF` (Sourcify exact_match,
> matchId 59996220).
> The steps below describe the first deployment; see the "Redeployment"
> section in TESTNET-REPORT.md for the current one.

- [x] Step 1 — Testnet-only wallets created in `keys/` (see `keys/README.md`):
  - Deployer: `0x5aC2E2c437506B5F34Dd231c89078f03fEb0A6ee`
  - Player 1: `0x882A3B4e3A2A54b5CfC5A31706E8b40907778197`
  - Player 2: `0x66f82b1270F8F4b5ccF767Ad1aA24881F156E5Cc`
- [x] Step 2 — Funding: deployer received 1.0 tBNB (owner-sent); 0.05 tBNB
  forwarded to each player.
- [x] Step 3 — Chainlink VRF v2.5 wrapper verified on chain 97:
  `0x471506e6ADED0b9811D05B8cAc8Db25eE839Ac94`.
- [x] Step 4 — MockAGC deployed
  (`0x17356908F432eD7F2a4b378F19b5c869b872e21E`); 100M minted to each player.
- [x] Step 5 — PlinkoRoyale deployed
  (`0x9F485aF31008f9678F43b4f9f81cD11C7216f79c`) with feeRecipient
  `0x627Ce1AEda3f4B8f2f63E6051Ddd1304fc533c87`. Sourcify verification
  submitted (job `b6906820-b564-4694-be98-2e27257fafda`), status unconfirmed.
- [x] Step 6 — Round 0 played end-to-end: 2M + 5M entries, VRF draw,
  settle, conservation verified exactly (payouts + burn 35,000 + fee 35,000
  + 1 wei dust = 7,000,000 pot), Player 1 withdrew successfully.
- [x] Step 7 — TESTNET-REPORT.md written with addresses, tx hashes, results.

RPC used: `https://data-seed-prebsc-1-s1.bnbchain.org:8545/` (chain 97).
Foundry: `~/.foundry/bin` (forge/cast 1.10.0). Note: chain 97 requires
legacy txs (`--legacy --gas-price 100000000`).
