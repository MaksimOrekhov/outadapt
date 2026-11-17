#!/usr/bin/env python3
"""PRO-192: сводка матрицы поздней игры (tests/late_matrix.sh).

python tests/late_report.py <папка прогона> [<папка сравнения>] [--csv=ячейка×волна.csv] [--games=партии.csv] [--md=сводка.md --title=...] [--wavekeys=s,d,m,ws;...]

Ячейки группируются по стратегия × сложность × модель × Мастерская (семейства карт объединяются, 4 × 10 сидов).
Фазы: 1–10, 11–20, 21–29 (обычные волны), отдельно особые и боссовые. Метрики:
  gate20 — доля обычных наземных врагов, убитых в первых 20% дороги (главная метрика «умирают у портала»);
  gate10 — то же для 10%; air20 — летающие в первых 20% прямой полёта;
  p90 — p90 доли пройденного пути убитыми (1.5 = прорыв); ttk/spawn — за сколько «ворота» снимают здоровье волны
  относительно времени её выхода из портала (< 1 — волна гибнет быстрее, чем выходит);
  leaks — прорывы за фазу на партию; win30 — победа к 30-й; p50end — медиана последней волны (цензура: cap).
Партии, проигранные раньше фазы, в фазу не входят (n — число партий-волн).
"""
import json, os, sys, glob, statistics as st
from collections import defaultdict

def phase_of(w):
    if w <= 10: return "1-10"
    if w <= 20: return "11-20"
    if w <= 29: return "21-29"
    if w == 30: return "30"
    return "31+"

def kind_of(wr):
    if wr["w"] % 10 == 0: return "boss"
    if wr.get("special"): return "special"
    return "normal"

def cell_key(name):
    # owner2_hard_signature_snake_ws0 -> (owner2, hard, signature, ws0)
    p = name.split("_")
    return (p[0], p[1], p[2], p[4])

def load(folder):
    games = defaultdict(list)
    for f in sorted(glob.glob(os.path.join(folder, "*.jsonl"))):
        key = cell_key(os.path.basename(f)[:-6])
        for line in open(f, encoding="utf-8"):
            if line.strip():
                games[key].append(json.loads(line))
    return games

def med(a): return st.median(a) if a else float("nan")
def mean(a): return sum(a) / len(a) if a else float("nan")

def summarize(games):
    out = {}
    for key, gs in games.items():
        acc = defaultdict(lambda: defaultdict(list))
        for g in gs:
            for wr in g["waves"]:
                if not wr.get("done") or wr.get("lost"):
                    if wr.get("lost"):
                        acc[(phase_of(wr["w"]), kind_of(wr))]["leaks"].append(wr.get("leaked", 0))
                    continue
                k = (phase_of(wr["w"]), kind_of(wr))
                a = acc[k]
                if "kill_g" in wr and wr["kill_g"][2] > 0:
                    a["gate20"].append(wr["kill_g"][1]); a["gate10"].append(wr["kill_g"][0])
                if "kill_a" in wr and wr["kill_a"][2] > 0:
                    a["air20"].append(wr["kill_a"][1])
                if wr.get("prog_g") and wr["prog_g"][1] >= 0:
                    a["p90"].append(wr["prog_g"][1])
                if wr.get("spawn_s"):
                    a["ttk"].append(wr["ttk_gate"] / wr["spawn_s"])
                a["leaks"].append(wr.get("leaked", 0))
                a["lost"].append(wr.get("lives_lost", 0))
                a["life"].append(wr["life_g"][0] if wr.get("life_g") and wr["life_g"][0] >= 0 else None)
        ends = [g["summary"]["end_wave"] for g in gs]
        out[key] = {
            "n": len(gs), "win30": mean([1.0 if g["summary"]["won30"] else 0.0 for g in gs]),
            "p50end": med(ends), "lives30": med([g["summary"]["lives_at_30"] for g in gs if g["summary"]["lives_at_30"] >= 0]),
            "phases": {k: {m: (mean([x for x in v if x is not None]), len(v)) for m, v in a.items()} for k, a in acc.items()},
        }
    return out

def fmt(v, d=2):
    return "—" if v != v else f"{v:.{d}f}"

def table(summ, other=None):
    rows = []
    hdr = "| Стратегия | Сложн. | Модель | Маст. | n | win30 | p50 конец | gate20 1–10 | gate20 11–20 | **gate20 21–29** | p90 21–29 | ttk/spawn 21–29 | утечки/волна 21–29 | особые 21–29 gate20 |"
    rows.append(hdr)
    rows.append("|" + "---|" * hdr.count("|")[:-0] if False else "|" + "|".join(["---"] * (hdr.count("|") - 1)) + "|")
    for key in sorted(summ):
        s = summ[key]
        ph = s["phases"]
        def g(p, kind, m):
            return ph.get((p, kind), {}).get(m, (float("nan"), 0))[0]
        cells = [*key, str(s["n"]), fmt(s["win30"]), fmt(s["p50end"], 0),
                 fmt(g("1-10", "normal", "gate20")), fmt(g("11-20", "normal", "gate20")), fmt(g("21-29", "normal", "gate20")),
                 fmt(g("21-29", "normal", "p90")), fmt(g("21-29", "normal", "ttk")), fmt(g("21-29", "normal", "leaks")),
                 fmt(g("21-29", "special", "gate20"))]
        if other and key in other:
            o = other[key]; oph = o["phases"]
            def og(p, kind, m):
                return oph.get((p, kind), {}).get(m, (float("nan"), 0))[0]
            cells[4] = f"{fmt(o['win30'])} → {fmt(s['win30'])}"
            cells[5] = f"{fmt(o['p50end'],0)} → {fmt(s['p50end'],0)}"
            cells[6] = f"{fmt(og('1-10','normal','gate20'))} → {fmt(g('1-10','normal','gate20'))}"
            cells[7] = f"{fmt(og('11-20','normal','gate20'))} → {fmt(g('11-20','normal','gate20'))}"
            cells[8] = f"**{fmt(og('21-29','normal','gate20'))} → {fmt(g('21-29','normal','gate20'))}**"
            cells[9] = f"{fmt(og('21-29','normal','p90'))} → {fmt(g('21-29','normal','p90'))}"
            cells[10] = f"{fmt(og('21-29','normal','ttk'))} → {fmt(g('21-29','normal','ttk'))}"
            cells[11] = f"{fmt(og('21-29','normal','leaks'))} → {fmt(g('21-29','normal','leaks'))}"
            cells[12] = f"{fmt(og('21-29','special','gate20'))} → {fmt(g('21-29','special','gate20'))}"
        rows.append("| " + " | ".join(cells) + " |")
    return "\n".join(rows)

def per_wave(games, key):
    """Средние по волнам для одной группы ячеек: для графиков/таблиц по волнам."""
    by = defaultdict(lambda: defaultdict(list))
    for g in games.get(key, []):
        for wr in g["waves"]:
            if not wr.get("done") or wr.get("lost"):
                continue
            b = by[wr["w"]]
            for m in ["wave_hp", "dps_gate", "dps_all", "invested", "gold_bank"]:
                if m in wr: b[m].append(wr[m])
            if "kill_g" in wr and wr["kill_g"][2] > 0: b["gate20"].append(wr["kill_g"][1])
            if wr.get("spawn_s"): b["ttk"].append(wr["ttk_gate"] / wr["spawn_s"])
            if wr.get("prog_g") and wr["prog_g"][1] >= 0: b["p90"].append(wr["prog_g"][1])
            b["leaks"].append(wr.get("leaked", 0))
    return by

def wave_table(games, key):
    by = per_wave(games, key)
    rows = ["| Волна | n | HP волны | DPS ворот | DPS всего | вложено | gate20 | ttk/spawn | p90 | утечки |", "|" + "|".join(["---"] * 10) + "|"]
    for w in sorted(by):
        b = by[w]
        rows.append(f"| {w} | {len(b['leaks'])} | {mean(b['wave_hp']):.0f} | {mean(b['dps_gate']):.0f} | {mean(b['dps_all']):.0f} | {mean(b['invested']):.0f} | {fmt(mean(b['gate20']))} | {fmt(mean(b['ttk']))} | {fmt(mean(b['p90']))} | {fmt(mean(b['leaks']))} |")
    return "\n".join(rows)

def _main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    opts = dict(a[2:].split("=", 1) for a in sys.argv[1:] if a.startswith("--") and "=" in a)
    games = load(args[0])
    summ = summarize(games)
    other = summarize(load(args[1])) if len(args) > 1 else None
    if other:
        # сравнение: строки «до → после», где первая папка — после, вторая — до
        print(table(summ, other))
    else:
        print(table(summ))
    for k in opts.get("wavekeys", "").split(";"):
        if k:
            key = tuple(k.split(","))
            print(f"\n### По волнам: {' · '.join(key)}\n")
            print(wave_table(games, key))
    if opts.get("csv"):
        write_csv(games, opts["csv"])
    if opts.get("games"):
        write_games(games, opts["games"])
    if opts.get("md"):
        write_summary(games, opts["md"], load(args[1]) if len(args) > 1 else None, opts.get("title", ""))


def write_csv(games, path):
    """Агрегат по ячейке × волне (средние по партиям, дожившим до волны) — для docs/balance/data/pro192/."""
    import csv
    cols = ["wave_hp", "dps_gate", "dps_all", "invested", "gold_bank", "gate20", "ttk", "p90", "leaks"]
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["strategy", "difficulty", "model", "workshop", "wave", "n"] + cols)
        for key in sorted(games):
            by = per_wave(games, key)
            for wave in sorted(by):
                b = by[wave]
                w.writerow([*key, wave, len(b["leaks"])] + [round(mean(b[c]), 3) if b.get(c) else "" for c in cols])


def write_games(games, path):
    """Сырые итоги по партиям (строка = партия) и её поздняя фаза: из них пересчитываются все пороги §5."""
    import csv
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["strategy", "difficulty", "model", "workshop", "family", "seed", "end_wave", "won30", "lives_at_30",
                    "gate20_21_29", "p90_21_29", "ttk_21_29", "leaks_21_29", "leaks_w20", "leaks_w30", "invested_w29"])
        for key in sorted(games):
            for g in games[key]:
                late = [wr for wr in g["waves"] if 21 <= wr["w"] <= 29 and kind_of(wr) == "normal" and wr.get("done") and not wr.get("lost")]
                def lk(n):
                    r = [wr.get("leaked", 0) for wr in g["waves"] if wr["w"] == n]
                    return r[0] if r else ""
                inv = [wr.get("invested", "") for wr in g["waves"] if wr["w"] == 29]
                gate = [wr["kill_g"][1] for wr in late if wr.get("kill_g") and wr["kill_g"][2] > 0]
                p90 = [wr["prog_g"][1] for wr in late if wr.get("prog_g") and wr["prog_g"][1] >= 0]
                ttk = [wr["ttk_gate"] / wr["spawn_s"] for wr in late if wr.get("spawn_s")]
                s = g["summary"]
                w.writerow([*key, g.get("family", ""), g.get("seed", ""), s["end_wave"], int(bool(s["won30"])), s["lives_at_30"],
                            round(mean(gate), 4) if gate else "", round(mean(p90), 4) if p90 else "",
                            round(mean(ttk), 4) if ttk else "", sum(wr.get("leaked", 0) for wr in late),
                            lk(20), lk(30), inv[0] if inv else ""])


def write_summary(games, path, other=None, title=""):
    summ = summarize(games)
    with open(path, "w", encoding="utf-8") as f:
        if title:
            f.write(f"# {title}\n\n")
        f.write(table(summ, summarize(other) if other else None) + "\n")


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    _main()
