class_name WireView
extends MeshInstance3D
## The wiring drawn in the world (Terraria shows it while you hold anything
## mechanical - a wrench, wire, a lever, a pressure plate... - or wear the
## Mechanical Lens): each colour of wire as a thin strand through the middle
## of its cells, a little off the others so crossing colours show, and
## actuators as small dark boxes; seen through the blocks, within RANGE of you.

const RANGE := 40
## Wire colours as Terraria draws them, and each one's offset in a cell.
const COLOURS := {Wiring.RED: Color(0.95, 0.2, 0.2), Wiring.BLUE: Color(0.25, 0.45, 1.0),
		Wiring.GREEN: Color(0.25, 0.9, 0.3), Wiring.YELLOW: Color(1.0, 0.85, 0.15)}
const OFFSETS := {Wiring.RED: Vector3(-0.08, -0.08, -0.08), Wiring.BLUE: Vector3(0.08, -0.08, 0.08),
		Wiring.GREEN: Vector3(-0.08, 0.08, 0.08), Wiring.YELLOW: Vector3(0.08, 0.08, -0.08)}
const THICK := 0.05
const ACTUATOR_COLOUR := Color(0.35, 0.3, 0.3, 0.7)

var game
var _built_version := -1
var _built_at := Vector3i(1 << 30, 0, 0)
var _imesh := ImmediateMesh.new()


func setup(g) -> void:
	game = g
	mesh = _imesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	mat.no_depth_test = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.render_priority = 2
	material_override = mat
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	extra_cull_margin = 16384.0
	visible = false


## Whether the player sees the wiring now.
static func showing(p) -> bool:
	return p.held().get("mech", false) or p.has_effect("wire_vision")


func _process(_delta: float) -> void:
	if game == null or game.player == null:
		return
	visible = showing(game.player)
	if not visible:
		return
	var at := Vector3i(game.player.global_position.floor())
	if game.wiring.version != _built_version or (at - _built_at).length() > 6.0:
		_build(at)


func _build(at: Vector3i) -> void:
	_built_version = game.wiring.version
	_built_at = at
	_imesh.clear_surfaces()
	var cells: Dictionary = game.wiring.cells
	var any := false
	for p in cells:
		if absi(p.x - at.x) > RANGE or absi(p.y - at.y) > RANGE or absi(p.z - at.z) > RANGE:
			continue
		if not any:
			_imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			any = true
		var m: int = cells[p]
		var c := Vector3(p) + Vector3(0.5, 0.5, 0.5)
		if m & Wiring.ACTUATOR:
			_box(c - Vector3.ONE * 0.18, c + Vector3.ONE * 0.18, ACTUATOR_COLOUR)
		for colour in Wiring.COLOURS:
			if m & colour == 0:
				continue
			var o: Vector3 = c + OFFSETS[colour]
			var col: Color = COLOURS[colour]
			_box(o - Vector3.ONE * THICK, o + Vector3.ONE * THICK, col)
			# A strand on to each neighbour with this colour (each pair once).
			for d in [Vector3i.RIGHT, Vector3i.UP, Vector3i.BACK]:
				if int(cells.get(p + d, 0)) & colour:
					var e: Vector3 = o + Vector3(d)
					_box(o.min(e) - Vector3.ONE * THICK, o.max(e) + Vector3.ONE * THICK, col)
	if any:
		_imesh.surface_end()


## An axis-aligned box from `lo` to `hi`.
func _box(lo: Vector3, hi: Vector3, col: Color) -> void:
	var v := [Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z),
			Vector3(lo.x, lo.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	for f in [[0, 1, 2, 3], [5, 4, 7, 6], [4, 0, 3, 7], [1, 5, 6, 2], [3, 2, 6, 7], [4, 5, 1, 0]]:
		_imesh.surface_set_color(col)
		for i in [0, 1, 2, 0, 2, 3]:
			_imesh.surface_add_vertex(v[f[i]])
