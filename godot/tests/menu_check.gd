extends SceneTree
## End-to-end menu actions with isolated save/settings files; no user data is modified.

var failures := 0
const TMP := "res://tests/.tmp_menu_check"

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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP))
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	for frame in 4:
		await process_frame
	scene.audio.config_path = TMP + "/audio.cfg"
	check("startup shows main menu without starting a run", scene.front.visible and not scene._run_started and scene.game.phase == "build")
	check("save disabled before a new game", button_named(scene.front, "Сохранить игру").disabled)
	check("continue disabled without any save", button_named(scene.front, "Продолжить").disabled)
	await capture("main-menu.png")
	scene._tutorial_seen = true
	button_named(scene.front, "Новая игра").pressed.emit()
	await process_frame
	check("new-game button opens mode and difficulty choice", scene.front.page == "newgame" and button_named(scene.front, "Начать") != null)
	button_named(scene.front, "Начать").pressed.emit()
	await process_frame
	check("new-game button enters a fresh run", scene._run_started and not scene.front.visible and scene.game.wave == 1)
	scene.set_process(false)
	# профиль игрока может давать стартовый выбор усиления (Мастерская): тест от этого не зависит
	scene.game.offer = []
	scene.game.start_wave()
	for step in 100:
		scene.game.step(1.0 / 60.0)
	scene.speed = 2
	scene._show_front()
	var frozen := TDSave.fields(scene.game, TDSave.GAME_FIELDS)
	scene.set_process(true)
	for frame in 10:
		await process_frame
	check("returning to menu freezes simulation", scene.front.visible and frozen == TDSave.fields(scene.game, TDSave.GAME_FIELDS))
	check("returning to menu creates an autosave", not TDSave.read(3).is_empty())
	var previous_tool: String = scene.tool
	var key := InputEventKey.new()
	key.keycode = KEY_1
	key.pressed = true
	scene._input(key)
	check("game shortcuts are blocked by the menu", scene.tool == previous_tool)
	button_named(scene.front, "Сохранить игру").pressed.emit()
	check("save button opens slot picker", scene.front.page == "save")
	var slot: Button
	for child in scene.front._content.get_children():
		if child is Button and child.text.begins_with("Слот 1\n"):
			slot = child
	slot.pressed.emit()
	check("slot button saves a complete run", not TDSave.read(0).is_empty() and scene.front.page == "home")
	scene.front.slots(true)
	for child in scene.front._content.get_children():
		if child is Button and child.text.begins_with("Слот 1\n"):
			slot = child
	slot.pressed.emit()
	check("occupied slot requires confirmation", scene.front.page == "confirm")
	button_named(scene.front, "Отмена").pressed.emit()
	check("overwrite can be cancelled", scene.front.page == "home" and not TDSave.read(0).is_empty())
	scene.front.slots(true)
	for child in scene.front._content.get_children():
		if child is Button and child.text.begins_with("Слот 1\n"):
			slot = child
	slot.pressed.emit()
	button_named(scene.front, "Подтвердить").pressed.emit()
	check("confirmed overwrite succeeds", scene.front.page == "home" and FileAccess.file_exists(TDSave.path_for(0) + ".bak"))
	scene.front.slots(false)
	await capture("save-slots.png")
	scene.front.home(true)
	var saved_gold: int = scene.game.gold
	scene.game.gold = 1
	check("load restores the saved game", scene._load_slot(0) and scene.game.gold == saved_gold and scene.speed == 2)
	check("loaded run is paused for the player", scene.user_paused and not scene.front.visible)
	var before_dist: float = scene.game.enemies[0].dist
	for frame in 8:
		await process_frame
	check("loaded enemies do not move until resumed", scene.game.enemies[0].dist == before_dist)
	scene._toggle_pause()
	for frame in 8:
		await process_frame
	check("resuming advances the restored wave", not scene.game.enemies.is_empty() and scene.game.enemies[0].dist > before_dist)
	scene._show_front()
	scene.front.settings()
	await capture("settings.png")
	if OS.get_cmdline_user_args().has("--visual"):
		scene.front._cancel_settings()
		await finish(scene)
		return
	var original_volume: float = scene.audio.master_volume
	scene.audio.set_volume("master", 0.37)
	check("volume adjusts the real audio bus", absf(db_to_linear(AudioServer.get_bus_volume_db(0)) - 0.37) < 0.001)
	scene.front._cancel_settings()
	check("cancelling settings restores volume", is_equal_approx(scene.audio.master_volume, original_volume))
	scene.front.settings()
	var prior_display := TDDisplay.values.duplicate(true)
	scene.front._mode.select(0 if TDDisplay.values["fullscreen"] else 1)
	scene.front._apply_settings()
	check("video changes require timed confirmation", scene.front.page == "video_confirm" and scene.front._trial > 0)
	scene.front._process(16.0)
	check("unconfirmed video mode rolls back", TDDisplay.values == prior_display and scene.front.page == "home")
	scene.front.settings()
	scene.audio.set_volume("master", 0.61)
	scene.audio.set_volume("music", 0.43)
	scene.audio.set_volume("sfx", 0.78)
	scene.front._apply_settings()
	var config := ConfigFile.new()
	check("settings are persisted", config.load(scene.audio.config_path) == OK and absf(config.get_value("audio", "music_volume") - 0.43) < 0.001 and FileAccess.file_exists(TDDisplay.config_path))
	TDSave.write_file(TDSave.path_for(1), {"version": 999})
	var previous_game = scene.game
	check("bad save leaves the active run intact", not scene._load_slot(1) and scene.game == previous_game)
	await finish(scene)

func capture(filename: String) -> void:
	if not OS.get_cmdline_user_args().has("--visual"):
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://screenshots/" + filename)

func finish(scene) -> void:
	scene._run_started = false
	root.remove_child(scene)
	scene.queue_free()
	await process_frame
	await create_timer(0.1).timeout
	for name in DirAccess.get_files_at(ProjectSettings.globalize_path(TDSave.directory)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TDSave.directory.path_join(name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TDSave.directory))
	for name in DirAccess.get_files_at(ProjectSettings.globalize_path(TMP)):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP.path_join(name)))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TMP))
	print("Menu checks: %d failures" % failures)
	quit(1 if failures > 0 else 0)
