class_name Wiring
extends RefCounted
## Terraria's wiring (Wiring.cs). Each cell can carry wire of four colours
## and an actuator; a signal from a trigger runs along each colour's wire
## from its cell through every touching cell with that colour (the six
## neighbours here) and hits every cell it reaches once (HitWireSingle):
## - An actuator there switches its block on or off (Actuate: an actuated
##   block isn't solid, lets light and liquid through and is drawn dark).
## - Doors open or close, lights with an off look switch, Dart Traps shoot
##   (200 ticks at least between shots), Explosives blow up, Geysers spout,
##   timers switch on or off.
## Triggers (HitSwitch): levers and switches (interact), pressure plates
## (Collision.SwitchTiles: red and green by anyone - you, NPCs, boulders;
## gray, brown, blue and orange by you, orange then breaking; yellow by
## anything but you; the Projectile Pressure Pad by shots), timers while on
## (every 1, 3 or 5 s, or 1/2, 1/4), and a Geyser stepped on (it spouts; not a
## signal). Also: Junction Boxes, Wire Bulbs, Teleporters, Pixel Boxes (trip).
##
## Worldgen lays its wire as "wire" decorations (style: the colours) and
## "actuator" ones (wires.rs); the game keeps them here and saves them with
## the world. Old saves' "trap_wire" and "switch" links become wire.

const RED := 1
const BLUE := 2
const GREEN := 4
const YELLOW := 8
const ACTUATOR := 16
const COLOURS := [RED, BLUE, GREEN, YELLOW]
## The Wire each colour's wrench lays (Terraria's ItemID by colour).
const WRENCHES := {RED: "Wrench", BLUE: "BlueWrench", GREEN: "GreenWrench", YELLOW: "YellowWrench"}

## Cell -> its wire colours and actuator (bits above).
var cells := {}
## Bumped whenever the wiring changes (the wire view redraws).
var version := 0
var _cooldown := {}
var _plate_of := {}
var _timer_left := {}
## Ticks between shots/spouts of one Dart Trap or Geyser (Wiring.CheckMech).
const MECH_TICKS := 200.0

const DART_SPEED := 12.0 * 3.75
const DART_DAMAGE := 20
## Terraria's Explosives: projectile 108 (500 damage, 260 px across).
const EXPLOSION := {"radius": 130.0 / 24.0, "tiles": true}
const EXPLOSIVES_DAMAGE := 500
## The Geyser's spout (projectile 654): 20 damage, a column up to 320 px
## (20 tiles: 13.3 blocks) to the first block over it.
const GEYSER_DAMAGE := 20


## From worldgen's decorations (and old saves' links).
func setup(game) -> void:
	cells.clear()
	_cooldown.clear()
	_plate_of.clear()
	_timer_left.clear()
	var w: VoxelWorld = game.world
	for d in w.get_decorations():
		var p := Vector3i(d.pos)
		match d.kind:
			"wire":
				cells[p] = int(cells.get(p, 0)) | int(d.style)
			"actuator":
				cells[p] = int(cells.get(p, 0)) | ACTUATOR
			"trap_wire":
				var s := int(d.style)
				var to := p + Vector3i((s & 127) - 64, (s >> 14) - 64, ((s >> 7) & 127) - 64)
				if Data.block(w.get_block(to)).get("trap", "") == "boulder":
					# The boulder sat on actuated plugs: now stone with actuators.
					var q := to + Vector3i.DOWN
					while Data.block(w.get_block(q)).get("actuated", false):
						w.set_block(q, Data.block_id("stone"))
						cells[q] = int(cells.get(q, 0)) | ACTUATOR
						q += Vector3i.DOWN
					to += Vector3i.DOWN
				lay(p, to, RED)
			"switch":
				var o := int(d.style)
				lay(p, p + Vector3i((o & 31) - 16, o >> 10, ((o >> 5) & 31) - 16), RED)
	version += 1


func save_state() -> Dictionary:
	var flat := []
	for p in cells:
		flat.append_array([p.x, p.y, p.z, cells[p]])
	return {"cells": flat}


func load_state(game, state: Dictionary) -> void:
	cells.clear()
	var flat: Array = state.get("cells", [])
	for i in range(0, flat.size() - 3, 4):
		cells[Vector3i(int(flat[i]), int(flat[i + 1]), int(flat[i + 2]))] = int(flat[i + 3])
	version += 1


## Wire of `colour` from `from` to `to`: across x, then z, then up or down
## (as worldgen lays it).
func lay(from: Vector3i, to: Vector3i, colour: int) -> void:
	var p := from
	add(p, colour)
	for axis in [0, 2, 1]:
		while p[axis] != to[axis]:
			p[axis] += signi(to[axis] - p[axis])
			add(p, colour)


func mask(p: Vector3i) -> int:
	return int(cells.get(p, 0))


func add(p: Vector3i, bits: int) -> void:
	cells[p] = mask(p) | bits
	version += 1


func remove(p: Vector3i, bits: int) -> void:
	var m := mask(p) & ~bits
	if m == 0:
		cells.erase(p)
	else:
		cells[p] = m
	version += 1


# ------------------------------------------------------------------ signals

## A trigger at `from` sends its signal (Wiring.TripWire): along each colour
## of wire in its cell in turn (HitWire), every cell reached is hit once for
## that colour (the trigger's own cell isn't). A Junction Box or Pixel Box
## passes it straight on (across, so wires cross there without joining).
## After each colour, the first two Teleporters it reached swap who stands
## on them; after them all, a Pixel Box reached both across and up or down
## switches (PixelBoxPass).
func trip(game, from: Vector3i) -> void:
	var here := mask(from)
	_pixels.clear()
	for colour in COLOURS:
		if here & colour == 0:
			continue
		var hit := {from: true}
		_objects.clear()
		_teleporters.clear()
		var seen := {[from, -1]: true}
		var queue: Array = [[from, -1]]
		var i := 0
		while i < queue.size():
			var p: Vector3i = queue[i][0]
			var came: int = queue[i][1]
			i += 1
			var junction: bool = came >= 0 and Data.block(game.world.get_block(p)).get("junction", false)
			for k in DIRS.size():
				if junction and k != came:
					continue
				var n: Vector3i = p + DIRS[k]
				if mask(n) & colour == 0:
					continue
				var nj: bool = Data.block(game.world.get_block(n)).get("junction", false)
				var state := [n, k if nj else -1]
				if seen.has(state):
					continue
				seen[state] = true
				queue.append(state)
				if nj and Data.block(game.world.get_block(n)).get("pixel_box", false):
					_pixels[n] = int(_pixels.get(n, 0)) | (2 if DIRS[k].y != 0 else 1)
				if not hit.has(n):
					hit[n] = true
					hit_single(game, n, colour)
		if _teleporters.size() >= 2:
			_teleport(game, _teleporters[0], _teleporters[1])
	for p in _pixels:
		if _pixels[p] == 3:
			var b: Dictionary = Data.block(game.world.get_block(p))
			if b.has("toggles_to"):
				game.world.set_block(p, Data.block_id(b.toggles_to))


const DIRS := [Vector3i.RIGHT, Vector3i.LEFT, Vector3i.UP, Vector3i.DOWN, Vector3i.FORWARD, Vector3i.BACK]
## The Wire Bulb's bit for each colour (its sheet: red, green, blue, yellow).
const BULB_BITS := {RED: 1, GREEN: 2, BLUE: 4, YELLOW: 8}
var _teleporters: Array = []
var _pixels := {}


## Objects of several cells already hit this time (Terraria's SkipWire:
## a door opens once however many of its cells the wire reaches).
var _objects := {}


## A cell the signal reaches (Wiring.HitWireSingle), by wire of `colour`.
func hit_single(game, p: Vector3i, colour := RED) -> void:
	var w: VoxelWorld = game.world
	if mask(p) & ACTUATOR and w.get_block(p) != 0:
		var off := not w.is_inactive(p)
		w.set_inactive(p, off)
		if off:
			# What rested on it may fall (sand, a boulder).
			game.settle_falling(p + Vector3i.UP)
	var b: Dictionary = Data.block(w.get_block(p))
	if b.is_empty():
		return
	if Doors.is_part(b):
		var base := Doors.bottom(w, p)
		if not _objects.has(base):
			_objects[base] = true
			Doors.toggle(game, base, Vector3(base) + Vector3(0.5, 0, 0.5))
	elif b.has("off") or b.has("lit"):
		w.set_block(p, Data.block_id(b.get("off", b.get("lit"))))
	elif b.has("timer"):
		w.set_block(p, Data.block_id(b.toggles_to))
		_timer_left.erase(p)
	elif b.has("bulb"):
		# Its light for this colour goes on or off.
		var st: int = int(b.bulb) ^ int(BULB_BITS[colour])
		w.set_block(p, Data.block_id("wire_bulb" if st == 0 else "wire_bulb_%d" % st))
	elif b.get("teleporter", false):
		if _teleporters.size() < 2 and not _teleporters.has(p):
			_teleporters.append(p)
	match b.get("trap", ""):
		"dart":
			if _ready_mech(p):
				_shoot_dart(game, p)
		"explosives":
			w.set_block(p, 0)
			game.explode(Vector3(p) + Vector3(0.5, 0.5, 0.5), EXPLOSIVES_DAMAGE, 10.0, EXPLOSION)
		"geyser":
			geyser(game, p)


## Wiring.Teleport: whoever stands on each of the two goes to the other (you
## and NPCs; not bosses, nor what flies through blocks). Not when they're
## next to each other.
func _teleport(game, a: Vector3i, b: Vector3i) -> void:
	if Vector3(b - a).length() < 2.0:
		return
	var moves := []
	for pair in [[a, b], [b, a]]:
		var on := func(pos: Vector3) -> bool:
			var c: Vector3i = pair[0]
			return absf(pos.x - (c.x + 0.5)) < 1.0 and absf(pos.z - (c.z + 0.5)) < 1.0 and pos.y >= c.y - 0.1 and pos.y < c.y + 1.5
		var off := Vector3(pair[1] - pair[0])
		var p = game.player
		if p.alive and on.call(p.global_position):
			moves.append([p, off])
		for npc in game.npcs():
			if npc.boss or npc.def.get("ai", "") in FLOATING or npc.def.get("life", 0) <= 5:
				continue
			if on.call(npc.global_position):
				moves.append([npc, off])
	for m in moves:
		m[0].global_position += m[1]
		if m[0] == game.player:
			game.player._fall_start = game.player.global_position.y
	if not moves.is_empty():
		Audio.play_at("Item_6", Vector3(a) + Vector3(0.5, 0.5, 0.5), 0.6)


## A switch or lever flipped (HitSwitch): its look, Terraria's click, the
## signal.
func flip(game, p: Vector3i) -> void:
	var b: Dictionary = Data.block(game.world.get_block(p))
	if b.has("toggles_to"):
		game.world.set_block(p, Data.block_id(b.toggles_to))
	Audio.play_at("Mech_0", Vector3(p) + Vector3(0.5, 0.5, 0.5))
	trip(game, p)


## A timer switched on or off by hand (HitSwitch for tile 144: no signal).
func toggle_timer(game, p: Vector3i) -> void:
	var b: Dictionary = Data.block(game.world.get_block(p))
	if b.has("timer"):
		game.world.set_block(p, Data.block_id(b.toggles_to))
		_timer_left.erase(p)
		Audio.play_at("Mech_0", Vector3(p) + Vector3(0.5, 0.5, 0.5))


## Wiring.CheckMech: one shot per Dart Trap or Geyser every 200 ticks.
func _ready_mech(p: Vector3i) -> bool:
	if _cooldown.has(p):
		return false
	_cooldown[p] = MECH_TICKS / 60.0
	return true


func _shoot_dart(game, at: Vector3i) -> void:
	var facing: int = int(game.block_rotations.get(Chests.key(at), 0))
	var f: Vector2i = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)][posmod(facing, 4)]
	var dir := Vector3(f.x, 0, f.y)
	# Terraria doubles hostile shots' damage on you.
	game.spawn_projectile("PoisonDart", Vector3(at) + Vector3(0.5, 0.5, 0.5) + dir * 0.6, dir * DART_SPEED, DART_DAMAGE * 2, 2.0, 0.0, 0.0, 0.5, false)
	Audio.play_at("Item_5", Vector3(at) + Vector3(0.5, 0.5, 0.5), 0.6)


## Wiring.GeyserTrap: a spout of fire up from it (Projectile "GeyserTrap").
func geyser(game, at: Vector3i) -> void:
	if not _ready_mech(at):
		return
	var p: Projectile = game.spawn_projectile("GeyserTrap", Vector3(at) + Vector3(0.5, 0.6, 0.5), Vector3.ZERO, GEYSER_DAMAGE * 2, 2.0, 0.0, 0.0, 0.5, false)
	p.geyser = true


# ------------------------------------------------------------------ each frame

## Pressure plates under you, the NPCs and the boulders; timers; cooldowns.
func update(game, delta: float) -> void:
	for k in _cooldown.keys():
		_cooldown[k] -= delta
		if _cooldown[k] <= 0.0:
			_cooldown.erase(k)
	var p = game.player
	if p.alive and not p.flying:
		_step(game, p.get_instance_id(), p.global_position, "player")
	else:
		_plate_of.erase(p.get_instance_id())
	for npc in game.npcs():
		if not npc.def.get("ai", "") in FLOATING:
			_step(game, npc.get_instance_id(), npc.global_position, "npc")
	for e in game.entities.get_children():
		if e is Projectile and e.boulder:
			_step(game, e.get_instance_id(), e.global_position - Vector3(0, 0.5, 0), "projectile")
		elif e is Projectile and not e.geyser:
			_step(game, e.get_instance_id(), e.global_position, "shot")
	for id in _plate_of.keys():
		if not is_instance_id_valid(id):
			_plate_of.erase(id)
	_run_timers(game, delta)


## NPCs that don't walk on the ground (nor stand on plates).
const FLOATING := ["dummy", "flyer", "bat", "harpy", "skull", "spike_ball", "wheel", "worm", "bee", "bird", "firefly", "butterfly",
		"boss_eoc", "skeletron", "skeletron_hand", "queen_bee", "brain", "creeper", "swim"]


## Something standing at `feet`: a plate it has just stepped onto goes off if
## it answers to it (Collision.SwitchTiles).
func _step(game, id: int, feet: Vector3, who: String) -> void:
	var cell := Vector3i(feet.floor())
	var b: Dictionary = Data.block(game.world.get_block(cell))
	var kind: String = b.get("pressure_plate", "")
	var was = _plate_of.get(id)
	if kind == "" and b.get("trap", "") != "geyser":
		_plate_of.erase(id)
		return
	_plate_of[id] = cell
	if was == cell:
		return
	if b.get("trap", "") == "geyser":
		if who == "player":
			geyser(game, cell)
		return
	# A shot only sets off the Projectile Pressure Pad, and only shots do.
	var answers := (kind == "projectile") == (who == "shot") and (kind in ["any", "projectile"] or (kind == "player" and who == "player")
			or (kind == "not_player" and who != "player"))
	if not answers:
		return
	Audio.play_at("Mech_0", Vector3(cell) + Vector3(0.5, 0.1, 0.5), 0.6)
	trip(game, cell)
	if b.get("plate_breaks", false):
		game.break_block(cell)


## Timers that are on signal every so often (Wiring.UpdateMech: 1, 3 or 5
## s, 1/2 or 1/4).
func _run_timers(game, delta: float) -> void:
	var w: VoxelWorld = game.world
	for p in _timer_left.keys():
		if not Data.block(w.get_block(p)).get("timer_on", false):
			_timer_left.erase(p)
	for p in _timer_cells(game):
		var b: Dictionary = Data.block(w.get_block(p))
		if not b.get("timer_on", false):
			continue
		var left: float = _timer_left.get(p, float(b.timer)) - delta
		if left <= 0.0:
			left += float(b.timer)
			trip(game, p)
		_timer_left[p] = left


## Timers on wire (a timer with no wire signals nothing, so only those),
## looked for again when the wiring changes or every second.
var _timers: Array = []
var _timers_version := -1
var _timers_age := 0.0


func _timer_cells(game) -> Array:
	_timers_age += game.get_process_delta_time()
	if _timers_version != version or _timers_age > 1.0:
		_timers_version = version
		_timers_age = 0.0
		_timers.clear()
		var w: VoxelWorld = game.world
		for p in cells:
			if Data.block(w.get_block(p)).has("timer"):
				_timers.append(p)
	return _timers
