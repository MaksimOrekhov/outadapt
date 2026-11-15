extends SceneTree
## Проверка вакцины: godot --headless --path godot --script res://tests/vaccine_check.gd

var failures := 0


func check(label: String, condition: bool, detail: String = "") -> void:
	print(("OK    " if condition else "FAIL  ") + label + ("" if detail == "" else "  (" + detail + ")"))
	if not condition:
		failures += 1


## Заканчивает волну без боя: имитирует итог, чтобы эволюция пошла по тем же путям, что и в игре.
func fake_wave(g: TDGame, hp_bias: float = 1.0) -> void:
	g.start_wave()
	g.finished = []
	for i in g.wave_genomes.size():
		g.finished.append({"genome": g.wave_genomes[i], "fitness": float(i) * hp_bias})
	g.pending = []
	g.enemies.clear()
	g.killed = g.wave_genomes.size()
	g._end_wave()


func avg_of(g: TDGame, gene: String) -> float:
	return TDGenome.average_genome(g.upcoming)[gene]


func max_of(g: TDGame, gene: String) -> float:
	var m := 0.0
	for e in g.upcoming:
		m = maxf(m, e[gene])
	return m


func _init() -> void:
	# 1. Ограничения покупки
	var g := TDGame.new(777)
	g.gold = 1000
	check("нельзя купить неизвестный ген", g.vaccine_problem("nope") != "")
	check("нельзя купить против нераскрытого признака", g.vaccine_problem("ward") != "")
	check("можно купить против открытого гена", g.vaccine_problem("plated") == "")
	var poor := TDGame.new(777)
	poor.gold = TDConfig.vaccine_cost(1) - 1
	check("не хватает золота", poor.vaccine_problem("plated") != "")
	g.start_wave()
	check("нельзя купить во время волны", g.vaccine_problem("plated") != "")
	g.pending = []
	g.enemies.clear()
	g.finished = []
	for i in g.wave_genomes.size():
		g.finished.append({"genome": g.wave_genomes[i], "fitness": float(i)})
	g._end_wave()

	# 2. Покупка списывает золото, ставит потолок, действует 2 волны, затем пауза
	g.gold = 1000
	var cost := TDConfig.vaccine_cost(g.wave)
	var cap_before := g.vaccine_cap("plated")
	check("покупка прошла", g.buy_vaccine("plated"))
	check("золото списано", g.gold == 1000 - cost)
	check("ближайшая волна не выше потолка", max_of(g, "plated") <= cap_before + 1e-9)
	check("вторую вакцину купить нельзя", g.vaccine_problem("tough") != "")
	check("повторная покупка отклонена", not g.buy_vaccine("tough") and g.gold == 1000 - cost)
	var w := g.wave
	fake_wave(g)
	check("вторая волна тоже под потолком", max_of(g, "plated") <= cap_before + 1e-9, "max=%.3f cap=%.3f" % [max_of(g, "plated"), cap_before])
	check("вакцина ещё действует (осталась 1 волна)", not g.vaccine.is_empty() and g.vaccine["left"] == 1)
	fake_wave(g)
	check("вакцина закончилась", g.vaccine.is_empty() and g.vaccine_cd == TDConfig.VACCINE_COOLDOWN)
	check("в перезарядке купить нельзя", g.vaccine_problem("plated") != "" and w + 2 == g.wave)
	fake_wave(g)
	fake_wave(g)
	check("перезарядка прошла", g.vaccine_cd == 0)

	# 3. Детерминированность: поток rng не зависит от вакцины
	var a := TDGame.new(4243)
	var b := TDGame.new(4243)
	a.gold = 1000
	b.gold = 1000
	for _i in 3:
		fake_wave(a)
		fake_wave(b)
	check("до вакцины игры совпадают", a.rng.a == b.rng.a and JSON.stringify(a.upcoming) == JSON.stringify(b.upcoming))
	a.buy_vaccine("tough")
	fake_wave(a)
	fake_wave(b)
	check("rng с вакциной и без неё идёт одинаково", a.rng.a == b.rng.a)
	var diff := 0.0
	for k in TDGenome.GENES:
		if k != "tough":
			for i in a.upcoming.size():
				diff += absf(a.upcoming[i][k] - b.upcoming[i][k])
	check("другие гены вакцина не меняет", diff < 1e-9, "diff=%f" % diff)
	check("защищённый ген не выше, чем без вакцины", avg_of(a, "tough") <= avg_of(b, "tough") + 1e-9)
	var c := TDGame.new(4243)
	var d := TDGame.new(4243)
	c.gold = 1000
	d.gold = 1000
	for _i in 6:
		if c.vaccine_problem("plated") == "":
			c.buy_vaccine("plated")
			d.buy_vaccine("plated")
		fake_wave(c)
		fake_wave(d)
	check("два одинаковых прогона с вакциной совпадают", JSON.stringify(c.upcoming) == JSON.stringify(d.upcoming) and c.gold == d.gold and c.rng.a == d.rng.a)

	# 4. Защита от эксплойтов: нельзя заглушить гены до разблокировки; потолок не растёт
	var e := TDGame.new(11)
	e.gold = 5000
	for _i in 13:
		fake_wave(e)
	check("перед 15-й волной щит недоступен", e.wave < 15 and e.vaccine_problem("ward") != "")
	fake_wave(e)
	e.gold = 5000
	check("на волне появления щита вакцина запрещена (скауты нельзя вычеркнуть)", e.wave == 15 and e.vaccine_problem("ward") != "")
	check("скауты щита присутствуют", max_of(e, "ward") >= 0.5)
	for _i in TDConfig.VACCINE_TRAIT_DELAY:
		fake_wave(e)
	e.gold = 5000
	check("через %d волны после появления щит доступен" % TDConfig.VACCINE_TRAIT_DELAY, e.vaccine_problem("ward") == "")
	e.buy_vaccine("ward")
	check("рост щита сдерживается потолком", max_of(e, "ward") <= e.vaccine["cap"] + 1e-9)

	# 5. Сохранение и загрузка
	var s := TDGame.new(99)
	s.gold = 1000
	fake_wave(s)
	s.buy_vaccine("ember")
	var snap := TDSave.snapshot(s)
	check("сохранение с вакциной валидно", TDSave.valid(snap))
	var r := TDSave.restore(snap)
	check("вакцина восстановлена", r != null and r.vaccine == s.vaccine and r.vaccine_cd == s.vaccine_cd and r.vaccine_uses == s.vaccine_uses)
	fake_wave(s)
	fake_wave(r)
	check("продолжение после загрузки совпадает", JSON.stringify(s.upcoming) == JSON.stringify(r.upcoming) and s.rng.a == r.rng.a and s.vaccine == r.vaccine)
	var old := TDSave.snapshot(TDGame.new(5))
	for key in ["vaccine", "vaccine_cd", "vaccine_uses"]:
		old["state"].erase(key)
	var ro := TDSave.restore(old)
	check("старое сохранение без вакцины грузится", ro != null and ro.vaccine.is_empty() and ro.vaccine_cd == 0)
	var bad := TDSave.snapshot(s)
	bad["state"]["vaccine"] = {"gene": "nope", "left": 1, "cap": 0.1}
	check("испорченная вакцина отклоняется", not TDSave.valid(bad))
	var bad2 := TDSave.snapshot(s)
	bad2["state"]["vaccine"] = {"gene": "tough", "left": 99, "cap": 0.1}
	check("слишком долгая вакцина отклоняется", not TDSave.valid(bad2))

	print("Vaccine checks: %d failures" % failures)
	quit(1 if failures > 0 else 0)
