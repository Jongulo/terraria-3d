class_name SkySystem
extends Node3D
## Day/night cycle with Terraria timing (15 min day, 9 min night), and the sky:
## a shader gradient with sunrise/sunset glow and twinkling stars
## (shaders/sky.gdshader), the sun and moon, drifting Terraria clouds, and
## rings of Terraria background art (mountains, then forest) that change with
## the biome you're in, cross-fading. Everything distant sits beyond the view
## distance, so terrain is always in front of it.

signal dawn
signal dusk

const DAY_LENGTH := 54000.0  # ticks, like Terraria
const NIGHT_LENGTH := 32400.0
const TICKS_PER_SECOND := 60.0

## Background layers per biome, far to near (Terraria's Background_N images):
## mountains, nearer mountains or hills, then trees. "" is the forest.
const BACKDROPS := {
	"": [7, 8, 10],
	"snow": [35, 36, 37],
	"desert": [7, 20, 21],
	"jungle": [7, 8, 17],
	"corruption": [7, 8, 13],
	"crimson": [7, 8, 44],
	"ocean": [7, 8],
}
## How far below the camera each ring's centre is (times its radius): the
## far mountains rise highest, the trees in front lower down.
const RING_DROP := [0.03, 0.08, 0.1]
## How hazy each ring is (far layers fade into the sky colour, like Terraria's).
const HAZE := [0.45, 0.25, 0.08]
## Normal clouds (Cloud_N); 22-41 are Terraria's rare shaped clouds.
const CLOUDS := [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 14, 15, 16, 17, 18, 19, 20, 21]
const RARE_CLOUDS := 22
const CLOUD_SLOTS := 26
## Cloud colour in the middle of the night (it multiplies the sprite's).
const NIGHT_CLOUD := Color(0.13, 0.15, 0.24)
## The sky through the day by the clock (hours: 0 is midnight, the day runs
## 4:30 to 19:30), eased from key to key so dawn and dusk fade, with nothing
## jumping when day turns to night. The light ramps over Terraria's 13500
## ticks (3.75 hours) after sunrise and before sunset.
const _NIGHT := {"light": 0.22, "tint": Color(0.75, 0.8, 1.0), "top": Color(0.02, 0.03, 0.09), "horizon": Color(0.05, 0.07, 0.16),
		"glow": 0.0, "glow_color": Color(0.75, 0.35, 0.3), "stars": 1.0, "halo": 0.25, "halo_color": Color(0.6, 0.7, 1.0)}
const _TWILIGHT := {"light": 0.25, "tint": Color(0.8, 0.78, 0.95), "top": Color(0.06, 0.05, 0.13), "horizon": Color(0.25, 0.12, 0.14),
		"glow": 0.15, "glow_color": Color(0.75, 0.35, 0.3), "stars": 0.85, "halo": 0.25, "halo_color": Color(0.6, 0.7, 1.0)}
const _SUNRISE := {"light": 0.35, "tint": Color(1.0, 0.75, 0.6), "top": Color(0.22, 0.18, 0.32), "horizon": Color(0.85, 0.45, 0.3),
		"glow": 1.0, "glow_color": Color(1.0, 0.5, 0.25), "stars": 0.45, "halo": 0.35, "halo_color": Color(1.0, 0.85, 0.7)}
const _SUNSET := {"light": 0.35, "tint": Color(1.0, 0.75, 0.6), "top": Color(0.25, 0.16, 0.26), "horizon": Color(0.85, 0.45, 0.3),
		"glow": 1.0, "glow_color": Color(1.0, 0.5, 0.25), "stars": 0.4, "halo": 0.35, "halo_color": Color(1.0, 0.85, 0.7)}
const _MORNING := {"light": 0.7, "tint": Color(1.0, 0.88, 0.8), "top": Color(0.3, 0.42, 0.75), "horizon": Color(0.8, 0.65, 0.62),
		"glow": 0.35, "glow_color": Color(1.0, 0.5, 0.25), "stars": 0.0, "halo": 0.45, "halo_color": Color(1.0, 0.92, 0.7)}
const _DAY := {"light": 1.0, "tint": Color.WHITE, "top": Color(0.33, 0.55, 0.98), "horizon": Color(0.6, 0.78, 1.0),
		"glow": 0.0, "glow_color": Color(1.0, 0.5, 0.25), "stars": 0.0, "halo": 0.45, "halo_color": Color(1.0, 0.92, 0.7)}
const SKY_KEYS := [[0.0, _NIGHT], [3.25, _NIGHT], [4.5, _SUNRISE], [6.0, _MORNING], [8.25, _DAY], [15.75, _DAY],
		[18.0, _MORNING], [19.5, _SUNSET], [21.0, _TWILIGHT], [22.5, _NIGHT], [24.0, _NIGHT]]

## Ticks into the current day or night.
var time := 13500.0
var is_day := true
## Terraria's wind (Main.UpdateWeather): `wind` (windSpeedCurrent, about
## -0.8..0.8; positive blows toward +x) eases toward `wind_target`, which
## wanders: every 900-2700 ticks it moves a little, and every 10-30 of those
## a new spell starts (calm, a breeze, wind or a gale). Weak (at most 0.35)
## until someone has 120 max life. Leaves fall with it (FallingLeaves).
var wind := 0.0
var wind_target := 0.0
var _wind_counter := 0
var _extreme_wind_counter := 0
var _wind_acc := 0.0
## Max life of the strongest player (the game keeps it up to date).
var strongest_life := 100
const MAX_WIND := 0.8
var moon_phase := 0
## Sun brightness and tint applied to every voxel/sprite material.
var sky_light := 1.0
var sky_tint := Color.WHITE
var camera: Camera3D
## Underground the backdrop fades away and the fog turns black.
var depth_factor := 0.0
## Corruption / Crimson sky: blended in by evil_amount (0-1).
var evil_color := Color(0.34, 0.26, 0.5)
var evil_amount := 0.0
## The biome whose backdrop shows (Game.biome), and how far into the Space
## layer you are (0 below it .. 1 well inside: the sky darkens, stars show).
var biome := ""
var space_factor := 0.0
## Where the open sea reaches the horizon the backdrop isn't drawn (an island's
## mountains don't rise out of the ocean): `sea_query` (set by the game for
## worlds with an ocean) gives, for SEA_DIRECTIONS directions round a point,
## how far you see before the sea (VoxelWorld.sea_distances); the rings' shader
## reads the result as a mask round the horizon.
var sea_query := Callable()
const SEA_DIRECTIONS := 64
var _sea_mask := Image.create(SEA_DIRECTIONS, 1, false, Image.FORMAT_R8)
var _sea_tex: ImageTexture
var _sea_at := Vector2.INF
## How cloudy today is (0 clear .. 1 overcast); rolled every dawn.
var cloudiness := 0.5
## Terraria's rain (Main.UpdateTime, StartRain, ChangeRain, StopRain): while
## no one has 120 max life it never rains; then each tick 1 in 5.75 days'
## ticks it starts (1 in 4.25 days' more on an overcast day: Terraria's
## cloudBGActive, here cloudiness at 0.9 or more), lasting 8 to 24 hours
## and often more (game hours, 3600 ticks), its strength (max_raining: 0.05
## to 0.9, heavier the cloudier: Terraria's numClouds is cloudiness x 200)
## changing 1 tick in 2 hours'. cloud_alpha eases toward it 0.0005 a tick:
## that's how wet it is (Main.cloudAlpha: it darkens the daylight by
## 0.9 x itself, Terraria's SetBackColor). A storm: cloud_alpha 0.5 and
## wind 0.4 or more (0.4 and 0.34 to end one: UpdateWindyDayState), with
## lightning; a windy day: no rain, 3 to 12 hours into the day, wind 0.4.
var raining := false
var rain_time := 0
var max_raining := 0.0
var cloud_alpha := 0.0
var storm := false
var windy_day := false
## Lightning: the flash (0..1) and how fast it brightens, its thunder's delay
## (ticks) and how far off it was.
var lightning := 0.0
var _lightning_speed := 0.0
var _thunder_delay := 0
var _thunder_distance := 0
## Terraria's Blood Moon (Main.bloodMoon): rolled at dusk by the game, over
## at dawn.
var blood_moon := false
const RAIN_DAY := 86400
const RAIN_HOUR := 3600
const MIN_WIND := 0.34
const MAX_WIND_STORM := 0.4
const MIN_RAIN := 0.4
const MAX_RAIN := 0.5
signal thunder(distance: int)

var env: Environment
var _sky_mat := ShaderMaterial.new()
var _sun: MeshInstance3D
var _moon: MeshInstance3D
## Per ring: {meshes: {image id: MeshInstance3D}, shown: image id}.
var _rings: Array = []
var _clouds: Array = []  # {node, angle, elevation, speed, scale, active}
var _seconds := 0.0
## The time of day's light, before rain and the Blood Moon change it.
var _time_light := 1.0


func _ready() -> void:
	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	_sky_mat.shader = preload("res://shaders/sky.gdshader")
	var sky := Sky.new()
	sky.sky_material = _sky_mat
	env.sky = sky
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	# The shaders light themselves: no ambient or sky reflections (the
	# global illumination, when it's on, is all the engine adds).
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.BLACK
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 120.0
	env.fog_depth_end = 220.0
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	_sun = _make_body(Assets.texture("Images/Sun"))
	_moon = _make_body(Assets.texture("Images/Moon_0"), 8)
	for i in 3:
		_rings.append({"meshes": {}, "shown": -1, "fades": {}})
	_sea_mask.fill(Color.WHITE)
	_sea_tex = ImageTexture.create_from_image(_sea_mask)
	for i in CLOUD_SLOTS:
		_clouds.append(_make_cloud(i))
	cloudiness = randf_range(0.25, 0.9)


## Sun/moon quad. Depth-tested so terrain (and the backdrop rings) hide it; it
## sits beyond everything else and ignores fog. `frames` > 1 selects one frame
## of a vertical strip (moon phases).
func _make_body(tex: Texture2D, frames := 1) -> MeshInstance3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.albedo_texture = tex
	mat.disable_fog = true
	mat.disable_receive_shadows = true
	mat.uv1_scale = Vector3(1.0, 1.0 / frames, 1.0)
	var quad := QuadMesh.new()
	quad.size = Vector2(tex.get_width(), tex.get_height() / frames)
	var mi := MeshInstance3D.new()
	mi.mesh = quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## A cloud: a random Terraria cloud on a far-off plane somewhere around the
## sky. (Not a billboard: those turn as you look around, which is distracting
## on something this big. The plane faces the middle of the sky, and as the
## sky moves with you it only turns as the cloud drifts round.)
func _make_cloud(i: int) -> Dictionary:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	mat.alpha_scissor_threshold = 0.4
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.disable_fog = true
	mat.disable_receive_shadows = true
	var mi := MeshInstance3D.new()
	mi.mesh = QuadMesh.new()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var c := {"node": mi, "angle": randf() * TAU, "slot": i}
	_pick_cloud(c)
	return c


## Gives a cloud slot a new look, height and speed (Terraria's rare shaped
## clouds now and then).
func _pick_cloud(c: Dictionary) -> void:
	var n: int = CLOUDS[randi() % CLOUDS.size()]
	if randf() < 0.03:
		n = RARE_CLOUDS + randi() % 20
	var tex := Assets.texture("Images/Cloud_%d" % n)
	var mat: StandardMaterial3D = c.node.material_override
	mat.albedo_texture = tex
	c["size"] = Vector2(tex.get_width(), tex.get_height())
	c["scale"] = randf_range(0.5, 0.95)
	c["elevation"] = randf_range(0.1, 0.42)  # radians above the horizon
	c["speed"] = randf_range(0.6, 1.4)
	c["active"] = float(c.slot) / CLOUD_SLOTS < cloudiness


## Direction from the viewer to the sun (or moon at night): east to west across the sky.
func sun_direction() -> Vector3:
	var angle := lerpf(PI * 0.92, PI * 0.08, phase())
	return Vector3(cos(angle), sin(angle), 0.25).normalized()


## 0..1 progress through the current day or night.
func phase() -> float:
	return time / (DAY_LENGTH if is_day else NIGHT_LENGTH)


## The time of day in hours (0 midnight, 4.5 dawn, 19.5 dusk).
func hours() -> float:
	return fmod((time + (4.5 * 3600.0 if is_day else 19.5 * 3600.0)) / 3600.0, 24.0)


## The sky at an hour of the day (SKY_KEYS, eased from key to key):
## {light, tint, top, horizon, glow, glow_color, stars, halo, halo_color}.
static func sky_at(h: float) -> Dictionary:
	h = fposmod(h, 24.0)
	var i := 0
	while i < SKY_KEYS.size() - 2 and SKY_KEYS[i + 1][0] <= h:
		i += 1
	var a: Dictionary = SKY_KEYS[i][1]
	var b: Dictionary = SKY_KEYS[i + 1][1]
	var span: float = SKY_KEYS[i + 1][0] - SKY_KEYS[i][0]
	var t := smoothstep(0.0, 1.0, (h - SKY_KEYS[i][0]) / span)
	var out := {}
	for key in a:
		out[key] = lerpf(a[key], b[key], t) if a[key] is float else (a[key] as Color).lerp(b[key], t)
	return out


## Terraria-style clock string ("4:30 AM" at dawn).
## The time, to the minute; `watch` 1 rounds it down to the hour, 2 to the
## half hour (Terraria's Copper / Silver / Gold Watches, Main.DrawInfoAccs).
func clock_text(watch := 3) -> String:
	# One tick is one in-game second; days start at 4:30 AM, nights at 7:30 PM.
	var seconds := time + (4.5 * 3600.0 if is_day else 19.5 * 3600.0)
	var hours := int(seconds / 3600.0) % 24
	var minutes := int(seconds / 60.0) % 60
	if watch == 1:
		minutes = 0
	elif watch == 2:
		minutes = 0 if minutes < 30 else 30
	var suffix := "AM" if hours < 12 else "PM"
	var h12 := hours % 12
	return "%d:%02d %s" % [12 if h12 == 0 else h12, minutes, suffix]


## Terraria's ResetWindCounter.
func _reset_wind_counter(extreme: bool) -> void:
	_wind_counter = randi_range(900, 2700)
	if extreme:
		_extreme_wind_counter = randi_range(10, 30)


## One tick of Terraria's wind.
func wind_tick() -> void:
	var rate := 0.0003 + absf(wind_target - wind) * 0.0015
	wind = minf(wind + rate, wind_target) if wind < wind_target else maxf(wind - rate, wind_target)
	_wind_counter -= 1
	if _wind_counter > 0:
		return
	var strong := strongest_life >= 120
	var sign := -1.0 if wind_target < 0.0 else 1.0
	if randi() % 4 == 0:
		wind_target += randi_range(-25, 25) * 0.001
	elif randi() % 2 == 0:
		wind_target += randi_range(-50, 50) * 0.001
	else:
		wind_target += randi_range(-100, 100) * 0.001
	if not strong and absf(wind_target) > 0.35:
		wind_target = 0.35 * signf(wind_target)
	_extreme_wind_counter -= 1
	if _extreme_wind_counter <= 0:
		_reset_wind_counter(true)
		if randi() % 30 < 13:
			if randi() % 2 == 0:
				wind_target = 0.0
				_wind_counter = randi_range(7200, 28800)
			else:
				wind_target = randi_range(-200, 200) * 0.001
		elif randi() % 20 < 13:
			wind_target = randi_range(-400, 400) * 0.001
		else:
			wind_target = randi_range(-850, 850) * 0.001
		if not strong and absf(wind_target) > 0.35:
			wind_target = 0.35 * signf(wind_target)
		if absf(wind_target) > 0.3:
			_extreme_wind_counter += randi_range(5, 10)
		if absf(wind_target) > 0.5:
			_extreme_wind_counter += randi_range(10, 20)
		if absf(wind_target) > 0.7:
			_extreme_wind_counter += randi_range(15, 30)
	else:
		_reset_wind_counter(false)
	# Two times in three it keeps blowing the way it was.
	if randi() % 3 != 0 and ((sign < 0.0 and wind_target > 0.0) or (sign > 0.0 and wind_target < 0.0)):
		wind_target = -wind_target
	wind_target = clampf(wind_target, -MAX_WIND, MAX_WIND)


func _process(delta: float) -> void:
	_wind_acc += delta * TICKS_PER_SECOND
	var wind_steps := 0
	while _wind_acc >= 1.0 and wind_steps < 10:
		_wind_acc -= 1.0
		wind_steps += 1
		wind_tick()
		rain_tick()
	time += delta * TICKS_PER_SECOND
	_seconds += delta
	if is_day and time >= DAY_LENGTH:
		time -= DAY_LENGTH
		is_day = false
		dusk.emit()
	elif not is_day and time >= NIGHT_LENGTH:
		time -= NIGHT_LENGTH
		is_day = true
		blood_moon = false
		moon_phase = (moon_phase + 1) % 8
		cloudiness = randf_range(0.15, 1.0)
		for c in _clouds:
			c.active = float(c.slot) / CLOUD_SLOTS < cloudiness
		dawn.emit()
	_update_visuals(delta)


## One tick of Terraria's rain and its storms (Main.UpdateTime's rain,
## UpdateWindyDayState, UpdateWeather's lightning).
func rain_tick() -> void:
	if raining:
		rain_time -= 1
		if rain_time <= 0:
			stop_rain()
		elif randi() % (RAIN_HOUR * 2) == 0:
			change_rain()
	elif strongest_life >= 120:
		if randi() % int(RAIN_DAY * 5.75) == 0:
			start_rain()
		elif cloudiness >= 0.9 and randi() % int(RAIN_DAY * 4.25) == 0:
			start_rain()
	var target := max_raining if raining else 0.0
	cloud_alpha = move_toward(cloud_alpha, target, 0.0005)
	if cloud_alpha == 0.0:
		storm = false
		if not is_day or time < 10800.0 or time > 43200.0 or absf(wind_target) < MIN_WIND:
			windy_day = false
		elif absf(wind_target) >= MAX_WIND_STORM:
			windy_day = true
	else:
		windy_day = false
		if cloud_alpha < MIN_RAIN or absf(wind_target) < MIN_WIND:
			storm = false
		elif cloud_alpha >= MAX_RAIN and absf(wind_target) >= MAX_WIND_STORM:
			storm = true
	_lightning_tick()


## StartRain: 8 to 24 hours, often longer, times up to 1.5.
func start_rain() -> void:
	var hour := RAIN_DAY / 24
	var t := randi_range(hour * 8, RAIN_DAY - 1)
	for step in [[3, 1], [4, 2], [5, 2], [6, 3], [7, 4], [8, 5]]:
		if randi() % int(step[0]) == 0:
			t += randi_range(0, hour * int(step[1]) - 1)
	var k := 1.0
	for step in [[2, 0.05], [3, 0.1], [4, 0.15], [5, 0.2]]:
		if randi() % int(step[0]) == 0:
			k += float(step[1])
	rain_time = int(t * k)
	change_rain()
	raining = true


## ChangeRain: how hard it rains, heavier under more clouds.
func change_rain() -> void:
	var clouds := cloudiness * 200.0
	if cloudiness >= 0.9 or clouds > 150.0:
		max_raining = (randi_range(20, 90) if randi() % 3 == 0 else randi_range(40, 90)) * 0.01
	elif clouds > 100.0:
		max_raining = (randi_range(10, 70) if randi() % 3 == 0 else randi_range(20, 60)) * 0.01
	else:
		max_raining = (randi_range(5, 40) if randi() % 3 == 0 else randi_range(5, 30)) * 0.01


func stop_rain() -> void:
	rain_time = 0
	raining = false
	max_raining = 0.0


## Lightning in a storm (UpdateWeather): now and then, more often the harder
## it rains and blows; the flash brightens over a few ticks and fades, and
## its thunder follows after a delay for its distance.
func _lightning_tick() -> void:
	if _thunder_delay > 0:
		_thunder_delay -= 1
		if _thunder_delay == 0:
			thunder.emit(_thunder_distance)
	if _lightning_speed > 0.0:
		lightning = minf(1.0, lightning + _lightning_speed)
		if lightning >= 1.0:
			_lightning_speed = 0.0
		return
	if lightning > 0.0:
		lightning = maxf(0.0, lightning - 0.02)
		return
	if _thunder_delay > 0 or depth_factor > 0.5 or not storm:
		return
	var lo := 600.0
	var hi := 1600.0
	for step in [[0.8, 0.6, 0.8], [0.7, 0.7, 0.9], [0.6, 0.8, 0.95]]:
		if max_raining > step[0]:
			lo *= step[1]
			hi *= step[2]
	for step in [[0.7, 0.6, 0.8], [0.6, 0.7, 0.9], [0.5, 0.8, 0.95]]:
		if absf(wind_target) > step[0]:
			lo *= step[1]
			hi *= step[2]
	var n := randf_range(lo, hi) * ((1.0 - max_raining) + 1.0) / 2.0 * ((1.0 - wind_target) + 1.0) / 2.0
	if randi() % maxi(1, int(n)) == 0:
		new_lightning()


## Main.NewLightning: a flash 0.05 to 0.1 a tick brighter, its thunder
## 1 to 15 ticks... later for each of up to 4 (its distance) away.
func new_lightning() -> void:
	if _thunder_delay > 0:
		return
	_lightning_speed = randf_range(0.05, 0.1)
	_thunder_distance = randi_range(1, 4)
	_thunder_delay = _thunder_distance * 15 + randi_range(0, 14)


## How far away the distant things are: the backdrop rings just beyond the
## view distance, the clouds beyond them and the sun and moon beyond those.
func ring_radius(i: int) -> float:
	return env.fog_depth_end + 30.0 + i * 25.0


func cloud_distance() -> float:
	return ring_radius(2) + 50.0


func body_distance() -> float:
	return cloud_distance() + 60.0


func _update_visuals(delta: float) -> void:
	var k := sky_at(hours())
	sky_light = k.light
	sky_tint = k.tint
	_time_light = sky_light
	# The Blood Moon: a redder, brighter night (Terraria's SetBackColor:
	# its night light 75, 15, 15 at midnight where a plain night's is 5).
	if blood_moon and not is_day:
		sky_tint = Color(1.0, 0.35, 0.35)
		sky_light = maxf(sky_light, 0.3)
	# Rain darkens the daylight (0.9 x how wet it is), and lightning
	# flashes it back up.
	sky_light *= 1.0 - cloud_alpha * 0.9 * (1.0 - depth_factor)
	if lightning > 0.0:
		sky_light = lerpf(sky_light, 1.0, lightning * 0.8)
	var top: Color = k.top
	var horizon: Color = k.horizon
	var glow: float = k.glow  # sunrise / sunset glow
	var stars: float = k.stars
	# Space: the sky darkens toward black and the stars come out, even by day.
	if space_factor > 0.0:
		top = top.lerp(Color(0.01, 0.01, 0.04), space_factor * 0.85)
		horizon = horizon.lerp(top, space_factor * 0.5)
		stars = maxf(stars, space_factor)

	if blood_moon and not is_day:
		top = top.lerp(Color(0.25, 0.02, 0.02), 0.7)
		horizon = horizon.lerp(Color(0.45, 0.06, 0.05), 0.7)
	# Rain clouds: a greyer, darker sky.
	if cloud_alpha > 0.0:
		var grey := Color(0.32, 0.34, 0.38) * clampf(sky_light + 0.15, 0.1, 1.0)
		top = top.lerp(grey, cloud_alpha * 0.8)
		horizon = horizon.lerp(grey.lightened(0.1), cloud_alpha * 0.8)
	if evil_amount > 0.0:
		var ec := evil_color.darkened(1.0 - sky_light)
		top = top.lerp(ec, evil_amount * 0.7)
		horizon = horizon.lerp(ec.lightened(0.15), evil_amount * 0.6)
	var under := depth_factor
	_sky_mat.set_shader_parameter("top_color", top)
	_sky_mat.set_shader_parameter("horizon_color", horizon)
	_sky_mat.set_shader_parameter("below_color", horizon.darkened(0.45))
	_sky_mat.set_shader_parameter("sun_dir", sun_direction())
	_sky_mat.set_shader_parameter("glow", glow * (1.0 - evil_amount * 0.5))
	_sky_mat.set_shader_parameter("glow_color", k.glow_color)
	_sky_mat.set_shader_parameter("halo", k.halo)
	_sky_mat.set_shader_parameter("halo_color", k.halo_color)
	_sky_mat.set_shader_parameter("stars", stars)
	_sky_mat.set_shader_parameter("time_s", _seconds)
	_sky_mat.set_shader_parameter("under", under)
	env.fog_light_color = horizon.lerp(Color.BLACK, under)

	if camera:
		var cam := camera.global_position
		var dir := sun_direction()
		var shown := under < 0.99
		var far := body_distance()
		_sun.visible = is_day and shown
		_moon.visible = not is_day and shown
		_sun.global_position = cam + dir * far
		_moon.global_position = cam + dir * far
		# Same size in the sky however far away they are.
		_sun.scale = Vector3.ONE * far / 400.0 * 0.6
		_moon.scale = _sun.scale
		(_moon.material_override as StandardMaterial3D).uv1_offset = Vector3(0.0, moon_phase / 8.0, 0.0)
		# The Blood Moon is drawn red (Terraria's moon colour then).
		(_moon.material_override as StandardMaterial3D).albedo_color = Color(1.0, 0.25, 0.22) if blood_moon else Color.WHITE
		# Rain brings the clouds in (Terraria: at least 200 x cloudAlpha).
		var cover := maxf(cloudiness, cloud_alpha)
		for c in _clouds:
			c.active = float(c.slot) / CLOUD_SLOTS < cover
		_update_backdrops(cam, horizon, under, delta)
		_update_clouds(cam, top, horizon, under, delta)


## The biome's background layers, as rings around the viewer, lit by the sky
## and hazed toward the horizon colour; a new biome's layers dissolve in.
func _update_backdrops(cam: Vector3, horizon: Color, under: float, delta: float) -> void:
	var layers: Array = BACKDROPS.get(biome, BACKDROPS[""])
	_update_sea_mask(cam)
	var bright := sky_light * (1.0 - under)
	var tint := Color(bright * sky_tint.r, bright * sky_tint.g, bright * sky_tint.b)
	for i in _rings.size():
		var ring: Dictionary = _rings[i]
		var want: int = layers[i] if i < layers.size() else -1
		if want >= 0 and not ring.meshes.has(want):
			ring.meshes[want] = _make_ring(want)
			ring.fades[want] = 0.0 if ring.shown >= 0 else 1.0
		ring.shown = want
		var r := ring_radius(2 - i)  # the first layer is the farthest
		for id in ring.meshes.keys():
			var fade: float = move_toward(ring.fades[id], 1.0 if id == want else 0.0, delta * 0.8)
			ring.fades[id] = fade
			var mi: MeshInstance3D = ring.meshes[id]
			if fade <= 0.0 and id != want:
				mi.queue_free()
				ring.meshes.erase(id)
				ring.fades.erase(id)
				continue
			var mat: ShaderMaterial = mi.material_override
			mat.set_shader_parameter("fade", fade)
			mat.set_shader_parameter("sea_mask", _sea_tex)
			mat.set_shader_parameter("tint", tint)
			mat.set_shader_parameter("haze_color", horizon.lerp(Color.BLACK, under))
			mat.set_shader_parameter("haze", HAZE[i])
			mi.visible = under < 0.99
			# Scaled to the ring's radius (built at 1); the art's bottom a bit
			# below the camera, the near layers lower than the far ones.
			mi.scale = Vector3(r, r, r)
			mi.global_position = Vector3(cam.x, cam.y - r * RING_DROP[i], cam.z)


## Recomputes the sea mask when you've moved: 1 in directions where the land
## (or fog) fills the horizon, falling to 0 where the open sea shows within
## the view distance; softened between neighbouring directions.
func _update_sea_mask(cam: Vector3) -> void:
	if not sea_query.is_valid():
		return
	var at := Vector2(cam.x, cam.z)
	if at.distance_to(_sea_at) < 6.0:
		return
	_sea_at = at
	var reach := env.fog_depth_end
	var dists: PackedFloat32Array = sea_query.call(at, SEA_DIRECTIONS, reach)
	var raw := PackedFloat32Array()
	raw.resize(SEA_DIRECTIONS)
	for i in SEA_DIRECTIONS:
		raw[i] = clampf((dists[i] - reach * 0.75) / (reach * 0.25), 0.0, 1.0)
	for i in SEA_DIRECTIONS:
		var m := minf(raw[i], (raw[(i + SEA_DIRECTIONS - 1) % SEA_DIRECTIONS] + raw[i] * 2.0 + raw[(i + 1) % SEA_DIRECTIONS]) * 0.25)
		_sea_mask.set_pixel(i, 0, Color(m, m, m))
	_sea_tex.update(_sea_mask)


## How much backdrop shows toward world direction `angle` (radians from +x
## toward +z): the sea mask (tests).
func sea_mask_at(angle: float) -> float:
	var i := posmod(roundi(angle / TAU * SEA_DIRECTIONS), SEA_DIRECTIONS)
	return _sea_mask.get_pixel(i, 0).r


## One background image wrapped around a ring of radius 1 (scaled to its real
## radius), repeated so each copy keeps the art's proportions.
func _make_ring(image: int) -> MeshInstance3D:
	var tex := Assets.texture("Images/Background_%d" % image)
	var repeats := 6.0
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.0
	mesh.bottom_radius = 1.0
	mesh.height = TAU / repeats * float(tex.get_height()) / tex.get_width()
	mesh.radial_segments = 64
	mesh.cap_top = false
	mesh.cap_bottom = false
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/backdrop.gdshader")
	mat.set_shader_parameter("art", tex)
	mat.set_shader_parameter("fade", 1.0)
	var mi := MeshInstance3D.new()
	mi.mesh = _repeat_uv(mesh, repeats)
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	return mi


## The mesh with its u coordinate repeated `n` times (and mirrored, since the
## inside of the cylinder is what's seen).
static func _repeat_uv(mesh: Mesh, n: float) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	for i in uv.size():
		uv[i] = Vector2(-uv[i].x * n, uv[i].y)
	arrays[Mesh.ARRAY_TEX_UV] = uv
	var out := ArrayMesh.new()
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return out


## Clouds drift slowly across the sky; their colour follows the time of day
## (white by day, warm at sunrise and sunset, dark blue at night).
func _update_clouds(cam: Vector3, top: Color, horizon: Color, under: float, delta: float) -> void:
	var dist := cloud_distance()
	# White by day, warm at sunrise and sunset; at night dark shapes, just
	# lighter than the sky behind them. All by the light, so they fade too.
	var dusk_col := Color(1.0, 0.72, 0.6)
	var col: Color
	var light := _time_light
	if light >= 0.35:
		col = dusk_col.lerp(Color.WHITE, clampf((light - 0.35) / 0.4, 0.0, 1.0))
	else:
		col = NIGHT_CLOUD.lerp(dusk_col, clampf((light - 0.22) / 0.13, 0.0, 1.0))
	col = col.lerp(top.lightened(0.3 * clampf((light - 0.22) / 0.13, 0.0, 1.0)), 0.15)
	if evil_amount > 0.0:
		col = col.lerp(evil_color.lightened(0.2), evil_amount * 0.5)
	# Rain clouds are grey and dark; a Blood Moon's are red.
	if cloud_alpha > 0.0:
		col = col.lerp(Color(0.42, 0.44, 0.48) * clampf(light + 0.2, 0.3, 1.0), cloud_alpha)
	if blood_moon and not is_day:
		col = col * Color(1.0, 0.4, 0.4)
	for c in _clouds:
		c.angle = fmod(c.angle + delta * 0.004 * c.speed, TAU)
		var mi: MeshInstance3D = c.node
		mi.visible = c.active and under < 0.99
		if not mi.visible:
			continue
		var e: float = c.elevation
		var dir := Vector3(cos(c.angle) * cos(e), sin(e), sin(c.angle) * cos(e))
		(mi.mesh as QuadMesh).size = c.size
		# Upright, its face (the quad's +z) toward the middle of the sky.
		var z := -dir
		var x := Vector3.UP.cross(z).normalized()
		mi.global_transform = Transform3D(Basis(x, z.cross(x), z).scaled(Vector3.ONE * c.scale * dist / 400.0), cam + dir * dist)
		(mi.material_override as StandardMaterial3D).albedo_color = Color(col.r, col.g, col.b) * (1.0 - under)


func save_state() -> Dictionary:
	return {"time": time, "is_day": is_day, "moon_phase": moon_phase, "cloudiness": cloudiness,
			"raining": raining, "rain_time": rain_time, "max_raining": max_raining, "blood_moon": blood_moon}


func load_state(d: Dictionary) -> void:
	time = d.get("time", 13500.0)
	is_day = d.get("is_day", true)
	moon_phase = int(d.get("moon_phase", 0))
	cloudiness = float(d.get("cloudiness", cloudiness))
	raining = bool(d.get("raining", false))
	rain_time = int(d.get("rain_time", 0))
	max_raining = float(d.get("max_raining", 0.0))
	cloud_alpha = max_raining if raining else 0.0
	blood_moon = bool(d.get("blood_moon", false))
	for c in _clouds:
		c.active = float(c.slot) / CLOUD_SLOTS < cloudiness
