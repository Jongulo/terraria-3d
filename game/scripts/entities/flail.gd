class_name Flail
extends Node3D
## Terraria's flails (projectile AI 15, Projectile.AI_015_Flails), in its
## pixels (16 a block, like the other weapons) and ticks:
##   spinning  while you hold the use button it whirls round you (Terraria's
##             circle round the player, here over your head), 5 turns a
##             second; after 12 ticks it hits anything within 55 px of you
##             that you can see, each enemy every 15 ticks, for 1.2x damage
##             and 0.35x knockback
##   launched  let go and it flies at your aim at its launch speed (plus your
##             own), for its launch time; 2x damage. A block sends it into
##             a ricochet (bouncing off at 0.4, falling 0.6 px/tick² for 15
##             ticks, then pulled back)
##   retracting  slows (x0.98 a tick) and accelerates back to you; 2x damage.
##             Ten bounces off blocks and it's pulled back through them
##   dropped   click while it's out and it drops (0.8 px/tick², stopping on
##             the ground) and stays while you hold the button, half
##             knockback; let go (or walk too far) and it's pulled back
##   pulled back  straight to you through blocks, faster; caught when it's
##             close or would pass you
## Knockback always pushes away from you. Melee speed makes every speed
## faster. Its head, chain and hitbox are drawn to the player's pixels (the
## Sunfury's head two thirds your height, as in Terraria); the chain's links
## shrink near your eye, like the item in your hand. Each flail's numbers (launch time and speed, return speeds, spin
## radius) are Terraria's, in items.json "flail".

enum State { SPIN = 0, LAUNCH = 1, RETRACT = 2, FORCED = 4, RICOCHET = 5, DROP = 6 }

const PX := 16.0
const TICK := 1.0 / 60.0
## Terraria's defaults (AI_015_Flails' locals), overridden per flail.
const DEFAULTS := {"launch_time": 10, "launch_speed": 24.0, "max_retract": 16.0, "max_forced": 48.0,
		"spin_radius": 30, "spin_cooldown": 15}
const MAX_LAUNCH := 800.0
const RETRACT_ACCEL := 3.0
const FORCED_ACCEL := 6.0
const HIT_COOLDOWN := 10
## Terraria's ricochet lasts the default launch time + 5 (whatever the flail).
const RICOCHET_TICKS := 15
## Spinning hits reach 55 px from you, squashed vertically (0.8 above you,
## 0.4 below), and start after 12 ticks of spin.
const SPIN_REACH := 55.0
const SPIN_WARMUP := 12
## Terraria: killed more than 900 px from you.
const MAX_DISTANCE := 900.0
## 10 pi radians every 60 ticks.
const SPIN_RATE := PI * 10.0 / 60.0
## The spin's height above your middle (over your head, in sight).
const SPIN_HEIGHT := 1.0
## Chain links closer to your eye than this (blocks) are drawn thinner.
const NEAR_EYE := 1.5

var player: Player
var def: Dictionary
var state := State.SPIN
var timer := 0
## Px a tick, y up.
var velocity := Vector3.ZERO
var bounces := 0
var spin_ticks := 0
var sprite := EntitySprite.new()
var _half := 0.6
var _acc := 0.0
var _angle := 0.0
var _rotation := 0.0
var _last := Vector3.ZERO
var _cooldowns := {}  # npc -> ticks until it can be hit again
var _chain := MeshInstance3D.new()
var _chain_mesh := ImmediateMesh.new()
var _links: Array = []  # [texture, size (blocks), material] per chain kind
## The Flaming Mace in water turns into a plain Mace (Terraria swaps it).
var _doused := false


## Blocks per sprite pixel: the player's.
static func pixel() -> float:
	return PaperDoll.player_pixel_size()


func setup(p: Player, item: Dictionary) -> void:
	player = p
	def = item
	_half = float(_f().get("size", 22)) * pixel() * 0.5
	_set_look(def.get("projectile", "Mace"))
	add_child(sprite)
	_chain.mesh = _chain_mesh
	_chain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_chain.top_level = true
	_chain.extra_cull_margin = 64.0
	add_child(_chain)


func _f() -> Dictionary:
	return def.get("flail", {})


## One of the flail's numbers (DEFAULTS, or its own).
func num(key: String) -> float:
	return float(_f().get(key, DEFAULTS[key]))


func _set_look(projectile: String) -> void:
	var id: int = Assets.ids.ProjectileID.get(projectile, 947)
	var tex := Assets.texture("Images/Projectile_%d" % id)
	var size := Vector2(tex.get_width(), tex.get_height()) * float(_f().get("scale", 1.0)) * pixel()
	sprite.setup(tex, 1, size, true, true)
	_links.clear()
	var chain: Array = _f().get("chain", ["Chain41"])
	if _doused:
		chain = ["Chain41"]
	for c in chain:
		var t := Assets.texture("Images/" + str(c))
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = t
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		_links.append([t, Vector2(t.get_width(), t.get_height()) * pixel(), m])


func melee_k() -> float:
	return 1.0 + player.stat("melee_speed") / 100.0


func launch_speed() -> float:
	return num("launch_speed") * melee_k()


## Where it's tied to you (Terraria's MountedCenter): your middle.
func anchor() -> Vector3:
	return player.center()


## Where the chain starts: your hand.
func hand() -> Vector3:
	return player.camera.global_transform * Viewmodel.hand_position()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or not player.alive or player.held().get("internal", "") != def.get("internal", ""):
		queue_free()
		return
	_last = global_position
	_acc += delta
	while _acc >= TICK:
		_acc -= TICK
		_tick()
		if is_queued_for_deletion():
			return
	var game := Game.current
	# Turns with its motion (Terraria: its velocity's angle plus a spin).
	var moved := global_position - _last
	if moved.length() > 0.02:
		_rotation = EntitySprite.facing_angle(player.camera, moved) - PI * 0.5
	sprite.set_rotation_angle(_rotation)
	sprite.update_light(game.world, game.sky, global_position)
	_draw_chain(game)


func _tick() -> void:
	var game := Game.current
	var a := anchor()
	if global_position.distance_to(a) > MAX_DISTANCE * melee_k() / PX:
		queue_free()
		return
	var liquid: Vector2i = game.world.get_liquid(Vector3i(global_position.floor()))
	if def.get("projectile") == "FlamingMace" and not _doused and liquid.y > 0 and liquid.x != 2:
		_doused = true
		_set_look("Mace")
	var k := melee_k()
	var max_retract := num("max_retract") * k
	var max_forced := num("max_forced") * k
	var to_player := (a - global_position).normalized()
	var dist := global_position.distance_to(a) * PX
	var collide := true
	match state:
		State.SPIN:
			collide = false
			if not player.use_down():
				# Let go: thrown at your aim, with your own speed.
				state = State.LAUNCH
				timer = 0
				velocity = player.forward() * launch_speed() + player.velocity * PX / 60.0
				global_position = hand()
				_cooldowns.clear()
				Audio.play_at("Item_1", global_position, 0.6)
			else:
				spin_ticks += 1
				_angle += SPIN_RATE
				var r := num("spin_radius") / PX
				global_position = a + Vector3(cos(_angle) * r, SPIN_HEIGHT, sin(_angle) * r)
				velocity = Vector3.ZERO
		State.LAUNCH:
			var done := timer >= int(num("launch_time")) or dist >= MAX_LAUNCH
			timer += 1
			if player.use_down():
				_drop()
			elif done:
				state = State.RETRACT
				timer = 0
				velocity *= 0.3
		State.RETRACT:
			if dist <= max_retract:
				queue_free()
				return
			if player.use_down():
				_drop()
			else:
				velocity *= 0.98
				velocity = velocity.move_toward(to_player * max_retract, RETRACT_ACCEL * k)
		State.FORCED:
			collide = false
			if dist <= max_forced:
				queue_free()
				return
			velocity *= 0.98
			velocity = velocity.move_toward(to_player * max_forced, FORCED_ACCEL * k)
			# Would pass you: caught.
			var next := global_position + velocity / PX
			if to_player.dot((a - next).normalized()) < 0.0:
				queue_free()
				return
		State.RICOCHET:
			timer += 1
			if timer > RICOCHET_TICKS:
				state = State.DROP
				timer = 0
			else:
				velocity.y -= 0.6
				velocity.x *= 0.95
				velocity.z *= 0.95
		State.DROP:
			if not player.use_down() or dist > launch_speed() * num("launch_time") + 160.0:
				state = State.FORCED
				timer = 0
			else:
				velocity.y -= 0.8
				velocity.x *= 0.95
				velocity.z *= 0.95
	if state != State.SPIN:
		_move(game, collide and state != State.FORCED)
	_dust(game)
	game.cut_tiles_at(global_position, _half)
	_check_hits(game)


func _drop() -> void:
	state = State.DROP
	timer = 0
	velocity *= 0.2


## Moves a tick; blocks bounce it (Terraria's AI_015_HandleMovementCollision):
## at 0.4 launched or ricocheting, not at all dropped, 0.2 otherwise. A
## launched flail that hits a block ricochets; ten bounces pull it back.
func _move(game, collide: bool) -> void:
	if not collide:
		global_position += velocity / PX
		return
	var bottom := global_position - Vector3(0, _half, 0)
	var r: Dictionary = game.world.move_aabb(bottom, Vector3(_half, _half * 2.0, _half), velocity / PX, 0.0, false)
	global_position = r.position + Vector3(0, _half, 0)
	var blocked: Vector3i = r.blocked
	if blocked == Vector3i.ZERO:
		return
	var bounce := 0.2
	if state in [State.LAUNCH, State.RICOCHET]:
		bounce = 0.4
	elif state == State.DROP:
		bounce = 0.0
	var hard := false
	for axis in 3:
		if blocked[axis]:
			hard = hard or absf(velocity[axis]) > 4.0
			velocity[axis] = -velocity[axis] * bounce
			bounces += 1
	if state == State.LAUNCH:
		state = State.RICOCHET
		timer = 0
		hard = true
		_cooldowns.clear()
	if hard:
		var b := Vector3i((global_position + velocity.normalized() * (_half + 0.1)).floor())
		var id: int = game.world.get_block(b)
		if id != 0:
			game.dust.tile_dust(b, id, false)
		Audio.play_at("Dig_0", global_position, 0.6)
	if state == State.RETRACT and bounces >= 10:
		state = State.FORCED
		timer = 0


## Terraria's flail dust (AI_015_Flails_Dust): items.json "flail.dust" {id,
## every (1 in), launched (1 in, while thrown), scale, speed (x its velocity)}.
func _dust(game) -> void:
	var d: Dictionary = _f().get("dust", {})
	if d.is_empty() or _doused:
		return
	var every := int(d.get("launched", d.get("every", 1))) if state == State.LAUNCH else int(d.get("every", 1))
	if randi() % maxi(every, 1) != 0:
		return
	var at := global_position + Vector3(randf_range(-_half, _half), randf_range(-_half, _half), randf_range(-_half, _half))
	# Dust moves in Terraria's 24 px a block.
	game.dust.spawn(int(d.id), at, velocity * 1.5 * float(d.get("speed", 0.0)), float(d.get("scale", 1.0)))


## The damage and knockback it does now: x1.2 and x0.35 spinning, x2 thrown
## out or coming back, half knockback dropped.
func damage_mult() -> float:
	match state:
		State.SPIN: return 1.2
		State.LAUNCH, State.RETRACT: return 2.0
	return 1.0


func knockback_mult() -> float:
	match state:
		State.SPIN: return 0.35
		State.DROP: return 0.5
	return 1.0


func _check_hits(game) -> void:
	for n in _cooldowns.keys():
		_cooldowns[n] -= 1
		if _cooldowns[n] <= 0 or not is_instance_valid(n):
			_cooldowns.erase(n)
	if state == State.SPIN and spin_ticks <= SPIN_WARMUP:
		return
	for npc in game.npcs():
		if _cooldowns.has(npc) or npc.def.ai == "town" or npc.dont_take_damage or (npc.def.get("invulnerable", false) and npc.def.ai != "dummy"):
			continue
		if not (_spin_reaches(npc, game) if state == State.SPIN else npc.overlaps_box(global_position - Vector3(0, _half, 0), Vector3(_half, _half * 2.0, _half))):
			continue
		var away: Vector3 = npc.center() - player.center()
		away.y = 0.0
		var dir := away.normalized() if away.length() > 0.01 else player.forward()
		npc.hit(int(round(player.weapon_damage(def) * damage_mult())), float(def.get("knockback", 0)) * knockback_mult(), dir,
				player.crit_chance(def), player.armor_penetration(def))
		_cooldowns[npc] = int(num("spin_cooldown")) if state == State.SPIN else HIT_COOLDOWN
		var fire: Array = def.get("on_fire", [])
		if not fire.is_empty() and not _doused and randi() % int(fire[0]) == 0:
			npc.ignite(randi_range(int(fire[1]), int(fire[2])) / 60.0)


## Spinning, it hits what's near you (Terraria's ellipse round the player,
## 55 px, squashed to 0.8 above you and 0.4 below) that you can see.
func _spin_reaches(npc, game) -> bool:
	var a := anchor()
	var lo: Vector3 = npc.global_position - Vector3(npc.half.x, 0, npc.half.z)
	var hi: Vector3 = npc.global_position + Vector3(npc.half.x, npc.half.y, npc.half.z)
	var off: Vector3 = a.clamp(lo, hi) - a
	off.y /= 0.8 if off.y >= 0.0 else 0.4
	if off.length() * PX >= SPIN_REACH:
		return false
	var to: Vector3 = npc.center() - player.camera.global_position
	return float(game.world.raycast(player.camera.global_position, to.normalized(), to.length()).get("distance", INF)) >= to.length() - 0.5


## The chain from your hand to the head: Terraria's links (its sprite, one
## after another, each its height apart), turned to face you. The Flaming
## Mace's first links glow (4 white-hot, 2 at least 55% bright).
func _draw_chain(game) -> void:
	_chain_mesh.clear_surfaces()
	if _links.is_empty():
		return
	var head := global_position
	var from := hand()
	var span := head - from
	var length := span.length()
	if length < 0.05:
		return
	var axis := span / length
	var cam := player.camera.global_position
	var l: Color = game.world.get_light((head + from) * 0.5)
	var sky: Vector3 = Vector3(l.a, l.a, l.a) * game.sky.sky_light * Vector3(game.sky.sky_tint.r, game.sky.sky_tint.g, game.sky.sky_tint.b)
	var lit := Color(maxf(l.r, sky.x), maxf(l.g, sky.y), maxf(l.b, sky.z))
	lit = Color(lit.r * lit.r, lit.g * lit.g, lit.b * lit.b)
	# Links from the head toward your hand, like Terraria draws them.
	var per_kind := {}
	var step: float = _links[0][1].y
	var n := int(ceil(length / step))
	for i in n:
		var kind := 0
		if _links.size() >= 3:
			kind = 2 if i < 4 else (1 if i < 6 else 0)
		per_kind.get_or_add(kind, []).append(i)
	for kind in per_kind:
		var link: Array = _links[mini(kind, _links.size() - 1)]
		var size: Vector2 = link[1]
		var mat: StandardMaterial3D = link[2]
		match kind:
			2: mat.albedo_color = Color.WHITE
			1: mat.albedo_color = Color(maxf(lit.r, 0.55), maxf(lit.g, 0.55), maxf(lit.b, 0.55))
			_: mat.albedo_color = lit
		_chain_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
		for i in per_kind[kind]:
			var mid: Vector3 = head - axis * (step * (float(i) + 0.5))
			# Near your eye the links shrink (to 30% at the hand), or the
			# first few would fill the view.
			var near := clampf(mid.distance_to(cam) / NEAR_EYE, 0.3, 1.0)
			var side := axis.cross(cam - mid).normalized() * size.x * 0.5 * near
			var up := axis * size.y * 0.5
			var q := [mid - side + up, mid + side + up, mid + side - up, mid - side - up]
			var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
			for j in [0, 1, 2, 0, 2, 3]:
				_chain_mesh.surface_set_uv(uv[j])
				_chain_mesh.surface_add_vertex(q[j])
		_chain_mesh.surface_end()
