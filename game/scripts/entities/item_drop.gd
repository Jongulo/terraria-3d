class_name ItemDrop
extends Node3D
## An item lying in the world: falls, gets pulled toward a nearby player and is
## picked up on contact (Terraria's item magnet).

const GRAB_RANGE := 4.5
const HEARTREACH := 250.0 / 24.0
const PICKUP_RANGE := 1.3
const DESPAWN_TIME := 600.0
const PICKUP_DELAY := 0.6

var item := ""
var def := {}
var count := 1
## Its prefix (Prefixes), 0 for none.
var prefix := 0
var velocity := Vector3.ZERO
var age := 0.0
var sprite := EntitySprite.new()
var _bob := randf() * TAU
## An animated item's animation (Data.item_anim), or {}.
var _anim := {}


func setup(item_name: String, n: int, pre := 0) -> void:
	item = item_name
	def = Data.item(item_name)
	count = n
	prefix = pre
	var id := Data.item_id(item_name)
	var tex := Assets.item_texture(id)
	var px := maxf(tex.get_width(), tex.get_height())
	# Terraria items are ~16-40px; show them at roughly half a block.
	var s := clampf(px / 40.0, 0.3, 0.8)
	_anim = Data.item_anim(id)
	if _anim.is_empty():
		sprite.setup(tex, 1, Vector2(s * tex.get_width() / px, s * tex.get_height() / px), true, true)
	else:
		sprite.setup(Assets.item_sheet(id), int(_anim.frames), Vector2(s * tex.get_width() / px, s * tex.get_height() / px), true, true)
	sprite.position.y = s * 0.5
	add_child(sprite)


func _physics_process(delta: float) -> void:
	var game := Game.current
	age += delta
	if age > DESPAWN_TIME:
		queue_free()
		return
	if Data.item(item).get("dawn", false) and game.sky.is_day:
		# Fallen Stars fade away at sunrise.
		game.spawn_dust(global_position + Vector3(0, 0.3, 0), Color(1.0, 0.9, 0.4), 10)
		queue_free()
		return
	var player := game.player
	var to_player := player.global_position + Vector3(0, 0.9, 0) - global_position
	var dist := to_player.length()
	# The Treasure Magnet reaches further (Terraria's treasureGrabRange).
	if player.alive and age > PICKUP_DELAY and dist < grab_range(player) and (def.has("pickup_heal") or def.has("pickup_mana") or player.inventory.count_space(item) > 0):
		if dist < PICKUP_RANGE:
			_pick_up(player)
			return
		velocity = velocity.lerp(to_player.normalized() * 9.0, 0.15)
		global_position += velocity * delta
	else:
		var liquid: Vector2i = game.world.get_liquid(Vector3i(global_position.floor()))
		if liquid.x == 2 and liquid.y > 0:
			# Terraria items burn up in lava.
			Audio.play_at("Item_14", global_position, 0.5)
			game.spawn_dust(global_position, Color(1.0, 0.45, 0.1), 8)
			queue_free()
			return
		# (Honey, like water, slows it.)
		var in_water := (liquid.x == 1 or liquid.x == 3) and liquid.y > 0
		velocity.x *= 0.8 if in_water else 0.9
		velocity.z *= 0.8 if in_water else 0.9
		velocity.y = maxf(velocity.y - (5.0 if in_water else 25.0) * delta, -1.0 if in_water else -20.0)
		var r := game.world.move_aabb(global_position, Vector3(0.2, 0.3, 0.2), velocity * delta, 0.0, false)
		global_position = r.position
		if r.on_floor:
			velocity.y = 0.0
	_bob += delta * 3.0
	sprite.position.y = sprite.scale.y * 0.5 + 0.08 + sin(_bob) * 0.06
	if not _anim.is_empty():
		sprite.set_frame(Data.item_frame(_anim, age))
	if Data.item(item).get("glow", false):
		# It shines (Terraria's Fallen Star lights up around it): full bright.
		sprite.set_glow()
	else:
		sprite.update_light(game.world, game.sky, global_position + Vector3(0, 0.3, 0))


## How near you it comes to you from: the Treasure Magnet's further; Hearts
## the Heartreach Potion's 250 px further (Player.lifeMagnetGrabRange).
func grab_range(player) -> float:
	var r: float = GRAB_RANGE + player.stat("grab_range")
	if def.has("pickup_heal") and player.has_effect("heartreach"):
		r += HEARTREACH
	return r


## Hearts and Stars aren't kept: they heal (20 life) or give mana (100).
func _pick_up(player) -> void:
	if def.has("pickup_heal") or def.has("pickup_mana"):
		Audio.play("Grab")
		if def.has("pickup_heal"):
			player.heal(int(def.pickup_heal))
		else:
			player.mana = mini(player.mana_cap(), player.mana + int(def.pickup_mana))
			Game.current.floating_text(str(def.pickup_mana), player.center() + Vector3(0, 1.3, 0), Color(0.4, 0.5, 1.0))
			player.stats_changed.emit()
		queue_free()
		return
	var left: int = player.inventory.add(item, count, prefix)
	var taken := count - left
	if taken > 0:
		Audio.play("Grab")
		Game.current.hud.pickup(item, taken, prefix)
	count = left
	if count <= 0:
		queue_free()
