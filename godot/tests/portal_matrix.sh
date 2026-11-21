#!/usr/bin/env bash
# PRO-141: плечи эксперимента «два портала, второй открывается посреди забега». Запуск из папки godot:
#   GODOT=<консольный Godot 4.7.2> ARMS="ctl p18" [MAPS="portal_a portal_b"] [MODELS="off signature"] [WS="0 1"] [STRATS="owner2 mixed adaptive owner"] \
#     [DIFFS="normal hard"] bash tests/portal_matrix.sh <тег> [jobs=11] [seeds=10] [seed_from=0]
# Плечи (ARMS):
#   ctl        — контроль: та же геометрия, второй портал не открывается никогда (один активный портал);
#   p18        — гипотеза: предупреждение с 15-й волны, открытие с 18-й, 50% врагов через второй портал, бот строит под второй вход после предупреждения;
#   p16, p21   — то же с открытием на 16-й (предупреждение с 13-й) и на 21-й (с 18-й);
#   p18_blind  — p18, но бот строит под второй вход только после открытия (независимая реактивная политика);
#   p18_early  — p18, но бот строит под оба входа с первой волны (как на развилке);
#   p18_s40, p18_s35 — p18 с долей 40% / 35% через второй портал;
#   p18_a12    — p18 с предупреждением заранее: с 12-й волны (шесть фаз строительства до открытия вместо трёх);
#   p14        — открытие с 14-й волны (предупреждение с 11-й);
#   p21_a15    — открытие с 21-й волны, предупреждение с 15-й;
#   fork       — старый fork 50/50 с одним порталом: fork_even / fork_skew PRO-213 (MAPS не используется), те же сиды.
# Ячейка: стратегия × normal/hard × модель (off/signature) × карта × Мастерская (WS: 0 — нет, 1 — на максимуме), до 35-й волны, --late=1.
# Вывод: ../build/portal/<тег>/<плечо>/<стратегия>_<сложность>_<модель>_<карта>_ws<0|1>.jsonl; сводка: python tests/portal_report.py <тег>
# Возобновление: ячейка с полным числом партий пропускается.
set -u
TAG=${1:?tag}
JOBS=${2:-11}
SEEDS=${3:-10}
FROM=${4:-0}
ARMS=${ARMS:-ctl p18}
MAPS=${MAPS:-portal_a portal_b}
MODELS=${MODELS:-off}
WS=${WS:-0}
STRATS=${STRATS:-owner2 mixed adaptive owner}
DIFFS=${DIFFS:-normal hard}
G=${GODOT:-/d/Godot/Godot_v4.7.2-stable_win64_console.exe}
OUTB=../build/portal/$TAG
mkdir -p "$OUTB"
CMDS="$OUTB/commands.txt"
TODO="$OUTB/commands_todo.txt"
: > "$CMDS"; : > "$TODO"
SKIP=0
arm_args() {
  case "$1" in
    ctl) echo "--portal-open=999 --portal-announce=999" ;;
    p18) echo "--portal-open=18 --portal-announce=15" ;;
    p16) echo "--portal-open=16 --portal-announce=13" ;;
    p21) echo "--portal-open=21 --portal-announce=18" ;;
    p18_blind) echo "--portal-open=18 --portal-announce=15 --portal-policy=blind" ;;
    p18_early) echo "--portal-open=18 --portal-announce=15 --portal-policy=early" ;;
    p18_s40) echo "--portal-open=18 --portal-announce=15 --portal-share=40" ;;
    p18_s35) echo "--portal-open=18 --portal-announce=15 --portal-share=35" ;;
    p18_a12) echo "--portal-open=18 --portal-announce=12" ;;
    p14) echo "--portal-open=14 --portal-announce=11" ;;
    p21_a15) echo "--portal-open=21 --portal-announce=15" ;;
    fork) echo "" ;;
    *) echo "unknown arm $1" >&2; exit 2 ;;
  esac
}
for arm in $ARMS; do
  A=$(arm_args "$arm") || exit 2
  OUT=$OUTB/$arm
  mkdir -p "$OUT"
  MAPLIST="$MAPS"; [ "$arm" = fork ] && MAPLIST="fork_even fork_skew"
  for s in $STRATS; do
    for d in $DIFFS; do
      for m in $MODELS; do
        for ws in $WS; do
          for f in $MAPLIST; do
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
