class_name FallingBlock
extends Node3D
## A block of sand (or ebonsand, crimsand, silt, slush) dropping down its
## column: Terraria's falling-tile projectiles (WorldGen.SpawnFallingBlockProjectile,
## Projectile.AI_010). It falls at 0.41 px/tick² up to 10 px/tick, hurts
## whatever it passes through (10 damage, knockback 6, players and enemies
## alike), and turns back into its block where it lands; if that cell is taken
## (a torch, a chest), it drops as an item instead.

const GRAVITY := 61.5  # 0.41 px/tick²
const MAX_SPEED := 25.0  # 10 px/tick
const DAMAGE := 10
const KNOCKBACK := 6.0

var block := 0
var velocity := 0.0
var _hit := {}
var _mat := StandardMaterial3D.new()


func setup(id: int) -> void:
	block = id
	var d := Data.block(id)
	var layer: int = d.get("tex_side", d.get("tex_top", 0))
	var tex := ImageTexture.create_from_image(Data.block_textures.get_layer_data(layer))
	_mat.albedo_texture = tex
	_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Each face of the box shows the whole texture (BoxMesh lays faces out 3 x 2).
	_mat.uv1_scale = Vector3(3, 2, 1)
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = _mat
	mi.position = Vector3(0.5, 0.5, 0.5)
	add_child(mi)


## The cell its bottom is in.
func cell() -> Vector3i:
	return Vector3i(global_position.floor())


func _physics_process(delta: float) -> void:
	var game := Game.current
	velocity = minf(MAX_SPEED, velocity + GRAVITY * delta)
	var step := velocity * delta
	var c := Vector3i(global_position.floor())
	# Landing: the next cell down is solid, or a platform (it falls on into a
	# plant's or a torch's cell).
	var below := Vector3i(c.x, int(floor(global_position.y - step)), c.z)
	if below.y < c.y and _lands_on(game.world, below):
		land(game, c)
		return
	if global_position.y - step < 0.0:
		queue_free()
		return
	global_position.y -= step
	_hurt_what_it_hits(game)
	var l := game.world.get_light(global_position + Vector3(0.5, 0.5, 0.5))
	var sun := game.sky.sky_light * l.a
	_mat.albedo_color = Color(maxf(l.r, sun * game.sky.sky_tint.r), maxf(l.g, sun * game.sky.sky_tint.g), maxf(l.b, sun * game.sky.sky_tint.b))


static func _lands_on(w: VoxelWorld, p: Vector3i) -> bool:
	var b := Data.block(w.get_block(p))
	return not b.is_empty() and (b.get("solid", true) or b.get("platform", false)) and int(b.get("tile_id", -1)) != 165


## Settles into cell `c`, or drops as an item when something is there.
func land(game: Game, c: Vector3i) -> void:
	var here := game.world.get_block(c)
	if here != 0 and Data.block(here).get("cut", false):
		game.break_block(c)
		here = game.world.get_block(c)
	if here == 0:
		game.world.set_block(c, block)
		Audio.play_at("Dig_*", Vector3(c) + Vector3(0.5, 0.5, 0.5), 0.5)
		# It may land on a gap's edge it can't rest on (a non-solid block).
		game.settle_falling(c)
	else:
		game.spawn_item(game.block_drop(Data.block(block)), 1, Vector3(c) + Vector3(0.5, 0.5, 0.5))
	queue_free()


func _hurt_what_it_hits(game: Game) -> void:
	var center := global_position + Vector3(0.5, 0.5, 0.5)
	var p := game.player
	if p.alive and not _hit.has(p) and p.overlaps_point(center, 0.5):
		_hit[p] = true
		p.hurt(DAMAGE, center)
	for npc in game.npcs():
		if not _hit.has(npc) and not npc.def.get("invulnerable", false) and npc.overlaps_point(center, 0.5):
			_hit[npc] = true
			npc.hit(DAMAGE, KNOCKBACK, Vector3(0, -1, 0), 0.0)
