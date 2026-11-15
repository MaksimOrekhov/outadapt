extends SceneTree
## Overview of the six actual game captures, cropped to the field.
class Sheet extends Control:
	var textures: Array[Texture2D] = []
	func _ready() -> void:
		for id in TDEnv.IDS:
			var path := ProjectSettings.globalize_path("res://../screenshots/biome-" + id + ".png")
			textures.append(ImageTexture.create_from_image(Image.load_from_file(path)))
	func _draw() -> void:
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		draw_rect(Rect2(0, 0, 1800, 900), Color("20252b"))
		for i in TDEnv.IDS.size():
			var id: String = TDEnv.IDS[i]
			var origin := Vector2((i % 3) * 600, (i / 3) * 450)
			var texture := textures[i]
			draw_string(ThemeDB.fallback_font, origin + Vector2(16, 28), TDEnv.BIOMES[id]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("eddbb5"))
			draw_texture_rect_region(texture, Rect2(origin + Vector2(0, 40), Vector2(600, 400)), Rect2(339, 76, 1219, 815))

func _initialize() -> void:
	call_deferred("render")

func render() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(1800, 900)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(Sheet.new())
	await process_frame
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://../screenshots/biomes-showcase.png")
	var result := viewport.get_texture().get_image().save_png(path)
	print("Biome contact sheet: ", path, " result=", result)
	quit(result)
