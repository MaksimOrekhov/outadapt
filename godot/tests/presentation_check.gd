extends SceneTree
## Asset seams/scale, route clearance, actor depth and real dock layout contracts.
var failures := 0

func check(label: String, condition: bool) -> void:
	print(("OK   " if condition else "FAIL ") + label)
	if not condition: failures += 1

func _initialize() -> void:
	call_deferred("run_checks")

func run_checks() -> void:
	TDArt.ok()
	for biome in TDEnv.IDS:
		var data: Dictionary = TDArt.biome_meta[biome]
		var surfaces: Array = data["ground_variants"].duplicate()
		surfaces.append(data["road_surface"])
		var sizes_ok: bool = surfaces.size() == 4 and data["pixel_scale"] == 64
		var seams_ok := true
		var first: Image
		for index in surfaces.size():
			var img := TDArt.tex(surfaces[index]).get_image()
			sizes_ok = sizes_ok and img.get_size() == Vector2i(256, 256)
			for i in 256:
				seams_ok = seams_ok and img.get_pixel(0, i) == img.get_pixel(255, i) and img.get_pixel(i, 0) == img.get_pixel(i, 255)
				if index > 0 and index < 3:
					seams_ok = seams_ok and img.get_pixel(0, i) == first.get_pixel(0, i) and img.get_pixel(i, 0) == first.get_pixel(i, 0)
			if index == 0: first = img
		var props_ok := true
		for kind in data["props"]:
			var img := TDArt.tex(data["props"][kind]).get_image()
			var side := 128 if kind in ["oak", "pine"] else 64
			props_ok = props_ok and img.get_size() == Vector2i(side, side) and img.get_used_rect().has_area()
			for y in side:
				for x in side:
					var alpha := img.get_pixel(x, y).a
					props_ok = props_ok and (alpha == 0.0 or alpha == 1.0)
		check(biome + ": 64px/cell, mixed seamless ground, hard-alpha props", sizes_ok and seams_ok and props_ok)
	var clearance_ok := true
	for seed_value in 120:
		var env := TDEnv.new(TDMap.generate(seed_value))
		for decor in env.decor:
			if decor["kind"] not in ["oak", "pine"]: continue
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					clearance_ok = clearance_ok and not env.map.cells.has(decor["c"] + Vector2i(dx, dy))
	check("120 maps: tall decor avoids road neighbours", clearance_ok)
	var board := TDBoard.new()
	var game := TDGame.new(99)
	board.game = game
	game.gold = 100000
	for c in game.map.blocked: # Towers are fixture objects here; no simulation changes needed.
		var tower := TDGame.Tower.new()
		tower.id = 1000 + game.towers.size()
		tower.x = c.x
		tower.y = c.y
		game.towers.append(tower)
	for i in 10:
		var enemy := TDGame.Enemy.new()
		enemy.id = i
		enemy.genome = {}
		for gene in TDGenome.GENES: enemy.genome[gene] = 0.0
		if i % 2 == 0: enemy.genome["wings"] = 1.0
		enemy.ph = TDGenome.phenotype(enemy.genome, 19)
		enemy.dist = i * 1.5
		game.enemies.append(enemy)
	var native_ok := true
	for specimen in [[0.0, false, 35], [1.0, false, 48], [1.0, true, 77]]:
		var genome := game.enemies[1].genome.duplicate()
		genome["tough"] = specimen[0]
		var model := board._enemy_visual_model(genome, false, specimen[1])
		var texture: Texture2D = model["texture"]
		var bounds := texture.get_image().get_used_rect()
		native_ok = native_ok and abs(maxi(bounds.size.x, bounds.size.y) - int(specimen[2])) <= 1
		native_ok = native_ok and is_equal_approx(board.enemy_canvas_side(genome, false, specimen[1]) / texture.get_width(), 1.0 / 64.0)
	check("enemy footprints retain the 64px/cell source grid", native_ok)
	var order := board.actor_order()
	var sorted_ok := true
	for i in range(1, order.size()):
		var prev: Dictionary = order[i - 1]
		var next: Dictionary = order[i]
		sorted_ok = sorted_ok and (not prev["fly"] or next["fly"]) and (prev["fly"] != next["fly"] or prev["y"] <= next["y"])
	check("shared actor depth list and flying layer", sorted_ok)
	board.free()
	var scene = load("res://scenes/main.tscn").instantiate()
	scene._demo = true
	root.add_child(scene)
	scene.set_process(false)
	for frame in 4: await process_frame
	scene.front.hide()
	game = TDGame.new(99)
	game.gold = 100000
	var dock_ok := true
	var widths: Array[float] = []
	for kind in TDConfig.TOWER_KINDS:
		var tower := TDGame.Tower.new()
		tower.kind = kind
		tower.def = TDConfig.TOWERS[kind].duplicate(true)
		for variant in 4:
			tower.level = mini(variant + 1, 3)
			tower.branch = ("b" if variant == 3 else "a") if tower.level == 3 else ""
			scene.dock.inspect(game, {"tower": tower}, {})
			for frame in 3: await process_frame
			var inspector: Control = scene.dock._inspector
			var actions: Control = scene.dock._actions
			dock_ok = dock_ok and inspector.get_combined_minimum_size().y <= inspector.get_parent().size.y + 1.0
			dock_ok = dock_ok and scene.dock.get_global_rect().encloses(actions.get_global_rect())
			widths.append(scene.dock.size.x)
	check("40 inspector variants: no scrolling, actions inside dock", dock_ok)
	check("dock width remains constant", widths.max() - widths.min() < 0.5)
	scene.game.offer.clear()
	var key := InputEventKey.new()
	key.pressed = true
	key.keycode = KEY_1
	scene._input(key)
	check("extracted input controller selects a tower", scene.tool == "arrow")
	# Exercise every extracted controller without writing settings or meta progression.
	scene._build_perk_overlay()
	scene._build_summary(scene.over_overlay, false)
	scene._build_summary(scene.victory_overlay, true)
	scene._build_meta()
	scene.tutorial_step = 0
	scene._build_tutorial()
	scene._build_help()
	check("extracted presentation controllers build their screens", true)
	scene.queue_free()
	await process_frame
	print("Presentation checks: ", failures, " failures")
	quit(1 if failures else 0)
