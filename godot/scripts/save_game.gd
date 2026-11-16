class_name TDSave
extends RefCounted
## Versioned data-only snapshots, including mid-wave status and RNG state.

const VERSION := 1
const DIRECTORY := "user://saves"
static var directory := DIRECTORY
const GAME_FIELDS := ["gold", "lives", "wave", "phase", "upcoming", "pending", "wave_genomes", "upcoming_boss", "pending_boss", "boss_killed", "spawn_t", "finished", "killed", "leaked", "damage_by", "perks", "offer", "next_id", "meta", "run_kills", "run_leaked", "bosses_killed", "run_damage", "victory"]
## Появились позже версии 1: в старых сохранениях их нет, это не ошибка.
const OPTIONAL_GAME_FIELDS := ["upcoming_special", "cur_special", "vaccine", "vaccine_cd", "vaccine_uses", "lure", "lure_cd", "lure_uses"]
const OPTIONAL_ENEMY_FIELDS := ["ability", "shield", "shield_max", "summon_t", "immune_type", "summon_left", "lured_gene"]
## PRO-152: пишутся только в забегах с флагом эксперимента, поэтому сохранения без флага остаются байт-в-байт прежними.
const STRAIN_GAME_FIELDS := ["strains", "strain_acc"]
const STRAIN_ENEMY_FIELDS := ["strain", "shell"]
const TOWER_FIELDS := ["id", "kind", "x", "y", "cd", "level", "branch", "spent", "mode", "kills", "dealt", "hits", "boosted", "recoil", "age", "aim", "upgraded_t"]
const ENEMY_FIELDS := ["id", "genome", "ph", "hp", "dist", "slow_t", "slow_factor", "scorch_t", "scorch_extra", "poison_t", "poison_dps", "boss", "child", "warded", "hit_flash", "last_kind"]

static func fields(object: Object, names: Array) -> Dictionary:
	var result := {}
	for key in names:
		var value = object.get(key)
		result[key] = value.duplicate(true) if value is Array or value is Dictionary else value
	return result

static func snapshot(game: TDGame, session: Dictionary = {}) -> Dictionary:
	var towers := {}
	var live_ids: Array = []
	for tower in game.towers:
		towers[tower.id] = fields(tower, TOWER_FIELDS)
		live_ids.append(tower.id)
	var strain_on := game.strains_on()
	var enemies: Array = []
	for enemy in game.enemies:
		var data := fields(enemy, ENEMY_FIELDS + OPTIONAL_ENEMY_FIELDS + (STRAIN_ENEMY_FIELDS if strain_on else []))
		data["poison_by"] = enemy.poison_by.id if enemy.poison_by != null else -1
		if enemy.poison_by != null:
			towers[enemy.poison_by.id] = fields(enemy.poison_by, TOWER_FIELDS)
		enemies.append(data)
	return {
		"version": VERSION, "saved_at": Time.get_datetime_string_from_system(false, true), "timestamp": Time.get_unix_time_from_system(),
		"seed": game.seed_value, "map_name": game.map.map_name,
		"waypoints": game.map.waypoints.duplicate(), "blocked": game.map.blocked.duplicate(),
		"state": fields(game, GAME_FIELDS + OPTIONAL_GAME_FIELDS + (STRAIN_GAME_FIELDS if strain_on else [])), "reports": game.reports.duplicate(true),
		"towers": towers, "live_towers": live_ids, "enemies": enemies,
		"rng": game.rng.a, "perk_rng": game.perk_rng.a, "session": session.duplicate(true),
	}

static func valid(data: Variant) -> bool:
	if not data is Dictionary or data.get("version", -1) != VERSION:
		return false
	for key in ["state", "towers", "blocked", "session"]:
		if not data.get(key) is Dictionary:
			return false
	for key in ["waypoints", "live_towers", "enemies", "reports"]:
		if not data.get(key) is Array:
			return false
	for key in ["seed", "rng", "perk_rng"]:
		if not data.get(key) is int:
			return false
	if not data.get("map_name", "") is String or not data.get("saved_at", "") is String or not numeric(data.get("timestamp", 0)):
		return false
	for p in data["blocked"]:
		if not p is Vector2i or p.x < 0 or p.y < 0 or p.x >= TDConfig.COLS or p.y >= TDConfig.ROWS:
			return false
	if data["waypoints"].size() < 2 or data["waypoints"].size() > 64 or data["enemies"].size() > 10000 or data["towers"].size() > 512:
		return false
	var previous: Vector2i
	for i in data["waypoints"].size():
		var p = data["waypoints"][i]
		if not p is Vector2i or p.x < 0 or p.y < 0 or p.x >= TDConfig.COLS or p.y >= TDConfig.ROWS:
			return false
		if i > 0 and p.x != previous.x and p.y != previous.y:
			return false
		previous = p
	var typed_waypoints: Array[Vector2i] = []
	typed_waypoints.assign(data["waypoints"])
	if TDMap.rasterize(typed_waypoints).is_empty():
		return false
	for key in GAME_FIELDS:
		if not data["state"].has(key):
			return false
	for key in ["gold", "lives", "wave", "killed", "leaked", "next_id", "run_kills", "run_leaked", "bosses_killed"]:
		if not data["state"][key] is int:
			return false
	for key in ["upcoming", "pending", "wave_genomes", "finished", "offer"]:
		if not data["state"][key] is Array:
			return false
	for key in ["upcoming_boss", "pending_boss", "damage_by", "perks", "meta", "run_damage"]:
		if not data["state"][key] is Dictionary:
			return false
	if not numeric(data["state"]["spawn_t"]) or not data["state"]["boss_killed"] is bool or not data["state"]["victory"] is bool:
		return false
	if data["state"]["phase"] not in ["build", "wave", "over"] or data["state"]["wave"] < 1:
		return false
	for id in data["towers"]:
		var t = data["towers"][id]
		if not t is Dictionary:
			return false
		for key in TOWER_FIELDS:
			if not t.has(key):
				return false
		for key in ["id", "x", "y", "level", "spent", "kills", "hits", "boosted"]:
			if not t[key] is int:
				return false
		for key in ["cd", "dealt", "recoil", "age", "upgraded_t"]:
			if not numeric(t[key]):
				return false
		if not t["aim"] is Vector2 or t["branch"] not in ["", "a", "b"] or t["mode"] not in ["first", "strong", "fresh"]:
			return false
		if not TDConfig.TOWERS.has(t["kind"]) or t["level"] < 1 or t["level"] > 3 or t["x"] < 0 or t["x"] >= TDConfig.COLS or t["y"] < 0 or t["y"] >= TDConfig.ROWS:
			return false
	for id in data["live_towers"]:
		if not data["towers"].has(id):
			return false
	for e in data["enemies"]:
		if not e is Dictionary or not e.get("ph") is Dictionary or not e.get("genome") is Dictionary:
			return false
		for key in ENEMY_FIELDS:
			if not e.has(key):
				return false
		if not e["id"] is int or not e.get("poison_by", -1) is int or not e["last_kind"] is String:
			return false
		for key in ["boss", "child", "warded"]:
			if not e[key] is bool:
				return false
		for gene in TDGenome.GENES:
			if not numeric(e["genome"].get(gene)):
				return false
		var phenotype := TDGenome.phenotype(e["genome"], data["state"]["wave"])
		for key in phenotype:
			if not e["ph"].has(key):
				return false
			if numeric(phenotype[key]):
				if not numeric(e["ph"][key]):
					return false
			elif typeof(phenotype[key]) != typeof(e["ph"][key]):
				return false
		for key in ["hp", "dist", "slow_t", "slow_factor", "scorch_t", "scorch_extra", "poison_t", "poison_dps", "hit_flash"]:
			if not numeric(e[key]):
				return false
		if e.get("poison_by", -1) != -1 and not data["towers"].has(e["poison_by"]):
			return false
	var vaccine = data["state"].get("vaccine", {})
	if not vaccine is Dictionary:
		return false
	if not vaccine.is_empty():
		if not vaccine.get("gene") is String or not TDGenome.GENES.has(vaccine["gene"]) or not vaccine.get("left") is int or not numeric(vaccine.get("cap")):
			return false
		if vaccine["left"] < 1 or vaccine["left"] > TDConfig.VACCINE_WAVES:
			return false
	var lure = data["state"].get("lure", {})
	if not lure is Dictionary:
		return false
	var state_wave: int = data["state"]["wave"]
	if not lure.is_empty():
		if not lure.get("gene") is String or not TDConfig.LURE_GENES.has(lure["gene"]) or not numeric(lure.get("boost")) or not lure.get("wave") is int:
			return false
		if float(lure["boost"]) <= 0.0 or float(lure["boost"]) > 1.0:
			return false
		# приманка живёт ровно одну волну и снимается в _end_wave: её волна обязана быть текущей
		if lure["wave"] != state_wave:
			return false
		# не на боссовых и особых волнах и не вместе с вакциной на тот же ген
		if state_wave % TDConfig.BOSS_EVERY == 0 or TDConfig.special_for(state_wave) != "" or data["state"]["phase"] == "over":
			return false
		if vaccine.get("gene", "") == lure["gene"]:
			return false
		if state_wave < TDConfig.LURE_MIN_WAVE:
			return false
	for e in data["enemies"]:
		var lg = e.get("lured_gene", "")
		if not lg is String:
			return false
		if lg != "" and (lure.is_empty() or lure["gene"] != lg):
			return false
	if not _valid_strains(data):
		return false
	for key in ["lure_cd", "lure_uses"]:
		if data["state"].has(key) and (not data["state"][key] is int or data["state"][key] < 0):
			return false
	if data["state"].get("lure_cd", 0) > TDConfig.LURE_COOLDOWN or (not lure.is_empty() and data["state"].get("lure_cd", 0) > 0):
		return false
	for key in ["vaccine_cd", "vaccine_uses"]:
		if data["state"].has(key) and (not data["state"][key] is int or data["state"][key] < 0):
			return false
	for report in data["reports"]:
		if not report is Dictionary:
			return false
	for key in ["speed", "_banked_waves", "_banked_bosses", "_run_points"]:
		if data["session"].has(key) and not data["session"][key] is int:
			return false
	for key in ["user_paused", "_victory_seen", "_banked_victory", "_run_closed", "_new_record"]:
		if data["session"].has(key) and not data["session"][key] is bool:
			return false
	if data["session"].has("acc") and not numeric(data["session"]["acc"]):
		return false
	if data["session"].has("_run_id") and not data["session"]["_run_id"] is String:
		return false
	return data.has("seed") and data.has("rng") and data.has("perk_rng")

## PRO-152: состояние эксперимента. Без флага в забеге полей и врагов пакетов быть не должно.
static func _valid_strains(data: Dictionary) -> bool:
	var meta: Dictionary = data["state"]["meta"]
	var on := TDStrains.enabled(meta)
	for key in STRAIN_GAME_FIELDS:
		if not data["state"].has(key):
			continue
		if not on or not data["state"][key] is Dictionary:
			return false
	var st = data["state"].get("strains", {})
	if not st.is_empty():
		if not st.get("sig") is Dictionary or not st.get("pk") is Dictionary or not st.get("n") is int:
			return false
		for p in TDStrains.PACKAGES:
			var k = st["pk"].get(p)
			if not k is Dictionary or not numeric(k.get("inc")) or not numeric(k.get("share")) or not k.get("appear") is int:
				return false
			if k.get("phase") not in ["quiet", "incubating", "announced", "active", "fading"]:
				return false
			if float(k["share"]) < 0.0 or float(k["share"]) > 1.0:
				return false
	var acc = data["state"].get("strain_acc", {})
	if not acc.is_empty():
		for key in ["del", "el", "rng", "tgt", "kind_burst", "kind_rapid", "kind"]:
			if not acc.get(key) is Dictionary:
				return false
		for key in ["total", "chill", "life_t", "slow_t"]:
			if not numeric(acc.get(key)):
				return false
	for e in data["enemies"]:
		var strain = e.get("strain", "")
		if not strain is String or not e.get("shell", 0) is int:
			return false
		if strain != "" and (not TDStrains.acts(meta) or not TDStrains.PACKAGES.has(strain)):
			return false
		if int(e.get("shell", 0)) < 0 or int(e.get("shell", 0)) > 1 or (int(e.get("shell", 0)) > 0 and not TDStrains.DEFLECT.has(strain)):
			return false
	for g in data["state"]["upcoming"] + data["state"]["pending"]:
		if g is Dictionary and g.has("strain") and (not TDStrains.acts(meta) or not TDStrains.PACKAGES.has(g["strain"])):
			return false
	return true

static func numeric(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func restore(data: Variant) -> TDGame:
	if not valid(data):
		return null
	data = data.duplicate(true)
	var waypoints: Array[Vector2i] = []
	waypoints.assign(data["waypoints"])
	var map := TDMap.build(data["seed"], data.get("map_name", "Карта"), waypoints, data["blocked"])
	var game := TDGame.new(data["seed"], map)
	for key in GAME_FIELDS:
		game.set(key, data["state"][key])
	for key in OPTIONAL_GAME_FIELDS + STRAIN_GAME_FIELDS:
		if data["state"].has(key):
			game.set(key, data["state"][key])
	# башни, добавленные после создания сохранения, не должны ломать учёт урона
	var zero := TDGame._zero_damage()
	game.damage_by = zero.merged(game.damage_by, true)
	game.run_damage = zero.merged(game.run_damage, true)
	game.reports.assign(data["reports"])
	game.rng.a = data["rng"]
	game.perk_rng.a = data["perk_rng"]
	var towers := {}
	for id in data["towers"]:
		var tower := TDGame.Tower.new()
		for key in TOWER_FIELDS:
			tower.set(key, data["towers"][id][key])
		tower.def = TDConfig.tower_def(tower.kind, tower.level, tower.branch)
		towers[id] = tower
	for id in data["live_towers"]:
		game.towers.append(towers[id])
	for record in data["enemies"]:
		var enemy := TDGame.Enemy.new()
		for key in ENEMY_FIELDS:
			enemy.set(key, record[key])
		for key in OPTIONAL_ENEMY_FIELDS + STRAIN_ENEMY_FIELDS:
			if record.has(key):
				enemy.set(key, record[key])
		enemy.poison_by = towers.get(record.get("poison_by", -1))
		game.enemies.append(enemy)
	return game

static func path_for(slot: int) -> String:
	return directory + ("/autosave.dat" if slot == 3 else "/slot_%d.dat" % (slot + 1))

static func read_file(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null or f.get_length() > 16 * 1024 * 1024:
		return {}
	var data = f.get_var(false)
	return data if valid(data) else {}

static func read(slot: int) -> Dictionary:
	var path := path_for(slot)
	var data := read_file(path)
	# A previous complete snapshot remains available after an interrupted replacement.
	return read_file(path + ".bak") if data.is_empty() else data

static func write_file(path: String, data: Dictionary) -> Error:
	var absolute := ProjectSettings.globalize_path(path)
	var err := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if err != OK:
		return err
	var f := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_var(data, false)
	f.flush()
	err = f.get_error()
	f.close()
	if err != OK:
		return err
	if FileAccess.file_exists(path):
		if read_file(path).is_empty():
			err = DirAccess.remove_absolute(absolute)
		else:
			if FileAccess.file_exists(path + ".bak"):
				DirAccess.remove_absolute(absolute + ".bak")
			err = DirAccess.rename_absolute(absolute, absolute + ".bak")
		if err != OK:
			return err
	err = DirAccess.rename_absolute(absolute + ".tmp", absolute)
	if err != OK and FileAccess.file_exists(path + ".bak"):
		DirAccess.rename_absolute(absolute + ".bak", absolute)
	return err

static func write(slot: int, game: TDGame, session: Dictionary) -> Error:
	return write_file(path_for(slot), snapshot(game, session))

static func latest_slot() -> int:
	var latest := -1
	var stamp := -1.0
	for slot in 4:
		var data := read(slot)
		if not data.is_empty() and float(data.get("timestamp", 0)) > stamp:
			stamp = data["timestamp"]
			latest = slot
	return latest
