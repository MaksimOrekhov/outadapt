extends SceneTree
## PRO-141: поиск и оценка геометрии двух пространственно разнесённых порталов на поле 16×10.
##   godot --headless --path godot --script res://tests/portal_geometry.gd -- --attempts=4000 --seed=1 [--top=6] [--min-len=30] [--max-len=40]
## Случайные самонепересекающиеся дороги: портал 0 на левом краю, портал 1 на верхнем, обе сходятся в клетке слияния (xm, yc)
## и дальше идут общим участком к замку на правом краю. Кандидат проходит TDMap.route_problems (расширенный валидатор).
## Оценка — перекрытие обстрела «ворот» (первых 20% пути каждого входа): доля клеток под башни, достающих оба входа, среди клеток,
## достающих хотя бы один, для дальностей башен 2.6–8.3 (Снайпер с Дальнобоем и перками). Чем ниже, тем независимее входы.
## Для сравнения — те же числа на развилках PRO-213 (общий ствол: перекрытие у входа 1.0 по построению).

const RANGES := [2.6, 3.2, 3.5, 5.2, 7.2, 8.3]

var rng := RandomNumberGenerator.new()


func neighbors(c: Vector2i) -> Array[Vector2i]:
	return [Vector2i(c.x + 1, c.y), Vector2i(c.x - 1, c.y), Vector2i(c.x, c.y + 1), Vector2i(c.x, c.y - 1)]


## Случайная самонепересекающаяся дорога от start до target; клетки не касаются друг друга (кроме соседей по порядку) и
## запрещённых клеток. Возвращает клетки включая start и target или пустой массив.
func walk(start: Vector2i, target: Vector2i, forbid: Dictionary, lo: int, hi: int, budget: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	var visited := {start: true}
	var nodes := 0
	var tries := {}
	while not path.is_empty() and nodes < budget:
		nodes += 1
		var cur: Vector2i = path.back()
		if cur == target:
			if path.size() >= lo:
				return path
			# слишком коротко: шаг назад
			visited.erase(cur)
			path.pop_back()
			continue
		var opts: Array[Vector2i] = []
		for n in neighbors(cur):
			if n.x < 0 or n.y < 0 or n.x >= TDConfig.COLS or n.y >= TDConfig.ROWS or visited.has(n) or forbid.has(n):
				continue
			if n.x > target.x:
				continue
			# осталось шагов не меньше манхэттенова расстояния до цели
			var rest: int = absi(target.x - n.x) + absi(target.y - n.y)
			if path.size() + 1 + rest > hi:
				continue
			# не касаться своих клеток (кроме предыдущей)
			var touch := false
			for m in neighbors(n):
				if m != cur and visited.has(m):
					touch = true
					break
			if touch and n != target:
				continue
			if n == target:
				pass
			opts.append(n)
		var key := path.hash()
		var used: Array = tries.get(key, [])
		opts = opts.filter(func(o): return not used.has(o))
		if opts.is_empty():
			visited.erase(cur)
			path.pop_back()
			continue
		# предпочитаем идти дальше от цели, пока дорога короткая: случайный выбор с лёгким уклоном
		var pick: Vector2i = opts[rng.randi() % opts.size()]
		used.append(pick)
		tries[key] = used
		visited[pick] = true
		path.append(pick)
	return []


func compress(cells: Array[Vector2i]) -> Array[Vector2i]:
	var out: Array[Vector2i] = [cells[0]]
	for i in range(1, cells.size() - 1):
		var d1: Vector2i = cells[i] - cells[i - 1]
		var d2: Vector2i = cells[i + 1] - cells[i]
		if d1 != d2:
			out.append(cells[i])
	out.append(cells.back())
	return out


func zone_samples(r: TDPath, share: float = 0.2) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var n := 10
	for i in n:
		out.append(r.pos_at((i + 0.5) / n * share * r.length))
	return out


## Для каждой дальности: доли клеток под башни, достающих оба входа / хотя бы один, и число клеток обоих.
func overlap(m: TDMap, zone_a: Array[Vector2], zone_b: Array[Vector2]) -> Dictionary:
	var res := {}
	for r in RANGES:
		var both := 0
		var any_ := 0
		for x in TDConfig.COLS:
			for y in TDConfig.ROWS:
				if m.is_path(x, y) or m.is_blocked(x, y):
					continue
				var c := Vector2(x + 0.5, y + 0.5)
				var ha := false
				for p in zone_a:
					if p.distance_to(c) <= r:
						ha = true
						break
				var hb := false
				for p in zone_b:
					if p.distance_to(c) <= r:
						hb = true
						break
				if ha or hb:
					any_ += 1
				if ha and hb:
					both += 1
		res[r] = {"both": both, "any": any_, "share": float(both) / maxi(1, any_)}
	return res


func zones_gap(zone_a: Array[Vector2], zone_b: Array[Vector2]) -> float:
	var g := INF
	for a in zone_a:
		for b in zone_b:
			g = minf(g, a.distance_to(b))
	return g


func literal(cells: Array[Vector2i]) -> String:
	var parts: Array[String] = []
	for w in compress(cells):
		parts.append("Vector2i(%d, %d)" % [w.x, w.y])
	return "[" + ", ".join(parts) + "]"


## Режим --eval: перекрытие обстрела ворот у технических карт PORTAL_MAPS и у развилок PRO-213 (общий ствол) по дальностям.
func evaluate_maps() -> void:
	print("| Карта | расстояние между воротами | входы | свободных клеток | " + " | ".join(RANGES.map(func(r): return "перекрытие при %.1f" % r)) + " |")
	print("|---|---|---|---|" + "---|".repeat(RANGES.size()))
	var rows: Array = []
	for name in TDMap.PORTAL_MAPS:
		var m := TDMap.portal_test(name)
		rows.append([name, m])
	for fam in ["fork_even", "fork_skew"]:
		for i in 40:
			var m2 := TDMap.generate((1000 + i + 1) * 4243, fam)
			if not m2.fork_fallback:
				rows.append([fam, m2])
	var acc := {}
	for row in rows:
		var m: TDMap = row[1]
		var za := zone_samples(m.routes[0])
		var zb := zone_samples(m.routes[1])
		var ov := overlap(m, za, zb)
		var key: String = row[0]
		if not acc.has(key):
			acc[key] = {"n": 0, "gap": 0.0, "free": 0.0, "ov": {}, "ent": 0.0}
			for r in RANGES:
				acc[key]["ov"][r] = 0.0
		acc[key]["n"] += 1
		acc[key]["gap"] += zones_gap(za, zb)
		acc[key]["free"] += 160 - m.cells.size() - m.blocked.size()
		acc[key]["ent"] += m.routes[0].points[0].distance_to(m.routes[1].points[0])
		for r in RANGES:
			acc[key]["ov"][r] += ov[r]["share"]
	for key in acc:
		var a: Dictionary = acc[key]
		var n: int = a["n"]
		var line := "| %s (%d) | %.1f | %.1f | %.0f |" % [key, n, a["gap"] / n, a["ent"] / n, a["free"] / n]
		for r in RANGES:
			line += " %.2f |" % (a["ov"][r] / n)
		print(line)
	quit()


func _initialize() -> void:
	if "--eval" in OS.get_cmdline_user_args():
		evaluate_maps()
		return
	var attempts := 4000
	var seed_v := 1
	var top := 6
	var lo := 30
	var hi := 40
	var max_ratio := 1.3
	var min_gap_zone := 6.5
	var max_corners := 16
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--attempts="):
			attempts = int(a.substr(11))
		elif a.begins_with("--seed="):
			seed_v = int(a.substr(7))
		elif a.begins_with("--top="):
			top = int(a.substr(6))
		elif a.begins_with("--min-len="):
			lo = int(a.substr(10))
		elif a.begins_with("--max-len="):
			hi = int(a.substr(10))
		elif a.begins_with("--max-ratio="):
			max_ratio = float(a.substr(12))
		elif a.begins_with("--min-zone-gap="):
			min_gap_zone = float(a.substr(15))
		elif a.begins_with("--max-corners="):
			max_corners = int(a.substr(14))
	rng.seed = seed_v
	var found: Array = []
	var ok_n := 0
	for _i in attempts:
		var yc := rng.randi_range(3, 6)
		var xm := rng.randi_range(9, 12)
		var m_cell := Vector2i(xm, yc)
		var tail: Array[Vector2i] = []
		for x in range(xm + 1, TDConfig.COLS):
			tail.append(Vector2i(x, yc))
		var forbid_a := {}
		for c in tail:
			forbid_a[c] = true
		var start_a := Vector2i(0, rng.randi_range(2, TDConfig.ROWS - 2))
		var pa := walk(start_a, m_cell, forbid_a, lo - tail.size(), hi - tail.size(), 4000)
		if pa.is_empty():
			continue
		var forbid_b := {}
		for c in pa:
			forbid_b[c] = true
			for n in neighbors(c):
				forbid_b[n] = true
		for c in tail:
			forbid_b[c] = true
			for n in neighbors(c):
				forbid_b[n] = true
		# вход в клетку слияния разрешён с любой стороны, кроме занятой первой дорогой
		forbid_b.erase(m_cell)
		var arrive_a: Vector2i = pa[pa.size() - 2]
		for n in neighbors(m_cell):
			if n != arrive_a and n.x < xm + 1 and not pa.has(n):
				var near_a := false
				for q in neighbors(n):
					if q != m_cell and pa.has(q):
						near_a = true
				if not near_a:
					forbid_b.erase(n)
		var start_b := Vector2i(rng.randi_range(2, TDConfig.COLS - 4), 0)
		if forbid_b.has(start_b):
			continue
		var pb := walk(start_b, m_cell, forbid_b, lo - tail.size(), hi - tail.size(), 4000)
		if pb.is_empty():
			continue
		var ca: Array[Vector2i] = pa.duplicate()
		ca.append_array(tail)
		var cb: Array[Vector2i] = pb.duplicate()
		cb.append_array(tail)
		var wa := compress(ca)
		var wb := compress(cb)
		var m := TDMap.build_routes(0, "поиск", [wa, wb])
		if m.routes[0].order.is_empty() or m.routes[1].order.is_empty():
			continue
		m.portal2 = true
		var probs := m.route_problems(TDMap.PORTAL_MIN_PATH, TDMap.MAX_PATH, max_ratio, TDMap.FORK_MIN_FLY, TDMap.FORK_MIN_BUILD)
		if not probs.is_empty():
			continue
		ok_n += 1
		if wa.size() > max_corners or wb.size() > max_corners:
			continue
		var za := zone_samples(m.routes[0])
		var zb := zone_samples(m.routes[1])
		if zones_gap(za, zb) < min_gap_zone:
			continue
		var ov := overlap(m, za, zb)
		var score := 0.0
		for r in [3.2, 3.5, 5.2]:
			score += ov[r]["share"]
		found.append({"score": score, "gap": zones_gap(za, zb), "ov": ov, "wa": wa, "wb": wb, "la": m.routes[0].order.size(), "lb": m.routes[1].order.size(),
			"free": 160 - m.cells.size()})
	found.sort_custom(func(a, b): return a["score"] < b["score"])
	print("корректных карт: %d из %d попыток" % [ok_n, attempts])
	for i in mini(top, found.size()):
		var f: Dictionary = found[i]
		var line := "#%d score=%.2f gap=%.1f длины %d/%d свободных %d | перекрытие по дальностям:" % [i + 1, f["score"], f["gap"], f["la"], f["lb"], f["free"]]
		for r in RANGES:
			line += " %.1f→%.2f" % [r, f["ov"][r]["share"]]
		print(line)
		print("   A: " + literal_w(f["wa"]))
		print("   B: " + literal_w(f["wb"]))
	quit()


func literal_w(w: Array) -> String:
	var parts: Array[String] = []
	for c in w:
		parts.append("Vector2i(%d, %d)" % [c.x, c.y])
	return "[" + ", ".join(parts) + "]"
