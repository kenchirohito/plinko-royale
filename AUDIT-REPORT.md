# Plinko Royale — Laporan Audit Internal

**Tanggal:** 26 November 2026
**Cakupan:** kontrak `PlinkoRoyale.sol`, frontend testnet (`frontend/index.html`), dan jalur main untuk AI agent.
**Jaringan pengujian:** BSC Testnet (chain 97) saja. Tidak ada mainnet, tidak ada dana asli, tidak ada wallet pengguna yang disentuh.

---

## Ringkasan eksekutif (bahasa sederhana)

**Putusan: sistemnya sehat untuk ukuran prototype yang sudah terbukti di testnet. Tidak ditemukan celah kritis atau tinggi.** Uang pemain tidak bisa dicuri lewat celah yang ditemukan dalam audit ini: hitungan payout terbukti pas sampai wei terakhir di 47 tes otomatis + 20.000 simulasi, serangan reentrancy (serangan klasik yang paling sering menguras kontrak game) terbukti mental, dan satu ronde penuh berhasil dimainkan oleh "agent" murni lewat contract call tanpa frontend sama sekali.

**Dua hal yang perlu diputuskan sebelum mainnet:**

1. **Batas jumlah pemain per ronde.** Kalau satu ronde diisi ribuan pemain, transaksi settlement-nya bisa terlalu besar untuk masuk ke satu blok, dan pot ronde itu terkunci selamanya. Ini butuh ribuan entri dalam 5 menit — belum tentu terjadi, tapi kalau terjadi, tidak ada jalan keluar. Perbaikannya sederhana: batasi pemain per ronde (mis. 500) atau bagi settlement jadi beberapa transaksi.
2. **Audit independen.** Laporan ini audit internal. Sebelum mainnet dengan uang asli, kontrak yang sama persis ini tetap harus diaudit pihak independen.

**Yang sudah kokoh:**

- **Matematika uang:** payout + burn + fee + debu pembulatan selalu persis sama dengan pot. Dibuktikan di 47 tes Foundry (termasuk fuzz 2.000 ronde) dan simulasi Python 20.000 ronde dengan seed baru.
- **Anti-curang:** angka acak dari Chainlink VRF, entri tutup sebelum angka ada, semua slot bisa dihitung ulang siapa pun. Di ronde testnet, slot hasil hitungan lokal cocok persis dengan on-chain.
- **Anti-serangan klasik:** reentrancy di withdraw/settle/enter/draw terbukti diblokir; token yang berbohong (return false, tidak transfer, kena pajak) ditolak bersih tanpa merusak catatan.
- **Token AGC asli aman dipakai:** source AGC terverifikasi di Sourcify — pajak 2% hanya untuk jual-beli di pair PancakeSwap; transfer wallet-ke-wallet (semua transfer game ini) tidak kena pajak. Tidak ada fungsi pause/blacklist/owner di token AGC, jadi skenario "token berhenti bekerja lalu game macet" tidak bisa terjadi dengan AGC yang sekarang terdeploy.
- **Jalur agent berfungsi penuh:** satu ronde dimainkan end-to-end hanya dengan `cast` (approve → enter → draw → settle → withdraw), semua cek lolos.

**Jumlah temuan:** Critical 0 · High 0 · Medium 2 · Low 6 · Info 12.

---

## 1. Metode & cakupan

| Bagian | Yang diperiksa | Cara |
|---|---|---|
| Kontrak | `PlinkoRoyale.sol` (semua fungsi), 27 tes bawaan, `verify.py`, `DESIGN.md`, `CONTRACT.md` | Baca manual baris per baris; 20 tes adversarial baru (`test/Adversarial.t.sol`); slither 0.11.6; fuzz 2.000 run; `verify.py` seed baru |
| Frontend | `frontend/index.html` (seluruh file), `frontend/README.md` | Baca manual; grep sink `innerHTML`, approval, script eksternal, permintaan key/seed |
| Agent | Interface kontrak + testnet live | Script `testnet/agent-round.sh` (bash+cast) memainkan 1 ronde penuh; uji penemuan pemain via event di 2 RPC publik |
| Token AGC | Source terverifikasi di Sourcify (chain 56, `0x63dea5aC…84bA6`) | Baca `_update` (logika pajak) — read-only, tanpa transaksi mainnet |

Hasil tes: **47/47 lolos** (27 bawaan + 20 adversarial). `verify.py` seed 20261127: 20.000 ronde, semua assertion lolos.

Catatan kejujuran cakupan: ini review internal oleh agent yang sama yang membangun sistemnya. Ia **bukan** pengganti audit independen sebelum mainnet (lihat §8).

---

## 2. Temuan — Medium

### M-1. Settlement & refund tanpa batas pemain → pot bisa terkunci permanen

- **Di mana:** `settle()` (PlinkoRoyale.sol:575) dan `refund()` (:639) — keduanya loop atas semua pemain dalam satu transaksi; `enter()` (:468) tidak membatasi jumlah pemain.
- **Kenapa penting:** kalau jumlah pemain dalam satu ronde melebihi kapasitas gas satu blok, `settle()` tidak akan pernah bisa dieksekusi. Setelah angka VRF keluar, `refund()` juga diblokir ("word received, settle instead") — jadi tidak ada jalan keluar sama sekali dan pot ronde itu terkunci selamanya. `refund()` punya batas yang sama untuk ronde yang belum di-draw.
- **Bukti (terukur):** tes `testSettleGas1000Players` / `testRefundGas1000Players` (`test/Adversarial.t.sol`):
  - settle: **37.478 gas/pemain** → 1.000 pemain = 37,5 juta gas.
  - refund: **32.236 gas/pemain** → 1.000 pemain = 32,2 juta gas. (Angka "~10k/pemain" di CONTRACT.md §6 terlalu rendah — lihat I-12.)
  - Batas pemain maksimum per ronde: blok 30 jt gas → settle ±800, refund ±930; blok 100,5 jt gas (gasLimit BSC testnet terukur saat audit) → settle ±2.681, refund ±3.117; blok 140 jt (angka mainnet di CONTRACT.md) → settle ±3.735, refund ±4.342.
- **Kemungkinan:** butuh ribuan entri dalam jendela 5 menit — bisa terjadi organik saat game ramai, atau disengaja dengan banyak alamat (penyerang ikut mengunci taruhannya sendiri, tapi tetap bisa mengunci pot semua orang).
- **Saran perbaikan (butuh persetujuan owner, belum diterapkan):** pilihan paling sederhana dan tetap gampang diaudit — batasi pemain per ronde di `enter()` (mis. `MAX_PLAYERS = 500`, jauh di bawah batas gas terendah). Alternatif: settlement bertahap dengan cursor (lebih kompleks). Batas pemain juga otomatis membatasi loop refund.

### M-2. Dua transfer keluar di `settle()` adalah titik macet tunggal bila token berhenti kooperatif

- **Di mana:** `settle()` (:575) — transfer burn ke dead address dan transfer fee ke `feeRecipient` di akhir; kalau salah satu gagal, seluruh settlement rollback dan ronde tidak bisa di-refund (angka sudah keluar).
- **Kenapa penting:** secara desain, ini membuat settlement bergantung pada token yang selalu mau mentransfer ke dua alamat itu. Token yang bisa di-pause, mem-blacklist alamat, atau return false akan mengunci ronde yang sudah dapat angka acak.
- **Bukti:** tes adversarial `testPausedTokenBricksSettleUntilUnpaused`, `testBlockedFeeRecipientBricksSettle`, `testBlockedDeadAddressBricksSettle`, `testFalseTransferRevertsCleanly` — semuanya menunjukkan pola yang sama: settle revert bersih (tidak ada state korup, burn ikut rollback), refund diblokir, dan semuanya pulih begitu token kooperatif lagi.
- **Mitigasi terverifikasi (penting):** dengan **AGC asli yang sekarang terdeploy**, skenario ini tidak bisa terjadi. Source AGC terverifikasi di Sourcify (chain 56): tidak ada fungsi pause, tidak ada blacklist, tidak ada owner/setter; pajak 2% hanya untuk transfer yang melibatkan pair PancakeSwap (`from == pair || to == pair`), sedangkan semua transfer game (pemain→kontrak, kontrak→dead, kontrak→feeRecipient, kontrak→pemain) adalah wallet-ke-wallet dan **tidak kena pajak**. Basisnya OpenZeppelin ERC20 (return bool, revert saat gagal). Jadi risiko residualnya hanya muncul kalau saat deploy mainnet dipakai token lain.
- **Saran perbaikan (opsional, butuh persetujuan owner):** kreditkan burn & fee sebagai saldo internal (pola pull) agar settle tidak bergantung pada dua transfer keluar; atau cukup verifikasi ulang perilaku token sekali lagi tepat sebelum deploy mainnet (sudah ada di checklist CONTRACT.md §9). Untuk AGC saat ini, tidak ada tindakan wajib.

---

## 3. Temuan — Low

### L-1. Frontend memuat ethers.js dari CDN tanpa SRI

- **Di mana:** `frontend/index.html:206` — `<script src="https://cdn.jsdelivr.net/npm/ethers@6.13.4/dist/ethers.umd.min.js">` tanpa atribut `integrity`.
- **Kenapa penting:** halaman ini meminta pengguna menghubungkan wallet. Kalau CDN (atau akun penerbit paket) disusupi, JS jahat bisa mengganti alamat kontrak/tujuan transaksi di halaman yang sama.
- **Bukti:** grep `<script` — satu-satunya script eksternal adalah ethers 6.13.4 dari jsdelivr, tanpa SRI.
- **Saran:** tambahkan hash SRI (`integrity="sha384-…" crossorigin="anonymous"`) atau host file ethers sendiri di deployment yang sama.

### L-2. Tombol Refund aktif sebelum timeout 1 jam (transaksi pasti revert)

- **Di mana:** `frontend/index.html:500-503` — `refundLikely` mengaktifkan tombol saat fase AwaitingRandom dan word belum keluar, tanpa mengecek apakah 1 jam sudah lewat.
- **Kenapa penting:** pengguna bisa mengirim transaksi yang pasti revert ("refund not available yet") dan membuang gas. Hint teksnya sudah benar, tombolnya yang terlalu dini. Akar masalahnya: `roundDetail()` tidak mengekspos `drawRequestedAt`, jadi UI tidak bisa menghitung timeout dari view saja.
- **Saran:** tambahkan `drawRequestedAt` ke `roundDetail()` (perubahan kontrak, sekalian dengan L-6), atau baca timestamp blok event `DrawRequested` di UI.

### L-3. Keeper berupa kontrak tanpa `receive()` tidak bisa draw dengan kelebihan fee

- **Di mana:** `draw()` (PlinkoRoyale.sol:501) — kelebihan fee dikembalikan via `call` dan `require(ok, "fee refund failed")`.
- **Bukti:** tes `testNoReceiveKeeperDraw` — draw dengan fee+1 ether revert; draw dengan fee persis berhasil.
- **Saran:** sudah terdokumentasi di CONTRACT.md §8. Keeper produksi pakai EOA atau kontrak dengan `receive()`; atau kirim fee persis dari `drawFee()`. Tidak perlu perubahan kontrak.

### L-4. `refund()` satu-satunya fungsi state-changing tanpa `nonReentrant`

- **Di mana:** `refund()` (PlinkoRoyale.sol:639) — `enter/draw/settle/withdraw` semua memakai guard (:288), `refund` tidak.
- **Kenapa penting:** saat ini aman — `refund` tidak melakukan external call sama sekali, dan percobaan reentry ke `refund` dari hook token / refund-call di `draw` terbukti gagal oleh cek fase+timeout (tes `testReentrantSettleAndRefundBlocked`). Tapi guard yang seragam adalah asuransi murah terhadap perubahan kode di masa depan.
- **Saran:** tambahkan `nonReentrant` ke `refund()` saat kontrak berikutnya disentuh (butuh persetujuan owner; bukan perbaikan mendesak).

### L-5. Scan event frontend mulai dari blok deploy untuk setiap ronde

- **Di mana:** `frontend/index.html:388-395` — `fetchPlayers()` memulai dari `DEPLOY_BLOCK - 1` untuk ronde yang belum pernah dipindai, per potongan 5.000 blok.
- **Kenapa penting:** jumlah panggilan `eth_getLogs` untuk tampilan pertama satu ronde tumbuh ±38 panggilan per hari umur kontrak (±1.150 panggilan setelah sebulan). RPC publik membatasi ini — terbukti saat audit: RPC data-seed-prebsc menolak `eth_getLogs` bahkan untuk rentang 100 blok (error -32005), sedangkan publicnode melayani. Halaman akan makin lambat/gagal seiring waktu.
- **Saran:** batasi scan ke jendela blok ronde itu sendiri (dari `opensAt`/`closesAt`), dan/atau tambahkan view daftar pemain di kontrak (L-6) sehingga UI tidak bergantung pada log sama sekali.

### L-6. Tidak ada view daftar pemain & `drawRequestedAt` — agent/UI bergantung pada `eth_getLogs`

- **Di mana:** interface kontrak — `roundDetail()` memberi `playerCount` tapi bukan daftar pemain; `entryOf/result` butuh alamat yang sudah diketahui; `drawRequestedAt` tidak diekspos.
- **Bukti:** saat audit, penemuan pemain ronde 5 via event berhasil di RPC publicnode (topic1=roundId, topic2=pemain, data=amount+seed) tetapi **gagal total** di RPC data-seed-prebsc (semua rentang ditolak -32005). Agent yang memakai RPC yang salah tidak bisa menemukan siapa saja yang ikut ronde, padahal itu dibutuhkan untuk verifikasi payout independen dan untuk UI.
- **Saran (perubahan kontrak, butuh persetujuan owner):** tambahkan `playersOf(roundId)` (atau `playerAt(roundId, i)` berpaginasi) dan sertakan `drawRequestedAt` di `roundDetail()`. Keduanya view murni, tidak mengubah logika uang.

---

## 4. Temuan — Info

- **I-1. requestId 0 dari wrapper patologis.** Kalau wrapper mengembalikan requestId 0, callback selalu revert "unknown request" dan angka tidak bisa disimpan — tapi taruhan tetap bisa kembali via refund setelah timeout. Terbukti di `testZeroRequestIdRecovery`. Chainlink tidak pernah mengembalikan 0; tidak perlu tindakan.
- **I-2. Word = 0.** On-chain ditangani benar (flag `wordSet`; `testWordZeroSettles` lolos), tapi frontend menganggap `word == 0` sebagai "belum keluar" (`index.html:460`) sehingga tombol Settle tidak akan aktif pada kejadian berprobabilitas 2^-256 itu. Perbaikan kecil: ekspos `wordSet` atau andalkan fase+event.
- **I-3. `result()`/`entryOf()` mengembalikan slot 0 sebelum settlement.** Slot 0 juga slot asli (11,6×), jadi konsumen harus mengecek fase dulu. Frontend sudah melakukannya; panduan agent (`llms-plinko.txt`) mencatatnya.
- **I-4. Constructor hanya mengecek alamat non-nol.** Deployer yang ceroboh bisa mengisi `feeRecipient` = kontrak game sendiri (fee terjebak selamanya, tidak ada sweep) atau menukar token/wrapper. Mitigasi: checklist deploy + verifikasi `token()`, `feeRecipient()`, `wrapper()` setelah deploy.
- **I-5. Dust menumpuk selamanya** di kontrak (<1 wei-unit per pemain per ronde; teramati 1 wei di ronde 0 dan ronde 5 testnet). Sesuai desain, tidak ada sweep. Nilainya dapat diabaikan.
- **I-6. Celah 1 detik tepat di `closesAt`:** pada timestamp == closesAt, entri ronde lama sudah tutup tetapi `draw()` masih revert ("round still open", butuh strictly greater). Terbukti di `testBoundaryTimestamps`. Tidak berbahaya.
- **I-7. Wrapper immutable:** kalau Chainlink memigrasikan wrapper, draw akan gagal dan ronde-ronde refund; dana aman, game perlu redeploy. Sesuai model kepercayaan "tanpa admin".
- **I-8. `friendlyError` → `innerHTML`.** Teks error fallback dari wallet/RPC disisipkan via `setStatus` (`index.html:298`) tanpa escaping. Semua sink `innerHTML` lain memakai data numerik/alamat hex dari chain. Risiko rendah (sumber error adalah wallet/RPC yang dipilih pengguna sendiri), tapi escaping/`textContent` lebih aman.
- **I-9. Kepercayaan pada satu RPC baca** (publicnode, `index.html:222` area konfigurasi). RPC yang berbohong bisa menyesatkan tampilan, tapi tidak bisa memalsukan transaksi — wallet menandatangani dan kontrak menegakkan aturan. Opsional: daftar RPC cadangan.
- **I-10. Browser in-app MetaMask mobile belum diuji di perangkat asli.** Kode memakai EIP-1193 standar (`eth_chainId`, `wallet_switchEthereumChain`, `wallet_addEthereumChain` dengan penanganan 4902) dan reload saat akun/chain berubah. Perlu uji manual sekali sebelum demo publik.
- **I-11. Jebakan tooling agent (teramati live):** run pertama script agent gagal karena perbandingan integer bash overflow pada allowance uint256 → approve terlewat → `enter` revert bersih "allowance too low", tanpa korupsi state. Pelajaran: agent harus memakai tooling big-int yang benar (cast/ethers/web3), bukan aritmetika shell 64-bit. Bukan bug kontrak.
- **I-12. Tabel gas di CONTRACT.md §6 kurang akurat untuk refund** ("~82k untuk 1 pemain, lalu ~10k/pemain") — terukur 32,2k/pemain. Perbaiki dokumen agar tidak menyesatkan perencanaan keeper.

---

## 5. Area yang diperiksa dan bersih

- **Reentrancy:** `enter/draw/settle/withdraw` memakai guard + checks-effects-interactions. Tes adversarial dengan token ber-hook (gaya ERC777): reentrant withdraw diblokir dan pemain dibayar tepat sekali (`testReentrantWithdrawBlocked`); reentrant settle saat transfer burn diblokir (`testReentrantSettleAndRefundBlocked`); reentrant enter saat `transferFrom` diblokir (`testReentrantEnterBlocked`); reentrant draw dari `receive()` keeper diblokir (tes bawaan `testReentrantDrawBlocked`).
- **Access control VRF:** callback hanya dari wrapper; requestId harus cocok; fulfill ganda revert; requestId palsu revert; word kedua ditolak (`testCallbackOnlyFromWrapper`, `testBogusRequestIdReverts`, `testDoubleFulfillReverts`).
- **State machine:** semua transisi ilegal revert — draw sebelum tutup, settle sebelum word, settle ganda, refund setelah settle, refund setelah word, enter ronde tertutup/masa depan, enter dua kali, tier tidak valid (`testBoundaryTimestamps`, `testRefundTimeoutBoundary`, + tes bawaan).
- **Matematika:** konservasi exact di semua tes; dust < jumlah pemain; tidak ada division-by-zero (multiplier minimum 40 > 0, taruhan > 0, ≥2 pemain untuk settle); overflow tidak terjangkau (checked math Solidity 0.8 + input terbatas tier); payout tidak pernah melebihi pot.
- **Token nakal:** fee-on-transfer ditolak oleh cek delta saldo di `enter` (tes bawaan `testTaxedTransferReverts` + `testLyingTransferFromCaught`); token return-false dan no-return revert bersih tanpa korupsi state (`testFalseTransferRevertsCleanly`, `testNoReturnTokenEnterReverts`).
- **VRF:** quote `drawFee` + refund kelebihan bekerja; callback muat di 100k gas (mock menegakkan exact-gas); word=0 ditangani.
- **Permissionless:** settle/refund oleh pihak ketiga acak berhasil (`testThirdPartySettleAndRefund`); dua ronde berjalan bersamaan settle independen walau urutannya dibalik (`testMultiRoundIndependence`).
- **Frontend — approval:** jumlah persis (`approve(GAME, amount)`, `index.html:636`), **bukan** unlimited. Alur switch/add chain benar. Tidak ada permintaan seed phrase/private key di mana pun (grep bersih; satu-satunya kemunculan kata "private key" adalah komentar yang menyatakan tidak ada). Pemetaan pesan revert mencakup semua string revert kontrak. `draw` mengirim `drawFee + 20%` dan kontrak mengembalikan kelebihan. Flag `busy` mencegah double-submit.
- **Frontend — animasi:** jalur bola dihitung dari word on-chain yang sama dengan kontrak (byte teratas keccak256) dan hanya visual; payout selalu dari `result()`.

### Triase slither (0.11.6, 102 detector, hanya PlinkoRoyale.sol)

12 temuan, **semuanya false positive / benign**:

| Detector | Lokasi | Penilaian |
|---|---|---|
| reentrancy-balance (High) | `enter` | Pola baca-saldo-sebelum/sesudah `transferFrom` memang disengaja (deteksi pajak); fungsi di-guard `nonReentrant`; AGC tidak punya hook. Bukan celah. |
| reentrancy-eth (High) | `draw` | `requestId` ditulis setelah call ke wrapper, tapi fase sudah diubah sebelum call dan fungsi di-guard; callback sinkron pun akan gagal cek requestId dengan aman. Bukan celah. |
| incorrect-equality ×2 (Medium) | `enter` | Kesamaan persis memang disyaratkan (roundId harus ronde aktif; delta saldo harus persis amount). |
| reentrancy-benign (Low) | `draw` | Sama seperti reentrancy-eth di atas. |
| timestamp ×6 (Low) | semua fungsi fase | Sesuai desain; jendela 300 detik / 1 jam jauh lebih besar dari drift validator (detik). |
| low-level-calls (Info) | `draw` | `call` untuk refund kelebihan fee; return value dicek (`require(ok)`); fungsi di-guard. |

---

## 6. Bukti jalur agent — ronde 5 dimainkan tanpa frontend

Script: `testnet/agent-round.sh` (bash + cast, hanya contract call + view). Ronde 5, pot 7.000.000 MockAGC (P1 tier 2jt, P2 tier 5jt):

| Langkah | Tx |
|---|---|
| P1 approve | `0xb60624c3f41d1fe0d449963793eea063fcacc163a0e27581e724bf912618003d` |
| P1 enter 2jt | `0xbfbd5f41ad71ed07353f04d244bd6cdc2e69dc41d73db10be161cac1feebddb7` |
| P2 approve | `0x2ebb39d5adefe860e073afc20e6045d9ca77223c5afc714db0999e2791f30be7` |
| P2 enter 5jt | `0x55fa91b2e3c4e0e687e44506384b5fd8b90078a3473fccae9efdfb696192a3f2` |
| Keeper draw | `0x73473589d60a9dd1e3c54c15a69889d3d1ed9023d705b37be4ca49c6976246db` |
| Keeper settle | `0xfd4e1f8be75c58ecd49035c61f7e2b9b8e0bff24ae8851cf2da8316e24d2e0c5` |
| P1 withdraw | `0xdffb6d145bd3cd6b545e2125a8cccf5847f7ead1b7530a16a49df23f8e66754e` |

Hasil terverifikasi on-chain oleh script (semua PASS): burn 35.000 → dead, fee 35.000 → feeRecipient, dust 1 wei, konservasi exact; P1 slot 2 (1,4×) payout 1.090.112,36; P2 slot 7 (3,0×) payout 5.839.887,64; **slot hasil hitungan lokal dari word publik cocok persis dengan `result()` on-chain untuk kedua pemain**; withdraw P1 berhasil (delta wallet = jumlah withdraw, saldo game 0). Word VRF tiba <10 detik setelah draw.

Catatan jujur: run pertama script gagal di langkah enter karena bug aritmetika bash pada script itu sendiri (I-11) — kontrak menolaknya dengan bersih ("allowance too low"), tidak ada state korup, dan run kedua yang diperbaiki menyelesaikan ronde penuh. Ini bukti tambahan bahwa jalur agent berfungsi, termasuk jalur gagalnya yang aman.

**Kesiapan interface untuk agent:** ronde aktif, pot, fase, fee draw, hasil & saldo sendiri — semua bisa dibaca dari view. Yang **kurang**: daftar pemain per ronde dan `drawRequestedAt` (L-6) — agent harus memakai event `Entered`, dan itu bergantung pada RPC yang melayani `eth_getLogs` (publicnode: bisa; data-seed-prebsc: ditolak total).

---

## 7. Panduan agent

`llms-plinko.txt` ditulis di root proyek, meniru format `llms-arena.txt` milik Battle Royale: alamat (ditandai jelas sebagai testnet), aturan exact, interface lengkap, checklist main langkah-demi-langkah, penanganan kegagalan, dan bagian "Mainnet" yang menandai nilai apa saja yang berubah saat launch (chain, alamat game/token, verifikasi ulang wrapper; aturan/tier/fee/interface tidak berubah karena hard-coded).

---

## 8. Checklist sebelum mainnet (dari temuan di atas)

1. Putuskan M-1: batasi pemain per ronde (disarankan) atau settlement bertahap. [butuh persetujuan owner]
2. Audit independen atas file kontrak final yang sama persis.
3. (Opsional, sekalian) tambahkan `playersOf` + `drawRequestedAt` (L-6), guard di `refund` (L-4). [butuh persetujuan owner]
4. Verifikasi ulang: perilaku token AGC (sudah terverifikasi di audit ini — ulangi sekali tepat sebelum deploy), alamat wrapper VRF mainnet, dan pilih `feeRecipient` permanen dengan hati-hati (immutable).
5. Frontend: SRI/self-host ethers (L-1), perbaiki tombol refund (L-2), batasi scan event (L-5), uji MetaMask mobile sekali (I-10), ganti alamat + hapus tombol faucet MockAGC.
6. Jalankan keeper (draw + settle) dengan wallet yang bisa menerima BNB (L-3).
7. Perbaiki angka gas refund di CONTRACT.md (I-12).

---

## 9. Catatan cakupan (jujur)

Audit ini dilakukan secara internal oleh agent yang sama yang membangun kontrak, frontend, dan deployment testnet-nya — jadi ia tidak independen. Ia mencakup baca manual penuh, 20 tes adversarial baru, slither, fuzz, satu ronde agent live di testnet, dan verifikasi source token AGC. Ia **tidak** mencakup: audit formal/matematis, pengujian beban di mainnet, uji perangkat mobile fisik, review ekonomi/tokenomics AGC, atau penilaian hukum soal game berhadiah. **Laporan ini bukan pengganti audit independen sebelum mainnet.** Tidak ada perubahan yang diterapkan ke kontrak dalam audit ini — semua saran perbaikan menunggu persetujuan owner. File tes yang ditambahkan: `contracts/test/Adversarial.t.sol`. File baru lain: `testnet/agent-round.sh`, `llms-plinko.txt`, laporan ini.

---

## 10. Perbaikan diterapkan (2026-11-26, atas persetujuan owner)

Owner menyetujui opsi A ("Terapkan batas 500 pemain"). Yang diterapkan ke
`contracts/PlinkoRoyale.sol` dan di-deploy ulang ke BSC testnet
(`0x20Aa35C4441F05f5435c812308A6620536B54fa2`, Sourcify exact_match):

- **M-1 — SELESAI.** `MAX_PLAYERS = 500`; entri ke-501 revert "round
  full". Tes baru `testRoundFullAtMaxPlayers`: ronde penuh 500 tetap
  settle satu transaksi, pot pas sampai wei.
- **L-4 — SELESAI.** `refund()` sekarang `nonReentrant`.
- **L-6 — SELESAI (sebagian).** View `playersOf(roundId)` ditambahkan;
  agent/UI tidak lagi bergantung pada `eth_getLogs`. Bagian
  `drawRequestedAt` tidak ditambahkan ke `roundDetail()` (mengubah tuple
  return) — UI masih bisa membaca timestamp event `DrawRequested` bila
  perlu; tersisa sebagai opsi kecil di masa depan.
- Suite Foundry lengkap: **49/49 lolos**. Ronde verifikasi di kontrak
  baru dimainkan via `agent-round.sh` (semua cek PASS; detail di
  `testnet/TESTNET-REPORT.md` § Redeployment).
- Frontend diperbarui (alamat baru, `playersOf`, pesan "ronde penuh");
  redeploy Vercel menunggu persetujuan owner saat catatan ini ditulis.
- M-2 tidak butuh tindakan (sudah terverifikasi di audit). Audit
  independen sebelum mainnet tetap wajib — checklist §8 item 2, 4–6
  masih berlaku.

---

## 11. Audit eksternal (Gemini) & tindak lanjut — 2026-11-26

Audit independen oleh model lain (Gemini; ringkasan di
`EXTERNAL-AUDIT-GEMINI.md`): **Critical 0, High 0, Medium 2, Low 6,
Info 2** — kontrak inti dinyatakan aman; verdict "belum siap mainnet"
karena frontend/keeper/konfigurasi. Auditor memverifikasi ulang M-1
(cap 500: settle ~18,75jt gas) dan M-2 (transfer push aman untuk AGC
asli) secara independen.

Semua temuan ditindaklanjuti pada hari yang sama atas perintah owner:

- **MEDIUM-1 (badai RPC frontend)** — SELESAI: `entryOf` via
  Multicall3 (satu eth_call), hasil ronde settled dihitung lokal.
- **MEDIUM-2 (keeper)** — SELESAI: scan 21 ronde terakhir, gas price
  dinamis, refund persis via `drawRequestedAtOf`.
- **LOW-1 (batas 1 detik roundDetail)** — SELESAI: `>=` closesAt;
  kontrak di-deploy ulang ke `0x8643ab8Fe68aBC315aC7D38b5518e6cc3644F0a7`
  (51/51 tes lolos; detail di `testnet/TESTNET-REPORT.md`).
- **LOW-2..6 + INFO-1 (frontend)** — SELESAI: gasPrice eksplisit +
  buffer 150% untuk draw, SRI ethers, escape HTML pesan error,
  snapshot animasi + gate `wordReceivedOf`, gate refund persis,
  `provider.destroy()` + `staticNetwork`.
- **INFO-2 (dokumentasi)** — SELESAI: DESIGN.md (sumber stake,
  `result()` 3-tuple, event Entered tanpa flag agent), CONTRACT.md
  (51 tes), NatSpec gas, alamat di semua file disinkronkan.
- **L-6 (audit internal, sisa)** — SELESAI: `drawRequestedAtOf` view
  ditambahkan (tanpa mengubah tuple `roundDetail`).

Sisa sebelum mainnet: checklist §8 item 2, 4–6 (audit independen
formal tetap disarankan; audit model lain ini bersifat statis),
feeRecipient permanen, dan migrasi konfigurasi testnet→mainnet.
