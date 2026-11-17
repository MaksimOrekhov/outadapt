extends SceneTree
## PRO-191: интерфейс эволюции — «что угрожает → когда → почему → что построить».
## godot --headless --path godot --script res://tests/evo_ui_check.gd
## Состояния — настоящие концы волн из TDEvoFixtures (см. scripts/sim/evo_fixtures.gd).

var failures := 0


func check(label: String, condition: bool, detail: String = "") -> void:
	print(("OK    " if condition else "FAIL  ") + label + ("" if detail == "" else "  (" + detail + ")"))
	if not condition:
		failures += 1


func _initialize() -> void:
	call_deferred("run_checks")


func strain_cards(cards: Array) -> Dictionary:
	var out := {}
	for c in cards:
		if c.has("strain"):
			out[c["strain"]] = c
	return out


func upcoming_count(g: TDGame, p: String) -> int:
	var n := 0
	for ge in g.upcoming:
		if String(ge.get("strain", "")) == p:
			n += 1
	return n


func run_checks() -> void:
	logic_checks()
	await ui_checks()
	print("evo_ui_check: %s" % ("OK" if failures == 0 else "%d FAIL" % failures))
	quit(1 if failures > 0 else 0)


# ── Логика карточек ──────────────────────────────────────────────

func logic_checks() -> void:
	var games := {}
	for n in TDEvoFixtures.NAMES:
		games[n] = TDEvoFixtures.build(n)

	# 1. даты соответствуют состоянию пакета, «может появиться» никогда не называет волну
	var seen := {}
	for n in games:
		var g: TDGame = games[n]
		if g.phase == "over":
			continue
		var cards := TDThreats.cards(g)
		var head := TDThreats.headline(cards)
		check("%s: в главной зоне не больше двух карточек" % n, head.size() <= TDThreats.MAIN_MAX)
		var sorted := true
		for i in range(1, cards.size()):
			sorted = sorted and int(cards[i - 1]["urgency"]) >= int(cards[i]["urgency"])
		check("%s: карточки по срочности" % n, sorted)
		for c in head:
			check("%s: в главной зоне только важное (%s)" % [n, c["id"]], int(c["urgency"]) >= TDThreats.MAIN_MIN)
		for c in cards:
			for k in c["towers"]:
				check("%s/%s: башня-ответ %s не закрыта" % [n, c["id"], k], not g.is_locked(k))
			check("%s/%s: не больше трёх башен-ответов" % [n, c["id"]], c["towers"].size() <= 3)
			if not c.has("strain"):
				continue
			var p: String = c["strain"]
			var k: Dictionary = g.strains["pk"][p]
			seen[c["status"]] = true
			match String(c["status"]):
				"maybe":
					check("%s/%s: «может появиться» только при инкубации" % [n, p], k["phase"] == "incubating")
					check("%s/%s: без обещания следующей волны" % [n, p], not String(c["title"]).contains("следующей") and not String(c["when"]).contains("после следующей"))
					check("%s/%s: нижняя граница не раньше min_wave" % [n, p], TDThreats.earliest_wave(g, p) >= int(TDStrains.PACK[p]["min_wave"]))
				"dated":
					check("%s/%s: «скоро» только при анонсе" % [n, p], k["phase"] == "announced")
					check("%s/%s: волна из состояния пакета (%d)" % [n, p, k["appear"]], String(c["when"]).contains(str(k["appear"])) and String(c["build"]).contains(str(k["appear"])))
					check("%s/%s: анонс за две фазы строительства" % [n, p], int(k["appear"]) == g.wave + 1)
				"next":
					check("%s/%s: «в следующей волне» только в первую волну пакета" % [n, p], k["phase"] == "active" and int(k["since"]) == g.wave)
				"active", "fading":
					check("%s/%s: фаза %s" % [n, p, c["status"]], k["phase"] == ("active" if c["status"] == "active" else "fading"))
			check("%s/%s: число врагов — по составу волны, не по доле" % [n, p], int(c["count"]) == upcoming_count(g, p), "%d vs %d" % [c["count"], upcoming_count(g, p)])
			# PRO-184: рекомендованные башни действительно ранят врагов пакета на уровнях 1–2;
			# ветки 3-го уровня, которые пакет гасит, названы в уточнении
			for t in c["towers"]:
				var ok12: bool = TDThreats.hurts(TDConfig.tower_def(t, 1, ""), p) and TDThreats.hurts(TDConfig.tower_def(t, 2, ""), p)
				check("%s/%s: %s ранит пакет на уровнях 1–2" % [n, p, t], ok12)
				for b in TDConfig.BRANCHES.get(t, []):
					if not TDThreats.hurts(TDConfig.tower_def(t, 3, b["id"]), p):
						var named := false
						for note in c["notes"]:
							named = named or (String(note).contains(TDConfig.TOWERS[t]["name"]) and String(note).contains(b["name"]))
						check("%s/%s: ветка «%s» у %s названа в уточнении" % [n, p, b["name"], t], named)
	for st in ["maybe", "dated", "next", "active", "fading"]:
		check("фикстуры покрывают статус «%s»" % st, seen.has(st))

	# 2. кадр живого плейтеста: 100% изучения до min_wave — не анонс
	var w7: TDGame = games["wave7"]
	var hk: Dictionary = w7.strains["pk"]["hulk"]
	var c7: Dictionary = strain_cards(TDThreats.cards(w7)).get("hulk", {})
	check("волна 7: инкубация панцирников ≥ 100%", float(hk["inc"]) >= TDStrains.ANNOUNCE, "%.2f" % hk["inc"])
	check("волна 7: это «может появиться», а не анонс", not c7.is_empty() and c7["status"] == "maybe")
	check("волна 7: главная карточка — защита от лёгких ударов", TDThreats.headline(TDThreats.cards(w7))[0]["id"] == "strain:hulk")
	check("волна 7: причина — твои башни", String(c7.get("why", "")).contains("Лучники"))
	check("волна 7: ответ — Снайпер, Пушка, Яд (Тесла закрыта у нового игрока)", c7.get("towers", []) == ["sniper", "cannon", "poison"], str(c7.get("towers", [])))
	check("волна 7: даты нет, но названа нижняя граница", String(c7.get("when", "")).contains("Даты пока нет") and String(c7.get("when", "")).contains("10"))

	# 3. закрытые башни не предлагаются, доступный ответ остаётся
	var lk: Dictionary = strain_cards(TDThreats.cards(games["locked"])).get("hulk", {})
	check("закрытые Снайпер и Тесла: ответ из доступных", lk.get("towers", []) == ["cannon", "poison"], str(lk.get("towers", [])))

	# 4. несколько пакетов сразу: оба видны в главной зоне
	var mh := TDThreats.headline(TDThreats.cards(games["multi"]))
	var ids: Array = []
	for c in mh:
		ids.append(c["id"])
	check("два пакета: оба в главной зоне", ids.has("strain:brood") and ids.has("strain:flock"), str(ids))
	var brood: Dictionary = strain_cards(TDThreats.cards(games["brood_next"])).get("brood", {})
	check("выводок: число кладок и малышей, не процент", String(brood.get("when", "")).contains("кладк") and String(brood.get("when", "")).contains("малыш") and not String(brood.get("when", "")).contains("%"))

	# 5. тихая волна и выключенный флаг
	check("тихая волна: главная зона пуста — «Новых угроз пока нет»", TDThreats.headline(TDThreats.cards(games["quiet"])).is_empty())
	for n in ["quiet_off", "boss_off", "stealth_off", "armor_off"]:
		var g: TDGame = games[n]
		check("%s: без флага нет пакетов и состояния роя" % n, not g.strains_on() and g.strains.is_empty() and strain_cards(TDThreats.cards(g)).is_empty())
	var boss := TDThreats.headline(TDThreats.cards(games["boss_off"]))
	check("без флага: босс следующей волны не исчезает", not boss.is_empty() and boss[0]["id"] == "boss")
	var stl := TDThreats.headline(TDThreats.cards(games["stealth_off"]))
	check("без флага: невидимки без Маяка — главная угроза с ответом Маяк", not stl.is_empty() and stl[0]["id"] == "stealth" and stl[0]["towers"] == ["beacon"])
	check("без флага: отчёт спокойный, если нового нет", TDThreats.calm_text(games["quiet_off"]).begins_with("Следующая волна"))

	# 6. новый признак: карточка, только если он задевает твои башни
	var ga: TDGame = games["armor_off"]
	var r: Dictionary = ga.reports[ga.reports.size() - 1]
	var low := r.duplicate(true)
	low["avg"]["plated"] = 0.0
	ga.reports[ga.reports.size() - 1] = low
	var tr := {}
	for c in TDThreats.cards(ga):
		tr[c["id"]] = c
	ga.reports[ga.reports.size() - 1] = r
	check("броня, ставшая заметной, — карточка с ответом", tr.has("trait:plated") and tr["trait:plated"]["status"] == "next" and not tr["trait:plated"]["towers"].is_empty())

	# 7. советы и плашки говорят то же, что отчёт
	var an: TDGame = games["announced"]
	var acard: Dictionary = strain_cards(TDThreats.cards(an))["hulk"]
	var same := false
	for tip in TDAdvisor.advice(an, TDAdvisor.wave_info(an)):
		same = same or (tip["title"] == acard["title"] and tip["towers"] == acard["towers"])
	check("советы: тот же заголовок и те же башни, что в отчёте", same)
	var chip_id := false
	for c in TDAdvisor.wave_chips(TDAdvisor.wave_info(games["appear_next"])):
		chip_id = chip_id or c.get("id", "") == "strain:hulk"
	check("плашка «Следом» связана с карточкой пакета", chip_id)

	# 8. карточка врага: конкретные башни, которые гасит панцирь, и кто его ранит
	var ah: TDGame = games["active_hulk"]
	check("враг-панцирник: «не ранят» твои лучники", TDThreats.enemy_label(ah, "hulk").contains("Лучники"))
	check("враг-панцирник: «ранят» — доступные ответы", TDThreats.enemy_answer(ah, "hulk").contains("Снайпер") and not TDThreats.enemy_answer(ah, "hulk").contains("Тесла"))

	# 9. экран поражения: причина только по фактическим прорывам
	var dh := TDThreats.defeat(games["defeat_hulk"])
	check("поражение: прорывы известны", dh["known"] and int(dh["lives"]) == 10)
	check("поражение: главная потеря — панцирники", not dh["cause"].is_empty() and String(dh["cause"]["title"]).contains("Панцирники"))
	var du := TDThreats.defeat(games["defeat_unknown"])
	check("поражение без данных: нейтрально, без причины", not du["known"] and du["cause"].is_empty())
	var mixed := TDEvoFixtures.build("active_hulk")
	TDEvoFixtures.defeat(mixed, {"hulk": 2}, 8)
	var dm := TDThreats.defeat(mixed)
	check("2 панцирника из 10 прорывов — не причина поражения", dm["known"] and dm["cause"].is_empty())

	# 10. учёт прорывов в настоящем бою совпадает со счётчиком игры и не трогает rng
	var a := TDGame.new(77, null, {})
	var b := TDGame.new(77, null, {})
	for gg in [a, b]:
		gg.start_wave()
	var steps := 0
	while a.phase == "wave" and steps < 20000:
		a.step(1.0 / 30.0)
		b.step(1.0 / 30.0)
		steps += 1
	check("бой: каждый прорыв учтён", int(a.wave_leaks["total"]) == a.leaked and a.leaked > 0, "%d vs %d" % [a.wave_leaks["total"], a.leaked])
	check("бой: жизни в учёте совпадают с потерей", int(a.wave_leaks["lives"]) == TDConfig.START_LIVES - a.lives or a.lives == 0)
	check("бой: два одинаковых забега совпадают (rng не тронут)", a.rng.a == b.rng.a and a.lives == b.lives and a.upcoming == b.upcoming)
	var restored := TDSave.restore(TDSave.snapshot(a))
	check("загрузка между волнами: учёт прорывов надёжен", restored != null and restored.leak_known)


# ── Окна ─────────────────────────────────────────────────────────

func find_node(root_node: Node, node_name: String) -> Node:
	return root_node.find_child(node_name, true, false)


func has_text(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text.contains(text):
		return true
	if node is Button and (node as Button).text.contains(text):
		return true
	for c in node.get_children():
		if has_text(c, text):
			return true
	return false


func settle(n: int = 4) -> void:
	for _i in n:
		await process_frame


func ui_checks() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene._demo = true
	root.add_child(scene)
	scene.set_process(false)
	await settle()
	scene.front.hide()
	for size in [Vector2i(960, 540), Vector2i(1920, 1080), Vector2i(1280, 720)]:
		root.size = size
		await settle(3)
		for n in ["wave7", "announced", "appear_next", "brood_next", "flock_next", "multi", "fading", "quiet", "quiet_off", "boss_off", "locked"]:
			scene.game = TDEvoFixtures.build(n)
			scene.board.set_game(scene.game)
			scene._wave_report.details_open = false
			scene._open_wave_report(TDWaveReport.snapshot(scene.game))
			await settle()
			var tag := "%s %dx%d" % [n, size.x, size.y]
			var view: Rect2 = scene.get_global_rect()
			var main_zone: Control = find_node(scene.wave_report_modal, "ReportMain")
			var okb: Control = find_node(scene.wave_report_modal, "ReportOk")
			check("%s: главная зона на экране без прокрутки" % tag, main_zone != null and view.grow(1.0).encloses(main_zone.get_global_rect()), str(main_zone.get_global_rect() if main_zone else null))
			check("%s: «ОК» на экране" % tag, okb != null and view.encloses(okb.get_global_rect()))
			check("%s: подробности свёрнуты" % tag, find_node(scene.wave_report_modal, "ReportScroll") == null)
			var head: Array = scene.wave_report["headline"]
			if head.is_empty():
				check("%s: «Новых угроз пока нет»" % tag, find_node(scene.wave_report_modal, "ThreatCalm") != null)
			else:
				var first := find_node(scene.wave_report_modal, "Threat_" + String(head[0]["id"]).replace(":", "_"))
				check("%s: главная карточка %s" % [tag, head[0]["id"]], first != null)
				var title: Label = first.find_child("ThreatTitle", true, false) if first != null else null
				check("%s: заголовок не длиннее двух строк" % tag, title != null and title.get_line_count() <= 2, str(title.get_line_count() if title else -1))
				for k in head[0]["towers"]:
					check("%s: кнопка башни %s" % [tag, k], first.find_child("Answer_" + k, true, false) != null)
			check("%s: в главной зоне нет процентов генов" % tag, not has_text(main_zone, "%"))
			scene._close_wave_report()
	# подробности раскрываются и прокручиваются, главная зона остаётся
	root.size = Vector2i(960, 540)
	await settle(3)
	scene.game = TDEvoFixtures.build("wave7")
	scene.board.set_game(scene.game)
	scene._open_wave_report(TDWaveReport.snapshot(scene.game))
	await settle()
	var tg: Button = find_node(scene.wave_report_modal, "ReportDetailsToggle")
	check("есть «Подробнее об эволюции»", tg != null)
	tg.pressed.emit()
	await settle()
	check("подробности: прокрутка и гены", find_node(scene.wave_report_modal, "ReportScroll") != null and has_text(scene.wave_report_modal, "изучает (100%)"))
	var okb2: Control = find_node(scene.wave_report_modal, "ReportOk")
	check("подробности: «ОК» на экране", scene.get_global_rect().encloses(okb2.get_global_rect()))
	# клик по башне-ответу закрывает отчёт и берёт башню
	var ans: Control = find_node(scene.wave_report_modal, "Answer_cannon")
	var ev := InputEventMouseButton.new()
	ev.pressed = true
	ev.button_index = MOUSE_BUTTON_LEFT
	ans.gui_input.emit(ev)
	await settle()
	check("клик по «Пушка» закрывает отчёт и берёт пушку", scene.wave_report.is_empty() and scene.tool == "cannon")
	scene._wave_report.details_open = false
	# панель «Рой»: сначала угрозы
	scene._set_tool("")
	scene._toggle_drawer()
	await settle()
	var sec: Control = find_node(scene.drawer_box, "ThreatsSection")
	check("панель «Рой»: блок «Угрозы и ответы» первым", sec != null and scene.drawer_box.get_child(0).get_child(0) == sec)
	check("панель «Рой»: та же главная карточка", find_node(sec, "Threat_strain_hulk") != null)
	scene._toggle_drawer()
	# экран поражения
	for n in ["defeat_hulk", "defeat_unknown"]:
		scene.game = TDEvoFixtures.build(n)
		scene.board.set_game(scene.game)
		scene._sigs.clear()
		scene._run_overlays._update_overlays()
		await settle()
		var dc: Control = find_node(scene.over_overlay, "DefeatCause")
		check("%s: блок «Что тебя погубило»" % n, dc != null)
		if n == "defeat_hulk":
			check("%s: причина — Панцирники, ответ Снайпер" % n, has_text(dc, "Панцирники") and dc.find_child("Answer_sniper", true, false) != null)
			check("%s: блок на экране" % n, scene.get_global_rect().grow(1.0).encloses(dc.get_global_rect()))
		else:
			check("%s: нейтрально, без башен" % n, dc.find_child("Answer_*", true, false) == null and has_text(dc, "Точных данных"))
	scene.queue_free()
	await settle()
