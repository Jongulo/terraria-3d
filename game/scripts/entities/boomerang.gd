class_name Boomerang
extends Node3D
## Terraria's boomerangs (projectile AI 3, Projectile.AI_003_Boomerang): thrown
## from your hand along your aim at the item's shoot speed, it flies straight
## for 30 ticks, or until it hits a block (it bounces off) or an enemy (it
## turns round), then comes back to you through blocks, steering toward you
## axis by axis at its return speed and acceleration (Terraria: 9 and 0.4
## pixels a tick for most; the Flamarang 20 and 1.5...), and is caught when
## it reaches you. Coming back it hits everything it passes; each enemy at
## most every 10 ticks (Terraria's immunity after a hit). Melee speed throws
## it faster and brings it back faster (Terraria: 1.5x the bonus, at most 10x).
## The Bloody Machete doesn't turn round on its own: after 10 ticks it drops
## like a thrown machete until it hits something. Spinning sprite, Terraria's.

## Terraria pixels per block; ticks a second.
const PX := 16.0
const TICK := 1.0 / 60.0
## Terraria: 30 ticks out before it turns round.
const OUT_TICKS := 30
const HIT_COOLDOWN := 10.0 / 60.0
## Terraria kills one more than 3000 px from you.
const MAX_DISTANCE := 3000.0 / PX
## Close enough to catch (Terraria: its hitbox touching yours).
const CATCH := 0.7
## Terraria spins it 0.4 radians a tick.
const SPIN := 0.4 * 60.0

var player: Player
var def: Dictionary
## Velocity in blocks a second.
var velocity := Vector3.ZERO
var returning := false
var ticks := 0
var sprite := EntitySprite.new()
var radius := 0.4
var _acc := 0.0
var _angle := 0.0
var _cooldowns := {}  # npc -> seconds


func setup(p: Player, item: Dictionary) -> void:
	player = p
	def = item
	var id: int = Assets.ids.ProjectileID.get(def.get("projectile", "WoodenBoomerang"), 52)
	var tex := Assets.texture("Images/Projectile_%d" % id)
	var size := Vector2(tex.get_width(), tex.get_height()) / PX
	radius = maxf(size.x, size.y) * 0.5
	sprite.setup(tex, 1, size, true, true)
	add_child(sprite)


## The boomerang's numbers, with melee speed: throw speed (blocks a second),
## return speed and acceleration (blocks a second, and per second a tick).
func melee_bonus() -> float:
	return player.stat("melee_speed") / 100.0


func throw_speed() -> float:
	return float(def.boomerang.speed) * (1.0 + melee_bonus()) * 60.0 / PX


func _return_k() -> float:
	return clampf(1.0 + 1.5 * melee_bonus(), 1.0, 10.0)


func return_speed() -> float:
	return float(def.boomerang.get("return", [9.0, 0.4])[0]) * _return_k() * 60.0 / PX


func return_accel() -> float:
	return float(def.boomerang.get("return", [9.0, 0.4])[1]) * _return_k() * 60.0 / PX


## Where it comes back to: your middle.
func catch_point() -> Vector3:
	return player.camera.global_position + Vector3(0, -0.45, 0)


func throw(from: Vector3, dir: Vector3) -> void:
	global_position = from
	velocity = dir.normalized() * throw_speed()


## Runs Terraria's AI tick by tick (it steers by fixed steps a tick).
func _physics_process(delta: float) -> void:
	var game := Game.current
	if not is_instance_valid(player) or not player.alive:
		queue_free()
		return
	_acc += delta
	while _acc >= TICK and not is_queued_for_deletion():
		_acc -= TICK
		_tick(game)
	_angle += SPIN * delta
	sprite.set_rotation_angle(_angle)
	sprite.update_light(game.world, game.sky, global_position)


func _tick(game) -> void:
	ticks += 1
	for n in _cooldowns.keys():
		_cooldowns[n] -= TICK
		if _cooldowns[n] <= 0.0 or not is_instance_valid(n):
			_cooldowns.erase(n)
	if not returning:
		var fall: int = int(def.boomerang.get("fall", 0))
		if fall > 0:
			if ticks >= fall:
				# Terraria: 0.5 px a tick faster down each tick (at most 16),
				# 5% slower along.
				velocity.y = maxf(velocity.y - 0.5 * 3600.0 / PX * TICK, -16.0 * 60.0 / PX)
				velocity.x *= 0.95
				velocity.z *= 0.95
		elif ticks >= OUT_TICKS:
			returning = true
		_move_out(game)
	else:
		_steer_home()
		global_position += velocity * TICK
		if global_position.distance_to(catch_point()) < CATCH:
			queue_free()
			return
		if global_position.distance_to(catch_point()) > MAX_DISTANCE:
			queue_free()
			return
	_check_hits(game)


## Going out it stops at blocks: bounces off and turns round.
func _move_out(game) -> void:
	var step := velocity * TICK
	for axis in 3:
		if step[axis] == 0.0:
			continue
		var to := global_position
		to[axis] += step[axis]
		var edge := to
		edge[axis] += signf(step[axis]) * radius * 0.5
		if game.world.is_solid(Vector3i(edge.floor())):
			velocity[axis] = -velocity[axis]
			returning = true
			Audio.play_at("Dig_*", global_position, 0.3)
		else:
			global_position = to


## Terraria's homing: each axis moves toward the velocity that would bring
## it straight back at the return speed by the acceleration, twice as hard
## while it's still going the wrong way.
func _steer_home() -> void:
	var to := catch_point() - global_position
	var want := to.normalized() * return_speed() if to.length() > 0.001 else Vector3.ZERO
	var a := return_accel()
	for axis in 3:
		if velocity[axis] < want[axis]:
			velocity[axis] += a
			if velocity[axis] < 0.0 and want[axis] > 0.0:
				velocity[axis] += a
		elif velocity[axis] > want[axis]:
			velocity[axis] -= a
			if velocity[axis] > 0.0 and want[axis] < 0.0:
				velocity[axis] -= a


func _check_hits(game) -> void:
	game.cut_tiles_at(global_position, radius)
	for npc in game.npcs():
		if _cooldowns.has(npc) or npc.def.ai == "town":
			continue
		if npc.dont_take_damage or (npc.def.get("invulnerable", false) and npc.def.ai != "dummy"):
			continue
		if not npc.overlaps_point(global_position, radius):
			continue
		npc.hit(player.weapon_damage(def), float(def.get("knockback", 0)), velocity.normalized(), player.crit_chance(def), player.armor_penetration(def))
		_cooldowns[npc] = HIT_COOLDOWN
		if not returning:
			# Terraria: it turns round on the first enemy it hits.
			returning = true
			velocity = -velocity
