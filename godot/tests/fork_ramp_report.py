#!/usr/bin/env python3
"""PRO-214: сводка эксперимента «постепенный ввод второй дороги» (боты на развилках, плечи A/B/C/D).

  python tests/fork_ramp_report.py <тег> [--root=../build/ramp] [--arms=a,b_short,...] [--model=off] [--ws=0]
         [--md=out.md] [--csv=out.csv] [--thresholds=../docs/architecture/data/pro214/registration.json]

Читает ../build/ramp/<тег>/<плечо>/<стратегия>_<сложность>_<модель>_<семейство>_ws<0|1>.jsonl (tests/fork_ramp_matrix.sh).
Среднее — по партиям группы, затем по группам (стратегия × сложность), как в PRO-192/213. Партии парные: один сид,
одна стратегия, одна сложность, одна карта; разность считается по парам.
  win30          победа к 30-й волне;
  утечки 1–10…   прорывы обычных врагов на волну в диапазоне волн, «потеря жизней» — жизни, включая боссов;
  по дорогам     короткая / длинная — по длине дороги; вторая дорога = не «первая» по расписанию;
  экономика      золото перед строительством (gold_pre), вложено в башни, число башен, доход волны = убийства + бонус + проценты;
  поздняя игра   gate20/p90/beyond40/cov20, волны 21–29, партии, которые до них дожили.
С --thresholds печатает вердикт по зарегистрированным порогам (registration.json), ничего не подгоняя.
"""
import json, os, sys, glob, csv, math
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
STRATS = ["owner2", "mixed", "adaptive", "owner"]


def mean(a):
    a = [x for x in a if x is not None and x == x]
    return sum(a) / len(a) if a else float("nan")


def f(x, n=2):
    return "—" if x != x else f"{x:.{n}f}"


def kind(wr):
    return "boss" if wr["w"] % 10 == 0 else ("special" if wr.get("special") else "normal")


def done_ok(w):
    return w.get("done") and not w.get("lost")


def wave_rng(g, lo, hi, normal_only=True):
    return [w for w in g["waves"] if done_ok(w) and lo <= w["w"] <= hi and (not normal_only or kind(w) == "normal")]


def game_row(g):
    s = g["summary"]
    row = {"seed": g["seed"], "family": g["family"], "won30": 1.0 if s["won30"] else 0.0, "end_wave": s["end_wave"]}
    w110, w1120, w2129 = wave_rng(g, 1, 10), wave_rng(g, 11, 20), wave_rng(g, 21, 29)
    row["reached21"] = 1.0 if w2129 else 0.0
    row["leaks_1_10"] = mean([w.get("leaked", 0) for w in w110])
    row["leaks_11_20"] = mean([w.get("leaked", 0) for w in w1120])
    row["leaks_21_29"] = mean([w.get("leaked", 0) for w in w2129])
    allw = [w for w in g["waves"] if w["w"] <= 10]
    row["lives_lost_1_10"] = sum(int(w.get("lives_lost", 0)) if done_ok(w) else int(w.get("lives0", 0)) for w in allw)
    row["lost_by_10"] = 1.0 if (not s["won30"] and s["end_wave"] <= 10) else 0.0
    row["lost_by_20"] = 1.0 if (not s["won30"] and s["end_wave"] <= 20) else 0.0
    # экономика: золото перед строительством, вложено, башни, доход
    gp = {w["w"]: w for w in g["waves"] if w["w"] <= 10}
    row["gold_pre_1_10"] = mean([w.get("gold_pre") for w in gp.values()])
    for k in (1, 2, 3, 5, 7, 10):
        row[f"gold_pre_w{k}"] = gp[k]["gold_pre"] if k in gp else None
    for k in (5, 10):
        w = gp.get(k)
        row[f"invested_w{k}"] = w.get("invested") if w and w.get("done") else None
        row[f"towers_w{k}"] = sum(w["towers"].values()) if w and w.get("done") and w.get("towers") else None
    row["income_1_10"] = sum(int(w.get("kill_income", 0)) + int(w.get("bonus", 0)) + int(w.get("interest", 0)) for w in w110) if w110 else None
    row["bank_w5"] = gp[5].get("gold_bank") if 5 in gp and gp[5].get("done") else None
    # боссы
    row["boss10"] = next((w.get("lives_lost", 0) for w in g["waves"] if w["w"] == 10 and w.get("done")), None)
    row["boss20"] = next((w.get("lives_lost", 0) for w in g["waves"] if w["w"] == 20 and w.get("done")), None)
    # поздняя игра
    row["gate20"] = mean([w["kill_g"][1] for w in w2129 if w.get("kill_g") and w["kill_g"][2] > 0])
    row["p90"] = mean([w["prog_g"][1] for w in w2129 if w.get("prog_g") and w["prog_g"][2] > 0])
    row["b40"] = mean([w.get("beyond40") for w in w2129])
    row["cov20"] = mean([w.get("cov20") for w in w2129])
    rt = g.get("routes")
    if rt:
        lens = rt["len"]
        short = 0 if lens[0] <= lens[1] else 1
        lead = rt.get("lead", None)
        row["lead_is_short"] = None if lead is None else (1.0 if lead == short else 0.0)
        for tag, rid in (("short", short), ("long", 1 - short)):
            ws = [w["routes"].get(str(rid)) for w in w110 if w.get("routes")]
            row[f"leaks_1_10_{tag}"] = mean([x["leaked"] for x in ws if x])
            ws2 = [w["routes"].get(str(rid)) for w in wave_rng(g, 3, 10) if w.get("routes")]
            row[f"leaks_3_10_{tag}"] = mean([x["leaked"] for x in ws2 if x])
            row[f"n_1_10_{tag}"] = mean([x["n"] for x in ws if x])
            row[f"cov20_w5_{tag}"] = next((w.get("cov20_routes", {}).get(str(rid)) for w in g["waves"] if w["w"] == 5 and w.get("done")), None)
            row[f"cov20_w10_{tag}"] = next((w.get("cov20_routes", {}).get(str(rid)) for w in g["waves"] if w["w"] == 10 and w.get("done")), None)
            row[f"gate20_{tag}_21_29"] = mean([x["gate20"] for x in [w["routes"].get(str(rid)) for w in w2129 if w.get("routes")] if x and x["n"] > 0])
        row["len_short"], row["len_long"] = min(lens), max(lens)
    if g.get("fork_fallback"):
        row["fallback"] = 1
    return row


def load(root, tag, arms, model, ws):
    out = []
    for arm in arms:
        for fn in sorted(glob.glob(os.path.join(root, tag, arm, "*.jsonl"))):
            name = os.path.basename(fn)[:-6]
            parts = name.split("_")
            strat, diff, m = parts[0], parts[1], parts[2]
            fam = "_".join(parts[3:-1])
            w = parts[-1][2:]
            if m != model or w != ws:
                continue
            for line in open(fn, encoding="utf-8"):
                if line.strip():
                    try:
                        g = json.loads(line)
                    except json.JSONDecodeError:
                        print(f"ВНИМАНИЕ: недописанная строка в {fn}", file=sys.stderr)
                        continue
                    r = game_row(g)
                    r.update({"arm": arm, "strat": strat, "diff": diff, "fam": fam})
                    out.append(r)
    return out


def pooled(rows, key, filt=lambda r: True):
    grp = defaultdict(list)
    for r in rows:
        if filt(r):
            grp[(r["strat"], r["diff"])].append(r.get(key))
    return mean([mean(v) for v in grp.values()])


def per_strat(rows, key, diff, strat):
    return pooled(rows, key, lambda r: r["diff"] == diff and r["strat"] == strat)


def paired(rows_a, rows_b, key):
    """Парная разность B − A по ключу (стратегия, сложность, сид): среднее по группам, число пар лучше/хуже."""
    idx = {(r["strat"], r["diff"], r["seed"]): r for r in rows_a}
    grp = defaultdict(list)
    better = worse = 0
    for r in rows_b:
        a = idx.get((r["strat"], r["diff"], r["seed"]))
        if a is None or a.get(key) is None or r.get(key) is None:
            continue
        d = r[key] - a[key]
        grp[(r["strat"], r["diff"])].append(d)
        better += d > 0
        worse += d < 0
    return mean([mean(v) for v in grp.values()]), better, worse


def evaluate(arm_rows, base_rows, thr):
    """Вердикт по зарегистрированным порогам: словарь {критерий: (прошёл, значение, порог)} для каждой семьи отдельно."""
    res = {}
    for fam in ("fork_even", "fork_skew"):
        rs = [r for r in arm_rows if r["fam"] == fam]
        if not rs:
            continue
        n_norm = pooled(rs, "won30", lambda r: r["diff"] == "normal")
        n_hard = pooled(rs, "won30", lambda r: r["diff"] == "hard")
        per_n = {s: per_strat(rs, "won30", "normal", s) for s in STRATS}
        per_h = {s: per_strat(rs, "won30", "hard", s) for s in STRATS}
        res[(fam, "normal pooled ≥ %.2f" % thr["normal_pooled_min"])] = (n_norm >= thr["normal_pooled_min"], n_norm)
        res[(fam, "normal каждая стратегия ≥ %.2f" % thr["normal_strategy_min"])] = (min(v for v in per_n.values() if v == v) >= thr["normal_strategy_min"], min(per_n.values()))
        res[(fam, "normal pooled ≤ %.2f (решения нужны, не легче одиночных)" % thr["normal_pooled_max"])] = (n_norm <= thr["normal_pooled_max"], n_norm)
        res[(fam, "hard pooled ≥ %.2f" % thr["hard_pooled_min"])] = (n_hard >= thr["hard_pooled_min"], n_hard)
        res[(fam, "hard pooled ≤ %.2f" % thr["hard_pooled_max"])] = (n_hard <= thr["hard_pooled_max"], n_hard)
        res[(fam, "hard: хотя бы %d из 4 стратегий выигрывают ≥ %.2f" % (thr["hard_strategies_n"], thr["hard_strategy_min"]))] = (
            sum(1 for v in per_h.values() if v == v and v >= thr["hard_strategy_min"]) >= thr["hard_strategies_n"],
            sum(1 for v in per_h.values() if v == v and v >= thr["hard_strategy_min"]))
        ra = [r for r in base_rows if r["fam"] == fam]
        if ra:
            d, b, w = paired(ra, rs, "won30")
            res[(fam, "win30 парно к A: не хуже (Δ ≥ 0)")] = (d >= 0.0, d)
            dg = abs(pooled(rs, "gate20") - pooled(ra, "gate20"))
            dc = abs(pooled(rs, "cov20") - pooled(ra, "cov20"))
            res[(fam, "поздняя игра не изменилась: |Δgate20| ≤ %.2f, |Δcov20| ≤ %.2f" % (thr["late_delta"], thr["late_delta"]))] = (dg <= thr["late_delta"] and dc <= thr["late_delta"], max(dg, dc))
    return res


def main():
    pos = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    if not pos:
        print(__doc__)
        return
    tag = pos[0]
    root = opts.get("root", os.path.join(HERE, "..", "..", "build", "ramp"))
    arms = opts.get("arms", "").split(",") if opts.get("arms") else sorted(d for d in os.listdir(os.path.join(root, tag)) if os.path.isdir(os.path.join(root, tag, d)))
    model, ws = opts.get("model", "off"), opts.get("ws", "0")
    rows = load(root, tag, arms, model, ws)
    if not rows:
        print("нет данных")
        return
    arms = [a for a in arms if any(r["arm"] == a for r in rows)]
    by = {a: [r for r in rows if r["arm"] == a] for a in arms}
    base = by.get("a", [])
    out = []
    out.append(f"## {tag}: модель `{model}`, Мастерская {'на максимуме' if ws == '1' else 'нет'}\n")
    for fam in ("fork_even", "fork_skew"):
        fr = {a: [r for r in by[a] if r["fam"] == fam] for a in arms}
        n_games = {a: len(fr[a]) for a in arms}
        out.append(f"### {fam}\n")
        out.append("| Плечо | партий | win30 normal | win30 hard | дожили до 21-й | проиграно к 10-й / 20-й | утечек/волну 1–10 | 11–20 | 21–29 | жизней потеряно к 10-й |")
        out.append("|---|---|---|---|---|---|---|---|---|---|")
        for a in arms:
            r = fr[a]
            out.append(f"| {a} | {n_games[a]} | {f(pooled(r, 'won30', lambda x: x['diff'] == 'normal'))} | {f(pooled(r, 'won30', lambda x: x['diff'] == 'hard'))} | "
                       f"{f(pooled(r, 'reached21'))} | {f(pooled(r, 'lost_by_10'))} / {f(pooled(r, 'lost_by_20'))} | {f(pooled(r, 'leaks_1_10'))} | {f(pooled(r, 'leaks_11_20'))} | "
                       f"{f(pooled(r, 'leaks_21_29'))} | {f(pooled(r, 'lives_lost_1_10'), 1)} |")
        out.append("\n**win30 по стратегиям (normal / hard):**\n")
        out.append("| Плечо | " + " | ".join(STRATS) + " |")
        out.append("|---|" + "---|" * len(STRATS))
        for a in arms:
            out.append(f"| {a} | " + " | ".join(f"{f(per_strat(fr[a], 'won30', 'normal', s))} / {f(per_strat(fr[a], 'won30', 'hard', s))}" for s in STRATS) + " |")
        out.append("\n**Ранняя экономика, волны 1–10 (золото перед строительством, вложено, башни, доход):**\n")
        out.append("| Плечо | gold_pre в1 | в3 | в5 | в7 | в10 | среднее 1–10 | вложено к 5-й / 10-й | башен к 5-й / 10-й | доход 1–10 (убийства+бонус+проценты) | боссовая 10-я: жизней |")
        out.append("|---|---|---|---|---|---|---|---|---|---|---|")
        for a in arms:
            r = fr[a]
            out.append(f"| {a} | {f(pooled(r, 'gold_pre_w1'), 0)} | {f(pooled(r, 'gold_pre_w3'), 0)} | {f(pooled(r, 'gold_pre_w5'), 0)} | {f(pooled(r, 'gold_pre_w7'), 0)} | {f(pooled(r, 'gold_pre_w10'), 0)} | "
                       f"{f(pooled(r, 'gold_pre_1_10'), 0)} | {f(pooled(r, 'invested_w5'), 0)} / {f(pooled(r, 'invested_w10'), 0)} | {f(pooled(r, 'towers_w5'), 1)} / {f(pooled(r, 'towers_w10'), 1)} | "
                       f"{f(pooled(r, 'income_1_10'), 0)} | {f(pooled(r, 'boss10'), 2)} |")
        out.append("\n**По дорогам, волны 1–10 (короткая / длинная): утечек на волну, врагов на волну, покрытие первых 20% дороги к 5-й и 10-й волне; утечки 3–10:**\n")
        out.append("| Плечо | утечки 1–10 | врагов 1–10 | cov20 к 5-й | cov20 к 10-й | утечки 3–10 |")
        out.append("|---|---|---|---|---|---|")
        for a in arms:
            r = fr[a]
            def sl(k):
                return f"{f(pooled(r, k + '_short'))} / {f(pooled(r, k + '_long'))}"
            out.append(f"| {a} | {sl('leaks_1_10')} | {sl('n_1_10')} | {sl('cov20_w5')} | {sl('cov20_w10')} | {sl('leaks_3_10')} |")
        out.append("\n**Поздняя игра (волны 21–29, партии, дожившие до них): gate20 / p90 / дальше 40% / cov20 / утечки на 20-й (босс):**\n")
        out.append("| Плечо | gate20 | p90 | b40 | cov20 | жизней на 20-й |")
        out.append("|---|---|---|---|---|---|")
        for a in arms:
            r = fr[a]
            out.append(f"| {a} | {f(pooled(r, 'gate20'))} | {f(pooled(r, 'p90'))} | {f(pooled(r, 'b40'))} | {f(pooled(r, 'cov20'))} | {f(pooled(r, 'boss20'), 2)} |")
        if base and fr.get("a"):
            out.append("\n**Парная разность с плечом A (B − A; лучше / хуже пар):**\n")
            out.append("| Плечо | Δwin30 | пар лучше / хуже | Δутечек 1–10 | Δжизней к 10-й | Δвложено к 10-й |")
            out.append("|---|---|---|---|---|---|")
            for a in arms:
                if a == "a":
                    continue
                d, b, w = paired(fr["a"], fr[a], "won30")
                dl, _, _ = paired(fr["a"], fr[a], "leaks_1_10")
                dv, _, _ = paired(fr["a"], fr[a], "lives_lost_1_10")
                di, _, _ = paired(fr["a"], fr[a], "invested_w10")
                out.append(f"| {a} | {d:+.2f} | {b} / {w} | {dl:+.2f} | {dv:+.1f} | {di:+.0f} |")
        out.append("")
    if opts.get("thresholds"):
        thr = json.load(open(opts["thresholds"], encoding="utf-8"))
        out.append("### Вердикт по зарегистрированным порогам\n")
        for a in arms:
            if a == "a":
                continue
            ev = evaluate(by[a], base, thr)
            ok = all(v[0] for v in ev.values())
            out.append(f"**{a}: {'ВСЕ ПОРОГИ ВЫПОЛНЕНЫ' if ok else 'не все пороги выполнены'}**\n")
            out.append("| Семья | Критерий | Значение | Итог |")
            out.append("|---|---|---|---|")
            for (fam, crit), (passed, val) in ev.items():
                out.append(f"| {fam} | {crit} | {f(val)} | {'✓' if passed else '✗'} |")
            out.append("")
    text = "\n".join(out)
    print(text)
    if opts.get("md"):
        open(opts["md"], "w", encoding="utf-8").write(text + "\n")
    if opts.get("csv"):
        keys = sorted({k for r in rows for k in r})
        with open(opts["csv"], "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(keys)
            for r in rows:
                w.writerow([r.get(k, "") for k in keys])


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
