class_name Crates
extends RefCounted
## Opening fishing crates and oysters (right click in the inventory): ports
## of Terraria's Player.OpenFishingCrate and OpenOyster, roll for roll
## (Main.rand.Next(n) is randi_range(0, n - 1), Next(a, b) randi_range(a,
## b - 1)). There's no Hardmode here, so its extra loot never rolls. Items
## not in this game are left out (what they'd have taken is still used up,
## so the rest comes out as often as in Terraria).

const POTIONS_WOODEN := ["ObsidianSkinPotion", "SwiftnessPotion", "IronskinPotion", "NightOwlPotion", "ShinePotion",
		"HunterPotion", "GillsPotion", "MiningPotion", "HeartreachPotion", "TrapsightPotion"]
const POTIONS_IRON := ["ObsidianSkinPotion", "SpelunkerPotion", "HunterPotion", "GravitationPotion", "MiningPotion",
		"HeartreachPotion", "CalmingPotion", "FlipperPotion"]
const POTIONS_GOLDEN := ["ObsidianSkinPotion", "SpelunkerPotion", "GravitationPotion", "MiningPotion", "HeartreachPotion"]
const POTIONS_BIOME := ["ObsidianSkinPotion", "SpelunkerPotion", "HunterPotion", "GravitationPotion", "MiningPotion",
		"HeartreachPotion"]
const DUNGEON_PAINTINGS := ["GreatWave", "BoneWarp", "TheCreationoftheGuide", "TheCursedMan", "TheDestroyer",
		"PoweredbyBirds", "TheEyeSeestheEnd", "RemnantsofDevotion", "GloryoftheFire", "GoblinsPlayingPoker",
		"BloodMoonRising", "TheGuardiansGaze", "TheHangedMan", "Impact", "ThePersistencyofEyes", "Dryadisque",
		"TheScreamer", "SkellingtonJSkellingsworth", "SparkyPainting", "SomethingEvilisWatchingYou", "StarryNight",
		"TrioSuperHeroes", "TheTwinsHaveAwoken", "UnicornCrossingtheHallows", "FacingtheCerebralMastermind"]
const OASIS_PAINTINGS := ["DivineEye", "WatchfulAntlion", "BurningSpirit", "LifeAboveTheSand", "TheSandsOfSlime",
		"BandageBoy", "JawsOfDeath", "Oasis", "PrehistoryPreserved", "AncientTablet", "Uluru", "VisitingThePyramids",
		"SnakesIHateSnakes", "AndrewSphinx"]
const SKY_PAINTINGS := ["HighPitch", "BlessingfromTheHeavens", "Constellation", "SeeTheWorldForWhatItIs",
		"LoveisintheTrashSlot", "SunOrnament"]
const LAVA_PAINTINGS := ["HandEarth", "Darkness", "DemonsEye", "FlowingMagma", "DarkSoulReaper", "ImpFace",
		"LakeofFire", "TrappedGhost", "OminousPresence", "ShiningMoon", "Skelehead", "LivingGore"]

var _rng: RandomNumberGenerator
var _out: Array = []


## What opening `item` gives: [[item, count], ...] (only items in this game).
static func open(item: String, rng: RandomNumberGenerator) -> Array:
	var c := Crates.new()
	c._rng = rng
	if item == "Oyster":
		c._oyster()
	else:
		c._crate(item)
	return c._out


## Terraria's Main.rand.Next(n).
func _next(n: int) -> int:
	return _rng.randi_range(0, n - 1)


## Main.rand.Next(lo, hi): lo to hi - 1.
func _range(lo: int, hi: int) -> int:
	return _rng.randi_range(lo, hi - 1)


func _give(item: String, count := 1) -> void:
	if count > 0 and Data.items.has(item):
		_out.append([item, count])


func _oyster() -> void:
	if _next(4) == 0:
		if _next(10) == 0:
			_give("PinkPearl")
		elif _next(3) == 0:
			_give("BlackPearl")
		else:
			_give("WhitePearl")
	_give("ShuckedOyster")


func _crate(item: String) -> void:
	match item:
		"WoodenCrate":
			_wooden()
		"IronCrate":
			_iron()
		"GoldenCrate":
			_golden()
		_:
			_biome(item)


func _wooden() -> void:
	var more := true
	while more:
		if more and _next(40) == 0:
			_give("SailfishBoots")
			more = false
		if more and _next(40) == 0:
			_give("TsunamiInABottle")
			more = false
		if _next(20) == 0:
			_give(["Aglet", "ClimbingClaws", "PortableStool", "CordageGuide", "Radar", "PoisonBarb"][_next(6)])
			more = false
		if more and _next(50) == 0:
			_give("Extractinator")
			more = false
		if _next(7) == 0:
			if _next(3) == 0:
				_give("GoldCoin", _range(1, 6))
			else:
				_give("SilverCoin", _range(20, 91))
			more = false
		if _next(7) == 0:
			var ore: String = ["CopperOre", "TinOre", "IronOre", "LeadOre"][_next(4)]
			_next(2)  # (Hardmode ores)
			_give(ore, _range(4, 16))
			more = false
		elif _next(8) == 0:
			var bar: String = ["CopperBar", "TinBar", "IronBar", "LeadBar"][_next(4)]
			var n := _range(2, 6)
			_next(2)  # (Hardmode bars)
			_give(bar, n)
			more = false
		if _next(7) == 0:
			_give(POTIONS_WOODEN[_next(10)], _range(1, 4))
			more = false
	if _next(3) == 0:
		_give(["LesserHealingPotion", "LesserManaPotion"][_next(2)], _range(5, 16))
	if _next(3) == 0:
		_give("JourneymanBait" if _next(3) == 0 else "ApprenticeBait", _range(1, 5))


func _iron() -> void:
	var more := true
	while more:
		for a in [["GingerBeard", 25], ["TartarSauce", 20], ["FalconBlade", 15], ["SailfishBoots", 20], ["TsunamiInABottle", 20]]:
			if more and _next(a[1]) == 0:
				_give(a[0])
				more = false
		if _next(4) == 0:
			_give("GoldCoin", _range(5, 11))
			more = false
		if _next(6) == 0:
			var ore: String = ["CopperOre", "TinOre", "IronOre", "LeadOre", "SilverOre", "TungstenOre"][_next(6)]
			_next(2)
			_give(ore, _range(12, 22))
			more = false
		elif _next(4) == 0:
			var bar: String = ["CopperBar", "TinBar", "IronBar", "LeadBar", "SilverBar", "TungstenBar"][_next(6)]
			var n := _range(4, 8)
			_next(3)
			_give(bar, n)
			more = false
		if _next(4) == 0:
			_give(POTIONS_IRON[_next(8)], _range(2, 5))
			more = false
	if _next(2) == 0:
		_give(["HealingPotion", "ManaPotion"][_range(0, 2)], _range(5, 16))
	if _next(2) == 0:
		_give("MasterBait" if _next(3) == 0 else "JourneymanBait", _range(2, 5))


func _golden() -> void:
	var more := true
	while more:
		if more and _next(8) == 0:
			_give("LifeCrystal")
			more = false
		if more and _next(10) == 0:
			_give("HardySaddle")
			more = false
		if _next(3) == 0:
			_give("GoldCoin", _range(8, 21))
			more = false
		if _next(5) == 0:
			var ore: String = ["SilverOre", "TungstenOre", "GoldOre", "PlatinumOre"][_next(4)]
			_next(2)
			_give(ore, _range(25, 35))
			more = false
		elif _next(3) == 0:
			var bar: String = ["SilverBar", "GoldBar", "TungstenBar", "PlatinumBar"][_next(4)]
			_next(3)
			_give(bar, _range(8, 12))
			more = false
	if _next(3) == 0:
		_give(POTIONS_GOLDEN[_next(5)], _range(2, 6))
	if _next(2) == 0:
		_give(["HealingPotion", "ManaPotion"][_range(0, 2)], _range(5, 21))
	if _next(3) != 0:
		_give("MasterBait", _range(3, 8))
	if _next(30) == 0:
		_give("EnchantedSword")
	_next(15)  # (Hardmode: another Enchanted Sword)


## The biome crates: one of the biome's treasures, then what they all share.
func _biome(item: String) -> void:
	var lava := item == "LavaCrate"
	var more := true
	while more:
		if item == "OceanCrate" and more and _next(1) == 0:
			var k := _next(4)
			if _next(10) == 0:
				_give("WaterWalkingBoots")
			else:
				_give(["BreathingReed", "FloatingTube", "Trident", "Flipper"][k])
			more = false
		if item == "CorruptFishingCrate" and more and _next(1) == 0:
			_give(["BallOHurt", "BandofStarpower", "Musket", "ShadowOrb", "Vilethorn"][_next(5)])
			more = false
		if item == "CrimsonFishingCrate" and more and _next(1) == 0:
			_give(["TheUndertaker", "TheRottedFork", "CrimsonRod", "PanicNecklace", "CrimsonHeart"][_next(5)])
			more = false
		if item == "DungeonFishingCrate" and more and _next(1) == 0:
			_give("LockBox")
			more = false
			if _next(2) == 0:
				_give("Book", _range(5, 16))
			if _next(2) == 0:
				_give(["BlueBrick", "GreenBrick", "PinkBrick"][_next(3)], _range(25, 51))
		if item == "FloatingIslandFishingCrate" and more and _next(1) == 0:
			_give(["LuckyHorseshoe", "Starfury", "ShinyRedBalloon", "CelestialMagnet"][_next(4)])
			more = false
		if item == "JungleFishingCrate" and more and _next(1) == 0:
			if _next(20) == 0:
				_next(5)
				_give("FlowerBoots")
			else:
				_give(["AnkletoftheWind", "Boomstick", "FeralClaws", "StaffofRegrowth", "FiberglassFishingPole"][_next(5)])
			more = false
		if item == "FrozenCrate" and more and _next(1) == 0:
			_give(["IceBoomerang", "IceBlade", "IceSkates", "SnowballCannon", "BlizzardinaBottle", "FlurryBoots", "GlacierFang"][_next(7)])
			more = false
		if item == "OasisCrate":
			if more and _next(1) == 0:
				_give(["AncientChisel", "ScarabFishingRod", "SandBoots", "ThunderSpear", "ThunderStaff", "CatBast",
						"MysticCoilSnake", "MagicConch"][_next(8)])
				more = false
			if _next(4) == 0:
				_give("ScarabBomb", _range(4, 7))
				more = false
			if _next(2) == 0:
				_give("FossilOre", _range(10, 17))
				more = false
			if _next(35) == 0:
				_give("SandstorminaBottle")
				more = false
		if lava:
			if more and _next(1) == 0:
				if _next(20) == 0:
					_next(5)
					_give("LavaCharm")
				else:
					_give(["FlameWakerBoots", "SuperheatedBlood", "LavaFishbowl", "LavaFishingHook", "VolcanoSmall"][_next(5)])
				more = false
				if _next(4) == 0:
					_give("PotSuspended", 2)
			_give("ObsidianLockbox")
			more = false
			if _next(3) == 0:
				_give("WetBomb", _range(7, 11))
			if _next(2) == 0:
				_give(["PottedLavaPlantPalm", "PottedLavaPlantBush", "PottedLavaPlantBramble", "PottedLavaPlantBulb",
						"PottedLavaPlantTendrils"][_next(5)])
		if _next(4) == 0:
			_give("GoldCoin", _range(5, 13))
			more = false
		if _next(7) == 0:
			var ore: String = ["CopperOre", "TinOre", "IronOre", "LeadOre", "SilverOre", "TungstenOre", "GoldOre", "PlatinumOre"][_next(8)]
			if lava:
				ore = "Hellstone"
			_next(2)
			_give(ore, _range(20, 36))
			more = false
		if _next(4) == 0:
			var bar: String = ["IronBar", "SilverBar", "GoldBar", "LeadBar", "TungstenBar", "PlatinumBar"][_next(6)]
			var n := _range(6, 17)
			if lava:
				bar = "HellstoneBar"
			_next(3)
			_give(bar, n)
			more = false
	if _next(4) == 0:
		_give(POTIONS_BIOME[_next(6)], _range(2, 5))
	if _next(2) == 0:
		_give(["HealingPotion", "ManaPotion"][_range(0, 2)], _range(5, 18))
	if _next(2) == 0:
		_give("MasterBait" if _next(2) == 0 else "JourneymanBait", _range(2, 7))
	match item:
		"OceanCrate":
			if _next(5) == 0:
				_give("OfSeaAndDreams")
			if _next(3) == 0:
				_give("ShellPileBlock", _range(20, 51))
			if _next(10) == 0:
				_give("SandcastleBucket")
			if _next(10) == 0:
				_give("SharkBait")
		"DungeonFishingCrate":
			if _next(2) == 0:
				_give(DUNGEON_PAINTINGS[_next(25)])
		"JungleFishingCrate":
			if _next(3) == 0:
				_give("BambooBlock", _range(20, 51))
			if _next(20) == 0:
				_give("Seaweed")
		"FrozenCrate":
			if _next(20) == 0:
				_give("Fish")
		"OasisCrate":
			if _next(2) == 0:
				_give(OASIS_PAINTINGS[_next(14)])
		"FloatingIslandFishingCrate":
			if _next(2) == 0:
				_give(SKY_PAINTINGS[_next(6)])
			if _next(2) == 0:
				_give("Cloud", _range(50, 101))
			if _next(40) == 0:
				_give("CreativeWings")
		"LavaCrate":
			if _next(2) == 0:
				_give(LAVA_PAINTINGS[_next(12)])
			for extra in ["Hellforge", "HellMinecart", "OrnateShadowKey", "HellCake"]:
				if _next(20) == 0:
					_give(extra)
