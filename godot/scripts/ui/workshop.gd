extends RefCounted
## Presentation controller extracted from main; run state remains owned by the root.

var host

func _init(owner: Control) -> void:
	host = owner

func _open_meta() -> void:
	host._close_popovers()
	host.meta_open = true
	host._update_modals()


func _close_meta() -> void:
	host.meta_open = false
	host._update_modals()
	host._dirty = true
	host._sigs.erase("over")
	host._sigs.erase("victory")


func _buy_meta(id: String) -> void:
	if TDMeta.buy(id):
		host._build_meta()


func _build_meta() -> void:
	var v = host._dialog(host.meta_modal, 620)
	var head = TDUI.hbox(10)
	head.add_child(TDUI.icon("perk-variety", 34, Color("#c9b5ff")))
	var hv = TDUI.vbox(0)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hv.add_child(TDUI.label("Мастерская", 22, TDUI.TEXT, true))
	hv.add_child(TDUI.label("Постоянные улучшения. Действуют со следующего забега.", 12, TDUI.MUTED))
	head.add_child(hv)
	var pts = TDUI.panel(Color("#1d1a2e"), Color("#7a64c8"), 10, 8)
	pts.add_child(TDUI.label("Очки знаний: %d" % TDMeta.points, 15, Color("#e3d9ff"), true))
	head.add_child(pts)
	v.add_child(head)
	for u in TDMeta.UPGRADES:
		var id: String = u["id"]
		var lv = TDMeta.level(id)
		var mx: int = u["cost"].size()
		var cost = TDMeta.next_cost(id)
		var row = TDUI.panel(TDUI.PANEL2, TDUI.LINE, 10, 10)
		var h = TDUI.hbox(10)
		row.add_child(h)
		h.add_child(TDUI.icon(u["icon"], 26, TDUI.GOLD))
		var c = TDUI.vbox(0)
		c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		c.add_child(TDUI.label("%s  %s" % [u["name"], "◆".repeat(lv) + "◇".repeat(mx - lv)], 14, TDUI.TEXT, true))
		c.add_child(TDUI.para(u["desc"], 12, TDUI.MUTED))
		h.add_child(c)
		var b = host._btn("Максимум" if cost < 0 else "Купить · %d" % cost)
		b.custom_minimum_size = Vector2(130, 36)
		b.disabled = cost < 0 or TDMeta.points < cost
		b.pressed.connect(host._buy_meta.bind(id))
		h.add_child(b)
		v.add_child(row)
	var stats = "Забегов: %d · побед: %d · лучшая волна: %d" % [TDMeta.runs, TDMeta.wins, TDMeta.best_wave]
	v.add_child(TDUI.para(stats, 12, TDUI.MUTED))
	var close = host._btn("Закрыть (Esc)")
	close.custom_minimum_size = Vector2(0, 40)
	close.pressed.connect(host._close_meta)
	v.add_child(close)


