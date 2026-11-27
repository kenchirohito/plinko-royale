#!/usr/bin/env python3
"""Plinko Royale — demo ronde 10 bot di BSC testnet (chain 97), kontrak 0x5133.

Satu ronde penuh 10 pemain (tier campuran 100K..10M), verifikasi on-chain,
hasil ditulis ke testnet/demo-round-10.json untuk render video replay.

TESTNET ONLY. Key dibaca dari testnet/keys/, tidak pernah dicetak.
"""
import json, re, subprocess, time, os
from concurrent.futures import ThreadPoolExecutor

RPC = 'https://data-seed-prebsc-1-s1.bnbchain.org:8545'
GAME = '0x5133d3a7b0AAb6dFb3c40b824741FA4A776Bc3EF'
TOKEN = '0x17356908F432eD7F2a4b378F19b5c869b872e21E'
DEAD = '0x000000000000000000000000000000000000dEaD'
FEERECIP = '0x627Ce1AEda3f4B8f2f63E6051Ddd1304fc533c87'
CAST = '/home/hatch/.foundry/bin/cast'
LEGACY = ['--legacy', '--gas-price', '100000000', '--rpc-url', RPC]
MULT = [1160, 300, 140, 70, 40, 70, 140, 300, 1160]  # x100
TIERS = [100_000, 300_000, 500_000, 1_000_000, 2_000_000,
         5_000_000, 10_000_000, 1_000_000, 300_000, 2_000_000]
OUT = 'testnet/demo-round-10.json'
os.chdir('/home/hatch/workspace/plinko-royale')

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
    return json.loads(r.stdout), None

def current_round():
    ls = call('currentRound()(uint256,uint64,uint64)').strip().split('\n')
    return num(ls[0]), num(ls[1]), num(ls[2])

def path_bits(word, rid, player, seed):
    enc = run([CAST, 'abi-encode', 'f(uint256,uint256,address,bytes32)', str(word), str(rid), player, seed]).stdout.strip()
    h = run([CAST, 'keccak', enc]).stdout.strip()
    top = int(h[2:4], 16)
    return [(top >> i) & 1 for i in range(7, -1, -1)]  # MSB first, like frontend

fails = []
def check(cond, label):
    print(('PASS ' if cond else 'FAIL ') + label, flush=True)
    if not cond:
        fails.append(label)
    return cond

# --- wallet player6..10 kalau belum ada ---
for i in range(6, 11):
    p = f'testnet/keys/player{i}.txt'
    if not os.path.exists(p):
        r = run([CAST, 'wallet', 'new'])
        m = re.search(r'0x[0-9a-fA-F]{64}', r.stdout)
        with open(p, 'w') as f:
            f.write('TESTNET ONLY - Plinko Royale demo bot\n' + m.group(0) + '\n')
        os.chmod(p, 0o600)
        print(f'player{i} key dibuat', flush=True)

bots = []
for i in range(1, 11):
    k = key_of(f'player{i}')
    bots.append({'name': f'player{i}', 'key': k, 'addr': addr_of(k)})
dk = key_of('deployer')
print('Bot:', ', '.join(f"{b['name']}={b['addr'][:8]}…" for b in bots), flush=True)

# --- persiapan: tBNB + mock AGC + approve ---
for b in bots:
    bal = num(run([CAST, 'balance', b['addr'], '--rpc-url', RPC]).stdout)
    if bal < 10**16:
        r = run([CAST, 'send', '--json', *LEGACY, '--private-key', dk, '--value', str(2 * 10**16), b['addr']])
        print(f"fund {b['name']} 0.02 tBNB: {'ok' if r.returncode == 0 else 'GAGAL ' + r.stderr[:150]}", flush=True)
    tb = num(token_call('balanceOf(address)(uint256)', b['addr']))
    if tb < 50_000_000 * 10**18:
        d, err = send(b['key'], TOKEN, 'mint(address,uint256)', b['addr'], 100_000_000 * 10**18)
        print(f"mint 100jt mock AGC {b['name']}: {'ok' if d and d.get('status') == '0x1' else 'GAGAL ' + str(err)}", flush=True)
    allow = num(token_call('allowance(address,address)(uint256)', b['addr'], GAME))
    if allow < 10**27:
        d, err = send(b['key'], TOKEN, 'approve(address,uint256)', GAME, 10**27)
        print(f"approve {b['name']}: {'ok' if d and d.get('status') == '0x1' else 'GAGAL ' + str(err)}", flush=True)

# --- tunggu ronde segar (sisa > 50 detik) ---
while True:
    rid, opens, closes = current_round()
    left = closes - int(time.time())
    if left > 50:
        break
    print(f'ronde {rid} sisa {left}s, tunggu ronde berikutnya…', flush=True)
    time.sleep(max(2, left + 2))
print(f'\nRonde #{rid} (tutup dalam {closes - int(time.time())}s) — enter 10 bot paralel', flush=True)

dead_before = num(token_call('balanceOf(address)(uint256)', DEAD))
fee_before = num(token_call('balanceOf(address)(uint256)', FEERECIP))

seeds = {}
def do_enter(i):
    b = bots[i]
    seed = '0x' + '00' * 29 + f'{rid:04x}{i:02x}'
    seeds[b['addr']] = seed
    d, err = send(b['key'], GAME, 'enter(uint256,uint256,bytes32)', rid, TIERS[i] * 10**18, seed)
    ok = bool(d and d.get('status') == '0x1')
    return i, ok, (d or {}).get('transactionHash'), err

with ThreadPoolExecutor(max_workers=10) as ex:
    for i, ok, txh, err in ex.map(do_enter, range(10)):
        print(f"enter {bots[i]['name']} {TIERS[i]:,}: {'ok ' + str(txh) if ok else 'GAGAL ' + str(err)}", flush=True)
        if not ok:
            fails.append(f"enter {bots[i]['name']}")

while int(time.time()) < closes + 3:
    time.sleep(3)
fee = num(call('drawFee(uint256)(uint256)', 100000000))
d, err = send(dk, GAME, 'draw(uint256)', rid, value=fee * 2)
draw_tx = (d or {}).get('transactionHash')
print(f'draw: {draw_tx if d else "GAGAL " + str(err)}', flush=True)

word = 0
for _ in range(60):
    word = num(call('randomWordOf(uint256)(uint256)', rid))
    if word:
        break
    time.sleep(10)
check(word != 0, 'VRF word datang')
print(f'word: {word}', flush=True)

d, err = send(dk, GAME, 'settle(uint256)', rid)
settle_tx = (d or {}).get('transactionHash')
print(f'settle: {settle_tx if d else "GAGAL " + str(err)}', flush=True)

det = call('roundDetail(uint256)(uint8,uint64,uint64,uint256,uint256,uint256,uint256,uint256,uint256)', rid).strip().split('\n')
phase, pot, burned, fee_paid, dust = num(det[0]), num(det[3]), num(det[6]), num(det[7]), num(det[8])
check(phase == 3, 'phase settled (3)')
exp_burn = pot * 30 // 10000
check(burned == exp_burn, f'burn == 0,3% pot ({burned/1e18:,.0f})')
check(fee_paid == exp_burn, f'fee == 0,3% pot ({fee_paid/1e18:,.0f})')

rows = []
for i, b in enumerate(bots):
    res = call('result(uint256,address)(uint256,uint256,uint8)', rid, b['addr']).strip().split('\n')
    rows.append({'name': b['name'], 'addr': b['addr'], 'stake': num(res[0]), 'payout': num(res[1]), 'slot': num(res[2])})

total_score = sum(r['stake'] * MULT[r['slot']] for r in rows)
pool = pot - burned - fee_paid
sum_pay = 0
for r in rows:
    bits = path_bits(word, rid, r['addr'], seeds[r['addr']])
    r['bits'] = bits
    check(sum(bits) == r['slot'], f"slot {r['name']} cocok hitung ulang ({r['slot']})")
    exp_pay = pool * (r['stake'] * MULT[r['slot']]) // total_score
    check(exp_pay == r['payout'], f"payout {r['name']} cocok rumus ({r['payout']/1e18:,.2f})")
    sum_pay += r['payout']
    print(f"  {r['name']}: stake {r['stake']/1e18:,.0f} slot {r['slot']} ({MULT[r['slot']]/100}×) payout {r['payout']/1e18:,.2f}", flush=True)

check(sum_pay + burned + fee_paid + dust == pot, 'conservation payout+burn+fee+dust == pot')
dead_after = num(token_call('balanceOf(address)(uint256)', DEAD))
fee_after = num(token_call('balanceOf(address)(uint256)', FEERECIP))
check(dead_after - dead_before == burned, 'delta dead == burn')
check(fee_after - fee_before == fee_paid, 'delta feeRecipient == fee')

out = {
    'roundId': rid, 'word': str(word), 'pot': pot, 'burned': burned,
    'feePaid': fee_paid, 'dust': dust, 'drawTx': draw_tx, 'settleTx': settle_tx,
    'players': [{'name': r['name'], 'addr': r['addr'], 'stake': r['stake'],
                 'slot': r['slot'], 'bits': r['bits'], 'payout': r['payout']} for r in rows],
    'fails': fails,
}
with open(OUT, 'w') as f:
    json.dump(out, f, indent=1)
print(f'\nHasil ditulis ke {OUT}. Fails: {len(fails)}', flush=True)
for f_ in fails:
    print(' - ' + f_)
