class_name Waterfalls
extends Node3D
## Terraria-style decorative waterfalls: streams that pour from cliff faces,
## cave walls and the Underworld ceiling (worldgen "waterfall" decorations).
## They don't drain any liquid. Each nearby one is a thin animated sheet from
## its spring down to whatever it lands on, with splash particles and a looping
## sound, re-measured as the terrain changes.

const ACTIVE_RANGE := 110.0
const SOUND_RANGE := 28.0
const REFRESH := 0.5
const DIRS := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
## Added to a decoration's style for springs made with a hammer: they only run
## while liquid sits behind their block (natural springs always run).
const NEEDS_LIQUID := 100

var world: VoxelWorld
var focus := Vector3.ZERO
var _falls: Array[Dictionary] = []  # {pos: Vector3i, type: int, dir: int, node: Node3D, key: String}
var _water_mat := ShaderMaterial.new()
var _lava_mat := ShaderMaterial.new()
var _timer := 0.0


func setup(voxel_world: VoxelWorld) -> void:
	world = voxel_world
	var shader := preload("res://shaders/waterfall.gdshader")
	_water_mat.shader = shader
	_water_mat.set_shader_parameter("fall_tex", Assets.texture("Images/Waterfall_0"))
	_lava_mat.shader = shader
	_lava_mat.set_shader_parameter("fall_tex", Assets.texture("Images/Waterfall_1"))
	_lava_mat.set_shader_parameter("lava", true)
	for d in world.get_decorations():
		if d.kind == "waterfall":
			var style := int(d.style)
			# Worlds made before the fix have natural springs on tree trunks
			# (worldgen took a tall tree for a cliff): those go.
			if style < NEEDS_LIQUID and style % 10 < 4 and pours_from_non_ground(d.pos, style % 10):
				world.remove_decorations_at(d.pos)
				continue
			_falls.append({"pos": d.pos, "type": (style % NEEDS_LIQUID) / 10, "dir": style % 10,
					"needs_liquid": style >= NEEDS_LIQUID, "node": null, "key": ""})


## Adds a waterfall at runtime (also stored in the world so it is saved).
## `dir`: 0 +x, 1 -x, 2 +z, 3 -z (direction from the wall into the open), 4 from the ceiling.
func add_fall(pos: Vector3i, liquid_type: int, dir: int, needs_liquid := false) -> void:
	world.add_decoration("waterfall", pos, liquid_type * 10 + dir + (NEEDS_LIQUID if needs_liquid else 0))
	_falls.append({"pos": pos, "type": liquid_type, "dir": dir, "needs_liquid": needs_liquid, "node": null, "key": ""})
	_timer = 0.0


## Direction index for a face normal: 0 +x, 1 -x, 2 +z, 3 -z, 4 down (ceiling), -1 up.
static func dir_index(normal: Vector3i) -> int:
	match normal:
		Vector3i(1, 0, 0): return 0
		Vector3i(-1, 0, 0): return 1
		Vector3i(0, 0, 1): return 2
		Vector3i(0, 0, -1): return 3
		Vector3i(0, -1, 0): return 4
	return -1


## Whether the wall behind a spring at `pos` pouring toward `dir` (0-3) is
## something other than ground: a tree trunk, furniture... (A dug-out wall,
## empty, isn't: the spring runs again if it's built back.)
func pours_from_non_ground(pos: Vector3i, dir: int) -> bool:
	var id := world.get_block(Vector3i(pos - Vector3i(DIRS[dir])))
	var b := Data.block(id)
	return id != 0 and not (b.get("solid", true) and b.get("render", "cube") == "cube")


func has_fall(pos: Vector3i, dir: int) -> bool:
	return _falls.any(func(f): return f.pos == pos and f.dir == dir)


func remove_fall(pos: Vector3i) -> void:
	world.remove_decorations_at(pos)
	for f in _falls.filter(func(f): return f.pos == pos):
		if f.node:
			f.node.queue_free()
		_falls.erase(f)


## Liquid type touching `block` from any side except `skip` (0 if none).
func liquid_behind(block: Vector3i, skip: Vector3i) -> int:
	for d in [Vector3i.LEFT, Vector3i.RIGHT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]:
		var c: Vector3i = block + d
		if c == skip:
			continue
		var l: Vector2i = world.get_liquid(c)
		if l.y > 0:
			return l.x
	return 0


## Opens a hammer-made spring on `block`'s face `normal`. Returns "" on success,
## otherwise a reason to show the player.
func try_make_spring(block: Vector3i, normal: Vector3i) -> String:
	var dir := dir_index(normal)
	if dir < 0:
		return "Waterfalls can't flow upward"
	var mouth := block + normal
	if world.is_solid(mouth) or world.get_liquid(mouth).y > 0:
		return "There's no room for a waterfall there"
	var t := liquid_behind(block, mouth)
	if t == 0:
		return "Hammer a block with water or lava behind it to make a waterfall"
	add_fall(mouth, t, dir, true)
	return ""


## Length of the stream at `pos` (0 if inactive or hidden): for tests and debugging.
func stream_length(pos: Vector3i) -> float:
	for f in _falls:
		if f.pos == pos and f.node != null and f.node.visible:
			var aabb: AABB = (f.node.get_node("Stream") as MeshInstance3D).mesh.get_aabb()
			return aabb.size.y
	return 0.0


func set_sky(light: float, color: Color) -> void:
	_water_mat.set_shader_parameter("sky_light", light)
	_water_mat.set_shader_parameter("sky_color", color)


func active_count() -> int:
	return _falls.filter(func(f): return f.node != null and f.node.visible).size()


func _process(delta: float) -> void:
	if world == null:
		return
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = REFRESH
	for f in _falls:
		var near := Vector2(f.pos.x + 0.5 - focus.x, f.pos.z + 0.5 - focus.z).length() < ACTIVE_RANGE \
				and absf(f.pos.y - focus.y) < ACTIVE_RANGE * 0.7
		if not near:
			if f.node:
				f.node.queue_free()
				f.node = null
				f.key = ""
			continue
		_update_fall(f)


## Where the stream starts and lands; empty if its spring is blocked or gone.
func _measure(f: Dictionary) -> Dictionary:
	var m: Vector3i = f.pos
	if world.is_solid(m):
		return {}
	var source: Vector3i = m + Vector3i.UP if f.dir == 4 else m - Vector3i(DIRS[f.dir])
	if not world.is_solid(source):
		return {}
	if f.get("needs_liquid", false) and liquid_behind(source, m) != f.type:
		return {}
	var y := m.y - 1
	while y > 0 and m.y - y < 160:
		var c := Vector3i(m.x, y, m.z)
		if world.is_solid(c):
			return {"bottom": float(y + 1), "liquid": false}
		var l: Vector2i = world.get_liquid(c)
		if l.y > 0:
			var above: Vector2i = world.get_liquid(c + Vector3i.UP)
			return {"bottom": y + (1.0 if above.y > 0 else l.y / 63.0 * 0.94), "liquid": true}
		y -= 1
	return {"bottom": float(y + 1), "liquid": false}


func _update_fall(f: Dictionary) -> void:
	var info := _measure(f)
	var key := "" if info.is_empty() else "%.2f" % info.bottom
	if key == f.key and f.node != null:
		_update_sound(f)
		return
	f.key = key
	if f.node == null:
		f.node = _make_node(f)
		add_child(f.node)
	f.node.visible = not info.is_empty()
	if info.is_empty():
		return
	var mi: MeshInstance3D = f.node.get_node("Stream")
	mi.mesh = _stream_mesh(f, info.bottom)
	mi.set_instance_shader_parameter("light", world.get_light(Vector3(f.pos) + Vector3(0.5, 0.5, 0.5)))
	var splash: CPUParticles3D = f.node.get_node("Splash")
	splash.position = Vector3(_stream_center(f).x, info.bottom + 0.05, _stream_center(f).z)
	var snd: AudioStreamPlayer3D = f.node.get_node("Sound")
	snd.position = splash.position
	_update_sound(f)


func _update_sound(f: Dictionary) -> void:
	var snd: AudioStreamPlayer3D = f.node.get_node("Sound")
	var near: bool = f.node.visible and (f.node.global_position + snd.position).distance_to(focus) < SOUND_RANGE
	if near and not snd.playing:
		snd.play()
	elif not near and snd.playing:
		snd.stop()


## Horizontal centre of the stream: just out from the wall face, or under the ceiling crack.
func _stream_center(f: Dictionary) -> Vector3:
	var c := Vector3(f.pos) + Vector3(0.5, 0, 0.5)
	if f.dir == 4:
		return c
	return c - DIRS[f.dir] * 0.5 + DIRS[f.dir] * 0.3


func _make_node(f: Dictionary) -> Node3D:
	var root := Node3D.new()
	var mi := MeshInstance3D.new()
	mi.name = "Stream"
	mi.material_override = _lava_mat if f.type == 2 else _water_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	var p := CPUParticles3D.new()
	p.name = "Splash"
	p.amount = 18
	p.lifetime = 0.7
	p.direction = Vector3.UP
	p.spread = 65.0
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.8
	p.gravity = Vector3(0, -9, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.25, 0.02, 0.25)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.08, 0.08)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var light := world.get_light(Vector3(f.pos))
	var l := clampf(maxf(maxf(light.r, light.g), light.a) + 0.15, 0.2, 1.0)
	mat.albedo_color = Color(1.0, 0.6, 0.15) if f.type == 2 else Color(0.75 * l, 0.85 * l, 1.0 * l, 0.8)
	quad.material = mat
	p.mesh = quad
	root.add_child(p)
	var snd := AudioStreamPlayer3D.new()
	snd.name = "Sound"
	snd.stream = _looping(Assets.sound("Liquid_1" if f.type == 2 else "Liquid_0"))
	snd.unit_size = 4.0
	snd.max_distance = SOUND_RANGE
	snd.volume_db = linear_to_db(0.5 * Audio.sfx_volume)
	root.add_child(snd)
	return root


var _loops := {}


## A looping copy of a sound effect.
func _looping(s: AudioStream) -> AudioStream:
	if s == null or not (s is AudioStreamWAV):
		return s
	if not _loops.has(s):
		var w: AudioStreamWAV = s.duplicate()
		var bytes := 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else 1
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / (bytes * (2 if w.stereo else 1))
		_loops[s] = w
	return _loops[s]


## A thin sheet: a lip sticking out of the wall, then a box down to `bottom`.
## UV.y = world height (texture scrolls continuously down the stream).
func _stream_mesh(f: Dictionary, bottom: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := _stream_center(f)
	var top: float = f.pos.y + (1.0 if f.dir == 4 else 0.85)
	var along: Vector3  # across the stream's width
	var out: Vector3  # thickness direction (away from the wall)
	var half_w: float
	var half_t: float
	if f.dir == 4:
		along = Vector3(1, 0, 0)
		out = Vector3(0, 0, 1)
		half_w = 0.22
		half_t = 0.22
	else:
		out = DIRS[f.dir]
		along = Vector3(out.z, 0, out.x).abs()
		half_w = 0.42  # close to one block wide, like Terraria's
		half_t = 0.12
	_box(st, c, along * half_w, out * half_t, bottom, top)
	if f.dir != 4:
		# Lip: from the wall face out to the stream, at the top.
		var wall := c - out * 0.3
		var mid := (wall + c) * 0.5
		_box(st, mid, along * half_w, out * 0.15, top - 0.14, top)
	return st.commit()


func _box(st: SurfaceTool, c: Vector3, a: Vector3, o: Vector3, y0: float, y1: float) -> void:
	var faces := [[-a - o, a - o], [a - o, a + o], [a + o, -a + o], [-a + o, -a - o]]
	for e in faces:
		var p0: Vector3 = c + e[0]
		var p1: Vector3 = c + e[1]
		var quad := [Vector3(p0.x, y0, p0.z), Vector3(p1.x, y0, p1.z), Vector3(p1.x, y1, p1.z), Vector3(p0.x, y1, p0.z)]
		var uvs := [Vector2(0, y0), Vector2(1, y0), Vector2(1, y1), Vector2(0, y1)]
		for i in [0, 1, 2, 0, 2, 3]:
			st.set_uv(uvs[i])
			st.add_vertex(quad[i])
