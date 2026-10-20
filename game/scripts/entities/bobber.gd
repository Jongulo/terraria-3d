class_name Bobber
extends Node3D
## A fishing pole's bobber on its line (Terraria's aiStyle 61:
## AI_061_FishingBobber, with Player.ItemCheck_PullFishingBobbers and
## Projectile.Kill's catch). Cast, it flies and falls (0.2 px a tick a tick,
## sideways x0.98 a tick) until it lands; on liquid it floats at the surface.
## Resting there it counts up (1-2 a tick, more with fishing power, now and
## then 60 at once) and past 660 checks for a bite (Fishing.check). A bite
## bobs it under for a while (90-240 ticks plus the fishing power); reel in
## then (use the pole again) for the catch: the bait may be used up, and 1
## time in 7 the line snaps (not with a High Test Fishing Line). Reeled in
## (or past 900 px away) it comes back to you, and what it caught is yours.
## Switching away from the pole takes it in.

## Terraria px -> blocks.
const PX := 1.0 / 24.0
const TICK := 1.0 / 60.0
## Further than this (px) it comes back by itself; at this it's gone.
const MAX_OUT := 900.0
const LOST := 3000.0
## The bobber's box (blocks, half its size) for blocks and liquid.
const HALF := 0.15
## Terraria's default line colour (DrawProj_FishingLine), alpha 100.
const LINE_COLOR := Color8(200, 200, 200)

var player
## The pole it's on (its definition).
var pole := {}
## Terraria px a tick, y up.
var velocity := Vector3.ZERO
## Reeled in or too far: on its way back (Terraria's ai[0] >= 1).
var returning := false
## Resting on liquid (not moving up or down): counting toward a bite.
var settled := false
var wet := false
var liquid := 0
## Terraria's localAI[1] before a bite: counts to 660, then a check.
var timer := 0.0
## Terraria's ai[1] < 0: a fish is on the line, until it counts up to 0.
var bite := 0.0
## What's biting, and the bait it bit on (localAI[1], localAI[2]).
var catch_item := ""
var catch_bait := ""
var catch_level := 0
## Reeled in with a catch: given to you when it comes back (ai[1] > 0).
var caught := ""
var caught_count := 1
var rng := RandomNumberGenerator.new()
var sprite := EntitySprite.new()
var _line := MeshInstance3D.new()
var _mesh := ImmediateMesh.new()
var _acc := 0.0
var _tip := Vector2.ZERO


func setup(p, def: Dictionary, dir: Vector3) -> void:
	player = p
	pole = def
	rng.randomize()
	velocity = dir.normalized() * float(def.get("cast_speed", 9.0))
	var tex := Assets.texture("Images/Projectile_%d" % int(Assets.ids.ProjectileID.get(def.get("bobber", "BobberWooden"), 360)))
	sprite.setup(tex, 1, Vector2(tex.get_width(), tex.get_height()) * PX, true, true)
	add_child(sprite)
	_line.mesh = _mesh
	_line.top_level = true
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line.material_override = m
	add_child(_line)
	_tip = rod_tip(Data.item_id(def.internal))
	add_to_group("bobbers")


## Where the line leaves a pole's sprite: its top right-most pixel (Terraria
## poles point up and right, the line at the tip).
static func rod_tip(item_id: int) -> Vector2:
	var img := Assets.item_image(item_id)
	if img == null:
		return Vector2.ZERO
	var best := Vector2(0, img.get_height())
	var best_score := -INF
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5 and x - y > best_score:
				best_score = x - y
				best = Vector2(x + 0.5, y + 0.5)
	return best


func center() -> Vector3:
	return global_position


func _physics_process(delta: float) -> void:
	if not _still_held():
		_finish()
		return
	_acc += delta
	while _acc >= TICK:
		_acc -= TICK
		_tick()
		if is_queued_for_deletion():
			return
	_draw()


## Terraria kills a bobber when you stop holding its pole, die or are stunned.
func _still_held() -> bool:
	if not is_instance_valid(player) or not player.alive:
		return false
	var held: Dictionary = player.held()
	return held.get("bobber", "") == pole.get("bobber", "")


func _tick() -> void:
	var game := Game.current
	var to_player: Vector3 = player.center() - global_position
	var dist := to_player.length() / PX
	if returning:
		if dist > LOST:
			_finish()
			return
		velocity = (velocity * 9.0 + to_player.normalized() * 15.9) / 10.0
		global_position += velocity * PX
		if global_position.distance_to(player.center()) < 0.9:
			_finish()
		return
	if dist > MAX_OUT:
		returning = true
	var wl := _water_line(game.world)
	wet = not is_nan(wl) and global_position.y - HALF < wl
	settled = false
	if wet:
		velocity.x *= 0.9
		velocity.z *= 0.9
		if velocity.y < 0.0:
			velocity.y *= 0.5
		if global_position.y < wl:
			velocity.y = minf(velocity.y + 0.1, 8.0)
			if global_position.y + velocity.y * PX > wl:
				velocity.y = (wl - global_position.y) / PX
		else:
			velocity.y = (wl - global_position.y) / PX
		settled = absf(velocity.y) <= 0.01
	else:
		if velocity.y == 0.0:
			velocity.x *= 0.95
			velocity.z *= 0.95
		velocity.x *= 0.98
		velocity.z *= 0.98
		velocity.y = maxf(velocity.y - 0.2, -15.9)
	if bite != 0.0:
		settled = true
	if settled:
		if bite == 0.0:
			var level: int = Fishing.conditions(player, game.sky).level
			if rng.randi_range(0, 299) < level:
				timer += rng.randi_range(1, 2)
			timer += level / 30
			timer += rng.randi_range(1, 2)
			if rng.randi_range(0, 59) == 0:
				timer += 60.0
			if timer > 660.0:
				timer = 0.0
				_check(game)
		else:
			# A bite: it bobs under, again and again, until the fish gets away.
			# (Terraria's test is a speed of exactly 0, which its sums reach
			# floating at the surface; here they leave a trace, so it's the
			# 0.01 of settling, Terraria's test in honey.)
			if absf(velocity.y) <= 0.01:
				velocity.y = -rng.randi_range(100, 499) * 0.015
				velocity.x = rng.randi_range(-100, 100) * 0.015
				velocity.z = rng.randi_range(-100, 100) * 0.015
			bite += rng.randi_range(1, 4)
			if bite >= 0.0:
				bite = 0.0
				catch_item = ""
				timer = 0.0
	var r: Dictionary = game.world.move_aabb(global_position - Vector3(0, HALF, 0), Vector3(HALF, HALF * 2.0, HALF), velocity * PX, 0.0, false)
	global_position = r.position + Vector3(0, HALF, 0)
	var blocked: Vector3i = r.blocked
	if blocked.x:
		velocity.x = 0.0
	if blocked.y:
		velocity.y = 0.0
	if blocked.z:
		velocity.z = 0.0


## Terraria's AI_061_FishingBobber_GetWaterLine: the liquid's surface in the
## column the bobber is in (the cell above it, its own, or the one below);
## NAN if there's none.
func _water_line(world: VoxelWorld) -> float:
	var c := Vector3i(global_position.floor())
	for dy in [1, 0, -1]:
		var p := c + Vector3i(0, dy, 0)
		var l := world.get_liquid(p)
		if l.y > 0:
			liquid = l.x
			var full := world.get_liquid(p + Vector3i.UP).y > 0
			return p.y + (1.0 if full else l.y / 63.0 * 0.94)
	liquid = 0
	return NAN


## Projectile.FishingCheck and SetFishingCheckResults.
func _check(game) -> void:
	var r: Dictionary = Fishing.check(game, player, global_position, rng)
	player.fishing_info = r.info
	if r.catch != "":
		catch_item = r.catch
		catch_level = r.level
		catch_bait = Fishing.conditions(player, game.sky).bait
		bite = rng.randi_range(-240, -91) - float(r.level)
		# The Sonar Potion: what's biting shows over the bobber.
		if player.has_buff("Sonar"):
			game.floating_text(Assets.item_name(catch_item), global_position + Vector3(0, 0.8, 0), Color(1.0, 0.95, 0.6))
	elif r.get("lava", false):
		# Lava gear makes the next check come sooner.
		var bait: String = Fishing.conditions(player, game.sky).bait
		var n := int(bait in Fishing.LAVA_BAIT) + int(pole.get("lava_fishing", false)) + int(player.has_effect("lava_fishing"))
		if n >= 3:
			timer += 480.0
		elif n >= 2:
			timer += 240.0


## Player.ItemCheck_PullFishingBobbers: using the pole with it out.
func reel() -> void:
	if returning:
		return
	returning = true
	if wet and velocity.y < 10.0:
		velocity.y = 10.0
	if bite >= 0.0 or catch_item == "":
		return
	# ItemCheck_CheckFishingBobber_ConsumeBait: the bait it bit on must be
	# there (else nothing); it may be used up.
	var slot := -1
	for i in player.inventory.slots.size():
		var s = player.inventory.slots[i]
		if s != null and s.item == catch_bait:
			slot = i
			break
	if slot < 0:
		return
	if Fishing.bait_used(catch_bait, catch_item, player.has_effect("tackle_box"), rng) and not player.creative:
		player.inventory.consume_slot(slot)
	# ItemCheck_CheckFishingBobber_PullBobber: 1 in 7 the line snaps.
	if rng.randi_range(0, 6) == 0 and not player.has_effect("fishing_line"):
		Audio.play_at("Item_17", global_position, 0.7)
		_splash()
	else:
		caught = catch_item
		caught_count = Fishing.catch_count(caught, catch_level, rng)
		if liquid == Player.LIQ_WATER:
			_splash()
	catch_item = ""
	bite = 0.0


func _splash() -> void:
	Game.current.spawn_dust(global_position + Vector3(0, 0.1, 0), Color(0.5, 0.65, 1.0), 24)
	Audio.play_at("Splash_0", global_position, 0.6)


## Projectile.Kill: the catch is yours (QuickSpawnItem: at your feet, picked up at once).
func _finish() -> void:
	if caught != "" and is_instance_valid(player):
		Game.current.spawn_item(caught, caught_count, player.center(), Vector3.ZERO, 0.0, Prefixes.NATURAL)
		caught = ""
	queue_free()


## The line, from the pole's tip in your hand to the bobber, sagging while
## it's slack (Terraria's DrawProj_FishingLine; its light is the bobber's).
func _draw() -> void:
	var game := Game.current
	sprite.update_light(game.world, game.sky, global_position)
	var from: Vector3 = player.viewmodel.item_point(_tip)
	var to := global_position
	var span := from.distance_to(to)
	var sag := 0.02 * span if returning or bite < 0.0 else minf(0.12 * span, 3.0)
	var mid := (from + to) * 0.5 - Vector3(0, sag, 0)
	var light: Color = game.world.get_light(to)
	var sun: float = light.a * game.sky.sky_light
	var c := LINE_COLOR
	if pole.has("line_color"):
		c = Color8(int(pole.line_color[0]), int(pole.line_color[1]), int(pole.line_color[2]))
	var lit := Color(maxf(light.r, sun * game.sky.sky_tint.r), maxf(light.g, sun * game.sky.sky_tint.g), maxf(light.b, sun * game.sky.sky_tint.b))
	c = Color(c.r * clampf(lit.r, 0.1, 1.0), c.g * clampf(lit.g, 0.1, 1.0), c.b * clampf(lit.b, 0.1, 1.0), 0.85)
	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var n := 24
	for i in n + 1:
		var t := float(i) / n
		_mesh.surface_set_color(c)
		_mesh.surface_add_vertex(from.lerp(mid, t).lerp(mid.lerp(to, t), t))
	_mesh.surface_end()
