#!/usr/bin/env bash
# PRO-192: диагностика источников снежного кома — те же ячейки, что в базе (normal, без флага, 4 семейства),
# но без одного источника силы обороны. Сравнивать с ../build/late/base (ячейки *_normal_off_*_ws0).
#   noupg — без улучшений башен (только постройка);  rperk — перки наугад, а не лучшие;
#   nosnp — без Снайпера (главного дальнобоя, накрывающего вход с любой клетки).
# Запуск из папки godot: bash tests/late_diag.sh [jobs=11] [seeds=10]
set -u
JOBS=${1:-11}
SEEDS=${2:-10}
G=${GODOT:-/d/Godot/Godot_v4.7.2-stable_win64_console.exe}
OUT=../build/late/diag
mkdir -p "$OUT"
CMDS="$OUT/commands.txt"
: > "$CMDS"
for s in owner2 mixed; do
  for f in snake vsnake stairs hooks; do
    for c in "noupg:--no-upgrades" "rperk:--perks=random" "nosnp:--ablate=sniper"; do
      echo "\"$G\" --headless --path . --script res://tests/balance_audit.gd -- --seeds=$SEEDS --cap=35 --late=1 --strategy=$s --difficulty=normal --family=$f ${c#*:} --out=$OUT/${s}_normal_off_${f}_${c%%:*}.jsonl" >> "$CMDS"
    done
  done
done
echo "cells: $(wc -l < "$CMDS")  seeds: $SEEDS  out: $OUT"
tr '\n' '\0' < "$CMDS" | xargs -0 -P "$JOBS" -I{} sh -c '{} > /dev/null 2>&1'
echo "done: $(ls "$OUT"/*.jsonl | wc -l) files"
