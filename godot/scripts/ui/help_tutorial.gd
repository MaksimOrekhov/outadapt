extends RefCounted
## Presentation controller extracted from main; run state remains owned by the root.

const TUTORIAL := [
	{"icon": "portal", "color": "#9a7bff", "title": "Враги идут по дороге", "text": "Они появляются из портала и бегут к замку. Если дойдут — ты теряешь жизнь. Жизней у тебя 20."},
	{"icon": "tower-arrow", "color": "#d6bd85", "title": "Строй башни рядом с дорогой", "text": "Выбери башню в панели слева и кликни по свободной клетке. Клик по башне выбирает её, правый клик — продаёт. Золото дают за убитых врагов."},
	{"icon": "dice", "color": "#ffd35a", "title": "Враги эволюционируют", "text": "После каждой волны выжившие приспосабливаются к твоей защите. Сверху видно, что придёт следом, а кнопка с лампочкой подскажет, чем бить. Подробности — по клавише Tab."},
	{"icon": "perk-rapid", "color": "#7ddc5a", "title": "Улучшай и выбирай перки", "text": "Кликни по башне: её можно улучшить (U) и на 3-м уровне выбрать специализацию. Каждые 3 волны можно взять одно усиление. Золотая звезда на плитке башни значит, что она особенно полезна против следующей волны."},
]

var host

func _init(owner: Control) -> void:
	host = owner

func _close_tutorial() -> void:
	host.tutorial_step = -1
	host._tutorial_seen = true
	var cf = ConfigFile.new()
	cf.load(host.SETTINGS)
	cf.set_value("game", "tutorial_seen", true)
	cf.save(host.SETTINGS)
	host._update_modals()


func _open_help() -> void:
	host.help_open = true
	host._update_modals()


func _close_help() -> void:
	host.help_open = false
	host._update_modals()


func _update_modals() -> void:
	host.tutorial_modal.visible = host.tutorial_step >= 0
	host.help_modal.visible = host.help_open
	host.meta_modal.visible = host.meta_open
	if host.meta_open:
		host._build_meta()
	if host.tutorial_step >= 0:
		host._build_tutorial()
	if host.help_open:
		host._build_help()


func _dialog(parent: Control, width: float) -> VBoxContainer:
	TDUI.clear(parent)
	var p = TDUI.panel(Color("#282118"), Color("#806440"), 18, 26, 2)
	p.get_theme_stylebox("panel").shadow_size = 24
	p.get_theme_stylebox("panel").shadow_color = Color(0, 0, 0, 0.6)
	p.add_theme_stylebox_override("panel", TDUI.skin("frame", 26))
	p.custom_minimum_size = Vector2(width, 0)
	var v = TDUI.vbox(12)
	p.add_child(v)
	host._center_in(parent, p)
	return v


func _build_tutorial() -> void:
	var s: Dictionary = TUTORIAL[host.tutorial_step]
	var v = host._dialog(host.tutorial_modal, 520)
	var ic = TDUI.icon(s["icon"], 64, Color(s["color"]))
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var t = TDUI.label(s["title"], 24, TDUI.TEXT, true)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var tx = TDUI.para(s["text"], 15, Color("#c7b99e"))
	tx.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(tx)
	var dots = TDUI.hbox(8)
	dots.alignment = BoxContainer.ALIGNMENT_CENTER
	for i in TUTORIAL.size():
		var d = Panel.new()
		d.custom_minimum_size = Vector2(26 if i == host.tutorial_step else 9, 9)
		d.add_theme_stylebox_override("panel", TDUI.sb(TDUI.GOLD if i == host.tutorial_step else Color("#706044"), Color(0, 0, 0, 0), 0, 5, 0))
		dots.add_child(d)
	v.add_child(dots)
	var row = TDUI.hbox(12)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	var skip = host._btn("Пропустить")
	skip.flat = true
	skip.pressed.connect(host._close_tutorial)
	row.add_child(skip)
	var last: bool = host.tutorial_step == TUTORIAL.size() - 1
	var nxt = host._btn("Играть" if last else "Дальше")
	nxt.custom_minimum_size = Vector2(140, 44)
	nxt.add_theme_stylebox_override("normal", TDUI.sb(Color("#2f9e44"), Color("#1f7a32"), 0, 10, 18))
	nxt.add_theme_stylebox_override("hover", TDUI.sb(Color("#38b04e"), Color("#1f7a32"), 0, 10, 18))
	nxt.pressed.connect(func():
		if last:
			host._close_tutorial()
		else:
			host.tutorial_step += 1
			host._update_modals())
	row.add_child(nxt)
	v.add_child(row)


func _help_row(icon_name: String, color: Color, title: String, sub: String, text: String, isize: float = 30.0) -> HBoxContainer:
	var r = TDUI.hbox(12)
	var ic = TDUI.icon(icon_name, isize, color)
	ic.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	r.add_child(ic)
	var c = TDUI.vbox(2)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var th = TDUI.hbox(8)
	th.add_child(TDUI.label(title, 14, TDUI.TEXT, true))
	if sub != "":
		th.add_child(TDUI.label("· " + sub, 12, TDUI.MUTED))
	c.add_child(th)
	if text != "":
		c.add_child(TDUI.para(text, 13, Color("#c7b99e")))
	r.add_child(c)
	return r


func _build_help() -> void:
	var outer = host._dialog(host.help_modal, 660)
	var head = TDUI.hbox(8)
	head.add_child(TDUI.label("Как играть", 24, TDUI.TEXT, true))
	head.add_child(TDUI.spacer())
	var x = host._btn("", "close")
	x.flat = true
	x.pressed.connect(host._close_help)
	head.add_child(x)
	outer.add_child(head)
	var sc = ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, minf(560.0, host.size.y - 160.0))
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	outer.add_child(sc)
	var v = TDUI.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
	v.add_child(TDUI.section_title("Башни"))
	for k in TDConfig.TOWER_KINDS:
		var d: Dictionary = TDConfig.TOWERS[k]
		v.add_child(host._help_row(d["icon"], Color(d["color"]), d["name"], "%s · %d золота" % [TDConfig.targets_text(d), d["cost"]], d["hint"]))
	v.add_child(TDUI.section_title("Связки"))
	v.add_child(host._help_row("tower-frost", Color("#62bdf0"), "Лёд → физический урон", "", "Замороженные получают +%d%% урона от лучников, пушек, снайперов и зениток." % round(TDConfig.SHATTER_BONUS * 100)))
	v.add_child(host._help_row("tower-ember", Color("#ef6a3c"), "Огонь → броня", "", "Обожжённые теряют %d%% брони, и слабые удары снова проходят." % round(TDConfig.SCORCH_ARMOR_CUT * 100)))
	v.add_child(host._help_row("tower-poison", Color("#7ddc5a"), "Яд → лечение", "", "Отравленный враг не лечится. Яд идёт сквозь броню и сопротивления."))
	v.add_child(host._help_row("tower-beacon", Color("#ffe27a"), "Маяк → невидимки и скорость", "", "Показывает невидимых и ускоряет стрельбу соседних башен. Без Маяка невидимку бьют только башни, которые стоят вплотную к нему (около клетки)."))
	v.add_child(host._help_row("tower-tesla", Color("#7fe3ff"), "Лёд → Тесла", "", "Молния бьёт замороженных на %d%% сильнее и не замечает броню." % round(TDConfig.SHOCK_CHILL_BONUS * 100)))
	v.add_child(TDUI.section_title("Улучшения"))
	v.add_child(host._help_row("perk-rapid", TDUI.GOLD, "Уровень 2 и специализация", "", "Выбери башню и нажми «Улучшить» (U): урон +40%, темп +10%, дальность +0.3. На 3-м уровне выбери одну из двух специализаций (Z / C) — например, Залп или Бронебой у лучников. Цена улучшений, как и постройки, растёт с числом башен этого типа. Продажа возвращает 70% вложенного."))
	v.add_child(host._help_row("target", Color("#9fb4d4"), "Режим прицела (T)", "", "Первый — ближе всех к замку. Сильный — у кого больше здоровья. Без эффекта — яд, лёд и огонь сперва ищут тех, на ком их эффекта ещё нет."))
	v.add_child(host._help_row("coin", TDUI.GOLD, "Проценты", "", "В конце волны к золоту добавляется %d%% накопленного, но не больше %d." % [round(TDConfig.INTEREST * 100), TDConfig.INTEREST_CAP]))
	v.add_child(TDUI.section_title("Боссы"))
	v.add_child(host._help_row("boss", Color("#ff6b7a"), "Каждые 10 волн приходит босс-зеркало", "", "Он копирует твою защиту: чем больше бил физикой, тем он бронированнее; огнём — огнестойкее; льдом — морозостойкее. Яд и Снайпер идут сквозь это. Прорвавшийся босс стоит 5 жизней. За победу — золото и внеочередной выбор усиления."))
	v.add_child(host._help_row("boss", Color("#ffb347"), "У каждого босса своя способность", "", "10-я волна — «Панцирь»: щит, который надо пробить. 20-я — «Призыватель»: зовёт быстрых прислужников, нужен урон по площади. 30-я — «Зеркало»: почти не боится урона того типа, которым ты бьёшь чаще всего. Дальше по кругу."))
	v.add_child(host._help_row("wave", Color("#ffb347"), "Особые волны (5, 15, 25…)", "", "Нашествие — врагов больше, но они хрупкие. Рывок — быстрые. Бронеколонна — их меньше, но каждый крепче. Награда за такую волну ×1.5. Предупреждение появляется в панели «Следом»."))
	v.add_child(host._help_row("star", TDUI.GOLD, "Достижения и сложность", "", "Достижения дают очки знаний и открывают башни и режимы. Тяжёлая сложность (после 15-й волны) даёт ×1.5 очков знаний. «Карта дня» — одна карта на всех, «Бесконечный» режим открывается после первой победы."))
	v.add_child(TDUI.section_title("Что умеет рой"))
	for k in TDGenome.GENES:
		v.add_child(host._help_row("gene-" + k, Color.WHITE, TDGenome.GENE_LABELS[k], TDGenome.GENE_HELP[k], "", 22))
	v.add_child(TDUI.para("Каждая волна — потомки тех, кто дошёл дальше всех. Если бить одним способом, рой привыкнет. Рой ещё и целенаправленно копит защиту от того, чем ты бил больше всего (броню — от физики, огнестойкость — от огня). Новые угрозы (лечение, полёт, невидимость, деление, щит) приходят по расписанию, о них предупреждают за 3 волны.", 13, TDUI.MUTED))
	v.add_child(TDUI.section_title("Управление"))
	v.add_child(TDUI.para("1–9, 0 — выбор башни · Q / E — листать башни · клик по башне — выбрать, правый клик — продать · X — режим продажи · U — улучшить · Z / C — специализация · T — режим прицела · пробел — запуск волны · P — пауза · F — скорость · A — советы · Tab — рой и итоги · H — справка · Esc или правый клик по пустой клетке — закрыть окно и снять выбор башни", 13, TDUI.MUTED))


# ── автопроверка: godot --path godot -- --shot=out.png [--seed=N] [--secs=S] [--skip=W] [--ui=...] ──


