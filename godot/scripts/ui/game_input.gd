extends RefCounted
## Presentation controller extracted from main; run state remains owned by the root.

var host

func _init(owner: Control) -> void:
	host = owner

func _input(ev: InputEvent) -> void:
	if not (ev is InputEventKey and ev.pressed and not ev.echo):
		return
	var k: int = ev.keycode
	if host.front != null and host.front.visible:
		if k == KEY_ESCAPE:
			host.front.back()
			host.get_viewport().set_input_as_handled()
		return
	# окно отчёта о волне: закрывается «ОК», Enter, Space или Esc; остальные клавиши под него не проходят
	if not host.wave_report.is_empty():
		if k in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE, KEY_ESCAPE]:
			host._close_wave_report()
		host.get_viewport().set_input_as_handled()
		return
	if k == KEY_ESCAPE:
		if host._active_pop != null:
			host._close_popovers()
		elif host.meta_open:
			host._close_meta()
		elif host.help_open:
			host._close_help()
		elif host.tutorial_step >= 0:
			host._close_tutorial()
		elif host.drawer.visible:
			host._toggle_drawer()
		elif host.selected_tower != null or host.tool != "":
			host.selected_tower = null
			host._set_tool("")
		else:
			host._show_front()
		return
	# Once a widget owns focus, Tab/Space belong to native keyboard navigation.
	var focus: Control = host.get_viewport().gui_get_focus_owner()
	if focus != null and (k == KEY_TAB or k == KEY_SPACE):
		return
	if host.tutorial_step >= 0 or host.help_open:
		return
	var idx = -1
	if k >= KEY_1 and k <= KEY_9:
		idx = k - KEY_1
	elif k == KEY_0:
		idx = 9
	if not host.game.offer.is_empty():
		if idx >= 0 and idx < host.game.offer.size():
			host._pick_perk(host.game.offer[idx])
		return
	if idx >= 0 and idx < TDConfig.TOWER_KINDS.size():
		host._toggle_tool(TDConfig.TOWER_KINDS[idx])
	elif k == KEY_Q:
		host._cycle_tool(-1)
	elif k == KEY_E:
		host._cycle_tool(1)
	elif k == KEY_X or k == KEY_S:
		host._set_tool("sell")
	elif k == KEY_U:
		host._upgrade_selected()
	elif k == KEY_Z and host.selected_tower != null and host.selected_tower.level == 2:
		host._upgrade_selected("a")
	elif k == KEY_C and host.selected_tower != null and host.selected_tower.level == 2:
		host._upgrade_selected("b")
	elif k == KEY_T:
		host._cycle_mode()
	elif k == KEY_P:
		host._toggle_pause()
	elif k == KEY_M:
		host._open_meta()
	elif k == KEY_SPACE:
		host._start_wave()
		host.get_viewport().set_input_as_handled()
	elif k == KEY_F:
		host._cycle_speed()
	elif k == KEY_TAB:
		host._toggle_drawer()
		host.get_viewport().set_input_as_handled()
	elif k == KEY_A:
		host._toggle_advice()
	elif k == KEY_H or k == KEY_QUESTION:
		host._open_help()


# ── цикл ──────────────────────────────────────────────────────


func _on_cell_clicked(c: Vector2i, button: int) -> void:
	if host._blocked():
		return
	var t = host.game.tower_at(c.x, c.y)
	if button == MOUSE_BUTTON_RIGHT:
		if t != null:
			host.game.sell_tower(c.x, c.y)
			if host.selected_tower == t:
				host.selected_tower = null
		else:
			host.selected_tower = null
			host._set_tool("")
	elif button == MOUSE_BUTTON_LEFT:
		if host.tool == "sell":
			if t != null:
				host.game.sell_tower(c.x, c.y)
		elif t != null:
			host.selected_tower = null if host.selected_tower == t else t
		else:
			host.selected_tower = null
			if host.tool != "":
				if not host.game.place_tower(host.tool, c.x, c.y):
					host.audio.ui_error()
	host._dirty = true


func _cycle_tool(dir: int) -> void:
	var kinds: Array = TDConfig.TOWER_KINDS
	var i = kinds.find(host.tool)
	for _step in kinds.size():
		if i < 0:
			i = 0 if dir > 0 else kinds.size() - 1
		else:
			i = (i + dir + kinds.size()) % kinds.size()
		if not host.game.is_locked(kinds[i]):
			break
	host._set_tool(kinds[i])


