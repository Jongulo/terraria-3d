class_name NPC
extends Node3D
## Enemies and bosses. Terraria's AI styles reinterpreted for 3D: ground
## movement steers on the XZ plane, fliers move freely.

## Terraria's NPC gravity (NPC.UpdateNPC_UpdateGravity): 0.3 px/tick², at most
## 10 px/tick. Terraria's px and ticks here: a block is 24 px, so 1 px/tick is
## 2.5 blocks/s and 0.01 px/tick² is 1.5 blocks/s².
const GRAVITY := 45.0
const MAX_FALL := 25.0
const PX_TICK := 2.5  # 1 px/tick in blocks/s
const DESPAWN_DISTANCE := 110.0

var kind := ""
var def: Dictionary
var life := 1
var life_max := 1
var damage := 0
var defense := 0
var velocity := Vector3.ZERO
var on_floor := false
var half := Vector3(0.4, 1.0, 0.4)
## Its billboard (EntitySprite), its 3D model (NPCModel) when the NPC picker
## gave its kind another method, or its pre-rendered sprites (RenderedSprite).
var sprite: Node3D
## Where its 3D model looks, when its AI says (the Eye of Cthulhu: at you
## while hovering); otherwise it faces its motion.
var look_dir := Vector3.ZERO
## How fast its model turns to look there (radians a second, as Terraria turns
## the Eye's rotation a step a tick); below 0: at once.
var turn_rate := -1.0
var _model_facing := Vector3.ZERO
var boss := false
var flying := false

var ai_timer := 0.0
var ai_state := 0
var ai_count := 0
var anim := 0.0
var _flash := 0.0
## Can't be hit and hits nothing (King Slime between teleports).
var untouchable := false
## Seconds of Terraria's On Fire! left (the Sunfury, the Flaming Mace): 4 life
## a second, taken (and shown) 1 at a time.
var on_fire := 0.0
var _burn := 0.0
var _stuck := 0.0
var _wander := Vector3.ZERO
## Which way the last hit came (its gore and death dust fly that way).
var _last_hit_dir := Vector3.ZERO
## The way a slime faces (it steers that way in the air).
var _facing := Vector3.ZERO
var _idle_sound := randf_range(4.0, 12.0)
var _lava_timer := 0.0
var _shot_timer := 2.0
var _pulse := 0.0
## Snatchers: where their vine is rooted, and the vine drawn to them.
var _anchor = null
var _vine: MeshInstance3D
## Target dummy: recent hits as [time, damage] for its DPS readout.
var _hits: Array = []
var _dps_label: Label3D
## Over the head once hurt (none for town NPCs and dummies).
var health_bar: HealthBar
var _bar_shown := Vector2i(-1, -1)
## Town NPCs (Town): their name, their home (Housing's key for the room, ""
## when homeless) and where they stand in it; talking: you're chatting with them.
var display_name := ""
var home_key := ""
var home_spot := Vector3i.ZERO
var talking := false
var _door = null
## The path it's walking (TownPaths): the middle of each cell's floor.
var _waypoints: Array = []
var _roam_from := Vector3.INF
var _help_index := 0
## Skeletron: a hand's head and side (Terraria's ai[1] and ai[0]: -1 rests to
## your right of the head, 1 to your left), the head's spin, a timer in ticks
## (Terraria's ai[2]) and a hand's two arm bones.
var _head: NPC = null
var _side := 1
var _spin := 0.0
var _sk_timer := 0.0
var _bones: Array = []


func setup(kind_name: String) -> void:
	kind = kind_name
	def = Data.npcs[kind_name]
	life_max = int(def.life)
	life = life_max
	damage = int(def.damage)
	defense = int(def.defense)
	boss = def.get("boss", false)
	var lk := look(kind_name)
	var size: Array = lk.hitbox
	half = Vector3(size[0] * 0.5, size[1], size[0] * 0.5)
	flying = lk.flying
	sprite = make_look(kind_name, lk)
	add_child(sprite)
	if not def.ai in ["town", "dummy"] and not def.get("invulnerable", false):
		health_bar = HealthBar.new()
		# Just above the top of the sprite (fliers' sprites are centred).
		health_bar.position.y = lk.top + 0.25
		if boss:
			health_bar.scale = Vector3.ONE * 1.6
		add_child(health_bar)
	if def.ai == "dummy":
		_dps_label = Label3D.new()
		_dps_label.font = Assets.font("Mouse_Text")
		_dps_label.font_size = 26
		_dps_label.pixel_size = 0.014
		_dps_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_dps_label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_dps_label.position.y = size[1] + 0.45
		add_child(_dps_label)


## How an NPC looks in the world, with its scale (Data.npc_scale, set in the
## NPC scale editor): {hitbox: [width, height] in blocks, tex, frames,
## frame_h, sprite_size (blocks), centred, sprite_y (a flier's sprite
## centre), trim (pixels cut off each frame's bottom, -1 none), top (the
## sprite's top above the feet), flying, scale, tint}. The game and the editor both
## draw NPCs from this.
static func look(kind_name: String) -> Dictionary:
	var d: Dictionary = Data.npcs[kind_name]
	var sc := Data.npc_scale(kind_name)
	var s: float = sc.scale
	var hs: float = s if sc.hitbox else 1.0
	var size: Array = d.size
	var flier: bool = d.ai in ["flyer", "bat", "harpy", "snatcher", "boss_eoc", "worm", "skeletron", "skeletron_hand", "skeletron_arm"]
	var tex := Assets.texture(image_path(kind_name))
	var frame_h := float(tex.get_height()) / int(d.frames)
	var vis_h: float = float(size[1]) * s
	var out := {"hitbox": [float(size[0]) * hs, float(size[1]) * hs], "tex": tex, "frames": int(d.frames), "frame_h": frame_h,
			"flying": flier, "centred": flier, "sprite_y": vis_h * 0.5 if flier else 0.0, "trim": -1.0, "scale": s}
	if d.has("tint"):
		var t: Array = d.tint
		out.tint = Color(t[0], t[1], t[2], t[3])
	if d.has("art_height"):
		# The figure itself (not its frame's empty margins) stands this tall,
		# feet on the ground: like the player, for town NPCs.
		var rows := art_rows(tex, frame_h)
		var trim := frame_h - 1.0 - rows.y
		var h: float = float(d.art_height) * s * (frame_h - trim) / (rows.y - rows.x + 1.0)
		out.sprite_size = Vector2(h * tex.get_width() / (frame_h - trim), h)
		out.trim = trim
		out.centred = false
		out.top = h
	elif d.has("sprite_ppb"):
		# Its sheet at its true size (worm segments overlap, as in Terraria).
		out.sprite_size = Vector2(tex.get_width(), frame_h) / float(d.sprite_ppb) * s
		out.top = vis_h * 0.5 + out.sprite_size.y * 0.3 if flier else out.sprite_size.y
	else:
		# Keep the art's aspect ratio; the height sets its size.
		var h: float = vis_h * (1.15 if flier else 1.1)
		out.sprite_size = Vector2(h * tex.get_width() / frame_h, h)
		if d.has("trim_bottom"):
			out.trim = float(d.trim_bottom)
		out.top = vis_h * (1.075 if flier else 1.1)
	return out


## Its sheet (Images/NPC_<sprite>, or its own "image").
static func image_path(kind_name: String) -> String:
	var d: Dictionary = Data.npcs[kind_name]
	return "Images/" + str(d.image) if d.has("image") else "Images/NPC_%d" % int(d.sprite)


## Sets up `sprite` (EntitySprite) from look().
## Its look as a node: the billboard, or the 3D model its kind's method makes
## (bottom on the ground; fliers' middle where the billboard's middle was).
static func make_look(kind_name: String, lk: Dictionary) -> Node3D:
	var m := NPCModels.method(kind_name)
	if m == "rendered":
		var r := RenderedSprite.new()
		r.setup_rendered(kind_name)
		return r
	if m == "billboard":
		var s := EntitySprite.new()
		apply_look(s, lk)
		return s
	var model := NPCModel.new()
	model.setup(kind_name, m)
	if lk.centred:
		model.position.y = lk.sprite_y - NPCModels.frames_of(kind_name).size.y * 0.5
	if lk.has("tint"):
		model.set_tint(lk.tint)
	return model


static func apply_look(sprite: EntitySprite, lk: Dictionary) -> void:
	sprite.setup(lk.tex, lk.frames, lk.sprite_size, lk.centred)
	if lk.trim >= 0.0:
		sprite.set_trim_bottom(lk.trim, lk.frame_h)
	sprite.position.y = lk.sprite_y
	if lk.has("tint"):
		sprite.set_tint(lk.tint)


## The first and last rows (pixels, from the frame's top) holding art in a
## sheet's first frame.
static func art_rows(tex: Texture2D, frame_h: float) -> Vector2i:
	var img := tex.get_image()
	var top := -1
	var bottom := -1
	for y in int(frame_h):
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.5:
				if top < 0:
					top = y
				bottom = y
				break
	return Vector2i(maxi(top, 0), bottom if bottom >= 0 else int(frame_h) - 1)


func center() -> Vector3:
	return global_position + Vector3(0, half.y * 0.5, 0)


func overlaps_point(p: Vector3, radius: float) -> bool:
	var pos := global_position
	return absf(p.x - pos.x) < half.x + radius and absf(p.z - pos.z) < half.z + radius \
			and p.y > pos.y - radius and p.y < pos.y + half.y + radius


func overlaps_box(pos: Vector3, h: Vector3) -> bool:
	var me := global_position
	return absf(pos.x - me.x) < half.x + h.x and absf(pos.z - me.z) < half.z + h.z \
			and pos.y < me.y + half.y and pos.y + h.y > me.y


func _physics_process(delta: float) -> void:
	var game := Game.current
	var player = game.player
	var to_player: Vector3 = player.global_position - global_position
	if not boss and not def.get("persistent", false) and to_player.length() > DESPAWN_DISTANCE:
		queue_free()
		return

	if def.ai in ["skeletron", "skeletron_hand"]:
		# Through the blocks (Terraria's noTileCollide), like the worms.
		if def.ai == "skeletron":
			_ai_skeletron(delta, game, player)
		else:
			_ai_skeletron_hand(delta, game, player)
		if is_queued_for_deletion():
			return
		global_position += velocity * delta
		if on_fire > 0.0:
			_burn_tick(delta, game)
			if life <= 0:
				return
		if damage > 0 and player.alive and overlaps_box(player.global_position, player.half):
			player.hurt(damage, center(), false, self)
		_update_sprite(delta, game)
		return

	if def.ai == "worm":
		_ai_worm(delta, game, player)
		if is_queued_for_deletion():
			return
		if on_fire > 0.0:
			_burn_tick(delta, game)
			if life <= 0:
				return
		if damage > 0 and player.alive and overlaps_box(player.global_position, player.half):
			player.hurt(damage, center(), false, self)
		_update_sprite(delta, game)
		return

	match def.ai:
		"slime": _ai_slime(delta, player)
		"fighter": _ai_fighter(delta, player)
		"flyer": _ai_flyer(delta, player)
		"bat": _ai_bat(delta, player)
		"harpy": _ai_harpy(delta, player)
		"swim": _ai_swim(delta, player)
		"turret": _ai_turret(delta, player)
		"snatcher": _ai_snatcher(delta, player)
		"boss_eoc": _ai_eye_of_cthulhu(delta, player)
		"king_slime": _ai_king_slime(delta, game, player)
		"dummy": _ai_dummy(delta)
		"town": _ai_town(delta)

	if on_fire > 0.0:
		_burn_tick(delta, game)
		if life <= 0:
			return
	var liquid: Vector2i = game.world.get_liquid(Vector3i(center().floor()))
	# Swimmers move freely in water, like fliers in air.
	var swimming: bool = def.ai == "swim" and in_water(center())
	if liquid.y > 0 and not boss:
		if liquid.x == 2:
			_lava_timer -= delta
			if _lava_timer <= 0.0:
				_lava_timer = 0.5
				hit(30, 0.0, Vector3.ZERO, 0.0)
				if life <= 0:
					return
		elif not flying and not swimming:
			velocity.x *= 0.92
			velocity.z *= 0.92
	if not flying and not swimming:
		var g := GRAVITY * (0.3 if liquid.y > 0 else 1.0)
		velocity.y = maxf(velocity.y - g * delta, -3.5 if liquid.y > 0 else -MAX_FALL)
	var r := game.world.move_aabb(global_position, half, velocity * delta, 1.05 if def.ai in ["fighter", "town"] else 0.0, false)
	global_position = r.position
	on_floor = r.on_floor
	var blocked: Vector3i = r.blocked
	if flying or swimming:
		# Fliers (and swimmers) bounce off terrain.
		if blocked.x: velocity.x *= -0.5
		if blocked.y: velocity.y *= -0.5
		if blocked.z: velocity.z *= -0.5
	else:
		if blocked.y:
			velocity.y = 0.0
		if blocked.x: velocity.x = 0.0
		if blocked.z: velocity.z = 0.0
	_stuck = _stuck + delta if (blocked.x or blocked.z) else 0.0

	if damage > 0 and player.alive and not untouchable and overlaps_box(player.global_position, player.half):
		player.hurt(damage, center(), false, self)

	_try_shoot(delta, player)
	_update_sprite(delta, game)
	_idle_sound -= delta
	if _idle_sound < 0.0 and def.has("idle_sound"):
		_idle_sound = randf_range(8.0, 20.0)
		Audio.play_at(def.idle_sound, center(), 0.6)


func _update_sprite(delta: float, game) -> void:
	var cam: Camera3D = game.player.camera
	var right := cam.global_transform.basis.x
	if def.ai == "worm":
		# Turned along the worm, toward the segment ahead (a head: its motion).
		if sprite is NPCModel or sprite is RenderedSprite:
			sprite.face(_worm_dir)
		elif _worm_dir.length() > 0.001:
			sprite.set_rotation_angle(EntitySprite.facing_angle(cam, _worm_dir) + deg_to_rad(float(def.get("sprite_angle", 0.0))))
	elif def.ai == "skeletron" and (sprite is NPCModel or sprite is RenderedSprite):
		# Its face turning slowly round toward you (not its bottom along its
		# flight, as fliers point: circle it and you see its sides), tipped
		# only part way down at you, rolled as the billboard turns: its lean
		# and its spin.
		var front := cam.global_position - center()
		var flat := Vector3(front.x, 0, front.z)
		if flat.length() > 0.01:
			turn_rate = SK_TURN
			var yaw := turn_facing(flat, delta)
			var pitch := clampf(atan2(front.y, flat.length()) * SK_TILT, -SK_TILT_MAX, SK_TILT_MAX)
			var z := (yaw * cos(pitch) + Vector3.UP * sin(pitch)).normalized()
			var x := Vector3.UP.cross(z).normalized()
			sprite.orient(Basis(x, z.cross(x), z) * Basis(Vector3.BACK, _spin))
	elif sprite is NPCModel or sprite is RenderedSprite:
		var heading := velocity if look_dir == Vector3.ZERO else look_dir
		if look_dir == Vector3.ZERO and Vector2(velocity.x, velocity.z).length() < 0.3 and not flying:
			heading = game.player.global_position - global_position
		sprite.face(turn_facing(heading, delta))
	elif not flying or def.ai == "bat" or def.get("upright", false):
		sprite.set_flip(velocity.dot(right) > 0.05)
	_flash = maxf(0.0, _flash - delta * 6.0)
	sprite.set_flash(_flash)
	sprite.update_light(game.world, game.sky, center())
	if health_bar != null and _bar_shown != Vector2i(life, life_max):
		_bar_shown = Vector2i(life, life_max)
		health_bar.set_life(life, life_max)


## Turns its facing toward `target` by at most turn_rate * delta (at once when
## turn_rate is below 0, or the first time) and returns it.
func turn_facing(target: Vector3, delta: float) -> Vector3:
	if target.length() < 0.01:
		return _model_facing
	var t := target.normalized()
	if turn_rate < 0.0 or _model_facing == Vector3.ZERO:
		_model_facing = t
		return _model_facing
	var angle := _model_facing.angle_to(t)
	var step := turn_rate * delta
	if angle <= step:
		_model_facing = t
	elif step > 0.0:
		var axis := _model_facing.cross(t)
		if axis.length() < 0.00001:  # right behind: turn either way
			axis = _model_facing.cross(Vector3.UP if absf(_model_facing.y) < 0.9 else Vector3.RIGHT)
		_model_facing = _model_facing.rotated(axis.normalized(), step).normalized()
	return _model_facing


## True when daytime should send night creatures away (not in the test world,
## where anything spawned on purpose stays put).
func _flees_day(game) -> bool:
	return game.sky.is_day and game.test_world == null


# ------------------------------------------------------------ AI styles

## Terraria's King Slime (AI_015_KingSlime), in its pixels (24 a block) and
## ticks. On the ground it slides to a stop (x0.8 a tick) and winds up for
## its next hop (2 a tick, faster as it's hurt: +1 under 80% life, +1 under
## 60%, +2 under 40%, +3 under 20%, +4 under 10%), then jumps at you in a
## cycle: 8 up / 4 on, 8 / 4, 6 / 4.5, then a big 13 / 3.5 (rests 120 ticks,
## 200 after the big one). In the air it steers at you (0.2 px/tick² up to
## 3). It's 1.25x its size at full life, down to 0.75x. When it can't reach
## you (no line of sight, or more than 160 px above or below you) for 5
## seconds it shrinks away (60 ticks), and grows back beside you (30);
## if you die or get 3000 px away it shrinks away for good. Each 5% of its
## life it loses, out pop 1-3 Blue Slimes.
var _ks_acc := 0.0
var _ks_jump := -100.0
var _ks_hop := 0
var _ks_state := 0  # 0 hopping, 5 shrinking away, 6 growing back
var _ks_t := 0
var _ks_stuck := 0
var _ks_mark := -1
var _ks_shrink := 1.0
var _ks_to := Vector3.ZERO
var _ks_leaving := false
var _ks_base_half := Vector3.ZERO
var _ks_base_scale := Vector3.ONE
## Drawn with it, as Terraria draws them: its crown on top, the ninja inside.
var _ks_crown: EntitySprite = null
var _ks_ninja: EntitySprite = null
## The crown's bob with each frame (Terraria's DrawNPCDirect, px).
const KS_CROWN_BOB := [2.0, -6.0, 2.0, 10.0, 2.0, 0.0]


func _ai_king_slime(delta: float, game, player) -> void:
	if _ks_mark < 0:
		_ks_mark = life_max
		_ks_base_half = half
		_ks_base_scale = sprite.scale
		_ks_crown = EntitySprite.new()
		var crown := Assets.texture("Images/Extra_39")
		_ks_crown.setup(crown, 1, Vector2(crown.get_width(), crown.get_height()) / WORM_PX, true)
		add_child(_ks_crown)
		_ks_ninja = EntitySprite.new()
		var ninja := Assets.texture("Images/Ninja")
		_ks_ninja.setup(ninja, 1, Vector2(ninja.get_width(), ninja.get_height()) / WORM_PX, true)
		# Seen through the sprite's blue, it's tinted; a see-through 3D body
		# tints it itself.
		if not _ks_glass():
			_ks_ninja.set_tint(Color(0.55, 0.7, 1.0))
		add_child(_ks_ninja)
	_ks_acc += delta
	while _ks_acc >= WORM_TICK:
		_ks_acc -= WORM_TICK
		_ks_tick(game, player)
		if is_queued_for_deletion():
			return
	_ks_resize()
	# Frames: wobbling on the ground (0-3; quicker as it winds up), 4-5 in the air.
	var frame := 0
	if not on_floor:
		frame = 4 if velocity.y > 0.0 else 5
	else:
		anim += delta * (16.0 if _ks_jump >= -30.0 else 8.0)
		frame = int(anim) % 4
	sprite.set_frame(frame)
	sprite.visible = not untouchable
	_ks_place_extras(game, frame)


## The crown (Extra_39) sits (70 - its bob) px above its middle, times its
## scale; the ninja (Ninja) lags its motion inside it (2x sideways, 1x up and
## down, bobbing with the frames) and tilts with it, a little toward you so
## it shows through.
func _ks_place_extras(game, frame: int) -> void:
	var k := float(life) / life_max * 0.5 + 0.75
	var c := global_position + Vector3(0, half.y * 0.5, 0)
	var cam: Camera3D = game.player.camera
	_ks_crown.global_position = c + Vector3(0, (70.0 - KS_CROWN_BOB[frame]) * k * _ks_shrink / WORM_PX, 0)
	var v := velocity / PX_TICK
	var bob: float = [0.0, -2.0, 0.0, 2.0, 6.0, 0.0][frame]
	var ninja := c + Vector3(-2.0 * v.x, -v.y + bob, -2.0 * v.z) / WORM_PX
	# A little toward you, so it shows in front of the flat sprite; inside a
	# see-through 3D body, right where it is.
	_ks_ninja.global_position = ninja + ((cam.global_position - ninja).normalized() * 0.4 if not _ks_glass() else Vector3.ZERO)
	_ks_ninja.set_rotation_angle(-v.dot(cam.global_transform.basis.x) * 0.05)
	_ks_ninja.scale = Vector3(_ks_ninja.scale.x, _ks_ninja.scale.y, 1.0)
	for e in [_ks_crown, _ks_ninja]:
		e.visible = not untouchable and _ks_shrink > 0.55
		e.update_light(game.world, game.sky, c)


## True when its body is a see-through 3D model (Claude's King Slime).
func _ks_glass() -> bool:
	return sprite is NPCModel and NPCModels.glass(kind, sprite.method) < 1.0


func _ks_tick(game, player) -> void:
	var to: Vector3 = player.center() - center()
	if (not player.alive or to.length() * WORM_PX > 3000.0) and _ks_state != 5:
		# Gone for good: off it goes.
		_ks_state = 5
		_ks_t = 0
		_ks_leaving = true
	elif player.alive and _ks_stuck >= 300 and _ks_state < 5 and on_floor:
		_ks_state = 5
		_ks_t = 0
		_ks_stuck = 0
		_ks_to = _ks_spot_near(game, player)
	# Can't reach you: counting toward a teleport.
	var top_y := global_position.y + half.y
	var sees := float(game.world.raycast(center(), to.normalized(), to.length()).get("distance", INF)) >= to.length() - 0.5
	if not sees or absf(top_y - player.global_position.y) * WORM_PX > 160.0:
		_ks_stuck += 1
	var hopping := _ks_state == 0
	untouchable = false
	if _ks_state == 5:
		_ks_t += 1
		_ks_shrink = 0.5 + 0.5 * clampf((60.0 - _ks_t) / 60.0, 0.0, 1.0)
		if _ks_t < 60:
			_ks_dust(game)
		else:
			untouchable = true
			if _ks_leaving:
				queue_free()
				game.on_boss_despawned(self)
				return
			global_position = _ks_to
			velocity = Vector3.ZERO
			_ks_state = 6
			_ks_t = 0
	elif _ks_state == 6:
		_ks_t += 1
		_ks_shrink = 0.5 + 0.5 * clampf(_ks_t / 30.0, 0.0, 1.0)
		_ks_dust(game)
		if _ks_t >= 30:
			_ks_state = 0
			_ks_t = 0
	var flat := Vector3(to.x, 0, to.z)
	var dir := flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
	if on_floor and velocity.y <= 0.0:
		velocity.x *= 0.8
		velocity.z *= 0.8
		if Vector2(velocity.x, velocity.z).length() < 0.1 * PX_TICK:
			velocity.x = 0.0
			velocity.z = 0.0
		if hopping:
			_ks_jump += 2.0
			var f := float(life) / life_max
			if f < 0.8: _ks_jump += 1.0
			if f < 0.6: _ks_jump += 1.0
			if f < 0.4: _ks_jump += 2.0
			if f < 0.2: _ks_jump += 3.0
			if f < 0.1: _ks_jump += 4.0
			if _ks_jump >= 0.0:
				var up := 8.0
				var on := 4.0
				if _ks_hop == 3:
					up = 13.0
					on = 3.5
					_ks_jump = -200.0
					_ks_hop = 0
				else:
					if _ks_hop == 2:
						up = 6.0
						on = 4.5
					_ks_jump = -120.0
					_ks_hop += 1
				velocity.y = up * PX_TICK
				velocity += dir * on * PX_TICK
	elif hopping and player.alive:
		var h := Vector3(velocity.x, 0, velocity.z)
		var along := h.dot(dir) / PX_TICK
		var side := h - dir * h.dot(dir)
		var keep := dir * h.dot(dir)
		if along < 3.0:
			if along > -0.1:
				keep += dir * 0.2 * PX_TICK
			else:
				keep *= 0.93
		side *= 0.93
		velocity.x = keep.x + side.x
		velocity.z = keep.z + side.z
	# Out pop slimes as it's hurt.
	if life + int(life_max * 0.05) < _ks_mark:
		_ks_mark = life
		for i in randi_range(1, 3):
			var at := global_position + Vector3(randf_range(-half.x, half.x) * 0.7, randf_range(0.2, half.y * 0.7), randf_range(-half.z, half.z) * 0.7)
			var s: NPC = game.spawn_npc("BlueSlime", at)
			if s != null:
				s.velocity = Vector3(randi_range(-15, 15) * 0.1, -randi_range(-30, 0) * 0.1, randi_range(-15, 15) * 0.1) * PX_TICK
				s.ai_timer = -float(randi() % 3) * 1000.0 / 60.0  # Terraria: ai[0] = -1000 x (0-2)


## Its size: 1.25x at full life, 0.75x at none, times the teleport shrink;
## the hitbox and sprite change together, feet where they were.
func _ks_resize() -> void:
	var k := (float(life) / life_max * 0.5 + 0.75) / 1.25 * _ks_shrink
	half = _ks_base_half * k
	sprite.scale = _ks_base_scale * k


func _ks_dust(game) -> void:
	for i in 2:
		var at := global_position + Vector3(randf_range(-half.x, half.x), randf_range(0.0, half.y * 0.3), randf_range(-half.z, half.z))
		game.dust.spawn(4, at, Vector3(0, 0.5, 0), 2.0, Color(0.3, 0.55, 1.0, 0.7))


## Where it reappears: a clear spot on the ground near you that can see you
## (Terraria's AI_015_KingSlime_FindTeleportSpot), else where you stand.
func _ks_spot_near(game, player) -> Vector3:
	var p: Vector3 = player.global_position
	for i in 40:
		var a := randf() * TAU
		var r := randf_range(4.0, 14.0)
		var x := p.x + cos(a) * r
		var z := p.z + sin(a) * r
		for dy in range(8, -12, -1):
			var y := floorf(p.y) + dy
			if game.world.is_solid(Vector3i(floori(x), int(y) - 1, floori(z))) and not game.world.is_solid(Vector3i(floori(x), int(y), floori(z))):
				var spot := Vector3(x, y, z)
				var box := _ks_base_half
				var clear := true
				for cx in [-1.0, 0.0, 1.0]:
					for cz in [-1.0, 0.0, 1.0]:
						for cy in [0.5, box.y * 0.5, box.y - 0.3]:
							if game.world.is_solid(Vector3i((spot + Vector3(cx * box.x * 0.9, cy, cz * box.z * 0.9)).floor())):
								clear = false
				if clear:
					var to: Vector3 = player.center() - (spot + Vector3(0, box.y * 0.5, 0))
					if float(game.world.raycast(spot + Vector3(0, box.y * 0.5, 0), to.normalized(), to.length()).get("distance", INF)) >= to.length() - 0.5:
						return spot
				break
	return p


## Terraria's worms (AI_006_Worms; the Eater of Worlds), in its pixels (24 a
## block) and ticks. Each segment is its own NPC with its own life, joined to
## the one ahead and the one behind. The head (the one summoned) lays out its
## segments behind it, then each tick:
##   in the ground (a block, or deep liquid, in its body), or far from you
##   (1000 px), it steers at you: each axis toward a velocity of its speed
##   at you, by its acceleration (x1.1 along the main axis when it's heading
##   away, with a push to keep moving; x2 to swing round when it overshoots);
##   in the open it falls (0.11 px/tick², at most its speed) and drifts.
## Every other segment trails the one ahead at `spacing` px. Kill a middle
## segment and the worm splits: the one behind becomes a head, the one ahead
## a tail; a head or tail left alone, or a segment with neither, dies. When
## you leave the Corruption (or die) it digs straight down and is gone once
## it's deep. Each segment drops its own loot; the last one the boss's.
const WORM_PX := 24.0
const WORM_TICK := 1.0 / 60.0
var ahead: NPC = null
var behind: NPC = null
var _worm_acc := 0.0
var _worm_laid := false
var _worm_dir := Vector3.DOWN
var _dig_delay := 0


## The worm's shared numbers (on its head's kind).
func _worm() -> Dictionary:
	var w: Dictionary = def.get("worm", {})
	if w.has("kinds"):
		return w
	return Data.npcs[str(def.get("boss_group", kind))].worm


func worm_role() -> String:
	return str(def.get("worm", {}).get("role", ""))


static func _segment_alive(n) -> bool:
	return n != null and is_instance_valid(n) and not n.is_queued_for_deletion() and n.life > 0


func _ai_worm(delta: float, game, player) -> void:
	var front := _segment_alive(ahead)
	var back := _segment_alive(behind)
	var role := worm_role()
	if role == "head" and not _worm_laid:
		_worm_laid = true
		_lay_segments(game)
		back = _segment_alive(behind)
	# Splitting (Terraria's worm checks, every tick).
	if (not front and not back) or (role == "head" and not back) or (role == "tail" and not front):
		life = 0
		_die(game)
		return
	if role == "body" and not front:
		_worm_become("head")
	elif role == "body" and not back:
		_worm_become("tail")
	if worm_role() != "head":
		return  # moved by the head
	_worm_acc += delta
	while _worm_acc >= WORM_TICK:
		_worm_acc -= WORM_TICK
		_worm_head_tick(game, player)
		if is_queued_for_deletion():
			return


## The head's segments: `segments` bodies and a tail, in a line below it.
func _lay_segments(game) -> void:
	var w := _worm()
	var gap: float = float(w.spacing) / WORM_PX
	var lead: NPC = self
	var total := life
	for i in int(w.segments) + 1:
		var k: String = w.kinds.tail if i == int(w.segments) else w.kinds.body
		var seg: NPC = game.spawn_npc(k, global_position - Vector3(0, gap * (i + 1), 0))
		seg.ahead = lead
		lead.behind = seg
		seg._worm_laid = true
		lead = seg
		total += seg.life
	game.boss_life_max[str(def.get("boss_group", kind))] = total


## Turns into a head or tail of the worm (Terraria's NPC.Transform), life kept.
func _worm_become(role: String) -> void:
	var k: String = _worm().kinds[role]
	kind = k
	def = Data.npcs[k]
	damage = int(def.damage)
	defense = int(def.defense)
	var lk := look(k)
	var old := sprite
	sprite = make_look(k, lk)
	add_child(sprite)
	old.queue_free()
	_worm_laid = true
	velocity = Vector3.ZERO


func _worm_unlink() -> void:
	if _segment_alive(ahead) and ahead.behind == self:
		ahead.behind = null
	if _segment_alive(behind) and behind.ahead == self:
		behind.ahead = null


## A block (or more than a quarter of liquid) in its body.
func _worm_in_ground(game) -> bool:
	var c := center()
	var r := half.x
	var lo := (c - Vector3(r, r, r)).floor()
	var hi := (c + Vector3(r, r, r)).floor()
	for x in range(int(lo.x), int(hi.x) + 1):
		for y in range(int(lo.y), int(hi.y) + 1):
			for z in range(int(lo.z), int(hi.z) + 1):
				var p := Vector3i(x, y, z)
				if game.world.is_solid(p) or game.world.get_liquid(p).y > 16:
					return true
	return false


func _worm_head_tick(game, player) -> void:
	var w := _worm()
	var speed: float = w.speed
	var accel: float = w.accel
	var v := velocity / PX_TICK  # px/tick
	var c := center()
	var to: Vector3 = (player.center() - c) * WORM_PX
	var dug := _worm_in_ground(game)
	if not dug and (absf(to.x) > 1000.0 or absf(to.y) > 1000.0 or absf(to.z) > 1000.0):
		dug = true  # far from you: on its way through anything
	# Out of its biome (or you're dead): straight down, and gone when deep.
	var leaving: bool = not player.alive or (game.test_world == null and not game.biome in w.get("stays_in", []))
	if leaving:
		to = Vector3(0, -speed, 0)
		dug = true
		if c.y < game.cavern_level * 0.5:
			_worm_despawn(game)
			return
	if not dug:
		# In the open: falls, drifting.
		v.y = maxf(v.y - 0.11, -speed)
		var h := Vector2(v.x, v.z)
		var aim := Vector2(to.x, to.z)
		if absf(v.x) + absf(v.y) + absf(v.z) < speed * 0.4:
			h += (h.normalized() if h.length() > 0.001 else aim.normalized()) * accel * 1.1
		elif v.y <= -speed:
			for a in 2:
				if h[a] < aim[a]:
					h[a] += accel
				elif h[a] > aim[a]:
					h[a] -= accel
		elif v.y < -4.0:
			h = h.move_toward(Vector2.ZERO, accel * 0.9 * 1.41)
		v.x = h.x
		v.z = h.y
	else:
		_dig_effects(game, to.length())
		var t := to.normalized() * speed if to.length() > 0.001 else Vector3.ZERO
		var toward := false
		for a in 3:
			if (v[a] > 0.0 and t[a] > 0.0) or (v[a] < 0.0 and t[a] < 0.0):
				toward = true
		if toward:
			for a in 3:
				if v[a] < t[a]:
					v[a] += accel
				elif v[a] > t[a]:
					v[a] -= accel
			# Overshooting on one axis: swing round on the others.
			for a in 3:
				if absf(t[a]) < speed * 0.2:
					for b in 3:
						if b != a and ((v[b] > 0.0 and t[b] < 0.0) or (v[b] < 0.0 and t[b] > 0.0)):
							v[a] += accel * 2.0 if v[a] > 0.0 else -accel * 2.0
							break
		else:
			var main := 0
			for a in 3:
				if absf(t[a]) > absf(t[main]):
					main = a
			if v[main] < t[main]:
				v[main] += accel * 1.1
			elif v[main] > t[main]:
				v[main] -= accel * 1.1
			if absf(v.x) + absf(v.y) + absf(v.z) < speed * 0.5:
				for a in 3:
					if a != main:
						v[a] += accel if v[a] > 0.0 else -accel
	velocity = v * PX_TICK
	global_position += velocity * WORM_TICK
	if velocity.length() > 0.01:
		_worm_dir = velocity.normalized()
	_trail(game)


## Each segment behind keeps `spacing` px from the one ahead, turned toward it.
func _trail(game) -> void:
	var gap: float = float(_worm().spacing) / WORM_PX
	var lead: NPC = self
	var seg: NPC = behind
	var n := 0
	while _segment_alive(seg) and n < 400:
		var d: Vector3 = lead.center() - seg.center()
		var dist := d.length()
		if dist > 0.0001:
			seg.global_position += d * ((dist - gap) / dist)
			seg._worm_dir = d / dist
		if randi() % 100 == 0:
			seg._crumble(game)
		lead = seg
		seg = seg.behind
		n += 1


## Digging: now and then a block it's in crumbles (dust and sound, nothing
## broken: Terraria's 1 in 100 fail-only KillTile), and the head's digging
## noise, more often the nearer you are (every 10 to 20 ticks).
func _dig_effects(game, dist_px: float) -> void:
	if randi() % 100 == 0:
		_crumble(game)
	_dig_delay -= 1
	if _dig_delay <= 0 and _worm_in_ground(game):
		_dig_delay = int(clampf(dist_px / 40.0, 10.0, 20.0))
		Audio.play_at(str(_worm().get("dig_sound", "Roar_1")), center(), 0.5)


func _crumble(game) -> void:
	var p := Vector3i(center().floor())
	var id: int = game.world.get_block(p)
	if id != 0 and game.world.is_solid(p):
		game.dust.tile_dust(p, id, false)


## Dug away: the whole worm is gone, nothing dropped.
func _worm_despawn(game) -> void:
	var seg: NPC = self
	var n := 0
	while _segment_alive(seg) and n < 400:
		var next: NPC = seg.behind
		seg.queue_free()
		seg = next
		n += 1
	game.on_boss_despawned(self)


## Target dummy: stands still; shows damage per second over the last 3 seconds.
func _ai_dummy(_delta: float) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	var now := Time.get_ticks_msec() / 1000.0
	while not _hits.is_empty() and now - _hits[0][0] > 3.0:
		_hits.pop_front()
	var total := 0
	for h in _hits:
		total += int(h[1])
	_dps_label.text = "DPS: %d" % int(total / 3.0) if total > 0 else "Target Dummy"
	anim = maxf(0.0, anim - _delta * 12.0)
	sprite.set_frame(int(anim))


## Town NPCs: the Old Man stands where he is; the town's residents walk
## about. Right-click to talk.
func _ai_town(delta: float) -> void:
	if def.has("town") and not talking:
		_ai_resident(delta)
		return
	velocity.x = 0.0
	velocity.z = 0.0
	sprite.set_frame(0)


## Terraria's town NPC: by day it potters about near home (or where it is,
## homeless), now and then standing still; at night it goes home and stays.
## It walks paths (TownPaths), so it goes round its house's walls and out the
## door, opening doors in its way and shutting them behind it. Far from home
## at night where you can't see, it's simply back home.
const TOWN_SPEED := 1.4
## How far from home (or where it started, homeless) it wanders by day.
const WANDER := 8

func _ai_resident(delta: float) -> void:
	var game := Game.current
	var night: bool = not game.sky.is_day
	var home := Vector3(home_spot) + Vector3(0.5, 0, 0.5)
	var housed := home_key != ""
	if _roam_from == Vector3.INF:
		_roam_from = global_position
	var you: Vector3 = game.player.global_position
	if night and housed and global_position.distance_to(home) > 16.0 and you.distance_to(global_position) > 32.0 and you.distance_to(home) > 32.0:
		global_position = home
		velocity = Vector3.ZERO
		_waypoints.clear()
	ai_timer -= delta
	if ai_timer <= 0.0 or _stuck > 1.0:
		_stuck = 0.0
		if night and housed:
			walk_to(home)
			ai_timer = randf_range(3.0, 6.0)
		elif randf() < 0.4:
			_waypoints.clear()
			ai_timer = randf_range(2.0, 5.0)
		else:
			wander(game, home if housed else _roam_from)
			ai_timer = randf_range(3.0, 7.0)
	_close_door_behind(game)
	if _waypoints.is_empty():
		velocity.x = 0.0
		velocity.z = 0.0
		sprite.set_frame(0)
		return
	var to: Vector3 = _waypoints[0] - global_position
	to.y = 0.0
	if to.length() < 0.1:
		_waypoints.pop_front()
		return
	var dir := to.normalized()
	if on_floor and not _ground_ahead(game, dir):
		_waypoints.clear()  # the ground's changed under the path
		return
	_open_door_on_path(game)
	velocity.x = dir.x * TOWN_SPEED
	velocity.z = dir.z * TOWN_SPEED
	var wf: Array = def.get("walk_frames", [0, int(def.frames) - 1])
	anim += delta * TOWN_SPEED * 2.5
	sprite.set_frame(int(wf[0]) + int(anim) % (int(wf[1]) - int(wf[0]) + 1))


## Sets off along a path to `target` (or as near it as it can get). Returns
## false if there's no way to walk anywhere (not standing on anything).
func walk_to(target: Vector3) -> bool:
	_waypoints.clear()
	var paths := TownPaths.new(Game.current.world)
	var start = paths.standing_cell(global_position)
	if start == null:
		return false
	var goal := Vector3i(target.floor())
	var radius := maxi(WANDER, maxi(absi(goal.x - start.x), absi(goal.z - start.z)) + 4)
	var came := paths.reachable(start, start, radius)
	if not came.has(goal):
		# As near as it gets (and not stopping in a doorway).
		var best := Vector3i(start)
		for c in came:
			if not paths.is_door(c) and Vector3(c).distance_squared_to(Vector3(goal)) < Vector3(best).distance_squared_to(Vector3(goal)):
				best = c
		goal = best
	_waypoints = TownPaths.path_to(came, goal)
	return true


## Off to a random spot it can walk to, within WANDER of `from`.
func wander(game, from: Vector3) -> void:
	_waypoints.clear()
	var paths := TownPaths.new(game.world)
	var start = paths.standing_cell(global_position)
	if start == null:
		return
	var center := Vector3i(from.floor())
	var came := paths.reachable(start, center, maxi(WANDER, maxi(absi(start.x - center.x), absi(start.z - center.z))))
	var spots := came.keys().filter(func(c): return not paths.is_door(c) and c != start)
	if not spots.is_empty():
		_waypoints = TownPaths.path_to(came, spots.pick_random())


## Something to stand on within 3 blocks below the step ahead (no lava).
func _ground_ahead(game, dir: Vector3) -> bool:
	var ahead := global_position + dir * 0.7
	for dy in range(0, 4):
		var c := Vector3i(floori(ahead.x), floori(global_position.y) - dy, floori(ahead.z))
		if game.world.get_liquid(c).x == 2:
			return false
		if game.world.is_solid(c + Vector3i.DOWN) or game.world.is_solid(c):
			return true
	return false


## A shut door on the next stretch of the path: opens it, to shut it again
## once through.
func _open_door_on_path(game) -> void:
	for w in _waypoints.slice(0, 2):
		var c := Vector3i(w.floor())
		if Vector2(w.x - global_position.x, w.z - global_position.z).length() > 1.6:
			return
		var d := Data.block(game.world.get_block(c))
		if Doors.is_door(d) and not Doors.is_open(d) and Doors.toggle(game, c, global_position):
			_door = c


func _close_door_behind(game) -> void:
	if _door == null:
		return
	var c := Vector3(_door) + Vector3(0.5, 0, 0.5)
	if Vector2(c.x - global_position.x, c.z - global_position.z).length() > 1.6:
		if Doors.is_open(Data.block(game.world.get_block(_door))):
			Doors.toggle(game, _door, global_position)
		_door = null


## "Andrew the Guide": Terraria's name and title.
func title() -> String:
	return "%s the %s" % [display_name, Assets.npc_name(kind)] if display_name != "" else Assets.npc_name(kind)


## Terraria's chat lines (LegacyDialog numbers) for each town NPC; "day" /
## "night" lines only then, "hurt" when you're hurt (the Nurse).
const DIALOG := {
	"guide": {"any": [174, 175, 176], "night": [173]},
	"merchant": {"any": [1, 2, 3, 4, 5, 8, 9, 10, 14, 15, 17, 18, 19, 20, 21, 22, 23, 24], "day": [6, 11, 12], "night": [7]},
	"nurse": {"any": [32, 33, 34, 35], "hurt": [25, 26, 27, 30, 36, 37, 38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 49, 50, 51]},
	"arms_dealer": {"any": [58, 59, 60, 61, 62, 63, 66, 67, 68], "night": [64, 65]},
	"dryad": {"any": [70, 71, 72, 73, 74, 75, 78, 79, 80, 81], "night": [76], "corruption": [69, 77], "crimson": [332, 333]},
	"demolitionist": {"any": [93, 94, 95, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109], "night": [96]},
	"old_man": {"day": [82, 83, 84], "night": [85, 86, 87, 88]},
}
## The Guide's Help button: Terraria's tips that fit this game, in order.
const GUIDE_HELP := [177, 178, 179, 183, 184, 185, 186, 187, 191, 192, 193, 195, 196, 197, 198, 201, 188, 211, 212,
		204, 213, 214, 208, 209, 215, 217, 218, 219, 220]


## What a town NPC says when you talk to them: one of Terraria's lines.
func talk_line() -> String:
	var game := Game.current
	var lines: Dictionary = DIALOG.get(def.get("talk", ""), {})
	var pool: Array = lines.get("any", []).duplicate()
	pool.append_array(lines.get("day" if game.sky.is_day else "night", []))
	if game.player.life < game.player.life_max:
		pool.append_array(lines.get("hurt", []))
	if lines.has("corruption"):
		pool.append_array(lines.get(game.town.world_evil(), []))
	var usable := []
	for n in pool:
		var text := dialog(n)
		if text != "":
			usable.append(text)
	return usable[randi() % usable.size()] if not usable.is_empty() else "..."


## The Guide's next tip (Help): skipping hints about NPCs who already live here.
func next_help() -> String:
	var game := Game.current
	var skip := {195: "Merchant", 196: "Nurse", 197: "ArmsDealer", 198: "Dryad", 201: "Demolitionist"}
	for i in GUIDE_HELP.size():
		var n: int = GUIDE_HELP[(_help_index + i) % GUIDE_HELP.size()]
		if skip.has(n) and game.town.residents.has(skip[n]):
			continue
		var text := dialog(n)
		if text != "":
			_help_index = (_help_index + i + 1) % GUIDE_HELP.size()
			return text
	return "..."


## Terraria's LegacyDialog line `n` with its {placeholders} filled in, or ""
## if it names someone who doesn't live here (or something this game lacks).
static func dialog(n: int) -> String:
	var game := Game.current
	var text: String = Assets.ids.get("names", {}).get("town", {}).get("LegacyDialog", {}).get(str(n), "")
	text = text.replace("{InventoryKey}", "Tab").replace("{WorldName}", game.world_name)
	if "{WorldEvilStone}" in text:
		text = text.replace("{WorldEvilStone}", "Crimstone" if game.town.world_evil() == "crimson" else "Ebonstone")
	for kind in Town.ROSTER:
		if "{%s}" % kind in text:
			var who: String = game.town.name_of(kind)
			if who == "":
				return ""
			text = text.replace("{%s}" % kind, who)
	if "{" in text:
		return ""  # {PlayerName}, or NPCs this game doesn't have
	return text


func dps() -> float:
	var now := Time.get_ticks_msec() / 1000.0
	var total := 0.0
	for h in _hits:
		if now - h[0] <= 3.0:
			total += h[1]
	return total / 3.0



func _ai_slime(delta: float, player) -> void:
	var dir: Vector3 = player.global_position - global_position
	dir.y = 0
	var ticks := delta * 60.0
	# (On the ground as Terraria has it: not moving up or down. A hit that
	# knocks it up counts as in the air from that tick.)
	if on_floor and velocity.y <= 0.0:
		# Terraria's AI_001: on the ground it slides to a stop (x0.8 a tick).
		var keep := pow(0.8, ticks)
		velocity.x *= keep
		velocity.z *= keep
		if Vector2(velocity.x, velocity.z).length() < 0.1 * PX_TICK:
			velocity.x = 0.0
			velocity.z = 0.0
		ai_timer += delta
		sprite.set_frame(int(ai_timer * 4.0) % 2)
		if ai_timer > 1.6:
			ai_timer = randf_range(0.0, 0.5)
			ai_count += 1
			_facing = dir.normalized() if dir.length() < 40.0 else Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
			# Every third hop is a big one: 8 px/tick up and 3 on (else 6 and 2).
			var big := ai_count % 3 == 0
			velocity += _facing * (3.0 if big else 2.0) * PX_TICK
			velocity.y = (8.0 if big else 6.0) * PX_TICK
	else:
		sprite.set_frame(1)
		# In the air it steers the way it faces: moving the other way (knocked
		# back) it slows x0.93 a tick, else it speeds up 0.2 px/tick² to 3.
		if dir.length() > 0.01:
			_facing = dir.normalized()
		var flat := Vector3(velocity.x, 0, velocity.z)
		var along := flat.dot(_facing) / PX_TICK
		if along < 3.0:
			if along > -0.01:
				flat += _facing * 0.2 * ticks * PX_TICK
			else:
				flat *= pow(0.93, ticks)
			velocity.x = flat.x
			velocity.z = flat.z


func _ai_fighter(delta: float, player) -> void:
	var game := Game.current
	var dir: Vector3 = player.global_position - global_position
	dir.y = 0
	var speed: float = def.get("speed", 2.5)
	# Undead wander off at dawn, as in Terraria.
	if _flees_day(game) and global_position.y > game.surface_level - 10:
		if _wander == Vector3.ZERO:
			_wander = -dir.normalized()
		dir = _wander
	if _stuck > 2.5:
		# Give up and try a different direction for a while.
		_wander = Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
		_stuck = 0.0
		ai_timer = 3.0
	if ai_timer > 0.0:
		ai_timer -= delta
		dir = _wander
	# Terraria's AI_003: faster than its walk (knocked back) it slows x0.8 a tick
	# on the ground and not at all in the air; else it speeds up 0.07 px/tick²
	# toward where it's going.
	var flat := Vector2(velocity.x, velocity.z)
	if flat.length() > speed + 0.001:
		if on_floor and velocity.y <= 0.0:
			flat *= pow(0.8, delta * 60.0)
	else:
		var want := Vector2(dir.x, dir.z).normalized() * speed
		flat = flat.move_toward(want, 0.07 * 60.0 * PX_TICK * delta)
	velocity.x = flat.x
	velocity.z = flat.y
	if on_floor and _stuck > 0.15:
		velocity.y = _wall_jump(game, dir)
	var wf: Array = def.get("walk_frames", [0, int(def.frames) - 1])
	if on_floor:
		anim += delta * Vector2(velocity.x, velocity.z).length() * 2.0
		sprite.set_frame(int(wf[0]) + int(anim) % (int(wf[1]) - int(wf[0]) + 1))
	else:
		sprite.set_frame(int(wf[0]))


## Terraria's fighter jump (AI_003) at a wall: 5 px/tick over a low one, 6,
## 7 or 8 as it rises 2, 3 or 4 tiles and more (a tile is 2/3 of a block).
func _wall_jump(game, dir: Vector3) -> float:
	var ahead := global_position + Vector3(dir.x, 0, dir.z).normalized() * (half.x + 0.4)
	var h := 0
	while h < 4 and game.world.is_solid(Vector3i((ahead + Vector3(0, h + 0.5, 0)).floor())):
		h += 1
	var tiles := h * 1.5
	return (5.0 if tiles < 2.0 else (6.0 if tiles < 3.0 else (7.0 if tiles < 4.0 else 8.0))) * PX_TICK


func _ai_flyer(delta: float, player) -> void:
	var target: Vector3 = player.global_position + Vector3(0, 1.0, 0)
	var game := Game.current
	if _flees_day(game) and kind == "DemonEye":
		target = global_position + Vector3(0, 10, 0)  # flee at dawn
	_fly_toward(target, delta)
	anim += delta * 6.0
	_fly_frame()
	if velocity.length() > 0.1 and not def.get("upright", false):
		sprite.set_rotation_angle(EntitySprite.facing_angle(player.camera, velocity) + deg_to_rad(float(def.get("sprite_angle", 0.0))))


## Terraria's harpy: hovers above the player, drifting around them, flapping,
## and throws a feather at them every few seconds.
func _ai_harpy(delta: float, player) -> void:
	ai_timer += delta
	var orbit := Vector3(cos(ai_timer * 0.6) * 6.0, 4.0 + sin(ai_timer * 1.3) * 1.5, sin(ai_timer * 0.6) * 6.0)
	_fly_toward(player.global_position + orbit, delta)
	anim += delta * 8.0
	_fly_frame()


## Hostile shots ("shoot" in its def; harpy feathers, hornet stingers, antlion
## sand) every few seconds while the player is in range. Shots with gravity
## are aimed high enough to arc onto the player.
func _try_shoot(delta: float, player) -> void:
	var shot: Dictionary = def.get("shoot", {})
	if shot.is_empty() or not player.alive:
		return
	_shot_timer -= delta
	var aim: Vector3 = player.global_position + Vector3(0, 1.0, 0) - center()
	if _shot_timer > 0.0 or aim.length() >= float(shot.range):
		return
	_shot_timer = float(shot.interval) * randf_range(0.8, 1.2)
	var speed := float(shot.speed)
	var gravity := float(shot.get("gravity", 0.0))
	var vel := aim.normalized() * speed
	if gravity > 0.0:
		vel.y += gravity * (aim.length() / speed) * 0.5  # rises as much as it will fall
	Game.current.spawn_projectile(shot.projectile, center(), vel, int(shot.damage), 2.0, gravity, 0.0, 0.5, false)
	Audio.play_at("Item_17", center(), 0.6)
	if def.ai == "turret":
		anim = 0.0  # the throw animation (see _ai_turret)


## Antlions: buried in the sand, they stay put and throw sand at you.
func _ai_turret(delta: float, _player) -> void:
	velocity.x = 0.0
	velocity.z = 0.0
	anim = minf(anim + delta * 8.0, float(int(def.frames) - 1))
	sprite.set_frame(int(anim))


## Snatchers and Man Eaters: a jaw on a vine rooted where they spawned,
## lunging at the player within its length (`tether`), turned to face them.
func _ai_snatcher(delta: float, player) -> void:
	if _anchor == null:
		_anchor = global_position
		_vine = MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.09
		cyl.height = 1.0
		cyl.radial_segments = 5
		_vine.mesh = cyl
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.25, 0.45, 0.12)
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_vine.material_override = m
		_vine.top_level = true
		add_child(_vine)
	var tether := float(def.get("tether", 5.0))
	var to: Vector3 = player.global_position + Vector3(0, 0.9, 0)
	var want: Vector3 = _anchor + (to - _anchor).limit_length(tether)
	var speed := float(def.get("speed", 4.0))
	velocity += (want - center()).normalized() * float(def.get("accel", 10.0)) * delta
	if velocity.length() > speed:
		velocity = velocity.normalized() * speed
	anim += delta * 6.0
	sprite.set_frame(int(anim) % int(def.frames))
	var face: Vector3 = to - center()
	if face.length() > 0.1:
		sprite.set_rotation_angle(EntitySprite.facing_angle(player.camera, face) + deg_to_rad(float(def.get("sprite_angle", 0.0))))
	# The vine: from the root to the jaw.
	var a: Vector3 = _anchor
	var b := center()
	var len := maxf(a.distance_to(b), 0.05)
	var up := (b - a) / len
	var side := up.cross(Vector3.FORWARD if absf(up.z) < 0.9 else Vector3.RIGHT).normalized()
	_vine.global_transform = Transform3D(Basis(side, up * len, side.cross(up)), (a + b) * 0.5)


## True if `p` is in water (deep enough to swim in).
func in_water(p: Vector3) -> bool:
	var l: Vector2i = Game.current.world.get_liquid(Vector3i(p.floor()))
	return l.x == 1 and l.y > 8


## Terraria's sharks and jellyfish: in water they chase you while you swim
## (within reach) and wander otherwise, keeping under the surface; jellyfish
## move in pulses and glow when you're close. Stranded, they flop about.
func _ai_swim(delta: float, player) -> void:
	if not in_water(center()):
		velocity.x *= 0.9
		velocity.z *= 0.9
		anim += delta * 3.0
		_fly_frame()
		return
	var speed: float = def.get("speed", 5.0)
	var to: Vector3 = player.global_position + Vector3(0, 0.9, 0) - center()
	var dir: Vector3
	if player.alive and player.in_liquid == 1 and to.length() < 30.0:
		dir = to.normalized()
	else:
		ai_timer -= delta
		if ai_timer <= 0.0:
			ai_timer = randf_range(2.0, 4.0)
			_wander = Vector3(randf_range(-1, 1), randf_range(-0.4, 0.2), randf_range(-1, 1)).normalized()
		dir = _wander
		speed *= 0.4
	if dir.y > 0.0 and not in_water(center() + Vector3(0, half.y * 0.6, 0)):
		dir.y = -0.3  # keep under the surface
	if def.get("pulse", false):
		velocity *= maxf(0.0, 1.0 - 1.5 * delta)
		_pulse -= delta
		if _pulse <= 0.0:
			_pulse = 1.3
			velocity += dir * speed
	else:
		velocity += dir * float(def.get("accel", 5.0)) * delta
		if velocity.length() > speed:
			velocity = velocity.normalized() * speed
	anim += delta * 6.0
	var glow: Array = def.get("glow_frames", [])
	if not glow.is_empty() and to.length() < 3.0:
		sprite.set_frame(int(glow[0]) + int(anim) % (int(glow[1]) - int(glow[0]) + 1))
	else:
		_fly_frame()


## Advances a flier's wing cycle: its "fly_frames" range (default every frame).
## Terraria's flight toward `target` (its "flight": see npcs.json), a tick at
## a time in its px/tick: across the ground toward the target and up or down
## to it each on its own, like Terraria's x and y; drift sideways brakes away.
## Fliers without one steer straight at it at their speed and accel.
func _fly_toward(target: Vector3, delta: float) -> void:
	var f: Dictionary = def.get("flight", {})
	var to := target - center()
	if f.is_empty():
		velocity += to.normalized() * float(def.get("accel", 5.0)) * delta
		var speed: float = def.get("speed", 6.0)
		if velocity.length() > speed:
			velocity = velocity.normalized() * speed
		return
	var ticks := delta * 60.0
	var d := Vector3(to.x, 0, to.z).normalized()
	var flat := Vector3(velocity.x, 0, velocity.z) / PX_TICK
	var along := flat.dot(d)
	var side := flat - d * along
	var vy := velocity.y / PX_TICK
	if f.has("homing"):
		# AI_005: each axis toward the speed at you, twice as hard against its motion.
		var speed: float = f.homing[0]
		var a: float = f.homing[1] * ticks
		var want := to.normalized() * speed
		along = _home_axis(along, want.dot(d), a)
		vy = _home_axis(vy, want.y, a)
		side = side.move_toward(Vector3.ZERO, 2.0 * a)
	else:
		var fx: Array = f.x
		var fy: Array = f.y
		along = _steer_axis(along, 1.0, fx, ticks)
		vy = _steer_axis(vy, signf(to.y) if absf(to.y) > 0.1 else 0.0, fy, ticks)
		side = side.move_toward(Vector3.ZERO, maxf(0.0, float(fx[0]) + float(fx[1])) * ticks)
	flat = d * along + side
	velocity = Vector3(flat.x, vy, flat.z) * PX_TICK


## One axis of Terraria's eye and bat flight (AI_002, aiStyle 14), toward `s`
## (+1 / -1; 0: just brake): accelerate p[0], brake p[1] more while still moving
## the other way, p[2] while over top speed p[3], and no faster than it.
static func _steer_axis(v: float, s: float, p: Array, ticks: float) -> float:
	var a := float(p[0]) * ticks
	var away := float(p[1]) * ticks
	var over := float(p[2]) * ticks
	var top := float(p[3])
	if s == 0.0:
		return move_toward(v, 0.0, a)
	if s < 0.0 and v > -top:
		v -= a
		if v > top:
			v -= over
		elif v > 0.0:
			v -= away
		return maxf(v, -top)
	if s > 0.0 and v < top:
		v += a
		if v < -top:
			v += over
		elif v < 0.0:
			v += away
		return minf(v, top)
	return v


## One axis of AI_005's homing: toward `want` by `a`, again if moving against it.
static func _home_axis(v: float, want: float, a: float) -> float:
	if v < want:
		v += a
		if v < 0.0 and want > 0.0:
			v += a
	elif v > want:
		v -= a
		if v > 0.0 and want < 0.0:
			v -= a
	return v


func _fly_frame() -> void:
	var ff: Array = def.get("fly_frames", [0, int(def.frames) - 1])
	sprite.set_frame(int(ff[0]) + int(anim) % (int(ff[1]) - int(ff[0]) + 1))


func _ai_bat(delta: float, player) -> void:
	ai_timer -= delta
	if ai_timer <= 0.0:
		ai_timer = randf_range(0.5, 1.2)
		_wander = Vector3(randf_range(-3, 3), randf_range(-1, 3), randf_range(-3, 3))
	_fly_toward(player.global_position + Vector3(0, 1.2, 0) + _wander, delta)
	anim += delta * 12.0
	_fly_frame()


## How fast a 3D Eye of Cthulhu turns (radians a second: Terraria's step a tick
## times 60): watching you while hovering, in phase 2, back toward you after a
## charge (once it has held the dash's direction `hold` seconds).
const EOC_TURN := {"hover": 1.2, "hover2": 3.0, "recover": 3.0, "recover2": 4.8, "hold": 40.0 / 60.0}


## Eye of Cthulhu: hover above the player summoning Servants, then charge three
## times. Below half life it transforms (mouth frames), roars and charges harder.
func _ai_eye_of_cthulhu(delta: float, player) -> void:
	var game := Game.current
	var phase2 := ai_state >= 10
	var to_player: Vector3 = player.center() - center()
	anim += delta * 6.0
	sprite.set_frame((3 if phase2 else 0) + int(anim) % 3)

	if _flees_day(game) or not player.alive:
		# Leaves at dawn or when the player dies.
		velocity = velocity.lerp(Vector3(0, 25, 0), 2.0 * delta)
		sprite.set_rotation_angle(EntitySprite.facing_angle(player.camera, Vector3.UP))
		look_dir = Vector3.UP
		turn_rate = EOC_TURN.hover
		if global_position.y > player.global_position.y + 80.0:
			game.on_boss_despawned(self)
			queue_free()
		return

	if not phase2 and life < life_max / 2 and ai_state != 5:
		ai_state = 5  # transformation spin
		ai_timer = 0.0

	ai_timer += delta
	match ai_state:
		0, 10:  # hover above the player
			var orbit := Vector3(sin(ai_timer * 0.8) * 8.0, 9.0, cos(ai_timer * 0.8) * 8.0)
			var target: Vector3 = player.center() + orbit
			var accel := 14.0 if phase2 else 9.0
			velocity = velocity.lerp((target - center()).limit_length(1.0) * (18.0 if phase2 else 12.0), accel * delta * 0.3)
			sprite.set_rotation_angle(EntitySprite.facing_angle(player.camera, to_player))
			# A model turns to watch you (Terraria: 0.02 a tick, 0.05 in phase 2).
			look_dir = to_player
			turn_rate = EOC_TURN.hover2 if phase2 else EOC_TURN.hover
			if not phase2 and int(ai_timer / 1.1) > ai_count and ai_count < 3:
				ai_count += 1
				var s = game.spawn_npc("ServantofCthulhu", center() + to_player.normalized() * 1.5)
				if s:
					s.velocity = to_player.normalized() * 6.0
				Audio.play_at("NPC_Hit_1", center())
			if ai_timer > (1.6 if phase2 else 3.5):
				ai_state += 1
				ai_timer = 0.0
				ai_count = 0
		1, 11:  # charge
			if ai_timer < delta * 1.5:
				velocity = to_player.normalized() * (24.0 if phase2 else 17.0)
				Audio.play_at("Roar_0", center(), 0.7)
				sprite.set_rotation_angle(EntitySprite.facing_angle(player.camera, velocity))
				# Terraria sets its rotation along the dash, holds it 40 ticks,
				# then turns back toward you (0.05 a tick, 0.08 in phase 2).
				look_dir = velocity
				_model_facing = velocity.normalized()
				turn_rate = 0.0
			elif ai_timer > EOC_TURN.hold:
				look_dir = to_player
				turn_rate = EOC_TURN.recover2 if phase2 else EOC_TURN.recover
			velocity *= pow(0.35, delta)
			if ai_timer > (0.75 if phase2 else 1.0):
				ai_count += 1
				ai_timer = 0.0
				if ai_count >= (5 if phase2 else 3):
					ai_count = 0
					ai_state -= 1
		5:  # transformation: spin in place, then roar into phase 2
			velocity *= pow(0.05, delta)
			sprite.set_rotation_angle(ai_timer * ai_timer * 8.0)
			# A model spins the same way, in the plane facing you.
			turn_rate = -1.0
			var cb: Basis = player.camera.global_transform.basis
			look_dir = -cb.y.rotated(cb.z, ai_timer * ai_timer * 8.0)
			if ai_timer > 2.0:
				ai_state = 10
				ai_timer = 0.0
				ai_count = 0
				damage = 23
				defense = 0
				Audio.play_at("Roar_0", center())
				for i in 6:
					game.spawn_dust(center(), Color(0.6, 0.0, 0.0), 6)


# ------------------------------------------------------------ skeletron

## Terraria's px for Skeletron's distances (24 a block, like its sprites).
const SK_PX := 24.0
## Its 3D model (not Terraria's: its sprite always faces the screen): how fast
## it turns round toward you (radians a second), and how much of the way down
## (or up) at you it tips, at most SK_TILT_MAX.
const SK_TURN := 0.6
const SK_TILT := 0.35
const SK_TILT_MAX := deg_to_rad(25.0)


## One axis of Skeletron's steering (aiStyles 11 and 12), in px a tick: toward
## `target` by `accel` a tick, braking by `damp` a tick while it still moves
## the other way, and no faster than `cap` that other way (Terraria caps only
## that side).
static func _sk_axis(v: float, pos: float, target: float, accel: float, damp: float, cap: float, ticks: float) -> float:
	if pos > target:
		if v > 0.0:
			v *= pow(damp, ticks)
		v -= accel * ticks
		return minf(v, cap)
	if pos < target:
		if v < 0.0:
			v *= pow(damp, ticks)
		v += accel * ticks
		return maxf(v, -cap)
	return v


## Skeletron's head (aiStyle 11; the Dungeon Guardian too). It brings its two
## hands. Hovering (ai_state 0), it keeps 250 px over your head and closes on
## you across (0.02 / 0.05 px a tick, 2 / 8 at most the other way); after 800
## ticks it spins at you for 400 (1.5 px a tick, its defense 10 lower). By
## day (always, for the Guardian) it's enraged (2): 9999 damage and defense,
## spinning at you at 8 px a tick. With you dead or 2000 px off it sinks away
## and leaves (3).
func _ai_skeletron(delta: float, game, player) -> void:
	var ticks := delta * 60.0
	var guardian := kind == "DungeonGuardian"
	defense = int(def.defense)
	if ai_count == 0:
		ai_count = 1
		Audio.play_at("Roar_0", center())
		if not guardian:
			for side in [-1, 1]:
				var hand: NPC = game.spawn_npc("SkeletronHand", center())
				if hand != null:
					hand._head = self
					hand._side = side
					# The second hand's timer starts half way (Terraria's ai[3] 150).
					hand.ai_timer = 150.0 if side == 1 else 0.0
	var to: Vector3 = player.center() - center()
	if not player.alive or to.length() > 2000.0 / SK_PX or (guardian and game.biome != "dungeon"):
		if ai_state != 3:
			ai_state = 3
			_sk_timer = 0.0
	elif (guardian or game.sky.is_day) and ai_state != 2 and ai_state != 3:
		ai_state = 2
		Audio.play_at("Roar_0", center())
	var cam: Camera3D = player.camera
	match ai_state:
		0:
			damage = int(def.damage)
			_sk_timer += ticks
			if _sk_timer >= 800.0:
				_sk_timer = 0.0
				ai_state = 1
			var v := velocity / PX_TICK
			var top := global_position.y + half.y
			var player_top: float = player.global_position.y + player.half.y
			v.y = _sk_axis(v.y, top, player_top + 250.0 / SK_PX, 0.02, 0.98, 2.0, ticks)
			# Across (Terraria's x): toward you, any drift sideways braking.
			var d := Vector3(to.x, 0, to.z)
			d = d.normalized() if d.length() > 0.01 else Vector3.FORWARD
			var flat := Vector3(v.x, 0, v.z)
			var along := _sk_axis(flat.dot(d), 0.0, 1.0, 0.05, 0.98, 8.0, ticks)
			var drift := (flat - d * flat.dot(d)) * pow(0.98, ticks)
			v = d * along + drift + Vector3(0, v.y, 0)
			velocity = v * PX_TICK
			# Tilted by its speed across your view (Terraria: velocity.x / 15).
			_spin = velocity.dot(cam.global_transform.basis.x) / PX_TICK / 15.0
		1:
			damage = int(def.damage)
			defense -= 10
			if _sk_timer < 2.0 and _sk_timer + ticks >= 2.0:
				Audio.play_at("Roar_0", center())
			_sk_timer += ticks
			if _sk_timer >= 400.0:
				_sk_timer = 0.0
				ai_state = 0
			_spin += 0.3 * ticks
			velocity = to.normalized() * 1.5 * PX_TICK
		2:
			damage = 9999
			defense = 9999
			_spin += 0.3 * ticks
			velocity = to.normalized() * 8.0 * PX_TICK
		3:
			# Falls away (Terraria's +0.1 a tick downward) and is gone.
			velocity.y -= 0.1 * PX_TICK * ticks
			if velocity.y > 0.0:
				velocity.y *= pow(0.95, ticks)
			velocity.x *= pow(0.95, ticks)
			velocity.z *= pow(0.95, ticks)
			_sk_timer += ticks
			if _sk_timer > 180.0:
				if boss:
					game.on_boss_despawned(self)
				queue_free()
				return
	if sprite is EntitySprite:
		sprite.set_frame(0)
		sprite.set_rotation_angle(_spin)


## Skeletron's hand (aiStyle 12): in your view's terms (Terraria's x across
## it, y up and down; toward you it keeps level with the head). Idle (0, 3) it
## hangs 200 px out to its side and 230 below the head's top (by a spinning
## head: 120 out and 100 above); every 300 ticks it attacks, in turn: up past
## 200 over the head, then down at you at 18 px a tick (1, 2), or out to 500
## px beside the head, then across at you at 17 (4, 5). Without its head it's
## gone in a few ticks.
func _ai_skeletron_hand(delta: float, game, player) -> void:
	var ticks := delta * 60.0
	if _head == null or not is_instance_valid(_head) or _head.life <= 0 or _head.is_queued_for_deletion():
		_sk_timer += 10.0 * ticks
		if _sk_timer > 50.0:
			game.spawn_dust(center(), Color(0.85, 0.85, 0.7), 10)
			for b in _bones:
				b.queue_free()
			queue_free()
		return
	var head: NPC = _head
	var f: Vector3 = player.center() - head.center()
	f.y = 0.0
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	var r := Vector3(-f.z, 0, f.x)
	var rel := center() - head.center()
	var hx := rel.dot(r) * SK_PX
	var hz := rel.dot(f) * SK_PX
	# Tops compared, up positive (Terraria's y the other way).
	var hy := ((global_position.y + half.y) - (head.global_position.y + head.half.y)) * SK_PX
	var v := velocity / PX_TICK
	var vx := v.dot(r)
	var vz := v.dot(f)
	var vy := v.y
	var to: Vector3 = player.center() - center()
	var steer := true
	match ai_state:
		0, 3:
			if head.ai_state != 0:
				vy = _sk_axis(vy, hy, 100.0, 0.07, 0.96, 6.0, ticks)
				vx = _sk_axis(vx, hx, -120.0 * _side, 0.1, 0.96, 8.0, ticks)
			else:
				ai_timer += ticks
				if ai_timer >= 300.0:
					ai_state += 1
					ai_timer = 0.0
				vy = _sk_axis(vy, hy, -230.0, 0.04, 0.96, 3.0, ticks)
				vx = _sk_axis(vx, hx, -200.0 * _side, 0.07, 0.96, 8.0, ticks)
			vz = _sk_axis(vz, hz, 0.0, 0.07, 0.96, 8.0, ticks)
		1:
			vx *= pow(0.95, ticks)
			vz *= pow(0.95, ticks)
			vy = minf(vy + 0.1 * ticks, 8.0)
			if hy > 200.0:
				ai_state = 2
				velocity = to.normalized() * 18.0 * PX_TICK
				steer = false
		2:
			steer = false
			if global_position.y < player.global_position.y or velocity.dot(to) <= 0.0 or to.length() > 2000.0 / SK_PX or velocity.y > 0.0:
				ai_state = 3
		4:
			vy *= pow(0.95, ticks)
			vx = clampf(vx - 0.1 * _side * ticks, -8.0, 8.0)
			if absf(hx) > 500.0:
				ai_state = 5
				velocity = to.normalized() * 17.0 * PX_TICK
				steer = false
		5:
			steer = false
			var hand_r := center().dot(r)
			var player_r: float = player.center().dot(r)
			if (vx > 0.0 and hand_r > player_r) or (vx < 0.0 and hand_r < player_r) or velocity.dot(to) <= 0.0 or to.length() > 2000.0 / SK_PX:
				ai_state = 0
	if steer:
		velocity = (r * vx + f * vz + Vector3(0, vy, 0)) * PX_TICK
	if sprite is EntitySprite:
		sprite.set_frame(0)
		# Its wrist toward where it rests (Terraria: atan2 to it + 90 degrees).
		var rest := head.center() + r * (-200.0 * _side / SK_PX) + Vector3(0, -230.0 / SK_PX, 0)
		sprite.set_rotation_angle(EntitySprite.facing_angle(player.camera, center() - rest))
	# (A model points the same way, not along its flight.)
	look_dir = center() - (head.center() + r * (-200.0 * _side / SK_PX) + Vector3(0, -230.0 / SK_PX, 0))
	_update_arm(game, head, r)


## A hand's arm (Main.DrawNPCDirect): from 20 px down its wrist, a bone 92 px
## toward 200 px out and 130 below the head's middle, then one 60 px toward
## 50 out and 80 below it, each Terraria's Arm_Bone drawn along its way (as
## the NPC picker shows the SkeletronArm: a billboard, or its 3D or rendered
## look, its art's bottom along the bone and its face turned to you).
func _update_arm(game, head: NPC, r: Vector3) -> void:
	if _bones.is_empty():
		var lk := look("SkeletronArm")
		for i in 2:
			var b: Node3D
			if NPCModels.method("SkeletronArm") == "billboard":
				var s := EntitySprite.new()
				s.setup(lk.tex, 1, lk.sprite_size, true, true)
				b = s
			else:
				# Held (the look keeps its own place in it) and turned whole.
				b = Node3D.new()
				b.add_child(make_look("SkeletronArm", lk))
			b.top_level = true
			add_child(b)
			_bones.append(b)
	var cam: Camera3D = game.player.camera
	var p := center() + Vector3(0, half.y * 0.5 - 20.0 / SK_PX, 0) - r * (5.0 * _side / SK_PX)
	var hc := head.center()
	for i in 2:
		var aim := hc + (r * (-200.0 * _side) + Vector3(0, -130.0, 0)) / SK_PX if i == 0 else hc + (r * (-50.0 * _side) + Vector3(0, -80.0, 0)) / SK_PX
		var dir := (aim - p).normalized()
		var length := (92.0 if i == 0 else 60.0) / SK_PX
		p += dir * length
		var b: Node3D = _bones[i]
		if b is EntitySprite:
			b.global_position = p
			b.set_rotation_angle(EntitySprite.facing_angle(cam, dir))
			b.update_light(game.world, game.sky, p)
		else:
			_place_bone(b, p, dir, cam)
			b.get_child(0).update_light(game.world, game.sky, p)
		if i == 0:
			p += dir * length * 0.5


## A 3D or rendered arm bone (in its holder) with its middle at `p`, its art's
## bottom along `dir` and its face turned as far toward the camera as that lets.
func _place_bone(holder: Node3D, p: Vector3, dir: Vector3, cam: Camera3D) -> void:
	var y := -dir
	var to_cam := cam.global_position - p
	var z := to_cam - y * to_cam.dot(y)
	z = z.normalized() if z.length() > 0.001 else cam.global_transform.basis.z
	var b := Basis(y.cross(z), y, z)
	var lk := look("SkeletronArm")
	var node: Node3D = holder.get_child(0)
	holder.global_position = p - Vector3(0, lk.sprite_y, 0)
	if node is NPCModel:
		# Its mesh stands on its bottom: turned round its middle instead.
		node.position = Vector3(0, lk.sprite_y, 0) - b * Vector3(0, NPCModels.frames_of("SkeletronArm").size.y * 0.5, 0)
	node.orient(b)


# ------------------------------------------------------------ damage

## Terraria damage: defense halves, ±15% variance, 4% base crit doubles.
## `armor_pen` ignores that much of its defense (Terraria's armor penetration).
func hit(base_damage: int, knockback: float, dir: Vector3, crit_chance := 0.04, armor_pen := 0) -> void:
	if untouchable:
		return
	var game := Game.current
	var crit := randf() < crit_chance
	var dmg := maxi(1, int(round(base_damage * randf_range(0.85, 1.15) - maxi(0, defense - armor_pen) * 0.5)))
	if crit:
		dmg *= 2
	life -= dmg
	_flash = 1.0
	if def.get("invulnerable", false):
		_hits.append([Time.get_ticks_msec() / 1000.0, dmg])
		life = life_max
		anim = float(int(def.frames) - 1)  # wobble back through the dummy's hit frames
	game.floating_text(str(dmg), center() + Vector3(0, half.y * 0.6, 0), Color(1.0, 0.55, 0.1) if crit else Color(1.0, 0.65, 0.3), crit)
	_knock_back(knockback, dir, dmg, crit)
	Audio.play_at(def.get("hit_sound", "NPC_Hit_1"), center())
	_last_hit_dir = dir
	if life > 0:
		var g: Dictionary = Data.npc_gore.get(kind, {})
		if g.is_empty():
			game.spawn_dust(center(), _blood_color(), 4)
		else:
			# Terraria's hit dust grows with the damage (it was read at 10).
			game.dust.npc_dust(self, g.get("hit_dust", []), float(dmg) / 10.0, dir, _dust_tint())
	if life <= 0:
		_die(game)


## Sets it on fire for `seconds` (Terraria's On Fire!; longer burns win).
func ignite(seconds: float) -> void:
	if def.get("fire_immune", false):
		return
	on_fire = maxf(on_fire, seconds)


## Burning: 4 life a second (Terraria's lifeRegen -8), each 1 shown as it
## goes, and flames all over it (UpdateNPC_BuffApplyVFX: 3 ticks in 4,
## rising; drawn at half Terraria's size).
func _burn_tick(delta: float, game) -> void:
	on_fire -= delta
	_burn += delta * 4.0
	while _burn >= 0.9999:  # (sixty 1/60 s ticks add up to a hair under 4)
		_burn -= 1.0
		game.floating_text("1", center() + Vector3(0, half.y * 0.6, 0), Color(1.0, 0.55, 0.16))
		if def.get("invulnerable", false):
			_hits.append([Time.get_ticks_msec() / 1000.0, 1])
			continue
		life -= 1
		if life <= 0:
			_die(game)
			return
	if randf() < delta * 60.0 * 0.75:
		var at := center() + Vector3(randf_range(-half.x, half.x), randf_range(-half.y, half.y) * 0.5, randf_range(-half.z, half.z))
		game.dust.spawn(6, at, Vector3(0, 0.9, 0), 1.75 if randf() < 0.75 else 0.875)
	if on_fire <= 0.0:
		_burn = 0.0


## Terraria's knockback (NPC.StrikeNPC_Inner), in its units: the weapon's
## knockback times the NPC's knockBackResist, eased off above 8 and at most 16,
## x1.4 on a crit. A hit doing more than a tenth of its life adds that much
## speed away from you (up to it) and three quarters of it upward (half for
## fliers); a weaker hit sets those speeds, its resistance counting twice.
func _knock_back(knockback: float, dir: Vector3, dmg: int, crit: bool) -> void:
	var kbr := float(def.get("knockback_resist", 1.0))
	var k := knockback * kbr
	if k <= 0.0:
		return
	for step in [[8.0, 0.9], [10.0, 0.8], [12.0, 0.7], [14.0, 0.6]]:
		if k > step[0]:
			k = step[0] + (k - step[0]) * step[1]
	k = minf(k, 16.0)
	if crit:
		k *= 1.4
	var away := Vector3(dir.x, 0, dir.z).normalized()
	if away == Vector3.ZERO:
		return
	var flat := Vector3(velocity.x, 0, velocity.z) / PX_TICK
	var along := flat.dot(away)
	var side := flat - away * along
	var rise := k * (0.5 if flying else 0.75)
	var vy := velocity.y / PX_TICK
	if dmg * 10 > life_max:
		if along < k:
			if along < 0.0:
				along += k
			along = minf(along + k, k)
		if vy < rise:
			vy = minf(vy + rise, rise)
	else:
		along = k * kbr
		side = Vector3.ZERO
		vy = rise * kbr
	flat = away * along + side
	velocity = Vector3(flat.x, vy, flat.z) * PX_TICK


## Terraria's death gores: one of its rolls of pieces (head, arms, legs...),
## each where it was on the body (across your view, as Terraria lays them
## out), flung with the enemy's own speed. Their size is the enemy's sprite's.
func gib(game, rolls: Array) -> Array:
	var out := []
	if rolls.is_empty():
		return out
	var roll: Array = rolls[randi() % rolls.size()]
	var lk := look(kind)
	var px: float = lk.sprite_size.y / float(lk.frame_h)
	var right: Vector3 = game.player.camera.global_transform.basis.x
	right.y = 0
	right = right.normalized()
	var top := center().y + half.y * 0.5
	var width := half.x * 2.0
	for gd in roll:
		var gore := Gore.new()
		gore.setup(int(gd[0]), px * float(gd[5]))
		game.entities.add_child(gore)
		# Terraria: x from its left edge, y down from its top (px, its own).
		var across := float(gd[1]) * px - width * 0.5 + randf_range(-0.1, 0.1)
		gore.global_position = Vector3(center().x, top - float(gd[2]) * px - 0.3, center().z) + right * across
		var r := func() -> float: return randi_range(-20, 20) * 0.1
		gore.velocity = velocity / PX_TICK + right * float(gd[3]) + Vector3(0, -float(gd[4]), 0) \
				+ Vector3(r.call(), randi_range(10, 30) * 0.1, r.call())
		out.append(gore)
	return out


## The tint of its dust: slimes bleed their own colour (Terraria's npc.color).
func _dust_tint() -> Color:
	if def.has("tint"):
		var t: Array = def.tint
		return Color(t[0], t[1], t[2])
	return Color.WHITE


## Slimes splatter in their own colour; everything else bleeds.
func _blood_color() -> Color:
	if def.has("tint"):
		var t: Array = def.tint
		return Color(t[0], t[1], t[2])
	return Color(0.65, 0.05, 0.05)


func _die(game) -> void:
	if def.ai == "worm":
		_worm_unlink()
	Audio.play_at(def.get("death_sound", "NPC_Killed_1"), center())
	for d in def.get("drops", []):
		if randf() < float(d[3]):
			game.spawn_item(d[0], randi_range(int(d[1]), int(d[2])), center())
	# One of these at most: the first that rolls (Skeletron's mask, hand, book).
	for d in def.get("drops_chain", []):
		if randf() < float(d[1]):
			game.spawn_item(d[0], 1, center())
			break
	var one_of: Array = def.get("drops_one_of", [])
	if not one_of.is_empty():
		game.spawn_item(one_of[randi() % one_of.size()], 1, center())
	game.spawn_coins(int(def.get("coins", 0)), center())
	var g: Dictionary = Data.npc_gore.get(kind, {})
	if g.is_empty():
		game.spawn_dust(center(), _blood_color(), 14)
	else:
		game.dust.npc_dust(self, g.get("death_dust", []), 1.0, _last_hit_dir, _dust_tint())
		gib(game, g.get("gores", []))
	game.on_npc_killed(self)
	queue_free()
