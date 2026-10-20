class_name Fishing
extends RefCounted
## Terraria's fishing (1.4.5): what a bobber in a pond catches, and when.
##
## Fishing power (Player.GetFishingConditions): the pole's and the bait's
## power plus your fishing skill (the Angler Earring), times the
## time of day and moon phase (Fishing_GetPowerMultiplier). A bobber resting
## on liquid counts up until it checks for a bite (Bobber, AI_061); the
## check (Projectile.FishingCheck, TryBuildFishingContext) needs at least 75
## tiles of liquid and cuts the power when the pond is smaller than 300
## (less high in the sky), rolls the catch's rarity (FishingCheck_RollDropLevels)
## and then walks Terraria's catch table (data/fishing.json, from
## Terraria.exe by tools/terraria_fishing.py): the first rule whose
## conditions hold and whose chance and rarity rolls succeed picks the catch.
##
## The pond: Terraria measures it in 2D, along the bobber's row and down
## each column. Here that's done in the vertical slices through the bobber
## along x and z (VoxelWorld.fishing_pond), the bigger one counting, and a
## block's cross-section is 1.5 x 1.5 Terraria tiles (a tile is 2/3 of a
## block), so each cell counts 2.25 tiles.
##
## The Angler's quest fish bite only while it's his fish today and you've
## none yet (Town.quest_fish). Not here: Blood Moon enemies, chum, luck,
## rain and the Truffle Worm. Catches that aren't items in this game skip
## their rule.

const RULES_PATH := "res://data/fishing.json"
## Tiles of liquid one cell counts for (1.5 x 1.5 tiles).
const TILES_PER_CELL := 2.25
## Below this the bobber catches nothing (Terraria: "Not Enough Water!").
const MIN_WATER := 75
## Full power from this much (times the height factor, atmo).
const FULL_WATER := 300
## Terraria's world width for the height factor's scale (maxTilesX / 4200).
const SMALL_WORLD_TILES := 4200.0
## A tile in blocks.
const TILE := 2.0 / 3.0
## Terraria's IsLavaBait: the Underworld's critters let any pole fish in lava.
const LAVA_BAIT := ["MagmaSnail", "HellButterfly", "Lavafly"]

static var _rules := []


static func rules() -> Array:
	if _rules.is_empty():
		var f := FileAccess.open(RULES_PATH, FileAccess.READ)
		_rules = JSON.parse_string(f.get_as_text()).rules
		for r in _rules:
			r.chance = [int(r.chance[0]), int(r.chance[1])]
	return _rules


## Float maths in 32 bits, like Terraria's.
static func f32(x: float) -> float:
	var a := PackedFloat32Array([x])
	return a[0]


## Terraria's Fishing_GetPowerMultiplier: dawn and dusk are good (1.3x),
## midday and midnight bad (0.8x); a full moon 1.1x, a new moon 0.9x.
## (No rain or Blood Moons here.) `time` is ticks into the day or night.
static func power_multiplier(is_day: bool, time: float, moon_phase: int) -> float:
	var m := 1.0
	if is_day and (time < 5400.0 or time > 48600.0):
		m = f32(m * f32(1.3))
	if is_day and time > 16200.0 and time < 37800.0:
		m = f32(m * f32(0.8))
	if not is_day and time > 6480.0 and time < 25920.0:
		m = f32(m * f32(0.8))
	if moon_phase == 0:
		m = f32(m * f32(1.1))
	if moon_phase == 1 or moon_phase == 7:
		m = f32(m * f32(1.05))
	if moon_phase == 3 or moon_phase == 5:
		m = f32(m * f32(0.95))
	if moon_phase == 4:
		m = f32(m * f32(0.9))
	return m


## Terraria's GetFishingConditions: {pole, pole_power, bait, bait_power,
## skill, level (FinalFishingLevel; 0 without a pole or bait)}. The pole is
## the held one, else the best in the inventory; the bait the first in the
## inventory.
static func conditions(player, sky) -> Dictionary:
	var c := {"pole": "", "pole_power": 0, "bait": "", "bait_power": 0, "skill": 0, "level": 0}
	var held: Dictionary = player.held()
	if int(held.get("fishing_power", 0)) > 0:
		c.pole = held.internal
		c.pole_power = int(held.fishing_power)
	else:
		for s in player.inventory.slots:
			var d := Data.item_of(s)
			if int(d.get("fishing_power", 0)) > c.pole_power:
				c.pole = d.internal
				c.pole_power = int(d.fishing_power)
	for s in player.inventory.slots:
		var d := Data.item_of(s)
		if s != null and int(d.get("bait", 0)) > 0:
			c.bait = s.item
			c.bait_power = int(d.bait)
			break
	if c.bait_power == 0 or c.pole_power == 0:
		return c
	c.skill = int(player.stat("fishing_skill"))
	# The Fishing Potion (Terraria's buff 121: fishingSkill + 15).
	if player.has_buff("Fishing"):
		c.skill += 15
	var total: int = c.bait_power + c.pole_power + c.skill
	var mult := power_multiplier(sky.is_day, sky.time, sky.moon_phase)
	c.level = int(f32(float(total) * mult))
	return c


## The pond the bobber at `pos` is in: {tiles (Terraria's numWaters), lava, honey}.
static func pond(world: VoxelWorld, pos: Vector3) -> Dictionary:
	var p: Dictionary = world.fishing_pond(Vector3i(pos.floor()), 2000)
	return {"tiles": int(maxi(int(p.x), int(p.z)) * TILES_PER_CELL), "lava": p.lava, "honey": p.honey}


## Terraria's height levels: 0 the sky (the space layer here), 1 the surface,
## 2 underground, 3 the caverns, 4 the Underworld.
static func height_level(game, y: float) -> int:
	if y > game.space_level():
		return 0
	if y > game.surface_level - 12:
		return 1
	if y > game.cavern_level:
		return 2
	if y > game.underworld_level:
		return 3
	return 4


## Terraria's atmo: near the top of the world a pond needs less liquid for
## full power (in Terraria tiles from the world's top).
static func height_factor(game, y: float) -> float:
	var size: Vector3i = game.world.get_size()
	var tiles_y := (size.y - y) / TILE
	var surface: float = (size.y - game.surface_level) / TILE
	var s := (size.x / TILE) / SMALL_WORLD_TILES
	s *= s
	return clampf((tiles_y - (60.0 + 10.0 * s)) / (surface / 6.0), 0.25, 1.0)


## Terraria's FishingCheck_RollDropLevels: which rarities this catch may be
## (each its own roll, likelier with more power), and whether it's a crate.
static func roll_rarity(level: int, crate_potion: bool, rng: RandomNumberGenerator) -> Dictionary:
	level = maxi(level, 1)
	var common := maxi(150 / level, 2)
	var uncommon := maxi(150 * 2 / level, 3)
	var rare := maxi(150 * 7 / level, 4)
	var very_rare := maxi(150 * 15 / level, 5)
	var legendary := maxi(150 * 30 / level, 6)
	var crate := 10 + (15 if crate_potion else 0)
	return {
		"common": rng.randi_range(0, common - 1) == 0,
		"uncommon": rng.randi_range(0, uncommon - 1) == 0,
		"rare": rng.randi_range(0, rare - 1) == 0,
		"veryrare": rng.randi_range(0, very_rare - 1) == 0,
		"legendary": rng.randi_range(0, legendary - 1) == 0,
		"crate": rng.randi_range(0, 99) < crate,
	}


## Terraria's TryBuildFishingContext, FishingCheck and the rules: a bobber
## at `pos` checks for a bite. Returns {"catch": item ("" for none),
## "level": the power after the pond's cut, "info": what the Fisherman's
## Pocket Guide says}.
static func check(game, player, pos: Vector3, rng: RandomNumberGenerator) -> Dictionary:
	var out := {"catch": "", "level": 0, "info": "", "lava": false}
	# Under water with the bobber above you: no bites.
	if player.in_liquid != 0 and pos.y > player.center().y:
		return out
	var p := pond(game.world, pos)
	out.lava = p.lava
	if p.tiles < MIN_WATER:
		out.info = "Not Enough Water!"
		return out
	var c := conditions(player, game.sky)
	var level: int = c.level
	if level == 0:
		return out
	var pole := Data.item(c.pole)
	var lava_ok: bool = pole.get("lava_fishing", false) or c.bait in LAVA_BAIT or player.has_effect("lava_fishing")
	out.info = "%d Fishing Power" % level
	var needed := int(FULL_WATER * height_factor(game, pos.y))
	var quality := float(p.tiles) / float(needed)
	if quality < 1.0:
		level = int(level * quality)
	if p.tiles < needed:
		out.info = "%d (%d%%) Fishing Power" % [level, -roundi((1.0 - quality) * 100.0)]
	out.level = level
	var height := height_level(game, pos.y)
	var junk := false
	if rng.randi_range(0, 49) > level and rng.randi_range(0, 49) > level:
		junk = p.tiles < needed
	var rarity := roll_rarity(level, player.has_buff("Crate"), rng)
	if rng.randi_range(0, 99) > (level + 75) / 2:
		return out
	var ctx := context(game, pos, p, height, junk, lava_ok, rarity)
	ctx["quest_fish"] = game.town.quest_fish(player)
	out["catch"] = roll_catch(ctx, rng)
	return out


## The catch table's conditions (AFishDropRulePopulator's fields) for a bobber.
static func context(game, pos: Vector3, p: Dictionary, height: int, junk: bool, lava_ok: bool, rarity: Dictionary) -> Dictionary:
	var biome: String = game.biome
	var dungeon: bool = biome == "dungeon" and game.defeated_bosses.has("SkeletronHead")
	var ocean: bool = height <= 1 and game.in_ocean(pos) and p.tiles > 1000
	var conds := {
		"HardMode": false, "EarlyMode": true, "InLava": p.lava, "InHoney": p.honey, "Junk": junk,
		"Crate": rarity.crate, "AnyEnemies": false, "CanFishInLava": lava_ok, "Dungeon": dungeon,
		"Beach": height <= 1 and game.in_ocean(pos), "Hallow": false, "GlowingMushrooms": biome == "mushroom",
		"TrueDesert": biome == "desert", "TrueSnow": biome == "snow", "Remix": false,
		"Height0": height == 0, "Height1": height == 1, "Height1And2": height == 1 or height == 2,
		"HeightAbove1": height > 1, "HeightAboveAnd1": height >= 1, "HeightUnder2": height < 2,
		"HeightAbove2": height > 2, "Height2": height == 2, "Height3": height == 3,
		"UnderRockLayer": pos.y <= game.cavern_level,
		"Corruption": biome == "corruption", "Crimson": biome == "crimson", "Jungle": biome == "jungle",
		"Snow": biome == "snow", "Desert": biome == "desert" and not dungeon, "RolledHallowDesert": false,
		"OriginalOcean": ocean, "RemixOcean": false, "Ocean": ocean, "Water1000": p.tiles > 1000,
		"BloodMoon": false, "DidNotUseCombatBook": true,
	}
	conds.merge(rarity)
	return conds


## Terraria's catch rarities (FishDropRules.Rarity).
static func rarity_matches(rarity: String, ctx: Dictionary) -> bool:
	match rarity:
		"Any":
			return true
		"Legendary":
			return ctx.legendary
		"VeryRare":
			return ctx.veryrare
		"Rare":
			return ctx.rare
		"Uncommon":
			return ctx.uncommon
		"Common":
			return ctx.common
		"BombRarityOfNotLegendaryAndNotVeryRareAndUncommon":
			return not ctx.legendary and not ctx.veryrare and ctx.uncommon
		"UncommonOrCommon":
			return ctx.uncommon or ctx.common
	return false


## FishDropRuleList.TryGetItemDropType: the first rule that holds decides.
static func roll_catch(ctx: Dictionary, rng: RandomNumberGenerator) -> String:
	for r in rules():
		# A quest fish only while it's the Angler's fish today (Town.quest_fish).
		if r.get("quest", false) and r.items[0] != ctx.get("quest_fish", ""):
			continue
		var ok := true
		for c in r.conditions:
			if not ctx.get(c, false):
				ok = false
				break
		if not ok or rng.randi_range(0, r.chance[1] - 1) >= r.chance[0] or not rarity_matches(r.rarity, ctx):
			continue
		if r.items.is_empty():
			return ""
		var item: String = r.items[rng.randi_range(0, r.items.size() - 1)]
		if Data.items.has(item):
			return item
	return ""


## How many of a catch: Bomb Fish and Frost Daggerfish come in stacks that
## grow with fishing power (AI_061_FishingBobber_GiveItemToPlayer).
static func catch_count(item: String, level: int, rng: RandomNumberGenerator) -> int:
	if item == "BombFish":
		var lo := (level / 20 + 3) / 2
		var hi := (level / 10 + 6) / 2
		for d in [50, 100, 150, 200]:
			if rng.randi_range(0, d - 1) < level:
				hi += 1
		return rng.randi_range(lo, hi)
	if item == "FrostDaggerfish":
		var lo := (level / 4 + 15) / 2
		var hi := (level / 2 + 40) / 2
		for d in [50, 100, 150, 200]:
			if rng.randi_range(0, d - 1) < level:
				hi += 6
		return rng.randi_range(lo, hi)
	return 1


## Terraria's ItemCheck_CheckFishingBobber_ConsumeBait: reeling in a bite
## may use up the bait it was on (1 in 1 + power / 6, less with a Tackle
## Box); junk never does, a Gold Worm only 1 in 20.
static func bait_used(bait: String, catch_item: String, tackle_box: bool, rng: RandomNumberGenerator) -> bool:
	var power := float(Data.item(bait).get("bait", 0))
	var odds := maxf(1.0 + power / 6.0, 1.0) + (1.0 if tackle_box else 0.0)
	var used := rng.randf() * odds < 1.0
	if catch_item != "" and int(Data.item(catch_item).get("rare", 0)) < 0:
		used = false
	if bait == "GoldWorm":
		used = rng.randi_range(0, 19) == 0
	if bait == "TruffleWorm":
		used = true
	return used
