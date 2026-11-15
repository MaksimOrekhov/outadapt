extends SceneTree
## Deterministic real-client captures and layout invariants. No player files are written.
## godot --path godot --script res://tests/visual_slice_check.gd -- --capture --out=../screenshots/pro150/after

var scene
var failures := 0
var output := ""
var baseline := false
var interactive := false
var inspect_state := ""
var inspect_size := Vector2i(960,540)
var metrics: Array = []

func _initialize() -> void:
	call_deferred("run_checks")

func check(description: String, ok: bool) -> void:
	if not ok: failures += 1
	print(("OK   " if ok else "FAIL ") + description)

func settle() -> void:
	for frame in 10: await process_frame
	if DisplayServer.get_name() != "headless": await RenderingServer.frame_post_draw

func descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children(): result.append_array(descendants(child))
	return result

func capture(state: String, wh: Vector2i) -> void:
	scene.board.selected = scene.selected_tower
	scene.board.queue_redraw()
	await settle()
	var bounds: Rect2 = scene.get_global_rect()
	if not baseline:
		check("%s %s: actual viewport" % [wh, state], root.size == wh and scene.size == Vector2(wh))
		check("%s %s: HUD and dock bounded" % [wh, state], bounds.grow(1).encloses(scene.topbar.get_global_rect()) and bounds.grow(1).encloses(scene.dock.get_global_rect()))
		for surface in [scene.drawer, scene._active_pop]:
			if surface != null and surface.visible:
				check("%s %s: popup content remains visible" % [wh, state], surface.size.y >= 48)
				check("%s %s: popup bounded" % [wh, state], bounds.grow(1).encloses(surface.get_global_rect()))
		for node in descendants(scene):
			if node is PanelContainer and node.has_meta("modal_surface") and node.is_visible_in_tree():
				check("%s %s: modal bounded" % [wh, state], bounds.grow(1).encloses(node.get_global_rect()))
			if node is ScrollContainer and node.is_visible_in_tree() and node.get_child_count() > 0:
				var body: Control = node.get_child(0)
				var bar: VScrollBar = node.get_v_scroll_bar()
				var available: float = node.size.x - (bar.size.x if bar.visible else 0)
				check("%s %s: scroll content width %s (%s <= %s)" % [wh,state,node.get_path(),body.size.x,available], body.size.x <= available + 1)
			if node is Button and node.is_visible_in_tree() and node.text.is_empty() and node.icon != null:
				check("%s %s: icon action has a hit target" % [wh,state], node.size.x >= 32 and node.size.y >= 32)
			if node is Label and node.is_visible_in_tree() and not node.text.is_empty():
				# Vertical scroll is permitted; clipping a label inside its own rect is not.
				if node.get_minimum_size().y > node.size.y + 1 or node.get_minimum_size().x > node.size.x + 1:
					check("%s %s: text fits %s (%s / %s)" % [wh, state, node.text.left(50), node.get_minimum_size(), node.size], false)
	if output != "" and DisplayServer.get_name() != "headless":
		var image := root.get_texture().get_image()
		var filename := "%s-%dx%d.png" % [state, wh.x, wh.y]
		check("saved " + filename, image.save_png(output.path_join(filename)) == OK)
	if inspect_state == state:
		scene.user_paused = true
		scene.board.set_process(true)
		scene.set_process(true)
		print("INTERACTIVE INSPECTION: ",state," ",wh)
		while is_instance_valid(scene): await create_timer(1).timeout
	metrics.append({"state":state,"window":[root.size.x,root.size.y],"canvas":[scene.size.x,scene.size.y],"seed":777,"wave":scene.game.wave,"gold":scene.game.gold,"lives":scene.game.lives})

func fixture() -> void:
	scene.selected_tower = null
	scene.tool = ""
	scene.board.hover_cell = Vector2i(-1,-1)
	scene.game = TDGame.new(777)
	scene.board.set_game(scene.game)
	scene._demo_t = 0.0
	scene._skip_to = 8
	scene._demo_ui = ""
	scene._run_demo(0.4)
	for tick in 180: scene.game.step(1.0 / 60.0)
	scene._sigs.clear()
	scene._refresh(true)

func run_checks() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="): output = ProjectSettings.globalize_path(arg.substr(6))
		if arg == "--baseline": baseline = true
		if arg == "--interactive": interactive = true
		if arg.begins_with("--inspect="): inspect_state = arg.substr(10)
		if arg.begins_with("--size="):
			var parts := arg.substr(7).split("x")
			inspect_size = Vector2i(int(parts[0]),int(parts[1]))
	if output != "": DirAccess.make_dir_recursive_absolute(output)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tests/.tmp_visual_slice"))
	TDSave.directory = "res://tests/.tmp_visual_slice/saves"
	TDDisplay.config_path = "res://tests/.tmp_visual_slice/display.cfg"
	scene = load("res://scenes/main.tscn").instantiate()
	scene._demo = true
	root.add_child(scene)
	scene.set_process(false)
	scene.board.set_process(false)
	scene.audio.config_path = "res://tests/.tmp_visual_slice/audio.cfg"
	scene._tutorial_seen = true
	TDMeta.points = 0
	TDMeta.levels = {}
	TDMeta.achievements = {}
	await settle()
	if interactive:
		scene._skip_to = 8
		scene._demo_ui = "build"
		scene.board.set_process(true)
		scene.set_process(true)
		return
	# Only baseline captures bypass the old minimum-size guard; no canvas overrides.
	if baseline: root.min_size = Vector2i.ZERO
	for wh in [Vector2i(960,540),Vector2i(1280,720),Vector2i(1600,900),Vector2i(1920,1080)]:
		if inspect_state != "" and wh != inspect_size: continue
		root.size = wh
		await settle()
		scene.front.home(false)
		scene.front.show()
		await capture("menu",wh)
		scene.front.settings()
		await capture("settings",wh)
		scene.front.hide()
		fixture()
		await capture("combat",wh)
		scene._demo_ui = "upgrade"
		scene._run_demo(0.7)
		for tick in 60: scene.game.step(1.0 / 60.0)
		scene.board.vfx.update(2.0)
		scene._refresh(true)
		await capture("upgrade",wh)
		scene._toggle_drawer()
		await capture("swarm",wh)
		scene._toggle_drawer()
		scene._toggle_advice()
		await capture("advice",wh)
		scene._close_popovers()
		scene._open_wave_report(TDWaveReport.snapshot(scene.game))
		await capture("wave-report",wh)
		scene._close_wave_report()
		var long_report := TDWaveReport.snapshot(scene.game).duplicate(true)
		var entries: Array = long_report["entries"]
		if not entries.is_empty():
			while entries.size() < 12: entries.append(entries[0].duplicate(true))
		scene._open_wave_report(long_report)
		await capture("long-report",wh)
		scene._close_wave_report()
		scene.game.offer = ["shatter","rapid","bounty","variety"]
		scene._refresh(true)
		await capture("perks",wh)
		scene.game.offer = []
		scene._refresh(true)
		scene._open_help()
		await capture("help",wh)
		scene._close_help()
		scene._open_meta()
		await capture("workshop",wh)
		scene._close_meta()
		# Activate both via real public gameplay actions, then show the unmodified previews.
		scene.game.enemies.clear()
		scene.game.pending.clear()
		scene.game.pending_boss.clear()
		scene.game.phase = "build"
		scene.game.upcoming_special = ""
		scene.game.upcoming_boss = {}
		scene.game.gold = 5000
		var vaccine_ok: bool = scene.game.buy_vaccine("swift")
		var lure_ok: bool = scene.game.buy_lure("plated")
		check("%s: vaccine + lure fixture" % wh, vaccine_ok and lure_ok)
		scene._refresh(true)
		scene._toggle_drawer()
		await capture("vaccine-lure",wh)
		for node in descendants(scene.drawer_box):
			if node is Label and node.text == "Скорость":
				(scene.drawer_box.get_parent() as ScrollContainer).ensure_control_visible(node)
				break
		await capture("vaccine-lure-actions",wh)
		scene._toggle_drawer()
		scene.selected_tower = null
		scene.game = TDGame.new(777)
		scene.board.set_game(scene.game)
		scene._refresh(true)
		scene._toggle_drawer()
		await capture("empty-swarm",wh)
		scene._toggle_drawer()
	if output != "":
		var file := FileAccess.open(output.path_join("capture-metrics.json"),FileAccess.WRITE)
		file.store_string(JSON.stringify(metrics,"\t"))
	scene.queue_free()
	await process_frame
	print("Visual slice checks: %d failures" % failures)
	quit(1 if failures else 0)
