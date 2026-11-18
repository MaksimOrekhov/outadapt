#!/usr/bin/env python3
"""PRO-212: сводки абляций и вариантов дальности (tests/range_ablate.sh, tests/range_matrix.sh).

  python tests/range_report.py ablate                      # ../build/range/ablate: плечи против none и rp-none
  python tests/range_report.py compare <база> <вариант>...  # папки ../build/range/<имя>: вариант против базы, те же ячейки
  [--md=out.md] [--csv=out.csv] [--groups] [--branches]   (--branches — G8: ветки по умолчанию против br-*, доля L3)

Имя ячейки: <стратегия>_<сложность>_<модель>_<семейство>_<хвост>; хвост — плечо абляции или wsN.

Определения (обычные волны — не особые и не боссовые; волна в фазе учитывается, если сыграна и не проиграна):
  gate20     доля наземных врагов волны, убитых в первых 20% дороги;
  p90        90-й перцентиль доли пройденного пути (убитые и прорвавшиеся, прорыв = 1,5) — НЕ максимум;
  max        максимум доли пути за волну (1,5 = прорыв);  b40 — доля наземных врагов, ушедших дальше 40% пути;
  cov20      доля точек первых 20% пути, которые достаёт хоть одна наземная башня;
  d20, drest сколько башен в среднем достаёт точку в первых 20% / на остальных 80% пути;
  z20        доля реального урона по наземным врагам, нанесённого в первых 20% пути (hits20 — доля попаданий);
  ttk        «ворота» снимают здоровье волны за ttk × время выхода волны из портала;
  leaks      прорывы на волну; win30 — победа к 30-й.
Пулинг как в PRO-192: среднее волн-записей внутри группы (стратегия × сложность × модель × хвост; 4 семейства × сиды),
затем среднее групп. Парная оценка: разность на уровне партии (те же стратегия, сложность, модель, семейство, сид),
95% бутстреп-интервал по партиям; в пары входят только партии, дожившие до фазы в обоих плечах.
"""
import json, os, sys, glob, random
from collections import defaultdict

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "build", "range")
PHASES = [("1-10", 1, 10), ("11-20", 11, 20), ("21-29", 21, 29), ("31-35", 31, 35)]
METRICS = ["gate20", "p90", "max", "b40", "cov20", "d20", "drest", "z20", "hits20", "ttk", "leaks"]


def kind_of(wr):
    if wr["w"] % 10 == 0:
        return "boss"
    if wr.get("special"):
        return "special"
    return "normal"


def wave_vals(wr):
    """Метрики одной волны (None — нет данных)."""
    v = {}
    kg = wr.get("kill_g")
    v["gate20"] = kg[1] if kg and kg[2] > 0 else None
    pg = wr.get("prog_g")
    v["p90"] = pg[1] if pg and pg[1] >= 0 else None
    v["max"] = wr["max_g"] if wr.get("max_g", -1) >= 0 else None
    v["b40"] = wr.get("beyond40") if kg and kg[2] > 0 else None
    v["cov20"] = wr.get("cov20")
    v["d20"] = wr.get("depth20")
    v["drest"] = wr.get("depth_rest")
    zd = wr.get("zone_dmg")
    v["z20"] = zd[0] if zd and zd[2] > 0 else None
    zh = wr.get("zone_hits")
    v["hits20"] = zh[0] if zh and zh[2] > 0 else None
    v["ttk"] = wr["ttk_gate"] / wr["spawn_s"] if wr.get("spawn_s") else None
    v["leaks"] = wr.get("leaked", 0)
    return v


def parse_name(name):
    p = name.split("_")
    return {"strategy": p[0], "difficulty": p[1], "model": p[2], "family": p[3], "tail": "_".join(p[4:])}


def load(folder):
    """[(ключ ячейки, партия)]"""
    out = []
    for f in sorted(glob.glob(os.path.join(folder, "*.jsonl"))):
        meta = parse_name(os.path.basename(f)[:-6])
        for line in open(f, encoding="utf-8"):
            if line.strip():
                try:
                    out.append((meta, json.loads(line)))
                except json.JSONDecodeError:
                    print(f"ВНИМАНИЕ: недописанная строка в {os.path.basename(f)} пропущена (прогон ещё идёт?)", file=sys.stderr)
    return out


def game_summary(g):
    """Средние по фазам (обычные волны) для одной партии + итоги."""
    acc = defaultdict(lambda: defaultdict(list))
    boss = {}
    for wr in g["waves"]:
        if wr.get("lost"):
            continue
        if not wr.get("done"):
            continue
        if kind_of(wr) == "boss":
            boss[wr["w"]] = wr.get("leaked", 0)
        if kind_of(wr) != "normal":
            continue
        ph = next((p for p, a, b in PHASES if a <= wr["w"] <= b), None)
        if ph is None:
            continue
        for m, x in wave_vals(wr).items():
            if x is not None:
                acc[ph][m].append(x)
    s = g["summary"]
    l3 = {}
    for wr in g["waves"]:
        if wr["w"] == 29 and "l3" in wr:
            l3 = wr["l3"]
    return {"phase": {p: {m: sum(v) / len(v) for m, v in d.items() if v} for p, d in acc.items()},
            "n": {p: len(d.get("leaks", [])) for p, d in acc.items()},
            "won30": 1.0 if s["won30"] else 0.0, "end": s["end_wave"], "boss20": boss.get(20), "boss30": boss.get(30),
            "reached21": any(wr["w"] >= 21 and wr.get("done") for wr in g["waves"]),
            "reached29": any(wr["w"] >= 29 and wr.get("done") for wr in g["waves"]),
            "l3": l3}


def group_key(meta, ws_from_tail=True):
    return (meta["strategy"], meta["difficulty"], meta["model"], meta["tail"])


def pooled(games, filt=lambda m: True):
    """PRO-192-совместимый пул: волна-записи → среднее в группе → среднее групп. {фаза: {метрика: значение}}."""
    grp = defaultdict(lambda: defaultdict(lambda: defaultdict(list)))
    win = defaultdict(list)
    boss = defaultdict(lambda: defaultdict(list))
    for meta, g in games:
        if not filt(meta):
            continue
        k = group_key(meta)
        win[k].append(1.0 if g["summary"]["won30"] else 0.0)
        for wr in g["waves"]:
            if not wr.get("done") or wr.get("lost"):
                continue
            if kind_of(wr) == "boss" and wr["w"] in (20, 30):
                boss[k][wr["w"]].append(wr.get("leaked", 0))
            if kind_of(wr) != "normal":
                continue
            ph = next((p for p, a, b in PHASES if a <= wr["w"] <= b), None)
            if ph is None:
                continue
            for m, x in wave_vals(wr).items():
                if x is not None:
                    grp[k][ph][m].append(x)
    out = defaultdict(dict)
    for p, _, _ in PHASES:
        for m in METRICS:
            vals = [sum(grp[k][p][m]) / len(grp[k][p][m]) for k in grp if grp[k][p][m]]
            out[p][m] = sum(vals) / len(vals) if vals else float("nan")
    out["all"]["win30"] = sum(sum(v) / len(v) for v in win.values()) / max(1, len(win))
    for w in (20, 30):
        vals = [sum(boss[k][w]) / len(boss[k][w]) for k in boss if boss[k][w]]
        out["all"][f"boss{w}"] = sum(vals) / len(vals) if vals else float("nan")
    out["all"]["groups"] = len(win)
    out["all"]["games"] = sum(len(v) for v in win.values())
    return out


def paired(games_a, games_b, metric, phase="21-29", filt=lambda m: True, n_boot=2000):
    """Разность b − a по партиям с одинаковыми стратегией/сложностью/моделью/семейством/сидом. -> (среднее, lo, hi, n пар, n только a, n только b)."""
    def index(games):
        d = {}
        for meta, g in games:
            if not filt(meta):
                continue
            gs = game_summary(g)
            key = (meta["strategy"], meta["difficulty"], meta["model"], meta["family"], g["seed"])
            if metric == "won30":
                d[key] = gs["won30"]
            else:
                v = gs["phase"].get(phase, {}).get(metric)
                if v is not None:
                    d[key] = v
        return d
    a, b = index(games_a), index(games_b)
    keys = sorted(set(a) & set(b))
    diffs = [b[k] - a[k] for k in keys]
    if not diffs:
        return (float("nan"),) * 3 + (0, len(a), len(b))
    rnd = random.Random(212)
    means = []
    for _ in range(n_boot):
        s = [diffs[rnd.randrange(len(diffs))] for _ in diffs]
        means.append(sum(s) / len(s))
    means.sort()
    return (sum(diffs) / len(diffs), means[int(0.025 * n_boot)], means[int(0.975 * n_boot)], len(keys),
            len(set(a) - set(b)), len(set(b) - set(a)))


def split_tail(games, tail):
    return [(m, g) for m, g in games if m["tail"] == tail]


def denominators(games):
    """Сколько партий в группе доживает до 21-й и 29-й волны (обычные волны поздней фазы)."""
    d = defaultdict(lambda: [0, 0, 0])
    for meta, g in games:
        k = group_key(meta)
        gs = game_summary(g)
        d[k][0] += 1
        d[k][1] += 1 if gs["reached21"] else 0
        d[k][2] += 1 if gs["reached29"] else 0
    return d


def f(x, n=2):
    return "—" if x != x else f"{x:.{n}f}"


def fd(t, n=2):
    m, lo, hi, k, oa, ob = t
    return "—" if m != m else f"{m:+.{n}f} [{lo:+.{n}f}; {hi:+.{n}f}] (n={k})"


def ablate_report(folder):
    games = load(folder)
    arms = ["none", "norange", "nodmg", "noperk", "nobranch", "nol2"]
    rows = []
    for mode, prefix in [("политика", ""), ("повтор", "rp-")]:
        base = split_tail(games, prefix + "none")
        pb = pooled(base)
        rows.append(f"\n### {mode.capitalize()} ({'бот сам строит оборону' if mode == 'политика' else 'те же покупки, размещение и перки, что в none'})\n")
        rows.append("| Плечо | win30 | gate20 1–10 | gate20 11–20 | **gate20 21–29** | p90 21–29 | max 21–29 | дальше 40% | cov20 | башен у входа | башен дальше | урон в 20% | попадания в 20% | ttk/spawn |")
        rows.append("|" + "---|" * 14)
        for arm in arms:
            ga = split_tail(games, prefix + arm)
            if not ga:
                continue
            p = pooled(ga)
            rows.append(f"| {prefix}{arm} | {f(p['all']['win30'])} | {f(p['1-10']['gate20'])} | {f(p['11-20']['gate20'])} | **{f(p['21-29']['gate20'])}** | "
                        f"{f(p['21-29']['p90'])} | {f(p['21-29']['max'])} | {f(p['21-29']['b40'], 3)} | {f(p['21-29']['cov20'])} | {f(p['21-29']['d20'], 1)} | "
                        f"{f(p['21-29']['drest'], 1)} | {f(p['21-29']['z20'])} | {f(p['21-29']['hits20'])} | {f(p['21-29']['ttk'])} |")
        rows.append(f"\nПарные разности с `{prefix}none` (партия к партии, 95% бутстреп; n — пары, дожившие до 21-й в обоих плечах):\n")
        rows.append("| Плечо | Δ gate20 21–29 | Δ p90 21–29 | Δ урон в 20% | Δ башен у входа | Δ win30 |")
        rows.append("|---|---|---|---|---|---|")
        for arm in arms[1:]:
            ga = split_tail(games, prefix + arm)
            if not ga:
                continue
            rows.append(f"| {prefix}{arm} | {fd(paired(base, ga, 'gate20'))} | {fd(paired(base, ga, 'p90'))} | {fd(paired(base, ga, 'z20'))} | "
                        f"{fd(paired(base, ga, 'd20'), 1)} | {fd(paired(base, ga, 'won30'))} |")
        rows.append("\nПо стратегиям, gate20 21–29 (обе сложности):\n")
        strats = ["owner2", "mixed", "adaptive", "owner"]
        rows.append("| Плечо | " + " | ".join(strats) + " |")
        rows.append("|---|" + "---|" * len(strats))
        for arm in arms:
            ga = split_tail(games, prefix + arm)
            if not ga:
                continue
            cells = [f(pooled(ga, lambda m, s=s: m["strategy"] == s)["21-29"]["gate20"]) for s in strats]
            rows.append(f"| {prefix}{arm} | " + " | ".join(cells) + " |")
    den = denominators(split_tail(games, "none"))
    rows.append("\n### Знаменатель (плечо none): партий / дожили до 21-й / до 29-й\n")
    rows.append("| Группа | партий | до 21-й | до 29-й |")
    rows.append("|---|---|---|---|")
    for k in sorted(den):
        rows.append(f"| {' · '.join(k[:2])} | {den[k][0]} | {den[k][1]} | {den[k][2]} |")
    return "\n".join(rows)


def compare_report(base_dir, var_dirs, groups=False):
    base = load(base_dir)
    rows = []
    filt_ws0 = lambda m: m["tail"] == "ws0"
    for vd in var_dirs:
        var = load(vd)
        name = os.path.basename(os.path.normpath(vd))
        rows.append(f"\n### {name} против {os.path.basename(os.path.normpath(base_dir))}\n")
        pb, pv = pooled(base, filt_ws0), pooled(var, filt_ws0)
        rows.append("| Метрика (без Мастерской, обычные волны) | база | вариант | парная Δ [95%] |")
        rows.append("|---|---|---|---|")
        for p in ["1-10", "11-20", "21-29", "31-35"]:
            for m in ["gate20", "p90", "max", "b40", "z20", "d20", "ttk", "leaks"]:
                rows.append(f"| {m} {p} | {f(pb[p][m], 3)} | {f(pv[p][m], 3)} | {fd(paired(base, var, m, p, filt_ws0), 3)} |")
        rows.append(f"| win30 | {f(pb['all']['win30'])} | {f(pv['all']['win30'])} | {fd(paired(base, var, 'won30', filt=filt_ws0))} |")
        rows.append(f"| утечки на 20-й / 30-й | {f(pb['all']['boss20'])} / {f(pb['all']['boss30'])} | {f(pv['all']['boss20'])} / {f(pv['all']['boss30'])} | |")
        if groups:
            rows.append("\n| Группа | win30 база → вариант | gate20 21–29 | p90 21–29 | утечки 21–29 |")
            rows.append("|---|---|---|---|---|")
            keys = sorted({group_key(m) for m, _ in base})
            for k in keys:
                fk = lambda m, k=k: group_key(m) == k
                a, b = pooled(base, fk), pooled(var, fk)
                rows.append(f"| {' · '.join(k)} | {f(a['all']['win30'])} → {f(b['all']['win30'])} | {f(a['21-29']['gate20'])} → {f(b['21-29']['gate20'])} | "
                            f"{f(a['21-29']['p90'])} → {f(b['21-29']['p90'])} | {f(a['21-29']['leaks'])} → {f(b['21-29']['leaks'])} |")
    return "\n".join(rows)


def l3_reach(games, filt=lambda m: True):
    """Доля партий, у которых к волне 10/20/29 есть хоть одна башня L3 данного вида и ветки (среди доживших до волны)."""
    out = defaultdict(lambda: defaultdict(lambda: [0, 0]))
    for meta, g in games:
        if not filt(meta):
            continue
        for wr in g["waves"]:
            if "l3" in wr and wr.get("done") and not wr.get("lost"):
                for kb in ["sniper_a", "sniper_b", "cannon_a", "cannon_b"]:
                    out[wr["w"]][kb][1] += 1
                    out[wr["w"]][kb][0] += 1 if wr["l3"].get(kb, 0) > 0 else 0
    return out


def branches_report(folder):
    """G8: ячейки с ветками по умолчанию (ws0, без флага) против ячеек br-* (вторая ветка), owner2 и mixed, парно по семейству и сиду."""
    games = load(folder)
    rows = [f"\n### Ветки L3 · {os.path.basename(os.path.normpath(folder))}\n",
            "| Стратегия · сложность | ветки | win30 по умолчанию | win30 br | Δ win30 (br − умолч.) | gate20 21–29 умолч. → br |",
            "|---|---|---|---|---|---|"]
    tails = sorted({m["tail"] for m, _ in games if m["tail"].startswith("br-")})
    for tail in tails:
        for st in ["owner2", "mixed"]:
            for d in ["normal", "hard"]:
                fd_ = lambda m, st=st, d=d: m["strategy"] == st and m["difficulty"] == d and m["model"] == "off"
                a = [(m, g) for m, g in games if fd_(m) and m["tail"] == "ws0"]
                b = [(m, g) for m, g in games if fd_(m) and m["tail"] == tail]
                if not b:
                    continue
                bb = [(dict(m, tail="ws0"), g) for m, g in b]
                pa, pb = pooled(a), pooled(bb)
                rows.append(f"| {st} · {d} | {tail} | {f(pa['all']['win30'])} | {f(pb['all']['win30'])} | {fd(paired(a, bb, 'won30'))} | "
                            f"{f(pa['21-29']['gate20'])} → {f(pb['21-29']['gate20'])} |")
    reach = l3_reach(games, lambda m: m["tail"] == "ws0")
    rows.append("\nДоля партий с L3 к волне (ячейки без Мастерской, без флага и с ним, среди доживших):\n")
    rows.append("| Волна | Снайпер «Палач» | Снайпер «Дальнобой» | Пушка «Мортира» | Пушка «Осадная» |")
    rows.append("|---|---|---|---|---|")
    for w in sorted(reach):
        r = reach[w]
        rows.append(f"| {w} | " + " | ".join(f(r[k][0] / max(1, r[k][1])) for k in ["sniper_a", "sniper_b", "cannon_a", "cannon_b"]) + " |")
    return "\n".join(rows)


def write_csv(games, path):
    import csv
    with open(path, "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        cols = [f"{m}_{p}" for p, _, _ in PHASES for m in METRICS]
        w.writerow(["strategy", "difficulty", "model", "family", "tail", "seed", "end_wave", "won30", "boss20_leaks", "boss30_leaks",
                    "reached21", "reached29", "l3_at_29"] + cols)
        for meta, g in games:
            gs = game_summary(g)
            w.writerow([meta["strategy"], meta["difficulty"], meta["model"], meta["family"], meta["tail"], g["seed"], gs["end"], int(gs["won30"]),
                        gs["boss20"] if gs["boss20"] is not None else "", gs["boss30"] if gs["boss30"] is not None else "",
                        int(gs["reached21"]), int(gs["reached29"]), json.dumps(gs["l3"], sort_keys=True)] +
                       [round(gs["phase"].get(p, {}).get(m), 4) if gs["phase"].get(p, {}).get(m) is not None else "" for p, _, _ in PHASES for m in METRICS])


def _main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) if "=" in a else (a[2:], "1") for a in sys.argv[1:] if a.startswith("--"))
    if args[0] == "ablate":
        folder = os.path.join(ROOT, "ablate")
        text = ablate_report(folder)
        games = None
        if opts.get("csv"):
            write_csv(load(folder), opts["csv"])
    else:
        dirs = [os.path.join(ROOT, a) for a in args[1:]]
        text = compare_report(dirs[0], dirs[1:], "groups" in opts)
        if "branches" in opts:
            text += "\n" + "\n".join(branches_report(d) for d in dirs)
        if opts.get("csv"):
            write_csv(load(dirs[-1]), opts["csv"])
    print(text)
    if opts.get("md"):
        open(opts["md"], "w", encoding="utf-8").write(text + "\n")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    _main()
