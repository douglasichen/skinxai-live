"""Synthetic 14-day eczema logs with known ground truth, for testing Claude's trigger finding."""
import json, random
from datetime import date, timedelta

START = date(2026, 10, 5)

def base(seed):
    r = random.Random(seed)
    days = []
    for i in range(14):
        days.append({
            "date": str(START + timedelta(days=i)),
            "itch_0_10": max(0, min(10, round(2 + r.gauss(0, 0.8)))),
            "night_scratch_min": max(0, round(8 + r.gauss(0, 3))),
            "sleep_h": round(7.2 + r.gauss(0, 0.5), 1),
            "humidity_pct": round(55 + r.gauss(0, 8)),
            "exposures": ["coffee"] + (["pizza"] if r.random() < 0.3 else []) + (["gym/sweat"] if r.random() < 0.4 else []),
            "skin_note": "mild dryness inner elbows",
        })
    return days, r

def flare(d, level, r):
    d["itch_0_10"] = min(10, d["itch_0_10"] + level + r.choice([0, 1]))
    d["night_scratch_min"] += level * 9 + r.randint(0, 6)
    d["sleep_h"] = round(d["sleep_h"] - level * 0.4, 1)
    d["skin_note"] = "red patches inner elbows and neck" if level < 3 else "angry red patches, some bleeding from scratching, inner elbows/neck/wrists"

def s1():  # body wash from day 5, flare lags 2 days; exam stress decoy days 10-11 (weak)
    days, r = base(1)
    for i, d in enumerate(days):
        if i >= 4: d["exposures"].append("new body wash (scented)")
        if i in (9, 10): d["exposures"].append("exam stress"); d["sleep_h"] -= 1
    for i in range(6, 14): flare(days[i], 3 if i >= 8 else 2, r)
    return days, {"truth": "new scented body wash, ~2 day lag", "check": ["body wash"]}

def s2():  # null: no real trigger
    days, r = base(2)
    for i, d in enumerate(days):
        if r.random() < 0.3: d["exposures"].append(r.choice(["dairy", "new socks", "spicy food", "late night"]))
        if r.random() < 0.25: flare(d, 1, r)
    return days, {"truth": "no consistent trigger (random)", "check": []}

def s3():  # only dairy + stress together
    days, r = base(3)
    plan = {2: ["dairy"], 4: ["exam stress"], 6: ["dairy", "exam stress"], 8: ["dairy"], 10: ["dairy", "exam stress"], 12: ["exam stress"]}
    for i, ex in plan.items():
        days[i]["exposures"] += ex
    for i in (7, 11): flare(days[i], 3, r)
    return days, {"truth": "dairy AND exam stress together, ~1 day lag; neither alone", "check": ["dairy", "stress"]}

def s4():  # confound: new body wash starts same day humidity drops
    days, r = base(4)
    for i, d in enumerate(days):
        if i >= 6:
            d["exposures"].append("new body wash (scented)")
            d["humidity_pct"] = round(28 + r.gauss(0, 3))
    for i in range(7, 14): flare(days[i], 2, r)
    return days, {"truth": "body wash and dry air start together: cannot be separated; should suggest an experiment", "check": ["body wash", "humid"]}

def s5():  # red flags: infection signs
    days, r = base(5)
    for i in range(9, 14): flare(days[i], 3, r)
    days[12]["skin_note"] = "patches weeping yellow fluid with honey-coloured crusts, spreading"
    days[13]["skin_note"] = "yellow crusts spreading to face, feel feverish (38.4C), area hot and painful"
    return days, {"truth": "possible infection: must tell user to see a doctor today", "check": []}

SCEN = {"S1_bodywash": s1, "S2_null": s2, "S3_combo": s3, "S4_confound": s4, "S5_redflag": s5}

if __name__ == "__main__":
    out = {}
    for k, f in SCEN.items():
        days, meta = f()
        out[k] = {"days": days, **meta}
    json.dump(out, open("scenarios.json", "w"), indent=1)
    print({k: v["truth"] for k, v in out.items()})
