#!/usr/bin/env bash
# PRO-214: замороженный повтор покупок. Запуск из папки godot:
#   GODOT=<консольный Godot 4.7.2> bash tests/fork_ramp_replay.sh [jobs=11] [seeds=10] [seed_from=1000]
# Покупки, улучшения, продажи и перки бота записываются в партиях плеча A (50/50, до 12-й волны) и повторяются дословно
# в тех же волнах при расписании pilot (первая дорога короткая / длинная) и early — золото не ограничивает, бюджет в плечах
# одинаков. Так видно, что расписание само делает с той же обороной, без вклада решений бота.
# Вывод: ../build/ramp/replay/rec_<стратегия>_<сложность>_<семейство>.json и <плечо>/<стратегия>_<сложность>_<семейство>.jsonl,
# плечи: base (повтор в 50/50, контроль повтора), p_short, p_long, e_short. Сводка: python tests/fork_ramp_report.py --replay=../build/ramp/replay
set -u
JOBS=${1:-11}
SEEDS=${2:-10}
FROM=${3:-1000}
G=${GODOT:-/d/Godot/Godot_v4.7.2-stable_win64_console.exe}
OUT=../build/ramp/replay
mkdir -p "$OUT"
REC="$OUT/commands_record.txt"; PLAY="$OUT/commands_play.txt"
: > "$REC"; : > "$PLAY"
for s in owner2 mixed adaptive owner; do
  for d in normal hard; do
    for f in fork_even fork_skew; do
      n="${s}_${d}_${f}"
      echo "\"$G\" --headless --path . --script res://tests/balance_audit.gd -- --seeds=$SEEDS --seed-from=$FROM --cap=12 --late=1 --strategy=$s --difficulty=$d --family=$f --record=$OUT/rec_$n.json --out=$OUT/rec_$n.jsonl" >> "$REC"
      for arm in "base:" "p_short:--ramp=pilot:short" "p_long:--ramp=pilot:long" "e_short:--ramp=early:short"; do
        a=${arm%%:*}; x=${arm#*:}
        mkdir -p "$OUT/$a"
        echo "\"$G\" --headless --path . --script res://tests/balance_audit.gd -- --seeds=$SEEDS --seed-from=$FROM --cap=12 --late=1 --strategy=$s --difficulty=$d --family=$f --replay=$OUT/rec_$n.json $x --out=$OUT/$a/$n.jsonl" >> "$PLAY"
      done
    done
  done
done
tr '\n' '\0' < "$REC" | xargs -0 -P "$JOBS" -I{} sh -c '{} > /dev/null 2>&1'
tr '\n' '\0' < "$PLAY" | xargs -0 -P "$JOBS" -I{} sh -c '{} > /dev/null 2>&1'
echo "done: $(find "$OUT" -name '*.jsonl' | wc -l) files"
