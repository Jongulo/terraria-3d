class_name Projectile
extends Node3D
## Arrows, bullets, bolts and thrown weapons. Friendly projectiles hit NPCs,
## hostile ones hit the player; all of them stop at solid blocks. Explosives
## (an item's "explosive") instead bounce, roll or stick until their fuse
## runs out, then go off (Game.explode).

var velocity := Vector3.ZERO
var gravity := 0.0
var damage := 0
var knockback := 0.0
var friendly := true
## Chance (0..1) of a critical hit, from the shooter (Player.crit_chance).
var crit := 0.04
var life := 3.0
var penetrate := 1
var spin := 0.0
var sprite := EntitySprite.new()
var _hit := {}
var _angle := 0.0
## Bombs, dynamite, grenades: the item's "explosive" ({} for other projectiles).
var explosive := {}
var _stuck := false
var _smoke := 0.0
## Its ProjectileID name.
var kind := ""
## Defense its hits ignore (the Sharpening Station's, for melee).
var armor_pen := 0
## Each enemy pierced takes this share off its damage (Glacier Fang: 34%).
var pierce_falloff := 0.0
## How far from its centre it hits enemies.
var radius := 0.3
## Gravity starts this late (Terraria's thrown aiStyle 2: after 20 ticks,
## slowing as it falls), and `drag` of its sideways speed is lost a second.
var gravity_delay := 0.0
var drag := 0.0
## A sheet frame held, not animated (-1: animated).
var frame := -1
## Lit, unshaded (the Ice Bolt's white light).
var glow := Color.BLACK
var _age := 0.0
var _zigzag := Vector2.ZERO
var _zig_offset := Vector3.ZERO
## How far from its centre the bomb touches blocks.
const BOMB_RADIUS := 0.18


## Projectiles whose sheet is an animation (frames stacked down it), drawn
## pointing right instead of up, or up and right (the Enchanted Beam: AI 27
## turns it its velocity's angle + 0.785); "styles": the frames are looks, one
## picked at random and held (the Book of Skulls' three skulls); "long": laid
## along its flight though not twice as long as it's wide (the stingers);
## "fps": its frames a second (else 20; the Flamelash's every 5 ticks, the
## Hellwing's every 2).
const SHEETS := {"ThunderSpearShot": {"frames": 4, "right": true}, "ThunderStaffShot": {"frames": 4}, "GlacierFangShot": {"frames": 3},
		"EnchantedBeam": {"diagonal": true}, "BookOfSkullsSkull": {"frames": 3, "styles": true},
		"Stinger": {"long": true}, "QueenBeeStinger": {"long": true},
		"Flamelash": {"frames": 8, "fps": 12}, "Hellwing": {"frames": 5, "right": true, "fps": 30}, "Volcano": {"frames": 5, "fps": 30},
		"Ghoulder": {"frames": 10}, "RainbowBoulder": {"frames": 100}, "LibrarianSkeletonBook": {"frames": 54}}
## How some fly (Terraria's AI for them): zigzag [sideways reach, seconds a
## swing] across the way it's going (the Thunder Zapper's bolt), and how
## long it lasts; a trail of dust [Terraria dust ids, one picked at random each
## tick] once it has flown "dust_after" ticks (the Enchanted Beam, AI 27: at
## its tail, a tenth of its speed).
## ghost: flies through blocks (the Book of Skulls' skull: tileCollide off);
## home: turns toward the nearest enemy within 25 blocks (how hard it turns). Water Bolt (AI 8): bounces off blocks; pierce: how many enemies it goes
## through (Terraria's penetrate); gravity in blocks/s^2 (the Aqua Scepter's
## stream, AI 12: 0.075 px a tick each of its 3 updates); hidden: no sprite,
## only its dust (Terraria draws them at alpha 255); glow: lit by itself
## (the Magic Missile's light); xray: seen through blocks like the boss that
## shot it (the Queen Bee's stingers). scythe: Terraria's AI 18 (the Demons'
## Demon Scythes and the weapon's): spinning (0.8 a tick), from its 30th tick
## to its 100th it speeds up 1.06 a tick; size: drawn that big (blocks);
## radius: how far from its centre it hits, enemies or you.
## Ball of Fire (the Flower of Fire's, AI 8): falls from its 20th tick
## (gravity_after) at 0.2 px a tick (45 blocks/s^2) up to 16 px a tick
## (max_fall: 60 blocks/s), spinning 0.3 a tick, and dies on its 6th touch of
## a block, Item10 each bounce. ignite: [1 in n, min, max ticks] On Fire! on
## the enemies it hits (Terraria's StatusNPC: the Ball of Fire 1 in 2 for 300,
## the Flamelash 1 in 2 for 240-479, the Flaming Arrow 1 in 3 for 180). hellwing: [aim, launch] (the Hellwing
## Bow's, AI 1): fired turned by up to half `launch` either way, it steers
## toward its way turned up to half `aim` (each tick its velocity is 39/40 of
## itself and 1/40 of that); Terraria's penetrate -1 (each enemy hit once).
## blast: when it dies (a block, an enemy, its time), it hurts every other
## enemy within that many blocks (the Hellfire Arrow: Terraria's 64 px box).
## melee: its hits are melee hits (the Magma Stone's Hellfire). The Volcano
## (the Fiery Greatsword's, AI 189): where it stands, 10 ticks, Terraria's
## 160 px box (here 80 px at 24 a block round it), each enemy once, 3 at most,
## On Fire! 3 s every hit.
const FLIGHT := {"ThunderStaffShot": {"zigzag": [0.35, 0.1], "life": 1.0},
		"EnchantedBeam": {"dust": [15, 57, 58], "dust_after": 7},
		"WaterBolt": {"bounce": 10, "pierce": 10, "hidden": true, "dust": [29], "life": 10.0},
		"WaterStream": {"gravity": 50.6, "pierce": 5, "hidden": true, "dust": [33], "life": 2.0},
		"MagicMissile": {"dust": [15], "glow": true, "life": 10.0},
		"BookOfSkullsSkull": {"ghost": true, "home": 0.6, "pierce": 3, "life": 8.0},
		"ChaosBall": {"ghost": true, "hidden": true, "dust": [27]},
		"BurningSphere": {"ghost": true, "hidden": true, "dust": [6]},
		"DemonSickle": {"scythe": true, "dust": [27], "size": 1.8, "radius": 0.9, "life": 5.0},
		"DemonScythe": {"scythe": true, "dust": [27], "size": 1.8, "radius": 0.9, "pierce": 5, "life": 60.0},
		"Stinger": {"dust": [18]}, "QueenBeeStinger": {"dust": [147], "life": 5.0, "xray": true},
		"BallofFire": {"bounce": 5, "bounce_sound": "Item_10", "gravity": 45.0, "gravity_after": 20, "max_fall": 60.0, "spin": 18.0,
			"dust": [6], "glow": true, "size": 0.5, "radius": 0.25, "ignite": [2, 300, 300], "life": 60.0},
		"Flamelash": {"dust": [6], "glow": true, "pierce": 2, "size": 1.5, "radius": 0.5, "ignite": [2, 240, 479], "life": 60.0},
		"Hellwing": {"hellwing": [0.3927, 0.19635], "gravity": 0.0, "pierce": 1000000, "dust": [6], "glow": true, "size": 0.94, "radius": 0.375, "life": 20.0},
		"HellfireArrow": {"blast": 1.35, "dust": [31, 6]},
		"FireArrow": {"ignite": [3, 180, 180], "dust": [6], "glow": true},
		"WaterSphere": {"ghost": true, "hidden": true, "dust": [172]},
		"PoisonDart": {"poison": 10.0, "life": 60.0},
		"Boulder": {"size": 1.0, "radius": 0.6, "life": 60.0}, "BoulderThatSpawnsPet": {"size": 1.0, "radius": 0.6, "life": 60.0},
		"BouncyBoulder": {"size": 1.0, "radius": 0.6, "life": 60.0}, "LavaBoulder": {"size": 1.0, "radius": 0.6, "life": 60.0},
		"RainbowBoulder": {"size": 1.0, "radius": 0.6, "life": 60.0, "glow": true},
		"Ghoulder": {"size": 1.06, "radius": 0.6, "life": 15.0},
		"LibrarianSkeletonBook": {"book": true, "ghost": true, "size": 1.0, "radius": 0.35, "life": 7.0},
		"Volcano": {"ghost": true, "pierce": 3, "radius": 3.33, "size": 2.2, "life": 10.0 / 60.0, "ignite": [1, 180, 180], "glow": true, "melee": true}}
## Hostile shots that poison you one hit in three, for 10 s (Terraria's
## StatusPlayer: the Hornet's and the Queen Bee's stingers).
const POISONS := ["Stinger", "QueenBeeStinger"]
## Hostile shots that set you on fire one hit in three, for 7 s (Terraria's
## StatusFromNPC: the Fire Imp's Burning Sphere, there an NPC).
const IGNITES := ["BurningSphere"]
var _ticks := 0.0
## Bounces left off blocks (Water Bolt).
var bounces := 0
## The player steering it while they hold the button (a channelled spell:
## the Magic Missile flies toward their crosshair, Terraria's AI 9).
var steered_by = null
## A rolling boulder (a trap's: Terraria's AI 25), and the way it rolls.
var boulder := false
var _roll := Vector3.ZERO
## Ticks since it set off (Terraria's localAI[2]); hard bounces (localAI[1]).
var _boulder_ticks := 0.0
var _hard_bounces := 0
## A Ghoulder that has hit something: the ghost (Terraria's ai[1] 1), and how
## far through its look it is.
var _ghost := false
var _ghost_frame := 0.0
## A Rainbow Boulder's jump: ticks left flying through blocks (its ai[1]).
var _jump := 0.0
## Who a Librarian Skeleton's book flies at (its ai[2]), its look (one of
## six), and whether it has set off.
var target = null
var _book_style := 0
var _launched := false
var _flight := {}
var _frames := 1
var _fps := 20.0
var _frame_t := 0.0
## The way a Hellwing steers toward (its "hellwing" flight).
var _aim := Vector3.ZERO
var _turn := PI
## A long, thin sprite (arrows, bullets, bolts): laid along its flight in 3D
## (EntitySprite.set_axis) rather than turned on the screen.
var _axial := false
var _trail: Array = []
var _trail_ticks := 0.0


## `proj` is a ProjectileID name; its sprite sheet is Projectile_<id>.
func setup(proj: String, size := 0.5) -> void:
	kind = proj
	var id: int = Assets.ids.ProjectileID.get(proj, 1)
	var tex := Assets.texture("Images/Projectile_%d" % id)
	if proj == "RainbowBoulder":
		tex = _grid_strip(tex, 5, 20)
	elif proj == "LibrarianSkeletonBook":
		tex = _grid_strip(tex, 6, 9)
	var sheet: Dictionary = SHEETS.get(proj, {})
	_frames = int(sheet.get("frames", 1))
	_fps = float(sheet.get("fps", 20.0))
	if sheet.get("styles", false):
		frame = randi() % _frames
	if sheet.get("right", false):
		_turn = PI / 2.0
	elif sheet.get("diagonal", false):
		_turn = PI * 0.75
	var aspect := float(tex.get_width()) / tex.get_height() * _frames
	size = float(FLIGHT.get(proj, {}).get("size", size))
	sprite.setup(tex, _frames, Vector2(size * aspect, size), true, true)
	add_child(sprite)
	# Long along the way it points: up the sheet, or across it for the ones
	# drawn pointing right.
	_axial = (aspect >= 2.0) if _turn == PI / 2.0 else ((aspect <= 0.5 or sheet.get("long", false)) and _turn == PI)
	if _axial:
		# Its point along the axis: the sprite turned from pointing up (or right).
		sprite.set_rotation_angle(PI - _turn)
	var flight: Dictionary = FLIGHT.get(proj, {})
	_flight = flight
	sprite.set_xray(flight.get("xray", false))
	bounces = int(flight.get("bounce", 0))
	if flight.get("hidden", false):
		sprite.visible = false
	if flight.has("zigzag"):
		_zigzag = Vector2(flight.zigzag[0], flight.zigzag[1])
	life = float(flight.get("life", life))
	_trail = flight.get("dust", [])
	_trail_ticks = -float(flight.get("dust_after", 0))
	if proj == "Ghoulder":
		frame = 0
	elif proj == "LibrarianSkeletonBook":
		# Terraria: one of six books, one of its three closed looks.
		_book_style = randi() % 6
		frame = _book_style * 9 + randi() % 3


## A sheet of `cols` columns of `rows` frames, its frames running down each
## column and on into the next (the Rainbow Boulder's colours, the
## Librarian Skeleton's six books), laid out as one strip.
static func _grid_strip(tex: Texture2D, cols: int, rows: int) -> Texture2D:
	var img := tex.get_image()
	var w := img.get_width() / cols
	var h := img.get_height() / rows
	var out := Image.create(w, h * cols * rows, false, img.get_format())
	for f in cols * rows:
		out.blit_rect(img, Rect2i((f / rows) * w, (f % rows) * h, w, h), Vector2i(0, f * h))
	return ImageTexture.create_from_image(out)


func _ready() -> void:
	# After the spawner has set what the item gives it.
	if _flight.has("gravity"):
		gravity = float(_flight.gravity)
	if _flight.has("pierce"):
		penetrate = int(_flight.pierce)
	if _flight.get("glow", false):
		glow = Color(0.4, 0.6, 1.0)
	if _flight.has("radius"):
		radius = float(_flight.radius)
	if _flight.get("scythe", false):
		spin = 48.0  # 0.8 a tick
	if _flight.has("spin"):
		spin = float(_flight.spin)
	if _flight.has("gravity_after"):
		gravity_delay = float(_flight.gravity_after) / 60.0
	if _flight.has("hellwing"):
		_aim = _turned(velocity, float(_flight.hellwing[0]))
		velocity = _turned(velocity, float(_flight.hellwing[1]))


## Terraria's RotatedByRandom: turned by up to half `most` either way (here
## about a random axis across the way it goes).
static func _turned(v: Vector3, most: float) -> Vector3:
	var axis := v.cross(Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1))).normalized()
	if axis == Vector3.ZERO:
		return v
	return v.rotated(axis, randf() * most - most / 2.0)


func _physics_process(delta: float) -> void:
	var game := Game.current
	if _flight.has("home") and friendly:
		var best: NPC = null
		var best_d := 25.0
		for npc in game.npcs():
			if npc.def.ai in ["town", "dummy"] or npc.untouchable or npc.dont_take_damage:
				continue
			var dd: float = npc.center().distance_to(global_position)
			if dd < best_d:
				best_d = dd
				best = npc
		if best != null:
			var speed := velocity.length()
			velocity = velocity.lerp((best.center() - global_position).normalized() * speed, minf(1.0, float(_flight.home) * delta * 6.0)).normalized() * speed
	if steered_by != null:
		if is_instance_valid(steered_by) and steered_by.alive and steered_by.use_down():
			var to: Vector3 = steered_by.aim_point() - global_position
			if to.length() > 0.3:
				var speed := velocity.length()
				velocity = velocity.lerp(to.normalized() * speed, minf(1.0, delta * 8.0)).normalized() * speed
		else:
			steered_by = null
	if not explosive.is_empty():
		_explosive_step(delta, game)
		return
	if boulder:
		_boulder_step(delta, game)
		return
	if _aim != Vector3.ZERO:
		velocity = velocity.lerp(_aim, 1.0 - pow(39.0 / 40.0, delta * 60.0))
	if _flight.get("book", false):
		_book_step(delta, game)
	life -= delta
	_age += delta
	if _flight.get("scythe", false):
		var was := int(_ticks)
		_ticks += delta * 60.0
		for t in range(was + 1, int(_ticks) + 1):
			if t >= 30 and t < 100:
				velocity *= 1.06
	if not _trail.is_empty():
		_trail_ticks += delta * 60.0
		while _trail_ticks >= 1.0:
			_trail_ticks -= 1.0
			# 4 ticks of its flight behind it, a tenth of its speed (px a tick).
			game.dust.spawn(int(_trail.pick_random()), global_position - velocity * 4.0 / 60.0, velocity * 0.1 * 16.0 / 60.0, 1.25)
	if _age >= gravity_delay:
		velocity.y -= gravity * delta
		if _flight.has("max_fall"):
			velocity.y = maxf(velocity.y, -float(_flight.max_fall))
		if drag > 0.0:
			var keep := pow(1.0 - drag, delta)
			velocity.x *= keep
			velocity.z *= keep
	var step := velocity * delta
	# The Thunder Zapper's bolt zigzags across its way (straight up or down
	# it doesn't).
	if _zigzag.x > 0.0:
		var side := Vector3(-velocity.z, 0, velocity.x).normalized()
		var phase := fmod(_age / _zigzag.y, 2.0)
		var want := side * _zigzag.x * (1.0 - absf(phase - 1.0) * 2.0)
		step += want - _zig_offset
		_zig_offset = want
	# Sub-step so fast bullets don't skip through blocks or enemies.
	var n := int(ceil(step.length() / 0.4))
	for i in maxi(n, 1):
		global_position += step / maxi(n, 1)
		# The player's projectiles cut grass, vines, cobwebs, pots...
		if friendly and damage > 0:
			game.cut_tiles_at(global_position, 0.25)
		if not _flight.get("ghost", false) and game.world.is_solid(Vector3i(global_position.floor())):
			if bounces > 0:
				# Back out and turn round on the axes that ran into the block.
				bounces -= 1
				var sub := step / maxi(n, 1)
				global_position -= sub
				var turned := false
				for axis in 3:
					var probe := global_position
					probe[axis] += sub[axis]
					if game.world.is_solid(Vector3i(probe.floor())):
						velocity[axis] = -velocity[axis]
						turned = true
				if not turned:
					velocity = -velocity
				if _flight.has("bounce_sound"):
					Audio.play_at(_flight.bounce_sound, global_position, 0.5)
				break
			Audio.play_at("Dig_*", global_position, 0.4)
			_die(game)
			return
		if _check_hits(game):
			_die(game)
			return
	if life <= 0:
		_die(game)
		return
	var cam := game.player.camera
	if spin != 0.0:
		_angle += spin * delta
		sprite.set_rotation_angle(_angle)
	elif _axial:
		sprite.set_axis(velocity)
	else:
		# Terraria projectile sprites point up; turn them along the flight path.
		sprite.set_rotation_angle(EntitySprite.facing_angle(cam, velocity) + _turn)
	if frame >= 0:
		sprite.set_frame(frame)
	elif _frames > 1:
		_frame_t += delta
		sprite.set_frame(int(_frame_t * _fps) % _frames)
	if glow != Color.BLACK:
		sprite.set_glow()
	else:
		sprite.update_light(game.world, game.sky, global_position)


## A lit explosive: falls, bounces off blocks (losing speed, rolling to a
## stop), or sticks to the first thing it touches; a grenade goes off on
## hitting an enemy. Smoke trails from its fuse; when it burns down, boom.
func _explosive_step(delta: float, game) -> void:
	life -= delta
	_smoke -= delta
	if _smoke <= 0.0 and not explosive.get("spiky", false):
		_smoke = 0.25
		game.spawn_dust(global_position + Vector3(0, 0.25, 0), Color(0.55, 0.55, 0.55), 1)
	if not _stuck:
		velocity.y -= gravity * delta
		var w: VoxelWorld = game.world
		for axis in 3:
			var move := velocity[axis] * delta
			if move == 0.0:
				continue
			var to := global_position
			to[axis] += move
			var edge := to
			edge[axis] += signf(move) * BOMB_RADIUS
			if w.is_solid(Vector3i(edge.floor())):
				if explosive.get("sticky", false):
					_stuck = true
					velocity = Vector3.ZERO
					break
				velocity[axis] *= -float(explosive.get("bounce", 0.3))
				if axis == 1:
					# On the ground: rolls to a stop.
					velocity.x *= 0.7
					velocity.z *= 0.7
				if absf(velocity[axis]) > 1.5:
					Audio.play_at("Dig_*", global_position, 0.25)
			else:
				global_position = to
		# Rolling along the ground slows it down.
		if w.is_solid(Vector3i((global_position - Vector3(0, BOMB_RADIUS + 0.05, 0)).floor())):
			var keep := exp(-2.5 * delta)
			velocity.x *= keep
			velocity.z *= keep
		if explosive.get("contact", false):
			for npc in game.npcs():
				if not npc.def.get("invulnerable", false) and not npc.dont_take_damage and npc.overlaps_point(global_position, 0.3):
					life = 0.0
	# A Spiky Ball (Terraria's aiStyle 14): no blast; rolling or lying still,
	# it hurts each enemy that touches it once, `pierce` of them in all.
	if explosive.get("spiky", false):
		if _check_hits(game) or life <= 0.0:
			queue_free()
			return
	var speed := velocity.length()
	if speed > 0.5:
		_angle += spin * delta * minf(1.0, speed / 6.0)
	sprite.set_rotation_angle(_angle)
	sprite.update_light(game.world, game.sky, global_position)
	if life <= 0.0:
		game.explode(global_position, damage, knockback, explosive)
		queue_free()


## The Librarian Skeleton's book (Terraria's projectile 1092): it rises (3 px
## a tick, keeping 95% of that a tick) for 45 ticks, hurting nothing, then
## flies open at its target at 9 px a tick, through the blocks.
func _book_step(delta: float, game) -> void:
	if _launched:
		return
	velocity.y *= pow(0.95, delta * 60.0)
	if _age + delta < 45.0 / 60.0:
		return
	_launched = true
	var who = target if is_instance_valid(target) else game.player
	var to: Vector3 = who.global_position + Vector3(0, 0.9, 0) - global_position
	velocity = (to.normalized() if to.length() > 0.01 else Vector3.DOWN) * 9.0 * 3.75
	frame = _book_style * 9 + 3 + randi() % 6


## Terraria's boulders (AI 25, its tile collisions and Projectile.Kill), in
## its px a tick (16 a block for shots). Each falls at 0.3 a tick (to 16)
## and, on the ground, picks the way with the longest run of floor (Terraria:
## away from the nearest wall), speeding up 0.05 a tick to 7 while it isn't
## falling fast (6). For its first 7 ticks it hurts nothing; then it hurts you
## (doubled, as hostile) and each enemy it rolls into once.
## - Boulder: landing faster than 5 bounces it up a fifth; a wall breaks it.
## - The boulder that leaves a pet breaks on that landing too (its Friendly
##   Boulder pet isn't here: no pets yet).
## - Lava Boulder: trails fire, sets what it hits On Fire! (5 s), breaks in
##   any liquid, and where it breaks lava fills 4 tiles round it (here 2.7
##   blocks) wherever it can see.
## - Ghoulder (15 s): a wall or a hard landing turns it into a ghost that
##   flies through blocks at you (6 a tick, 1/36 of the way each tick) while
##   you look away, and stops and drops when you look at it.
## - Bouncy Boulder: bounces off everything, keeping 95% of its speed (less
##   when slow); breaks after 20 hard bounces (faster than 5, or any once it's
##   500 ticks old) or when it stops after 50 ticks.
## - Rainbow Boulder (100 damage): friendly - it never hurts you - bounces as
##   the Bouncy one and on every bounce leaps (through blocks while it flies)
##   at the nearest enemy in view, else the best treasure in view (Terraria's
##   ore finder: a big ore vein, a chest, a Life Crystal...), else you;
##   it leaps back when it's out of your view (1 in 4 a tick), now and then
##   anyway (1 in 180), and breaks on hitting a boss.
func _boulder_step(delta: float, game) -> void:
	var w: VoxelWorld = game.world
	var tick := delta * 60.0
	life -= delta
	_boulder_ticks += tick
	if kind == "Ghoulder" and _ghost:
		_ghoulder_step(delta, game)
	elif kind in ["BouncyBoulder", "RainbowBoulder"]:
		if not _bounce_step(delta, game):
			return
	elif not _roll_step(delta, game):
		return
	if kind == "LavaBoulder":
		if randi() % 3 == 0:
			game.dust.spawn(6, global_position + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)), Vector3(0, 0.15, 0), 1.5)
		var liquid: Vector2i = w.get_liquid(Vector3i(global_position.floor()))
		if liquid.y > 0:
			_boulder_break(game)
			return
	if kind == "RainbowBoulder":
		frame = int(_boulder_ticks / 2.0) % 100
	if frame >= 0:
		sprite.set_frame(frame)
	sprite.set_rotation_angle(_angle)
	sprite.update_light(w, game.sky, global_position)
	if _boulder_ticks > 7.0 or kind == "RainbowBoulder":
		_boulder_hits(game)
	if life <= 0.0 and is_inside_tree():
		queue_free()


## Rolls (the Boulder, Lava Boulder, pet boulder, a Ghoulder before it turns).
## False when it broke.
func _roll_step(delta: float, game) -> bool:
	var w: VoxelWorld = game.world
	velocity.y = maxf(velocity.y - 0.3 * 225.0 * delta, -16.0 * 3.75)
	var below := Vector3i((global_position - Vector3(0, 0.55, 0)).floor())
	if w.is_solid(below) and _roll == Vector3.ZERO:
		_pick_roll(w)
	# The Ghoulder speeds up even while it falls fast.
	if _roll != Vector3.ZERO and (velocity.y > -6.0 * 3.75 or kind == "Ghoulder"):
		var along := velocity.dot(_roll)
		along = minf(along + 0.05 * 225.0 * delta, 7.0 * 3.75)
		velocity = _roll * along + Vector3(0, velocity.y, 0)
	var next := global_position + velocity * delta
	if velocity.y < 0.0 and w.is_solid(Vector3i((next - Vector3(0, 0.5, 0)).floor())):
		if velocity.y < -5.0 * 3.75:
			velocity.y = -velocity.y * 0.2
			Audio.play_at("Dig_*", global_position, 0.6)
			if kind == "LavaBoulder":
				for i in 10:
					game.dust.spawn(6, global_position + Vector3(randf_range(-0.5, 0.5), -0.3, randf_range(-0.5, 0.5)), Vector3(randf_range(-1, 1), 0.5, randf_range(-1, 1)), 2.0)
			elif kind == "Ghoulder":
				_ghost = true
			elif kind == "BoulderThatSpawnsPet":
				_boulder_break(game)
				return false
		else:
			velocity.y = 0.0
		next.y = global_position.y
	if _roll != Vector3.ZERO and w.is_solid(Vector3i((next + _roll * 0.5).floor())):
		if kind == "Ghoulder":
			_ghost = true
			velocity -= _roll * velocity.dot(_roll)
			Audio.play_at("Dig_*", global_position, 0.6)
			return true
		_boulder_break(game)
		return false
	global_position = next
	_angle -= velocity.length() * delta / 0.5
	return true


## The way with the longest run of floor ahead.
func _pick_roll(w: VoxelWorld) -> void:
	var best := -1
	for d in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
		var n := 0
		while n < 12:
			var c := Vector3i((global_position + d * (n + 1)).floor())
			if w.is_solid(c) or not w.is_solid(c + Vector3i.DOWN):
				break
			n += 1
		if n > best or (n == best and randi() % 2 == 0):
			best = n
			_roll = d


## The Bouncy and Rainbow Boulders: a bounce off whatever they meet, each way
## on its own (Terraria's per-axis tile collision). False when it broke.
func _bounce_step(delta: float, game) -> bool:
	var w: VoxelWorld = game.world
	var tick := delta * 60.0
	var rainbow := kind == "RainbowBoulder"
	velocity.y = maxf(velocity.y - 0.3 * 225.0 * delta, -16.0 * 3.75)
	if rainbow:
		_jump = maxf(0.0, _jump - tick)
		var off_view := not _in_view(game.player, global_position)
		if (off_view and randf() < 1.0 - pow(0.75, tick)) or randf() < tick / 180.0:
			_rainbow_leap(game)
	var flying := rainbow and (_jump > 0.0 or w.box_hits_solid(global_position - Vector3(0, 0.45, 0), Vector3(0.45, 0.9, 0.45)))
	var on_ground := w.is_solid(Vector3i((global_position - Vector3(0, 0.55, 0)).floor()))
	if not flying:
		if on_ground and _roll == Vector3.ZERO:
			_pick_roll(w)
		if _roll != Vector3.ZERO and velocity.y > -6.0 * 3.75:
			var flat := Vector3(velocity.x, 0, velocity.z)
			var dir := flat.normalized() if flat.length() > 0.05 else _roll
			velocity += dir * (0.05 * 225.0 * delta) * (1.0 if flat.length() < 7.0 * 3.75 else 0.0)
	var next := global_position + velocity * delta
	var bounced := false
	var hard := false
	if not flying:
		for axis in 3:
			var probe := global_position
			probe[axis] = next[axis] + signf(velocity[axis]) * 0.5
			if velocity[axis] != 0.0 and w.is_solid(Vector3i(probe.floor())):
				var v := absf(velocity[axis]) / 3.75
				var keep := 0.95 if v >= 1.0 else (0.5 if v >= 0.75 else (0.25 if v >= 0.5 else 0.1))
				if v > 5.0 or (not rainbow and _boulder_ticks >= 500.0):
					hard = true
				velocity[axis] = -velocity[axis] * keep
				next[axis] = global_position[axis]
				if axis != 1:
					_roll = Vector3(velocity.x, 0, velocity.z).normalized()
				bounced = true
	if hard:
		_hard_bounces += 1
		Audio.play_at("Custom/rainbow_boulder" if rainbow else "Dig_*", global_position, 0.6)
	if not rainbow and (_hard_bounces > 20 or (velocity.length() < 0.1 * 3.75 and _boulder_ticks > 50.0)):
		_boulder_break(game)
		return false
	global_position = next
	_angle -= Vector3(velocity.x, 0, velocity.z).length() * delta / 0.5
	if rainbow and bounced:
		_rainbow_leap(game)
	return is_inside_tree()


## Within the player's view (Terraria's MaxWorldViewSize round them: here
## 40 blocks either way across, 25 up and down).
static func _in_view(p, at: Vector3) -> bool:
	var d: Vector3 = at - p.global_position
	return absf(d.x) <= 40.0 and absf(d.z) <= 40.0 and absf(d.y) <= 25.0


## Terraria's ore finder priorities by tile (Main.SetTileValue): pots, the
## ores, meteorite, chests, Life Crystals...
const TREASURE := {28: 100, 7: 200, 166: 210, 6: 220, 167: 230, 9: 240, 168: 250, 8: 260, 169: 270, 22: 300, 204: 310,
		37: 400, 21: 500, 467: 500, 441: 500, 468: 500, 12: 550, 107: 600, 221: 610, 108: 620, 222: 630, 111: 640, 223: 650,
		129: 675, 211: 700, 227: 750, 236: 810}
## The ores that count only as part of a big vein (Terraria: 40 of the 7 x 7
## tiles round it; here 40 of the 5 x 5 x 5 blocks).
const VEIN_ORES := [7, 166, 6, 167, 9, 168, 8, 169, 22, 204, 37, 107, 221, 108, 222, 111, 223, 211]
static var _treasure_ids := {}


## RainbowBoulder_PerformSmartBounce: never more than 7 at once; then a leap.
func _rainbow_leap(game) -> void:
	var others := 0
	for n in get_parent().get_children():
		if n != self and n is Projectile and n.kind == kind and not n.is_queued_for_deletion():
			others += 1
	if others >= 7:
		_boulder_break(game)
		return
	var p = game.player
	var best = null
	var best_d := INF
	for npc in game.npcs():
		if npc.def.ai in ["town", "dummy"] or npc.untouchable or npc.dont_take_damage or npc.is_critter():
			continue
		if not _in_view(p, npc.global_position):
			continue
		var dd := global_position.distance_to(npc.global_position)
		if dd < best_d:
			best_d = dd
			best = npc
	if best != null:
		_leap_to(best.global_position + Vector3(0, 0.5, 0))
		return
	var spot = _treasure(game)
	if spot != null:
		_leap_to(Vector3(spot) + Vector3(0.5, 0.5, 0.5))
		return
	if global_position.distance_to(p.global_position) < 3000.0 / 24.0:
		_leap_to(p.global_position + Vector3(0, 0.9, 0))


## The best treasure in the player's view: the highest priority, then the
## nearest.
func _treasure(game):
	if _treasure_ids.is_empty():
		for id in Data.blocks.size():
			var sheet: String = Data.block(id).get("tex", {}).get("all", {}).get("sheet", "")
			if sheet.begins_with("Tiles_") and sheet.substr(6).is_valid_int() and TREASURE.has(int(sheet.substr(6))):
				_treasure_ids[id] = int(sheet.substr(6))
	var w: VoxelWorld = game.world
	var centre := Vector3i(game.player.global_position.floor())
	var found: PackedInt32Array = w.find_blocks(centre, Vector3i(40, 25, 40), PackedInt32Array(_treasure_ids.keys()), 400)
	var best = null
	var best_rank := -1
	var best_d := INF
	for i in range(0, found.size(), 3):
		var c := Vector3i(found[i], found[i + 1], found[i + 2])
		var id := w.get_block(c)
		var tile: int = _treasure_ids.get(id, 0)
		var rank: int = TREASURE.get(tile, 0)
		if rank < best_rank:
			continue
		if tile in VEIN_ORES and w.find_blocks(c, Vector3i(2, 2, 2), PackedInt32Array([id]), 40).size() < 40 * 3:
			continue
		var dd := global_position.distance_to(Vector3(c))
		if rank > best_rank or dd < best_d:
			best = c
			best_rank = rank
			best_d = dd
	return best


## RainbowBoulder_JumpToPosition: 4 to 32 px a tick as the way runs 0 to 200
## px, aimed to fall onto it (Terraria's 0.6 a tick allowance); it flies
## through blocks until it's nearly there.
func _leap_to(target: Vector3) -> void:
	var d := target - global_position
	var len_px := d.length() * 16.0
	var speed := remap(clampf(len_px, 0.0, 200.0), 0.0, 200.0, 4.0, 32.0)
	var t := minf(120.0, len_px / speed)
	var v := (d * 16.0 / maxf(t, 1.0)) if d.length() > 0.01 else Vector3(0, speed, 0)
	v.y += 0.5 * 0.6 * t
	velocity = v * 3.75
	_jump = maxf(0.0, t - 2.0)
	if d.x != 0.0 or d.z != 0.0:
		_roll = Vector3(d.x, 0, d.z).normalized()


## A Ghoulder's ghost: at you through blocks while you look away; stopping
## and falling while you look at it (Terraria: while you face it).
func _ghoulder_step(delta: float, game) -> void:
	var w: VoxelWorld = game.world
	var tick := delta * 60.0
	var p = game.player
	var to: Vector3 = p.global_position + Vector3(0, 0.9, 0) - global_position
	var flat := Vector2(to.x, to.z)
	var f: Vector3 = p.forward()
	var chase: bool = flat.length() < p.half.x + 0.5 or Vector2(f.x, f.z).dot(flat) > 0.0
	_angle *= pow(0.6, tick)
	if chase:
		# Its look runs on to frame 7, 4 ticks a frame.
		_ghost_frame = minf(7.0, _ghost_frame + tick / 4.0)
		var k := 1.0 - pow(35.0 / 36.0, tick)
		velocity = velocity.lerp(to.normalized() * 6.0 * 3.75, k)
		global_position += velocity * delta
	else:
		_ghost_frame = maxf(0.0, _ghost_frame - tick / 4.0)
		var keep := pow(0.92, tick)
		velocity.x *= keep
		velocity.z *= keep
		velocity.y = maxf(velocity.y - 0.3 * 225.0 * delta, -16.0 * 3.75)
		var moved: Dictionary = w.move_aabb(global_position - Vector3(0, 0.45, 0), Vector3(0.45, 0.9, 0.45), velocity * delta, 0.0, false)
		global_position = moved.position + Vector3(0, 0.45, 0)
		if moved.get("on_floor", false):
			velocity.y = 0.0
	frame = int(_ghost_frame)


## Hurts what it rolls into: you (not the Rainbow Boulder's), each enemy once.
func _boulder_hits(game) -> void:
	var p = game.player
	if kind != "RainbowBoulder" and p.alive and p.overlaps_point(global_position, radius):
		p.hurt(damage * 2, global_position)
		if kind == "LavaBoulder":
			p.ignite(5.0)
	for npc in game.npcs():
		if not _hit.has(npc) and npc.overlaps_point(global_position, radius):
			_hit[npc] = true
			npc.hit(damage, knockback, velocity.normalized(), 0.0)
			if kind == "LavaBoulder":
				npc.ignite(5.0)
			if kind == "RainbowBoulder" and npc.boss:
				_boulder_break(game)
				return


## Breaks (Projectile.Kill): its sound and dust; the Lava Boulder's lava.
func _boulder_break(game) -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		return
	match kind:
		"LavaBoulder":
			Audio.play_at("Item_14", global_position)
			for i in 40:
				game.dust.spawn(6, global_position + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)), Vector3(randf_range(-3, 3), randf_range(-3, 3), randf_range(-3, 3)), 2.5)
			_lava_pool(game)
		"Ghoulder":
			Audio.play_at("NPC_Killed_6", global_position)
			for i in 50:
				game.dust.spawn(192, global_position + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)), velocity * 0.5 / 3.75 + Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)), 1.5)
		"BoulderThatSpawnsPet":
			Audio.play_at("Dig_*", global_position)
		_:
			Audio.play_at("Dig_*", global_position)
			var dust_id: int = {"BouncyBoulder": 243}.get(kind, 1)
			for i in 30:
				game.dust.spawn(dust_id, global_position + Vector3(randf_range(-0.5, 0.5), randf_range(-0.5, 0.5), randf_range(-0.5, 0.5)), Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)), 1.2)
	queue_free()


## LavaBoulderExplosion: lava in every open cell within 4 tiles (here 2.7
## blocks) that it can see.
func _lava_pool(game) -> void:
	var w: VoxelWorld = game.world
	var c := Vector3i(global_position.floor())
	var r := 4.0 * 2.0 / 3.0
	var n := int(ceil(r))
	for dx in range(-n, n + 1):
		for dy in range(-n, n + 1):
			for dz in range(-n, n + 1):
				var q := c + Vector3i(dx, dy, dz)
				if Vector3(dx, dy, dz).length() >= r or w.get_block(q) != 0:
					continue
				var to := Vector3(q) + Vector3(0.5, 0.5, 0.5)
				var hit: Dictionary = w.raycast(global_position, (to - global_position).normalized(), global_position.distance_to(to))
				if hit.is_empty():
					w.set_liquid(q, Player.LIQ_LAVA, 63)


## Gone: a Hellfire Arrow's blast first ("blast": Terraria's Kill grows it to
## 64 px and Damage()s every enemy in that, the one it hit being immune just
## then), with Item14.
func _die(game) -> void:
	if _flight.has("blast") and friendly:
		var r := float(_flight.blast)
		Audio.play_at("Item_14", global_position, 0.6)
		for i in 10:
			game.dust.spawn(6, global_position, Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 2.0, 1.5)
		for npc in game.npcs():
			if _hit.has(npc) or npc.def.ai in ["town", "dummy"] or npc.untouchable or npc.dont_take_damage:
				continue
			var to: Vector3 = npc.center() - global_position
			if to.length() < r + npc.half.x:
				npc.hit(damage, knockback, to.normalized(), crit, armor_pen)
	queue_free()


func _check_hits(game) -> bool:
	if friendly:
		for npc in game.npcs():
			if not _hit.has(npc) and npc.overlaps_point(global_position, radius):
				_hit[npc] = true
				npc.hit(damage, knockback, velocity.normalized(), crit, armor_pen)
				if _flight.get("melee", false):
					game.player.on_melee_hit(npc, {})
				var fire: Array = _flight.get("ignite", [])
				if not fire.is_empty() and randi() % int(fire[0]) == 0:
					npc.ignite(randi_range(int(fire[1]), int(fire[2])) / 60.0)
				damage = maxi(1, int(round(damage * (1.0 - pierce_falloff))))
				penetrate -= 1
				if penetrate <= 0:
					return true
	elif not _flight.get("book", false) or _launched:
		var p = game.player
		if p.alive and p.overlaps_point(global_position, float(_flight.get("radius", 0.2))):
			p.hurt(damage, global_position)
			if kind in POISONS and randi() % 3 == 0:
				p.poison(10.0)
			if _flight.has("poison"):
				p.poison(float(_flight.poison))
			if kind in IGNITES and randi() % 3 == 0:
				p.ignite(7.0)
			# The Librarian Skeleton's books go on through (penetrate -1).
			return not _flight.get("book", false)
	return false
