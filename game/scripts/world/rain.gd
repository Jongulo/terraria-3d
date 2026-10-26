class_name RainFall
extends Node3D
## Terraria's rain round you (Rain.MakeRain, NewRain, Update; Main.DrawRain),
## in its pixels (24 a block) and ticks. While it rains and you're on the
## surface, each tick 25 x (0.25 + how wet it is) drops start a little over
## your head, round you, upwind of where they'll land (wind x 15 x 40 px),
## where nothing roofs them; at most 750 x how wet it is fall at once. Each
## falls at 14 px a tick and blows wind x 18 across (both times its size,
## 0.8 to 1.2), and is gone in a splash of water when it reaches a block or
## water. Its look: the Rain sheet's drops for the water there (Terraria's
## water style: the biome's, red under a Blood Moon). The rain's sound is
## Terraria's RainAmbience, louder the harder it rains; thunder rolls after
## lightning.

const PX := 24.0
const TICK := 1.0 / 60.0
const MAX_RAIN := 750
## How far round you drops start (blocks), and how high over your eyes.
const AREA := 24.0
const SPAWN_HEIGHT := Vector2(12.0, 18.0)
## Terraria's water styles by biome (Main.CalculateWaterStyle): forest 0,
## corruption 2, jungle 3, hallow 4, snow 5, desert 6, Blood Moon 9,
## crimson 10, ocean 13.
const WATER_STYLE := {"corruption": 2, "jungle": 3, "hallow": 4, "snow": 5, "desert": 6, "crimson": 10, "ocean": 13}

## Dust.dustWater: each water style's splash.
const WATER_DUST := {2: 98, 3: 99, 4: 100, 5: 101, 6: 102, 7: 103, 8: 104, 9: 105, 10: 123, 12: 288}

var game
## Each drop: [position, velocity (blocks/s), drop type].
var _drops: Array = []
var _acc := 0.0
var _mm := MultiMesh.new()
var _mi := MultiMeshInstance3D.new()
var _mat := ShaderMaterial.new()


func setup(g) -> void:
	game = g
	_mm.transform_format = MultiMesh.TRANSFORM_3D
	_mm.use_custom_data = true
	_mm.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	quad.center_offset = Vector3(0, -0.5, 0)
	_mm.mesh = quad
	_mm.instance_count = MAX_RAIN
	_mm.visible_instance_count = 0
	_mi.multimesh = _mm
	_mat.shader = preload("res://shaders/rain.gdshader")
	_mat.set_shader_parameter("sheet", Assets.texture("Images/Rain"))
	_mi.material_override = _mat
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mi.extra_cull_margin = 16384.0
	add_child(_mi)
	game.sky.thunder.connect(_on_thunder)


## Whether it's raining where you are (Terraria's ZoneRain: raining, and you
## on the surface).
func raining_here() -> bool:
	var sky: SkySystem = game.sky
	return sky.raining and sky.depth_factor < 0.5 and game.player.global_position.y > game.surface_level - 20.0


func _process(delta: float) -> void:
	if game == null or game.state != Game.State.PLAYING:
		return
	var here := raining_here()
	_acc = minf(_acc + delta, 0.25)
	while _acc >= TICK:
		_acc -= TICK
		_tick(here)
	_draw()
	Audio.set_ambient("RainAmbience" if here and game.sky.cloud_alpha > 0.0 else "", game.sky.cloud_alpha)


func _tick(here: bool) -> void:
	var sky: SkySystem = game.sky
	var cam: Vector3 = game.player.view().global_position
	if here:
		var cap := int(MAX_RAIN * sky.cloud_alpha)
		var n := 25.0 * (0.25 + sky.cloud_alpha)
		var style: int = 9 if sky.blood_moon and not sky.is_day else int(WATER_STYLE.get(game.biome, 0))
		while n > 0.0 and _drops.size() < cap:
			if n < 1.0 and randf() >= n:
				break
			n -= 1.0
			var a := randf() * TAU
			var r := sqrt(randf()) * AREA
			var p := cam + Vector3(cos(a) * r, randf_range(SPAWN_HEIGHT.x, SPAWN_HEIGHT.y), sin(a) * r)
			# Upwind of where it will land, and ahead of you as you run.
			p.x -= sky.wind * 15.0 * 40.0 / PX
			p += game.player.velocity * 40.0 / 60.0
			var x := floori(p.x)
			var z := floori(p.z)
			if game.world.surface_y(x, z) >= floori(p.y) or game.world.is_solid(Vector3i(p.floor())):
				continue
			var k := randf_range(0.8, 1.2)
			var v := Vector3(sky.wind * 18.0, -14.0, 0.0) * k * 60.0 / PX
			_drops.append([p, v, style * 3 + randi() % 3, k])
	var keep := []
	for d in _drops:
		var p: Vector3 = d[0] + d[1] * TICK
		var cell := Vector3i(p.floor())
		if p.y < cam.y - 30.0:
			continue
		if game.world.is_solid(cell) or game.world.get_liquid(cell).y > 0:
			# A splash (Terraria: its water's dust, a little back up).
			game.dust.spawn(WATER_DUST.get(int(d[2]) / 3, 33), p - d[1] * TICK, -d[1] / 2.5 * 0.025 + Vector3(0, 2.0, 0), 0.6)
			continue
		d[0] = p
		keep.append(d)
	_drops = keep


func _draw() -> void:
	_mat.set_shader_parameter("sky_light", game.sky.sky_light)
	_mat.set_shader_parameter("sky_color", game.sky.sky_tint)
	var n := mini(_drops.size(), MAX_RAIN)
	_mm.visible_instance_count = n
	for i in n:
		var d: Array = _drops[i]
		var k: float = d[3]
		var along: Vector3 = -(d[1] as Vector3).normalized() * 40.0 / PX * k
		var basis := Basis(Vector3.RIGHT * 2.0 / PX * k, along, Vector3.BACK)
		_mm.set_instance_transform(i, Transform3D(basis, d[0]))
		_mm.set_instance_custom_data(i, Color(int(d[2]) * 4.0, 0.0, 0.0, 1.0))
		_mm.set_instance_color(i, game.world.get_light(d[0]))


## Thunder after lightning (Terraria's thunder sound, quieter further off).
func _on_thunder(distance: int) -> void:
	if game.sky.depth_factor < 0.5:
		Audio.play("Thunder_*", 1.0 - (distance - 1) * 0.2)
