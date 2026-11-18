#!/usr/bin/env bash
# PRO-192: матрица поздней игры (tests/balance_audit.gd --late=1) параллельно, по процессу на ячейку.
# Запуск из папки godot:
#   GODOT=<консольный Godot 4.7.2> bash tests/late_matrix.sh <тег> [jobs=11] [seeds=10] [-- доп. аргументы харнесса]
# Тег — имя прогона (base, A, B, ...); доп. аргументы (например --late-variant=B) идут в каждую ячейку.
# Ячейки пишут ../build/late/<тег>/<ячейка>.jsonl; сводка: python tests/late_report.py ../build/late/<тег> [...]
set -u
TAG=${1:?tag}
JOBS=${2:-11}
SEEDS=${3:-10}
shift $(( $# >= 3 ? 3 : $# ))
[ "${1:-}" = "--" ] && shift
EXTRA="$*"
G=${GODOT:-/d/Godot/Godot_v4.7.2-stable_win64_console.exe}
OUT=../build/late/$TAG
mkdir -p "$OUT"
CMDS="$OUT/commands.txt"
: > "$CMDS"
FAMS="snake vsnake stairs hooks"

add() { # имя, аргументы
  local name=$1; shift
  echo "\"$G\" --headless --path . --script res://tests/balance_audit.gd -- --seeds=$SEEDS --cap=35 --late=1 $* $EXTRA --out=$OUT/$name.jsonl" >> "$CMDS"
}

for s in owner2 mixed adaptive owner; do
  for d in normal hard; do
    for m in off signature; do
      for f in $FAMS; do
        if [ "$m" = off ]; then add "${s}_${d}_${m}_${f}_ws0" --strategy=$s --difficulty=$d --family=$f; else add "${s}_${d}_${m}_${f}_ws0" --strategy=$s --difficulty=$d --family=$f --model=$m; fi
      done
    done
  done
done
# Мастерская на максимуме: поздняя сборка владельца и смешанная, Hard, OFF и ON
for s in owner2 mixed; do
  for m in off signature; do
    for f in $FAMS; do
      if [ "$m" = off ]; then add "${s}_hard_${m}_${f}_ws1" --strategy=$s --difficulty=hard --family=$f --workshop=1; else add "${s}_hard_${m}_${f}_ws1" --strategy=$s --difficulty=hard --family=$f --workshop=1 --model=$m; fi
    done
  done
done

echo "cells: $(wc -l < "$CMDS")  seeds: $SEEDS  extra: '$EXTRA'  out: $OUT"
tr '\n' '\0' < "$CMDS" | xargs -0 -P "$JOBS" -I{} sh -c '{} > /dev/null 2>&1'
echo "done: $(ls "$OUT"/*.jsonl | wc -l) files"
