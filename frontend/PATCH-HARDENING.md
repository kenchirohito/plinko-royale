# Frontend hardening patch — siap terapkan saat redeploy Vercel

Sumber: `AUDIT-REPORT.md` §8 item 5 (L-1, L-2, I-8). File ini **belum**
diterapkan ke `index.html` — terapkan bersamaan dengan redeploy kontrak
baru `0x20Aa35C4441F05f5435c812308A6620536B54fa2` supaya cukup satu approval
Vercel. Nomor baris mengacu ke `index.html` saat patch ini ditulis
(26 Nov 2026); verifikasi ulang sebelum menerapkan.

## L-1 — ethers dari CDN tanpa SRI (baris 206)

Sekarang:

```html
<script src="https://cdn.jsdelivr.net/npm/ethers@6.13.4/dist/ethers.umd.min.js"></script>
```

Pilihan A (disarankan untuk demo publik): **self-host** file ethers di
deployment yang sama (unduh `ethers.umd.min.js` v6.13.4 sekali, deploy
sebagai file kedua `ethers.umd.min.js`, ganti `src` jadi `./ethers.umd.min.js`).
Tidak ada lagi kepercayaan ke CDN saat halaman meminta connect wallet.

Pilihan B (tetap CDN + SRI): hitung hash dari file yang benar-benar
diunduh **saat deploy** — jangan menyalin hash dari dokumen ini atau dari
internet tanpa verifikasi:

```bash
curl -sL https://cdn.jsdelivr.net/npm/ethers@6.13.4/dist/ethers.umd.min.js -o /tmp/ethers.umd.min.js
openssl dgst -sha384 -binary /tmp/ethers.umd.min.js | openssl base64 -A
# lalu: <script src="...ethers.umd.min.js" integrity="sha384-<hasil>" crossorigin="anonymous"></script>
```

## L-2 — tombol Refund aktif sebelum timeout 1 jam (baris 498–501)

Sekarang `refundLikely` mengaktifkan tombol saat fase AwaitingRandom dan
word belum keluar, tanpa mengecek 1 jam — klik akan revert
("refund not available yet") dan membuang gas. `roundDetail()` tidak
mengekspos `drawRequestedAt` (audit L-6), jadi UI harus membaca timestamp
event `DrawRequested`:

```js
// Tambahkan state: let drawAt = null; // timestamp blok DrawRequested ronde tampil
// Di refreshAll(), setelah lastDetail dimuat dan phase === 2:
//   const evs = await gameRead.queryFilter(gameRead.filters.DrawRequested(viewRoundId));
//   drawAt = evs.length ? (await evs[evs.length-1].getBlock()).timestamp : null;
// Ganti refundLikely menjadi:
const refundLikely =
  (phase === 1 && (d.playerCount < 2 || now > d.closesAt + 3600)) ||
  (phase === 2 && !wordArrived && drawAt !== null && now > drawAt + 3600);
```

Catatan: `queryFilter` bergantung pada RPC yang melayani `eth_getLogs`
(publicnode bisa; data-seed-prebsc menolak — lihat audit L-5/L-6). Bila
event tidak terbaca, tombol tetap nonaktif dan hint teks yang sudah benar
("Refund baru bisa setelah 1 jam") tetap tampil — gagal aman, bukan
gagal boros gas. Alternatif jangka panjang: tambahkan `drawRequestedAt`
ke `roundDetail()` di kontrak (mengubah tuple return; butuh redeploy +
persetujuan owner terpisah).

## I-8 — teks error masuk lewat innerHTML (baris 299–302)

`setStatus` menyisipkan `msg` via `innerHTML`; pesan sukses memang butuh
link `<a>` (tx hash dari chain, aman), tapi fallback error dari
wallet/RPC (`friendlyError`) tidak di-escape. Perbaikan minimal: escape
hanya jalur error, biarkan jalur sukses apa adanya:

```js
function esc(s) {
  return String(s).replace(/[&<>"']/g, c => ({"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;","'":"&#39;"}[c]));
}
// Di semua pemanggilan error: setStatus(el, esc(friendlyError(e)), "err")
// dan: "Gagal membaca data chain: " + esc(friendlyError(e))
```

Risiko saat ini rendah (sumber error adalah wallet/RPC pilihan pengguna
sendiri), tapi escaping ini murah dan menutup sink-nya.

## Yang TIDAK diubah patch ini

- Alamat kontrak/token, ABI, logika enter/draw/settle/withdraw, animasi.
- Approval token tetap jumlah persis (bukan unlimited) — sudah benar.
- Setelah patch: jalankan `node --check` pada blok `<script>` yang
  diekstrak, muat halaman lokal sekali (mode baca tanpa wallet), baru
  deploy ke Vercel.
