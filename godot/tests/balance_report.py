#!/usr/bin/env python3
"""PRO-151: сводка матрицы баланс-прогонов (tests/balance_matrix.sh -> *.jsonl).

Запуск из папки godot:
    python tests/balance_report.py ../build/balance/runs[,другая_папка] ../docs/balance/data

Пишет:
    runs.csv        — одна строка на партию (все эксперименты);
    waves_owner.csv — средние по волнам для ключевых стратегий (E1, без Мастерской);
    tables.md       — markdown-таблицы, которые цитирует docs/balance/02-baseline-report.md.
Только стандартная библиотека Python 3.
"""
import csv
import glob
import json
import math
import os
import statistics as st
import sys
from collections import defaultdict

KINDS = ["arrow", "cannon", "ember", "frost", "sniper", "poison", "flak", "tesla", "net", "beacon"]


def load(src):
    runs = []
    for fn in sorted(glob.glob(os.path.join(src, "*.jsonl"))):
        exp = os.path.basename(fn).split("_")[0]
        cell = os.path.basename(fn)[:-6]
        for line in open(fn, encoding="utf-8"):
            line = line.strip()
            if not line:
                continue
            try:
                r = json.loads(line)
            except json.JSONDecodeError:
                continue  # недописанная строка (прогон ещё идёт)
            r["exp"] = exp
            r["cell"] = cell
            runs.append(r)
    return runs


def boss_leaks_by30(r):
    return sum(int(w.get("boss_leak", 0) or 0) for w in r["waves"] if w["w"] <= 30 and w.get("done") and not w.get("lost"))


def row(r):
    s = r["summary"]
    dmg = s.get("run_damage", {})
    tot = sum(dmg.values()) or 1
    spent = s.get("spent_by", {})
    out = {
        "exp": r["exp"], "cell": r["cell"], "strategy": r["strategy"], "difficulty": r["difficulty"], "family": r["family"],
        "workshop": int(bool(r["workshop"])), "swarm": r["swarm"] or "normal", "ablate": r["ablate"], "branch": r["branch"] or "default",
        "upgrades": int(bool(r["upgrades"])), "perks": r["perks"], "micro": int(bool(r.get("micro", True))), "seed": r["seed"],
        "path_len": r["path_len"], "fly_len": r["fly_len"],
        "end_wave": s["end_wave"], "won30": int(bool(s["won30"])), "lives_at_30": s["lives_at_30"], "leaks_by_30": s["leaks_by_30"],
        "boss_leaks_by_30": boss_leaks_by30(r), "min_lives": s["min_lives"], "spent_build": s["spent_build"],
        "spent_upgrade": s["spent_upgrade"], "bosses_killed": s["bosses_killed"],
    }
    for k in KINDS:
        out["dmg_" + k] = round(dmg.get(k, 0) / tot, 4)
        out["abs_" + k] = dmg.get(k, 0)
        out["n_" + k] = s["composition"].get(k, 0)
        out["spent_" + k] = spent.get(k, 0)
    return out


def mean(v):
    v = [x for x in v if x is not None]
    return sum(v) / len(v) if v else float("nan")


def med(v):
    v = [x for x in v if x is not None]
    return st.median(v) if v else float("nan")


def se(v):
    return st.stdev(v) / math.sqrt(len(v)) if len(v) > 1 else float("nan")


def fmt(x, d=1):
    if isinstance(x, float) and math.isnan(x):
        return "—"
    return f"{x:.{d}f}"


def group(rows, keys):
    g = defaultdict(list)
    for r in rows:
        g[tuple(r[k] for k in keys)].append(r)
    return g


def outcome_cells(rs):
    n = len(rs)
    won = [r for r in rs if r["won30"]]
    ends = [r["end_wave"] for r in rs]
    clean = sum(1 for r in rs if r["won30"] and r["leaks_by_30"] == 0)
    boss_only = sum(1 for r in won if r["leaks_by_30"] > 0 and r["leaks_by_30"] == r["boss_leaks_by_30"])
    return [str(n), f"{100 * len(won) / n:.0f}%", f"{100 * clean / n:.0f}%", fmt(mean(ends)) + " ± " + fmt(se(ends)), fmt(med(ends), 0),
            fmt(mean([r["lives_at_30"] for r in won])), fmt(mean([r["leaks_by_30"] for r in won])),
            fmt(mean([r["boss_leaks_by_30"] for r in won])), f"{boss_only}/{len(won)}"]


OUT_HEAD = "| n | дожили до 31 | без утечек к 30 | волна конца (ср. ± SE) | медиана | жизни на 30 (у доживших) | утечки к 30 | из них боссов | только боссы |"
OUT_SEP = "|---|---|---|---|---|---|---|---|---|"


def table_e1(rows):
    out = ["### T1. Исходы по стратегиям (E1: 4 семейства × 10 сидов на ячейку; cap = 40 волн, «41» = дожил до 40)", ""]
    out.append("| стратегия | сложность | Мастерская " + OUT_HEAD)
    out.append("|---|---|---" + OUT_SEP)
    order = ["arrow", "sniper", "arrow_sniper", "arrow_frost_ember", "owner", "mixed", "adaptive"]
    g = group([r for r in rows if r["exp"] == "E1"], ["strategy", "difficulty", "workshop"])
    for s in order:
        for d in ["normal", "hard"]:
            for w in [0, 1]:
                rs = g.get((s, d, w))
                if rs:
                    out.append(f"| {s} | {d} | {'да' if w else 'нет'} | " + " | ".join(outcome_cells(rs)) + " |")
    e1b = group([r for r in rows if r["exp"] == "E1b"], ["strategy", "difficulty"])
    if e1b:
        out += ["", "### T1c. Сильнейший вариант бота: без микро на боссах (E1b, без Мастерской)", "", "| стратегия | сложность " + OUT_HEAD, "|---|---" + OUT_SEP]
        for s in order:
            for d in ["normal", "hard"]:
                if (s, d) in e1b:
                    out.append(f"| {s} | {d} | " + " | ".join(outcome_cells(e1b[(s, d)])) + " |")
    e2 = group([r for r in rows if r["exp"] == "E2"], ["strategy"])
    if e2:
        out += ["", "### T1b. Лёгкая сложность (E2, без Мастерской)", "", "| стратегия " + OUT_HEAD, "|---" + OUT_SEP]
        for s in order:
            if (s,) in e2:
                out.append(f"| {s} | " + " | ".join(outcome_cells(e2[(s,)])) + " |")
    return out


def table_family(rows):
    out = ["### T2. Семейства карт (E1, owner/mixed/adaptive, без Мастерской)", ""]
    out.append("| семейство | сложность | средняя длина дороги | прямая полёта " + OUT_HEAD)
    out.append("|---|---|---|---" + OUT_SEP)
    g = group([r for r in rows if r["exp"] == "E1" and r["workshop"] == 0 and r["strategy"] in ("owner", "mixed", "adaptive")], ["family", "difficulty"])
    for f in ["snake", "vsnake", "stairs", "hooks"]:
        for d in ["normal", "hard"]:
            rs = g.get((f, d))
            if rs:
                out.append(f"| {f} | {d} | {fmt(mean([r['path_len'] for r in rs]))} | {fmt(mean([r['fly_len'] for r in rs]))} | " + " | ".join(outcome_cells(rs)) + " |")
    return out


def table_damage(rows):
    out = ["### T3. Доля урона за забег по типам башен (E1, без Мастерской, только дожившие до 31); в скобках — урон на вложенную монету", ""]
    out.append("| стратегия | сложность | " + " | ".join(KINDS[:-1]) + " |")
    out.append("|---|---|" + "---|" * (len(KINDS) - 1))
    g = group([r for r in rows if r["exp"] == "E1" and r["workshop"] == 0 and r["won30"]], ["strategy", "difficulty"])
    for (s, d), rs in sorted(g.items()):
        cells = []
        for k in KINDS[:-1]:
            share = mean([r["dmg_" + k] for r in rs])
            dpg = [r["abs_" + k] / r["spent_" + k] for r in rs if r["spent_" + k] > 0]
            cells.append("—" if share < 0.0005 else f"{100 * share:.0f}% ({fmt(mean(dpg), 0)})")
        out.append(f"| {s} | {d} | " + " | ".join(cells) + " |")
    return out


def table_ablation(rows):
    out = ["### T4. Предельная ценность: стратегия владельца без одного элемента (E4 против E1 owner без Мастерской)", ""]
    out.append("| вариант | сложность " + OUT_HEAD)
    out.append("|---|---" + OUT_SEP)
    base = group([r for r in rows if r["exp"] == "E1" and r["strategy"] == "owner" and r["workshop"] == 0], ["difficulty"])
    e4 = [r for r in rows if r["exp"] == "E4"]
    for d in ["normal", "hard"]:
        if (d,) in base:
            out.append(f"| **база (owner)** | {d} | " + " | ".join(outcome_cells(base[(d,)])) + " |")
        variants = defaultdict(list)
        for r in e4:
            if r["difficulty"] != d:
                continue
            if r["ablate"]:
                variants["без " + r["ablate"]].append(r)
            elif not r["upgrades"]:
                variants["без улучшений"].append(r)
            elif r["branch"] != "default":
                variants["все ветки " + r["branch"]].append(r)
            elif r["perks"] == "random":
                variants["случайные перки"].append(r)
            elif not r["micro"]:
                variants["без микро на боссе"].append(r)
        for name in sorted(variants):
            out.append(f"| {name} | {d} | " + " | ".join(outcome_cells(variants[name])) + " |")
    return out


def table_swarm(rows):
    out = ["### T5. Вклад эволюции роя (E3 против E1 без Мастерской)", ""]
    out.append("| стратегия | сложность | режим роя | броня (ген) на 15 | эфф. лучника L1 на 15 | утечки к 30 | " + OUT_HEAD[2:])
    out.append("|---|---|---|---|---|---" + OUT_SEP)
    return out


def waves_of(runs, pred):
    by = defaultdict(list)
    for r in runs:
        if not pred(r):
            continue
        for w in r["waves"]:
            if w.get("done") and not w.get("lost"):
                by[w["w"]].append(w)
    return by


def swarm_rows(runs, rows):
    out = table_swarm(rows)
    rowmap = {(r["cell"], r["seed"]): r for r in rows}
    for s in ["owner", "mixed", "arrow_sniper"]:
        for d in ["normal", "hard"]:
            for mode in ["normal", "no_press", "no_select", "drift"]:
                if mode == "normal":
                    sel = [r for r in runs if r["exp"] == "E1" and r["strategy"] == s and r["difficulty"] == d and not r["workshop"]]
                else:
                    sel = [r for r in runs if r["exp"] == "E3" and r["strategy"] == s and r["difficulty"] == d and r["swarm"] == mode]
                if not sel:
                    continue
                w15 = [w for r in sel for w in r["waves"] if w["w"] == 15 and w.get("done") and not w.get("lost")]
                plated = mean([w["genes"]["plated"] for w in w15])
                eff = mean([w["ph"]["arrow1_eff"] for w in w15])
                rs = [rowmap[(r["cell"], r["seed"])] for r in sel]
                out.append(f"| {s} | {d} | {mode} | {fmt(plated, 2)} | {fmt(100 * eff, 0)}% | {fmt(mean([x['leaks_by_30'] for x in rs]))} | " + " | ".join(outcome_cells(rs)) + " |")
    return out


def swarm_genes(runs):
    """T5a: через какие гены отбор и адаптация влияют на исход."""
    out = ["### T5a. Здоровье и скорость роя по режимам эволюции (owner/mixed; E1/E3 без Мастерской; средние по дожившим)", "",
           "| стратегия | сложность | режим роя | ген здоровья w10 / w20 | ген скорости w10 / w20 | ген брони w10 / w20 | HP врага w10 / w20 | HP босса w10 / w20 | p90 гибели врагов на боссовой волне w10 / w20 |",
           "|---|---|---|---|---|---|---|---|---|"]
    for s in ["owner", "mixed"]:
        for d in ["normal", "hard"]:
            for m in ["normal", "no_press", "no_select", "drift"]:
                sel = [r for r in runs if r["strategy"] == s and r["difficulty"] == d and
                       ((r["exp"] == "E1" and not r["workshop"] and m == "normal") or (r["exp"] == "E3" and r["swarm"] == m))]
                ws = {w: [x for r in sel for x in r["waves"] if x["w"] == w and x.get("done") and not x.get("lost")] for w in (10, 20)}
                if not ws[10]:
                    continue
                g = lambda k: " / ".join(fmt(mean([x["genes"][k] for x in ws[w]]), 2) for w in (10, 20))
                hp = " / ".join(fmt(mean([x["ph"]["hp"] for x in ws[w]]), 0) for w in (10, 20))
                bh = " / ".join(fmt(mean([x["boss_hp"] for x in ws[w] if "boss_hp" in x]), 0) for w in (10, 20))
                p9 = " / ".join(fmt(mean([x["prog_g"][1] for x in ws[w] if x["prog_g"][1] >= 0]), 2) for w in (10, 20))
                out.append(f"| {s} | {d} | {m} | {g('tough')} | {g('swift')} | {g('plated')} | {hp} | {bh} | {p9} |")
    return out


def wave_curve(runs, strategy, difficulty, label):
    by = waves_of(runs, lambda r: r["exp"] == "E1" and r["strategy"] == strategy and r["difficulty"] == difficulty and not r["workshop"])
    out = [f"### {label}", "",
           "| волна | n | золото до стройки | доход: убийства | бонус | проценты | вложено всего | HP врага | броня | огнест. | морозост. | скорость | эфф. лучника L1/L3a | летающих | невидимых | гибель земли p50/p90 | гибель воздуха p50/p90 | утечки |",
           "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    csv_rows = []
    for w in sorted(by):
        ws = by[w]
        if w > 40:
            continue
        pg50 = [x["prog_g"][0] for x in ws if x["prog_g"][0] >= 0]
        pg90 = [x["prog_g"][1] for x in ws if x["prog_g"][1] >= 0]
        pa50 = [x["prog_a"][0] for x in ws if x["prog_a"][0] >= 0]
        pa90 = [x["prog_a"][1] for x in ws if x["prog_a"][1] >= 0]
        rec = {
            "strategy": strategy, "difficulty": difficulty, "wave": w, "n": len(ws),
            "gold_pre": mean([x["gold_pre"] for x in ws]), "kill_income": mean([x["kill_income"] for x in ws]),
            "bonus": mean([x["bonus"] for x in ws]), "interest": mean([x["interest"] for x in ws]),
            "invested": mean([x["invested"] for x in ws]), "hp": mean([x["ph"]["hp"] for x in ws]),
            "armor": mean([x["ph"]["armor"] for x in ws]), "fireRes": mean([x["ph"]["fireRes"] for x in ws]),
            "frostRes": mean([x["ph"]["frostRes"] for x in ws]), "speed": mean([x["ph"]["speed"] for x in ws]),
            "arrow1_eff": mean([x["ph"]["arrow1_eff"] for x in ws]), "arrow3a_eff": mean([x["ph"]["arrow3a_eff"] for x in ws]),
            "fly": mean([x["ph"]["fly"] for x in ws]), "stealth": mean([x["ph"]["stealth"] for x in ws]),
            "split": mean([x["ph"]["split"] for x in ws]), "ward": mean([x["ph"]["ward"] for x in ws]),
            "prog_g50": mean(pg50), "prog_g90": mean(pg90), "prog_a50": mean(pa50), "prog_a90": mean(pa90),
            "life_g": mean([x["life_g"][0] for x in ws if x["life_g"][0] >= 0]), "expo_g": mean([x["life_g"][1] for x in ws if x["life_g"][1] >= 0]),
            "life_a": mean([x["life_a"][0] for x in ws if x["life_a"][0] >= 0]), "expo_a": mean([x["life_a"][1] for x in ws if x["life_a"][1] >= 0]),
            "leaked": mean([x["leaked"] for x in ws]), "size": mean([x["size"] for x in ws]),
        }
        for g in ["tough", "swift", "plated", "ember", "frost", "wings", "veil", "regen", "split", "ward"]:
            rec["gene_" + g] = mean([x["genes"][g] for x in ws])
        for g in ["plated", "ember", "frost", "tough"]:
            rec["press_" + g] = mean([x["press"].get(g, 0.0) for x in ws])
        csv_rows.append(rec)
        if w in (1, 3, 5, 8, 10, 12, 15, 18, 20, 22, 25, 28, 30, 33, 35, 38, 40):
            out.append(f"| {w} | {len(ws)} | {fmt(rec['gold_pre'], 0)} | {fmt(rec['kill_income'], 0)} | {fmt(rec['bonus'], 0)} | {fmt(rec['interest'], 0)} | {fmt(rec['invested'], 0)} | {fmt(rec['hp'], 0)} | {fmt(rec['armor'], 2)} | {fmt(100 * rec['fireRes'], 0)}% | {fmt(100 * rec['frostRes'], 0)}% | {fmt(rec['speed'], 2)} | {fmt(100 * rec['arrow1_eff'], 0)}% / {fmt(100 * rec['arrow3a_eff'], 0)}% | {fmt(rec['fly'])} | {fmt(rec['stealth'])} | {fmt(rec['prog_g50'], 2)} / {fmt(rec['prog_g90'], 2)} | {fmt(rec['prog_a50'], 2)} / {fmt(rec['prog_a90'], 2)} | {fmt(rec['leaked'], 2)} |")
    return out, csv_rows


def genome_table(runs):
    out = ["### T7. Геном роя по волнам: среднее значение генов (E1, normal, без Мастерской, только партии, дожившие до волны)", "",
           "| стратегия | волна | здоровье | скорость | броня | огнест. | морозост. | полёт | невид. | лечение | деление | щит | давление: броня / огонь / мороз / HP |",
           "|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for s in ["arrow", "arrow_frost_ember", "owner", "mixed"]:
        by = waves_of(runs, lambda r: r["exp"] == "E1" and r["strategy"] == s and r["difficulty"] == "normal" and not r["workshop"])
        for w in (1, 5, 10, 15, 20, 25, 30):
            ws = by.get(w)
            if not ws:
                continue
            gm = lambda g: fmt(mean([x["genes"][g] for x in ws]), 2)
            pm = lambda g: fmt(mean([x["press"].get(g, 0.0) for x in ws]), 2)
            out.append(f"| {s} | {w} | {gm('tough')} | {gm('swift')} | {gm('plated')} | {gm('ember')} | {gm('frost')} | {gm('wings')} | {gm('veil')} | {gm('regen')} | {gm('split')} | {gm('ward')} | {pm('plated')} / {pm('ember')} / {pm('frost')} / {pm('tough')} |")
    return out


def air_table(runs):
    out = ["### T8. Воздух против земли (E1 owner/mixed, без Мастерской): время жизни и время под огнём, с", "",
           "| стратегия | сложность | волны | земля: жизнь / под огнём / p50 гибели | воздух: жизнь / под огнём / p50 гибели | летающих в волне |",
           "|---|---|---|---|---|---|"]
    for s in ["owner", "mixed"]:
        for d in ["normal", "hard"]:
            by = waves_of(runs, lambda r: r["exp"] == "E1" and r["strategy"] == s and r["difficulty"] == d and not r["workshop"])
            for lo, hi in [(6, 15), (16, 30), (31, 40)]:
                ws = [x for w in range(lo, hi + 1) for x in by.get(w, [])]
                wa = [x for x in ws if x["life_a"][2] > 0]
                if not ws:
                    continue
                out.append(f"| {s} | {d} | {lo}–{hi} | {fmt(mean([x['life_g'][0] for x in ws if x['life_g'][0] >= 0]))} / {fmt(mean([x['life_g'][1] for x in ws if x['life_g'][1] >= 0]))} / {fmt(mean([x['prog_g'][0] for x in ws if x['prog_g'][0] >= 0]), 2)} | {fmt(mean([x['life_a'][0] for x in wa]))} / {fmt(mean([x['life_a'][1] for x in wa]))} / {fmt(mean([x['prog_a'][0] for x in wa if x['prog_a'][0] >= 0]), 2)} | {fmt(mean([x['ph']['fly'] for x in ws]))} |")
    return out


def leaks_by_type(runs):
    out = ["### T9. Откуда берутся потери жизней (owner/mixed/adaptive, без Мастерской, волны 1–30)", "",
           "| эксперимент | сложность | всего партий | жизней потеряно | на боссовых волнах | на особых волнах | на обычных волнах | партий проиграно | проиграно на боссовой волне |",
           "|---|---|---|---|---|---|---|---|---|"]
    for exp, d in [(e, d) for e in ("E1", "E1b") for d in ("normal", "hard")]:
        sel = [r for r in runs if r["exp"] == exp and r["strategy"] in ("owner", "mixed", "adaptive") and r["difficulty"] == d and not r["workshop"]]
        if not sel:
            continue
        boss = special = normal = 0
        lost = lost_boss = 0
        for r in sel:
            for w in r["waves"]:
                if w["w"] > 30:
                    continue
                ll = int(w.get("lives_lost", 0) or 0)
                if w.get("lost"):
                    ll = int(w.get("lives0", 0))
                if w["w"] % 10 == 0:
                    boss += ll
                elif w.get("special"):
                    special += ll
                elif w["w"] % 5 == 0 and w["w"] % 10 != 0:
                    special += ll
                else:
                    normal += ll
            if not r["summary"]["won30"]:
                lost += 1
                if r["summary"]["end_wave"] % 10 == 0:
                    lost_boss += 1
        tot = boss + special + normal or 1
        out.append(f"| {exp} | {d} | {len(sel)} | {tot} | {boss} ({100 * boss / tot:.0f}%) | {special} ({100 * special / tot:.0f}%) | {normal} ({100 * normal / tot:.0f}%) | {lost} | {lost_boss} |")
    return out


def switch_table(runs):
    """T10: реакция текущего роя на смену обороны (E5 switch против E1 owner, normal, с Мастерской)."""
    sw = waves_of(runs, lambda r: r["exp"] == "E5" and r["strategy"] == "switch")
    base = waves_of(runs, lambda r: r["exp"] == "E1" and r["strategy"] == "owner" and r["difficulty"] == "normal" and r["workshop"])
    if not sw:
        return []
    out = ["### T10. Смена обороны на 13-й волне: физика → огонь/яд/Тесла/лёд (E5 switch против E1 owner; normal, Мастерская)", "",
           "| волна | n | давление на броню: switch / owner | ген брони: switch / owner | огнест.: switch / owner | здоровье: switch / owner | эфф. лучника L1 (switch) | p90 гибели: switch / owner |",
           "|---|---|---|---|---|---|---|---|"]
    for w in range(8, 31):
        a, b = sw.get(w, []), base.get(w, [])
        if not a:
            continue
        g = lambda ws, k: fmt(mean([x["genes"][k] for x in ws]), 2)
        pr = lambda ws, k: fmt(mean([x["press"].get(k, 0.0) for x in ws]), 2)
        p90 = lambda ws: fmt(mean([x["prog_g"][1] for x in ws if x["prog_g"][1] >= 0]), 2)
        out.append(f"| {w} | {len(a)} | {pr(a, 'plated')} / {pr(b, 'plated')} | {g(a, 'plated')} / {g(b, 'plated')} | {g(a, 'ember')} / {g(b, 'ember')} | {g(a, 'tough')} / {g(b, 'tough')} | {fmt(100 * mean([x['ph']['arrow1_eff'] for x in a]), 0)}% | {p90(a)} / {p90(b)} |")
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    os.makedirs(dst, exist_ok=True)
    runs = []
    for d in src.split(","):
        new = load(d)
        cells = {r["cell"] for r in new}
        runs = [r for r in runs if r["cell"] not in cells] + new  # более поздняя папка заменяет одноимённые ячейки
    rows = [row(r) for r in runs]
    with open(os.path.join(dst, "runs.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        w.writeheader()
        w.writerows(rows)
    md = [f"<!-- generated by tests/balance_report.py from {len(runs)} runs -->", ""]
    md += table_e1(rows) + [""] + table_family(rows) + [""] + table_damage(rows) + [""] + table_ablation(rows) + [""]
    md += swarm_rows(runs, rows) + [""] + swarm_genes(runs) + [""]
    all_csv = []
    for s, d in [("owner", "normal"), ("owner", "hard"), ("arrow", "normal"), ("mixed", "normal"), ("arrow_frost_ember", "normal")]:
        t, c = wave_curve(runs, s, d, f"T6 · {s} / {d}: кривая по волнам (E1, без Мастерской; средние по партиям, дожившим до волны)")
        all_csv += c
        if s in ("owner",):
            md += t + [""]
    with open(os.path.join(dst, "waves.csv"), "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(all_csv[0].keys()))
        w.writeheader()
        for rec in all_csv:
            w.writerow({k: (round(v, 4) if isinstance(v, float) else v) for k, v in rec.items()})
    md += genome_table(runs) + [""] + air_table(runs) + [""] + leaks_by_type(runs) + [""] + switch_table(runs) + [""]
    with open(os.path.join(dst, "tables.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(md) + "\n")
    print(f"{len(runs)} runs -> {dst}")


if __name__ == "__main__":
    main()
