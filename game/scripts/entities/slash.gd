class_name Slash
extends Node3D
## Terraria's held slashing weapons (projectile AI 75: the Terragrim,
## Projectile 735, and the Arkhalis's kind). While you hold the button it
## keeps on slashing toward your aim; let go and it stops (Terraria's channel).
## Each tick, as AI_075 does:
##   the slash's frame steps on (its "frames"), a swing sound every 12 ticks,
##   it points along your aim at the item's shoot speed ("speed", Terraria px a
##   tick), shines (Lighting.AddLight 0.8 at its tip, 3 ticks of speed out) and,
##   1 tick in 3, throws a dust ("dust") there along the aim.
## Its hitbox is centred on you ("size", Terraria px: 68 x 64 for the
## Terragrim), whichever way you aim, so it reaches a little behind you as in
## Terraria; it hits what you can see (ownerHitCheck), every enemy in it, each
## at most every "immunity" ticks (Damage_PVE_Inner: 5, so 12 hits a second),
## at the item's damage (melee speed doesn't make it faster, as in Terraria).
## The slashes are drawn as Terraria centres them, on you: a sheet as big as
## the hitbox lying flat round you a little below your eyes, its art (each
## frame's right half) sweeping out toward your aim, tilting as you look up
## or down; glowing (Terraria's GetAlpha: 85% white, half see-through).

## Terraria pixels per block (weapons).
const PX := 16.0
const TICK := 1.0 / 60.0
## How far below your eyes the sheet of slashes lies (blocks): at your
## shoulders, so you see it sweep round you.
const EYE_DROP := 0.55

var player: Player
var def: Dictionary
var frame := 0
var aim := Vector3.FORWARD
var _acc := 0.0
var _sound := 0
var _cooldowns := {}  # npc -> ticks until it can be hit again
var _quad := MeshInstance3D.new()
var _mat := ShaderMaterial.new()


func setup(p: Player, item: Dictionary) -> void:
	player = p
	def = item
	var id: int = Assets.ids.ProjectileID.get(def.get("projectile", "Terragrim"), 735)
	var size := slash_size() / PX
	var quad := QuadMesh.new()
	quad.size = size
	_quad.mesh = quad
	_mat.shader = preload("res://shaders/slash.gdshader")
	_mat.set_shader_parameter("sprite", Assets.texture("Images/Projectile_%d" % id))
	_mat.set_shader_parameter("frames", frames())
	_quad.material_override = _mat
	_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_quad.extra_cull_margin = 4.0
	add_child(_quad)


func num(key: String, default := 0.0) -> float:
	return float(def.slash.get(key, default))


func frames() -> int:
	return int(num("frames", 28))


## Its hitbox, in Terraria pixels (width across, height).
func slash_size() -> Vector2:
	var s: Array = def.slash.get("size", [68, 64])
	return Vector2(float(s[0]), float(s[1]))


## Where it shines and throws dust: 3 ticks of its speed out along the aim.
func tip() -> Vector3:
	return player.center() + aim * num("speed", 15.0) * 3.0 / PX


## Whether an enemy is in its hitbox (centred on you: its width across, any
## way round, its height up and down).
func reaches(npc) -> bool:
	var s := slash_size() / PX * 0.5
	var c := player.center()
	var lo: Vector3 = npc.global_position - Vector3(npc.half.x, 0, npc.half.z)
	var hi: Vector3 = npc.global_position + Vector3(npc.half.x, npc.half.y, npc.half.z)
	var near := c.clamp(lo, hi) - c
	return Vector2(near.x, near.z).length() <= s.x and absf(near.y) <= s.y


func _physics_process(delta: float) -> void:
	if not is_instance_valid(player) or not player.alive or not player.use_down() \
			or player.held().get("internal", "") != def.get("internal", ""):
		queue_free()
		return
	_acc += delta
	while _acc >= TICK:
		_acc -= TICK
		_tick()
	_place()


func _tick() -> void:
	var game := Game.current
	aim = player.forward()
	frame = (frame + 1) % frames()
	_sound -= 1
	if _sound <= 0:
		Audio.play_at("Item_1", player.center(), 0.6)
		_sound = 12
	if randi() % 3 == 0:
		var s := slash_size() / PX * 0.5
		var at := tip() + Vector3(randf_range(-s.x, s.x), randf_range(-s.y, s.y), randf_range(-s.x, s.x)) * 0.5
		# Dust moves in 24-px blocks; the slash's speed is in 16-px ones.
		game.dust.spawn(int(def.slash.get("dust", -1)), at, aim * num("speed", 15.0) * 24.0 / PX, 2.0)
	game.cut_tiles_at(player.center(), slash_size().x / PX * 0.5)
	_check_hits(game)


## What the swing has done once already (a Bat Bat's heal).
var _swing := {}


func _check_hits(game) -> void:
	for n in _cooldowns.keys():
		_cooldowns[n] -= 1
		if _cooldowns[n] <= 0 or not is_instance_valid(n):
			_cooldowns.erase(n)
	for npc in game.npcs():
		if _cooldowns.has(npc) or npc.def.ai == "town" or npc.dont_take_damage or (npc.def.get("invulnerable", false) and npc.def.ai != "dummy"):
			continue
		if not reaches(npc) or not _can_see(game, npc):
			continue
		var away: Vector3 = npc.center() - player.center()
		away.y = 0.0
		var dir := away.normalized() if away.length() > 0.01 else aim
		npc.hit(player.weapon_damage(def), float(def.get("knockback", 0)), dir, player.crit_chance(def), player.armor_penetration(def))
		player.on_melee_hit(npc, def, _swing)
		_cooldowns[npc] = int(num("immunity", 5))


## Terraria's ownerHitCheck: you have to see the enemy (its middle or top).
func _can_see(game, npc) -> bool:
	var cam: Vector3 = player.camera.global_position
	for p in [npc.center(), npc.center() + Vector3(0, npc.half.y * 0.45, 0)]:
		var to: Vector3 = p - cam
		if float(game.world.raycast(cam, to.normalized(), to.length()).get("distance", INF)) >= to.length() - 0.3:
			return true
	return false


## The sheet of slashes round you: flat in the plane of your aim and your
## right hand, its art's right (each frame's right) along the aim, just
## below your eyes.
func _place() -> void:
	var cam := player.camera.global_transform
	var fwd := -cam.basis.z
	var up := cam.basis.y
	# Quad axes: x along the aim, y to your left (so the art isn't mirrored),
	# its face up.
	_quad.global_transform = Transform3D(Basis(fwd, up.cross(fwd), up), cam.origin - up * EYE_DROP)
	_mat.set_shader_parameter("frame", frame)
	var light := Game.current.world.get_light(player.center())
	_mat.set_shader_parameter("light", Color(light.r, light.g, light.b).lerp(Color.WHITE, 0.85))
