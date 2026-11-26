# Plinko Royale — Stress Test 5 Bot (BSC Testnet)

Kontrak: 0x66d8e0d61f3b89d1962bfef0cd19be767a2a3d49 · Mulai: 2026-11-26 12:45:32 WIB

Bot: player1=0x882A3B…, player2=0x66f82b…, player3=0x89C412…, player4=0x763CB2…, player5=0x1f94F4…
approve player2: ok
fund player3 0.02 tBNB: ok
mint 100jt AGC test untuk player3: ok
approve player3: ok
fund player4 0.02 tBNB: ok
mint 100jt AGC test untuk player4: ok
approve player4: ok
fund player5 0.02 tBNB: ok
mint 100jt AGC test untuk player5: ok
approve player5: ok

## Ronde A (campuran) — ronde #12 (tutup dalam 126s)
enter player1 2jt: ok
enter player2 2jt: ok
enter player3 5jt: ok
enter player4 5jt: ok
enter player5 10jt: ok
draw: 0x8ec2b6c6eb5affa7a5310b23bde3e8565587c59051d6275a03ce7754d32b3818
PASS Ronde A (campuran): VRF word datang
settle: 0x996b569ad6f1e69d4b8854409e391b3e08ac0c2ed1e0835a83d64e2e88204627
PASS Ronde A (campuran): phase settled (3)
PASS Ronde A (campuran): burn == 0,3% pot (72,000)
PASS Ronde A (campuran): fee == 0,3% pot (72,000)
PASS Ronde A (campuran): slot player1 cocok hitung ulang (3)
PASS Ronde A (campuran): payout player1 cocok rumus (1,403,294.12)
PASS Ronde A (campuran): delta saldo game player1 == payout
  player1: stake 2,000,000 slot 3 (0.7×) payout 1,403,294.12
PASS Ronde A (campuran): slot player2 cocok hitung ulang (5)
PASS Ronde A (campuran): payout player2 cocok rumus (1,403,294.12)
PASS Ronde A (campuran): delta saldo game player2 == payout
  player2: stake 2,000,000 slot 5 (0.7×) payout 1,403,294.12
PASS Ronde A (campuran): slot player3 cocok hitung ulang (6)
PASS Ronde A (campuran): payout player3 cocok rumus (7,016,470.59)
PASS Ronde A (campuran): delta saldo game player3 == payout
  player3: stake 5,000,000 slot 6 (1.4×) payout 7,016,470.59
PASS Ronde A (campuran): slot player4 cocok hitung ulang (6)
PASS Ronde A (campuran): payout player4 cocok rumus (7,016,470.59)
PASS Ronde A (campuran): delta saldo game player4 == payout
  player4: stake 5,000,000 slot 6 (1.4×) payout 7,016,470.59
PASS Ronde A (campuran): slot player5 cocok hitung ulang (3)
PASS Ronde A (campuran): payout player5 cocok rumus (7,016,470.59)
PASS Ronde A (campuran): delta saldo game player5 == payout
  player5: stake 10,000,000 slot 3 (0.7×) payout 7,016,470.59
PASS Ronde A (campuran): conservation payout+burn+fee+dust == pot
PASS Ronde A (campuran): dust < jumlah pemain (4 wei)
PASS Ronde A (campuran): delta dead == burn
PASS Ronde A (campuran): delta feeRecipient == fee

## Ronde B (campuran) — ronde #13 (tutup dalam 263s)
enter player1 10jt: ok
enter player2 10jt: ok
enter player3 2jt: ok
enter player4 5jt: ok
enter player5 2jt: ok
draw: 0xbad12dd4a0c47decd0d5bfbb005b60f8fb194b1c5114b99bfe4d19203286b452
PASS Ronde B (campuran): VRF word datang
settle: 0x13564ebae473377dd5e718bbb2731012759b7ec800d658a8085502c4446d4273
PASS Ronde B (campuran): phase settled (3)
PASS Ronde B (campuran): burn == 0,3% pot (87,000)
PASS Ronde B (campuran): fee == 0,3% pot (87,000)
PASS Ronde B (campuran): slot player1 cocok hitung ulang (3)
PASS Ronde B (campuran): payout player1 cocok rumus (12,082,754.49)
PASS Ronde B (campuran): delta saldo game player1 == payout
  player1: stake 10,000,000 slot 3 (0.7×) payout 12,082,754.49
PASS Ronde B (campuran): slot player2 cocok hitung ulang (4)
PASS Ronde B (campuran): payout player2 cocok rumus (6,904,431.14)
PASS Ronde B (campuran): delta saldo game player2 == payout
  player2: stake 10,000,000 slot 4 (0.4×) payout 6,904,431.14
PASS Ronde B (campuran): slot player3 cocok hitung ulang (4)
PASS Ronde B (campuran): payout player3 cocok rumus (1,380,886.23)
PASS Ronde B (campuran): delta saldo game player3 == payout
  player3: stake 2,000,000 slot 4 (0.4×) payout 1,380,886.23
PASS Ronde B (campuran): slot player4 cocok hitung ulang (5)
PASS Ronde B (campuran): payout player4 cocok rumus (6,041,377.25)
PASS Ronde B (campuran): delta saldo game player4 == payout
  player4: stake 5,000,000 slot 5 (0.7×) payout 6,041,377.25
PASS Ronde B (campuran): slot player5 cocok hitung ulang (3)
PASS Ronde B (campuran): payout player5 cocok rumus (2,416,550.90)
PASS Ronde B (campuran): delta saldo game player5 == payout
  player5: stake 2,000,000 slot 3 (0.7×) payout 2,416,550.90
PASS Ronde B (campuran): conservation payout+burn+fee+dust == pot
PASS Ronde B (campuran): dust < jumlah pemain (3 wei)
PASS Ronde B (campuran): delta dead == burn
PASS Ronde B (campuran): delta feeRecipient == fee

## Uji withdraw
withdraw player2 16,176,891.92: ok
PASS withdraw: saldo game 0, wallet bertambah persis

## Ronde C (semua 5jt) — ronde #14 (tutup dalam 255s)
enter player1 5jt: ok
enter player2 5jt: ok
enter player3 5jt: ok
enter player4 5jt: ok
enter player5 5jt: ok
draw: 0x8a3444f2f94926c956310f36aaa6dcd330bb404ac08feffa69e97a11da630c57
PASS Ronde C (semua 5jt): VRF word datang
settle: 0x87517b55c2009f96330cb30d2dc43d804496708d203646000d070da2f56bcbff
PASS Ronde C (semua 5jt): phase settled (3)
PASS Ronde C (semua 5jt): burn == 0,3% pot (75,000)
PASS Ronde C (semua 5jt): fee == 0,3% pot (75,000)
PASS Ronde C (semua 5jt): slot player1 cocok hitung ulang (5)
PASS Ronde C (semua 5jt): payout player1 cocok rumus (3,550,000.00)
PASS Ronde C (semua 5jt): delta saldo game player1 == payout
  player1: stake 5,000,000 slot 5 (0.7×) payout 3,550,000.00
PASS Ronde C (semua 5jt): slot player2 cocok hitung ulang (3)
PASS Ronde C (semua 5jt): payout player2 cocok rumus (3,550,000.00)
PASS Ronde C (semua 5jt): delta saldo game player2 == payout
  player2: stake 5,000,000 slot 3 (0.7×) payout 3,550,000.00
PASS Ronde C (semua 5jt): slot player3 cocok hitung ulang (2)
PASS Ronde C (semua 5jt): payout player3 cocok rumus (7,100,000.00)
PASS Ronde C (semua 5jt): delta saldo game player3 == payout
  player3: stake 5,000,000 slot 2 (1.4×) payout 7,100,000.00
PASS Ronde C (semua 5jt): slot player4 cocok hitung ulang (5)
PASS Ronde C (semua 5jt): payout player4 cocok rumus (3,550,000.00)
PASS Ronde C (semua 5jt): delta saldo game player4 == payout
  player4: stake 5,000,000 slot 5 (0.7×) payout 3,550,000.00
PASS Ronde C (semua 5jt): slot player5 cocok hitung ulang (2)
PASS Ronde C (semua 5jt): payout player5 cocok rumus (7,100,000.00)
PASS Ronde C (semua 5jt): delta saldo game player5 == payout
  player5: stake 5,000,000 slot 2 (1.4×) payout 7,100,000.00
PASS Ronde C (semua 5jt): conservation payout+burn+fee+dust == pot
PASS Ronde C (semua 5jt): dust < jumlah pemain (0 wei)
PASS Ronde C (semua 5jt): delta dead == burn
PASS Ronde C (semua 5jt): delta feeRecipient == fee

## Ronde D (campuran + double-enter) — ronde #15 (tutup dalam 259s)
enter player1 2jt: ok
PASS Ronde D (campuran + double-enter): double-enter player1 revert
enter player2 10jt: ok
enter player3 10jt: ok
enter player4 10jt: ok
enter player5 2jt: ok
draw: 0xfba818c8f11d9acfeba8da6ccd2f8f3ac4ea1b7c55bc8a19e116a1208187cbc6
PASS Ronde D (campuran + double-enter): VRF word datang
settle: 0x8087c9d7c1a4bcb36ba566d358ef3f624b0b98bcfd535c3a0faa994b148166e2
PASS Ronde D (campuran + double-enter): phase settled (3)
PASS Ronde D (campuran + double-enter): burn == 0,3% pot (102,000)
PASS Ronde D (campuran + double-enter): fee == 0,3% pot (102,000)
PASS Ronde D (campuran + double-enter): slot player1 cocok hitung ulang (5)
PASS Ronde D (campuran + double-enter): payout player1 cocok rumus (1,701,956.83)
PASS Ronde D (campuran + double-enter): delta saldo game player1 == payout
  player1: stake 2,000,000 slot 5 (0.7×) payout 1,701,956.83
PASS Ronde D (campuran + double-enter): slot player2 cocok hitung ulang (4)
PASS Ronde D (campuran + double-enter): payout player2 cocok rumus (4,862,733.81)
PASS Ronde D (campuran + double-enter): delta saldo game player2 == payout
  player2: stake 10,000,000 slot 4 (0.4×) payout 4,862,733.81
PASS Ronde D (campuran + double-enter): slot player3 cocok hitung ulang (5)
PASS Ronde D (campuran + double-enter): payout player3 cocok rumus (8,509,784.17)
PASS Ronde D (campuran + double-enter): delta saldo game player3 == payout
  player3: stake 10,000,000 slot 5 (0.7×) payout 8,509,784.17
PASS Ronde D (campuran + double-enter): slot player4 cocok hitung ulang (6)
PASS Ronde D (campuran + double-enter): payout player4 cocok rumus (17,019,568.35)
PASS Ronde D (campuran + double-enter): delta saldo game player4 == payout
  player4: stake 10,000,000 slot 6 (1.4×) payout 17,019,568.35
PASS Ronde D (campuran + double-enter): slot player5 cocok hitung ulang (3)
PASS Ronde D (campuran + double-enter): payout player5 cocok rumus (1,701,956.83)
PASS Ronde D (campuran + double-enter): delta saldo game player5 == payout
  player5: stake 2,000,000 slot 3 (0.7×) payout 1,701,956.83
PASS Ronde D (campuran + double-enter): conservation payout+burn+fee+dust == pot
PASS Ronde D (campuran + double-enter): dust < jumlah pemain (2 wei)
PASS Ronde D (campuran + double-enter): delta dead == burn
PASS Ronde D (campuran + double-enter): delta feeRecipient == fee

## Uji refund 1 pemain — ronde #16
enter player1 5jt (sendirian): ok
refund: 0xd008f451e58ea5548934f7ad366c8a917e550cabfae48b8949e2ed655231d554
PASS refund: phase refunded (4)
PASS refund: burn & fee 0
PASS refund: stake kembali penuh ke saldo game

## Kesimpulan
SEMUA CEK LOLOS — 4 ronde settle 5 pemain + refund + withdraw + double-enter.
Selesai: 2026-11-26 13:08:37 WIB
