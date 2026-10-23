class_name FlyingPiggyBank
extends Node3D
## The Money Trough's Flying Piggy Bank (Terraria's projectile 525, aiStyle
## 97), in its px/tick (24 px a block): it's thrown out at 4 px/tick and
## slows x0.94 a tick till it stops, then bobs where it is (0.005 px/tick²
## up for 45 ticks, then turning every 90), facing you, flapping (frames
## 0 1 2 3 4 3 2 1, 4 ticks each). It's gone after 3 minutes (10800 ticks)
## or when you throw out another. Right-click it to open your Piggy Bank.

const PX := 24.0
const PX_TICK := 60.0 / PX
const LIFE := 10800
const FLAP := [0, 1, 2, 3, 4, 3, 2, 1]
## Its hitbox (30 x 24 px).
const HALF := Vector3(15.0, 12.0, 15.0) / PX

var velocity := Vector3.ZERO
var _ticks := 0
var _bob := 45.0
var _settled := false
var _acc := 0.0
var _sprite := EntitySprite.new()


func setup(at: Vector3, dir: Vector3) -> void:
	position = at
	velocity = dir.normalized() * 4.0 * PX_TICK
	var tex := Assets.texture("Images/Projectile_525")
	_sprite.setup(tex, 5, Vector2(tex.get_width(), tex.get_height() / 5.0) / PX, true)
	add_child(_sprite)


func _process(delta: float) -> void:
	var game := Game.current
	if game == null:
		return
	_acc = minf(_acc + delta, 0.25)
	while _acc >= 1.0 / 60.0:
		_acc -= 1.0 / 60.0
		_tick()
		if is_queued_for_deletion():
			return
	global_position += velocity * delta
	var cam: Camera3D = game.player.camera
	_sprite.set_frame(FLAP[(_ticks / 4) % FLAP.size()])
	if not _settled and Vector2(velocity.x, velocity.z).length() > 0.01:
		_sprite.set_flip(velocity.dot(cam.global_transform.basis.x) > 0.0)
	elif _settled:
		_sprite.set_flip((game.player.global_position - global_position).dot(cam.global_transform.basis.x) > 0.0)
	_sprite.update_light(game.world, game.sky, global_position)


func _tick() -> void:
	_ticks += 1
	if _ticks >= LIFE:
		queue_free()
		return
	if not _settled:
		if velocity.length() / PX_TICK < 0.1:
			velocity = Vector3.ZERO
			_settled = true
			_bob = 45.0
		else:
			velocity *= 0.94
		return
	_bob += 1.0
	velocity.y += (0.005 if _bob > 0.0 else -0.005) * PX_TICK
	if _bob >= 90.0:
		_bob = -_bob


## Whether a look from `origin` along `fwd` hits it within `reach` blocks.
func aimed(origin: Vector3, fwd: Vector3, reach: float) -> bool:
	var along := (global_position - origin).dot(fwd)
	if along <= 0.0 or along > reach:
		return false
	var off := origin + fwd * along - global_position
	return absf(off.y) < HALF.y + 0.2 and Vector2(off.x, off.z).length() < HALF.x + 0.3
