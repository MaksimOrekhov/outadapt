class_name TDWaveReport
extends RefCounted
## Постоянное модальное окно «Волна N пройдена»: итог, объяснения адаптации и башни-ответы.
## Закрывается только действием игрока (кнопка «ОК», Enter, Space или Esc). Состояние забега не меняет.

const MAX_ENTRIES := 8

var host


func _init(owner: Control) -> void:
	host = owner


## Снимок отчёта на момент конца волны: окно показывает именно его, даже если состояние игры потом изменится.
static func snapshot(g: TDGame) -> Dictionary:
	var r := TDPanels.last_report(g)
	if r.is_empty():
		return {}
	return {
		"wave": int(r["wave"]), "killed": int(r["killed"]), "size": int(r["size"]), "leaked": int(r["leaked"]),
		"bonus": int(r.get("bonus", 0)), "interest": int(r.get("interest", 0)), "special": String(r.get("special", "")),
		"lure": r.get("lure", {}).duplicate(),
		"entries": TDAdvisor.adaptation(g).slice(0, MAX_ENTRIES),
		"strains": TDStrains.forecast(g),
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


func build() -> void:
	var modal: Control = host.wave_report_modal
	var snap: Dictionary = host.wave_report
	TDUI.clear(modal)
	var width: float = clampf(host.size.x - 48.0, 320.0, 640.0)
	var p := TDUI.panel(Color("#1b292b"), Color("#465b59"), 18, 22, 2)
	p.get_theme_stylebox("panel").shadow_size = 24
	p.get_theme_stylebox("panel").shadow_color = Color(0, 0, 0, 0.6)
	p.add_theme_stylebox_override("panel", TDUI.skin("frame", 26))
	p.custom_minimum_size = Vector2(width, 0)
	var v := TDUI.vbox(10)
	p.add_child(v)

	var title := TDUI.label("Волна %d пройдена" % snap["wave"], 26, TDUI.OK, true)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var chips := TDUI.flow(6)
	chips.alignment = FlowContainer.ALIGNMENT_CENTER
	chips.add_child(TDUI.chip("", "убито %d из %d" % [snap["killed"], snap["size"]], TDUI.TEXT))
	chips.add_child(TDUI.chip("", "прорвалось %d" % snap["leaked"], TDUI.BAD if snap["leaked"] > 0 else TDUI.TEXT))
	if snap["bonus"] + snap["interest"] > 0:
		chips.add_child(TDUI.chip("coin", "+%d золота" % (snap["bonus"] + snap["interest"]), TDUI.GOLD, "Бонус за волну %d, проценты %d" % [snap["bonus"], snap["interest"]]))
	if not snap.get("lure", {}).is_empty():
		var lr: Dictionary = snap["lure"]
		var gname: String = TDGenome.GENE_LABELS[lr["gene"]]
		if lr["bonus"] > 0:
			chips.add_child(TDUI.chip("coin", "приманка +%d золота" % lr["bonus"], TDUI.GOLD, "«%s»: %d%% дохода волны (%d) × затронутая оборона %d%% × усиление гена %d%%" % [gname, roundi(TDConfig.LURE_SHARE * 100.0), lr["income"], roundi(lr["exposure"] * 100.0), roundi(lr["saturation"] * 100.0)]))
		else:
			chips.add_child(TDUI.chip("coin", "приманка без награды", TDUI.MUTED, "«%s»: твой урон почти не зависел от этого гена (затронуто %d%%) или ген уже был максимален — риска не было, награды тоже" % [gname, roundi(lr["exposure"] * 100.0)]))
	v.add_child(chips)

	var entries: Array = snap["entries"]
	var strains: Array = snap.get("strains", [])
	var scroll: ScrollContainer = null
	var content: VBoxContainer = null
	if entries.size() > 0 or strains.size() > 0:
		scroll = ScrollContainer.new()
		scroll.name = "ReportScroll"
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content = TDUI.vbox(8)
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(content)
		# PRO-152: «заметил → готовит → ответ» — выше генов: это то, что меняет состав волн
		for e in strains:
			var row := TDUI.hbox(8)
			row.add_child(TDUI.icon(e["icon"], 22, Color(e["color"])))
			var para := TDUI.para(TDStrains.line(e), 13, TDUI.TEXT)
			para.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(para)
			content.add_child(row)
		if entries.size() > 0:
			content.add_child(TDUI.section_title("Рой адаптируется"))
			for e in entries:
				content.add_child(TDPanels._adaptation_row(e))
			content.add_child(TDUI.para("Сдвиг считается по среднему роя до и после отбора. Давление — доля твоего урона данного типа; оно лишь подталкивает ген. Подробности — в панели «Рой» (Tab).", 11, TDUI.MUTED))
		v.add_child(scroll)

	var ok: Button = host._btn("ОК")
	ok.name = "ReportOk"
	ok.custom_minimum_size = Vector2(160, 44)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.add_theme_stylebox_override("normal", TDUI.skin("primary", 18))
	ok.add_theme_stylebox_override("hover", TDUI.skin("hover", 18))
	ok.pressed.connect(close)
	v.add_child(ok)
	host._center_in(modal, p)
	# длинный отчёт прокручивается внутри окна, кнопка «ОК» остаётся на экране
	if scroll != null:
		var fit := func() -> void:
			if not is_instance_valid(scroll) or not is_instance_valid(content) or not is_instance_valid(v):
				return
			var chrome: float = v.get_combined_minimum_size().y - scroll.get_combined_minimum_size().y
			var room: float = host.size.y - 56.0 - chrome
			scroll.custom_minimum_size.y = clampf(content.get_combined_minimum_size().y, 40.0, maxf(80.0, room))
		host.call_deferred("_fit_wave_report", fit)
