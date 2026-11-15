extends SceneTree
## Slice the generated 3x3 creature sheets into crisp 64px in-game sprites.

const ROOT := "res://assets/custom_enemies"
const GROUPS := {
	"ground": {
		"names": ["leafbug", "scorpion", "magma_crab", "firebug", "", "rotcap", "basalt_tortoise", "split_slime", "rune_guardian"],
		"flying": false,
	},
	"flying": {
		"names": ["flying_locust", "firewasp", "clampbeetle", "voidbutterfly", "frost_moth", "sporebat", "rune_drake", "splitwing", "stormray"],
		"flying": true,
	},
}
## Local point on each sprite that follows the route center, in 64px frame coordinates.
const PIVOTS := {
	"leafbug": [32, 40], "scorpion": [32, 39], "magma_crab": [32, 41],
	"firebug": [32, 41], "rotcap": [32, 42],
	"basalt_tortoise": [32, 42], "split_slime": [32, 36], "rune_guardian": [32, 40],
	"flying_locust": [32, 36], "firewasp": [32, 36], "clampbeetle": [32, 38],
	"voidbutterfly": [32, 34], "frost_moth": [32, 39], "sporebat": [32, 37],
	"rune_drake": [32, 41], "splitwing": [32, 35], "stormray": [32, 40],
}
func _initialize() -> void:
	var models: Dictionary = {}
	for group_name in GROUPS:
		var group: Dictionary = GROUPS[group_name]
		var sheet := Image.new()
		var image_bytes := FileAccess.get_file_as_bytes(ROOT + "/source/" + group_name + "-atlas.png")
		var load_error := sheet.load_png_from_buffer(image_bytes)
		if load_error != OK or sheet.is_empty():
			push_error("Could not load generated enemy atlas: " + group_name)
			quit(1)
			return
		for index in range(group["names"].size()):
			var species: String = group["names"][index]
			if species.is_empty():
				continue
			var row := int(index / 3)
			var col := index % 3
			var bounds := Rect2i(
				int(round(float(col) * sheet.get_width() / 3.0)),
				int(round(float(row) * sheet.get_height() / 3.0)),
				int(round(float(col + 1) * sheet.get_width() / 3.0)) - int(round(float(col) * sheet.get_width() / 3.0)),
				int(round(float(row + 1) * sheet.get_height() / 3.0)) - int(round(float(row) * sheet.get_height() / 3.0)),
			)
			var sprite := sheet.get_region(bounds)
			_threshold_alpha(sprite)
			var used := sprite.get_used_rect()
			if used.size.x == 0 or used.size.y == 0:
				push_error("Empty generated enemy cell: " + str(group["names"][index]))
				quit(1)
				return
			sprite = sprite.get_region(used)
			var scale := minf(60.0 / float(sprite.get_width()), 60.0 / float(sprite.get_height()))
			var size := Vector2i(maxi(1, roundi(sprite.get_width() * scale)), maxi(1, roundi(sprite.get_height() * scale)))
			sprite.resize(size.x, size.y, Image.INTERPOLATE_NEAREST)
			_threshold_alpha(sprite)
			used = sprite.get_used_rect()
			sprite = sprite.get_region(used)
			size = Vector2i(sprite.get_width(), sprite.get_height())
			var canvas := Image.create(64, 64, false, Image.FORMAT_RGBA8)
			canvas.fill(Color(0, 0, 0, 0))
			canvas.blit_rect(sprite, Rect2i(Vector2i.ZERO, size), Vector2i((64 - size.x) / 2, (64 - size.y) / 2))
			var out_path: String = ROOT + "/" + str(group_name) + "/" + species + ".png"
			var save_err := canvas.save_png(ProjectSettings.globalize_path(out_path))
			if save_err != OK:
				push_error("Could not save generated enemy sprite: " + out_path)
				quit(1)
				return
			models[species] = {
				"file": out_path,
				"frame": 64,
				"flying": group["flying"],
				"pivot": PIVOTS[species],
				"forward_degrees": 90.0,
			}
			print("prepared ", species, " ", size.x, "x", size.y)
	var output := FileAccess.open(ROOT + "/custom_enemies.json", FileAccess.WRITE)
	if output == null:
		push_error("Could not write custom enemy metadata")
		quit(1)
		return
	output.store_string(JSON.stringify({"enemies": models}, "\t") + "\n")
	output.close()
	print("Wrote ", models.size(), " custom enemy sprites")
	quit(0)


func _threshold_alpha(image: Image) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var color := image.get_pixel(x, y)
			if color.a < 0.58:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				image.set_pixel(x, y, Color(color.r, color.g, color.b, 1.0))
