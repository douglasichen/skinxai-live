#!/usr/bin/env python3
"""Fetch a labelled test recording from the relay, replay it through the real detector, report per move.

usage: analyze.py [recording-id|latest] [ENV=VALUE ...]   (env goes to Tools/Replay: PRESET, GATE, THRESHOLD, MAXSTRENGTH, WEIGHTS)
"""
import csv, io, json, os, subprocess, sys, urllib.request, statistics as st

BASE = "https://eczema-twin-live.zhongzhenyu190.workers.dev"
HERE = os.path.dirname(os.path.abspath(__file__))
REPLAY = os.path.join(HERE, "..", "Replay", ".build", "release", "Replay")
OUT = "/tmp/et-tune"

def get(path):
    req = urllib.request.Request(BASE + path, headers={"user-agent": "curl/8 eczema-twin-tune"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)

def main():
    rid = sys.argv[1] if len(sys.argv) > 1 else "latest"
    extra = dict(a.split("=", 1) for a in sys.argv[2:])
    if rid == "latest":
        recs = [r for r in get("/api/recordings")["recordings"] if r["labels"] > 4]
        rid = recs[0]["rec_id"]
    os.makedirs(OUT, exist_ok=True)
    cache = f"{OUT}/{rid}.json"
    if not os.path.exists(cache) or extra.get("REFRESH"):
        data = get(f"/api/recording?id={rid}")
        json.dump(data, open(cache, "w"))
    data = json.load(open(cache))
    raw = {}
    for b in data["batches"]:
        for r in b.get("raw") or []:
            raw[r[0]] = r
    rows = [raw[k] for k in sorted(raw)]
    csvp = f"{OUT}/{rid}.csv"
    with open(csvp, "w") as f:
        f.write("t,x,y,z\n")
        for t, x, y, z in rows:
            f.write(f"{t - 978307200:.3f},{x},{y},{z}\n")   # back to the watch's reference-date seconds
    # steps from labels
    steps, cur = [], {}
    for l in data["labels"]:
        if l["action"] == "step" and l["phase"] == "start": cur[l["label"]] = l["t"]
        if l["action"] == "step" and l["phase"] == "end" and l["label"] in cur:
            steps.append((l["label"], cur.pop(l["label"]) - 978307200, l["t"] - 978307200))
    env = dict(os.environ, PRESET="live")
    env.update({k: v for k, v in extra.items() if k != "REFRESH"})
    out = subprocess.run([REPLAY, csvp], capture_output=True, text=True, env=env)
    wins = list(csv.DictReader(io.StringIO(out.stdout)))
    for w in wins:
        for k in w: w[k] = float(w[k])
    gaps = [b[0] - a[0] for a, b in zip(rows, rows[1:])]
    print(f"recording {rid}: {len(rows)} raw samples, {len(wins)} windows, max gap {max(gaps) if gaps else 0:.2f}s · env {extra or '-'}")
    print(f"{'move':16} {'wins':>4} {'flag%':>6} {'p_med':>6} {'p_max':>6} {'str_med':>8} {'str_max':>8} {'hz_med':>6} {'per_med':>7} {'band_med':>8}")
    for label, a, b in steps:
        ws = [w for w in wins if w["start"] >= a + 0.3 and w["start"] + 3.0 <= b + 0.6]
        if not ws: print(f"{label:16} no windows"); continue
        fl = sum(w["isScratch"] for w in ws) / len(ws) * 100
        med = lambda k: st.median(w[k] for w in ws)
        print(f"{label:16} {len(ws):>4} {fl:>5.0f}% {med('p'):>6.2f} {max(w['p'] for w in ws):>6.2f} {med('strength'):>8.3f} {max(w['strength'] for w in ws):>8.3f} {med('dominantHz'):>6.2f} {med('periodicity'):>7.2f} {med('inBand'):>8.2f}")
    json.dump({"steps": steps, "windows": wins}, open(f"{OUT}/{rid}.windows.json", "w"))

main()
