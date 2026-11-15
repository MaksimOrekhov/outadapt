class_name TDSprites
extends RefCounted
## Legacy environment fallback sprites only; towers and enemies use raster assets.

const PX := 192
const HEAD := "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 128 128\" width=\"128\" height=\"128\">"
const TAIL := "</svg>"

static var _cache: Dictionary = {}


static func tex(sprite_name: String) -> Texture2D:
	if _cache.has(sprite_name):
		return _cache[sprite_name]
	var t: Texture2D = null
	var svg := _svg(sprite_name)
	if svg != "":
		var img := Image.new()
		if img.load_svg_from_string(svg, PX / 128.0) == OK:
			img.generate_mipmaps()
			t = ImageTexture.create_from_image(img)
		else:
			push_warning("SVG не разобран: " + sprite_name)
	_cache[sprite_name] = t
	return t


static func all_names() -> Array[String]:
	return ["d_pine", "d_oak", "d_bush", "d_rock1", "d_rock2", "d_pond", "d_crystal", "d_portal", "d_swirl", "d_castle"]


static func _svg(n: String) -> String:
	match n:
		"d_pine": return _d_pine()
		"d_oak": return _d_oak()
		"d_bush": return _d_bush()
		"d_rock1": return _d_rock1()
		"d_rock2": return _d_rock2()
		"d_pond": return _d_pond()
		"d_crystal": return _d_crystal()
		"d_portal": return _d_portal()
		"d_swirl": return _d_swirl()
		"d_castle": return _d_castle()
	return ""


# ── окружение ─────────────────────────────────────────────────

static func _d_pine() -> String:
	var s := HEAD
	s += "<defs><linearGradient id=\"p\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"#3a9560\"/><stop offset=\"1\" stop-color=\"#164a30\"/></linearGradient></defs>"
	s += "<rect x=\"58\" y=\"94\" width=\"12\" height=\"22\" rx=\"2\" fill=\"#5b3c22\" stroke=\"#2d1e0f\" stroke-width=\"2\"/>"
	s += "<path d=\"M64 50 L98 106 L30 106 Z\" fill=\"url(#p)\" stroke=\"#0e2e1d\" stroke-width=\"3\" stroke-linejoin=\"round\"/>"
	s += "<path d=\"M64 28 L92 78 L36 78 Z\" fill=\"url(#p)\" stroke=\"#0e2e1d\" stroke-width=\"3\" stroke-linejoin=\"round\"/>"
	s += "<path d=\"M64 4 L86 52 L42 52 Z\" fill=\"url(#p)\" stroke=\"#0e2e1d\" stroke-width=\"3\" stroke-linejoin=\"round\"/>"
	s += "<path d=\"M64 4 L42 52 L52 52 Z M64 28 L36 78 L48 78 Z M64 50 L30 106 L44 106 Z\" fill=\"#fff\" opacity=\"0.13\"/>"
	s += "<path d=\"M42 52 L86 52 M36 78 L92 78\" stroke=\"#0e2e1d\" stroke-opacity=\"0.35\" stroke-width=\"2\"/>"
	return s + TAIL


static func _d_oak() -> String:
	var s := HEAD
	s += "<defs><radialGradient id=\"c\" cx=\"0.4\" cy=\"0.3\" r=\"0.8\"><stop offset=\"0\" stop-color=\"#7fcf5a\"/><stop offset=\"0.6\" stop-color=\"#3f9a45\"/><stop offset=\"1\" stop-color=\"#1d5a30\"/></radialGradient></defs>"
	s += "<path d=\"M55 116 L58 76 L70 76 L74 116 Z\" fill=\"#6b4423\" stroke=\"#2d1e0f\" stroke-width=\"2.5\" stroke-linejoin=\"round\"/>"
	s += "<path d=\"M62 84 L50 70 M66 82 L80 68\" stroke=\"#4a2f18\" stroke-width=\"4\" stroke-linecap=\"round\"/>"
	for c in [[38.0, 66.0, 26.0], [90.0, 66.0, 26.0], [64.0, 76.0, 28.0], [46.0, 40.0, 26.0], [84.0, 40.0, 26.0], [64.0, 28.0, 25.0]]:
		s += "<circle cx=\"%.0f\" cy=\"%.0f\" r=\"%.0f\" fill=\"url(#c)\" stroke=\"#143f26\" stroke-width=\"3\"/>" % [c[0], c[1], c[2]]
	for h in [[52.0, 30.0, 9.0], [80.0, 44.0, 8.0], [40.0, 62.0, 8.0], [66.0, 60.0, 9.0]]:
		s += "<circle cx=\"%.0f\" cy=\"%.0f\" r=\"%.0f\" fill=\"#d9ffb0\" opacity=\"0.22\"/>" % [h[0], h[1], h[2]]
	return s + TAIL


static func _d_bush() -> String:
	var s := HEAD
	s += "<defs><radialGradient id=\"c\" cx=\"0.4\" cy=\"0.3\" r=\"0.8\"><stop offset=\"0\" stop-color=\"#7fcf5a\"/><stop offset=\"0.6\" stop-color=\"#3f9a45\"/><stop offset=\"1\" stop-color=\"#1d5a30\"/></radialGradient></defs>"
	for c in [[40.0, 96.0, 20.0], [88.0, 96.0, 20.0], [64.0, 86.0, 25.0]]:
		s += "<circle cx=\"%.0f\" cy=\"%.0f\" r=\"%.0f\" fill=\"url(#c)\" stroke=\"#143f26\" stroke-width=\"3\"/>" % [c[0], c[1], c[2]]
	for b in [[52.0, 80.0], [74.0, 92.0], [92.0, 88.0], [38.0, 98.0], [64.0, 100.0]]:
		s += "<circle cx=\"%.0f\" cy=\"%.0f\" r=\"3.6\" fill=\"#e0453a\" stroke=\"#6a1b12\" stroke-width=\"1.2\"/>" % [b[0], b[1]]
	s += "<ellipse cx=\"54\" cy=\"74\" rx=\"10\" ry=\"5\" fill=\"#e0ffc0\" opacity=\"0.25\" transform=\"rotate(-20 54 74)\"/>"
	return s + TAIL


static func _d_rock1() -> String:
	var s := HEAD
	s += "<defs><linearGradient id=\"r\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\"><stop offset=\"0\" stop-color=\"#a3adbf\"/><stop offset=\"0.55\" stop-color=\"#667087\"/><stop offset=\"1\" stop-color=\"#353c4e\"/></linearGradient></defs>"
	s += "<path d=\"M16 112 L10 82 L30 54 L62 44 L98 54 L118 84 L112 112 Z\" fill=\"url(#r)\" stroke=\"#1a2030\" stroke-width=\"4\" stroke-linejoin=\"round\"/>"
	s += "<path d=\"M30 54 L50 78 L40 112 M62 44 L66 76 L50 78 M98 54 L84 82 L66 76 M84 82 L88 112\" fill=\"none\" stroke=\"#1a2030\" stroke-opacity=\"0.45\" stroke-width=\"2.5\" stroke-linejoin=\"round\"/>"
	s += "<path d=\"M30 54 L62 44 L66 76 L50 78 Z\" fill=\"#fff\" opacity=\"0.16\"/>"
	s += "<path d=\"M24 62 Q46 42 78 48 Q56 58 34 74 Z\" fill=\"#5c9a4a\" opacity=\"0.85\"/>"
	return s + TAIL


static func _d_rock2() -> String:
	var s := HEAD
	s += "<defs><linearGradient id=\"r\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\"><stop offset=\"0\" stop-color=\"#9fa9bc\"/><stop offset=\"0.55\" stop-color=\"#636d84\"/><stop offset=\"1\" stop-color=\"#333a4b\"/></linearGradient></defs>"
	s += "<path d=\"M52 112 L46 70 L62 52 L86 56 L100 80 L96 112 Z\" fill=\"url(#r)\" stroke=\"#1a2030\" stroke-width=\"4\" stroke-linejoin=\"round\"/>"
	s += "<path d=\"M8 112 L6 92 L20 76 L40 80 L52 98 L50 112 Z\" fill=\"url(#r)\" stroke=\"#1a2030\" stroke-width=\"4\" stroke-linejoin=\"round\"/>"
	s += "<path d=\"M62 52 L66 82 L46 70 Z\" fill=\"#fff\" opacity=\"0.16\"/><path d=\"M20 76 L26 94 L6 92 Z\" fill=\"#fff\" opacity=\"0.14\"/>"
	s += "<path d=\"M104 112 Q112 100 118 112 Z\" fill=\"#667087\" stroke=\"#1a2030\" stroke-width=\"3\"/>"
	return s + TAIL


static func _d_pond() -> String:
	var s := HEAD
	s += "<defs><radialGradient id=\"w\" cx=\"0.4\" cy=\"0.35\" r=\"0.75\"><stop offset=\"0\" stop-color=\"#7fd0e8\"/><stop offset=\"0.6\" stop-color=\"#2f78a8\"/><stop offset=\"1\" stop-color=\"#16466a\"/></radialGradient></defs>"
	s += "<ellipse cx=\"64\" cy=\"68\" rx=\"56\" ry=\"42\" fill=\"#2a2218\"/>"
	s += "<ellipse cx=\"64\" cy=\"66\" rx=\"52\" ry=\"38\" fill=\"#4a3c2a\"/>"
	s += "<ellipse cx=\"64\" cy=\"66\" rx=\"47\" ry=\"33\" fill=\"url(#w)\" stroke=\"#0c2a44\" stroke-width=\"3\"/>"
	s += "<ellipse cx=\"64\" cy=\"66\" rx=\"34\" ry=\"22\" fill=\"none\" stroke=\"#fff\" stroke-opacity=\"0.22\" stroke-width=\"2\"/>"
	s += "<ellipse cx=\"46\" cy=\"54\" rx=\"12\" ry=\"5\" fill=\"#fff\" opacity=\"0.3\" transform=\"rotate(-15 46 54)\"/>"
	s += "<ellipse cx=\"84\" cy=\"74\" rx=\"12\" ry=\"7\" fill=\"#4aa860\" stroke=\"#1d5a30\" stroke-width=\"2\"/><circle cx=\"84\" cy=\"72\" r=\"3.4\" fill=\"#ff9ad0\"/>"
	s += "<path d=\"M20 84 Q18 62 22 48 M28 88 Q28 68 34 56 M104 50 Q108 38 112 30\" stroke=\"#4a7a3a\" stroke-width=\"3.5\" fill=\"none\" stroke-linecap=\"round\"/>"
	return s + TAIL


static func _d_crystal() -> String:
	var s := HEAD
	s += "<defs><linearGradient id=\"a\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\"><stop offset=\"0\" stop-color=\"#f0e4ff\"/><stop offset=\"0.5\" stop-color=\"#a77cf0\"/><stop offset=\"1\" stop-color=\"#4b2a96\"/></linearGradient></defs>"
	s += "<path d=\"M30 110 L20 70 L36 80 L40 112 Z\" fill=\"url(#a)\" stroke=\"#2c1a63\" stroke-width=\"3\" stroke-linejoin=\"round\"/>"
	s += "<path d=\"M98 112 L104 76 L116 94 L112 112 Z\" fill=\"url(#a)\" stroke=\"#2c1a63\" stroke-width=\"3\" stroke-linejoin=\"round\"/>"
	s += "<path d=\"M64 8 L86 52 L82 112 L46 112 L42 52 Z\" fill=\"url(#a)\" stroke=\"#2c1a63\" stroke-width=\"3.5\" stroke-linejoin=\"round\"/>"
	s += "<path d=\"M64 8 L64 112 L46 112 L42 52 Z\" fill=\"#fff\" opacity=\"0.28\"/>"
	s += "<path d=\"M54 40 L60 28\" stroke=\"#fff\" stroke-width=\"3.5\" stroke-linecap=\"round\" opacity=\"0.85\"/>"
	return s + TAIL


static func _d_portal() -> String:
	var runes := ""
	for i in 10:
		var a := i * TAU / 10.0
		runes += "<rect x=\"-2.4\" y=\"-6\" width=\"4.8\" height=\"12\" rx=\"2\" fill=\"#b58cff\" transform=\"translate(%.1f %.1f) rotate(%.1f)\"/>" % [64.0 + cos(a) * 48.0, 64.0 + sin(a) * 48.0, rad_to_deg(a) + 90.0]
	var s := HEAD
	s += "<defs>"
	s += "<radialGradient id=\"v\" cx=\"0.5\" cy=\"0.5\" r=\"0.5\"><stop offset=\"0\" stop-color=\"#e9dcff\"/><stop offset=\"0.25\" stop-color=\"#8a5cf0\"/><stop offset=\"0.75\" stop-color=\"#2d1670\"/><stop offset=\"1\" stop-color=\"#120a30\"/></radialGradient>"
	s += "<linearGradient id=\"s\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\"><stop offset=\"0\" stop-color=\"#8d97ad\"/><stop offset=\"1\" stop-color=\"#394156\"/></linearGradient>"
	s += "</defs>"
	s += "<ellipse cx=\"64\" cy=\"74\" rx=\"58\" ry=\"50\" fill=\"#000\" opacity=\"0.35\"/>"
	s += "<circle cx=\"64\" cy=\"64\" r=\"58\" fill=\"url(#s)\" stroke=\"#12101e\" stroke-width=\"4\"/>"
	s += "<circle cx=\"64\" cy=\"64\" r=\"41\" fill=\"#0b0718\" stroke=\"#12101e\" stroke-width=\"3\"/>"
	s += "<circle cx=\"64\" cy=\"64\" r=\"38\" fill=\"url(#v)\"/>"
	s += runes
	s += "<path d=\"M16 44 A52 52 0 0 1 64 12\" stroke=\"#fff\" stroke-opacity=\"0.18\" stroke-width=\"5\" fill=\"none\" stroke-linecap=\"round\"/>"
	return s + TAIL


static func _d_swirl() -> String:
	var s := HEAD
	s += "<defs><linearGradient id=\"g\" x1=\"0\" y1=\"0\" x2=\"1\" y2=\"1\"><stop offset=\"0\" stop-color=\"#ffffff\" stop-opacity=\"0.9\"/><stop offset=\"1\" stop-color=\"#9a6bff\" stop-opacity=\"0.1\"/></linearGradient></defs>"
	for i in 3:
		s += "<path d=\"M64 64 Q84 40 100 62 Q102 88 70 96\" fill=\"none\" stroke=\"url(#g)\" stroke-width=\"7\" stroke-linecap=\"round\" transform=\"rotate(%d 64 64)\"/>" % (i * 120)
	return s + TAIL


static func _d_castle() -> String:
	var cren := ""
	for i in 7:
		cren += "<rect x=\"%d\" y=\"54\" width=\"8\" height=\"10\" fill=\"url(#st)\" stroke=\"#1a1218\" stroke-width=\"2\"/>" % (24 + i * 12)
	var s := HEAD
	s += "<defs>"
	s += "<linearGradient id=\"st\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"#b9a99c\"/><stop offset=\"1\" stop-color=\"#6a5a54\"/></linearGradient>"
	s += "<linearGradient id=\"rf\" x1=\"0\" y1=\"0\" x2=\"0\" y2=\"1\"><stop offset=\"0\" stop-color=\"#e8604f\"/><stop offset=\"1\" stop-color=\"#8f2418\"/></linearGradient>"
	s += "<radialGradient id=\"gt\" cx=\"0.5\" cy=\"0.6\" r=\"0.6\"><stop offset=\"0\" stop-color=\"#ffd27a\"/><stop offset=\"1\" stop-color=\"#5a2a10\"/></radialGradient>"
	s += "</defs>"
	s += "<ellipse cx=\"64\" cy=\"116\" rx=\"58\" ry=\"9\" fill=\"#000\" opacity=\"0.35\"/>"
	s += "<rect x=\"22\" y=\"62\" width=\"84\" height=\"54\" fill=\"url(#st)\" stroke=\"#1a1218\" stroke-width=\"3\"/>" + cren
	s += "<rect x=\"46\" y=\"26\" width=\"36\" height=\"38\" fill=\"url(#st)\" stroke=\"#1a1218\" stroke-width=\"3\"/>"
	s += "<path d=\"M42 28 L64 4 L86 28 Z\" fill=\"url(#rf)\" stroke=\"#4a1008\" stroke-width=\"3\" stroke-linejoin=\"round\"/>"
	s += "<rect x=\"6\" y=\"40\" width=\"28\" height=\"76\" fill=\"url(#st)\" stroke=\"#1a1218\" stroke-width=\"3\"/>"
	s += "<path d=\"M2 44 L20 12 L38 44 Z\" fill=\"url(#rf)\" stroke=\"#4a1008\" stroke-width=\"3\" stroke-linejoin=\"round\"/>"
	s += "<rect x=\"94\" y=\"40\" width=\"28\" height=\"76\" fill=\"url(#st)\" stroke=\"#1a1218\" stroke-width=\"3\"/>"
	s += "<path d=\"M90 44 L108 12 L126 44 Z\" fill=\"url(#rf)\" stroke=\"#4a1008\" stroke-width=\"3\" stroke-linejoin=\"round\"/>"
	s += "<path d=\"M50 116 L50 92 Q64 76 78 92 L78 116 Z\" fill=\"url(#gt)\" stroke=\"#1a1218\" stroke-width=\"3\"/>"
	s += "<path d=\"M64 80 L64 116 M54 98 L74 98\" stroke=\"#3a1f0c\" stroke-width=\"2.5\"/>"
	for w in [[16.0, 62.0], [100.0, 62.0], [58.0, 40.0]]:
		s += "<rect x=\"%.0f\" y=\"%.0f\" width=\"9\" height=\"13\" rx=\"4\" fill=\"#ffd27a\" stroke=\"#3a2208\" stroke-width=\"1.8\"/>" % [w[0], w[1]]
	s += "<line x1=\"20\" y1=\"12\" x2=\"20\" y2=\"-2\" stroke=\"#3a2a20\" stroke-width=\"2\"/><path d=\"M20 -2 L34 3 L20 8 Z\" fill=\"#ff6b7a\"/>"
	s += "<line x1=\"108\" y1=\"12\" x2=\"108\" y2=\"-2\" stroke=\"#3a2a20\" stroke-width=\"2\"/><path d=\"M108 -2 L122 3 L108 8 Z\" fill=\"#ff6b7a\"/>"
	s += "<path d=\"M16 44 L16 112 M28 44 L28 112\" stroke=\"#fff\" stroke-opacity=\"0.08\" stroke-width=\"3\"/>"
	return s + TAIL
