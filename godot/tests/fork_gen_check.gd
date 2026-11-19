extends SceneTree
## PRO-213: генератор статических развилок (dev-режим). godot --headless --path godot --script res://tests/fork_gen_check.gd
## Развилки — только по явному запросу (TDMap.generate(seed, "fork_even" | "fork_skew")), обычная ротация не меняется.

const SEEDS := 1000
const MAX_FALLBACK := 0.05

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


## Простая оборона «как у бота»: лучшие по покрытию всех дорог клетки (с весом доли врагов).
func defend(g: TDGame, n: int) -> void:
	var cells: Array = []
	for x in TDConfig.COLS:
		for y in TDConfig.ROWS:
			if g.map.is_path(x, y) or g.map.is_blocked(x, y):
				continue
			var sc := 0.0
			for r in g.map.routes:
				for s in 60:
					if r.pos_at(s / 60.0 * r.length).distance_to(Vector2(x + 0.5, y + 0.5)) <= 3.2:
						sc += TDAdvisor.route_share(g.map, r.id)
			cells.append([sc, x, y])
	cells.sort_custom(func(a, b): return a[0] > b[0])
	var kinds := ["arrow", "cannon", "frost", "arrow", "sniper", "ember"]
	var placed := 0
	for c in cells:
		if placed >= n:
			break
		if g.place_tower(kinds[placed % kinds.size()], c[1], c[2]):
			placed += 1


func _initialize() -> void:
	# ── 1. Обычная ротация не меняется ──
	var rot_ok := true
	for f in TDMap.FAMILIES:
		rot_ok = rot_ok and not TDMap.is_fork_family(f["id"])
	for s in 5000:
		if TDMap.is_fork_family(TDMap.family_for(s)):
			rot_ok = false
	for s in 300:
		if TDMap.generate(s).is_multi():
			rot_ok = false
	check("развилок нет в обычной ротации: family_for и generate(seed) их не выдают", rot_ok)

	# ── 2. Каждая выданная карта корректна; доля отката ──
	for fam in TDMap.FORK_FAMILIES:
		var spec: Dictionary = TDMap.FORK_FAMILIES[fam]
		var fallback := 0
		var invalid: Array = []
		var trunk := {}
		var t0 := Time.get_ticks_msec()
		for i in SEEDS:
			var s := i * 4243 + 1
			var m := TDMap.generate(s, fam)
			if m.fork_fallback:
				fallback += 1
				if m.is_multi() or not m.route_problems(2, 1000, 100.0, 0.0, 0).is_empty() or TDMap.is_fork_family(m.family):
					invalid.append("%d откат" % s)
				continue
			var probs := m.route_problems(TDMap.FORK_MIN_PATH, TDMap.MAX_PATH, TDMap.FORK_MAX_RATIO, TDMap.FORK_MIN_FLY, TDMap.FORK_MIN_BUILD)
			var ratio := maxf(m.routes[0].length, m.routes[1].length) / minf(m.routes[0].length, m.routes[1].length)
			if m.routes.size() != 2 or not probs.is_empty() or m.family != fam or ratio < float(spec["ratio"][0]) - 1e-6 or ratio > float(spec["ratio"][1]) + 1e-6 \
					or m.shared_in() < 1 or m.shared_in() > 3 or m.shared_out() < 3:
				invalid.append("%d: %s r=%.2f in=%d out=%d" % [s, ", ".join(probs), ratio, m.shared_in(), m.shared_out()])
			trunk[m.shared_in()] = int(trunk.get(m.shared_in(), 0)) + 1
		var rate := float(fallback) / SEEDS
		check("%s: %d сидов — все выданные карты корректны (развилка: две дороги ≥ %d клеток, отношение %.2f–%.2f, ствол 1–3, участок у замка ≥ 3)" % [
			fam, SEEDS, TDMap.FORK_MIN_PATH, spec["ratio"][0], spec["ratio"][1]], invalid.is_empty(), ", ".join(invalid.slice(0, 3)))
		check("%s: откат на обычную карту %.1f%% (≤ %d%%), общий ствол %s, %d мс" % [fam, rate * 100.0, int(MAX_FALLBACK * 100), trunk, Time.get_ticks_msec() - t0], rate <= MAX_FALLBACK)

	# ── 3. Детерминизм и независимость от потоков волн ──
	var det := true
	for i in 50:
		var s := i * 977 + 5
		for fam in TDMap.FORK_FAMILIES:
			det = det and TDMap.generate(s, fam).geometry_key() == TDMap.generate(s, fam).geometry_key()
	check("тот же сид — та же развилка", det)
	var s1 := 1003
	var mf := TDMap.generate(s1, "fork_even")
	var gf := TDGame.new(s1, mf, {"start_perk": true})
	var gn := TDGame.new(s1, null, {"start_perk": true})
	check("на развилке волны, гены и перки сида те же, что на обычной карте", var_to_bytes(gf.upcoming) == var_to_bytes(gn.upcoming)
		and gf.offer == gn.offer and gf.rng.a == gn.rng.a and gf.perk_rng.a == gn.perk_rng.a)
	check("рекорд развилки отдельно от рекорда обычной карты сида", TDMeta.record_key(s1, mf) != TDMeta.record_key(s1, TDMap.generate(s1)))
	check("вариант для dev-режима выбирается по сиду детерминированно", TDMap.fork_family_for(s1) == TDMap.fork_family_for(s1)
		and TDMap.is_fork_family(TDMap.fork_family_for(s1)))
	var fly_ok := true
	for r in mf.routes:
		fly_ok = fly_ok and r.fly_length == mf.fly_length and r.points[0] == mf.points[0] and r.points.back() == mf.points.back()
	check("один портал и один замок: прямая полёта одна для обеих дорог", fly_ok)

	# ── 4. Партия на сгенерированных развилках: обе дороги в деле, сохранение посреди волны ──
	for fam in TDMap.FORK_FAMILIES:
		var m := TDMap.generate(4243, fam)
		var g := TDGame.new(4243, m, {"lives": 1000})
		g.gold = 1500
		defend(g, 10)
		var kills := {}
		var spawned := {}
		var snap_done := false
		var snap := {}
		var restored: TDGame = null
		for w in 8:
			if not g.offer.is_empty():
				g.choose_perk(g.offer[0])
			g.start_wave()
			for i in 6000:
				g.step(0.05)
				for e in g.enemies:
					spawned[e.route] = true
				if restored != null and w == 5:
					restored.step(0.05)
				if w == 5 and i == 150 and not snap_done:
					snap_done = true
					snap = TDSave.snapshot(g)
					restored = TDSave.restore(snap)
				if g.phase != "wave":
					break
			for f in g.finished:
				if float(f["fitness"]) < 1.5:
					kills[int(f["route"])] = true
			if restored != null and w == 5:
				check("%s: после загрузки посреди волны бой идёт так же" % fam, snap_hash(restored) == snap_hash(g))
		var routes_in_snap := {}
		for e in snap.get("enemies", []):
			routes_in_snap[int(e.get("route", 0))] = true
		check("%s: враги шли по обеим дорогам, убийства на обеих, в сохранении враги обеих дорог" % fam,
			spawned.has(0) and spawned.has(1) and kills.has(0) and kills.has(1) and routes_in_snap.size() == 2, "%s %s %s" % [spawned, kills, routes_in_snap])

	# ── 5. Подсказки: две дороги и открытая дорога ──
	var ga := TDGame.new(7, TDMap.generate(7, "fork_even"))
	var tips := TDAdvisor.advice(ga, TDAdvisor.wave_info(ga))
	var titles: Array = tips.map(func(t): return t["title"])
	check("в начале — подсказка «Две дороги» с долями", "Две дороги" in titles)
	var names: Array = TDAdvisor.route_coverage(ga).map(func(x): return x["name"])
	check("дороги называются «северная» и «южная»", names.has("северная") and names.has("южная"))
	ga.gold = 2000
	var north_id := 0 if TDAdvisor.route_name(ga.map, 0) == "северная" else 1
	var placed := 0
	for c in ga.map.routes[north_id].order:
		if ga.map.routes_at(c).size() > 1:
			continue
		for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var p: Vector2i = c + d
			if placed < 3 and p.y >= 0 and ga.map.routes_at(p).is_empty() and p.y < ga.map.routes[north_id].order[0].y - 1 and ga.place_tower("arrow", p.x, p.y):
				placed += 1
	var rc := TDAdvisor.route_coverage(ga)
	var tips2: Array = TDAdvisor.advice(ga, TDAdvisor.wave_info(ga)).map(func(t): return t["title"])
	check("башни только у северной — подсказка «Открыта южная дорога»", "Открыта южная дорога" in tips2, "%s %s" % [tips2, rc])

	print("\nFAIL: %d" % failures if failures > 0 else "\nВсе проверки PRO-213 прошли")
	quit(1 if failures > 0 else 0)
