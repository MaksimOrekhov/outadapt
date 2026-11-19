extends SceneTree
## PRO-213: таблица сгенерированных развилок по сидам (CSV). Сиды (i+1)·4243, как в харнессе.
##   godot --headless --path godot --script res://tests/fork_maps_report.gd -- --seeds=1000 --out=../docs/architecture/data/pro213/fork_maps.csv

func _initialize() -> void:
	var seeds := 1000
	var out_path := "../build/fork/fork_maps.csv"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--seeds="):
			seeds = int(a.substr(8))
		elif a.begins_with("--out="):
			out_path = a.substr(6)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_path).get_base_dir())
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	f.store_line("seed,family,fallback,cells_north,cells_south,length_ratio,shared_in,shared_out,road_cells,rocks,free_cells,geometry")
	var stats := {}
	for fam in TDMap.FORK_FAMILIES:
		var fb := 0
		for i in seeds:
			var s := (i + 1) * 4243
			var m := TDMap.generate(s, fam)
			var free := 0
			for x in TDConfig.COLS:
				for y in TDConfig.ROWS:
					if not m.cells.has(Vector2i(x, y)) and not m.blocked.has(Vector2i(x, y)):
						free += 1
			if m.fork_fallback:
				fb += 1
				f.store_line("%d,%s,1,%d,,,,,%d,%d,%d,%s" % [s, fam, m.order.size(), m.cells.size(), m.blocked.size(), free, m.geometry_key()])
				continue
			var nid := 0 if TDAdvisor.route_name(m, 0) == "северная" else 1
			var ratio := maxf(m.routes[0].length, m.routes[1].length) / minf(m.routes[0].length, m.routes[1].length)
			f.store_line("%d,%s,0,%d,%d,%.3f,%d,%d,%d,%d,%d,%s" % [s, fam, m.routes[nid].order.size(), m.routes[1 - nid].order.size(), ratio,
				m.shared_in(), m.shared_out(), m.cells.size(), m.blocked.size(), free, m.geometry_key()])
		stats[fam] = fb
	f.close()
	print("written %s; fallback: %s of %d per family" % [out_path, stats, seeds])
	quit()
