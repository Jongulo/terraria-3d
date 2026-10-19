class_name Player
extends Node3D
## First-person player: movement, item use (mining, building, combat,
## consumables), health/mana, armor and Terraria's accessory effects.

signal stats_changed
signal died
signal respawned

const EYE_HEIGHT := 1.62
## Terraria's movement (Player.Update, HorizontalMovement, JumpMovement), its
## pixels per tick in blocks per second: 1 px/tick is 2.5 blocks/s (a tile is
## 16 px and 2/3 of a block, 60 ticks a second), 0.01 px/tick² is 1.5 blocks/s².
const RUN_SPEED := 7.5  # maxRunSpeed 3
const RUN_ACCEL := 12.0  # runAcceleration 0.08
const RUN_SLOWDOWN := 30.0  # runSlowdown 0.2 (half of it in the air)
const GRAVITY := 60.0  # 0.4
const MAX_FALL := 25.0  # maxFallSpeed 10
## A jump holds its speed while jump is held, for jumpHeight ticks after the
## first: jumpSpeed 5.01 for 15 (the Shiny Red Balloon: 6.51 for 20).
const JUMP_SPEED := 12.525
const JUMP_TICKS := 15
const BALLOON_JUMP_SPEED := 16.275
const BALLOON_JUMP_TICKS := 20
## In water and lava: gravity 0.2, maxFallSpeed 5, and you move half as far
## (Terraria's WetCollision; honey 0.25, shimmer 0.375).
const LIQUID_GRAVITY := 30.0
const LIQUID_MAX_FALL := 12.5
const LIQUID_MOVE := 0.5
const FLY_SPEED := 13.0
const REACH := 5.5
## Fall damage: 10 for each whole tile fallen beyond 25.
const SAFE_FALL_TILES := 25
const IMMUNE_TIME := 0.67
const POTION_SICKNESS := 60.0
const MAX_LIFE := 400
const MAX_MANA := 200
const LIQ_WATER := 1
const LIQ_LAVA := 2
## Seconds of air underwater (Terraria's 200 breath ticks at 7 ticks each ≈ 23 s).
const BREATH_MAX := 23.0
const DROWN_DPS := 20.0
const LAVA_DAMAGE := 50
const ON_FIRE_TIME := 7.0
const ON_FIRE_DPS := 4.0
## Buried in sand, silt or slush (Terraria's Suffocation: lifeRegen -40).
const SUFFOCATION_DPS := 20.0

var half := Vector3(0.3, 1.8, 0.3)
var velocity := Vector3.ZERO
var on_floor := false
var camera := Camera3D.new()
var viewmodel := Viewmodel.new()
var inventory := Inventory.new(50)
var accessories := Inventory.new(5)
## Head, body and legs (Data.ARMOR_SLOTS order).
var armor := Inventory.new(3)
## Terraria's hook equipment slot (miscEquips[4]): the hook the Grapple key throws.
var hook_slot := Inventory.new(1)
## The yoyo you have out (Yoyo), or null; hold_use keeps it out without the
## mouse (tests).
var yoyo: Yoyo = null
## Boomerangs you've thrown that haven't come back (Boomerang).
var boomerangs: Array = []
## The spear you're holding (Spear, out in the world while you hold one), or null.
var spear: Spear = null
## The flail you're spinning or have thrown (Flail), or null.
var flail: Flail = null
## The slashes you're holding out (Slash: the Terragrim), or null.
var slash: Slash = null
var hold_use := false
## The use button was up last frame (Terraria's releaseUseItem): items that
## don't reuse by themselves (weapons, potions, yoyos...) take a fresh click.
var _use_released := true
var _yoyo_was_out := false
var _flail_was_out := false
var selected := 0

var life := 100
var life_max := 100
var mana := 20
var mana_max := 20
var alive := true
var spawn_point := Vector3.ZERO
## The bed you set your spawn with (NO_BED: none).
var bed := NO_BED
const NO_BED := Vector3i(-1, -1, -1)
## False while a menu has the mouse.
var input_enabled := true
var potion_sickness := 0.0
var respawn_timer := 0.0
## Liquid around the body / at the eyes: 0 none, 1 water, 2 lava.
var in_liquid := 0
var head_liquid := 0
var breath := BREATH_MAX
var on_fire := 0.0
## Test-world cheats: no damage / free flight (jump rises, Shift sinks).
var god_mode := false
var flying := false
## Creative mode (Game.creative): invulnerable, double-tap jump flies, blocks
## break at once without drops, nothing is used up, middle-click picks blocks.
var creative := false

## Current raycast target: {} or {block, normal, id, distance}.
var target := {}

var _yaw := 0.0
var _pitch := 0.0
var _immune := 0.0
var _use_timer := 0.0
## The channelled projectile (Magic Missile) you're steering, if any.
var channelled: Projectile = null
var _free_shots := 0
var _free_shots_item := ""
var _fall_start := 0.0
var _panic := 0.0
var _jump_held := false
## Ticks the jump's speed is still held for (Terraria's Player.jump).
var _jump_ticks := 0
## Extra jumps left in the air (Cloud / Blizzard in a Bottle: each once,
## refilled on the ground), as shares of the jump's length.
var _extra_jumps: Array = []
## The Sharpening Station's buff (Terraria's Sharpened): until you die.
var sharpened := false
## Buried in sand (Suffocation).
var suffocating := false
## A Bast Statue is near (The Bast Defense).
var bast_near := false
var _bast_check := 0.0
## The Ice Blade's bolt: how long until the next one.
var _swing_shot_cd := 0.0
## A charging Glacier Fang: {def, t, paid} ({} when not charging).
var charging := {}
## The Magic Conch's teleport, counting down (< 0: none).
var _conch_timer := -1.0
## Holding on to a rope snake (Snake Charmer's Flute).
var climbing: Node3D = null
## Holding on to a rope or chain (_rope_climb).
var on_rope := false
var _rope_cooldown := 0.0
var _rope_dir_held := false
## Jumped off a rope: no grabbing one again until jump is let go.
var _rope_need_release := false
var _mine_pos := Vector3i(-1, -1, -1)
var _mine_damage := 0.0
var _since_hurt := 0.0
var _regen_acc := 0.0
var _mana_acc := 0.0
var _highlight := MeshInstance3D.new()
var _step_sound := 0.0
var _dot_acc := 0.0
var _last_jump_press := -1000
## Seconds between taps of jump that toggle creative flight.
const DOUBLE_TAP := 0.3


func _ready() -> void:
	_extract_rng.randomize()
	camera.position.y = EYE_HEIGHT
	camera.fov = float(Settings.get_value("fov"))
	camera.near = 0.05
	camera.far = 1000.0  # the sky's backdrops, clouds and sun lie beyond the view distance
	add_child(camera)
	camera.add_child(viewmodel)
	viewmodel.player = self
	_highlight.mesh = BoxMesh.new()
	(_highlight.mesh as BoxMesh).size = Vector3.ONE * 1.004
	var m := ShaderMaterial.new()
	m.shader = preload("res://shaders/block_highlight.gdshader")
	_highlight.material_override = m
	_highlight.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_highlight.top_level = true
	add_child(_highlight)
	inventory.changed.connect(func(): stats_changed.emit())
	armor.changed.connect(func(): stats_changed.emit())
	accessories.changed.connect(func(): stats_changed.emit())


func center() -> Vector3:
	return global_position + Vector3(0, 0.9, 0)


func forward() -> Vector3:
	return -camera.global_transform.basis.z


func yaw() -> float:
	return _yaw


## True if the player's box is in a block with this flag set (cobwebs: "sticky").
func touching(flag: String) -> bool:
	var w := Game.current.world
	var lo := (global_position - Vector3(half.x, 0, half.z)).floor()
	var hi := (global_position + Vector3(half.x, half.y, half.z) - Vector3.ONE * 0.001).floor()
	for x in range(int(lo.x), int(hi.x) + 1):
		for y in range(int(lo.y), int(hi.y) + 1):
			for z in range(int(lo.z), int(hi.z) + 1):
				if Data.block(w.get_block(Vector3i(x, y, z))).get(flag, false):
					return true
	return false


## The point the crosshair is on (the targeted block's face), or REACH ahead.
func aim_point() -> Vector3:
	return camera.global_position + forward() * float(target.get("distance", REACH))


func overlaps_block(p: Vector3i) -> bool:
	return _box_overlap(global_position, half, Vector3(p))


func overlaps_point(p: Vector3, radius: float) -> bool:
	var pos := global_position
	return absf(p.x - pos.x) < half.x + radius and absf(p.z - pos.z) < half.z + radius \
			and p.y > pos.y - radius and p.y < pos.y + half.y + radius


func held() -> Dictionary:
	var s = inventory.slots[selected]
	return {} if s == null else Data.item(s.item)


## Maximum mana with equipment (Band of Starpower: +20, Jungle armor).
func mana_cap() -> int:
	return mana_max + int(stat("mana_bonus"))


## What you wear: the armor pieces and accessories, then the set bonus (if
## the three pieces make a set), as item-like dictionaries of stats.
func equipment() -> Array:
	var out := []
	for inv in [armor, accessories]:
		for s in inv.slots:
			if s != null:
				out.append(Data.item(s.item))
	var bonus := armor_set()
	if not bonus.is_empty():
		out.append(bonus)
	return out


## The armor set the three pieces you wear make ({} if none), like Terraria's.
func armor_set() -> Dictionary:
	var worn := []
	for s in armor.slots:
		worn.append("" if s == null else s.item)
	for a in Data.armor_sets:
		if worn == [a.head, a.body, a.legs]:
			return a
	return {}


## The sum of a stat over your equipment and set bonus (Data's armor keys:
## defense, melee_damage, magic_crit, mining_speed, ...).
func stat(key: String) -> float:
	var total := 0.0
	for d in equipment():
		var v = d.get(key, 0)
		if v is float or v is int:
			total += v
	return total


## Whether something you wear has this effect (Hermes Boots: "run_speed",
## the Molten set: "fire_immune", ...).
func has_effect(effect: String) -> bool:
	for d in equipment():
		if d.has(effect):
			return true
	return false


func defense() -> int:
	return int(stat("defense")) + (BAST_DEFENSE if bast_near else 0)


const BAST_DEFENSE := 5
## The Bast Statue's reach: Terraria's 170 x 125 tiles round it.
const BAST_REACH := Vector3i(57, 42, 57)
const SHARPENED_PEN := 12


## Armor penetration of a weapon's hits: the Sharpening Station's 12 for melee.
func armor_penetration(def: Dictionary) -> int:
	return SHARPENED_PEN if sharpened and _damage_kind(def) == "melee" else 0


## A weapon's damage with your bonuses (Terraria adds them: armor's "7%
## increased melee damage" and so on).
func weapon_damage(def: Dictionary, base := -1) -> int:
	var kind := _damage_kind(def)
	var mult := 1.0 + (stat("damage") + (stat(kind + "_damage") if kind != "" else 0.0)) / 100.0
	return maxi(1, int(round(float(def.get("damage", 1) if base < 0 else base) * mult)))


## Critical strike chance (0..1): Terraria's base 4% plus your bonuses.
func crit_chance(def: Dictionary) -> float:
	var kind := _damage_kind(def)
	# The weapon's own crit (Terraria's item crit: the Ice Boomerang's +2) adds on.
	return (4.0 + float(def.get("crit", 0)) + stat("crit") + (stat(kind + "_crit") if kind != "" else 0.0)) / 100.0


static func _damage_kind(def: Dictionary) -> String:
	return {"melee": "melee", "tool": "melee", "ranged": "ranged", "magic": "magic", "thrown": "thrown"}.get(def.get("type", ""), "")


## The light you carry: a held torch or a Mining Helmet (black: none).
## Shaders add it around the camera (shaders/player_light.gdshaderinc).
func carried_light() -> Color:
	var c := Color.BLACK
	var h := held()
	# A held Demon Torch pulses like a placed one.
	var lights := [h.get("light")] if not h.has("pulse") else [_color_array(Data.pulse_color(h.pulse))]
	for s in armor.slots:
		if s != null:
			lights.append(Data.item(s.item).get("light"))
	# Slashing, the Terragrim shines (Terraria's AddLight at its tip).
	if slash_out():
		lights.append(slash.def.slash.get("light"))
	for l in lights:
		if l is Array and alive:
			c = Color(maxf(c.r, l[0]), maxf(c.g, l[1]), maxf(c.b, l[2]))
	return c


static func _color_array(c: Color) -> Array:
	return [c.r, c.g, c.b]


# ------------------------------------------------------------------ input

func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not alive:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var sens := float(Settings.get_value("mouse_sensitivity"))
		var invert := -1.0 if Settings.get_value("invert_y") else 1.0
		_yaw -= event.relative.x * sens
		_pitch = clampf(_pitch - event.relative.y * sens * invert, -1.55, 1.55)
		rotation.y = _yaw
		camera.rotation.x = _pitch
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select((selected + 1) % 10)
			return
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select((selected + 9) % 10)
			return
	if event.is_echo():
		return
	if event.is_action_pressed("interact"):
		_interact()
	elif event.is_action_pressed("quick_heal"):
		quick_heal()
	elif event.is_action_pressed("throw_item"):
		throw_held()
	elif event.is_action_pressed("grapple"):
		grapple()
	elif event.is_action_pressed("pick_block") and creative:
		pick_block()
	else:
		for i in 10:
			if event.is_action_pressed("hotbar_%d" % (i + 1)):
				select(i)
				break


## Creative: the targeted block's item into the hotbar (Minecraft's pick
## block): selects it if it's already there, else fills the held slot if
## empty, else a free hotbar slot, else replaces what's held.
func pick_block() -> bool:
	if target.is_empty():
		return false
	var item := Data.block_item(Game.current.world.get_block(Doors.bottom(Game.current.world, target.block)))
	if item == "":
		return false
	for i in 10:
		if inventory.slots[i] != null and inventory.slots[i].item == item:
			select(i)
			return true
	var slot := selected
	if inventory.slots[slot] != null:
		for i in 10:
			if inventory.slots[i] == null:
				slot = i
				break
	inventory.slots[slot] = Inventory.stack(item, inventory.max_stack(item))
	inventory.changed.emit()
	select(slot)
	return true


func select(i: int) -> void:
	selected = i
	_mine_damage = 0.0
	stats_changed.emit()


func look_at_yaw_pitch(yaw: float, pitch: float) -> void:
	_yaw = yaw
	_pitch = pitch
	rotation.y = yaw
	camera.rotation.x = pitch


# ------------------------------------------------------------------ update

func _physics_process(delta: float) -> void:
	var game := Game.current
	if not alive:
		respawn_timer -= delta
		if respawn_timer <= 0.0:
			_respawn()
		return
	_update_liquid(game)
	_move(delta, game)
	_flower_boots(game)
	_regen(delta)
	_liquid_effects(delta)
	_immune = maxf(0.0, _immune - delta)
	potion_sickness = maxf(0.0, potion_sickness - delta)
	_use_timer = maxf(0.0, _use_timer - delta)
	_swing_shot_cd = maxf(0.0, _swing_shot_cd - delta)
	_update_bast(delta, game)
	_update_charge(delta)
	if _conch_timer >= 0.0:
		_conch_timer -= delta
		if _conch_timer < 0.0:
			ocean_teleport()

	target = Doors.raycast(game, camera.global_position, forward(), REACH) if input_enabled else {}
	_highlight.visible = not target.is_empty() and not game.taking_screenshot
	if _highlight.visible:
		# Doors outline their panel (both halves); other blocks their cell.
		var box := Doors.outline(game, target.block)
		_highlight.global_position = box.get_center()
		_highlight.scale = box.size
	if input_enabled and Input.is_action_pressed("use_item") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		use_item()
	if yoyo_out():
		# Held out while the use button is down and it's still in your hand.
		yoyo.held = held().get("internal", "") == yoyo.def.internal and use_down()
	elif _yoyo_was_out:
		# Terraria keeps the yoyo's item busy for 2 ticks after it's back.
		_use_timer = maxf(_use_timer, 2.0 / 60.0)
	_yoyo_was_out = yoyo_out()
	# Terraria keeps a flail's item busy for 2 ticks after it's caught too.
	if _flail_was_out and not flail_out():
		_use_timer = maxf(_use_timer, 2.0 / 60.0)
	_flail_was_out = flail_out()
	_update_spear()
	_use_released = not use_down()
	viewmodel.update_light(game.world.get_light(camera.global_position), game.sky, carried_light())
	update_carried_light()


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("player_light_color", Vector3.ZERO)


## Hands the carried light to the shaders (global uniforms, project.godot).
func update_carried_light() -> void:
	var c := carried_light()
	RenderingServer.global_shader_parameter_set("player_light_pos", camera.global_position)
	RenderingServer.global_shader_parameter_set("player_light_color", Vector3(c.r, c.g, c.b))


func _move(delta: float, game) -> void:
	var input := Vector2.ZERO
	if input_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	# Creative: double-tap jump to start or stop flying, like Minecraft.
	if creative and input_enabled and Input.is_action_just_pressed("jump"):
		var now := Time.get_ticks_msec()
		if now - _last_jump_press < DOUBLE_TAP * 1000.0:
			toggle_creative_flight()
			_last_jump_press = -1000
		else:
			_last_jump_press = now
	if flying:
		_fly(delta, game, dir)
		return
	if _grapple(delta, game):
		return
	if _climb(delta, game, dir):
		return
	if _rope_climb(delta, game, dir):
		return
	var ground := Data.block(game.world.get_block(Vector3i((global_position + Vector3(0, -0.1, 0)).floor()))) if on_floor else {}
	# Terraria's run: its speed, the boots' speed, acceleration and slowdown,
	# changed by what you wear and stand in.
	var max_run := RUN_SPEED
	var acc_run := maxf(RUN_SPEED, best("run_speed"))
	var accel := RUN_ACCEL
	var slowdown := RUN_SLOWDOWN
	# Movement speed bonuses speed up the run, not the boots.
	var move := 1.0 + stat("move_speed") / 100.0
	max_run *= move
	accel *= move
	# Panic Necklace: a burst of speed after being struck.
	_panic = maxf(0.0, _panic - delta)
	if _panic > 0.0:
		max_run *= 1.4
	# Dunerider Boots: 75% faster on sand, sandstone and hardened sand.
	if ground.get("name", "") in SAND_RUN_BLOCKS and stat("sand_run") > 0.0:
		var k := stat("sand_run")
		max_run *= k
		acc_run *= k
		accel *= k
		slowdown *= k
	# Ice: you slide; Ice Skates grip and run a quarter faster on it.
	if ground.get("slippery", false):
		accel *= 0.7
		if has_effect("ice_skates"):
			accel *= 3.5
			max_run *= 1.25
		else:
			slowdown *= 0.1
	# Shadow armor: quicker to speed up and stop, and a little faster
	# (Terraria's shadowArmor: acceleration and slowdown x1.75, speeds x1.15).
	if has_effect("shadow_run"):
		accel *= 1.75
		slowdown *= 1.75
		max_run *= 1.15
		acc_run *= 1.15
	# Cobwebs: caught, you can only crawl through.
	var webbed := touching("sticky")
	if webbed:
		max_run *= 0.25
		accel *= 0.25
		slowdown *= 2.0
	_run(delta, dir, max_run, acc_run, accel, slowdown)
	if webbed:
		var flat := Vector2(velocity.x, velocity.z).limit_length(max_run)
		velocity.x = flat.x
		velocity.z = flat.y

	var jump := input_enabled and Input.is_action_pressed("jump")
	var jump_speed := BALLOON_JUMP_SPEED if has_effect("jump_boost") else JUMP_SPEED
	var jump_ticks := BALLOON_JUMP_TICKS if has_effect("jump_boost") else JUMP_TICKS
	if webbed:
		jump_speed /= 5.0
		jump_ticks /= 10
	# Like Terraria, you can't swim: in water and lava you sink, and you jump
	# only off the bottom (or with a double jump you haven't used); the jump
	# goes half as far, like all movement in liquid (JumpMovement starts a
	# jump only standing, sliding, with a jump left, or wet with Flippers).
	if jump and not _jump_held:
		if on_floor:
			velocity.y = jump_speed
			_jump_ticks = jump_ticks
		elif not _extra_jumps.is_empty():
			velocity.y = jump_speed
			_jump_ticks = int(jump_ticks * float(_extra_jumps.pop_front()))
			# Like Terraria, the fall restarts here: a double jump just above
			# the ground saves you from a long fall.
			_fall_start = global_position.y
			Audio.play("Double_Jump")
			game.spawn_dust(global_position, Color(0.9, 0.95, 1.0), 10)
	elif jump and _jump_ticks > 0:
		velocity.y = jump_speed
		_jump_ticks -= 1
	if not jump:
		# Letting go ends the jump's push; you rise on as gravity slows you.
		_jump_ticks = 0
	_jump_held = jump

	if in_liquid != 0:
		# Water and lava: lighter gravity, a slow sinking speed, fast falls
		# damped.
		velocity.y -= LIQUID_GRAVITY * delta
		if velocity.y < -LIQUID_MAX_FALL:
			velocity.y = move_toward(velocity.y, -LIQUID_MAX_FALL, 80.0 * delta)
		_fall_start = global_position.y
	else:
		velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL)
	if webbed:
		# Stuck in a web: you sink and climb slowly, and a fall stops there.
		velocity.y = clampf(velocity.y, -1.0, 1.5)
		_fall_start = global_position.y
	# Buried in sand, silt or slush: stuck in it, suffocating, until you dig
	# out (Terraria doesn't push you clear).
	if buried():
		velocity = Vector3.ZERO
		_fall_start = global_position.y
		return
	# Holding Drop down falls through platforms (Terraria's down key).
	var drop := input_enabled and Input.is_action_pressed("drop_down")
	var step := velocity * delta * (LIQUID_MOVE if in_liquid != 0 else 1.0)
	var r: Dictionary = game.world.move_aabb(global_position, half, step, 1.05 if on_floor else 0.0, drop)
	var was_on_floor := on_floor
	global_position = r.position
	on_floor = r.on_floor
	var blocked: Vector3i = r.blocked
	if blocked.y:
		if velocity.y < 0.0:
			var fall := _fall_start - global_position.y
			# Lucky Horseshoe, or landing on a cloud: no fall damage.
			var below := Vector3i((global_position + Vector3(0, -0.1, 0)).floor())
			if has_effect("no_fall_damage") or Data.block(game.world.get_block(below)).get("fall_safe", false):
				fall = 0.0
			var tiles := int(fall * 1.5)
			if tiles > SAFE_FALL_TILES:
				hurt((tiles - SAFE_FALL_TILES) * 10, Vector3.ZERO, true)
		elif velocity.y > 0.0:
			_jump_ticks = 0  # a bumped head ends the jump
		velocity.y = 0.0
	if blocked.x:
		velocity.x = 0.0
	if blocked.z:
		velocity.z = 0.0
	if on_floor:
		_fall_start = global_position.y
		_extra_jumps = extra_jumps()
	else:
		_fall_start = maxf(_fall_start, global_position.y)
	if on_floor and not was_on_floor and velocity.y <= 0.0:
		Audio.play("Dig_*", 0.15)
	# Out of the world: put the player back.
	if global_position.y < -10.0:
		global_position = spawn_point


## Terraria's run (HorizontalMovement), turned to face the way you press:
## along it you speed up by `accel` up to `max_run` (first shedding
## `slowdown` if going the other way); past that, boots keep speeding up on
## the ground at a fifth of `accel`, up to `acc_run`. Drift across it, and
## all of your speed when you press nothing, slows by `slowdown` on the
## ground and half that in the air.
func _run(delta: float, dir: Vector3, max_run: float, acc_run: float, accel: float, slowdown: float) -> void:
	var v := Vector2(velocity.x, velocity.z)
	var friction := slowdown * (1.0 if on_floor else 0.5) * delta
	var d := Vector2(dir.x, dir.z)
	if d == Vector2.ZERO:
		v = v.move_toward(Vector2.ZERO, friction)
	else:
		d = d.normalized()
		var along := v.dot(d)
		var side := (v - d * along).move_toward(Vector2.ZERO, friction)
		if along < max_run:
			if along < -slowdown * delta:
				along += slowdown * delta
			along += accel * delta
		elif along < acc_run:
			if on_floor:
				along += accel * 0.2 * delta
		else:
			along = move_toward(along, 0.0, friction)
		v = d * along + side
	velocity.x = v.x
	velocity.z = v.y


## The highest value of `key` on what you wear (Terraria sets, not adds,
## the boots' speed).
func best(key: String) -> float:
	var top := 0.0
	for d in equipment():
		top = maxf(top, float(d.get(key, 0)))
	return top


## Blocks the Dunerider Boots run faster on (Terraria's sand, sandstone and
## hardened sand of every kind; not smooth sandstone or its brick).
const SAND_RUN_BLOCKS := ["sand", "ebonsand", "crimsand", "pearlsand", "sandstone", "hardened_sand"]
## Double jumps, as a share of the jump's length (Terraria's: the Cloud 0.75,
## the Blizzard 1.5).
const EXTRA_JUMPS := {"cloud": 0.75, "blizzard": 1.5}


## The jumps you get in the air from what you wear (each bottle once; the
## Cloud's first, like Terraria's).
func extra_jumps() -> Array:
	var kinds := []
	for d in equipment():
		if d.get("double_jump", false):
			var k: String = d.get("jump_kind", "cloud")
			if not k in kinds:
				kinds.append(k)
	kinds.sort_custom(func(a, b): return EXTRA_JUMPS.keys().find(a) < EXTRA_JUMPS.keys().find(b))
	return kinds.map(func(k): return EXTRA_JUMPS.get(k, 0.75))


## Checks once a second for a Bast Statue near you (Terraria's nearby-tile
## buff: The Bast Defense, +5 defense).
func _update_bast(delta: float, game) -> void:
	_bast_check -= delta
	if _bast_check > 0.0:
		return
	_bast_check = 1.0
	var was := bast_near
	bast_near = Data.near_buff_ids.has("CatBast") and game.world.any_block_near(Vector3i(center().floor()), BAST_REACH, Data.near_buff_ids.CatBast)
	if bast_near != was:
		stats_changed.emit()


## Climbing a rope snake: grab it by jumping into it; jump climbs, Drop down
## lets you down, walking off it lets go. True while on it.
func _climb(delta: float, game, dir: Vector3) -> bool:
	var jump := input_enabled and Input.is_action_pressed("jump")
	var down := input_enabled and Input.is_action_pressed("drop_down")
	if climbing != null and (not is_instance_valid(climbing) or not climbing.holds(global_position)):
		climbing = null
	if climbing == null and jump:
		for r in get_tree().get_nodes_in_group("rope_snakes"):
			if r.holds(global_position):
				climbing = r
				break
	if climbing == null:
		return false
	var v := (1.0 if jump else 0.0) - (1.0 if down else 0.0)
	velocity = dir * 2.0 + Vector3(0, v * RopeSnake.CLIMB_SPEED, 0)
	# Not past its head.
	if velocity.y > 0.0 and global_position.y >= climbing.top() - 0.5:
		velocity.y = 0.0
	var r: Dictionary = game.world.move_aabb(global_position, half, velocity * delta, 0.0, true)
	global_position = r.position
	on_floor = r.on_floor
	_fall_start = global_position.y
	_extra_jumps = extra_jumps()
	_jump_held = jump
	return true


## Grappling: pulled at up to 11 px a tick; under 2 px a tick you hang still
## (and can jump off).
const GRAPPLE_PULL := 11.0 * 2.5
const GRAPPLE_STILL := 2.0 * 2.5

## Where you hold a rope: Terraria's hand, half a tile (1/3 block) over your
## head (Player.FindPulley: position.Y - 8 px). You can climb on while there
## is rope a tile above that (position.Y - 16 px).
const ROPE_HAND := 1.8 + 1.0 / 3.0
const ROPE_REACH := 1.8 + 2.0 / 3.0
## Climbing (Player.Update's pulley movement, in px a tick x2.5): up to 3 px
## a tick quickly (0.2 a tick each tick), then slowly (0.02) on up to 8; down
## the same to 3, then (0.1) on to the fall speed. Let go of both, it slows
## to a stop (x0.7 a tick).
const ROPE_FAST := 7.5
const ROPE_ACCEL := 30.0
const ROPE_UP_ACCEL := 3.0
const ROPE_UP_MAX := 20.0
const ROPE_DOWN_ACCEL := 15.0
## You hang this far beside the rope (Terraria: 6 px to its side, a quarter
## block; farther here, so in first person it isn't right in your face).
const ROPE_HANG := 0.45
## Dropping or walking off a rope, it can't be grabbed again for 10 ticks
## (Terraria's ropeCount).
const ROPE_REGRAB := 10.0 / 60.0


## Ropes and chains, like Terraria's (Up and Down are jump and Drop down):
## either grabs the rope at your hand; jump climbs, Drop down slides down, a
## tap sideways moves you to the rope beside you or lets go, and jumping
## while you move leaps off. True while on one.
func _rope_climb(delta: float, game, dir: Vector3) -> bool:
	var w: VoxelWorld = game.world
	var up := input_enabled and Input.is_action_pressed("jump")
	var down := input_enabled and Input.is_action_pressed("drop_down")
	var tapped := dir != Vector3.ZERO and not _rope_dir_held
	_rope_dir_held = dir != Vector3.ZERO
	_rope_cooldown = maxf(0.0, _rope_cooldown - delta)
	if not up:
		_rope_need_release = false
	var hand := Vector3i((global_position + Vector3(0, ROPE_HAND, 0)).floor())
	var grabbed := false
	if not on_rope:
		if _rope_cooldown > 0.0 or not (down or up and not _rope_need_release) or not Ropes.is_rope(w, hand):
			return false
		on_rope = true
		grabbed = true
	if not Ropes.is_rope(w, hand):
		on_rope = false  # off the end of it
		return false
	if up and dir != Vector3.ZERO and not grabbed and (tapped or not _jump_held):
		# Leaping off: a full jump (Terraria's jump off a rope).
		on_rope = false
		_rope_need_release = true
		velocity = Vector3(dir.x * 2.5, JUMP_SPEED, dir.z * 2.5)
		_jump_ticks = JUMP_TICKS
		_jump_held = true
		return false
	var shift := Vector3.ZERO
	if tapped and not up:
		var side := Vector3i(signi(roundi(dir.x)), 0, 0) if absf(dir.x) > absf(dir.z) else Vector3i(0, 0, signi(roundi(dir.z)))
		if Ropes.is_rope(w, hand + side):
			shift = Vector3(side)  # along to the next rope
		else:
			# Let go, with a little push (1 px a tick).
			on_rope = false
			_rope_cooldown = ROPE_REGRAB
			velocity = Vector3(dir.x * 2.5, 0.0, dir.z * 2.5)
			return false
	var vertical := Ropes.is_rope(w, hand + Vector3i.UP) or Ropes.is_rope(w, hand + Vector3i.DOWN)
	var can_up := Ropes.is_rope(w, Vector3i((global_position + Vector3(0, ROPE_REACH, 0)).floor()))
	var slow := pow(0.7, delta * 60.0)
	if not vertical:
		# A rope across: you hang still; Drop down drops you.
		if down:
			on_rope = false
			_rope_cooldown = ROPE_REGRAB
			velocity = Vector3(0, -2.5, 0)
			return false
		velocity.y = 0.0
	elif up and can_up:
		if velocity.y < 0.0:
			velocity.y *= slow
		velocity.y = minf(ROPE_UP_MAX, velocity.y + (ROPE_ACCEL if velocity.y < ROPE_FAST else ROPE_UP_ACCEL) * delta)
	elif down:
		if velocity.y > 0.0:
			velocity.y *= slow
		velocity.y = maxf(-MAX_FALL, velocity.y - (ROPE_ACCEL if velocity.y > -ROPE_FAST else ROPE_DOWN_ACCEL) * delta)
	else:
		velocity.y *= slow
		if absf(velocity.y) < 0.25:
			velocity.y = 0.0
	if not can_up and velocity.y > 0.0:
		velocity.y = 0.0
	# Hang beside the rope, on the side you came from.
	var axis := Vector3(hand.x + 0.5, 0, hand.z + 0.5) + shift
	var off := Vector3(global_position.x - axis.x, 0, global_position.z - axis.z)
	if off.length() < 0.05:
		off = -forward() * Vector3(1, 0, 1)
	var hang := axis + off.normalized() * ROPE_HANG - Vector3(global_position.x, 0, global_position.z)
	var step := Vector3(hang.x, 0, hang.z) * (1.0 if shift != Vector3.ZERO else minf(1.0, 15.0 * delta))
	step.y = velocity.y * delta
	if step.y > 0.0:
		# Not past where the hand is a tile under the rope's top.
		var top := hand
		while Ropes.is_rope(w, top + Vector3i.UP):
			top += Vector3i.UP
		step.y = minf(step.y, maxf(0.0, top.y + 1.0 - ROPE_REACH - global_position.y))
	var r: Dictionary = w.move_aabb(global_position, half, step, 0.0, true)
	global_position = r.position
	on_floor = r.on_floor
	velocity.x = 0.0
	velocity.z = 0.0
	if r.blocked.y:
		velocity.y = 0.0
	_fall_start = global_position.y
	_extra_jumps = extra_jumps()
	_jump_ticks = 0
	_jump_held = up
	return true


## Your grappling hooks out (GrappleHook).
func hooks() -> Array:
	return get_tree().get_nodes_in_group("grapple_hooks").filter(func(h): return h.player == self and not h.is_queued_for_deletion())


## Where your hooks' chains start: low and to the right of your view, so you
## see the chain go out.
func hook_hand() -> Vector3:
	var b := camera.global_transform.basis
	return camera.global_position + b.x * 0.3 - b.y * 0.35 - b.z * 0.8


## The Grapple key (Terraria's QuickGrapple_GetItemToUse): the hook in your
## hook slot, else the first one in your inventory.
func grapple() -> bool:
	if not alive:
		return false
	var def := grapple_hook()
	return not def.is_empty() and fire_hook(def)


## The hook the Grapple key throws ({} if you have none).
func grapple_hook() -> Dictionary:
	for s in hook_slot.slots + inventory.slots:
		if s != null and Data.item(s.item).get("type") == "hook":
			return Data.item(s.item)
	return {}


## Throws a hook where you look, if it may go (Terraria's QuickGrapple): `fly`
## out at once, less those latched (at least one); with `out` already out the
## oldest lets go (single hooks: throwing again lets go of the last).
func fire_hook(def: Dictionary) -> bool:
	var h: Dictionary = def.hook
	var mine := hooks()
	var latched := mine.filter(func(k): return k.latched()).size()
	var flying_out := mine.size() - latched
	if flying_out >= maxi(1, int(h.get("fly", 3)) - latched):
		return false
	if not mine.is_empty() and mine.size() >= int(h.get("out", 999)):
		var oldest: GrappleHook = mine[0]
		for k in mine:
			if k.born < oldest.born:
				oldest = k
		oldest.queue_free()
	var hook := GrappleHook.new()
	hook.setup(self, h, forward())
	Game.current.entities.add_child(hook)
	hook.global_position = center()
	Audio.play(def.get("sound", "Item_1"), 0.6)
	return true


## A hook just latched on: like Terraria, the fall restarts and your jumps
## come back.
func on_hook_latched() -> void:
	on_rope = false
	climbing = null
	_fall_start = global_position.y
	_extra_jumps = extra_jumps()


## Pulled by your latched hooks (Player.GrappleMovement): toward the middle of
## them at up to 11 px a tick, no gravity, no falls. Jump lets go of them all,
## with a jump if you hang still (moving under 2 px a tick; not holding Drop
## down). True while you're held.
func _grapple(delta: float, game) -> bool:
	var held_by := hooks().filter(func(h): return h.latched())
	if held_by.is_empty():
		return false
	var jump := input_enabled and Input.is_action_pressed("jump")
	if jump and not _jump_held:
		var still := velocity.length() < GRAPPLE_STILL and not (input_enabled and Input.is_action_pressed("drop_down"))
		for h in hooks():
			h.queue_free()
		_extra_jumps = extra_jumps()
		_jump_held = true
		if still:
			velocity.y = JUMP_SPEED
			_jump_ticks = JUMP_TICKS
		return false
	_jump_held = jump
	var to := Vector3.ZERO
	for h in held_by:
		to += h.global_position
	to = to / held_by.size() - center()
	var want := to / delta
	if want.length() > GRAPPLE_PULL:
		want = want.normalized() * GRAPPLE_PULL
	var start := global_position
	var r: Dictionary = game.world.move_aabb(global_position, half, want * delta, 0.0, want.y < 0.0)
	global_position = r.position
	on_floor = r.on_floor
	# What you really moved (blocks stop you): how still you hang.
	velocity = (global_position - start) / delta
	_fall_start = global_position.y
	_extra_jumps = extra_jumps()
	_jump_ticks = 0
	return true


## A Rope Coil thrown where you look (shootSpeed 10).
func _throw_rope_coil(def: Dictionary) -> bool:
	var game := Game.current
	var c := RopeCoil.new()
	c.setup(def.internal, def.rope_coil)
	c.velocity = forward() * RopeCoil.SPEED
	game.entities.add_child(c)
	var start := camera.global_position + forward() * 0.5
	c.global_position = start if not game.world.is_solid(Vector3i(start.floor())) else camera.global_position
	_use_up(selected)
	Audio.play(def.get("sound", "Item_1"), 0.6)
	return true


## Snake Charmer's Flute: a rope snake rises from a basket where you aim (on
## the ground, within reach), else at your feet.
func _summon_rope_snake(def: Dictionary) -> bool:
	var game := Game.current
	var base := Vector3i(global_position.floor())
	if not target.is_empty() and target.has("block"):
		var t: Vector3i = target.block + Vector3i(target.get("normal", Vector3i.UP))
		if not game.world.is_solid(t) and game.world.is_solid(t + Vector3i.DOWN):
			base = t
	for r in get_tree().get_nodes_in_group("rope_snakes"):
		r.queue_free()  # one at a time
	var snake := RopeSnake.new()
	snake.setup(def.rope_snake)
	game.entities.add_child(snake)
	snake.global_position = Vector3(base) + Vector3(0.5, 0, 0.5)
	Audio.play(def.get("sound", "Item_151"), 0.7)
	return true


## The Magic Conch: off to the beach of the ocean furthest from you (across
## the world from where you are), on the sand by the water.
func ocean_teleport() -> void:
	var game := Game.current
	var spot = game.far_beach(global_position)
	if spot == null:
		return
	game.spawn_dust(center(), Color(0.6, 0.8, 1.0), 16)
	global_position = spot
	velocity = Vector3.ZERO
	_fall_start = global_position.y
	game.spawn_dust(center(), Color(0.6, 0.8, 1.0), 16)
	Audio.play("Item_6", 0.7)


## Glacier Fang: holding the button charges an icicle (Terraria's channel
## weapon); it flies on letting go or when full.
func _start_charge(def: Dictionary) -> bool:
	if not charging.is_empty():
		return false
	var cost := mana_cost(def)
	if mana < cost:
		return false
	mana -= cost
	stats_changed.emit()
	charging = {"def": def, "t": 0.0, "paid": 0}
	Audio.play(def.charge.get("sound", "Item_210"), 0.6)
	return true


func _update_charge(delta: float) -> void:
	if charging.is_empty():
		return
	var def: Dictionary = charging.def
	var c: Dictionary = def.charge
	if held().get("internal", "") != def.get("internal", ""):
		charging = {}
		return
	# More mana a third and two thirds of the way; without it, charging
	# slows to 40%.
	var at: Array = c.get("mana_at", [])
	var speed := 1.0
	if int(charging.paid) < at.size() and float(charging.t) >= float(at[charging.paid]):
		var cost := mana_cost(def)
		if mana >= cost:
			mana -= cost
			charging.paid += 1
			stats_changed.emit()
			Audio.play(c.get("sound", "Item_210"), 0.6)
		else:
			speed = 0.4
	charging.t = minf(float(c.get("seconds", 1.0)), float(charging.t) + delta * speed)
	if not use_down() or float(charging.t) >= float(c.get("seconds", 1.0)):
		release_charge()


## Lets the charged icicle fly: from 150% to 400% damage, faster, bigger and
## piercing more the longer it charged (Terraria's GlacierFangShot).
func release_charge() -> void:
	var def: Dictionary = charging.def
	var c: Dictionary = def.charge
	var full := float(c.get("seconds", 1.0))
	var k := clampf(float(charging.t) / full, 0.0, 1.0)
	charging = {}
	var ramp := float(c.get("ramp_from", 0.0)) / full
	var dmg_mult := 1.0 if k < ramp else lerpf(c.damage[0], c.damage[1], inverse_lerp(ramp, 1.0, k))
	var speed := lerpf(c.speed[0], c.speed[1], k) * (float(c.get("full_speed", 1.0)) if k >= 1.0 else 1.0)
	var pierce := 0
	for p in c.get("pierce", []):
		if k >= float(p[0]) / full:
			pierce = int(p[1])
	var size := lerpf(c.size[0], c.size[1], k)
	var b := Game.current.spawn_projectile(def.projectile, camera.global_position + forward() * 0.6, forward() * speed,
			weapon_damage(def, int(round(float(def.damage) * dmg_mult))), float(def.knockback) * maxf(1.0, dmg_mult), float(c.get("gravity", 0.0)), 0.0,
			size, true, crit_chance(def))
	b.penetrate = 1 + pierce
	b.pierce_falloff = float(c.get("pierce_falloff", 0.0))
	b.radius = maxf(0.3, size * 0.5)
	b.frame = 0 if k < 0.34 else (1 if k < 0.67 else 2)
	_use_timer = float(def.get("use_time", 24)) / 60.0
	viewmodel.play(Viewmodel.use_style(def), _use_timer)
	Audio.play(c.get("release_sound", "Item_201"), 0.7)


func _fly(delta: float, game, dir: Vector3) -> void:
	var speed := FLY_SPEED
	var vertical := float(input_enabled and Input.is_action_pressed("jump")) - float(input_enabled and Input.is_key_pressed(KEY_SHIFT))
	velocity = velocity.lerp(dir * speed + Vector3(0, vertical * speed, 0), minf(1.0, 10.0 * delta))
	# Flying passes through platforms both ways.
	var r: Dictionary = game.world.move_aabb(global_position, half, velocity * delta, 0.0, true)
	global_position = r.position
	on_floor = false
	_fall_start = global_position.y
	# Creative flight ends on touching the ground, as in Minecraft.
	if creative and r.on_floor and vertical <= 0.0:
		flying = false
		on_floor = true
		velocity.y = 0.0


func toggle_creative_flight() -> void:
	flying = not flying
	velocity.y = 0.0
	_jump_held = true  # the tap doesn't also jump

## Which liquid the body and eyes are in. The eye counts as submerged only
## below the cell's surface height.
func _update_liquid(game) -> void:
	var w: VoxelWorld = game.world
	var feet: Vector2i = w.get_liquid(Vector3i((global_position + Vector3(0, 0.25, 0)).floor()))
	var body: Vector2i = w.get_liquid(Vector3i((global_position + Vector3(0, 0.9, 0)).floor()))
	var eye := camera.global_position
	var e: Vector2i = w.get_liquid(Vector3i(eye.floor()))
	var above: Vector2i = w.get_liquid(Vector3i(eye.floor()) + Vector3i.UP)
	var surface := 1.0 if above.y > 0 else e.y / 63.0 * 0.94
	var was := in_liquid
	in_liquid = LIQ_LAVA if (feet.x == LIQ_LAVA or body.x == LIQ_LAVA) else maxi(feet.x, body.x)
	head_liquid = e.x if e.y > 0 and fposmod(eye.y, 1.0) < surface else 0
	if in_liquid != was:
		Audio.play("Splash_*", 0.5)
		if in_liquid != 0 and velocity.y < -6.0:
			game.spawn_dust(global_position, Color(0.5, 0.65, 1.0) if in_liquid == LIQ_WATER else Color(1.0, 0.5, 0.1), 14)


## No damage of any kind: the test world's god mode, or creative mode.
func invulnerable() -> bool:
	return god_mode or creative


func _liquid_effects(delta: float) -> void:
	if invulnerable():
		breath = BREATH_MAX
		on_fire = 0.0
		mana = mana_max
		return
	if head_liquid != 0:
		breath = maxf(0.0, breath - delta)
	else:
		breath = minf(BREATH_MAX, breath + delta * 6.0)
	var dot := 0.0
	if breath <= 0.0:
		dot += DROWN_DPS
	var fire_immune := has_effect("fire_immune")
	if in_liquid == LIQ_LAVA:
		hurt(LAVA_DAMAGE, Vector3.ZERO)
		# The Molten set: "Cannot be set on fire".
		if not fire_immune:
			on_fire = ON_FIRE_TIME
	elif not fire_immune and _touching_hot():
		# Hellstone, like Terraria's fire blocks, sets you on fire.
		on_fire = ON_FIRE_TIME
	# Spikes (Terraria's TouchDamageImmediate): hurt at once, give or take 15%.
	var spikes := _touch_damage()
	if spikes > 0:
		hurt(int(round(spikes * randf_range(0.85, 1.15))), Vector3.ZERO)
	elif in_liquid == LIQ_WATER:
		on_fire = 0.0
	if on_fire > 0.0:
		on_fire = maxf(0.0, on_fire - delta)
		dot += ON_FIRE_DPS
	suffocating = buried()
	if suffocating:
		dot += SUFFOCATION_DPS
	if dot > 0.0:
		_dot_acc += dot * delta
		if _dot_acc >= 1.0:
			var n := int(_dot_acc)
			_dot_acc -= n
			_damage_over_time(n)
	else:
		_dot_acc = 0.0


## Inside a block of sand, silt or slush (one that falls): Terraria's hitbox
## shrunk by 2 px a side touching one of its Suffocate tiles.
func buried() -> bool:
	var w := Game.current.world
	var m := 2.0 / 24.0  # 2 px; a block is 24 px
	var lo := (global_position - Vector3(half.x - m, -m, half.z - m)).floor()
	var hi := (global_position + Vector3(half.x - m, half.y - m, half.z - m)).floor()
	for x in range(int(lo.x), int(hi.x) + 1):
		for y in range(int(lo.y), int(hi.y) + 1):
			for z in range(int(lo.z), int(hi.z) + 1):
				if Data.block(w.get_block(Vector3i(x, y, z))).get("falls", false):
					return true
	return false


## Touching a "hot" block (Hellstone), standing on one included.
func _touching_hot() -> bool:
	if touching("hot"):
		return true
	var w := Game.current.world
	for dx in [-half.x, half.x]:
		for dz in [-half.z, half.z]:
			if Data.block(w.get_block(Vector3i((global_position + Vector3(dx, -0.05, dz)).floor()))).get("hot", false):
				return true
	return false


## The touch damage of a block you're in or standing on (Spikes), 0 for none.
func _touch_damage() -> int:
	var w := Game.current.world
	var lo := (global_position - Vector3(half.x, 0.05, half.z)).floor()
	var hi := (global_position + Vector3(half.x, half.y, half.z) - Vector3.ONE * 0.001).floor()
	var most := 0
	for x in range(int(lo.x), int(hi.x) + 1):
		for y in range(int(lo.y), int(hi.y) + 1):
			for z in range(int(lo.z), int(hi.z) + 1):
				most = maxi(most, int(Data.block(w.get_block(Vector3i(x, y, z))).get("touch_damage", 0)))
	return most


## Damage from drowning or burning: ignores immunity frames and knockback.
func _damage_over_time(n: int) -> void:
	if not alive or invulnerable():
		return
	life -= n
	_since_hurt = 0.0
	Game.current.floating_text(str(n), center() + Vector3(0, 1.2, 0) + forward() * 0.8, Color(1.0, 0.4, 0.2))
	stats_changed.emit()
	if life <= 0:
		_die()


## Active buff icons for the HUD: [Terraria buff id, name, seconds left].
func buffs() -> Array:
	var out := []
	if on_fire > 0.0:
		out.append([24, "On Fire!", on_fire])
	if potion_sickness > 0.0:
		out.append([21, "Potion Sickness", potion_sickness])
	if sharpened:
		out.append([159, "Sharpened", INF])
	if bast_near:
		out.append([215, "The Bast Defense", INF])
	if suffocating:
		out.append([68, "Suffocation", INF])
	return out


func _regen(delta: float) -> void:
	_since_hurt += delta
	# Terraria's natural regen ramps up the longer you avoid damage.
	var rate := (0.5 if _since_hurt > 8.0 else 0.0) + (1.0 if _since_hurt > 20.0 else 0.0)
	if has_effect("regen"):
		rate += 1.0
	if life < life_max and rate > 0.0:
		_regen_acc += rate * delta
		if _regen_acc >= 1.0:
			life = mini(life_max, life + int(_regen_acc))
			_regen_acc = fmod(_regen_acc, 1.0)
			stats_changed.emit()
	if mana < mana_cap() and _use_timer <= 0.0:
		_mana_acc += delta * (4.0 + mana_cap() * 0.05)
		if _mana_acc >= 1.0:
			mana = mini(mana_cap(), mana + int(_mana_acc))
			_mana_acc = fmod(_mana_acc, 1.0)
			stats_changed.emit()


# ------------------------------------------------------------------ items

func use_item() -> void:
	if _use_timer > 0.0 or slash_out():
		return
	# Like Terraria: without autoReuse (or the Autofire setting) holding the
	# button doesn't use it again; it takes a fresh click.
	if not _use_released and not auto_reuses(held()):
		return
	var slot = inventory.slots[selected]
	var def := held()
	var used := false
	if slot == null:
		used = _mine({})  # hands can still break plants and torches
		if used:
			_use_timer = 0.3
			viewmodel.play("punch", 0.3)
		return
	var duration := float(def.get("use_time", 20)) / 60.0
	# Melee speed (Molten Greaves) swings faster; mining speed (Mining
	# armor) digs faster.
	if def.get("type") == "melee":
		duration /= 1.0 + stat("melee_speed") / 100.0
	elif def.has("pick"):
		duration /= 1.0 + stat("mining_speed") / 100.0
	match def.get("type", ""):
		"tool":
			if def.has("hammer"):
				_hammer(def)
			else:
				_mine(def)
			_melee(def)
			used = true
		"melee":
			if def.has("yoyo"):
				used = _throw_yoyo(def)
			elif def.has("flail"):
				used = _spin_flail(def)
			elif def.has("slash"):
				used = _start_slash(def)
			elif def.has("spear"):
				used = _thrust_spear(def, duration)
			elif def.has("boomerang"):
				used = _throw_boomerang(def)
			else:
				_melee(def)
				if def.get("regrow", false):
					_regrow()
				used = true
		"ranged":
			used = _shoot_ranged(def)
		"magic":
			if def.has("charge"):
				used = _start_charge(def)
			else:
				used = _cast(def)
		"thrown":
			used = _throw(def)
		"block":
			if def.get("extractinator", false) and _aiming_at_extractinator():
				used = _extract()
				duration = EXTRACT_TIME
			else:
				used = _place(def)
				duration = 0.2
		"consumable":
			used = _consume(def)
		"summon":
			used = _summon(def)
		"bucket":
			used = _use_bucket(def)
		"ammo":
			# Snowballs: ammo you can throw too.
			if def.get("thrown_too", false):
				used = _throw(def)
		"tool_use":
			if def.has("rope_snake"):
				used = _summon_rope_snake(def)
			elif def.has("rope_coil"):
				used = _throw_rope_coil(def)
			elif def.has("ocean_teleport"):
				_conch_timer = float(def.ocean_teleport)
				Audio.play(def.get("sound", "Item_6"), 0.7)
				used = true
		"hook":
			used = fire_hook(def)
		_:
			duration = 0.25
	if used:
		_use_timer = duration
		# Placing blocks and using generic items swing the arm, as in Minecraft.
		viewmodel.play(Viewmodel.use_style(def), duration)
		if def.get("type") in ["tool", "melee"]:
			Audio.play("Item_1", 0.7)


## Applies one tool hit to the targeted block. Returns true if a block was hit.
func _mine(def: Dictionary) -> bool:
	if target.is_empty():
		return false
	var game := Game.current
	var pos: Vector3i = target.block
	var bdef := Data.block(target.id)
	if creative:
		# Any block, at once, and nothing drops.
		game.break_block(pos, false)
		_mine_damage = 0.0
		return true
	var tool: String = bdef.get("tool", "pickaxe")
	# A block that takes an axe and a pickaxe (cactus) goes with what you hold.
	if bdef.get("pickable", false) and def.has("pick"):
		tool = "pickaxe"
	var power := 0.0
	if bdef.has("unbreakable"):
		Audio.play("Tink_*", 0.6)
		game.message(bdef.unbreakable, Color(0.9, 0.7, 0.7))
		return true
	if tool == "any":
		power = 100.0
	elif tool == "pickaxe" and def.has("pick"):
		if def.pick < bdef.get("min_pick", 0):
			Audio.play("Tink_*", 0.6)
			game.message("This block is too hard for your pickaxe", Color(0.9, 0.7, 0.7))
			return true
		power = float(def.pick) * float(bdef.get("hardness", 1.0))
		# Grass: the first hit knocks it back to dirt (Terraria's extra hit).
		if bdef.has("hit_to"):
			game.world.set_block(pos, Data.block_id(bdef.hit_to))
			game.block_hit_effects(pos, target.id)
			_mine_pos = pos
			_mine_damage = 0.0
			return true
	elif tool == "axe" and def.has("axe"):
		# Terraria's chop: axe power x 0.24 a hit (Copper Axe: 8), 100 per tree tile.
		power = floorf(float(def.axe) * 0.24) * float(bdef.get("axe_mult", 1.0))
	elif tool == "hammer" and def.has("hammer"):
		power = float(def.hammer) * 1.5
	if power <= 0.0:
		return false
	if pos != _mine_pos:
		_mine_pos = pos
		_mine_damage = 0.0
	_mine_damage += power
	if _mine_damage >= 100.0:
		game.break_block(pos)
		_mine_damage = 0.0
	else:
		game.block_hit_effects(pos, target.id)
	return true


## The hammer, like Terraria's. Hammering the face of a block that has water
## or lava behind it opens a spring there (side faces, or the underside for a
## drip from the ceiling); the same face again closes it. Any other block it
## reshapes (Game.hammer_shape).
func _hammer(def := {}) -> void:
	if target.is_empty():
		return
	# Shadow Orbs and Crimson Hearts are smashed with hammers.
	if Data.block(target.id).get("tool") == "hammer":
		_mine(def)
		return
	var game := Game.current
	var block: Vector3i = target.block
	var normal: Vector3i = target.normal
	if Data.block(target.id).get("platform", false):
		# Platforms hammer into stairs (Terraria's platform stairs).
		game.hammer_shape(block, facing_dir())
		return
	if not game.world.is_solid(block):
		return
	var mouth := block + normal
	if game.waterfalls.has_fall(mouth, Waterfalls.dir_index(normal)):
		game.waterfalls.remove_fall(mouth)
		Audio.play_at("Tink_*", Vector3(block) + Vector3(0.5, 0.5, 0.5))
		return
	# Water or lava behind the block: a spring (when there's room for one).
	if game.waterfalls.liquid_behind(block, mouth) != 0 and Waterfalls.dir_index(normal) >= 0 \
			and not game.world.is_solid(mouth) and game.world.get_liquid(mouth).y == 0:
		var result := game.waterfalls.try_make_spring(block, normal)
		if result != "":
			game.message(result, Color(0.8, 0.8, 0.9))
			Audio.play_at("Tink_*", Vector3(block) + Vector3(0.5, 0.5, 0.5), 0.5)
			return
		Audio.play_at("Tink_*", Vector3(block) + Vector3(0.5, 0.5, 0.5))
		Audio.play_at("Splash_*", Vector3(mouth) + Vector3(0.5, 0.5, 0.5), 0.5)
		return
	# Otherwise the hammer reshapes the block, like Terraria's: half block,
	# then a ramp rising away from you, then the ramp upside down, then whole.
	game.hammer_shape(block, facing_dir())


## The town NPC under the crosshair within talking reach (nearer than the
## block you aim at), or null.
func talk_target():
	var origin := camera.global_position
	var fwd := forward()
	var best = null
	var best_d := minf(5.0, float(target.get("distance", 5.0)) + 0.5)
	for npc in Game.current.npcs():
		if not npc.def.has("talk"):
			continue
		var c: Vector3 = npc.center()
		var along := (c - origin).dot(fwd)
		if along <= 0.0 or along > best_d:
			continue
		var off := origin + fwd * along - c
		if absf(off.y) < npc.half.y * 0.6 and Vector2(off.x, off.z).length() < npc.half.x + 0.3:
			best = npc
			best_d = along
	return best


## Which of Player.WALL_NORMALS you are facing most (horizontally).
func facing_dir() -> int:
	var f := forward()
	if absf(f.x) > absf(f.z):
		return 1 if f.x > 0.0 else 3
	return 0 if f.z > 0.0 else 2


## The Staff of Regrowth: the dirt you swing at turns to grass (mud to
## jungle grass), like Terraria's.
func _regrow() -> void:
	if target.is_empty():
		return
	var world := Game.current.world
	var name: String = Data.block(target.id).get("name", "")
	var grows := {"dirt": "grass", "mud": "jungle_grass"}
	if grows.has(name):
		world.set_block(target.block, Data.block_id(grows[name]))
		Audio.play("Grass", 0.6)


## Flower Boots: walking over grass, flowers come up behind you.
func _flower_boots(game) -> void:
	if not on_floor or not has_effect("flower_boots") or Vector2(velocity.x, velocity.z).length() < 0.5:
		return
	var feet := Vector3i(global_position.floor())
	if feet == _last_flower_cell:
		return
	_last_flower_cell = feet
	var grass := Data.block_id("grass")
	if game.world.get_block(feet + Vector3i.DOWN) == grass and game.world.get_block(feet) == 0 and randf() < 0.5:
		game.world.set_block(feet, Data.random_style("flowers" if randf() < 0.8 else "tall_flowers"))


var _last_flower_cell := Vector3i(-1, -1, -1)


func _melee(def: Dictionary) -> void:
	var game := Game.current
	var thrust: bool = def.get("style", "swing") == "thrust"
	var reach := 2.4 if thrust else 2.9
	var cone := cos(deg_to_rad(38.0 if thrust else 65.0))
	var origin := camera.global_position
	var fwd := forward()
	for npc in game.npcs():
		# Aim at the point of the enemy's body nearest the view ray, so short or
		# low enemies are hit when the crosshair is on them.
		var c: Vector3 = npc.center()
		var ray_point := origin + fwd * maxf((c - origin).dot(fwd), 0.0)
		var bottom: float = npc.global_position.y
		var aim := Vector3(c.x, clampf(ray_point.y, bottom, bottom + npc.half.y), c.z)
		var to := aim - origin
		var dist: float = to.length() - npc.half.x
		if dist < reach and to.normalized().dot(fwd) > cone:
			npc.hit(weapon_damage(def), float(def.get("knockback", 0)), to.normalized(), crit_chance(def), armor_penetration(def))
	# Ice Blade: a bolt with the swing, every so often (Terraria's useTime
	# longer than its useAnimation).
	if def.has("swing_shot") and _swing_shot_cd <= 0.0:
		var shot: Dictionary = def.swing_shot
		_swing_shot_cd = float(shot.get("every", 60)) / 60.0
		var b := game.spawn_projectile(shot.projectile, origin + fwd * 0.6, fwd * float(shot.get("speed", 20)),
				weapon_damage(def), float(def.get("knockback", 0)), 0.0, 0.0, 0.45, true, crit_chance(def))
		b.armor_pen = armor_penetration(def)
		if shot.has("light"):
			b.glow = Color(shot.light[0], shot.light[1], shot.light[2])
	# Grass, vines, cobwebs, pots... in the swing are cut (anything swung that
	# does damage, tools too, as in Terraria).
	if int(def.get("damage", 0)) > 0:
		game.cut_tiles_in_cone(origin, fwd, reach, cone)
	if def.get("star", false):
		_call_star(def)


func _shoot_ranged(def: Dictionary) -> bool:
	var ammo_slot := inventory.find_ammo(def.ammo)
	if ammo_slot < 0:
		return false
	var ammo := Data.item(inventory.slots[ammo_slot].item)
	# Some armor has a chance to save ammo.
	if randf() * 100.0 >= stat("ammo_save"):
		_use_up(ammo_slot)
	var is_arrow: bool = def.ammo == "WoodenArrow"
	var drop := float(ammo.get("gravity", 6.0 if is_arrow else 0.0))
	# A shotgun (the Boomstick) fires several, spread out, for one round.
	var pellets: Array = def.get("pellets", [1, 1])
	var spread := float(def.get("spread", 0.0))
	var basis := camera.global_transform.basis
	for i in randi_range(int(pellets[0]), int(pellets[1])):
		var dir := forward()
		if spread > 0.0:
			dir = (dir + basis.x * randf_range(-spread, spread) + basis.y * randf_range(-spread, spread)).normalized()
		var pr := Game.current.spawn_projectile(ammo.projectile, camera.global_position + forward() * 0.5 + basis.y * -0.1,
				dir * float(def.shoot_speed), weapon_damage(def, int(def.damage) + int(ammo.get("damage", 0))),
				float(def.knockback) + float(ammo.get("knockback", 0)), drop, 0.0, 0.7 if is_arrow else 0.25,
				true, crit_chance(def))
		pr.gravity_delay = float(ammo.get("gravity_delay", 0.0))
		pr.drag = float(ammo.get("drag", 0.0))
	Audio.play(def.get("sound", "Item_5"), 0.7)
	return true


func _cast(def: Dictionary) -> bool:
	# A channelled spell (the Magic Missile): one at a time, steered while
	# the button is held.
	if def.get("channel", false) and channelled != null and is_instance_valid(channelled):
		return false
	# A use that shoots more than once (Terraria's useAnimation over
	# useTime: the Aqua Scepter's two streams) costs its mana once.
	var cost := mana_cost(def)
	if _free_shots > 0 and _free_shots_item == def.internal:
		_free_shots -= 1
		cost = 0
	elif def.has("use_animation"):
		_free_shots = int(def.use_animation) / int(def.get("use_time", 20)) - 1
		_free_shots_item = def.internal
	if mana < cost:
		return false
	mana -= cost
	stats_changed.emit()
	var pr := Game.current.spawn_projectile(def.projectile, camera.global_position + forward() * 0.6, forward() * float(def.shoot_speed),
			weapon_damage(def), float(def.knockback), 0.0, 0.0, 0.5, true, crit_chance(def))
	if def.get("channel", false):
		channelled = pr
		pr.steered_by = self
	Audio.play(def.get("sound", "Item_8"), 0.7)
	return true


## Whether holding the use button keeps using this item (Terraria's
## autoReuse, or every item with the Autofire setting on).
func auto_reuses(def: Dictionary) -> bool:
	# Feral Claws: autoswing for melee weapons.
	if def.get("type") == "melee" and has_effect("autoswing"):
		return true
	return def.get("auto_reuse", true) or bool(Settings.get_value("autofire"))


## The use button is held (or hold_use, for tests).
func use_down() -> bool:
	return hold_use or (input_enabled and Input.is_action_pressed("use_item") and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)


## Throws a yoyo, one out at a time (holding the button as it comes back
## doesn't throw it again: use_item wants a fresh click).
func _throw_yoyo(def: Dictionary) -> bool:
	if yoyo_out():
		return false
	yoyo = Yoyo.new()
	yoyo.setup(self, def)
	Game.current.entities.add_child(yoyo)
	yoyo.global_position = yoyo.hand()
	yoyo.velocity = forward() * yoyo.top_speed()
	Audio.play("Item_1", 0.6)
	return true


## Starts spinning a flail (Flail): one out at a time; it's thrown when you
## let go of the button.
func _spin_flail(def: Dictionary) -> bool:
	if flail_out():
		return false
	flail = Flail.new()
	flail.setup(self, def)
	Game.current.entities.add_child(flail)
	flail.global_position = center() + Vector3(0, Flail.SPIN_HEIGHT, 0)
	return true


func flail_out() -> bool:
	return flail != null and is_instance_valid(flail) and not flail.is_queued_for_deletion()


## Starts slashing (Slash: the Terragrim); it goes on while you hold the button.
func _start_slash(def: Dictionary) -> bool:
	if slash_out():
		return false
	slash = Slash.new()
	slash.setup(self, def)
	Game.current.entities.add_child(slash)
	return true


func slash_out() -> bool:
	return slash != null and is_instance_valid(slash) and not slash.is_queued_for_deletion()


## Throws a boomerang: one at a time, like Terraria's (the Trimarang three),
## until it's back.
func _throw_boomerang(def: Dictionary) -> bool:
	if boomerangs_out(def) >= int(def.boomerang.get("max", 1)):
		return false
	var b := Boomerang.new()
	b.setup(self, def)
	Game.current.entities.add_child(b)
	b.throw(camera.global_transform * Viewmodel.hand_position(), forward())
	boomerangs.append(b)
	return true


## How many of this item's boomerangs are out.
func boomerangs_out(def: Dictionary) -> int:
	boomerangs = boomerangs.filter(func(b): return is_instance_valid(b) and not b.is_queued_for_deletion())
	return boomerangs.filter(func(b): return b.def.get("internal", "") == def.get("internal", "")).size()


## Thrusts the spear for the whole use (`seconds`).
func _thrust_spear(_def: Dictionary, seconds: float) -> bool:
	_update_spear()
	if not spear_out():
		return false
	spear.thrust(seconds)
	return true


## Holding a spear puts it out in the world (resting in your hand); putting
## it away (or dying) takes it back.
func _update_spear() -> void:
	var def := held()
	var want := alive and def.has("spear")
	if spear_out() and (not want or spear.def.get("internal", "") != def.get("internal", "")):
		spear.queue_free()
		spear = null
	if want and not spear_out():
		spear = Spear.new()
		spear.setup(self, def)
		Game.current.entities.add_child(spear)


## A spear is out (you're holding one).
func spear_out() -> bool:
	return spear != null and is_instance_valid(spear) and not spear.is_queued_for_deletion()


func spear_thrusting() -> bool:
	return spear_out() and spear.using


func yoyo_out() -> bool:
	return yoyo != null and is_instance_valid(yoyo) and not yoyo.is_queued_for_deletion()


## A spell's mana cost after your reductions (Jungle set: 16%).
func mana_cost(def: Dictionary) -> int:
	return int(round(float(def.get("mana", 0)) * maxf(0.0, 1.0 - stat("mana_cost") / 100.0)))


func _throw(def: Dictionary) -> bool:
	var pr := Game.current.spawn_projectile(def.projectile, camera.global_position + forward() * 0.5, forward() * float(def.shoot_speed),
			weapon_damage(def), float(def.knockback), float(def.get("gravity", 10.0)), 18.0, 0.45, true, crit_chance(def))
	pr.gravity_delay = float(def.get("gravity_delay", 0.0))
	pr.drag = float(def.get("drag", 0.0))
	if def.has("explosive"):
		# A lit bomb: lobbed a little upward, heavier, with its fuse burning.
		pr.explosive = def.explosive
		pr.life = float(def.explosive.get("fuse", 3.0))
		pr.gravity = 20.0
		pr.velocity += Vector3(0, 3.0, 0) + velocity * 0.5
	_use_up(selected)
	Audio.play("Item_1", 0.6)
	return true


func _place(def: Dictionary) -> bool:
	if target.is_empty():
		return false
	var game := Game.current
	var id := Data.block_id(def.place)
	var bdef := Data.block(id)
	var pos: Vector3i = target.block
	var normal: Vector3i = target.normal
	# Grass seeds ("plant_on"): the block they're used on turns to their grass.
	if def.has("plant_on"):
		if Data.block(target.id).get("name", "") != def.plant_on:
			return false
		game.world.set_block(pos, id)
		_use_up(selected)
		Audio.play("Dig_*", 0.6)
		return true
	if bdef.get("rope", false):
		return _place_rope(id, pos, normal)
	if Doors.is_door(bdef):
		if Data.block(target.id).get("render", "cube") != "cross":
			pos += normal
		if not Doors.place_from_player(game, self, pos, id):
			return false
		_use_up(selected)
		Audio.play("Dig_*", 0.6)
		return true
	# Plants and other non-solid clutter get replaced; otherwise build on the hit face.
	if Data.block(target.id).get("render", "cube") != "cross" or Data.block(target.id).get("drop") == "Torch":
		pos += normal
	# On the side of a solid block, a torch becomes a wall torch (like
	# Minecraft's) and wall blocks (banners) hang there; banners only go on walls.
	var wall_dir := -1
	var on_wall: bool = normal.y == 0 and game.world.is_solid(target.block)
	if on_wall and bdef.has("wall_variant"):
		id = Data.block_id(bdef.wall_variant)
		bdef = Data.block(id)
	if bdef.get("wall", false):
		if not on_wall:
			return false
		wall_dir = WALL_NORMALS.find(normal)
	if game.world.get_block(pos) != 0 and Data.kind_of(game.world.get_block(pos)) != "tall_grass":
		return false
	if bdef.get("solid", true):
		var box_min := Vector3(pos)
		if _box_overlap(global_position, half, box_min) or game.any_npc_in_block(pos):
			return false
	elif wall_dir < 0 and not _has_support(pos, bdef.get("hangs", false), bdef.get("platform", false)):
		return false
	if not game.world.set_block(pos, id):
		return false
	if wall_dir >= 0:
		# Faces out of the wall (the hit face's normal).
		game.block_rotations[Chests.key(pos)] = wall_dir
	else:
		# Directional models face the player. A model's front is +z; turning it by
		# the player's yaw points it back along their view, toward them.
		game.block_rotations[Chests.key(pos)] = posmod(roundi(_yaw / (PI * 0.5)), 4)
	_use_up(selected)
	Audio.play("Dig_*", 0.6)
	if bdef.get("interact") == "chest":  # chests, barrels
		game.chests.register_new(pos)
	# Sand placed over a gap falls.
	game.settle_falling(pos)
	return true


## Ropes (Player.PlaceThing_Tiles): placed on a rope, it goes on under the
## bottom of it, however far down that is; anywhere else, beside anything
## (or in place of a plant).
func _place_rope(id: int, pos: Vector3i, normal: Vector3i) -> bool:
	var game := Game.current
	var w: VoxelWorld = game.world
	var at := Vector3i(-1, -1, -1)
	if Ropes.is_rope(w, pos):
		at = Ropes.extend_at(w, pos)
	else:
		var p := pos if Data.block(target.id).get("cut", false) else pos + normal
		if Ropes.is_free(w, p) and Ropes.can_hang(w, p):
			at = p
	if at.y < 0 or not Ropes.put(game, at, id):
		return false
	_use_up(selected)
	Audio.play("Dig_*", 0.6)
	return true


## Silt and slush go through an Extractinator one block per use: the block's
## useTime, 10 ticks (Terraria's Player.PlaceThing_ItemInExtractinator).
const EXTRACT_TIME := 10.0 / 60.0
var _extract_rng := RandomNumberGenerator.new()


func _aiming_at_extractinator() -> bool:
	return not target.is_empty() and Data.block(int(target.get("id", 0))).get("interact") == "extractinator"


## Feeds the held block into the Extractinator you aim at: it's used up, and
## what the Extractinator sifts out drops where you aim (Terraria drops it at
## the mouse), just in front of the machine.
func _extract() -> bool:
	var game := Game.current
	_use_up(selected)
	Audio.play("Grab")
	var drop := Extractinator.roll(_extract_rng)
	var at := camera.global_position + forward() * maxf(0.5, float(target.get("distance", 2.0)) - 0.4)
	game.spawn_item(drop[0], drop[1], at, Vector3(0, 1.5, 0))
	return true


## Where a model's front (+z) points after 0-3 quarter turns (BlockModels):
## a wall torch with rotation r leans out along WALL_NORMALS[r].
const WALL_NORMALS := [Vector3i(0, 0, 1), Vector3i(1, 0, 0), Vector3i(0, 0, -1), Vector3i(-1, 0, 0)]


## Starfury: a star falls from the sky onto the point you aim at.
func _call_star(def: Dictionary) -> void:
	var game := Game.current
	var hit := game.world.raycast(camera.global_position, forward(), 30.0)
	var target := camera.global_position + forward() * float(hit.get("distance", 18.0))
	var start := target + Vector3(randf_range(-4.0, 4.0), 22.0, randf_range(-4.0, 4.0))
	game.spawn_projectile("Starfury", start, (target - start).normalized() * 36.0, weapon_damage(def),
			float(def.get("knockback", 0)), 0.0, 12.0, 0.7, true, crit_chance(def))
	Audio.play_at("Item_9", start, 0.7)


func _box_overlap(pos: Vector3, h: Vector3, block_min: Vector3) -> bool:
	return pos.x + h.x > block_min.x and pos.x - h.x < block_min.x + 1.0 \
			and pos.z + h.z > block_min.z and pos.z - h.z < block_min.z + 1.0 \
			and pos.y + h.y > block_min.y and pos.y < block_min.y + 1.0


## Something to rest on: a solid block below or beside (`hangs`: above), or a
## platform below. A platform can also go off the side of another platform,
## like Terraria's, so a row of them can bridge a gap.
func _has_support(pos: Vector3i, hangs := false, platform := false) -> bool:
	var w := Game.current.world
	if hangs:
		return w.is_solid(pos + Vector3i.UP)
	if Data.block(w.get_block(pos + Vector3i.DOWN)).get("platform", false):
		return true
	for d in [Vector3i.DOWN, Vector3i.LEFT, Vector3i.RIGHT, Vector3i.FORWARD, Vector3i.BACK]:
		if w.is_solid(pos + d):
			return true
		if platform and d != Vector3i.DOWN and Data.block(w.get_block(pos + d)).get("platform", false):
			return true
	return false


func _consume(def: Dictionary) -> bool:
	var game := Game.current
	if def.has("heal"):
		if potion_sickness > 0.0 or life >= life_max:
			return false
		heal(int(def.heal))
		potion_sickness = POTION_SICKNESS if def.internal != "Mushroom" else 0.0
	elif def.has("mana"):
		if mana >= mana_cap():
			return false
		mana = mini(mana_cap(), mana + int(def.mana))
		game.floating_text(str(def.mana), center() + Vector3(0, 1.3, 0), Color(0.4, 0.5, 1.0))
	elif def.has("max_life"):
		if life_max >= MAX_LIFE:
			return false
		life_max += int(def.max_life)
		heal(int(def.max_life))
	elif def.has("max_mana"):
		if mana_max >= MAX_MANA:
			return false
		mana_max += int(def.max_mana)
		mana = mana_max
		Audio.play("MaxMana")
	else:
		return false
	Audio.play(def.get("sound", "Item_3"))
	_use_up(selected)
	stats_changed.emit()
	return true


func _summon(def: Dictionary) -> bool:
	var game := Game.current
	match def.get("summon_when", "night"):
		"night":
			if game.sky.is_day:
				game.message("Nothing happens... it must be used at night.", Color(0.8, 0.8, 0.8))
				return false
		"corruption":
			# Terraria: Worm Food works only in the Corruption (and does nothing elsewhere).
			if game.biome != "corruption":
				return false
	if game.boss_alive():
		return false
	game.summon_boss(def.summons)
	_use_up(selected)
	return true


## Empty buckets scoop up a cell of liquid; full ones pour it out.
func _use_bucket(def: Dictionary) -> bool:
	var game := Game.current
	var w := game.world
	var liquid := int(def.get("liquid", 0))
	if liquid == 0:
		var hit: Dictionary = w.raycast_liquid(camera.global_position, forward(), REACH)
		if hit.is_empty() or int(hit.liquid) == 0:
			return false
		var cell: Vector3i = hit.block
		var t: int = w.get_liquid(cell).x
		# Like Terraria, gather a bucketful from the surrounding cells, not just one.
		var cells: Array[Vector3i] = [cell]
		for dy in [0, 1, -1]:
			for dx in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					if dx != 0 or dy != 0 or dz != 0:
						cells.append(cell + Vector3i(dx, dy, dz))
		var total := 0
		for c in cells:
			var l: Vector2i = w.get_liquid(c)
			if l.x == t:
				total += l.y
		if total < 32:
			return false
		var need := 63
		for c in cells:
			var l: Vector2i = w.get_liquid(c)
			if need <= 0 or l.x != t or l.y == 0:
				continue
			var take := mini(need, l.y)
			w.set_liquid(c, t, l.y - take)
			need -= take
		_swap_held("WaterBucket" if t == LIQ_WATER else "LavaBucket")
	else:
		if target.is_empty():
			return false
		var cell: Vector3i = target.block
		if Data.block(target.id).get("render", "cube") != "cross":
			cell += target.normal
		if w.is_solid(cell) or (w.get_block(cell) != 0 and Data.kind_of(w.get_block(cell)) != "tall_grass"):
			return false
		var have: Vector2i = w.get_liquid(cell)
		if have.y > 0 and have.x != liquid:
			return false
		if w.get_block(cell) != 0:
			w.set_block(cell, 0)
		w.set_liquid(cell, liquid, 63)
		_swap_held("EmptyBucket")
	Audio.play("Splash_*", 0.6)
	return true


## Uses up one item from inventory slot `i` (none in creative mode).
func _use_up(i: int) -> void:
	if not creative:
		inventory.consume_slot(i)


## Turns one of the held item into `item` (buckets filling/emptying; in
## creative mode a bucket stays as it is, so it never runs dry).
func _swap_held(item: String) -> void:
	if creative:
		return
	var s = inventory.slots[selected]
	if s.count == 1:
		inventory.slots[selected] = Inventory.stack(item, 1)
		inventory.changed.emit()
	else:
		inventory.consume_slot(selected)
		if inventory.add(item, 1) > 0:
			Game.current.spawn_item(item, 1, center())


func quick_heal() -> void:
	for i in inventory.slots.size():
		var s = inventory.slots[i]
		if s != null and Data.item(s.item).has("heal") and Data.item(s.item).get("type") == "consumable":
			var prev := selected
			selected = i
			_consume(Data.item(s.item))
			selected = prev
			return


func throw_held() -> void:
	var s = inventory.slots[selected]
	if s == null:
		return
	inventory.slots[selected] = null
	inventory.changed.emit()
	Game.current.spawn_item(s.item, s.count, camera.global_position + forward(), forward() * 6.0, 1.5)


func _interact() -> void:
	var npc = talk_target()
	if npc != null:
		Game.current.hud.open_chat(npc)
		return
	if target.is_empty():
		return
	var bdef := Data.block(target.id)
	if Doors.is_part(bdef):
		Doors.toggle(Game.current, target.block, global_position)
	elif bdef.get("interact") == "chest":
		Game.current.open_chest(target.block)
	elif bdef.get("interact") == "locked_chest":
		Game.current.unlock_chest(target.block)
	elif bdef.get("interact") == "switch":
		Game.current.hit_switch(target.block)
	elif bdef.get("interact") == "bed":
		use_bed(target.block)
	elif bdef.get("interact") == "sign":
		Game.current.hud.open_sign(target.block, Game.current.sign_text(target.block))
	elif bdef.get("interact") == "buff" and bdef.get("buff") == "Sharpened":
		# The Sharpening Station: Sharpened until you die.
		sharpened = true
		Audio.play("Item_37", 0.7)
		Game.current.message("Sharpened: melee weapons pierce 12 more armor", Color(1.0, 0.95, 0.6))
	elif bdef.get("interact") == "clock":
		Game.current.message("Current time: " + Game.current.sky.clock_text(), Color(1.0, 0.95, 0.6))
	elif bdef.get("interact") == "spawner" and Game.current.test_world:
		Game.current.test_world.use_spawner(target.block, Input.is_key_pressed(KEY_SHIFT))


# ------------------------------------------------------------------ health

func heal(amount: int) -> void:
	var before := life
	life = mini(life_max, life + amount)
	if life > before:
		Game.current.floating_text(str(life - before), center() + Vector3(0, 1.3, 0), Color(0.3, 1.0, 0.3))
	stats_changed.emit()


## Terraria player damage: defense halves it, then 0.67 s of immunity.
## `attacker` (an NPC touching you) takes the Cactus set's thorns damage.
func hurt(amount: int, from: Vector3, ignore_immunity := false, attacker = null) -> void:
	if not alive or invulnerable() or (_immune > 0.0 and not ignore_immunity):
		return
	var game := Game.current
	var dmg := maxi(1, amount - defense() / 2)
	life -= dmg
	if has_effect("panic"):
		_panic = 8.0
	var thorns := int(stat("thorns"))
	if thorns > 0 and attacker != null and is_instance_valid(attacker) and attacker.life > 0:
		attacker.hit(thorns, 0.0, (attacker.center() - center()).normalized(), 0.0)
	_since_hurt = 0.0
	_immune = IMMUNE_TIME
	game.floating_text(str(dmg), center() + Vector3(0, 1.2, 0) + forward() * 0.8, Color(1.0, 0.25, 0.25))
	Audio.play("Player_Hit_*")
	game.hud.flash_damage()
	# The Cobalt Shield: no knockback.
	if from != Vector3.ZERO and not has_effect("no_knockback"):
		var away := (global_position - from)
		away.y = 0
		velocity += away.normalized() * 7.0
		velocity.y = maxf(velocity.y, 5.0)
	stats_changed.emit()
	if life <= 0:
		_die()


func _die() -> void:
	alive = false
	sharpened = false
	charging = {}
	climbing = null
	on_rope = false
	for h in hooks():
		h.queue_free()
	_jump_ticks = 0
	life = 0
	respawn_timer = 5.0
	_highlight.visible = false
	viewmodel.visible = false
	Audio.play("Player_Killed")
	# Terraria drops half of your coins where you die.
	var game := Game.current
	for coin in ["CopperCoin", "SilverCoin", "GoldCoin"]:
		var n := inventory.count_of(coin) / 2
		if n > 0:
			inventory.remove(coin, n)
			game.spawn_item(coin, n, center())
	died.emit()


## Right-clicking a bed makes it your spawn point, like Terraria's; your own
## bed again clears it.
func use_bed(pos: Vector3i) -> void:
	if bed == pos:
		bed = NO_BED
		Game.current.message("Spawn point removed!", Color(1.0, 0.95, 0.6))
	else:
		bed = pos
		Game.current.message("Spawn point set!", Color(1.0, 0.95, 0.6))


## Where you come back: your bed if it is still there, else the world's spawn.
func respawn_point() -> Vector3:
	if bed != NO_BED:
		if Data.block(Game.current.world.get_block(bed)).get("interact") == "bed":
			return Vector3(bed) + Vector3(0.5, 0.0, 0.5)
		bed = NO_BED
		Game.current.message("Your bed has been destroyed.", Color(1.0, 0.7, 0.6))
	return spawn_point


func _respawn() -> void:
	alive = true
	breath = BREATH_MAX
	on_fire = 0.0
	life = life_max
	mana = mana_max
	velocity = Vector3.ZERO
	global_position = respawn_point()
	_fall_start = global_position.y
	_immune = 2.0
	viewmodel.visible = true
	stats_changed.emit()
	respawned.emit()


# ------------------------------------------------------------------ save

func save_state() -> Dictionary:
	return {
		"inventory": inventory.to_data(),
		"accessories": accessories.to_data(),
		"armor": armor.to_data(),
		"hook": hook_slot.to_data(),
		"life": life, "life_max": life_max, "mana": mana, "mana_max": mana_max,
		"pos": [global_position.x, global_position.y, global_position.z],
		"yaw": _yaw, "pitch": _pitch, "selected": selected,
		"bed": [bed.x, bed.y, bed.z],
	}


func load_state(d: Dictionary) -> void:
	inventory.from_data(d.get("inventory", []))
	accessories.from_data(d.get("accessories", []))
	armor.from_data(d.get("armor", []))
	hook_slot.from_data(d.get("hook", []))
	life_max = int(d.get("life_max", 100))
	life = int(d.get("life", life_max))
	mana_max = int(d.get("mana_max", 20))
	mana = int(d.get("mana", mana_max))
	var p: Array = d.get("pos", [])
	if p.size() == 3:
		global_position = Vector3(p[0], p[1], p[2])
		_fall_start = p[1]
	look_at_yaw_pitch(float(d.get("yaw", 0.0)), float(d.get("pitch", 0.0)))
	selected = int(d.get("selected", 0))
	var b: Array = d.get("bed", [])
	bed = Vector3i(int(b[0]), int(b[1]), int(b[2])) if b.size() == 3 else NO_BED
	stats_changed.emit()
