class_name HarpoonShot
extends Node3D
## The Harpoon's head on its chain (Terraria's aiStyle 13): out at its speed,
## dropping after `drop_after` ticks (0.6 px a tick each tick, its sideways
## speed x0.995 a tick), and reeled back at `back` px a tick once you let go
## of the button (after 10 ticks), it hits a block or it's `reach` px out.
## It goes through `pierce` enemies, hitting each at most every 12 ticks.

## px -> blocks, px a tick -> blocks a second.
const PX := 1.0 / 24.0
const PX_TICK := 60.0 / 24.0
const HIT_COOLDOWN := 12.0 / 60.0

var player
## The item's "harpoon": speed, back, reach, pierce, drop_after, chain.
var def := {}
var damage := 0
var knockback := 0.0
var crit := 0.04
var velocity := Vector3.ZERO
var returning := false
var _age := 0.0
var _pierce := 3
var _hit_at := {}
var sprite := EntitySprite.new()
var _links: Array[EntitySprite] = []
var _link_tex: Texture2D
var _link_len := 0.5


func setup(p, item: Dictionary, dir: Vector3) -> void:
	player = p
	def = item.harpoon
	damage = p.weapon_damage(item)
	knockback = float(item.get("knockback", 0))
	crit = p.crit_chance(item)
	_pierce = int(def.get("pierce", 3))
	velocity = dir.normalized() * float(def.speed) * PX_TICK
	var tex := Assets.texture("Images/Projectile_23")
	sprite.setup(tex, 1, Vector2(tex.get_width(), tex.get_height()) * PX, true, true)
	add_child(sprite)
	_link_tex = Assets.texture("Images/" + str(def.get("chain", "Chain")))
	_link_len = _link_tex.get_height() * PX
	add_to_group("harpoons")


func _physics_process(delta: float) -> void:
	var game := Game.current
	if not is_instance_valid(player) or not player.alive or Projectile.in_shimmer(global_position):
		queue_free()
		return
	_age += delta
	var hand: Vector3 = player.hook_hand()
	var dist := global_position.distance_to(player.center())
	if not returning:
		if (_age > 10.0 / 60.0 and not player.use_down()) or dist > float(def.reach) * PX:
			returning = true
		elif _age * 60.0 >= float(def.get("drop_after", 17)):
			var k := pow(0.995, delta * 60.0)
			velocity.x *= k
			velocity.z *= k
			velocity.y -= 0.6 * 150.0 * delta
	if returning:
		if dist < 50.0 * PX:
			queue_free()
			return
		velocity = (player.center() - global_position).normalized() * float(def.back) * PX_TICK
	var move := velocity * delta
	var steps := maxi(1, ceili(move.length() / 0.2))
	for i in steps:
		var next := global_position + move / steps
		if not returning and game.world.is_solid(Vector3i(next.floor())):
			returning = true
			Audio.play_at("Dig_*", next, 0.4)
			break
		global_position = next
		_hits(game)
	_draw(game, hand)


func _hits(game) -> void:
	var now := _age
	for npc in game.npcs():
		if npc.def.ai == "town" or npc.dont_take_damage:
			continue
		if now - float(_hit_at.get(npc, -1.0)) < HIT_COOLDOWN or not npc.overlaps_point(global_position, 0.3):
			continue
		_hit_at[npc] = now
		npc.hit(damage, knockback, velocity.normalized(), crit)
		_pierce -= 1
		if _pierce <= 0:
			returning = true
			return


func _draw(game, hand: Vector3) -> void:
	var to := global_position - hand
	sprite.set_axis(velocity if not returning else -to)
	sprite.update_light(game.world, game.sky, global_position)
	var n := int(to.length() / _link_len)
	while _links.size() < n:
		var l := EntitySprite.new()
		l.setup(_link_tex, 1, Vector2(_link_tex.get_width(), _link_tex.get_height()) * PX, true, true)
		add_child(l)
		_links.append(l)
	for i in _links.size():
		var l := _links[i]
		l.visible = i < n
		if l.visible:
			var at := global_position - to.normalized() * _link_len * (i + 0.5)
			l.global_position = at
			l.set_axis(to)
			l.update_light(game.world, game.sky, at)
