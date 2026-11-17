#!/usr/bin/env bash
# PRO-115: автономная сборка для живых плейтестов — build/playtest/Outadapt-<хэш>/ с Outadapt.exe и ярлыками.
# Запуск из корня или папки godot: GODOT=<консольный Godot 4.7.2> bash godot/tools/package_playtest.sh
# Нужны export templates 4.7.2. Хэш коммита вшивается в ярлыки (--build), журнал пишет его в первую строку.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
G=${GODOT:-godot}
REV=$(git rev-parse --short HEAD)
if ! git diff --quiet -- scripts scenes project.godot; then REV="$REV-dirty"; fi
OUT=../build/playtest/Outadapt-$REV
mkdir -p "$OUT"
"$G" --headless --path . --import > /dev/null
"$G" --headless --path . --export-release "Windows" "$OUT/Outadapt.exe"
test -s "$OUT/Outadapt.exe" || { echo "FAIL: exe не создан"; exit 1; }
crlf() { sed 's/$/\r/'; }
cat <<EOF | crlf > "$OUT/play-experiment.bat"
@echo off
rem Outadapt playtest: experimental adaptive swarm (PRO-152), build $REV
cd /d "%~dp0"
start "" Outadapt.exe -- --playtest --swarm=signature --build=$REV-on
EOF
cat <<EOF | crlf > "$OUT/play-control.bat"
@echo off
rem Outadapt playtest: control run without the experiment, build $REV
cd /d "%~dp0"
start "" Outadapt.exe -- --playtest --build=$REV-off
EOF
cat <<EOF | crlf > "$OUT/play-owner-ab.bat"
@echo off
rem Owner A/B on a fixed map without Workshop bonuses: play-owner-ab.bat on^|off SEED
cd /d "%~dp0"
set SWARM=
if /i "%~1"=="on" set SWARM=--swarm=signature
start "" Outadapt.exe -- --playtest %SWARM% --fixed-seed=%~2 --no-workshop --build=$REV-%~1
EOF
cat <<EOF > "$OUT/README.txt"
Outadapt — сборка для живого плейтеста (PRO-115 / PRO-152), коммит $REV

play-experiment.bat  — игра с экспериментальным адаптивным роем
play-control.bat     — та же игра без эксперимента (контроль)
play-owner-ab.bat on|off СИД — A/B владельца на одной карте без бонусов Мастерской (сиды: 1003, 1002, ...)

Журнал каждого забега: %APPDATA%\Godot\app_userdata\Outadapt\playtest\
После сессии отправьте файл(ы) .jsonl из этой папки организатору. Личных данных в журнале нет.
Протокол наблюдателя: docs/balance/pro152-live-playtest.md
EOF
ls -l "$OUT"
