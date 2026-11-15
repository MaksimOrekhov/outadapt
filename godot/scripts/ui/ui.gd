class_name TDUI
extends RefCounted
## Палитра, тема и маленькие фабрики виджетов. Интерфейс строится кодом.

const BG := Color("#101a1b")
const PANEL := Color("#1b292b")
const PANEL2 := Color("#26383a")
const PANEL3 := Color("#304447")
const LINE := Color("#465b59")
const TEXT := Color("#f1ebdd")
const MUTED := Color("#b5c4be")
const GOLD := Color("#e2ba72")
const BAD := Color("#f28b82")
const OK := Color("#76c5a1")
const ACCENT := Color("#e2ba72")

static var font: Font
static var font_bold: Font


static func init_fonts() -> void:
	if font != null:
		return
	font = ThemeDB.fallback_font
	var bold := FontVariation.new()
	bold.base_font = font
	bold.variation_embolden = 0.5
	font_bold = bold


static func sb(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 10, pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(mini(radius, 8))
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.anti_aliasing = true
	return s


static func skin(kind: String = "button", pad: int = 12) -> StyleBoxFlat:
	var colors := {
		"frame": [PANEL, LINE], "inset": [BG, LINE],
		"button": [PANEL2, LINE], "hover": [PANEL3, ACCENT],
		"selected": [Color("#314b43"), OK], "primary": [Color("#665336"), GOLD],
	}
	var pair: Array = colors.get(kind, colors["button"])
	var style := sb(pair[0], pair[1], 1, 8, pad)
	if kind == "frame":
		style.shadow_color = Color(0, 0, 0, 0.25)
		style.shadow_size = 12
	return style


static func primary(button: Button) -> void:
	button.add_theme_stylebox_override("normal", skin("primary", 16))
	button.add_theme_stylebox_override("hover", sb(Color("#806a43"), GOLD, 1, 8, 16))
	button.add_theme_stylebox_override("pressed", sb(Color("#493e2b"), GOLD, 1, 8, 16))


static func action(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 40
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.pressed.connect(callback)
	return button


static func make_theme() -> Theme:
	init_fonts()
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 16
	t.set_color("font_color", "Label", TEXT)
	# Кнопки
	t.set_stylebox("normal", "Button", skin("button", 12))
	t.set_stylebox("hover", "Button", skin("hover", 12))
	t.set_stylebox("pressed", "Button", skin("selected", 12))
	t.set_stylebox("hover_pressed", "Button", skin("selected", 12))
	t.set_font_size("font_size", "Button", 14)
	t.set_constant("scrollbar_width", "VScrollBar", 10)
	var disabled := skin("inset", 12)
	disabled.bg_color = BG
	t.set_stylebox("disabled", "Button", disabled)
	var focus := skin("selected", 12)
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = TEXT
	focus.set_border_width_all(2)
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("#91a59b"))
	t.set_color("icon_normal_color", "Button", Color.WHITE)
	t.set_color("icon_disabled_color", "Button", Color("#91a59b"))
	t.set_constant("h_separation", "Button", 8)
	t.set_constant("icon_max_width", "Button", 24)
	# Подсказки
	var tp := sb(Color("#101a1b"), Color("#76c5a1"), 1, 8, 10)
	tp.shadow_size = 8
	tp.shadow_color = Color(0, 0, 0, 0.5)
	t.set_stylebox("panel", "TooltipPanel", tp)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 14)
	# Скроллбар
	var grab := sb(Color("#465b59"), Color(0, 0, 0, 0), 0, 4, 0)
	var grab_h := sb(Color("#76c5a1"), Color(0, 0, 0, 0), 0, 4, 0)
	var scroll_track := sb(BG, LINE, 0, 4, 0)
	scroll_track.content_margin_left = 5
	scroll_track.content_margin_right = 5
	t.set_stylebox("scroll", "VScrollBar", scroll_track)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_h)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_h)
	t.set_stylebox("panel", "PanelContainer", sb(PANEL, LINE, 1, 12, 12))
	t.set_stylebox("panel", "PopupMenu", skin("frame", 12))
	t.set_stylebox("hover", "PopupMenu", sb(Color("#65502c"), GOLD, 1, 2, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	var track := sb(Color("#101a1b"), LINE, 1, 2, 0)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	var fill := track.duplicate() as StyleBoxFlat
	fill.bg_color = Color("#b28b4f")
	var fill_hover := fill.duplicate() as StyleBoxFlat
	fill_hover.bg_color = GOLD
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill_hover)
	var knob := GradientTexture2D.new()
	knob.width = 10
	knob.height = 18
	knob.gradient = Gradient.new()
	knob.gradient.set_color(0, Color("#f2d58e"))
	knob.gradient.set_color(1, Color("#8c6231"))
	t.set_icon("grabber", "HSlider", knob)
	t.set_icon("grabber_highlight", "HSlider", knob)
	return t


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


static func label(text: String, size: int = 14, color: Color = TEXT, bold: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", maxi(14, size))
	l.add_theme_color_override("font_color", color)
	if bold:
		l.add_theme_font_override("font", font_bold)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## Абзац с переносом по словам.
static func para(text: String, size: int = 13, color: Color = MUTED) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(40, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func icon(icon_name: String, size: float = 20.0, color: Color = Color.WHITE) -> TextureRect:
	var r := TextureRect.new()
	r.texture = TDIcons.tex(icon_name)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = Vector2(size, size)
	r.modulate = Color.WHITE if icon_name == "portal" or (ResourceLoader.exists("res://assets/ui/icon_" + icon_name + ".png") and not ResourceLoader.exists("res://assets/ui/glyphs/" + icon_name + ".svg")) else color
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return r


static func hbox(sep: int = 8) -> HBoxContainer:
	var b := HBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func vbox(sep: int = 8) -> VBoxContainer:
	var b := VBoxContainer.new()
	b.add_theme_constant_override("separation", sep)
	return b


static func flow(sep: int = 6) -> HFlowContainer:
	var b := HFlowContainer.new()
	b.add_theme_constant_override("h_separation", sep)
	b.add_theme_constant_override("v_separation", sep)
	return b


static func panel(bg: Color = PANEL, border: Color = LINE, radius: int = 12, pad: int = 12, bw: int = 1) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb(bg, border, bw, radius, pad))
	return p


static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Плашка с иконкой и текстом.
static func chip(icon_name: String, text: String, color: Color = TEXT, tip: String = "", bg: Color = PANEL2) -> PanelContainer:
	var p := panel(bg, Color(color.r, color.g, color.b, 0.35), 20, 8, 1)
	p.get_theme_stylebox("panel").content_margin_top = 3
	p.get_theme_stylebox("panel").content_margin_bottom = 3
	var h := hbox(5)
	if icon_name != "":
		h.add_child(icon(icon_name, 15, color))
	var l := label(text, 12, TEXT)
	h.add_child(l)
	p.add_child(h)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	if tip != "":
		p.tooltip_text = tip
	return p


static func bar(value: float, color: Color, h: int = 8) -> ProgressBar:
	var b := ProgressBar.new()
	b.min_value = 0.0
	b.max_value = 1.0
	b.value = clampf(value, 0.0, 1.0)
	b.show_percentage = false
	b.custom_minimum_size = Vector2(40, h)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.add_theme_stylebox_override("background", sb(Color("#1c1813"), Color("#58472f"), 1, h / 2, 0))
	b.add_theme_stylebox_override("fill", sb(color, Color(0, 0, 0, 0), 0, h / 2, 0))
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return b


static func section_title(text: String) -> Label:
	var l := label(text.to_upper(), 14, MUTED, true)
	return l


## Строка «иконка название ═══ значение» для справок и итогов.
static func data_row(icon_name: String, icon_color: Color, text: String, value: float, bar_color: Color, value_text: String, dim: bool = false) -> HBoxContainer:
	var r := hbox(8)
	var left := hbox(6)
	left.custom_minimum_size = Vector2(142, 0)
	left.add_child(icon(icon_name, 16, icon_color))
	left.add_child(label(text, 12, TEXT))
	r.add_child(left)
	r.add_child(bar(value, bar_color, 6))
	var v := label(value_text, 12, TEXT, true)
	v.custom_minimum_size = Vector2(44, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_child(v)
	if dim:
		r.modulate = Color(1, 1, 1, 0.4)
	return r


## Компактная плашка: иконка и (необязательно) короткое значение; детали в подсказке.
static func mini_chip(icon_name: String, color: Color, short: String = "", tip: String = "") -> PanelContainer:
	var p := panel(PANEL2, Color(color.r, color.g, color.b, 0.5), 14, 7, 1)
	var st: StyleBoxFlat = p.get_theme_stylebox("panel")
	st.content_margin_top = 3
	st.content_margin_bottom = 3
	var h := hbox(4)
	h.add_child(icon(icon_name, 16, color))
	if short != "":
		h.add_child(label(short, 12, TEXT, true))
	p.add_child(h)
	p.mouse_filter = Control.MOUSE_FILTER_PASS
	if tip != "":
		p.tooltip_text = tip
	return p


static func vsep(h: float = 28.0) -> ColorRect:
	var r := ColorRect.new()
	r.color = LINE
	r.custom_minimum_size = Vector2(1, h)
	r.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Иконка башни из спрайтов: основание и голова друг на друге.
static func tower_icon(kind: String, size: float, level: int = 1, branch: String = "") -> Control:
	var box := TDTowerPortrait.new()
	box.kind = kind
	box.level = level
	box.branch = branch
	box.custom_minimum_size = Vector2(size, size)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return box


static func keycap(text: String) -> Label:
	var l := label(text, 10, MUTED, true)
	return l


static func spacer_v() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Bound native tooltip text before Godot creates its popup window.
static func fit_tooltip(reference: WeakRef) -> void:
	var control := reference.get_ref() as Control
	if control == null or control.tooltip_text.is_empty(): return
	if control is Label: control.mouse_filter = Control.MOUSE_FILTER_PASS
	var width := minf(460, control.get_viewport_rect().size.x - 48)
	var lines := PackedStringArray()
	for paragraph in control.tooltip_text.split("\n"):
		var line := ""
		for word in paragraph.split(" "):
			var candidate: String = word if line.is_empty() else line + " " + word
			if font.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x > width and not line.is_empty():
				lines.append(line)
				line = word
			else: line = candidate
		lines.append(line)
	control.tooltip_text = "\n".join(lines)
