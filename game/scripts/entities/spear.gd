class_name Spear
extends Node3D
## Terraria's spears (projectile AI 19): one use thrusts the spear out along
## your aim for the first two thirds of the use, then pulls it back for the
## last third, the spear's tip going exactly as far as Terraria's
## (Projectile.AI_019_Spears_GetSpearOffsetRelativeToPlayer):
##   tip = shoot speed x (base + out x ticks out - back x ticks back)
## Terraria pixels from you (16 to a block), with the spear's own base, out
## and back numbers (the item's "spear"). It passes through blocks, hits every
## enemy its tip touches, each at most every 10 ticks (Terraria's immunity
## after a hit), but only enemies you can see (Terraria's ownerHitCheck). The
## Dark Lance and The Rotted Fork also reach a little past the tip while
## thrusting (AI_019_Spears_GetExtensionHitbox); the Storm Spear throws a
## bolt as it goes (Storm Spear Shot: 1.6x damage, half knockback, 4x the
## spear's speed, 0.35 s, stops at blocks).
## In 3D the spear is the projectile's sprite extruded like a held item. It's
## out while you hold the spear (the player makes it), resting in your hand
## pointing at the crosshair; a thrust slides it out along that line and back
## (drawn_tip), and it eases back to rest. The shaft passes through you as it
## does through Terraria's player, so it's cut off at your hand. It's in the
## world, so it goes behind walls and is lit by them.

## Terraria pixels per block.
const PX := 16.0
## Spear projectiles' hitbox (18 x 18 Terraria pixels), round the tip.
const TIP_RADIUS := 9.0 / PX
## Terraria: 10 ticks of immunity after a hit.
const HIT_COOLDOWN := 10.0 / 60.0
const BOLT_LIFE := 0.35
## At rest the tip is this far out from your hand (blocks).
const REST := 2.0
## How fast it settles back to rest after a thrust (per second).
const SETTLE := 14.0

var player: Player
var def: Dictionary
## Thrusting; seconds since the thrust began, and the whole use.
var using := false
var t := 0.0
var duration := 0.5
## How far out from your hand the tip is drawn (blocks).
var drawn := REST
## Taken out it swings up into place from below, like held items (0 -> 1
## over Viewmodel.EQUIP_TIME).
var _equip := 0.0
## Terraria pixels a tick (the item's shoot speed, faster with melee speed).
var speed := 4.0
var _mesh := MeshInstance3D.new()
var _size := Vector2.ONE  # sprite size, texture pixels
var _cooldowns := {}  # npc -> seconds


func setup(p: Player, item: Dictionary) -> void:
	player = p
	def = item
	_time_use(float(def.get("use_time", 20)) / 60.0 / (1.0 + player.stat("melee_speed") / 100.0))
	var id: int = Assets.ids.ProjectileID.get(def.get("projectile", "Spear"), 49)
	var img := Assets.image("Images/Projectile_%d" % id)
	_size = Vector2(img.get_size())
	_mesh.mesh = ItemMesh.build_art(img, "proj%d" % id)
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/block_model.gdshader")
	m.set_shader_parameter("sprite", Assets.texture("Images/Projectile_%d" % id))
	m.set_shader_parameter("textured", true)
	_mesh.material_override = m
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mesh.extra_cull_margin = 4.0
	add_child(_mesh)


## A use `seconds` long: Terraria's shoot speed is faster with melee speed.
func _time_use(seconds: float) -> void:
	duration = maxf(seconds, 0.05)
	speed = float(def.spear.speed) * (1.0 + player.stat("melee_speed") / 100.0)


## Starts a thrust lasting `seconds` (the item's use).
func thrust(seconds: float) -> void:
	_time_use(seconds)
	t = 0.0
	using = true
	_cooldowns.clear()
	if def.has("bolt"):
		_throw_bolt(Game.current)


## Terraria's ticks for a time in this use (the use is `duration` long).
func _ticks(seconds: float) -> float:
	return seconds * 60.0


## How far the tip is from your eye (blocks) `seconds` into the thrust.
func reach_at(seconds: float) -> float:
	var total := _ticks(duration)
	var third := floorf(total / 3.0)
	var e := clampf(_ticks(seconds), 0.0, total)
	var s: Dictionary = def.spear
	var out := minf(e, total - third)
	var back := maxf(0.0, e - (total - third))
	return speed * (float(s.base) + float(s.out) * out - float(s.back) * back) / PX


## Still going out (Terraria's first two thirds), and how far along (0-1).
func thrusting() -> bool:
	return _ticks(t) < _ticks(duration) - floorf(_ticks(duration) / 3.0)


func tip() -> Vector3:
	return player.camera.global_position + player.forward() * reach_at(t)


func hand() -> Vector3:
	return player.camera.global_transform * Viewmodel.hand_position()


func _physics_process(delta: float) -> void:
	var game := Game.current
	if not is_instance_valid(player) or not player.alive:
		queue_free()
		return
	if using and t >= duration:
		using = false
	if using:
		for n in _cooldowns.keys():
			_cooldowns[n] -= delta
			if _cooldowns[n] <= 0.0 or not is_instance_valid(n):
				_cooldowns.erase(n)
		_check_hits(game)
		drawn = thrust_drawn()
		t += delta
	else:
		drawn = lerpf(drawn, REST, 1.0 - exp(-SETTLE * delta))
	_equip = minf(1.0, _equip + delta / Viewmodel.EQUIP_TIME)
	_place(game)


## Where the tip is drawn during a thrust (blocks from your hand). The real
## tip is always on your crosshair (it goes out along your line of sight), so
## drawn there it wouldn't seem to move. Instead the spear slides along the
## line from your hand to where the tip is at full reach, from rest to the
## end of that line as the real tip goes from where it starts to its full
## reach, and back.
func thrust_drawn() -> float:
	var start := reach_at(0.0)
	var k := (reach_at(t) - start) / maxf(peak() - start, 0.01)
	return REST + (hand().distance_to(full_reach_point()) - REST) * k


func drawn_tip() -> Vector3:
	var hd := hand()
	return hd + (full_reach_point() - hd).normalized() * drawn


## How far the tip gets (blocks), and where that is on your crosshair.
func peak() -> float:
	var total := _ticks(duration)
	return reach_at((total - floorf(total / 3.0)) / 60.0)


func full_reach_point() -> Vector3:
	return player.camera.global_position + player.forward() * peak()


func _ready() -> void:
	# In place from the first frame.
	_place(Game.current)


func _place(game) -> void:
	var hd := hand()
	var tp := drawn_tip()
	var dir := (full_reach_point() - hd).normalized()
	# Terraria's spear sprites point to their top-left corner (mesh units:
	# pixels, origin bottom-left, y up).
	var axis := Vector3(-_size.x, _size.y, 0.0).normalized()
	# As long as Terraria's (a pixel a 16th of a block along it, so at full
	# reach your hand holds its end, as in Terraria) but only as thick as the
	# player's pixels.
	var thin := PaperDoll.player_pixel_size()
	var mid := tp - dir * minf(_size.length() / PX, tp.distance_to(hd)) * 0.5
	var stretch := Basis.from_scale(Vector3.ONE * thin)
	for i in 3:
		var e := Vector3.ZERO
		e[i] = 1.0
		stretch[i] = e * thin + axis * axis.dot(e) * (1.0 / PX - thin)
	var basis := Viewmodel.aim_basis(axis, dir, (player.camera.global_position - mid).normalized()) * stretch
	# Swung down about your eye while it's being taken out.
	var cam := player.camera.global_transform
	var swing := Transform3D(Basis(cam.basis.x, -deg_to_rad(55.0) * pow(1.0 - _equip, 2.0)), Vector3.ZERO)
	swing = Transform3D(Basis(), cam.origin) * swing * Transform3D(Basis(), -cam.origin)
	global_transform = swing * Transform3D(basis, tp - basis * Vector3(0.0, _size.y, 0.0))
	_mesh.set_instance_shader_parameter("entity_light", game.world.get_light(mid))
	var m: ShaderMaterial = _mesh.material_override
	var clip := swing * Plane(dir, hd)
	m.set_shader_parameter("clip_plane", Vector4(clip.normal.x, clip.normal.y, clip.normal.z, clip.d))
	m.set_shader_parameter("sky_light", game.sky.sky_light)
	m.set_shader_parameter("sky_color", game.sky.sky_tint)


## The points that hit: the tip, and while thrusting the Dark Lance's or
## Rotted Fork's reach past it ([centre, radius] pairs, blocks).
func hit_spots() -> Array:
	var fwd := player.forward()
	var tp := tip()
	var out := [[tp, TIP_RADIUS]]
	if def.spear.has("lunge") and thrusting():
		# Terraria: a square 10 + S x p px wide, 10 + L x p px past the tip
		# (L shorter with melee speed), p going 0 -> 1 as it thrusts.
		var total := _ticks(duration)
		var p := clampf(_ticks(t) / (total - floorf(total / 3.0)), 0.0, 1.0)
		var l: Array = def.spear.lunge
		var along := (10.0 + float(l[0]) / (1.0 + player.stat("melee_speed") / 100.0) * p) / PX
		out.append([tp + fwd * along, (10.0 + float(l[1]) * p) * 0.5 / PX])
	return out


func _check_hits(game) -> void:
	for s in hit_spots():
		game.cut_tiles_at(s[0], s[1])
	var cam: Vector3 = player.camera.global_position
	for npc in game.npcs():
		if _cooldowns.has(npc) or npc.def.ai == "town":
			continue
		if npc.dont_take_damage or (npc.def.get("invulnerable", false) and npc.def.ai != "dummy"):
			continue
		var touched := false
		for s in hit_spots():
			if npc.overlaps_point(s[0], s[1]):
				touched = true
				break
		if not touched or not _can_see(game, cam, npc):
			continue
		npc.hit(player.weapon_damage(def), float(def.get("knockback", 0)), (npc.center() - cam).normalized(), player.crit_chance(def), player.armor_penetration(def))
		player.on_melee_hit(npc, def)
		_cooldowns[npc] = HIT_COOLDOWN


## Terraria's ownerHitCheck: you have to see the enemy (its middle or top).
func _can_see(game, cam: Vector3, npc) -> bool:
	for p in [npc.center(), npc.center() + Vector3(0, npc.half.y * 0.45, 0)]:
		var to: Vector3 = p - cam
		if float(game.world.raycast(cam, to.normalized(), to.length()).get("distance", INF)) >= to.length() - 0.3:
			return true
	return false


## The Storm Spear's bolt, from the spear's tip along your aim.
func _throw_bolt(game) -> void:
	var b: Projectile = game.spawn_projectile(def.bolt, tip(), player.forward() * speed * 4.0 * 60.0 / PX,
			int(player.weapon_damage(def) * 1.6), float(def.get("knockback", 0)) * 0.5, 0.0, 0.0, 0.5, true, player.crit_chance(def))
	b.life = BOLT_LIFE
	b.armor_pen = player.armor_penetration(def)
