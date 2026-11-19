class_name TDPlaytestLog
extends RefCounted
## PRO-152/115: журнал живого плейтеста. Пишется в забегах с флагом эксперимента (`-- --swarm=signature`) и в любых
## забегах при `-- --playtest` (контрольная партия без флага). Первая строка — конфигурация забега, дальше по строке JSON
## на старт и конец волны: что рой заметил и готовит, что игрок построил, улучшил и продал, режимы прицела, утечки по
## типам врагов. Сводка — tests/playtest_summary.py; протокол — docs/balance/pro152-live-playtest.md. На игру не влияет.

static var directory := "user://playtest"

var path := ""
var _towers := {}


func _init(run_id: String) -> void:
	path = "%s/%s.jsonl" % [directory, run_id.replace(":", "-")]


static func _tower_state(g: TDGame) -> Dictionary:
	var d := {}
	for t in g.towers:
		d[t.id] = {"kind": t.kind, "level": t.level, "branch": t.branch, "mode": t.mode}
	return d


## Конфигурация забега: сборка, флаг, сид, семейство карты, сложность, режим, Мастерская (бонусы), окно.
func header(g: TDGame, info: Dictionary) -> void:
	var bonuses := {}
	for k in g.meta:
		if k not in ["difficulty", "mode", "locked", "swarm_model"]:
			bonuses[k] = g.meta[k]
	var d := info.duplicate()
	d.merge({"event": "run", "swarm_model": String(g.meta.get("swarm_model", "off")), "seed": g.seed_value, "family": g.map.family,
		"map": g.map.map_name, "difficulty": g.difficulty_id(), "mode": g.mode_id(), "workshop_bonuses": bonuses,
		"locked": g.meta.get("locked", []), "start_gold": g.gold, "start_lives": g.lives})
	# PRO-213: карта с развилкой (или откат на обычную карту) — геометрия, длины дорог и общие участки
	if g.map.is_multi() or g.map.fork_fallback:
		var lens: Array = []
		for r in g.map.routes:
			lens.append(r.order.size())
		d.merge({"geometry": g.map.geometry_key(), "routes_cells": lens, "shared_in": g.map.shared_in(), "shared_out": g.map.shared_out(),
			"route_plan": g.map.route_plan, "fork_fallback": g.map.fork_fallback})
	_write(d)


## Запомнить оборону на старте волны: изменения считаются между стартами соседних волн.
func wave_started(g: TDGame) -> void:
	var now := _tower_state(g)
	var built: Array = []
	var upgraded: Array = []
	var sold: Array = []
	var retargeted: Array = []
	for id in now:
		if not _towers.has(id):
			built.append(now[id]["kind"])
		elif int(now[id]["level"]) > int(_towers[id]["level"]):
			upgraded.append("%s→%d%s" % [now[id]["kind"], now[id]["level"], now[id]["branch"]])
		if _towers.has(id) and now[id]["mode"] != _towers[id]["mode"]:
			retargeted.append("%s:%s" % [now[id]["kind"], now[id]["mode"]])
	for id in _towers:
		if not now.has(id):
			sold.append(_towers[id]["kind"])
	_towers = now
	_write({"event": "start", "seed": g.seed_value, "family": g.map.family, "difficulty": g.difficulty_id(), "wave": g.wave, "lives": g.lives, "gold": g.gold, "built": built, "upgraded": upgraded, "sold": sold, "retargeted": retargeted,
		"towers": _counts(g),
		"strains_in_wave": _wave_strains(g)})


func wave_ended(g: TDGame) -> void:
	if g.reports.is_empty():
		return
	var r: Dictionary = g.reports[g.reports.size() - 1]
	var dmg := {}
	for k in r["damageBy"]:
		if float(r["damageBy"][k]) > 0.0:
			dmg[k] = int(r["damageBy"][k])
	var forecast: Array = []
	for e in TDStrains.forecast(g):
		forecast.append({"id": e["id"], "phase": e["phase"], "inc": snappedf(e["inc"], 0.01), "share": snappedf(e["share"], 0.01), "appear": e["appear"]})
	var sx: Dictionary = r.get("strains", {})
	var sig: Dictionary = sx.get("sig", {})
	var d := {"event": "end", "wave": int(r["wave"]), "lives": g.lives, "gold": g.gold, "killed": int(r["killed"]), "leaked": int(r["leaked"]),
		"damage": dmg, "burst": snappedf(float(sig.get("burst", 0.0)), 0.01), "rapid": snappedf(float(sig.get("rapid", 0.0)), 0.01), "chill": snappedf(float(sig.get("chill", 0.0)), 0.01),
		"air_gap": snappedf(float(sig.get("air_gap", 0.0)), 0.01), "C": snappedf(float(sx.get("C", 0.0)), 0.01), "forecast": forecast}
	# PRO-213: по дорогам — сколько врагов волны убито и прорвалось и какая доля собственных клеток дороги обстреливается
	if g.map.is_multi():
		var per := {}
		for x in TDAdvisor.route_coverage(g):
			per[x["id"]] = {"name": x["name"], "killed": 0, "leaked": 0, "cover": snappedf(float(x["pct"]), 0.01)}
		for f in g.finished:
			var rid: int = int(f.get("route", 0))
			if per.has(rid):
				per[rid]["leaked" if float(f["fitness"]) >= 1.5 else "killed"] += 1
		d["routes"] = per.values()
	_write(d)


func run_over(g: TDGame) -> void:
	_write({"event": "over", "wave": g.wave, "victory": g.victory, "lives": g.lives})


static func _counts(g: TDGame) -> Dictionary:
	var n := {}
	for t in g.towers:
		n[t.kind] = int(n.get(t.kind, 0)) + 1
	return n


static func _wave_strains(g: TDGame) -> Dictionary:
	var n := {}
	for ge in g.wave_genomes:
		var s := String(ge.get("strain", ""))
		if s != "":
			n[s] = int(n.get(s, 0)) + 1
	return n


func _write(d: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
	if f == null:
		return
	f.seek_end()
	d["t"] = Time.get_datetime_string_from_system(false, true)
	f.store_line(JSON.stringify(d))
	f.close()
