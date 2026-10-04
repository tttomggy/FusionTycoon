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
        python3 tools/econ_sim.py --fuse=3      # player puts 3 items per
                                                # fusion (default 2)
        python3 tools/econ_sim.py --sessions=3  # 3 sessions of 45 min, 8 h
                                                # away between: Rebirth 1-3
                                                # in played time, with vs.
                                                # without offline earnings
        python3 tools/econ_sim.py 30 12 --events
                                                # the lab-weather clock on
                                                # (EventConfig), then Rebirth
                                                # 1-3 vs. the same seeds
                                                # without events
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

# Shop (keep in sync with ShopConfig): what a paying player's passes and
# boosts change. --monetization compares free / passes / passes + a Boost.
DOUBLE_CASH_MULT = 2.0  # ShopConfig.DoubleCashMultiplier
VIP_MULT = 1.25  # ShopConfig.VipMultiplier
BOOST_MULT = 2.0  # ShopConfig.BoostMultiplier
EXTRA_PEDESTALS = 6  # ShopConfig.ExtraPedestals
PAYERS = {
    "free": {"mult": 1.0, "pedestals": PEDESTALS, "boost": False},
    "passes": {"mult": DOUBLE_CASH_MULT * VIP_MULT, "pedestals": EXTRA_PEDESTALS, "boost": False},
    # One 1 h Boost bought every played hour: x2 is always on.
    "passes+boost": {"mult": DOUBLE_CASH_MULT * VIP_MULT, "pedestals": EXTRA_PEDESTALS, "boost": True},
}
GACHA_COST = 250
GACHA_GROWTH = 1.045
GACHA_RATES = {"Common": 0.77998, "Rare": 0.18, "Epic": 0.035, "Legendary": 0.0045,
               "Mythic": 0.0005, "Secret": 0.00002}
LUCKY_TIERS = ("Legendary", "Mythic", "Secret")  # luck multiplies these; Common absorbs
# Fusion: put 2-6 same-tier items in; success -> 1 item of the next tier,
# fail -> you keep 1 (your best) and lose the rest. Chance by input count:
FUSE_CHANCE = {  # tier: {count: chance}
    "Common":    {2: 0.55, 3: 0.68, 4: 0.78, 5: 0.90, 6: 1.00},
    "Rare":      {2: 0.45, 3: 0.57, 4: 0.66, 5: 0.74, 6: 0.80},
    "Epic":      {2: 0.35, 3: 0.45, 4: 0.53, 5: 0.60, 6: 0.66},
    "Legendary": {2: 0.20, 3: 0.27, 4: 0.33, 5: 0.39, 6: 0.45},
    "Mythic":    {2: 0.07, 3: 0.09, 4: 0.11, 5: 0.13, 6: 0.15},
}
FUSE_COUNT = 2  # how many items the simulated player puts in (--fuse N)
SECRET_FUSION_REBIRTHS = 1  # Mythic -> Secret fusion unlocks at this many rebirths
FUSE_SECONDS = 4.0
PULL_BUDGET_SECONDS = 60  # pull if cost <= this many seconds of income
# Mutations: (name, income mult, gacha chance, fusion-success chance)
MUTATIONS = [("Rainbow", 12, 0.001, 0.0005), ("Diamond", 5, 0.008, 0.004), ("Golden", 2, 0.04, 0.02)]
MUT_MULT = {"None": 1, "Golden": 2, "Charged": 3, "Diamond": 5, "Void": 8, "Rainbow": 12, "Celestial": 20}
# Index variants per item: Normal + all six mutations (event-only included),
# so a full page needs the event mutations too (IndexConfig: 17 x 7 = 119).
INDEX_VARIANTS = 7
# Rebirth costs REBIRTH_BASE * REBIRTH_GROWTH ** rebirths cash. The player
# stops spending once the rebirth is within SAVE_SECONDS of income.
REBIRTH_BASE = 1.5e7
REBIRTH_GROWTH = 3.2
SAVE_SECONDS = 600
REBIRTH_INCOME_PER = 0.5   # income x(1 + 0.5 * rebirths)
REBIRTH_LUCK_PER = 0.05    # luck x(1 + 0.05 * rebirths)
INDEX_PER_ENTRY = 0.01     # +1% income per Index entry discovered
INDEX_PER_PAGE = 0.05      # +5% per completed tier page (all items x all mutations)
# DEPTH = False simulates Polish 4 alone (rebirth, no Secret tier / mutations /
# Index). Run with --no-depth.
DEPTH = True

# Offline earnings (OfflineConfig.lua): while away, Rate x income per second
# for at most MaxSeconds; nothing under MinSeconds. Only --sessions uses it.
OFFLINE_RATE = 0.25
OFFLINE_MAX_SECONDS = 4 * 3600
OFFLINE_MIN_SECONDS = 120
SESSION_SECONDS = 45 * 60
AWAY_SECONDS = 8 * 3600

# Events (EventConfig.lua), only with --events. The game picks each slot's
# event from Random.new(slotStart); the sim draws the same distribution
# from its own seeded RNG per slot.
EVENTS = False
EV_SLOT = 15 * 60
EV_VOID_MOON_CHANCE = 0.15
EV_DURATION = {"GoldenRain": 300, "PowerSurge": 300, "MeteorShower": 180, "RainbowStorm": 300,
               "Night": 600, "VoidMoon": 600}
EV_WEATHER = [("GoldenRain", 40), ("PowerSurge", 35), ("MeteorShower", 20), ("RainbowStorm", 5)]
COIN_INTERVAL = 10         # a coin per plot every 10 s
COIN_INCOME_SECONDS = 3    # each worth 3 s of income
COIN_PICKUP = 0.70         # share of lab coins the player actually collects
BIG_COIN_CHANCE = 8        # 1 in 8 lab coins is BIG ...
BIG_COIN_INCOME_SECONDS = 20  # ... and worth this many seconds instead
STREET_COIN_INTERVAL = 15  # a street coin every 15 s ...
STREET_COIN_INCOME_SECONDS = 6  # ... paying the grabber 6 s of income
# street coins are a race: the player gets 1 in SERVER_PLAYERS of them
GOLDEN_RAIN_GOLDEN_ODDS = 3
SURGE_GENERATOR_MULT = 1.25
LIGHTNING_INTERVAL = 20
LIGHTNING_CHARGE_CHANCE = 0.25
SERVER_PLAYERS = 6         # lightning picks one displayed item in the server;
                           # meteors are raced by this many players
METEOR_COUNT = 6
METEOR_CORE_TIERS = [("Epic", 60), ("Legendary", 30), ("Mythic", 9), ("Secret", 1)]
METEOR_CELESTIAL = 0.15
NIGHT_FUSION_MUT_ODDS = 2
VOID_MOON_FUSION_BONUS = 0.05
VOID_CHANCE = 0.05
RAINBOW_STORM_ODDS = 5


def run(seed, horizon=10 * 3600, sessions=0, offline=True, payer="free"):
    """t is played time. With sessions > 0 the player plays that many
    SESSION_SECONDS sessions with AWAY_SECONDS between them, collecting
    offline earnings (unless offline=False) at the start of each new one."""
    if sessions:
        horizon = sessions * SESSION_SECONDS
    next_break = SESSION_SECONDS if sessions else horizon + 1
    rng = random.Random(seed)
    # Events: the clock starts at a random minute; one cached pick per slot.
    ev_offset = random.Random(seed * 31 + 7).uniform(0, 3600)
    ev_slots = {}
    ev_last = [None, -1]  # (id, slot) seen last step: meteor cores on a start

    def event_at(time):
        if not EVENTS:
            return None
        clock = time + ev_offset
        slot = int(clock // EV_SLOT)
        if slot not in ev_slots:
            r = random.Random(slot * 104729 + 13)
            if slot % 4 == 0:
                ev = "VoidMoon" if r.random() < EV_VOID_MOON_CHANCE else "Night"
            else:
                roll = r.random() * sum(w for _, w in EV_WEATHER)
                ev = EV_WEATHER[-1][0]
                for name, w in EV_WEATHER:
                    roll -= w
                    if roll < 0:
                        ev = name
                        break
            ev_slots[slot] = ev
        ev = ev_slots[slot]
        return (ev, slot) if clock - slot * EV_SLOT < EV_DURATION[ev] else None

    shop = PAYERS[payer]
    pedestals = shop["pedestals"]
    shop_mult = shop["mult"] * (BOOST_MULT if shop["boost"] else 1)

    cash = 0.0
    t = 0.0
    rebirths = 0
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
            if sum(1 for e in index if e[0] == tr) == ITEMS_PER_TIER[tr] * INDEX_VARIANTS:
                b += INDEX_PER_PAGE
        return 1 + b

    def global_mult():
        return mult() * (1 + REBIRTH_INCOME_PER * rebirths) * index_bonus() * shop_mult

    def ped_items():
        items = []
        for (tr, mu), n in inv.items():
            items += [(PEDESTAL_CPS[tr] * MUT_MULT[mu], tr, mu)] * min(n, pedestals)
        items.sort(reverse=True)
        return items[:pedestals]

    def cps(ev=None):
        g = sum(b * GEN_TIER_MULT[tr] * gen[i] for i, tr, b, *_ in GENS)
        if ev == "PowerSurge":
            g *= SURGE_GENERATOR_MULT
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

    def odds_mult(ev, name, fusion):
        if ev == "GoldenRain" and name == "Golden":
            return GOLDEN_RAIN_GOLDEN_ODDS
        if ev == "RainbowStorm":
            return RAINBOW_STORM_ODDS
        if ev in ("Night", "VoidMoon") and fusion:
            return NIGHT_FUSION_MUT_ODDS
        return 1

    def roll_mut(fusion, ev=None):
        if not DEPTH:
            return "None"
        if fusion and ev == "VoidMoon" and rng.random() < VOID_CHANCE:
            return "Void"  # replaces the normal fusion roll
        r = rng.random(); acc = 0
        for name, _, g, f in MUTATIONS:
            acc += (f if fusion else g) * luck() * odds_mult(ev, name, fusion)
            if r <= acc:
                return name
        return "None"

    def meteor_core():
        roll = rng.random() * sum(w for _, w in METEOR_CORE_TIERS)
        tier = METEOR_CORE_TIERS[0][0]
        for tr, w in METEOR_CORE_TIERS:
            roll -= w
            if roll < 0:
                tier = tr
                break
        add(tier, "Celestial" if rng.random() < METEOR_CELESTIAL else "None")

    def lightning():
        # One strike on a random displayed item in a SERVER_PLAYERS server.
        if rng.random() >= 1 / SERVER_PLAYERS:
            return
        shown = ped_items()
        if not shown:
            return
        _, tr, mu = rng.choice(shown)
        if mu == "None" and rng.random() < LIGHTNING_CHARGE_CHANCE:
            inv[(tr, "None")] -= 1
            add(tr, "Charged")

    step = 1.0
    while t < horizon:
        # Session boundary: away AWAY_SECONDS, paid at the income left with.
        while next_break <= t and next_break < horizon:
            next_break += SESSION_SECONDS
            if offline and AWAY_SECONDS >= OFFLINE_MIN_SECONDS:
                cash += cps() * OFFLINE_RATE * min(AWAY_SECONDS, OFFLINE_MAX_SECONDS)
        cur = event_at(t)
        ev = cur[0] if cur else None
        if cur and (ev_last[0], ev_last[1]) != cur:
            if ev == "MeteorShower":
                # METEOR_COUNT cores, SERVER_PLAYERS racing: about one each.
                for _ in range(round(METEOR_COUNT / SERVER_PLAYERS)):
                    meteor_core()
        ev_last[0], ev_last[1] = (cur if cur else (None, -1))
        income = cps(ev)
        cash += income * step
        if ev == "GoldenRain":
            lab_seconds = ((BIG_COIN_CHANCE - 1) * COIN_INCOME_SECONDS + BIG_COIN_INCOME_SECONDS) / BIG_COIN_CHANCE
            cash += income * COIN_PICKUP * lab_seconds / COIN_INTERVAL * step
            cash += income * (1 / SERVER_PLAYERS) * STREET_COIN_INCOME_SECONDS / STREET_COIN_INTERVAL * step
        if ev == "PowerSurge" and int(t) % LIGHTNING_INTERVAL == 0:
            lightning()
        t += step
        # rebirth as soon as affordable
        rebirth_cost = REBIRTH_BASE * REBIRTH_GROWTH ** rebirths
        if cash >= rebirth_cost:
            rebirths += 1
            mark(f"rebirth{rebirths}")
            cash = 0; pulls = 0; mult_lvl = 0
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
        saving = (rebirth_cost - cash) / max(income, 1e-9) <= SAVE_SECONDS
        bought = not saving
        while bought:
            bought = False
            gcost = GACHA_COST * GACHA_GROWTH ** pulls
            if gcost <= max(income, 1) * PULL_BUDGET_SECONDS and cash >= gcost:
                cash -= gcost
                pulls += 1
                add(roll_tier(), roll_mut(False, ev))
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
        # fuse plain surplus in groups of FUSE_COUNT (mutated items are kept)
        fusable = TIERS[:-1] if DEPTH and rebirths >= SECRET_FUSION_REBIRTHS else TIERS[:-2]
        for tr in fusable:
            def keep():
                return sum(1 for _, ptr, pmu in ped_items() if ptr == tr and pmu == "None")
            while inv.get((tr, "None"), 0) - keep() >= FUSE_COUNT:
                t += FUSE_SECONDS
                inv[(tr, "None")] -= FUSE_COUNT
                bonus = VOID_MOON_FUSION_BONUS if ev == "VoidMoon" else 0
                if rng.random() < min(1, FUSE_CHANCE[tr][FUSE_COUNT] + bonus):
                    add(TIERS[TIERS.index(tr) + 1], roll_mut(True, ev))
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


def report_sessions(seeds, sessions):
    """Rebirth 1-3 in played time for an N-session player, offline on/off."""
    on = [run(s, sessions=sessions, offline=True) for s in range(seeds)]
    off = [run(s, sessions=sessions, offline=False) for s in range(seeds)]
    mid = seeds // 2
    print(f"{sessions} sessions x {SESSION_SECONDS // 60} min, {AWAY_SECONDS // 3600} h away between "
          f"(offline {OFFLINE_RATE:.0%} for up to {OFFLINE_MAX_SECONDS // 3600} h); played time, {seeds} seeds")
    print(f"{'':10s} {'no offline':>12s} {'offline':>12s}  {'reached (off/on)':>16s}  speed-up")
    for k in ["rebirth1", "rebirth2", "rebirth3"]:
        a = sorted(r[0].get(k, 1e12) for r in off)
        b = sorted(r[0].get(k, 1e12) for r in on)
        f = lambda v: fmt(v if v < 1e12 else None)
        got_a = sum(1 for v in a if v < 1e12)
        got_b = sum(1 for v in b if v < 1e12)
        if a[mid] < 1e12 and b[mid] < 1e12:
            speed = f"{(a[mid] - b[mid]) / 60:+.0f} min ({a[mid] / b[mid]:.2f}x faster)"
        elif b[mid] < 1e12:
            speed = "only reached with offline"
        else:
            speed = "-"
        print(f"{k:10s} {f(a[mid]):>12s} {f(b[mid]):>12s}  {got_a:>7d}/{got_b:<8d}  {speed}")
    print("rebirths after the last session, median: no offline", sorted(r[2] for r in off)[mid],
          " offline", sorted(r[2] for r in on)[mid])


def report_monetization(seeds, hours):
    """Median time to each milestone for a free player, a 2x Cash + VIP +
    Extra Pedestals player, and the same with one Boost per hour."""
    keys = ["first_Epic", "mult1", "first_Legendary", "gen_core", "first_Mythic", "rebirth1", "gen_sing",
            "rebirth2", "rebirth3", "sing_lv10", "rebirth4", "rebirth5"]
    mid = seeds // 2
    results = {name: [run(s, hours * 3600, payer=name) for s in range(seeds)] for name in PAYERS}
    print(f"Monetization: median of {seeds} seeds, {hours:g} h played (no events)")
    print(f"{'milestone':16s}" + "".join(f"{name:>16s}" for name in PAYERS) + "   passes / boost vs free")
    for k in keys:
        row = []
        for name in PAYERS:
            vals = sorted(r[0].get(k, 1e12) for r in results[name])
            row.append(vals[mid])
        cells = "".join(f"{fmt(v if v < 1e12 else None):>16s}" for v in row)
        free = row[0]
        ratios = "   " + "  ".join(
            (f"{v / free:.0%}" if free < 1e12 and v < 1e12 else "  -") for v in row[1:]
        )
        print(f"{k:16s}{cells}{ratios}")
    for name in PAYERS:
        print(f"  {name:13s} rebirths after {hours:g} h, median", sorted(r[2] for r in results[name])[mid])


if __name__ == "__main__":
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if "--no-depth" in sys.argv:
        DEPTH = False
    if "--events" in sys.argv:
        EVENTS = True
    sessions = 0
    for a in sys.argv:
        if a.startswith("--fuse="):
            FUSE_COUNT = int(a.split("=")[1])
        if a.startswith("--sessions="):
            sessions = int(a.split("=")[1])
    seeds = int(args[0]) if len(args) > 0 else 20
    if "--monetization" in sys.argv:
        report_monetization(seeds, float(args[1]) if len(args) > 1 else 12)
        sys.exit(0)
    if sessions:
        report_sessions(seeds, sessions)
        sys.exit(0)
    hours = float(args[1]) if len(args) > 1 else 10
    keys = ["first_pull", "gen_ember", "first_Rare", "first_Epic", "mult1", "first_Golden", "gen_flare",
            "first_Legendary", "first_Diamond", "gen_core", "first_Mythic", "rebirth1", "gen_sing", "rebirth2",
            "rebirth3", "first_Rainbow", "first_Charged", "first_Void", "first_Celestial", "rebirth4", "sing_lv10", "rebirth5", "first_Secret", "rebirth6",
            "rebirth7", "rebirth8", "mult_max"]
    runs = [run(s, hours * 3600) for s in range(seeds)]
    lo, mid, hi = seeds // 10, seeds // 2, seeds - 1 - seeds // 10
    for k in keys:
        vals = sorted(r[0].get(k, 1e12) for r in runs)
        f = lambda v: fmt(v if v < 1e12 else None)
        print(f"{k:16s} median {f(vals[mid])}   p10 {f(vals[lo])}  p90 {f(vals[hi])}")
    print(f"after {hours:g} h: rebirths median", sorted(r[2] for r in runs)[mid],
          " index entries median", sorted(r[3] for r in runs)[mid], "/", sum(ITEMS_PER_TIER.values()) * INDEX_VARIANTS,
          " cps median", f"{sorted(r[1] for r in runs)[mid]:.3g}")
    if EVENTS:
        # The same seeds without events: how much the clock speeds Rebirth
        # 1-3 (target: at most 15% sooner).
        EVENTS = False
        base = [run(s, hours * 3600) for s in range(seeds)]
        print("events vs. none (same seeds), median:")
        for k in ["rebirth1", "rebirth2", "rebirth3"]:
            a = sorted(r[0].get(k, 1e12) for r in base)[mid]
            b = sorted(r[0].get(k, 1e12) for r in runs)[mid]
            if a < 1e12 and b < 1e12:
                print(f"  {k:10s} none {fmt(a)}  events {fmt(b)}  {(a - b) / a:+.1%} sooner")
            else:
                print(f"  {k:10s} none {fmt(a if a < 1e12 else None)}  events {fmt(b if b < 1e12 else None)}")
