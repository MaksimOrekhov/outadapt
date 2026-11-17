"""PRO-192: проверка вариантов по порогам docs/balance/late-game-pressure.md §5 (P1, P2, G1–G6).
Из папки godot: python tests/late_thresholds.py ../build/late base dense budget econ  (первый тег — база)"""
import sys, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from late_report import load, summarize, mean

root = sys.argv[1]
tags = sys.argv[2:]
S = {t: summarize(load(os.path.join(root, t))) for t in tags}
STRATS = ["owner2", "mixed", "adaptive", "owner"]

def ph(s, key, p, kind, m):
    return s[key]["phases"].get((p, kind), {}).get(m, (float("nan"), 0))[0]

def pooled(s, p, kind, m, filt=lambda k: k[3] == "ws0", w=False):
    # среднее по ячейкам (как в §3: среднее средних)
    vals = [ph(s, k, p, kind, m) for k in s if filt(k)]
    vals = [v for v in vals if v == v]
    return mean(vals)

def win(s, filt):
    return mean([s[k]["win30"] for k in s if filt(k)])

def boss_leaks(s, w, filt=lambda k: k[3] == "ws0"):
    # утечки на боссовых волнах 20 / 30 (фазы 11-20 boss = волна 20; 30 boss = волна 30)
    p = "11-20" if w == 20 else "30"
    return pooled(s, p, "boss", "leaks", filt)

out = []
for t in tags:
    s = S[t]
    r = {}
    r["P1 gate20 21-29"] = pooled(s, "21-29", "normal", "gate20")
    r["P2 p90 21-29"] = pooled(s, "21-29", "normal", "p90")
    r["G1 gate20 1-10"] = pooled(s, "1-10", "normal", "gate20")
    r["G1 leaks 1-10"] = pooled(s, "1-10", "normal", "leaks")
    r["G2 mixed normal win30"] = win(s, lambda k: k[0] == "mixed" and k[1] == "normal" and k[3] == "ws0")
    r["G2 adaptive normal win30"] = win(s, lambda k: k[0] == "adaptive" and k[1] == "normal" and k[3] == "ws0")
    r["G3 leaks 21-29"] = pooled(s, "21-29", "normal", "leaks")
    r["G3 mixed normal leaks 21-29"] = pooled(s, "21-29", "normal", "leaks", lambda k: k[0] == "mixed" and k[1] == "normal" and k[3] == "ws0")
    r["G4 mixed hard ws1 win30"] = win(s, lambda k: k[0] == "mixed" and k[3] == "ws1")
    r["G4 owner2 hard ws1 win30"] = win(s, lambda k: k[0] == "owner2" and k[3] == "ws1")
    r["G5 boss20 leaks"] = boss_leaks(s, 20)
    r["G5 boss30 leaks"] = boss_leaks(s, 30)
    for st in STRATS:
        r[f"G6 gate20 21-29 {st}"] = pooled(s, "21-29", "normal", "gate20", lambda k, st=st: k[0] == st and k[3] == "ws0")
    r["11-20 gate20"] = pooled(s, "11-20", "normal", "gate20")
    r["21-29 ttk"] = pooled(s, "21-29", "normal", "ttk")
    r["hard ws0 win30"] = win(s, lambda k: k[1] == "hard" and k[3] == "ws0")
    r["normal ws0 win30"] = win(s, lambda k: k[1] == "normal" and k[3] == "ws0")
    r["special 21-29 gate20"] = pooled(s, "21-29", "special", "gate20")
    r["special 21-29 leaks"] = pooled(s, "21-29", "special", "leaks")
    out.append(r)

keys = list(out[0].keys())
print("| metric | " + " | ".join(tags) + " |")
print("|---|" + "---|" * len(tags))
for k in keys:
    print(f"| {k} | " + " | ".join(f"{o[k]:.3f}" for o in out) + " |")

# вердикт
b = out[0]
for t, o in zip(tags[1:], out[1:]):
    v = {
        "P1": o["P1 gate20 21-29"] <= 0.46,
        "P2": o["P2 p90 21-29"] >= 0.40,
        "G1": abs(o["G1 gate20 1-10"] - b["G1 gate20 1-10"]) <= 0.01 and abs(o["G1 leaks 1-10"] - b["G1 leaks 1-10"]) <= 0.01,
        "G2": b["G2 mixed normal win30"] - o["G2 mixed normal win30"] <= 0.10 and b["G2 adaptive normal win30"] - o["G2 adaptive normal win30"] <= 0.10,
        "G3": o["G3 leaks 21-29"] <= 0.30 and o["G3 mixed normal leaks 21-29"] <= 0.30,
        "G4": o["G4 mixed hard ws1 win30"] >= 0.80 and o["G4 owner2 hard ws1 win30"] >= 0.50,
        "G5": o["G5 boss20 leaks"] - b["G5 boss20 leaks"] <= 0.5 and o["G5 boss30 leaks"] - b["G5 boss30 leaks"] <= 0.5,
        "G6": all(b[f"G6 gate20 21-29 {st}"] - o[f"G6 gate20 21-29 {st}"] >= 0.10 for st in STRATS),
    }
    print(t, " ".join(f"{k}:{'OK' if x else 'FAIL'}" for k, x in v.items()), "=> PASS" if all(v.values()) else "=> fail")
