extends SceneTree
## PRO-152: эксперимент «сигнатура обороны + инкубация контрмер» (TDStrains).
## Метрика (инварианты из docs/balance/04 §4.4.1), динамика инкубации и анонса, бюджет пакетов, эффекты в бою,
## отсутствие следов без флага, детерминизм и сохранение посреди волны с врагами пакетов.

var failures := 0


func check(label: String, condition: bool) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		failures += 1


func _initialize() -> void:
	TDSave.directory = "res://tests/.tmp_saves_strains"
	_metric()
	_incubation()
	_packages_in_combat()
	_off_has_no_traces()
	_observe_matches_off()
	_determinism_and_saves()
	_answers()
	_vaccine_and_lure()
	_playtest_log()
	_shell_matrix()
	_execute_vs_shell()
	_warning_lead()
	_cleanup()
	print("strains_check: %s" % ("OK" if failures == 0 else "%d FAIL" % failures))
	quit(1 if failures > 0 else 0)


static func _meta(model: String = TDStrains.MODEL) -> Dictionary:
	return {"difficulty": "normal", "mode": "standard", "swarm_model": model}


# ── Метрика ───────────────────────────────────────────────────────

func _metric() -> void:
	var acc := TDStrains.new_acc()
	var snipe: Dictionary = TDConfig.tower_def("sniper", 1, "")
	var arrow: Dictionary = TDConfig.tower_def("arrow", 1, "")
	var blizzard: Dictionary = TDConfig.tower_def("frost", 3, "a")
	var tesla: Dictionary = TDConfig.tower_def("tesla", 1, "")
	TDStrains.record_hit(acc, snipe, "sniper", Vector2.ZERO, Vector2(5, 0), false, 55.0, false)
	TDStrains.record_hit(acc, arrow, "arrow", Vector2.ZERO, Vector2(2, 0), true, 4.0, true)
	TDStrains.record_hit(acc, tesla, "tesla", Vector2.ZERO, Vector2(3, 0), false, 14.0, false)
	var before: float = acc["total"]
	TDStrains.record_hit(acc, blizzard, "frost", Vector2.ZERO, Vector2(1, 0), false, 7.0, false)
	check("«Вьюга»: один удар — одна запись в каждом распределении", is_equal_approx(acc["total"] - before, 7.0)
		and is_equal_approx(acc["del"]["area"], 7.0) and is_equal_approx(acc["el"]["frost"], 7.0))
	TDStrains.record_dot(acc, Vector2.ZERO, Vector2(2, 0), false, 3.0, false)
	check("классы: снайпер burst, стрела rapid, Тесла chain, яд dot", acc["del"]["burst"] == 55.0 and acc["del"]["rapid"] == 4.0
		and acc["del"]["chain"] == 14.0 and acc["del"]["dot"] == 3.0)
	TDStrains.record_hit(acc, arrow, "arrow", Vector2.ZERO, Vector2(1, 0), false, 0.0, false)
	check("удар без урона (скорлупа, иммунитет) не попадает в сигнатуру", is_equal_approx(acc["total"], 83.0))
	var s := TDStrains.sample(acc)
	var sums_ok := true
	for dist in [["del", TDStrains.DEL], ["el", TDStrains.EL], ["rng", TDStrains.RANGE_CLS], ["tgt", TDStrains.TGT]]:
		var t := 0.0
		for k in dist[1]:
			t += float(s[dist[0]].get(k, 0.0))
		sums_ok = sums_ok and absf(t - 1.0) < 1e-6
	check("каждое распределение нормировано (сумма = 1)", sums_ok)
	check("доля по замороженным = 4 / 83", is_equal_approx(s["chill"], 4.0 / 83.0))
	check("пустая волна: среза нет", TDStrains.sample(TDStrains.new_acc()).is_empty())
	check("H* пустого распределения = 0, моно = 1, поровну = 0",
		TDStrains.hhi({}, TDStrains.DEL) == 0.0 and is_equal_approx(TDStrains.hhi({"burst": 1.0}, TDStrains.DEL), 1.0)
		and is_zero_approx(TDStrains.hhi({"burst": 0.2, "rapid": 0.2, "area": 0.2, "chain": 0.2, "dot": 0.2}, TDStrains.DEL)))
	# инвариантность к переименованию классов: перестановка долей не меняет C
	var a := {"del": {"burst": 0.6, "rapid": 0.3, "area": 0.1, "chain": 0.0, "dot": 0.0}, "el": {"physical": 0.9, "frost": 0.1}, "rng": {"far": 0.7, "mid": 0.3}}
	var b := {"del": {"burst": 0.0, "rapid": 0.1, "area": 0.6, "chain": 0.3, "dot": 0.0}, "el": {"shock": 0.9, "fire": 0.1}, "rng": {"near": 0.7, "far": 0.3}}
	check("C инвариантна к перестановке классов", is_equal_approx(TDStrains.concentration(a), TDStrains.concentration(b)))
	# монотонность: перенос 10% из доминирующего класса строго снижает H*
	var m := {"burst": 0.6, "rapid": 0.3, "area": 0.1, "chain": 0.0, "dot": 0.0}
	var m2 := {"burst": 0.5, "rapid": 0.3, "area": 0.1, "chain": 0.1, "dot": 0.0}
	check("перенос 10% из доминирующего класса снижает H*", TDStrains.hhi(m2, TDStrains.DEL) < TDStrains.hhi(m, TDStrains.DEL))
	# EMA: без урона распределения не меняются, покрытие воздуха — меняется
	var sig := TDStrains.blend({}, s, 0.2)
	var held := TDStrains.blend(sig, {}, 1.0)
	check("волна без урона по обычным врагам не меняет распределения", held["del"] == sig["del"] and held["chill"] == sig["chill"])
	check("покрытие неба обновляется и без урона", held["air_gap"] > sig["air_gap"])
	var mixed := TDStrains.blend(sig, {"del": {"area": 1.0}, "el": {"physical": 1.0}, "rng": {"near": 1.0}, "tgt": {"ground": 1.0}, "burst": 0.0, "chill": 0.0, "control": 0.0}, 0.2)
	var t2 := 0.0
	for k in TDStrains.DEL:
		t2 += float(mixed["del"][k])
	check("EMA сохраняет нормировку", absf(t2 - 1.0) < 1e-6)


# ── Инкубация, анонс, инерция ────────────────────────────────────

## Оборона, закрывающая небо (чтобы «Стая» не вмешивалась), и синтетические удары нужного класса.
func _covered_game(model: String = TDStrains.MODEL) -> TDGame:
	var g := TDGame.new(4243, null, _meta(model))
	g.gold = 100000
	for x in TDConfig.COLS:
		for y in TDConfig.ROWS:
			g.place_tower("arrow", x, y)
	return g


func _feed(g: TDGame, cls: String, n: int = 20) -> void:
	g.strain_acc = TDStrains.new_acc()
	var def: Dictionary = TDConfig.tower_def("sniper" if cls == "burst" else "arrow", 1, "")
	for i in n:
		TDStrains.record_hit(g.strain_acc, def, "sniper" if cls == "burst" else "arrow", Vector2.ZERO, Vector2(3, 0), false, 10.0, false)


func _incubation() -> void:
	var g := _covered_game()
	check("небо закрыто стрелками", TDStrains.air_gap(g) < 0.05)
	var announced_at := -1
	var active_at := -1
	var max_share := 0.0
	var max_total := 0.0
	var early := false
	for w in range(1, 16):
		g.upcoming = []
		for i in TDConfig.wave_size(w + 1):
			g.upcoming.append(TDGenome.random_genome(g.rng, w + 1))
		_feed(g, "burst")
		TDStrains.end_wave(g, w)
		var k: Dictionary = g.strains["pk"]["brood"]
		if k["phase"] == "announced" and announced_at < 0:
			announced_at = w
		if k["phase"] == "active" and active_at < 0:
			active_at = w + 1
			var tagged := 0
			for ge in g.upcoming:
				tagged += 1 if ge.get("strain", "") == "brood" else 0
			check("первая волна выводка: %d из %d (≈ %d%%)" % [tagged, g.upcoming.size(), roundi(TDStrains.SHARE_START * 100)], tagged == int(round(TDStrains.SHARE_START * g.upcoming.size())))
		if w < TDStrains.WARMUP_WAVE and float(k["inc"]) > 0.0:
			early = true
		max_share = maxf(max_share, float(k["share"]))
		var tot := 0.0
		for p in TDStrains.PACKAGES:
			tot += float(g.strains["pk"][p]["share"])
		max_total = maxf(max_total, tot)
	check("до разминки инкубация не идёт", not early)
	check("анонс был (волна %d)" % announced_at, announced_at > 0)
	check("появление через LEAD волн после анонса (%d → %d)" % [announced_at, active_at], active_at == announced_at + TDStrains.LEAD)
	check("не раньше MIN_WAVE", active_at >= TDStrains.MIN_WAVE)
	check("доля пакета не выше потолка normal", max_share <= TDStrains.SHARE_CAP["normal"] + 1e-6)
	check("сумма долей не выше TOTAL_CAP", max_total <= TDStrains.TOTAL_CAP + 1e-6)
	check("«Панцирники» молчат без лёгких одиночных ударов", g.strains["pk"]["hulk"]["phase"] == "quiet")
	# игрок перестроился: триггер ниже порога → инкубация тает, доля уходит шагами, не мгновенно
	var phases: Array = []
	var shares: Array = []
	for w in range(16, 30):
		_feed(g, "rapid")
		TDStrains.end_wave(g, w)
		phases.append(g.strains["pk"]["brood"]["phase"])
		shares.append(snappedf(float(g.strains["pk"]["brood"]["share"]), 0.01))
	print("     после перестройки: ", shares)
	check("окно выгоды: доля держится хотя бы 2 волны после смены", phases.slice(0, 2).all(func(p): return p == "active"))
	check("потом пакет отступает и исчезает", phases.has("fading") and phases[phases.size() - 1] == "quiet")
	var monotone := true
	for i in range(1, shares.size()):
		monotone = monotone and shares[i] <= shares[i - 1] + 1e-6 and shares[i - 1] - shares[i] <= TDStrains.SHARE_STEP + 1e-6
	check("отступление не быстрее SHARE_STEP за волну", monotone)
	# «Стая» — только при открытом небе, и не раньше, чем открывается полёт
	var bare := TDGame.new(4243, null, _meta())
	check("без башен небо открыто", TDStrains.air_gap(bare) == 1.0)
	var fl_active := -1
	for w in range(1, 12):
		bare.upcoming = []
		for i in TDConfig.wave_size(w + 1):
			bare.upcoming.append(TDGenome.random_genome(bare.rng, w + 1))
		bare.strain_acc = TDStrains.new_acc()
		TDStrains.end_wave(bare, w)
		if bare.strains["pk"]["flock"]["phase"] == "active" and fl_active < 0:
			fl_active = w + 1
			var fly := 0
			for ge in bare.upcoming:
				if ge.get("strain", "") == "flock":
					fly += 1
			check("«Стая» размечает врагов волны", fly > 0)
	check("«Стая» появляется не раньше открытия полёта (волна %d)" % fl_active, fl_active >= int(TDGenome.UNLOCK_WAVE["wings"]))


# ── Пакеты в бою ─────────────────────────────────────────────────

func _spawned(g: TDGame) -> Array:
	g.start_wave()
	for i in 4000:
		g.step(1.0 / 30.0)
		if g.pending.is_empty():
			break
	return g.enemies


func _packages_in_combat() -> void:
	var g := TDGame.new(99, null, _meta())
	g.wave = 8
	g.upcoming = []
	for i in 6:
		var ge := TDGenome.random_genome(g.rng, 8)
		ge["wings"] = 0.0
		ge["strain"] = ["brood", "hulk", "flock", "", "", ""][i]
		g.upcoming.append(TDGenome.fit_to_budget(ge, 8).merged({"strain": ge["strain"]}, true))
	var es := _spawned(g)
	var by := {}
	for e in es:
		by[e.strain] = by.get(e.strain, []) + [e]
	var base_hp: float = TDGenome.phenotype(g.wave_genomes[0], 8)["hp"]
	check("выводок: кладка из %d" % TDStrains.BROOD_N, by.get("brood", []).size() == TDStrains.BROOD_N)
	var hp_sum := 0.0
	var shells := true
	var carriers := 0
	for e in by.get("brood", []):
		hp_sum += e.ph["hp"]
		shells = shells and e.shell == 1
		carriers += 0 if e.child else 1
	check("выводок: суммарное здоровье кладки = %.0f%% одного врага" % (TDStrains.BROOD_N * TDStrains.BROOD_HP * 100), is_equal_approx(hp_sum, base_hp * TDStrains.BROOD_N * TDStrains.BROOD_HP))
	check("выводок: у каждого панцирь, носитель один (отбор не раздувается)", shells and carriers == 1)
	var hulk: TDGame.Enemy = by["hulk"][0]
	check("панцирник: панцирь, здоровье ×%.2f" % TDStrains.HULK_HP, hulk.shell == 1 and is_equal_approx(hulk.ph["hp"], TDGenome.phenotype(g.wave_genomes[1], 8)["hp"] * TDStrains.HULK_HP))
	var flyer: TDGame.Enemy = by["flock"][0]
	check("стая: летит, геном не изменён (полёт не наследуется)", flyer.ph["fly"] and float(flyer.genome["wings"]) == 0.0)
	# скорлупа гасит первый удар целиком, второй проходит
	g.gold = 100000
	var spot := Vector2i(-1, -1)
	for x in TDConfig.COLS:
		for y in TDConfig.ROWS:
			if spot.x < 0 and g.can_place("sniper", x, y):
				spot = Vector2i(x, y)
	g.place_tower("sniper", spot.x, spot.y)
	var sn := g.tower_at(spot.x, spot.y)
	var arrow_spot := Vector2i(-1, -1)
	var frost_spot := Vector2i(-1, -1)
	for x in TDConfig.COLS:
		for y in TDConfig.ROWS:
			if arrow_spot.x < 0 and g.can_place("arrow", x, y):
				arrow_spot = Vector2i(x, y)
			elif frost_spot.x < 0 and arrow_spot.x >= 0 and g.can_place("frost", x, y):
				frost_spot = Vector2i(x, y)
	g.place_tower("arrow", arrow_spot.x, arrow_spot.y)
	g.place_tower("frost", frost_spot.x, frost_spot.y)
	var ar := g.tower_at(arrow_spot.x, arrow_spot.y)
	var fr := g.tower_at(frost_spot.x, frost_spot.y)
	var mite: TDGame.Enemy = by["brood"][1]
	var hp0 := mite.hp
	g._hit(mite, sn, g.mods())
	g._hit(mite, sn, g.mods())
	check("выводок: тяжёлые выстрелы не ранят (и второй тоже — панцирь не разбивается)", mite.hp == hp0 and mite.shell == 1)
	g._hit(mite, ar, g.mods())
	check("выводок: лёгкий удар проходит", mite.hp < hp0)
	var h0 := hulk.hp
	g._hit(hulk, ar, g.mods())
	check("панцирник: стрела не ранит", hulk.hp == h0)
	g._hit(hulk, fr, g.mods())
	check("панцирник: лёд по площади ранит и замедляет", hulk.hp < h0 and hulk.slow_t > 0.0)
	var h1 := hulk.hp
	g._hit(hulk, sn, g.mods())
	check("панцирник: тяжёлый выстрел проходит", hulk.hp < h1)
	# золото за кладку = награда за одного врага
	var gold0 := g.gold
	for e in by["brood"]:
		e.hp = 0.0
	g.step(0.0001)
	var bounty: int = TDConfig.KILL_REWARD + g.perk_level("bounty")
	check("кладка приносит столько же золота, сколько один враг (%d)" % (g.gold - gold0), g.gold - gold0 == bounty)


# ── Без флага: ни следа ──────────────────────────────────────────

func _auto_game(seed_v: int, model: String) -> TDGame:
	var meta := {"difficulty": "normal", "mode": "standard"}
	if model != "":
		meta["swarm_model"] = model
	var g := TDGame.new(seed_v, null, meta)
	return g


## Простая детерминированная оборона: лучники, лёд, снайпер у дороги.
func _defend(g: TDGame) -> void:
	for kind in ["arrow", "frost", "sniper", "arrow", "ember"]:
		var placed := false
		for c in g.map.order:
			if placed:
				break
			for d in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
				var p: Vector2i = c + d
				if g.can_place(kind, p.x, p.y):
					g.place_tower(kind, p.x, p.y)
					placed = true
					break


func _play(g: TDGame, waves: int) -> void:
	while g.wave <= waves and g.phase != "over":
		if g.phase == "build":
			if not g.offer.is_empty():
				g.choose_perk(g.offer[0])
			_defend(g)
			g.start_wave()
		g.step(1.0 / 30.0)


func _off_has_no_traces() -> void:
	var g := _auto_game(4243, "")
	_play(g, 8)
	var tagged := false
	for ge in g.upcoming + g.wave_genomes:
		tagged = tagged or ge.has("strain")
	check("без флага: состояние эксперимента пустое", g.strains.is_empty() and g.strain_acc.is_empty() and not g.strains_on())
	check("без флага: в геномах нет пакетов", not tagged)
	check("без флага: в отчётах нет записей эксперимента", g.reports.all(func(r): return not r.has("strains")))
	var snap := TDSave.snapshot(g)
	check("без флага: сохранение без новых полей", not snap["state"].has("strains") and not snap["state"].has("strain_acc"))
	var bad := snap.duplicate(true)
	bad["state"]["strains"] = TDStrains.new_state()
	check("без флага: состояние эксперимента в сохранении отклоняется", not TDSave.valid(bad))


func _observe_matches_off() -> void:
	var off := _auto_game(8486, "")
	var obs := _auto_game(8486, TDStrains.OBSERVE)
	_play(off, 12)
	_play(obs, 12)
	var same := off.lives == obs.lives and off.gold == obs.gold and off.rng.a == obs.rng.a and off.wave == obs.wave
	for i in mini(off.reports.size(), obs.reports.size()):
		same = same and off.reports[i]["damageBy"] == obs.reports[i]["damageBy"] and off.reports[i]["avg"] == obs.reports[i]["avg"]
	check("observe: бой и rng совпадают с выключенным флагом (контрольное плечо A/B)", same and off.reports.size() == obs.reports.size())
	check("observe: сигнатура собрана", obs.strains.get("n", 0) > 0)


# ── Детерминизм и сохранения ──────────────────────────────────────

func _clean(g: TDGame) -> Dictionary:
	var d := TDSave.snapshot(g)
	d.erase("timestamp")
	d.erase("saved_at")
	return d


func _determinism_and_saves() -> void:
	var a := _auto_game(12729, TDStrains.MODEL)
	var b := _auto_game(12729, TDStrains.MODEL)
	_play(a, 10)
	_play(b, 10)
	check("с флагом: две партии с одним сидом совпадают", _clean(a) == _clean(b))
	# насильно включить выводок и стаю, чтобы проверить сохранение посреди волны с их врагами
	var g := _auto_game(16972, TDStrains.MODEL)
	g.lives = 999
	_play(g, 7)
	if g.phase != "build":
		check("сохранение: партия дошла до фазы строительства", false)
		return
	g.strains["pk"]["brood"]["phase"] = "active"
	g.strains["pk"]["brood"]["share"] = 0.3
	g.strains["pk"]["hulk"]["phase"] = "active"
	g.strains["pk"]["hulk"]["share"] = 0.15
	g.upcoming = TDStrains.assign(g.upcoming, g.strains, g.wave)
	if not g.offer.is_empty():
		g.choose_perk(g.offer[0])
	g.start_wave()
	var has_brood := false
	for i in 900:
		g.step(1.0 / 30.0)
		for e in g.enemies:
			has_brood = has_brood or (e.strain == "brood" and e.child)
		if has_brood and g.strain_acc["total"] > 0.0:
			break
	check("посреди волны есть малыши выводка и накопленная сигнатура", has_brood and g.phase == "wave")
	check("сохранение с флагом пишет состояние эксперимента", TDSave.write(0, g, {}) == OK)
	var r := TDSave.restore(TDSave.read(0))
	check("сохранение с флагом загружается", r != null)
	if r == null:
		return
	check("все поля, включая пакеты врагов и накопитель, совпадают", _clean(g) == _clean(r))
	for i in 900:
		g.step(1.0 / 30.0)
		r.step(1.0 / 30.0)
	_play(g, 12)
	_play(r, 12)
	check("продолжение после загрузки совпадает до 12-й волны", _clean(g) == _clean(r))
	var snap := TDSave.snapshot(g)
	var wrong := snap.duplicate(true)
	wrong["state"]["meta"].erase("swarm_model")
	if wrong["enemies"].size() > 0 or wrong["state"]["upcoming"].any(func(ge): return ge.has("strain")):
		check("враги/геномы пакетов без флага в сохранении отклоняются", not TDSave.valid(wrong))
	var bad_phase := snap.duplicate(true)
	bad_phase["state"]["strains"]["pk"]["brood"]["phase"] = "boom"
	check("неизвестная фаза пакета отклоняется", not TDSave.valid(bad_phase))


# ── Ответы ───────────────────────────────────────────────────────

func _answers() -> void:
	# без Мастерской и достижений закрыты Тесла и Сеть
	var g := TDGame.new(1, null, {"swarm_model": TDStrains.MODEL, "locked": ["tesla", "net"]})
	for p in TDStrains.PACKAGES:
		var a := TDStrains.answers(g, p)
		check("«%s»: ≥ 2 ответа без прогрессии (%s)" % [TDStrains.PACK[p]["name"], ", ".join(a)], a.size() >= 2)
	for p in TDStrains.PACKAGES:
		var fine := true
		for k in TDStrains.PACK[p]["answers"]:
			fine = fine and TDConfig.TOWERS.has(k)
		check("«%s»: ответы — существующие башни" % TDStrains.PACK[p]["name"], fine)


## Вакцина и приманка работают поверх разметки пакетов: метки не теряются, приманка доходит до малышей, rng не сдвигается.
func _vaccine_and_lure() -> void:
	var g := _auto_game(21215, TDStrains.MODEL)
	g.lives = 999
	_play(g, 6)
	if g.phase != "build":
		check("вакцина/приманка: партия дошла до фазы строительства", false)
		return
	if not g.offer.is_empty():
		g.choose_perk(g.offer[0])
	var st := TDStrains.new_state()
	st["pk"]["brood"]["phase"] = "active"
	st["pk"]["brood"]["share"] = 0.3
	g.upcoming = TDStrains.assign(g.upcoming, st, g.wave)
	var tagged := func() -> int:
		var n := 0
		for ge in g.upcoming:
			n += 1 if ge.get("strain", "") == "brood" else 0
		return n
	var before: int = tagged.call()
	g.gold = 100000
	g.vaccine_cd = 0
	var gene := ""
	for k in ["tough", "swift", "plated"]:
		if gene == "" and g.vaccine_problem(k) == "":
			gene = k
	var rng0 := g.rng.a
	check("вакцина покупается при включённом эксперименте", gene != "" and g.buy_vaccine(gene))
	check("вакцина не стирает разметку пакетов и не трогает rng", tagged.call() == before and before > 0 and g.rng.a == rng0)
	var lg := ""
	for k in TDConfig.LURE_GENES:
		if lg == "" and g.lure_problem(k) == "":
			lg = k
	if lg != "":
		g.buy_lure(lg)
		g.start_wave()
		var lured_mites := 0
		for i in 600:
			g.step(1.0 / 30.0)
			for e in g.enemies:
				if e.strain == "brood" and e.child and e.lured_gene == lg:
					lured_mites += 1
		check("приманка доходит до малышей выводка", lured_mites > 0)
	else:
		check("приманка недоступна на этой волне — пропуск", true)


## Журнал плейтеста: строка на старт и конец волны, с сидом, постройками и прогнозом роя.
func _playtest_log() -> void:
	TDPlaytestLog.directory = TDSave.directory
	var g := _auto_game(4243, TDStrains.MODEL)
	var plog := TDPlaytestLog.new("check-run")
	_defend(g)
	g.start_wave()
	plog.wave_started(g)
	while g.phase == "wave":
		g.step(1.0 / 30.0)
	plog.wave_ended(g)
	var lines := FileAccess.get_file_as_string(plog.path).strip_edges().split("\n")
	var first = JSON.parse_string(lines[0]) if lines.size() > 0 else null
	var last = JSON.parse_string(lines[lines.size() - 1]) if lines.size() > 0 else null
	check("журнал плейтеста: старт и конец волны", lines.size() == 2 and first is Dictionary and last is Dictionary
		and first["event"] == "start" and int(first["seed"]) == 4243 and first["built"].size() > 0 and last["event"] == "end" and last.has("forecast"))


# ── PRO-184: панцири обещают то же, что делают ───────────────────

## Что обещает подсказка, записано независимо от реализации: тяжёлые одиночные выстрелы — снайпер (все уровни и ветки),
## «Гарпун» (сеть 3Б), «Стужа» (лёд 3Б); лёгкие одиночные — лучники (все), одиночный огонь, укус яда. Площадь и цепь — ни то ни другое.
const PROMISE_HEAVY := ["sniper:1:", "sniper:2:", "sniper:3:a", "sniper:3:b", "net:3:b", "frost:3:b"]
const PROMISE_LIGHT := ["arrow:1:", "arrow:2:", "arrow:3:a", "arrow:3:b", "ember:1:", "ember:2:", "ember:3:b", "poison:1:", "poison:2:", "poison:3:a", "poison:3:b"]


static func _variants() -> Array:
	var out: Array = []
	for k in TDConfig.TOWER_KINDS:
		if TDConfig.TOWERS[k].has("aura"):
			continue
		for v in [[1, ""], [2, ""], [3, "a"], [3, "b"]]:
			out.append([k, v[0], v[1]])
	return out


## Матрица: башня × уровень/ветка × перки × волна (HP врага, ген «здоровья» 0/1) × сложность × пакет.
## Для каждой комбинации — класс удара, прошёл ли урон и совпадает ли это с обещанием подсказки.
func _shell_matrix() -> void:
	var rows: Array = ["kind,level,branch,perks,wave,tough,difficulty,strain,max_hp,class,deflected,promise,ok"]
	var bad: Array = []
	var classes := {}
	for v in _variants():
		var key := "%s:%d:%s" % v
		var promise := "heavy" if PROMISE_HEAVY.has(key) else ("light" if PROMISE_LIGHT.has(key) else "other")
		for perks in ["none", "max"]:
			for diff in ["normal", "hard"]:
				var g := TDGame.new(4243, null, {"difficulty": diff, "swarm_model": TDStrains.MODEL})
				if perks == "max":
					g.perks = {"rapid": 2, "variety": 1, "pierce": 3, "shatter": 3, "scorch": 2, "range": 2}
					g.gold = 100000
					var placed := 0
					for x in TDConfig.COLS:
						for y in TDConfig.ROWS:
							if placed < TDConfig.TOWER_KINDS.size() and g.can_place(TDConfig.TOWER_KINDS[placed], x, y):
								g.place_tower(TDConfig.TOWER_KINDS[placed], x, y)
								placed += 1
				var t := TDGame.Tower.new()
				t.kind = v[0]
				t.level = v[1]
				t.branch = v[2]
				t.def = TDConfig.tower_def(v[0], v[1], v[2])
				t.x = 0
				t.y = 0
				for wave in [6, 10, 15, 20, 30, 40]:
					for tough in [0.0, 1.0]:
						for strain in ["", "brood", "hulk"]:
							var ge := {}
							for gk in TDGenome.GENES:
								ge[gk] = 0.0
							ge["tough"] = tough
							var e := TDGame.Enemy.new()
							e.ph = TDStrains.apply_ph(TDGenome.phenotype(ge, wave), strain)
							e.ph["hp"] = e.ph["hp"] * float(TDConfig.difficulty(g.meta)["hp"])
							e.hp = e.ph["hp"]
							e.genome = ge
							e.strain = strain
							e.shell = 1 if TDStrains.DEFLECT.has(strain) else 0
							var hp0 := e.hp
							g._hit(e, t, g.mods())
							var deflected := e.hp >= hp0
							var expected: bool = (strain == "brood" and promise == "heavy") or (strain == "hulk" and promise == "light")
							var cls := TDStrains.del_class(t.def)
							classes[key] = classes.get(key, {})
							classes[key][cls] = true
							var ok: bool = deflected == expected
							if not ok:
								bad.append("%s %s w%d tough%d %s %s: class=%s deflected=%s promise=%s" % [key, perks, wave, int(tough), diff, strain, cls, deflected, promise])
							rows.append("%s,%d,%s,%s,%d,%d,%s,%s,%d,%s,%s,%s,%s" % [v[0], v[1], v[2], perks, wave, int(tough), diff, strain if strain != "" else "base", int(e.ph["hp"]), cls, deflected, promise, ok])
	var unstable: Array = []
	for key in classes:
		if classes[key].size() > 1:
			unstable.append(key)
	check("класс удара не зависит от HP, волны, сложности и перков (%d вариантов башен)" % classes.size(), unstable.is_empty())
	if not unstable.is_empty():
		print("     нестабильны: ", unstable)
	check("панцири делают то, что обещает подсказка: %d расхождений из %d комбинаций" % [bad.size(), rows.size() - 1], bad.is_empty())
	for b in bad.slice(0, 6):
		print("     ", b)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--matrix="):
			var f := FileAccess.open(a.substr(9), FileAccess.WRITE)
			f.store_string("\n".join(rows) + "\n")
			f.close()


## «Палач» не добивает сквозь панцирь, который погасил удар; обычное добивание и эффекты сквозь панцирь — как раньше.
func _execute_vs_shell() -> void:
	for model in ["", TDStrains.MODEL]:
		var meta := {"difficulty": "normal"}
		if model != "":
			meta["swarm_model"] = model
		var g := TDGame.new(4243, null, meta)
		var t := TDGame.Tower.new()
		t.kind = "sniper"
		t.level = 3
		t.branch = "a"
		t.def = TDConfig.tower_def("sniper", 3, "a")
		var ge := {}
		for gk in TDGenome.GENES:
			ge[gk] = 0.0
		ge["tough"] = 1.0
		var mk := func(strain: String) -> TDGame.Enemy:
			var e := TDGame.Enemy.new()
			e.ph = TDStrains.apply_ph(TDGenome.phenotype(ge, 30), strain)
			e.genome = ge
			e.strain = strain
			e.shell = 1 if TDStrains.DEFLECT.has(strain) else 0
			# здоровье чуть ниже порога «Палача», но выше урона одного выстрела: убить может только добивание
			e.hp = e.ph["hp"] * (float(t.def["execute"]) - 0.01)
			return e
		var plain: TDGame.Enemy = mk.call("")
		var dmg_one: float = g.t_damage(t)
		g._hit(plain, t, g.mods())
		check("%s: обычный враг ниже порога добивается «Палачом»" % ("флаг" if model != "" else "без флага"), plain.hp == 0.0 and plain.ph["hp"] * 0.24 > dmg_one)
		if model == "":
			continue
		var mite: TDGame.Enemy = mk.call("brood")
		var hp0 := mite.hp
		g._hit(mite, t, g.mods())
		check("выводок: «Палач» не добивает сквозь панцирь (hp %.0f → %.0f)" % [hp0, mite.hp], mite.hp == hp0)
		var hulk: TDGame.Enemy = mk.call("hulk")
		g._hit(hulk, t, g.mods())
		check("панцирники: тяжёлый выстрел проходит, «Палач» добивает как обычно", hulk.hp == 0.0)
	# эффекты удара сквозь панцирь: укус яда по панцирнику не ранит, но яд ложится и тикает
	var g2 := TDGame.new(4243, null, {"difficulty": "normal", "swarm_model": TDStrains.MODEL})
	var pt := TDGame.Tower.new()
	pt.kind = "poison"
	pt.level = 1
	pt.def = TDConfig.tower_def("poison", 1, "")
	var ge2 := {}
	for gk in TDGenome.GENES:
		ge2[gk] = 0.0
	var hk := TDGame.Enemy.new()
	hk.ph = TDStrains.apply_ph(TDGenome.phenotype(ge2, 12), "hulk")
	hk.genome = ge2
	hk.hp = hk.ph["hp"]
	hk.strain = "hulk"
	hk.shell = 1
	var h0 := hk.hp
	g2._hit(hk, pt, g2.mods())
	check("панцирник: укус яда не ранит, но яд ложится", hk.hp == h0 and hk.poison_t > 0.0)
	g2.enemies.append(hk)
	g2.phase = "wave"
	g2.pending_boss = {}
	for i in 30:
		g2.step(1.0 / 30.0)
	check("панцирник: яд тикает сквозь панцирь", hk.hp < h0)


## PRO-115: игрок видит пакет за 2 фазы строительства до появления — в окне отчёта, совете и плашке «Следом»,
## а в волне появления — в составе «Следом» с числом врагов; текст называет башни-ответы, которые реально пробивают панцирь.
func _warning_lead() -> void:
	var g := _covered_game()
	var blank := {}
	for k in TDGenome.GENES:
		blank[k] = 0.0
	var seen_announce := -1
	var seen_in_wave := -1
	var ok_report := false
	var ok_advice := false
	var ok_chip := false
	var answers_ok := true
	for w in range(1, 14):
		g.wave = w + 1
		g.upcoming = []
		for i in TDConfig.wave_size(w + 1):
			g.upcoming.append(TDGenome.random_genome(g.rng, w + 1))
		_feed(g, "burst")
		g.reports.append({"wave": w, "killed": 0, "size": 0, "leaked": 0, "avg": blank, "nextAvg": blank, "prevAvg": blank, "pressure": {}, "damageBy": TDGame._zero_damage()})
		TDStrains.end_wave(g, w)
		var k: Dictionary = g.strains["pk"]["brood"]
		if k["phase"] == "announced" and seen_announce < 0:
			seen_announce = w
			var snap := TDWaveReport.snapshot(g)
			for e in snap["strains"]:
				if e["id"] == "brood" and e["phase"] == "announced" and TDStrains.line(e).contains("в волне %d" % k["appear"]):
					ok_report = true
				for t in e["towers"]:
					answers_ok = answers_ok and not TDStrains.deflects("brood", TDStrains.del_class(TDConfig.tower_def(t, 1, "")))
			for tip in TDAdvisor.advice(g, TDAdvisor.wave_info(g)):
				ok_advice = ok_advice or String(tip["title"]).contains("Выводок")
		if k["phase"] == "active" and seen_in_wave < 0:
			seen_in_wave = w + 1
			for c in TDAdvisor.wave_chips(TDAdvisor.wave_info(g)):
				ok_chip = ok_chip or String(c["text"]).begins_with("Выводок")
	check("анонс в окне отчёта с номером волны появления", ok_report)
	check("анонс в советах", ok_advice)
	check("в волне появления — плашка «Следом» с выводком", ok_chip)
	check("между анонсом (после волны %d) и появлением (волна %d) — 2 фазы строительства" % [seen_announce, seen_in_wave], seen_in_wave - seen_announce == 2)
	check("башни-ответы в предупреждении пробивают панцирь выводка", answers_ok)


func _cleanup() -> void:
	var dir := DirAccess.open(TDSave.directory)
	if dir != null:
		for f in dir.get_files():
			dir.remove(f)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TDSave.directory))
