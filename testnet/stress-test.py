#!/usr/bin/env python3
"""Plinko Royale — stress test 5 bot di BSC testnet (chain 97).

Memainkan beberapa ronde penuh dengan 5 wallet test (tier 2jt/5jt/10jt),
memverifikasi on-chain: conservation, burn/fee 0,3%, slot hasil hitung
ulang lokal, payout hasil hitung ulang lokal, delta saldo dead/feeRecipient,
plus uji refund 1 pemain, double-enter (harus revert), dan withdraw.

TESTNET ONLY. Key dibaca dari testnet/keys/, tidak pernah dicetak.
Laporan ditulis ke testnet/STRESS-REPORT.md.
"""
import json, re, subprocess, time, sys

RPC = 'https://data-seed-prebsc-1-s1.bnbchain.org:8545'
GAME = '0x8643ab8Fe68aBC315aC7D38b5518e6cc3644F0a7'
TOKEN = '0x17356908F432eD7F2a4b378F19b5c869b872e21E'
DEAD = '0x000000000000000000000000000000000000dEaD'
FEERECIP = '0x627Ce1AEda3f4B8f2f63E6051Ddd1304fc533c87'
CAST = '/home/hatch/.foundry/bin/cast'
LEGACY = ['--legacy', '--gas-price', '100000000', '--rpc-url', RPC]
MULT = [1160, 300, 140, 70, 40, 70, 140, 300, 1160]  # x100
REPORT = 'testnet/STRESS-REPORT.md'

def run(args, timeout=180):
    return subprocess.run(args, capture_output=True, text=True, timeout=timeout)

def num(s):
    return int(s.strip().split()[0])

def key_of(name):
    return re.search(r'0x[0-9a-fA-F]{64}', open(f'testnet/keys/{name}.txt').read()).group(0)

def addr_of(key):
    return run([CAST, 'wallet', 'address', '--private-key', key]).stdout.strip()

def call(sig, *args):
    return run([CAST, 'call', GAME, sig, *[str(a) for a in args], '--rpc-url', RPC]).stdout

def token_call(sig, *args):
    return run([CAST, 'call', TOKEN, sig, *[str(a) for a in args], '--rpc-url', RPC]).stdout

def send(key, to, sig, *args, value=None):
    cmd = [CAST, 'send', '--json', *LEGACY, '--private-key', key]
    if value is not None:
        cmd += ['--value', str(value)]
    cmd += [to, sig, *[str(a) for a in args]]
    r = run(cmd)
    if r.returncode != 0:
        return None, (r.stdout + r.stderr)[:300]
    d = json.loads(r.stdout)
    return d, None

def current_round():
    ls = call('currentRound()(uint256,uint64,uint64)').strip().split('\n')
    return num(ls[0]), num(ls[1]), num(ls[2])

def slot_recompute(word, rid, player, seed):
    enc = run([CAST, 'abi-encode', 'f(uint256,uint256,address,bytes32)', str(word), str(rid), player, seed]).stdout.strip()
    h = run([CAST, 'keccak', enc]).stdout.strip()
    top = int(h[2:4], 16)
    return bin(top).count('1')

def log(msg):
    print(msg, flush=True)
    with open(REPORT, 'a') as f:
        f.write(msg + '\n')

fails = []
def check(cond, label):
    log(('PASS ' if cond else 'FAIL ') + label)
    if not cond:
        fails.append(label)
    return cond

with open(REPORT, 'w') as f:
    f.write('# Plinko Royale — Stress Test 5 Bot (BSC Testnet)\n\n')
    f.write(f'Kontrak: {GAME} · Mulai: {time.strftime("%Y-%m-%d %H:%M:%S")} WIB\n\n')

bots = []
for name in ['player1', 'player2', 'player3', 'player4', 'player5']:
    k = key_of(name)
    bots.append({'name': name, 'key': k, 'addr': addr_of(k)})
dk = key_of('deployer')
log('Bot: ' + ', '.join(f"{b['name']}={b['addr'][:8]}…" for b in bots))

# --- Persiapan: danai tBNB + mint AGC test + approve -----------------------
for b in bots:
    bal = num(run([CAST, 'balance', b['addr'], '--rpc-url', RPC]).stdout)
    if bal < 10**16:  # < 0.01 tBNB
        d, err = send(dk, b['addr'], '', value=2 * 10**16) if False else (None, None)
        r = run([CAST, 'send', '--json', *LEGACY, '--private-key', dk, '--value', str(2 * 10**16), b['addr']])
        log(f"fund {b['name']} 0.02 tBNB: {'ok' if r.returncode == 0 else 'GAGAL ' + r.stderr[:150]}")
    tb = num(token_call('balanceOf(address)(uint256)', b['addr']))
    if tb < 50_000_000 * 10**18:
        d, err = send(b['key'], TOKEN, 'mint(address,uint256)', b['addr'], 100_000_000 * 10**18)
        log(f"mint 100jt AGC test untuk {b['name']}: {'ok' if d and d.get('status') == '0x1' else 'GAGAL ' + str(err)}")
    allow = num(token_call('allowance(address,address)(uint256)', b['addr'], GAME))
    if allow < 10**27:
        d, err = send(b['key'], TOKEN, 'approve(address,uint256)', GAME, 10**27)
        log(f"approve {b['name']}: {'ok' if d and d.get('status') == '0x1' else 'GAGAL ' + str(err)}")

def play_round(tiers_m, label, double_enter_bot=None):
    rid, opens, closes = current_round()
    if closes - int(time.time()) < 100:
        log(f'[{label}] ronde {rid} mepet, tunggu ronde berikutnya…')
        while int(time.time()) < closes + 2:
            time.sleep(5)
        rid, opens, closes = current_round()
    log(f'\n## {label} — ronde #{rid} (tutup dalam {closes - int(time.time())}s)')
    dead_before = num(token_call('balanceOf(address)(uint256)', DEAD))
    fee_before = num(token_call('balanceOf(address)(uint256)', FEERECIP))
    gb_before = {b['addr']: num(call('balanceOf(address)(uint256)', b['addr'])) for b in bots}

    seeds = {}
    for i, (b, tier) in enumerate(zip(bots, tiers_m)):
        seed = '0x' + '00' * 30 + f'{rid:02x}{i:02x}'
        seeds[b['addr']] = seed
        d, err = send(b['key'], GAME, 'enter(uint256,uint256,bytes32)', rid, tier * 1_000_000 * 10**18, seed)
        ok = d and d.get('status') == '0x1'
        log(f"enter {b['name']} {tier}jt: {'ok' if ok else 'GAGAL ' + str(err)}")
        if not ok:
            fails.append(f'{label} enter {b["name"]}')
        if double_enter_bot == i:
            d2, err2 = send(b['key'], GAME, 'enter(uint256,uint256,bytes32)', rid, tier * 1_000_000 * 10**18, seed)
            reverted = (d2 is None) or (d2.get('status') != '0x1')
            check(reverted, f'{label}: double-enter {b["name"]} revert')

    while int(time.time()) < closes + 3:
        time.sleep(5)
    fee = num(call('drawFee(uint256)(uint256)', 100000000))
    d, err = send(dk, GAME, 'draw(uint256)', rid, value=fee * 2)
    log(f"draw: {d.get('transactionHash') if d else 'GAGAL ' + str(err)}")
    word = 0
    for _ in range(40):
        word = num(call('randomWordOf(uint256)(uint256)', rid))
        if word:
            break
        time.sleep(10)
    check(word != 0, f'{label}: VRF word datang')
    d, err = send(dk, GAME, 'settle(uint256)', rid)
    log(f"settle: {d.get('transactionHash') if d else 'GAGAL ' + str(err)}")

    det = call('roundDetail(uint256)(uint8,uint64,uint64,uint256,uint256,uint256,uint256,uint256,uint256)', rid).strip().split('\n')
    phase, pot, burned, fee_paid, dust = num(det[0]), num(det[3]), num(det[6]), num(det[7]), num(det[8])
    check(phase == 3, f'{label}: phase settled (3)')
    exp_burn = pot * 30 // 10000
    check(burned == exp_burn, f'{label}: burn == 0,3% pot ({burned/1e18:,.0f})')
    check(fee_paid == exp_burn, f'{label}: fee == 0,3% pot ({fee_paid/1e18:,.0f})')

    rows = []
    for b in bots:
        res = call('result(uint256,address)(uint256,uint256,uint8)', rid, b['addr']).strip().split('\n')
        rows.append({'bot': b, 'stake': num(res[0]), 'payout': num(res[1]), 'slot': num(res[2])})

    total_score = sum(r['stake'] * MULT[r['slot']] for r in rows)
    pool = pot - burned - fee_paid
    sum_pay = 0
    for r in rows:
        exp_slot = slot_recompute(word, rid, r['bot']['addr'], seeds[r['bot']['addr']])
        check(exp_slot == r['slot'], f"{label}: slot {r['bot']['name']} cocok hitung ulang ({r['slot']})")
        exp_pay = pool * (r['stake'] * MULT[r['slot']]) // total_score
        check(exp_pay == r['payout'], f"{label}: payout {r['bot']['name']} cocok rumus ({r['payout']/1e18:,.2f})")
        sum_pay += r['payout']
        gb_after = num(call('balanceOf(address)(uint256)', r['bot']['addr']))
        check(gb_after - gb_before[r['bot']['addr']] == r['payout'], f"{label}: delta saldo game {r['bot']['name']} == payout")
        log(f"  {r['bot']['name']}: stake {r['stake']/1e18:,.0f} slot {r['slot']} ({MULT[r['slot']]/100}×) payout {r['payout']/1e18:,.2f}")
    check(sum_pay + burned + fee_paid + dust == pot, f'{label}: conservation payout+burn+fee+dust == pot')
    check(dust < len(rows), f'{label}: dust < jumlah pemain ({dust} wei)')
    dead_after = num(token_call('balanceOf(address)(uint256)', DEAD))
    fee_after = num(token_call('balanceOf(address)(uint256)', FEERECIP))
    check(dead_after - dead_before == burned, f'{label}: delta dead == burn')
    check(fee_after - fee_before == fee_paid, f'{label}: delta feeRecipient == fee')
    return rid

def refund_round():
    rid, opens, closes = current_round()
    if closes - int(time.time()) < 100:
        while int(time.time()) < closes + 2:
            time.sleep(5)
        rid, opens, closes = current_round()
    log(f'\n## Uji refund 1 pemain — ronde #{rid}')
    b = bots[0]
    gb_before = num(call('balanceOf(address)(uint256)', b['addr']))
    seed = '0x' + '00' * 30 + f'{rid:02x}ff'
    d, err = send(b['key'], GAME, 'enter(uint256,uint256,bytes32)', rid, 5_000_000 * 10**18, seed)
    log(f"enter {b['name']} 5jt (sendirian): {'ok' if d and d.get('status') == '0x1' else 'GAGAL'}")
    while int(time.time()) < closes + 3:
        time.sleep(5)
    d, err = send(dk, GAME, 'refund(uint256)', rid)
    log(f"refund: {d.get('transactionHash') if d else 'GAGAL ' + str(err)}")
    det = call('roundDetail(uint256)(uint8,uint64,uint64,uint256,uint256,uint256,uint256,uint256,uint256)', rid).strip().split('\n')
    check(num(det[0]) == 4, 'refund: phase refunded (4)')
    check(num(det[6]) == 0 and num(det[7]) == 0, 'refund: burn & fee 0')
    gb_after = num(call('balanceOf(address)(uint256)', b['addr']))
    check(gb_after - gb_before == 5_000_000 * 10**18, 'refund: stake kembali penuh ke saldo game')

def withdraw_test():
    log('\n## Uji withdraw')
    b = bots[1]
    gb = num(call('balanceOf(address)(uint256)', b['addr']))
    wb = num(token_call('balanceOf(address)(uint256)', b['addr']))
    d, err = send(b['key'], GAME, 'withdraw(uint256)', gb)
    ok = d and d.get('status') == '0x1'
    log(f"withdraw {b['name']} {gb/1e18:,.2f}: {'ok' if ok else 'GAGAL ' + str(err)}")
    gb2 = num(call('balanceOf(address)(uint256)', b['addr']))
    wb2 = num(token_call('balanceOf(address)(uint256)', b['addr']))
    check(gb2 == 0 and wb2 - wb == gb, 'withdraw: saldo game 0, wallet bertambah persis')

play_round([2, 2, 5, 5, 10], 'Ronde A (campuran)')
play_round([10, 10, 2, 5, 2], 'Ronde B (campuran)')
withdraw_test()
play_round([5, 5, 5, 5, 5], 'Ronde C (semua 5jt)')
play_round([2, 10, 10, 10, 2], 'Ronde D (campuran + double-enter)', double_enter_bot=0)
refund_round()

log('\n## Kesimpulan')
if fails:
    log(f'GAGAL {len(fails)} cek:')
    for f in fails:
        log(' - ' + f)
else:
    log('SEMUA CEK LOLOS — 4 ronde settle 5 pemain + refund + withdraw + double-enter.')
log(f'Selesai: {time.strftime("%Y-%m-%d %H:%M:%S")} WIB')
print('STRESS_DONE fails=', len(fails))
