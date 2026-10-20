class_name AnglerQuests
extends RefCounted
## Terraria's Angler: the fish he wants today (Main.anglerQuestItemNetIDs,
## picked each dawn by AnglerQuestSwap) and what he gives for it
## (Player.GetAnglerReward), roll for roll. The quest fish themselves are in
## Terraria's catch table (Fishing: a quest rule only bites while it's
## today's fish, the Angler lives here and you haven't got one yet). No
## Hardmode here, so its fish (Pixiefish, Mirage Fish...) never come up and
## its rewards never roll. Rewards not in this game are left out (the rolls
## for them still happen, so the rest come as often as in Terraria).

## Main.anglerQuestItemNetIDs, in order.
const FISH := ["Batfish", "BumblebeeTuna", "Catfish", "Cloudfish", "Cursedfish", "Dirtfish", "DynamiteFish",
		"EaterofPlankton", "FallenStarfish", "TheFishofCthulu", "Fishotron", "Harpyfish", "Hungerfish", "Ichorfish",
		"Jewelfish", "MirageFish", "MutantFlinxfin", "Pengfish", "Pixiefish", "Spiderfish", "TundraTrout", "UnicornFish",
		"GuideVoodooFish", "Wyverntail", "ZombieFish", "AmanitaFungifin", "Angelfish", "BloodyManowar", "Bonefish",
		"Bunnyfish", "CapnTunabeard", "Clownfish", "DemonicHellfish", "Derpfish", "Fishron", "InfectedScabbardfish",
		"Mudfish", "Slimefish", "TropicalBarracuda", "ScarabFish", "ScorpioFish"]
## Hardmode's quest fish (AnglerQuestSwap rerolls them before it).
const HARDMODE_FISH := ["Cursedfish", "Hungerfish", "Ichorfish", "MirageFish", "Pixiefish", "UnicornFish", "Wyverntail",
		"CapnTunabeard", "Derpfish", "Fishron"]
## The sky's fish: only once a boss is beaten (or Hardmode).
const SKY_FISH := ["Angelfish", "Cloudfish", "Wyverntail"]
## The accessories he gives (GetAnglerReward_MainReward's pool), one at a
## time till you have each.
const ACCESSORIES := ["HighTestFishingLine", "AnglerEarring", "TackleBox", "FishermansGuide", "WeatherRadio", "Sextant", "FishingBobber"]
## What you already have that counts for the pool (RemoveAnglerAccOptionsFromRewardPool).
const COUNTS_AS := {
	"AnglerTackleBag": ["HighTestFishingLine", "TackleBox", "AnglerEarring"],
	"LavaproofTackleBag": ["HighTestFishingLine", "TackleBox", "AnglerEarring"],
	"FishFinder": ["FishermansGuide", "WeatherRadio", "Sextant"],
	"GPS": ["FishermansGuide", "WeatherRadio", "Sextant"],
	"GoblinTech": ["FishermansGuide", "WeatherRadio", "Sextant"],
	"REK": ["FishermansGuide", "WeatherRadio", "Sextant"],
	"PDA": ["FishermansGuide", "WeatherRadio", "Sextant"],
	"CellPhone": ["FishermansGuide", "WeatherRadio", "Sextant"],
}
## Quest counts that always give these (the 5th, 10th...).
const MILESTONES := {5: "FuzzyCarrot", 10: "AnglerHat", 15: "AnglerVest", 20: "AnglerPants", 25: "BottomlessBucket", 30: "GoldenFishingRod"}
const DECORATIONS := ["LifePreserver", "ShipsWheel", "CompassRose", "WallAnchor", "PillaginMePixels", "TreasureMap",
		"GoldfishTrophy", "BunnyfishTrophy", "SwordfishTrophy", "SharkteethTrophy", "ShipInABottle", "SeaweedPlanter",
		"NotSoLostInParadise", "Crustography", "Fangs", "WhatLurksBelow", "CouchGag", "SilentFish", "TheDuke"]


## Terraria's UnifiedRandom.Next(n) (0 for n <= 0, like .NET's).
static func _next(rng: RandomNumberGenerator, n: int) -> int:
	return 0 if n <= 1 else rng.randi_range(0, n - 1)


static func f32(x: float) -> float:
	var a := PackedFloat32Array([x])
	return a[0]


## Main.AnglerQuestSwap: today's fish, rerolled till it suits the world
## (its evil, Hardmode, a boss beaten for the sky's).
static func pick(crimson: bool, boss_beaten: bool, rng: RandomNumberGenerator) -> String:
	while true:
		var fish: String = FISH[rng.randi_range(0, FISH.size() - 1)]
		if fish in HARDMODE_FISH:
			continue
		if fish == "EaterofPlankton" and crimson:
			continue
		if fish == "BloodyManowar" and not crimson:
			continue
		if fish == "InfectedScabbardfish" and crimson:
			continue
		if fish in SKY_FISH and not boss_beaten:
			continue
		return fish
	return FISH[0]


## Player.GetAnglerRewardRarityMultiplier: rarer rewards come likelier the
## more quests you've done.
static func rarity_multiplier(quests: int) -> float:
	var m := 1.0
	if quests <= 50:
		m = f32(1.0 - f32(quests * f32(0.01)))
	elif quests <= 100:
		m = f32(0.5 - f32((quests - 50) * f32(0.005)))
	elif quests <= 150:
		m = f32(0.25 - f32((quests - 100) * f32(0.002)))
	else:
		m = 0.15
	return f32(m * f32(0.9))


## Player.GetAnglerReward, for the `quests`th quest done (counted already)
## handing in `fish`; `owned` is what you have (for the accessory pool).
## [[item, count], ...] (only items in this game).
static func rewards(quests: int, fish: String, owned: Array, rng: RandomNumberGenerator) -> Array:
	var out := []
	var give := func(item: String, n := 1) -> void:
		if n > 0 and Data.items.has(item):
			out.append([item, n])
	var mult := rarity_multiplier(quests)
	# The main reward.
	var main := ""
	var count := 1
	if MILESTONES.has(quests):
		main = MILESTONES[quests]
	elif fish == "BumblebeeTuna" and _next(rng, 2) == 0:
		main = "BottomlessHoneyBucket" if _next(rng, 2) == 0 else "HoneyAbsorbantSponge"
	else:
		var keep := 1.0
		for i in 3:
			keep = f32(keep * f32(1.0 - 1.0 / float(int(f32(40.0 * mult)))))
		for i in 3:
			keep = f32(keep * f32(1.0 - 1.0 / float(int(f32(30.0 * mult)))))
		keep = f32(keep * f32(1.0 - 1.0 / float(int(f32(25.0 * mult)))))
		var acc_chance := f32(f32(1.0 - keep) * f32(0.8))
		var rolls := [[75, 250.0, "GoldenFishingRod"], [10, 70.0, "BottomlessBucket"], [10, 70.0, "SuperAbsorbantSponge"],
				[-1, 80.0, "GoldenBugNet"], [-1, 60.0, "FishHook"], [-1, 60.0, "FishMinecart"], [-1, 80.0, "SeashellHairpin"],
				[-1, 80.0, "FishCostumeMask"]]
		for r in rolls:
			if quests > r[0] and _next(rng, int(f32(r[1] * mult))) == 0:
				main = r[2]
				break
		if main == "":
			# DropAnglerAccByMissing: an accessory you haven't got yet...
			var missing := ACCESSORIES.duplicate()
			for item in owned:
				for gone in COUNTS_AS.get(item, [item]):
					missing.erase(gone)
			var pool_left := not missing.is_empty()
			if pool_left and rng.randf() < acc_chance:
				main = missing[rng.randi_range(0, missing.size() - 1)]
			elif not pool_left and rng.randf() < acc_chance:
				main = ACCESSORIES[rng.randi_range(0, ACCESSORIES.size() - 1)]
			else:
				# ...else a few fishing potions.
				main = ["FishingPotion", "SonarPotion", "CratePotion"][_next(rng, 3)]
				count = rng.randi_range(2, 5)
	give.call(main, count)
	if main == "SeashellHairpin":
		give.call("MermaidAdornment")
		give.call("MermaidTail")
	elif main == "FishCostumeMask":
		give.call("FishCostumeShirt")
		give.call("FishCostumeFinskirt")
	# A decoration, likelier with more quests done.
	var deco_chance: float = lerpf(1.0 - mult, 1.0, minf(1.0, quests / 100.0))
	if deco_chance >= 1.0 or rng.randf() <= deco_chance:
		give.call(DECORATIONS[_next(rng, DECORATIONS.size())])
	# Money: more with more quests.
	var money := (quests + 50) / 2
	money = int(f32(float(money * rng.randi_range(50, 200)) * f32(0.015)))
	money = int(money * 1.5)
	if money > 100:
		give.call("GoldCoin", clampi(money / 100, 1, 10))
	else:
		give.call("SilverCoin", clampi(money, 1, 99))
	# Bait, half the time or so.
	if _next(rng, int(f32(100.0 * mult))) <= 50:
		var bait := "ApprenticeBait"
		if _next(rng, int(f32(15.0 * mult))) == 0:
			bait = "MasterBait"
		elif _next(rng, int(f32(5.0 * mult))) == 0:
			bait = "JourneymanBait"
		var n := 1
		for d in [25, 50, 100, 150, 200, 250]:
			if _next(rng, d) <= quests:
				n += 1
		give.call(bait, n)
	return out
