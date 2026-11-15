#!/usr/bin/env bash
# Release-сборка Windows в ../build/win/Outadapt.exe (встроенный PCK).
# Запуск из любой папки: GODOT=<путь к консольному Godot 4.7.2> bash godot/tools/export_win.sh
# Нужны export templates 4.7.2 (Editor → Manage Export Templates, либо Godot_v4.7.2-stable_export_templates.tpz).
# Без GODOT берётся `godot` из PATH. Путь вывода задаёт preset "Windows" в export_presets.cfg.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
G=${GODOT:-godot}
mkdir -p ../build/win
rm -f ../build/win/Outadapt.exe
"$G" --headless --path . --import
"$G" --headless --path . --export-release "Windows" ../build/win/Outadapt.exe
test -s ../build/win/Outadapt.exe || { echo "FAIL: exe не создан"; exit 1; }
ls -l ../build/win/Outadapt.exe
