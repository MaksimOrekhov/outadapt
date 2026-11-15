extends SceneTree
## Проверка «Приманки» (PRO-118): godot --headless --path godot --script res://tests/lure_check.gd

var failures := 0


func check(label: String, condition: bool, detail: String = "") -> void:
	print(("OK    " if condition else "FAIL  ") + label + ("" if detail == "" else "  (" + detail + ")"))
	if not condition:
		failures += 1


## Конец волны без боя: все враги «убиты», отчёт и экономика идут обычным путём.
func fake_wave(g: TDGame) -> void:
	g.start_wave()
	g.finished = []
	for i in g.wave_genomes.size():
		g.finished.append({"genome": g.wave_genomes[i], "fitness": float(g.wave_genomes.size() - i)})
	g.pending = []
	g.pending_boss = {}
	g.enemies.clear()
	g.killed = g.wave_genomes.size()
	g._end_wave()


## Доводит игру до волны wave_n (без боссовых и особых волн мы не уходим: их проверяем отдельно).
func game_at(seed_v: int, wave_n: int) -> TDGame:
	var g := TDGame.new(seed_v)
	g.gold = 1000
	while g.wave < wave_n:
		fake_wave(g)
	g.offer = []
	return g


## Дотягивает игру g до той же волны, что и у образца ref (без приманок): для сравнения спавна.
func plain_wave_to(g: TDGame, ref: TDGame) -> void:
	while g.wave < ref.wave:
		fake_wave(g)
		g.offer = []


func plain_wave(g: TDGame) -> void:
	# ближайшая волна без босса и особенностей: двигаем игру, пока такая не подвернётся
	while not g.upcoming_boss.is_empty() or g.upcoming_special != "" or g.lure_cd > 0 or not g.lure.is_empty() or g.wave < TDConfig.LURE_MIN_WAVE:
		fake_wave(g)
		g.offer = []


func _initialize() -> void:
	# 1. правила покупки
	var g := TDGame.new(4243)
	check("до волны %d приманка недоступна" % TDConfig.LURE_MIN_WAVE, g.lure_problem("tough") != "")
	g = game_at(4243, TDConfig.LURE_MIN_WAVE)
	plain_wave(g)
	check("базовый ген можно", g.lure_problem("tough") == "")
	check("редкий признак нельзя", g.lure_problem("wings") != "" and g.lure_problem("ward") != "")
	check("неизвестный ген нельзя", g.lure_problem("nope") != "")
	g.start_wave()
	check("во время волны нельзя", g.lure_problem("tough") != "")
	g.pending = []
	g.enemies.clear()
	g.phase = "build"

	# 2. эффект: геномы роя не меняются, фенотип врагов считается с усиленным геном
	var before: Array = g.upcoming.duplicate(true)
	var rng_before := g.rng.a
	var gold_before := g.gold
	var plain: TDGame = game_at(4243, g.wave)  # тот же сид и волна без приманки
	plain_wave_to(plain, g)
	check("покупка прошла", g.buy_lure("swift"))
	check("приманка бесплатна (цена — риск)", g.gold == gold_before)
	check("rng не сдвинут", g.rng.a == rng_before)
	check("геномы роя не изменены (не наследуется)", JSON.stringify(g.upcoming) == JSON.stringify(before))
	var ok_gene := true
	var ok_rest := true
	for i in before.size():
		var lg := g.lured_genome(g.upcoming[i])
		ok_gene = ok_gene and absf(lg["swift"] - minf(1.0, before[i]["swift"] + TDConfig.lure_boost("swift"))) < 1e-9
		for k in TDGenome.GENES:
			if k != "swift":
				ok_rest = ok_rest and lg[k] == before[i][k]
	check("ген выбранный +%.0f%%, не выше 1" % (TDConfig.lure_boost("swift") * 100), ok_gene)
	check("остальные гены не менялись", ok_rest)
	check("вторую приманку взять нельзя", g.lure_problem("tough") != "" and not g.buy_lure("tough"))
	# настоящий спавн: враги быстрее, чем без приманки
	g.start_wave()
	g.step(0.05)
	plain.start_wave()
	plain.step(0.05)
	check("первый враг спавнится", g.enemies.size() > 0 and plain.enemies.size() > 0)
	if g.enemies.size() > 0 and plain.enemies.size() > 0:
		check("враг волны с приманкой быстрее", g.enemies[0].ph["speed"] > plain.enemies[0].ph["speed"], "%.3f против %.3f" % [g.enemies[0].ph["speed"], plain.enemies[0].ph["speed"]])
		check("геном врага остался прежним (для отбора)", g.enemies[0].genome["swift"] == plain.enemies[0].genome["swift"])
	g.pending = []
	g.enemies.clear()
	g.phase = "build"
	g.finished = []
	for i in g.wave_genomes.size():
		g.finished.append({"genome": g.wave_genomes[i], "fitness": float(g.wave_genomes.size() - i)})
	g.killed = g.wave_genomes.size()

	# 3. награда и перезарядка
	var gold_pre := g.gold
	var wave_w := g.wave
	fake_wave(g)
	var r: Dictionary = g.reports[g.reports.size() - 1]
	check("в отчёте записана приманка", r.has("lure") and r["lure"]["gene"] == "swift" and r["lure"]["bonus"] > 0)
	var bounty := TDConfig.KILL_REWARD
	var expect := int(round(TDConfig.LURE_SHARE * (g.killed * bounty + TDConfig.wave_bonus(wave_w))))
	check("награда = %d%% дохода волны" % round(TDConfig.LURE_SHARE * 100), r["lure"]["bonus"] == expect, "%d против %d" % [r["lure"]["bonus"], expect])
	check("золото выросло на бонус волны + проценты + награду приманки", g.gold == gold_pre + r["bonus"] + r["interest"] + r["lure"]["bonus"], "%d против %d" % [g.gold, gold_pre + r["bonus"] + r["interest"] + r["lure"]["bonus"]])
	check("приманка снята, пауза включена", g.lure.is_empty() and g.lure_cd == TDConfig.LURE_COOLDOWN)
	g.offer = []
	check("в паузу взять приманку нельзя", g.lure_problem("tough") != "")
	fake_wave(g)
	g.offer = []
	check("после паузы снова можно (если волна обычная)", g.lure_cd == 0)

	# 4. не на боссовых и особых волнах
	var gb := game_at(11, 3)
	while gb.upcoming_boss.is_empty():
		fake_wave(gb)
		gb.offer = []
	check("на боссовой волне нельзя", gb.lure_problem("tough") != "")
	var gs := game_at(12, 3)
	while gs.upcoming_special == "":
		fake_wave(gs)
		gs.offer = []
	check("на особой волне нельзя", gs.lure_problem("tough") != "")

	# 5. взаимодействие с вакциной
	var gv := game_at(77, 12)
	plain_wave(gv)
	gv.gold = 5000
	check("вакцина на ген А куплена", gv.buy_vaccine("plated"))
	check("приманка на ген с вакциной запрещена", gv.lure_problem("plated") != "" and not gv.buy_lure("plated"))
	var plated_cap: float = gv.vaccine["cap"]
	check("приманка на другой ген при вакцине разрешена", gv.buy_lure("tough"))
	var cap_ok := true
	var boost_ok := true
	for i in gv.upcoming.size():
		var lg := gv.lured_genome(gv.upcoming[i])
		cap_ok = cap_ok and lg["plated"] <= plated_cap + 1e-9
		boost_ok = boost_ok and absf(lg["tough"] - minf(1.0, gv.upcoming[i]["tough"] + TDConfig.lure_boost("tough"))) < 1e-9
	check("потолок вакцины не нарушен приманкой", cap_ok)
	check("приманка работает при вакцине", boost_ok)
	# обратный порядок: сначала приманка, потом вакцина на тот же ген
	var gl := game_at(78, 12)
	plain_wave(gl)
	gl.gold = 5000
	check("приманка куплена", gl.buy_lure("ember"))
	check("вакцина на приманку запрещена (иначе бесплатное золото)", gl.vaccine_problem("ember") != "" and not gl.buy_vaccine("ember"))
	check("вакцина на другой ген не стирает приманку", gl.buy_vaccine("frost"))
	var lure_ok := true
	for i in gl.upcoming.size():
		lure_ok = lure_ok and gl.lured_genome(gl.upcoming[i])["ember"] > gl.upcoming[i]["ember"] - 1e-12 and (gl.upcoming[i]["ember"] >= 1.0 or gl.lured_genome(gl.upcoming[i])["ember"] > gl.upcoming[i]["ember"])
	check("ген приманки остался усиленным", lure_ok)
	# обе одновременно, затем волны: вакцина и перезарядки идут независимо, rng общий
	fake_wave(gv)
	gv.offer = []
	check("после волны: приманка снята, вакцина ещё действует", gv.lure.is_empty() and not gv.vaccine.is_empty())

	# 6. детерминированность
	var a := game_at(4243, 3)
	var b := game_at(4243, 3)
	for gg in [a, b]:
		plain_wave(gg)
		gg.gold = 5000
	check("до покупок игры совпадают", JSON.stringify(a.upcoming) == JSON.stringify(b.upcoming) and a.rng.a == b.rng.a)
	a.buy_lure("tough")
	for _i in 4:
		fake_wave(a)
		fake_wave(b)
		a.offer = []
		b.offer = []
	check("rng с приманкой и без идёт одинаково", a.rng.a == b.rng.a)
	var c := game_at(4243, 3)
	var d := game_at(4243, 3)
	for gg in [c, d]:
		plain_wave(gg)
		gg.gold = 5000
	for _i in 8:
		for gg in [c, d]:
			if gg.lure_problem("swift") == "":
				gg.buy_lure("swift")
			if gg.vaccine_problem("plated") == "":
				gg.buy_vaccine("plated")
			fake_wave(gg)
			gg.offer = []
	check("два одинаковых прогона с приманкой и вакциной совпадают", JSON.stringify(c.upcoming) == JSON.stringify(d.upcoming) and c.gold == d.gold and c.rng.a == d.rng.a and c.lure_uses == d.lure_uses)

	# 7. сохранение и загрузка
	var s := game_at(99, 3)
	plain_wave(s)
	s.buy_lure("frost")
	var snap := TDSave.snapshot(s)
	check("сохранение с приманкой валидно", TDSave.valid(snap))
	var rs := TDSave.restore(snap)
	check("приманка восстановлена", rs != null and rs.lure == s.lure and rs.lure_cd == s.lure_cd and rs.lure_uses == s.lure_uses)
	fake_wave(s)
	fake_wave(rs)
	check("награда и продолжение после загрузки совпадают", s.gold == rs.gold and JSON.stringify(s.upcoming) == JSON.stringify(rs.upcoming) and s.rng.a == rs.rng.a and s.lure_cd == rs.lure_cd)
	var snap_cd := TDSave.snapshot(s)
	check("сохранение с перезарядкой валидно", TDSave.valid(snap_cd) and TDSave.restore(snap_cd).lure_cd == s.lure_cd)
	var old := TDSave.snapshot(TDGame.new(5))
	for key in ["lure", "lure_cd", "lure_uses"]:
		old["state"].erase(key)
	var ro := TDSave.restore(old)
	check("старое сохранение без приманки грузится", ro != null and ro.lure.is_empty() and ro.lure_cd == 0)
	var bad := TDSave.snapshot(s)
	bad["state"]["lure"] = {"gene": "wings", "boost": 0.2, "wave": 3}
	check("приманка на редкий признак в сохранении отклоняется", not TDSave.valid(bad))
	var bad2 := TDSave.snapshot(s)
	bad2["state"]["lure"] = {"gene": "tough", "boost": 5.0, "wave": 3}
	check("чрезмерный множитель в сохранении отклоняется", not TDSave.valid(bad2))

	# 8. объяснение адаптации не искажено: средние по геномам до и после приманки не содержат прибавки
	var e := game_at(31, 3)
	plain_wave(e)
	e.buy_lure("tough")
	fake_wave(e)
	for x in TDAdvisor.adaptation(e):
		check("после приманки нет сдвига, придуманного приманкой (%s)" % x["gene"], x["verdict"] != "lure_end")
	check("в отчёте о волне приманка записана", e.reports[e.reports.size() - 1].has("lure"))

	print("Lure checks: %d failures" % failures)
	quit(1 if failures > 0 else 0)
