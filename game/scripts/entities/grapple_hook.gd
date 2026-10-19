class_name GrappleHook
extends Node3D
## A grappling hook (Terraria's AI_007_GrapplingHooks): it flies out at its
## speed until it's `reach` from you, then comes back; touching a block or
## platform it latches on, and while one is latched you're pulled to it
## (Player._grapple). Drawn as its Projectile sheet at the end of a line of
## its chain links back to your hand.

enum { FLYING, RETRACTING, LATCHED }

## px -> blocks: a tile (16 px) is 2/3 of a block.
const PX := 1.0 / 24.0
## px a tick -> blocks a second.
const PX_TICK := 60.0 / 24.0
## It goes when it's this far from you (2500 px), or back within 24 px.
const LOST := 2500.0 * PX
const HOME := 24.0 * PX

var player  # the Player who threw it (untyped: Player refers back to this class)
## The item's "hook": projectile, speed, reach, retract, fly, out, latched,
## updates, chain.
var def := {}
var state := FLYING
var velocity := Vector3.ZERO
## The block it holds on to.
var cell := Vector3i.ZERO
## When it was thrown (the oldest goes first, Terraria's timeLeft).
var born := 0
var sprite := EntitySprite.new()
var _links: Array[EntitySprite] = []
var _link_tex: Texture2D
var _link_len := 0.5
static var _count := 0


func setup(p: Node3D, hook: Dictionary, dir: Vector3) -> void:
	player = p
	def = hook
	_count += 1
	born = _count
	velocity = dir.normalized() * float(def.speed) * PX_TICK * _updates()
	var tex := Assets.texture("Images/Projectile_%d" % int(def.projectile))
	sprite.setup(tex, 1, Vector2(tex.get_width(), tex.get_height()) * PX, true, true)
	add_child(sprite)
	_link_tex = Assets.texture("Images/" + str(def.chain))
	_link_len = _link_tex.get_height() * PX
	add_to_group("grapple_hooks")


func _updates() -> int:
	return int(def.get("updates", 1))


func latched() -> bool:
	return state == LATCHED


## Something a hook holds on to: a solid block or a platform (not a tree).
static func can_latch(world: VoxelWorld, p: Vector3i) -> bool:
	var b := Data.block(world.get_block(p))
	if b.is_empty() or b.get("trunk", false):
		return false
	return world.is_solid(p) or b.get("platform", false)


func _physics_process(delta: float) -> void:
	var game := Game.current
	if not is_instance_valid(player) or not player.alive:
		queue_free()
		return
	var w: VoxelWorld = game.world
	var dist := global_position.distance_to(player.center())
	if dist > LOST:
		queue_free()
		return
	match state:
		FLYING:
			if dist > float(def.reach) * PX:
				state = RETRACTING
			else:
				_fly(w, delta)
		RETRACTING:
			if dist < HOME:
				queue_free()
				return
			velocity = (player.center() - global_position).normalized() * float(def.retract) * PX_TICK * _updates()
			global_position += velocity * delta
		LATCHED:
			if not can_latch(w, cell):
				state = RETRACTING
	_draw(game)


## Flies on in steps of at most a tenth of a block; the first step into a
## block it can hold latches it there, at the block's face.
func _fly(w: VoxelWorld, delta: float) -> void:
	var move := velocity * delta
	var steps := maxi(1, ceili(move.length() / 0.1))
	for i in steps:
		var next := global_position + move / steps
		var c := Vector3i(next.floor())
		if can_latch(w, c):
			_latch(c)
			return
		global_position = next


func _latch(c: Vector3i) -> void:
	state = LATCHED
	cell = c
	velocity = Vector3.ZERO
	# Past its limit of latched hooks, the oldest lets go (Terraria's l26).
	var mine: Array = player.hooks().filter(func(h): return h.latched())
	if mine.size() > int(def.get("latched", 3)):
		var oldest: GrappleHook = null
		for h in mine:
			if h != self and (oldest == null or h.born < oldest.born):
				oldest = h
		if oldest != null:
			oldest.queue_free()
	Audio.play_at("Dig_*", global_position, 0.7)
	player.on_hook_latched()


func _draw(game) -> void:
	var hand: Vector3 = player.hook_hand()
	var to := global_position - hand
	# The hook's point away from you, along its line.
	sprite.set_axis(to)
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
		if not l.visible:
			continue
		# From the hook back toward your hand, a link length apart.
		var at := global_position - to.normalized() * _link_len * (i + 0.5)
		l.global_position = at
		l.set_axis(to)
		l.update_light(game.world, game.sky, at)
