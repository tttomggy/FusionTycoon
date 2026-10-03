"""Greedy-player economy sim for Fusion Tycoon.

Simulates a brand-new save played by a greedy player (always buys the best
income-per-cost upgrade, pulls the Gacha when cheap relative to income, fuses
surplus pairs) and prints median milestone times over many seeds.

The tunables below must mirror TycoonConfig.lua / FusionConfig.lua. Change a
number in both places, run `python3 tools/econ_sim.py`, and check the
milestones against the targets in TycoonConfig's header before shipping.
"""
import random, sys

TIERS = ["Common", "Rare", "Epic", "Legendary", "Mythic"]
TIER_MULT = {"Common": 1, "Rare": 2.5, "Epic": 6, "Legendary": 15, "Mythic": 40}

# ---- tunables ----
DROP_VALUE = 4
DROP_INTERVAL = 2.0
DROPPER2_COST = 60
START_BASIC = 1  # new saves start with Basic Generator LV 1
NO_DROPPERS = True  # the factory line replaced the old droppers
GENS = [  # id, tier, base cps, base cost, growth, max, unlock(prev level)
    ("basic", "Common", 2, 25, 1.15, 25, None),
    ("ember", "Rare", 4, 400, 1.17, 25, ("basic", 5)),
    ("flare", "Epic", 15, 8000, 1.19, 25, ("ember", 10)),
    ("core", "Legendary", 60, 150000, 1.21, 25, ("flare", 15)),
    ("sing", "Mythic", 250, 4000000, 1.23, 25, ("core", 20)),
]
MULT_LEVELS = [(5000, 1.5), (30000, 2), (150000, 2.5), (750000, 3), (3500000, 4),
               (15000000, 5), (60000000, 6.5), (250000000, 8), (1000000000, 10), (4000000000, 12.5)]
PEDESTAL_CPS = {"Common": 3, "Rare": 12, "Epic": 50, "Legendary": 220, "Mythic": 1000}
PEDESTALS = 4
GACHA_COST = 250
GACHA_GROWTH = 1.045
GACHA_RATES = {"Common": 0.78, "Rare": 0.18, "Epic": 0.035, "Legendary": 0.0045, "Mythic": 0.0005}
FUSE_SUCCESS = {"Common": 0.70, "Rare": 0.50, "Epic": 0.35, "Legendary": 0.20}
FUSE_SECONDS = 4.0
PULL_BUDGET_SECONDS = 60  # pull if cost <= this many seconds of income


def run(seed, horizon=4 * 3600, verbose=False):
    rng = random.Random(seed)
    cash = 0.0
    t = 0.0
    dropper2 = False
    gen = {g[0]: 0 for g in GENS}
    gen['basic'] = START_BASIC
    mult_lvl = 0
    inv = {k: 0 for k in TIERS}
    milestones = {}
    pulls = 0

    def mult():
        return 1 if mult_lvl == 0 else MULT_LEVELS[mult_lvl - 1][1]

    def ped_tiers():
        out = []
        for tier in reversed(TIERS):
            out += [tier] * inv[tier]
            if len(out) >= PEDESTALS:
                break
        return out[:PEDESTALS]

    def cps():
        drop = 0 if NO_DROPPERS else DROP_VALUE / DROP_INTERVAL * (2 if dropper2 else 1)
        g = sum(b * TIER_MULT[tr] * gen[i] for i, tr, b, *_ in GENS)
        p = sum(PEDESTAL_CPS[tr] for tr in ped_tiers())
        return (drop + g + p) * mult()

    def mark(name):
        if name not in milestones:
            milestones[name] = t

    step = 1.0
    while t < horizon:
        income = cps()
        cash += income * step
        t += step
        # options: (cost, gain_cps, action)
        opts = []
        if not dropper2 and not NO_DROPPERS:
            opts.append((DROPPER2_COST, DROP_VALUE / DROP_INTERVAL * mult(), "d2"))
        for i, tr, b, c0, gr, mx, unlock in GENS:
            if gen[i] >= mx:
                continue
            if unlock and gen[unlock[0]] < unlock[1]:
                continue
            cost = c0 * gr ** gen[i]
            opts.append((cost, b * TIER_MULT[tr] * mult(), ("g", i)))
        if mult_lvl < len(MULT_LEVELS):
            cost, m = MULT_LEVELS[mult_lvl]
            opts.append((cost, income / mult() * (m - mult()), "m"))
        bought = True
        while bought:
            bought = False
            # gacha
            gcost = GACHA_COST * GACHA_GROWTH ** pulls
            if gcost <= max(income, 1) * PULL_BUDGET_SECONDS and cash >= gcost:
                cash -= gcost
                pulls += 1
                r = rng.random(); acc = 0
                for tr in TIERS:
                    acc += GACHA_RATES[tr]
                    if r <= acc:
                        inv[tr] += 1; break
                bought = True
            if opts:
                best = min(opts, key=lambda o: o[0] / max(o[1], 1e-9))
                if cash >= best[0]:
                    cash -= best[0]
                    a = best[2]
                    if a == "d2": dropper2 = True; mark("dropper2")
                    elif a == "m": mult_lvl += 1; mark(f"mult{mult_lvl}")
                    else:
                        gen[a[1]] += 1; mark(f"gen_{a[1]}")
                    opts = []  # recompute next tick
            # fuse lowest pair (keep pedestal items: fuse only surplus)
        for tr in TIERS[:-1]:
            keep = ped_tiers().count(tr)
            while inv[tr] - keep >= 2:
                t += FUSE_SECONDS
                inv[tr] -= 2
                if rng.random() < FUSE_SUCCESS[tr]:
                    nxt = TIERS[TIERS.index(tr) + 1]
                    inv[nxt] += 1
                else:
                    inv[tr] += 1
                keep = ped_tiers().count(tr)
        if pulls >= 1: mark("first_pull")
        for tr in TIERS[1:]:
            if inv[tr] > 0 or tr in ped_tiers(): mark(f"first_{tr}")
        if ped_tiers().count("Mythic") == PEDESTALS: mark("4_mythic")
        if mult_lvl == len(MULT_LEVELS): mark("mult_max")
    return milestones, cps(), pulls


def fmt(s):
    if s is None: return "   -   "
    m, sec = divmod(int(s), 60)
    h, m = divmod(m, 60)
    return f"{h}:{m:02d}:{sec:02d}"


if __name__ == "__main__":
    keys = ["dropper2", "first_pull", "gen_basic", "mult1", "gen_ember", "first_Rare", "first_Epic", "mult3",
            "gen_flare", "first_Legendary", "mult5", "gen_core", "first_Mythic", "gen_sing", "mult_max", "4_mythic"]
    runs = [run(s) for s in range(20)]
    for k in keys:
        vals = sorted(r[0].get(k, 1e9) for r in runs)
        med = vals[len(vals) // 2]
        print(f"{k:16s} median {fmt(med if med < 1e9 else None)}   p10 {fmt(vals[2] if vals[2]<1e9 else None)}  p90 {fmt(vals[17] if vals[17]<1e9 else None)}")
    print("final cps median", sorted(r[1] for r in runs)[10], "pulls", sorted(r[2] for r in runs)[10])
