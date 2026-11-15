class_name TDFrontMenu
extends Control
## Title screen, save slots and shared settings. The host freezes the running game.

signal action_requested(action: String, slot: int)

var audio: TDAudio
## Выбор на странице «Новая игра»; main читает его при действии "new".
var options := {"difficulty": "normal", "mode": "standard"}
var has_run := false
var page := "home"
var _content: VBoxContainer
var _panel: PanelContainer
var _notice: Label
var _pending: Callable
var _audio_before: Dictionary
var _display_before: Dictionary
var _resolution: OptionButton
var _mode: OptionButton
var _vsync: CheckButton
var _sizes: Array[Vector2i] = []
var _trial := 0.0
var _countdown: Label

func setup(sound: TDAudio) -> void:
	audio = sound
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 200
	mouse_filter = Control.MOUSE_FILTER_STOP
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var background := TextureRect.new()
	background.texture = load("res://assets/ui/menu-background.png")
	background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var shade := ColorRect.new()
	shade.color = Color(0.025, 0.02, 0.015, 0.18)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 52)
	add_child(margin)
	var row := TDUI.hbox()
	margin.add_child(row)
	_panel = PanelContainer.new()
	_panel.add_theme_stylebox_override("panel", TDUI.skin("frame", 28))
	_panel.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_panel)
	_content = TDUI.vbox(10)
	_panel.add_child(_content)
	row.add_child(TDUI.spacer())
	visible = false

func _begin(title: String, width: float = 440) -> void:
	TDUI.clear(_content)
	_panel.custom_minimum_size.x = width
	_panel.reset_size()
	_content.add_child(TDUI.label(title, 29, TDUI.TEXT, true))
	_notice = null

func _button(text: String, icon: String, callback: Callable, primary := false, disabled := false) -> Button:
	var button := Button.new()
	button.text = text
	button.icon = TDIcons.tex(icon)
	button.expand_icon = true
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 44
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_constant_override("icon_max_width", 24)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.disabled = disabled
	if primary:
		button.add_theme_stylebox_override("normal", TDUI.skin("primary", 16))
		button.add_theme_stylebox_override("hover", TDUI.skin("selected", 16))
	button.pressed.connect(callback)
	_content.add_child(button)
	return button

func message(text: String, error := false) -> void:
	if not is_instance_valid(_notice):
		_notice = TDUI.para(text, 12, TDUI.BAD if error else TDUI.MUTED)
		_content.add_child(_notice)
	else:
		_notice.text = text
		_notice.add_theme_color_override("font_color", TDUI.BAD if error else TDUI.MUTED)

func home(active: bool, text := "") -> void:
	visible = true
	has_run = active
	page = "home"
	_pending = Callable()
	_begin("OUTADAPT", 440)
	_content.add_child(TDUI.label("ВРАГИ УЧАТСЯ", 25, TDUI.GOLD, true))
	_content.add_child(TDUI.para("Построй защиту. Останови рой.\nКаждая волна учится у предыдущей.", 14, TDUI.MUTED))
	_content.add_child(HSeparator.new())
	var latest := TDSave.latest_slot()
	var resume := _button("Продолжить", "play", func(): action_requested.emit("continue", latest), true, not active and latest < 0)
	resume.tooltip_text = "Вернуться к текущему забегу" if active else "Загрузить последнее сохранение"
	var new_game := _button("Новая игра", "wave", new_game_page, not active and latest < 0)
	_button("Сохранить игру", "info", func(): slots(true), false, not active)
	_button("Загрузить игру", "help", func(): slots(false))
	var done := TDMeta.achievements.size()
	_button("Достижения  %d / %d" % [done, TDMeta.ACHIEVEMENTS.size()], "star", achievements_page)
	_button("Настройки", "menu", settings)
	_button("Выйти из игры", "portal", func(): confirm("Выйти из игры?", "Текущий забег будет автоматически сохранён." if has_run else "До следующей битвы!", func(): action_requested.emit("quit", -1)))
	message(text if text != "" else "Esc — вернуться к забегу" if active else "Выбери новую игру или загрузи сохранение.")
	if resume.disabled:
		new_game.grab_focus()
	else:
		resume.grab_focus()

## Кнопка-переключатель для выбора режима и сложности.
func _choice(group: ButtonGroup, text: String, on: bool, locked: bool, hint: String) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.button_pressed = on and not locked
	b.disabled = locked
	b.tooltip_text = hint
	b.custom_minimum_size = Vector2(0, 42)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_disabled_color", Color("#6f6450"))
	b.add_theme_stylebox_override("pressed", TDUI.skin("selected", 12))
	b.add_theme_stylebox_override("hover_pressed", TDUI.skin("selected", 12))
	return b


func new_game_page() -> void:
	page = "newgame"
	_begin("Новая игра", 660)
	var modes := ButtonGroup.new()
	var diffs := ButtonGroup.new()
	var mode_text := TDUI.para("", 13, TDUI.MUTED)
	var diff_text := TDUI.para("", 13, TDUI.MUTED)
	if not TDMeta.mode_unlocked(options["mode"]):
		options["mode"] = "standard"
	if not TDMeta.difficulty_unlocked(options["difficulty"]):
		options["difficulty"] = "normal"
	_content.add_child(TDUI.section_title("Режим"))
	var mode_row := TDUI.hbox(8)
	for id in TDConfig.MODES:
		var def: Dictionary = TDConfig.MODES[id]
		var locked := not TDMeta.mode_unlocked(id)
		var b := _choice(modes, def["name"] + (" · закрыто" if locked else ""), options["mode"] == id, locked, TDMeta.unlock_hint("mode", id))
		var mid: String = id
		b.toggled.connect(func(on: bool):
			if on:
				options["mode"] = mid
				mode_text.text = _mode_info(mid))
		mode_row.add_child(b)
	_content.add_child(mode_row)
	mode_text.text = _mode_info(options["mode"])
	_content.add_child(mode_text)
	_content.add_child(TDUI.section_title("Сложность"))
	var diff_row := TDUI.hbox(8)
	for id in TDConfig.DIFFICULTIES:
		var def: Dictionary = TDConfig.DIFFICULTIES[id]
		var locked := not TDMeta.difficulty_unlocked(id)
		var b := _choice(diffs, def["name"] + (" · закрыто" if locked else ""), options["difficulty"] == id, locked, TDMeta.unlock_hint("difficulty", id))
		var did: String = id
		b.toggled.connect(func(on: bool):
			if on:
				options["difficulty"] = did
				diff_text.text = _diff_info(did))
		diff_row.add_child(b)
	_content.add_child(diff_row)
	diff_text.text = _diff_info(options["difficulty"])
	_content.add_child(diff_text)
	var note := TDUI.para("Карта дня всегда идёт на обычной сложности. Новые карты открываются по мере прохождения: зима, болото, вулкан и подземелье.", 12, Color("#a49476"))
	_content.add_child(note)
	_button("Начать", "play", func():
		if options["mode"] == "daily":
			options["difficulty"] = "normal"
		if has_run:
			confirm("Новая игра", "Текущий забег заменится. Перед этим будет создано автосохранение.", func(): action_requested.emit("new", -1))
		else:
			action_requested.emit("new", -1), true)
	_button("Назад", "help", func(): home(has_run))


func _mode_info(id: String) -> String:
	var text: String = TDConfig.MODES[id]["desc"]
	if id == "daily":
		var best := TDMeta.record_for(TDMeta.daily_seed())
		text += "  Твой рекорд сегодня: %s." % (("волна %d" % best) if best > 0 else "пока нет")
	return text


func _diff_info(id: String) -> String:
	return TDConfig.DIFFICULTIES[id]["desc"]


func achievements_page() -> void:
	page = "achievements"
	_begin("Достижения", 640)
	_content.add_child(TDUI.para("Получено %d из %d. Каждое даёт очки знаний для Мастерской, а некоторые открывают башни и режимы." % [TDMeta.achievements.size(), TDMeta.ACHIEVEMENTS.size()], 13))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 360)
	var list := TDUI.vbox(6)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	_content.add_child(scroll)
	for a in TDMeta.ACHIEVEMENTS:
		var got := TDMeta.has_achievement(a["id"])
		var row := TDUI.hbox(10)
		row.add_child(TDUI.icon(a["icon"], 26, TDUI.GOLD if got else TDUI.MUTED))
		var col := TDUI.vbox(1)
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(TDUI.label(a["name"], 15, TDUI.TEXT if got else TDUI.MUTED, true))
		var line: String = a["desc"]
		if a["unlock"] != "":
			line += " · " + a["unlock"]
		col.add_child(TDUI.para(line, 12, Color("#c7b99e") if got else Color("#8a7d66")))
		row.add_child(col)
		row.add_child(TDUI.label("✓" if got else "+%d" % a["reward"], 15, TDUI.OK if got else TDUI.GOLD, true))
		list.add_child(row)
	_button("Назад", "play", func(): home(has_run))


func confirm(title: String, text: String, callback: Callable) -> void:
	page = "confirm"
	_pending = callback
	_begin(title, 500)
	_content.add_child(TDUI.para(text, 15))
	_button("Подтвердить", "play", func():
		var action := _pending
		if action.is_valid():
			action.call(), true)
	_button("Отмена", "help", func(): home(has_run))

func slots(saving: bool) -> void:
	page = "save" if saving else "load"
	_begin("Сохранить игру" if saving else "Загрузить игру", 600)
	_content.add_child(TDUI.para("Выбери слот. Сохраняется весь забег, включая текущую волну." if saving else "После загрузки игра будет на паузе.", 14))
	for slot in (3 if saving else 4):
		var data := TDSave.read(slot)
		var title := "Слот %d" % (slot + 1) if slot < 3 else "Автосохранение"
		var description := "Пусто"
		if not data.is_empty():
			var state: Dictionary = data["state"]
			description = "%s · волна %d · %d золота\n%s" % [TDEnv.biome_name(data["seed"]), state["wave"], state["gold"], data.get("saved_at", "")]
		elif FileAccess.file_exists(TDSave.path_for(slot)):
			description = "Сохранение недоступно или повреждено"
		var button := _button(title + "\n" + description, "help", func():
			if saving and not data.is_empty():
				confirm("Перезаписать " + title.to_lower() + "?", description, func(): action_requested.emit("save", slot))
			elif not saving and has_run:
				confirm("Загрузить сохранение?", "Текущий забег заменится выбранным сохранением.", func(): action_requested.emit("load", slot))
			else:
				action_requested.emit("save" if saving else "load", slot), false, not saving and data.is_empty())
		button.custom_minimum_size.y = 82
		button.add_theme_font_size_override("font_size", 14)
	_button("Назад", "play", func(): home(has_run))

func settings() -> void:
	page = "settings"
	_display_before = TDDisplay.values.duplicate(true)
	_audio_before = {"master": audio.master_volume, "music": audio.music_volume, "sfx": audio.sfx_volume, "music_on": audio.music_on, "sfx_on": audio.sfx_on}
	_begin("Настройки", 600)
	_content.add_child(TDUI.section_title("Звук"))
	for channel in ["master", "music", "sfx"]:
		var heading := TDUI.hbox()
		heading.add_child(TDUI.label({"master": "Общая громкость", "music": "Музыка", "sfx": "Звуковые эффекты"}[channel], 14))
		heading.add_child(TDUI.spacer())
		var number := TDUI.label("%d%%" % round(audio.get(channel + "_volume") * 100), 14, TDUI.GOLD)
		heading.add_child(number)
		_content.add_child(heading)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.value = audio.get(channel + "_volume") * 100
		slider.custom_minimum_size.y = 22
		slider.value_changed.connect(func(value: float):
			audio.set_volume(channel, value / 100.0)
			number.text = "%d%%" % value)
		_content.add_child(slider)
	var toggles := TDUI.hbox(18)
	for channel in ["music", "sfx"]:
		var toggle := CheckButton.new()
		toggle.text = "Музыка включена" if channel == "music" else "Эффекты включены"
		toggle.button_pressed = audio.get(channel + "_on")
		toggle.toggled.connect(func(on: bool):
			audio.set(channel + "_on", on)
			audio._apply_mutes())
		toggles.add_child(toggle)
	_content.add_child(toggles)
	_content.add_child(TDUI.section_title("Экран"))
	_mode = OptionButton.new()
	_mode.add_item("Оконный режим")
	_mode.add_item("Полноэкранный режим")
	_mode.select(1 if TDDisplay.values["fullscreen"] else 0)
	_setting_row("Режим экрана", _mode)
	_resolution = OptionButton.new()
	_sizes.clear()
	var screen := DisplayServer.screen_get_size(get_window().current_screen)
	for candidate in [Vector2i(1200, 700), Vector2i(1280, 720), Vector2i(1366, 768), Vector2i(1600, 900), Vector2i(1920, 1080), Vector2i(2560, 1440), Vector2i(3840, 2160)]:
		if candidate.x <= screen.x and candidate.y <= screen.y:
			_sizes.append(candidate)
	var current: Vector2i = TDDisplay.values["resolution"]
	if not _sizes.has(current):
		_sizes.append(current)
	for resolution in _sizes:
		_resolution.add_item("%d × %d" % [resolution.x, resolution.y])
	_resolution.select(_sizes.find(current))
	_resolution.disabled = _mode.selected == 1
	_mode.item_selected.connect(func(index: int): _resolution.disabled = index == 1)
	_setting_row("Разрешение окна", _resolution)
	_vsync = CheckButton.new()
	_vsync.text = "Вертикальная синхронизация"
	_vsync.button_pressed = TDDisplay.values["vsync"]
	_content.add_child(_vsync)
	_button("Применить", "upgrade", _apply_settings, true)
	_button("Отмена", "help", _cancel_settings)
	message("Громкость меняется сразу для прослушивания. Изменения сохраняются кнопкой «Применить».")

func _setting_row(text: String, control: Control) -> void:
	var row := TDUI.hbox(12)
	var label := TDUI.label(text, 14)
	label.custom_minimum_size.x = 190
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	control.custom_minimum_size.y = 36
	row.add_child(control)
	_content.add_child(row)

func _apply_settings() -> void:
	var proposed := {"resolution": _sizes[_resolution.selected], "fullscreen": _mode.selected == 1, "vsync": _vsync.button_pressed}
	var video_changed: bool = proposed["resolution"] != _display_before["resolution"] or proposed["fullscreen"] != _display_before["fullscreen"]
	if not video_changed:
		TDDisplay.values = proposed
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if proposed["vsync"] else DisplayServer.VSYNC_DISABLED)
		_commit_settings()
		return
	TDDisplay.apply(get_window(), proposed)
	page = "video_confirm"
	_trial = 15.0
	_begin("Сохранить режим экрана?", 550)
	_countdown = TDUI.para("", 15)
	_content.add_child(_countdown)
	_button("Оставить", "upgrade", func():
		_trial = 0
		_commit_settings(), true)
	_button("Вернуть предыдущий", "help", _cancel_settings)

func _commit_settings() -> void:
	var display_error := TDDisplay.save()
	var sound_error := audio._save_cfg()
	home(has_run)
	message("Настройки сохранены." if display_error == OK and sound_error == OK else "Не удалось записать настройки на диск.", display_error != OK or sound_error != OK)

func _cancel_settings() -> void:
	_trial = 0
	if TDDisplay.values != _display_before:
		TDDisplay.apply(get_window(), _display_before)
	for channel in ["master", "music", "sfx"]:
		audio.set_volume(channel, _audio_before[channel])
	audio.music_on = _audio_before["music_on"]
	audio.sfx_on = _audio_before["sfx_on"]
	audio._apply_mutes()
	home(has_run)

func back() -> void:
	if page in ["settings", "video_confirm"]:
		_cancel_settings()
	elif page != "home":
		home(has_run)
	elif has_run:
		action_requested.emit("continue", -1)

func _process(delta: float) -> void:
	if _trial > 0:
		_trial -= delta
		_countdown.text = "Предыдущий режим вернётся через %d с, если не подтвердить выбор." % ceili(_trial)
		if _trial <= 0:
			_cancel_settings()
