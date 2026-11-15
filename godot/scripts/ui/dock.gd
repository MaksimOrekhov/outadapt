class_name TDDock
extends PanelContainer
## Левый док: магазин башен (сетка с вкладками, масштабируется на любое число башен)
## и инспектор — подробности о том, на что наведён курсор или что выбрано.

signal tool_selected(kind: String)
signal sell_tool_selected
signal sell_tower_requested
signal tile_hovered(kind: String)
signal upgrade_requested(branch: String)
signal mode_requested(mode: String)

const TILE := Vector2(88, 100)
const COLS := 3

var tiles: Dictionary = {}
var _cat: String = "all"
var _tab_btns: Dictionary = {}
var _scroll: ScrollContainer
var _grid: GridContainer
var _sell_btn: Button
var _actions: VBoxContainer
var _inspector: VBoxContainer
var _perks_wrap: VBoxContainer
var _perks_flow: HFlowContainer
var _sig: Dictionary = {}
var _stat_max: Dictionary = {}
var _tile_state: Dictionary = {}
var _sell_on: bool = false
var _catalog: VBoxContainer
var _catalog_toggle: Button
var _inspector_scroll: ScrollContainer
var _has_tower := false


func setup() -> void:
	_stat_max = TDConfig.tower_stat_max()
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_stylebox_override("panel", TDUI.skin("frame", 12))
	custom_minimum_size = Vector2(320, 0)
	var v := TDUI.vbox(5)
	add_child(v)

	# заголовок и вкладки
	var head := TDUI.hbox(6)
	_catalog_toggle = TDUI.action("Башни  ▾", func():
		_catalog.visible = not _catalog.visible)
	_catalog_toggle.tooltip_text = "Открыть или свернуть каталог башен"
	head.add_child(_catalog_toggle)
	head.add_child(TDUI.spacer())
	var hk := TDUI.label("Q / E — листать", 10, Color("#b5c4be"))
	head.add_child(hk)
	v.add_child(head)
	_catalog = TDUI.vbox(8)
	_catalog.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_catalog)
	var tabs := TDUI.flow(4)
	for c in TDConfig.CATEGORIES:
		var b := Button.new()
		b.text = c["name"]
		b.focus_mode = Control.FOCUS_ALL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_font_size_override("font_size", 14)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var id: String = c["id"]
		b.pressed.connect(func(): set_category(id))
		_tab_btns[id] = b
		tabs.add_child(b)
	_catalog.add_child(tabs)

	# сетка плиток
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.custom_minimum_size.y = TILE.y
	_catalog.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = COLS
	_grid.add_theme_constant_override("h_separation", 5)
	_grid.add_theme_constant_override("v_separation", 6)
	_scroll.add_child(_grid)
	var i := 0
	for kind in TDConfig.TOWER_KINDS:
		_grid.add_child(_make_tile(kind, i))
		i += 1

	# режим продажи
	_sell_btn = Button.new()
	_sell_btn.focus_mode = Control.FOCUS_ALL
	_sell_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_sell_btn.text = "X"
	_sell_btn.icon = TDIcons.tex("sell")
	_sell_btn.expand_icon = true
	_sell_btn.add_theme_font_size_override("font_size", 14)
	_sell_btn.pressed.connect(func(): sell_tool_selected.emit())
	_sell_btn.tooltip_text = "Режим продажи: клик по башне продаёт её за %d%% цены. Правый клик продаёт всегда." % round(TDConfig.SELL_RATIO * 100)
	head.add_child(_sell_btn)

	# инспектор
	var ip := TDUI.panel(Color("#101a1b"), Color("#5f4d36"), 10, 10)
	ip.add_theme_stylebox_override("panel", TDUI.skin("inset", 10))
	ip.custom_minimum_size = Vector2(0, 96)
	ip.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# прокрутка: длинная карточка (ветки улучшений) не растягивает док выше окна
	var isc := ScrollContainer.new()
	_inspector_scroll = isc
	isc.follow_focus = true
	# SHOW_NEVER, а не DISABLED: иначе ширина содержимого растягивает весь док
	isc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	isc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var inspector_layout := TDUI.vbox(4)
	ip.add_child(inspector_layout)
	inspector_layout.add_child(isc)
	_inspector = TDUI.vbox(5)
	_inspector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_inspector.size_flags_vertical = Control.SIZE_EXPAND_FILL
	isc.add_child(_inspector)
	_actions = TDUI.vbox(4)
	inspector_layout.add_child(_actions)
	v.add_child(ip)

	# усиления
	_perks_wrap = TDUI.vbox(5)
	_perks_wrap.add_child(TDUI.section_title("Усиления"))
	_perks_flow = TDUI.flow(5)
	_perks_wrap.add_child(_perks_flow)
	_perks_wrap.visible = false
	v.add_child(_perks_wrap)
	_update_tabs()


func _make_tile(kind: String, idx: int) -> Button:
	var def: Dictionary = TDConfig.TOWERS[kind]
	var b := Button.new()
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = TILE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(func(): tool_selected.emit(kind))
	b.tooltip_text = "%s — %s · %s" % [def["name"], def["role"], TDConfig.targets_text(def)]
	b.mouse_entered.connect(func(): tile_hovered.emit(kind))
	b.mouse_exited.connect(func(): tile_hovered.emit(""))
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_top", 5)
	m.add_theme_constant_override("margin_bottom", 5)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	var col := TDUI.vbox(1)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(col)
	var ic := TDUI.tower_icon(kind, 44)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(ic)
	var title := TDUI.label("Лучник" if kind == "arrow" else def["name"], 12, TDUI.TEXT, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(title)
	var stripe := ColorRect.new()
	stripe.custom_minimum_size = Vector2(0, 2)
	stripe.color = {"damage": Color("#d99458"), "effect": Color("#80b9c1"), "support": Color("#bd9cdf")}.get(def.get("cat", "damage"), TDUI.GOLD)
	stripe.tooltip_text = {"damage": "Урон", "effect": "Эффект", "support": "Поддержка"}.get(def.get("cat", "damage"), "")
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(stripe)
	var pr := TDUI.hbox(3)
	pr.alignment = BoxContainer.ALIGNMENT_CENTER
	pr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pr.add_child(TDUI.icon("coin", 13, TDUI.GOLD))
	var price := TDUI.label("0", 12, TDUI.GOLD, true)
	pr.add_child(price)
	col.add_child(pr)
	var key_text := ""
	if idx < 9:
		key_text = str(idx + 1)
	elif idx == 9:
		key_text = "0"
	var key := TDUI.keycap(key_text)
	pr.add_child(key)
	pr.move_child(key, 0)
	var rec := TDUI.label("★", 12, TDUI.GOLD, true)
	rec.position = Vector2(TILE.x - 14, 1)
	rec.visible = false
	b.add_child(rec)
	tiles[kind] = {"btn": b, "price": price, "rec": rec, "color": Color(def["color"]), "cat": def.get("cat", "damage")}
	return b


func set_category(id: String) -> void:
	_cat = id
	_update_tabs()


func cycle_category(dir: int) -> void:
	var ids: Array = []
	for c in TDConfig.CATEGORIES:
		ids.append(c["id"])
	var i := ids.find(_cat)
	_cat = ids[(i + dir + ids.size()) % ids.size()]
	_update_tabs()


func _update_tabs() -> void:
	for id in _tab_btns:
		var b: Button = _tab_btns[id]
		var on: bool = id == _cat
		b.add_theme_stylebox_override("normal", TDUI.sb(Color("#314b43") if on else Color("#26383a"), Color("#76c5a1") if on else Color("#465b59"), 1, 8, 6))
		b.add_theme_stylebox_override("hover", TDUI.sb(Color("#3e5b50") if on else Color("#304447"), Color("#76c5a1") if on else Color("#465b59"), 1, 8, 6))
		b.add_theme_stylebox_override("pressed", TDUI.sb(Color("#314b43"), Color("#76c5a1"), 1, 8, 6))
		b.add_theme_color_override("font_color", Color.WHITE if on else TDUI.MUTED)
	var shown := 0
	for kind in tiles:
		var t: Dictionary = tiles[kind]
		var vis: bool = _cat == "all" or t["cat"] == _cat
		t["btn"].visible = vis
		if vis:
			shown += 1
	_scroll.custom_minimum_size.y = TILE.y if shown > 0 else 0


## Обновляет плитки: цены, нехватку золота, рекомендации, выбор.
func refresh(g: TDGame, ratings: Dictionary, recommended: Dictionary, tool: String) -> void:
	for kind in tiles:
		var t: Dictionary = tiles[kind]
		var cost := g.tower_cost(kind)
		var poor := g.gold < cost
		var on: bool = tool == kind
		var locked := g.is_locked(kind)
		var rec: bool = recommended.has(kind) and not locked
		var useless: bool = ratings.has(kind) and ratings[kind]["stars"] == 0
		t["price"].text = "закрыта" if locked else str(cost)
		t["price"].add_theme_color_override("font_color", TDUI.MUTED if locked else (TDUI.BAD if poor else TDUI.GOLD))
		t["rec"].visible = rec
		if locked:
			(t["btn"] as Button).tooltip_text = unlock_text(kind)
		var state := "%s%s%s" % [on, rec, useless]
		if _tile_state.get(kind, "") != state:
			_tile_state[kind] = state
			var b: Button = t["btn"]
			b.add_theme_stylebox_override("normal", TDUI.skin("selected" if on else "button", 4))
			b.add_theme_stylebox_override("hover", TDUI.skin("selected" if on else "hover", 4))
			b.add_theme_stylebox_override("pressed", TDUI.skin("selected", 4))
		var btn: Button = t["btn"]
		btn.modulate = Color(0.55, 0.55, 0.65, 0.6) if locked else (Color(1, 1, 1, 0.5) if (poor and not on) or (useless and not on) else Color.WHITE)
	var sell_on: bool = tool == "sell"
	if sell_on != _sell_on:
		_sell_on = sell_on
		_sell_btn.add_theme_stylebox_override("normal", TDUI.sb(Color("#3a2630") if sell_on else Color("#26383a"), Color("#ff9a8a") if sell_on else Color("#465b59"), 1, 8, 8))
		_sell_btn.add_theme_stylebox_override("hover", TDUI.sb(Color("#4a2e3a") if sell_on else Color("#304447"), Color("#ff9a8a") if sell_on else Color("#465b59"), 1, 8, 8))
		_sell_btn.add_theme_stylebox_override("pressed", TDUI.sb(Color("#3a2630"), Color("#ff9a8a"), 1, 8, 8))
	_refresh_perks(g)


## Чем открывается закрытая башня.
static func unlock_text(kind: String) -> String:
	var a := TDMeta.achievement_def(TDMeta.TOWER_UNLOCK.get(kind, ""))
	if a.is_empty():
		return "Башня закрыта"
	return "Закрыто. Откроется достижением «%s»: %s" % [a["name"], a["desc"].to_lower()]


func _refresh_perks(g: TDGame) -> void:
	var sig := JSON.stringify(g.perks)
	if _sig.get("perks", "") == sig:
		return
	_sig["perks"] = sig
	TDUI.clear(_perks_flow)
	var any := false
	for p in TDConfig.PERKS:
		var lvl := g.perk_level(p["id"])
		if lvl > 0:
			any = true
			_perks_flow.add_child(TDUI.mini_chip(p["icon"], TDUI.GOLD, ("×%d" % lvl) if lvl > 1 else "", "%s — %s" % [p["name"], p["desc"]]))
	_perks_wrap.visible = any


# ── инспектор ─────────────────────────────────────────────────

## Однострочная подпись не растягивает док: лишнее обрезается многоточием, полный текст — в подсказке.
func _fit(l: Label) -> Label:
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 20
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.tooltip_text = l.text
	l.mouse_filter = Control.MOUSE_FILTER_PASS
	return l

func _small_btn(text: String, on: bool, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_ALL
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.tooltip_text = tip
	b.add_theme_font_size_override("font_size", 14)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_stylebox_override("normal", TDUI.sb(Color("#314b43") if on else Color("#26383a"), Color("#76c5a1") if on else Color("#465b59"), 1, 6, 4))
	b.add_theme_stylebox_override("hover", TDUI.sb(Color("#3e5b50") if on else Color("#304447"), Color("#76c5a1"), 1, 6, 4))
	b.add_theme_stylebox_override("pressed", TDUI.sb(Color("#314b43"), Color("#76c5a1"), 1, 6, 4))
	b.add_theme_color_override("font_color", Color.WHITE if on else TDUI.MUTED)
	return b


## Режим прицела: Первый / Сильный / Без эффекта (T — листать).
func _mode_row(t: TDGame.Tower) -> VBoxContainer:
	var v := TDUI.vbox(3)
	var head := TDUI.hbox(6)
	head.add_child(TDUI.label("ЦЕЛЬ", 10, TDUI.MUTED, true))
	head.add_child(TDUI.spacer())
	head.add_child(TDUI.label("T — листать", 10, Color("#b5c4be")))
	v.add_child(head)
	var row := TDUI.hbox(4)
	for m in TDConfig.TARGET_MODES:
		if m["id"] == "fresh" and not TDConfig.has_status_effect(t.def):
			continue
		var id: String = m["id"]
		var b := _small_btn(m["name"], t.mode == id, m["desc"])
		b.pressed.connect(func(): mode_requested.emit(id))
		row.add_child(b)
	v.add_child(row)
	return v


## Улучшение: кнопка на 2-й уровень или выбор из двух веток на 3-м.
func _upgrade_box(g: TDGame, t: TDGame.Tower) -> Control:
	var v := TDUI.vbox(3)
	var cost := g.upgrade_cost(t)
	if cost < 0:
		var b: Dictionary = TDConfig.branch_def(t.kind, t.branch)
		if not b.is_empty():
			v.add_child(TDUI.label("Специализация: " + b["name"], 11, TDUI.MUTED))
		return v
	var poor := g.gold < cost
	if t.level == 1:
		var btn := Button.new()
		btn.focus_mode = Control.FOCUS_ALL
		btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		btn.text = "Улучшить  ·  %d   (U)" % cost
		btn.icon = TDIcons.tex("coin")
		btn.expand_icon = true
		btn.tooltip_text = "Уровень 2: урон +40%, темп +10%, дальность +0.3. Дальше — выбор специализации."
		btn.add_theme_stylebox_override("normal", TDUI.sb(Color("#1f3324") if not poor else Color("#29251e"), Color("#6fd36f") if not poor else Color("#655d4b"), 1, 8, 8))
		btn.add_theme_stylebox_override("hover", TDUI.sb(Color("#284530"), Color("#8fe88f"), 1, 8, 8))
		btn.add_theme_color_override("font_color", TDUI.TEXT if not poor else TDUI.MUTED)
		btn.pressed.connect(func(): upgrade_requested.emit(""))
		v.add_child(btn)
		return v
	v.add_child(TDUI.label("СПЕЦИАЛИЗАЦИЯ  ·  %d" % cost, 10, TDUI.BAD if poor else TDUI.GOLD, true))
	var row := TDUI.vbox(3)
	var keys := {"a": "Z", "b": "C"}
	for b in TDConfig.BRANCHES.get(t.kind, []):
		var id: String = b["id"]
		var card := Button.new()
		card.focus_mode = Control.FOCUS_ALL
		card.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 40)
		card.tooltip_text = b["desc"]
		card.add_theme_stylebox_override("normal", TDUI.sb(Color("#30281c"), Color("#ffd35a") if not poor else Color("#665234"), 1, 8, 6))
		card.add_theme_stylebox_override("hover", TDUI.sb(Color("#493b27"), Color("#ffe58a"), 1, 8, 6))
		card.pressed.connect(func(): upgrade_requested.emit(id))
		var margin := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 8)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var cv := TDUI.vbox(4)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(cv)
		var top := TDUI.hbox(4)
		top.mouse_filter = Control.MOUSE_FILTER_IGNORE
		top.add_child(TDUI.icon(b["icon"], 16, TDUI.GOLD))
		top.add_child(_fit(TDUI.label(b["name"], 12, TDUI.TEXT, true)))
		cv.add_child(top)
		top.add_child(TDUI.spacer())
		top.add_child(TDUI.keycap(keys[id]))
		var d := _fit(TDUI.label(b["desc"], 10, Color("#d5ded5")))
		d.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.add_child(d)
		card.add_child(margin)
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var fit_card := func(): card.custom_minimum_size.y = margin.get_combined_minimum_size().y
		margin.minimum_size_changed.connect(fit_card)
		fit_card.call()
		row.add_child(card)
	v.add_child(row)
	return v


func _stat_row(label_text: String, v01: float, color: Color, value_text: String) -> HBoxContainer:
	var r := TDUI.hbox(8)
	var l := TDUI.label(label_text, 12, TDUI.MUTED)
	l.custom_minimum_size = Vector2(64, 0)
	r.add_child(l)
	r.add_child(TDUI.bar(v01, color, 6))
	var v := TDUI.label(value_text, 12, TDUI.TEXT, true)
	v.custom_minimum_size = Vector2(50, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	r.add_child(v)
	return r


## target: {"tower": Tower} — стоящая башня, либо {"kind": String} — тип для покупки.
func inspect(g: TDGame, target: Dictionary, ratings: Dictionary) -> void:
	var tower: TDGame.Tower = target.get("tower")
	if (tower != null) != _has_tower:
		_has_tower = tower != null
		_catalog.visible = not _has_tower
		_catalog_toggle.text = "Башни  ▸" if _has_tower else "Башни  ▾"
	var kind: String = tower.kind if tower != null else target.get("kind", "arrow")
	var cost := g.tower_cost(kind)
	var sig := "%s|%d|%d|%d|%d|%d|%s" % [kind, tower.id if tower != null else -1, int(tower.dealt) if tower != null else 0, tower.hits if tower != null else 0, cost, g.perks.size(), str(ratings.get(kind, {}))]
	sig += "|" + JSON.stringify(g.perks)
	if tower != null:
		sig += "|%d|%d|%s|%s|%s|%d" % [g.towers.size(), tower.level, tower.branch, tower.mode, g.can_upgrade(tower), tower.kills]
	if _sig.get("inspect", "") == sig:
		return
	_sig["inspect"] = sig

	var def: Dictionary = tower.def if tower != null else TDConfig.TOWERS[kind]
	var col := Color(def["color"])
	TDUI.clear(_inspector)
	TDUI.clear(_actions)
	if tower != null:
		cost = tower.spent

	var head := TDUI.hbox(10)
	head.add_child(TDUI.tower_icon(kind, 46, tower.level if tower != null else 1, tower.branch if tower != null else ""))
	var names := TDUI.vbox(0)
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	names.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var title: String = def["name"]
	if tower != null and tower.branch != "":
		title += " · " + String(TDConfig.branch_def(kind, tower.branch).get("name", ""))
	names.add_child(_fit(TDUI.label(title, 17 if tower == null or tower.branch == "" else 14, TDUI.TEXT, true)))
	if tower != null:
		names.add_child(_fit(TDUI.label("Ур. %d/%d  %s" % [tower.level, TDConfig.MAX_LEVEL, "◆".repeat(tower.level) + "◇".repeat(TDConfig.MAX_LEVEL - tower.level)], 12, col)))
	else:
		names.add_child(_fit(TDUI.label(def["role"], 12, col)))
	head.add_child(names)
	var price := TDUI.hbox(4)
	price.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	price.add_child(TDUI.icon("coin", 16, TDUI.GOLD))
	price.add_child(TDUI.label(str(cost), 16, TDUI.GOLD, true))
	head.add_child(price)
	_inspector.add_child(head)

	if def.has("aura"):
		var a: Dictionary = def["aura"]
		_inspector.add_child(_stat_row("Радиус", a["radius"] / 4.5, col, "%.1f" % a["radius"]))
		_inspector.add_child(_stat_row("Ускорение", a["fireRate"] / 0.5, col, "+%d%%" % round(a["fireRate"] * 100)))
	else:
		var dmg := g.t_damage(tower) if tower != null else g.damage_of(kind)
		var rate := 1.0 / (g.t_cooldown(tower) if tower != null else g.cooldown_of(kind))
		var rng_v := g.t_range(tower) if tower != null else g.range_of(kind)
		var dmg_txt := "%d" % round(dmg)
		if def.get("multishot", 1) > 1:
			dmg_txt = "%d×%d" % [round(dmg), def["multishot"]]
		_inspector.add_child(_stat_row("Урон", minf(1.0, dmg / (_stat_max["damage"] * 1.5)), col, dmg_txt))
		_inspector.add_child(_stat_row("Темп", minf(1.0, rate / (_stat_max["rate"] * 1.3)), col, "%.1f/с" % rate))
		_inspector.add_child(_stat_row("Дальность", minf(1.0, rng_v / (_stat_max["range"] + 2.5)), col, "%.1f" % rng_v))

	var tags := TDConfig.targets_text(def)
	for tag in TDConfig.tower_tags(def):
		tags += " · " + str(tag["text"])
	var tags_label := _fit(TDUI.label(tags, 10, col))
	tags_label.tooltip_text = tags
	_inspector.add_child(tags_label)
	if tower == null:
		_inspector.add_child(TDUI.para(def["hint"], 13, Color("#d5ded5")))
		if g.is_locked(kind):
			_inspector.add_child(TDUI.para(unlock_text(kind), 12, TDUI.BAD))

	if tower != null:
		var gain := g.sell_value(tower)
		var txt := "За волну: %d урона · убито всего: %d" % [roundi(tower.dealt), tower.kills]
		if tower.hits > 0:
			txt += " · ✦ %d%% усилено" % round(float(tower.boosted) / tower.hits * 100.0)
		_inspector.add_child(_fit(TDUI.label(txt, 10, TDUI.TEXT)))
		if not def.has("aura"):
			_inspector.add_child(_mode_row(tower))
		_actions.add_child(_upgrade_box(g, tower))
		var sb := Button.new()
		sb.focus_mode = Control.FOCUS_ALL
		sb.text = "Продать за %d" % gain
		sb.icon = TDIcons.tex("sell")
		sb.expand_icon = true
		sb.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		sb.add_theme_stylebox_override("normal", TDUI.sb(Color("#3a2630"), Color("#ff9a8a"), 1, 8, 5))
		sb.add_theme_stylebox_override("hover", TDUI.sb(Color("#4a2e3a"), Color("#ff9a8a"), 1, 8, 5))
		sb.pressed.connect(func(): sell_tower_requested.emit())
		_actions.add_child(sb)
	else:
		var r: Dictionary = ratings.get(kind, {})
		if not r.is_empty():
			var stars := int(r["stars"])
			var row := TDUI.hbox(8)
			var rt := RichTextLabel.new()
			rt.bbcode_enabled = true
			rt.fit_content = true
			rt.scroll_active = false
			rt.autowrap_mode = TextServer.AUTOWRAP_OFF
			rt.mouse_filter = Control.MOUSE_FILTER_IGNORE
			rt.custom_minimum_size = Vector2(70, 18)
			rt.add_theme_font_size_override("normal_font_size", 13)
			rt.text = "[color=#ffd35a]%s[/color][color=#655d4b]%s[/color]" % ["★".repeat(stars), "★".repeat(5 - stars)]
			row.add_child(rt)
			var note: String = r["note"] if r["note"] != "" else "против следующей волны"
			row.add_child(TDUI.para(note, 12, TDUI.MUTED))
			_inspector.add_child(row)
		_inspector.add_child(TDUI.spacer_v())
		if g.towers.is_empty():
			_actions.add_child(TDUI.para("Выбери башню (1–9, 0), затем клетку", 10, Color("#b5c4be")))
