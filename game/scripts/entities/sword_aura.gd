class_name SwordAura
extends Node3D
## Terraria's swing auras (projectile AI 190: the Night's Edge's, projectile
## 972). A swing of the Night's Edge (noMelee: the sword itself doesn't hit)
## lets loose two (Player.ItemCheck_Shoot for item 273), each with the
## swing's damage and knockback:
##   one round you for the swing (ai[0] 1, its life the swing's ticks,
##   itemAnimationMax), sweeping half a turn from behind you to in front;
##   one toward your aim (ai[0] 0.1, 30 ticks), spinning two turns more as it
##   goes out 45 px (from its 10th tick to 5 before its end) and grows 40%.
## Each tick, as AI_190_NightsEdge does (localAI[0] the ticks, p = them over
## its life): it's turned pi x ai[0] x p + pi x ai[0] from the way it was
## let loose, sits its velocity behind you (1 px, the second 5 px: the item's
## shoot speed) and is scale 1 + 0.2 p (times the item's scale, a prefix's);
## at p 1 it's gone. 1 tick in 2 a dust 84 px out, near its edge (1 in 5 a
## Dust 14, else 1 in 2 a Dust 27).
## It hits (Projectile.Colliding for AI 190) what's within 94 px x its scale
## of its centre and 45 degrees of the way it points turned on 0.08 pi x ai[0],
## and early on (from 30% of its life to 50%, shrinking away) as much again
## behind that, trailing it; each enemy once (localNPCHitCooldown -1), two at
## most (penetrate 2, stopsDealingDamageAfterPenetrateHits), not one a swing's
## other aura has hit (usesOwnerMeleeHitCD), only enemies you can see within
## 300 px (ownerHitCheck). It cuts grass and pots in its way.
## Terraria's 2D, in 3D: its x is your aim, its y (down) your left, so the
## swing sweeps from behind you round your right to in front; its px are 24
## a block (Player.SWING_PX); the cone is a 3D one round its point.
## Drawn as DrawProj_NightsEdge does (frame 0 of its 4 in four tints, its
## edge, frame 3, white over them; the tints fade in the dark and the edge
## shows), on a sheet lying in that plane just below your eyes, at DRAW_SCALE
## of its size so it shows in front of you like a held item.

const TICK := 1.0 / 60.0
## How far below your eyes the sheet lies (blocks), as the Terragrim's.
const EYE_DROP := 0.55
## The sheet is drawn this much of the aura's size.
const DRAW_SCALE := 0.5
## Terraria px an aura reaches at scale 1, and its sheet's frame.
const REACH_PX := 94.0
const FRAME_PX := 170.0
## The half angle of its cone (Terraria's pi / 4).
const HALF_ANGLE := PI / 4.0

var player: Player
var def: Dictionary
## Terraria's ai[0], ai[1] (its life in ticks), ai[2] (the item's scale).
var turn := 1.0
var life_ticks := 30.0
var item_scale := 1.0
## Its velocity's length, px a tick (it sits that far behind you).
var push := 1.0
var damage := 0
var knockback := 0.0
var crit := 0.04
var armor_pen := 0
## Enemies a swing's auras have hit (shared between them).
var hits: Dictionary
## localAI[0].
var ticks := 0
## Its rotation, from your aim toward your left; its scale; how far out along
## your aim its centre has gone (px).
var angle := 0.0
var size := 1.0
var out := 0.0
var _left := 2
var _acc := 0.0
var _swing := {}
var _quad := MeshInstance3D.new()
var _mat := ShaderMaterial.new()


## A swing's auras (`duration`: the swing's, seconds).
static func swing(p: Player, item: Dictionary, duration: float) -> Array:
	var shared := {}
	var anim := maxf(1.0, roundf(duration * 60.0))
	var speed := float(item.aura.get("speed", 5.0))
	return [_spawn(p, item, 1.0, anim, 1.0, shared), _spawn(p, item, 0.1, 30.0, speed, shared)]


static func _spawn(p: Player, item: Dictionary, ai0: float, ai1: float, speed: float, shared: Dictionary) -> SwordAura:
	var a := SwordAura.new()
	a.player = p
	a.def = item
	a.turn = ai0
	a.life_ticks = ai1
	a.item_scale = float(item.get("scale", 1.0))
	a.push = speed
	a.damage = p.weapon_damage(item)
	a.knockback = p.weapon_knockback(item)
	a.crit = p.crit_chance(item)
	a.armor_pen = p.armor_penetration(item)
	a.hits = shared
	Game.current.entities.add_child(a)
	a._tick()
	return a


func _ready() -> void:
	var id: int = Assets.ids.ProjectileID.get(def.aura.get("projectile", "NightsEdge"), 972)
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	_quad.mesh = quad
	_mat.shader = preload("res://shaders/sword_aura.gdshader")
	_mat.set_shader_parameter("sprite", Assets.texture("Images/Projectile_%d" % id))
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.extra_cull_margin = 4.0
	add_child(_quad)
	_place()


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or not player.alive:
		queue_free()
		return
	_acc += delta
	while _acc >= TICK and not is_queued_for_deletion():
		_acc -= TICK
		_tick()
	if not is_queued_for_deletion():
		_place()


## Its plane: your aim (its x) and your left (its y).
func axes() -> Array:
	var b := player.camera.global_transform.basis
	return [-b.z, -b.x]


## Its centre (where it hits from): you, its velocity behind, and out along
## your aim.
func centre() -> Vector3:
	var a := axes()
	return player.center() + a[0] * (out - push) / Player.SWING_PX


## The way it points (its rotation in its plane) turned on `by`.
func pointing(by := 0.0) -> Vector3:
	var a := axes()
	return a[0] * cos(angle + by) + a[1] * sin(angle + by)


func reach() -> float:
	return REACH_PX * size / Player.SWING_PX


func progress() -> float:
	return float(ticks) / life_ticks


func _tick() -> void:
	var game := Game.current
	ticks += 1
	var p := progress()
	angle = PI * turn * p + turn * PI
	size = 1.0 + p * 0.2
	if absf(turn) < 0.2:
		angle += TAU * 2.0 * turn * 10.0 * p
		var t := Projectile.remap_clamped(ticks, 10.0, life_ticks - 5.0, 0.0, 1.0)
		out = 45.0 * t
		size += t * 0.4
	size *= item_scale
	if randi() % 2 == 0:
		var at := centre() + pointing(randf_range(-1.0, 1.0) * PI / 2.0 * 0.7) * 84.0 * size / Player.SWING_PX
		if randi() % 5 == 0:
			game.dust.spawn(14, at, Vector3.ZERO, 1.4)
		elif randi() % 2 == 0:
			game.dust.spawn(27, at, player.velocity * Player.SWING_PX / 60.0 * 0.2 + axes()[0] * 3.0, 1.4)
	# Gone at the end of its life, before it would hit (Kill in its AI).
	if p >= 1.0:
		queue_free()
		return
	game.cut_tiles_in_cone(centre(), pointing(0.2513 * turn), reach(), cos(HALF_ANGLE))
	_check_hits(game)


## Its cones (Colliding: 0.08 pi on, and the trailing one early on).
func cones() -> Array:
	var on := 0.2513 * turn
	var out_cones := [pointing(on)]
	var trail := Projectile.remap_clamped(ticks, life_ticks * 0.3, life_ticks * 0.5, 1.0, 0.0)
	if trail > 0.0:
		out_cones.append(pointing(on - HALF_ANGLE * turn * trail))
	return out_cones


## Whether an enemy's box is in one of its cones: its nearest point, its
## middle, or its nearest to points along the cone's axis.
func reaches(npc) -> bool:
	var c := centre()
	var r := reach()
	var lo: Vector3 = npc.global_position - Vector3(npc.half.x, 0, npc.half.z)
	var hi: Vector3 = npc.global_position + Vector3(npc.half.x, npc.half.y, npc.half.z)
	var limit := cos(HALF_ANGLE)
	for axis in cones():
		for q in [c.clamp(lo, hi), npc.center(), (c + axis * r * 0.5).clamp(lo, hi), (c + axis * r).clamp(lo, hi)]:
			var to: Vector3 = q - c
			if to.length() <= r and (to.length() < 0.01 or to.normalized().dot(axis) >= limit):
				return true
	return false


func _check_hits(game) -> void:
	if _left <= 0:
		return
	for npc in game.npcs():
		if hits.has(npc) or npc.def.ai == "town" or npc.dont_take_damage or npc.untouchable \
				or (npc.def.get("invulnerable", false) and npc.def.ai != "dummy"):
			continue
		if not reaches(npc) or not _can_see(game, npc):
			continue
		hits[npc] = true
		var away: Vector3 = npc.center() - player.center()
		away.y = 0.0
		npc.hit(damage, knockback, away.normalized() if away.length() > 0.01 else axes()[0], crit, armor_pen)
		player.on_melee_hit(npc, def, _swing)
		_left -= 1
		if _left <= 0:
			return


## Terraria's ownerHitCheck: you have to see the enemy (its middle or top),
## within 300 px.
func _can_see(game, npc) -> bool:
	var cam: Vector3 = player.camera.global_position
	for q in [npc.center(), npc.center() + Vector3(0, npc.half.y * 0.45, 0)]:
		var to: Vector3 = q - cam
		if to.length() > 300.0 / Player.SWING_PX:
			continue
		if float(game.world.raycast(cam, to.normalized(), to.length()).get("distance", INF)) >= to.length() - 0.3:
			return true
	return false


## The sheet: in its plane just below your eyes, its art's right along the
## way it points.
func _place() -> void:
	var cam := player.camera.global_transform
	var a := axes()
	var up: Vector3 = a[0].cross(a[1])
	var x := pointing()
	var y := up.cross(x)
	var s := FRAME_PX * size * 1.1 / Player.SWING_PX * DRAW_SCALE
	var at: Vector3 = cam.origin - cam.basis.y * EYE_DROP + a[0] * (out - push) / Player.SWING_PX * DRAW_SCALE
	_quad.global_transform = Transform3D(Basis(x * s, y * s, up), at)
	var p := progress()
	_mat.set_shader_parameter("fade", Projectile.remap_clamped(p, 0.0, 0.6, 0.0, 1.0) * Projectile.remap_clamped(p, 0.6, 1.0, 1.0, 0.0))
	_mat.set_shader_parameter("back_turn", -turn * HALF_ANGLE * (1.0 - p))
	_mat.set_shader_parameter("edge_turn", turn * 0.01)
	var game := Game.current
	var c := game.world.get_light(centre())
	var sun := Vector3.ONE * c.a * game.sky.sky_light
	var lit := Vector3(maxf(c.r, sun.x), maxf(c.g, sun.y), maxf(c.b, sun.z))
	_mat.set_shader_parameter("lit", Projectile.remap_clamped(lit.length() / sqrt(3.0), 0.2, 1.0, 0.0, 1.0))
