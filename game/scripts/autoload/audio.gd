extends Node
## Sound effects (pooled 2D and positional players) and context music with crossfades.

const POOL_2D := 12
const POOL_3D := 24
const FADE_TIME := 1.5

var sfx_volume := 0.8
var music_volume := 0.6

var _players_2d: Array[AudioStreamPlayer] = []
var _players_3d: Array[AudioStreamPlayer3D] = []
var _next_2d := 0
var _next_3d := 0
var _music_a := AudioStreamPlayer.new()
var _music_b := AudioStreamPlayer.new()
var _current_track := ""
var _fade := 1.0
## An ambience loop (Terraria's rain: its RainAmbience track), at the sound
## volume.
var _ambient := AudioStreamPlayer.new()
var _ambient_track := ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players_2d.append(p)
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 8.0
		p.max_distance = 60.0
		add_child(p)
		_players_3d.append(p)
	add_child(_music_a)
	add_child(_music_b)
	add_child(_ambient)
	sfx_volume = float(Settings.get_value("sfx_volume"))
	music_volume = float(Settings.get_value("music_volume"))
	Settings.changed.connect(func(key):
		if key == "sfx_volume":
			sfx_volume = float(Settings.get_value(key))
		elif key == "music_volume":
			music_volume = float(Settings.get_value(key)))


## Loops an ambience (a MusicID name; "" for none) at `volume` (0..1).
func set_ambient(track: String, volume := 1.0) -> void:
	if track != _ambient_track:
		_ambient_track = track
		var id: int = Assets.ids.get("MusicID", {}).get(track, 0)
		_ambient.stream = Assets.music("Music_%d" % id) if id > 0 else null
		if _ambient.stream != null:
			_ambient.play()
		else:
			_ambient.stop()
	_ambient.volume_db = linear_to_db(maxf(0.0001, volume * sfx_volume))


## Plays a sound by Terraria name. Names ending in "_*" pick a random variant
## that exists, e.g. "Dig_*" -> Dig_0..Dig_2.
func play(name: String, volume := 1.0, pitch_jitter := 0.08) -> void:
	var stream := _resolve(name)
	if stream == null:
		return
	var p := _players_2d[_next_2d]
	_next_2d = (_next_2d + 1) % POOL_2D
	p.stream = stream
	p.volume_db = linear_to_db(volume * sfx_volume)
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func play_at(name: String, pos: Vector3, volume := 1.0, pitch_jitter := 0.08) -> void:
	var stream := _resolve(name)
	if stream == null:
		return
	var p := _players_3d[_next_3d]
	_next_3d = (_next_3d + 1) % POOL_3D
	p.stream = stream
	p.global_position = pos
	p.volume_db = linear_to_db(volume * sfx_volume)
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


var _variant_counts := {}


func _resolve(name: String) -> AudioStream:
	if not name.ends_with("_*"):
		return Assets.sound(name)
	var base := name.trim_suffix("*")
	if not _variant_counts.has(base):
		var n := 0
		while Assets.sound(base + str(n)) != null:
			n += 1
		_variant_counts[base] = n
	var count: int = _variant_counts[base]
	return Assets.sound(base + str(randi() % count)) if count > 0 else null


## Switches music to a MusicID name ("OverworldDay", "Night", "Underground", "Boss1", "Title").
func set_music(track: String) -> void:
	if track == _current_track:
		return
	_current_track = track
	var id: int = Assets.ids.get("MusicID", {}).get(track, 0)
	var stream := Assets.music("Music_%d" % id) if id > 0 else null
	# Swap players: the old one fades out while the new one fades in.
	var tmp := _music_a
	_music_a = _music_b
	_music_b = tmp
	_music_a.stream = stream
	_music_a.volume_db = -80.0
	if stream:
		_music_a.play()
	_fade = 0.0


func _process(delta: float) -> void:
	_fade = minf(1.0, _fade + delta / FADE_TIME)
	_music_a.volume_db = linear_to_db(maxf(0.0001, _fade * music_volume))
	_music_b.volume_db = linear_to_db(maxf(0.0001, (1.0 - _fade) * music_volume))
	if _fade >= 1.0 and _music_b.playing:
		_music_b.stop()
