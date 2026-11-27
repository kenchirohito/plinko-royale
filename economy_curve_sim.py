#!/usr/bin/env python3
"""
Plinko Royale — economy curve comparison (research only, 2026-11-27).

Compares three multiplier tables, all with EV exactly 1.0 before fees
(sum(C(8,k)*M_k) = 25,600), under the real PvP payout formula:
  payout_i = 0.994 * pot * score_i / sum(scores), score = stake * mult.
Equal stakes, so payout/stake = 0.994 * n * mult_i / sum(mults).

Tables (x100, slots 0..8, symmetric):
  A current jackpot : 1160,300,140,70,40,70,140,300,1160
  B landai sedang   :  600,230,125,85,60,85,125,230,600
  C sering profit   :  330,150,130,105,50,105,130,150,330

Run: python3 economy_curve_sim.py
"""
import random, statistics
from math import comb

weights = [comb(8, k) for k in range(9)]
tables = {
    "A_current_jackpot_11.6/3.0/1.4/0.7/0.4": [1160,300,140,70,40,70,140,300,1160],
    "B_landai_sedang_6.0/2.3/1.25/0.85/0.6": [600,230,125,85,60,85,125,230,600],
    "C_sering_profit_3.3/1.5/1.3/1.05/0.5": [330,150,130,105,50,105,130,150,330],
}
for name, m in tables.items():
    assert sum(weights[i]*m[i] for i in range(9)) == 25600, name
    assert min(m) > 0

def drop(rng):
    return sum(1 for _ in range(8) if rng.random() < 0.5)

def sim(mult, n_players, rounds=20000, seed=20261127):
    rng = random.Random(seed)
    ratios = []
    for _ in range(rounds):
        slots = [drop(rng) for _ in range(n_players)]
        scores = [mult[s] for s in slots]
        total = sum(scores)
        pool = 0.994 * n_players
        ratios.extend(pool * sc / total for sc in scores)
    ratios.sort()
    def pct(p): return ratios[int(len(ratios)*p)]
    return {
        "mean": statistics.mean(ratios), "median": statistics.median(ratios),
        "p10": pct(0.10), "p90": pct(0.90), "p99": pct(0.99), "max": max(ratios),
        "profit%": sum(1 for r in ratios if r > 1)/len(ratios)*100,
        ">=0.9%": sum(1 for r in ratios if r >= 0.9)/len(ratios)*100,
        "<0.5%": sum(1 for r in ratios if r < 0.5)/len(ratios)*100,
        "<0.8%": sum(1 for r in ratios if r < 0.8)/len(ratios)*100,
        ">2x%": sum(1 for r in ratios if r > 2)/len(ratios)*100,
        ">5x%": sum(1 for r in ratios if r > 5)/len(ratios)*100,
        "stdev": statistics.pstdev(ratios),
    }

if __name__ == "__main__":
    for n in (10, 50):
        print(f"\n=== N={n} pemain, stake sama, 20000 ronde, seed 20261127 ===")
        for name, mult in tables.items():
            r = sim(mult, n)
            print(name)
            for k, v in r.items():
                print(f"  {k}: {v:.4f}")
    print("\nBR model: 80 pemain, 10/room, stake sama -> survivor 1.1357x (87.5%), killed 0 (12.5%), mean 0.9937")
