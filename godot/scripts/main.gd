extends Control
## Корневой экран: раскладка и игровой цикл; окна и ввод делегированы ui-контроллерам.
##
## Раскладка: сверху тонкая полоса (TDTopBar), слева док с магазином и инспектором (TDDock),
## всё остальное место занимает поле строго 16:10. Второстепенное (советы, итоги, справка)
## спрятано во всплывающие панели и открывается по запросу.

const FIXED := 1.0 / 60.0
const SETTINGS := "user://settings.cfg"
const DRAWER_W := 444.0
## Рамка вокруг поля в клетках: сверху нужен запас под высокие модели башен.
const FIELD_PAD_X := 0.4
const FIELD_PAD_TOP := 0.85
const FIELD_PAD_BOTTOM := 0.4


var _run_overlays = preload("res://scripts/ui/run_overlays.gd").new(self)
var _workshop = preload("res://scripts/ui/workshop.gd").new(self)
var _help_tutorial = preload("res://scripts/ui/help_tutorial.gd").new(self)
var _wave_report = TDWaveReport.new(self)
var _game_input = preload("res://scripts/ui/game_input.gd").new(self)

var game: TDGame
var seed_v: int = 0
## Выбранный инструмент: тип башни, "sell" или "" — курсор свободный.
var tool: String = ""
var speed: int = 1
var acc: float = 0.0
var tutorial_step: int = -1
var help_open: bool = false
## Пауза по кнопке / клавише P.
var user_paused: bool = false
## Окно «Мастерской» (мета-прогрессия).
var meta_open: bool = false
var meta_modal: Control
## Окно «Волна N пройдена»: снимок отчёта (пусто — закрыто) и баннеры, отложенные до закрытия.
var wave_report_modal: Control
var wave_report: Dictionary = {}
var _banner_queue: Array = []
var victory_overlay: Control
## Показан ли уже экран победы в этом забеге.
var _victory_seen: bool = false
## Что из забега уже переведено в очки знаний (чтобы не начислить дважды).
var _banked_waves: int = 0
var _banked_bosses: int = 0
var _banked_victory: bool = false
var _run_closed: bool = false
var _run_points: int = 0
var _new_record: bool = false
var front: TDFrontMenu
var _run_started := false
var _run_id := ""
var _tutorial_seen := false
var selected_tower: TDGame.Tower = null
var dock_hover: String = ""

var topbar: TDTopBar
var dock: TDDock
var board: TDBoard
var audio: TDAudio
## Параметры текущего забега: "difficulty" и "mode" (хранятся и в game.meta).
var _opts: Dictionary = {"difficulty": "normal", "mode": "standard"}
var ground: TDGround
var stage: Control
var stage_hint: PanelContainer
var pause_lbl: Label
var cursor_tip: PanelContainer
var cursor_lbl: Label
var enemy_tip: PanelContainer
var enemy_tip_box: VBoxContainer
var perk_overlay: Control
var over_overlay: Control
var tutorial_modal: Control
var help_modal: Control
var pop_layer: Control
var pop_catcher: ColorRect
var advice_pop: PanelContainer
var menu_pop: PanelContainer
var drawer: PanelContainer
var drawer_box: VBoxContainer
var _drawer_context: WeakRef
var _drawer_scroll_revision := 0
var _drawer_scroll_pending := false
var _drawer_scroll_target := 0
var _active_pop: PanelContainer = null

var info: Dictionary = {}
var tips: Array = []
var ratings: Dictionary = {}
var coverage: Dictionary = {}
var threat: Dictionary = {}
var recommended: Dictionary = {}

var _refresh_t: float = 0.0
var _dirty: bool = true
var _sigs: Dictionary = {}
var _last_phase: String = "build"

# отладка / проверка (см. _run_demo)
var _demo: bool = false
var _demo_t: float = 0.0
var _shot_path: String = ""
var _demo_len: float = 14.0
var _demo_ui: String = ""
var _skip_to: int = 0
## PRO-152: модель роя для новых забегов этой сессии (`-- --swarm=signature`, см. run_experiment.bat). Пусто — обычная игра.
## Загруженный забег сохраняет свою модель из сохранения.
var _swarm_model: String = ""
var _ptlog: TDPlaytestLog = null
## PRO-115, живые плейтесты (run_playtest.bat): журнал волн и для контрольных забегов без флага, одна карта на все
## новые забеги сессии (A/B на одном сиде), игра без бонусов Мастерской, метка сборки для протокола.
var _playtest: bool = false
var _fixed_seed: int = -1
var _no_workshop: bool = false
var _build: String = ""
## PRO-139: изолированный прототип развилки (`-- --map=fork` или `--map=fork_uneven`, см. run_fork.bat).
## PRO-213, dev-режим генератора развилок: `--map=fork_even` / `--map=fork_skew` (вариант задан) или `--map=forks`
## (вариант по сиду). Только по явному флагу: в обычные забеги эти карты не попадают.
var _map_variant: String = ""


func _ready() -> void:
	theme = TDUI.make_theme()
	get_window().min_size = Vector2i(960, 540)
	randomize()
	seed_v = _pick_seed()
	_parse_args()
	if not _demo:
		var requested_size := get_window().size
		TDDisplay.load_settings(get_window())
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--size="):
				get_window().size = requested_size
				TDDisplay.values["resolution"] = requested_size
	TDMeta.load_meta()
	game = TDGame.new(seed_v, _proto_map(), _game_meta())
	audio = TDAudio.new()
	add_child(audio)
	if _demo:
		audio.sfx_on = false
	else:
		audio.play_music(seed_v % TDAudio.MUSIC.size())
	# щелчок на любой кнопке интерфейса, в том числе созданной позже
	get_tree().node_added.connect(func(n: Node):
		if n is Control:
			TDUI.fit_tooltip.call_deferred(weakref(n))
		if n is BaseButton and not (n as BaseButton).pressed.is_connected(audio.ui_click):
			(n as BaseButton).pressed.connect(audio.ui_click))
	_build_ui()
	board.audio = audio
	board.set_game(game)
	_load_settings()
	_refresh(true)
	front = TDFrontMenu.new()
	add_child(front)
	front.setup(audio)
	front.action_requested.connect(_front_action)
	get_tree().auto_accept_quit = false
	if not _demo:
		_show_front()
	else:
		_run_started = true


## Карта нового забега: null — обычная карта по сиду; с `--map=fork…` — техническая карта прототипа PRO-139,
## с `--map=fork_even|fork_skew|forks` — сгенерированная развилка PRO-213 (волны, гены и перки по сиду не меняются).
func _proto_map() -> TDMap:
	if TDMap.FORK_MAPS.has(_map_variant):
		return TDMap.fork_test(_map_variant)
	if TDMap.is_fork_family(_map_variant):
		return TDMap.generate(seed_v, _map_variant)
	if _map_variant == "forks":
		return TDMap.generate(seed_v, TDMap.fork_family_for(seed_v))
	return null


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			_shot_path = a.substr(7)
			_demo = true
		elif a.begins_with("--seed="):
			seed_v = int(a.substr(7))
		elif a.begins_with("--secs="):
			_demo_len = float(a.substr(7))
		elif a.begins_with("--skip="):
			_skip_to = int(a.substr(7))
		elif a.begins_with("--ui="):
			_demo_ui = a.substr(5)
		elif a == "--demo":
			_demo = true
		elif a.begins_with("--swarm="):
			_swarm_model = a.substr(8)
		elif a == "--playtest":
			_playtest = true
		elif a.begins_with("--fixed-seed="):
			_fixed_seed = int(a.substr(13))
			seed_v = _fixed_seed
		elif a == "--no-workshop":
			_no_workshop = true
		elif a.begins_with("--build="):
			_build = a.substr(8)
		elif a.begins_with("--map="):
			_map_variant = a.substr(6)
		elif a.begins_with("--size="):
			var wh := a.substr(7).split("x")
			get_window().size = Vector2i(int(wh[0]), int(wh[1]))


# ── настройки ─────────────────────────────────────────────────

func _load_settings() -> void:
	var cf := ConfigFile.new()
	var seen := false
	if cf.load(SETTINGS) == OK:
		seen = cf.get_value("game", "tutorial_seen", false)
	_tutorial_seen = seen
	_update_modals()


func _close_tutorial() -> void:
	_help_tutorial._close_tutorial()


func _session_snapshot() -> Dictionary:
	var result := {}
	for key in ["speed", "acc", "user_paused", "_victory_seen", "_banked_waves", "_banked_bosses", "_banked_victory", "_run_closed", "_run_points", "_new_record", "_run_id"]:
		result[key] = get(key)
	return result


func _autosave() -> Error:
	if _demo or not _run_started or game.phase == "over":
		return OK
	return TDSave.write(3, game, _session_snapshot())


func _show_front() -> void:
	wave_report = {}
	_banner_queue = []
	var save_error := _autosave()
	_close_popovers()
	drawer.visible = false
	tutorial_step = -1
	help_open = false
	meta_open = false
	_update_modals()
	board.process_mode = Node.PROCESS_MODE_DISABLED
	audio.stop_effects()
	front.home(_run_started and game.phase != "over")
	if save_error != OK:
		front.message("Не удалось создать автосохранение. Забег остаётся в памяти — можно продолжить.", true)


func _resume_from_front() -> void:
	front.visible = false
	board.process_mode = Node.PROCESS_MODE_INHERIT
	_dirty = true


func _front_action(action: String, slot: int) -> void:
	match action:
		"continue":
			if _run_started and game.phase != "over":
				_resume_from_front()
			elif slot >= 0:
				_load_slot(slot)
		"new":
			if _autosave() != OK:
				front.message("Не удалось сохранить текущий забег. Новая игра не начата.", true)
				return
			_opts = front.options.duplicate()
			_resume_from_front()
			_restart(true)
			_last_phase = "build"
			tool = ""
			board.tool = ""
			if not _demo:
				audio.play_music(seed_v % TDAudio.MUSIC.size())
				if not _tutorial_seen:
					tutorial_step = 0
					_update_modals()
		"save":
			if _demo:
				front.message("Сохранение недоступно в демонстрационном режиме.", true)
				return
			if not _run_started or game.phase == "over" or slot not in [0, 1, 2]:
				front.message("Нет активного забега для сохранения.", true)
				return
			var error := TDSave.write(slot, game, _session_snapshot())
			if error == OK:
				front.home(true, "Игра сохранена в слот %d." % (slot + 1))
			else:
				front.message("Не удалось записать сохранение. Проверь свободное место и доступ к папке игры.", true)
		"load":
			_load_slot(slot)
		"quit":
			if front.page in ["settings", "video_confirm"]:
				front._cancel_settings()
			if _autosave() != OK:
				board.process_mode = Node.PROCESS_MODE_DISABLED
				front.visible = true
				front.has_run = _run_started and game.phase != "over"
				front.confirm("Сохранение не удалось", "Забег остаётся в памяти. Можно отменить выход, повторить сохранение или выйти без сохранения.", func(): _front_action("quit", -1))
				front._button("Выйти без сохранения", "sell", func(): get_tree().quit())
				return
			get_tree().quit()


func _load_slot(slot: int) -> bool:
	var data := TDSave.read(slot)
	var restored := TDSave.restore(data)
	if restored == null:
		front.message("Не удалось загрузить сохранение. Текущий забег не изменён.", true)
		return false
	game = restored
	_opts = {"difficulty": game.difficulty_id(), "mode": game.mode_id()}
	seed_v = game.seed_value
	var session: Dictionary = data["session"]
	for key in ["speed", "acc", "_victory_seen", "_banked_waves", "_banked_bosses", "_banked_victory", "_run_closed", "_run_points", "_new_record", "_run_id"]:
		if session.has(key):
			set(key, session[key])
	speed = int(speed) if speed in [1, 2, 4] else 1
	acc = clampf(acc, 0, FIXED)
	_run_started = true
	if _run_id == "":
		_run_id = str(Time.get_unix_time_from_system()) + "-" + str(randi())
	selected_tower = null
	dock_hover = ""
	tool = ""
	board.tool = ""
	board.set_game(game)
	_last_phase = game.phase
	_sigs.clear()
	user_paused = true
	topbar.set_paused(true)
	pause_lbl.visible = true
	victory_overlay.visible = false
	wave_report = {}
	_banner_queue = []
	_update_modals()
	_resume_from_front()
	_refresh(true)
	if not _demo:
		audio.play_music(seed_v % TDAudio.MUSIC.size())
	_flash_hint("Игра загружена. P — продолжить")
	return true


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and front != null:
		_front_action("quit", -1)


# ── построение интерфейса ─────────────────────────────────────

func _btn(text: String = "", icon_name: String = "") -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(40, 40)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if icon_name != "":
		b.icon = TDIcons.tex(icon_name)
		b.expand_icon = true
	return b


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = TDUI.BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var grad := Gradient.new()
	grad.set_color(0, Color("#393127"))
	grad.set_color(1, Color("#15130f"))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.35, 0.3)
	gt.fill_to = Vector2(1.0, 1.0)
	gt.width = 256
	gt.height = 256
	var glow := TextureRect.new()
	glow.texture = gt
	glow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 8)
	add_child(margin)
	var col := TDUI.vbox(8)
	margin.add_child(col)

	topbar = TDTopBar.new()
	col.add_child(topbar)
	topbar.setup()
	topbar.go_pressed.connect(_start_wave)
	topbar.speed_selected.connect(_set_speed)
	topbar.advice_pressed.connect(_toggle_advice)
	topbar.menu_pressed.connect(_toggle_menu)
	topbar.pause_pressed.connect(_toggle_pause)

	var row := TDUI.hbox(8)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(row)
	dock = TDDock.new()
	row.add_child(dock)
	dock.setup()
	dock.tool_selected.connect(_toggle_tool)
	dock.sell_tool_selected.connect(_set_tool.bind("sell"))
	dock.sell_tower_requested.connect(_sell_selected)
	dock.upgrade_requested.connect(_upgrade_selected)
	dock.mode_requested.connect(_set_mode)
	dock.tile_hovered.connect(func(k: String): dock_hover = k)

	# поле всегда 16:10: контейнер держит пропорции, клетки остаются квадратными
	var arc := AspectRatioContainer.new()
	arc.ratio = (TDConfig.COLS + 2.0 * FIELD_PAD_X) / (TDConfig.ROWS + FIELD_PAD_TOP + FIELD_PAD_BOTTOM)
	arc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	arc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(arc)
	stage = Control.new()
	stage.custom_minimum_size = Vector2(240, 160)
	stage.clip_contents = true
	arc.add_child(stage)
	# рамка вокруг поля: портал, замок и крайние башни не обрезаются краем
	var frame := Panel.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_theme_stylebox_override("panel", TDUI.skin("inset", 0))
	stage.add_child(frame)
	ground = TDGround.new()
	stage.add_child(ground)
	board = TDBoard.new()
	# Арт высоких башен может выступать за край клеточного поля в запас рамки;
	# родительская stage всё ещё обрезает отрисовку по внешнему контуру.
	board.clip_contents = false
	board.ground = ground
	board.cell_clicked.connect(_on_cell_clicked)
	stage.add_child(board)

	stage.resized.connect(_layout_field)
	_build_stage_widgets()
	pause_lbl = TDUI.label("ПАУЗА  ·  P — продолжить", 26, Color("#ffd27a"), true)
	pause_lbl.add_theme_constant_override("outline_size", 8)
	pause_lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	pause_lbl.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24)
	pause_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_lbl.visible = false
	stage.add_child(pause_lbl)
	perk_overlay = _make_overlay()
	over_overlay = _make_overlay()
	victory_overlay = _make_overlay()

	# слой поповеров и выезжающей панели
	pop_layer = Control.new()
	pop_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	pop_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pop_layer)
	pop_catcher = ColorRect.new()
	pop_catcher.color = Color(0, 0, 0, 0)
	pop_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	pop_catcher.visible = false
	pop_catcher.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed:
			_close_popovers())
	pop_layer.add_child(pop_catcher)
	advice_pop = _make_popover(430.0)
	menu_pop = _make_popover(300.0)
	_build_menu()
	_build_drawer()

	tutorial_modal = _make_modal_root()
	help_modal = _make_modal_root()
	meta_modal = _make_modal_root()
	wave_report_modal = _make_modal_root()
	resized.connect(_resize_surfaces)
	topbar.resized.connect(_resize_surfaces)


func _resize_surfaces() -> void:
	if drawer == null: return
	_place_drawer()
	if not wave_report.is_empty(): _wave_report.build()
	if _active_pop != null:
		var anchor: Control = topbar.advice_btn if _active_pop == advice_pop else topbar.menu_btn
		_layout_popover(_active_pop, anchor)


func _build_stage_widgets() -> void:
	# подсказка для пустого поля
	stage_hint = TDUI.panel(Color(0.05, 0.07, 0.11, 0.82), Color("#806440"), 12, 12)
	var hh := TDUI.hbox(10)
	hh.add_child(TDUI.icon("info", 18, TDUI.ACCENT))
	hh.add_child(TDUI.para("Выбери башню слева, затем свободную клетку рядом с дорогой", 14, TDUI.TEXT))
	stage_hint.custom_minimum_size.x = 280
	stage_hint.add_child(hh)
	stage_hint.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 16)
	stage_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(stage_hint)
	# подсказка у курсора: цена или причина отказа
	cursor_tip = TDUI.panel(Color(0.05, 0.07, 0.11, 0.9), Color("#806440"), 8, 8)
	cursor_lbl = TDUI.label("", 13, TDUI.GOLD, true)
	cursor_tip.add_child(cursor_lbl)
	cursor_tip.visible = false
	cursor_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(cursor_tip)
	# карточка врага у курсора
	enemy_tip = TDUI.panel(Color(0.06, 0.08, 0.13, 0.94), Color("#9b7b49"), 12, 12)
	enemy_tip.custom_minimum_size = Vector2(250, 0)
	enemy_tip_box = TDUI.vbox(7)
	enemy_tip.add_child(enemy_tip_box)
	enemy_tip.visible = false
	enemy_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(enemy_tip)


func _make_overlay() -> Control:
	var o := ColorRect.new()
	o.color = Color(0.03, 0.05, 0.09, 0.82)
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.visible = false
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(o)
	return o


func _make_modal_root() -> Control:
	var o := ColorRect.new()
	o.color = Color(0.02, 0.03, 0.06, 0.78)
	o.set_anchors_preset(Control.PRESET_FULL_RECT)
	o.visible = false
	o.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(o)
	return o


func _make_popover(width: float) -> PanelContainer:
	var surface := TDModalSurface.new(width, 14)
	surface.viewport_margin = Vector2(32, 160)
	surface.visible = false
	pop_layer.add_child(surface)
	return surface


func _build_menu() -> void:
	var v := TDUI.vbox(6)
	_popover_content(menu_pop, v)
	var items := [
		["Главное меню", "Esc", "menu", func(): _show_front()],
		["Сохранить игру", "", "info", func(): _show_front(); front.slots(true)],
		["Загрузить игру", "", "help", func(): _show_front(); front.slots(false)],
		["Настройки", "", "menu", func(): _show_front(); front.settings()],
		["Как играть", "H", "help", func(): _open_help()],
		["Рой и итоги", "Tab", "wave", func(): _toggle_drawer()],
		["Мастерская", "M", "upgrade", func(): _open_meta()],
	]
	for it in items:
		var b := _btn("", it[2])
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 38)
		b.add_theme_stylebox_override("normal", TDUI.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 8, 10))
		var h := TDUI.hbox(8)
		h.set_anchors_preset(Control.PRESET_FULL_RECT)
		h.offset_left = 40
		h.offset_right = -10
		h.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(TDUI.label(it[0], 14, TDUI.TEXT))
		h.add_child(TDUI.spacer())
		h.add_child(TDUI.label(it[1], 11, TDUI.MUTED, true))
		b.add_child(h)
		var act: Callable = it[3]
		b.pressed.connect(func():
			_close_popovers()
			act.call())
		v.add_child(b)
	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 10)
	v.add_child(sep)
	v.add_child(TDUI.para("Иконки: game-icons.net, CC BY 3.0", 11, Color("#a49476")))


func _build_drawer() -> void:
	drawer = TDUI.panel(Color("#252018"), Color("#806440"), 14, 12, 1)
	var st: StyleBoxFlat = drawer.get_theme_stylebox("panel")
	st.shadow_size = 24
	st.shadow_color = Color(0, 0, 0, 0.55)
	drawer.visible = false
	drawer.add_theme_stylebox_override("panel", TDUI.skin("frame", 14))
	pop_layer.add_child(drawer)
	var v := TDUI.vbox(8)
	drawer.add_child(v)
	var head := TDUI.hbox(8)
	head.add_child(TDUI.label("Рой и итоги", 17, TDUI.TEXT, true))
	head.add_child(TDUI.spacer())
	head.add_child(TDUI.label("Tab", 11, TDUI.MUTED, true))
	var x := _btn("", "close")
	x.name = "DrawerClose"
	x.flat = true
	x.custom_minimum_size = Vector2(40, 40)
	x.pressed.connect(_toggle_drawer)
	head.add_child(x)
	v.add_child(head)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sc)
	drawer_box = TDUI.vbox(10)
	drawer_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(drawer_box)


# ── поповеры ──────────────────────────────────────────────────

func _popover_content(p: PanelContainer, content: Control) -> void:
	var surface := p as TDModalSurface
	TDUI.clear(surface.content)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	surface.content.add_child(content)
	surface.schedule_fit()


func _show_popover(p: PanelContainer, anchor: Control) -> void:
	_close_popovers()
	_active_pop = p
	pop_catcher.visible = true
	p.visible = true
	_layout_popover(p, anchor)


func _layout_popover(p: PanelContainer, anchor: Control) -> void:
	var surface := p as TDModalSurface
	# Advice belongs to the field side of the HUD: never cover the tower inspector/actions.
	var left := dock.get_global_rect().end.x + 12.0 if p == advice_pop else 16.0
	surface.viewport_margin = Vector2(left + 16.0, topbar.size.y + 64.0)
	surface.schedule_fit()
	await get_tree().process_frame
	await get_tree().process_frame
	if not p.visible or _active_pop != p: return
	p.reset_size()
	p.position = Vector2(clampf(anchor.global_position.x + anchor.size.x - p.size.x, left, size.x - p.size.x - 16), topbar.global_position.y + topbar.size.y + 8)


func _close_popovers() -> void:
	pop_catcher.visible = false
	if _active_pop != null:
		_active_pop.visible = false
	_active_pop = null


func _toggle_advice() -> void:
	if _active_pop == advice_pop:
		_close_popovers()
		return
	_build_advice()
	_show_popover(advice_pop, topbar.advice_btn)


func _toggle_menu() -> void:
	if _active_pop == menu_pop:
		_close_popovers()
		return
	_show_popover(menu_pop, topbar.menu_btn)


func _build_advice() -> void:
	_popover_content(advice_pop, TDPanels.advice(game, tips, func(k: String):
		_set_tool(k)
		_close_popovers()))
	advice_pop.reset_size()
	advice_pop.call_deferred("reset_size")


func _toggle_drawer() -> void:
	drawer.visible = not drawer.visible
	_sigs["drawer"] = ""
	_place_drawer()
	if drawer.visible:
		_build_drawer_content()
		drawer.find_child("DrawerClose", true, false).grab_focus()


func _place_drawer() -> void:
	var room := size - Vector2(32, topbar.size.y + 40)
	drawer.custom_minimum_size = Vector2(minf(DRAWER_W, room.x), maxf(120, room.y))
	drawer.size = drawer.custom_minimum_size
	drawer.position = Vector2(size.x - drawer.size.x - 16, topbar.position.y + topbar.size.y + 12)


func _on_lure(gene: String) -> void:
	if game.buy_lure(gene):
		_sigs.clear()
		_dirty = true
		_build_drawer_content()


func _on_vaccine(gene: String) -> void:
	if game.buy_vaccine(gene):
		_sigs.clear()
		_dirty = true
		_build_drawer_content()


func _build_drawer_content() -> void:
	var scroll := drawer_box.get_parent() as ScrollContainer
	var changed_run: bool = _drawer_context == null or _drawer_context.get_ref() != game
	_drawer_context = weakref(game)
	if changed_run:
		_drawer_scroll_target = 0
		scroll.scroll_vertical = 0
	elif not _drawer_scroll_pending:
		_drawer_scroll_target = scroll.scroll_vertical
	_drawer_scroll_revision += 1
	_drawer_scroll_pending = true
	TDUI.clear(drawer_box)
	drawer_box.add_child(TDPanels.swarm(game, _on_vaccine, _on_lure, _set_tool))
	_restore_drawer_scroll(_drawer_scroll_revision)


func _restore_drawer_scroll(revision: int) -> void:
	# Container layout may clamp its old range while the replacement content is measured.
	await get_tree().process_frame
	await get_tree().process_frame
	if revision != _drawer_scroll_revision: return
	(drawer_box.get_parent() as ScrollContainer).scroll_vertical = _drawer_scroll_target
	_drawer_scroll_pending = false


# ── ввод ──────────────────────────────────────────────────────

## Поле внутри сцены: квадратные клетки, увеличенный запас сверху для высоких башен.
func _layout_field() -> void:
	var cols_with_pad := TDConfig.COLS + 2.0 * FIELD_PAD_X
	var rows_with_pad := TDConfig.ROWS + FIELD_PAD_TOP + FIELD_PAD_BOTTOM
	var cs := minf(stage.size.x / cols_with_pad, stage.size.y / rows_with_pad)
	var off := Vector2(FIELD_PAD_X, FIELD_PAD_TOP) * cs
	var sz := Vector2(TDConfig.COLS, TDConfig.ROWS) * cs
	board.base_pos = off
	board.position = off
	board.size = sz
	ground.position = off
	ground.size = sz


func _set_tool(t: String) -> void:
	tool = t
	board.tool = t
	if t != "sell":
		selected_tower = null
	_dirty = true


## Повторный выбор той же башни снимает инструмент.
func _toggle_tool(t: String) -> void:
	if t != "sell" and game.is_locked(t):
		audio.ui_error()
		return
	_set_tool("" if tool == t else t)


func _cycle_tool(dir: int) -> void:
	_game_input._cycle_tool(dir)


func _set_speed(s: int) -> void:
	speed = s
	_dirty = true


func _cycle_speed() -> void:
	_set_speed(2 if speed == 1 else (4 if speed == 2 else 1))


func _start_wave() -> void:
	if not wave_report.is_empty():
		return
	game.start_wave()
	_dirty = true


func _sell_selected() -> void:
	if selected_tower != null and game.towers.has(selected_tower):
		game.sell_tower(selected_tower.x, selected_tower.y)
	selected_tower = null
	_dirty = true


func _upgrade_selected(branch: String = "") -> void:
	if selected_tower == null or not game.towers.has(selected_tower):
		return
	if selected_tower.level == 2 and branch == "":
		_flash_hint("Выбери ветку улучшения в карточке башни (Z / C)")
		return
	if not game.upgrade_tower(selected_tower, branch):
		if game.upgrade_cost(selected_tower) > game.gold:
			_flash_hint("Не хватает золота")
	_dirty = true


func _set_mode(mode: String) -> void:
	if selected_tower != null:
		game.set_mode(selected_tower, mode)
		_dirty = true


func _cycle_mode() -> void:
	if selected_tower == null:
		return
	var ids: Array = []
	for m in TDConfig.TARGET_MODES:
		if m["id"] != "fresh" or TDConfig.has_status_effect(selected_tower.def):
			ids.append(m["id"])
	var i := ids.find(selected_tower.mode)
	_set_mode(ids[(i + 1) % ids.size()])


func _toggle_pause() -> void:
	user_paused = not user_paused
	topbar.set_paused(user_paused)
	pause_lbl.visible = user_paused
	_dirty = true


## Короткое сообщение над полем.
func _flash_hint(text: String) -> void:
	var l := TDUI.label(text, 16, Color.WHITE, true)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.set_anchors_preset(Control.PRESET_CENTER_TOP)
	l.position = Vector2(stage.size.x * 0.5 - 200.0, 18.0)
	l.custom_minimum_size = Vector2(400, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stage.add_child(l)
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(l, "modulate:a", 0.0, 0.4)
	tw.tween_callback(l.queue_free)


func _blocked() -> bool:
	return (front != null and front.visible) or tutorial_step >= 0 or help_open or meta_open or victory_overlay.visible or not game.offer.is_empty() or not wave_report.is_empty()


func _on_cell_clicked(c: Vector2i, button: int) -> void:
	_game_input._on_cell_clicked(c, button)


func _pick_perk(id: String) -> void:
	game.choose_perk(id)
	_dirty = true


## Карта забега: в режиме «Карта дня» — одна на всех, иначе случайная из открытых биомов.
func _pick_seed() -> int:
	if _fixed_seed >= 0:
		return _fixed_seed
	TDMeta.load_meta()
	if _opts.get("mode", "standard") == "daily":
		return TDMeta.daily_seed()
	var s := randi() % 1000000
	if _demo:
		return s
	for _i in 60:
		if TDMeta.biome_unlocked(TDEnv.biome_of_seed(s)):
			break
		s = randi() % 1000000
	return s


## Всё, что симуляция должна знать о забеге: бонусы Мастерской, сложность, режим, закрытые башни.
func _game_meta() -> Dictionary:
	var m := _meta_bonus()
	m["difficulty"] = _opts.get("difficulty", "normal")
	m["mode"] = _opts.get("mode", "standard")
	if not _demo:
		m["locked"] = TDMeta.locked_towers()
	if _swarm_model != "":
		m["swarm_model"] = _swarm_model
	return m


## Бонусы Мастерской; в режиме автопроверки — без них, чтобы скриншоты были одинаковыми.
func _meta_bonus() -> Dictionary:
	return {} if _demo or _no_workshop else TDMeta.bonuses()


## Переводит прогресс забега в очки знаний. final — забег окончен (поражение или рестарт).
func _bank(final: bool) -> void:
	if _demo or _run_closed:
		return
	var survived: int = game.wave - 1
	var award := TDMeta.claim_run(_run_id, seed_v, survived, game.bosses_killed, game.victory, final, float(TDConfig.difficulty(game.meta)["points"]), game.map)
	_run_points += award["total"]
	if award["record"]:
		_new_record = true
	_banked_waves = survived
	_banked_bosses = game.bosses_killed
	_banked_victory = game.victory
	if final:
		_run_closed = true
	TDMeta.save_meta()


func _restart(new_map: bool) -> void:
	if game.wave > 1:
		_bank(true)
	if new_map:
		seed_v = _pick_seed()
	game = TDGame.new(seed_v, _proto_map(), _game_meta())
	_run_started = true
	_run_id = str(Time.get_unix_time_from_system()) + "-" + str(randi())
	_victory_seen = false
	_banked_waves = 0
	_banked_bosses = 0
	_banked_victory = false
	_run_closed = false
	_run_points = 0
	_new_record = false
	user_paused = false
	topbar.set_paused(false)
	pause_lbl.visible = false
	wave_report = {}
	_banner_queue = []
	_update_modals()
	board.set_game(game)
	selected_tower = null
	acc = 0.0
	_sigs.clear()
	_dirty = true
	if drawer.visible:
		_build_drawer_content()


func _open_help() -> void:
	_help_tutorial._open_help()


func _close_help() -> void:
	_help_tutorial._close_help()


func _input(ev: InputEvent) -> void:
	_game_input._input(ev)


func _process(delta: float) -> void:
	if front != null and front.visible:
		if _demo:
			_run_demo(delta)
		return
	var paused := tutorial_step >= 0 or help_open or user_paused or meta_open or _active_pop == menu_pop or victory_overlay.visible or not wave_report.is_empty()
	if not paused:
		acc = minf(0.5, acc + minf(delta, 0.1) * speed)
		while acc >= FIXED:
			game.step(FIXED)
			acc -= FIXED
	if selected_tower != null and not game.towers.has(selected_tower):
		selected_tower = null
	board.selected = selected_tower
	_refresh_t += delta
	if _refresh_t >= 0.12 or _dirty:
		_refresh_t = 0.0
		_dirty = false
		_refresh(false)
	_watch_phase()
	_update_hover_widgets()
	if drawer.visible:
		_place_drawer()
	if _demo:
		_run_demo(delta)


func _sig_changed(key: String, value: String) -> bool:
	if _sigs.get(key, "") == value:
		return false
	_sigs[key] = value
	return true


func _refresh(_force: bool) -> void:
	info = TDAdvisor.wave_info(game)
	tips = TDAdvisor.advice(game, info)
	ratings = TDAdvisor.rate_towers(game, info)
	coverage = TDAdvisor.road_coverage(game)
	threat = TDAdvisor.next_threat(game)
	recommended = {}
	for t in tips:
		for k in t["towers"]:
			recommended[k] = true
	topbar.update(game, info, threat, coverage, tips, speed)
	dock.refresh(game, ratings, recommended, tool)
	dock.inspect(game, _inspect_target(), ratings)
	if _active_pop == advice_pop:
		if _sig_changed("advice_pop", "%d|%s|%d" % [game.wave, game.phase, game.towers.size()]):
			_build_advice()
	if drawer.visible:
		if _sig_changed("drawer", "%d|%d|%d|%d|%s|%d|%s|%s|%d" % [game.reports.size(), game.wave, game.perks.size(), game.gold, str(game.vaccine), game.vaccine_cd, game.phase, str(game.lure), game.lure_cd]):
			_build_drawer_content()
	_update_overlays()
	stage_hint.visible = game.towers.is_empty() and game.phase == "build" and game.offer.is_empty()


func _inspect_target() -> Dictionary:
	if dock_hover != "":
		return {"kind": dock_hover}
	var h := board.hover_cell
	if h.x >= 0:
		var t := game.tower_at(h.x, h.y)
		if t != null:
			return {"tower": t}
	if selected_tower != null:
		return {"tower": selected_tower}
	return {"kind": tool if tool != "sell" and tool != "" else TDConfig.TOWER_KINDS[0]}


## Баннеры начала и конца волны.
func _watch_phase() -> void:
	if game.phase == _last_phase:
		return
	if game.phase == "wave":
		audio.wave_started(not game.pending_boss.is_empty())
		if not game.pending_boss.is_empty():
			var ab: Dictionary = TDConfig.BOSS_ABILITIES[TDConfig.boss_ability(game.wave)]
			_banner("БОСС · " + ab["name"], ab["desc"], Color("#ff6b7a"))
		elif game.cur_special != "":
			var sp: Dictionary = TDConfig.SPECIAL_WAVES[game.cur_special]
			_banner("Волна %d: %s" % [game.wave, sp["name"]], sp["desc"], Color("#ffb347"))
		else:
			_banner("Волна %d" % game.wave, "%d врагов" % game.wave_genomes.size() + _strain_banner(), TDUI.TEXT)
		_playtest_log("start")
	elif game.phase == "build" and _last_phase == "wave":
		# итог волны и объяснения адаптации: постоянное окно с кнопкой «ОК», а не баннер; в демо-режиме не нужно
		if not _demo and game.phase == "build":
			_wave_report.open(TDWaveReport.snapshot(game))
		_playtest_log("end")
		_check_achievements()
	if game.phase == "over":
		_playtest_log("over")
		if not game.victory:
			audio.defeat()
		_check_achievements()
	_last_phase = game.phase


## PRO-152: состав пакетов роя в баннере начала волны ("" — без флага эксперимента или без пакетов).
func _strain_banner() -> String:
	if not game.strains_on():
		return ""
	var n := {}
	for ge in game.wave_genomes:
		var s := String(ge.get("strain", ""))
		if s != "":
			n[s] = int(n.get(s, 0)) + 1
	var parts: Array[String] = []
	for p in TDStrains.PACKAGES:
		if n.has(p):
			parts.append("%s: %s" % [TDStrains.PACK[p]["name"], TDThreats.strain_count_text(p, n[p])])
	return "" if parts.is_empty() else " · " + ", ".join(parts)


## PRO-152, только демо-кадры: включить эксперимент; выводок в ближайшей волне (оборона на снайперах),
## панцирники отступают (раньше оборона держалась на лучниках).
func _demo_force_strains() -> void:
	game.meta["swarm_model"] = TDStrains.MODEL
	var st := TDStrains.new_state()
	st["sig"] = {"del": {"burst": 0.62, "rapid": 0.27, "area": 0.06, "chain": 0.02, "dot": 0.03},
		"el": {"physical": 0.9, "fire": 0.04, "frost": 0.03, "poison": 0.03, "shock": 0.0},
		"rng": {"near": 0.2, "mid": 0.3, "far": 0.5}, "tgt": {"ground": 0.9, "air": 0.1},
		"burst": 0.62, "rapid": 0.27, "chill": 0.48, "control": 0.12, "air_gap": 0.18}
	st["n"] = game.wave
	st["pk"]["brood"] = {"inc": 1.4, "share": 0.3, "phase": "active", "appear": game.wave, "since": game.wave}
	st["pk"]["hulk"] = {"inc": 0.32, "share": 0.1, "phase": "fading", "appear": game.wave - 5, "since": game.wave - 5}
	st["last"] = {"wave": game.wave - 1, "kind_burst": {"sniper": 900.0, "net": 30.0}, "kind_rapid": {"arrow": 400.0}, "kind": {}, "had_damage": true}
	game.strains = st
	game.strain_acc = TDStrains.new_acc()
	if not game.reports.is_empty():
		game.reports[game.reports.size() - 1]["strains"] = TDStrains.report(st)
	game.upcoming = TDStrains.assign(game.upcoming, st, game.wave)


## PRO-191, только демо-кадры: состояние роя из TDEvoFixtures и нужное окно.
## `evo:<имя>` — отчёт о волне, `evo:<имя>:swarm` — панель «Рой», `evo:<имя>:over` — итоги поражения,
## `evo:<имя>:advice` — советы, `evo:<имя>:wave` — та же волна в бою.
func _demo_evo(spec: String) -> void:
	var parts := spec.split(":")
	game = TDEvoFixtures.build(parts[0])
	board.set_game(game)
	selected_tower = null
	_sigs.clear()
	var view: String = parts[1] if parts.size() > 1 else "report"
	match view:
		"swarm":
			_toggle_drawer()
		"over":
			pass
		"advice":
			_toggle_advice()
		"wave":
			game.start_wave()
		_:
			_wave_report.open(TDWaveReport.snapshot(game))
	_dirty = true


## PRO-152/115: журнал живого плейтеста — забеги с флагом эксперимента или любые при `--playtest` (контроль без флага).
func _playtest_log(event: String) -> void:
	if _demo or not (game.strains_on() or _playtest):
		return
	if _ptlog == null or not _ptlog.path.contains(_run_id.replace(":", "-")):
		_ptlog = TDPlaytestLog.new(_run_id if _run_id != "" else "run-%d" % seed_v)
		_ptlog.header(game, {"build": _build if _build != "" else "unknown", "fixed_seed": _fixed_seed, "workshop": not _no_workshop,
			"window": "%dx%d" % [get_window().size.x, get_window().size.y]})
	match event:
		"start":
			_ptlog.wave_started(game)
		"end":
			_ptlog.wave_ended(game)
		"over":
			_ptlog.run_over(game)


## Достижения проверяются в конце каждой волны и в конце забега.
func _check_achievements() -> void:
	if _demo:
		return
	var fresh := TDMeta.evaluate(game)
	if fresh.is_empty():
		return
	var names: Array[String] = []
	var reward := 0
	var unlocks: Array[String] = []
	for a in fresh:
		names.append(a["name"])
		reward += int(a["reward"])
		if a["unlock"] != "":
			unlocks.append(a["unlock"])
	audio.play("upgrade", -3.0, 0.5)
	var sub := ", ".join(names) + " · +%d очков знаний" % reward
	if not unlocks.is_empty():
		sub += "
" + " · ".join(unlocks)
	_banner("Достижение!", sub, TDUI.GOLD)


func _banner(text: String, sub: String, color: Color) -> void:
	# пока открыто окно отчёта о волне, короткие баннеры ждут его закрытия, а не прячутся под затемнением
	if not wave_report.is_empty():
		_banner_queue.append([text, sub, color])
		return
	_run_overlays._banner(text, sub, color)


func _open_wave_report(snap: Dictionary) -> void:
	_wave_report.open(snap)


func _close_wave_report() -> void:
	_wave_report.close()


func _fit_wave_report(fit: Callable) -> void:
	fit.call()
	call_deferred("_fit_wave_report_once", fit)


func _fit_wave_report_once(fit: Callable) -> void:
	fit.call()


func _update_hover_widgets() -> void:
	var cs := board.cell_size()
	var mouse := board.base_pos + board.hover_pos * cs
	var e := board.hovered_enemy
	var blocked := _blocked()

	# карточка врага
	if e != null and not blocked:
		var st := TDGame.status_of(e)
		var sig := "%d|%d|%d|%s%s%s|%d" % [e.id, int(ceil(e.hp)), int(ceil(e.shield)), st["chilled"], st["scorched"], st["poisoned"], game.towers.size()]
		if _sig_changed("enemy_tip", sig):
			TDUI.clear(enemy_tip_box)
			enemy_tip_box.add_child(TDPanels.enemy_tip(game, e))
			enemy_tip.reset_size()
		enemy_tip.visible = true
		var sz := enemy_tip.get_combined_minimum_size()
		var pos := mouse + Vector2(22, 14)
		if pos.x + sz.x > stage.size.x - 6:
			pos.x = mouse.x - sz.x - 22
		pos.y = clampf(pos.y, 6.0, maxf(6.0, stage.size.y - sz.y - 6.0))
		enemy_tip.position = pos
	else:
		enemy_tip.visible = false
		_sigs["enemy_tip"] = ""

	# цена или причина отказа
	var h := board.hover_cell
	var show_cursor := false
	if h.x >= 0 and e == null and not blocked and tool != "sell" and tool != "":
		if game.tower_at(h.x, h.y) == null:
			var problem := game.place_problem(tool, h.x, h.y)
			show_cursor = true
			if problem != "":
				cursor_lbl.text = problem
				cursor_lbl.add_theme_color_override("font_color", TDUI.BAD)
			else:
				cursor_lbl.text = "−%d" % game.tower_cost(tool)
				cursor_lbl.add_theme_color_override("font_color", TDUI.GOLD)
	elif h.x >= 0 and e == null and not blocked and tool == "sell":
		var t := game.tower_at(h.x, h.y)
		if t != null:
			show_cursor = true
			cursor_lbl.text = "+%d" % game.sell_value(t)
			cursor_lbl.add_theme_color_override("font_color", TDUI.OK)
	cursor_tip.visible = show_cursor
	if show_cursor:
		cursor_tip.reset_size()
		var csz := cursor_tip.get_combined_minimum_size()
		var cp := mouse + Vector2(16, 20)
		if cp.x + csz.x > stage.size.x - 4:
			cp.x = mouse.x - csz.x - 12
		if cp.y + csz.y > stage.size.y - 4:
			cp.y = mouse.y - csz.y - 12
		cursor_tip.position = cp


# ── оверлеи и модальные окна ──────────────────────────────────

func _update_overlays() -> void:
	_run_overlays._update_overlays()


func _center_in(parent: Control, content: Control) -> void:
	_run_overlays._center_in(parent, content)


func _build_perk_overlay() -> void:
	_run_overlays._build_perk_overlay()


func _build_summary(parent: Control, won: bool) -> void:
	_run_overlays._build_summary(parent, won)


func _dock_width_test() -> void:
	var widths := {}
	for k in TDConfig.TOWER_KINDS:
		dock_hover = k
		_dirty = true
		await get_tree().process_frame
		await get_tree().process_frame
		widths[k] = dock.size.x
	dock_hover = ""
	game.gold += 5000
	for t in game.towers:
		selected_tower = t
		game.upgrade_tower(t)
		for step in 2:
			_dirty = true
			await get_tree().process_frame
			await get_tree().process_frame
			widths["%s ур.%d" % [t.kind, t.level]] = dock.size.x
			game.upgrade_tower(t, "a" if t.id % 2 == 0 else "b")
	var mn := INF
	var mx := 0.0
	for k in widths:
		mn = minf(mn, widths[k])
		mx = maxf(mx, widths[k])
	print("dock widths: min=%.1f max=%.1f %s" % [mn, mx, "OK" if mx - mn < 0.5 else "ПРЫГАЕТ " + str(widths)])


func _continue_endless() -> void:
	_victory_seen = true
	_dirty = true


# ── Мастерская ────────────────────────────────────────────────

func _open_meta() -> void:
	_workshop._open_meta()


func _close_meta() -> void:
	_workshop._close_meta()


func _buy_meta(id: String) -> void:
	_workshop._buy_meta(id)


func _build_meta() -> void:
	_workshop._build_meta()


func _update_modals() -> void:
	_help_tutorial._update_modals()


func _dialog(parent: Control, width: float) -> VBoxContainer:
	return _help_tutorial._dialog(parent, width)


func _build_tutorial() -> void:
	_help_tutorial._build_tutorial()


func _help_row(icon_name: String, color: Color, title: String, sub: String, text: String, isize: float = 30.0) -> HBoxContainer:
	return _help_tutorial._help_row(icon_name, color, title, sub, text, isize)


func _build_help() -> void:
	_help_tutorial._build_help()


func _run_demo(delta: float) -> void:
	_demo_t += delta
	if _demo_t > 0.3 and game.towers.is_empty():
		var cycle := ["arrow", "frost", "ember", "cannon", "sniper", "poison", "beacon", "arrow", "net", "flak"]
		var cells := []
		for ci in range(10, game.map.order.size(), 3):
			var c: Vector2i = game.map.order[ci]
			for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
				var n: Vector2i = c + d
				if n.x >= 0 and n.y >= 0 and n.x < TDConfig.COLS and n.y < TDConfig.ROWS and not game.map.cells.has(n) and not game.map.blocked.has(n) and not cells.has(n):
					cells.append(n)
		game.gold = 900
		var i := 0
		for n in cells:
			if i >= 11:
				break
			if i % 2 == 0 or i > 6:
				game.place_tower(cycle[i % cycle.size()], n.x, n.y)
				i += 1
			else:
				i += 1
		game.lives = 999
		while game.wave < _skip_to and game.phase != "over":
			if game.phase == "build":
				if not game.offer.is_empty():
					game.choose_perk(game.offer[0])
				game.gold += 300
				game.start_wave()
			game.step(1.0 / 30.0)
		game.events.clear()
		if not game.offer.is_empty():
			game.choose_perk(game.offer[0])
		_set_speed(1)
		game.start_wave()
		_dirty = true
	if _demo_t > 1.0 and _demo_ui != "":
		var which := _demo_ui
		_demo_ui = ""
		if which.begins_with("evo:"):
			_demo_evo(which.substr(4))
			which = ""
		match which:
			"startscreen":
				_run_started = false
				_show_front()
			"mainmenu":
				_show_front()
			"settings":
				_show_front()
				front.settings()
			"saves":
				_show_front()
				front.slots(false)
			"pause":
				_toggle_pause()
			"build":
				game.enemies.clear()
				game.pending.clear()
				game.pending_boss.clear()
				game.phase = "build"
			"perk":
				game.offer = ["shatter", "rapid", "bounty"]
			"help":
				_open_help()
			"tutorial":
				tutorial_step = 0
				_update_modals()
			"over":
				game.lives = 0
				game.phase = "over"
			"victory":
				game.victory = true
			"dockwidth":
				_dock_width_test()
			"meta":
				_open_meta()
			"advice":
				_toggle_advice()
			"swarm":
				_toggle_drawer()
			"lure":
				# между волнами: взять приманку и открыть панель «Рой» (для кадров)
				game.enemies.clear()
				game.pending.clear()
				game.pending_boss.clear()
				game.phase = "build"
				game.buy_lure("plated")
				_toggle_drawer()
			"lurewave":
				# волна с приманкой уже идёт: враги с золотой каймой (для кадров)
				game.enemies.clear()
				game.pending.clear()
				game.pending_boss.clear()
				game.phase = "build"
				game.upcoming_boss = {}
				game.upcoming_special = ""
				if not game.buy_lure("plated"):
					game.buy_lure("swift")
				game.start_wave()
			"strains", "strainswave", "strainsreport":
				# PRO-152: кадры эксперимента — выводок в волне, панцирники объявлены (состояние задаётся принудительно)
				game.enemies.clear()
				game.pending.clear()
				game.pending_boss.clear()
				game.phase = "build"
				game.upcoming_boss = {}
				game.upcoming_special = ""
				_demo_force_strains()
				if which == "strains":
					_toggle_drawer()
				elif which == "strainswave":
					game.start_wave()
				else:
					_wave_report.open(TDWaveReport.snapshot(game))
			"wavereport":
				# отчёт о последней волне: для кадров и проверки (нужен хотя бы один сыгранный отчёт)
				game.enemies.clear()
				game.pending.clear()
				game.pending_boss.clear()
				game.phase = "build"
				_wave_report.open(TDWaveReport.snapshot(game))
			"menu":
				_toggle_menu()
			"newgame":
				_show_front()
				front.new_game_page()
			"achv":
				_show_front()
				front.achievements_page()
			"boss10", "boss20", "boss30":
				game.wave = int(which.substr(4)) - 0
				game.gold += 3000
				game.upcoming_boss = game._make_boss(game.damage_by)
				game.upcoming_special = ""
			"select":
				if not game.towers.is_empty():
					selected_tower = game.towers[1] if game.towers.size() > 1 else game.towers[0]
			"sell":
				if not game.towers.is_empty():
					var sold: TDGame.Tower = game.towers[0]
					game.sell_tower(sold.x, sold.y)
			"upgrade":
				game.gold += 2000
				for i in game.towers.size():
					var tw: TDGame.Tower = game.towers[i]
					if i % 3 != 2:
						game.upgrade_tower(tw)
					if i % 3 == 0:
						game.upgrade_tower(tw, "a" if i % 2 == 0 else "b")
				if game.towers.size() > 1:
					selected_tower = game.towers[1]
		_dirty = true
	if _demo_t > _demo_len * 0.5 and board.hover_cell.x < 0 and not game.towers.is_empty():
		board.hover_cell = Vector2i(game.towers[0].x + 1, game.towers[0].y)
		board.hover_pos = Vector2(board.hover_cell) + Vector2(0.5, 0.5)
	if _shot_path != "" and _demo_t > _demo_len:
		print("fps=", Engine.get_frames_per_second(), " parts=", board.vfx.parts.size() + board.vfx.glows.size())
		var img := get_viewport().get_texture().get_image()
		img.save_png(_shot_path)
		get_tree().quit()
