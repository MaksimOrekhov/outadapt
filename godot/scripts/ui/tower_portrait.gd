class_name TDTowerPortrait
extends Control
## Shop defaults to level one; inspector supplies the selected specialization.

var kind: String
var level: int = 1
var branch: String = ""

func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)

func _draw() -> void:
	var data := TDArt.tower_level(kind, level, branch)
	if data.is_empty():
		return
	var dimensions: Array = data["base_size"]
	var ground: float = data["ground"]
	var mount: float = data["mount"] - ground
	var weapon: Dictionary = data["weapon"]
	var base := TDArt.tex(data["base"])
	var head := TDArt.tex(weapon["file"])
	if base == null or head == null:
		return
	var fw: float = weapon["frame"]
	var fh: float = weapon.get("frame_h", fw)
	var bounds := Rect2(base.get_image().get_used_rect())
	bounds.position += Vector2(-float(dimensions[0]) * 0.5, -ground)
	var head_bounds := Rect2(head.get_image().get_region(Rect2i(TDArt.frame_rect(weapon, 0))).get_used_rect())
	head_bounds.position += Vector2(-fw * 0.5, mount - fh * 0.5)
	bounds = bounds.merge(head_bounds)
	var unit := minf(size.x / bounds.size.x, size.y / bounds.size.y) * 0.94
	var anchor := size * 0.5 - bounds.get_center() * unit
	draw_texture_rect(base, Rect2(anchor + Vector2(-float(dimensions[0]) * 0.5, -ground) * unit, Vector2(dimensions[0], dimensions[1]) * unit), false)
	TDArt.draw_frame(self, weapon, 0, anchor + Vector2(0, mount * unit), unit)
