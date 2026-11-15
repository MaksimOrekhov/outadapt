extends SceneTree
## Проверка: все группы звуков и треки музыки загружаются.

func _initialize() -> void:
	var a := TDAudio.new()
	root.add_child(a)
	var bad := 0
	var groups := ["hit", "hit_heavy", "boom", "death", "leak", "place", "sell", "upgrade", "victory", "defeat", "wave",
		"ui_click", "ui_select", "ui_error", "ui_open", "ui_close"]
	for k in TDAudio.SHOTS:
		groups.append(TDAudio.SHOTS[k].get("group", "shot_" + k))
	for g in groups:
		var n := a._group(g).size()
		print("%s %s (%d)" % ["OK  " if n > 0 else "FAIL", g, n])
		if n == 0:
			bad += 1
	for m in TDAudio.MUSIC:
		var s = load(m)
		print("%s %s" % ["OK  " if s != null else "FAIL", m])
		if s == null:
			bad += 1
	print("ГОТОВО: %d проблем" % bad)
	quit(1 if bad > 0 else 0)
