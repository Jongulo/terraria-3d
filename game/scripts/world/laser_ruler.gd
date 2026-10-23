class_name LaserRuler
extends MeshInstance3D
## The Laser Ruler's measuring lines (an accessory: "Creates measurement
## lines on screen for block placement"). Terraria draws a grid across the
## screen from the tile under the cursor; here three lines run through the
## block you aim at, along x, y and z, with a mark at each block and a longer
## one every fifth, out to REACH blocks either way.

const REACH := 24
const COLOUR := Color(1.0, 0.25, 0.25, 0.6)

var game
var _shown := Vector3i(1 << 30, 0, 0)
var _imesh := ImmediateMesh.new()


func setup(g) -> void:
	game = g
	mesh = _imesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	visible = false


func _process(_delta: float) -> void:
	if game == null or game.player == null:
		return
	var p = game.player
	visible = p.has_effect("laser_ruler") and not p.target.is_empty()
	if not visible:
		return
	var at: Vector3i = p.target.block
	if at != _shown:
		_build(at)


func _build(at: Vector3i) -> void:
	_shown = at
	_imesh.clear_surfaces()
	_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var c := Vector3(at) + Vector3(0.5, 0.5, 0.5)
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_line(c - axis * REACH, c + axis * REACH)
		var across: Vector3 = Vector3.UP if axis != Vector3.UP else Vector3.RIGHT
		for k in range(-REACH, REACH + 1):
			var len := 0.3 if k % 5 == 0 else 0.12
			var m: Vector3 = c + axis * k
			_line(m - across * len, m + across * len)
	_imesh.surface_end()


func _line(a: Vector3, b: Vector3) -> void:
	_imesh.surface_set_color(COLOUR)
	_imesh.surface_add_vertex(a)
	_imesh.surface_set_color(COLOUR)
	_imesh.surface_add_vertex(b)
