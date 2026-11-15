extends SceneTree
## Native render and nearest-neighbour 4x proof: terrain, road, props, tower, enemy.
class Sheet extends TDBoard:
	func _draw() -> void:
		_cs = 64.0
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var kinds := ["arrow", "ember", "frost", "poison", "cannon", "tesla"]
		for row in TDEnv.IDS.size():
			var id: String = TDEnv.IDS[row]
			var data: Dictionary = TDArt.biome_meta[id]
			var y := row * 192.0
			draw_texture_rect(TDArt.tex(data["ground"]), Rect2(0, y, 640, 192), true)
			draw_texture_rect(TDArt.tex(data["road_surface"]), Rect2(0, y + 124, 640, 56), true)
			draw_string(ThemeDB.fallback_font, Vector2(12, y + 25), id + " / 64 source px per cell", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
			draw_texture_rect(TDArt.tex(data["props"]["bush"]), Rect2(66, y + 110, 64, 64), false)
			_draw_tower_model(kinds[row], 2, "", Vector2(230, y + 174), 1.0, -PI * 0.5, Vector2.ZERO, 1.0, Color.WHITE)
			var genome := {}
			for gene in TDGenome.GENES: genome[gene] = 0.0
			var model := _enemy_visual_model(genome, false, false)
			_draw_custom_enemy(model, Vector2(355, y + 155), 64, Vector2.RIGHT, Color.WHITE, 0, false)
			draw_texture_rect(TDArt.tex(data["props"]["oak"]), Rect2(470, y + 48, 128, 128), false)

func _initialize() -> void:
	call_deferred("render")

func render() -> void:
	TDArt.ok()
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 1152)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(Sheet.new())
	await process_frame
	await RenderingServer.frame_post_draw
	var image := viewport.get_texture().get_image()
	image.save_png(ProjectSettings.globalize_path("res://../screenshots/pixel-scale-native.png"))
	image.resize(2560, 4608, Image.INTERPOLATE_NEAREST)
	var result := image.save_png(ProjectSettings.globalize_path("res://../screenshots/pixel-scale-4x.png"))
	print("Native pixel grid and 4x proof: result=", result)
	quit(result)
