class_name RenderedSprite
extends EntitySprite
## An NPC drawn with its pre-rendered sprites (NPCRenders: its voxel model shot
## from every angle, at the sprite's pixel size). Each frame it shows the shot
## that looks at the model the way the camera does, turned in the screen plane
## to match. It faces its heading as an NPCModel would (fliers that tilt point
## their art along it). Until the shots are ready (or where they can't be
## made: headless), it's the ordinary sprite.

var kind := ""
var _look := {}
var _renders := {}
var _frame := 0
## Its model's turn (mesh space to the NPC), as NPCModel's mesh would be.
var _orient := Basis.IDENTITY
var _art_forward := Vector3.LEFT
var _tilts := false


func _shader() -> Shader:
	return preload("res://shaders/billboard_rendered.gdshader")


func setup_rendered(kind_name: String) -> void:
	kind = kind_name
	_look = NPC.look(kind)
	NPC.apply_look(self, _look)
	var d: Dictionary = Data.npcs[kind]
	if _look.flying and d.ai != "bat" and not d.get("upright", false):
		_tilts = true
		var a := Vector2(0, -1).rotated(-deg_to_rad(float(d.get("sprite_angle", 0.0))))
		_art_forward = Vector3(a.x, a.y, 0).normalized()
	_poll()


## Turns it to face `heading` (as NPCModel.face).
func face(heading: Vector3) -> void:
	if heading.length() < 0.01:
		return
	if _tilts:
		_orient = Basis(Quaternion(_art_forward, heading.normalized()))
		return
	var h := Vector3(heading.x, 0, heading.z)
	if h.length() < 0.01:
		return
	h = h.normalized()
	_orient = Basis(Vector3.UP, atan2(h.z, -h.x))


## Turns it to exactly `b` (as NPCModel.orient).
func orient(b: Basis) -> void:
	_orient = b


func set_frame(f: int) -> void:
	_frame = f
	if _renders.is_empty():
		super.set_frame(f)


## The billboard's own turn (fliers' AI): the shots turn themselves.
func set_rotation_angle(a: float) -> void:
	if _renders.is_empty():
		super.set_rotation_angle(a)


func set_flip(f: bool) -> void:
	if _renders.is_empty():
		super.set_flip(f)


func _process(_delta: float) -> void:
	if _renders.is_empty():
		_poll()
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var turn := global_transform.basis.orthonormalized() * _orient
	var to_cam := turn.inverse() * (cam.global_position - global_position)
	var v := NPCRenders.pick(to_cam)
	_mat.set_shader_parameter("sprite", _renders.atlases[clampi(_frame, 0, _renders.atlases.size() - 1)])
	_mat.set_shader_parameter("region", Vector4(float(v.x) / NPCRenders.YAWS, float(v.y) / NPCRenders.PITCHES.size(),
			1.0 / NPCRenders.YAWS, 1.0 / NPCRenders.PITCHES.size()))
	_mat.set_shader_parameter("rotation", NPCRenders.roll(turn * NPCRenders.view_up(v.x, v.y), cam.global_transform.basis))


## Switches to the shots once they're made.
func _poll() -> void:
	var r := NPCRenders.renders(kind)
	if r.is_empty():
		return
	_renders = r
	var size: float = r.n * r.px
	scale = Vector3(size, size, 1.0)
	extra_cull_margin = size
	(mesh as QuadMesh).center_offset = Vector3.ZERO
	_mat.set_shader_parameter("frames", 1)
	_mat.set_shader_parameter("frame", 0)
	_mat.set_shader_parameter("trim_bottom", 0.0)
	_mat.set_shader_parameter("flip", false)
	_mat.set_shader_parameter("spherical", true)
	_mat.set_shader_parameter("unpremultiply", true)
	# To the front of the model (its radius, in the quad's half widths), so
	# the ground under it doesn't cut it seen from above.
	_mat.set_shader_parameter("push", r.radius / (size * 0.5))
	# Centred on the model's middle: where a centred sprite is, or (grounded)
	# the middle's height above the feet.
	position.y = _look.sprite_y if _look.centred else float(r.center.y)
