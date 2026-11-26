# Plinko Royale — Testnet Frontend

Single-file static page (`index.html`, ethers v6 via CDN) connected to the
BSC testnet deployment. No build step, no keys, testnet only.

- **Live:** https://plinko-royale-testnet-kenchiro.vercel.app
- **Vercel project:** `plinko-royale-testnet` (team kenchiro, `prj_FEZTKmeZff7DHmvWtXUIuZQUrmyw`)
- **Contracts (chain 97):** PlinkoRoyale `0x4f65C6db7ECA6E81B7fb139D0d539b5ae2E1d614`
  (redeployed 2026-11-26 with the 500-player cap + `playersOf` view;
  Sourcify exact_match),
  MockAGC `0x17356908F432eD7F2a4b378F19b5c869b872e21E`
- **Deploy block:** 144883915 (reference only — player lists now come from
  the `playersOf` view, not event scans)

## Redeploy

Edit `index.html`, then create a new production deployment with the file
inlined (Vercel MCP `create_deployment`, name `plinko-royale-testnet`,
target `production`, files `[{file: "index.html", data: <utf-8>, encoding: "utf-8"}]`).
SSO deployment protection was disabled on this project so the demo is public;
if the URL ever redirects to a Vercel login again, set `ssoProtection: null`
via `update_project`.

## Notes

- Read-only mode works without a wallet (public RPC); actions need MetaMask
  on BSC testnet. Test AGC comes from MockAGC's public `mint` (faucet button).
- `draw()` sends `drawFee(gasPrice)` + 20% buffer; the contract refunds excess.
- The ball animation recomputes the exact slot path from the VRF word
  (`keccak256(word, roundId, player, clientSeed)`, top byte) — visual only;
  payouts always come from `result()`.
