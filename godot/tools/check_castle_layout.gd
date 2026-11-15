extends SceneTree
## Regression: foundation on the final road strip, gate never shifted off its lane.


func _initialize() -> void:
	var checks := 0
	for field_size in [Vector2(1466, 950), Vector2(960, 540), Vector2(800, 1000)]:
		for seed_value in 120:
			var map := TDMap.generate(seed_value)
			var layout := map.castle_layout(field_size)
			var base: Vector2 = layout["base"]
			var side: float = layout["side"]
			var end: Vector2 = layout["end"]
			var road_end: Vector2 = layout["road_end"]
			var cell := minf(field_size.x / TDConfig.COLS, field_size.y / TDConfig.ROWS)
			if absf(base.y - end.y - cell * 0.05) > 0.01 or side < cell * 1.79:
				push_error("Castle shifted off route or insufficient headroom: seed %d" % seed_value)
				quit(1)
				return
			for x in [-0.46, 0.0, 0.46]:
				var foot := base + Vector2(side * x, 0)
				if absf(foot.y - end.y) > cell * 0.43 or foot.x > road_end.x + 0.01 or foot.x < map.points[-2].x * cell:
					push_error("Castle foundation off final road strip: seed %d" % seed_value)
					quit(1)
					return
			if base.x - side * 0.5 < 0 or base.x + side * 0.5 > field_size.x or base.y > field_size.y or base.y - side < 0:
				push_error("Castle outside field: seed %d" % seed_value)
				quit(1)
				return
			checks += 1
	print("Castle layout: %d placements passed" % checks)
	quit(0)
