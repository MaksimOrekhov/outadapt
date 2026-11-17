class_name TDWaveReport
extends RefCounted
## Постоянное модальное окно «Волна N пройдена»: итог, главная угроза и башни-ответы.
## Закрывается только действием игрока (кнопка «ОК», Enter, Space или Esc). Состояние забега не меняет.
## PRO-191: главное — карточки угроз TDThreats («что угрожает → когда → почему → что построить»), не больше двух;
## гены, сигнатура и проценты — в сворачиваемом блоке «Подробнее об эволюции».

const MAX_ENTRIES := 8

var host
## Открыт ли блок «Подробнее об эволюции» (помнится между отчётами в пределах сессии).
var details_open := false


func _init(owner: Control) -> void:
	host = owner


## Снимок отчёта на момент конца волны: окно показывает именно его, даже если состояние игры потом изменится.
static func snapshot(g: TDGame) -> Dictionary:
	var r := TDPanels.last_report(g)
	if r.is_empty():
		return {}
	var all := TDThreats.cards(g)
	return {
		"wave": int(r["wave"]), "killed": int(r["killed"]), "size": int(r["size"]), "leaked": int(r["leaked"]),
		"bonus": int(r.get("bonus", 0)), "interest": int(r.get("interest", 0)), "special": String(r.get("special", "")),
		"lure": r.get("lure", {}).duplicate(),
		"entries": TDAdvisor.adaptation(g).slice(0, MAX_ENTRIES),
		"strains": TDStrains.forecast(g),
		"cards": all,
		"headline": TDThreats.headline(all),
		"calm": TDThreats.calm_text(g),
		"gold": g.gold,
	}


func open(snap: Dictionary) -> void:
	if snap.is_empty():
		return
	host.wave_report = snap
	build()
	host._update_modals()
	host._dirty = true


## Закрыть окно. Отложенные баннеры (достижения) показываются после закрытия.
func close() -> void:
	if host.wave_report.is_empty():
		return
	host.wave_report = {}
	TDUI.clear(host.wave_report_modal)
	host._update_modals()
	host._dirty = true
	var queued: Array = host._banner_queue
	host._banner_queue = []
	for b in queued:
		host._banner(b[0], b[1], b[2])


func toggle_details() -> void:
	details_open = not details_open
	if not host.wave_report.is_empty():
		build()


## Клик по башне-ответу: закрыть отчёт и взять эту башню для постройки.
func _pick(kind: String) -> void:
	close()
	host._set_tool(kind)


func build() -> void:
	var modal: Control = host.wave_report_modal
	var snap: Dictionary = host.wave_report
	TDUI.clear(modal)
	var small: bool = host.size.y < 640.0
	var width: float = clampf(host.size.x - 48.0, 320.0, 660.0)
	var p := TDUI.panel(Color("#1b292b"), Color("#465b59"), 18, 22, 2)
	p.add_theme_stylebox_override("panel", TDUI.skin("frame", 16 if small else 24))
	p.get_theme_stylebox("panel").shadow_size = 24
	p.get_theme_stylebox("panel").shadow_color = Color(0, 0, 0, 0.6)
	p.custom_minimum_size = Vector2(width, 0)
	var v := TDUI.vbox(8 if small else 10)
	p.add_child(v)

	# шапка: итог волны одной строкой
	var top := TDUI.flow(8)
	top.alignment = FlowContainer.ALIGNMENT_CENTER
	var title := TDUI.label("Волна %d пройдена" % snap["wave"], 22 if small else 26, TDUI.OK, true)
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(title)
	var chips := TDUI.hbox(6)
	chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chips.add_child(TDUI.chip("", "убито %d из %d" % [snap["killed"], snap["size"]], TDUI.TEXT))
	chips.add_child(TDUI.chip("lives" if snap["leaked"] > 0 else "", "прорвалось %d" % snap["leaked"], TDUI.BAD if snap["leaked"] > 0 else TDUI.TEXT))
	if snap["bonus"] + snap["interest"] > 0:
		chips.add_child(TDUI.chip("coin", "+%d" % (snap["bonus"] + snap["interest"]), TDUI.GOLD, "Бонус за волну %d, проценты %d" % [snap["bonus"], snap["interest"]]))
	top.add_child(chips)
	if not snap.get("lure", {}).is_empty():
		var lr: Dictionary = snap["lure"]
		var gname: String = TDGenome.GENE_LABELS[lr["gene"]]
		if lr["bonus"] > 0:
			top.add_child(TDUI.chip("coin", "приманка +%d золота" % lr["bonus"], TDUI.GOLD, "«%s»: %d%% дохода волны (%d) × затронутая оборона %d%% × усиление гена %d%%" % [gname, roundi(TDConfig.LURE_SHARE * 100.0), lr["income"], roundi(lr["exposure"] * 100.0), roundi(lr["saturation"] * 100.0)]))
		else:
			top.add_child(TDUI.chip("coin", "приманка без награды", TDUI.MUTED, "«%s»: твой урон почти не зависел от этого гена (затронуто %d%%) или ген уже был максимален — риска не было, награды тоже" % [gname, roundi(lr["exposure"] * 100.0)]))
	v.add_child(top)

	# главная зона: одна полная карточка и, если нужно, одна короткая; иначе — спокойное состояние
	var main := TDUI.vbox(8)
	main.name = "ReportMain"
	var head: Array = snap.get("headline", [])
	var gold: int = int(snap.get("gold", 0))
	if head.is_empty():
		main.add_child(TDThreatView.calm(String(snap.get("calm", ""))))
	else:
		main.add_child(TDThreatView.card(head[0], gold, _pick))
		if head.size() > 1:
			main.add_child(TDThreatView.compact(head[1], gold, _pick))
	v.add_child(main)

	# подробности: свёрнуты по умолчанию, внутри прокрутка
	var entries: Array = snap["entries"]
	var strains: Array = snap.get("strains", [])
	var rest: Array = []
	for c in snap.get("cards", []):
		if not head.has(c):
			rest.append(c)
	var has_details: bool = entries.size() > 0 or strains.size() > 0 or rest.size() > 0
	var scroll: ScrollContainer = null
	var content: VBoxContainer = null
	if has_details:
		var tg: Button = host._btn(("▾ " if details_open else "▸ ") + "Подробнее об эволюции")
		tg.name = "ReportDetailsToggle"
		tg.flat = true
		tg.alignment = HORIZONTAL_ALIGNMENT_LEFT
		tg.add_theme_font_size_override("font_size", 14)
		tg.add_theme_color_override("font_color", TDUI.MUTED)
		tg.focus_mode = Control.FOCUS_NONE
		tg.pressed.connect(toggle_details)
		v.add_child(tg)
	if details_open and has_details:
		scroll = ScrollContainer.new()
		scroll.name = "ReportScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content = TDUI.vbox(8)
		content.name = "ReportDetails"
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(content)
		details(content, rest, strains, entries, gold)
		v.add_child(scroll)

	var ok: Button = host._btn("ОК")
	ok.name = "ReportOk"
	ok.custom_minimum_size = Vector2(160, 40 if small else 44)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.add_theme_stylebox_override("normal", TDUI.skin("primary", 18))
	ok.add_theme_stylebox_override("hover", TDUI.skin("hover", 18))
	ok.pressed.connect(close)
	v.add_child(ok)
	host._center_in(modal, p)
	# длинные подробности прокручиваются внутри окна, главная зона и кнопка «ОК» остаются на экране
	if scroll != null:
		var fit := func() -> void:
			if not is_instance_valid(scroll) or not is_instance_valid(content) or not is_instance_valid(v):
				return
			var chrome: float = v.get_combined_minimum_size().y - scroll.get_combined_minimum_size().y
			var room: float = host.size.y - 56.0 - chrome
			scroll.custom_minimum_size.y = clampf(content.get_combined_minimum_size().y, 40.0, maxf(80.0, room))
		host.call_deferred("_fit_wave_report", fit)


## «Подробнее об эволюции»: остальные угрозы, как рой изучает оборону (сигнатура), сдвиги генов с причинами.
## Здесь допустимы термины — каждый блок начинается с пояснения.
static func details(content: VBoxContainer, rest: Array, strains: Array, entries: Array, gold: int) -> void:
	if rest.size() > 0:
		content.add_child(TDUI.section_title("Ещё о следующих волнах"))
		for c in rest:
			content.add_child(TDThreatView.compact(c, gold))
	if strains.size() > 0:
		content.add_child(TDUI.section_title("Как рой изучает оборону"))
		content.add_child(TDUI.para("Рой считает, какими ударами ты убиваешь обычных врагов. Если одного способа слишком много, он выращивает ответ: сначала изучает (процент — насколько ответ созрел), потом объявляет волну появления и выводит пакет врагов.", 13, TDUI.MUTED))
		for e in strains:
			var row := TDUI.hbox(8)
			row.add_child(TDUI.icon(e["icon"], 20, Color(e["color"])))
			var para := TDUI.para(TDStrains.line(e), 13, TDUI.TEXT)
			para.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(para)
			content.add_child(row)
	if entries.size() > 0:
		content.add_child(TDUI.section_title("Гены роя"))
		content.add_child(TDUI.para("Каждая волна рождается от лучших врагов прошлой. Гены — средние свойства роя: «▲ +10%» — насколько свойство выросло, «ты бил» — какой тип урона подталкивал рост.", 13, TDUI.MUTED))
		for e in entries:
			content.add_child(TDPanels._adaptation_row(e))
		content.add_child(TDUI.para("Сдвиг считается по среднему роя до и после отбора. Давление — доля твоего урона данного типа; оно лишь подталкивает ген. Подробности — в панели «Рой» (Tab).", 13, TDUI.MUTED))
