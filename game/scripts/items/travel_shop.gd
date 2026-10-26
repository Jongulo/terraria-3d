class_name TravelShop
## The Traveling Merchant's stock (Terraria's Chest.SetupTravelShop), rolled
## each time he comes: 4 to 6 items, one more 1 time in 4, 8, 16 and 32 each
## (Player.RollLuck with no luck: 1 in n), then one painting. Each item is a
## pass down Terraria's list (SetupTravelShop_GetItem): every entry rolls 1 in
## its tier's rarity (100, 200 ... 600 for tiers 0 to 5) and the last that
## comes up (with its condition) is the one. Items this game doesn't have yet
## can't be stocked, so a pass that ends on one is rolled again, as Terraria
## rolls again for one already in the shop. A set comes whole (the Dynasty
## Wood and its shingles, a vanity piece and the rest of its outfit; the Team
## Blocks one colour, block and platform). The painting's rarities ease to 1
## as its tries run on (SetupTravelShop_AdjustSlotRarities).

const RARITY := [100, 200, 300, 400, 500, 600]
## The rest of a set (Chest.SetupTravelShop_AddToShop).
const SETS := {"DynastyWood": ["RedDynastyShingles", "BlueDynastyShingles"],
		"LilacDuskHead": ["LilacDuskBody", "LilacDuskLegs"], "ChefHat": ["ChefShirt", "ChefPants"],
		"GameMasterShirt": ["GameMasterPants"], "StarPrincessCrown": ["StarPrincessDress", "CelestialWand"],
		"LincolnsHood": ["LincolnsHoodie", "LincolnsPants"], "PrettyPinkRibbon": ["PrettyPinkDressSkirt", "PrettyPinkDressPants"]}
## The Team Blocks: one colour of them, block then platform.
const TEAM := [["TeamBlockWhite", "TeamBlockWhitePlatform"], ["TeamBlockRed", "TeamBlockRedPlatform"],
		["TeamBlockBlue", "TeamBlockBluePlatform"], ["TeamBlockGreen", "TeamBlockGreenPlatform"],
		["TeamBlockYellow", "TeamBlockYellowPlatform"], ["TeamBlockPink", "TeamBlockPinkPlatform"]]


static func roll(game, rng: RandomNumberGenerator) -> Array:
	var shop := []
	var count := rng.randi_range(4, 6)
	for n in [4, 8, 16, 32]:
		if rng.randi() % n == 0:
			count += 1
	# (Terraria's Expert mode, Peddler's Satchel and anniversary worlds add
	# more; Hardmode first rolls one of its rarer items.)
	var added := 0
	var tries := 0
	while added < count and tries < 5000:
		tries += 1
		var it := get_item(game, RARITY, 0, rng)
		if can_add(shop, it):
			_add(shop, it, rng)
			added += 1
	var r := RARITY.duplicate()
	for attempt in range(1, 5001):
		_adjust(attempt, r)
		var p := get_painting(game, r, rng)
		if can_add(shop, p):
			_add(shop, p, rng)
			break
	return shop


## 1 in n (Player.RollLuck(n) == 0, no luck).
static func _one_in(rng: RandomNumberGenerator, n: int) -> bool:
	return rng.randi() % n == 0


## Terraria's list (SetupTravelShop_GetItem), in its order: [tier, item,
## condition]. Conditions: hardmode (not in yet), skeletron, orb (a Shadow Orb
## or Crimson Heart smashed), boss (any boss beaten), eye (the Eye of
## Cthulhu); "@skin" is one of the Tiger, Leopard and Zebra Skins.
const ITEMS := [
	[4, "BlackCounterweight", ""], [3, "YellowCounterweight", ""], [5, "AngelHalo", ""],
	[4, "Gatligator", "hardmode"], [4, "BouncingShield", "hardmode"], [4, "Kimono", ""], [4, "ArcaneRuneWall", ""],
	[3, "PulseBow", "hardmode"], [3, "WaterGun", ""], [3, "DiamondRing", ""], [3, "CrimsonCloak", ""], [3, "MysteriousCape", ""],
	[3, "RedCape", ""], [3, "WinterCape", ""], [3, "HunterCloak", ""], [3, "SittingDucksFishingRod", "skeletron"],
	[3, "CompanionCube", ""], [3, "AntiPortalBlock", "hardmode"], [3, "BirdieRattle", ""], [3, "ExoticEasternChewToy", ""],
	[3, "BlueEgg", ""], [3, "BedazzledNectar", ""], [3, "BambooLeaf", ""],
	[2, "LilacDuskHead", ""], [2, "Pho", ""], [2, "Revolver", "orb"], [2, "Fez", ""], [2, "MagicHat", ""], [2, "GypsyRobe", ""],
	[2, "Gi", ""], [2, "ChefHat", ""], [2, "GameMasterShirt", ""], [2, "StarPrincessCrown", ""], [2, "LincolnsHood", ""],
	[2, "DemonHorns", ""], [2, "DevilHorns", ""], [2, "PandaEars", ""], [2, "VulkelfEar", ""], [2, "GoblorcEar", ""], [2, "Fedora", ""],
	[2, "StarHairpin", ""], [2, "HeartHairpin", ""], [2, "UnicornHornHat", ""], [2, "PrettyPinkRibbon", ""],
	[2, "ZapinatorGray", "boss"], [2, "Code1", "eye"], [2, "Code2", "hardmode"],
	[1, "RollerSkatesBlueMountItem", ""], [1, "PadThai", ""], [1, "BrickLayer", ""], [1, "ExtendoGrip", ""], [1, "PaintSprayer", ""],
	[1, "PortableCementMixer", ""], [1, "ActuationAccessory", ""], [1, "Katana", ""], [1, "UltrabrightTorch", ""],
	[0, "Sake", ""], [0, "@skin", ""], [0, "SteampunkCup", ""], [0, "FancyDishes", ""], [0, "DynastyWood", ""], [0, "TeamBlockWhite", ""],
	[0, "LawnFlamingo", ""], [0, "DPSMeter", ""], [0, "LifeformAnalyzer", ""], [0, "Stopwatch", ""],
]
const SKINS := ["TigerSkin", "LeopardSkin", "ZebraSkin"]


## Everything he can bring (his list, its sets and the paintings).
static func all_items() -> Array:
	var out := []
	for e in ITEMS:
		out.append_array(SKINS if e[1] == "@skin" else [e[1]])
	for e in PAINTINGS:
		out.append(e[1])
	for k in SETS:
		out.append_array(SETS[k])
	for t in TEAM:
		out.append_array(t)
	return out


static func _holds(game, cond: String) -> bool:
	match cond:
		"hardmode": return false
		"skeletron": return game.defeated_bosses.has("SkeletronHead")
		"orb": return game.orbs_broken > 0
		"boss": return not game.defeated_bosses.is_empty()
		"eye": return game.defeated_bosses.has("EyeofCthulhu")
	return true


## SetupTravelShop_GetItem: the item a pass comes to ("" none), skipping the
## tiers below `least` (past its first three entries Terraria's list goes
## down the tiers, stopping at the first below `least`). Each entry rolls
## before its condition is looked at, as Terraria's do.
static func get_item(game, r: Array, least: int, rng: RandomNumberGenerator) -> String:
	var it := ""
	for e in ITEMS:
		if int(e[0]) < least:
			continue
		if _one_in(rng, r[e[0]]) and _holds(game, e[2]):
			it = SKINS[rng.randi() % 3] if e[1] == "@skin" else e[1]
	return it


## SetupTravelShop_GetPainting's list (not a Don't Starve world; "late":
## Hardmode, the Martians, the Frost Moon or the Moon Lord, none in yet).
const PAINTINGS := [
	[3, "PaintingWilson", ""], [3, "PaintingWillow", ""], [3, "PaintingWolfgang", ""], [3, "PaintingWendy", ""],
	[2, "MoonLordPainting", "late"], [2, "PaintingCastleMarsberg", "late"], [2, "PaintingMartiaLisa", "late"],
	[2, "PaintingTheTruthIsUpThere", "late"], [2, "PaintingAcorns", "late"], [2, "PaintingColdSnap", "late"],
	[2, "PaintingCursedSaint", "late"], [2, "PaintingSnowfellas", "late"], [2, "PaintingTheSeason", "late"],
	[2, "MoonmanandCompany", "late"], [2, "StickmanVsTerrTerr", ""], [2, "PaintingGermanZenith", ""], [2, "PaintingGermanBeer", ""],
	[1, "KargohsSummon", ""], [1, "BennyWarhol", ""], [1, "Duality", ""], [1, "HoplitePizza", ""], [1, "ParsecPals", ""],
	[1, "DoNotEattheVileMushroom", ""], [1, "SunshineofIsrapony", ""], [1, "HeroesFromAnotherWorld", ""],
	[1, "YuumaTheBlueTiger", ""], [1, "CozyWindow", ""],
]


static func get_painting(_game, r: Array, rng: RandomNumberGenerator) -> String:
	var it := ""
	for e in PAINTINGS:
		if _one_in(rng, r[e[0]]) and e[2] != "late":
			it = e[1]
	return it


## SetupTravelShop_CanAddItemToShop: something (that this game has), not in
## the shop yet, and only one colour of Team Blocks.
static func can_add(shop: Array, it: String) -> bool:
	if it == "" or Data.item(it).is_empty() or shop.has(it):
		return false
	if it == "TeamBlockWhite":
		for t in TEAM:
			if shop.has(t[0]):
				return false
	return true


static func _add(shop: Array, it: String, rng: RandomNumberGenerator) -> void:
	if it == "TeamBlockWhite":
		for name in TEAM[rng.randi() % TEAM.size()]:
			if not Data.item(name).is_empty():
				shop.append(name)
		return
	shop.append(it)
	for name in SETS.get(it, []):
		if not Data.item(name).is_empty():
			shop.append(name)


## SetupTravelShop_AdjustSlotRarities: past 4200 tries tier 0 comes up every
## time, past 4300 tier 1, and so on to tier 5 past 4700.
static func _adjust(attempt: int, r: Array) -> void:
	for tier in r.size():
		if r[tier] > 1 and attempt > 4200 + tier * 100:
			r[tier] = 1
