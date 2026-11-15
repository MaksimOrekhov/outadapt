extends RefCounted
## Presentation controller extracted from main; run state remains owned by the root.

var host

func _init(owner: Control) -> void:
	host = owner

func _update_overlays() -> void:
	var offer_sig = ",".join(host.game.offer)
	host.perk_overlay.visible = not host.game.offer.is_empty() and host.game.phase != "over"
	if host._sig_changed("perk_overlay", offer_sig):
		TDUI.clear(host.perk_overlay)
		if not host.game.offer.is_empty():
			host._build_perk_overlay()
	var over: bool = host.game.phase == "over"
	if over and not host._run_closed:
		host._bank(true)
	host.over_overlay.visible = over
	if host._sig_changed("over", str(over) + str(host.game.wave) + str(TDMeta.points)):
		TDUI.clear(host.over_overlay)
		if over:
			host._build_summary(host.over_overlay, false)
	# победа: один раз за забег, с начислением очков
	var won = host.game.victory and not host._victory_seen and not over
	if won and not host._banked_victory:
		host._bank(false)
	host.victory_overlay.visible = won
	if host._sig_changed("victory", str(won) + str(TDMeta.points)):
		TDUI.clear(host.victory_overlay)
		if won:
			host._build_summary(host.victory_overlay, true)


func _center_in(parent: Control, content: Control) -> void:
	var cc = CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cc.add_child(content)
	parent.add_child(cc)


func _build_perk_overlay() -> void:
	var v = TDUI.vbox(18)
	var head = TDUI.hbox(10)
	head.alignment = BoxContainer.ALIGNMENT_CENTER
	head.add_child(TDUI.label("Выбери усиление", 26, TDUI.TEXT, true))
	head.add_child(TDUI.label("клик или клавиши 1–3", 13, TDUI.MUTED))
	v.add_child(head)
	var row = TDUI.hbox(16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	var i = 0
	for id in host.game.offer:
		i += 1
		var p = TDConfig.perk_def(id)
		var b = host._btn()
		b.custom_minimum_size = Vector2(230, 250)
		b.add_theme_stylebox_override("normal", TDUI.sb(Color("#30271d"), Color("#a1814c"), 2, 16, 14))
		b.add_theme_stylebox_override("hover", TDUI.sb(Color("#51412c"), TDUI.GOLD, 2, 16, 14))
		b.add_theme_stylebox_override("pressed", TDUI.sb(Color("#3e321f"), TDUI.GOLD, 2, 16, 14))
		b.pressed.connect(host._pick_perk.bind(id))
		var m = MarginContainer.new()
		m.set_anchors_preset(Control.PRESET_FULL_RECT)
		m.add_theme_constant_override("margin_left", 14)
		m.add_theme_constant_override("margin_right", 14)
		m.add_theme_constant_override("margin_top", 22)
		m.add_theme_constant_override("margin_bottom", 14)
		m.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(m)
		var c = TDUI.vbox(8)
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		m.add_child(c)
		var ic = TDUI.icon(p["icon"], 56, TDUI.GOLD)
		ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		c.add_child(ic)
		var nm = TDUI.label(p["name"], 18, TDUI.TEXT, true)
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(nm)
		var ds = TDUI.para(p["desc"], 13, Color("#c7b99e"))
		ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ds.size_flags_vertical = Control.SIZE_EXPAND_FILL
		c.add_child(ds)
		var lv = host.game.perk_level(id)
		var pl = TDUI.label("уровень %d → %d" % [lv, lv + 1], 12, TDUI.GOLD)
		pl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.add_child(pl)
		var key = TDUI.label(str(i), 12, TDUI.MUTED, true)
		key.position = Vector2(12, 8)
		b.add_child(key)
		row.add_child(b)
	host._center_in(host.perk_overlay, v)


## Итоги забега: поражение или победа на волне VICTORY_WAVE.


func _build_summary(parent: Control, won: bool) -> void:
	var p = TDUI.panel(Color("#282118"), Color("#ffd35a") if won else Color("#806440"), 18, 22, 2)
	p.custom_minimum_size = Vector2(640, 0)
	var v = TDUI.vbox(10)
	p.add_child(v)
	var survived: int = host.game.wave - 1
	var head = TDUI.hbox(14)
	head.add_child(TDUI.icon("castle", 52, TDUI.GOLD if won else TDUI.BAD))
	var hv = TDUI.vbox(2)
	var title = ("Замок выстоял %d волн!" % TDConfig.VICTORY_WAVE) if won else ("Замок пал на волне %d" % host.game.wave)
	hv.add_child(TDUI.label(title, 24, TDUI.TEXT, true))
	var sub = "%s · %s, %s · рекорд карты: %d" % [host.game.map.map_name, TDConfig.MODES[host.game.mode_id()]["name"], TDConfig.difficulty(host.game.meta)["name"].to_lower(), maxi(TDMeta.record_for(host.seed_v), survived)]
	if host._new_record and not won:
		sub = "Новый рекорд карты! " + sub
	hv.add_child(TDUI.label(sub, 13, TDUI.GOLD if host._new_record else TDUI.MUTED))
	head.add_child(hv)
	v.add_child(head)

	# главные цифры
	var nums = TDUI.hbox(8)
	for it in [["Волн пережито", str(survived)], ["Убито", str(host.game.run_kills)], ["Прорвалось", str(host.game.run_leaked)], ["Боссов", str(host.game.bosses_killed)], ["Башен", str(host.game.towers.size())]]:
		var c = TDUI.panel(TDUI.PANEL2, TDUI.LINE, 10, 8)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var cv = TDUI.vbox(0)
		var n = TDUI.label(it[1], 20, TDUI.TEXT, true)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(n)
		var l = TDUI.label(it[0], 11, TDUI.MUTED)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cv.add_child(l)
		c.add_child(cv)
		nums.add_child(c)
	v.add_child(nums)

	var cols = TDUI.hbox(12)
	# урон за забег и лучшая башня
	var left = TDUI.vbox(5)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_child(TDUI.section_title("Урон за забег"))
	var total = 0.0
	for k in host.game.run_damage:
		total += host.game.run_damage[k]
	var kinds: Array = TDConfig.TOWER_KINDS.duplicate()
	kinds.sort_custom(func(a, b): return host.game.run_damage.get(a, 0.0) > host.game.run_damage.get(b, 0.0))
	for k in kinds.slice(0, 5):
		var dmg: float = host.game.run_damage.get(k, 0.0)
		if dmg <= 0.0:
			continue
		var d: Dictionary = TDConfig.TOWERS[k]
		left.add_child(TDUI.data_row(d["icon"], Color(d["color"]), d["name"], dmg / maxf(1.0, total), Color(d["color"]), "%d%%" % round(dmg / maxf(1.0, total) * 100)))
	var mvp: TDGame.Tower = null
	for t in host.game.towers:
		if mvp == null or t.kills > mvp.kills:
			mvp = t
	if mvp != null and mvp.kills > 0:
		var md: Dictionary = TDConfig.TOWERS[mvp.kind]
		var bn = ""
		if mvp.branch != "":
			bn = " · " + String(TDConfig.branch_def(mvp.kind, mvp.branch)["name"])
		left.add_child(TDUI.para("Лучшая башня: %s%s, ур. %d — %d убийств" % [md["name"], bn, mvp.level, mvp.kills], 12, TDUI.GOLD))
	cols.add_child(left)

	# как рой приспособился
	var right = TDUI.vbox(5)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_child(TDUI.section_title("Как рой приспособился"))
	var any_shift = false
	if host.game.reports.size() >= 1:
		var first: Dictionary = host.game.reports[0]["avg"]
		var last: Dictionary = TDGenome.average_genome(host.game.upcoming)
		var diffs: Array = []
		for k in TDGenome.GENES:
			diffs.append([k, float(last.get(k, 0.0)) - float(first.get(k, 0.0))])
		diffs.sort_custom(func(a, b): return a[1] > b[1])
		for dd in diffs.slice(0, 4):
			if dd[1] < 0.05:
				continue
			any_shift = true
			right.add_child(TDUI.data_row("gene-" + String(dd[0]), Color.WHITE, TDGenome.GENE_LABELS[dd[0]], minf(1.0, float(last[dd[0]])), TDUI.BAD, "+%d%%" % round(dd[1] * 100)))
	if not any_shift:
		right.add_child(TDUI.para("Рой не успел измениться.", 12, TDUI.MUTED))
	cols.add_child(right)
	v.add_child(cols)

	# очки знаний
	if not host._demo:
		var kp = TDUI.panel(Color("#1d1a2e"), Color("#7a64c8"), 10, 10)
		var kh = TDUI.hbox(10)
		kh.add_child(TDUI.icon("perk-variety", 28, Color("#c9b5ff")))
		var kv = TDUI.vbox(0)
		kv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		kv.add_child(TDUI.label("Очки знаний: +%d  (всего %d)" % [host._run_points, TDMeta.points], 15, Color("#e3d9ff"), true))
		kv.add_child(TDUI.para("Трать их в Мастерской на постоянные улучшения для следующих забегов.", 12, TDUI.MUTED))
		kh.add_child(kv)
		kp.add_child(kh)
		v.add_child(kp)

	var row = TDUI.hbox(10)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if won:
		var cont = host._btn("Играть дальше (без конца)")
		cont.custom_minimum_size = Vector2(0, 44)
		cont.add_theme_stylebox_override("normal", TDUI.sb(Color("#2f9e44"), Color("#1f7a32"), 0, 10, 18))
		cont.add_theme_stylebox_override("hover", TDUI.sb(Color("#38b04e"), Color("#1f7a32"), 0, 10, 18))
		cont.pressed.connect(host._continue_endless)
		row.add_child(cont)
	else:
		var a = host._btn("Ещё раз на этой карте")
		a.custom_minimum_size = Vector2(0, 44)
		a.add_theme_stylebox_override("normal", TDUI.sb(Color("#2f9e44"), Color("#1f7a32"), 0, 10, 18))
		a.add_theme_stylebox_override("hover", TDUI.sb(Color("#38b04e"), Color("#1f7a32"), 0, 10, 18))
		a.pressed.connect(host._restart.bind(false))
		row.add_child(a)
	var b = host._btn("Новая карта")
	b.custom_minimum_size = Vector2(0, 44)
	b.pressed.connect(host._restart.bind(true))
	row.add_child(b)
	if not host._demo:
		var mb = host._btn("Мастерская")
		mb.custom_minimum_size = Vector2(0, 44)
		mb.pressed.connect(host._open_meta)
		row.add_child(mb)
	v.add_child(row)
	host._center_in(parent, p)


## Автопроверка вёрстки: ширина дока не должна меняться от содержимого карточки.


func _banner(text: String, sub: String, color: Color) -> void:
	var cc = CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var v = TDUI.vbox(0)
	var l = TDUI.label(text, 54, color, true)
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var sl = TDUI.label(sub, 20, Color(1, 1, 1, 0.8))
	sl.add_theme_constant_override("outline_size", 6)
	sl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.75))
	sl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sl)
	cc.add_child(v)
	cc.pivot_offset = host.stage.size * 0.5
	cc.modulate.a = 0.0
	host.stage.add_child(cc)
	var tw = host.create_tween()
	tw.tween_property(cc, "modulate:a", 1.0, 0.18)
	tw.parallel().tween_property(cc, "scale", Vector2.ONE, 0.32).from(Vector2(1.6, 1.6)).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(0.75)
	tw.tween_property(cc, "modulate:a", 0.0, 0.45)
	tw.parallel().tween_property(cc, "scale", Vector2(0.92, 0.92), 0.45)
	tw.tween_callback(cc.queue_free)


# ── подсказки у курсора ───────────────────────────────────────


