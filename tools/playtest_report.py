#!/usr/bin/env python3
"""Summarise a playtest .jsonl (default: newest in the Godot user folder). Usage: playtest_report.py [file]"""
import glob, json, os, sys
d = os.path.expanduser("~/Library/Application Support/Godot/app_userdata/TheLastFireMage/playtests")
path = sys.argv[1] if len(sys.argv) > 1 else max(glob.glob(d + "/*.jsonl"), key=os.path.getmtime)
rows = [json.loads(l) for l in open(path)]
print(path)
for r in (x for x in rows if x["ev"] == "round_end"):
    print(f"\nRound {r['round']}: {r['winner']} won ({r['reason']}) after {r['round_seconds']}s")
    for p in r["players"]:
        print(f"  {p['name']:<12}{p['role']:<9}" + " ".join(f"{k}={v}" for k, v in p.items() if k not in ("id", "name", "role")))
    deaths = [x for x in rows if x["ev"] == "death" and x["round"] == r["round"]]
    print("  deaths at:", ", ".join(f"{x['name']}@{x['t']:.0f}s" for x in deaths) or "none")
    pw = [x for x in rows if x["ev"] == "power" and x["round"] == r["round"]]
    if pw:
        print(f"  mage power: start {pw[0]['power']} peak {max(x['power'] for x in pw)} end {pw[-1]['power']}")
