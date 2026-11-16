#!/usr/bin/env python3
"""PRO-115: сводка журнала живого плейтеста (user://playtest/<run>.jsonl) для протокола наблюдателя.

python tests/playtest_summary.py <файл.jsonl> [ещё файлы...] > summary.md

Для каждого забега: конфигурация (сборка, флаг, сид, семейство, сложность, Мастерская), поволновая таблица
(жизни, золото, утечки, что построено/улучшено/продано/перенацелено, пакеты в волне, фазы пакетов после волны,
сигнатура) и ключевые события: первый анонс, первое появление, первая постройка башни-ответа после анонса,
жизни, потерянные до и после ответа. Сопоставляйте с поминутными заметками наблюдателя: журнал фиксирует,
ЧТО сделал игрок, а ПОЧЕМУ — только интервью.
"""
import json
import sys

ANSWERS = {"brood": {"arrow", "cannon", "tesla", "poison", "frost"},
           "hulk": {"sniper", "cannon", "tesla", "poison"},
           "flock": {"flak", "net", "arrow", "sniper"}}
NAMES = {"brood": "Выводок", "hulk": "Панцирники", "flock": "Стая"}


def load(path):
    rows = []
    for line in open(path, encoding="utf-8"):
        line = line.strip()
        if line:
            rows.append(json.loads(line))
    return rows


def summarize(path):
    rows = load(path)
    out = []
    run = next((r for r in rows if r.get("event") == "run"), {})
    out.append(f"## {path.replace(chr(92), '/').split('/')[-1]}")
    out.append("")
    out.append(f"сборка `{run.get('build', '?')}` · модель `{run.get('swarm_model', '?')}` · сид {run.get('seed', '?')} · "
               f"{run.get('family', '?')} · {run.get('difficulty', '?')} · режим {run.get('mode', '?')} · "
               f"Мастерская {'да' if run.get('workshop', True) else 'нет'} {run.get('workshop_bonuses', {})} · окно {run.get('window', '?')}")
    out.append("")
    out.append("| волна | жизни старт→конец | утечки | пакеты в волне | построено / улучшено / продано / прицел | после волны: фазы роя | burst / rapid / небо |")
    out.append("|---|---|---|---|---|---|---|")
    starts = {r["wave"]: r for r in rows if r.get("event") == "start"}
    ends = {r["wave"]: r for r in rows if r.get("event") == "end"}
    first_ann, first_act, first_answer = {}, {}, {}
    for w in sorted(set(starts) | set(ends)):
        s, e = starts.get(w, {}), ends.get(w, {})
        sw = s.get("strains_in_wave", {})
        for p in sw:
            first_act.setdefault(p, w)
        acts = " / ".join(", ".join(s.get(k, [])) or "—" for k in ("built", "upgraded", "sold", "retargeted"))
        for p, w0 in first_ann.items():
            if p not in first_answer and any(b in ANSWERS[p] for b in s.get("built", [])) and w > w0:
                first_answer[p] = w
        fc = []
        for f in e.get("forecast", []):
            tail = f" → в {f['appear']}" if f["phase"] == "announced" else (f" {min(1.0, f['inc']):.0%}" if f["phase"] == "incubating" else f" {f['share']:.0%} волны")
            fc.append(f"{NAMES.get(f['id'], f['id'])}: {f['phase']}{tail}")
            if f["phase"] == "announced":
                first_ann.setdefault(f["id"], w)
        out.append(f"| {w} | {s.get('lives', '?')}→{e.get('lives', '?')} | {e.get('leaked', '—')} | "
                   f"{', '.join(f'{NAMES.get(k, k)} {v}' for k, v in sw.items()) or '—'} | {acts} | {'; '.join(fc) or '—'} | "
                   f"{e.get('burst', '—')} / {e.get('rapid', '—')} / {e.get('air_gap', '—')} |")
    over = next((r for r in rows if r.get("event") == "over"), None)
    out.append("")
    out.append("**Ключевые события**")
    for p in NAMES:
        if p in first_ann or p in first_act:
            ans = first_answer.get(p)
            out.append(f"- {NAMES[p]}: анонс после волны {first_ann.get(p, '—')}, в бою с волны {first_act.get(p, '—')}, "
                       f"первая башня-ответ построена перед волной {ans if ans else '— (не строил)'}")
    if over:
        out.append(f"- конец забега: волна {over.get('wave')}, победа {over.get('victory')}, жизни {over.get('lives')}")
    out.append("")
    return "\n".join(out)


if __name__ == "__main__":
    sys.stdout.reconfigure(encoding="utf-8")
    for p in sys.argv[1:]:
        print(summarize(p))
