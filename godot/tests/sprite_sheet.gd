extends SceneTree
## Контактный лист спрайтов: godot --headless --path godot --script res://tests/sprite_sheet.gd -- out.png

func _init() -> void:
	var names := TDSprites.all_names()
	var cols := 7
	var cell := 192
	var rows := int(ceil(names.size() / float(cols)))
	var sheet := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#1d283a"))
	var bad := 0
	for i in names.size():
		var t := TDSprites.tex(names[i])
		if t == null:
			print("НЕТ: ", names[i])
			bad += 1
			continue
		var img: Image = t.get_image()
		if img.is_compressed():
			img.decompress()
		if img.get_format() != Image.FORMAT_RGBA8:
			img.convert(Image.FORMAT_RGBA8)
		if img.has_mipmaps():
			img.clear_mipmaps()
		sheet.blend_rect(img, Rect2i(0, 0, cell, cell), Vector2i((i % cols) * cell, (i / cols) * cell))
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "sheet.png"
	sheet.save_png(out)
	print("спрайтов: ", names.size(), ", ошибок: ", bad)
	quit()
