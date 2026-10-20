class_name Invasion
extends RefCounted
## Terraria's Goblin Army (Main.StartInvasion / UpdateInvasion): it comes
## from the west or east edge of the world toward the spawn point, a tile a
## tick, and its goblins spawn round you while you're near it; it's over
## once you've killed 80 + 40 of them for each player (120 here). Beating it
## the first time frees the Goblin Tinkerer to be found, bound, in the caverns.

## Kills it takes: 80, and 40 a player.
const SIZE := 80 + 40
## It marches a tile a tick: 60 tiles (40 blocks) a second.
const MARCH := 40.0
## Its goblins spawn while you're within 187.5 tiles of it across, and no more
## than 67.5 tiles under the surface.
const NEAR := 125.0
const DEEP := 45.0
## Spawn weights before Hardmode (Terraria's group B, out of 405).
const SPAWNS := [["GoblinSorcerer", 45], ["GoblinThief", 64], ["GoblinPeon", 72], ["GoblinArcher", 96], ["GoblinWarrior", 128]]
const COLOR := Color(0.69, 0.29, 1.0)

var game
var active := false
var size := 0
## Where the army is across the world (blocks along x), and the way it comes.
var army_x := 0.0
var from_west := true
var arrived := false
## Beaten at least once (Terraria's NPC.downedGoblins).
var downed := false


func _init(g) -> void:
	game = g


## Starts it, if a player has 200 max life and none is on (the Goblin Battle
## Standard, or a dawn). False if it can't.
func start() -> bool:
	if active or game.player.life_max < 200:
		return false
	active = true
	size = SIZE
	arrived = false
	from_west = randf() < 0.5
	army_x = 0.0 if from_west else float(game.world.get_size().x)
	game.message("A goblin army is approaching from the %s!" % ("west" if from_west else "east"), COLOR)
	return true


## Terraria's dawn roll: with an orb or heart smashed and a player of 200 life,
## a 1 in 3 chance until it's first beaten, then 1 in 30. (Not in the test
## world unless its natural spawns are on, F7.)
func dawn() -> void:
	if game.test_world != null and not game.test_world.natural_spawns:
		return
	if not active and game.orbs_broken > 0 and game.player.life_max >= 200 and randi() % (30 if downed else 3) == 0:
		start()


func update(delta: float) -> void:
	if not active or arrived:
		return
	var to: float = game.player.spawn_point.x
	army_x = move_toward(army_x, to, MARCH * delta)
	if is_equal_approx(army_x, to):
		arrived = true
		game.message("A goblin army has arrived!", COLOR)


## Whether its goblins come for you here.
func near(p: Vector3) -> bool:
	return active and absf(p.x - army_x) < NEAR and p.y > game.surface_level - DEEP


## How far it's been beaten back (0..1).
func progress() -> float:
	return 1.0 - float(size) / SIZE if active else 0.0


## One of its goblins killed: one fewer to go.
func on_kill(npc) -> void:
	if not active or npc.def.get("invasion", "") != "goblin":
		return
	size -= int(npc.def.get("invasion_points", 1))
	if size <= 0:
		active = false
		downed = true
		game.message("A goblin army has been defeated!", COLOR)


func save_state() -> Dictionary:
	return {"active": active, "size": size, "army_x": army_x, "from_west": from_west, "arrived": arrived, "downed": downed}


func load_state(d: Dictionary) -> void:
	active = d.get("active", false)
	size = int(d.get("size", 0))
	army_x = float(d.get("army_x", 0.0))
	from_west = d.get("from_west", true)
	arrived = d.get("arrived", false)
	downed = d.get("downed", false)
