class_name Herbs
extends Node
## Terraria's seven herbs (tiles 82-84; worldgen plants them, alchemy.rs):
## Daybloom, Moonglow, Blinkroot, Deathweed, Waterleaf, Fireblossom and
## Shiverthorn, each a sprout, then grown, then in bloom. Blocks with "herb"
## (its style), "herb_stage" (0 sprout, 1 grown, 2 blooming).
##
## Each herb near you gets a random update about as often as Terraria's
## world updates reach a tile (UPDATE), and in it WorldGen.GrowAlch:
## - In liquid it dies (dropping what it drops), but Moonglow and Waterleaf
##   in water and Fireblossom in lava; off its soil it dies too.
## - A sprout grows 1 in 50 (Shiverthorn half as often), and has another 1 in
##   50 when it's its time: Daybloom by day, Moonglow by night, Waterleaf in
##   the rain, Blinkroot underground, Fireblossom in the Underworld.
## - Grown Blinkroot flickers into bloom and back; Shiverthorn blooms 1 in 30.
## The others are in bloom whenever they can be harvested
## (IsAlchemyPlantHarvestable): Daybloom by day, Moonglow by night, Deathweed
## on full-moon (or Blood Moon) nights, Waterleaf in the rain, Fireblossom from
## 3:45 PM till dusk when it isn't raining (or below the surface), and in lava.
##
## Harvested (KillTile_GetItemDrops): a sprout gives nothing; grown, the
## herb; harvestable, the herb and 1-3 seeds; with the Staff of Regrowth
## (which cuts only what's harvestable, in pots too) 1-2 herbs and 1-5 seeds.

const STYLES := ["daybloom", "moonglow", "blinkroot", "deathweed", "waterleaf", "fireblossom", "shiverthorn"]
const DAYBLOOM := 0
const MOONGLOW := 1
const BLINKROOT := 2
const DEATHWEED := 3
const WATERLEAF := 4
const FIREBLOSSOM := 5
const SHIVERTHORN := 6
## Seconds between a herb's updates.
const UPDATE := 166.0 / 60.0
## How far round you herbs grow.
const REACH := Vector3i(64, 40, 64)
const MOST := 4000
## Fireblossom blooms past this many ticks into the day (3:45 PM).
const FIREBLOSSOM_TIME := 40500.0
## ...or in this much lava (Terraria's liquid > 16 of 255).
const FIREBLOSSOM_LAVA := 16.0 / 255.0 * 63.0

var game
var _ids := PackedInt32Array()
## [style][stage] -> block id.
var _stage_ids := []
var _t := 0.0


func setup(g) -> void:
	game = g
	for s in STYLES.size():
		var row := []
		for suffix in ["_sprout", "_mature", ""]:
			var id := Data.block_id(STYLES[s] + suffix)
			row.append(id)
			_ids.append(id)
		_stage_ids.append(row)


func _process(delta: float) -> void:
	if game == null or game.player == null:
		return
	_t += delta
	if _t < UPDATE:
		return
	_t -= UPDATE
	update_near(Vector3i(game.player.global_position.floor()))


## One update for every herb round `at`.
func update_near(at: Vector3i) -> void:
	var cells: PackedInt32Array = game.world.find_blocks(at, REACH, _ids, MOST)
	var tw = game.test_world
	var c := Vector3i(TestWorld.SIZE.x / 2, TestWorld.GROUND + 1, TestWorld.SIZE.z / 2)
	for i in range(0, cells.size(), 3):
		var p := Vector3i(cells[i], cells[i + 1], cells[i + 2])
		# (The test world's gallery shows each herb as it was put there.)
		if tw != null and TestWorld.in_gallery(c, p):
			continue
		grow(p)


## WorldGen.GrowAlch (and the bloom of those that bloom when harvestable).
func grow(p: Vector3i) -> void:
	var w: VoxelWorld = game.world
	var b := Data.block(w.get_block(p))
	if not b.has("herb"):
		return
	var style := int(b.herb)
	var stage := int(b.herb_stage)
	var liquid: Vector2i = w.get_liquid(p)
	if liquid.y > 0:
		var safe: bool = (liquid.x == Player.LIQ_LAVA and style == FIREBLOSSOM) \
				or (liquid.x == Player.LIQ_WATER and style in [MOONGLOW, WATERLEAF])
		if not safe:
			game.break_block(p)
			return
	if not Data.block(w.get_block(p + Vector3i.DOWN)).get("name", "") in b.grows_on:
		game.break_block(p)
		return
	if stage == 0:
		var grows := randi() % 50 == 0 and (style != SHIVERTHORN or randi() % 2 == 0)
		if not grows and randi() % 50 == 0:
			match style:
				DAYBLOOM: grows = game.sky.is_day
				MOONGLOW: grows = not game.sky.is_day
				WATERLEAF: grows = raining()
				BLINKROOT: grows = p.y < game.surface_level
				FIREBLOSSOM: grows = p.y < game.underworld_level
		if grows:
			_set_stage(p, style, 1)
		return
	match style:
		BLINKROOT:
			if randi() % 3 != 0:
				if stage == 1 and randi() % 2 == 0:
					_set_stage(p, style, 2)
				elif stage == 2:
					_set_stage(p, style, 1)
		SHIVERTHORN:
			if stage == 1 and randi() % 30 == 0:
				_set_stage(p, style, 2)
		_:
			var bloom := blooms(style, p)
			if bloom != (stage == 2):
				_set_stage(p, style, 2 if bloom else 1)


func _set_stage(p: Vector3i, style: int, stage: int) -> void:
	game.world.set_block(p, _stage_ids[style][stage])


## Whether it's raining (no rain in this game yet).
func raining() -> bool:
	return false


## IsAlchemyPlantHarvestable: whether a grown herb of `style` at `p` is ready.
func blooms(style: int, p: Vector3i) -> bool:
	var sky = game.sky
	match style:
		DAYBLOOM:
			return sky.is_day
		MOONGLOW:
			return not sky.is_day
		DEATHWEED:
			return not sky.is_day and sky.moon_phase == 0
		WATERLEAF:
			return raining()
		FIREBLOSSOM:
			var liquid: Vector2i = game.world.get_liquid(p)
			if liquid.x == Player.LIQ_LAVA and liquid.y > FIREBLOSSOM_LAVA:
				return true
			return (not raining() or p.y < game.surface_level) and sky.is_day and sky.time > FIREBLOSSOM_TIME
	return false


## Whether the herb block `b` at `p` gives its seeds now.
func harvestable(b: Dictionary, p: Vector3i) -> bool:
	var stage := int(b.get("herb_stage", 0))
	return stage == 2 or (stage == 1 and blooms(int(b.herb), p))


## What breaking it drops (KillTile_GetItemDrops): [[item, count], ...].
func drops(b: Dictionary, p: Vector3i, regrowth: bool) -> Array:
	var stage := int(b.get("herb_stage", 0))
	if stage == 0:
		return []
	if regrowth:
		return [[b.herb_item, randi_range(1, 2)], [b.herb_seeds, randi_range(1, 5)]]
	if harvestable(b, p):
		return [[b.herb_item, 1], [b.herb_seeds, randi_range(1, 3)]]
	return [[b.herb_item, 1]]
