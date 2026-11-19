#!/usr/bin/env bash
# PRO-213: боты на сгенерированных развилках. Запуск из папки godot:
#   GODOT=<консольный Godot 4.7.2> bash tests/fork_matrix.sh [jobs=11] [seeds=10] [seed_from=0]
# 4 стратегии × normal/hard × fork_even/fork_skew, без флага и Мастерской, до 35-й волны, --late=1 (метрики по дорогам).
# Те же сиды и ячейки, что база PRO-212 на одиночных картах (../build/range/base, хвост ws0) — сравнение один к одному.
# Вывод: ../build/fork/matrix/<стратегия>_<сложность>_off_<семейство>_ws0.jsonl; сводка: python tests/fork_report.py
set -u
JOBS=${1:-11}
SEEDS=${2:-10}
FROM=${3:-0}
G=${GODOT:-/d/Godot/Godot_v4.7.2-stable_win64_console.exe}
OUT=../build/fork/matrix
mkdir -p "$OUT"
CMDS="$OUT/commands.txt"
: > "$CMDS"
for s in owner2 mixed adaptive owner; do
  for d in normal hard; do
    for f in fork_even fork_skew; do
      echo "\"$G\" --headless --path . --script res://tests/balance_audit.gd -- --seeds=$SEEDS --seed-from=$FROM --cap=35 --late=1 --strategy=$s --difficulty=$d --family=$f --out=$OUT/${s}_${d}_off_${f}_ws0.jsonl" >> "$CMDS"
    done
  done
done
echo "cells: $(wc -l < "$CMDS")  seeds: $SEEDS from $FROM  out: $OUT"
tr '\n' '\0' < "$CMDS" | xargs -0 -P "$JOBS" -I{} sh -c '{} > /dev/null 2>&1'
echo "done: $(ls "$OUT"/*.jsonl | wc -l) files"
