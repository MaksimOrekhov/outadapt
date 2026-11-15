#!/usr/bin/env bash
# Гоняет бота на N картах параллельно (по процессу на карту) и сводит результат в таблицу.
# Запуск из папки godot: bash tests/bot_all.sh [карт=5] [волн=30]
N=${1:-5}
W=${2:-30}
shift 2 2>/dev/null
EXTRA="$*"
G=${GODOT:-/d/Godot/Godot_v4.7.2-stable_win64_console.exe}
TMP=$(mktemp -d)
for i in $(seq 0 $((N - 1))); do
  "$G" --headless --path . --script res://tests/bot.gd -- --seeds=1 --seed-from=$i --waves=$W $EXTRA > "$TMP/$i.txt" 2>&1 &
done
wait
PYTHONIOENCODING=utf-8 python - "$TMP" "$N" "$W" <<'EOF'
import sys, re, os
d, n, w = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
rows = {}
order = []
for i in range(n):
    name = None
    for line in open(os.path.join(d, f"{i}.txt"), encoding="utf-8", errors="replace"):
        line = line.rstrip()
        m = re.search(r"дошёл до волны: (\d+)", line)
        if m and name:
            rows.setdefault(name, []).append(int(m.group(1)))
        elif line and not line.startswith(("Godot", " ")):
            name = line.strip()
            if name not in order:
                order.append(name)
for name in order:
    v = rows.get(name, [])
    if v:
        print(f"{name:45s} {' '.join(f'{x:3d}' for x in v)}   среднее {sum(v)/len(v):5.1f}")
print(f"(>{w} = не проиграл)")
EOF
rm -rf "$TMP"
