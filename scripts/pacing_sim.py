"""M8-12 pacing simulation (dev tool, not part of the game).

Plays a typical ACTIVE player second-by-second (coarse 5 s steps) through the M8
economy and skill rules, mirroring ReplicatedStorage/Shared/Config.luau + Perks.luau.
Prints a timeline (rebirths, income, skills, total level, gap between purchases)
so the tuning targets in the M8 plan can be checked:
  * something to buy every 1-3 min early, 5-10 min late
  * first 99 around 200 h, max (all 99s) around 1,200-1,700 h

Usage:  python -I scripts/pacing_sim.py [hours]
Keep the CONFIG block in sync with Config.luau when tuning.
"""

import math
import random
import sys

# ---- mirrored Config ---------------------------------------------------------
RARITIES = [  # name, forest chance, $/s, tier
    ("Sprout", 0.62, 1, 1), ("Amber", 0.25, 3, 2), ("Frost", 0.09, 8, 3),
    ("Ember", 0.032, 20, 4), ("Void", 0.007, 50, 5), ("Celestial", 0.001, 120, 6),
    ("Prismatic", 0, 400, 7), ("Nebula", 0, 1600, 8), ("Singularity", 0, 7000, 9),
    ("Eternal", 0, 30000, 10),
]
TIER = {r[0]: r[3] for r in RARITIES}
RATE = {r[0]: r[2] for r in RARITIES}
ORDER = [r[0] for r in RARITIES]
UNLOCK = {"Prismatic": (1, 50), "Nebula": (2, 65), "Singularity": (3, 80), "Eternal": (4, 95)}
MUT = {"Gold": (2, 0.7), "Void": (10, 0.25), "Celestial": (30, 0.05)}
NETWORTH = {"Sprout": 50, "Amber": 150, "Frost": 400, "Ember": 1000, "Void": 2500, "Celestial": 6000,
            "Prismatic": 20000, "Nebula": 80000, "Singularity": 350000, "Eternal": 1500000}
PEDESTAL_PRICES = [150, 300, 600, 1200, 2500, 5000, 10000, 25000, 60000, 150000, 400000]
CRATES = [  # id, price, cultivation, odds
    ("Fertile", 2000, 20, {"Amber": .55, "Frost": .30, "Ember": .12, "Void": .025, "Celestial": .005}),
    ("Ancient", 250000, 45, {"Frost": .5, "Ember": .32, "Void": .13, "Celestial": .045, "Prismatic": .005}),
    ("Mythic", 50e6, 70, {"Void": .5, "Celestial": .35, "Prismatic": .12, "Nebula": .03}),
    ("Cosmic", 10e9, 90, {"Celestial": .45, "Prismatic": .35, "Nebula": .15, "Singularity": .049, "Eternal": .001}),
]
REB_REQ, REB_REQ_GROWTH, REB_INCOME = 300000, 2.6, 1.75
TIER_EVERY = 5
UP_BASE, UP_GROWTH, UP_SLOT_STEP, UP_INCOME, CAP_BASE, CAP_TIER, CAP_MAX = 200, 1.11, 0.15, 0.12, 50, 10, 10000
CYCLE_BONUS = 0.10
UP_INCOME_MULT = 1.08  # income x1.08 per pedestal level (compounding)
SKILL_XP_SCALE = {"Foraging": 1, "Cultivation": 1, "Alchemy": 1.2, "Thievery": 1.3, "Guarding": 1.3, "Survival": 1,
                  "Commerce": 2.5}
FEED_BASE, FEED_PER_LEVEL = 10, 0.1
KEEP_LEVELS = False  # 2026-10-18 review: tried keeping levels -> runaway; levels reset
UP_COST_REBIRTH_SCALED = False
CAP_PER_REBIRTH = 0  # >0: level cap grows per rebirth instead of per tier
NW_COUNTS_LEVELS = True  # net worth includes cash spent on pedestal levels
CRATE_NEAR_FLOOR_ONLY = False  # crates may replace any unmutated core below their top rarity
CRATE_EV_RULE = True  # crate replaces the weakest core whose income is below the crate's expected income
COMPOST_SECONDS = 20
UPGRADE_UNLOCK_CULT = 10  # pedestal upgrades unlock at Cultivation 10
CRATE_SECONDS = {"Fertile": 60, "Ancient": 300, "Mythic": 900, "Cosmic": 1800}
COMMERCE_FLAT, COMMERCE_SCALE = 5, 40
HATCH = 60
MUT_INTERVAL, MUT_DAY, MUT_NIGHT = 300, 0.02, 0.04
DAY, NIGHT = 240, 120
LEVEL_XP_FACTOR = 0.03
XP = dict(harvest=20, plant=5, feed=15, hatch=[10, 25, 60, 150, 400, 1100, 3000, 8000, 22000, 60000],
          mut_roll=3, mut={"Gold": 100, "Void": 400, "Celestial": 1500}, infuse=40, rip=120, secure_tier=80,
          night=250, streak=15, outside=1.5, night_def=40, commerce_base=10, quest=200, daily=250)
INFUSE_SECONDS, INFUSE_BASE = 90, 0.12
# skill tracks (stat, per, every)
TRACKS = {
    "Foraging": [("doubleSeed", .006, 3), ("harvestCash", 1, 3)],
    "Cultivation": [("hatchSpeed", .0075, 3), ("rarityLuck", .015, 3)],
    "Alchemy": [("mutationChance", .02, 3), ("infuseChance", .005, 3)],
    "Thievery": [("carrySpeed", .01, 3), ("ripSpeed", .01, 3)],
    "Guarding": [("defenseDamage", .02, 3), ("trapRecharge", .01, 3)],
    "Survival": [("maxHealth", 2, 3), ("nightIncome", .01, 3)],
    "Commerce": [("discount", .003, 3), ("income", .005, 3)],
}
SEEDBAG_LEVELS = [10, 25, 40, 55, 70, 85, 99]
TREE = {  # id: (stat, per, costs)
    "GoldenTouch": ("income", .05, [1, 1, 1, 1, 1, 2, 2, 2, 2, 2]),
    "Expansion": ("pedestalSlots", 1, [2, 3, 4, 5]),
    "LuckyRoots": ("rarityLuck", .05, [1, 1, 1, 1, 1, 2, 2, 2, 2, 2]),
    "QuickSprouts": ("hatchSpeed", .03, [1, 1, 1, 1, 1, 2, 2, 2, 2, 2]),
    "UnstableSoil": ("mutationChance", .05, [1, 1, 1, 1, 1, 2, 2, 2, 2, 2]),
    "Scholar": ("xpBoost", .03, [1, 1, 1, 1, 1, 2, 2, 2, 2, 2]),
    "NestEgg": ("startCash", 1, [1, 1, 2, 2, 3]),
}
SKILLS = list(TRACKS)

# ---- RuneScape XP table -----------------------------------------------------
XP_FOR = [0, 0]
_points = 0
for n in range(1, 99):
    _points += math.floor(n + 300 * 2 ** (n / 7))
    XP_FOR.append(math.floor(_points / 4))


def level_for(xp):
    lo, hi = 1, 99
    while lo < hi:
        mid = (lo + hi + 1) // 2
        if XP_FOR[mid] <= xp:
            lo = mid
        else:
            hi = mid - 1
    return lo


class Player:
    def __init__(self, seed=1):
        self.rng = random.Random(seed)
        self.t = 0.0
        self.cash = 0.0
        self.rebirths = 0
        self.tokens = 0
        self.tree = {k: 0 for k in TREE}
        self.xp = {s: 0.0 for s in SKILLS}
        self.index = set()
        self.peds = [self.new_ped()]  # dicts: rarity, mut, cycles, level, hatch_at, mprog
        self.seeds = 0
        self.purchases = []  # timestamps
        self.streak = 0
        self.rebirth_times = []
        self.first99 = None
        self.pre_income = None
        self.recover_from = 0
        self.recoveries = []
        self.kinds = {}

    @staticmethod
    def new_ped():
        return {"rarity": None, "mut": None, "cycles": 0, "level": 1, "hatch_at": None, "mprog": 0.0, "crate": None}

    # -- stats --
    def lvl(self, s):
        return level_for(self.xp[s])

    def stats(self):
        st = {}
        for s, tracks in TRACKS.items():
            L = self.lvl(s)
            for stat, per, every in tracks:
                st[stat] = st.get(stat, 0) + (L // every) * per
        st["seedBag"] = sum(1 for lv in SEEDBAG_LEVELS if self.lvl("Foraging") >= lv)
        for k, (stat, per, _) in TREE.items():
            st[stat] = st.get(stat, 0) + per * self.tree[k]
        st["income"] = st.get("income", 0) + 0.01 * len(self.index)
        return st

    def reb_mult(self, n=None):
        return REB_INCOME ** (self.rebirths if n is None else n)

    def discounted(self, price, st):
        return price * (1 - min(st.get("discount", 0), 0.3))

    def add_xp(self, skill, base, st):
        L = self.lvl(skill)
        self.xp[skill] += base * SKILL_XP_SCALE[skill] * (1 + LEVEL_XP_FACTOR * (L - 1)) * (1 + st.get("xpBoost", 0))
        if self.first99 is None and self.lvl(skill) >= 99:
            self.first99 = (skill, self.t)

    def commerce(self, price, st, income):
        # XP scales with how big the purchase is relative to income (no spam farming)
        self.add_xp("Commerce", COMMERCE_FLAT + COMMERCE_SCALE * min(1, price / max(income * 60, 1)), st)
        self.purchases.append(self.t)

    # -- economy --
    def core_rate(self, p):
        if p["rarity"] is None or p["hatch_at"] is not None:
            return 0
        m = MUT[p["mut"]][0] if p["mut"] else 1
        return RATE[p["rarity"]] * (1 + CYCLE_BONUS * p["cycles"]) * m * UP_INCOME_MULT ** (p["level"] - 1)

    def income(self, st, night):
        base = sum(self.core_rate(p) for p in self.peds)
        return base * self.reb_mult() * (1 + st.get("income", 0)) * (1 + (st.get("nightIncome", 0) if night else 0))

    def unlocked(self, r):
        gate = UNLOCK.get(r)
        return gate is None or (self.rebirths // TIER_EVERY >= gate[0] and self.lvl("Cultivation") >= gate[1])

    def roll(self, odds, luck):
        lowest = min(TIER[r] for r, c in odds.items() if c > 0)
        w = {r: c * (1 + luck) if TIER[r] > lowest else c for r, c in odds.items()}
        x = self.rng.random() * sum(w.values())
        pick = None
        for r in ORDER:
            if w.get(r, 0) > 0:
                pick = r
                x -= w[r]
                if x < 0:
                    break
        i = ORDER.index(pick)
        while i > 0 and not self.unlocked(ORDER[i]):
            i -= 1
        return ORDER[i]

    def net_worth(self):
        lv = sum(p.get("spent", 0) for p in self.peds) if NW_COUNTS_LEVELS else 0
        return self.cash + lv + sum(NETWORTH[p["rarity"]] for p in self.peds if p["rarity"])

    def cap(self):
        if CAP_PER_REBIRTH:
            return min(CAP_BASE + CAP_PER_REBIRTH * self.rebirths, CAP_MAX)
        return min(CAP_BASE + CAP_TIER * (self.rebirths // TIER_EVERY), CAP_MAX)

    def up_cost(self, slot, level):
        scale = self.reb_mult() if UP_COST_REBIRTH_SCALED else 1
        return UP_BASE * UP_GROWTH ** (level - 1) * (1 + UP_SLOT_STEP * (slot - 1)) * scale

    # -- one step of play --
    def step(self, dt, st):
        cyc = self.t % (DAY + NIGHT)
        night = cyc >= DAY
        inc = self.income(st, night)
        self.cash += inc * dt
        if self.pre_income is not None and self.income(st, False) >= self.pre_income:
            self.recoveries.append((self.t - self.recover_from) / 60)
            self.pre_income = None
        # harvest: one seed every ~12 s of active play when the bag has room
        bag = 3 + st.get("seedBag", 0)
        if self.rng.random() < dt / 12 and self.seeds < bag:
            self.seeds += 1
            if self.rng.random() < st.get("doubleSeed", 0) and self.seeds < bag:
                self.seeds += 1
            self.cash += inc * st.get("harvestCash", 0)
            self.add_xp("Foraging", XP["harvest"], st)
        # plant / feed one seed per step
        if self.seeds > 0:
            empty = [p for p in self.peds if p["rarity"] is None and p["hatch_at"] is None]
            if empty:
                p = empty[0]
                p["hatch_at"] = self.t + HATCH * (1 - min(st.get("hatchSpeed", 0), 0.6))
                p["crate"] = None
                self.seeds -= 1
                self.add_xp("Cultivation", XP["plant"], st)
            else:
                fed = [p for p in self.peds if p["rarity"] and p["hatch_at"] is None
                       and p["cycles"] < FEED_BASE + int(FEED_PER_LEVEL * p["level"])]
                if fed:
                    min(fed, key=lambda p: p["cycles"])["cycles"] += 1
                    self.seeds -= 1
                    self.add_xp("Cultivation", XP["feed"], st)
                else:  # compost: every core fully fed
                    self.seeds -= 1
                    self.cash += inc / max(1, len(self.peds)) * COMPOST_SECONDS
                    self.add_xp("Cultivation", XP["feed"], st)
        # hatch + mutation rolls
        for p in self.peds:
            if p["hatch_at"] is not None and self.t >= p["hatch_at"]:
                odds = dict(next(c[3] for c in CRATES if c[0] == p["crate"])) if p["crate"] else \
                    {r[0]: r[1] for r in RARITIES if r[1] > 0}
                r = self.roll(odds, st.get("rarityLuck", 0))
                p.update(rarity=r, mut=None, hatch_at=None, cycles=p["cycles"] + 1, mprog=0)
                self.index.add(r)
                self.add_xp("Cultivation", XP["hatch"][TIER[r] - 1], st)
            if p["rarity"] and p["hatch_at"] is None:
                p["mprog"] += dt
                if p["mprog"] >= MUT_INTERVAL:
                    p["mprog"] -= MUT_INTERVAL
                    self.add_xp("Alchemy", XP["mut_roll"] * TIER[p["rarity"]], st)
                    ch = (MUT_NIGHT if night else MUT_DAY) * (1 + st.get("mutationChance", 0))
                    if self.rng.random() < ch:
                        m = self.rng.choices(list(MUT), [v[1] for v in MUT.values()])[0]
                        if not p["mut"] or MUT[m][0] > MUT[p["mut"]][0]:
                            p["mut"] = m
                            self.index.add(p["rarity"] + "+" + m)
                            self.add_xp("Alchemy", XP["mut"][m], st)
        # infuse: ~15% of income on the cheapest core (Alchemy training)
        if self.rng.random() < dt / 75:
            cores = [p for p in self.peds if p["rarity"] and p["hatch_at"] is None and p["mut"] != "Celestial"]
            if cores:
                p = min(cores, key=self.core_rate)
                price = self.discounted(max(100, self.core_rate(p) * self.reb_mult() * INFUSE_SECONDS), st)
                if self.cash >= price * 4:
                    self.cash -= price
                    self.add_xp("Alchemy", XP["infuse"] + 10 * TIER[p["rarity"]], st)
                    if self.rng.random() < INFUSE_BASE + st.get("infuseChance", 0):
                        m = self.rng.choices(list(MUT), [v[1] for v in MUT.values()])[0]
                        if not p["mut"] or MUT[m][0] > MUT[p["mut"]][0]:
                            p["mut"] = m
                            self.index.add(p["rarity"] + "+" + m)
        # nights: survival + guarding at night end
        if cyc < dt and self.t > 0:
            self.streak += 1
            self.add_xp("Survival", XP["night"] + XP["streak"] * min(self.streak, 20), st)
            self.add_xp("Guarding", XP["night_def"] * 4, st)  # 4 defenses owned
        if night:
            self.add_xp("Survival", XP["outside"] * dt * 0.4, st)
        # thievery: one raid every ~10 min in a populated server
        if self.rng.random() < dt / 600:
            self.add_xp("Thievery", XP["rip"] + XP["secure_tier"] * 3, st)
        # quests + daily (~1.5 h/day of play): ~3 claims per 1.5 h
        if self.rng.random() < dt / 1800:
            self.add_xp("Commerce", XP["quest"], st)
        self.shop(st)

    def shop(self, st):
        # rebirth first when ready
        if self.net_worth() >= REB_REQ * REB_REQ_GROWTH ** self.rebirths:
            self.rebirth_times.append(self.t)
            self.pre_income = self.income(st, False)
            self.recover_from = self.t
            self.rebirths += 1
            self.tokens += 1 + (1 if self.rebirths % 5 == 0 else 0)
            nest = self.tree["NestEgg"]
            self.cash = 1000 * 4 ** (nest - 1) * self.reb_mult() if nest else 0
            for p in self.peds:
                if not KEEP_LEVELS:
                    p["level"] = 1
                    p["spent"] = 0
                if p["rarity"] and TIER[p["rarity"]] < 4 and not p["mut"]:
                    p.update(rarity=None, mut=None, cycles=0)
            self.purchases.append(self.t)
            return
        # tree
        for k in TREE:
            costs = TREE[k][2]
            lv = self.tree[k]
            if lv < len(costs) and self.tokens >= costs[lv]:
                self.tokens -= costs[lv]
                self.tree[k] += 1
                break
        # cheapest of: pedestal, upgrade, crate
        options = []
        max_ped = 8 + st.get("pedestalSlots", 0)
        if len(self.peds) < max_ped:
            options.append((self.discounted(PEDESTAL_PRICES[len(self.peds) - 1], st), "ped", None))
        cap = self.cap() if self.lvl("Cultivation") >= UPGRADE_UNLOCK_CULT else 0
        # value-based: best income gain per dollar, cores only (UPGRADE ALL rule)
        best = None
        for i, p in enumerate(self.peds):
            if p["level"] < cap and p["rarity"] and p["hatch_at"] is None:
                c = self.discounted(self.up_cost(i + 1, p["level"]), st)
                v = self.core_rate(p) * (UP_INCOME_MULT - 1) / c
                if best is None or v > best[0]:
                    best = (v, c, p)
        if best:
            options.append((best[1], "up", best[2]))
        cult = self.lvl("Cultivation")
        income_now = self.income(st, False)
        for cid, price, need, odds in CRATES:
            if cult >= need:
                top_tier = max(TIER[r] for r in odds)
                if CRATE_EV_RULE:
                    tot = sum(odds.values())
                    ev_base = sum(RATE[r] * w for r, w in odds.items()) / tot

                    def ev(p):
                        return ev_base * (1 + CYCLE_BONUS * p["cycles"]) * UP_INCOME_MULT ** (p["level"] - 1)
                    weak = [p for p in self.peds if p["rarity"] and p["hatch_at"] is None
                            and TIER[p["rarity"]] < top_tier and self.core_rate(p) < ev(p)]
                else:
                    weak = [p for p in self.peds if p["rarity"] and p["hatch_at"] is None and not p["mut"]
                            and TIER[p["rarity"]] < top_tier]
                # crates only worth it on a core weaker than the crate's average roll
                floor_tier = min(TIER[r] for r in odds)
                if CRATE_NEAR_FLOOR_ONLY:
                    weak = [p for p in weak if TIER[p["rarity"]] <= floor_tier + 1]
                if weak:
                    cost = max(price * self.reb_mult(), income_now * CRATE_SECONDS[cid])
                    options.append((self.discounted(cost, st), "crate", (cid, weak)))
        if not options:
            return
        price, kind, arg = min(options, key=lambda o: o[0])
        if self.cash < price:
            return
        self.cash -= price
        self.commerce(price, st, self.income(st, False))
        self.kinds[kind] = self.kinds.get(kind, 0) + 1
        if kind == "ped":
            self.peds.append(self.new_ped())
        elif kind == "up":
            arg["level"] += 1
            arg["spent"] = arg.get("spent", 0) + price
        else:
            cid, weak = arg
            p = min(weak, key=self.core_rate)
            p.update(rarity=None, mut=None, hatch_at=self.t + HATCH * (1 - min(st.get("hatchSpeed", 0), .6)),
                     crate=cid, mprog=0)


def fmt(n):
    if n >= 1e36:
        return f"{n:.2e}"
    for suffix, value in (("Dc", 1e33), ("No", 1e30), ("Oc", 1e27), ("Sp", 1e24), ("Sx", 1e21), ("Qi", 1e18),
                          ("Qa", 1e15), ("T", 1e12), ("B", 1e9), ("M", 1e6), ("K", 1e3)):
        if n >= value:
            return f"{n / value:.2f}{suffix}"
    return f"{n:.0f}"


def main():
    hours = float(sys.argv[1]) if len(sys.argv) > 1 else 300
    pl = Player()
    dt = 5
    checkpoints = [0.083, 0.25, 0.5, 1, 2, 5, 10, 20, 50, 100, 200, 300, 500, 800, 1200, 1700, 2500]
    nxt = 0
    print("hours | rebirths | income/s | gap(min) | total | " + " ".join(s[:4] for s in SKILLS))
    while pl.t < hours * 3600:
        st = pl.stats()
        for _ in range(12):  # recompute stats once a minute (cheap)
            pl.step(dt, st)
            pl.t += dt
        h = pl.t / 3600
        if nxt < len(checkpoints) and h >= checkpoints[nxt]:
            recent = [x for x in pl.purchases if x > pl.t - 3600 * max(0.25, h * 0.1)]
            gaps = [b - a for a, b in zip(recent, recent[1:])]
            gap = (sorted(gaps)[len(gaps) // 2] / 60) if gaps else float("nan")
            levels = [pl.lvl(s) for s in SKILLS]
            print(f"{h:7.2f} | {pl.rebirths:8d} | {fmt(pl.income(st, False)):>8} | {gap:8.1f} | {sum(levels):5d} | "
                  + " ".join(f"{lv:4d}" for lv in levels))
            nxt += 1
    if pl.recoveries:
        print("minutes to regain pre-rebirth income:", " ".join(f"{m:.1f}" for m in pl.recoveries[:40]))
    print("purchases by kind:", pl.kinds)
    if pl.first99:
        print(f"first 99: {pl.first99[0]} at {pl.first99[1] / 3600:.0f} h")
    reb = pl.rebirth_times
    if len(reb) > 1:
        gaps = [(b - a) / 3600 for a, b in zip(reb, reb[1:])]
        print("rebirth durations (h):", " ".join(f"{g:.1f}" for g in gaps[:40]))


if __name__ == "__main__":
    main()
