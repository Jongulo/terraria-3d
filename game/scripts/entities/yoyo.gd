class_name Yoyo
extends Node3D
## Terraria's yoyo: thrown out while you hold the use button, it chases the
## point you aim at (up to its reach), tethered to your hand by a string,
## spinning. It hits whatever it touches up to 6 times a second, bouncing off
## (each hit takes a third of a second off its spin; a block between you and
## it cuts the damage by a quarter and costs a whole second). When you let go,
## or its spin runs out, it comes back to your hand.

## Terraria: 10 ticks between hits.
const HIT_COOLDOWN := 10.0 / 60.0
## How far its edge reaches (it fits through 1-block gaps).
const RADIUS := 0.25
## Terraria's top speed is in mph; this turns it into blocks a second (a
## little slower than Terraria's, so you can follow it in first person).
const MPH_TO_SPEED := 0.44

var player: Player
var def: Dictionary
var velocity := Vector3.ZERO
## Seconds of spin left.
var spin := 3.0
## Held out (the use button down); false: coming back.
var held := true
var returning := false
var sprite := EntitySprite.new()
var _hit_cd := 0.0
var _angle := 0.0
var _string := MeshInstance3D.new()
var _string_mesh := ImmediateMesh.new()


func setup(p: Player, item: Dictionary) -> void:
	player = p
	def = item
	spin = float(def.yoyo.duration)
	var id: int = Assets.ids.ProjectileID.get(def.get("projectile", "WoodYoyo"), 541)
	sprite.setup(Assets.texture("Images/Projectile_%d" % id), 1, Vector2(0.5, 0.5), true, true)
	add_child(sprite)
	_string.mesh = _string_mesh
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.95, 0.95, 0.92)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_string.material_override = m
	_string.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_string.top_level = true
	add_child(_string)


## How far it reaches (blocks): Terraria's tiles, longer with melee speed and a
## string (x1.25 + 1.875 tiles, like Terraria's).
func reach() -> float:
	var r := float(def.yoyo.reach) * (1.0 + player.stat("melee_speed") / 100.0)
	if player.has_effect("yoyo_string"):
		r = r * 1.25 + 1.875
	return r


func top_speed() -> float:
	return float(def.yoyo.speed) * MPH_TO_SPEED


## The point it chases: where you aim, no farther than its reach, short of
## the block you're aiming at, and on the first enemy in your sights (like
## Terraria's cursor on it).
func target() -> Vector3:
	var cam := player.camera.global_position
	var fwd := player.forward()
	var d := minf(reach(), float(player.target.get("distance", reach())) - RADIUS - 0.1)
	for npc in Game.current.npcs():
		if npc.def.ai == "town":
			continue
		var c: Vector3 = npc.center()
		var along := (c - cam).dot(fwd)
		if along <= 0.0 or along >= d:
			continue
		var off: Vector3 = cam + fwd * along - c
		if Vector2(off.x, off.z).length() < npc.half.x + RADIUS and absf(off.y) < npc.half.y * 0.5 + RADIUS:
			d = along
	return cam + fwd * maxf(d, 1.0)


func hand() -> Vector3:
	return player.camera.global_transform * Viewmodel.hand_position()


func _physics_process(delta: float) -> void:
	var game := Game.current
	if not is_instance_valid(player) or not player.alive:
		queue_free()
		return
	spin -= delta
	_hit_cd = maxf(0.0, _hit_cd - delta)
	if not held or spin <= 0.0:
		returning = true
	if returning:
		var to := hand() - global_position
		if to.length() < 0.6:
			queue_free()
			return
		global_position += to.normalized() * minf(to.length(), top_speed() * 1.6 * delta)
	else:
		# Chase the aim point, slowing as it gets there (it hovers on it).
		var to := target() - global_position
		var want := to.normalized() * minf(top_speed(), to.length() * 10.0)
		velocity = velocity.lerp(want, 1.0 - exp(-18.0 * delta))
		_move(velocity * delta, game.world)
		# Never past its reach.
		var cam := player.camera.global_position
		var off := global_position - cam
		if off.length() > reach():
			global_position = cam + off.normalized() * reach()
		_check_hits(game)
	_angle += delta * 30.0
	sprite.set_rotation_angle(_angle)
	sprite.update_light(game.world, game.sky, global_position)
	_draw_string()


## Moves axis by axis, bouncing off blocks.
func _move(step: Vector3, world: VoxelWorld) -> void:
	for axis in 3:
		if step[axis] == 0.0:
			continue
		var to := global_position
		to[axis] += step[axis]
		var edge := to
		edge[axis] += signf(step[axis]) * RADIUS
		if world.is_solid(Vector3i(edge.floor())):
			velocity[axis] *= -0.3
		else:
			global_position = to


func _check_hits(game) -> void:
	game.cut_tiles_at(global_position, RADIUS)
	if _hit_cd > 0.0:
		return
	for npc in game.npcs():
		if npc.dont_take_damage or (npc.def.get("invulnerable", false) and npc.def.ai != "dummy"):
			continue
		if not npc.overlaps_point(global_position, RADIUS):
			continue
		var dmg := player.weapon_damage(def)
		var cam: Vector3 = player.camera.global_position
		var to := global_position - cam
		var blocked: bool = float(game.world.raycast(cam, to.normalized(), to.length()).get("distance", INF)) < to.length() - 0.5
		if blocked:
			dmg = maxi(1, int(dmg * 0.75))
		npc.hit(dmg, float(def.get("knockback", 0)), (npc.center() - cam).normalized(), player.crit_chance(def), player.armor_penetration(def))
		spin -= 1.0 if blocked else 1.0 / 3.0
		_hit_cd = HIT_COOLDOWN
		# Bounces off what it hit.
		var away: Vector3 = global_position - npc.center()
		velocity = away.normalized() * top_speed() * 0.2 if away.length() > 0.01 else -velocity * 0.2
		Audio.play_at("Item_1", global_position, 0.4)
		return


## The string from your hand to the yoyo: a thin strip turned to the camera.
func _draw_string() -> void:
	_string_mesh.clear_surfaces()
	var a := hand()
	var b := global_position
	var cam := player.camera.global_position
	var side := (b - a).cross(cam - (a + b) * 0.5).normalized() * 0.008
	if side == Vector3.ZERO:
		return
	_string_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [a - side, b - side, b + side, a - side, b + side, a + side]:
		_string_mesh.surface_add_vertex(v)
	_string_mesh.surface_end()
