extends SceneTree
## PRO-141: два пространственно разнесённых портала (dev-прототип). godot --headless --path godot --script res://tests/portal_check.gd
## Второй портал виден с начала, но открывается с волны portal_open; до неё забег идентичен контролю «один активный портал».

var failures := 0


func check(label: String, condition: bool, detail: String = "") -> void:
	print(("OK    " if condition else "FAIL  ") + label + ("" if detail == "" else "  (" + detail + ")"))
	if not condition:
		failures += 1


func snap_hash(g: TDGame) -> int:
	var s := TDSave.snapshot(g)
	s.erase("saved_at")
	s.erase("timestamp")
	return hash(var_to_bytes(s))


func expected_route(k: int, pct: int) -> int:
	return 1 if ((k + 1) * pct) / 100 > (k * pct) / 100 else 0


## Простая оборона у первого входа: лучшие клетки по покрытию дороги 0.
func defend(g: TDGame, n: int, rid: int = 0) -> void:
	var cells: Array = []
	for x in TDConfig.COLS:
		for y in TDConfig.ROWS:
			if g.map.is_path(x, y) or g.map.is_blocked(x, y):
				continue
			var sc := 0.0
			var r: TDPath = g.map.routes[rid]
			for s in 60:
				if r.pos_at(s / 60.0 * r.length).distance_to(Vector2(x + 0.5, y + 0.5)) <= 3.2:
					sc += 1.0
			cells.append([sc, x, y])
	cells.sort_custom(func(a, b): return a[0] > b[0])
	var kinds := ["arrow", "cannon", "frost", "arrow", "sniper", "ember"]
	var placed := 0
	for c in cells:
		if placed >= n:
			break
		if g.place_tower(kinds[placed % kinds.size()], c[1], c[2]):
			placed += 1


func play_wave(g: TDGame, seen: Dictionary, routes_out: Array, fly_start: Array = []) -> void:
	g.start_wave()
	for _i in 8000:
		g.step(0.05)
		for e in g.enemies:
			if not seen.has(e.id):
				seen[e.id] = true
				if not e.child:
					routes_out.append(e.route)
					if e.ph["fly"] and e.dist <= 0.5:
						fly_start.append([e.route, g.pos_of(e)])
		if g.phase != "wave":
			break


func new_game(open_wave: int, announce: int, share: int = 50, seed_v: int = 4243) -> TDGame:
	var m := TDMap.portal_test("portal_a", open_wave, announce, share)
	return TDGame.new(seed_v, m, {"lives": 100000})


func _initialize() -> void:
	# ── 1. Геометрия и валидатор ──
	var m := TDMap.portal_test("portal_a")
	var probs := m.route_problems(TDMap.PORTAL_MIN_PATH, TDMap.MAX_PATH, TDMap.FORK_MAX_RATIO, TDMap.FORK_MIN_FLY, TDMap.FORK_MIN_BUILD)
	check("portal_a: два портала, проверки карты проходят", m.portal2 and not m.portal_fallback and probs.is_empty(), str(probs))
	check("входы на левом и верхнем краях, разные клетки, общего стартового узла нет", m.portal_cell(0).x == 0 and m.portal_cell(1).y == 0
		and m.portal_cell(0) != m.portal_cell(1) and m.shared_in() == 0 and m.shared_out() >= 3)
	var gap := m.routes[0].points[0].distance_to(m.routes[1].points[0])
	check("входы разнесены: %.1f клетки (≥ %.1f)" % [gap, TDMap.PORTAL_MIN_GAP], gap >= TDMap.PORTAL_MIN_GAP)
	# отклонение плохих карт
	var bad_same := TDMap.build_routes(0, "x", [m.routes[0].waypoints, m.routes[0].waypoints])
	bad_same.portal2 = true
	var bad_corner := TDMap.build_routes(0, "x", [m.routes[0].waypoints, [Vector2i(0, 0), Vector2i(0, 1)] as Array[Vector2i]])
	bad_corner.portal2 = true
	check("входы совпадают / вход в углу — карта отклонена", not bad_same.route_problems(30, 90, 1.5, 8.0, 40).is_empty() and not bad_corner.route_problems(30, 90, 1.5, 8.0, 40).is_empty())
	var near_wps: Array[Vector2i] = [Vector2i(0, 3), Vector2i(0, 5)]
	var near := TDMap.build_routes(0, "x", [m.routes[0].waypoints, [Vector2i(1, 0), Vector2i(1, 2), Vector2i(2, 2), Vector2i(2, 3)] as Array[Vector2i]])
	near.portal2 = true
	check("близкие входы и общий стартовый узел отклоняются", not near.route_problems(0, 90, 9.0, 0.0, 0).is_empty())
	var shared_head := TDMap.build_routes(0, "x", [m.routes[0].waypoints, [Vector2i(0, 3), Vector2i(0, 5), Vector2i(15, 5)] as Array[Vector2i]])
	shared_head.portal2 = true
	check("общий старт (оба от одного портала) на карте с двумя порталами отклоняется", not shared_head.route_problems(0, 90, 9.0, 0.0, 0).is_empty())
	check("карта без второго портала не обязана иметь разные входы: развилка PRO-139 по-прежнему корректна, а два входа без portal2 — нет",
		TDMap.fork_test("fork").route_problems(0, 90, 1.5, 8.0, 40).is_empty() and not TDMap.build_routes(0, "x", m.routes.map(func(r): return r.waypoints)).route_problems(30, 90, 1.5, 8.0, 40).is_empty())
	var legacy_ok := true
	for s in 60:
		legacy_ok = legacy_ok and TDMap.generate(s).route_problems().is_empty() and not TDMap.generate(s).portal2
	check("обычные карты: проверки прежние, второго портала нет", legacy_ok)

	# ── 2. Расписание и запасной вариант ──
	var ok_sched := true
	for w in range(1, 30):
		var open2: bool = w >= 18
		ok_sched = ok_sched and m.portal_is_open(1, w) == open2 and m.portal_is_open(0, w)
		ok_sched = ok_sched and m.portal_state(w) == ("open" if w >= 18 else ("announced" if w >= 15 else "closed"))
		for k in 30:
			ok_sched = ok_sched and m.route_for(k, w) == (expected_route(k, 50) if w >= 18 else 0)
		ok_sched = ok_sched and m.share_at(1, w) == (0.5 if w >= 18 else 0.0) and m.share_at(0, w) == (0.5 if w >= 18 else 1.0)
	check("расписание: до 18-й волны все через первый портал, с 18-й — 50/50 по очереди; предупреждение с 15-й", ok_sched)
	check("share_at без волны — установившаяся (50/50)", m.share_at(0) == 0.5 and m.share_at(1) == 0.5)
	var m40 := TDMap.portal_test("portal_a", 20, 17, 40)
	var c40 := 0
	for k in 20:
		c40 += m40.route_for(k, 20)
	check("доля 40%: ⌊n·p/100⌋ врагов через второй портал", c40 == 8 and m40.portal2)
	for args in [[1, 1, 50], [18, 19, 50], [18, 15, 0], [18, 15, 60], [18, 0, 50]]:
		var bad := TDMap.portal_test("portal_a", args[0], args[1], args[2])
		check("неверное расписание %s — запасная карта с одним порталом" % str(args), bad.portal_fallback and not bad.portal2 and bad.routes.size() == 1
			and bad.route_problems(TDMap.PORTAL_MIN_PATH, TDMap.MAX_PATH, 1.5, 8.0, 40).is_empty() == bad.route_problems(TDMap.PORTAL_MIN_PATH, TDMap.MAX_PATH, 1.5, 8.0, 40).is_empty())

	# ── 3. Рекорды (PRO-147): график угроз — другое испытание ──
	var key := m.geometry_key()
	var variants := [TDMap.portal_test("portal_a", 19, 15, 50), TDMap.portal_test("portal_a", 18, 14, 50), TDMap.portal_test("portal_a", 18, 15, 40)]
	var keys_ok := true
	for v in variants:
		keys_ok = keys_ok and v.geometry_key() != key
	var same_geo := TDMap.build_routes(0, "x", m.routes.map(func(r): return r.waypoints))
	check("ключ геометрии: другая волна открытия / предупреждения / доля — другой ключ; те же дороги без второго портала — тоже другой; детерминирован",
		keys_ok and same_geo.geometry_key() != key and TDMap.portal_test("portal_a").geometry_key() == key)
	check("рекорд карты с порталами отдельный", TDMeta.record_key(4243, m) != TDMeta.record_key(4243, same_geo))

	# ── 4. Партия: до открытия — как контроль, после — оба входа ──
	var gc := new_game(999, 999)
	var gt := new_game(18, 15)
	defend(gc, 8)
	defend(gt, 8)
	var seen_c := {}
	var seen_t := {}
	var same_before := true
	var detail := ""
	var routes_by_wave := {}
	var fly_starts: Array = []
	for w in range(1, 21):
		if not gc.offer.is_empty():
			gc.choose_perk(gc.offer[0])
		if not gt.offer.is_empty():
			gt.choose_perk(gt.offer[0])
		var rc: Array = []
		var rt: Array = []
		play_wave(gc, seen_c, rc)
		play_wave(gt, seen_t, rt, fly_starts)
		routes_by_wave[w] = rt
		if w < 18:
			var eq: bool = gc.lives == gt.lives and gc.gold == gt.gold and gc.rng.a == gt.rng.a and rc == rt and gc.perk_rng.a == gt.perk_rng.a
			same_before = same_before and eq
			if not eq:
				detail += "w%d: жизни %d/%d золото %d/%d " % [w, gc.lives, gt.lives, gc.gold, gt.gold]
	check("волны 1–17 с тем же сидом и покупками идентичны контролю «один активный портал» (жизни, золото, RNG, маршруты)", same_before, detail)
	var sched_ok := true
	for w in range(1, 21):
		for k in routes_by_wave[w].size():
			sched_ok = sched_ok and routes_by_wave[w][k] == (expected_route(k, 50) if w >= 18 else 0)
	check("выпущенные враги (включая босса 10-й волны) идут точно по расписанию", sched_ok)
	var late_both := {}
	for r in routes_by_wave[18]:
		late_both[r] = true
	check("с 18-й волны оба входа в деле", late_both.size() == 2, str(late_both.keys()))
	var fly_ok := true
	for f in fly_starts:
		fly_ok = fly_ok and (f[1] as Vector2).distance_to(gt.map.routes[f[0]].points[0]) < 1.0
	check("летающие стартуют у своего портала (%d)" % fly_starts.size(), fly_ok)
	check("прямая полёта у второго входа своя: другая длина и направление", absf(gt.map.routes[0].fly_length - gt.map.routes[1].fly_length) > 0.05
		and gt.map.routes[0].heading_at(0.0, true).distance_to(gt.map.routes[1].heading_at(0.0, true)) > 0.05)
	# никто не появляется у замка без времени на подготовку
	var castle := gt.map.routes[0].points.back() as Vector2
	check("оба входа далеко от замка: ≥ %.1f клетки по прямой" % TDMap.FORK_MIN_FLY, gt.map.routes[0].fly_length >= TDMap.FORK_MIN_FLY and gt.map.routes[1].fly_length >= TDMap.FORK_MIN_FLY)
	castle = castle

	# ── 5. Малыши, кладка, прислужники босса — на дороге родителя ──
	var gk := new_game(18, 15)
	var parent := TDGame.Enemy.new()
	parent.id = gk.next_id
	gk.next_id += 1
	parent.genome = TDGenome.random_genome(TDRng.new(parent.id), 1)
	parent.ph = TDGenome.phenotype(parent.genome, 1).duplicate()
	parent.ph["fly"] = false
	parent.ph["stealth"] = false
	parent.hp = parent.ph["hp"]
	parent.route = 1
	parent.dist = 9.0
	gk.enemies.append(parent)
	var kids := gk._split(parent)
	var summ := gk._summon(parent)
	var kr := {}
	for k in kids + summ:
		kr[k.route] = true
	gk.enemies.clear()
	var carrier := TDGame.Enemy.new()
	carrier.id = gk.next_id
	gk.next_id += 1
	carrier.genome = parent.genome
	carrier.ph = parent.ph
	carrier.hp = parent.hp
	carrier.route = 1
	carrier.dist = 0.0
	gk.enemies.append(carrier)
	gk._spawn_strain(carrier, "brood")
	var brood_ok := true
	for k in gk.enemies:
		brood_ok = brood_ok and k.route == 1
	check("малыши деления, прислужники босса и кладка выводка — на дороге родителя (втором входе)", kr.keys() == [1] and brood_ok)

	# ── 6. Сохранения: до предупреждения, после него, в момент открытия, посреди волны ──
	var gs := new_game(18, 15)
	defend(gs, 6)
	var seen_s := {}
	var snaps := {}
	var plain_ok := true
	for w in range(1, 20):
		if not gs.offer.is_empty():
			gs.choose_perk(gs.offer[0])
		if w in [10, 15, 17, 18]:
			# фаза строительства перед волной w
			var snap := TDSave.snapshot(gs)
			var rs := TDSave.restore(bytes_to_var(var_to_bytes(snap)))
			snaps[w] = rs
			plain_ok = plain_ok and rs != null and rs.map.portal2 and rs.map.portal_open == 18 and rs.map.geometry_key() == gs.map.geometry_key() and snap_hash(rs) == snap_hash(gs)
			if w == 18:
				plain_ok = plain_ok and snap.has("portal") and snap["portal"]["open"] == 18
		gs.start_wave()
		var mid_done := false
		var mid: TDGame = null
		for i in 8000:
			gs.step(0.05)
			if mid != null:
				mid.step(0.05)
			if w == 18 and i == 150 and not mid_done:
				mid_done = true
				mid = TDSave.restore(bytes_to_var(var_to_bytes(TDSave.snapshot(gs))))
				plain_ok = plain_ok and mid != null and mid.route_k == gs.route_k and gs.route_k > 0 and snap_hash(mid) == snap_hash(gs)
			if gs.phase != "wave":
				break
		if mid != null:
			check("посреди 18-й волны (второй портал только что открыт): после загрузки бой идёт так же", snap_hash(mid) == snap_hash(gs))
		# загруженные раньше копии догоняют основную партию волна за волной
		for k in snaps:
			if k <= w and snaps[k] != null and k == w:
				pass
	check("загрузка перед волнами 10, 15 (предупреждение), 17 и 18 (открытие): то же расписание, тот же ключ карты и состояние", plain_ok)
	# детерминизм после загрузки: копия из волны 17 проходит 17–19 так же, как основная партия
	var ga := new_game(18, 15)
	defend(ga, 6)
	var seen_a := {}
	var rest: TDGame = null
	var snapped := false
	for w in range(1, 20):
		if not ga.offer.is_empty():
			ga.choose_perk(ga.offer[0])
		if w == 17 and not snapped:
			snapped = true
			rest = TDSave.restore(bytes_to_var(var_to_bytes(TDSave.snapshot(ga))))
		play_wave(ga, seen_a, [])
		if rest != null and w >= 17:
			if not rest.offer.is_empty():
				rest.choose_perk(rest.offer[0])
			play_wave(rest, {}, [])
	check("копия, загруженная перед 17-й волной, к концу 19-й в том же состоянии, что основная партия", rest != null and snap_hash(rest) == snap_hash(ga))
	var snap_plain := TDSave.snapshot(TDGame.new(5, TDMap.generate(5), {}))
	var snap_fork := TDSave.snapshot(TDGame.new(5, TDMap.generate(5, "fork_even"), {}))
	check("сохранения обычной карты и развилки: поля portal нет (формат прежний)", not snap_plain.has("portal") and not snap_fork.has("portal") and TDSave.restore(snap_fork) != null)
	var base_snap := TDSave.snapshot(new_game(18, 15))
	var bads: Array = []
	for mutate in [
		func(d): d["portal"]["open"] = 1,
		func(d): d["portal"]["announce"] = 19,
		func(d): d["portal"]["share"] = 80,
		func(d): d["portal"]["share"] = 0,
		func(d): d["portal"].erase("share"),
		func(d): d["portal"]["open"] = "18",
		func(d): d["portal"] = 5,
		func(d): d.erase("routes"),
	]:
		var d2: Dictionary = base_snap.duplicate(true)
		mutate.call(d2)
		bads.append(TDSave.restore(d2) == null)
	var snap1 := TDSave.snapshot(TDGame.new(5, TDMap.generate(5), {}))
	snap1["portal"] = {"open": 18, "announce": 15, "share": 50}
	check("битые расписания в сохранении отвергаются (волны, доля, тип, нет маршрутов); поле portal на карте с одним путём — тоже", bads.all(func(b): return b) and TDSave.restore(snap1) == null and TDSave.restore(base_snap) != null, str(bads))

	# ── 7. Интерфейс: предупреждение за три волны, не обманывает, не притворяется адаптацией ──
	var gu := new_game(18, 15)
	gu.gold = 3000
	defend(gu, 3)
	var cards_before: Array = []
	var tips_before: Array = []
	var texts := ""
	for w in [10, 14]:
		gu.wave = w
		cards_before.append(TDThreats.cards(gu).filter(func(c): return c["id"] == "portal").size())
		tips_before.append(TDAdvisor.advice(gu, TDAdvisor.wave_info(gu)).map(func(t): return String(t["title"])))
	check("до предупреждения (волны 10, 14): карточки и совета про портал нет, закрытая дорога не считается дырой",
		cards_before == [0, 0] and not tips_before.any(func(t): return t.any(func(x): return "портал" in String(x).to_lower() or "подход" in String(x).to_lower()))
		and TDAdvisor.road_coverage(gu)["uncovered"].keys().all(func(c): return gu.map.routes[0].order.has(c)))
	var seen_cards: Array = []
	for w in [15, 16, 17]:
		gu.wave = w
		var cc: Array = TDThreats.cards(gu).filter(func(c): return c["id"] == "portal")
		var tp: Array = TDAdvisor.advice(gu, TDAdvisor.wave_info(gu))
		seen_cards.append([w, cc.size(), cc[0]["status"] if not cc.is_empty() else "", tp.map(func(t): return String(t["title"]))])
		for c in cc:
			texts += TDThreats.tip_text(c) + "\n"
		for t in tp:
			texts += String(t["text"]) + "\n"
	check("в волнах 15, 16, 17 карточка «Откроется второй портал» (dated) и совет; в 17-й тревога о необстреливаемом подходе",
		seen_cards[0][1] == 1 and seen_cards[0][2] == "dated" and seen_cards[1][2] == "dated" and seen_cards[2][2] == "dated"
		and seen_cards[2][3].any(func(x): return String(x).begins_with("Не защищён"))
		and seen_cards.all(func(s): return s[3].any(func(x): return String(x).begins_with("Не защищён") or x == "Второй портал")), str(seen_cards))
	gu.wave = 15
	var card15: Dictionary = TDThreats.cards(gu).filter(func(c): return c["id"] == "portal")[0]
	check("карточка: волна открытия, доля, башни-ответы, «северный подход»; слов про рой, адаптацию, эволюцию нет",
		"Волна 18" in String(card15["when"]) and "50%" in String(card15["effect"]) and "подход" in String(card15["build"]) and not card15["towers"].is_empty()
		and not (" рой" in texts.to_lower() or "адапт" in texts.to_lower() or "эволю" in texts.to_lower() or "гены" in texts.to_lower()), texts)
	gu.wave = 18
	var c18: Array = TDThreats.cards(gu).filter(func(c): return c["id"] == "portal")
	check("фаза строительства 18-й волны: портал ещё закрыт, карточка «со следующей волны» (next), совет «со следующей волны»",
		c18.size() == 1 and c18[0]["status"] == "next" and gu.portal_state_now() == "announced" and not gu.portal_open_now()
		and TDAdvisor.portal_text(gu).begins_with("Второй портал откроется со следующей волны"))
	gu.phase = "wave"
	check("волна 18 идёт: портал открыт, карточки нет, совет объясняет два портала и долю", TDThreats.cards(gu).filter(func(c): return c["id"] == "portal").is_empty()
		and gu.portal_state_now() == "open" and gu.portal_open_now() and TDAdvisor.portal_text(gu).begins_with("Враги идут через два портала"))
	gu.phase = "build"
	check("состояния по волнам (карта): 1–14 closed, 15–17 announced, с 18-й open; до волны 18 в фазе строительства игра считает его закрытым",
		gu.map.portal_state(1) == "closed" and gu.map.portal_state(14) == "closed" and gu.map.portal_state(15) == "announced" and gu.map.portal_state(17) == "announced" and gu.map.portal_state(18) == "open")
	# защищённый второй подход: тревоги нет
	var gu2 := new_game(18, 15)
	gu2.gold = 4000
	defend(gu2, 3, 0)
	defend(gu2, 4, 1)
	gu2.wave = 16
	var rc2 := TDAdvisor.route_coverage(gu2)
	check("оборона у обоих подходов — тревоги «Не защищён» нет", not TDAdvisor.advice(gu2, TDAdvisor.wave_info(gu2)).any(func(t): return String(t["title"]).begins_with("Не защищён")), str(rc2))

	# ── 8. Карта без портала не затронута ──
	var gf := TDGame.new(7, TDMap.generate(7, "fork_even"))
	var tf: Array = TDAdvisor.advice(gf, TDAdvisor.wave_info(gf)).map(func(t): return String(t["title"]))
	check("развилка PRO-213: подсказка «Две дороги» как прежде, карточки портала нет", "Две дороги" in tf and TDThreats.cards(gf).filter(func(c): return c["id"] == "portal").is_empty())
	var gp := TDGame.new(7, TDMap.generate(7), {})
	check("обычная карта: нет второго портала, share_at и route_for прежние", not gp.map.portal2 and gp.map.share_at(0) == 1.0 and gp.map.route_for(5, 20) == 0 and gp.map.portal_state(20) == "none")

	print("\nFAIL: %d" % failures if failures > 0 else "\nВсе проверки PRO-141 прошли")
	quit(1 if failures > 0 else 0)
