# Audit Eksternal (Gemini) — Plinko Royale — 2026-11-26

Sumber: laporan audit model lain (Gemini) yang dibaca via link share
https://share.gemini.google/owzLYbQI0TpV pada 2026-11-26 13:25 WIB.
Bundle yang diaudit: `plinko-royale-source-bundle.txt` (12 file inti).

**Verdict: BELUM SIAP MAINNET** — kontrak inti aman (Critical 0, High 0),
tetapi frontend, keeper, dan migrasi konfigurasi harus dibenerin dulu.
Hitungan: Critical 0 | High 0 | Medium 2 | Low 6 | Info 2.

## Yang terverifikasi aman oleh auditor

- Kontrak immutable/ownerless, CEI + nonReentrant, conservation persis wei.
- M-1 terverifikasi: MAX_PLAYERS=500, settle 500 pemain ~18,75jt gas,
  refund ~16,1jt gas — jauh di bawah limit blok BSC ~140jt.
- M-2 terverifikasi dengan catatan: transfer burn/fee di settle() aman
  untuk AGC asli (ERC20 standar, tanpa pause/blacklist).
- Matematika: EV tabel multiplier tepat 1,0; return bersih 99,4% setelah
  0,3% burn + 0,3% fee; slot dari popcount 8-bit teratas, tanpa modulo bias.
- Tidak ditemukan bug bola demo jatuh sebelum settle (sudah dibenerin).

## Temuan

### MEDIUM-1 — Badai RPC N+1 di frontend
`frontend/index.html` fetchPlayers/renderResults memanggil entryOf/result
per pemain tiap 6 detik tanpa cache. Di ronde 500 pemain: 501–1.001
eth_call paralel tiap 6 detik → RPC publik kena 429, UI lumpuh.
Fix: Multicall3 (0xcA11bde05977b3631167028862bE2a173976CA11) + hitung
hasil ronde settled lokal di JS dari word on-chain.

### MEDIUM-2 — Jendela scan keeper.py terlalu sempit
`keeper.py` hanya memindai current_id-2..current_id (10–15 menit),
padahal refund timeout baru aktif setelah 1 jam (12 ronde) → refund
otomatis tidak pernah terpicu. Gas price juga hardcoded 0,1 gwei.
Fix: scan sampai current_id-20 / simpan active_rounds di state,
gas price dinamis dari RPC.

### LOW-1 — Inkonsistensi 1 detik di roundDetail() (kontrak)
`PlinkoRoyale.sol:382-383` memakai `block.timestamp > closesAt`,
sedangkan _currentRoundId sudah pindah ronde tepat di closesAt.
Fix: `>=` bila kontrak di-compile ulang sebelum mainnet; kalau tidak,
dokumentasikan di panduan agent.

### LOW-2 — Gas price draw() frontend bisa mismatch
Frontend menghitung drawFee dari readProvider +20%, kontrak memakai
tx.gasprice wallet pengguna → bisa revert "insufficient VRF fee".
Fix: kirim {value, gasPrice} eksplisit atau buffer 150%.

### LOW-3 — ethers.js dari CDN tanpa SRI
`index.html:206` tanpa integrity/crossorigin. Fix: tambah hash SRI
atau self-host file ethers.

### LOW-4 — Potensi DOM XSS via friendlyError()
Pesan error RPC/wallet masuk ke innerHTML tanpa escaping.
Fix: escape & < > " ' sebelum ditampilkan.

### LOW-5 — Race condition animasi bola + word==0
animPlayedFor ditandai sebelum cek animating; playSettleAnimations
membaca global viewRoundId/lastWord di loop async; tombol Settle mati
kalau word VRF persis 0. Fix: snapshot {roundId, word} lokal, tandai
setelah cek, izinkan settle saat phase 2 dengan status menunggu VRF.

### LOW-6 — Tombol Refund aktif terlalu dini
Aktif di phase 2 tanpa cek 1 jam sejak drawRequestedAt → pengguna
bisa buang gas untuk tx yang pasti revert.
Fix: cek timestamp event DrawRequested + 3600.

### INFO-1 — Kebocoran timer provider saat rotateRpc()
Provider lama tidak di-destroy(). Fix: destroy() + staticNetwork.

### INFO-2 — Dokumentasi tidak sinkron dengan kode final
DESIGN.md masih menyebut stake dari saldo game & event agent;
CONTRACT.md menyebut 27 test (aktual 49); AUDIT-REPORT.md:203 alamat
lama 0x20Aa…; NatSpec PlinkoRoyale.sol:588-591 estimasi gas lama.
Fix: samakan teks dokumen + NatSpec.

## Checklist pra-mainnet auditor

1. Fix MEDIUM-1 (Multicall3 + hitung lokal).
2. Fix MEDIUM-2 (scan keeper + gas dinamis).
3. Hardening frontend LOW-2..6 + INFO-1.
4. Bersihkan mode testnet (banner, faucet, CHAIN_ID 56, explorer, RPC mainnet).
5. Deploy mainnet dengan parameter terverifikasi (token AGC asli,
   feeRecipient permanen, wrapper VRF re-verify di docs.chain.link).
6. Sinkronkan alamat mainnet ke frontend/keeper/llms + docs INFO-2.
