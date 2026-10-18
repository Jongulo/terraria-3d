class_name Housing
## Terraria's housing check, in 3D. A home is a room closed off on every side
## (floor, walls and ceiling, the way Terraria's background walls close a room
## off) by blocks, doors and platforms, neither too small nor too big, with a
## door (or a platform) for a way in, a light source, a table and a chair, and
## somewhere to stand. Rooms are found with VoxelWorld.flood_room; the blocks'
## "house" key (light, chair, table) says what they give a room.

## Open cells: a room of at least 3 x 3 x 2 cells, and no more than a big
## hall (beyond that a room counts as leaking: a wall is missing).
const MIN_CELLS := 18
const MAX_CELLS := 1500

static var _walls := PackedInt32Array()


## Door parts and platforms: they close a room off like walls do.
static func walls() -> PackedInt32Array:
	if _walls.is_empty():
		for id in Data.blocks.size():
			if _is_entrance(Data.block(id)):
				_walls.append(id)
	return _walls


static func _is_entrance(d: Dictionary) -> bool:
	return Doors.is_part(d) or (d.get("platform", false) and String(d.get("name", "")).ends_with("_platform"))


## Checks the room around `start`: {ok, reason (Terraria's words when it
## isn't a home), key (the room's identity: its lowest cell), spot (where to
## stand), cells}.
static func check(world: VoxelWorld, start: Vector3i) -> Dictionary:
	var town: Dictionary = Assets.ids.get("names", {}).get("town", {})
	var reasons: Dictionary = town.get("TownNPCHousingFailureReasons", {})
	var out := {"ok": false, "reason": "", "key": "", "spot": Vector3i.ZERO, "cells": 0}
	var room := world.flood_room(start, MAX_CELLS, walls())
	var cells: PackedInt32Array = room.cells
	out.cells = cells.size() / 3
	if cells.is_empty():
		out.reason = reasons.get("RoomCheckStartedInASolidTile", "This is a solid block!")
		return out
	if room.overflow:
		out.reason = reasons.get("HoleInWallIsTooBig", "This room is missing a wall")
		return out
	if out.cells < MIN_CELLS:
		out.reason = reasons.get("RoomIsTooSmall", "This room is too small")
		return out
	var floor: PackedInt32Array = room.floor
	if floor.is_empty():
		out.reason = reasons.get("RoomHasNoStandingSpace", "This room has no space to stand in!")
		return out
	var has := {}
	for id in room.ids:
		var d := Data.block(id)
		if d.has("house"):
			has[d.house] = true
		if _is_entrance(d):
			has["door"] = true
	var missing := []
	for need in ["door", "light", "table", "chair"]:
		if not has.has(need):
			missing.append({"door": "a door", "light": "a light source", "table": "a table", "chair": "a chair"}[need])
	if not missing.is_empty():
		out.reason = "This housing is missing " + " and ".join(missing) + "."
		return out
	# Its identity: the lowest (then most north-west) cell; where to stand: the
	# standing cell nearest the room's middle.
	var key := Vector3i(cells[0], cells[1], cells[2])
	var mid := Vector3.ZERO
	for i in range(0, cells.size(), 3):
		var c := Vector3i(cells[i], cells[i + 1], cells[i + 2])
		mid += Vector3(c)
		if c.y < key.y or (c.y == key.y and (c.x < key.x or (c.x == key.x and c.z < key.z))):
			key = c
	mid /= out.cells
	var spot := Vector3i(floor[0], floor[1], floor[2])
	for i in range(0, floor.size(), 3):
		var c := Vector3i(floor[i], floor[i + 1], floor[i + 2])
		if Vector3(c).distance_squared_to(mid) < Vector3(spot).distance_squared_to(mid):
			spot = c
	out.ok = true
	out.key = Chests.key(key)
	out.spot = spot
	out.reason = "This housing is suitable."
	return out


## The homes around `center`: a room checked from every chair within reach
## (every home has one). Valid rooms only, one entry per room.
static func find_homes(world: VoxelWorld, center: Vector3i, reach := Vector3i(48, 24, 48)) -> Array:
	var chairs := PackedInt32Array()
	for id in Data.blocks.size():
		if Data.block(id).get("house") == "chair":
			chairs.append(id)
	var found := world.find_blocks(center, reach, chairs, 64)
	var homes := {}
	for i in range(0, found.size(), 3):
		var h := check(world, Vector3i(found[i], found[i + 1], found[i + 2]))
		if h.ok and not homes.has(h.key):
			homes[h.key] = h
	return homes.values()
