#!/usr/bin/env bash
# PRO-152: парные A/B-прогоны эксперимента «сигнатура + инкубация» (tests/balance_audit.gd).
# Не входит в обычный CI. Запуск из папки godot:
#   GODOT=<консольный Godot 4.7.2> bash tests/strains_ab.sh [out=../build/pro152/ab] [jobs=11] [seeds=10] [cells=all]
# Затем: python tests/strains_ab.py <out> ../docs/balance/data/pro152
#
# Плечи (одинаковые сид, семейство карты, сложность, бот, Мастерская; различается только модель роя и/или поведение бота):
#   A0 --model=observe              контроль: бой как без флага (проверено strains_check), сигнатура пишется в лог
#   A1 --model=signature            рой с контрмерами, бот не читает предупреждения
#   B0 --model=observe   --counter=auto   бот отвечает на анонсы, которые без флага не сбываются (цена «лишнего» контрхода)
#   B1 --model=signature --counter=auto   бот отвечает на анонсы роя
#   F0/F1 — «замороженная политика»: журнал покупок A0 воспроизводится с неограниченным золотом в observe/signature
set -u
OUT=${1:-../build/pro152/ab}
JOBS=${2:-11}
SEEDS=${3:-10}
CELLS=${4:-all}
G=${GODOT:-/d/Godot/Godot_v4.7.2-stable_win64_console.exe}
FAMS="snake vsnake stairs hooks"
mkdir -p "$OUT/rec"
run() { # имя, аргументы
  local name=$1; shift
  echo "\"$G\" --headless --path . --script res://tests/balance_audit.gd -- --seeds=$SEEDS --waves=30 --micro=0 $* --out=$OUT/$name.jsonl"
}
want() { [ "$CELLS" = all ] || [[ ",$CELLS," == *",$1,"* ]]; }

# фаза 1: контроль с записью журнала, остальные живые плечи
P1="$OUT/phase1.txt"; : > "$P1"
for f in $FAMS; do
  for cell in "owner normal 0" "owner hard 0" "mixed normal 0" "adaptive normal 0" "arrow normal 0" "arrow_sniper normal 0" "switch normal 1" "cannon normal 0"; do
    set -- $cell; s=$1; d=$2; ws=$3; id="${s}_${d}"
    want "$id" || continue
    base="--strategy=$s --difficulty=$d --family=$f --workshop=$ws"
    run "${id}_${f}_A0" $base --model=observe --record=$OUT/rec/${id}_${f}.json >> "$P1"
    run "${id}_${f}_A1" $base --model=signature >> "$P1"
    if [[ "$s" == owner || "$s" == mixed || "$s" == cannon ]]; then
      run "${id}_${f}_B0" $base --model=observe --counter=auto >> "$P1"
      run "${id}_${f}_B1" $base --model=signature --counter=auto >> "$P1"
    fi
  done
done
xargs -P "$JOBS" -I{} sh -c '{} > /dev/null 2>&1' < "$P1"

# фаза 2: замороженная политика (нужен журнал из A0)
P2="$OUT/phase2.txt"; : > "$P2"
for f in $FAMS; do
  for cell in "owner normal 0" "owner hard 0" "mixed normal 0"; do
    set -- $cell; s=$1; d=$2; ws=$3; id="${s}_${d}"
    want "$id" || continue
    base="--strategy=$s --difficulty=$d --family=$f --workshop=$ws --replay=$OUT/rec/${id}_${f}.json"
    run "${id}_${f}_F0" $base --model=observe >> "$P2"
    run "${id}_${f}_F1" $base --model=signature >> "$P2"
  done
done
xargs -P "$JOBS" -I{} sh -c '{} > /dev/null 2>&1' < "$P2"
cat "$P1" "$P2" > "$OUT/commands.txt"
echo "done: $(ls "$OUT"/*.jsonl | wc -l) files"
