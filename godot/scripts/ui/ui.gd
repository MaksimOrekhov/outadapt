class_name TDUI
extends RefCounted
## Палитра, тема и маленькие фабрики виджетов. Интерфейс строится кодом.

const BG := Color("#171410")
const PANEL := Color("#26221c")
const PANEL2 := Color("#30291f")
const PANEL3 := Color("#3b3023")
const LINE := Color("#65513a")
const TEXT := Color("#f1e5cb")
const MUTED := Color("#baab8c")
const GOLD := Color("#ffd35a")
const BAD := Color("#ff6b7a")
const OK := Color("#7ddc5a")
const ACCENT := Color("#cda55f")

static var font: Font
static var font_bold: Font


static func init_fonts() -> void:
	if font != null:
		return
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Segoe UI", "Inter", "Roboto", "Arial", "sans-serif"])
	font = f
	var b := SystemFont.new()
	b.font_names = PackedStringArray(["Segoe UI Semibold", "Segoe UI", "Inter", "Roboto", "Arial", "sans-serif"])
	b.font_weight = 650
	font_bold = b


static func sb(bg: Color, border: Color = Color(0, 0, 0, 0), bw: int = 0, radius: int = 10, pad: int = 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(mini(radius, 3))
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	s.anti_aliasing = true
	return s


static func skin(kind: String = "button", pad: int = 10) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = load("res://assets/ui/" + kind + ".png")
	s.set_texture_margin_all(12 if kind in ["frame", "inset"] else 9)
	s.content_margin_left = pad
	s.content_margin_right = pad
	s.content_margin_top = pad * 0.6
	s.content_margin_bottom = pad * 0.6
	return s


static func make_theme() -> Theme:
	init_fonts()
	var t := Theme.new()
	t.default_font = font
	t.default_font_size = 14
	t.set_color("font_color", "Label", TEXT)
	# Кнопки
	t.set_stylebox("normal", "Button", skin("button", 12))
	t.set_stylebox("hover", "Button", skin("hover", 12))
	t.set_stylebox("pressed", "Button", skin("selected", 12))
	var disabled := skin("inset", 12)
	disabled.modulate_color = Color(0.65, 0.65, 0.65)
	t.set_stylebox("disabled", "Button", disabled)
	var focus := skin("selected", 12)
	focus.draw_center = false
	t.set_stylebox("focus", "Button", focus)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color("#80745e"))
	t.set_color("icon_normal_color", "Button", Color.WHITE)
	t.set_color("icon_disabled_color", "Button", Color("#80745e"))
	t.set_constant("h_separation", "Button", 8)
	t.set_constant("icon_max_width", "Button", 24)
	# Подсказки
	var tp := sb(Color("#181510"), Color("#9b7b49"), 1, 8, 10)
	tp.shadow_size = 8
	tp.shadow_color = Color(0, 0, 0, 0.5)
	t.set_stylebox("panel", "TooltipPanel", tp)
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font_size("font_size", "TooltipLabel", 13)
	# Скроллбар
	var grab := sb(Color("#706044"), Color(0, 0, 0, 0), 0, 4, 0)
	var grab_h := sb(Color("#9b8051"), Color(0, 0, 0, 0), 0, 4, 0)
	t.set_stylebox("scroll", "VScrollBar", sb(Color(0, 0, 0, 0.15), Color(0, 0, 0, 0), 0, 4, 0))
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab_h)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab_h)
	t.set_stylebox("panel", "PanelContainer", sb(PANEL, LINE, 1, 12, 12))
	t.set_stylebox("panel", "PopupMenu", skin("frame", 12))
	t.set_stylebox("hover", "PopupMenu", sb(Color("#65502c"), GOLD, 1, 2, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	var track := sb(Color("#181510"), LINE, 1, 2, 0)
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
	l.add_theme_font_size_override("font_size", size)
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
	r.modulate = Color.WHITE if icon_name == "portal" or ResourceLoader.exists("res://assets/ui/icon_" + icon_name + ".png") else color
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
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
static func chip(icon_name: String, text: String, color: Color = TEXT, tip: String = "", bg: Color = Color("#342b20")) -> PanelContainer:
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
	var l := label(text.to_upper(), 11, MUTED, true)
	return l


## Строка «иконка название ═══ значение» для справок и итогов.
static func data_row(icon_name: String, icon_color: Color, text: String, value: float, bar_color: Color, value_text: String, dim: bool = false) -> HBoxContainer:
	var r := hbox(8)
	var left := hbox(6)
	left.custom_minimum_size = Vector2(118, 0)
	left.add_child(icon(icon_name, 16, icon_color))
	left.add_child(label(text, 12, TEXT))
	r.add_child(left)
	r.add_child(bar(value, bar_color, 6))
	var v := label(value_text, 12, TEXT, true)
	v.custom_minimum_size = Vector2(38, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_child(v)
	if dim:
		r.modulate = Color(1, 1, 1, 0.4)
	return r


## Компактная плашка: иконка и (необязательно) короткое значение; детали в подсказке.
static func mini_chip(icon_name: String, color: Color, short: String = "", tip: String = "") -> PanelContainer:
	var p := panel(Color("#32291e"), Color(color.r, color.g, color.b, 0.5), 14, 7, 1)
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
