#!/usr/bin/env bash
# PRO-212: независимые абляции дальности. Запуск из папки godot:
#   GODOT=<консольный Godot 4.7.2> bash tests/range_ablate.sh [jobs=11] [seeds=10]
# Ячейки: 4 стратегии × normal/hard × 4 семейства, адаптация OFF, без Мастерской, до 30-й волны.
# Плечи (5): none — без изменений; norange — улучшения и перк без прибавки дальности (A); nodmg — улучшения без прибавки
# урона/скорострельности (B); noperk — только перк дальности (C); nobranch — только дальность веток L3 (D).
# Этап 1 «политика»: бот сам строит оборону в каждом плече (реакция покупок включена).
# Этап 2 «повтор»: покупки, размещение, улучшения и перки плеча none повторяются в каждом плече (те же действия,
# золото не ограничивает) — причинность без реакции бота. Имена: <стратегия>_<сложность>_off_<семейство>_<плечо>,
# повтор — плечо rp-<плечо>. Вывод: ../build/range/ablate/; сводка: python tests/range_report.py ablate
set -u
JOBS=${1:-11}
SEEDS=${2:-10}
G=${GODOT:-/d/Godot/Godot_v4.7.2-stable_win64_console.exe}
OUT=../build/range/ablate
mkdir -p "$OUT/rec"
FAMS="snake vsnake stairs hooks"
# ARMS можно задать снаружи (например ARMS="nol2:--range-variant=abl_nol2" — дополнительное плечо к уже записанным
# покупкам none; повтор берёт rec/ из прошлого запуска)
ARMS=${ARMS:-"none: norange:--range-variant=abl_norange nodmg:--range-variant=abl_nodmg noperk:--range-variant=abl_noperk nobranch:--range-variant=abl_nobranch nol2:--range-variant=abl_nol2"}
run() { tr '\n' '\0' < "$1" | xargs -0 -P "$JOBS" -I{} sh -c '{} > /dev/null 2>&1'; }

C1="$OUT/commands_policy.txt"; : > "$C1"
C2="$OUT/commands_replay.txt"; : > "$C2"
for s in owner2 mixed adaptive owner; do
  for d in normal hard; do
    for f in $FAMS; do
      cell="${s}_${d}_off_${f}"
      base="\"$G\" --headless --path . --script res://tests/balance_audit.gd -- --seeds=$SEEDS --cap=30 --late=1 --strategy=$s --difficulty=$d --family=$f"
      for arm in $ARMS; do
        tag=${arm%%:*}; extra=${arm#*:}
        rec=""
        [ "$tag" = none ] && rec="--record=$OUT/rec/$cell.json"
        echo "$base $extra $rec --out=$OUT/${cell}_${tag}.jsonl" >> "$C1"
        echo "$base $extra --replay=$OUT/rec/$cell.json --out=$OUT/${cell}_rp-${tag}.jsonl" >> "$C2"
      done
    done
  done
done
echo "policy cells: $(wc -l < "$C1")  replay cells: $(wc -l < "$C2")  seeds: $SEEDS  out: $OUT"
run "$C1"
echo "policy done: $(ls "$OUT"/*.jsonl | wc -l) files"
run "$C2"
echo "done: $(ls "$OUT"/*.jsonl | wc -l) files"
