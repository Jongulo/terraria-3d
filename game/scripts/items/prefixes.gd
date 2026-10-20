class_name Prefixes
extends RefCounted
## Terraria's item prefixes (modifiers: "Legendary", "Warding"...), from
## data/prefixes.json. A stack carries its prefix ({"item", "count",
## "prefix"}); Data.item_of(stack) is its definition with the prefix applied
## (Prefixes.of). Terraria's Item.Prefix: crafted items, enemy and tile drops
## and chest loot roll one (NATURAL), the Goblin Tinkerer rerolls (REFORGE);
## shop items have none. Its sums are in 32-bit floats and Math.Round rounds
## halves to even; both are kept so the numbers come out as Terraria's.

## Item.Prefix(-1): a quarter of the time none; the reduced ones kept 1 in 3.
const NATURAL := -1
## Item.Prefix(-2): always one.
const REFORGE := -2

static var _data := {}
## Terraria item id -> its class ("swords", "guns_bows"...).
static var _class_of := {}
static var _no_prefix := {}
## "item#prefix" -> the prefixed definition.
static var _cache := {}


static func data() -> Dictionary:
	if _data.is_empty():
		var f := FileAccess.open("res://data/prefixes.json", FileAccess.READ)
		_data = JSON.parse_string(f.get_as_text())
		# (JSON numbers are floats; prefixes are compared as ints.)
		for k in _data.rollable:
			_data.rollable[k] = _data.rollable[k].map(func(x): return int(x))
		_data.reduced_natural_chance = _data.reduced_natural_chance.map(func(x): return int(x))
		# First class wins, in Terraria's order (GetRollablePrefixes).
		var order: Array = _data.order
		for i in range(order.size() - 1, -1, -1):
			for id in _data.classes[order[i]]:
				_class_of[int(id)] = order[i]
		for id in _data.no_prefix:
			_no_prefix[int(id)] = true
	return _data


## The prefixes an item can have ([] if none: Item.GetRollablePrefixes).
static func rollable(def: Dictionary) -> Array:
	var d := data()
	var id := int(def.get("id", 0))
	if _class_of.has(id):
		return d.rollable[_class_of[id]]
	if def.get("type") == "accessory" and not _no_prefix.has(id):
		return d.rollable.accessories
	return []


static func can_have(item: String) -> bool:
	return not rollable(Data.item(item)).is_empty()


## The prefix's English name ("Legendary"; Deadly2 is "Deadly" too).
static func prefix_name(pre: int) -> String:
	var ids: Dictionary = Assets.ids.get("PrefixID", {})
	for key in ids:
		if int(ids[key]) == pre:
			return Assets.ids.get("names", {}).get("prefixes", {}).get(key, key)
	return ""


## Item.TryGetPrefixStatMultipliersForItem: the prefix's multipliers for this
## item and its value multiplier, or {} if it can't have it (it would leave
## the damage, speed or mana as they are, or add knockback to none).
static func multipliers(def: Dictionary, pre: int) -> Dictionary:
	var s: Dictionary = data().stats.get(str(pre), {})
	var m := {}
	for k in ["damage", "knockback", "speed", "size", "velocity", "mana"]:
		m[k] = f32(float(s.get(k, 1.0)))
	for k in ["crit", "tag_damage", "armor_pen"]:
		m[k] = int(s.get(k, 0))
	var v := 1.0
	for x in [m.damage, f32(2.0 - m.speed), f32(2.0 - m.mana), m.size, m.knockback, m.velocity,
			f32(1.0 + f32(m.crit * f32(0.02))), f32(1.0 + f32(m.armor_pen * f32(0.015))), f32(1.0 + f32(m.tag_damage * f32(0.03)))]:
		v = f32(v * x)
	v = f32(v * f32(float(data().accessory_value.get(str(pre), 1.0))))
	m["value"] = v
	if m.damage != 1.0 and _scaled(def.get("damage", 0), m.damage) == int(def.get("damage", 0)):
		return {}
	var anim := int(def.get("use_animation", def.get("use_time", 0)))
	if m.speed != 1.0 and _scaled(anim, m.speed) == anim:
		return {}
	if m.mana != 1.0 and _scaled(def.get("mana", 0), m.mana) == int(def.get("mana", 0)):
		return {}
	if m.knockback != 1.0 and float(def.get("knockback", 0)) == 0.0:
		return {}
	return m


## Item.Prefix: rolls a prefix for the item (0: none; always 0 for one that
## can't have any).
static func roll(def: Dictionary, mode := NATURAL) -> int:
	var list := rollable(def)
	if list.is_empty():
		return 0
	var pre := mode
	for i in 1000:
		if pre == -1 and randi() % 4 == 0:
			pre = 0
		if mode < -1:
			pre = -1
		if pre < 0:
			pre = int(list[randi() % list.size()])
		if mode == NATURAL and pre in data().reduced_natural_chance and randi() % 3 != 0:
			pre = 0
		if pre != 0 and multipliers(def, pre).is_empty():
			pre = -1
			continue
		if mode == REFORGE and pre == 0:
			pre = -1
			continue
		return pre
	return 0


## The best value multiplier any of its prefixes gives (Item.BestPrefixValue:
## rolling it is a "best reforge").
static func best_value(def: Dictionary) -> float:
	var best := 0.0
	for pre in rollable(def):
		var m := multipliers(def, int(pre))
		if not m.is_empty():
			best = maxf(best, m.value)
	return best


## The item with its prefix: damage, use time, mana rounded like Terraria's,
## knockback, size (scale), velocity (shoot_speed), crit and value; "name"
## "Prefix Item". Accessory prefixes' stats are in bonus(), not here.
static func of(item: String, pre: int) -> Dictionary:
	var key := "%s#%d" % [item, pre]
	if _cache.has(key):
		return _cache[key]
	var def := Data.item(item)
	var m := multipliers(def, pre) if pre > 0 and not def.is_empty() else {}
	if m.is_empty():
		return def
	var d := def.duplicate()
	d["prefix"] = pre
	d["name"] = "%s %s" % [prefix_name(pre), def.get("name", item)]
	if def.has("damage"):
		d["damage"] = _scaled(def.damage, m.damage)
	for k in ["use_time", "use_animation", "mana"]:
		if def.has(k):
			d[k] = _scaled(def[k], m.speed if k != "mana" else m.mana)
	if def.has("knockback"):
		d["knockback"] = f32(float(def.knockback) * m.knockback)
	if def.has("shoot_speed"):
		d["shoot_speed"] = float(def.shoot_speed) * m.velocity
	if m.size != 1.0:
		d["scale"] = float(def.get("scale", 1.0)) * m.size
	if m.crit != 0:
		d["crit"] = int(def.get("crit", 0)) + m.crit
	if m.armor_pen != 0:
		d["armor_pen"] = int(def.get("armor_pen", 0)) + m.armor_pen
	d["value"] = int(f32(Data.value(item) * f32(m.value * m.value)))
	_cache[key] = d
	return d


## What an accessory's prefix adds to you, in the player's stat keys
## (Player.GrantPrefixBenefits: "defense", "mana_bonus", "crit", "damage",
## "move_speed", "melee_speed").
static func bonus(pre: int) -> Dictionary:
	return data().accessory.get(str(pre), {})


## The value of an item with this prefix (copper).
static func value(item: String, pre: int) -> int:
	return int(of(item, pre).get("value", Data.value(item))) if pre > 0 else Data.value(item)


## The tooltip lines its prefix adds, as Terraria words them, against the
## plain item: [[text, good], ...] (good ones green, bad ones red).
static func tooltip_lines(def: Dictionary) -> Array:
	var pre := int(def.get("prefix", 0))
	if pre <= 0:
		return []
	var out := []
	var base := Data.item(def.get("internal", ""))
	var pct := func(key: String, suffix: String, invert := false, bad_if_up := false) -> void:
		var a := float(base.get(key, 0.0))
		var b := float(def.get(key, a))
		if a == b or a == 0.0:
			return
		var n := int(round_even((b - a) / a * 100.0)) * (-1 if invert else 1)
		out.append([("+" if n > 0 else "") + str(n) + suffix, n <= 0 if bad_if_up else n >= 0])
	pct.call("damage", "% damage")
	pct.call("use_animation" if base.has("use_animation") else "use_time", "% speed", true)
	if int(def.get("crit", 0)) != int(base.get("crit", 0)):
		var n := int(def.get("crit", 0)) - int(base.get("crit", 0))
		out.append([("+" if n > 0 else "") + str(n) + "% critical strike chance", n >= 0])
	pct.call("mana", "% mana cost", false, true)
	if def.has("scale"):
		var a := float(base.get("scale", 1.0))
		var n := int(round_even((float(def.scale) - a) / a * 100.0))
		if n != 0:
			out.append([("+" if n > 0 else "") + str(n) + "% size", n >= 0])
	pct.call("shoot_speed", "% velocity")
	pct.call("knockback", "% knockback")
	var b := bonus(pre)
	var words := {"defense": " defense", "mana_bonus": " mana", "crit": "% critical strike chance", "damage": "% damage",
			"move_speed": "% movement speed", "melee_speed": "% melee speed"}
	for k in b:
		out.append(["+%d%s" % [int(b[k]), words[k]], true])
	return out


## A 32-bit float, as Terraria's sums keep them.
static func f32(x: float) -> float:
	return PackedFloat32Array([x])[0]


## .NET's Math.Round: halves to the even number.
static func round_even(x: float) -> float:
	var r := floorf(x + 0.5)
	if r - x == 0.5 and fmod(r, 2.0) != 0.0:
		r -= 1.0
	return r


## (int)Math.Round((float)n * mult), Terraria's rounding of a stat.
static func _scaled(n, mult: float) -> int:
	return int(round_even(f32(float(n) * mult)))
