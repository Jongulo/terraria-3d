class_name PalmArt
## Palm trees, Terraria's beach trees: a column of "palm_trunk" cells (solid,
## chopped like any trunk) under a Tree_Tops_15 canopy decoration. Each cell
## draws one Tiles_323 segment as a billboard, shifted sideways along the
## palm's curve; the canopy sits on the end of it. The curve is Terraria's
## (WorldGen.GrowPalmTree): a lean of up to 16 px is picked, and from a quarter
## of the way up every segment steps 2 px towards it until it gets there (its
## 1-in-13 / 9 / 5 checks all end in an else that steps anyway). In 3D the palm
## leans towards the sea. Everything comes from the column's position and
## height, so nothing else is saved.

## palm_trunk's variants (Tiles_323 frames): 0-2 the trunk, 3 the base (with
## its roots), 4-6 the top.
const BASE := 3
const TOPS := [4, 5, 6]
## Terraria's palm segments are 20 px tall on 16 px tiles: each hangs 4 px
## (a quarter block) into the one below, the base's roots into the ground.
const HANG := 0.25
## Texture pixels per block (a lean of 16 px is one block).
const PX := 16.0
## How much nearer the camera each segment is drawn than the one above it, so
## the overlapping quarter blocks don't z-fight: the lower one covers the
## overhang, as Terraria draws them (top to bottom).
const NUDGE := 0.01
## The canopy decoration's style sheet (CanopyArt.SHEETS: Tree_Tops_15).
const CANOPY_SHEET := 15


## The palm column through `p`: [base, height] (height 0 if `p` isn't palm).
static func column(world: VoxelWorld, p: Vector3i) -> Array:
	if not _is_palm(world, p):
		return [p, 0]
	var base := p
	while _is_palm(world, base + Vector3i.DOWN):
		base += Vector3i.DOWN
	var h := 1
	while _is_palm(world, base + Vector3i.UP * h):
		h += 1
	return [base, h]


static func _is_palm(world: VoxelWorld, p: Vector3i) -> bool:
	return Data.block(world.get_block(p)).get("palm", false)


## A palm `height` cells tall at `base`: {height, frames (variant per cell,
## from the base up), offsets (px, per cell), dir (the lean, a horizontal unit
## vector)}. `dir` defaults to a direction from the position.
static func shape(base: Vector3i, height: int, dir := Vector3.ZERO) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(base)
	# Terraria: genRand.Next(-8, 9) * 2. Here it leans one way (dir), so the
	# size is what counts.
	var target := absi(rng.randi_range(-8, 8) * 2)
	var frames: Array[int] = []
	var offsets: Array[int] = []
	var off := 0
	for k in height:
		if k == 0:
			frames.append(BASE)
		elif k == height - 1:
			frames.append(TOPS[rng.randi_range(0, 2)])
		else:
			if off != target and float(k) / height >= 0.25:
				off += 2
			frames.append(rng.randi_range(0, 2))
		offsets.append(off)
	if dir == Vector3.ZERO:
		var a := rng.randf() * TAU
		dir = Vector3(cos(a), 0.0, sin(a))
	return {"height": height, "frames": frames, "offsets": offsets, "dir": dir}


## The way a palm at `base` leans: towards the sea (where the coast is nearer),
## or any way inland.
static func lean(world: VoxelWorld, base: Vector3i) -> Vector3:
	var g := Vector2(world.coast_inland(base.x + 4, base.z) - world.coast_inland(base.x - 4, base.z),
			world.coast_inland(base.x, base.z + 4) - world.coast_inland(base.x, base.z - 4))
	if g.length() < 0.01:
		return Vector3.ZERO
	g = -g.normalized()
	return Vector3(g.x, 0.0, g.y)


## A palm in the world: its column and shape, or {} if `p` isn't palm.
static func at(world: VoxelWorld, p: Vector3i) -> Dictionary:
	var col := column(world, p)
	if col[1] == 0:
		return {}
	var s := shape(col[0], col[1], lean(world, col[0]))
	s["base"] = col[0]
	return s


## Where cell `k`'s segment is drawn, from its cell (blocks).
static func segment_offset(s: Dictionary, k: int) -> Vector3:
	return s.dir * (s.offsets[k] / PX) + Vector3(0.0, -HANG, 0.0)


## How much nearer the camera cell `k`'s billboard is drawn (see NUDGE).
static func segment_nudge(s: Dictionary, k: int) -> float:
	return (s.height - 1 - k) * NUDGE


## How far the top of the trunk leans (where the canopy goes).
static func top_offset(s: Dictionary) -> Vector3:
	return s.dir * (s.offsets[s.height - 1] / PX)
