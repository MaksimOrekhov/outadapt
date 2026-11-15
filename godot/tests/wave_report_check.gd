extends SceneTree
## Smoke-проверка модального окна «Волна N пройдена» (PRO-148):
## godot --headless --path godot --script res://tests/wave_report_check.gd

var failures := 0


func check(label: String, condition: bool, detail: String = "") -> void:
	print(("OK    " if condition else "FAIL  ") + label + ("" if detail == "" else "  (" + detail + ")"))
	if not condition:
		failures += 1


## Завершает волну без боя: даёт настоящий отчёт и объяснения адаптации.
func finish_wave(g: TDGame, dmg: Dictionary) -> void:
	g.start_wave()
	g.finished = []
	for i in g.wave_genomes.size():
		g.finished.append({"genome": g.wave_genomes[i], "fitness": float(g.wave_genomes.size() - i)})
	g.pending = []
	g.enemies.clear()
	g.killed = g.wave_genomes.size()
	g.damage_by = TDGame._zero_damage()
	for k in dmg:
		g.damage_by[k] = dmg[k]
	g._end_wave()


func key(scene: Node, code: int) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = code
	scene._input(ev)


func find_node(root_node: Node, node_name: String) -> Node:
	return root_node.find_child(node_name, true, false)


func _initialize() -> void:
	call_deferred("run_checks")


func run_checks() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	scene._demo = true
	root.add_child(scene)
	scene.set_process(false)
	for frame in 4:
		await process_frame
	scene.front.hide()
	# настоящий забег с отчётами о волнах
	scene.game = TDGame.new(4243)
	scene.board.set_game(scene.game)
	var g: TDGame = scene.game
	for _w in 7:
		finish_wave(g, {"arrow": 70.0, "cannon": 30.0})
	var snap := TDWaveReport.snapshot(g)
	check("снимок отчёта не пуст", not snap.is_empty() and snap["wave"] == 7)
	check("в отчёте есть объяснения адаптации", snap["entries"].size() > 0)

	# 1. окно открывается и остаётся без таймера
	check("окно закрыто до конца волны", scene.wave_report.is_empty() and not scene.wave_report_modal.visible)
	scene._open_wave_report(snap)
	await process_frame
	check("окно открыто и видно", not scene.wave_report.is_empty() and scene.wave_report_modal.visible)
	var phase_before := g.phase
	var wave_before := g.wave
	await create_timer(2.5).timeout
	check("окно не исчезает само (дольше баннера в 1,5 с)", not scene.wave_report.is_empty() and scene.wave_report_modal.visible)
	check("в окне есть заголовок «Волна 7 пройдена»", find_label(scene.wave_report_modal, "Волна 7 пройдена"))
	check("в окне есть кнопка «ОК»", find_node(scene.wave_report_modal, "ReportOk") != null)

	# 2. клики и клавиши не проходят под окно
	scene.tool = "arrow"
	scene.board.tool = "arrow"
	var towers_before := g.towers.size()
	scene._on_cell_clicked(Vector2i(3, 3), MOUSE_BUTTON_LEFT)
	check("клик по полю не ставит башню", g.towers.size() == towers_before)
	scene._start_wave()
	check("старт волны заблокирован", g.phase == phase_before)
	key(scene, KEY_2)
	check("горячая клавиша башни не проходит под окно", scene.tool == "arrow")
	key(scene, KEY_TAB)
	check("Tab не открывает панель под окном", not scene.drawer.visible)
	check("окно осталось открытым после чужих клавиш", not scene.wave_report.is_empty())
	check("_blocked() истинно", scene._blocked())

	# 3. «ОК» закрывает, фаза и волна не меняются
	var ok: Button = find_node(scene.wave_report_modal, "ReportOk")
	ok.pressed.emit()
	await process_frame
	check("«ОК» закрывает окно", scene.wave_report.is_empty() and not scene.wave_report_modal.visible)
	check("игра осталась между волнами", g.phase == phase_before and g.wave == wave_before)
	g.offer = []  # выбор усиления после волн 3 и 6 — отдельная законная блокировка
	check("после закрытия блокировки нет", not scene._blocked(), "front=%s tut=%d help=%s meta=%s vic=%s offer=%d" % [scene.front.visible, scene.tutorial_step, scene.help_open, scene.meta_open, scene.victory_overlay.visible, scene.game.offer.size()])

	# 4. клавиатура: Enter, Space, Esc закрывают; Space не запускает волну
	for code in [KEY_ENTER, KEY_SPACE, KEY_ESCAPE]:
		scene._open_wave_report(snap)
		await process_frame
		key(scene, code)
		await process_frame
		check("клавиша %s закрывает окно" % OS.get_keycode_string(code), scene.wave_report.is_empty())
		check("клавиша %s не запускает волну и не открывает меню" % OS.get_keycode_string(code), g.phase == "build" and not (scene.front != null and scene.front.visible))

	# 5. повторные волны не дублируют окно
	scene._open_wave_report(snap)
	scene._open_wave_report(snap)
	await process_frame
	check("два вызова подряд оставляют одно окно", scene.wave_report_modal.get_child_count() == 1)
	var snap2 := snap.duplicate(true)
	snap2["wave"] = 8
	scene._open_wave_report(snap2)
	await process_frame
	check("следующая волна заменяет содержимое", scene.wave_report_modal.get_child_count() == 1 and find_label(scene.wave_report_modal, "Волна 8 пройдена") and not find_label(scene.wave_report_modal, "Волна 7 пройдена"))
	scene._close_wave_report()

	# 6. не накладывается на окно усиления и победу
	g.offer = ["shatter", "rapid", "bounty"]
	scene._open_wave_report(snap)
	scene._run_overlays._update_overlays()
	check("усиление ждёт закрытия отчёта", not scene.perk_overlay.visible)
	key(scene, KEY_1)
	check("клавиша 1 не выбирает усиление под окном", g.offer.size() == 3)
	scene._close_wave_report()
	scene._run_overlays._update_overlays()
	check("после «ОК» усиление показывается", scene.perk_overlay.visible)
	g.offer = []
	scene._run_overlays._update_overlays()
	g.victory = true
	scene._victory_seen = false
	scene._open_wave_report(snap)
	scene._run_overlays._update_overlays()
	check("победа ждёт закрытия отчёта", not scene.victory_overlay.visible)
	scene._close_wave_report()
	scene._run_overlays._update_overlays()
	check("после «ОК» показывается победа", scene.victory_overlay.visible)
	scene.victory_overlay.visible = false
	g.victory = false
	scene._victory_seen = true

	# 7. короткие баннеры не прячутся под затемнением, а ждут закрытия
	var stage_children: int = scene.stage.get_child_count()
	scene._open_wave_report(snap)
	scene._banner("Достижение!", "тест", Color.WHITE)
	check("баннер во время окна ставится в очередь", scene._banner_queue.size() == 1 and scene.stage.get_child_count() == stage_children)
	scene._close_wave_report()
	check("после закрытия очередь баннеров показана", scene._banner_queue.is_empty() and scene.stage.get_child_count() == stage_children + 1)

	# 8. нет пустых секций, когда объяснений нет
	var plain := snap.duplicate(true)
	plain["entries"] = []
	scene._open_wave_report(plain)
	await process_frame
	check("без объяснений нет блока прокрутки и заголовка секции", find_node(scene.wave_report_modal, "ReportScroll") == null and not find_label(scene.wave_report_modal, "РОЙ АДАПТИРУЕТСЯ") and not find_label(scene.wave_report_modal, "Рой адаптируется"))
	check("итог и «ОК» на месте без объяснений", find_label(scene.wave_report_modal, "Волна 7 пройдена") and find_node(scene.wave_report_modal, "ReportOk") != null)
	scene._close_wave_report()

	# 9. размеры окна: длинный отчёт помещается, «ОК» на экране
	var long_snap := snap.duplicate(true)
	var entries: Array = long_snap["entries"]
	while entries.size() < 8:
		entries.append(entries[entries.size() % maxi(1, snap["entries"].size())].duplicate(true))
	for size in [Vector2i(960, 540), Vector2i(1280, 720), Vector2i(1600, 900), Vector2i(1000, 700)]:
		root.size = size
		for frame in 3:
			await process_frame
		scene._open_wave_report(long_snap)
		for frame in 4:
			await process_frame
		var view: Rect2 = scene.get_global_rect()
		var okb: Control = find_node(scene.wave_report_modal, "ReportOk")
		var panel: Control = okb.get_parent().get_parent()
		check("%dx%d: «ОК» в пределах экрана" % [size.x, size.y], view.encloses(okb.get_global_rect()), "%s в %s" % [okb.get_global_rect(), view])
		check("%dx%d: окно целиком в пределах экрана" % [size.x, size.y], view.grow(1.0).encloses(panel.get_global_rect()), "%s в %s" % [panel.get_global_rect(), view])
		scene._close_wave_report()

	# 10. новая игра и главное меню закрывают окно
	scene._open_wave_report(snap)
	scene._show_front()
	check("главное меню закрывает окно отчёта", scene.wave_report.is_empty() and not scene.wave_report_modal.visible)

	scene.queue_free()
	await process_frame
	print("Wave report checks: %d failures" % failures)
	quit(1 if failures > 0 else 0)


func find_label(node: Node, text: String) -> bool:
	if node is Label and (node as Label).text == text:
		return true
	for c in node.get_children():
		if find_label(c, text):
			return true
	return false
