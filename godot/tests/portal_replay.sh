#!/usr/bin/env bash
# PRO-141: замороженный повтор покупок. Запуск из папки godot:
#   GODOT=<консольный Godot 4.7.2> bash tests/portal_replay.sh [jobs=11] [seeds=10] [seed_from=1000]
# Покупки, улучшения, продажи и перки записываются в партиях бота (до 24-й волны) в двух режимах:
#   rec_ctl — бот при контроле «один активный портал» (обороны под второй вход нет);
#   rec_p18 — бот при p18 (предупреждение с 15-й волны, открытие с 18-й; оборона отвечает на второй вход).
# Затем те же действия в те же волны повторяются дословно (золото не ограничивает), расписание меняется:
#   ctl_in_ctl, ctl_in_p18, ctl_in_p21 — оборона «не ответившего» игрока при контроле / при открытии с 18-й / с 21-й;
#   p18_in_p18, p18_in_ctl             — оборона «ответившего» игрока при открытии с 18-й и при контроле.
# Так видно, что второй портал делает с той же обороной, без вклада решений бота. Сводка: python tests/portal_report.py --replay=../build/portal/replay
set -u
JOBS=${1:-11}
SEEDS=${2:-10}
FROM=${3:-1000}
G=${GODOT:-/d/Godot/Godot_v4.7.2-stable_win64_console.exe}
OUT=../build/portal/replay
mkdir -p "$OUT"
REC="$OUT/commands_record.txt"; PLAY="$OUT/commands_play.txt"
: > "$REC"; : > "$PLAY"
CTL="--portal-open=999 --portal-announce=999"
P18="--portal-open=18 --portal-announce=15"
P21="--portal-open=21 --portal-announce=18"
for s in owner2 mixed adaptive owner; do
  for d in normal hard; do
    for f in portal_a portal_b; do
      n="${s}_${d}_${f}"
      base="\"$G\" --headless --path . --script res://tests/balance_audit.gd -- --seeds=$SEEDS --seed-from=$FROM --cap=24 --late=1 --strategy=$s --difficulty=$d --family=$f"
      echo "$base $CTL --record=$OUT/rec_ctl_$n.json --out=$OUT/rec_ctl_$n.jsonl" >> "$REC"
      echo "$base $P18 --record=$OUT/rec_p18_$n.json --out=$OUT/rec_p18_$n.jsonl" >> "$REC"
      for spec in "ctl_in_ctl:rec_ctl:$CTL" "ctl_in_p18:rec_ctl:$P18" "ctl_in_p21:rec_ctl:$P21" "p18_in_p18:rec_p18:$P18" "p18_in_ctl:rec_p18:$CTL"; do
        IFS=: read arm rec args <<< "$spec"
        mkdir -p "$OUT/$arm"
        echo "$base $args --replay=$OUT/${rec}_$n.json --out=$OUT/$arm/$n.jsonl" >> "$PLAY"
      done
    done
  done
done
tr '\n' '\0' < "$REC" | xargs -0 -P "$JOBS" -I{} sh -c '{} > /dev/null 2>&1'
tr '\n' '\0' < "$PLAY" | xargs -0 -P "$JOBS" -I{} sh -c '{} > /dev/null 2>&1'
echo "done: $(find "$OUT" -name '*.jsonl' | wc -l) files"
