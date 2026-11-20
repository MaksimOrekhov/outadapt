#!/usr/bin/env bash
# PRO-214: плечи эксперимента «постепенный ввод второй дороги» на сгенерированных развилках. Запуск из папки godot:
#   GODOT=<консольный Godot 4.7.2> ARMS="a b_short" [MODELS="off signature"] [WS="0 1"] [STRATS="owner2 mixed adaptive owner"] \
#     bash tests/fork_ramp_matrix.sh <тег> [jobs=11] [seeds=10] [seed_from=0]
# Плечи (ARMS):
#   a        — как сейчас: 50/50 с первой волны (то же, что tests/fork_matrix.sh PRO-213, байт-в-байт);
#   b_short  — расписание pilot (1–2: 100/0, 3–4: 80/20, 5–6: 65/35, с 7-й: 50/50), первой идёт КОРОТКАЯ дорога;
#   b_long   — то же, первой идёт ДЛИННАЯ дорога;
#   e_short  — ограниченный пилот более раннего ввода early (1: 100/0, 2–3: 90/10, 4–5: 70/30, с 6-й: 50/50), первая — короткая;
#   e_long   — то же, первая — длинная;
#   c25, c50 — диагностический контроль: единовременно +25 / +50 золота на старте, поток 50/50, экономика дальше прежняя;
#   d_short  — вариант D: pilot (первая короткая) + 25 золота на старте (только если B и пилот показывают нужду).
# Ячейка: стратегия × normal/hard × модель (off/signature) × fork_even/fork_skew × Мастерская (WS: 0 — без неё, 1 — на максимуме).
# Вывод: ../build/ramp/<тег>/<плечо>/<стратегия>_<сложность>_<модель>_<семейство>_ws<0|1>.jsonl; сводка: python tests/fork_ramp_report.py
# Возобновление: ячейка с полным числом партий пропускается.
set -u
TAG=${1:?tag}
JOBS=${2:-11}
SEEDS=${3:-10}
FROM=${4:-0}
ARMS=${ARMS:-a b_short}
MODELS=${MODELS:-off}
WS=${WS:-0}
STRATS=${STRATS:-owner2 mixed adaptive owner}
DIFFS=${DIFFS:-normal hard}
G=${GODOT:-/d/Godot/Godot_v4.7.2-stable_win64_console.exe}
OUTB=../build/ramp/$TAG
mkdir -p "$OUTB"
CMDS="$OUTB/commands.txt"
TODO="$OUTB/commands_todo.txt"
: > "$CMDS"; : > "$TODO"
SKIP=0
arm_args() {
  case "$1" in
    a) echo "" ;;
    b_short) echo "--ramp=pilot:short" ;;
    b_long) echo "--ramp=pilot:long" ;;
    e_short) echo "--ramp=early:short" ;;
    e_long) echo "--ramp=early:long" ;;
    c25) echo "--start-gold=25" ;;
    c50) echo "--start-gold=50" ;;
    d_short) echo "--ramp=pilot:short --start-gold=25" ;;
    *) echo "unknown arm $1" >&2; exit 2 ;;
  esac
}
for arm in $ARMS; do
  A=$(arm_args "$arm") || exit 2
  OUT=$OUTB/$arm
  mkdir -p "$OUT"
  for s in $STRATS; do
    for d in $DIFFS; do
      for m in $MODELS; do
        for ws in $WS; do
          for f in fork_even fork_skew; do
            mm=""; [ "$m" = signature ] && mm="--model=signature"
            wsf=""; [ "$ws" = 1 ] && wsf="--workshop=1"
            name="${s}_${d}_${m}_${f}_ws${ws}"
            c="\"$G\" --headless --path . --script res://tests/balance_audit.gd -- --seeds=$SEEDS --seed-from=$FROM --cap=35 --late=1 --strategy=$s --difficulty=$d --family=$f $mm $wsf $A --out=$OUT/$name.jsonl"
            echo "$c" >> "$CMDS"
            if [ -f "$OUT/$name.jsonl" ] && [ "$(wc -l < "$OUT/$name.jsonl")" -ge "$SEEDS" ]; then SKIP=$((SKIP + 1)); continue; fi
            rm -f "$OUT/$name.jsonl"
            echo "$c" >> "$TODO"
          done
        done
      done
    done
  done
done
echo "arms: $ARMS  cells: $(wc -l < "$CMDS"), to run: $(wc -l < "$TODO") (complete, skipped: $SKIP)  seeds: $SEEDS from $FROM  out: $OUTB"
tr '\n' '\0' < "$TODO" | xargs -0 -P "$JOBS" -I{} sh -c '{} > /dev/null 2>&1'
echo "done: $(find "$OUTB" -name '*.jsonl' | wc -l) files"
