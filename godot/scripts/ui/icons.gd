class_name TDIcons
extends RefCounted
## Иконки game-icons.net: SVG растеризуется один раз в белую текстуру, цвет задаётся через modulate.

const RES := 128

static var _cache: Dictionary = {}


static func tex(icon_name: String) -> Texture2D:
	if _cache.has(icon_name):
		return _cache[icon_name]
	var t: Texture2D = null
	if icon_name == "portal":
		var portal := AtlasTexture.new()
		portal.atlas = load("res://assets/biomes/portal.png")
		portal.region = Rect2(0, 0, 128, 128)
		_cache[icon_name] = portal
		return portal
	var custom_path := "res://assets/ui/icon_" + icon_name + ".png"
	if ResourceLoader.exists(custom_path):
		t = load(custom_path)
		_cache[icon_name] = t
		return t
	var body: String = TDIconData.BODIES.get(icon_name, "")
	if body != "":
		var svg := "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 512 512\" width=\"512\" height=\"512\">" + body + "</svg>"
		var img := Image.new()
		if img.load_svg_from_string(svg, RES / 512.0) == OK:
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
	_cache[icon_name] = t
	return t
