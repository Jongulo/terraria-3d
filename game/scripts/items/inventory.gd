class_name Inventory
extends RefCounted
## A list of item stacks. Slots hold null or {"item": internal name, "count": int}.
## The player's first 10 slots are the hotbar; chests use the same class.

signal changed

var slots: Array = []
## Coins, largest first: 100 of each make one of the next, like Terraria's.
const COINS: Array[String] = ["PlatinumCoin", "GoldCoin", "SilverCoin", "CopperCoin"]
const COIN_VALUES: Array[int] = [1000000, 10000, 100, 1]


func _init(size := 50) -> void:
	slots.resize(size)


static func stack(item: String, count: int) -> Dictionary:
	return {"item": item, "count": count}


func max_stack(item: String) -> int:
	return int(Data.item(item).get("max_stack", 9999))


## Adds items, filling existing stacks first. Returns how many didn't fit.
## Coins join your money (100 copper turn into a silver, and so on).
func add(item: String, count: int) -> int:
	if count <= 0 or item == "":
		return 0
	var coin := COINS.find(item)
	if coin >= 0:
		var total := money() + COIN_VALUES[coin] * count
		_take_coins()
		return ceili(add_money(total) / float(COIN_VALUES[coin]))
	var limit := max_stack(item)
	for s in slots:
		if s != null and s.item == item and s.count < limit:
			var n := mini(count, limit - s.count)
			s.count += n
			count -= n
			if count == 0:
				break
	for i in slots.size():
		if count == 0:
			break
		if slots[i] == null:
			var n := mini(count, limit)
			slots[i] = stack(item, n)
			count -= n
	changed.emit()
	return count


## How many more of `item` would fit.
func count_space(item: String) -> int:
	var limit := max_stack(item)
	var space := 0
	for s in slots:
		if s == null:
			space += limit
		elif s.item == item:
			space += limit - int(s.count)
	return space


func count_of(item: String) -> int:
	var total := 0
	for s in slots:
		if s != null and s.item == item:
			total += s.count
	return total


## Removes up to `count` items, taking from the last stacks first. Returns true if all were removed.
func remove(item: String, count: int) -> bool:
	for i in range(slots.size() - 1, -1, -1):
		var s = slots[i]
		if count == 0:
			break
		if s != null and s.item == item:
			var n := mini(count, int(s.count))
			s.count -= n
			count -= n
			if s.count == 0:
				slots[i] = null
	changed.emit()
	return count == 0


## Recipe ingredient spec like "IronBar|LeadBar": total count across alternatives.
func count_spec(spec: String) -> int:
	var total := 0
	for name in spec.split("|"):
		total += count_of(name)
	return total


func remove_spec(spec: String, count: int) -> void:
	for name in spec.split("|"):
		var n := mini(count, count_of(name))
		remove(name, n)
		count -= n
		if count == 0:
			return


## Removes one item from a specific slot (used ammo, thrown weapons, potions).
func consume_slot(i: int, n := 1) -> void:
	var s = slots[i]
	if s == null:
		return
	s.count -= n
	if s.count <= 0:
		slots[i] = null
	changed.emit()


## First slot holding any item whose ammo group matches `ammo` (e.g. WoodenArrow covers UnholyArrow).
func find_ammo(ammo: String) -> int:
	for i in slots.size():
		var s = slots[i]
		if s == null:
			continue
		var def := Data.item(s.item)
		if def.get("type") == "ammo" and (s.item == ammo or def.get("ammo_group", "") == ammo):
			return i
	return -1


## The money held, in copper coins.
func money() -> int:
	var total := 0
	for s in slots:
		if s != null and s.item in COINS:
			total += COIN_VALUES[COINS.find(s.item)] * int(s.count)
	return total


## Pays `amount` copper out of the coins held, making change. Returns false
## (paying nothing) if there isn't enough.
func pay(amount: int) -> bool:
	var total := money()
	if total < amount:
		return false
	_take_coins()
	add_money(total - amount)
	return true


## Adds `amount` copper as the fewest coins. Returns the copper that didn't fit.
func add_money(amount: int) -> int:
	var left := 0
	for k in COINS.size():
		var n := amount / COIN_VALUES[k]
		amount -= n * COIN_VALUES[k]
		if n > 0:
			left += _add_plain(COINS[k], n) * COIN_VALUES[k]
	changed.emit()
	return left


## "2 gold 5 silver": an amount of copper in Terraria's words.
static func money_text(amount: int) -> String:
	if amount <= 0:
		return "0 copper"
	var parts := []
	for k in COINS.size():
		var n := amount / COIN_VALUES[k]
		amount -= n * COIN_VALUES[k]
		if n > 0:
			parts.append("%d %s" % [n, ["platinum", "gold", "silver", "copper"][k]])
	return " ".join(parts)


func _take_coins() -> void:
	for i in slots.size():
		if slots[i] != null and slots[i].item in COINS:
			slots[i] = null


func _add_plain(item: String, count: int) -> int:
	var limit := max_stack(item)
	for s in slots:
		if s != null and s.item == item and s.count < limit:
			var n := mini(count, limit - s.count)
			s.count += n
			count -= n
			if count == 0:
				return 0
	for i in slots.size():
		if slots[i] == null:
			var n := mini(count, limit)
			slots[i] = stack(item, n)
			count -= n
			if count == 0:
				return 0
	return count


func is_empty() -> bool:
	return slots.all(func(s): return s == null)


func to_data() -> Array:
	return slots.duplicate(true)


func from_data(data: Array) -> void:
	for i in mini(data.size(), slots.size()):
		var s = data[i]
		slots[i] = null if s == null else stack(s.item, int(s.count))
	changed.emit()
