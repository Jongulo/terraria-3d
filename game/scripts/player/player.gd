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
## The Flipper Potion's swim up (blocks a second).
const FLIPPER_SWIM := 6.0
const LIQUID_MAX_FALL := 12.5
const LIQUID_MOVE := 0.5
## In honey: gravity 0.1, maxFallSpeed 3, a quarter as far.
const HONEY_GRAVITY := 15.0
const HONEY_MAX_FALL := 7.5
const HONEY_MOVE := 0.25
## Touching honey makes you Honey (Terraria's buff 48) for 1800 ticks.
const HONEY_TIME := 30.0
## The Honey Comb's bees' damage, and its Honey (Terraria's 300 ticks).
const HONEY_COMB_BEE_DAMAGE := 13
const HONEY_COMB_HONEY := 5.0
## A honey block's side (Terraria's StickyMovement): 1 px a tick across and
## down at most, 5 up.
const HONEY_STICK_ACROSS := 2.5
const HONEY_STICK_FALL := 2.5
const HONEY_STICK_RISE := 12.5
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
const LIQ_HONEY := 3
## Seconds of air underwater (Terraria's 200 breath ticks at 7 ticks each ≈ 23 s).
const BREATH_MAX := 23.0
const DROWN_DPS := 20.0
## Terraria's lava (Player.Update): 80 damage and 7 s of On Fire!; the
## Obsidian Rose ("lava_rose") takes 45 and 3.5 s off.
const LAVA_DAMAGE := 80
const LAVA_ROSE_DAMAGE := 45
const ON_FIRE_TIME := 7.0
const ON_FIRE_DPS := 4.0
## Poisoned (stingers): lifeRegen -4.
const POISON_DPS := 2.0
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
## Your Piggy Bank's and Safe's 40 slots: every Piggy Bank opens the same
## one, every Safe the other, in any world (Terraria's bank, bank2).
var piggy_bank := Inventory.new(40)
var safe := Inventory.new(40)
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
## The Honey buff (seconds left): better natural healing.
var honey_time := 0.0
## Potions' buffs (BuffID name -> seconds left): Fishing, Sonar, Crate,
## and those in BUFF_EFFECTS.
var timed_buffs := {}
## Frostburn: 8 life a second (Terraria's lifeRegen -16).
const FROSTBURN_DPS := 8.0
## A slime's carried item's touch: [debuff, min, max ticks].
const CARRIED_DEBUFFS := {"StoneBlock": ["Stoned", 30, 59], "Cobweb": ["Webbed", 30, 59],
		"SnowBlock": ["Frostburn", 180, 359], "SlushBlock": ["Frostburn", 180, 359]}
## Terraria's debuffs among timed_buffs (Main.debuff: no right-clicking
## them off).
const DEBUFFS := ["Chilled", "Frozen", "Stoned", "Webbed", "Cursed", "Frostburn"]
## Your minions (Minion), oldest first, and your pet and light pet (null:
## none). Minions go when you die; pets stay with you.
var minions: Array = []
var pet: Minion = null
var light_pet: Minion = null
## The enemy you've set your minions on (right-clicking it with a summon
## staff: Terraria's MinionAttackTargetNPC), or null; marked (Extra_199)
## while you hold a summon staff.
var minion_target = null
## The whip you're cracking (Whip), if one is out.
var whip: Whip = null
var _target_marker: EntitySprite = null
## Terraria's mounts (Mount.Initialize's MountData), by name: buff, height
## (heightBoost px: you ride that much higher), run / dash speed and
## acceleration (px/tick, px/tick²: they replace yours, bonuses and all),
## jump speed and ticks (jumpSpeed, jumpHeight), auto_jump (constantJump:
## holding jump keeps hopping), fall_damage (the share of it you take) and
## extra_fall (tiles more before a fall hurts), stomp: falling onto an enemy
## hurts it (that times your summon damage, knockback 5; each enemy every 10
## ticks) and bounces you up at 10 px/tick (Terraria's slime mounts), and in
## water it can jump; sprite: Images/Mount_<sprite>, its frames (running
## every 12 ticks, frame 1 in the air; or run_frames / air_frames [first,
## last]), dust (spawnDust, getting on and off). hover: a flying mount
## (usesHover: _hover) with flight and fatigue ticks (flightTimeMax,
## fatigueMax); no_extra_jumps (blockExtraJumps); no_water: gone under water
## (the Bee).
const MOUNTS := {"slime": {"buff": "SlimeMount", "height": 20, "run": 4.0, "dash": 4.0, "accel": 0.18, "jump_speed": 8.25,
		"jump_ticks": 12, "auto_jump": true, "fall_damage": 0.5, "extra_fall": 10, "stomp": 40, "sprite": "Slime", "frames": 4},
	"bee": {"buff": "BeeMount", "height": 16, "run": 2.0, "dash": 2.0, "accel": 0.16, "jump_speed": 4.0, "jump_ticks": 10,
		"fall_damage": 0.0, "hover": [320, 320], "no_extra_jumps": true, "no_water": true, "sprite": "Bee", "frames": 12,
		"run_frames": [0, 4], "air_frames": [5, 7], "dust": 152}}
## A hovering mount's flight left and fatigue (Terraria's _flyTime, _fatigue),
## in ticks.
var _fly_time := 0.0
var _fatigue := 0.0
var _last_mount_dust := 56
## The mount you ride ("": none) and the item that called it.
var mount := ""
var mount_item := {}
var _mount_sprite: EntitySprite = null
var _mount_frame := 0.0
var _stomped := {}  # npc -> seconds before it can be stomped again
## What potions' buffs do (Player.UpdateBuffs), as effects on what you wear
## (equipment() lists them): Ironskin's 8 defense, Swiftness's 25% speed,
## Regeneration's lifeRegen 4, Wrath's 10% damage, Rage's 10% crit...
const BUFF_EFFECTS := {
	# Debuffs (DEBUFFS): Chilled, a quarter slower (strongestMoveSpeedDebuff
	# 0.75); Frozen, Stoned and Webbed, held still and helpless (CCed: no
	# moving, jumping or using anything); Cursed, no using items (noItems);
	# Frostburn, 8 life a second (lifeRegen -16).
	"Chilled": {"chilled": true},
	"Frozen": {"cc": true},
	"Stoned": {"cc": true},
	"Webbed": {"cc": true},
	"Cursed": {"cursed": true},
	"Frostburn": {"frostburn": true},
	# Jungle's Fury (the Snapthorn's tag): 12% summon weapon speed.
	"ThornWhipPlayerBuff": {"whip_speed": 12},
	"ObsidianSkin": {"lava_immune": true, "fire_walk": true, "fire_immune": true},
	"Regeneration": {"regen": 4},
	"Swiftness": {"move_speed": 25},
	"Gills": {"gills": true},
	"Ironskin": {"defense": 8},
	"ManaRegeneration": {"mana_regen_buff": true},
	"MagicPower": {"magic_damage": 20},
	"Featherfall": {"featherfall": true},
	"Spelunker": {"spelunker": true},
	"Invisibility": {"invisible": true},
	"Shine": {"shine": true},
	"NightOwl": {"night_owl": true},
	"Battle": {"battle": true},
	"Thorns": {"thorns_reflect": 1.0},
	"WaterWalking": {"water_walk": true},
	"Archery": {"archery": true},
	"Hunter": {"hunter": true},
	"Mining": {"mining_speed": 25},
	"Heartreach": {"heartreach": true},
	"Calm": {"calm": true},
	"Builder": {"block_range": 1, "place_speed": 25},
	"Titan": {"titan": true},
	"Flipper": {"flipper": true, "ignore_water": true},
	"Dangersense": {"dangersense": true},
	"AmmoReservation": {"ammo_save": 20},
	"Lifeforce": {"lifeforce": true},
	"Endurance": {"endurance": 10},
	"Rage": {"crit": 10},
	"Inferno": {"inferno": true},
	"Wrath": {"damage": 10},
	"Warmth": {"warmth": true},
	# Food (Well Fed, Plenty Satisfied, Exquisitely Stuffed): defense, crit,
	# damage, melee speed, move speed and mining speed.
	"WellFed": {"defense": 2, "crit": 2, "damage": 5, "melee_speed": 5, "move_speed": 20, "mining_speed": 5},
	"WellFed2": {"defense": 3, "crit": 3, "damage": 7.5, "melee_speed": 7.5, "move_speed": 30, "mining_speed": 10},
	"WellFed3": {"defense": 4, "crit": 4, "damage": 10, "melee_speed": 10, "move_speed": 40, "mining_speed": 15},
}
const WELL_FED := ["WellFed", "WellFed2", "WellFed3"]
## Shine's light (Lighting.AddLight 0.8, 0.95, 1) and Inferno's (0.65, 0.4, 0.1).
const SHINE_LIGHT := [0.8, 0.95, 1.0]
const INFERNO_LIGHT := [0.65, 0.4, 0.1]
## Inferno: 20 damage a second to enemies within 200 px (8.3 blocks).
const INFERNO_DAMAGE := 20
const INFERNO_RANGE := 200.0 / 24.0
var _inferno_t := 0.0
## Quests done for the Angler (Terraria's anglerQuestsFinished).
var angler_quests := 0
## What the bobber's last bite check found (Terraria's displayedFishingInfo,
## shown by the Fisherman's Pocket Guide): "12 Fishing Power", "Not Enough Water!".
var fishing_info := ""
var respawn_timer := 0.0
## Liquid around the body / at the eyes: 0 none, 1 water, 2 lava.
var in_liquid := 0
var head_liquid := 0
var breath := BREATH_MAX
var on_fire := 0.0
## Poisoned's seconds left.
var poisoned := 0.0
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
## The last creature you hit, by its banner (Terraria's lastCreatureHit: the
## Tally Counter's).
var last_creature_hit := ""
## What's being used, and how long the use lasts (for its swing's dust).
var _use_def := {}
var _use_length := 0.0
var _swing_dust_ticks := 0.0
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
## Where the teleport at the end of _conch_timer goes: "ocean" (the Magic
## Conch), "home" (the Magic Mirror) or "random" (the Teleportation Potion).
var _conch_to := "ocean"
## Holding on to a rope snake (Snake Charmer's Flute).
var climbing: Node3D = null
## Holding on to a rope or chain (_rope_climb).
var on_rope := false
## Sliding down (or stuck to) a wall: Climbing Claws / Shoe Spikes; away
## from the wall is _slide_away.
var sliding := false
## Against a honey block's side (sticking to it).
var honey_stuck := false
var _slide_away := Vector3.ZERO
## Wings: flight left (seconds), refilled on the ground.
var _wing_time := 0.0
## Rocket boots: bursts left (Terraria's rocketTime), the one firing (s), and
## whether jump has been let go in the air since you left the ground.
var _rocket_time := 0
var _rocket_burst := 0.0
var _rocket_release := false
## Lava Charm: seconds of lava immunity left (Terraria's lavaTime).
var lava_time := 0.0
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
	return global_position + Vector3(0, half.y / 2.0, 0)


func forward() -> Vector3:
	return -camera.global_transform.basis.z


func yaw() -> float:
	return _yaw


## True if the player's box is in a block with this flag set (cobwebs: "sticky").
## Whether a block with `flag` is against your side (within Terraria's pixel,
## 1/24 block, of your box; not under your feet or over your head).
func touching_side(flag: String) -> bool:
	var w := Game.current.world
	var m := 1.0 / 24.0
	var lo := (global_position - Vector3(half.x + m, -0.01, half.z + m)).floor()
	var hi := (global_position + Vector3(half.x + m, half.y - 0.01, half.z + m)).floor()
	for x in range(int(lo.x), int(hi.x) + 1):
		for y in range(int(lo.y), int(hi.y) + 1):
			for z in range(int(lo.z), int(hi.z) + 1):
				if Data.block(w.get_block(Vector3i(x, y, z))).get(flag, false):
					return true
	return false


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


## How far you reach: blocks you hold go a tile further for each Toolbelt
## (Terraria's blockRange, a tile is 2/3 of a block).
func reach() -> float:
	var def := held()
	# Wrenches and the Wire Cutter reach 20 tiles further (tileBoost).
	return REACH + (stat("block_range") * 2.0 / 3.0 if def.get("type") == "block" else 0.0) + float(def.get("tile_boost", 0)) * 2.0 / 3.0


## The point the crosshair is on (the targeted block's face), or REACH ahead.
func aim_point() -> Vector3:
	return camera.global_position + forward() * float(target.get("distance", REACH))


func overlaps_block(p: Vector3i) -> bool:
	return _box_overlap(global_position, half, Vector3(p))


func overlaps_point(p: Vector3, radius: float) -> bool:
	var pos := global_position
	return absf(p.x - pos.x) < half.x + radius and absf(p.z - pos.z) < half.z + radius \
			and p.y > pos.y - radius and p.y < pos.y + half.y + radius


## A px/tick in blocks a second (24 px a block).
const UMBRELLA_PX_TICK := 60.0 / 24.0


func held() -> Dictionary:
	return Data.item_of(inventory.slots[selected])


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
				out.append(Data.item_of(s))
				# An accessory's prefix: Warding's 4 defense and so on.
				if s.has("prefix"):
					out.append(Prefixes.bonus(int(s.prefix)))
	var bonus := armor_set()
	if not bonus.is_empty():
		out.append(bonus)
	for b in timed_buffs:
		if BUFF_EFFECTS.has(b):
			out.append(BUFF_EFFECTS[b])
	return out


## Your money: what you carry and what's in your Piggy Bank and Safe (their
## coins can be spent in shops).
func money() -> int:
	return inventory.money() + piggy_bank.money() + safe.money()


## Pays `amount` copper (Player.BuyItem): from what you carry, then the Piggy
## Bank, then the Safe, change in kind. False (paying nothing) if short.
func pay(amount: int) -> bool:
	if money() < amount:
		return false
	for inv in [inventory, piggy_bank, safe]:
		var here: int = inv.money()
		if here >= amount:
			return inv.pay(amount)
		inv.pay(here)
		amount -= here
	return amount <= 0


## Your maximum life now: Lifeforce adds a fifth (to the 20 below).
func life_cap() -> int:
	return life_max + (life_max / 5 / 20 * 20 if has_effect("lifeforce") else 0)


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


## A weapon's knockback: the Titan Potion's half again (kbBuff).
func weapon_knockback(def: Dictionary) -> float:
	return float(def.get("knockback", 0)) * (1.5 if has_effect("titan") else 1.0)


func defense() -> int:
	return int(stat("defense")) + (BAST_DEFENSE if bast_near else 0)


const BAST_DEFENSE := 5
## The Bast Statue's reach: Terraria's 170 x 125 tiles round it.
const BAST_REACH := Vector3i(57, 42, 57)
const SHARPENED_PEN := 12


## Armor penetration of a weapon's hits: the Sharpening Station's 12 for
## melee, and what you wear (the Shark Tooth Necklace's 5).
func armor_penetration(def: Dictionary) -> int:
	return (SHARPENED_PEN if sharpened and _damage_kind(def) == "melee" else 0) + int(def.get("armor_pen", 0)) \
			+ int(stat("armor_pen"))


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
	return {"melee": "melee", "tool": "melee", "ranged": "ranged", "magic": "magic", "thrown": "thrown", "summon": "summon"}.get(def.get("type", ""), "")


## The light you carry: a held torch, a Mining Helmet or a glowing accessory
## (black: none).
## Shaders add it around the camera (shaders/player_light.gdshaderinc).
func carried_light() -> Color:
	var c := Color.BLACK
	var h := held()
	# A held Demon Torch pulses like a placed one.
	var lights := [h.get("light")] if not h.has("pulse") else [_color_array(Data.pulse_color(h.pulse))]
	for s in armor.slots + accessories.slots:
		if s != null:
			var d := Data.item(s.item)
			# The Jellyfish Necklace: brighter under water.
			lights.append(d.get("light_wet") if in_liquid != 0 and d.has("light_wet") else d.get("light"))
	# Slashing, the Terragrim shines (Terraria's AddLight at its tip).
	if slash_out():
		lights.append(slash.def.slash.get("light"))
	if has_effect("shine"):
		lights.append(SHINE_LIGHT)
	if has_effect("inferno"):
		lights.append(INFERNO_LIGHT)
	# A light pet shines on you as it follows (the Shadow Orb).
	if light_pet != null and is_instance_valid(light_pet):
		var lc := light_pet.light()
		lights.append([lc.r, lc.g, lc.b])
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
	_crack_bricks(game, delta)
	_move(delta, game)
	if mount != "":
		_ride(delta, game)
	_mark_target()
	_flower_boots(game)
	_regen(delta)
	_liquid_effects(delta)
	_immune = maxf(0.0, _immune - delta)
	potion_sickness = maxf(0.0, potion_sickness - delta)
	_tick_buffs(delta)
	_inferno(delta, game)
	_use_timer = maxf(0.0, _use_timer - delta)
	if _use_timer > 0.0 and _use_def.has("swing_dust"):
		_swing_dust(delta)
	_swing_shot_cd = maxf(0.0, _swing_shot_cd - delta)
	_update_bast(delta, game)
	_update_charge(delta)
	if _conch_timer >= 0.0:
		_conch_timer -= delta
		if _conch_timer < 0.0:
			match _conch_to:
				"home": home_teleport()
				"random": random_teleport()
				_: ocean_teleport()
		elif _conch_to == "home":
			# The mirror's sparkles while you gaze into it.
			if randf() < delta * 30.0:
				game.spawn_dust(center() + Vector3(randf_range(-0.4, 0.4), randf_range(-0.8, 0.8), randf_range(-0.4, 0.4)), Color(0.75, 0.6, 1.0), 1)

	target = Doors.raycast(game, camera.global_position, forward(), reach()) if input_enabled else {}
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
	RenderingServer.global_shader_parameter_set("night_vision", 1.0 if has_effect("night_owl") else 0.0)


func _move(delta: float, game) -> void:
	var input := Vector2.ZERO
	if can_act():
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
	# A mount's own run (Terraria's maxRunSpeed, accRunSpeed and
	# runAcceleration from it, in place of yours and your bonuses).
	if mount != "":
		var mt: Dictionary = MOUNTS[mount]
		max_run = float(mt.run) * 2.5
		acc_run = float(mt.dash) * 2.5
		accel = float(mt.accel) * 150.0
		# The Bee flying: 4 px/tick faster, less as it tires (Mount.RunSpeed).
		if mt.has("hover") and not on_floor:
			max_run += 4.0 * (1.0 - _fatigue / float(mt.hover[1])) * 2.5
			acc_run = max_run
	# Chilled: a quarter slower (Terraria's strongestMoveSpeedDebuff).
	if has_effect("chilled"):
		max_run *= 0.75
		acc_run *= 0.75
		accel *= 0.75
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
	# Magiluminescence: the same, on the ground only.
	if has_effect("shadow_run") or has_effect("magiluminescence") and on_floor:
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

	var jump := can_act() and Input.is_action_pressed("jump")
	var jump_speed := BALLOON_JUMP_SPEED if has_effect("jump_boost") else JUMP_SPEED
	var jump_ticks := BALLOON_JUMP_TICKS if has_effect("jump_boost") else JUMP_TICKS
	# The Frog Leg: Terraria's jumpSpeedBoost (px a tick on top of jumpSpeed).
	jump_speed += stat("jump_speed_boost") * 2.5
	# A mount's jump instead (the slime's 8.25 px/tick for 12 ticks); holding
	# jump on the slime keeps you hopping (constantJump), and it jumps out of
	# water too.
	var mount_ground := false
	if mount != "":
		var mj: Dictionary = MOUNTS[mount]
		jump_speed = float(mj.jump_speed) * 2.5
		jump_ticks = int(mj.jump_ticks)
		if mj.get("auto_jump", false) and on_floor:
			_jump_held = false
		mount_ground = mj.has("stomp") and in_liquid != 0 and in_liquid != LIQ_LAVA
	if webbed:
		jump_speed /= 5.0
		jump_ticks /= 10
	# Like Terraria, you can't swim: in water and lava you sink, and you jump
	# only off the bottom (or with a double jump you haven't used); the jump
	# goes half as far, like all movement in liquid (JumpMovement starts a
	# jump only standing, sliding, with a jump left, or wet with Flippers).
	if jump and not _jump_held:
		if on_floor or mount_ground:
			velocity.y = jump_speed
			_jump_ticks = jump_ticks
		elif sliding:
			# A wall jump: a jump, pushed off the wall (3 px a tick), and
			# your double jumps back (Terraria's JumpMovement while sliding).
			velocity.y = jump_speed
			_jump_ticks = jump_ticks
			velocity += _slide_away * WALL_JUMP_PUSH
			_extra_jumps = extra_jumps()
			sliding = false
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
		# damped; honey more so.
		var honey := in_liquid == LIQ_HONEY
		velocity.y -= (HONEY_GRAVITY if honey else LIQUID_GRAVITY) * delta
		var max_fall := HONEY_MAX_FALL if honey else LIQUID_MAX_FALL
		if velocity.y < -max_fall:
			velocity.y = move_toward(velocity.y, -max_fall, 80.0 * delta)
		# Flippers and the Flipper Potion (accFlipper): jump swims you up.
		if jump and has_effect("flipper") and in_liquid != LIQ_LAVA:
			velocity.y = maxf(velocity.y, FLIPPER_SWIM)
		_fall_start = global_position.y
	else:
		var wing := wings()
		var hovering := mount != "" and MOUNTS[mount].has("hover")
		if hovering:
			wing = {}
		if on_floor or sliding:
			_wing_time = float(wing.get("time", 0)) / 60.0
			_rocket_time = ROCKET_TIME
			_rocket_burst = 0.0
			_rocket_release = false
		elif not jump:
			_rocket_release = true
		if hovering and not on_floor:
			_hover(delta, jump)
		elif not wing.is_empty() and jump and _wing_time > 0.0 and _jump_ticks == 0 and not on_floor:
			_wing_flight(delta, wing)
		elif _rocketing(jump, wing):
			_wing_flight(delta, {"lift_max": 1.5})
			_rocket_burst -= delta
			_rocket_effects(delta)
		elif not wing.is_empty() and jump and velocity.y < 0.0:
			# Gliding: a third of gravity, a third of the fall speed, no fall.
			velocity.y = maxf(velocity.y - GRAVITY / 3.0 * delta, -MAX_FALL / 3.0)
			_fall_start = global_position.y
		elif has_effect("featherfall") and not (input_enabled and Input.is_action_pressed("drop_down")):
			# Featherfall (slowFall): a third of gravity and of the fall speed
			# (hold Drop down to fall as usual).
			velocity.y = maxf(velocity.y - GRAVITY / 3.0 * delta, -MAX_FALL / 3.0)
		else:
			velocity.y = maxf(velocity.y - GRAVITY * delta, -MAX_FALL)
	_wall_slide(game, dir)
	# Holding the Umbrella (Terraria's hold style 2): you fall at most 2
	# px/tick, and land unhurt (hold Drop down to fall as usual).
	if held().get("umbrella", false) and velocity.y < -2.0 * UMBRELLA_PX_TICK \
			and not (input_enabled and Input.is_action_pressed("drop_down")):
		velocity.y = -2.0 * UMBRELLA_PX_TICK
	if held().get("umbrella", false):
		_fall_start = global_position.y
	if webbed:
		# Stuck in a web: you sink and climb slowly, and a fall stops there.
		velocity.y = clampf(velocity.y, -1.0, 1.5)
		_fall_start = global_position.y
	honey_stuck = touching_side("honey_sticky")
	if honey_stuck:
		# Against a honey block you stick: slow across, sliding slowly down,
		# and a fall stops there; you can still jump off it.
		var flat := Vector2(velocity.x, velocity.z).limit_length(HONEY_STICK_ACROSS)
		flat *= pow(0.85 if flat.length() > HONEY_STICK_ACROSS * 0.75 else 0.6, delta * 60.0)
		velocity.x = flat.x
		velocity.z = flat.y
		velocity.y = clampf(velocity.y, -HONEY_STICK_FALL, HONEY_STICK_RISE)
		velocity.y *= pow(0.96 if velocity.y > 0.0 else 0.3, delta * 60.0)
		_fall_start = global_position.y
	# Buried in sand, silt or slush: stuck in it, suffocating, until you dig
	# out (Terraria doesn't push you clear).
	if buried():
		velocity = Vector3.ZERO
		_fall_start = global_position.y
		return
	# Holding Drop down falls through platforms (Terraria's down key).
	var drop := input_enabled and Input.is_action_pressed("drop_down")
	# The Flipper Potion (ignoreWater): not slowed by water or honey.
	var slowed := in_liquid != 0 and not (has_effect("ignore_water") and in_liquid != LIQ_LAVA)
	var step := velocity * delta * ((HONEY_MOVE if in_liquid == LIQ_HONEY else LIQUID_MOVE) if slowed else 1.0)
	# The Water Walking Potion: water and honey bear you like a floor (not
	# lava; hold Drop down to go in).
	var walk_on := -INF
	if has_effect("water_walk") and not drop and velocity.y <= 0.0:
		walk_on = liquid_top(game.world, global_position)
	var r: Dictionary = game.world.move_aabb(global_position, half, step, 1.05 if on_floor else 0.0, drop)
	var was_on_floor := on_floor
	global_position = r.position
	on_floor = r.on_floor
	if global_position.y < walk_on:
		global_position.y = walk_on
		on_floor = true
		velocity.y = 0.0
		_fall_start = global_position.y
	var blocked: Vector3i = r.blocked
	if blocked.y:
		if velocity.y < 0.0:
			var fall := _fall_start - global_position.y
			# Lucky Horseshoe, or landing on a cloud: no fall damage.
			var below := Vector3i((global_position + Vector3(0, -0.1, 0)).floor())
			if has_effect("no_fall_damage") or has_effect("featherfall") or Data.block(game.world.get_block(below)).get("fall_safe", false):
				fall = 0.0
			var tiles := int(fall * 1.5)
			# The Frog Leg's extraFall: tiles more before a fall hurts; a
			# mount's too, and its share of the damage (the slime's half).
			var safe := SAFE_FALL_TILES + int(stat("extra_fall"))
			var share := 1.0
			if mount != "":
				safe += int(MOUNTS[mount].get("extra_fall", 0))
				share = float(MOUNTS[mount].get("fall_damage", 1.0))
			if tiles > safe:
				if share > 0.0:
					hurt(int((tiles - safe) * 10 * share), Vector3.ZERO, true, null, "fall")
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


## Terraria's wall jump push (3 px a tick) and wall slides (WallslideMovement:
## 0.5 px a tick down, 4 holding Down).
const WALL_JUMP_PUSH := 3.0 * 2.5
const WALL_SLIDE := 0.5 * 2.5
const WALL_SLIDE_DOWN := 4.0 * 2.5


## Climbing Claws / Shoe Spikes: in the air, pressing into a wall (solid at
## your feet and above them), you slide down it slowly, or with both you
## stick; Drop down slides fast. Sliding, you can jump off it.
func _wall_slide(game, dir: Vector3) -> void:
	sliding = false
	var grip := int(stat("wall_slide"))
	if grip <= 0 or on_floor or dir == Vector3.ZERO or in_liquid != 0:
		return
	var side := Vector3(signf(dir.x), 0, 0) if absf(dir.x) > absf(dir.z) else Vector3(0, 0, signf(dir.z))
	var w: VoxelWorld = game.world
	for h in [0.05, 0.75]:
		if not w.is_solid(Vector3i((global_position + side * (half.x + 0.05) + Vector3(0, h, 0)).floor())):
			return
	var down := input_enabled and Input.is_action_pressed("drop_down")
	if grip >= 2:
		if velocity.y > 0.0:
			return  # rising past it
		velocity.y = -WALL_SLIDE_DOWN if down else 0.0
	elif velocity.y < -WALL_SLIDE:
		velocity.y = -WALL_SLIDE_DOWN if down else -WALL_SLIDE
	else:
		return
	sliding = true
	_slide_away = -side
	_fall_start = global_position.y


## The wings you wear ({} if none): their "wings" stats.
func wings() -> Dictionary:
	for s in accessories.slots:
		if s != null and Data.item(s.item).has("wings"):
			return Data.item(s.item).wings
	return {}


## Flying (Terraria's WingMovement, default wings): no gravity; up 0.1 px a
## tick each tick, 0.5 more while still falling, 0.1 more while slower than
## half a jump, up to `lift_max` jump speeds; it uses up flight time.
func _wing_flight(delta: float, wings: Dictionary) -> void:
	var k := 0.1 * 150.0 * delta  # 0.1 px a tick each tick, in blocks/s
	velocity.y += k
	if velocity.y < 0.0:
		velocity.y += 5.0 * k
	elif velocity.y < JUMP_SPEED * 0.5:
		velocity.y += k
	velocity.y = minf(velocity.y, JUMP_SPEED * float(wings.get("lift_max", 1.5)))
	_wing_time -= delta


## A hovering mount in the air (Terraria's Mount.Hover, the Bee; px a tick,
## its y down turned up here). Its flight time runs out first, then it
## tires (a tick a tick; a third as fast with Featherfall). Tiring, f of the
## way: left alone it sinks at 4f (fresh, it hangs still); holding jump it
## climbs (not once worn out) up to 2 + 6(1 - f); holding Drop down it
## sinks up to 8; it reaches those speeds 0.16 a tick. On the ground it
## gets its flight back and rests off 2 fatigue a tick (ResetFlightTime,
## FatigueRecovery).
func _hover(delta: float, rise: bool) -> void:
	var hv: Array = MOUNTS[mount].hover
	var ticks := delta * 60.0
	var can_rise := true
	if _fly_time > 0.0:
		_fly_time = maxf(0.0, _fly_time - ticks)
	elif _fatigue < float(hv[1]):
		_fatigue = minf(float(hv[1]), _fatigue + ticks * (1.0 / 3.0 if has_effect("featherfall") else 1.0))
	else:
		can_rise = false
	var f := _fatigue / float(hv[1])
	var accel := float(MOUNTS[mount].accel)
	var top := -4.0 * f  # fastest climb (px/tick, up); left alone, its sink
	var bottom := -4.0 * f  # fastest fall
	var vy := velocity.y / 2.5
	var down := input_enabled and Input.is_action_pressed("drop_down")
	if rise and can_rise:
		top = 2.0 + 6.0 * (1.0 - f)
		vy += accel * ticks
	elif down:
		bottom = -8.0
		vy -= accel * ticks
	if vy > top:
		vy = top if vy - top < accel * ticks else vy - accel * ticks
	elif vy < bottom:
		vy = bottom if bottom - vy < accel * ticks else vy + accel * ticks
	velocity.y = vy * 2.5
	_fall_start = global_position.y


## Rocket boots (Terraria's): 7 bursts of 10 ticks of the wings' lift, once
## your wings (if any) are spent and you've let go of jump and pressed it
## again in the air; they fill up on the ground.
const ROCKET_TIME := 7
const ROCKET_BURST := 10.0 / 60.0
var _rocket_sound := 0.0

func _rocketing(jump: bool, wing: Dictionary) -> bool:
	if stat("rocket") <= 0.0 or not jump or on_floor or _jump_ticks > 0 or not _rocket_release:
		return false
	if not wing.is_empty() and _wing_time > 0.0:
		return false
	if _rocket_burst <= 0.0:
		if _rocket_time <= 0:
			return false
		_rocket_time -= 1
		_rocket_burst = ROCKET_BURST
	return true


## Their flames and roar (Item_13 the Rocket Boots', Item_24 the others').
func _rocket_effects(delta: float) -> void:
	var game := Game.current
	game.dust.spawn(6, global_position + Vector3(0, 0.1, 0), Vector3(0, -2, 0), 1.5)
	_rocket_sound -= delta
	if _rocket_sound <= 0.0:
		_rocket_sound = 0.5 if stat("rocket") <= 1.0 else 0.25
		Audio.play("Item_13" if stat("rocket") <= 1.0 else "Item_24", 0.5)


## Your informational accessories, carried anywhere in your inventory or worn
## (Terraria's): {"watch": best level, "depth", "compass", "radar": true}.
func info_accessories() -> Dictionary:
	var out := {}
	for s in inventory.slots + accessories.slots:
		if s == null:
			continue
		var d := Data.item(s.item)
		var kind: String = d.get("info", "")
		if kind == "gps":
			# The GPS: a Gold Watch, a Depth Meter and a Compass in one.
			out["watch"] = 3
			out["depth"] = true
			out["compass"] = true
		elif kind == "watch":
			out["watch"] = maxi(int(out.get("watch", 0)), int(d.watch))
		elif kind != "":
			out[kind] = true
	return out


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
	if mount != "" and MOUNTS[mount].get("no_extra_jumps", false):
		return kinds
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
	var jump := can_act() and Input.is_action_pressed("jump")
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
	var up := can_act() and Input.is_action_pressed("jump")
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
	var jump := can_act() and Input.is_action_pressed("jump")
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


## The Harpoon: its head out on its chain where you look, one at a time, back
## when you let go (HarpoonShot).
func _shoot_harpoon(def: Dictionary) -> bool:
	if get_tree().get_nodes_in_group("harpoons").any(func(h): return h.player == self and not h.is_queued_for_deletion()):
		return false
	var h := HarpoonShot.new()
	h.setup(self, def, forward())
	Game.current.entities.add_child(h)
	h.global_position = camera.global_position + forward() * 0.6
	Audio.play(def.get("sound", "Item_10"), 0.6)
	return true


## A Bug Net's swing (Player.ItemCheck_CatchCritters): critters it sweeps
## through are caught, their item yours (NPC.CatchNPC). The Underworld's
## (lava bait) burn you instead, unless it's a Golden or Fireproof Bug Net:
## 1 damage and On Fire! for 5 s.
func _catch_critters(def: Dictionary) -> bool:
	var game := Game.current
	var reach := 2.4 * float(def.get("scale", 1.0))
	var cone := cos(deg_to_rad(65.0))
	var origin := camera.global_position
	var fwd := forward()
	for npc in game.npcs():
		if not npc.is_critter() or npc.is_queued_for_deletion():
			continue
		var c: Vector3 = npc.center()
		var ray_point := origin + fwd * maxf((c - origin).dot(fwd), 0.0)
		var bottom: float = npc.global_position.y
		var aim := Vector3(c.x, clampf(ray_point.y, bottom, bottom + npc.half.y), c.z)
		var to := aim - origin
		if to.length() - npc.half.x >= reach or to.normalized().dot(fwd) <= cone:
			continue
		if npc.def.get("lava_bait", false) and not def.get("lava_safe", false):
			hurt(1, c, true)
			on_fire = maxf(on_fire, 5.0)
			continue
		game.spawn_item(npc.catch_item(), 1, center())
		npc.queue_free()
	Audio.play("Item_1", 0.6)
	return true


## Using a critter's item lets it go where you aim (Player.ItemCheck_ReleaseCritter:
## within reach, not inside a block).
func _release(def: Dictionary) -> bool:
	var game := Game.current
	var at: Vector3
	if not target.is_empty():
		var cell: Vector3i = target.block + target.normal
		if game.world.is_solid(cell):
			return false
		at = Vector3(cell) + Vector3(0.5, 0.05, 0.5)
	else:
		at = camera.global_position + forward() * minf(reach(), 3.0)
		if game.world.is_solid(Vector3i(at.floor())):
			return false
	var npc: NPC = game.spawn_npc(def.release, at)
	npc.released = true
	if def.has("variant"):
		npc.variant = int(def.variant)
	_use_up(selected)
	return true


## A fishing pole: casts its bobber where you look, or with it out, reels it
## in (Terraria's ItemCheck_PullFishingBobbers: no new cast while one's out).
func _fish(def: Dictionary) -> bool:
	var out := bobbers()
	if out.is_empty():
		var b := Bobber.new()
		b.setup(self, def, forward())
		Game.current.entities.add_child(b)
		b.global_position = camera.global_position + forward() * 0.6
	else:
		for b in out:
			b.reel()
	Audio.play(def.get("sound", "Item_1"), 0.6)
	return true


func bobbers() -> Array:
	return get_tree().get_nodes_in_group("bobbers").filter(func(b): return b.player == self and not b.is_queued_for_deletion())


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
## Home: to your bed, or the world's spawn (the Magic Mirror, the Recall
## Potion).
func home_teleport() -> void:
	_teleport(respawn_point())


## The Teleportation Potion (Player.TeleportationPotion): somewhere at random
## in the world, standing on ground clear of lava, liquid and hurting blocks,
## no more than 100 tiles (here 66 blocks) above it; 1000 tries.
func random_teleport() -> void:
	var game := Game.current
	var size: Vector3i = game.world.get_size()
	for i in 1000:
		var spot = random_spot(game.world, Vector3i(randi_range(20, size.x - 21), randi_range(10, size.y - 10), randi_range(20, size.z - 21)))
		if spot != null:
			_teleport(spot)
			return


## Down from `p` to a safe floor (for random_teleport), or null.
static func random_spot(w: VoxelWorld, p: Vector3i):
	if w.is_solid(p) or w.is_solid(p + Vector3i.UP):
		return null
	for i in 66:
		var below := p + Vector3i.DOWN
		if below.y < 1 or w.get_liquid(p).y > 0:
			return null
		if w.is_solid(below):
			var under := Data.block(w.get_block(below))
			if under.has("touch_damage") or under.get("hot", false) or w.is_solid(p + Vector3i.UP):
				return null
			return Vector3(p.x + 0.5, p.y, p.z + 0.5)
		p = below
	return null


func _teleport(to: Vector3) -> void:
	var game := Game.current
	game.spawn_dust(center(), Color(0.75, 0.6, 1.0), 16)
	global_position = to
	velocity = Vector3.ZERO
	_fall_start = global_position.y
	game.spawn_dust(center(), Color(0.75, 0.6, 1.0), 16)
	Audio.play("Item_6", 0.7)


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
			weapon_damage(def, int(round(float(def.damage) * dmg_mult))), weapon_knockback(def) * maxf(1.0, dmg_mult), float(c.get("gravity", 0.0)), 0.0,
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
	var vertical := float(can_act() and Input.is_action_pressed("jump")) - float(input_enabled and Input.is_key_pressed(KEY_SHIFT))
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
## The top of the water or honey you'd stand on at `pos` (its surface, with
## you no lower than a little under it), or -INF.
static func liquid_top(w: VoxelWorld, pos: Vector3) -> float:
	for dy in [0.0, -1.0]:
		var cell := Vector3i((pos + Vector3(0, dy - 0.01, 0)).floor())
		var l: Vector2i = w.get_liquid(cell)
		if l.y <= 0 or l.x == LIQ_LAVA or w.get_liquid(cell + Vector3i.UP).y > 0:
			continue
		var top := cell.y + l.y / 63.0 * 0.94
		if pos.y >= top - 0.3:
			return top
	return -INF


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
		# Honey has its own splash (Terraria's Splash_1) and honey dust.
		var honey := LIQ_HONEY in [in_liquid, was]
		Audio.play("Splash_1" if honey else "Splash_*", 0.5)
		if in_liquid != 0 and velocity.y < -6.0:
			var col: Color = {LIQ_WATER: Color(0.5, 0.65, 1.0), LIQ_HONEY: Color(1.0, 0.75, 0.15)}.get(in_liquid, Color(1.0, 0.5, 0.1))
			game.spawn_dust(global_position, col, 20 if in_liquid == LIQ_HONEY else 14)


## No damage of any kind: the test world's god mode, or creative mode.
func invulnerable() -> bool:
	return god_mode or creative


func _liquid_effects(delta: float) -> void:
	honey_time = HONEY_TIME if in_liquid == LIQ_HONEY else maxf(0.0, honey_time - delta)
	if in_liquid != LIQ_LAVA:
		lava_time = minf(stat("lava_time"), lava_time + delta)
	lava_time = minf(lava_time, stat("lava_time"))
	if invulnerable():
		breath = BREATH_MAX
		on_fire = 0.0
		poisoned = 0.0
		mana = mana_max
		return
	# The Diving Helmet: breath lasts six times as long (breathCD 7 -> 42
	# ticks), drowning hurts a sixth as much.
	var diving := 6.0 if has_effect("diving") else 1.0
	if head_liquid != 0 and not has_effect("gills"):
		breath = maxf(0.0, breath - delta / diving)
	else:
		breath = minf(BREATH_MAX, breath + delta * 6.0)
	var dot := 0.0
	if breath <= 0.0:
		dot += DROWN_DPS / diving
	var fire_immune := has_effect("fire_immune")
	var fire_walk := has_effect("fire_walk")
	# The Lava Charm: lava doesn't hurt while its time lasts; out of lava it
	# fills back up as fast (a tick a tick).
	if in_liquid == LIQ_LAVA and has_effect("lava_immune"):
		pass  # Obsidian Skin: lava doesn't hurt at all
	elif in_liquid == LIQ_LAVA and lava_time > 0.0:
		lava_time = maxf(0.0, lava_time - delta)
	elif in_liquid == LIQ_LAVA:
		var rose := has_effect("lava_rose")
		var before := life
		hurt(LAVA_DAMAGE - (LAVA_ROSE_DAMAGE if rose else 0), Vector3.ZERO)
		# The Molten set: "Cannot be set on fire".
		if not fire_immune and life < before:
			on_fire = maxf(on_fire, ON_FIRE_TIME * (0.5 if rose else 1.0))
	elif not fire_walk and not fire_immune and _touching_hot():
		# Hellstone, like Terraria's fire blocks, sets you on fire.
		on_fire = ON_FIRE_TIME
	# Spikes (Terraria's TouchDamageImmediate): hurt at once, give or take 15%.
	var spikes := _touch_damage()
	if spikes > 0:
		hurt(int(round(spikes * randf_range(0.85, 1.15))), Vector3.ZERO)
	elif in_liquid == LIQ_WATER or in_liquid == LIQ_HONEY:
		on_fire = 0.0
	if on_fire > 0.0:
		on_fire = maxf(0.0, on_fire - delta)
		dot += ON_FIRE_DPS
	if poisoned > 0.0:
		poisoned = maxf(0.0, poisoned - delta)
		dot += POISON_DPS
	if has_effect("frostburn"):
		dot += FROSTBURN_DPS
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
	if poisoned > 0.0:
		out.append([20, "Poisoned", poisoned])
	if potion_sickness > 0.0:
		out.append([21, "Potion Sickness", potion_sickness])
	if sharpened:
		out.append([159, "Sharpened", INF])
	if bast_near:
		out.append([215, "The Bast Defense", INF])
	if suffocating:
		out.append([68, "Suffocation", INF])
	if honey_time > 0.0:
		out.append([48, "Honey", honey_time])
	for b in timed_buffs:
		out.append([int(Assets.ids.BuffID.get(b, 0)), Assets.ids.names.buffs.get(b, b), timed_buffs[b]])
	for b in companion_buffs():
		out.append([int(Assets.ids.BuffID.get(b, 0)), Assets.ids.names.buffs.get(b, b), INF])
	return out


## The buffs your minions and pets give (BuffID names, one for each kind).
func companion_buffs() -> Array:
	var out := []
	for m in minions + [pet, light_pet]:
		if m != null and is_instance_valid(m) and not m.cfg.buff in out:
			out.append(m.cfg.buff)
	if mount != "":
		out.append(MOUNTS[mount].buff)
	return out


## Cancels a buff (Terraria's right-click on its icon): a potion's, or a
## minion's or pet's (they go).
func cancel_buff(b: String) -> void:
	timed_buffs.erase(b)
	for m in minions.duplicate():
		if is_instance_valid(m) and m.cfg.buff == b:
			_dismiss(m)
	if pet != null and is_instance_valid(pet) and pet.cfg.buff == b:
		_dismiss(pet)
	if light_pet != null and is_instance_valid(light_pet) and light_pet.cfg.buff == b:
		_dismiss(light_pet)
	if mount != "" and MOUNTS[mount].buff == b:
		dismount()
	stats_changed.emit()


## How many minions you can have (Terraria's maxMinions: 1, and more from
## what you wear: the Bee Headgear's and Breastplate's 1 each).
func max_minions() -> int:
	return 1 + int(stat("max_minions"))


func _dismiss(m: Minion) -> void:
	minions.erase(m)
	if m == pet:
		pet = null
	if m == light_pet:
		light_pet = null
	m.queue_free()
	_number_minions()


## Terraria's minionPos: each minion's place in line, oldest first.
func _number_minions() -> void:
	minions = minions.filter(func(m): return is_instance_valid(m) and not m.is_queued_for_deletion())
	for i in minions.size():
		minions[i].index = i


func _spawn_companion(proj: String, def: Dictionary, at: Vector3, is_pet: bool) -> Minion:
	var m := Minion.new()
	m.setup(self, proj, def, is_pet)
	Game.current.entities.add_child(m)
	m.global_position = at - Vector3(0, m.box.y / 2.0, 0)
	return m


## A mount's item: on (if there's room over you for it) or off.
func _use_mount(def: Dictionary) -> bool:
	if mount != "":
		var same: bool = mount == def.mount
		dismount()
		if same:
			return true
	return ride(def)


## Gets on a mount: you ride `height` px higher, your box that much taller
## (Terraria's heightBoost; no room over you, no mount). False if it can't.
func ride(def: Dictionary) -> bool:
	var m: Dictionary = MOUNTS[def.mount]
	if m.get("no_water", false) and head_liquid != 0:
		return false
	var up := float(m.height) / 24.0
	var w := Game.current.world
	var lo := (global_position - Vector3(half.x, -0.01, half.z)).floor()
	var hi := (global_position + Vector3(half.x, half.y + up, half.z) - Vector3.ONE * 0.001).floor()
	for x in range(int(lo.x), int(hi.x) + 1):
		for y in range(int(lo.y), int(hi.y) + 1):
			for z in range(int(lo.z), int(hi.z) + 1):
				if w.is_solid(Vector3i(x, y, z)):
					return false
	mount = def.mount
	mount_item = def
	# Its flight starts spent (SetMount): on the ground it fills at once,
	# called up in the air it has only its fatigue to go on.
	_fly_time = 0.0
	_fatigue = 0.0
	half.y += up
	camera.position.y = EYE_HEIGHT + up
	if _mount_sprite != null and _mount_sprite.get_meta("mount", "") != def.mount:
		_mount_sprite.queue_free()
		_mount_sprite = null
	if _mount_sprite == null:
		_mount_sprite = EntitySprite.new()
		_mount_sprite.set_meta("mount", def.mount)
		var tex := Assets.texture("Images/Mount_%s" % m.sprite)
		var frames := int(m.frames)
		_mount_sprite.setup(tex, frames, Vector2(tex.get_width(), tex.get_height() / float(frames)) / 24.0, false, true)
		add_child(_mount_sprite)
	_mount_sprite.visible = true
	_mount_dust()
	stats_changed.emit()
	return true


func dismount() -> void:
	if mount == "":
		return
	var up := float(MOUNTS[mount].height) / 24.0
	half.y -= up
	camera.position.y = EYE_HEIGHT
	mount = ""
	mount_item = {}
	if _mount_sprite != null:
		_mount_sprite.visible = false
	_mount_dust()
	stats_changed.emit()


## Terraria's spawnDust as you get on or off (the slime's 56, the Bee's 152).
func _mount_dust() -> void:
	var id: int = MOUNTS[mount].get("dust", 56) if mount != "" else _last_mount_dust
	_last_mount_dust = id
	for i in 15:
		Game.current.dust.spawn(id, global_position + Vector3(randf_range(-0.5, 0.5), randf_range(0.0, 0.8), randf_range(-0.5, 0.5)),
				Vector3(randf_range(-1, 1), randf_range(0, 1.5), randf_range(-1, 1)), 1.2)


## Riding: the slime's stomp, falling onto enemies; its frames.
func _ride(delta: float, game) -> void:
	for n in _stomped.keys():
		_stomped[n] -= delta
		if _stomped[n] <= 0.0 or not is_instance_valid(n):
			_stomped.erase(n)
	var m: Dictionary = MOUNTS[mount]
	if m.get("no_water", false) and head_liquid != 0:
		dismount()
		return
	if m.has("hover") and on_floor:
		_fly_time = float(m.hover[0])
		_fatigue = maxf(0.0, _fatigue - 2.0 * delta * 60.0)
	if m.has("stomp") and velocity.y < 0.0 and in_liquid == 0:
		# Terraria's feet strip: 2 px at the bottom, 12 px wider each side and
		# 6 px taller each way.
		var feet := global_position - Vector3(0, 7.0 / 24.0, 0)
		var strip := Vector3(half.x + 0.5, 14.0 / 24.0, half.z + 0.5)
		for npc in game.npcs():
			if _stomped.has(npc) or npc.def.ai == "town" or npc.untouchable or npc.dont_take_damage:
				continue
			if not npc.overlaps_box(feet, strip):
				continue
			var dir := Vector3(velocity.x, 0, velocity.z).normalized()
			npc.hit(int(float(m.stomp) * (1.0 + (stat("damage") + stat("summon_damage")) / 100.0)), 5.0, dir, 0.0)
			_stomped[npc] = 10.0 / 60.0
			velocity.y = 25.0
			_immune = maxf(_immune, 6.0 / 60.0)
			break
	if _mount_sprite != null:
		var run: Array = m.get("run_frames", [0, int(m.frames) - 1])
		var air: Array = m.get("air_frames", [1, 1])
		if not on_floor:
			_mount_frame = _cycle(_mount_frame, air, delta * 5.0)
		elif Vector2(velocity.x, velocity.z).length() > 0.3:
			_mount_frame = _cycle(_mount_frame, run, delta * 5.0)
		else:
			_mount_frame = float(run[0])
		_mount_sprite.set_frame(int(_mount_frame))
		_mount_sprite.update_light(game.world, game.sky, global_position + Vector3(0, 0.4, 0))


## `frame` moved on `by` frames through [first, last], from first if it was
## outside them.
static func _cycle(frame: float, span: Array, by: float) -> float:
	var lo := float(span[0])
	var n := float(span[1]) - lo + 1.0
	if frame < lo or frame >= lo + n:
		return lo
	return lo + fmod(frame - lo + by, n)


## A whip's crack (Whip; Terraria's Item152 as it goes). It isn't held
## while it's out (Terraria's noUseGraphic): you see the whip itself.
func _crack_whip(def: Dictionary) -> bool:
	var w := Whip.new()
	w.setup(self, def)
	Game.current.entities.add_child(w)
	whip = w
	Audio.play(def.get("sound", "Item_152"), 0.7)
	return true


## A summon staff: its minion where you aim (Terraria: at the mouse), and if
## that's more than your minion slots, the oldest go (Terraria's
## Player.FreeUpPetsAndMinions). Item44 like Terraria's.
func _summon_minion(def: Dictionary) -> bool:
	var game := Game.current
	var at := aim_point()
	# Not in a block: back along your aim until it's clear.
	var back := forward()
	var tries := 0
	while game.world.is_solid(Vector3i(at.floor())) and tries < 12:
		at -= back * 0.25
		tries += 1
	var m := _spawn_companion(def.minion, def, at, false)
	minions.append(m)
	var used := 0.0
	for x in minions:
		used += x.slots()
	while used > max_minions() and minions.size() > 1:
		used -= minions[0].slots()
		_dismiss(minions[0])
	_number_minions()
	Audio.play(def.get("sound", "Item_44"), 0.7)
	stats_changed.emit()
	return true


## A pet's item: its pet, or away if it's out (Terraria toggles the buff); a
## new pet sends the old one off (one pet, one light pet).
func _use_pet(def: Dictionary) -> bool:
	var light: bool = def.get("light_pet", false)
	var old: Minion = light_pet if light else pet
	if old != null and is_instance_valid(old):
		var same: bool = old.kind == def.pet
		_dismiss(old)
		if same:
			Audio.play(def.get("sound", "Item_2"), 0.6)
			stats_changed.emit()
			return true
	call_pet(def)
	Audio.play(def.get("sound", "Item_2"), 0.6)
	stats_changed.emit()
	return true


## Calls the pet of a pet item to your side.
func call_pet(def: Dictionary) -> void:
	var m := _spawn_companion(def.pet, def, center() + Vector3(0, 0.5, 0), true)
	if def.get("light_pet", false):
		light_pet = m
	else:
		pet = m


## Whether a potion's buff (BuffID name) is on.
func has_buff(b: String) -> bool:
	return timed_buffs.get(b, 0.0) > 0.0


## Puts a debuff on you for `seconds` (a longer one already on stays):
## Warmth (resistCold) cuts Chilled to a quarter and Frozen to half
## (AddBuff_DetermineBuffTimeToAdd). Frozen doesn't take while you're frozen.
func debuff(b: String, seconds: float) -> void:
	if not alive:
		return
	if has_effect("warmth"):
		if b == "Chilled":
			seconds /= 4.0
		elif b == "Frozen":
			seconds /= 2.0
	if b == "Frozen" and has_buff("Frozen"):
		return
	timed_buffs[b] = maxf(timed_buffs.get(b, 0.0), seconds)
	stats_changed.emit()


## What an enemy's touch or a shot puts on you (Terraria's StatusFromNPC,
## StatusPlayer): [[debuff, 1 in n, ticks], ...].
func take_debuffs(list: Array) -> void:
	for d in list:
		if randi() % int(d[1]) == 0:
			debuff(d[0], float(d[2]) / 60.0)


## The Inferno Potion's ring: 20 damage a second to the enemies near you.
func _inferno(delta: float, game) -> void:
	if not has_effect("inferno"):
		_inferno_t = 0.0
		return
	_inferno_t += delta
	if _inferno_t < 1.0:
		return
	_inferno_t -= 1.0
	for npc in game.npcs():
		if npc.def.ai == "town" or npc.is_critter() or npc.def.get("invulnerable", false) or npc.dont_take_damage:
			continue
		var to: Vector3 = npc.center() - center()
		if to.length() < INFERNO_RANGE + npc.half.x:
			npc.hit(INFERNO_DAMAGE, 0.0, to.normalized(), 0.0)


func _tick_buffs(delta: float) -> void:
	for b in timed_buffs.keys():
		timed_buffs[b] -= delta
		if timed_buffs[b] <= 0.0:
			timed_buffs.erase(b)
			life = mini(life, life_cap())


func _regen(delta: float) -> void:
	# Honey: natural healing ramps up three times as fast (lifeRegenTime +2
	# a tick); the Crimson set twice as fast (+1), and heals half again as
	# much (Terraria's crimsonRegen).
	var crimson := has_effect("crimson_regen")
	_since_hurt += delta * (1.0 + (2.0 if honey_time > 0.0 else 0.0) + (1.0 if crimson else 0.0))
	# Terraria's natural regen ramps up the longer you avoid damage.
	var rate := (0.5 if _since_hurt > 8.0 else 0.0) + (1.0 if _since_hurt > 20.0 else 0.0)
	if crimson:
		rate *= 1.5
	# Terraria's lifeRegen from what you wear: half a life a second each (the
	# Band of Regeneration's 1, the Mana Regeneration Band's 2).
	rate += stat("regen") * 0.5
	# And a life a second more (lifeRegen +2).
	if honey_time > 0.0:
		rate += 1.0
	# On fire or poisoned, no healing, and it starts over (lifeRegen 0,
	# lifeRegenTime 0).
	if on_fire > 0.0 or poisoned > 0.0 or has_effect("frostburn"):
		rate = 0.0
		_since_hurt = 0.0
	if life < life_cap() and rate > 0.0:
		_regen_acc += rate * delta
		if _regen_acc >= 1.0:
			life = mini(life_cap(), life + int(_regen_acc))
			_regen_acc = fmod(_regen_acc, 1.0)
			stats_changed.emit()
	if mana < mana_cap() and _use_timer <= 0.0:
		# The Mana Regeneration Band's manaRegenBonus: half a mana a second each.
		# The Mana Regeneration Potion: as fast as standing still, always (manaRegenBuff).
		_mana_acc += delta * (4.0 + mana_cap() * 0.05 + stat("mana_regen_bonus") * 0.5) * (2.0 if has_effect("mana_regen_buff") else 1.0)
		if _mana_acc >= 1.0:
			mana = mini(mana_cap(), mana + int(_mana_acc))
			_mana_acc = fmod(_mana_acc, 1.0)
			stats_changed.emit()


# ------------------------------------------------------------------ items

func use_item() -> void:
	if _use_timer > 0.0 or slash_out():
		return
	# Frozen, or Cursed (noItems): nothing can be used.
	if has_effect("cc") or has_effect("cursed"):
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
	elif def.has("whip"):
		# Summon weapon speed (Jungle's Fury) cracks whips faster.
		duration /= 1.0 + stat("whip_speed") / 100.0
	match def.get("type", ""):
		"tool":
			# A hamaxe (the Molten Hamaxe) chops trees and hammers the rest.
			if def.has("hammer") and not (def.has("axe") and not target.is_empty() and Data.block(target.id).get("tool") == "axe"):
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
				Game.current.regrowth = def.get("regrow", false)
				_melee(def)
				Game.current.regrowth = false
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
				# The Builder Potion: 25% faster (tileSpeed).
				duration = 0.2 / (1.0 + stat("place_speed") / 100.0)
		"consumable":
			used = _consume(def)
		"summon":
			used = _summon(def)
		"pet":
			used = _use_pet(def)
		"mount":
			used = _use_mount(def)
		"bucket":
			used = _use_bucket(def)
		"ammo":
			# Snowballs: ammo you can throw too.
			if def.get("thrown_too", false):
				used = _throw(def)
		"critter":
			used = _release(def)
			duration = 10.0 / 60.0
		"tool_use":
			if def.get("bug_net", false):
				used = _catch_critters(def)
			elif def.has("rope_snake"):
				used = _summon_rope_snake(def)
			elif def.has("rope_coil"):
				used = _throw_rope_coil(def)
			elif def.has("ocean_teleport"):
				_conch_timer = float(def.ocean_teleport)
				_conch_to = "ocean"
				Audio.play(def.get("sound", "Item_6"), 0.7)
				used = true
			elif def.has("recall"):
				# The Magic and Ice Mirrors: home halfway through the use
				# (itemTime == itemTimeMax / 2).
				_conch_timer = float(def.recall)
				_conch_to = "home"
				Audio.play(def.get("sound", "Item_6"), 0.7)
				used = true
		"wire_tool":
			used = _use_wire_tool(def)
		"hook":
			used = fire_hook(def)
		"fishing_pole":
			used = _fish(def)
		_:
			duration = 0.25
	if used:
		_use_timer = duration
		_use_def = def
		_use_length = duration
		# Placing blocks and using generic items swing the arm, as in Minecraft.
		viewmodel.play(Viewmodel.use_style(def), duration)
		if def.get("type") in ["tool", "melee"]:
			Audio.play("Item_1", 0.7)


## A wrench lays its colour of wire in the targeted cell (a Wire from your
## inventory each); the Wire Cutter takes the cell's wire and actuator back
## (Terraria's KillWire, KillActuator: the Wire and Actuator drop); an
## Actuator goes onto a solid block.
func _use_wire_tool(def: Dictionary) -> bool:
	if target.is_empty():
		return false
	var game := Game.current
	var w: Wiring = game.wiring
	var cell: Vector3i = target.block
	var at := Vector3(cell) + Vector3(0.5, 0.5, 0.5)
	if def.has("wire"):
		var colour := int(def.wire)
		if w.mask(cell) & colour or (not creative and not inventory.remove("Wire", 1)):
			return false
		w.add(cell, colour)
		Audio.play_at("Dig_*", at, 0.5)
		return true
	if def.get("cut_wire", false):
		var m := w.mask(cell)
		if m == 0:
			return false
		w.remove(cell, m)
		if not creative:
			for c in Wiring.COLOURS:
				if m & c:
					game.spawn_item("Wire", 1, at)
			if m & Wiring.ACTUATOR:
				game.spawn_item("Actuator", 1, at)
		if m & Wiring.ACTUATOR and game.world.is_inactive(cell):
			game.world.set_inactive(cell, false)
		Audio.play_at("Dig_*", at, 0.5)
		return true
	if def.get("actuator", false):
		if w.mask(cell) & Wiring.ACTUATOR or not Data.block(target.id).get("solid", true):
			return false
		if not creative and not inventory.remove("Actuator", 1):
			return false
		w.add(cell, Wiring.ACTUATOR)
		Audio.play_at("Dig_*", at, 0.5)
		return true
	return false


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


func whip_out() -> bool:
	return whip != null and is_instance_valid(whip) and not whip.is_queued_for_deletion()


## Whether you can move and jump: not in a menu, not Frozen, Stoned or
## Webbed (Terraria's CCed clears your controls).
func can_act() -> bool:
	return input_enabled and not has_effect("cc")


## The enemy your aim falls on, up to 60 blocks off and not behind a block
## (Minion.chaseable ones), or null.
func aimed_enemy():
	var origin := camera.global_position
	var fwd := forward()
	var best_d := float(Game.current.world.raycast(origin, fwd, 60.0).get("distance", 60.0))
	var best = null
	for npc in Game.current.npcs():
		if not Minion.chaseable(npc):
			continue
		var c: Vector3 = npc.center()
		var along := (c - origin).dot(fwd)
		if along <= 0.0 or along > best_d:
			continue
		var off := origin + fwd * along - c
		if absf(off.y) < npc.half.y * 0.6 + 0.2 and Vector2(off.x, off.z).length() < npc.half.x + 0.3:
			best = npc
			best_d = along
	return best


## The mark on your minions' target: Terraria's Extra_199 (4 frames, 10 a
## second, white at 0.7 and half see-through), seen through walls, only
## while you hold a summon staff; gone with the enemy.
func _mark_target() -> void:
	if minion_target != null and not Minion.chaseable(minion_target):
		minion_target = null
	var show: bool = minion_target != null and (held().has("minion") or held().has("whip")) and alive
	if show and _target_marker == null:
		_target_marker = EntitySprite.new()
		var tex := Assets.texture("Images/Extra_199")
		_target_marker.setup(tex, 4, Vector2(tex.get_width(), tex.get_height() / 4.0) / 24.0, true, true)
		_target_marker.set_xray(true)
		_target_marker.set_tint(Color(0.7, 0.7, 0.7, 0.5))
		Game.current.entities.add_child(_target_marker)
	if _target_marker != null:
		_target_marker.visible = show
		if show:
			_target_marker.global_position = minion_target.center()
			_target_marker.set_frame(int(Time.get_ticks_msec() / 100) % 4)
			_target_marker.set_glow()


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
	var swing := {}
	var thrust: bool = def.get("style", "swing") == "thrust"
	# A bigger sword (a size prefix: Large, Massive...) reaches further.
	var reach := (2.4 if thrust else 2.9) * float(def.get("scale", 1.0))
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
			npc.hit(weapon_damage(def), weapon_knockback(def), to.normalized(), crit_chance(def), armor_penetration(def))
			on_melee_hit(npc, def, swing)
	# Ice Blade: a bolt with the swing, every so often (Terraria's useTime
	# longer than its useAnimation).
	if def.has("swing_shot") and _swing_shot_cd <= 0.0:
		var shot: Dictionary = def.swing_shot
		_swing_shot_cd = float(shot.get("every", 60)) / 60.0
		var b := game.spawn_projectile(shot.projectile, origin + fwd * 0.6, fwd * float(shot.get("speed", 20)),
				weapon_damage(def), weapon_knockback(def), 0.0, 0.0, 0.45, true, crit_chance(def))
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
	if def.has("harpoon"):
		return _shoot_harpoon(def)
	var ammo_slot := inventory.find_ammo(def.ammo)
	if ammo_slot < 0:
		return false
	var ammo := Data.item(inventory.slots[ammo_slot].item)
	# The Hellwing Bow fires Hellwings for Wooden Arrows, Molten Fury Flaming
	# Arrows (Terraria's PickAmmo; a Hellwing's flight has no drop).
	var proj: String = def.get("converts", {}).get(inventory.slots[ammo_slot].item, ammo.projectile)
	# Some armor has a chance to save ammo.
	if randf() * 100.0 >= stat("ammo_save"):
		_use_up(ammo_slot)
	var is_arrow: bool = def.ammo == "WoodenArrow"
	var drop := float(ammo.get("gravity", 6.0 if is_arrow else 0.0))
	# A shotgun (the Boomstick) fires several, spread out, for one round.
	var pellets: Array = def.get("pellets", [1, 1])
	var spread := float(def.get("spread", 0.0))
	var basis := camera.global_transform.basis
	# The Archery Potion: arrows 20% faster, 10% harder.
	var archery := is_arrow and has_effect("archery")
	var speed := float(def.shoot_speed) * (1.2 if archery else 1.0)
	var dmg := weapon_damage(def, int(def.damage) + int(ammo.get("damage", 0)))
	if archery:
		dmg = int(dmg * 1.1)
	for i in randi_range(int(pellets[0]), int(pellets[1])):
		var dir := forward()
		if spread > 0.0:
			dir = (dir + basis.x * randf_range(-spread, spread) + basis.y * randf_range(-spread, spread)).normalized()
		var pr := Game.current.spawn_projectile(proj, camera.global_position + forward() * 0.5 + basis.y * -0.1,
				dir * speed, dmg, weapon_knockback(def) + float(ammo.get("knockback", 0)), drop, 0.0, 0.7 if is_arrow else 0.25,
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
	if def.get("bees", false):
		_shoot_bees(def)
		Audio.play(def.get("sound", "Item_8"), 0.7)
		return true
	var pr := Game.current.spawn_projectile(def.projectile, camera.global_position + forward() * 0.6, forward() * float(def.shoot_speed),
			weapon_damage(def), weapon_knockback(def), 0.0, 0.0, 0.5, true, crit_chance(def))
	if def.get("channel", false):
		channelled = pr
		pr.steered_by = self
	Audio.play(def.get("sound", "Item_8"), 0.7)
	return true


## The Bee Gun (Terraria's ItemCheck_Shoot for item 1121): 1 to 3 bees, and
## one more at 1 in 6 twice, each off at the gun's speed give or take 0.7 px
## a tick each way, its damage (and 1 in 2 one more), through 3 hits or
## bounces.
func _shoot_bees(def: Dictionary) -> void:
	var n := randi_range(1, 3)
	for i in 2:
		if randi() % 6 == 0:
			n += 1
	Projectile.release_bees(Game.current, n, camera.global_position + forward() * 0.6, forward() * float(def.shoot_speed),
			weapon_damage(def), crit_chance(def))


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
			weapon_damage(def), weapon_knockback(def), float(def.get("gravity", 10.0)), 18.0, 0.45, true, crit_chance(def))
	pr.gravity_delay = float(def.get("gravity_delay", 0.0))
	pr.drag = float(def.get("drag", 0.0))
	# Through this many enemies (Terraria's penetrate: the Frost Daggerfish's 3).
	pr.penetrate = int(def.get("pierce", pr.penetrate))
	if def.has("explosive"):
		# A lit bomb: lobbed a little upward, heavier, with its fuse burning.
		pr.explosive = def.explosive
		pr.life = float(def.explosive.get("fuse", 3.0))
		pr.gravity = 20.0
		pr.velocity += Vector3(0, 3.0, 0) + velocity * 0.5
		pr.penetrate = int(def.explosive.get("pierce", 1))
	_use_up(selected)
	Audio.play("Item_1", 0.6)
	return true


func _place(def: Dictionary) -> bool:
	if target.is_empty():
		return false
	var game := Game.current
	# A tile wand (the Bone Wand) needs what it places from.
	if def.has("wand_ammo") and inventory.count_of(def.wand_ammo) <= 0:
		return false
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
	if bdef.has("grows_on"):
		return _plant_seed(id, bdef)
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
	# A painting needs the wall for all of it; nothing goes where one hangs.
	if Paintings.is_painting(bdef) and not Paintings.fits(game, bdef, pos, wall_dir):
		return false
	if not Paintings.covering(game, pos).is_empty():
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
	if def.has("wand_ammo"):
		inventory.remove(def.wand_ammo, 1)
	else:
		_use_up(selected)
	Audio.play("Dig_*", 0.6)
	if bdef.get("interact") == "chest":  # chests, barrels
		game.chests.register_new(pos)
	# Sand placed over a gap falls.
	game.settle_falling(pos)
	return true


## Herb seeds go in only on their soil (or a clay pot); on a herb ready to
## harvest they harvest it and go in its place, and they replace grass
## (Terraria's TryKillingReplaceableTile).
func _plant_seed(id: int, bdef: Dictionary) -> bool:
	var game := Game.current
	var pos: Vector3i = target.block
	if Data.block(target.id).get("render", "cube") != "cross":
		pos += target.normal
	var at := game.world.get_block(pos)
	var there := Data.block(at)
	if at != 0 and not (there.get("cut", false) and (not there.has("herb") or game.herbs.harvestable(there, pos))):
		return false
	if not Data.block(game.world.get_block(pos + Vector3i.DOWN)).get("name", "") in bdef.grows_on:
		return false
	if at != 0:
		game.break_block(pos)
	if not game.world.set_block(pos, id):
		return false
	_use_up(selected)
	Audio.play("Dig_*", 0.6)
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
	# A Hive gives a Honey Block (Terraria's ExtractinatorMode 5).
	var into: String = held().get("extract_to", "")
	_use_up(selected)
	Audio.play("Grab")
	var drop := [into, 1] if into != "" else Extractinator.roll(_extract_rng)
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
			weapon_knockback(def), 0.0, 12.0, 0.7, true, crit_chance(def))
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
		# (Bottled Honey: drunk for its buff at full life too.)
		if potion_sickness > 0.0 or (life >= life_cap() and not def.has("honey")):
			return false
		heal(int(def.heal))
		potion_sickness = float(def.get("sickness", POTION_SICKNESS)) if def.internal != "Mushroom" else 0.0
		honey_time = maxf(honey_time, float(def.get("honey", 0)))
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
	elif def.has("buff"):
		# A buff potion: its buff for its time (drinking another restarts it).
		# Food's three kinds of Well Fed replace one another.
		if def.buff[0] in WELL_FED:
			for b in WELL_FED:
				timed_buffs.erase(b)
		timed_buffs[def.buff[0]] = float(def.buff[1])
	elif def.get("recall", false):
		home_teleport()
	elif def.get("teleport_random", false):
		random_teleport()
	else:
		return false
	Audio.play(def.get("sound", "Item_3"))
	_use_up(selected)
	stats_changed.emit()
	return true


func _summon(def: Dictionary) -> bool:
	if def.has("minion"):
		return _summon_minion(def)
	if def.has("whip"):
		return _crack_whip(def)
	var game := Game.current
	# The Goblin Battle Standard: the Goblin Army, if you've 200 max life and
	# none is on (else nothing happens and it isn't used up).
	if def.has("invasion"):
		if not game.invasion.start():
			return false
		Audio.play("Roar_0", 0.8)
		_use_up(selected)
		return true
	# The Bloody Tear (Terraria's BloodMoonStarter): a Blood Moon, at night
	# with none on (else nothing happens and it isn't used up); a new moon
	# turns waxing crescent.
	if def.get("event") == "blood_moon":
		if game.sky.is_day or game.sky.blood_moon:
			return false
		Audio.play("Roar_0", 0.8)
		if game.sky.moon_phase == 4:
			game.sky.moon_phase = 5
		game.start_blood_moon()
		_use_up(selected)
		return true
	# The Money Trough: the Flying Piggy Bank, thrown out the way you look
	# (one at a time; never used up).
	if def.get("piggy", false):
		for e in game.entities.get_children():
			if e is FlyingPiggyBank:
				e.queue_free()
		var pig := FlyingPiggyBank.new()
		game.entities.add_child(pig)
		pig.setup(camera.global_position + forward() * 0.8, forward())
		Audio.play("Item_59")
		return true
	match def.get("summon_when", "night"):
		"night":
			if game.sky.is_day:
				game.message("Nothing happens... it must be used at night.", Color(0.8, 0.8, 0.8))
				return false
		"corruption":
			# Terraria: Worm Food works only in the Corruption (and does nothing elsewhere).
			if game.biome != "corruption":
				return false
		"crimson":
			# Terraria: the Bloody Spine works only in the Crimson.
			if game.biome != "crimson":
				return false
		"jungle":
			# Terraria: the Abeemination works only in the Jungle.
			if game.biome != "jungle":
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
	# A sponge soaks up its liquid and stays a sponge (the Super Absorbant
	# Sponge: water; the Honey and Lava Absorbant ones).
	var sponge := int(def.get("sponge", 0))
	if liquid == 0:
		var hit: Dictionary = w.raycast_liquid(camera.global_position, forward(), REACH)
		if hit.is_empty() or int(hit.liquid) == 0:
			return false
		var cell: Vector3i = hit.block
		var t: int = w.get_liquid(cell).x
		if sponge != 0 and t != sponge:
			return false
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
		if sponge == 0:
			_swap_held({LIQ_WATER: "WaterBucket", LIQ_LAVA: "LavaBucket", LIQ_HONEY: "HoneyBucket"}[t])
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
		# A Bottomless Bucket never runs out.
		if not def.get("endless", false):
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
	Game.current.spawn_item(s.item, s.count, camera.global_position + forward(), forward() * 6.0, 1.5, int(s.get("prefix", 0)))


func _interact() -> void:
	if has_effect("cc"):
		return
	# Holding a summon staff: set your minions on the enemy you aim at (on
	# it again: let it go).
	if held().has("minion") or held().has("whip"):
		var foe = aimed_enemy()
		if foe != null:
			minion_target = null if minion_target == foe else foe
			return
	# The Flying Piggy Bank: your Piggy Bank.
	for e in Game.current.entities.get_children():
		if e is FlyingPiggyBank and e.aimed(camera.global_position, forward(), minf(5.0, float(target.get("distance", 5.0)) + 0.5)):
			Audio.play("Menu_Open")
			Game.current.hud.open_chest(piggy_bank, Vector3i(e.global_position.floor()))
			return
	var npc = talk_target()
	if npc != null and npc.kind == "BoundGoblin":
		# Untied, he's the Goblin Tinkerer.
		var freed: NPC = Game.current.town.free_goblin(npc)
		Game.current.hud.open_chat(freed, NPC.dialog(NPC.FREED_LINE))
		return
	if npc != null and npc.kind == "BoundMechanic":
		var mechanic: NPC = Game.current.town.free_mechanic(npc)
		Game.current.hud.open_chat(mechanic, NPC.dialog(NPC.MECHANIC_FREED_LINE))
		return
	if npc != null and npc.kind == "SleepingAngler":
		# Woken, he's the Angler (Terraria's: one of his thank-you lines).
		var angler: NPC = Game.current.town.wake_angler(npc)
		Game.current.hud.open_chat(angler, NPC.dialog(randi_range(353, 355)))
		return
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
	elif bdef.get("interact") == "bank":
		Audio.play("Menu_Open")
		Game.current.hud.open_chest(piggy_bank if bdef.get("bank") == "piggy" else safe, target.block)
	elif bdef.get("interact") == "locked_chest":
		Game.current.unlock_chest(target.block)
	elif bdef.get("interact") == "switch":
		Game.current.hit_switch(target.block)
	elif bdef.get("interact") == "timer":
		Game.current.wiring.toggle_timer(Game.current, target.block)
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
	life = mini(life_cap(), life + amount)
	if life > before:
		Game.current.floating_text(str(life - before), center() + Vector3(0, 1.3, 0), Color(0.3, 1.0, 0.3))
	stats_changed.emit()


## Terraria player damage: defense halves it, then 0.67 s of immunity.
## `attacker` (an NPC touching you) takes the Cactus set's thorns damage.
## Poisons you for `seconds` (the longer of it and what's left).
func poison(seconds: float) -> void:
	if alive and not invulnerable():
		poisoned = maxf(poisoned, seconds)


## Sets you on fire for `seconds` (the longer of it and what's left), unless
## you can't be (the Molten set: Terraria's buffImmune for On Fire!).
func ignite(seconds: float) -> void:
	if alive and not invulnerable() and not has_effect("fire_immune"):
		on_fire = maxf(on_fire, seconds)


## Fire thrown off a swing (Terraria's ItemCheck_EmitUseVisuals: the Molten
## tools' and the Fiery Greatsword's dust 6 in the swung item's box): along
## the arc the swing sweeps, from over your right shoulder down to the left.
func _swing_dust(delta: float) -> void:
	var dust: Array = _use_def.swing_dust
	_swing_dust_ticks += delta * 60.0
	var basis := camera.global_transform.basis
	while _swing_dust_ticks >= 1.0:
		_swing_dust_ticks -= 1.0
		var t := 1.0 - _use_timer / maxf(_use_length, 0.001)
		var a := lerpf(deg_to_rad(60.0), deg_to_rad(-120.0), t)
		for i in int(dust[1]):
			var at := camera.global_position - basis.z * randf_range(0.9, 1.6) + (basis.x * cos(a) + basis.y * sin(a)) * randf_range(0.3, 0.8)
			Game.current.dust.spawn(int(dust[0]), at, Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * 1.5, float(dust[2]) * 0.6)


## Terraria's Player.CheckCrackedBrickBreak, in its px a tick: running faster
## than a random 2-11 across, or landing faster than that, on cracked brick
## (unless you're also on firm ground) shatters the cracked bricks under you
## and a tile either side (nothing on top of them), and you fall through.
func _crack_bricks(game, delta: float) -> void:
	var across := Vector2(velocity.x, velocity.z).length() / 2.5
	var down := -velocity.y / 2.5
	if not (randi_range(2, 11) < across or randi_range(2, 11) < down):
		return
	var w: VoxelWorld = game.world
	# Where this tick takes you (Terraria's position + velocity).
	var feet := global_position + velocity * delta
	var below := int(floor(feet.y - 0.05))
	var cracked := func(q: Vector3i) -> bool: return Data.block(w.get_block(q)).get("cracked", false)
	if down < 1.0:
		for c in [Vector2(0, 0), Vector2(-half.x, -half.z), Vector2(half.x, half.z), Vector2(-half.x, half.z), Vector2(half.x, -half.z)]:
			var q := Vector3i(floori(feet.x + c.x), below, floori(feet.z + c.y))
			if w.is_solid(q) and not cracked.call(q):
				return
	var lo := Vector3i(floori(feet.x - half.x - 1.0), below - 1, floori(feet.z - half.z - 1.0))
	var hi := Vector3i(floori(feet.x + half.x + 1.0), below, floori(feet.z + half.z + 1.0))
	var under := false
	for x in range(floori(feet.x - half.x), floori(feet.x + half.x) + 1):
		for z in range(floori(feet.z - half.z), floori(feet.z + half.z) + 1):
			var q := Vector3i(x, below, z)
			if cracked.call(q) and not w.is_solid(q + Vector3i.UP):
				under = true
	if not under:
		return
	for x in range(lo.x, hi.x + 1):
		for z in range(lo.z, hi.z + 1):
			for y in range(hi.y, lo.y - 1, -1):
				var q := Vector3i(x, y, z)
				if cracked.call(q) and not w.is_solid(q + Vector3i.UP):
					game.break_block(q)


## A melee hit's extras (Terraria's StatusToNPC, and Projectile.StatusNPC for
## melee projectiles): the Magma Stone's Hellfire (6 s one hit in four, else
## 4 s or 2 s at even odds); a "leech" weapon (the Bat Bat) heals you 1, once a
## swing (`swing`: a dictionary the swing keeps), and not off target dummies
## or critters (BatBat_TryLifeLeeching).
func on_melee_hit(npc, def: Dictionary, swing := {}) -> void:
	if has_effect("magma_stone"):
		npc.ignite_hellfire(6.0 if randi() % 4 == 0 else (4.0 if randi() % 2 == 0 else 2.0))
	# The Fiery Greatsword: the first enemy a swing hits erupts (Terraria's
	# Volcano_TrySpawningVolcano: 75% of the hit, not off target dummies or
	# critters).
	if def.get("volcano", false) and not swing.get("erupted", false) and npc.def.ai != "dummy" and not npc.is_critter():
		swing["erupted"] = true
		Game.current.spawn_projectile("Volcano", npc.center(), Vector3(0, 0.01, 0), int(weapon_damage(def) * 0.75),
				weapon_knockback(def), 0.0, 0.0, 2.2, true, crit_chance(def))
		Audio.play_at("Custom/dd2_explosive_trap_explode_*", npc.center(), 0.7)
		for i in 20:
			Game.current.dust.spawn(6, npc.center() + Vector3(randf_range(-0.4, 0.4), randf_range(-0.4, 0.4), randf_range(-0.4, 0.4)),
					Vector3(randf_range(-0.6, 0.6), 1.0, randf_range(-0.6, 0.6)) * randf_range(2.0, 7.0), randf_range(1.0, 2.0))
	# The Beekeeper (ApplyNPCOnHitEffects, StatusToNPC): each hit lets loose
	# 1 to 3 bees with a third of its damage, off your way at 2 px a tick,
	# and Confuses the enemy for 2 s (not off target dummies or critters).
	if def.get("bees_on_hit", false) and npc.def.ai != "dummy" and not npc.is_critter():
		var away := Vector3(forward().x, 0, forward().z).normalized() * 2.0 * 3.75
		Projectile.release_bees(Game.current, randi_range(1, 3), npc.center(), away, weapon_damage(def) / 3, crit_chance(def))
	if def.has("confuses") and npc.def.ai != "dummy":
		npc.confuse(float(def.confuses))
	if def.get("leech", false) and not swing.get("leeched", false) and life < life_cap() \
			and npc.def.ai != "dummy" and not npc.is_critter():
		swing["leeched"] = true
		heal(1)


## Hurts you; true if it did (not invulnerable or immune). `source`: what
## else hurt you, for what only some hurts set off ("shot": an enemy's
## projectile, "fall").
func hurt(amount: int, from: Vector3, ignore_immunity := false, attacker = null, source := "") -> bool:
	if not alive or invulnerable() or (_immune > 0.0 and not ignore_immunity):
		return false
	var game := Game.current
	var npc_attacker: bool = attacker != null and is_instance_valid(attacker) and attacker is NPC
	# Warmth (resistCold): cold enemies hit 30% softer.
	if npc_attacker and attacker.def.get("cold", false) and has_effect("warmth"):
		amount = int(amount * 0.7)
	var dmg := maxi(1, amount - defense() / 2)
	# The Endurance Potion: 10% less damage taken.
	if stat("endurance") > 0.0:
		dmg = maxi(1, int(dmg * (1.0 - stat("endurance") / 100.0)))
	life -= dmg
	if has_effect("panic"):
		_panic = 8.0
	# Magic Cuffs: the damage you take comes back as mana.
	if has_effect("magic_cuffs"):
		mana = mini(mana_cap(), mana + dmg)
	# The Honey Comb (Player.Hurt; 1.4.5: only enemies and falls): a bee, and
	# one more at 1 in 3 twice, 13 damage each, and 5 s of Honey.
	if has_effect("honey_comb") and (npc_attacker or source in ["shot", "fall"]):
		var n := 1 + (1 if randi() % 3 == 0 else 0) + (1 if randi() % 3 == 0 else 0)
		Projectile.release_bees(game, n, center(), Vector3.ZERO, HONEY_COMB_BEE_DAMAGE, 0.0)
		honey_time = maxf(honey_time, HONEY_COMB_HONEY)
	# The Thorns Potion: the attacker takes what it dealt (thorns 1).
	var thorns := int(stat("thorns")) + int(amount * stat("thorns_reflect"))
	if thorns > 0 and attacker != null and is_instance_valid(attacker) and attacker.life > 0:
		attacker.hit(thorns, 0.0, (attacker.center() - center()).normalized(), 0.0)
	_since_hurt = 0.0
	_immune = IMMUNE_TIME
	if npc_attacker:
		take_debuffs(attacker.def.get("contact_debuffs", []))
		# What a slime carries inside it can hurt too (StatusFromNPC): stone
		# Stoned, cobweb Webbed, snow and slush Frostburn.
		var held: String = attacker.carried
		if held in CARRIED_DEBUFFS:
			var cd: Array = CARRIED_DEBUFFS[held]
			debuff(cd[0], randi_range(int(cd[1]), int(cd[2])) / 60.0)
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
	return true


func _die() -> void:
	alive = false
	sharpened = false
	charging = {}
	climbing = null
	on_rope = false
	for h in hooks():
		h.queue_free()
	dismount()
	# Your minions go (their buffs end with you); pets wait for you.
	for m in minions:
		if is_instance_valid(m):
			m.queue_free()
	minions.clear()
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
	lava_time = stat("lava_time")
	on_fire = 0.0
	poisoned = 0.0
	honey_time = 0.0
	timed_buffs.clear()
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
		"piggy_bank": piggy_bank.to_data(),
		"safe": safe.to_data(),
		"life": life, "life_max": life_max, "mana": mana, "mana_max": mana_max,
		"pos": [global_position.x, global_position.y, global_position.z],
		"yaw": _yaw, "pitch": _pitch, "selected": selected,
		"bed": [bed.x, bed.y, bed.z],
		"angler_quests": angler_quests,
		"buffs": timed_buffs.duplicate(),
		"pets": [pet.item.internal if pet != null and is_instance_valid(pet) else "",
				light_pet.item.internal if light_pet != null and is_instance_valid(light_pet) else ""],
	}


func load_state(d: Dictionary) -> void:
	inventory.from_data(d.get("inventory", []))
	accessories.from_data(d.get("accessories", []))
	armor.from_data(d.get("armor", []))
	hook_slot.from_data(d.get("hook", []))
	piggy_bank.from_data(d.get("piggy_bank", []))
	safe.from_data(d.get("safe", []))
	life_max = int(d.get("life_max", 100))
	timed_buffs = {}
	var saved_buffs: Dictionary = d.get("buffs", {})
	for b in saved_buffs:
		timed_buffs[b] = float(saved_buffs[b])
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
	angler_quests = int(d.get("angler_quests", 0))
	# Your pets come back with you (Terraria keeps their buffs).
	for m in [pet, light_pet]:
		if m != null and is_instance_valid(m):
			m.queue_free()
	pet = null
	light_pet = null
	for p_item in d.get("pets", []):
		if p_item != "" and Data.items.has(p_item) and Data.item(p_item).has("pet"):
			call_pet(Data.item(p_item))
	stats_changed.emit()
