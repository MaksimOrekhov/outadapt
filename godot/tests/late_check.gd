extends SceneTree
## PRO-192: хуки вариантов поздней игры только для балансных прогонов. godot --headless --path godot --script res://tests/late_check.gd
## 1) По умолчанию (late_variant == "") интервал выхода, награда и бюджет признаков — прежние константы на всех волнах.
## 2) Любой вариант не трогает волны 1–15, боссов и особые волны (кроме бюджета признаков — он про генокод, не про волну).
## 3) Одна и та же партия с выключенными хуками даёт тот же результат, что и раньше (детерминизм по сиду).

var failures := 0


func check(label: String, condition: bool, detail: String = "") -> void:
	print(("OK    " if condition else "FAIL  ") + label + ("" if detail == "" else "  (" + detail + ")"))
	if not condition:
		failures += 1


func old_budget(w: int) -> float:
	return minf(3.4, 1.5 + 0.13 * w)


func _initialize() -> void:
	var specials: Array = [""] + TDConfig.SPECIAL_ORDER
	check("по умолчанию хуки выключены", TDConfig.late_variant == "")

	var bad := []
	for w in range(1, 61):
		for sp in specials:
			if TDConfig.spawn_interval(w, sp) != TDConfig.SPAWN_INTERVAL:
				bad.append("spawn w%d %s" % [w, sp])
		if TDConfig.kill_reward(w) != TDConfig.KILL_REWARD:
			bad.append("reward w%d" % w)
		if TDGenome.budget(w) != old_budget(w):
			bad.append("budget w%d" % w)
	check("без варианта: интервал 0,6, награда 3, бюджет как раньше (волны 1–60)", bad.is_empty(), ", ".join(bad.slice(0, 5)))

	for v in ["dense", "dense2", "budget", "econ"]:
		TDConfig.late_variant = v
		var early := []
		for w in range(1, 16):
			for sp in specials:
				if TDConfig.spawn_interval(w, sp) != TDConfig.SPAWN_INTERVAL:
					early.append("spawn w%d" % w)
			if TDConfig.kill_reward(w) != TDConfig.KILL_REWARD:
				early.append("reward w%d" % w)
			if TDGenome.budget(w) != old_budget(w):
				early.append("budget w%d" % w)
		check("%s: волны 1–15 без изменений" % v, early.is_empty(), ", ".join(early.slice(0, 5)))
		var boss_sp := []
		for w in range(16, 61):
			var boss := w % TDConfig.BOSS_EVERY == 0
			for sp in specials:
				if (boss or sp != "") and TDConfig.spawn_interval(w, sp) != TDConfig.SPAWN_INTERVAL:
					boss_sp.append("w%d %s" % [w, sp])
		check("%s: боссовые и особые волны выходят как раньше" % v, boss_sp.is_empty(), ", ".join(boss_sp.slice(0, 5)))
	TDConfig.late_variant = "dense"
	check("dense: 21-я волна плотнее (0,6 × 0,76)", is_equal_approx(TDConfig.spawn_interval(21, ""), 0.6 * 0.76))
	check("dense: пол интервала 0,3 с", is_equal_approx(TDConfig.spawn_interval(59, ""), 0.3))
	TDConfig.late_variant = "dense2"
	check("dense2: пол интервала 0,21 с", is_equal_approx(TDConfig.spawn_interval(29, ""), 0.6 * 0.35))
	TDConfig.late_variant = "econ"
	check("econ: награда 2 после 15-й", TDConfig.kill_reward(16) == 2 and TDConfig.kill_reward(15) == 3)
	TDConfig.late_variant = "budget"
	check("budget: бюджет растёт после 15-й", is_equal_approx(TDGenome.budget(30), 3.4 + 0.08 * 15.0))
	TDConfig.late_variant = ""

	# Детерминизм: две одинаковые партии без вмешательства — одинаковый ход боя и экономика.
	var a := _play(4243)
	var b := _play(4243)
	check("партия детерминирована по сиду (8 волн)", a == b, "%s vs %s" % [a, b])

	print("\nFAIL: %d" % failures if failures > 0 else "\nВсе проверки PRO-192 прошли")
	quit(1 if failures > 0 else 0)


## Короткая партия без башен-ботов: ставит лучников вдоль дороги и играет 8 волн; итог — снимок состояния.
func _play(seed_v: int) -> String:
	var g := TDGame.new(seed_v)
	g.gold = 3000
	var placed := 0
	for c in g.map.order:
		if placed >= 24:
			break
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var n: Vector2i = c + d
			if g.can_place("arrow", n.x, n.y):
				g.place_tower("arrow", n.x, n.y)
				placed += 1
				break
	for i in 8:
		if not g.offer.is_empty():
			g.choose_perk(g.offer[0])
		if not g.start_wave():
			break
		var guard := 0
		while g.phase == "wave" and guard < 20000:
			g.step(0.05)
			guard += 1
	return "w%d gold%d lives%d killed%d" % [g.wave, g.gold, g.lives, g.killed]
