#!/usr/bin/env python3
"""PRO-213: боты на сгенерированных развилках против одиночных карт тех же сидов.

  python tests/fork_report.py [--fork=../build/fork/matrix] [--base=../build/range/base] [--md=out.md] [--csv=out.csv]

Развилки — tests/fork_matrix.sh (fork_even, fork_skew); база — ячейки PRO-212 без флага и Мастерской
(tests/range_matrix.sh base: snake, vsnake, stairs, hooks), те же 4 стратегии, normal/hard, сиды (i+1)·4243.
Обычные волны (не особые и не боссовые), волна учитывается, если сыграна и не проиграна.
  win30        доля побед к 30-й волне;
  gate20/p90   доля наземных врагов, убитых в первых 20% своей дороги / 90-й перцентиль пройденной доли своей дороги;
  max, b40     максимум пройденной доли за волну и доля дальше 40% пути;
  утечки       прорывы обычных врагов на волну 1–29; боссовые волны — отдельно (утечки на 20-й);
  по дорогам   «короткая/длинная» — по длине дороги (на fork_even почти равны); утечки и gate20 21–29 по дороге,
               cov20 — доля первых 20% дороги, которую достаёт хоть одна наземная башня (волны 21–29);
  вложено      золото в башни к 20-й и 29-й волне (сколько денег у обороны).
Среднее — по партиям группы, затем по группам (как в PRO-192), группы — стратегия × сложность.
"""
import json, os, sys, glob, csv
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))


def load(folder, families):
    out = []
    for f in sorted(glob.glob(os.path.join(folder, "*.jsonl"))):
        name = os.path.basename(f)[:-6]
        if not name.endswith("_ws0") or "_off_" not in name:
            continue
        strat, diff = name.split("_")[:2]
        fam = name.split("_off_")[1][:-4]
        if fam not in families:
            continue
        for line in open(f, encoding="utf-8"):
            if line.strip():
                try:
                    out.append((strat, diff, fam, json.loads(line)))
                except json.JSONDecodeError:
                    print(f"ВНИМАНИЕ: недописанная строка в {name}", file=sys.stderr)
    return out


def kind(wr):
    return "boss" if wr["w"] % 10 == 0 else ("special" if wr.get("special") else "normal")


def mean(a):
    a = [x for x in a if x is not None and x == x]
    return sum(a) / len(a) if a else float("nan")


def game_row(g):
    s = g["summary"]
    late = [w for w in g["waves"] if w.get("done") and not w.get("lost") and kind(w) == "normal" and 21 <= w["w"] <= 29]
    early = [w for w in g["waves"] if w.get("done") and not w.get("lost") and kind(w) == "normal" and w["w"] <= 29]
    row = {
        "seed": g["seed"], "family": g["family"], "won30": 1.0 if s["won30"] else 0.0, "end_wave": s["end_wave"],
        "reached21": 1.0 if late else 0.0,
        "gate20": mean([w["kill_g"][1] for w in late if w.get("kill_g") and w["kill_g"][2] > 0]),
        "p90": mean([w["prog_g"][1] for w in late if w.get("prog_g") and w["prog_g"][2] > 0]),
        "max": mean([w.get("max_g") for w in late if w.get("max_g", -1) >= 0]),
        "b40": mean([w.get("beyond40") for w in late]),
        "cov20": mean([w.get("cov20") for w in late]),
        "leaks": mean([w.get("leaked", 0) for w in early]),
        "boss20": next((w.get("lives_lost", 0) for w in g["waves"] if w["w"] == 20 and w.get("done")), None),
        "inv20": next((w.get("invested") for w in g["waves"] if w["w"] == 20 and w.get("done")), None),
        "inv29": next((w.get("invested") for w in g["waves"] if w["w"] == 29 and w.get("done")), None),
    }
    rt = g.get("routes")
    if rt:
        lens = rt["len"]
        short = 0 if lens[0] <= lens[1] else 1
        for tag, rid in (("short", short), ("long", 1 - short)):
            ws = [w["routes"].get(str(rid)) for w in early if w.get("routes")]
            wl = [w["routes"].get(str(rid)) for w in late if w.get("routes")]
            row[f"leaks_{tag}"] = mean([x["leaked"] for x in ws if x])
            row[f"gate20_{tag}"] = mean([x["gate20"] for x in wl if x and x["n"] > 0])
            row[f"p90_{tag}"] = mean([x["p90"] for x in wl if x and x["n"] > 0])
            row[f"cov20_{tag}"] = mean([w.get("cov20_routes", {}).get(str(rid)) for w in late])
        row["len_short"], row["len_long"] = min(lens), max(lens)
        row["shared_in"] = rt["shared_in"]
    if g.get("fork_fallback"):
        row["fallback"] = 1
    return row


def pooled(rows, key, filt=lambda s, d, fa: True):
    grp = defaultdict(list)
    for (strat, diff, fam, r) in rows:
        if filt(strat, diff, fam):
            grp[(strat, diff)].append(r.get(key))
    return mean([mean(v) for v in grp.values()])


def f(x, n=2):
    return "—" if x != x else f"{x:.{n}f}"


def main():
    opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    fork_dir = opts.get("fork", os.path.join(HERE, "..", "..", "build", "fork", "matrix"))
    base_dir = opts.get("base", os.path.join(HERE, "..", "..", "build", "range", "base"))
    forks = [(s, d, fam, game_row(g)) for s, d, fam, g in load(fork_dir, {"fork_even", "fork_skew"})]
    base = [(s, d, fam, game_row(g)) for s, d, fam, g in load(base_dir, {"snake", "vsnake", "stairs", "hooks"})]
    out = []
    out.append("### Развилки против одиночных карт (боты, те же сиды и стратегии)\n")
    out.append("| Карты | партий | win30 normal | win30 hard | дожили до 21-й | gate20 21–29 | p90 21–29 | max 21–29 | дальше 40% | cov20 | утечек на волну 1–29 | потеря жизней на 20-й | вложено к 20-й / 29-й |")
    out.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|")
    sets = [("одиночные (4 семейства)", base), ("fork_even", [x for x in forks if x[2] == "fork_even"]), ("fork_skew", [x for x in forks if x[2] == "fork_skew"])]
    for label, rows in sets:
        out.append(f"| {label} | {len(rows)} | {f(pooled(rows, 'won30', lambda s, d, fa: d == 'normal'))} | {f(pooled(rows, 'won30', lambda s, d, fa: d == 'hard'))} | "
                   f"{f(pooled(rows, 'reached21'))} | {f(pooled(rows, 'gate20'))} | {f(pooled(rows, 'p90'))} | {f(pooled(rows, 'max'))} | {f(pooled(rows, 'b40'))} | "
                   f"{f(pooled(rows, 'cov20'))} | {f(pooled(rows, 'leaks'))} | {f(pooled(rows, 'boss20'))} | {f(pooled(rows, 'inv20'), 0)} / {f(pooled(rows, 'inv29'), 0)} |")
    out.append("\n### По стратегиям: win30 normal / hard\n")
    out.append("| Стратегия | одиночные | fork_even | fork_skew |")
    out.append("|---|---|---|---|")
    for st in ["owner2", "mixed", "adaptive", "owner"]:
        cells = []
        for label, rows in sets:
            cells.append(f"{f(pooled(rows, 'won30', lambda s, d, fa, st=st: s == st and d == 'normal'))} / {f(pooled(rows, 'won30', lambda s, d, fa, st=st: s == st and d == 'hard'))}")
        out.append(f"| {st} | " + " | ".join(cells) + " |")
    out.append("\n### По дорогам развилки (короткая / длинная)\n")
    out.append("| Карты | длина, клеток | утечек на волну 1–29 | gate20 21–29 | p90 21–29 | cov20 21–29 |")
    out.append("|---|---|---|---|---|---|")
    for label, rows in sets[1:]:
        out.append(f"| {label} | {f(pooled(rows, 'len_short'), 1)} / {f(pooled(rows, 'len_long'), 1)} | {f(pooled(rows, 'leaks_short'))} / {f(pooled(rows, 'leaks_long'))} | "
                   f"{f(pooled(rows, 'gate20_short'))} / {f(pooled(rows, 'gate20_long'))} | {f(pooled(rows, 'p90_short'))} / {f(pooled(rows, 'p90_long'))} | "
                   f"{f(pooled(rows, 'cov20_short'))} / {f(pooled(rows, 'cov20_long'))} |")
    fb = sum(1 for x in forks if x[3].get("fallback"))
    out.append(f"\nОткатов на обычную карту в матрице: {fb} из {len(forks)} партий.")
    text = "\n".join(out)
    print(text)
    if opts.get("md"):
        open(opts["md"], "w", encoding="utf-8").write(text + "\n")
    if opts.get("csv"):
        keys = sorted({k for _, _, _, r in forks + base for k in r})
        with open(opts["csv"], "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(["strategy", "difficulty", "set"] + keys)
            for s, d, fam, r in base + forks:
                w.writerow([s, d, fam] + [r.get(k, "") for k in keys])


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
