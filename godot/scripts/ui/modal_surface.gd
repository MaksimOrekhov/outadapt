class_name TDModalSurface
extends PanelContainer
## A viewport-bounded surface. Containers own layout; only the scroll budget is responsive.

var preferred_width := 640.0
var viewport_margin := Vector2(48, 48)
var content: VBoxContainer
var scroll: ScrollContainer
var _pending := false

func _init(width: float = 640.0, padding: int = 24) -> void:
	preferred_width = width
	set_meta("modal_surface", true)
	add_theme_stylebox_override("panel", TDUI.skin("frame", padding))
	scroll = ScrollContainer.new()
	scroll.name = "SurfaceScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	add_child(scroll)
	content = TDUI.vbox(12)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	content.minimum_size_changed.connect(schedule_fit)

func _ready() -> void:
	get_viewport().size_changed.connect(schedule_fit)
	schedule_fit()

func schedule_fit() -> void:
	if _pending or not is_inside_tree(): return
	_pending = true
	call_deferred("_fit")

func _fit() -> void:
	_pending = false
	if not is_inside_tree(): return
	var available := get_viewport_rect().size - viewport_margin
	var style := get_theme_stylebox("panel")
	var chrome := style.get_minimum_size()
	custom_minimum_size.x = minf(preferred_width, available.x)
	scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, maxf(80, available.y - chrome.y))

static func mount(parent: Control, width: float = 640.0) -> TDModalSurface:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(center)
	var surface := TDModalSurface.new(width)
	center.add_child(surface)
	return surface
