extends SceneTree
## Боевая интеграционная проверка «Приманки» (PRO-118, ревью): настоящая симуляция боя (`step`), а не fake_wave.
## Сравниваются два прогона одной и той же игры: без приманки и с приманкой на ближайшей волне.
## godot --headless --path godot --script res://tests/lure_combat_check.gd

const DT := 1.0 / 30.0
var failures := 0


func check(label: String, condition: bool, detail: String = "") -> void:
	print(("OK    " if condition else "FAIL  ") + label + ("" if detail == "" else "  (" + detail + ")"))
	if not condition:
		failures += 1


## Клетки рядом с дорогой, лучшие по покрытию пути.
func coverage_cells(g: TDGame, r: float = 3.0) -> Array:
	var cells: Array = []
	for x in TDConfig.COLS:
		for y in TDConfig.ROWS:
			if g.map.is_path(x, y) or g.map.is_blocked(x, y):
				continue
			var score := 0
			for s in 60:
				if g.map.pos_at(s / 60.0 * g.map.length).distance_to(Vector2(x + 0.5, y + 0.5)) <= r:
					score += 1
			cells.append({"x": x, "y": y, "score": score})
	cells.sort_custom(func(a, b): return a["score"] > b["score"] if a["score"] != b["score"] else (a["x"] * 100 + a["y"]) < (b["x"] * 100 + b["y"]))
	return cells


## Тратит золото как бот: новая башня по кругу из cycle, иначе улучшение самой полезной.
func spend(g: TDGame, cycle: Array, cells: Array) -> void:
	for _guard in 80:
		var kind: String = cycle[g.towers.size() % cycle.size()]
		var up: TDGame.Tower = null
		for t in g.towers:
			if g.can_upgrade(t) and (up == null or t.dealt > up.dealt):
				up = t
		var spot = null
		for c in cells:
			if g.can_place(kind, c["x"], c["y"]):
				spot = c
				break
		if up != null and (spot == null or g.upgrade_cost(up) <= g.tower_cost(kind)):
			if not g.upgrade_tower(up, "a" if up.id % 2 == 0 else "b"):
				return
		elif spot == null or not g.place_tower(kind, spot["x"], spot["y"]):
			return


## Играет одну волну полностью. Возвращает показатели боя.
func fight(g: TDGame) -> Dictionary:
	var lives0 := g.lives
	var gold0 := g.gold
	g.start_wave()
	var steps := 0
	while g.phase == "wave" and steps < 60000:
		g.step(DT)
		steps += 1
	var fit := 0.0
	for f in g.finished:
		fit += float(f["fitness"])
	var r: Dictionary = g.reports[g.reports.size() - 1]
	return {"lives_lost": lives0 - g.lives, "leaked": int(r["leaked"]), "killed": int(r["killed"]), "size": int(r["size"]),
		"mean_fitness": fit / maxf(1.0, float(g.finished.size())), "gold_gain": g.gold - gold0, "report": r, "steps": steps}


## Игра, доведённая обычной игрой (без приманок) до волны target; null, если рой победил раньше.
func prepared(seed_v: int, cycle: Array, target: int) -> TDGame:
	var g := TDGame.new(seed_v)
	var cells := coverage_cells(g)
	while g.wave < target:
		g.offer = []
		spend(g, cycle, cells)
		fight(g)
		if g.phase == "over":
			return null
	g.offer = []
	return g


## Продвигает пару идентичных игр до обычной волны, на которой приманка разрешена (без босса и особенностей).
func advance_pair(a: TDGame, b: TDGame, cycle: Array, cells: Array) -> bool:
	var guard := 0
	while (not a.upcoming_boss.is_empty() or a.upcoming_special != "" or a.wave < TDConfig.LURE_MIN_WAVE) and guard < 12:
		for gg in [a, b]:
			gg.offer = []
			spend(gg, cycle, cells)
			fight(gg)
		guard += 1
		if a.phase == "over" or b.phase == "over":
			return false
	a.offer = []
	b.offer = []
	return true


func _initialize() -> void:
	var fire_cycle := ["ember", "arrow", "ember", "frost", "arrow", "cannon"]
	var phys_cycle := ["arrow", "cannon", "arrow", "sniper", "cannon", "arrow"]
	var seeds := [4243, 8486, 12729, 16972, 21215, 25458, 29701, 33944]

	# A. Безрисковой приманки нет: без нужных башен ген запрещён, а реальная выплата равна нулю
	var g0 := TDGame.new(4243)
	var cells0 := coverage_cells(g0)
	var guard0 := 0
	while (g0.wave < 6 or not g0.upcoming_boss.is_empty() or g0.upcoming_special != "") and guard0 < 14 and g0.phase != "over":
		g0.offer = []
		spend(g0, phys_cycle, cells0)
		fight(g0)
		guard0 += 1
	g0.offer = []
	spend(g0, phys_cycle, cells0)
	check("A: игра дожила до проверки", g0.phase == "build" and g0.upcoming_boss.is_empty() and g0.upcoming_special == "")
	check("A: без огня и льда приманка на огнестойкость запрещена", g0.lure_problem("ember") != "", g0.lure_problem("ember"))
	check("A: без огня и льда приманка на морозостойкость запрещена", g0.lure_problem("frost") != "")
	check("A: оценка награды без риска нулевая", g0.lure_estimate("ember") == 0)
	# обход: приманка принудительно (старое сохранение или ошибка) — реальная выплата всё равно нулевая
	g0.lure = {"gene": "ember", "boost": TDConfig.lure_boost("ember"), "wave": g0.wave}
	var fr := fight(g0)
	check("A: принудительная приманка без огня не даёт награды", fr["report"].has("lure") and fr["report"]["lure"]["bonus"] == 0 and fr["report"]["lure"]["exposure"] < TDConfig.LURE_MIN_EXPOSURE, str(fr["report"].get("lure")))

	# B. Реальный риск: на одной и той же игре приманка делает волну опаснее, чем без неё
	var totals := {"lost_p": 0, "lost_l": 0, "fit_p": 0.0, "fit_l": 0.0, "n": 0, "bonus": 0}
	var rng_equal := 0
	var rng_checked := 0
	var upcoming_diff := 0
	var diff_mag := 0.0
	for gene in ["swift", "tough", "ember"]:
		var cycle: Array = fire_cycle
		var lost_p := 0
		var lost_l := 0
		var fit_p := 0.0
		var fit_l := 0.0
		var n := 0
		for sd in seeds:
			var a := TDGame.new(sd)
			var b := TDGame.new(sd)
			var cells := coverage_cells(a)
			if not advance_pair(a, b, cycle, cells):
				continue
			for gg in [a, b]:
				spend(gg, cycle, cells)
			if a.lure_problem(gene) != "":
				continue
			check("B: до приманки прогоны идентичны (%s, сид %d)" % [gene, sd], JSON.stringify(a.upcoming) == JSON.stringify(b.upcoming) and a.rng.a == b.rng.a and a.gold == b.gold)
			a.buy_lure(gene)
			var ra := fight(a)
			var rb := fight(b)
			lost_p += rb["lives_lost"]
			lost_l += ra["lives_lost"]
			fit_p += rb["mean_fitness"]
			fit_l += ra["mean_fitness"]
			n += 1
			totals["bonus"] += int(ra["report"]["lure"]["bonus"])
			rng_checked += 1
			if a.rng.a == b.rng.a:
				rng_equal += 1
			if JSON.stringify(a.upcoming) != JSON.stringify(b.upcoming):
				upcoming_diff += 1
				var d := 0.0
				for i in mini(a.upcoming.size(), b.upcoming.size()):
					for k in TDGenome.GENES:
						d += absf(a.upcoming[i][k] - b.upcoming[i][k])
				diff_mag += d / maxf(1.0, float(a.upcoming.size() * TDGenome.GENES.size()))
		totals["lost_p"] += lost_p
		totals["lost_l"] += lost_l
		totals["fit_p"] += fit_p
		totals["fit_l"] += fit_l
		totals["n"] += n
		print("  %s: %d прогонов; потеряно жизней без приманки %d, с приманкой %d; средний прогресс врагов к смерти %.3f → %.3f" % [gene, n, lost_p, lost_l, fit_p / maxf(1.0, n), fit_l / maxf(1.0, n)])
		check("B: %s — есть сравнимые прогоны" % gene, n >= 4, str(n))
		check("B: %s — приманка не облегчает волну (враги заходят не ближе)" % gene, fit_l >= fit_p - 1e-9, "%.3f против %.3f" % [fit_l / maxf(1.0, n), fit_p / maxf(1.0, n)])
	check("B: приманка суммарно опаснее обычной волны (прогресс врагов к смерти выше)", totals["fit_l"] > totals["fit_p"], "%.3f против %.3f" % [totals["fit_l"], totals["fit_p"]])
	check("B: жизней с приманкой потеряно не меньше", totals["lost_l"] >= totals["lost_p"], "%d против %d" % [totals["lost_l"], totals["lost_p"]])
	check("B: награда выплачена в боях с риском", totals["bonus"] > 0, str(totals["bonus"]))
	print("B: прогонов %d; потеряно жизней без приманки %d, с приманкой %d; суммарная награда %d" % [totals["n"], totals["lost_p"], totals["lost_l"], totals["bonus"]])

	# C. Влияние на отбор: rng не сдвигается, а геномы следующей волны могут отличаться из-за другого fitness
	check("C: rng после волны одинаков с приманкой и без неё", rng_equal == rng_checked and rng_checked > 0, "%d из %d" % [rng_equal, rng_checked])
	print("C: геномы следующей волны отличались в %d из %d сравнений, среднее отличие гена %.4f (косвенное влияние через боевые результаты)" % [upcoming_diff, rng_checked, diff_mag / maxf(1.0, upcoming_diff)])
	check("C: косвенное влияние на отбор действительно наблюдается (документация не должна обещать «нулевое»)", upcoming_diff > 0)

	# D. Награда в бою совпадает с формулой и ограничена долей дохода волны
	var ad := TDGame.new(8486)
	var bd := TDGame.new(8486)
	var cd := coverage_cells(ad)
	check("D: пара игр дошла до обычной волны", advance_pair(ad, bd, fire_cycle, cd))
	spend(ad, fire_cycle, cd)
	var est := ad.lure_estimate("swift")
	check("D: приманка куплена", ad.buy_lure("swift"))
	var rd := fight(ad)
	var lr: Dictionary = rd["report"].get("lure", {})
	check("D: в отчёте боя есть приманка", not lr.is_empty())
	if not lr.is_empty():
		var expect := int(round(TDConfig.LURE_SHARE * lr["income"] * lr["exposure"] * lr["saturation"]))
		check("D: награда боя = формула", lr["bonus"] == expect, "%d против %d" % [lr["bonus"], expect])
		check("D: награда не больше доли дохода волны", lr["bonus"] <= int(ceil(TDConfig.LURE_SHARE * lr["income"])))
		check("D: оценка до боя того же порядка, что и итог", est > 0 and absi(est - lr["bonus"]) <= maxi(10, int(0.6 * est)), "оценка %d, итог %d" % [est, lr["bonus"]])

	print("Lure combat checks: %d failures" % failures)
	quit(1 if failures > 0 else 0)
