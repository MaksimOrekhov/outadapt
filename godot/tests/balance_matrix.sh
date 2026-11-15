#!/usr/bin/env bash
# PRO-151: полная матрица баланс-прогонов (tests/balance_audit.gd) параллельно, по процессу на ячейку.
# Запуск из папки godot:  GODOT=<консольный Godot 4.7.2> bash tests/balance_matrix.sh [out_dir=../build/balance/runs] [jobs=11] [seeds=10]
# Затем сводка:          python tests/balance_report.py ../build/balance/runs ../docs/balance/data
# Каждая ячейка пишет <out_dir>/<имя>.jsonl; список команд — <out_dir>/commands.txt.
set -u
OUT=${1:-../build/balance/runs}
JOBS=${2:-11}
SEEDS=${3:-10}
G=${GODOT:-/d/Godot/Godot_v4.7.2-stable_win64_console.exe}
CAP=40
mkdir -p "$OUT"
CMDS="$OUT/commands.txt"
: > "$CMDS"
FAMS="snake vsnake stairs hooks"

add() { # имя, аргументы
  local name=$1; shift
  echo "\"$G\" --headless --path . --script res://tests/balance_audit.gd -- --seeds=$SEEDS --cap=$CAP $* --out=$OUT/$name.jsonl" >> "$CMDS"
}

# E1: основная матрица — 7 стратегий × normal/hard × 4 семейства × без/с Мастерской
for s in arrow sniper arrow_sniper arrow_frost_ember owner mixed adaptive; do
  for d in normal hard; do
    for f in $FAMS; do
      for w in 0 1; do add "E1_${s}_${d}_${f}_ws$w" --strategy=$s --difficulty=$d --family=$f --workshop=$w; done
    done
  done
done
# E2: лёгкая сложность для кривой сложности
for s in arrow arrow_sniper owner mixed; do
  for f in $FAMS; do add "E2_${s}_easy_${f}_ws0" --strategy=$s --difficulty=easy --family=$f; done
done
# E3: вклад эволюции — без направленной адаптации, без отбора, чистый дрейф
for s in owner mixed arrow_sniper; do
  for m in no_press no_select drift; do
    for d in normal hard; do
      for f in $FAMS; do add "E3_${s}_${m}_${d}_${f}" --strategy=$s --swarm=$m --difficulty=$d --family=$f; done
    done
  done
done
# E4: предельная ценность — стратегия владельца без одного типа башен, без улучшений, ветки, перки, микро
for d in normal hard; do
  for f in $FAMS; do
    for k in arrow sniper frost ember poison tesla beacon; do add "E4_owner_no-${k}_${d}_${f}" --strategy=owner --ablate=$k --difficulty=$d --family=$f; done
    add "E4_owner_noupg_${d}_${f}" --strategy=owner --no-upgrades --difficulty=$d --family=$f
    add "E4_owner_branchA_${d}_${f}" --strategy=owner --branch=a --difficulty=$d --family=$f
    add "E4_owner_branchB_${d}_${f}" --strategy=owner --branch=b --difficulty=$d --family=$f
    add "E4_owner_randperks_${d}_${f}" --strategy=owner --perks=random --difficulty=$d --family=$f
    add "E4_owner_nomicro_${d}_${f}" --strategy=owner --micro=0 --difficulty=$d --family=$f
  done
done

# E1b: сильнейший вариант бота — без микро на боссах (E4 показал, что режим «Сильный» на боссовых волнах вредит)
for s in owner mixed adaptive; do
  for d in normal hard; do
    for f in $FAMS; do add "E1b_${s}_${d}_${f}_ws0" --strategy=$s --difficulty=$d --family=$f --micro=0; done
  done
done
# E5: смена обороны на 13-й волне (физика → огонь/яд/Тесла/лёд), normal, с Мастерской — латентность ответа роя
for f in $FAMS; do add "E5_switch_normal_${f}_ws1" --strategy=switch --difficulty=normal --family=$f --workshop=1; done

echo "cells: $(wc -l < "$CMDS"), jobs: $JOBS, seeds: $SEEDS, cap: $CAP"
date
# shellcheck disable=SC2016
tr '\n' '\0' < "$CMDS" | xargs -0 -P "$JOBS" -I{} bash -c '{} > /dev/null 2>&1'
date
echo "done: $(ls "$OUT"/*.jsonl | wc -l) files"
