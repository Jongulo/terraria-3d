class_name Ropes
extends RefCounted
## Terraria's ropes and chains (Main.tileRope: Rope, Vine, Silk and Web Rope,
## Chain). They go beside anything, and placed on a rope they go on under the
## bottom of it (Player.PlaceThing_Tiles); a Rope Coil lays a line of them
## where it lands (Projectile AI 35); you climb them (Player._rope_climb).

## How many a Rope Coil lays.
const COIL := 10
## How far down placing on a rope looks for its bottom.
const MAX_LENGTH := 512
const SIDES := [Vector3i.UP, Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]


static func is_rope(world: VoxelWorld, p: Vector3i) -> bool:
	return Data.block(world.get_block(p)).get("rope", false)


## Free for a rope: empty, or a plant or cobweb that gets cut out of the way
## (Main.tileCut; 1.4.5 ropes go through them).
static func is_free(world: VoxelWorld, p: Vector3i) -> bool:
	var id := world.get_block(p)
	return id == 0 or Data.block(id).get("cut", false)


## Something to hang a rope on: anything next to it, rope included.
static func can_hang(world: VoxelWorld, p: Vector3i) -> bool:
	for d in SIDES:
		if world.get_block(p + d) != 0:
			return true
	return false


## Where more rope placed on the rope at `p` goes: the cell under the bottom
## of its line, or (-1, -1, -1) if that isn't free.
static func extend_at(world: VoxelWorld, p: Vector3i) -> Vector3i:
	var q := p
	for i in MAX_LENGTH:
		q += Vector3i.DOWN
		if is_rope(world, q):
			continue
		return q if is_free(world, q) else Vector3i(-1, -1, -1)
	return Vector3i(-1, -1, -1)


## Puts rope `id` at `p`, cutting what's in the way. True if it went in.
static func put(game, p: Vector3i, id: int) -> bool:
	game.cut_tile(p)
	return game.world.get_block(p) == 0 and game.world.set_block(p, id)


## A Rope Coil landed at `p`: down past any rope already there, it lays up to
## COIL of rope `id` until something else is in the way. How many it laid.
static func lay(game, p: Vector3i, id: int) -> int:
	var q := p
	while is_rope(game.world, q):
		q += Vector3i.DOWN
	var laid := 0
	while laid < COIL and is_free(game.world, q) and put(game, q, id):
		laid += 1
		q += Vector3i.DOWN
	return laid
