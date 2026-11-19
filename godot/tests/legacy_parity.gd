extends SceneTree
## PRO-147/213: паритет старых однопутевых забегов. godot --headless --path godot --script res://tests/legacy_parity.gd
## Снимок сохранения посреди 7-й волны (12 башен у дороги, первый перк) на 6 сидах; хэш var_to_bytes без времени сохранения.
## Эталон снят до PRO-139 (коммит 2875dc3) на Windows. Не в CI: побитовое совпадение float между платформами не гарантировано.
## Расхождение значит, что изменилось поведение или формат сохранения обычной карты — это нужно объяснить, а не обновить эталон.

const GOLDEN := {1: 1715223560, 2: 2385908612, 3: 3585916528, 1003: 915732116, 4243: 140110222, 8486: 831410610}


func _initialize() -> void:
	var bad := 0
	for seed_v in GOLDEN:
		var g := TDGame.new(seed_v)
		g.gold = 2000
		var n := 0
		for ci in range(2, g.map.order.size(), 3):
			var c: Vector2i = g.map.order[ci]
			for d in [Vector2i(0, 1), Vector2i(0, -1)]:
				var p: Vector2i = c + d
				if n < 12 and g.place_tower(["arrow", "cannon", "frost", "sniper"][n % 4], p.x, p.y):
					n += 1
		for _w in 6:
			if not g.offer.is_empty():
				g.choose_perk(g.offer[0])
			g.start_wave()
			for _i in 4000:
				g.step(0.05)
				if g.phase != "wave":
					break
		if not g.offer.is_empty():
			g.choose_perk(g.offer[0])
		g.start_wave()
		for _i in 150:
			g.step(0.05)
		var s := TDSave.snapshot(g)
		s.erase("saved_at")
		s.erase("timestamp")
		var h := hash(var_to_bytes(s))
		var ok: bool = h == GOLDEN[seed_v]
		bad += 0 if ok else 1
		print("%s  seed %d: волна %d, врагов %d, хэш %d" % ["OK  " if ok else "FAIL", seed_v, g.wave, g.enemies.size(), h])
	print("\nПаритет %d/%d" % [GOLDEN.size() - bad, GOLDEN.size()])
	quit(1 if bad > 0 else 0)
