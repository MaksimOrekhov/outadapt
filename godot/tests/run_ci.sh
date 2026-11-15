#!/usr/bin/env bash
# Запускает все headless-проверки подряд и печатает сводку; код выхода 1, если упала хоть одна.
# Запуск из папки godot: GODOT=/path/to/godot bash tests/run_ci.sh [имя_проверки ...]
# Без аргументов гоняет полный набор. Нужен Godot 4.7.x (консольная сборка на Windows).
set -u
G=${GODOT:-godot}
CHECKS=("$@")
if [ ${#CHECKS[@]} -eq 0 ]; then
  CHECKS=(sanity features_check save_check menu_check audio_check tower_levels_check presentation_check)
fi

echo "== Godot: $("$G" --version 2>&1 | tail -1)"
# Свежий клон без кэша .godot/: импорт ассетов и реестр class_name.
"$G" --headless --path . --import > import.log 2>&1 || { cat import.log; echo "FAIL: --import"; exit 1; }

failed=()
for t in "${CHECKS[@]}"; do
  echo "::group::$t"
  timeout 900 "$G" --headless --path . --script "res://tests/$t.gd" 2>&1 | tee "check_$t.log"
  rc=${PIPESTATUS[0]}
  echo "::endgroup::"
  if [ "$rc" -ne 0 ] || grep -q "^FAIL" "check_$t.log"; then
    failed+=("$t")
    echo "RESULT $t: FAIL (exit=$rc)"
  else
    echo "RESULT $t: ok"
  fi
done

echo
if [ ${#failed[@]} -gt 0 ]; then
  echo "Упали проверки: ${failed[*]}"
  exit 1
fi
echo "Все проверки прошли (${#CHECKS[@]})"
