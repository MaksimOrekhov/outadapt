extends SceneTree
## PRO-150 review regressions: run boundaries, in-run scroll, unobscured advice and real input routing.
var scene
var failures := 0
var output := ""

func _initialize() -> void:
	call_deferred("run_checks")

func check(text: String, condition: bool) -> void:
	print(("OK   " if condition else "FAIL ") + text)
	if not condition: failures += 1

func settle() -> void:
	for frame in 10: await process_frame

func nodes(node: Node) -> Array[Node]:
	var found: Array[Node] = [node]
	for child in node.get_children(): found.append_array(nodes(child))
	return found

func scroll() -> ScrollContainer:
	return scene.drawer_box.get_parent() as ScrollContainer

func scroll_down() -> void:
	scroll().scroll_vertical = 360
	await settle()
	check("fixture is scrolled away from top", scroll().scroll_vertical > 0)

func empty_top(context: String) -> void:
	check(context + ": scroll reset", scroll().scroll_vertical == 0)
	var caption: Label
	for node in nodes(scene.drawer_box):
		if node is Label and node.text.begins_with("Пока нет данных"):
			caption = node
	check(context + ": empty-state caption in scroll viewport", caption != null and scroll().get_global_rect().encloses(caption.get_global_rect()))

func fixture() -> void:
	scene.selected_tower = null
	scene.game = TDGame.new(777)
	scene.board.set_game(scene.game)
	scene._demo_t = 0
	scene._skip_to = 8
	scene._demo_ui = ""
	scene._run_demo(0.4)
	for tick in 180: scene.game.step(1.0 / 60.0)
	scene._sigs.clear()
	scene._refresh(true)

func screenshot(name: String) -> void:
	await settle()
	if output == "" or DisplayServer.get_name() == "headless": return
	scene.board.queue_redraw()
	await RenderingServer.frame_post_draw
	check("save " + name, root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await settle()

func click(at: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	root.push_input(motion, true)
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = at
	event.pressed = true
	root.push_input(event, true)
	event = event.duplicate()
	event.pressed = false
	root.push_input(event, true)
	await settle()

func advice_bounds(context: String) -> void:
	var popup: Rect2 = scene.advice_pop.get_global_rect()
	check(context + ": advice is visible", scene._active_pop == scene.advice_pop and scene.advice_pop.visible and popup.size.y >= 48)
	check(context + ": advice inside window", scene.get_global_rect().encloses(popup))
	check(context + ": inspector and actions remain uncovered", not popup.intersects(scene.dock.get_global_rect()))
	check(context + ": advice clears HUD", popup.position.y >= scene.topbar.get_global_rect().end.y + 4)

func run_checks() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = ProjectSettings.globalize_path(arg.substr(6))
	if output != "": DirAccess.make_dir_recursive_absolute(output)
	TDSave.directory = "res://tests/.tmp_ui_context/saves"
	TDDisplay.config_path = "res://tests/.tmp_ui_context/display.cfg"
	scene = load("res://scenes/main.tscn").instantiate()
	scene._demo = true
	root.add_child(scene)
	scene.set_process(false)
	scene.board.set_process(false)
	scene.front.hide()
	await settle()
	for wh in [Vector2i(960,540), Vector2i(1280,720)]:
		root.size = wh
		await settle()
		fixture()
		if not scene.drawer.visible: scene._toggle_drawer()
		await settle()
		await scroll_down()
		var position_before: int = scroll().scroll_vertical
		# Ordinary refreshes, including rapid repeated action updates, must not lose position.
		scene._build_drawer_content()
		scene._build_drawer_content()
		await settle()
		check("%s same run retains scroll across refresh" % wh, scroll().scroll_vertical == position_before)
		scene.game.phase = "build"
		scene.game.enemies.clear()
		scene.game.pending.clear()
		scene.game.pending_boss.clear()
		scene.game.upcoming_boss = {}
		scene.game.upcoming_special = ""
		scene._on_vaccine("swift")
		await settle()
		check("vaccine action succeeds and retains scroll", not scene.game.vaccine.is_empty() and scroll().scroll_vertical == position_before)
		scene._on_lure("plated")
		await settle()
		check("lure action succeeds and retains scroll", not scene.game.lure.is_empty() and scroll().scroll_vertical == position_before)
		# Real restart path, not just swapping a fixture.
		scene._restart(false)
		scene._refresh(true)
		await settle()
		empty_top("%s restart" % wh)
		await screenshot("restart-swarm-%dx%d" % [wh.x,wh.y])
		await scroll_down()
		check("save isolated fresh run", TDSave.write(0, TDGame.new(4243), {}) == OK)
		check("load path succeeds", scene._load_slot(0))
		await settle()
		empty_top("%s loaded run" % wh)
		await screenshot("loaded-swarm-%dx%d" % [wh.x,wh.y])
		await scroll_down()
		position_before = scroll().scroll_vertical
		check("bad load rejected", not scene._load_slot(1))
		await settle()
		check("failed load preserves current scroll", scroll().scroll_vertical == position_before)
		# Reopening the same context preserves scroll; a different fixture is a new context.
		scene._toggle_drawer()
		scene._toggle_drawer()
		await settle()
		check("same-run close/reopen preserves scroll", scroll().scroll_vertical == position_before)
		# A pending old-context restore must not win over a restart in the same frame.
		scene._build_drawer_content()
		scene._restart(false)
		scene._refresh(true)
		await settle()
		empty_top("%s restart during pending scroll restore" % wh)
		scene._toggle_drawer()
		scene._restart(false)
		scene._refresh(true)
		scene._toggle_drawer()
		await settle()
		empty_top("%s hidden restart then open" % wh)
		scene._toggle_drawer()
		fixture()
		scene._toggle_drawer()
		await settle()
		check("different game instance resets on open", scroll().scroll_vertical == 0)
		scene._toggle_drawer()
		await key(KEY_A)
		advice_bounds("%s keyboard open" % wh)
		# A live content update must leave the popup positioned and nonempty.
		scene._sigs.erase("advice_pop")
		scene._refresh(true)
		await settle()
		advice_bounds("%s advice refresh" % wh)
		await screenshot("advice-%dx%d" % [wh.x,wh.y])
		await key(KEY_ESCAPE)
		check("Esc closes advice", scene._active_pop == null and not scene.advice_pop.visible)
		await click(scene.topbar.advice_btn.get_global_rect().get_center())
		advice_bounds("%s mouse open" % wh)
		await click(scene.dock.get_global_rect().get_center())
		check("outside click closes advice", scene._active_pop == null and not scene.advice_pop.visible)
		await key(KEY_A)
		var counter: Control
		for node in nodes(scene.advice_pop):
			if node is PanelContainer and node.tooltip_text.begins_with("Выбрать:"):
				counter = node
				break
		check("countermeasure available", counter != null)
		if counter != null:
			var expected: String = counter.tooltip_text.trim_prefix("Выбрать: ")
			await click(counter.get_global_rect().get_center())
			check("countermeasure click chooses tower and closes advice", scene._active_pop == null and scene.tool != "" and TDConfig.TOWERS[scene.tool]["name"] == expected)
		# Shrinking an already open popup must preserve the safe inspector region.
		await key(KEY_A)
		root.size = Vector2i(960,540)
		await settle()
		advice_bounds("%s resize to 960" % wh)
		scene._close_popovers()
	scene.queue_free()
	await process_frame
	print("UI context checks: %d failures" % failures)
	quit(1 if failures else 0)
