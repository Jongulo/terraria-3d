class_name Town
extends Node
## Terraria's town NPCs. The Guide is there from the start; the others move in
## once what brings them is true (npcs.json "town": "arrives") and there's a
## free home (Housing) near you, one at a time, and come back whenever they
## have no one in their place (they're invulnerable here, so only once). Each
## has a name from Terraria's lists and a home; without one they wander where
## they are until a house turns up.

## Seconds between housing checks (Terraria checks every few seconds too).
const CHECK_INTERVAL := 4.0
## In the order they can move in.
const ROSTER := ["Guide", "Merchant", "Nurse", "ArmsDealer", "Dryad", "Demolitionist", "GoblinTinkerer", "Angler"]

var game: Game
## Kind -> the NPC living here.
var residents := {}
## Kinds that have moved in before.
var arrived := {}
## The Angler's quest: today's fish (AnglerQuests.pick) and whether it's
## been handed in today (Terraria's anglerQuestFinished).
var angler_quest := ""
var angler_done := false
var _angler_rng := RandomNumberGenerator.new()
var _timer := 1.0


func _process(delta: float) -> void:
	if game == null or game.state != Game.State.PLAYING:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = CHECK_INTERVAL
		update_housing()


## The Guide, at the start of a new world (homeless, by the spawn point).
func start_new() -> void:
	if not residents.has("Guide"):
		var at := game.player.spawn_point + Vector3(3, 0, 2)
		at.y = game.world.surface_y(floori(at.x), floori(at.z)) + 1
		move_in("Guide", at)


## Whether what brings this NPC is true now (or they've lived here before).
func wants_to_come(kind: String) -> bool:
	if arrived.has(kind):
		return true
	var p := game.player
	match Data.npcs[kind].get("town", {}).get("arrives", ""):
		"":
			return true
		"money":
			return p.inventory.money() >= 5000
		"life":
			return residents.has("Merchant") and p.life_max > 100
		"gun":
			return p.inventory.slots.any(func(s): return s != null and (s.item == "MusketBall" or Data.item(s.item).get("ammo") == "MusketBall"))
		"boss":
			return not game.defeated_bosses.is_empty()
		"explosive":
			return p.inventory.slots.any(func(s): return s != null and Data.item(s.item).has("explosive"))
		"freed":
			return false  # only once you've freed him (free_goblin)
		"woken":
			return false  # only once you've woken him (wake_angler)
	return false


## Checks the homes near you: residents whose home is gone lose it, the
## homeless take free homes, and one newcomer moves into a free home.
func update_housing() -> void:
	prune()
	for kind in residents:
		var npc: NPC = residents[kind]
		if npc.home_key != "":
			var h := Housing.check(game.world, npc.home_spot)
			if not h.ok or h.key != npc.home_key:
				npc.home_key = ""
	var homes := Housing.find_homes(game.world, Vector3i(game.player.global_position.floor()))
	var free := homes.filter(func(h): return not residents.values().any(func(n): return n.home_key == h.key))
	for kind in residents:
		var npc: NPC = residents[kind]
		if npc.home_key == "" and not free.is_empty():
			var h: Dictionary = free.pop_front()
			npc.home_key = h.key
			npc.home_spot = h.spot
	if free.is_empty():
		return
	for kind in ROSTER:
		if not residents.has(kind) and wants_to_come(kind):
			var h: Dictionary = free.pop_front()
			var npc := move_in(kind, Vector3(h.spot) + Vector3(0.5, 0, 0.5))
			npc.home_key = h.key
			npc.home_spot = h.spot
			game.message("%s has arrived!" % npc.title(), Color(0.35, 0.6, 1.0))
			return


## Forgets residents that are gone (removed from the world); they move back
## in when a home is free, like Terraria's town NPCs after dying.
func prune() -> void:
	for kind in residents.keys():
		if not is_instance_valid(residents[kind]) or residents[kind].is_queued_for_deletion():
			residents.erase(kind)


## Brings a town NPC into the world at `pos`, with a name from Terraria's list.
func move_in(kind: String, pos: Vector3, npc_name := "") -> NPC:
	var npc := game.spawn_npc(kind, pos)
	if npc_name == "":
		var names: Array = Assets.ids.get("names", {}).get("town", {}).get(kind + "Names", [])
		npc_name = names[randi() % names.size()] if not names.is_empty() else Assets.npc_name(kind)
	npc.display_name = npc_name
	residents[kind] = npc
	arrived[kind] = true
	return npc


## Freeing the Bound Goblin (Terraria's): he's the Goblin Tinkerer from now
## on, homeless where he stood until a house is free (then he moves in, and
## comes back like the others).
func free_goblin(bound: NPC) -> NPC:
	var at := bound.global_position
	bound.queue_free()
	return move_in("GoblinTinkerer", at)


## Waking the Sleeping Angler (Terraria's: talking to him saves him): he's
## the Angler from now on, homeless where he floated until a house is free.
func wake_angler(sleeping: NPC) -> NPC:
	var at := sleeping.global_position
	sleeping.queue_free()
	if angler_quest == "":
		new_angler_quest()
	return move_in("Angler", at)


## Main.AnglerQuestSwap: a new fish for today (at dawn, and in a new world).
func new_angler_quest() -> void:
	angler_quest = AnglerQuests.pick(world_evil() == "crimson", not game.defeated_bosses.is_empty(), _angler_rng)
	angler_done = false


## Today's quest fish if it can bite (Projectile.FishingCheck_ProbeForQuestFish):
## the Angler lives here, it isn't handed in yet and you haven't one on you.
func quest_fish(player) -> String:
	if angler_quest == "" or angler_done or not residents.has("Angler") or player.inventory.count_of(angler_quest) > 0:
		return ""
	return angler_quest


## The Angler's Quest button (Main.NPCChatText_DoAnglerQuest): hands in
## today's fish if you've caught it (his rewards go in your inventory),
## else tells you what he wants. Returns what he says.
func angler_quest_chat() -> String:
	var p = game.player
	var text: Dictionary = Assets.ids.get("names", {}).get("town", {}).get("AnglerQuestText", {})
	var pick := func(prefix: String) -> String:
		var lines := []
		for k in text:
			if k.begins_with(prefix):
				var t := NPC.fill(text[k])
				if t != "":
					lines.append(t)
		return lines[randi() % lines.size()] if not lines.is_empty() else "..."
	if angler_quest == "":
		new_angler_quest()
	if not angler_done and p.inventory.remove(angler_quest, 1):
		p.angler_quests += 1
		var owned := []
		for inv in [p.inventory, p.armor, p.accessories]:
			for s in inv.slots:
				if s != null:
					owned.append(s.item)
		for r in AnglerQuests.rewards(p.angler_quests, angler_quest, owned, _angler_rng):
			var left: int = p.inventory.add(r[0], r[1], Prefixes.roll(Data.item(r[0])) if r[1] == 1 else 0)
			if left > 0:
				game.spawn_item(r[0], left, p.center())
		angler_done = true
		Audio.play("Coin_*")
		return pick.call("TurnIn_")
	if angler_done:
		return pick.call("NoQuest_")
	return NPC.fill(text.get("Quest_" + angler_quest, "..."))


## The world's evil ("corruption" or "crimson"), from its surface.
func world_evil() -> String:
	var share := evil_share()
	return "crimson" if share.crimson > share.corruption else "corruption"


## How much of the world's surface is Corruption and Crimson (percent), from
## a grid of columns: the Dryad's Status.
func evil_share() -> Dictionary:
	if not _evil.is_empty() and Time.get_ticks_msec() - _evil_at < 30000:
		return _evil
	var w := game.world
	var size := w.get_size()
	var step := maxi(4, size.x / 96)
	var counts := {"corruption": 0, "crimson": 0}
	var total := 0
	var ids := {}
	for b in counts:
		for id in Data.biome_blocks.get(b, []):
			ids[id] = b
	for x in range(step / 2, size.x, step):
		for z in range(step / 2, size.z, step):
			var y := w.surface_y(x, z)
			if y < 0 or (game.has_ocean and game.in_ocean(Vector3(x, y, z))):
				continue
			total += 1
			var b = ids.get(w.get_block(Vector3i(x, y, z)))
			if b != null:
				counts[b] += 1
	for b in counts:
		counts[b] = 100.0 * counts[b] / maxi(1, total)
	_evil = counts
	_evil_at = Time.get_ticks_msec()
	return _evil

var _evil := {}
var _evil_at := 0


## The Dryad's Status: Terraria's words for how corrupt the world is.
func dryad_status() -> String:
	var text: Dictionary = Assets.ids.get("names", {}).get("town", {}).get("DryadSpecialText", {})
	var share := evil_share()
	var c := roundi(share.corruption)
	var r := roundi(share.crimson)
	var line: String
	if c == 0 and r == 0:
		line = text.get("WorldStatusPure", "{0} is completely pure. You have done an amazing job!")
	elif r == 0:
		line = text.get("WorldStatusCorrupt", "{0} is {1}% corrupt.").replace("{1}", str(c))
	elif c == 0:
		line = text.get("WorldStatusCrimson", "{0} is {1}% crimson.").replace("{1}", str(r))
	else:
		line = text.get("WorldStatusCorruptCrimson", "{0} is {1}% corrupt and {2}% crimson.").replace("{1}", str(c)).replace("{2}", str(r))
	line = line.replace("{0}", game.world_name)
	var evil := c + r
	if evil > 0:
		var desc: String = "WorldDescriptionClose" if evil < 5 else ("WorldDescriptionWork" if evil < 20 else "WorldDescriptionGrim")
		line += " " + text.get(desc, "")
	return line


## What the Nurse charges to heal you: a copper per life missing and a silver
## for being on fire, more the more bosses you've beaten (like Terraria's).
func heal_price() -> int:
	var p := game.player
	var price := (p.life_max - p.life) + (100 if p.on_fire > 0.0 else 0)
	return price * (1 + game.defeated_bosses.size())


## The Nurse's Heal button: heals you if you can pay; her answer.
func nurse_heal() -> String:
	var p := game.player
	var price := heal_price()
	var line := 0
	if price <= 0:
		line = [55, 56, 57][randi() % 3]
	elif not p.inventory.pay(price):
		line = [52, 53, 54][randi() % 3]
	else:
		p.heal(p.life_max - p.life)
		p.on_fire = 0.0
		Audio.play("Item_4")
		line = [227, 228, 229, 230][randi() % 4]
	return NPC.dialog(line)


## Terraria's {Guide}, {Nurse}... in chat lines: that resident's name.
func name_of(kind: String) -> String:
	return residents[kind].display_name if residents.has(kind) and is_instance_valid(residents[kind]) else ""


func save_state() -> Dictionary:
	prune()
	var list := []
	for kind in residents:
		var n: NPC = residents[kind]
		var p := n.global_position
		list.append({"kind": kind, "name": n.display_name, "pos": [p.x, p.y, p.z], "home": n.home_key,
				"spot": [n.home_spot.x, n.home_spot.y, n.home_spot.z]})
	return {"residents": list, "arrived": arrived.keys(), "angler_quest": angler_quest, "angler_done": angler_done}


func load_state(d: Dictionary) -> void:
	for r in d.get("residents", []):
		var p: Array = r.pos
		var npc := move_in(r.kind, Vector3(p[0], p[1], p[2]), r.name)
		npc.home_key = r.get("home", "")
		var s: Array = r.get("spot", [0, 0, 0])
		npc.home_spot = Vector3i(int(s[0]), int(s[1]), int(s[2]))
	for k in d.get("arrived", []):
		arrived[k] = true
	angler_quest = d.get("angler_quest", "")
	angler_done = d.get("angler_done", false)
