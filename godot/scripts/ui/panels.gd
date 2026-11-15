class_name TDPanels
extends RefCounted
## Содержимое всплывающих панелей: советы, сводка «Рой», карточка врага у курсора.

static func tower_chip(kind: String, on_pick: Callable) -> PanelContainer:
	var d: Dictionary = TDConfig.TOWERS[kind]
	var c := TDUI.chip(d["icon"], d["name"], Color(d["color"]), "Выбрать: " + d["name"])
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	c.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	c.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			on_pick.call(kind))
	return c


static func last_report(g: TDGame) -> Dictionary:
	return g.reports[g.reports.size() - 1] if not g.reports.is_empty() else {}


## Что сделать прямо сейчас.
static func advice(g: TDGame, tips: Array, on_pick: Callable) -> VBoxContainer:
	var v := TDUI.vbox(8)
	v.add_child(TDUI.section_title("Советы на следующую волну"))
	for t in tips:
		var danger: bool = t["level"] == "danger"
		var col := Color(t["color"])
		var tp := TDUI.panel(Color(0.45, 0.12, 0.16, 0.25) if danger else Color("#30291f"), Color(1, 0.42, 0.48, 0.5) if danger else TDUI.LINE, 10, 10)
		var h := TDUI.hbox(10)
		tp.add_child(h)
		h.add_child(TDUI.icon(t["icon"], 28, col))
		var c := TDUI.vbox(4)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(c)
		c.add_child(TDUI.label(t["title"], 14, TDUI.BAD if danger else TDUI.TEXT, true))
		c.add_child(TDUI.para(t["text"], 13, Color("#c7b99e")))
		var fl := TDUI.flow(6)
		for k in t["towers"]:
			fl.add_child(tower_chip(k, on_pick))
		c.add_child(fl)
		v.add_child(tp)
	return v


## Сводка: итог прошлой волны, смещение роя, гены, перки.
static func swarm(g: TDGame) -> VBoxContainer:
	var v := TDUI.vbox(12)
	var r := last_report(g)
	if r.is_empty():
		v.add_child(TDUI.para("Пока нет данных. После первой волны здесь появится итог и то, как изменился рой.", 13, TDUI.MUTED))
	else:
		var pv := _section("Итог волны %d" % r["wave"])
		var fl := TDUI.flow(6)
		fl.add_child(TDUI.chip("", "убито %d из %d" % [r["killed"], r["size"]], TDUI.TEXT))
		fl.add_child(TDUI.chip("", "прорвалось %d" % r["leaked"], TDUI.BAD if r["leaked"] > 0 else TDUI.TEXT))
		pv[1].add_child(fl)
		var total := 0.0
		for k in TDConfig.TOWER_KINDS:
			total += r["damageBy"].get(k, 0.0)
		if total == 0.0:
			total = 1.0
		for k in TDConfig.TOWER_KINDS:
			var dmg: float = r["damageBy"].get(k, 0.0)
			if dmg > 0.0:
				var d: Dictionary = TDConfig.TOWERS[k]
				pv[1].add_child(TDUI.data_row(d["icon"], Color(d["color"]), d["name"], dmg / total, Color(d["color"]), "%d%%" % round(dmg / total * 100)))
		v.add_child(pv[0])
		# смещение
		var shifts: Array = []
		for k in TDGenome.GENES:
			var dd: float = r["nextAvg"][k] - r["avg"][k]
			if absf(dd) >= 0.04:
				shifts.append([k, dd])
		shifts.sort_custom(func(a, b): return absf(a[1]) > absf(b[1]))
		if shifts.size() > 0:
			var sv := _section("Рой изменился")
			var sf := TDUI.flow(6)
			for s in shifts.slice(0, 5):
				var up: bool = s[1] > 0
				sf.add_child(TDUI.chip("gene-" + String(s[0]), ("▲ " if up else "▼ ") + TDGenome.GENE_LABELS[s[0]], TDUI.BAD if up else TDUI.OK, TDGenome.GENE_HELP[s[0]]))
			sv[1].add_child(sf)
			for line in pressure_lines(r):
				sv[1].add_child(TDUI.para(line, 12, Color("#c7b99e")))
			v.add_child(sv[0])
	# гены
	var gv := _section("Гены следующей волны")
	var avg := TDGenome.average_genome(g.upcoming)
	for k in TDGenome.GENES:
		var row := TDUI.data_row("gene-" + k, Color.WHITE, TDGenome.GENE_LABELS[k], avg[k], TDUI.ACCENT, "%d%%" % round(minf(1.0, avg[k]) * 100))
		row.tooltip_text = TDGenome.GENE_HELP[k]
		gv[1].add_child(row)
	v.add_child(gv[0])
	# перки
	var owned: Array = []
	for p in TDConfig.PERKS:
		if g.perk_level(p["id"]) > 0:
			owned.append(p)
	if owned.size() > 0:
		var pv2 := _section("Твои усиления")
		for p in owned:
			var lvl := g.perk_level(p["id"])
			var row2 := TDUI.hbox(8)
			row2.add_child(TDUI.icon(p["icon"], 20, TDUI.GOLD))
			var col := TDUI.vbox(0)
			col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			col.add_child(TDUI.label(p["name"] + (" ×%d" % lvl if lvl > 1 else ""), 13, TDUI.TEXT, true))
			col.add_child(TDUI.para(p["desc"], 11, TDUI.MUTED))
			row2.add_child(col)
			pv2[1].add_child(row2)
		v.add_child(pv2[0])
	return v


const _PRESSURE_WHY := {
	"plated": "был физическим — рой наращивает броню. Огонь плавит её, Снайпер пробивает.",
	"ember": "был огнём — рой становится огнестойким. Добавь физический урон или лёд.",
	"frost": "был льдом — рой привыкает к холоду. Добавь огонь или яд.",
	"tough": "шёл сквозь броню (яд, молния) — рой копит здоровье.",
}


## Почему рой изменился: «64% урона было физическим — рой наращивает броню».
static func pressure_lines(r: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var press: Dictionary = r.get("pressure", {})
	var keys := press.keys()
	keys.sort_custom(func(a, b): return press[a] > press[b])
	for k in keys:
		if press[k] >= 0.3 and _PRESSURE_WHY.has(k) and out.size() < 2:
			out.append("%d%% урона %s" % [round(press[k] * 100), _PRESSURE_WHY[k]])
	return out


static func _section(title: String) -> Array:
	var p := TDUI.panel(TDUI.PANEL2, TDUI.LINE, 10, 12)
	var v := TDUI.vbox(7)
	p.add_child(v)
	v.add_child(TDUI.section_title(title))
	return [p, v]


static func trait_list(e: TDGame.Enemy) -> Array:
	var list: Array = []
	if e.boss:
		list.append(["boss", Color("#ff6b7a"), "БОСС"])
		if e.ability != "":
			list.append(["boss", Color("#ffb347"), TDConfig.BOSS_ABILITIES[e.ability]["name"]])
	if e.ph["fly"]:
		list.append(["gene-wings", Color("#9ad7ff"), "летит"])
	if e.ph["stealth"]:
		list.append(["gene-veil", Color("#c9a0ff"), "невидим"])
	if e.ph.get("split", false):
		list.append(["gene-split", Color("#e08af0"), "делится"])
	if e.ph.get("ward", false):
		list.append(["gene-ward", Color("#8fd0ff"), "щит соседям"])
	if e.warded:
		list.append(["gene-ward", Color("#8fd0ff"), "под щитом"])
	if e.child:
		list.append(["gene-split", Color("#e08af0"), "малыш"])
	for t in TDBoard.TRAITS:
		if e.genome[t[0]] >= 0.3 and not (e.boss and t[0] == "tough"):
			list.append(["gene-" + String(t[0]), Color(t[1]), TDGenome.GENE_LABELS[t[0]]])
	return list


## Карточка врага у курсора: здоровье, черты, чем бить.
static func enemy_tip(g: TDGame, e: TDGame.Enemy) -> VBoxContainer:
	var v := TDUI.vbox(7)
	var frac: float = clampf(e.hp / e.ph["hp"], 0.0, 1.0)
	var hr := TDUI.hbox(8)
	hr.add_child(TDUI.bar(frac, Color("#6fd36f") if frac > 0.5 else (Color("#e8c04a") if frac > 0.25 else Color("#e8604a")), 10))
	hr.add_child(TDUI.label("%d / %d" % [ceili(e.hp), roundi(e.ph["hp"])], 12, TDUI.TEXT, true))
	v.add_child(hr)
	if e.boss and e.ability != "":
		var info: Dictionary = TDConfig.BOSS_ABILITIES[e.ability]
		var text: String = info["desc"]
		if e.ability == "immune":
			text = "Почти не боится урона по: %s (×%.2f)" % [TDConfig.TYPE_NAMES.get(e.immune_type, e.immune_type), TDConfig.IMMUNE_MULT]
		v.add_child(TDUI.para(text, 12, Color("#ffcf8a")))
		if e.shield_max > 0.0:
			var sr := TDUI.hbox(8)
			sr.add_child(TDUI.bar(clampf(e.shield / e.shield_max, 0.0, 1.0), Color("#6ab7ff"), 8))
			sr.add_child(TDUI.label("щит %d" % ceili(e.shield) if e.shield > 0.0 else "щит пробит", 12, Color("#9fd2ff"), true))
			v.add_child(sr)
	var fl := TDUI.flow(5)
	var traits := trait_list(e)
	for t in traits:
		fl.add_child(TDUI.mini_chip(t[0], t[1], t[2]))
	if traits.is_empty():
		fl.add_child(TDUI.mini_chip("", TDUI.MUTED, "обычный"))
	var st := TDGame.status_of(e)
	if st["chilled"]:
		fl.add_child(TDUI.mini_chip("st-frozen", Color("#9fdcff"), "заморожен"))
	if st["scorched"]:
		fl.add_child(TDUI.mini_chip("st-burn", Color("#ff9a5c"), "обожжён"))
	if st["poisoned"]:
		fl.add_child(TDUI.mini_chip("st-poison", Color("#7ddc5a"), "отравлен"))
	v.add_child(fl)
	if e.ph["stealth"]:
		v.add_child(TDUI.para("Невидим: бьют вплотную или рядом с Маяком.", 11, TDUI.MUTED))
	var m := g.mods()
	var rows: Array = []
	for k in TDConfig.TOWER_KINDS:
		var d: Dictionary = TDConfig.TOWERS[k]
		if d.has("aura") or not TDGame.can_hit(d, e):
			continue
		var dmg := TDGame.effective_damage(g.damage_of(k), d["type"], e.ph, TDGame.status_of(e), m, d.get("pierce", 0.0))
		if e.boss and e.ability == "immune" and d["type"] == e.immune_type:
			dmg *= TDConfig.IMMUNE_MULT
		rows.append([k, dmg])
	rows.sort_custom(func(a, b): return a[1] / TDConfig.TOWERS[a[0]]["damage"] > b[1] / TDConfig.TOWERS[b[0]]["damage"])
	v.add_child(TDUI.label("УРОН ЗА УДАР", 10, TDUI.MUTED, true))
	for r in rows:
		var d2: Dictionary = TDConfig.TOWERS[r[0]]
		v.add_child(TDUI.data_row(d2["icon"], Color(d2["color"]), d2["name"], minf(1.0, r[1] / d2["damage"] / 1.5), Color(d2["color"]), "%.1f" % r[1]))
	return v
