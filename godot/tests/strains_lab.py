#!/usr/bin/env python3
"""PRO-152: сводка лаборатории пакетов. Каждый файл <оборона>_<пакет>_<семейство>.jsonl — замороженная политика
(--replay) с принудительной долей пакета с волны 8 (--lab-strain=пакет:1.0:8) или без пакета (none, observe).
Печатает по волнам 8–16: p90 дистанции гибели (земля/воздух), утечки, потерянные жизни, суммарное HP волны.

python tests/strains_lab.py <каталог> [волна_от=8] [волна_до=16]
"""
import glob
import json
import os
import sys
from collections import defaultdict

d = sys.argv[1]
w_from = int(sys.argv[2]) if len(sys.argv) > 2 else 8
w_to = int(sys.argv[3]) if len(sys.argv) > 3 else 16
agg = defaultdict(lambda: defaultdict(list))
for f in glob.glob(os.path.join(d, "*_*_*.jsonl")):
    base = os.path.basename(f)[:-6]
    if base.startswith("rec_"):
        continue
    defense, pack, fam = base.split("_")
    for line in open(f, encoding="utf-8"):
        r = json.loads(line)
        for x in r["waves"]:
            if w_from <= x["w"] <= w_to and x["w"] != 10:
                agg[(defense, pack)]["p90"].append(1.5 if x.get("lost") else max(x.get("prog_g", [0, 1.5])[1], x.get("prog_a", [0, 0])[1]))
                agg[(defense, pack)]["lives"].append(x.get("lives_lost", x.get("lives0", 0)))
                agg[(defense, pack)]["hp"].append(x.get("sx", {}).get("wave_hp", 0))
                agg[(defense, pack)]["life"].append(max(x.get("life_g", [0])[0], 0))
sys.stdout.reconfigure(encoding="utf-8")
print(f"волны {w_from}–{w_to} без 10-й; среднее на волну")
print("| оборона | пакет | p90 гибели | жизни −/волну | время жизни, с | HP волны |")
print("|---|---|---|---|---|---|")
for key in sorted(agg):
    a = agg[key]
    m = lambda k: sum(a[k]) / len(a[k])
    print(f"| {key[0]} | {key[1]} | {m('p90'):.3f} | {m('lives'):.2f} | {m('life'):.1f} | {m('hp'):.0f} |")
