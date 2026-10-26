class_name Counterweight
extends Node3D
## A yoyo's counterweight (Terraria's Player.Counterweight and
## AI_099_1_Counterweights, projectiles 556-561): when your yoyo hits an
## enemy with a counterweight on, one flies out from you toward it at 16
## px/tick (24 px a block, as the NPCs here), with the hit's damage and
## (knockback + 6) / 2. It flies free inside 125 px of you, turned back in at
## that edge, goes for the nearest enemy it can see within 800 px (steering
## 7:1 toward 6 px/tick), its speed kept between 9 and 12 px/tick, and hits
## each enemy every 10 ticks. Once the yoyo is gone it flies back to you
## (18 px/tick) and is gone within 40 px.

const PX := 24.0
const TICK := 1.0 / 60.0
const TETHER := 125.0
const TOP := 12.0
const LEAST := 9.0
const HIT_TICKS := 10

var player: Player
var damage := 0
var knockback := 0.0
## Px a tick, y up.
var vel := Vector3.ZERO
var returning := false
var sprite := EntitySprite.new()
var _acc := 0.0
var _cooldowns := {}  # npc -> ticks left
var _angle := 0.0


func setup(p: Player, kind: String, toward: Vector3, dmg: int, kb: float) -> void:
	player = p
	damage = dmg
	knockback = (kb + 6.0) / 2.0
	var id: int = Assets.ids.ProjectileID.get(kind, 557)
	var tex := Assets.texture("Images/Projectile_%d" % id)
	sprite.setup(tex, 1, Vector2(tex.get_width(), tex.get_height()) / PX, true, true)
	add_child(sprite)
	var dir := (toward - p.center()).normalized()
	vel = (dir if dir != Vector3.ZERO else p.forward()) * 16.0


func _physics_process(delta: float) -> void:
	var game := Game.current
	if not is_instance_valid(player) or not player.alive:
		queue_free()
		return
	if not player.yoyo_out() or player.yoyo.returning:
		returning = true
	_acc += delta
	while _acc >= TICK:
		_acc -= TICK
		if not _tick(game):
			queue_free()
			return
	_angle += 0.5 * delta * 60.0
	sprite.set_rotation_angle(_angle)
	sprite.update_light(game.world, game.sky, global_position)


func _tick(game) -> bool:
	var you: Vector3 = player.center()
	var to := (you - global_position) * PX
	if returning:
		# Back to you through the blocks (ai[0] -1).
		var d := to.length()
		if d < 40.0 or d > 2000.0:
			return false
		vel = (vel * 11.0 + to / d * TOP * 1.5) / 12.0
		global_position += vel / PX
		return true
	var reach := TETHER * (1.25 + 10.0 / TETHER if player.has_effect("yoyo_string") else 1.0)
	# At the edge of its reach it's turned back in.
	if to.length() > reach:
		var out := -to.normalized()
		global_position = you + out * reach / PX
		if vel.dot(out) > 0.0:
			vel -= out * vel.dot(out) * 2.0
	# The nearest enemy it can see within 800 px (and inside its reach of you).
	var best = null
	var best_d := 800.0
	for npc in game.npcs():
		if npc.def.ai in ["town", "dummy"] or npc.untouchable or npc.dont_take_damage or npc.is_critter():
			continue
		var d: float = (npc.center() - global_position).length() * PX
		if d < best_d and (npc.center() - you).length() * PX < reach * 0.9 \
				and float(game.world.raycast(global_position, (npc.center() - global_position).normalized(), d / PX).get("distance", INF)) >= d / PX - 0.5:
			best_d = d
			best = npc
	if best != null:
		vel = (vel * 7.0 + (best.center() - global_position).normalized() * 6.0) / 8.0
	if vel.length() > TOP:
		vel = vel.normalized() * TOP
	elif vel.length() < LEAST:
		vel = (vel.normalized() if vel != Vector3.ZERO else Vector3.UP) * LEAST
	# Blocks turn it (tileCollide).
	var w: VoxelWorld = game.world
	for axis in 3:
		var to_pos := global_position
		to_pos[axis] += vel[axis] / PX
		var edge := to_pos
		edge[axis] += signf(vel[axis]) * 0.2
		if w.is_solid(Vector3i(edge.floor())):
			vel[axis] = -vel[axis]
		else:
			global_position = to_pos
	for npc in _cooldowns.keys():
		_cooldowns[npc] -= 1
		if _cooldowns[npc] <= 0 or not is_instance_valid(npc):
			_cooldowns.erase(npc)
	for npc in game.npcs():
		if _cooldowns.has(npc) or npc.dont_take_damage or (npc.def.get("invulnerable", false) and npc.def.ai != "dummy"):
			continue
		if npc.overlaps_point(global_position, 0.25):
			npc.hit(damage, knockback, vel.normalized(), player.crit_chance(player.yoyo.def if player.yoyo_out() else {}))
			_cooldowns[npc] = HIT_TICKS
	return true
