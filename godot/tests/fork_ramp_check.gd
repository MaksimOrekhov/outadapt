extends SceneTree
## PRO-214: постепенный ввод второй дороги (dev-эксперимент). godot --headless --path godot --script res://tests/fork_ramp_check.gd
## Расписание — только по явному запросу (TDMap.set_ramp); без него всё как в PRO-213. Волны, гены, награды и RNG не меняются.

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


## Независимая запись правила: k-й враг идёт по второй дороге, если (k+1)·p/100 > k·p/100.
func expected_route(k: int, pct: int, lead: int) -> int:
	return 1 - lead if ((k + 1) * pct) / 100 > (k * pct) / 100 else lead


## Играет волну без башен (все прорываются) и возвращает маршруты выпущенных врагов по порядку, без малышей.
func play_wave(g: TDGame, seen: Dictionary, hp_acc: Array) -> Array:
	var routes: Array = []
	g.start_wave()
	for _i in 8000:
		g.step(0.05)
		for e in g.enemies:
			if not seen.has(e.id):
				seen[e.id] = true
				if not e.child:
					routes.append(e.route)
					hp_acc[0] += float(e.ph["hp"])
		if g.phase != "wave":
			break
	return routes


func new_game(seed_v: int, fam: String, ramp: String, lead: String) -> TDGame:
	var m := TDMap.generate(seed_v, fam)
	if ramp != "":
		m.set_ramp(ramp, lead)
	return TDGame.new(seed_v, m, {"lives": 100000})


func _initialize() -> void:
	# ── 1. Правило распределения и расписания ──
	var m0 := TDMap.generate(1003, "fork_even")
	check("без расписания: route_for(k, wave) равен route_for(k) — прежний порядок 0, 1, 0, 1", m0.route_ramp.is_empty() and m0.ramp_start() == 0
		and range(40).all(func(k): return m0.route_for(k, 5) == m0.route_for(k) and m0.route_for(k) == k % 2))
	var m1 := TDMap.generate(1003, "fork_even")
	check("set_ramp: известное имя принято, неизвестное и карта с одной дорогой — нет",
		m1.set_ramp("pilot") and not m1.set_ramp("nope") and not TDMap.generate(1003).set_ramp("pilot") and not m1.set_ramp("pilot", "x"))
	var pilot_ok := true
	for w in range(1, 13):
		var pct := 0
		if w >= 3:
			pct = 20
		if w >= 5:
			pct = 35
		if w >= 7:
			pct = 50
		pilot_ok = pilot_ok and m1.ramp_pct(w) == pct
		for lead in [0, 1]:
			m1.route_lead = lead
			var n := TDConfig.wave_size(w)
			var late := 0
			for k in n:
				var r := m1.route_for(k, w)
				pilot_ok = pilot_ok and r == expected_route(k, pct, lead)
				late += 1 if r == 1 - lead else 0
			pilot_ok = pilot_ok and late == (n * pct) / 100
	check("pilot: 1–2 = 0%, 3–4 = 20%, 5–6 = 35%, с 7-й = 50% на второй дороге; число врагов на ней = ⌊n·p/100⌋ при любой первой дороге", pilot_ok)
	m1.route_lead = 0
	check("с 7-й волны расписание совпадает с прежним порядком 0, 1, 0, 1", range(7, 40).all(func(w): return range(30).all(func(k): return m1.route_for(k, w) == k % 2)))
	check("первые две волны — все враги по первой дороге, в 3-й первый втородорожный — пятый", range(30).all(func(k): return m1.route_for(k, 1) == 0 and m1.route_for(k, 2) == 0)
		and m1.route_for(3, 3) == 0 and m1.route_for(4, 3) == 1)
	var late_start := m1.ramp_start()
	check("ramp_start = 3 (pilot); доли по дорогам: share_at(·, 1) = 1/0, share_at(·, 7) = 0,5/0,5, без волны — установившаяся",
		late_start == 3 and m1.share_at(0, 1) == 1.0 and m1.share_at(1, 1) == 0.0 and m1.share_at(0, 7) == 0.5 and m1.share_at(1, 0) == 0.5 and m1.share_at(1, 4) == 0.2)
	var early := TDMap.generate(1003, "fork_even")
	early.set_ramp("early", "long")
	check("early (ограниченный пилот 90/10): со 2-й волны 10%, с 4-й 30%, с 6-й 50%; первая дорога — длинная",
		early.ramp_pct(1) == 0 and early.ramp_pct(2) == 10 and early.ramp_pct(3) == 10 and early.ramp_pct(4) == 30 and early.ramp_pct(6) == 50
		and early.routes[early.route_lead].length >= early.routes[1 - early.route_lead].length)
	var sk := TDMap.generate(1003, "fork_skew")
	sk.set_ramp("pilot", "short")
	var shorter: int = 0 if sk.routes[0].length <= sk.routes[1].length else 1
	var sk2 := TDMap.generate(1003, "fork_skew")
	sk2.set_ramp("pilot", "long")
	check("fork_skew: «короткая» и «длинная» первая дорога — разные дороги, короткая действительно короче",
		sk.route_lead == shorter and sk2.route_lead == 1 - shorter and sk.routes[sk.route_lead].length < sk.routes[1 - sk.route_lead].length)

	# ── 2. Рекорды (PRO-147): расписание — другое испытание, без него ключ прежний ──
	var key_plain := m0.geometry_key()
	var ma := TDMap.generate(1003, "fork_even")
	ma.set_ramp("pilot", "0")
	var ma2 := TDMap.generate(1003, "fork_even")
	ma2.set_ramp("pilot", "0")
	var mb := TDMap.generate(1003, "fork_even")
	mb.set_ramp("pilot", "1")
	var mc := TDMap.generate(1003, "fork_even")
	mc.set_ramp("early", "0")
	check("ключ геометрии: с расписанием — другой, зависит от имени и первой дороги, детерминирован",
		ma.geometry_key() != key_plain and ma.geometry_key() != mb.geometry_key() and ma.geometry_key() != mc.geometry_key()
		and ma.geometry_key() == ma2.geometry_key())
	var mr := TDMap.generate(1003, "fork_even")
	mr.set_ramp("pilot", "0")
	mr.route_ramp = []
	check("снятое расписание возвращает прежний ключ; рекорд карты с расписанием отдельный", mr.geometry_key() == key_plain and TDMeta.record_key(1003, ma) != TDMeta.record_key(1003, m0))

	# ── 3. Партия без башен ──
	# Симметричная карта (две ветки одной длины, PRO-139): все враги прорываются в одно и то же время на любой дороге, поэтому
	# расписание обязано не изменить ни гены волн (они выводятся из прорвавшихся), ни RNG, ни золото, ни жизни, ни HP.
	var sym := TDMap.fork_test("fork")
	check("карта «fork» симметрична: ветки одной длины", absf(sym.routes[0].length - sym.routes[1].length) < 0.001)
	for lead in ["0", "1"]:
		var ma_ := TDMap.fork_test("fork")
		var mb_ := TDMap.fork_test("fork")
		mb_.set_ramp("pilot", lead)
		var ga := TDGame.new(4243, ma_, {"lives": 100000})
		var gb := TDGame.new(4243, mb_, {"lives": 100000})
		var seen_a := {}
		var seen_b := {}
		var same := true
		var spawn_ok := true
		var detail := ""
		for w in range(1, 11):
			var s1 := var_to_bytes(ga.upcoming) == var_to_bytes(gb.upcoming)
			var s2 := ga.rng.a == gb.rng.a and ga.perk_rng.a == gb.perk_rng.a
			if not (s1 and s2 and ga.gold == gb.gold):
				detail += "w%d до: гены %s RNG %s золото %d/%d " % [w, s1, s2, ga.gold, gb.gold]
			same = same and s1 and s2 and ga.gold == gb.gold
			if not ga.offer.is_empty():
				ga.choose_perk(ga.offer[0])
			if not gb.offer.is_empty():
				gb.choose_perk(gb.offer[0])
			var hp_a := [0.0]
			var hp_b := [0.0]
			var ra := play_wave(ga, seen_a, hp_a)
			var rb := play_wave(gb, seen_b, hp_b)
			var s5 := ra.size() == rb.size() and absf(hp_a[0] - hp_b[0]) < 0.001 and ga.lives == gb.lives
			if not s5:
				detail += "w%d после: n=%d/%d hp=%s/%s жизни %d/%d " % [w, ra.size(), rb.size(), hp_a[0], hp_b[0], ga.lives, gb.lives]
			same = same and s5
			var pct: int = gb.map.ramp_pct(w)
			for k in rb.size():
				spawn_ok = spawn_ok and rb[k] == expected_route(k, pct, gb.map.route_lead)
		check("симметричная развилка, первая дорога %s: волны 1–10 — те же гены, RNG, золото, жизни, число и HP врагов, что без расписания" % lead, same, detail)
		check("симметричная развилка, первая дорога %s: маршруты выпущенных врагов (включая босса 10-й волны) идут точно по расписанию" % lead, spawn_ok)

	# На сгенерированных картах разный порядок прорыва по дорогам разной длины законно меняет отбор роя (это не сдвиг RNG
	# расписанием): первая волна, число врагов, жизни при полном прорыве и маршруты по расписанию — те же и верные.
	for fam in ["fork_even", "fork_skew"]:
		for lead in ["short", "long"]:
			var ga := new_game(4243, fam, "", "")
			var gb := new_game(4243, fam, "pilot", lead)
			var seen_a := {}
			var seen_b := {}
			var same := var_to_bytes(ga.upcoming) == var_to_bytes(gb.upcoming) and ga.rng.a == gb.rng.a and ga.perk_rng.a == gb.perk_rng.a
			var spawn_ok := true
			var detail := ""
			for w in range(1, 11):
				if not ga.offer.is_empty():
					ga.choose_perk(ga.offer[0])
				if not gb.offer.is_empty():
					gb.choose_perk(gb.offer[0])
				var ra := play_wave(ga, seen_a, [0.0])
				var rb := play_wave(gb, seen_b, [0.0])
				same = same and ra.size() == rb.size() and ga.lives == gb.lives
				var pct: int = gb.map.ramp_pct(w)
				for k in rb.size():
					if rb[k] != expected_route(k, pct, gb.map.route_lead):
						spawn_ok = false
						detail = "волна %d" % w
			check("%s, первая дорога %s: первая волна, RNG на старте, число врагов и потеря жизней волн 1–10 те же, что без расписания" % [fam, lead], same)
			check("%s, первая дорога %s: маршруты выпущенных врагов идут точно по расписанию" % [fam, lead], spawn_ok, detail)

	# ── 4. Малыши, кладка и прислужники остаются на дороге родителя при расписании ──
	var gk := new_game(12, "fork_even", "pilot", "0")
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
	check("малыши деления и прислужники босса — на дороге родителя, расписание их не трогает", kr.keys() == [1])

	# ── 5. Сохранения: расписание, переход между волнами, середина волны ──
	var gs := new_game(4243, "fork_even", "pilot", "short")
	var seen_s := {}
	var hp_s := [0.0]
	for _w in 2:
		if not gs.offer.is_empty():
			gs.choose_perk(gs.offer[0])
		play_wave(gs, seen_s, hp_s)
	check("перед 3-й волной (переход): сохранение хранит расписание и первую дорогу", gs.wave == 3 and gs.phase == "build"
		and TDSave.snapshot(gs).get("route_ramp") == gs.map.route_ramp and TDSave.snapshot(gs).get("route_lead") == gs.map.route_lead)
	var rs := TDSave.restore(bytes_to_var(var_to_bytes(TDSave.snapshot(gs))))
	check("загрузка перед 3-й волной: то же расписание и тот же ключ карты", rs != null and rs.map.route_ramp == gs.map.route_ramp
		and rs.map.route_lead == gs.map.route_lead and rs.map.geometry_key() == gs.map.geometry_key() and snap_hash(rs) == snap_hash(gs))
	if not gs.offer.is_empty():
		gs.choose_perk(gs.offer[0])
	if rs != null and not rs.offer.is_empty():
		rs.choose_perk(rs.offer[0])
	gs.start_wave()
	rs.start_wave()
	var mid_ok := true
	var mid: TDGame = null
	for i in 8000:
		gs.step(0.05)
		rs.step(0.05)
		if mid != null:
			mid.step(0.05)
		if i == 120:
			# середина 3-й волны: часть врагов выпущена, route_k > 0
			mid = TDSave.restore(bytes_to_var(var_to_bytes(TDSave.snapshot(gs))))
			mid_ok = mid != null and mid.route_k == gs.route_k and gs.route_k > 0 and snap_hash(mid) == snap_hash(gs)
		if gs.phase != "wave":
			break
	check("загрузка до волны и посреди волны: бой идёт так же, враги выпускаются по расписанию дальше", mid_ok and snap_hash(rs) == snap_hash(gs) and mid != null and snap_hash(mid) == snap_hash(gs))
	var gm := new_game(4243, "fork_even", "pilot", "short")
	var snap_bad: Dictionary = TDSave.snapshot(gm)
	var bad1 := snap_bad.duplicate(true)
	bad1["route_ramp"] = [[2, 0], [3, 20]]
	var bad2 := snap_bad.duplicate(true)
	bad2["route_lead"] = 5
	var bad3 := snap_bad.duplicate(true)
	bad3["route_ramp"] = [[1, 0], [3, 80]]
	var bad4 := snap_bad.duplicate(true)
	bad4["route_ramp"] = []
	var bad5 := snap_bad.duplicate(true)
	bad5.erase("route_lead")
	var plain_snap := TDSave.snapshot(new_game(4243, "fork_even", "", ""))
	var legacy_snap := TDSave.snapshot(TDGame.new(5, TDMap.generate(5), {}))
	var bad6 := legacy_snap.duplicate(true)
	bad6["route_ramp"] = [[1, 0], [3, 20]]
	bad6["route_lead"] = 0
	check("битое расписание в сохранении отвергается (волна не с 1-й, лидер вне дорог, доля > 50%, пустое, без лидера, на карте без дорог)",
		TDSave.restore(snap_bad) != null and TDSave.restore(bad1) == null and TDSave.restore(bad2) == null and TDSave.restore(bad3) == null
		and TDSave.restore(bad4) == null and TDSave.restore(bad5) == null and TDSave.restore(bad6) == null)
	check("карта без расписания и обычная карта: в сохранении нет полей расписания (формат прежний)",
		not plain_snap.has("route_ramp") and not plain_snap.has("route_lead") and not legacy_snap.has("route_ramp") and TDSave.restore(plain_snap) != null)

	# ── 6. Подсказки: расписание объяснено, адаптация не обещана; предупреждение за волну до второй дороги ──
	var gt := new_game(7, "fork_even", "pilot", "0")
	var tips := TDAdvisor.advice(gt, TDAdvisor.wave_info(gt))
	var two: Array = tips.filter(func(t): return t["title"] == "Две дороги")
	var txt: String = String(two[0]["text"]) if not two.is_empty() else ""
	check("1-я волна: подсказка «Две дороги» называет первую дорогу, волну подключения и доли; рой и адаптация не упомянуты",
		not two.is_empty() and "С 3-й волны" in txt and "20%" in txt and "35%" in txt and "заранее известно" in txt
		and not ("адапт" in txt.to_lower()) and not (" рой" in txt.to_lower()) and not ("эволю" in txt.to_lower()), txt)
	gt.gold = 3000
	var first_id: int = gt.map.route_lead
	var placed := 0
	for c in gt.map.routes[first_id].order:
		if gt.map.routes_at(c).size() > 1:
			continue
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var p: Vector2i = c + d
			if placed < 3 and p.y >= 0 and gt.map.routes_at(p).is_empty() and gt.place_tower("arrow", p.x, p.y):
				placed += 1
	var t1: Array = TDAdvisor.advice(gt, TDAdvisor.wave_info(gt)).map(func(t): return t["title"])
	check("1-я волна: вторая дорога ещё пуста, «Открыта … дорога» не показывается", not t1.any(func(t): return String(t).begins_with("Открыта")), str(t1))
	gt.wave = 2
	var t2: Array = TDAdvisor.advice(gt, TDAdvisor.wave_info(gt)).map(func(t): return t["title"])
	check("2-я волна (перед подключением): «Открыта … дорога» предупреждает о необстреливаемой дороге", t2.any(func(t): return String(t).begins_with("Открыта")), str(t2))
	gt.wave = 6
	var t5: Array = TDAdvisor.advice(gt, TDAdvisor.wave_info(gt))
	var t5txt: String = String(t5.filter(func(t): return String(t["title"]).begins_with("Открыта"))[0]["text"]) if t5.any(func(t): return String(t["title"]).begins_with("Открыта")) else ""
	check("6-я волна: текст говорит о текущей доле (65/35) и о следующей волне (50%)", "65%" in t5txt and "35%" in t5txt and "50%" in t5txt, t5txt)

	print("\nFAIL: %d" % failures if failures > 0 else "\nВсе проверки PRO-214 прошли")
	quit(1 if failures > 0 else 0)
