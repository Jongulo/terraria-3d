class_name RopeCoil
extends Node3D
## A thrown Rope Coil (Terraria's aiStyle 35): it flies straight for 30
## ticks, then falls (0.2 px a tick each tick, at most 14 px a tick, its
## sideways speed x0.985 a tick), spinning. Where it hits a block it lays its
## rope (Ropes.lay); what it couldn't lay drops, the rope left over, or the
## coil itself if it laid none.

## Its throw: shootSpeed 10 px a tick.
const SPEED := 25.0
const STRAIGHT := 0.5
const GRAVITY := 30.0
const MAX_FALL := 35.0
const DRAG := 0.985
const SIZE := 0.45
## It's gone (back as a coil) if it hasn't landed by then.
const LIFE := 10.0

var velocity := Vector3.ZERO
## The coil's item, the rope block it lays and that rope's item.
var coil := "RopeCoil"
var rope := "rope"
var item := "Rope"
var sprite := EntitySprite.new()
var _age := 0.0
var _angle := 0.0


func setup(coil_item: String, d: Dictionary) -> void:
	coil = coil_item
	rope = d.rope
	item = d.item
	var id: int = Assets.ids.ProjectileID.get(d.projectile, 171)
	sprite.setup(Assets.texture("Images/Projectile_%d" % id), 1, Vector2(SIZE, SIZE), true, true)
	add_child(sprite)


func _physics_process(delta: float) -> void:
	var game := Game.current
	_age += delta
	if _age > STRAIGHT:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL)
		var k := pow(DRAG, delta * 60.0)
		velocity.x *= k
		velocity.z *= k
	if _age > LIFE:
		game.spawn_item(coil, 1, global_position)
		queue_free()
		return
	# In steps of at most a quarter block, so it can't skip through one.
	var move := velocity * delta
	var steps := maxi(1, ceili(move.length() / 0.25))
	for i in steps:
		var next := global_position + move / steps
		if game.world.is_solid(Vector3i(next.floor())):
			land(game)
			return
		global_position = next
	# rotation += (|vx| + |vy|) * 0.02 a tick, in px a tick.
	_angle += (absf(velocity.x) + absf(velocity.z) + absf(velocity.y)) / 2.5 * 0.02 * 60.0 * delta
	sprite.set_rotation_angle(_angle)
	sprite.update_light(game.world, game.sky, global_position)


func land(game) -> void:
	var laid := Ropes.lay(game, Vector3i(global_position.floor()), Data.block_id(rope))
	if laid == 0:
		game.spawn_item(coil, 1, global_position)
	elif laid < Ropes.COIL:
		game.spawn_item(item, Ropes.COIL - laid, global_position)
	queue_free()
