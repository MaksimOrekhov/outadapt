extends SceneTree
## Contact sheet rendered with the same modular drawing path as the field.

class Sheet extends TDBoard:
	const KINDS := ["arrow", "cannon", "ember", "frost", "sniper", "poison", "flak", "tesla", "net", "beacon"]
	func _draw() -> void:
		_cs = 64.0
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		draw_rect(Rect2(0, 0, 960, 1660), Color("242a30"))
		var font := ThemeDB.fallback_font
		for col in 4:
			draw_string(font, Vector2(210 + col * 185, 35), ["Уровень 1", "Уровень 2", "Уровень 3 А", "Уровень 3 Б"][col], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("f0d9a2"))
		for row in KINDS.size():
			var y := 65.0 + row * 157.0
			draw_rect(Rect2(10, y, 940, 151), Color("303942") if row % 2 == 0 else Color("29323a"))
			draw_string(font, Vector2(22, y + 65), TDConfig.TOWERS[KINDS[row]]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("f0d9a2"))
			for col in 4:
				var anchor := Vector2(245 + col * 185, y + 125)
				draw_line(anchor + Vector2(-62, 1), anchor + Vector2(62, 1), Color("64705d"))
				_draw_tower_model(KINDS[row], mini(col + 1, 3), "b" if col == 3 else "a", anchor, 1.0, -PI * 0.5, Vector2.ZERO, 1.0, Color.WHITE)
				if col >= 2:
					var label: String = TDConfig.branch_def(KINDS[row], "b" if col == 3 else "a")["name"]
					draw_string(font, Vector2(anchor.x - 65, y + 145), label, HORIZONTAL_ALIGNMENT_CENTER, 130, 15, Color("c4c7c6"))

func _initialize() -> void:
	call_deferred("render")

func render() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(960, 1660)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	viewport.add_child(Sheet.new())
	await process_frame
	await RenderingServer.frame_post_draw
	var output := ProjectSettings.globalize_path("res://../screenshots/towers-levels.png")
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var result := viewport.get_texture().get_image().save_png(output)
	print("Tower contact sheet: ", output, " result=", result)
	quit(result)
