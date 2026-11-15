class_name TDTopBar
extends PanelContainer
## Верхняя полоса: только то, что нужно каждую секунду.
## Жизни, золото, волна · что придёт следом · советы, скорость, меню, старт.

signal go_pressed
signal speed_selected(s: int)
signal advice_pressed
signal menu_pressed
signal pause_pressed

var lives_lbl: Label
var gold_lbl: Label
var wave_lbl: Label
var next_box: HBoxContainer
var go_btn: Button
var advice_btn: Button
var menu_btn: Button
var pause_btn: Button
var _badge: PanelContainer
var _badge_lbl: Label
var _speed_btns: Array[Button] = []
var _last_lives: int = -1
var _last_gold: int = -1
var _sig: String = ""


func setup() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_stylebox_override("panel", TDUI.skin("frame", 14))
	custom_minimum_size = Vector2(0, 54)
	var h := TDUI.hbox(10)
	add_child(h)

	lives_lbl = _stat(h, "lives", TDUI.BAD, "Жизни: сколько врагов ещё может дойти до замка")
	gold_lbl = _stat(h, "coin", TDUI.GOLD, "Золото")
	var wp := _pill()
	var wh := TDUI.hbox(6)
	wh.add_child(TDUI.label("Волна", 13, TDUI.MUTED))
	wave_lbl = TDUI.label("1", 18, TDUI.TEXT, true)
	wave_lbl.custom_minimum_size = Vector2(22, 0)
	wh.add_child(wave_lbl)
	wp.add_child(wh)
	h.add_child(wp)
	h.add_child(TDUI.vsep(30))

	next_box = TDUI.hbox(8)
	next_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(next_box)

	# советы с бейджем-счётчиком
	advice_btn = _icon_button("info", "Советы (A)")
	advice_btn.add_theme_constant_override("icon_max_width", 22)
	advice_btn.pressed.connect(func(): advice_pressed.emit())
	_badge = TDUI.panel(TDUI.ACCENT, Color(0, 0, 0, 0), 9, 4, 0)
	var bs: StyleBoxFlat = _badge.get_theme_stylebox("panel")
	bs.content_margin_top = 0
	bs.content_margin_bottom = 0
	bs.content_margin_left = 5
	bs.content_margin_right = 5
	_badge_lbl = TDUI.label("", 10, Color.WHITE, true)
	_badge.add_child(_badge_lbl)
	_badge.position = Vector2(24, -4)
	_badge.visible = false
	advice_btn.add_child(_badge)
	h.add_child(advice_btn)

	# пауза
	pause_btn = _icon_button("pause", "Пауза (P)")
	pause_btn.add_theme_constant_override("icon_max_width", 18)
	pause_btn.pressed.connect(func(): pause_pressed.emit())
	h.add_child(pause_btn)

	# скорость
	var seg := TDUI.panel(Color("#1c1813"), Color("#58472f"), 10, 3)
	seg.tooltip_text = "Скорость игры (F)"
	var sh := TDUI.hbox(2)
	seg.add_child(sh)
	var grp := ButtonGroup.new()
	for sp in [1, 2, 4]:
		var b := Button.new()
		b.text = "×%d" % sp
		b.focus_mode = Control.FOCUS_NONE
		b.toggle_mode = true
		b.button_group = grp
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_stylebox_override("normal", TDUI.sb(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 7, 11))
		b.add_theme_stylebox_override("hover", TDUI.sb(Color("#403423"), Color(0, 0, 0, 0), 0, 7, 11))
		b.add_theme_stylebox_override("pressed", TDUI.sb(Color("#6c5730"), Color(0, 0, 0, 0), 0, 7, 11))
		b.add_theme_stylebox_override("hover_pressed", TDUI.sb(Color("#826938"), Color(0, 0, 0, 0), 0, 7, 11))
		b.pressed.connect(func(): speed_selected.emit(sp))
		_speed_btns.append(b)
		sh.add_child(b)
	h.add_child(seg)

	# меню: три полоски
	menu_btn = Button.new()
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.icon = TDIcons.tex("menu")
	menu_btn.expand_icon = true
	menu_btn.custom_minimum_size = Vector2(40, 38)
	menu_btn.tooltip_text = "Меню"
	menu_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var lines := TDUI.vbox(4)
	lines.visible = false
	lines.alignment = BoxContainer.ALIGNMENT_CENTER
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 3:
		var r := ColorRect.new()
		r.color = Color("#eadbb9")
		r.custom_minimum_size = Vector2(16, 2)
		r.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lines.add_child(r)
	menu_btn.add_child(lines)
	menu_btn.pressed.connect(func(): menu_pressed.emit())
	h.add_child(menu_btn)

	# старт волны
	go_btn = Button.new()
	go_btn.focus_mode = Control.FOCUS_NONE
	go_btn.text = "Волна 1"
	go_btn.icon = TDIcons.tex("play")
	go_btn.expand_icon = true
	go_btn.custom_minimum_size = Vector2(196, 40)
	go_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	go_btn.tooltip_text = "Запустить волну (пробел)"
	go_btn.add_theme_font_size_override("font_size", 16)
	go_btn.add_theme_font_override("font", TDUI.font_bold)
	var g1 := TDUI.skin("primary", 16)
	var g2: StyleBoxTexture = g1.duplicate()
	g2.modulate_color = Color(1.15, 1.15, 1.05)
	var g3: StyleBoxTexture = g1.duplicate()
	g3.modulate_color = Color(0.8, 0.8, 0.8)
	var g4 := TDUI.skin("inset", 16)
	g4.modulate_color = Color(0.65, 0.65, 0.65)
	go_btn.add_theme_stylebox_override("normal", g1)
	go_btn.add_theme_stylebox_override("hover", g2)
	go_btn.add_theme_stylebox_override("pressed", g3)
	go_btn.add_theme_stylebox_override("disabled", g4)
	go_btn.pressed.connect(func(): go_pressed.emit())
	h.add_child(go_btn)


func _pill() -> PanelContainer:
	var p := TDUI.panel(Color("#32291e"), Color("#79603c"), 20, 12)
	var st: StyleBoxFlat = p.get_theme_stylebox("panel")
	st.content_margin_top = 4
	st.content_margin_bottom = 4
	return p


func _stat(parent: Control, icon_name: String, color: Color, tip: String) -> Label:
	var p := _pill()
	p.tooltip_text = tip
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	var h := TDUI.hbox(8)
	h.add_child(TDUI.icon(icon_name, 22, color))
	var l := TDUI.label("0", 18, TDUI.TEXT, true)
	l.custom_minimum_size = Vector2(36, 0)
	h.add_child(l)
	p.add_child(h)
	parent.add_child(p)
	return l


func _icon_button(icon_name: String, tip: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.icon = TDIcons.tex(icon_name)
	b.expand_icon = true
	b.custom_minimum_size = Vector2(40, 38)
	b.tooltip_text = tip
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func _flash(l: Label, c: Color) -> void:
	l.modulate = c
	var tw := create_tween()
	tw.tween_property(l, "modulate", Color.WHITE, 0.5)


## Пауза: кнопка подсвечивается и меняет значок.
func set_paused(p: bool) -> void:
	pause_btn.icon = TDIcons.tex("play" if p else "pause")
	pause_btn.tooltip_text = "Продолжить (P)" if p else "Пауза (P)"
	pause_btn.add_theme_stylebox_override("normal", TDUI.sb(Color("#5a3a10") if p else Color("#2e271e"), Color("#ffb347") if p else Color("#66513a"), 1, 8, 8))


func update(g: TDGame, info: Dictionary, threat: Dictionary, coverage: Dictionary, tips: Array, speed: int) -> void:
	if g.lives != _last_lives:
		if _last_lives >= 0 and g.lives < _last_lives:
			_flash(lives_lbl, Color(1.6, 0.4, 0.4))
		_last_lives = g.lives
	if g.gold != _last_gold:
		if _last_gold >= 0 and g.gold > _last_gold:
			_flash(gold_lbl, Color(1.5, 1.4, 0.7))
		_last_gold = g.gold
	lives_lbl.text = str(g.lives)
	gold_lbl.text = str(g.gold)
	# до победы показываем прогресс к цели, потом — просто номер волны
	var open_ended: bool = g.victory or g.mode_id() == "endless"
	wave_lbl.text = str(g.wave) if open_ended else "%d / %d" % [g.wave, TDConfig.VICTORY_WAVE]
	wave_lbl.tooltip_text = "%s · %s" % [TDConfig.MODES[g.mode_id()]["name"], TDConfig.difficulty(g.meta)["name"]]
	wave_lbl.mouse_filter = Control.MOUSE_FILTER_PASS
	for i in _speed_btns.size():
		_speed_btns[i].set_pressed_no_signal([1, 2, 4][i] == speed)

	# кнопка старта
	var busy := g.phase != "build" or not g.offer.is_empty()
	go_btn.disabled = busy
	if g.phase == "wave":
		var left := g.pending.size() + g.enemies.size() + (1 if not g.pending_boss.is_empty() else 0)
		go_btn.text = "Идёт волна · %d" % left
		go_btn.icon = TDIcons.tex("fast")
	elif not g.offer.is_empty():
		go_btn.text = "Выбери усиление"
		go_btn.icon = TDIcons.tex("perk-rapid")
	elif g.phase == "over":
		go_btn.text = "Игра окончена"
		go_btn.icon = TDIcons.tex("castle")
	else:
		go_btn.text = "Волна %d" % g.wave
		go_btn.icon = TDIcons.tex("play")

	# бейдж советов: красный, если есть опасность
	var danger := 0
	var useful := 0
	for t in tips:
		if t["level"] == "danger":
			danger += 1
		if t["title"] != "Рой пока без особенностей" and t["title"] != "Начни с простого":
			useful += 1
	_badge.visible = useful > 0
	_badge_lbl.text = str(useful)
	var bs: StyleBoxFlat = _badge.get_theme_stylebox("panel")
	bs.bg_color = TDUI.BAD if danger > 0 else TDUI.ACCENT

	# «Следом»: перестраиваем только при изменении
	var sig := "%d|%d|%s|%d|%s|%d|%s" % [g.wave, g.upcoming.size(), str(not g.upcoming_boss.is_empty()), int(coverage["pct"] * 20), g.phase, g.towers.size(), g.upcoming_special]
	if sig == _sig:
		return
	_sig = sig
	TDUI.clear(next_box)
	next_box.add_child(TDUI.label("Следом", 13, TDUI.MUTED))
	next_box.add_child(TDUI.label("%d врагов" % info["n"], 15, TDUI.TEXT, true))
	if not g.upcoming_boss.is_empty():
		var boss_chip := {"text": "БОСС", "title": "Копирует твою защиту. Прорвавшийся босс стоит 5 жизней"}
		for c in TDAdvisor.wave_chips(info):
			if c["icon"] == "boss":
				boss_chip = c
		next_box.add_child(TDUI.mini_chip("boss", TDUI.BAD, boss_chip["text"], "%s: %s" % [boss_chip["text"], boss_chip["title"]]))
	# плашки с подписями; если их много — коротко, подробности во всплывающей подсказке
	var chips: Array = []
	for c in TDAdvisor.wave_chips(info):
		if c["icon"] != "boss":
			chips.append(c)
	var wide := chips.size() <= 4
	for c in chips:
		var txt: String = c["text"] if wide else (c["short"] if c["short"] != "" else c["text"])
		next_box.add_child(TDUI.mini_chip(c["icon"], Color(c["color"]), txt, "%s: %s" % [c["text"], c["title"]]))
	if not threat.is_empty():
		var w: int = threat["inWaves"]
		var tp := TDUI.mini_chip(threat["icon"], Color("#ffb347"), "через %d" % w, "Через %d %s: %s" % [w, "волну" if w == 1 else "волны", threat["label"]])
		next_box.add_child(tp)
	if g.towers.size() >= 3 and coverage["pct"] < 0.65:
		next_box.add_child(TDUI.mini_chip("target", TDUI.BAD, "%d%%" % round(coverage["pct"] * 100), "Только %d%% дороги под обстрелом. Красные клетки на дороге — дыры" % round(coverage["pct"] * 100)))
