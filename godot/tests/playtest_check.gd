extends SceneTree
## PRO-115: настоящий путь живого плейтеста через сцену игры — меню «Новая игра» → волна → окно отчёта → журнал.
## Аргументы run_playtest.bat (--playtest, --swarm, --fixed-seed, --no-workshop, --build) задаются полями сцены.
## Журнал пишется во временный каталог; сохранения и мета-прогресс игрока не трогаются (играется одна волна, без рестартов).

var failures := 0
const TMP := "res://tests/.tmp_playtest_check"


func check(label: String, condition: bool) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition:
		failures += 1


func button_named(node: Node, text: String) -> Button:
	for child in node.get_children():
		if child is Button and child.text == text:
			return child
		var found := button_named(child, text)
		if found != null:
			return found
	return null


func _initialize() -> void:
	call_deferred("run_checks")


func run_checks() -> void:
	TDSave.directory = TMP + "/saves"
	TDDisplay.config_path = TMP + "/display.cfg"
	TDPlaytestLog.directory = TMP + "/playtest"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP))
	var on_log := await _one_run("signature")
	var off_log := await _one_run("")
	check("два забега — два журнала", on_log != off_log and on_log != "" and off_log != "")
	_cleanup()
	await create_timer(0.1).timeout
	print("playtest_check: %s" % ("OK" if failures == 0 else "%d FAIL" % failures))
	quit(1 if failures > 0 else 0)


## Один забег: новая игра через меню, одна волна, возвращает путь журнала.
func _one_run(model: String) -> String:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene._playtest = true
	scene._swarm_model = model
	scene._fixed_seed = 1003
	scene._no_workshop = true
	scene._build = "check-" + (model if model != "" else "off")
	root.add_child(scene)
	for frame in 4:
		await process_frame
	scene.audio.config_path = TMP + "/audio.cfg"
	# как в демо-режиме: без звуков — их таймеры пережили бы сцену, которую тест освобождает
	scene.audio.sfx_on = false
	scene._tutorial_seen = true
	button_named(scene.front, "Новая игра").pressed.emit()
	await process_frame
	button_named(scene.front, "Начать").pressed.emit()
	await process_frame
	var tag := "ON" if model != "" else "OFF"
	check("%s: фиксированный сид и семейство карты" % tag, scene.game.seed_value == 1003 and scene.game.map.family == "snake")
	check("%s: флаг эксперимента %s" % [tag, "включён" if model != "" else "выключен"], scene.game.strains_on() == (model != ""))
	check("%s: без бонусов Мастерской" % tag, not scene.game.meta.has("gold") and not scene.game.meta.has("lives"))
	scene.set_process(false)
	scene.game.offer = []
	scene.game.gold = 400
	for c in scene.game.map.order.slice(8, 30):
		for d in [Vector2i(0, 1), Vector2i(1, 0)]:
			var p: Vector2i = c + d
			scene.game.place_tower("arrow", p.x, p.y)
	scene._start_wave()
	scene._watch_phase()
	for i in 6000:
		scene.game.step(1.0 / 30.0)
		scene._watch_phase()
		if scene.game.phase != "wave":
			break
	check("%s: волна сыграна, открыто окно отчёта" % tag, scene.game.phase == "build" and not scene.wave_report.is_empty())
	var path: String = scene._ptlog.path if scene._ptlog != null else ""
	var lines: Array = []
	if path != "" and FileAccess.file_exists(path):
		for l in FileAccess.get_file_as_string(path).strip_edges().split("\n"):
			lines.append(JSON.parse_string(l))
	var events: Array = lines.map(func(x): return x.get("event", "") if x is Dictionary else "")
	check("%s: журнал — конфигурация, старт, конец волны (%s)" % [tag, ", ".join(events)], events == ["run", "start", "end"])
	if lines.size() >= 3:
		var run: Dictionary = lines[0]
		check("%s: в конфигурации сборка, флаг, сид, семейство, сложность, Мастерская" % tag, run["build"] == scene._build
			and run["swarm_model"] == (model if model != "" else "off") and int(run["seed"]) == 1003 and run["family"] == "snake"
			and run["difficulty"] == "normal" and run["workshop"] == false)
		check("%s: старт волны — постройки и состав обороны" % tag, lines[1]["built"].size() > 0 and int(lines[1]["towers"].get("arrow", 0)) > 0)
		check("%s: конец волны — жизни, утечки, урон" % tag, lines[2].has("lives") and lines[2].has("leaked") and lines[2]["damage"].has("arrow"))
	# как в menu_check: закрыть окно отчёта (у него отложенная подгонка), снять сцену и дать движку освободить ресурсы
	# окно отчёта подгоняет размер в следующих кадрах: игрок не может закрыть его раньше
	for frame in 3:
		await process_frame
	scene._close_wave_report()
	scene._run_started = false
	for frame in 3:
		await process_frame
	root.remove_child(scene)
	scene.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	return path


func _cleanup() -> void:
	for sub in ["/saves", "/playtest", ""]:
		var dir := DirAccess.open(TMP + sub)
		if dir != null:
			for f in dir.get_files():
				dir.remove(f)
	for sub in ["/saves", "/playtest", ""]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP + sub))
