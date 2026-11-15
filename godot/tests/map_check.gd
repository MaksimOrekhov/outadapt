extends SceneTree
## Проверка генератора карт: godot --headless --path godot --script res://tests/map_check.gd [-- --seeds=600 --print-golden]

var failures := 0
var seeds := 600


func check(label: String, condition: bool, detail: String = "") -> void:
	if not condition:
		failures += 1
		print("FAIL  " + label + ("" if detail == "" else "  (" + detail + ")"))


func _initialize() -> void:
	var print_golden := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a == "--print-golden":
			print_golden = true
	if print_golden:
		# хэши карт для сравнения до и после появления семейств (только у карт семейства snake)
		for s in seeds:
			var m := TDMap.generate(s)
			print("G %d %s %d" % [s, m.family, hash(str(m.waypoints) + str(m.blocked.keys()))])
		quit()
		return
	var counts := {}
	var lengths := {}
	for fam in ["snake", "vsnake", "stairs", "hooks"]:
		lengths[fam] = []
		counts[fam] = 0
	var forced_fallbacks := 0
	for fam in ["snake", "vsnake", "stairs", "hooks"]:
		for s in seeds:
			var m := TDMap.generate(s, fam)
			check("%s seed %d: семейство" % [fam, s], m.family == fam or (m.family == "snake" and fam != "snake"))
			if m.family != fam:
				forced_fallbacks += 1
			_check_map(m, "%s seed %d" % [fam, s])
			# детерминированность
			var m2 := TDMap.generate(s, fam)
			check("%s seed %d: детерминированность" % [fam, s], m.waypoints == m2.waypoints and m.blocked == m2.blocked and m.map_name == m2.map_name)
			if m.family == fam:
				lengths[fam].append(m.order.size())
	for s in seeds:
		var m := TDMap.generate(s)
		counts[m.family] += 1
		_check_map(m, "seed %d" % s)
		check("seed %d: семейство по сиду" % s, m.family == TDMap.family_for(s) or m.family == "snake")
	# сохранение и загрузка карт каждого семейства; полёт и порядок клеток после загрузки совпадают
	for fam in ["snake", "vsnake", "stairs", "hooks"]:
		for s in 20:
			var g := TDGame.new(s * 7 + 1, TDMap.generate(s * 7 + 1, fam))
			var snap := TDSave.snapshot(g)
			check("%s: сохранение валидно" % fam, TDSave.valid(snap))
			var r := TDSave.restore(snap)
			check("%s: карта после загрузки совпадает" % fam, r != null and r.map.waypoints == g.map.waypoints and r.map.order == g.map.order and r.map.blocked == g.map.blocked and absf(r.map.fly_length - g.map.fly_length) < 1e-6)
	for fam in lengths:
		var arr: Array = lengths[fam]
		arr.sort()
		if arr.size() > 0:
			print("%-7s карт %3d  длина дороги min %d  медиана %d  max %d" % [fam, arr.size(), arr[0], arr[arr.size() / 2], arr[arr.size() - 1]])
	print("распределение семейств по сидам: ", counts)
	print("не удалось построить семейство и пришлось взять змейку: %d из %d" % [forced_fallbacks, seeds * 3])
	check("не менее 3 семейств дали карты", counts.values().filter(func(v): return v > 0).size() >= 3)
	check("запасной вариант почти не нужен", forced_fallbacks <= seeds * 3 * 0.01, "%d" % forced_fallbacks)
	print("Map checks: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func _check_map(m: TDMap, label: String) -> void:
	var cols := TDConfig.COLS
	var rows := TDConfig.ROWS
	check(label + ": rasterize", not TDMap.rasterize(m.waypoints).is_empty())
	check(label + ": длина дороги", m.order.size() >= 30 and m.order.size() <= 90, str(m.order.size()))
	check(label + ": вход слева, строка ≥ 1", m.waypoints[0].x == 0 and m.waypoints[0].y >= 1)
	var last: Vector2i = m.waypoints[m.waypoints.size() - 1]
	check(label + ": выход справа, строка ≥ 2", last.x == cols - 1 and last.y >= 2)
	check(label + ": последний участок горизонтальный", m.waypoints[m.waypoints.size() - 2].y == last.y)
	for w in m.waypoints:
		check(label + ": вершина в поле", w.x >= 0 and w.y >= 0 and w.x < cols and w.y < rows)
	for c in m.blocked:
		check(label + ": скала не на дороге", not m.cells.has(c))
		check(label + ": скала в поле", c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows)
	# летающие: по прямой от входа к выходу
	check(label + ": fly_length", absf(m.fly_length - m.points[0].distance_to(m.points[m.points.size() - 1])) < 1e-6)
	check(label + ": fly_pos в начале и конце", m.fly_pos_at(0.0).distance_to(m.points[0]) < 1e-6 and m.fly_pos_at(m.fly_length).distance_to(m.points[m.points.size() - 1]) < 1e-6)
	check(label + ": путь не короче прямой", m.length >= m.fly_length)
	# замок и портал
	for field_size in [Vector2(1466, 950), Vector2(960, 540)]:
		var layout := m.castle_layout(field_size)
		var cell := minf(field_size.x / cols, field_size.y / rows)
		var base: Vector2 = layout["base"]
		var side: float = layout["side"]
		var end: Vector2 = layout["end"]
		var road_end: Vector2 = layout["road_end"]
		check(label + ": замок на оси дороги", absf(base.y - end.y - cell * 0.05) < 0.01 and side >= cell * 1.79)
		for x in [-0.46, 0.0, 0.46]:
			var foot := base + Vector2(side * x, 0)
			check(label + ": основание на последнем участке", absf(foot.y - end.y) <= cell * 0.43 and foot.x <= road_end.x + 0.01 and foot.x >= m.points[m.points.size() - 2].x * cell)
		check(label + ": замок в поле", base.x - side * 0.5 >= 0 and base.x + side * 0.5 <= field_size.x and base.y <= field_size.y and base.y - side >= 0)
	# позиции вдоль дороги непрерывны и ведут от входа к выходу
	check(label + ": pos_at(0) — вход", m.pos_at(0.0).distance_to(m.points[0]) < 1e-6)
	check(label + ": pos_at(length) — выход", m.pos_at(m.length).distance_to(m.points[m.points.size() - 1]) < 1e-6)
	# места под башни: достаточно свободных клеток рядом с дорогой
	var buildable := 0
	for x in cols:
		for y in rows:
			if not m.is_path(x, y) and not m.is_blocked(x, y):
				buildable += 1
	check(label + ": достаточно места под башни", buildable >= 50, str(buildable))
