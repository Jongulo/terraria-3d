class_name DustParticles
extends MultiMeshInstance3D
## Terraria's dust: the specks a block throws off when it's hit or broken
## (WorldGen.KillTile_MakeTileDust picks each block's dust type, read into
## assets/terraria/tile_dust.json by tools/terraria_dust.py), drawn from
## Images/Dust and moving as Dust.NewDust / Dust.UpdateDust move them, in
## Terraria's pixels and ticks (a block is 24 px):
##   born somewhere in the block, flying off at up to 2 px/tick each way, scale
##   1 +-0.2; then each tick it moves, falls (0.1 px/tick² unless it has no
##   gravity), slows (x0.97 across, x0.99 up and down) and shrinks by 0.01,
##   gone below 0.1. Fire dusts (torches) drift up slowly and glow; the rest
##   take the light where they are.

const MAX := 2000
const PX := 1.0 / 24.0  # a Terraria pixel, in blocks
## Dust that rises like a torch's flame (Dust.NewDust's list): slow, up,
## smaller, and drawn at full brightness.
const FLAME := [6, 29, 59, 60, 61, 62, 63, 64, 65, 75, 135, 158, 169, 228, 242, 269, 279, 293, 294, 295,
		296, 297, 298, 302, 307, 310]

var _pos := PackedVector3Array()
var _vel := PackedVector3Array()  # px / tick, y up
var _scale := PackedFloat32Array()
var _type := PackedInt32Array()
var _row := PackedInt32Array()
var _flags := PackedInt32Array()  # 1: no gravity, 2: glows
var _tint := PackedColorArray()
var _accum := 0.0


func _ready() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2(8.0 * PX, 8.0 * PX)
	mm.mesh = quad
	mm.instance_count = MAX
	mm.visible_instance_count = 0
	multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/dust.gdshader")
	var tex := Assets.texture("Images/Dust")
	mat.set_shader_parameter("atlas", tex)
	mat.set_shader_parameter("atlas_size", Vector2(tex.get_width(), tex.get_height()))
	material_override = mat
	# Always drawn (the instances move every frame; the box would be stale).
	custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func count() -> int:
	return _pos.size()


## One dust of `type` at `at` (blocks), flying off at NewDust's random velocity
## plus `speed` (px/tick), its scale times `scale`.
func spawn(type: int, at: Vector3, speed := Vector3.ZERO, scale := 1.0, tint := Color.WHITE) -> void:
	if type < 0 or _pos.size() >= MAX:
		return
	var r := func() -> float: return randi_range(-20, 20) * 0.1
	var v := Vector3(r.call(), r.call(), r.call()) + speed
	var s := (1.0 + randi_range(-20, 20) * 0.01) * scale
	var flags := 0
	if type in FLAME:
		# Terraria: velocity.Y = Next(-10, 6) * 0.1 (mostly up), X * 0.3, scale * 0.7.
		v = Vector3(v.x * 0.3, -randi_range(-10, 5) * 0.1, v.z * 0.3)
		s *= 0.7
		flags |= 2
	_pos.append(at)
	_vel.append(v)
	_scale.append(s)
	_type.append(type)
	_row.append(randi() % 3)
	_flags.append(flags)
	_tint.append(tint)


## The dust a block makes when hit (`kill` false: 3 of them) or broken (10),
## Terraria's for that tile; blocks Terraria gives none to make none.
func tile_dust(p: Vector3i, block_id: int, kill: bool) -> void:
	var b := Data.block(block_id)
	var d: Dictionary = Data.tile_dust.get(b.get("name", ""), {})
	if d.is_empty():
		return
	var kinds: Array = d.get("dust", [])
	if kinds.is_empty():
		return
	var n := int(d.get("kill" if kill else "hit", 10 if kill else 3))
	for i in n:
		# Terraria: Position + Next(Width - 4) + 4 across the tile.
		var at := Vector3(p) + Vector3(randf_range(0.2, 0.95), randf_range(0.05, 0.8), randf_range(0.2, 0.95))
		spawn(_pick(kinds), at)


## An enemy's dust (Terraria's NPC.HitEffect): `kinds` [[DustID, n], ...]
## times `k`, all over its body, flung away from you (`dir`) and up a little,
## tinted (slimes bleed their own colour).
func npc_dust(npc: Node3D, kinds: Array, k: float, dir: Vector3, tint := Color.WHITE) -> void:
	var c: Vector3 = npc.center()
	var h: Vector3 = npc.half
	var push := Vector3(dir.x, 0, dir.z).normalized()
	for kd in kinds:
		var n := mini(100, int(round(float(kd[1]) * k)))
		for i in n:
			var at := c + Vector3(randf_range(-h.x, h.x), randf_range(-h.y, h.y) * 0.5, randf_range(-h.z, h.z))
			spawn(int(kd[0]), at, push + Vector3(0, 1, 0), 1.0, tint)


static func _pick(kinds: Array) -> int:
	var r := randf()
	for k in kinds:
		r -= float(k[1])
		if r <= 0.0:
			return int(k[0])
	return int(kinds[0][0])


func _physics_process(delta: float) -> void:
	# Terraria's dust updates once a tick (60 a second).
	_accum += delta
	while _accum >= 1.0 / 60.0:
		_accum -= 1.0 / 60.0
		_tick()
	_draw()


func _tick() -> void:
	var i := 0
	while i < _pos.size():
		var v := _vel[i]
		_pos[i] += v * PX
		if _flags[i] & 1:
			v *= 0.93
			_scale[i] += 0.0025
		else:
			v.y -= 0.1
		v = Vector3(v.x * 0.97, v.y * 0.99, v.z * 0.97)
		_vel[i] = v
		_scale[i] -= 0.01
		if _scale[i] < 0.1:
			_remove(i)
			continue
		i += 1


func _remove(i: int) -> void:
	var last := _pos.size() - 1
	_pos[i] = _pos[last]
	_vel[i] = _vel[last]
	_scale[i] = _scale[last]
	_type[i] = _type[last]
	_row[i] = _row[last]
	_flags[i] = _flags[last]
	_tint[i] = _tint[last]
	_tint.resize(last)
	_pos.resize(last)
	_vel.resize(last)
	_scale.resize(last)
	_type.resize(last)
	_row.resize(last)
	_flags.resize(last)


func _draw() -> void:
	var game := Game.current
	var mm := multimesh
	mm.visible_instance_count = _pos.size()
	for i in _pos.size():
		var s := _scale[i]
		mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(s, s, s)), _pos[i]))
		var t := _type[i]
		mm.set_instance_custom_data(i, Color((t % 100) * 10, (t / 100) * 30 + _row[i] * 10, 0, 0))
		var c := Color.WHITE
		if not (_flags[i] & 2) and game != null:
			var l := game.world.get_light(_pos[i])
			var sun := game.sky.sky_light * l.a
			c = Color(maxf(l.r, sun * game.sky.sky_tint.r), maxf(l.g, sun * game.sky.sky_tint.g), maxf(l.b, sun * game.sky.sky_tint.b))
		mm.set_instance_color(i, c * _tint[i])
