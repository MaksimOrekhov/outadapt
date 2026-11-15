class_name TDFxLayer
extends Control
## Слой поверх поля с аддитивным смешиванием: свечение, искры, трассеры.

var vfx: TDVfx


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _process(_d: float) -> void:
	queue_redraw()


func _draw() -> void:
	if vfx != null:
		vfx.draw_add(self)
