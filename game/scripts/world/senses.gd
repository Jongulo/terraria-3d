class_name Senses
extends MeshInstance3D
## What the Spelunker, Trapsight and Hunter Potions show (Terraria's
## findTreasure, dangerSense, detectCreature). Terraria brightens them on
## screen: treasure to at least (200, 170, 0) with a gold sparkle now and
## then, dangers to (255, 50, 50) with a red one, and creatures to (255, 50,
## 50), friendly ones (50, 255, 50), drawn in front of the blocks. Here they
## are outlined in those colours through the walls, out to REACH blocks:
## - Spelunker: Main.tileSpelunker (ores, chests, pots, Life Crystals, gems,
##   herbs grown, paintings, trophies, statues, fossils...).
## - Trapsight: TileDrawing.IsTileDangerous (pressure plates, traps,
##   boulders, explosives, cobwebs, spikes and what burns you).
## - Hunter: every creature with more than 1 life, seen through the blocks
##   as the bosses are (their x-ray silhouettes), red or green.

const REACH := Vector3i(24, 16, 24)
const CREATURE_REACH := 60.0
const MOST := 1500
const TREASURE := Color(200.0 / 255.0, 170.0 / 255.0, 0.0, 0.85)
const DANGER := Color(1.0, 50.0 / 255.0, 50.0 / 255.0, 0.85)
## Main.tileSpelunker.
const SPELUNKER_TILES := [6, 7, 8, 9, 12, 21, 467, 441, 468, 28, 107, 108, 111, 63, 64, 65, 66, 67, 68, 566, 166, 167,
		168, 169, 178, 211, 221, 222, 223, 236, 702, 37, 407, 227, 84, 83, 404, 242, 240, 246, 245, 105, 349, 337,
		531, 506, 751, 752, 639]
## IsTileDangerous's own tiles (with Sets.Boulders, touch damage, Hellstone).
const DANGER_TILES := [135, 137, 141, 210, 442, 443, 444, 411, 485, 85, 654, 314, 230, 58, 483, 482, 51]
## Seconds between looks round for blocks.
const RESCAN := 0.5

var game
var _imesh := ImmediateMesh.new()
var _treasure_ids := PackedInt32Array()
var _danger_ids := PackedInt32Array()
var _treasure := PackedInt32Array()
var _danger := PackedInt32Array()
var _scan_t := 0.0


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
	for id in Data.blocks.size():
		var b := Data.block(id)
		if is_treasure(b):
			_treasure_ids.append(id)
		if is_danger(b):
			_danger_ids.append(id)


static func is_treasure(b: Dictionary) -> bool:
	return int(b.get("tile_id", -1)) in SPELUNKER_TILES or b.get("interact") == "chest" or b.get("on_break") == "pot"


static func is_danger(b: Dictionary) -> bool:
	return int(b.get("tile_id", -1)) in DANGER_TILES or b.has("trap") or b.has("pressure_plate") \
			or b.has("touch_damage") or b.get("hot", false)


func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	var p = game.player
	var spelunker: bool = p.has_effect("spelunker")
	var danger: bool = p.has_effect("dangersense")
	var hunter: bool = p.has_effect("hunter")
	_hunt(p, hunter)
	visible = spelunker or danger
	if not visible:
		_treasure.clear()
		_danger.clear()
		return
	var at := Vector3i(p.global_position.floor())
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = RESCAN
		_treasure = game.world.find_blocks(at, REACH, _treasure_ids, MOST) if spelunker else PackedInt32Array()
		_danger = game.world.find_blocks(at, REACH, _danger_ids, MOST) if danger else PackedInt32Array()
	_imesh.clear_surfaces()
	_imesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var lines := 0
	lines += _cells(_treasure, TREASURE, delta, 60.0)
	lines += _cells(_danger, DANGER, delta, 30.0)
	if lines == 0:
		# (An empty surface errors: one line out of the way.)
		_line(Vector3.ZERO, Vector3.ZERO, Color.TRANSPARENT)
	_imesh.surface_end()


## Creatures (more than 1 life) near you show through the blocks with the
## Hunter Potion, tinted red, or green if friendly.
func _hunt(p, on: bool) -> void:
	for npc in game.npcs():
		var state := 0
		if on and npc.life_max > 1 and npc.center().distance_to(p.center()) <= CREATURE_REACH:
			state = 2 if npc.def.ai == "town" or npc.is_critter() else 1
		npc.set_hunted(state)


## Outlines the cells (flat x, y, z), sparkling 1 in `sparkle` a frame each
## (Terraria's, at 60 a second) near you.
func _cells(cells: PackedInt32Array, colour: Color, delta: float, sparkle: float) -> int:
	var near: Vector3 = game.player.global_position
	for i in range(0, cells.size(), 3):
		var c := Vector3(cells[i], cells[i + 1], cells[i + 2])
		_box(c + Vector3.ONE * 0.02, c + Vector3.ONE * 0.98, colour)
		if randf() < delta * 60.0 / sparkle and c.distance_to(near) < 12.0:
			game.spawn_dust(c + Vector3(randf(), randf(), randf()), colour, 1)
	return cells.size() / 3


func _box(lo: Vector3, hi: Vector3, colour: Color) -> void:
	var c := [lo, Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
			Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), hi, Vector3(lo.x, hi.y, hi.z)]
	for e in [[0, 1], [1, 2], [2, 3], [3, 0], [4, 5], [5, 6], [6, 7], [7, 4], [0, 4], [1, 5], [2, 6], [3, 7]]:
		_line(c[e[0]], c[e[1]], colour)


func _line(a: Vector3, b: Vector3, colour: Color) -> void:
	_imesh.surface_set_color(colour)
	_imesh.surface_add_vertex(a)
	_imesh.surface_set_color(colour)
	_imesh.surface_add_vertex(b)
