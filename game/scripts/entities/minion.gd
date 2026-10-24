class_name Minion
extends Node3D
## Your companions: minions from summon staffs (Terraria's Projectile.minion,
## a minion slot each) and pets. Each runs its Terraria projectile AI tick by
## tick, in its pixels (24 a block, as the NPCs here) and ticks; Terraria's
## "left or right of you" becomes toward or away from a point on the ground.
## Where Terraria lines minions up behind you, here they line up beside you,
## right and left in turn (first person, you'd never see them behind you).
##   ground: AI_026 on foot (the Baby Slime, the Baby Dinosaur, the Baby Face
##     Monster). It walks after you (a minion to its place in the line beside
##     you, 40 px apart), jumps what's in its way (higher walls, higher
##     jumps), and when you get too far ahead (500 px, more for a minion
##     that's fighting) or 300 px above or below it, it flies back to you
##     through the blocks until it's near you and you're standing on
##     something. The Baby Slime hops as it goes, goes for the nearest enemy
##     within 300 px it can see (150 underground; 800 once fighting, jumping
##     up to it) and hurts what it touches (each enemy every 12 ticks, all
##     Baby Slimes together).
##   eater / skull / fish: AI_026's fliers (the Baby Eater, the Baby
##     Skeletron Head, the Zephyr Fish and Baby Hornet: speed, accel [mid,
##     near, far] px/tick² their own): through the blocks after you,
##     steering each axis toward a speed at you.
##   swarm: AI_062 (the Hornet, the Imp): flies over you (the Imp in line
##     beside you), to an enemy it can see within 2000 px, shooting at it
##     (the Hornet's stingers every 90 ticks or so, the Imp's fireballs every
##     60); back to you through the blocks when 500 px off (1000 fighting).
##   bird: AI_158 (the Finch): sits on your head, darts at enemies within
##     800 px and pecks them (each every 15 ticks).
##   orb: AI_011 (the Shadow Orb): drifts after you at 3 px a tick, shining.
##   walker: AI_067 on foot (the Flinx, the Vampire Frog; the Crimson Heart
##     and the Friendly Boulder pets). It walks to its place (a minion beside
##     you, a pet behind you), hopping onto what's in its way and up toward
##     its goal, flies back like the others when 500 px off (the pets 200),
##     and a minion runs at the nearest enemy within 800 px of it or you that
##     it can see: the Flinx bowls into it (each enemy every 10 ticks, all
##     Flinxes together), the Vampire Frog leaps at it with a 20-tick
##     attack, hurting only in the middle of it, and rests 60 ticks after.
## Right-click an enemy holding a summon staff and every minion goes for it
## first (Terraria's MinionAttackTargetNPC; again on it to let go).

const PX := 24.0
const TICK := 1.0 / 60.0

## Each companion's numbers, by its ProjectileID name: ai, hitbox [w, h] px,
## its sheet's frames (Main.projFrames), buff (BuffID name), slot (a minion's
## slots), and per AI: near (px it stops short of you), walk [accel, top
## speed] px/tick, walk_frames / fly_frames [first, last], faces "right" (its
## art faces right; Terraria's others face left), light.
const KINDS := {
	"BabySlime": {"ai": "ground", "size": [24, 16], "frames": 12, "buff": "BabySlime", "slot": 1, "hops": true,
		"walk": [0.2, 6.0], "contact": 12},
	"BabyDino": {"ai": "ground", "size": [34, 34], "frames": 13, "buff": "BabyDinosaur", "near": 85,
		"walk": [0.08, 6.5], "walk_frames": [2, 8], "fly_frames": [9, 12]},
	"BabyFaceMonster": {"ai": "ground", "size": [34, 34], "frames": 12, "buff": "BabyFaceMonster", "near": 85,
		"walk": [0.08, 6.5], "walk_frames": [2, 7], "fly_frames": [8, 11]},
	"BabyEater": {"ai": "eater", "size": [34, 34], "frames": 2, "buff": "BabyEater"},
	"BabySkeletronHead": {"ai": "skull", "size": [42, 42], "frames": 1, "buff": "BabySkeletronHead"},
	"ZephyrFish": {"ai": "fish", "size": [26, 26], "frames": 4, "buff": "ZephyrFish"},
	# The Nectar's Baby Hornet: the Zephyr Fish's flight, faster (14 px a
	# tick; 0.4 px/tick², 0.1 near you, 0.6 far off), tipped as it goes.
	"BabyHornet": {"ai": "fish", "size": [26, 26], "frames": 4, "buff": "BabyHornet", "speed": 14.0, "accel": [0.4, 0.1, 0.6], "tilt": true},
	"Hornet": {"ai": "swarm", "size": [24, 26], "frames": 3, "buff": "HornetMinion", "slot": 1,
		"shot": "HornetStinger", "shot_speed": 10.0, "shot_sound": "Item_17"},
	"FlyingImp": {"ai": "swarm", "size": [34, 26], "frames": 8, "buff": "ImpMinion", "slot": 1,
		"shot": "ImpFireball", "shot_speed": 22.0, "shot_sound": "Item_20"},
	"BabyBird": {"ai": "bird", "size": [10, 10], "frames": 5, "buff": "BabyBird", "slot": 1, "faces": "right", "contact": 15},
	"ShadowOrb": {"ai": "orb", "size": [26, 26], "frames": 1, "buff": "ShadowOrb", "scale": 0.8, "light": [0.54, 0.09, 0.9]},
	# AI_067: home [px behind you past half its width, px more for each
	# minion], leash (px), walk / hunt [accel, top speed] px/tick, hop:
	# "moving" (a hop whenever it walks), "hunting" (only after an enemy),
	# "fast" (above 5 px/tick), "" (only at walls).
	"FlinxMinion": {"ai": "walker", "size": [26, 26], "frames": 12, "buff": "FlinxMinion", "slot": 1, "faces": "right",
		"contact": 10, "home": [45, 30], "leash": 500, "walk": [0.5, 4.0], "hunt": [0.65, 5.5], "hop": ""},
	"VampireFrog": {"ai": "walker", "size": [20, 30], "frames": 24, "buff": "VampireFrog", "slot": 1, "faces": "right",
		"contact": 10, "home": [35, 40], "leash": 500, "walk": [0.5, 4.0], "hunt": [0.7, 6.0], "hop": "hunting",
		"attack": [20, 60, 50]},
	"CrimsonHeart": {"ai": "walker", "size": [16, 16], "frames": 4, "buff": "CrimsonHeart", "scale": 0.8, "faces": "right",
		"home": [15, 40], "leash": 200, "walk": [0.5, 4.0], "hop": "moving", "light": [0.9, 0.1, 0.3]},
	"BoulderPet": {"ai": "walker", "size": [32, 32], "frames": 1, "buff": "BoulderPet", "faces": "right",
		"home": [15, 0], "leash": 200, "walk": [0.5, 4.0], "hop": "fast", "rolls": true},
}
## Terraria's jumps for a wall in the way (AI_026: 5.1 px/tick for a tile,
## up to 11.1 for five), and how many blocks each clears (gravity 0.4).
const JUMPS := [5.1, 7.1, 9.1, 10.1, 11.1]

var player: Player
## Its ProjectileID name, its KINDS entry and the item that summoned it.
var kind := ""
var cfg := {}
var item := {}
## Its place among your minions of its kind (Terraria's minionPos).
var index := 0
var pet := false
## Velocity in px a tick, y up.
var vel := Vector3.ZERO
## Terraria's ai[0] (0 on foot / hunting, 1 flying back to you), ai[1] (a
## shot's cooldown), localAI[0] (ticks since it last fought).
var ai0 := 0
var ai1 := 0.0
var local0 := 0.0
var frame := 0
var frame_counter := 0.0
var spin := 0.0
## Hurts what it touches now (Terraria's friendly, the Baby Slime's while
## it's fighting).
var friendly := false
## The Vampire Frog's attack (Terraria's ai[0] 2): ticks of it left, and of
## its rest after (below 0).
var attack_left := 0.0
var on_floor := false
var sprite := EntitySprite.new()
## Half width, height, half depth in blocks (move_aabb's box).
var box := Vector3.ONE
var _acc := 0.0
var _face := 1.0
## When it turns to face its target instead of the way it goes (the Imp's):
## 1 right, -1 left on your screen, 0 not.
var _face_target := 0.0
var _cooldowns := {}  # npc -> ticks left (its own, Terraria's localNPCHitCooldown)
## The physics frame each enemy can next be hurt by any of a kind
## (Terraria's idStaticNPCHitCooldown: all Baby Slimes share one).
static var _shared := {}


func setup(p: Player, proj: String, from_item: Dictionary, is_pet := false) -> void:
	player = p
	kind = proj
	cfg = KINDS[proj]
	item = from_item
	pet = is_pet
	var size: Array = cfg.size
	box = Vector3(size[0] / PX / 2.0, size[1] / PX, size[0] / PX / 2.0)
	var id: int = Assets.ids.ProjectileID.get(proj, 0)
	var tex := Assets.texture("Images/Projectile_%d" % id)
	var frames := int(cfg.frames)
	var s := float(cfg.get("scale", 1.0))
	var frame_px := Vector2(tex.get_width(), tex.get_height() / float(frames))
	sprite.setup(tex, frames, frame_px * s / PX, true, false)
	# Its middle where its hitbox's middle is (Terraria draws it there); on
	# foot its feet on the ground.
	sprite.position.y = frame_px.y * s / PX / 2.0 if cfg.ai == "ground" else box.y / 2.0
	attack_left = 0.0
	add_child(sprite)
	add_to_group("minions")


func center() -> Vector3:
	return global_position + Vector3(0, box.y / 2.0, 0)


func slots() -> float:
	return float(cfg.get("slot", 0))


## Its damage now: the staff's, with your summon damage (Terraria 1.4
## works it out again from originalDamage as your bonuses change).
func damage() -> int:
	return player.weapon_damage(item)


func _physics_process(delta: float) -> void:
	var game := Game.current
	if not is_instance_valid(player):
		queue_free()
		return
	visible = player.alive
	if not player.alive:
		return
	_acc += delta
	while _acc >= TICK and not is_queued_for_deletion():
		_acc -= TICK
		match cfg.ai:
			"ground": _ground_tick(game)
			"eater", "skull", "fish": _flier_tick(game)
			"swarm": _swarm_tick(game)
			"bird": _bird_tick(game)
			"orb": _orb_tick(game)
			"walker": _walker_tick(game)
		_contact(game)
	_draw(game)


# ------------------------------------------------------------- shared

## Your middle and feet, and the way you face (flat), in blocks.
func _you() -> Vector3:
	return player.center()


## A minion's place in the line beside you: the `place`th (from 1), right
## then left of you in turn, `step` px further out each pair, after `first`.
func _beside(place: int, step: float, first := 0.0) -> Vector3:
	var right := _facing().cross(Vector3.UP)
	var side := 1.0 if place % 2 == 1 else -1.0
	return right * side * (first + step * ceili(place / 2.0)) / PX


func _facing() -> Vector3:
	var f := player.forward()
	f.y = 0.0
	return f.normalized() if f.length() > 0.01 else Vector3.FORWARD


## Your speed in px a tick (|x| + |y| as Terraria adds them).
func _your_speed() -> float:
	var v: Vector3 = player.velocity * PX / 60.0
	return Vector2(v.x, v.z).length() + absf(v.y)


func _teleport_to_you() -> void:
	global_position = _you() - Vector3(0, box.y / 2.0, 0)
	vel = Vector3.ZERO


## Moves it `vel` for a tick, through blocks or not (stepping up a block on
## foot); a blocked axis stops.
func _move(game, collide: bool, step := 0.0) -> void:
	var motion := vel / PX
	if not collide:
		global_position += motion
		on_floor = false
		return
	var r: Dictionary = game.world.move_aabb(global_position, box, motion, step, false)
	global_position = r.position
	on_floor = r.on_floor
	var blocked: Vector3i = r.blocked
	if blocked.x:
		vel.x = 0.0
	if blocked.y:
		vel.y = 0.0
	if blocked.z:
		vel.z = 0.0


func _in_solid(game) -> bool:
	var lo := Vector3i((global_position - Vector3(box.x, 0, box.z)).floor())
	var hi := Vector3i((global_position + Vector3(box.x, box.y, box.z)).floor())
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				if game.world.is_solid(Vector3i(x, y, z)):
					return true
	return false


func _sees(game, a: Vector3, b: Vector3) -> bool:
	var to := b - a
	return to.length() < 0.01 or game.world.raycast(a, to.normalized(), to.length()).is_empty()


## Terraria's NPC.CanBeChasedBy: an enemy (not a town NPC, critter or target
## dummy) that can be hurt.
static func chaseable(npc) -> bool:
	return is_instance_valid(npc) and not npc.is_queued_for_deletion() and npc.life > 0 and npc.life_max > 5 \
			and not npc.def.ai in ["town", "dummy"] and not npc.is_critter() and not npc.def.get("invulnerable", false) \
			and not npc.untouchable and not npc.dont_take_damage


## A minion's hit (its own, or its shot's): a whip's tag on the enemy adds
## its damage (before defense) and crit chance (Terraria's
## WhipTagEffect.ModifyTaggedHit), and the Meteor Whip's waiting meteor
## falls on it (1.33x the hit, from 280 px above at 8 px a tick).
static func strike(game, npc, dmg: int, knockback: float, dir: Vector3) -> void:
	var t: Dictionary = npc.tag()
	var crit := 0.0
	if not t.is_empty():
		dmg += int(t.damage)
		crit = float(t.crit) / 100.0
		if t.get("proc", "") == "meteor":
			t.proc = ""
			# From 280 px over it, tipped up to an eighth of a turn any way.
			var tilt := Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
			var from: Vector3 = npc.center() + (Vector3.UP * 280.0 / PX).rotated(tilt, randf_range(-PI / 4.0, PI / 4.0))
			var meteor: Projectile = game.spawn_projectile("MeteorWhipMeteor", from, (npc.center() - from).normalized() * 8.0 * 60.0 / PX,
					int(dmg * 1.33), knockback, 0.0, 0.0, 1.0, true, 0.0)
			meteor.minion_shot = true
	npc.hit(dmg, knockback, dir, crit)


## The enemy you've set your minions on (right-clicking it with a summon
## staff), if it's still there, within `reach` px of `from` and in sight.
func _your_target(game, from: Vector3, reach: float):
	var t = player.minion_target
	if t == null or not chaseable(t):
		return null
	if (t.center() - from).length() * PX > reach or not _sees(game, center(), t.center()):
		return null
	return t


## Terraria's Minion_FindTargetInRange: your target first, else the nearest
## enemy within `reach` px of it (or of you) that it can see.
func _find_target(game, reach: float, of_you := false):
	var t = _your_target(game, center(), reach * 3.0)
	if t != null:
		return t
	var best = null
	var best_d := reach
	for npc in game.npcs():
		if not chaseable(npc):
			continue
		var d: float = (npc.center() - center()).length() * PX
		if of_you:
			d = minf(d, (npc.center() - _you()).length() * PX)
		if d < best_d and _sees(game, center(), npc.center()):
			best_d = d
			best = npc
	return best


## Terraria's |dx| + |dy| (here |dx| + |dy| + |dz|), in px.
static func _manhattan(a: Vector3, b: Vector3) -> float:
	var d := (a - b) * PX
	return absf(d.x) + absf(d.y) + absf(d.z)


## Steers one axis of `v` toward `want` by `accel` (half again on top when
## it's heading the other way: AI_026's flight).
static func _steer(v: float, want: float, accel: float) -> float:
	if v < want:
		v += accel
		if v < 0.0:
			v += accel * 1.5
	elif v > want:
		v -= accel
		if v > 0.0:
			v -= accel * 1.5
	return v


## Each companion pushes off others of its kind that crowd it (AI_062's
## 0.05 px/tick within its width, AI_158's).
func _spread(push: float, within: float) -> void:
	for m in get_tree().get_nodes_in_group("minions"):
		if m == self or m.kind != kind or m.player != player:
			continue
		if _manhattan(global_position, m.global_position) < within:
			var away: Vector3 = global_position - m.global_position
			vel.x += push if away.x >= 0.0 else -push
			vel.y += push if away.y >= 0.0 else -push
			vel.z += push if away.z >= 0.0 else -push


## Hurting what it touches: the Baby Slime while it's fighting (every 12
## ticks for all of them), the Finch (each its own 15).
func _contact(game) -> void:
	for n in _cooldowns.keys():
		_cooldowns[n] -= 1
		if _cooldowns[n] <= 0 or not is_instance_valid(n):
			_cooldowns.erase(n)
	if not cfg.has("contact") or not friendly:
		return
	var shared: bool = kind == "BabySlime"
	var now := Engine.get_physics_frames()
	for npc in game.npcs():
		if npc.untouchable or npc.dont_take_damage or npc.def.ai == "town" or npc.is_critter():
			continue
		var key := "%s:%d" % [kind, npc.get_instance_id()]
		if (shared and int(_shared.get(key, 0)) > now) or (not shared and _cooldowns.has(npc)):
			continue
		if not npc.overlaps_box(global_position, box):
			continue
		var dir: Vector3 = (npc.center() - center()).normalized()
		Minion.strike(game, npc, damage(), player.weapon_knockback(item), dir)
		if shared:
			_shared[key] = now + int(cfg.contact)
		else:
			_cooldowns[npc] = int(cfg.contact)


# ------------------------------------------------------------- AI_026 on foot

func _ground_tick(game) -> void:
	var you := _you()
	var to_you := (you - center()) * PX
	var dist := to_you.length()
	var fighting := not pet and local0 > 0.0
	# Too far: fly back (Terraria's 500 px, a minion 40 more for each before
	# it, 500 more while it's fighting and the Baby Slime 100 on top).
	var leash := 500.0
	if not pet:
		leash += 40.0 * index
		if local0 > 0.0:
			leash += 500.0 + (100.0 if kind == "BabySlime" else 0.0)
	if dist > 2000.0:
		_teleport_to_you()
	elif dist > leash or (absf(to_you.y) > 300.0 and not fighting):
		if (to_you.y < 0.0 and vel.y > 0.0) or (to_you.y > 0.0 and vel.y < 0.0):
			vel.y = 0.0
		ai0 = 1
	if ai0 == 1:
		_ground_fly(game, you)
		return
	_ground_walk(game, you)


## Flying back to you: through the blocks, each axis toward 10 px a tick at
## you (0.2 px/tick², half again turning round); near you (200 px) and you on
## the ground, it lands. A minion flying back drops to an enemy it sees within
## 700 px of you.
func _ground_fly(game, you: Vector3) -> void:
	var accel := 0.2
	var goal := you + _beside(1, 40.0) if not pet else you - _facing() * 40.0 / PX
	if not pet:
		var found := false
		var seen := false
		for npc in game.npcs():
			if chaseable(npc) and _manhattan(you, npc.center()) < 700.0:
				found = true
				seen = _sees(game, center(), npc.center())
				break
		if not found:
			goal = you + _beside(index + 1, 40.0)
		elif seen:
			ai0 = 0
	var d := (goal - center()) * PX
	var dist := d.length()
	if dist < 200.0 and player.on_floor and global_position.y >= player.global_position.y and not _in_solid(game):
		ai0 = 0
		vel.y = minf(vel.y, 6.0)
	var want := vel if dist < 60.0 else d * 10.0 / dist
	vel.x = _steer(vel.x, want.x, accel)
	vel.y = _steer(vel.y, want.y, accel)
	vel.z = _steer(vel.z, want.z, accel)
	_move(game, false)
	_anim_fly()


func _ground_walk(game, you: Vector3) -> void:
	var goal := you
	var near := float(cfg.get("near", 85))
	if not pet:
		# A minion goes to its place in the line beside you (Terraria's
		# 40 px each, there behind you), within 10 px.
		near = 10.0
		goal = you + _beside(index + 1, 40.0)
	var walk_to = null
	if _flat_dist(goal) > near:
		walk_to = goal
	local0 = maxf(0.0, local0 - 1.0)
	if kind == "BabySlime":
		var hunt = _slime_hunt(game)
		if hunt != null:
			walk_to = hunt
	var accel := float(cfg.walk[0])
	var top := float(cfg.walk[1])
	if not pet and _your_speed() > top:
		# Keeping up with you (Terraria: your speed, 0.3 px/tick²).
		top = _your_speed()
		accel = 0.3
	var flat := Vector2(vel.x, vel.z)
	var dir := Vector2.ZERO
	if walk_to != null:
		var to: Vector3 = walk_to - global_position
		dir = Vector2(to.x, to.z).normalized()
	if dir != Vector2.ZERO:
		var along := flat.dot(dir)
		var side := flat - dir * along
		along += accel if along < 3.5 else accel * 0.25
		flat = dir * along + side * 0.9
	else:
		flat *= 0.9
		if flat.length() < accel:
			flat = Vector2.ZERO
	if flat.length() > top:
		flat = flat.normalized() * top
	vel.x = flat.x
	vel.z = flat.y
	if on_floor and dir != Vector2.ZERO:
		var wall := _wall_ahead(game, dir)
		if wall > 0:
			vel.y = _jump_for(wall)
		elif cfg.get("hops", false):
			vel.y += 6.0
	# Gravity 0.4, at most 10 down; the Baby Slime swims up to you in water.
	var wet: bool = game.world.get_liquid(Vector3i(center().floor())).y > 0
	if cfg.get("hops", false) and wet and player.global_position.y > global_position.y and local0 == 0.0:
		if vel.y < 4.0:
			vel.y += 0.2
		if vel.y < 0.0:
			vel.y *= 0.95
	else:
		vel.y = maxf(vel.y - 0.4, -10.0)
	_move(game, true, 1.05)
	_anim_walk()


func _flat_dist(p: Vector3) -> float:
	return Vector2(p.x - global_position.x, p.z - global_position.z).length() * PX


## The Baby Slime's hunt: the nearest enemy it can see (by |dx| + |dy|), or
## failing that the nearest at all within 300 px (150 underground). Fighting
## one (within 800 px): it hurts what it touches, and jumps up to it when it's
## more than 100 px above and near. Returns where to go (null: nowhere).
func _slime_hunt(game):
	friendly = false
	var best_seen = null
	var best_seen_d := 100000.0
	var best_any = null
	var best_any_d := 100000.0
	# Your target first (Terraria's OwnerMinionAttackTargetNPC), if it can
	# see it.
	var yours = _your_target(game, center(), 100000.0)
	if yours != null:
		best_seen = yours
		best_seen_d = _manhattan(center(), yours.center())
	for npc in game.npcs():
		if yours != null or not chaseable(npc):
			continue
		var d: float = _manhattan(center(), npc.center())
		if d < best_seen_d:
			if best_seen == null and d <= best_any_d:
				best_any_d = d
				best_any = npc
			if _sees(game, center(), npc.center()):
				best_seen_d = d
				best_seen = npc
	var off := 40.0 * index
	if best_seen == null:
		var reach := 300.0 if global_position.y > game.surface_level else 150.0
		if best_any != null and best_any_d < reach + off:
			return best_any.center()
		return null
	if best_seen_d >= 800.0 + off:
		return null
	friendly = true
	local0 = 60.0
	var t: Vector3 = best_seen.center()
	var up := (t.y - center().y) * PX
	if up > 100.0 and _flat_dist(t) < 50.0 and on_floor:
		for step in [[120.0, 10.0], [210.0, 13.0], [270.0, 15.0], [310.0, 17.0], [380.0, 18.0]]:
			if up < step[0]:
				vel.y = step[1]
				break
	return t


## How many blocks of wall stand in its way (0: none), up from its feet.
func _wall_ahead(game, dir: Vector2) -> int:
	var ahead := global_position + Vector3(dir.x, 0, dir.y) * (box.x + 0.3)
	var base := Vector3i(ahead.floor())
	var mid := Vector3i((ahead + Vector3(0, box.y / 2.0, 0)).floor())
	if not game.world.is_solid(mid) and not game.world.is_solid(base):
		return 0
	var h := 0
	while h < 7 and game.world.is_solid(base + Vector3i(0, h, 0)):
		h += 1
	return h


## The least of Terraria's jumps that clears `blocks` (it rises v²/0.8 px).
static func _jump_for(blocks: int) -> float:
	for v in JUMPS:
		if v * v / 0.8 / PX >= blocks + 0.1:
			return v
	return JUMPS[-1]


func _anim_walk() -> void:
	var still := Vector2(vel.x, vel.z).length() < 0.05
	if kind == "BabySlime":
		# Hopping: frames 1-7 in the air, 0 and 5-7 on the ground.
		if not on_floor:
			frame_counter += 1
			if frame_counter > 4:
				frame_counter = 0
				frame += 1
			if frame == 0 or frame >= 8:
				frame = 1
		else:
			frame_counter += 1
			if frame_counter > 7:
				frame_counter = 0
				frame += 1
				if frame == 1:
					frame = 5
			if (frame >= 1 and frame <= 4) or frame >= 8:
				frame = 0
		return
	var wf: Array = cfg.walk_frames
	if not on_floor and (vel.y > 0.0 or vel.y < -0.8):
		frame = 1
		frame_counter = 0
	elif still:
		frame = 0
		frame_counter = 0
	elif Vector2(vel.x, vel.z).length() > 0.8:
		if frame < wf[0]:
			frame = wf[0]
		frame_counter += Vector2(vel.x, vel.z).length() + 1.0
		if frame_counter > 6:
			frame += 1
			frame_counter = 0
		if frame > wf[1]:
			frame = wf[0]
	else:
		frame = 0
		frame_counter = 0


func _anim_fly() -> void:
	if kind == "BabySlime":
		# Its wings: frames 8 on, every 6 ticks.
		frame_counter += 1
		if frame_counter > 5:
			frame += 1
			frame_counter = 0
		if frame < 8 or frame >= int(cfg.frames):
			frame = 8
		return
	var ff: Array = cfg.fly_frames
	frame_counter += 2 if vel.y > 0.0 else 1
	if frame_counter >= 6:
		frame += 1
		frame_counter = 0
	if frame > ff[1] or frame < ff[0]:
		frame = ff[0]


# ------------------------------------------------------------- AI_026 fliers

## The Zephyr Fish's acceleration [mid, under 100 px, over 300 px].
const FISH_ACCEL := [0.3, 0.1, 0.4]


## The Baby Eater (7 px a tick at you, 0.1 px/tick²: 0.2 beyond 300 px; near
## you, 150 px, gently), the Baby Skeletron Head (3, and 14 once it's been
## 500 px off, spinning), the Zephyr Fish (over your shoulder: 60 px behind
## and above you, 6 px a tick).
func _flier_tick(game) -> void:
	var you := _you()
	var goal := you
	var speed := 7.0
	var accel := 0.1
	if cfg.ai == "fish":
		goal = you - _facing() * 60.0 / PX + Vector3(0, 60.0, 0) / PX \
				+ Vector3(randf_range(-10, 20), randf_range(-20, 10), randf_range(-10, 20)) / PX
		speed = float(cfg.get("speed", 6.0))
		accel = float(cfg.get("accel", FISH_ACCEL)[0])
	elif cfg.ai == "skull":
		speed = 3.0
		if (you - center()).length() * PX > 500.0:
			local0 = 10000.0
		if local0 >= 10000.0:
			speed = 14.0
	var d := (goal - center()) * PX
	var dist := d.length()
	if dist > 2000.0:
		_teleport_to_you()
		return
	# The Baby Eater steers only along the way that's furthest to go (both
	# when it's slowing down).
	var both: bool = cfg.ai != "eater"
	var flat_first := Vector2(d.x, d.z).length() > absf(d.y)
	var near := 50.0 if cfg.ai == "fish" else 150.0
	if dist < near:
		if absf(vel.x) > 2.0 or absf(vel.y) > 2.0 or absf(vel.z) > 2.0:
			vel *= 0.99
		accel = 0.01
		if cfg.ai == "fish":
			d = vel
		else:
			d = d.clamp(Vector3(-2, -2, -2), Vector3(2, 2, 2))
	else:
		if cfg.ai == "fish":
			var a: Array = cfg.get("accel", FISH_ACCEL)
			accel = float(a[1]) if dist < 100.0 else (float(a[2]) if dist > 300.0 else float(a[0]))
		elif dist > 300.0:
			accel = 0.2
		d *= speed / dist
	if accel == 0.01:
		both = true
	for a in 3:
		if not both and (a == 1) == flat_first:
			continue
		if vel[a] < d[a]:
			vel[a] += accel
			if accel > 0.05 and vel[a] < 0.0:
				vel[a] += accel
		elif vel[a] > d[a]:
			vel[a] -= accel
			if accel > 0.05 and vel[a] > 0.0:
				vel[a] -= accel
	_move(game, false)
	if cfg.ai == "skull":
		local0 += randi() % 10
		if local0 > 10000.0:
			spin += 0.25 * (1.0 if _face > 0 else -1.0)
			if local0 > 12000.0:
				local0 = 0.0
		else:
			spin = move_toward(spin, _screen_x(vel) * 0.1, (absf(vel.x) + absf(vel.y) + absf(vel.z)) * 0.01)
	else:
		frame_counter += 1
		if frame_counter > 6:
			frame = (frame + 1) % int(cfg.frames)
			frame_counter = 0


# ------------------------------------------------------------- AI_062

func _swarm_tick(game) -> void:
	_spread(0.05, float(cfg.size[0]))
	var you := _you()
	# Your target (within 6000 px), else an enemy it can see within 2000 px
	# of it, the nearest.
	var target = _your_target(game, center(), 6000.0)
	var best := 2000.0
	for npc in game.npcs():
		if target != null or not chaseable(npc):
			continue
		var d: float = (npc.center() - center()).length() * PX
		if d < best and _sees(game, center(), npc.center()):
			best = d
			target = npc
	var leash := 1000.0 if target != null else 500.0
	var to_you := (you - center()) * PX
	if ai0 != 1 and to_you.length() > leash:
		ai0 = 1
	var imp := kind == "FlyingImp"
	if target != null and ai0 == 0:
		var to: Vector3 = (target.center() - center()) * PX
		var dist := to.length()
		var dir := to / maxf(dist, 0.001)
		if dist > 200.0:
			vel = (vel * 40.0 + dir * 6.0) / 41.0
		elif imp:
			if dist < 150.0:
				vel = (vel * 40.0 - dir * 4.0) / 41.0
			else:
				vel *= 0.97
		elif vel.y < 1.0:
			vel.y += 0.1
		_face_target = signf(_screen_x(to)) if imp else 0.0
	else:
		_face_target = 0.0
		if ai0 != 1 and not _sees(game, center(), you):
			ai0 = 1
		var speed := 15.0 if ai0 == 1 else 6.0
		var goal := you + Vector3(0, 60.0, 0) / PX
		if imp:
			ai1 = 80.0
			var place := 1
			for m in get_tree().get_nodes_in_group("minions"):
				if m != self and m.kind == kind and m.player == player and m.index < index:
					place += 1
			goal = you + _beside(place, 40.0, 10.0) + Vector3(0, 10.0, 0) / PX
		var d := (goal - center()) * PX
		var dist := d.length()
		if dist > 200.0 and speed < 9.0:
			speed = 9.0
		if imp:
			speed = float(int(speed * 0.75))
		if dist < 100.0 and ai0 == 1 and not _in_solid(game):
			ai0 = 0
		if dist > 2000.0:
			_teleport_to_you()
		elif imp:
			if dist > 10.0:
				vel = (vel * 20.0 + d.normalized() * (speed / 2.0 if dist < 50.0 else speed)) / 21.0
			else:
				vel *= 0.9
		elif dist > 70.0:
			vel = (vel * 20.0 + d.normalized() * speed) / 21.0
		else:
			if vel == Vector3.ZERO:
				vel = Vector3(-0.15, 0.05, 0)
			vel *= 1.01
	_move(game, ai0 != 1)
	# Its shot: when ready (ai[1] 0) with a target, then cooling down (the
	# Hornet 1-3 a tick to 90, the Imp 1 and 1 in 3 another, to 90).
	if ai1 > 0.0:
		ai1 += (randi_range(1, 3) if not imp else (2 if randi() % 3 == 0 else 1))
		if ai1 > 90.0:
			ai1 = 0.0
	if ai0 == 0 and target != null and ai1 == 0.0:
		ai1 = 1.0
		var dir: Vector3 = (target.center() - center()).normalized()
		var shot: Projectile = game.spawn_projectile(cfg.shot, center(), dir * float(cfg.shot_speed) * 60.0 / PX, damage(),
				player.weapon_knockback(item), 0.0, 0.0, 0.5, true, 0.0)
		shot.minion_shot = true
		Audio.play_at(cfg.shot_sound, center(), 0.5)
	# Wings: the Hornet's 3 frames, every 2 ticks; the Imp's 4 every 5 ticks,
	# its casting 4 after a shot.
	frame_counter += 1
	if imp:
		if frame_counter >= 20:
			frame_counter = 0
		frame = int(frame_counter) / 5
		if ai1 > 0.0 and ai1 < 24.0:
			frame += 4
	else:
		if frame_counter > 1:
			frame += 1
			frame_counter = 0
		if frame > 2:
			frame = 0


# ------------------------------------------------------------- AI_158

func _bird_tick(game) -> void:
	var target = _your_target(game, center(), 2400.0)
	var best := 800.0
	for npc in game.npcs():
		if target != null or not chaseable(npc):
			continue
		var d: float = (npc.center() - center()).length() * PX
		if d < best and (npc.center() - _you()).length() * PX <= 800.0 and _sees(game, center(), npc.center()):
			best = d
			target = npc
	friendly = true
	if target != null:
		var collide := not _in_solid(game)
		var to: Vector3 = (target.center() - center()) * PX
		var dist := to.length()
		if target.overlaps_box(global_position, box):
			collide = false
			if absf(vel.x) + absf(vel.y) + absf(vel.z) < 8.0:
				vel *= 1.1
			if vel.length() > 8.0:
				vel = vel.normalized() * 8.0
		elif dist > 150.0:
			vel = vel.lerp(to / dist * 6.0, 0.15)
		else:
			collide = false
			vel += Vector3(signf(to.x), signf(to.y), signf(to.z)) * 0.35
			if vel.length() > 8.0:
				vel = vel.normalized() * 8.0
		_spread(0.025, float(cfg.size[0]) * 3.0)
		_move(game, collide)
		frame_counter += 1
		if frame_counter >= 6:
			frame_counter = 0
			frame = (frame + 1) % (int(cfg.frames) - 1)
		return
	# Home: on your head (Terraria's 21 px above your middle, the others
	# beside it in sixes, 16 px higher for each six).
	var home := _you() + Vector3(0, 23.0, 0) / PX
	var spots := [Vector2.ZERO, Vector2(8, 2), Vector2(-10, 2), Vector2(10, 10), Vector2(-12, 10), Vector2(0, 10)]
	var spot: Vector2 = spots[index % 6]
	home += _facing() * spot.x / PX + Vector3(0, spot.y + 16.0 * (index / 6), 0) / PX
	var d := (home - center()) * PX
	var dist := d.length()
	if dist > 2000.0:
		global_position = home - Vector3(0, box.y / 2.0, 0)
		vel = Vector3.ZERO
		frame = int(cfg.frames) - 1
		return
	if dist > 40.0:
		var top := 6.0 + dist * 0.006
		var want := d / dist * lerpf(1.0, 5.0, clampf((dist - 40.0) / 760.0, 0.0, 1.0))
		vel = vel.lerp(want * top, 0.025)
		if vel.length() > top:
			vel = vel.normalized() * top
		_spread(0.05, float(cfg.size[0]))
		_move(game, false)
		frame_counter += 1
		if frame_counter >= 6:
			frame_counter = 0
			frame = (frame + 1) % (int(cfg.frames) - 1)
	elif dist > 8.0 + _your_speed():
		vel += Vector3(signf(d.x), signf(d.y), signf(d.z)) * 0.05
		if vel.length() > 6.0:
			vel = vel.normalized() * 6.0
		_move(game, false)
	else:
		# Sitting.
		global_position = home - Vector3(0, box.y / 2.0, 0)
		vel = Vector3.ZERO
		frame = int(cfg.frames) - 1


# ------------------------------------------------------------- AI_067

func _walker_tick(game) -> void:
	var you := _you()
	var target = null if pet else _find_target(game, 800.0, true)
	friendly = kind == "FlinxMinion"
	if attack_left > 0.0:
		_frog_attack(game)
		return
	if attack_left < 0.0:
		attack_left += 1.0
	if ai0 == 0 and target == null:
		var to_you := (you - center()) * PX
		if to_you.length() > 2000.0:
			_teleport_to_you()
		elif to_you.length() > float(cfg.leash) or absf(to_you.y) > 300.0:
			if (to_you.y < 0.0 and vel.y > 0.0) or (to_you.y > 0.0 and vel.y < 0.0):
				vel.y = 0.0
			ai0 = 1
	if ai0 == 1:
		_walker_fly(game, you)
		return
	# Where it goes: at an enemy (the Frog to 20 px short of it), else home,
	# on the ground under that spot.
	var goal: Vector3
	var home: Array = cfg.home
	if target != null:
		goal = target.center()
		if cfg.has("attack"):
			var back := center() - goal
			back.y = 0.0
			goal += back.normalized() * 20.0 / PX if back.length() > 0.01 else Vector3.ZERO
	else:
		var first: float = float(home[0]) + float(cfg.size[0]) / 2.0
		if pet:
			goal = you - _facing() * (first + float(home[1])) / PX
		else:
			goal = you + _beside(index + 1, float(home[1]), first - float(home[1]))
		var cell := Vector3i(goal.floor())
		for i in 14:
			if game.world.is_solid(cell + Vector3i(0, -i - 1, 0)):
				goal.y = cell.y - i + box.y / 2.0
				break
	# Its walk (faster after an enemy, and keeping up with you).
	var accel := float(cfg.walk[0])
	var top := float(cfg.walk[1])
	if target != null and cfg.has("hunt"):
		accel = float(cfg.hunt[0])
		top = float(cfg.hunt[1])
	var cap := top
	if _your_speed() > cap:
		cap = _your_speed()
		accel = 0.7
	var flat := Vector2(vel.x, vel.z)
	var to := (goal - center()) * PX
	var to_flat := Vector2(to.x, to.z)
	var dir := Vector2.ZERO
	var hop := false
	if cfg.get("rolls", false) and to_flat.length() < 50.0:
		# The boulder rolls to a stop near you, no faster than you go.
		var yours := _your_speed()
		if yours >= 0.1 and yours < cap:
			cap = yours
		flat *= 0.9
		if flat.length() < 0.1:
			flat = Vector2.ZERO
	elif to_flat.length() > 5.0:
		dir = to_flat.normalized()
		var along := flat.dot(dir)
		var side := flat - dir * along
		along += accel if along < top else 0.1
		flat = dir * along + side * 0.9
		match cfg.hop:
			"moving": hop = true
			"hunting": hop = target != null
			"fast": hop = flat.length() > 5.0
	else:
		flat *= 0.9
		if flat.length() < accel * 2.0:
			flat = Vector2.ZERO
	if flat.length() > cap:
		flat = flat.normalized() * cap
	vel.x = flat.x
	vel.z = flat.y
	if dir != Vector2.ZERO and _wall_ahead(game, dir) > 0:
		hop = true
	# Up to an enemy above it (TryJumpingToTarget: sqrt(2 x 0.4 x height),
	# at most 26), else hopping along and up toward its goal.
	if target != null and on_floor:
		var up_t: float = (target.center().y - center().y) * PX
		if up_t > 30.0:
			vel.y = minf(sqrt(0.8 * up_t), 26.0)
	var wet: bool = game.world.get_liquid(Vector3i(center().floor())).y > 0
	if on_floor and vel.y == 0.0 and hop:
		var wall := _wall_ahead(game, dir) if dir != Vector2.ZERO else 0
		vel.y = _jump_for(wall) if wall > 0 else JUMPS[0]
		var up := to.y
		if up >= 48.0:
			for step in [[60.0, 6.0], [80.0, 7.0], [100.0, 8.0], [120.0, 9.0], [140.0, 10.0], [160.0, 11.0], [190.0, 12.0],
					[210.0, 13.0], [270.0, 14.0], [310.0, 15.0], [INF, 16.0]]:
				if up < step[0]:
					vel.y = step[1]
					break
		if wet and to.y <= 0.0:
			vel.y *= 2.0
	# The Frog's leap: near its enemy, a 20-tick attack.
	if cfg.has("attack") and target != null and attack_left == 0.0 and to.length() < float(cfg.attack[2]):
		attack_left = float(cfg.attack[0])
		if vel.length() > 10.0:
			vel = vel.normalized() * 10.0
		_face_target = signf(_screen_x(target.center() - center()))
	# Gravity 0.4, and heavier rising while its goal is below it.
	var extra := clampf(-to.y / 100.0, 0.0, 1.0) * clampf((vel.y - 2.0) / 4.0, 0.0, 1.0)
	vel.y = maxf(vel.y - 0.4 - extra, -10.0)
	_move(game, true, 1.05)
	_walker_anim()


## The Vampire Frog's attack: hurting in its middle half; then 60 ticks' rest.
func _frog_attack(game) -> void:
	var length := float(cfg.attack[0])
	var p := (length - attack_left) / length
	friendly = p > 0.25 and p < 0.75
	var k := int(p * 5.0)
	if k > 2:
		k = 4 - k
	frame = (18 if on_floor else 21) + k
	if on_floor:
		vel.x *= 0.8
		vel.z *= 0.8
	vel.y = maxf(vel.y - 0.4, -10.0)
	_move(game, true, 1.05)
	attack_left -= 1.0
	if attack_left <= 0.0:
		attack_left = -float(cfg.attack[1])
		_face_target = 0.0


## Flying back to you through the blocks (10 px a tick, or your speed).
func _walker_fly(game, you: Vector3) -> void:
	var speed := maxf(10.0, _your_speed())
	var d := (you - center()) * PX
	var dist := d.length()
	if dist > 2000.0:
		_teleport_to_you()
		return
	if dist < 200.0 and player.on_floor and global_position.y >= player.global_position.y and not _in_solid(game):
		ai0 = 0
		vel.y = minf(vel.y, 6.0)
	if dist >= 60.0:
		var want := d / dist * speed
		vel.x = _steer(vel.x, want.x, 0.2)
		vel.y = _steer(vel.y, want.y, 0.2)
		vel.z = _steer(vel.z, want.z, 0.2)
	_move(game, false)
	match kind:
		"FlinxMinion":
			frame_counter += 1
			if frame_counter > 3:
				frame += 1
				frame_counter = 0
			if frame < 2 or frame >= int(cfg.frames):
				frame = 2
			spin += 0.25 * _face
		"VampireFrog":
			frame_counter = fmod(frame_counter + 1, 12)
			frame = 14 + int(frame_counter) / 3
		"BoulderPet":
			spin += 0.5 * _face
		_:
			_walker_anim()


func _walker_anim() -> void:
	var speed := Vector2(vel.x, vel.z).length()
	var sx := _screen_x(vel)
	match kind:
		"FlinxMinion":
			if on_floor:
				spin = move_toward(spin, 0.0, 0.3)
				if speed < 0.5:
					frame = 0
					frame_counter = 0
				else:
					frame_counter += speed + 1.0
					if frame_counter > 10:
						frame += 1
						frame_counter = 0
					if frame < 2 or frame >= int(cfg.frames):
						frame = 2
			else:
				frame = 1
				frame_counter = 0
				spin = minf(4.0, -vel.y) * -0.1 * _face
		"VampireFrog":
			if on_floor:
				if speed < 0.5:
					frame_counter += 1
					if frame_counter >= 28 and randi() % 50 == 0:
						frame_counter = 0
					var f := int(frame_counter) / 4
					if f >= 4:
						f = 6 - f
					frame = 1 + maxi(f, 0)
				else:
					frame_counter = fmod(frame_counter + speed + 1.0, 120.0)
					frame = 5 + int(frame_counter) / 15
			elif vel.y > 0.0:
				if frame > 9 or frame < 5:
					frame = 5
				elif frame < 9:
					frame += 1
			else:
				if frame > 13 or frame < 9:
					frame = 9
					frame_counter = 0
				frame_counter += 1
				if frame_counter >= 2 and frame < 11:
					frame += 1
					frame_counter = 0
		"CrimsonHeart":
			# Its beat: frames 0-3, 6 ticks each (12 on 0 and 2), turning
			# with its roll.
			frame_counter += 1
			if frame_counter >= (12 if frame % 2 == 0 else 6):
				frame_counter = 0
				frame = (frame + 1) % int(cfg.frames)
			spin += sx / 20.0
		"BoulderPet":
			spin += sx / 16.0


# ------------------------------------------------------------- AI_011

func _orb_tick(_game) -> void:
	var d := (_you() - center()) * PX
	var dist := d.length()
	if dist > 800.0:
		_teleport_to_you()
	elif dist > 70.0:
		vel = d / dist * 3.0
	else:
		vel = Vector3.ZERO
	global_position += vel / PX
	spin += 0.02


## Its light, if it gives one (the Shadow Orb's: Terraria's 0.9, purple).
func light() -> Color:
	var l: Array = cfg.get("light", [])
	return Color(l[0], l[1], l[2]) if l.size() == 3 and visible else Color.BLACK


# ------------------------------------------------------------- drawing

## How far right on your screen `v` points.
func _screen_x(v: Vector3) -> float:
	return v.dot(player.camera.global_transform.basis.x)


func _draw(game) -> void:
	var sx := _screen_x(vel)
	if _face_target != 0.0:
		_face = _face_target
	elif absf(sx) > 0.05:
		_face = signf(sx)
	# Terraria's art faces left (the Finch's right): turned to the way it goes.
	var right: bool = cfg.get("faces", "left") == "right"
	sprite.set_flip((_face > 0.0) != right)
	sprite.set_frame(frame)
	match cfg.ai:
		"eater":
			# Along its flight, head first (Terraria: its rotation is its
			# velocity's angle less a quarter turn).
			if vel.length() > 0.01:
				sprite.set_rotation_angle(EntitySprite.facing_angle(player.camera, vel))
		"skull", "orb", "walker":
			sprite.set_rotation_angle(-spin)
		"bird":
			sprite.set_rotation_angle(-sx * 0.1)
		"swarm":
			sprite.set_rotation_angle(-sx * 0.05)
		"fish" when cfg.get("tilt", false):
			sprite.set_rotation_angle(-sx * 0.05)
		_:
			sprite.set_rotation_angle(0.0)
	if cfg.has("light") and cfg.ai == "orb":
		sprite.set_glow()
	else:
		sprite.update_light(game.world, game.sky, center())
