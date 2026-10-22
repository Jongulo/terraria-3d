class_name Paintings
extends RefCounted
## Terraria's paintings (blocks.json "painting": tiles 240-246, trophies and
## racks too) are wall blocks whose art, two tiles a block, is centred on
## their cell and so covers the cells round it. Like Terraria's multi-tile
## paintings, one needs every cell it covers empty with a solid block behind
## it, keeps other blocks out of those cells, and comes down when a block
## behind it goes. (Worldgen hangs them by the same rule: rust paintings.rs.)

## Paintings are at most 3 blocks across and 2 tall: they reach 1 cell round
## their own.
const REACH := 1


static func is_painting(d: Dictionary) -> bool:
	return d.get("painting", false)


## The cells a painting covers round its own, as offsets: [along from, along
## to, up from, up to] (along: Player.WALL_NORMALS turned a quarter, `along`).
static func cover(d: Dictionary) -> Array:
	var w: float = d.sprite.get_width() * float(d.sprite_px)
	var h: float = d.sprite.get_height() * float(d.sprite_px)
	var r := float(d.get("wall_raise", 0.0))
	return [floori(0.5 - w * 0.5 + 0.001), floori(0.5 + w * 0.5 - 0.001), floori(r + 0.001), floori(r + h - 0.001)]


## The way along the wall of a painting facing out along Player.WALL_NORMALS[r].
static func along(r: int) -> Vector3i:
	var n: Vector3i = Player.WALL_NORMALS[r % 4]
	return Vector3i(-n.z, 0, n.x)


## The cells painting `d` at `pos` facing `r` covers (its own too).
static func cells(d: Dictionary, pos: Vector3i, r: int) -> Array:
	var c := cover(d)
	var a := along(r)
	var out: Array = []
	for k in range(c[0], c[1] + 1):
		for j in range(c[2], c[3] + 1):
			out.append(pos + a * k + Vector3i(0, j, 0))
	return out


## Whether painting `d` fits at `pos` facing `r`: every cell it covers but
## its own empty, a solid block behind each, and no other painting there.
static func fits(game: Node, d: Dictionary, pos: Vector3i, r: int) -> bool:
	var n: Vector3i = Player.WALL_NORMALS[r % 4]
	for c in cells(d, pos, r):
		if c != pos and game.world.get_block(c) != 0:
			return false
		if not game.world.is_solid(c - n):
			return false
		if c != pos and not covering(game, c).is_empty():
			return false
	return true


## The paintings whose art covers cell `p` (their own cells aside).
static func covering(game: Node, p: Vector3i) -> Array:
	var found: Array = []
	for q in _near(game, p):
		if q != p and p in cells(Data.block(game.world.get_block(q)), q, game.block_rotation(q)):
			found.append(q)
	return found


## The paintings hanging on block `p` (on it behind any cell they cover).
static func resting_on(game: Node, p: Vector3i) -> Array:
	var found: Array = []
	for q in _near(game, p):
		var r: int = game.block_rotation(q)
		var n: Vector3i = Player.WALL_NORMALS[r % 4]
		if p + n in cells(Data.block(game.world.get_block(q)), q, r):
			found.append(q)
	return found


## Painting cells within reach (and a step out from a wall) of `p`.
static func _near(game: Node, p: Vector3i) -> Array:
	var found: Array = []
	for dx in range(-REACH - 1, REACH + 2):
		for dy in range(-REACH, REACH + 1):
			for dz in range(-REACH - 1, REACH + 2):
				var q := p + Vector3i(dx, dy, dz)
				if is_painting(Data.block(game.world.get_block(q))):
					found.append(q)
	return found
