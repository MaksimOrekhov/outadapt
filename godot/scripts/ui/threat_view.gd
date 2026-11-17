class_name TDThreatView
extends RefCounted
## PRO-191: вид карточки угрозы из TDThreats. Один и тот же вид в отчёте о волне, панели «Рой» и экране поражения.
## Статус различается текстом, значком и формой плашки (залитая / контурная / без рамки), а не только цветом.


## Плашка статуса: «Следующая волна» (залитая), «Скоро» (контур), «Уже в бою» (тёмная), «Может появиться» (без рамки).
static func status_pill(c: Dictionary) -> PanelContainer:
	var status: String = c["status"]
	var col := Color(c["color"])
	var bg := Color(0, 0, 0, 0)
	var border := Color(0, 0, 0, 0)
	var fg := TDUI.TEXT
	match status:
		"next":
			bg = col.darkened(0.15)
			fg = Color("#15201f")
		"dated":
			border = col
			fg = col.lightened(0.25)
		"active":
			bg = Color(col.r, col.g, col.b, 0.28)
			border = Color(col.r, col.g, col.b, 0.6)
		_:
			fg = TDUI.MUTED
	var p := TDUI.panel(bg, border, 10, 7, 2 if status == "dated" else 1)
	var st: StyleBoxFlat = p.get_theme_stylebox("panel")
	st.content_margin_top = 1
	st.content_margin_bottom = 1
	var h := TDUI.hbox(4)
	h.add_child(TDUI.icon(TDThreats.STATUS_ICON.get(status, "info"), 14, fg))
	h.add_child(TDUI.label(String(TDThreats.STATUS_TEXT.get(status, "")).to_upper(), 12, fg, true))
	p.add_child(h)
	p.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return p


## Башня-ответ: портрет, имя и текущая цена (золотом, если хватает золота). Клик выбирает башню, если задан on_pick.
static func tower_button(kind: String, cost: int, gold: int, on_pick: Callable = Callable()) -> PanelContainer:
	var d: Dictionary = TDConfig.TOWERS[kind]
	var col := Color(d["color"])
	var p := TDUI.panel(TDUI.PANEL3, Color(col.r, col.g, col.b, 0.55), 10, 6, 1)
	var st: StyleBoxFlat = p.get_theme_stylebox("panel")
	st.content_margin_top = 2
	st.content_margin_bottom = 2
	var h := TDUI.hbox(5)
	# цветной значок типа башни: на этом размере портреты из спрайтов неразличимы
	h.add_child(TDUI.icon(d["icon"], 20, col))
	h.add_child(TDUI.label(d["name"], 14, TDUI.TEXT, true))
	if cost > 0:
		h.add_child(TDUI.icon("coin", 13, TDUI.GOLD if gold >= cost else TDUI.MUTED))
		h.add_child(TDUI.label(str(cost), 13, TDUI.GOLD if gold >= cost else TDUI.MUTED))
	p.add_child(h)
	p.name = "Answer_" + kind
	p.tooltip_text = "%s — %s. Цена сейчас: %d" % [d["name"], d["role"], cost]
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	if on_pick.is_valid():
		p.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		p.gui_input.connect(func(ev: InputEvent):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				on_pick.call(kind))
	return p


static func towers_row(c: Dictionary, gold: int, on_pick: Callable, compact: bool) -> Control:
	var row := TDUI.flow(6)
	row.add_child(_shrink(TDUI.label(String(c["build"]), 14 if not compact else 13, TDUI.GOLD, true)))
	for k in c["towers"]:
		row.add_child(tower_button(k, int(c["costs"].get(k, 0)), gold, on_pick))
	return row


static func _shrink(l: Label) -> Label:
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return l


## Полная карточка: статус и срок, заголовок, чем грозит, почему, что построить.
static func card(c: Dictionary, gold: int, on_pick: Callable = Callable()) -> PanelContainer:
	var col := Color(c["color"])
	var p := TDUI.panel(Color("#22302f"), Color(col.r, col.g, col.b, 0.75), 12, 12, 2)
	p.name = "Threat_" + String(c["id"]).replace(":", "_")
	var h := TDUI.hbox(12)
	p.add_child(h)
	var ic := TDUI.icon(c["icon"], 44, col)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var v := TDUI.vbox(5)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var head := TDUI.flow(8)
	head.add_child(status_pill(c))
	if String(c["when"]) != "":
		head.add_child(_shrink(TDUI.label(c["when"], 14, TDUI.TEXT if c["status"] in ["next", "dated", "active"] else TDUI.MUTED, c["status"] in ["next", "dated"])))
	v.add_child(head)
	var title := TDUI.para(c["title"], 19, TDUI.TEXT)
	title.add_theme_font_override("font", TDUI.font_bold)
	title.name = "ThreatTitle"
	v.add_child(title)
	if String(c["effect"]) != "":
		v.add_child(TDUI.para(c["effect"], 15, Color("#e6dccb")))
	if String(c["why"]) != "":
		var why := TDUI.hbox(6)
		why.add_child(TDUI.icon("info", 14, TDUI.MUTED))
		why.add_child(TDUI.para(c["why"], 14, TDUI.MUTED))
		v.add_child(why)
	if not c["towers"].is_empty():
		v.add_child(towers_row(c, gold, on_pick, false))
		for n in c["notes"]:
			v.add_child(TDUI.para(n, 13, TDUI.MUTED))
	return p


## Короткая карточка (вторая в отчёте, список в панели): значок, заголовок, срок и ответ в одну-две строки.
static func compact(c: Dictionary, gold: int, on_pick: Callable = Callable()) -> PanelContainer:
	var col := Color(c["color"])
	var p := TDUI.panel(TDUI.PANEL2, Color(col.r, col.g, col.b, 0.45), 10, 9, 1)
	p.name = "ThreatCompact_" + String(c["id"]).replace(":", "_")
	var h := TDUI.hbox(10)
	p.add_child(h)
	var ic := TDUI.icon(c["icon"], 28, col)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	h.add_child(ic)
	var v := TDUI.vbox(4)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(v)
	var head := TDUI.flow(8)
	head.add_child(status_pill(c))
	if String(c["when"]) != "":
		head.add_child(_shrink(TDUI.label(c["when"], 13, TDUI.MUTED)))
	v.add_child(head)
	var title := TDUI.para(c["title"], 16, TDUI.TEXT)
	title.add_theme_font_override("font", TDUI.font_bold)
	title.name = "ThreatTitle"
	v.add_child(title)
	if String(c["effect"]) != "":
		v.add_child(TDUI.para(c["effect"], 14, Color("#d8cfbf")))
	if not c["towers"].is_empty():
		v.add_child(towers_row(c, gold, on_pick, true))
	p.tooltip_text = TDThreats.tip_text(c)
	return p


## Спокойное состояние: новых угроз нет.
static func calm(text: String) -> PanelContainer:
	var p := TDUI.panel(TDUI.PANEL2, TDUI.LINE, 12, 12, 1)
	p.name = "ThreatCalm"
	var h := TDUI.hbox(10)
	h.add_child(TDUI.icon("castle", 30, TDUI.OK))
	var v := TDUI.vbox(2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(TDUI.label("Новых угроз пока нет", 18, TDUI.OK, true))
	v.add_child(TDUI.para(text, 14, TDUI.MUTED))
	h.add_child(v)
	p.add_child(h)
	return p
