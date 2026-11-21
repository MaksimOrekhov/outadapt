#!/usr/bin/env python3
"""PRO-141: сводка эксперимента «два портала, второй открывается посреди забега».

  python tests/portal_report.py <тег> [--root=../build/portal] [--arms=ctl,p18,...] [--model=off] [--ws=0]
         [--md=out.md] [--csv=out.csv] [--thresholds=../docs/architecture/data/pro141/registration.json]

Читает ../build/portal/<тег>/<плечо>/<стратегия>_<сложность>_<модель>_<карта>_ws<0|1>.jsonl (tests/portal_matrix.sh).
Среднее — по партиям группы, затем по группам (стратегия × сложность), как в PRO-192/212/213. Партии парные: один сид,
стратегия, сложность, карта. «Дожили до N-й» — партия дошла до волны N (end_wave ≥ N); win30 — победа к 30-й.
  утечки/жизни   обычные волны диапазона; жизни — включая боссов; боссовые 10-я, 20-я, 30-я отдельно;
  дорога 0/1     по порталам (дорога 0 — первый портал, дорога 1 — второй; на fork — «короткая» и «длинная» не различаются);
  ворота         первые 20% каждой дороги: gate20 (доля убитых в них), cov20 (доля точек под обстрелом);
  dps_gate       оценка урона в секунду башен, достающих ворота; доля первого портала = dps0/(dps0+dps1);
  n_both         доля башен, достающих ворота ОБОИХ входов (на развилке — все: общий ствол).
Окно после активации — волны 19–29 (для ctl и fork окно то же, чтобы сравнивать с теми же волнами).
С --thresholds печатает вердикт по зарегистрированным порогам, ничего не подгоняя.
"""
import json, os, sys, glob, csv
from collections import defaultdict

HERE = os.path.dirname(os.path.abspath(__file__))
STRATS = ["owner2", "mixed", "adaptive", "owner"]
OPEN_W = 18  # волна открытия гипотезы: окно «момент подготовки» и «после» берётся относительно неё для всех плеч


def mean(a):
    a = [x for x in a if x is not None and x == x]
    return sum(a) / len(a) if a else float("nan")


def f(x, n=2):
    return "—" if x != x else f"{x:.{n}f}"


def kind(w):
    return "boss" if w["w"] % 10 == 0 else ("special" if w.get("special") else "normal")


def fin(w):
    return w.get("done") or w.get("lost")


def lost_lives(w):
    return int(w.get("lives0", 0)) - int(w.get("lives", w.get("lives0", 0)))


def game_row(g):
    s = g["summary"]
    e = s["end_wave"]
    ws = [w for w in g["waves"] if fin(w)]
    wd = [w for w in ws if w.get("done") and not w.get("lost")]
    by = {w["w"]: w for w in ws}
    r = {"seed": g["seed"], "won30": 1.0 if s["won30"] else 0.0, "end_wave": e}
    for n in (10, 18, 21, 30):
        r[f"reached{n}"] = 1.0 if e >= n else 0.0
    def norm(lo, hi):
        return [w for w in wd if lo <= w["w"] <= hi and kind(w) == "normal"]
    for tag, lo, hi in (("1_10", 1, 10), ("11_20", 11, 20), ("21_29", 21, 29), ("19_29", 19, 29)):
        r[f"leaks_{tag}"] = mean([w.get("leaked", 0) for w in norm(lo, hi)])
        r[f"lives_{tag}"] = sum(lost_lives(w) for w in ws if lo <= w["w"] <= hi) if any(lo <= w["w"] <= hi for w in ws) else None
    for b in (10, 20, 30):
        r[f"boss{b}"] = lost_lives(by[b]) if b in by else None
    rt = g.get("routes") or {}
    pt = rt.get("portal")
    ow = pt["open"] if pt else None
    r["open"] = ow
    r["announce"] = pt["announce"] if pt else None
    r["shock"] = (sum(lost_lives(by[x]) for x in (ow, ow + 1) if x in by) if ow and ow < 999 and ow in by else None)
    # маршруты после активации (окно 19–29) и «момент подготовки» (волна 18, иначе 17)
    n19 = norm(19, 29)
    for rid in ("0", "1"):
        xs = [w["routes"].get(rid) for w in n19 if w.get("routes")]
        r[f"leaks_r{rid}"] = mean([x["leaked"] for x in xs if x])
        r[f"n_r{rid}"] = mean([x["n"] for x in xs if x])
        xs21 = [w["routes"].get(rid) for w in norm(21, 29) if w.get("routes")]
        r[f"gate20_r{rid}"] = mean([x["gate20"] for x in xs21 if x and x["n"] > 0])
        r[f"p90_r{rid}"] = mean([x["p90"] for x in xs21 if x and x["n"] > 0])
        r[f"beyond40_r{rid}"] = mean([x["beyond40"] for x in xs21 if x and x["n"] > 0])
        r[f"cov20_r{rid}_21_29"] = mean([w.get("cov20_routes", {}).get(rid) for w in wd if 21 <= w["w"] <= 29])
        prep = by.get(18) if by.get(18, {}).get("done") else by.get(17)
        r[f"cov20_r{rid}_prep"] = prep.get("cov20_routes", {}).get(rid) if prep and prep.get("done") else None
    tot = (r["n_r0"] or 0) + (r["n_r1"] or 0)
    r["share_r1"] = (r["n_r1"] / tot) if tot == tot and tot > 0 else None
    # ворота: доля урона первого портала, башни, достающие оба входа
    pw = [w["portal"] for w in wd if 19 <= w["w"] <= 29 and w.get("portal")]
    r["dps_share_r0"] = mean([p["dps_gate"][0] / max(1, p["dps_gate"][0] + p["dps_gate"][1]) for p in pw if p["dps_gate"][0] + p["dps_gate"][1] > 0])
    r["both_share"] = mean([p["n_both"] / max(1, p["n_shooters"]) for p in pw])
    r["dps_both_share"] = mean([p["dps_both"] / max(1, p["dps_any"]) for p in pw if p["dps_any"] > 0])
    pw2 = [w["portal"] for w in wd if 12 <= w["w"] <= 17 and w.get("portal")]
    r["both_share_pre"] = mean([p["n_both"] / max(1, p["n_shooters"]) for p in pw2])
    # экономика вокруг активации
    r["gold_pre_14_18"] = mean([w.get("gold_pre") for w in ws if 14 <= w["w"] <= 18])
    r["spend_15_18"] = sum(int(w.get("build", 0)) + int(w.get("upg", 0)) for w in ws if 15 <= w["w"] <= 18)
    tw = lambda x: sum(by[x]["towers"].values()) if x in by and by[x].get("towers") else None
    r["towers_14"], r["towers_22"] = tw(14), tw(22)
    r["wave_hp_pre"] = {w["w"]: w.get("wave_hp") for w in wd if w["w"] < 30}
    r["sizes"] = {w["w"]: w.get("size") for w in wd if w["w"] < 30}
    # время жизни обычных наземных (волны 19–29): секунды в бою
    r["life_g"] = mean([w["life_g"][0] for w in n19 if w.get("life_g") and w["life_g"][2] > 0])
    if g.get("fork_fallback"):
        r["fallback"] = 1
    return r


def load(root, tag, arms, model, ws):
    out = []
    for arm in arms:
        for fn in sorted(glob.glob(os.path.join(root, tag, arm, "*.jsonl"))):
            name = os.path.basename(fn)[:-6]
            parts = name.split("_")
            strat, diff, m = parts[0], parts[1], parts[2]
            mp = "_".join(parts[3:-1])
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
                    r.update({"arm": arm, "strat": strat, "diff": diff, "map": mp})
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


def identical_before_open(rows_a, rows_b):
    """Парные партии: до волны предупреждения число врагов и суммарное HP волн совпадают с контролем (бот ещё ведёт себя так же,
    расписание — одно); размеры волн совпадают во всех волнах. Возвращает (проверено, расхождений HP, расхождений размеров)."""
    idx = {(r["strat"], r["diff"], r["seed"]): r for r in rows_a}
    n = bad_hp = bad_sz = 0
    for r in rows_b:
        a = idx.get((r["strat"], r["diff"], r["seed"]))
        if a is None:
            continue
        ann = r.get("announce") or 999
        for w, hp in r["wave_hp_pre"].items():
            if w < ann and w in a["wave_hp_pre"]:
                n += 1
                bad_hp += a["wave_hp_pre"][w] != hp
        for w, sz in r["sizes"].items():
            if w in a["sizes"]:
                n += 1
                bad_sz += a["sizes"][w] != sz
    return n, bad_hp, bad_sz


def evaluate(arm_rows, ctl_rows, thr):
    """Вердикт по порогам v1 (относительно контроля «один активный портал» на той же геометрии)."""
    out = {}
    o = thr["outcomes"]
    for mp in sorted({r["map"] for r in arm_rows}):
        rs = [r for r in arm_rows if r["map"] == mp]
        cs = [r for r in ctl_rows if r["map"] == mp]
        if not cs:
            continue
        nm, cn = pooled(rs, "won30", lambda r: r["diff"] == "normal"), pooled(cs, "won30", lambda r: r["diff"] == "normal")
        hd, ch = pooled(rs, "won30", lambda r: r["diff"] == "hard"), pooled(cs, "won30", lambda r: r["diff"] == "hard")
        drop = cn - nm
        out[(mp, "win30 normal ниже контроля на %.2f–%.2f (второй портал чего-то стоит, но не ломает)" % (o["normal_drop_min"], o["normal_drop_max"]))] = (o["normal_drop_min"] <= drop <= o["normal_drop_max"], drop)
        good = sum(1 for s in STRATS if per_strat(rs, "won30", "normal", s) >= o["strategy_ratio_min"] * per_strat(cs, "won30", "normal", s))
        out[(mp, "win30 normal ≥ %.0f%% контроля у ≥ %d из 4 стратегий" % (100 * o["strategy_ratio_min"], o["strategies_n"]))] = (good >= o["strategies_n"], good)
        out[(mp, "win30 hard ≥ %.0f%% контроля" % (100 * o["hard_ratio_min"]))] = (hd >= o["hard_ratio_min"] * ch, hd / ch if ch else float("nan"))
        r21, c21 = pooled(rs, "reached21"), pooled(cs, "reached21")
        out[(mp, "дожили до 21-й ≥ %.0f%% контроля (нет провала на середине матча)" % (100 * o["reached21_ratio_min"]))] = (r21 >= o["reached21_ratio_min"] * c21, r21 / c21 if c21 else float("nan"))
        # дожили до волны открытия — как контроль (открытие своё у каждого плеча)
        idx = {(r["strat"], r["diff"], r["seed"]): r for r in cs}
        dd = []
        for r in rs:
            c = idx.get((r["strat"], r["diff"], r["seed"]))
            if c is not None and r.get("open"):
                dd.append((1.0 if r["end_wave"] >= r["open"] else 0.0) - (1.0 if c["end_wave"] >= r["open"] else 0.0))
        d_open = mean(dd)
        out[(mp, "дожили до волны открытия как контроль (|Δ| ≤ %.2f)" % o["survive_to_activation_delta_max"])] = (abs(d_open) <= o["survive_to_activation_delta_max"], d_open)
        n_, bad_hp, bad_sz = identical_before_open(cs, rs)
        out[(mp, "HP волн до предупреждения и размеры всех волн те же, что у контроля (расхождений)")] = (bad_hp + bad_sz == 0, bad_hp + bad_sz)
        reach = [r for r in rs if r["reached18"] == 1.0 and r.get("cov20_r1_prep") is not None]
        prep = mean([1.0 if r["cov20_r1_prep"] >= o["activation_prepared_cov20_min"] else 0.0 for r in reach]) if reach else float("nan")
        out[(mp, "к открытию cov20 второго входа ≥ %.2f в ≥ %.0f%% партий" % (o["activation_prepared_cov20_min"], 100 * o["activation_prepared_share_min"]))] = (prep >= o["activation_prepared_share_min"], prep)
        bs = pooled(rs, "both_share")
        out[(mp, "волны 19–29: башен, достающих оба входа, ≤ %.2f" % o["both_share_max"])] = (bs <= o["both_share_max"], bs)
        ds = pooled(rs, "dps_share_r0")
        out[(mp, "волны 19–29: доля урона ворот первого портала ≤ %.2f (второй вход реально защищён)" % o["dps_share_first_max"])] = (ds <= o["dps_share_first_max"], ds)
        l1 = pooled(rs, "leaks_r1")
        out[(mp, "утечки на второй дороге в 19–29 ≤ %.2f на волну" % o["second_route_leaks_max"])] = (l1 <= o["second_route_leaks_max"], l1)
        sh = pooled(rs, "shock")
        out[(mp, "потеря жизней в волне открытия и следующей ≤ %.1f" % o["shock_lives_max"])] = (sh <= o["shock_lives_max"], sh)
    return out


def main():
    pos = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    if not pos:
        print(__doc__)
        return
    tag = pos[0]
    root = opts.get("root", os.path.join(HERE, "..", "..", "build", "portal"))
    arms = opts["arms"].split(",") if opts.get("arms") else sorted(d for d in os.listdir(os.path.join(root, tag)) if os.path.isdir(os.path.join(root, tag, d)))
    model, ws = opts.get("model", "off"), opts.get("ws", "0")
    rows = load(root, tag, arms, model, ws)
    if not rows:
        print("нет данных")
        return
    arms = [a for a in arms if any(r["arm"] == a for r in rows)]
    maps = sorted({r["map"] for r in rows})
    out = [f"## {tag}: модель `{model}`, Мастерская {'на максимуме' if ws == '1' else 'нет'}\n"]
    ctl = [r for r in rows if r["arm"] == "ctl"]
    for mp in maps:
        arm_list = [a for a in arms if any(r["arm"] == a and r["map"] == mp for r in rows)]
        sel = {a: [r for r in rows if r["arm"] == a and r["map"] == mp] for a in arm_list}
        out.append(f"### {mp}\n")
        out.append("| Плечо | партий | win30 normal | win30 hard | дожили до 18-й | до 21-й | до 30-й | жизней 1–10 / 11–20 / 21–29 | босс 10 / 20 / 30 | жизней в волне открытия и следующей |")
        out.append("|---|---|---|---|---|---|---|---|---|---|")
        for a in arm_list:
            r = sel[a]
            out.append(f"| {a} | {len(r)} | {f(pooled(r, 'won30', lambda x: x['diff'] == 'normal'))} | {f(pooled(r, 'won30', lambda x: x['diff'] == 'hard'))} | {f(pooled(r, 'reached18'))} | "
                       f"{f(pooled(r, 'reached21'))} | {f(pooled(r, 'reached30'))} | {f(pooled(r, 'lives_1_10'), 1)} / {f(pooled(r, 'lives_11_20'), 1)} / {f(pooled(r, 'lives_21_29'), 1)} | "
                       f"{f(pooled(r, 'boss10'), 1)} / {f(pooled(r, 'boss20'), 1)} / {f(pooled(r, 'boss30'), 1)} | {f(pooled(r, 'shock'), 1)} |")
        out.append("\n**win30 по стратегиям (normal / hard):**\n")
        out.append("| Плечо | " + " | ".join(STRATS) + " |")
        out.append("|---|" + "---|" * len(STRATS))
        for a in arm_list:
            out.append(f"| {a} | " + " | ".join(f"{f(per_strat(sel[a], 'won30', 'normal', s))} / {f(per_strat(sel[a], 'won30', 'hard', s))}" for s in STRATS) + " |")
        out.append("\n**Оборона после открытия (волны 19–29) и у момента открытия:** доля врагов через второй вход, утечки на дорогу, gate20 / p90 по воротам (21–29), cov20 ворот, доля урона первого портала, башни, достающие оба входа:\n")
        out.append("| Плечо | через 2-й вход | утечки 19–29: дорога 0 / 1 | gate20 21–29: 0 / 1 | p90: 0 / 1 | cov20 ворот к открытию: 0 / 1 | cov20 21–29: 0 / 1 | доля урона 1-го портала | башен, достающих оба входа (12–17 / 19–29) | урона обоих входов |")
        out.append("|---|---|---|---|---|---|---|---|---|---|")
        for a in arm_list:
            r = sel[a]
            two = lambda k: f"{f(pooled(r, k + '0'))} / {f(pooled(r, k + '1'))}"
            out.append(f"| {a} | {f(pooled(r, 'share_r1'))} | {f(pooled(r, 'leaks_r0'))} / {f(pooled(r, 'leaks_r1'))} | {two('gate20_r')} | {two('p90_r')} | "
                       f"{f(pooled(r, 'cov20_r0_prep'))} / {f(pooled(r, 'cov20_r1_prep'))} | {f(pooled(r, 'cov20_r0_21_29'))} / {f(pooled(r, 'cov20_r1_21_29'))} | {f(pooled(r, 'dps_share_r0'))} | "
                       f"{f(pooled(r, 'both_share_pre'))} / {f(pooled(r, 'both_share'))} | {f(pooled(r, 'dps_both_share'))} |")
        out.append("\n**Экономика у открытия:** золото перед строительством 14–18, потрачено на башни и улучшения в 15–18, башен к 14-й / 22-й, время жизни обычных наземных врагов 19–29 (с):\n")
        out.append("| Плечо | gold_pre 14–18 | потрачено 15–18 | башен 14 / 22 | время жизни врага |")
        out.append("|---|---|---|---|---|")
        for a in arm_list:
            r = sel[a]
            out.append(f"| {a} | {f(pooled(r, 'gold_pre_14_18'), 0)} | {f(pooled(r, 'spend_15_18'), 0)} | {f(pooled(r, 'towers_14'), 1)} / {f(pooled(r, 'towers_22'), 1)} | {f(pooled(r, 'life_g'), 1)} |")
        if ctl and sel.get("ctl"):
            out.append("\n**Парная разность с контролем (плечо − ctl; пар лучше / хуже):**\n")
            out.append("| Плечо | Δwin30 | пар лучше / хуже | Δжизней 19–29 | Δдожили до 21-й |")
            out.append("|---|---|---|---|---|")
            for a in arm_list:
                if a in ("ctl", "fork"):
                    continue
                d, b, w = paired(sel["ctl"], sel[a], "won30")
                dl, _, _ = paired(sel["ctl"], sel[a], "lives_19_29")
                d21, _, _ = paired(sel["ctl"], sel[a], "reached21")
                out.append(f"| {a} | {d:+.2f} | {b} / {w} | {dl:+.1f} | {d21:+.2f} |")
        out.append("")
    if opts.get("thresholds"):
        thr = json.load(open(opts["thresholds"], encoding="utf-8"))
        out.append("### Вердикт по зарегистрированным порогам (исходы; геометрия — tests/portal_geometry.gd и tests/portal_layouts.gd)\n")
        for a in arms:
            if a in ("ctl", "fork"):
                continue
            ev = evaluate([r for r in rows if r["arm"] == a], ctl, thr)
            ok = all(v[0] for v in ev.values())
            out.append(f"**{a}: {'ВСЕ ПОРОГИ ВЫПОЛНЕНЫ' if ok else 'не все пороги выполнены'}**\n")
            out.append("| Карта | Критерий | Значение | Итог |")
            out.append("|---|---|---|---|")
            for (mp, crit), (passed, val) in ev.items():
                out.append(f"| {mp} | {crit} | {f(val)} | {'✓' if passed else '✗'} |")
            out.append("")
    text = "\n".join(out)
    print(text)
    if opts.get("md"):
        open(opts["md"], "w", encoding="utf-8").write(text + "\n")
    if opts.get("csv"):
        skip = {"wave_hp_pre", "sizes"}
        keys = sorted({k for r in rows for k in r if k not in skip})
        with open(opts["csv"], "w", newline="", encoding="utf-8") as fh:
            w = csv.writer(fh)
            w.writerow(keys)
            for r in rows:
                w.writerow([r.get(k, "") for k in keys])


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    main()
