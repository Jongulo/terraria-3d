class_name NPCModel
extends Node3D
## An enemy or town NPC drawn as a 3D model (NPCModels: its chosen method, a
## mesh per frame of its sprite) instead of a billboard. It answers the same
## calls an EntitySprite does (frames, tint, the hit flash, light), and turns
## to face where it's going: the art's left (Terraria sprites look left) along
## its heading; fliers that tilt with their flight point their art along it.

var kind := ""
var method := ""
var frames := 1
var _frame := -1
var _mi := MeshInstance3D.new()
## Fliers: which way their art points (Terraria's sprite_angle; 0: down).
var _art_forward := Vector3.LEFT
var _tilts := false
var _fade := 1.0
var _xray := false
static var XRAY := _xray_material()


static func _xray_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/npc_model_xray.gdshader")
	return m


func setup(kind_name: String, m: String) -> void:
	kind = kind_name
	method = m
	frames = int(NPC.look(kind).frames)
	NPCModels.prebuild(kind, m)
	_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(_mi)
	var d: Dictionary = Data.npcs[kind]
	var lk := NPC.look(kind)
	if lk.flying and d.ai != "bat" and not d.get("upright", false):
		_tilts = true
		var a := Vector2(0, -1).rotated(-deg_to_rad(float(d.get("sprite_angle", 0.0))))
		_art_forward = Vector3(a.x, a.y, 0).normalized()
	set_frame(0)


func set_frame(f: int) -> void:
	f = clampi(f, 0, frames - 1)
	if f == _frame:
		return
	_frame = f
	var m := NPCModels.mesh(kind, method, f)
	_mi.mesh = m.mesh
	_mi.material_override = NPCModels.material(kind, f, m.textured, NPCModels.glass(kind, method))


## Turns it to face `heading` (its motion, or toward you when it stands still).
func face(heading: Vector3) -> void:
	if heading.length() < 0.01:
		return
	if _tilts:
		# Its art's pointing direction along the flight, in 3D.
		_mi.quaternion = Quaternion(_art_forward, heading.normalized())
		return
	var h := Vector3(heading.x, 0, heading.z)
	if h.length() < 0.01:
		return
	h = h.normalized()
	# Local -x (the art's left) onto h.
	_mi.rotation = Vector3(0, atan2(h.z, -h.x), 0)


## Turns it to exactly `b` (mesh space to the NPC): Skeletron's face toward
## you, rolled by its lean and spin.
func orient(b: Basis) -> void:
	_mi.basis = b


func set_tint(c: Color) -> void:
	_mi.set_instance_shader_parameter("tint", c)


## 1: whole; less fades it out, dithered (the Brain of Cthulhu teleporting);
## its see-through silhouette goes once it's half gone.
func set_fade(v: float) -> void:
	if v == _fade:
		return
	_fade = v
	_mi.set_instance_shader_parameter("fade", v)
	_mi.material_overlay = XRAY if _xray and v >= 0.5 else null


func set_flash(v: float) -> void:
	_mi.set_instance_shader_parameter("flash", v)


## Seen through whatever's in front of it (bosses), as a tinted silhouette
## where it's hidden.
func set_xray(on: bool) -> void:
	_xray = on
	_mi.material_overlay = XRAY if on and _fade >= 0.5 else null


## Billboard-only calls: a model faces its heading instead.
func set_flip(_f: bool) -> void:
	pass


func set_rotation_angle(_a: float) -> void:
	pass


func set_trim_bottom(_px: float, _frame_height: float) -> void:
	pass


func update_light(world: VoxelWorld, sky: SkySystem, at: Vector3) -> void:
	_mi.set_instance_shader_parameter("entity_light", world.get_light(at))
	var mat := _mi.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("sky_light", sky.sky_light)
		mat.set_shader_parameter("sky_color", sky.sky_tint)


## Full daylight, with no world to ask (the NPC picker).
func set_full_light() -> void:
	_mi.set_instance_shader_parameter("entity_light", Color(1, 1, 1, 1))
