class_name Shimmer
## What Shimmer does to an item lying in it (Terraria's WorldItem.UpdateShimmer
## and GetShimmered, ShimmerTransforms): after 1.5 s in it, under it all, it
##   - turns into another item (ItemID.Sets.ShimmerTransformToItem: Data.shimmer);
##   - or, made by a recipe, comes apart into what it was made of, as many
##     times as its stack holds the recipe's output (its last recipe that isn't
##     notDecraftable; the world evil's own where it has one). At a Placed
##     Bottle each ingredient is lost 1 time in 3. Recipes using Bones wait
##     for Skeletron, Lihzahrd Bricks for Golem;
##   - coins go into your coin luck (Player.AddCoinLuck: a copper coin 1, a
##     silver 100, a gold 10,000, a platinum fills it), if you're near;
##   - a Slime Crown starts the Slime Rain (one of the stack);
##   - a caught critter is let go, as its shimmer form (most become
##     Faelings: NPC.SHIMMER_TO_FAELING), up to 50 of the stack at a time,
##     faded out at first (shimmerTransparency 1).
## What comes out rises to the top and hangs there, glowing, until you take it.
## Not here yet: Moon Lord's items.

## Critters let go at a time from a stack.
const CRITTERS_AT_ONCE := 50

## Seconds an item must lie in it (shimmerTime 0.01 a tick to 0.9).
const TIME := 1.5
## Coin luck a coin gives (Player.AddCoinLuck).
const COIN_LUCK := {"CopperCoin": 1, "SilverCoin": 100, "GoldCoin": 10000, "PlatinumCoin": 1000000}
## How near you must be for coins to count: Terraria's 1000 px.
const COIN_REACH := 1000.0 / 24.0
## Decrafted items fly out sideways at k px a tick for the kth (SpawnShimmeredItem).
const PX_TICK := 60.0 / 24.0


## The item it's shimmered as (Sets.ShimmerCountsAsItem, and for coming apart
## ShimmerCountsAsItemForDecraft).
static func equivalent(item: String, decraft := false) -> String:
	if decraft and Data.shimmer.get("counts_as_decraft", {}).has(item):
		return Data.shimmer.counts_as_decraft[item]
	return Data.shimmer.get("counts_as", {}).get(item, item)


## What it turns into, or "" (none, the Moon Lord's not beaten, or not in
## this game).
static func transform_of(item: String) -> String:
	var e := equivalent(item)
	var to: String = Data.shimmer.get("transform", {}).get(e, "")
	if e in Data.shimmer.get("post_moonlord", []) or not Data.items.has(to):
		return ""
	return to


## The recipe it comes apart by, or {} (none, locked, or what it gives isn't
## in this game).
static func decraft_of(item: String, game) -> Dictionary:
	var d: Dictionary = Data.decrafts.get(equivalent(item, true), {})
	var crimson: bool = game != null and game.town != null and game.town.world_evil() == "crimson"
	var r: Dictionary = d.get("crimson" if crimson and d.has("crimson") else ("corruption" if not crimson and d.has("corruption") else "any"), {})
	if r.is_empty():
		return {}
	for ing in r.ingredients:
		if ing[0] == "Bone" and (game == null or not game.defeated_bosses.has("SkeletronHead")):
			return {}
		if ing[0] == "LihzahrdBrick":
			return {}
	for ing in r.get("shimmer", r.ingredients):
		if not Data.items.has(ing[0]):
			return {}
	return r


## Whether Shimmer does anything to `count` of it (Item.CanShimmer).
static func can_shimmer(item: String, count: int, game) -> bool:
	if COIN_LUCK.has(item) or transform_of(item) != "":
		return true
	if item == "SlimeCrown":
		return game != null and not game.sky.slime_rain
	if Data.item(item).has("release"):
		return true
	var r := decraft_of(item, game)
	return not r.is_empty() and count >= int(r.count)


## Shimmers an item lying in it (GetShimmered). Returns false when nothing
## happened.
static func apply(drop: ItemDrop, game) -> bool:
	var pos := drop.global_position
	var item := drop.item
	if COIN_LUCK.has(item):
		var n := mini(drop.count, 1) if item == "PlatinumCoin" else drop.count
		var p = game.player
		if p.alive and p.global_position.distance_to(pos) < COIN_REACH:
			p.add_coin_luck(n * int(COIN_LUCK[item]))
		drop.count = 0
	elif transform_of(item) != "":
		drop.setup_item(transform_of(item))
		drop.shimmered = true
	elif item == "SlimeCrown":
		if game.sky.slime_rain:
			return false
		game.sky.start_slime_rain()
		drop.count -= 1
		drop.shimmered = drop.count > 0
	elif Data.item(item).has("release"):
		var def := Data.item(item)
		var kind: String = def.release
		kind = NPC.SHIMMER_TO_NPC.get(kind, "Shimmerfly" if kind in NPC.SHIMMER_TO_FAELING else kind)
		for i in mini(drop.count, CRITTERS_AT_ONCE):
			var npc: NPC = game.spawn_npc(kind, pos)
			if npc != null:
				npc.released = true
				npc.shimmer_fade = 1.0
				if kind == def.release and def.has("variant"):
					npc.variant = int(def.variant)
		drop.count -= mini(drop.count, CRITTERS_AT_ONCE)
		drop.shimmered = drop.count > 0
	else:
		var r := decraft_of(item, game)
		if r.is_empty():
			return false
		var times := drop.count / int(r.count)
		if times <= 0:
			return false
		var k := 0
		for ing in r.get("shimmer", r.ingredients):
			var n: int = times * int(ing[1])
			if r.alchemy:
				for i in times * int(ing[1]):
					if randi() % 3 == 0:
						n -= 1
			var cap := maxi(1, int(Data.item(ing[0]).get("max_stack", 9999)))
			while n > 0:
				var part := mini(n, cap)
				n -= part
				k += 1
				# Out to alternate sides, faster each (here round you).
				var side := Vector3(1, 0, 0).rotated(Vector3.UP, randf() * TAU)
				var d: ItemDrop = game.spawn_item_drop(ing[0], part, pos, side * k * (k % 2 * 2 - 1) * PX_TICK)
				if d != null:
					d.shimmered = true
					d.shimmer_time = 1.0
		drop.count -= times * int(r.count)
	drop.shimmer_time = 1.0 if drop.count > 0 else 0.0
	drop.velocity *= 0.1
	effect(game, pos)
	if drop.count <= 0:
		drop.queue_free()
	return true


## The sound and sparkles (WorldItem.ShimmerEffect: Item_176, 20 dust 309 in
## its four colours).
static func effect(game, pos: Vector3) -> void:
	Audio.play_at("Item_176", pos)
	for c in [Color8(255, 255, 210), Color8(190, 245, 255), Color8(255, 150, 255), Color8(190, 175, 255)]:
		game.spawn_dust(pos, c, 5)
