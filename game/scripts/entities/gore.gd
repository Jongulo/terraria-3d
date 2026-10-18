class_name Gore
extends Node3D
## A piece of a dead enemy (Terraria's gore: Images/Gore_<n>), flung off as it
## dies (NPC.HitEffect, read into assets/terraria/npc_gore.json by
## tools/terraria_gore.py) and moving as Terraria's Gore.Update moves a gore,
## in its pixels and ticks (a block is 24 px): thrown with the enemy's speed,
## plus up to 2 px/tick sideways and 1-3 up; falling 0.2 px/tick², spinning
## with its sideways speed, stopped by blocks, sliding to rest (x0.97 a tick
## on the ground); after 600 ticks it fades out over 255 more.

const PX := 1.0 / 24.0
const LIFE := 600
const FADE := 255
const MAX_SPEED := 32.0  # px/tick

var velocity := Vector3.ZERO  # px/tick, y up
var spin := 0.0
var _sprite := EntitySprite.new()
var _half := Vector3.ONE * 0.2
var _size := 0.4
var _ticks := 0
var _accum := 0.0


## `id`: its Gore_<n> sprite; `px`: blocks per sprite pixel (the enemy's own,
## so it's the size it was on the enemy).
func setup(id: int, px: float) -> void:
	var tex := Assets.texture("Images/Gore_%d" % id)
	var w := float(tex.get_width()) * px
	var h := float(tex.get_height()) * px
	_sprite.setup(tex, 1, Vector2(w, h), true)
	add_child(_sprite)
	# Terraria collides it as a square 0.9 of its longer side.
	_size = maxf(w, h)
	var c := _size * 0.9 * 0.5
	_half = Vector3(c, c * 2.0, c)
	_sprite.position.y = c


func _physics_process(delta: float) -> void:
	_accum += delta
	while _accum >= 1.0 / 60.0:
		_accum -= 1.0 / 60.0
		_tick()
		if not is_inside_tree():
			return
	var game := Game.current
	_sprite.set_rotation_angle(spin)
	_sprite.update_light(game.world, game.sky, global_position + Vector3(0, _half.x, 0))
	if _ticks > LIFE:
		_sprite.set_fade(1.0 - float(_ticks - LIFE) / FADE)


func _tick() -> void:
	var game := Game.current
	_ticks += 1
	if _ticks >= LIFE + FADE:
		queue_free()
		return
	velocity.y -= 0.2
	if velocity.length() > MAX_SPEED:
		velocity = velocity.normalized() * MAX_SPEED
	# Spins with its speed across your view (Terraria's x).
	var cam := game.player.camera
	var across := velocity.dot(cam.global_transform.basis.x)
	spin -= across * 0.05
	var r: Dictionary = game.world.move_aabb(global_position, _half, velocity * PX, 0.0, false)
	global_position = r.position
	var blocked: Vector3i = r.blocked
	if blocked.x:
		velocity.x = 0.0
	if blocked.z:
		velocity.z = 0.0
	if blocked.y:
		velocity.y = 0.0
	if r.on_floor:
		velocity.x *= 0.97
		velocity.z *= 0.97
		if Vector2(velocity.x, velocity.z).length() < 0.01:
			velocity.x = 0.0
			velocity.z = 0.0
