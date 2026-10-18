class_name Extractinator
## What the Extractinator sifts out of a block of silt or slush: Terraria's
## ExtractinatorHelper.RollExtractinatorDrop for ExtractinatorMode 0, roll for
## roll. Half the time coins; else 1 in 5000 an Amber Mosquito, 1 in 25 a gem,
## 1 in 50 Amber; else a third of the time coins again (better odds of the
## big ones), two thirds an ore of the eight early ores. Gems, Amber and ores
## can come several to a block.

const GEMS := ["Amethyst", "Topaz", "Sapphire", "Emerald", "Ruby", "Diamond"]
const ORES := ["CopperOre", "IronOre", "SilverOre", "GoldOre", "TinOre", "LeadOre", "TungstenOre", "PlatinumOre"]


## Terraria's UnifiedRandom.Next(n): 0 .. n - 1.
static func _next(rng: RandomNumberGenerator, n: int) -> int:
	return rng.randi_range(0, n - 1)


## Next(a, b): a .. b - 1.
static func _between(rng: RandomNumberGenerator, a: int, b: int) -> int:
	return rng.randi_range(a, b - 1)


## [item, count] for one block.
static func roll(rng: RandomNumberGenerator) -> Array:
	if _next(rng, 2) == 0:
		return _coins(rng, [12000, 14, 3, 2], [800, 6], [60, 4], [3])
	if _next(rng, 5000) == 0:
		return ["AmberMosquito", 1]
	if _next(rng, 25) == 0:
		return [GEMS[_next(rng, 6)], _bonus(rng, 1)]
	if _next(rng, 50) == 0:
		return ["Amber", _bonus(rng, 1)]
	if _next(rng, 3) == 0:
		return _coins(rng, [5000, 10, 5, 3], [400, 5], [30, 3], [2])
	# RollOreEarlymode: Copper, Iron, Silver, Gold, Tin, Lead, Tungsten, Platinum.
	return [ORES[_next(rng, 8)], _bonus(rng, 1)]


## Extra gems, Amber or ore: 1 in 20 for 0-1 more, 1 in 30 for 0-2 ... 1 in 60 for 0-5.
static func _bonus(rng: RandomNumberGenerator, n: int) -> int:
	for k in 5:
		if _next(rng, 20 + k * 10) == 0:
			n += _between(rng, 0, k + 2)
	return n


## Platinum `plat` = [chance, bonus chance, bonus rolls, bonus max + 1]; gold,
## silver [chance, bonus chance]; copper [bonus chance]. Each coin's extra
## rolls: gold four of 1-20 and one of 1-19, silver three of 5-25 and one of
## 5-24, copper three of 10-25 and one of 10-24.
static func _coins(rng: RandomNumberGenerator, plat: Array, gold: Array, silver: Array, copper: Array) -> Array:
	if _next(rng, plat[0]) == 0:
		var n := 1
		for k in plat[2]:
			if _next(rng, plat[1]) == 0:
				n += _between(rng, 0, plat[3])
		return ["PlatinumCoin", n]
	if _next(rng, gold[0]) == 0:
		return ["GoldCoin", _coin_stack(rng, gold[1], 1, 21, 4)]
	if _next(rng, silver[0]) == 0:
		return ["SilverCoin", _coin_stack(rng, silver[1], 5, 26, 3)]
	return ["CopperCoin", _coin_stack(rng, copper[0], 10, 26, 3)]


static func _coin_stack(rng: RandomNumberGenerator, chance: int, lo: int, hi: int, rolls: int) -> int:
	var n := 1
	for k in rolls:
		if _next(rng, chance) == 0:
			n += _between(rng, lo, hi)
	if _next(rng, chance) == 0:
		n += _between(rng, lo, hi - 1)
	return n
