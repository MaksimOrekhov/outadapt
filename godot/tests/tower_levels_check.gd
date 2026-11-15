extends SceneTree
## Asset contract and specialization resolution, without altering simulation or saves.

func _initialize() -> void:
	var count := 0
	for kind in ["arrow", "cannon", "ember", "frost", "sniper", "poison", "flak", "tesla", "net", "beacon"]:
		var bases := {}
		var heads := {}
		for variant in 4:
			var level := mini(variant + 1, 3)
			var branch := "b" if variant == 3 else "a"
			var data := TDArt.tower_level(kind, level, branch)
			assert(data.get("pixel_scale", 0) == 64, kind + " pixel scale")
			assert(data["base_size"][0] == 64 and data["base_size"][1] <= 112)
			assert(data["ground"] == data["base_size"][1])
			assert(data["mount"] < data["ground"])
			assert(data["weapon"]["frame"] == 96 and data["weapon"]["frame_h"] == 96)
			for path in [data["base"], data["weapon"]["file"]]:
				var texture := TDArt.tex(path)
				assert(texture != null, path)
				var img := texture.get_image()
				for y in img.get_height():
					for x in img.get_width():
						var alpha := img.get_pixel(x, y).a
						assert(alpha == 0.0 or alpha == 1.0, path + " soft edge")
			bases[TDArt.tex(data["base"]).get_image().get_data().hex_encode().sha256_text()] = true
			heads[TDArt.tex(data["weapon"]["file"]).get_image().get_data().hex_encode().sha256_text()] = true
			count += 1
		assert(bases.size() == 3, kind + " repeated base")
		assert(heads.size() == 4, kind + " repeated head")
		var selected := TDArt.tower_level(kind, 3, "b")
		selected["weapon"]["file"] = "invalid"
		assert(TDArt.tower_level(kind, 3, "b")["weapon"]["file"] != "invalid", "metadata was mutated")
	print("OK: ", count, " tower variants; unique sprites, hard alpha, scale and branch isolation")
	quit()
