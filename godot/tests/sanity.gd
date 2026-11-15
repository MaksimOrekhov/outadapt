extends SceneTree
## Проверка механик без интерфейса: godot --headless --path godot --script res://tests/sanity.gd
## Печатает OK/FAIL по каждому пункту и итог; код выхода 1, если что-то сломано.

var fails := 0


func check(name: String, ok: bool, detail: String = "") -> void:
	print(("OK    " if ok else "FAIL  ") + name + ("" if detail == "" else "  (" + detail + ")"))
	if not ok:
		fails += 1


## Свободная клетка рядом с дорогой.
func free_cell(g: TDGame) -> Vector2i:
	for c in g.map.order:
		for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
			var n: Vector2i = c + d
			if n.x >= 0 and n.y >= 0 and n.x < TDConfig.COLS and n.y < TDConfig.ROWS and not g.map.is_path(n.x, n.y) and not g.map.is_blocked(n.x, n.y) and g.tower_at(n.x, n.y) == null:
				return n
	return Vector2i(-1, -1)


func spawn(g: TDGame, genome: Dictionary, dist: float) -> TDGame.Enemy:
	var e := TDGame.Enemy.new()
	e.id = g.next_id
	g.next_id += 1
	e.genome = genome
	e.ph = TDGenome.phenotype(genome, g.wave)
	e.hp = e.ph["hp"]
	e.dist = dist
	g.enemies.append(e)
	return e


func plain() -> Dictionary:
	var g := {}
	for k in TDGenome.GENES:
		g[k] = 0.0
	return g


func _init() -> void:
	# Импорт пакета Spire: у всех башен есть три модели и анимации оружия.
	var art_loaded := TDArt.ok()
	check("индекс ассетов Spire загружается", art_loaded)
	if art_loaded:
		var tower_assets_ok := true
		for kind in TDConfig.TOWER_KINDS:
			for level in [1, 2, 3]:
				var art := TDArt.tower_level(kind, level)
				var weapon: Dictionary = art.get("weapon", {})
				var projectile: Dictionary = art.get("projectile", {})
				var impact: Dictionary = art.get("impact", {})
				tower_assets_ok = tower_assets_ok and not art.is_empty() and TDArt.tex(art.get("base", "")) != null and not weapon.is_empty() and TDArt.tex(weapon.get("file", "")) != null
				if not projectile.is_empty():
					tower_assets_ok = tower_assets_ok and TDArt.tex(projectile.get("file", "")) != null
				if not impact.is_empty():
					tower_assets_ok = tower_assets_ok and TDArt.tex(impact.get("file", "")) != null
		check("Башни имеют основания, оружие, снаряды и попадания", tower_assets_ok)
		var enemy_assets_ok := TDArt.custom_enemies.size() == 17
		for species in TDArt.custom_enemies:
			var art: Dictionary = TDArt.custom_enemies[species]
			enemy_assets_ok = enemy_assets_ok and TDArt.tex(art.get("file", "")) != null and art.get("frame", 0) == 64
		check("17 моделей врагов загружаются", enemy_assets_ok)
		var tile_assets_ok := true
		for name in ["grass", "road_h", "road_v", "corner_rd", "corner_ld", "corner_ru", "corner_lu"]:
			tile_assets_ok = tile_assets_ok and TDArt.tex(TDArt.meta["tiles"].get(name, "")) != null
		check("трава и все типы дорожных поворотов загружаются", tile_assets_ok)
		var construction: Dictionary = TDArt.meta.get("fx", {}).get("construct", {})
		check("последний кадр стройки точно попадает во вторую строку", TDArt.frame_rect(construction, 43).position.y == 192.0)
		var g_art := plain()
		g_art["plated"] = 0.9
		var ghost_art := plain()
		ghost_art["veil"] = 0.9
		check("главные гены выбирают виды врагов", TDArt.species(g_art, false, false) == "scorpion" and TDArt.species(ghost_art, true, false) == "voidbutterfly")

	# бонусы Мастерской
	var meta := {"gold": 60, "lives": 6, "upgrade_disc": 0.24, "growth_cut": 0.4, "perk_choices": 1, "start_perk": true}
	var g := TDGame.new(4243, null, meta)
	check("стартовое золото с бонусом", g.gold == TDConfig.START_GOLD + 60, str(g.gold))
	check("стартовые жизни с бонусом", g.lives == TDConfig.START_LIVES + 6, str(g.lives))
	check("Наследие: выбор перка на старте, 4 варианта", g.offer.size() == 4, str(g.offer.size()))
	check("волну нельзя начать, пока не выбран перк", not g.start_wave())
	g.choose_perk(g.offer[0])

	# постройка, улучшение, продажа
	g = TDGame.new(4243)
	g.gold = 5000
	var c := free_cell(g)
	check("башня ставится", g.place_tower("arrow", c.x, c.y))
	var t := g.tower_at(c.x, c.y)
	var paid := t.spent
	var up1 := g.upgrade_cost(t)
	check("улучшение до 2-го уровня", g.upgrade_tower(t) and t.level == 2)
	check("на 2→3 без ветки нельзя", not g.upgrade_tower(t))
	check("ветка «Залп» даёт 3 цели", g.upgrade_tower(t, "a") and t.def.get("multishot", 1) == 3)
	check("дальше улучшать некуда", g.upgrade_cost(t) == -1)
	check("вложено = постройка + улучшения", t.spent > paid + up1, str(t.spent))
	var before := g.gold
	var val := g.sell_value(t)
	g.sell_tower(c.x, c.y)
	check("продажа возвращает 70% вложенного", g.gold - before == val and val == int(floor(t.spent * 0.7)), str(val))

	# цена улучшения растёт с числом башен типа; скидка Мастерской работает
	var g2 := TDGame.new(4243, null, {"upgrade_disc": 0.24})
	g2.gold = 5000
	var c2 := free_cell(g2)
	g2.place_tower("cannon", c2.x, c2.y)
	check("Ремесло удешевляет улучшение", g2.upgrade_cost(g2.tower_at(c2.x, c2.y)) < ceil(TDConfig.TOWERS["cannon"]["cost"] * TDConfig.UPGRADE_COST), str(g2.upgrade_cost(g2.tower_at(c2.x, c2.y))))

	# деление
	g = TDGame.new(4243)
	g.wave = 12
	g.phase = "wave"
	var gs := plain()
	gs["split"] = 0.9
	var e := spawn(g, gs, 3.0)
	e.hp = 0.0
	g.step(1.0 / 60.0)
	var kids := 0
	for x in g.enemies:
		if x.child:
			kids += 1
	check("делящийся враг распадается на двоих", kids == TDConfig.SPLIT_COUNT, str(kids))

	# щит
	g = TDGame.new(4243)
	g.wave = 15
	g.phase = "wave"
	var gw := plain()
	gw["ward"] = 0.9
	spawn(g, gw, 3.0)
	var guarded := spawn(g, plain(), 3.3)
	var far := spawn(g, plain(), 9.0)
	g.pending = [{}] # не даём волне закончиться
	g.spawn_t = 99.0
	g.step(1.0 / 60.0)
	check("щит прикрывает соседа", guarded.warded)
	check("щит не достаёт дальнего", not far.warded)

	# цепная молния
	g = TDGame.new(4243)
	g.gold = 5000
	g.wave = 3
	g.phase = "wave"
	g.pending = [{}]
	g.spawn_t = 99.0
	var ct := free_cell(g)
	g.place_tower("tesla", ct.x, ct.y)
	var tes := g.tower_at(ct.x, ct.y)
	# ставим троих врагов рядом с башней, на дорожных клетках
	var center := Vector2(ct.x + 0.5, ct.y + 0.5)
	var best_d := 0.0
	var best_dist := INF
	for i in 400:
		var dd := i * g.map.length / 400.0
		var dist_to := g.map.pos_at(dd).distance_to(center)
		if dist_to < best_dist:
			best_dist = dist_to
			best_d = dd
	var hit_count := 0
	var es: Array = []
	for i in 3:
		es.append(spawn(g, plain(), best_d + i * 0.4))
	g.step(1.0 / 60.0)
	for x in es:
		if x.hp < x.ph["hp"]:
			hit_count += 1
	check("молния бьёт цепью по трём", hit_count == 3, str(hit_count))

	# победа на волне VICTORY_WAVE: прогоняем волны с бесконечными жизнями
	g = TDGame.new(4243)
	g.lives = 100000
	while g.wave <= TDConfig.VICTORY_WAVE and g.phase != "over":
		if g.phase == "build":
			if not g.offer.is_empty():
				g.choose_perk(g.offer[0])
			g.start_wave()
		g.step(1.0 / 20.0)
	check("после волны %d — победа" % TDConfig.VICTORY_WAVE, g.victory, "волна %d" % g.wave)
	check("отчёт по каждой волне", g.reports.size() >= TDConfig.VICTORY_WAVE, str(g.reports.size()))
	check("в отчётах есть давление и проценты", g.reports[0].has("pressure") and g.reports[0].has("interest"))

	print("\n%s: %d проверок не прошло" % ["ГОТОВО" if fails == 0 else "ЕСТЬ ОШИБКИ", fails])
	quit(1 if fails > 0 else 0)
