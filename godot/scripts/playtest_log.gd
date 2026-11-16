class_name TDPlaytestLog
extends RefCounted
## PRO-152: журнал живого плейтеста эксперимента роя. Пишется только в забегах с флагом эксперимента
## (`-- --swarm=signature`), по строке JSON на сыгранную волну: что рой заметил и готовит, что игрок построил,
## улучшил и продал между волнами, утечки по типам врагов. Наблюдатель сверяет его с записью экрана
## (docs/balance/experiment-signature-incubation.md, §плейтест). На игру не влияет.

static var directory := "user://playtest"

var path := ""
var _towers := {}


func _init(run_id: String) -> void:
	path = "%s/%s.jsonl" % [directory, run_id.replace(":", "-")]


static func _tower_state(g: TDGame) -> Dictionary:
	var d := {}
	for t in g.towers:
		d[t.id] = {"kind": t.kind, "level": t.level, "branch": t.branch}
	return d


## Запомнить оборону на старте волны: изменения считаются между стартами соседних волн.
func wave_started(g: TDGame) -> void:
	var now := _tower_state(g)
	var built: Array = []
	var upgraded: Array = []
	var sold: Array = []
	for id in now:
		if not _towers.has(id):
			built.append(now[id]["kind"])
		elif int(now[id]["level"]) > int(_towers[id]["level"]):
			upgraded.append("%s→%d%s" % [now[id]["kind"], now[id]["level"], now[id]["branch"]])
	for id in _towers:
		if not now.has(id):
			sold.append(_towers[id]["kind"])
	_towers = now
	_write({"event": "start", "seed": g.seed_value, "family": g.map.family, "difficulty": g.difficulty_id(), "wave": g.wave, "lives": g.lives, "gold": g.gold, "built": built, "upgraded": upgraded, "sold": sold,
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
	_write({"event": "end", "wave": int(r["wave"]), "lives": g.lives, "gold": g.gold, "killed": int(r["killed"]), "leaked": int(r["leaked"]),
		"damage": dmg, "burst": snappedf(float(sig.get("burst", 0.0)), 0.01), "chill": snappedf(float(sig.get("chill", 0.0)), 0.01),
		"air_gap": snappedf(float(sig.get("air_gap", 0.0)), 0.01), "C": snappedf(float(sx.get("C", 0.0)), 0.01), "forecast": forecast})


func run_over(g: TDGame) -> void:
	_write({"event": "over", "wave": g.wave, "victory": g.victory, "lives": g.lives})


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
