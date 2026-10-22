class_name Traps
extends RefCounted
## Terraria's traps (worldgen: traps.rs): a pressure plate wired to a dart
## trap, a boulder or explosives ("trap_wire" decorations: the plate, the
## target's offset in the style). Stepping on a plate (Terraria's gray, brown
## and orange: players only) sets off all it's wired to (Wiring.HitSwitch):
## - Dart trap: a Poison Dart out of its face (12 px a tick, 20 damage; it
##   poisons you 10 s), 200 ticks at least between shots.
## - Boulder: the actuated stone under it drops away and the Boulder falls
##   and rolls (Projectile "Boulder").
## - Explosives: they blow up (Terraria's 500-damage blast, 260 px across),
##   blocks and all.

## Plate key -> the cells it's wired to.
var wires := {}
var _cooldown := {}
var _on_plate := ""

const DART_SPEED := 12.0 * 3.75
const DART_DAMAGE := 20
const DART_COOLDOWN := 200.0 / 60.0
## Terraria's Explosives: projectile 108 (500 damage, 260 px across).
const EXPLOSION := {"radius": 130.0 / 24.0, "tiles": true}
const EXPLOSIVES_DAMAGE := 500


func setup(world: VoxelWorld) -> void:
	wires.clear()
	for d in world.get_decorations():
		if d.kind == "trap_wire":
			var s := int(d.style)
			var to := Vector3i(d.pos) + Vector3i((s & 127) - 64, (s >> 14) - 64, ((s >> 7) & 127) - 64)
			var k := Chests.key(d.pos)
			if not wires.has(k):
				wires[k] = []
			wires[k].append(to)


## Each physics frame: the plate under the player's feet, when they first
## step on it.
func update(game, delta: float) -> void:
	for k in _cooldown.keys():
		_cooldown[k] -= delta
		if _cooldown[k] <= 0.0:
			_cooldown.erase(k)
	var p = game.player
	if not p.alive or p.flying:
		_on_plate = ""
		return
	var cell := Vector3i(p.global_position.floor())
	var b: Dictionary = Data.block(game.world.get_block(cell))
	var k := Chests.key(cell) if b.get("pressure_plate", "") == "player" else ""
	if k != "" and k != _on_plate:
		trigger(game, cell)
	_on_plate = k


## A plate pressed: everything wired to it goes off.
func trigger(game, plate: Vector3i) -> void:
	Audio.play_at("Mech_0", Vector3(plate) + Vector3(0.5, 0.1, 0.5), 0.6)
	for to in wires.get(Chests.key(plate), []):
		var b: Dictionary = Data.block(game.world.get_block(to))
		match b.get("trap", ""):
			"dart":
				_shoot_dart(game, to)
			"boulder":
				_drop_boulder(game, to)
			"explosives":
				game.world.set_block(to, 0)
				game.explode(Vector3(to) + Vector3(0.5, 0.5, 0.5), EXPLOSIVES_DAMAGE, 10.0, EXPLOSION)


func _shoot_dart(game, at: Vector3i) -> void:
	var k := Chests.key(at)
	if _cooldown.has(k):
		return
	_cooldown[k] = DART_COOLDOWN
	var facing: int = int(game.block_rotations.get(k, 0))
	var f: Vector2i = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)][posmod(facing, 4)]
	var dir := Vector3(f.x, 0, f.y)
	# Terraria doubles hostile shots' damage on you.
	game.spawn_projectile("PoisonDart", Vector3(at) + Vector3(0.5, 0.5, 0.5) + dir * 0.6, dir * DART_SPEED, DART_DAMAGE * 2, 2.0, 0.0, 0.0, 0.5, false)
	Audio.play_at("Item_5", Vector3(at) + Vector3(0.5, 0.5, 0.5), 0.6)


## The plug of actuated stone under the boulder drops away; the boulder
## falls out of its pocket (Terraria's tile with nothing under it becomes the
## rolling projectile).
func _drop_boulder(game, at: Vector3i) -> void:
	var w: VoxelWorld = game.world
	var q := at + Vector3i.DOWN
	while Data.block(w.get_block(q)).get("actuated", false):
		w.set_block(q, 0)
		q += Vector3i.DOWN
	w.set_block(at, 0)
	# Boulder: 70 damage (Terraria's tile drop; doubled on you as hostile).
	var b: Projectile = game.spawn_projectile("Boulder", Vector3(at) + Vector3(0.5, 0.5, 0.5), Vector3.ZERO, 70, 10.0, 0.0, 0.0, 1.0, false)
	b.boulder = true
