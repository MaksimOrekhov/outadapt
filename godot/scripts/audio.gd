class_name TDAudio
extends Node
## Звук: эффекты (пул проигрывателей с ограничением частоты) и фоновая музыка.
## Источники и лицензии — в assets/audio/CREDITS.md.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC := [
	"res://assets/audio/music/shakkar.ogg",
	"res://assets/audio/music/exploration.mp3",
]
const POOL := 20
const CFG := "user://audio.cfg"
var config_path := CFG

## Громкость (дБ) и обрезка по длине (с) для выстрелов разных башен.
const SHOTS := {
	"arrow": {"db": -9.0, "len": 0.35},
	"cannon": {"db": -6.0, "len": 0.9},
	"ember": {"db": -16.0, "len": 0.35},
	"frost": {"db": -14.0, "len": 0.35},
	"sniper": {"db": -11.0, "len": 0.5},
	"poison": {"db": -12.0, "len": 0.45},
	"flak": {"db": -14.0, "len": 0.25},
	"tesla": {"db": -13.0, "len": 0.35},
	"net": {"db": -13.0, "len": 0.35, "group": "shot_frost"},
}

var sfx_on: bool = true
var music_on: bool = true
var master_volume: float = 1.0
var music_volume: float = 1.0
var sfx_volume: float = 1.0

var _sfx: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _last: Dictionary = {}
var _music_player: AudioStreamPlayer
var _music_fade: Tween
var _track: int = -1
var _time: float = 0.0


func _ready() -> void:
	_ensure_bus("Sfx")
	_ensure_bus("Music")
	for i in POOL:
		var p := AudioStreamPlayer.new()
		p.bus = "Sfx"
		add_child(p)
		_players.append(p)
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = "Music"
	_music_player.volume_db = -80.0
	add_child(_music_player)
	_load_cfg()
	_apply_mutes()


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.get_bus_count() - 1
	AudioServer.set_bus_name(i, bus_name)
	AudioServer.set_bus_send(i, "Master")


func _group(g: String) -> Array:
	if _sfx.has(g):
		return _sfx[g]
	var list: Array = []
	for i in 6:
		for ext in ["ogg", "wav"]:
			var path := "%s%s_%d.%s" % [SFX_DIR, g, i, ext]
			if ResourceLoader.exists(path):
				list.append(load(path))
				break
	_sfx[g] = list
	return list


## Проигрывает случайный вариант звука из группы. gap — минимальная пауза между
## одинаковыми звуками, len — обрезать звук через столько секунд (0 — целиком).
func play(g: String, db: float = 0.0, gap: float = 0.04, len: float = 0.0, pitch_var: float = 0.07) -> void:
	if not sfx_on:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(g, -10.0)) < gap:
		return
	var list := _group(g)
	if list.is_empty():
		return
	for p in _players:
		if p.playing:
			continue
		_last[g] = now
		var s: AudioStream = list[randi() % list.size()]
		p.stream = s
		p.volume_db = db
		p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
		p.play()
		if len > 0.0:
			get_tree().create_timer(len).timeout.connect(func():
				if is_instance_valid(p) and p.stream == s:
					p.stop())
		return


func on_event(ev: Dictionary) -> void:
	match ev["type"]:
		"shot":
			if ev.get("hop", false):
				return
			var cfg: Dictionary = SHOTS.get(ev["kind"], {})
			if not cfg.is_empty():
				play(cfg.get("group", "shot_" + ev["kind"]), cfg["db"], 0.05, cfg["len"])
		"hit":
			if ev["kind"] == "cannon":
				play("boom", -10.0, 0.08, 0.6)
			else:
				play("hit", -17.0, 0.07)
		"death":
			if ev.get("boss", false):
				play("boom", -2.0, 0.2, 1.2)
				play("hit_heavy", -4.0, 0.2)
			else:
				play("death", -9.0, 0.06)
		"leak":
			play("leak", -3.0, 0.2)
			if ev.get("boss", false):
				play("boom", -4.0, 0.3, 1.0)
		"place":
			play("place", -5.0, 0.08)
		"upgrade":
			play("upgrade", -6.0, 0.1)
		"sell":
			play("sell", -6.0, 0.08)
		"victory":
			play("victory", -3.0, 1.0)


func wave_started(boss: bool) -> void:
	play("wave", -4.0, 0.5)
	if boss:
		play("hit_heavy", -2.0, 0.5)


func defeat() -> void:
	play("defeat", -3.0, 1.0)


func ui_click() -> void:
	play("ui_click", -10.0, 0.03, 0.0, 0.04)


func ui_error() -> void:
	play("ui_error", -9.0, 0.15)


func ui_open() -> void:
	play("ui_open", -10.0, 0.1)


## Включает музыку; track < 0 — следующая по кругу.
func play_music(track: int = -1) -> void:
	var next_track := (_track + 1) % MUSIC.size() if track < 0 else track % MUSIC.size()
	if next_track == _track and _music_player.playing:
		return
	_track = next_track
	var s: AudioStream = load(MUSIC[_track])
	if s == null:
		return
	if is_instance_valid(_music_fade):
		_music_fade.kill()
	_music_player.stop()
	if "loop" in s:
		s.loop = true
	_music_player.stream = s
	_music_player.volume_db = -80.0
	_music_player.play()
	_music_fade = create_tween()
	_music_fade.tween_property(_music_player, "volume_db", -17.0, 3.0)


func toggle_sfx() -> bool:
	sfx_on = not sfx_on
	_apply_mutes()
	_save_cfg()
	return sfx_on


func toggle_music() -> bool:
	music_on = not music_on
	_apply_mutes()
	_save_cfg()
	return music_on


func _apply_mutes() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Sfx"), not sfx_on)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not music_on)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Master"), linear_to_db(maxf(0.0001, master_volume)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), master_volume <= 0.0)
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Music"), linear_to_db(maxf(0.0001, music_volume)))
	AudioServer.set_bus_volume_db(AudioServer.get_bus_index("Sfx"), linear_to_db(maxf(0.0001, sfx_volume)))
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not music_on or music_volume <= 0.0)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Sfx"), not sfx_on or sfx_volume <= 0.0)


func set_volume(channel: String, value: float) -> void:
	if channel not in ["master", "music", "sfx"]:
		return
	set(channel + "_volume", clampf(value, 0.0, 1.0))
	_apply_mutes()


func stop_effects() -> void:
	for player in _players:
		player.stop()


func _exit_tree() -> void:
	stop_effects()
	if is_instance_valid(_music_fade):
		_music_fade.kill()
	if is_instance_valid(_music_player):
		_music_player.stop()
		_music_player.stream = null


func _load_cfg() -> void:
	var cf := ConfigFile.new()
	if cf.load(config_path) == OK:
		sfx_on = cf.get_value("audio", "sfx", true)
		music_on = cf.get_value("audio", "music", true)
		for channel in ["master", "music", "sfx"]:
			set(channel + "_volume", clampf(float(cf.get_value("audio", channel + "_volume", 1.0)), 0, 1))


func _save_cfg() -> Error:
	var cf := ConfigFile.new()
	cf.set_value("audio", "sfx", sfx_on)
	cf.set_value("audio", "music", music_on)
	for channel in ["master", "music", "sfx"]:
		cf.set_value("audio", channel + "_volume", get(channel + "_volume"))
	return cf.save(config_path)
