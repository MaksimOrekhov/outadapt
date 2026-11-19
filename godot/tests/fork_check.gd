extends SceneTree
## PRO-139: прототип развилки и обратная совместимость. godot --headless --path godot --script res://tests/fork_check.gd
## Карты TDMap.fork_test("fork" | "fork_uneven") — технические, в обычные забеги не попадают.

var failures := 0


func check(label: String, condition: bool, detail: String = "") -> void:
	print(("OK    " if condition else "FAIL  ") + label + ("" if detail == "" else "  (" + detail + ")"))
	if not condition:
		failures += 1


func near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 1e-4


func enemy(g: TDGame, route: int, dist: float, fly := false) -> TDGame.Enemy:
	var e := TDGame.Enemy.new()
	e.id = g.next_id
	g.next_id += 1
	e.genome = TDGenome.random_genome(TDRng.new(e.id), 1)
	e.ph = TDGenome.phenotype(e.genome, 1).duplicate()
	e.ph["fly"] = fly
	e.ph["stealth"] = false
	e.hp = e.ph["hp"]
	e.route = route
	e.dist = dist
	return e


## Волна без башен до конца: [выпущено по маршрутам, прорвалось, итоги finished].
func run_wave(g: TDGame) -> Dictionary:
	if not g.offer.is_empty():
		g.choose_perk(g.offer[0])
	g.start_wave()
	var by_route := {}
	var seen := {}
	var hit_on := {}
	for _i in 6000:
		g.step(0.05)
		for e in g.enemies:
			if not seen.has(e.id) and not e.child:
				seen[e.id] = true
				by_route[e.route] = int(by_route.get(e.route, 0)) + 1
			if e.last_kind != "":
				hit_on[e.route] = true
		if g.phase != "wave":
			break
	return {"by_route": by_route, "leaked": g.leaked, "finished": g.finished.duplicate(), "hit_on": hit_on}


func snap_hash(g: TDGame) -> int:
	var s := TDSave.snapshot(g)
	s.erase("saved_at")
	s.erase("timestamp")
	return hash(var_to_bytes(s))


func _initialize() -> void:
	# ── 1. Обратная совместимость: обычные карты — один маршрут, всё как раньше ──
	var legacy_ok := true
	var legacy_bad := ""
	for s in 200:
		var m := TDMap.generate(s * 4243 + 7)
		var probs := m.route_problems(2, 1000, 100.0, 0.0, 0)
		if m.routes.size() != 1 or m.is_multi() or m.road_cells() != m.order or m.route_plan != [0] or not probs.is_empty() \
				or m.routes[0].order != m.order or m.routes[0].length != m.length:
			legacy_ok = false
			legacy_bad = "%d: %s" % [s, ", ".join(probs)]
	check("200 обычных карт: один маршрут, road_cells = order, план [0], сеть корректна", legacy_ok, legacy_bad)
	var lg := TDGame.new(1003)
	var le := enemy(lg, 0, 7.3)
	check("обычная карта: цель выбирается по прежней доле пути", lg.target_progress(le) == lg.progress_of(le))
	lg.start_wave()
	for _i in 200:
		lg.step(0.05)
	var routes_used := {}
	for e in lg.enemies:
		routes_used[e.route] = true
	check("обычная карта: все враги на маршруте 0", routes_used.keys() == [0] or routes_used.is_empty())
	var legacy_snap := TDSave.snapshot(lg)
	check("обычная карта: в сохранении нет полей маршрутов", not legacy_snap.has("routes") and not legacy_snap.has("route_plan")
		and not legacy_snap["state"].has("route_k") and (legacy_snap["enemies"].is_empty() or not legacy_snap["enemies"][0].has("route")))

	# ── 2. Инварианты сети маршрутов ──
	for v in ["fork", "fork_uneven"]:
		var fm := TDMap.fork_test(v)
		var probs := fm.route_problems(15, 90, 1.5, 8.0, 40)
		check("%s: два маршрута, сеть корректна (вход, замок, касания, циклы, тупики, длины, места под башни)" % v,
			fm.routes.size() == 2 and probs.is_empty(), ", ".join(probs))
	var f := TDMap.fork_test("fork")
	var fu := TDMap.fork_test("fork_uneven")
	check("fork: ветки равной длины (%.0f и %.0f)" % [f.routes[0].length, f.routes[1].length], f.routes[0].length == f.routes[1].length)
	check("fork_uneven: южная ветка длиннее (%.0f и %.0f), отношение ≤ 1,5" % [fu.routes[0].length, fu.routes[1].length],
		fu.routes[1].length > fu.routes[0].length and fu.routes[1].length / fu.routes[0].length <= 1.5)
	check("развилка (3,4) и слияние (11,4) — общие клетки, ветки — свои",
		f.routes_at(Vector2i(3, 4)).size() == 2 and f.routes_at(Vector2i(11, 4)).size() == 2
		and f.routes_at(Vector2i(7, 1)) == [0] and f.routes_at(Vector2i(7, 7)) == [1])
	check("road_cells: каждая клетка дороги один раз", f.road_cells().size() == f.cells.size())
	check("версия геометрии различает карты и стабильна", f.geometry_key() != fu.geometry_key()
		and f.geometry_key() == TDMap.fork_test("fork").geometry_key() and f.geometry_key() != TDMap.generate(1).geometry_key())
	var A := TDMap.FORK_MAPS["fork"][0]
	var bad_maps := {
		"дубль маршрута": [A, A],
		"касание веток": [A, [Vector2i(0, 4), Vector2i(4, 4), Vector2i(4, 2), Vector2i(10, 2), Vector2i(10, 4), Vector2i(15, 4)]],
		"другой замок": [A, [Vector2i(0, 4), Vector2i(3, 4), Vector2i(3, 7), Vector2i(15, 7)]],
		"другой вход": [A, [Vector2i(0, 7), Vector2i(11, 7), Vector2i(11, 4), Vector2i(15, 4)]],
	}
	for label in bad_maps:
		var bm := TDMap.build_routes(0, "", bad_maps[label])
		check("сеть отклоняется: %s" % label, not bm.route_problems(2, 1000, 100.0, 0.0, 0).is_empty(), ", ".join(bm.route_problems(2, 1000, 100.0, 0.0, 0)))
	var near_castle := TDMap.build(0, "", [Vector2i(0, 4), Vector2i(4, 4)] as Array[Vector2i])
	check("сеть отклоняется: вход у замка (спавн без времени на ответ)", near_castle.route_problems(2, 1000, 100.0, 8.0, 0).size() > 0)

	# ── 3. Движение по веткам ──
	var g := TDGame.new(5, f)
	var e0 := enemy(g, 0, 2.0)
	var e1 := enemy(g, 1, 2.0)
	check("общий участок до развилки: одна и та же точка", near(g.pos_of(e0), g.pos_of(e1)))
	e0.dist = 8.0
	e1.dist = 8.0
	check("после развилки: маршрут 0 — север, маршрут 1 — юг", g.pos_of(e0).y < 4.5 and g.pos_of(e1).y > 4.5,
		"%s / %s" % [g.pos_of(e0), g.pos_of(e1)])
	check("на ветках направление спрайта своё", not near(g.heading_of(e0), g.heading_of(e1)) or g.heading_of(e0) == Vector2.RIGHT)
	e0.dist = f.routes[0].length - 1.0
	e1.dist = f.routes[1].length - 1.0
	check("после слияния: снова одна точка перед замком", near(g.pos_of(e0), g.pos_of(e1)))
	var fl0 := enemy(g, 0, 3.0, true)
	var fl1 := enemy(g, 1, 3.0, true)
	check("летающие не идут по веткам: прямая от портала к замку одна для обоих маршрутов",
		near(g.pos_of(fl0), g.pos_of(fl1)) and is_equal_approx(g.pos_of(fl0).y, 4.5) and g.path_len_of(fl0) == f.fly_length)

	# ── 4. Распределение по маршрутам: фиксированный шаблон, дети наследуют маршрут ──
	var g2 := TDGame.new(11, TDMap.fork_test("fork"), {"lives": 1000})
	var r1 := run_wave(g2)
	var spawned: int = r1["by_route"].get(0, 0) + r1["by_route"].get(1, 0)
	check("волна делится по веткам по очереди (%s)" % str(r1["by_route"]),
		absi(int(r1["by_route"].get(0, 0)) - int(r1["by_route"].get(1, 0))) <= 1 and spawned == g2.route_k)
	var routes_fin := {}
	for x in r1["finished"]:
		routes_fin[x["route"]] = true
	check("без башен все прорываются по обеим веткам; в итогах для отбора записан маршрут",
		r1["leaked"] == spawned and routes_fin.has(0) and routes_fin.has(1))
	var g3 := TDGame.new(12, TDMap.fork_test("fork"))
	var parent := enemy(g3, 1, 9.0)
	var kids := g3._split(parent)
	var summ := g3._summon(parent)
	var kid_routes := {}
	for k in kids + summ:
		kid_routes[k.route] = true
	check("малыши деления и прислужники босса остаются на ветке родителя", kid_routes.keys() == [1])
	g3.enemies.clear()
	var carrier := enemy(g3, 1, 0.0)
	g3._spawn_strain(carrier, "brood")
	var brood_ok := true
	for k in g3.enemies:
		brood_ok = brood_ok and k.route == 1
	check("кладка выводка — на ветке носителя", brood_ok and g3.enemies.size() == TDStrains.BROOD_N - 1)
	var g4 := TDGame.new(13, TDMap.fork_test("fork", [1] as Array[int]), {"lives": 1000})
	var r4 := run_wave(g4)
	check("другой план карты (все на юг) соблюдается", r4["by_route"].keys() == [1])

	# ── 5. Цели при разной длине веток ──
	var gu := TDGame.new(5, fu)
	# X на короткой ветке ближе к замку (осталось 9), Y на длинной дальше (осталось 10), но доля пути у Y больше
	var X := enemy(gu, 0, fu.routes[0].length - 9.0)
	var Y := enemy(gu, 1, fu.routes[1].length - 10.0)
	gu.enemies.append_array([X, Y])
	check("доли пути несравнимы: у дальнего от замка Y доля больше", gu.progress_of(Y) > gu.progress_of(X))
	gu.gold = 1000
	gu.place_tower("sniper", 9, 5)
	var tw: TDGame.Tower = gu.towers[0]
	var picked := gu._pick_targets(tw, Vector2(9.5, 5.5), 1)
	check("«первый» бьёт того, кто ближе к замку, а не того, у кого больше доля пути", picked.size() == 1 and picked[0] == X)
	var M0 := enemy(gu, 0, fu.routes[0].dist_to_cell(Vector2i(12, 4)))
	var M1 := enemy(gu, 1, fu.routes[1].dist_to_cell(Vector2i(12, 4)))
	check("в точке слияния враги разных веток равны для выбора цели",
		near(gu.pos_of(M0), gu.pos_of(M1)) and is_equal_approx(gu.target_progress(M0), gu.target_progress(M1)))
	check("итог для отбора — доля своего маршрута", is_equal_approx(gu.progress_of(M0), M0.dist / fu.routes[0].length)
		and is_equal_approx(gu.progress_of(M1), M1.dist / fu.routes[1].length))

	# ── 6. Башня между ветками бьёт обе; советник видит обе ветки ──
	var g5 := TDGame.new(21, TDMap.fork_test("fork"), {"lives": 1000})
	g5.gold = 1000
	check("башня в середине между ветками ставится", g5.place_tower("sniper", 7, 4), g5.place_problem("sniper", 7, 4))
	var r5 := run_wave(g5)
	var killed_on := {}
	for x in r5["finished"]:
		if float(x["fitness"]) < 1.5:
			killed_on[x["route"]] = true
	check("одна башня между ветками убивает врагов на обеих", killed_on.has(0) and killed_on.has(1), str(killed_on))
	var g6 := TDGame.new(22, TDMap.fork_test("fork"))
	g6.gold = 1000
	g6.place_tower("arrow", 7, 2)
	var cov := TDAdvisor.road_coverage(g6)
	var south_open: bool = cov["uncovered"].has(Vector2i(7, 7))
	check("покрытие дороги считает обе ветки: башня у северной оставляет южную открытой", south_open and cov["pct"] < 1.0)

	# ── 7. Сохранение посреди волны и детерминизм ──
	var ga := TDGame.new(31, TDMap.fork_test("fork_uneven"), {"lives": 1000})
	ga.gold = 1000
	ga.place_tower("arrow", 4, 6)
	ga.place_tower("cannon", 7, 4)
	if not ga.offer.is_empty():
		ga.choose_perk(ga.offer[0])
	ga.start_wave()
	for _i in 120:
		ga.step(0.05)
	var snap := TDSave.snapshot(ga)
	var on_routes := {}
	for e in ga.enemies:
		on_routes[e.route] = true
	check("посреди волны враги на обеих ветках", on_routes.has(0) and on_routes.has(1))
	check("сохранение карты с развилкой проходит проверку", TDSave.valid(snap))
	var gb := TDSave.restore(snap)
	if gb == null:
		check("загрузка сохранения карты с развилкой", false)
		print("\nFAIL: %d" % failures)
		quit(1)
		return
	check("после загрузки: маршруты, план, семейство, счётчик и маршруты врагов те же",
		gb != null and gb.map.routes.size() == 2 and gb.map.route_plan == ga.map.route_plan and gb.map.family == "fork_uneven"
		and gb.route_k == ga.route_k and gb.enemies.size() == ga.enemies.size()
		and gb.enemies.map(func(e): return e.route) == ga.enemies.map(func(e): return e.route))
	for _i in 400:
		ga.step(0.05)
		gb.step(0.05)
	check("после загрузки бой идёт так же, как без неё", snap_hash(ga) == snap_hash(gb))
	var gc := TDGame.new(31, TDMap.fork_test("fork_uneven"), {"lives": 1000})
	gc.gold = 1000
	gc.place_tower("arrow", 4, 6)
	gc.place_tower("cannon", 7, 4)
	if not gc.offer.is_empty():
		gc.choose_perk(gc.offer[0])
	gc.start_wave()
	for _i in 520:
		gc.step(0.05)
	check("тот же сид и действия — тот же бой", snap_hash(gc) == snap_hash(ga))
	var broken := snap.duplicate(true)
	broken["enemies"][0]["route"] = 5
	check("сохранение с несуществующим маршрутом врага отклоняется", not TDSave.valid(broken))
	broken = snap.duplicate(true)
	broken.erase("routes")
	check("маршрут у врага без маршрутов карты отклоняется", not TDSave.valid(broken))
	broken = snap.duplicate(true)
	broken["routes"][1] = [Vector2i(0, 4), Vector2i(4, 4), Vector2i(4, 2), Vector2i(10, 2), Vector2i(10, 4), Vector2i(15, 4)]
	check("сохранение с касающимися ветками отклоняется", not TDSave.valid(broken))
	broken = snap.duplicate(true)
	broken["route_plan"] = [0, 2]
	check("план с несуществующим маршрутом отклоняется", not TDSave.valid(broken))

	print("\nFAIL: %d" % failures if failures > 0 else "\nВсе проверки PRO-139 прошли")
	quit(1 if failures > 0 else 0)
