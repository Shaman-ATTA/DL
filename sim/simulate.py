"""Dragonshard Legends economy simulator.
Plays the game for N days using the same formulas as scripts/economy.gd and data/balance.json.
Player model: several short active sessions per day (tapping ~5 taps/s, using skills),
offline earnings in between, greedy upgrade buying, prestige when progress stalls."""
import json, math, sys, os
C = json.load(open(os.path.join(os.path.dirname(__file__), "..", "data", "balance.json")))
TAPS = float(os.environ.get("TAPS", 5))
SESSIONS = [(8, 15), (12.5, 15), (17, 20), (21, 25)]  # (hour, minutes active)

def hp(s):
    L = C["late_growth_from_stage"]
    if s <= L: return C["enemy_hp_base"] * C["enemy_hp_growth"] ** (s - 1)
    return C["enemy_hp_base"] * C["enemy_hp_growth"] ** (L - 1) * C["enemy_hp_growth_late"] ** (s - L)

def comp_mult(l):
    m = 1.0
    for lv, x in C["companion_milestones"]:
        if l >= lv: m *= x
    last = C["companion_milestones"][-1][0]
    if l > last: m *= C["companion_milestone_repeat_mult"] ** ((l - last) // C["companion_milestone_repeat_every"])
    return m

class P:
    def __init__(s):
        s.art = {a["id"]: 0 for a in C["artifacts"]}; s.shards = 0; s.reset()
    def reset(s):
        s.gold = 0.0; s.hero = 1; s.comp = [0] * len(C["companions"])
        s.stage = 1 + s.artv("wings"); s.maxrun = s.stage
    def artv(s, i):
        a = next(a for a in C["artifacts"] if a["id"] == i); L = s.art[i]
        if a["effect"] in ("boss_time", "start_stage"): return a["per_level"] * L
        return a["per_level"] ** L
    def dps(s):
        t = sum(c["base_dps"] * l * comp_mult(l) for c, l in zip(C["companions"], s.comp))
        return t * s.artv("heart")
    def tap(s):
        h = C["hero"]; l = s.hero
        return (l * h["dmg_per_level"] * h["milestone_mult"] ** (l // h["milestone_every"]) * s.artv("gauntlet") * s.artv("heart")
                + s.dps() * h["dps_to_tap_share"])
    def skill_mults(s):
        # average uptime multipliers for unlocked skills
        tapm = dpsm = goldm = 1.0; extra_taps = 0.0; burst = 0.0; boss_bonus = 0.0
        for k in C["skills"]:
            if s.hero < k["unlock_level"]: continue
            up = k["duration"] / k["cooldown"] if k["cooldown"] else 0
            if k["id"] == "rage": tapm *= 1 + (k["power"] - 1) * up
            if k["id"] == "meteor": dpsm *= 1 + (k["power"] - 1) * up
            if k["id"] == "goldrain": goldm *= 1 + (k["power"] - 1) * up
            if k["id"] == "haste": extra_taps += k["power"] * up
            if k["id"] == "blade": burst += k["power"] / k["cooldown"]  # taps-equivalent per second
            if k["id"] == "ward": boss_bonus = k["power"]
        return tapm, dpsm, goldm, extra_taps, burst, boss_bonus
    def total_dps(s, active=True):
        tapm, dpsm, goldm, et, burst, _ = s.skill_mults()
        d = s.dps() * dpsm
        if active:
            tp = s.tap() * tapm
            crit = 1 + C["crit_chance"] * (C["crit_mult"] - 1)
            d += (TAPS + et + burst) * tp * crit
        return d
    def gold_kill(s, st, boss=False):
        g = hp(st) * C["gold_per_hp"] * s.artv("crown") * s.skill_mults()[2]
        return g * (C["boss_gold_mult"] if boss else 1)
    def buy(s):
        h = C["hero"]; bought = True
        while bought:
            bought = False; best = None
            base = s.total_dps()
            hc = h["base_cost"] * h["cost_growth"] ** s.hero
            s.hero += 1; gain = s.total_dps() - base; s.hero -= 1
            best = (gain / hc, hc, "h", -1)
            for i, c in enumerate(C["companions"]):
                cc = c["base_cost"] * C["companion_cost_growth"] ** s.comp[i]
                if cc > s.gold * 4: continue
                s.comp[i] += 1; gain = s.total_dps() - base; s.comp[i] -= 1
                if gain / cc > best[0]: best = (gain / cc, cc, "c", i)
            if best[1] <= s.gold:
                s.gold -= best[1]; bought = True
                if best[2] == "h": s.hero += 1
                else: s.comp[best[3]] += 1
    def shards_for(s, st):
        p = C["prestige"]
        return 0 if st < p["min_stage"] else int(p["base"] * p["growth"] ** (st - p["min_stage"]))
    def spend_shards(s):
        while True:
            opts = []
            for a in C["artifacts"]:
                L = s.art[a["id"]]
                if L >= a["max"]: continue
                cost = math.ceil(a["cost_base"] * a["cost_growth"] ** L)
                w = {"heart": 1.0, "gauntlet": 0.9, "crown": 0.9, "hourglass": 0.6, "moonwell": 0.4, "wings": 0.5}[a["id"]]
                opts.append((cost / w, cost, a["id"]))
            if not opts: return
            opts.sort(); _, cost, i = opts[0]
            if cost > s.shards: return
            s.shards -= cost; s.art[i] += 1

def run(days=30, verbose=True):
    p = P(); t = 0.0; log = []; runs = []; run_start = 0.0; last_new = 0.0
    longest_stall = 0
    for day in range(days):
        for hour, mins in SESSIONS:
            now = day * 86400 + hour * 3600
            # offline earnings since last session end
            if t > 0:
                off = min(now - t, C["offline_cap_hours"] * 3600)
                d = p.dps()
                kt = max(C["respawn_delay"], hp(p.stage) / max(d, 1e-9))
                p.gold += off * C["offline_gold_factor"] * p.artv("moonwell") * p.gold_kill(p.stage) / kt
                p.buy()
            t = now; end = now + mins * 60
            while t < end:
                st = p.stage; D = p.total_dps()
                kt = max(C["respawn_delay"], hp(st) / D)
                n = C["enemies_per_stage"]
                t += kt * n; p.gold += p.gold_kill(st) * n
                bt = hp(st) * C["boss_hp_mult"] / D
                limit = C["boss_time"] + p.artv("hourglass") + p.skill_mults()[5]
                if bt <= limit:
                    t += max(bt, C["respawn_delay"]); p.gold += p.gold_kill(st, True); p.stage += 1
                    if p.stage > p.maxrun: p.maxrun = p.stage; last_new = t
                else:
                    t += limit
                p.buy()
                stall = t - last_new
                if stall > 8 * 60 and p.maxrun >= C["prestige"]["min_stage"]:
                    sh = p.shards_for(p.maxrun)
                    runs.append(dict(day=round(t / 86400, 2), stage=p.maxrun, shards=sh, hours=round((t - run_start) / 3600, 2), hero=p.hero, comps=list(p.comp)))
                    p.shards += sh; p.spend_shards(); p.reset(); run_start = t; last_new = t
            # session end
    return p, runs

if __name__ == "__main__":
    days = int(sys.argv[1]) if len(sys.argv) > 1 else 30
    p, runs = run(days)
    for i, r in enumerate(runs[:200]):
        print(f"run {i+1:3d}: day {r['day']:6.2f}  max stage {r['stage']:4d}  shards +{r['shards']:5d}  wall-clock {r['hours']:6.2f} h  hero lv {r['hero']}")
    print("final artifacts:", p.art, "current stage", p.stage)
    json.dump(runs, open(os.path.join(os.path.dirname(__file__), "runs.json"), "w"), indent=1)
