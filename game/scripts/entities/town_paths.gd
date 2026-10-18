class_name TownPaths
extends RefCounted
## Where a town NPC can walk: a search over the cells it can stand in (feet
## cell open, head cell open, something to stand on below), stepping up a
## block, dropping up to 3, and through doors (shut ones too: the NPC opens
## them on the way). Terraria's NPCs walk a line and turn at walls; in 3D they
## would just push against a wall of their house, so they walk paths instead.

const DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const DIAGONALS := [Vector3i(1, 0, 1), Vector3i(1, 0, -1), Vector3i(-1, 0, 1), Vector3i(-1, 0, -1)]
const MAX_DROP := 3

var world: VoxelWorld
var _open := {}  # cell -> can be walked through
var _floor := {}  # cell -> can be stood on (top of)


func _init(w: VoxelWorld) -> void:
	world = w


## Open to walk through: not solid (a door counts as open) and no lava.
func is_open(c: Vector3i) -> bool:
	if _open.has(c):
		return _open[c]
	var ok := true
	if world.is_solid(c):
		ok = Doors.is_part(Data.block(world.get_block(c)))
	if ok and world.get_liquid(c).x == 2:
		ok = false
	_open[c] = ok
	return ok


func _is_floor(c: Vector3i) -> bool:
	if not _floor.has(c):
		var d := Data.block(world.get_block(c))
		_floor[c] = (world.is_solid(c) and not Doors.is_part(d)) or d.get("platform", false)
	return _floor[c]


## The NPC fits standing here (feet in `c`).
func can_stand(c: Vector3i) -> bool:
	return is_open(c) and is_open(c + Vector3i.UP) and _is_floor(c + Vector3i.DOWN)


## True if `c` is part of a door: walked through, never stopped in.
func is_door(c: Vector3i) -> bool:
	return Doors.is_part(Data.block(world.get_block(c)))


## The cell where the NPC lands stepping from `c` toward `d` (a step up, level,
## or a drop), or null.
func _step(c: Vector3i, d: Vector3i):
	var n := c + d
	if can_stand(n):
		return n
	if can_stand(n + Vector3i.UP) and is_open(c + Vector3i.UP * 2):
		return n + Vector3i.UP
	if not (is_open(n) and is_open(n + Vector3i.UP)):
		return null
	for k in range(1, MAX_DROP + 1):
		var m := n + Vector3i.DOWN * k
		if not is_open(m):
			return null
		if can_stand(m):
			return m
	return null


## Every cell reachable from `start` within `radius` (across) of `center`:
## cell -> the cell it's reached from (start -> start).
func reachable(start: Vector3i, center: Vector3i, radius: int) -> Dictionary:
	var came := {start: start}
	var queue: Array[Vector3i] = [start]
	var i := 0
	while i < queue.size():
		var c := queue[i]
		i += 1
		var nexts := []
		for d in DIRS:
			var n = _step(c, d)
			if n != null:
				nexts.append(n)
		# Diagonals on the level, when both sides are clear (no corner cutting)
		# and neither end is a doorway (walked straight through).
		if not is_door(c):
			for d in DIAGONALS:
				var n: Vector3i = c + d
				if can_stand(n) and not is_door(n) and can_stand(c + Vector3i(d.x, 0, 0)) and can_stand(c + Vector3i(0, 0, d.z)):
					nexts.append(n)
		for n in nexts:
			if came.has(n) or maxi(absi(n.x - center.x), absi(n.z - center.z)) > radius:
				continue
			came[n] = c
			queue.append(n)
	return came


## The walk from the search's start to `goal`: the middle of each cell's floor
## after the start.
static func path_to(came: Dictionary, goal: Vector3i) -> Array:
	var cells := []
	var c := goal
	while came[c] != c:
		cells.push_front(Vector3(c) + Vector3(0.5, 0, 0.5))
		c = came[c]
	return cells


## The cell the NPC at `pos` stands in (its feet), or null if it isn't
## standing anywhere (falling, swimming).
func standing_cell(pos: Vector3):
	var c := Vector3i(pos.floor())
	for dy in [0, 1, -1]:
		if can_stand(c + Vector3i(0, dy, 0)):
			return c + Vector3i(0, dy, 0)
	return null
