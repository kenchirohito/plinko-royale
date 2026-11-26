#!/usr/bin/env python3
"""
Plinko Royale — conservation & safety verification.

Simulates many randomized rounds and asserts, for EVERY round:
  1. sum(payouts) + burn + fee + dust == pot    (exact conservation, integer math)
  2. every payout >= 0                          (no negative payouts)
  3. total score > 0 before any division        (no division by zero, by construction)
  4. rounds with < 2 players refund in full     (no burn, no fee, payout == stake)
  5. every payout <= pot                        (nobody can win more than the pot)

Fee model: 0.3% of pot burned + 0.3% of pot operational fee = 0.6% total house edge.
Both are computed in basis points: burn = floor(pot * 30 / 10000),
fee = floor(pot * 30 / 10000), payoutPool = pot - burn - fee.

Money math is integer-only. Multipliers are scaled x100 (11.6 -> 1160).
Zero external dependencies (Python stdlib only).

Run:  python3 verify.py [rounds] [seed]
"""

import random
import sys
from math import comb

# ---------------------------------------------------------------------------
# Game constants (must match DESIGN.md and PROTOTYPE.html exactly)
# ---------------------------------------------------------------------------

ROWS = 8                      # peg rows -> ROWS+1 = 9 landing slots
SLOTS = ROWS + 1
STAKE_TIERS = (100_000, 300_000, 500_000, 1_000_000, 2_000_000, 5_000_000, 10_000_000)   # AGC, mirrors Battle Royale's 7-tier ladder
BURN_BPS = 30                                       # 0.3% of pot burned
FEE_BPS = 30                                        # 0.3% of pot operational fee
BPS_DEN = 10_000                                    # basis-point denominator
MIN_PLAYERS = 2                                     # fewer -> full refund

# Multipliers x100, slots 0..8 (edges high, center low).
# Slot probability = C(8,k)/256. EV = sum(C*M) / (256*100) = 25600/25600 = 1.0 exactly.
MULT_X100 = (1160, 300, 140, 70, 40, 70, 140, 300, 1160)
assert len(MULT_X100) == SLOTS
assert min(MULT_X100) > 0, "minimum multiplier must be > 0 (denominator safety)"
assert sum(comb(ROWS, k) * MULT_X100[k] for k in range(SLOTS)) == 256 * 100, "EV must be exactly 1.0"


def drop_slot(rng):
    """One ball: 8 pegs, each 50/50. Slot = number of right turns (binomial)."""
    return sum(1 for _ in range(ROWS) if rng.random() < 0.5)


def settle_round(stakes, slots):
    """
    Pure settlement function — the exact logic a contract would run.

    stakes: list of int (AGC, whole units)
    slots:  list of int (0..8), same length as stakes
    Returns (payouts, burn, fee, dust). All ints.

    Rules:
      - < MIN_PLAYERS players  -> full refund, burn = 0, fee = 0, dust = 0.
      - otherwise:
          pot        = sum(stakes)
          burn       = floor(pot * 30 / 10000)      (0.3% burned)
          fee        = floor(pot * 30 / 10000)      (0.3% operational fee)
          payoutPool = pot - burn - fee             (99.4% of pot)
          score_i    = stake_i * MULT_X100[slot_i]
          payout_i   = floor(payoutPool * score_i / sum(scores))
          dust       = payoutPool - sum(payouts)    (stays in contract)

    Dust bound: each payout floor loses < 1 unit, so dust < number of
    players. The two bps floors each under-collect by < 1 unit vs exact
    0.3% (<= 2 units total); that residue flows into payoutPool and is
    paid to players, so the total flooring deviation from exact rational
    accounting is < players + 2 units, of which only < players stays in
    the contract as dust.
    """
    n = len(stakes)
    assert n == len(slots)
    assert all(s > 0 for s in stakes), "stakes must be positive"
    assert all(0 <= s < SLOTS for s in slots), "slot out of range"

    if n < MIN_PLAYERS:
        # Refund rule: nobody to play against -> everyone gets their stake back.
        return list(stakes), 0, 0, 0

    pot = sum(stakes)
    burn = pot * BURN_BPS // BPS_DEN
    fee = pot * FEE_BPS // BPS_DEN
    payout_pool = pot - burn - fee

    scores = [stakes[i] * MULT_X100[slots[i]] for i in range(n)]
    total_score = sum(scores)
    # total_score > 0 always: every stake > 0 and every multiplier > 0.
    # This is why the minimum multiplier must never be 0.
    assert total_score > 0

    payouts = [payout_pool * sc // total_score for sc in scores]
    dust = payout_pool - sum(payouts)
    return payouts, burn, fee, dust


def check_round(stakes, slots, payouts, burn, fee, dust):
    """All invariants that must hold for every settled round."""
    pot = sum(stakes)
    assert sum(payouts) + burn + fee + dust == pot, "conservation violated"
    assert all(p >= 0 for p in payouts), "negative payout"
    assert burn >= 0 and fee >= 0 and dust >= 0, "negative burn/fee/dust"
    assert all(p <= pot for p in payouts), "payout exceeds pot"
    if len(stakes) < MIN_PLAYERS:
        assert payouts == list(stakes) and burn == 0 and fee == 0 and dust == 0, "refund rule violated"
    else:
        assert burn == pot * BURN_BPS // BPS_DEN, "burn amount wrong"
        assert fee == pot * FEE_BPS // BPS_DEN, "fee amount wrong"
        # Dust is bounded: each payout floor loses < 1 unit, so dust < players.
        assert dust < len(stakes), "dust larger than flooring bound"


def main():
    rounds = int(sys.argv[1]) if len(sys.argv) > 1 else 20_000
    seed = int(sys.argv[2]) if len(sys.argv) > 2 else 20261126
    rng = random.Random(seed)

    stats = {
        "rounds": 0, "refunds": 0, "total_pot": 0, "total_burn": 0,
        "total_fee": 0, "total_dust": 0, "max_dust": 0, "ties_all_same_slot": 0,
    }

    for r in range(rounds):
        # Player count: mostly 2..50, occasionally 0 or 1 to exercise the refund rule.
        if r % 97 == 0:
            n = rng.choice((0, 1))
        else:
            n = rng.randint(2, 50)
        stakes = [rng.choice(STAKE_TIERS) for _ in range(n)]
        slots = [drop_slot(rng) for _ in range(n)]

        payouts, burn, fee, dust = settle_round(stakes, slots)
        check_round(stakes, slots, payouts, burn, fee, dust)

        stats["rounds"] += 1
        stats["total_pot"] += sum(stakes)
        stats["total_burn"] += burn
        stats["total_fee"] += fee
        stats["total_dust"] += dust
        stats["max_dust"] = max(stats["max_dust"], dust)
        if n < MIN_PLAYERS:
            stats["refunds"] += 1
        if n >= 2 and len(set(slots)) == 1:
            stats["ties_all_same_slot"] += 1

    # Deterministic edge-case rounds (not random):
    edge_cases = [
        ([], []),                                   # empty round
        ([2_000_000], [4]),                         # single player -> refund
        ([10_000_000], [0]),                        # single player, edge slot -> refund
        ([2_000_000, 2_000_000], [0, 8]),           # both edges
        ([2_000_000, 5_000_000, 10_000_000], [4, 4, 4]),  # all same slot (tie)
        ([10_000_000] * 50, [4] * 50),              # max players, all center
        ([100_000, 10_000_000], [8, 0]),          # min vs max tier, both edges
    ]
    for stakes, slots in edge_cases:
        payouts, burn, fee, dust = settle_round(stakes, slots)
        check_round(stakes, slots, payouts, burn, fee, dust)

    print(f"Plinko Royale verification — seed {seed}")
    print(f"  randomized rounds simulated : {stats['rounds']:,}")
    print(f"  deterministic edge cases    : {len(edge_cases)}")
    print(f"  refund rounds (<2 players)  : {stats['refunds']:,}")
    print(f"  all-same-slot rounds        : {stats['ties_all_same_slot']:,}")
    print(f"  total pot simulated         : {stats['total_pot']:,} AGC")
    print(f"  total burned (0.3%)         : {stats['total_burn']:,} AGC")
    print(f"  total operational fee (0.3%)    : {stats['total_fee']:,} AGC")
    print(f"  total dust (flooring)       : {stats['total_dust']:,} AGC")
    print(f"  max dust in one round       : {stats['max_dust']} AGC")
    print("  ALL ASSERTIONS PASSED: conservation exact, no negatives,")
    print("  no division by zero, refund rule correct.")


if __name__ == "__main__":
    main()
