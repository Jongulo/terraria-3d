class_name SlimeSky
extends Node3D
## Slime Rain's slimes falling far off in the sky (Terraria's SlimeSky): the
## Sky_Slime sheets (1 or 2 mostly, 3 one time in 30, 4 one time in 60), each
## falling 5 to 8 px a tick behind the clouds, the further (depth 1.6 to
## 3.35) the slower and smaller (drawn at 2 / depth), flapping 6 ticks a
## frame, tinted by the sky and dimmer the further off. They come when it
## starts and fall till they're gone when it stops. A px is 1/400 of a
## radian here (as the clouds are drawn).

const COUNT := 80
const SHEETS := 4

var active := false
## Each: {angle, elevation, speed (px/tick), depth, sheet, frame, on}.
var _slimes: Array = []
var _batches: Array = []
var _sizes: Array = []
var _acc := 0.0


func _ready() -> void:
	for i in SHEETS:
		var tex := Assets.texture("Images/Misc/Sky_Slime_%d" % (i + 1))
		_sizes.append(Vector2(tex.get_width(), tex.get_height() / 4.0))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_custom_data = true
		mm.use_colors = true
		mm.mesh = QuadMesh.new()
		mm.instance_count = COUNT
		mm.visible_instance_count = 0
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		var m := ShaderMaterial.new()
		m.shader = preload("res://shaders/sky_slime.gdshader")
		m.set_shader_parameter("sheet", tex)
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 16384.0
		add_child(mi)
		_batches.append(mi)


## Starts them falling all over the sky (SlimeSky.GenerateSlimes).
func start() -> void:
	active = true
	_slimes.clear()
	for i in COUNT:
		var s := {"angle": randf() * TAU, "elevation": randf_range(0.0, 1.4), "on": true}
		_pick(s, i)
		_slimes.append(s)


## No more come; those falling fall on out of sight.
func stop() -> void:
	active = false


func _pick(s: Dictionary, i: int) -> void:
	s.depth = float(i) / COUNT * 1.75 + 1.6
	s.sheet = randi() % 2
	s.speed = 5.0 + 3.0 * randf()
	if randi() % 60 == 0:
		s.sheet = 3
		s.speed = 6.0 + 3.0 * randf()
		s.depth += 0.5
	elif randi() % 30 == 0:
		s.sheet = 2
		s.speed = 6.0 + 2.0 * randf()
	s.frame = randi() % 24


## `dist`: how far off the sky's things are drawn; `sky_col`: the sky's colour.
func update(delta: float, cam: Vector3, dist: float, sky_col: Color, under: float) -> void:
	_acc = minf(_acc + delta, 0.25)
	while _acc >= 1.0 / 60.0:
		_acc -= 1.0 / 60.0
		for i in _slimes.size():
			var s: Dictionary = _slimes[i]
			if not s.on:
				continue
			s.frame = (s.frame + 1) % 24
			s.elevation -= s.speed / s.depth / 400.0
			if s.elevation < -0.1:
				if active:
					s.angle = randf() * TAU
					s.elevation = 1.4 + randf() * 0.2
					_pick(s, i)
				else:
					s.on = false
	var counts := [0, 0, 0, 0]
	var base := Color(sky_col.r * 0.9 + 0.1, sky_col.g * 0.9 + 0.1, sky_col.b * 0.9 + 0.1) * 0.8 * (1.0 - under)
	for s in _slimes:
		if not s.on or under >= 0.99:
			continue
		var k: int = s.sheet
		var mm: MultiMesh = _batches[k].multimesh
		var n: int = counts[k]
		counts[k] += 1
		var e: float = s.elevation
		var dir := Vector3(cos(s.angle) * cos(e), sin(e), sin(s.angle) * cos(e))
		var z := -dir
		var x := Vector3.UP.cross(z).normalized()
		var size: Vector2 = _sizes[k] * 2.0 / s.depth * dist / 400.0
		mm.set_instance_transform(n, Transform3D(Basis(x * size.x, z.cross(x) * size.y, z), cam + dir * dist))
		mm.set_instance_custom_data(n, Color(float(int(s.frame) / 6), 0, 0, 0))
		var dim := 1.0 if s.depth <= 1.5 else (0.9 if s.depth <= 2.0 else (0.8 if s.depth <= 2.5 else (0.7 if s.depth <= 3.0 else 0.6)))
		mm.set_instance_color(n, base * dim * 0.8)
	for k in SHEETS:
		_batches[k].multimesh.visible_instance_count = counts[k]
