class_name FallingStar
extends Node3D
## A falling star (Terraria's projectile 12): it comes down at a steady 12
## pixels a tick from high in the sky, twinkling (Item_9, every 20-60 ticks)
## and shining, through enemies (1000 damage each, never you or the town's
## NPCs) until it hits a block, where it lands as a Fallen Star (Item_10).
## At sunrise it's gone. Like Terraria's star spawner it waits 3 seconds
## (180 ticks) before it starts to fall.

const PX := 16.0
const DAMAGE := 1000
const KNOCKBACK := 10.0
const RADIUS := 0.35

## Blocks a second.
var velocity := Vector3.ZERO
var sprite := EntitySprite.new()
var _hit := {}
var _twinkle := 0.0
var _trail := 0.0
var _angle := 0.0
## Seconds before it appears and starts falling.
var delay := 3.0


func _ready() -> void:
	var tex := Assets.texture("Images/Projectile_12")
	sprite.setup(tex, 1, Vector2(tex.get_width(), tex.get_height()) / PX, true, true)
	sprite.set_glow()
	add_child(sprite)


func _physics_process(delta: float) -> void:
	var game := Game.current
	if game.sky.is_day:
		queue_free()
		return
	sprite.visible = delay <= 0.0
	if delay > 0.0:
		delay -= delta
		return
	_twinkle -= delta
	if _twinkle <= 0.0:
		_twinkle = randf_range(20.0, 60.0) / 60.0
		Audio.play_at("Item_9", global_position, 0.6)
	_trail -= delta
	if _trail <= 0.0:
		_trail = 0.05
		game.spawn_dust(global_position, Color(1.0, 0.85, 0.35), 1)
	# Terraria spins it by its speed.
	_angle += (absf(velocity.x) + absf(velocity.y) + absf(velocity.z)) * PX / 60.0 * 0.01 * 60.0 * delta
	sprite.set_rotation_angle(_angle)
	var step := velocity * delta
	var n := int(ceil(step.length() / 0.3))
	for i in maxi(n, 1):
		var to := global_position + step / maxi(n, 1)
		var cell := Vector3i(to.floor())
		var size: Vector3i = game.world.get_size()
		if cell.y < 0 or cell.x < 0 or cell.z < 0 or cell.x >= size.x or cell.z >= size.z:
			queue_free()  # off the edge of the world
			return
		if game.world.is_solid(cell):
			_land(game)
			return
		global_position = to
		_check_hits(game)


func _check_hits(game) -> void:
	for npc in game.npcs():
		if _hit.has(npc) or npc.def.ai == "town" or npc.def.get("invulnerable", false):
			continue
		if npc.overlaps_point(global_position, RADIUS):
			_hit[npc] = true
			npc.hit(DAMAGE, KNOCKBACK, velocity.normalized(), 0.0)


## Lands where it stopped: a Fallen Star lying there.
func _land(game) -> void:
	Audio.play_at("Item_10", global_position, 0.7)
	game.spawn_dust(global_position, Color(1.0, 0.9, 0.4), 10)
	game.spawn_item("FallenStar", 1, global_position, Vector3(0, 1.0, 0))
	queue_free()
