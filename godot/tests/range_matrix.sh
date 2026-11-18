#!/usr/bin/env bash
# PRO-212: итоговая матрица варианта дальности. Запуск из папки godot:
#   GODOT=<консольный Godot 4.7.2> bash tests/range_matrix.sh <тег> [jobs=11] [seeds=10] [seed_from=0] [-- доп. аргументы]
# Те же ячейки, что в PRO-192 (tests/late_matrix.sh): 4 стратегии × normal/hard × OFF/ON (signature) × 4 семейства, без
# Мастерской; плюс Мастерская на максимуме для owner2 и mixed на Hard. До 35-й волны (проверка режима 30+).
# seed_from: 0 — основные сиды (как в PRO-192), 1000 — отложенный набор (сиды (1000+i+1)·4243, ни разу не смотрели).
# Плюс ячейки веток L3 (хвост br-*): mixed и owner2, normal/hard, OFF, 4 семейства — вторая ветка Снайпера или Пушки.
# Вывод: ../build/range/<тег>/; сводка: python tests/range_report.py compare <база> <тег>
set -u
TAG=${1:?tag}
JOBS=${2:-11}
SEEDS=${3:-10}
FROM=${4:-0}
shift $(( $# >= 4 ? 4 : $# ))
[ "${1:-}" = "--" ] && shift
EXTRA="$*"
G=${GODOT:-/d/Godot/Godot_v4.7.2-stable_win64_console.exe}
OUT=../build/range/$TAG
mkdir -p "$OUT"
CMDS="$OUT/commands.txt"
: > "$CMDS"
FAMS="snake vsnake stairs hooks"
add() { local name=$1; shift
  echo "\"$G\" --headless --path . --script res://tests/balance_audit.gd -- --seeds=$SEEDS --seed-from=$FROM --cap=35 --late=1 $* $EXTRA --out=$OUT/$name.jsonl" >> "$CMDS"; }
for s in owner2 mixed adaptive owner; do
  for d in normal hard; do
    for m in off signature; do
      for f in $FAMS; do
        mm=""; [ "$m" = signature ] && mm="--model=signature"
        add "${s}_${d}_${m}_${f}_ws0" --strategy=$s --difficulty=$d --family=$f $mm
      done
    done
  done
done
for s in owner2 mixed; do
  for m in off signature; do
    for f in $FAMS; do
      mm=""; [ "$m" = signature ] && mm="--model=signature"
      add "${s}_hard_${m}_${f}_ws1" --strategy=$s --difficulty=hard --family=$f --workshop=1 $mm
    done
  done
done
# ветки L3: по умолчанию Снайпер «Дальнобой» (b), Пушка «Осадная» (b), у owner2 — «Мортира» (a)
for s in owner2 mixed; do
  for d in normal hard; do
    for f in $FAMS; do
      add "${s}_${d}_off_${f}_br-sniper-a" --strategy=$s --difficulty=$d --family=$f --branch-set=sniper:a
      if [ "$s" = owner2 ]; then add "${s}_${d}_off_${f}_br-cannon-b" --strategy=$s --difficulty=$d --family=$f --branch-set=cannon:b
      else add "${s}_${d}_off_${f}_br-cannon-a" --strategy=$s --difficulty=$d --family=$f --branch-set=cannon:a; fi
    done
  done
done
echo "cells: $(wc -l < "$CMDS")  seeds: $SEEDS from $FROM  extra: '$EXTRA'  out: $OUT"
tr '\n' '\0' < "$CMDS" | xargs -0 -P "$JOBS" -I{} sh -c '{} > /dev/null 2>&1'
echo "done: $(ls "$OUT"/*.jsonl | wc -l) files"
