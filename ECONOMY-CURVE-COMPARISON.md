# Plinko Royale — Perbandingan Kurva Ekonomi (27 Nov 2026)

Dokumen riset saja. **Kontrak testnet TIDAK diubah** (`0x5133d3a7b0AAb6dFb3c40b824741FA4A776Bc3EF`
masih pakai kurva A). Fee tetap 0,3% burn + 0,3% operasional (total 0,6%, RTP 99,4%)
di semua opsi. Yang beda cuma bentuk kurva multiplier-nya.

Pertanyaan bos 27 Nov: fokus ekonomi dulu biar terasa rewarding; tax 0,3% sudah cukup;
khawatir RTP 99% bikin win kecil, lebih kecil dari Battle Royale (BR).

## Inti yang perlu dipahami (bahasa simpel)

RTP 99,4% cuma rata-rata. Rasa "rewarding" ditentukan **seberapa sering** lo pulang
di atas stake, dan **seberapa sakit** kalau kalah. Itu ditentukan kurva, bukan RTP.

Penting: melandaikan kurva biasa (min naik, max turun) **tidak** bikin lebih sering
menang. Frekuensi menang baru naik kalau slot yang peluangnya besar (slot 3 dan 5,
masing-masing 21,9%) multiplier-nya di atas 1,0. Di kurva sekarang slot itu 0,7 —
jadi 71% bola jatuh ke slot di bawah 1,0.

## Tiga kurva yang dibandingkan

Semua EV-nya persis 1,0 sebelum fee (Σ C(8,k)·M = 25.600, terverifikasi di
`economy_curve_sim.py`), semua min > 0 (denominator settle tidak bisa nol),
jadi keamanan kontrak tidak berubah. Angka ×100 di kontrak:

| Kurva | Slot pinggir → tengah | Karakter |
|---|---|---|
| **A — sekarang (jackpot)** | 11,6 / 3,0 / 1,4 / 0,7 / **0,4** | Jarang menang, sekali menang meledak |
| **B — landai sedang** | 6,0 / 2,3 / 1,25 / 0,85 / **0,6** | Kalah tidak sesakit A, jackpot setengah A |
| **C — sering profit** | 3,3 / 1,5 / 1,3 / **1,05** / 0,5 | Mirip rasa BR: sering menang kecil, tengah tetap sakit |

Simulasi: 20.000 ronde per kurva, stake semua pemain sama, rumus payout asli
kontrak (pool 99,4% dibagi proporsional ke skor), seed 20261127.
Reproduksi: `python3 economy_curve_sim.py`.

## Hasil simulasi — ronde 50 pemain (paling dekat ke "rata-rata")

| Ukuran (per pemain) | A sekarang | B landai | C sering profit | BR (80 pemain, 10/room) |
|---|---:|---:|---:|---:|
| Rata-rata balik | 0,994× | 0,994× | 0,994× | 0,994× |
| **Median balik** (pemain tengah) | **0,73×** | 0,86× | **1,05×** | 1,14× (yang selamat) |
| **% ronde profit** (balik > stake) | 28,6% | 29,2% | **63,6%** | 87,5% |
| % balik ≥ 0,9× stake | 30,4% | 40,3% | 72,6% | 87,5% |
| % balik < 0,5× (kalah separuh+) | 26,2% | 0,6% | 12,5% | 12,5% (hangus 0) |
| % balik > 2× | 7,0% | 6,4% | 0,8% | 0% (room seimbang) |
| % balik > 5× | 0,78% | 0,67% | 0% | 0% |
| Max teramati | 12,96× | 6,60× | 3,74× | 1,14× |

Ronde 10 pemain polanya sama: profit A 33,3% / B 35,8% / C 57,3%;
median A 0,78× / B 0,89× / C 1,04×; kalah <0,5× A 20,2% / B 2,8% / C 8,7%.

## Contoh konkret — stake 100.000 AGC (stake BR bos hari ini)

Di ronde besar (rata-rata multiplier ronde ≈ 1), balik ≈ 99.400 × multiplier slot:

| Slot | Peluang | A sekarang | B landai | C sering profit |
|---|---:|---:|---:|---:|
| Pinggir (0/8) | 0,78% | 1.153.040 | 596.400 | 328.020 |
| 1/7 | 6,25% | 298.200 | 228.620 | 149.100 |
| 2/6 | 21,88% | 139.160 | 124.250 | 129.220 |
| 3/5 | 43,75% | 69.580 | 84.490 | **104.370** |
| Tengah (4) | 27,34% | 39.760 | 59.640 | 49.700 |

Contoh ronde kecil 10 pemain × 1.000.000, 1 orang kena pinggir + 9 kena tengah:
A pinggir 7.585.789 / tengah 261.579 · B pinggir 5.231.579 / tengah 523.158 ·
C pinggir 4.205.385 / tengah 637.179. Kalau semua kena slot sama, semua kurva
sama: tiap orang balik 994.000.

## Kesimpulan jujur

- **B tidak menjawab keluhan "win kecil / jarang menang"** — frekuensi profitnya
  hampir sama dengan A (29% vs 29% di ronde 50). B cuma bikin kalahnya lebih
  ringan (kalah separuh+ turun dari 26% ke 0,6%) dan jackpotnya lebih kecil.
- **C yang benar-benar mengubah rasa main**: median pemain pulang profit
  (1,05×), 64% ronde profit — paling dekat ke rasa BR (87,5% menang +13,6%),
  tapi tanpa hangus total: yang apes di tengah balik ~0,5×, bukan 0.
  Harga yang dibayar: momen jackpot hilang (max ~3,7×, >2× cuma 0,8%).
- **A tetap paling "slot machine"**: 71% bola di bawah 1,0, tapi 0,78% ronde
  tembus >5× — itu bahan leaderboard/viral, bukan bahan rasa menang rutin.
- Di semua kurva, yang diuntungkan jangka panjang tetap holder yang tidak main
  (burn 0,3% jalan terus) dan fee operasional 0,3% — sama seperti BR.

## Konsekuensi kalau ganti kurva

Multiplier itu konstanta hardcoded di kontrak (`multipliersX100()`), tidak ada
setter. Ganti kurva = **deploy kontrak testnet baru** (alamat berubah) + update
frontend/keeper/llms/docs + tes ulang + ronde verifikasi + push GitHub —
persis pola redeploy 26 Nov. Proposal PDF tetap tidak disentuh sampai bos
perintahkan. Keputusan karakter game (A/B/C) di bos; tidak ada yang dieksekusi
dari dokumen ini.

File terkait: `DESIGN.md` §1/§3 (kurva A + rumus), `verify.py` (konservasi),
`contracts/PlinkoRoyale.sol` (`multipliersX100`), `economy_curve_sim.py` (simulasi ini).

## Keputusan bos (27 Nov 2026)

Bos memilih **tetap kurva A (jackpot)** — "Tetap jackpot A" (27 Nov 2026,
19:04 WIB). Jadi tidak ada perubahan kontrak: kurva A yang sudah live di
testnet `0x5133…c3EF` adalah kurva final untuk sekarang. Opsi B/C di atas
tinggal sebagai bahan perbandingan; tidak dieksekusi.
