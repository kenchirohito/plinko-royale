# Plinko Royale — Paket Sebar (siap copy-paste)

Dibuat 26 Nov 2026. Isi file ini: link resmi, cara coba 2 menit, teks siap
kirim (ID + EN, versi grup + versi dev), dan FAQ singkat. Semua alamat di
bawah disalin persis dari `testnet/TESTNET-REPORT.md` dan `llms-plinko.txt`.

> **Status jujur (jangan diubah saat menyebar):** ini **testnet** (BSC
> Testnet, chain 97) dengan token bohongan (MockAGC) — bukan AGC asli,
> tidak bernilai, **belum mainnet**. Kontrak sudah lolos audit internal
> (0 Critical / 0 High) dan satu ronde penuh terverifikasi on-chain, tapi
> audit independen tetap wajib sebelum mainnet. Jangan janjikan tanggal
> mainnet atau keuntungan apa pun.

---

## 1. Link & alamat

| Apa | Link / alamat |
| --- | --- |
| Demo testnet (browser) | https://plinko-royale-testnet-kenchiro.vercel.app |
| Kontrak game (testnet, **current**) | `0x5133d3a7b0AAb6dFb3c40b824741FA4A776Bc3EF` — https://testnet.bscscan.com/address/0x5133d3a7b0AAb6dFb3c40b824741FA4A776Bc3EF |
| Kontrak lama (**superseded, jangan dipakai**) | `0x9F485aF31008f9678F43b4f9f81cD11C7216f79c`, `0x20Aa35C4441F05f5435c812308A6620536B54fa2`, `0x66d8e0d61f3b89d1962bfef0cd19be767a2a3d49`, `0x8643ab8Fe68aBC315aC7D38b5518e6cc3644F0a7`, `0x4f65C6db7ECA6E81B7fb139D0d539b5ae2E1d614` |
| Token test (MockAGC) | `0x17356908F432eD7F2a4b378F19b5c869b872e21E` |
| Proposal ID (5 halaman) | `~/workspace/your_files/plinko-royale-proposal/plinko-royale-proposal.pdf` |
| Proposal EN (5 halaman) | `~/workspace/your_files/plinko-royale-proposal-en/plinko-royale-proposal-en.pdf` |
| Panduan agent (llms) | `~/workspace/plinko-royale/llms-plinko.txt` |
| Laporan audit internal | `~/workspace/plinko-royale/AUDIT-REPORT.md` |
| Laporan testnet (tx + angka ronde) | `~/workspace/plinko-royale/testnet/TESTNET-REPORT.md` |
| Faucet tBNB (gas testnet) | https://www.bnbchain.org/en/testnet-faucet |

Catatan demo live: fee **sudah diputuskan dan diterapkan** 26 Nov 2026
11:38–11:49 WIB atas perintah owner — turun dari 1% ke **0,6% total
(0,3% burn + 0,3% fee operasional)**, setara Battle Royale. Tangga tier
juga **sudah disamakan persis Battle Royale** atas perintah owner 26 Nov
2026 ~16:28 WIB: **100K/300K/500K/1M/2M/5M/10M AGC** (sebelumnya
2jt/5jt/10jt). Kontrak current
`0x5133d3a7b0AAb6dFb3c40b824741FA4A776Bc3EF` (BURN_BPS/FEE_BPS = 30,
cap 500 pemain, 52/52 tes, Sourcify exact_match). Ronde verifikasi
~13:42 WIB (5 bot, pot 24jt, burn/fee 72.000 masing-masing, keeper
draw+settle sendiri) itu di kontrak **sebelumnya** `0x8643…F0a7`,
bukan di kontrak current — ronde verifikasi untuk `0x4f65…` (5 bot,
tier campuran 100K/300K/1jt/2jt/10jt, pot 13,4jt, burn/fee 40.200
masing-masing) lolos dan dilaporkan 26 Nov ~17:04 WIB; hasilnya
tercatat di `testnet/TESTNET-REPORT.md` §7-tier. Ronde kemudian
dipendekkan jadi **1 menit** atas perintah owner 26 Nov ~19:01 WIB —
ronde verifikasi #1 di kontrak current `0x5133…c3EF` lolos malam itu
juga (5 bot dalam satu jendela 60 detik, tier 100K/500K/1M/5M/10M,
pot 16,6jt, burn/fee 49.800 masing-masing, conservation exact;
tercatat di `testnet/TESTNET-REPORT.md`). Frontend
live + `frontend/index.html` + `keeper.py` sudah menunjuk alamat ini.
**Teks §3–§4 + FAQ §6 sudah disamakan ke angka current 27 Nov atas
perintah owner. Proposal PDF masih memakai angka lama
0,5% + 0,5% — JANGAN disebar** sampai disamakan; owner memerintahkan
proposal menyusul, fokus dulu ke konsep dan desain ekonomi game
(26 Nov 11:38 WIB).

## 2. Cara coba (2 menit, testnet)

1. Buka demo, klik **Hubungkan Wallet** — MetaMask akan minta pindah ke
   BSC Testnet (chain 97).
2. Ambil tBNB gratis dari faucet (link di atas) buat gas.
3. Klik **Ambil 100jt AGC test** (token bohongan, gratis).
4. Pilih taruhan 100rb / 300rb / 500rb / 1jt / 2jt / 5jt / 10jt, klik
   **Ikut Ronde** (ronde tiap 1 menit, maks 500 pemain/ronde).
5. Setelah ronde tutup: **Draw** (Chainlink VRF) → **Settle** → payout
   masuk saldo game → **Tarik** ke wallet. Ronde <2 pemain bisa di-refund
   penuh.

Agent AI tidak perlu website: semua langkah di atas bisa lewat contract
call langsung — panduannya di `llms-plinko.txt`.

## 3. Teks siap kirim — versi grup (ID, pendek)

> Halo semua — gue lagi bangun **Plinko Royale**, game PvP Plinko buat
> ekosistem AGC (pola Battle Royale: pot dari pemain, tanpa bandar).
> Taruhan tetap 100rb/300rb/500rb/1jt/2jt/5jt/10jt AGC per ronde
> 1 menit, hasil dari Chainlink VRF, potongan transparan 0,3% burn +
> 0,3% fee operasional, sisanya 99,4% ke pemain. Kontraknya tanpa
> owner/admin, dan AI agent bisa ikut main lewat contract call langsung.
>
> Sekarang sudah jalan di **BSC Testnet** (token bohongan, gratis dicoba):
> demo + proposal + laporan audit internal gue lampirkan. Minta feedback:
> coba satu ronde, terus bilang bagian mana yang membingungkan atau
> terasa tidak fair. Belum mainnet — audit independen masih antre.
> Makasih!

## 4. Teks siap kirim — versi dev (EN, teknis)

> **Plinko Royale — PvP Plinko for the AGC ecosystem (testnet)**
>
> One shared pot per 1-minute round, fixed stakes
> (100K/300K/500K/1M/2M/5M/10M), max 500 entries/round. One Chainlink
> VRF v2.5 word per round; each player's slot = popcount of the top byte of
> `keccak256(word, roundId, player, clientSeed)` (9 slots, EV exactly 1.0
> before fees). Settlement: 0.3% burn + 0.3% operational fee (immutable
> recipient) + 99.4% split by stake × multiplier. No owner, no admin, no
> bankroll, no upgrade path — players pay each other.
>
> Testnet (chain 97): game `0x5133d3a7b0AAb6dFb3c40b824741FA4A776Bc3EF`
> (Sourcify exact_match), MockAGC `0x17356908F432eD7F2a4b378F19b5c869b872e21E`.
> 52/52 Foundry tests pass (incl. adversarial + 2,000-round fuzz);
> internal audit: 0 Critical / 0 High; external model audit findings all
> fixed and redeployed (reports attached). Agents can play
> with plain contract calls — see `llms-plinko.txt`. A full round was
> played agent-only via cast and verified to the wei.
>
> Ask: review the contract (`PlinkoRoyale.sol`, single file, zero
> imports) and try one testnet round. Mainnet still needs an independent
> audit and a permanent fee-recipient decision — nothing is live with
> real funds.

## 5. Checklist sebelum sebar (owner)

- [x] Redeploy frontend Vercel ke kontrak current — terakhir ke
      `0x5133…c3EF` (redeploy ronde 1 menit 26 Nov ~19:02 WIB atas
      perintah owner, `ROUND_DURATION = 60`, 52/52 tes; ronde
      verifikasi #1 lolos malam itu juga: 5 bot dalam satu jendela
      60 detik, pot 16,6jt, burn/fee 49.800 masing-masing, tercatat
      di `testnet/TESTNET-REPORT.md`). Redeploy sebelumnya:
      `0x4f65…d614` (7-tier 26 Nov ~16:28 WIB, sekarang superseded),
      lalu
      `0x8643…F0a7` ~13:32 WIB (audit eksternal: LOW-1 + view baru,
      51/51 tes; frontend live terverifikasi di ronde #1 kontrak itu,
      dilaporkan ~13:42 WIB) — alamat itu sekarang superseded.
- [x] Fee final diputuskan owner 26 Nov 11:38 WIB: **0,6% (0,3% burn +
      0,3% operasional)**. Sudah diterapkan: konstanta kontrak (30/30),
      redeploy testnet (terbaru `0x5133…c3EF`, termasuk tangga tier
      100K–10M atas perintah owner ~16:28 WIB dan ronde 1 menit atas
      perintah owner ~19:01 WIB), frontend, keeper, llms.
      Teks §3–§4 + FAQ §6 file ini sudah disamakan 27 Nov atas
      perintah owner. Masih harus disamakan sebelum sebar: proposal
      ID + EN dan sketsa angka di DESIGN.md.
- [ ] Putuskan patch hardening frontend (`frontend/PATCH-HARDENING.md`)
      diterapkan atau tidak — belum terkonfirmasi masuk redeploy
      11:27 WIB.
- [ ] Jalankan keeper testnet (`python3 keeper.py --once` dry-run dulu,
      lalu `--loop --live` / cron) supaya ronde demo tidak macet menunggu
      klik Draw/Settle manual. Pastikan wallet keeper ada tBNB.
- [ ] Uji sekali di MetaMask mobile (audit I-10 belum teruji di perangkat
      asli) sebelum link disebar luas.
- [ ] Putuskan alamat fee operasional **permanen** untuk mainnet nanti
      (immutable — tidak bisa diganti setelah deploy). Alamat testnet
      sekarang `0x627Ce1AEda3f4B8f2f63E6051Ddd1304fc533c87` hanya untuk testnet.
- [ ] Jangan sebar alamat kontrak lama `0x9F48…f79c` — superseded.

## 6. FAQ singkat

**Ini fair?** Hasil ditentukan Chainlink VRF setelah pendaftaran tutup;
slot tiap pemain bisa dihitung ulang siapa pun dari data publik. Tabel
pengali EV-nya persis 1,0 — satu-satunya potongan adalah 0,6% yang tertulis
(0,3% burn + 0,3% operasional).

**Siapa yang bayar pemenang?** Pemain lain. Pot ronde dibagi ke pemain;
kontrak tidak pegang bankroll, jadi game tidak bisa bangkrut dan owner
tidak bisa menyentuh dana (tidak ada fungsi admin sama sekali).

**Agent AI bisa main?** Bisa — `enter / draw / settle / withdraw` lewat
contract call, tanpa website. Panduan: `llms-plinko.txt`.

**Kapan mainnet?** Belum diputuskan. Syaratnya: audit independen atas
kontrak final, alamat fee permanen, verifikasi ulang wrapper VRF mainnet,
dan keeper yang jalan terus. Testnet ini buat validasi + feedback dulu.
