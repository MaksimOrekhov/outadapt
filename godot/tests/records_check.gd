extends SceneTree
## PRO-147: рекорды привязаны к сыгранной геометрии, старые рекорды по сиду сохранены и переносятся только доказуемо.
## godot --headless --path godot --script res://tests/records_check.gd   (файл meta.cfg не читается и не пишется)

var failures := 0

## Эталонные ключи: формат канонической записи и SHA-256 не должны меняться между сборками и платформами.
## Меняется формат — поднять TDMap.GEOMETRY_SCHEMA и написать миграцию TDMeta, а не править эти значения.
const GOLDEN := {
	"seed 1": "012dc037d443611ea0873ad2",
	"seed 1003": "cd48a01f842ea063c287481c",
	"seed 4243": "5de1490b9446348fc8dc1090",
	"fork": "e218d641d6fe2e2d629054cd",
	"fork_uneven": "fad910eedf8cd7b81d3ddf2d",
}


func check(label: String, condition: bool, detail: String = "") -> void:
	print(("OK    " if condition else "FAIL  ") + label + ("" if detail == "" else "  (" + detail + ")"))
	if not condition:
		failures += 1


func seed_where(pred: Callable, from := 1) -> int:
	for s in range(from, from + 5000):
		if pred.call(s):
			return s
	return -1


func _initialize() -> void:
	# ── 1. Ключ геометрии: стабильный, длинный, канонический ──
	var golden_now := {
		"seed 1": TDMap.generate(1).geometry_key(),
		"seed 1003": TDMap.generate(1003).geometry_key(),
		"seed 4243": TDMap.generate(4243).geometry_key(),
		"fork": TDMap.fork_test("fork").geometry_key(),
		"fork_uneven": TDMap.fork_test("fork_uneven").geometry_key(),
	}
	if GOLDEN["seed 1"] == "":
		print("GOLDEN ", golden_now)
	var golden_ok := true
	for k in GOLDEN:
		golden_ok = golden_ok and GOLDEN[k] == golden_now[k]
	check("эталонные ключи совпадают (формат и SHA-256 не изменились)", golden_ok, str(golden_now))
	var m1 := TDMap.generate(1003)
	check("ключ — 24 hex-символа, повторная генерация даёт тот же", m1.geometry_key().length() == 24
		and m1.geometry_key().is_valid_hex_number() and m1.geometry_key() == TDMap.generate(1003).geometry_key())
	check("каноническая запись начинается с версии схемы и размера поля", m1.geometry_canonical().begins_with("geo%d|grid:%dx%d|" % [TDMap.GEOMETRY_SCHEMA, TDConfig.COLS, TDConfig.ROWS]))
	var wps: Array[Vector2i] = m1.waypoints.duplicate()
	wps.insert(1, (wps[0] + wps[1]) / 2 if (wps[0].x == wps[1].x or wps[0].y == wps[1].y) else wps[0])
	var m1b := TDMap.build(1003, "другое имя", wps, m1.blocked)
	check("лишняя вершина на прямой и другое название — та же геометрия", m1b.geometry_key() == m1.geometry_key())
	var rocks := m1.blocked.duplicate()
	for x in TDConfig.COLS:
		var c := Vector2i(x, 0)
		if not m1.cells.has(c) and not rocks.has(c):
			rocks[c] = true
			break
	check("другие скалы — другая геометрия", TDMap.build(1003, "", m1.waypoints, rocks).geometry_key() != m1.geometry_key())
	var reordered := {}
	var keys := m1.blocked.keys()
	keys.reverse()
	for c in keys:
		reordered[c] = true
	check("порядок скал в словаре не важен", TDMap.build(1003, "", m1.waypoints, reordered).geometry_key() == m1.geometry_key())
	check("развилка: другой план распределения — другое испытание", TDMap.fork_test("fork").geometry_key() != TDMap.fork_test("fork", [1] as Array[int]).geometry_key())
	check("развилка и одиночная карта, две развилки — разные ключи", TDMap.fork_test("fork").geometry_key() != TDMap.fork_test("fork_uneven").geometry_key()
		and TDMap.fork_test("fork").geometry_key() != m1.geometry_key())

	# ── 2. Коллизии на наборе карт ──
	var canon := {}
	var by_key := {}
	var collisions := 0
	for s in 1000:
		var maps := [TDMap.generate(s * 7919 + 13)]
		if s < 250:
			for fam in ["vsnake", "stairs", "hooks"]:
				maps.append(TDMap.generate(s * 7919 + 13, fam))
		for m in maps:
			var cs: String = m.geometry_canonical()
			var k: String = m.geometry_key()
			canon[cs] = true
			if by_key.has(k) and by_key[k] != cs:
				collisions += 1
			by_key[k] = cs
	check("1 750 карт: %d разных геометрий, %d ключей, коллизий нет" % [canon.size(), by_key.size()], collisions == 0 and canon.size() == by_key.size())

	# ── 3. Семейство и ключ после сохранения и загрузки ──
	var s_stairs := seed_where(func(s): return TDMap.generate(s).family == "stairs")
	var gs := TDGame.new(s_stairs)
	var snap := TDSave.snapshot(gs)
	check("сохранение карты с одним путём — прежний формат, без семейства", not snap.has("family") and not snap.has("routes"))
	var gr := TDSave.restore(snap)
	check("после загрузки: семейство «лесенка» восстановлено, ключ тот же", gr != null and gr.map.family == "stairs" and gr.map.geometry_key() == gs.map.geometry_key())
	var old := snap.duplicate(true)
	old["waypoints"] = TDMap.CLASSIC_WAYPOINTS.duplicate()
	old["blocked"] = {}
	var go := TDSave.restore(old)
	check("карта, которой генератор сейчас не даёт: семейство неизвестно, а не «змейка»", go != null and go.map.family == "" and go.map.geometry_key() != gs.map.geometry_key())
	var gf := TDGame.new(5, TDMap.fork_test("fork_uneven"))
	var gfr := TDSave.restore(TDSave.snapshot(gf))
	check("развилка: семейство и ключ после загрузки те же", gfr != null and gfr.map.family == "fork_uneven" and gfr.map.geometry_key() == gf.map.geometry_key())
	check("новая карта по умолчанию — семейство неизвестно", TDMap.build(0, "", TDMap.CLASSIC_WAYPOINTS).family == "")

	# ── 4. Перенос старых рекордов ──
	var same := 0
	for s in 600:
		if TDMap.generate_v1(s).geometry_key() == TDMap.generate(s).geometry_key():
			same += 1
	print("сиды 0–599: карта первой версии генератора совпадает с нынешней у %d из 600" % same)
	var all_snake_same := true
	for s in 300:
		var now := TDMap.generate(s)
		if now.family == "snake" and TDMap.generate_v1(s).geometry_key() != now.geometry_key():
			all_snake_same = false
	check("все сиды, где сейчас змейка, дают ту же карту, что генератор первой версии", all_snake_same)
	var s_snake := seed_where(func(s): return TDMap.generate(s).family == "snake" and TDMap.family_for(s) == "snake")
	var s_new := seed_where(func(s): return TDMap.generate(s).family == "hooks")
	TDMeta.records = {str(s_snake): 12, str(s_new): 20, "мусор": 5}
	TDMeta.map_records = {}
	TDMeta.records_schema = 1
	var legacy_copy := TDMeta.records.duplicate(true)
	var res := TDMeta.migrate_records()
	var k_snake := TDMeta.record_key(s_snake, TDMap.generate(s_snake))
	check("перенесён только доказуемый рекорд (змейка, та же карта)", res["moved"] == 1 and res["kept"] == 2
		and TDMeta.map_records.size() == 1 and int(TDMeta.map_records.get(k_snake, 0)) == 12, str(res))
	check("рекорд сида, который теперь даёт «крюки», не показывается на новой карте", TDMeta.record_for_map(s_new, TDMap.generate(s_new)) == 0)
	check("история по сиду сохранена без изменений, схема обновлена", TDMeta.records == legacy_copy and TDMeta.records_schema == TDMeta.RECORDS_SCHEMA)
	var after_first := TDMeta.map_records.duplicate()
	TDMeta.migrate_records()
	check("повторный перенос ничего не меняет", TDMeta.map_records == after_first)
	TDMeta.map_records[k_snake] = 15
	TDMeta.migrate_records()
	check("новый рекорд выше старого не затирается", int(TDMeta.map_records[k_snake]) == 15)

	# ── 5. Новые рекорды ──
	TDMeta.map_records = {}
	var legacy_before := TDMeta.records.duplicate(true)
	var mn := TDMap.generate(s_new)
	check("первый результат на карте — рекорд", TDMeta.note_run(s_new, 7, false, true, mn) and TDMeta.record_for_map(s_new, mn) == 7)
	check("меньший результат — не рекорд", not TDMeta.note_run(s_new, 5, false, true, mn) and TDMeta.record_for_map(s_new, mn) == 7)
	var mf := TDMap.fork_test("fork")
	check("тот же сид на другой карте — отдельный рекорд", TDMeta.record_for_map(s_new, mf) == 0
		and TDMeta.note_run(s_new, 3, false, true, mf) and TDMeta.record_for_map(s_new, mn) == 7)
	check("без карты рекорд записывается на карту, которую сид даёт сейчас", TDMeta.note_run(s_new, 9, false, true) and TDMeta.record_for(s_new) == 9)
	TDMeta.credited_runs = {}
	var award := TDMeta.claim_run("rec-147", s_new, 11, 1, false, true, 1.0, mn)
	check("итог забега пишет рекорд сыгранной карты", award["record"] and TDMeta.record_for_map(s_new, mn) == 11)
	check("новые рекорды не пишутся в историю по сиду", TDMeta.records == legacy_before)

	print("\nFAIL: %d" % failures if failures > 0 else "\nВсе проверки PRO-147 прошли")
	quit(1 if failures > 0 else 0)
