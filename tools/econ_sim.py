"""Greedy-player economy sim for Fusion Tycoon.

Simulates a brand-new save played by a greedy player (always buys the best
income-per-cost upgrade, pulls the Gacha when cheap relative to income, fuses
plain surplus pairs, displays the best 4 items, rebirths as soon as it can)
and prints median milestone times over many seeds.

The tunables below must mirror TycoonConfig.lua / FusionConfig.lua /
RebirthConfig.lua / IndexConfig.lua. Change a number in both places, run
`python3 tools/econ_sim.py`, and check the milestones against the targets in
TycoonConfig's header before shipping.

Usage:  python3 tools/econ_sim.py               # 20 seeds, 10 h horizon
        python3 tools/econ_sim.py 40 14         # 40 seeds, 14 h horizon
        python3 tools/econ_sim.py --no-depth    # Polish 4 only (no Secret,
                                                # mutations or Index)
"""
import random, sys

TIERS = ["Common", "Rare", "Epic", "Legendary", "Mythic", "Secret"]
GEN_TIER_MULT = {"Common": 1, "Rare": 2.5, "Epic": 6, "Legendary": 15, "Mythic": 40}
ITEMS_PER_TIER = {"Common": 3, "Rare": 3, "Epic": 3, "Legendary": 3, "Mythic": 3, "Secret": 2}

# ---- tunables (mirror the Lua configs) ----
START_BASIC = 1  # new saves (and every rebirth) start with Basic Generator LV 1
GENS = [  # id, tier, base cps, base cost, growth, max, unlock(prev level)
    ("basic", "Common", 2, 25, 1.15, 25, None),
    ("ember", "Rare", 4, 400, 1.17, 25, ("basic", 5)),
    ("flare", "Epic", 15, 8000, 1.19, 25, ("ember", 10)),
    ("core", "Legendary", 60, 150000, 1.21, 25, ("flare", 15)),
    ("sing", "Mythic", 250, 4000000, 1.23, 25, ("core", 20)),
]
# Multiplier Pad: 15 levels, +0.25 each (x1.25 .. x4.5), and LV 15 jumps to x5.
MULT_COSTS = [5e3, 3e4, 1.5e5, 7.5e5, 3.5e6, 1.5e7, 6e7, 2.5e8, 1e9, 4e9,
              1.5e10, 5e10, 1.5e11, 5e11, 1.5e12]
MULT_LEVELS = [(c, 5.0 if i == 14 else 1 + 0.25 * (i + 1)) for i, c in enumerate(MULT_COSTS)]
PEDESTAL_CPS = {"Common": 3, "Rare": 12, "Epic": 50, "Legendary": 300, "Mythic": 3000, "Secret": 50000}
PEDESTALS = 4
GACHA_COST = 250
GACHA_GROWTH = 1.045
GACHA_RATES = {"Common": 0.77998, "Rare": 0.18, "Epic": 0.035, "Legendary": 0.0045,
               "Mythic": 0.0005, "Secret": 0.00002}
LUCKY_TIERS = ("Legendary", "Mythic", "Secret")  # luck multiplies these; Common absorbs
FUSE_SUCCESS = {"Common": 0.70, "Rare": 0.50, "Epic": 0.35, "Legendary": 0.20, "Mythic": 0.08}
SECRET_FUSION_REBIRTHS = 1  # Mythic -> Secret fusion unlocks at this many rebirths
FUSE_SECONDS = 4.0
PULL_BUDGET_SECONDS = 60  # pull if cost <= this many seconds of income
# Mutations: (name, income mult, gacha chance, fusion-success chance)
MUTATIONS = [("Rainbow", 12, 0.001, 0.0005), ("Diamond", 5, 0.008, 0.004), ("Golden", 2, 0.04, 0.02)]
MUT_MULT = {"None": 1, "Golden": 2, "Diamond": 5, "Rainbow": 12}
# Rebirth: needs RunEarnings >= REBIRTH_BASE * REBIRTH_GROWTH ** rebirths.
REBIRTH_BASE = 3e7
REBIRTH_GROWTH = 3.2
REBIRTH_INCOME_PER = 0.5   # income x(1 + 0.5 * rebirths)
REBIRTH_LUCK_PER = 0.05    # luck x(1 + 0.05 * rebirths)
INDEX_PER_ENTRY = 0.01     # +1% income per Index entry discovered
INDEX_PER_PAGE = 0.05      # +5% per completed tier page (all items x all mutations)
# DEPTH = False simulates Polish 4 alone (rebirth, no Secret tier / mutations /
# Index). Run with --no-depth.
DEPTH = True


def run(seed, horizon=10 * 3600):
    rng = random.Random(seed)
    cash = 0.0
    t = 0.0
    rebirths = 0
    run_earn = 0.0
    gen = {g[0]: 0 for g in GENS}
    gen['basic'] = START_BASIC
    mult_lvl = 0
    inv = {}  # (tier, mutation) -> count
    index = set()  # (itemNo, tier, mutation)
    milestones = {}
    pulls = 0

    def add(tier, mut):
        inv[(tier, mut)] = inv.get((tier, mut), 0) + 1
        if DEPTH:
            index.add((tier, rng.randrange(ITEMS_PER_TIER[tier]), mut))

    def mult():
        return 1 if mult_lvl == 0 else MULT_LEVELS[mult_lvl - 1][1]

    def luck():
        return 1 + REBIRTH_LUCK_PER * rebirths

    def index_bonus():
        b = INDEX_PER_ENTRY * len(index)
        for tr in TIERS:
            if sum(1 for e in index if e[0] == tr) == ITEMS_PER_TIER[tr] * 4:
                b += INDEX_PER_PAGE
        return 1 + b

    def global_mult():
        return mult() * (1 + REBIRTH_INCOME_PER * rebirths) * index_bonus()

    def ped_items():
        items = []
        for (tr, mu), n in inv.items():
            items += [(PEDESTAL_CPS[tr] * MUT_MULT[mu], tr, mu)] * min(n, PEDESTALS)
        items.sort(reverse=True)
        return items[:PEDESTALS]

    def cps():
        g = sum(b * GEN_TIER_MULT[tr] * gen[i] for i, tr, b, *_ in GENS)
        p = sum(v for v, *_ in ped_items())
        return (g + p) * global_mult()

    def mark(name):
        if name not in milestones:
            milestones[name] = t

    def roll_tier():
        rates = dict(GACHA_RATES)
        if not DEPTH:
            rates["Secret"] = 0
        for tr in LUCKY_TIERS:
            rates[tr] *= luck()
        rates["Common"] = 1 - sum(v for k, v in rates.items() if k != "Common")
        r = rng.random(); acc = 0
        for tr in TIERS:
            acc += rates[tr]
            if r <= acc:
                return tr
        return "Common"

    def roll_mut(fusion):
        if not DEPTH:
            return "None"
        r = rng.random(); acc = 0
        for name, _, g, f in MUTATIONS:
            acc += (f if fusion else g) * luck()
            if r <= acc:
                return name
        return "None"

    step = 1.0
    while t < horizon:
        income = cps()
        cash += income * step
        run_earn += income * step
        t += step
        # rebirth as soon as possible
        if run_earn >= REBIRTH_BASE * REBIRTH_GROWTH ** rebirths:
            rebirths += 1
            mark(f"rebirth{rebirths}")
            cash = 0; run_earn = 0; pulls = 0; mult_lvl = 0
            gen = {g[0]: 0 for g in GENS}; gen['basic'] = START_BASIC
            continue
        opts = []
        for i, tr, b, c0, gr, mx, unlock in GENS:
            if gen[i] >= mx:
                continue
            if unlock and gen[unlock[0]] < unlock[1]:
                continue
            opts.append((c0 * gr ** gen[i], b * GEN_TIER_MULT[tr] * global_mult(), ("g", i)))
        if mult_lvl < len(MULT_LEVELS):
            cost, m = MULT_LEVELS[mult_lvl]
            opts.append((cost, income / mult() * (m - mult()), "m"))
        bought = True
        while bought:
            bought = False
            gcost = GACHA_COST * GACHA_GROWTH ** pulls
            if gcost <= max(income, 1) * PULL_BUDGET_SECONDS and cash >= gcost:
                cash -= gcost
                pulls += 1
                add(roll_tier(), roll_mut(False))
                bought = True
            if opts:
                best = min(opts, key=lambda o: o[0] / max(o[1], 1e-9))
                if cash >= best[0]:
                    cash -= best[0]
                    a = best[2]
                    if a == "m": mult_lvl += 1; mark(f"mult{mult_lvl}")
                    else:
                        gen[a[1]] += 1; mark(f"gen_{a[1]}")
                    opts = []
        # fuse plain surplus pairs (mutated items are kept, like Fuse All)
        fusable = TIERS[:-1] if DEPTH and rebirths >= SECRET_FUSION_REBIRTHS else TIERS[:-2]
        for tr in fusable:
            def keep():
                return sum(1 for _, ptr, pmu in ped_items() if ptr == tr and pmu == "None")
            while inv.get((tr, "None"), 0) - keep() >= 2:
                t += FUSE_SECONDS
                inv[(tr, "None")] -= 2
                if rng.random() < FUSE_SUCCESS[tr]:
                    add(TIERS[TIERS.index(tr) + 1], roll_mut(True))
                else:
                    inv[(tr, "None")] += 1
        if pulls >= 1: mark("first_pull")
        owned = {tr for (tr, mu), n in inv.items() if n > 0}
        for tr in TIERS[1:]:
            if tr in owned: mark(f"first_{tr}")
        for mu in MUT_MULT:
            if mu != "None" and any(n > 0 and m == mu for (tr, m), n in inv.items()):
                mark(f"first_{mu}")
        if mult_lvl == len(MULT_LEVELS): mark("mult_max")
        if gen["sing"] >= 10: mark("sing_lv10")
    return milestones, cps(), rebirths, len(index)


def fmt(s):
    if s is None: return "   -   "
    m, sec = divmod(int(s), 60)
    h, m = divmod(m, 60)
    return f"{h}:{m:02d}:{sec:02d}"


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--no-depth" in sys.argv:
        DEPTH = False
    seeds = int(args[0]) if len(args) > 0 else 20
    hours = float(args[1]) if len(args) > 1 else 10
    keys = ["first_pull", "gen_ember", "first_Rare", "first_Epic", "mult1", "first_Golden", "gen_flare",
            "first_Legendary", "first_Diamond", "gen_core", "first_Mythic", "rebirth1", "gen_sing", "rebirth2",
            "rebirth3", "first_Rainbow", "rebirth4", "sing_lv10", "rebirth5", "first_Secret", "rebirth6",
            "rebirth7", "rebirth8", "mult_max"]
    runs = [run(s, hours * 3600) for s in range(seeds)]
    lo, mid, hi = seeds // 10, seeds // 2, seeds - 1 - seeds // 10
    for k in keys:
        vals = sorted(r[0].get(k, 1e12) for r in runs)
        f = lambda v: fmt(v if v < 1e12 else None)
        print(f"{k:16s} median {f(vals[mid])}   p10 {f(vals[lo])}  p90 {f(vals[hi])}")
    print(f"after {hours:g} h: rebirths median", sorted(r[2] for r in runs)[mid],
          " index entries median", sorted(r[3] for r in runs)[mid], "/ 68",
          " cps median", f"{sorted(r[1] for r in runs)[mid]:.3g}")
