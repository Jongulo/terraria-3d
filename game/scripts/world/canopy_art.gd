class_name CanopyArt
## Tree canopy sprites, built from Terraria's Tree_Tops art: each style's frame
## at art resolution, processed by SpriteFx with the "tree_canopy" settings
## (by default upscaled 4x with Scale2x twice and smoothly warped, the warp
## fading out at the bottom so the trunk stub still meets the trunk). Used as
## the "tree_canopy" placeable (Data) and drawn by Decorations.

const STYLES := 3  # forest styles (shown in the sprite editor)
## Terraria's Tree_Tops sheets, indexed by worldgen's canopy style / 10 (its
## frame is style % 10): see worldgen.rs TreeTops. Each world splits its
## forest into zones with their own leaves (sheets 0, 5-9), and picks one snow
## look (3, 10-13) and one jungle look (4, 14); palm trees on the beach have
## 15 (PalmArt), the gem trees in the caves 16-22 (worldgen.rs gem_trees), the
## vanity trees in the forest 23 (Sakura) and 24 (Yellow Willow), the ash
## trees in the Underworld 25, and the underground jungle's mahogany 26.
const SHEETS := ["Tree_Tops_0", "Tree_Tops_1", "Tree_Tops_5", "Tree_Tops_17", "Tree_Tops_2",
		"Tree_Tops_6", "Tree_Tops_7", "Tree_Tops_8", "Tree_Tops_9", "Tree_Tops_10",
		"Tree_Tops_12", "Tree_Tops_16", "Tree_Tops_18", "Tree_Tops_4", "Tree_Tops_11",
		"Tree_Tops_15",
		"Tree_Tops_22", "Tree_Tops_23", "Tree_Tops_24", "Tree_Tops_25", "Tree_Tops_26", "Tree_Tops_27", "Tree_Tops_28",
		"Tree_Tops_29", "Tree_Tops_30", "Tree_Tops_31",
		"Tree_Tops_13"]
## What each sheet is (sprite editor).
const SHEET_NAMES := ["Forest", "Corruption", "Crimson", "Snowy pine", "Jungle",
		"Forest", "Forest", "Forest", "Forest", "Forest",
		"Snow, round", "Snow, green pine", "Snow, snowier", "Snow, bare", "Jungle, bushy",
		"Palm",
		"Gem: topaz", "Gem: amethyst", "Gem: sapphire", "Gem: emerald", "Gem: ruby", "Gem: diamond", "Gem: amber",
		"Sakura", "Yellow willow", "Ash",
		"Underground jungle"]
## Frame size (texture pixels, 2 px apart) per sheet: most are 80 x 80; the
## jungle's are bigger, like Terraria's.
const FRAMES := [Vector2i(80, 80), Vector2i(80, 80), Vector2i(80, 80), Vector2i(80, 80), Vector2i(114, 96),
		Vector2i(80, 80), Vector2i(80, 80), Vector2i(80, 80), Vector2i(80, 80), Vector2i(80, 80),
		Vector2i(80, 80), Vector2i(80, 80), Vector2i(80, 80), Vector2i(80, 80), Vector2i(116, 96),
		Vector2i(80, 80),
		Vector2i(116, 96), Vector2i(116, 96), Vector2i(116, 96), Vector2i(116, 96), Vector2i(116, 96), Vector2i(116, 96), Vector2i(116, 96),
		Vector2i(118, 96), Vector2i(118, 96), Vector2i(116, 96),
		Vector2i(116, 96)]
## Every canopy style (three frames per sheet).
static var STYLE_IDS: Array[int] = _style_ids()
const FRAME := 80  # the usual frame width, which SIZE is measured against
## World width of an 80 px canopy frame (before any warp margin), in blocks;
## bigger frames come out bigger at the same pixel size.
const SIZE := 5.0


## "Forest (Tree_Tops_6)" for a sheet.
static func sheet_label(k: int) -> String:
	return "%s (%s)" % [SHEET_NAMES[k], SHEETS[k]]


static func _style_ids() -> Array[int]:
	var out: Array[int] = []
	for k in SHEETS.size():
		for f in 3:
			out.append(k * 10 + f)
	return out


## The placeable block for a style (each listed in the picker with its own
## choices): "tree_canopy" for style 0, "tree_canopy@<style>" for the rest.
static func block_name(style: int) -> String:
	return "tree_canopy" if style == 0 else "tree_canopy@%d" % style


## One style's frame at art resolution (40 x 40 for Terraria's 2x art).
static func frame_art(style: int) -> Image:
	var k := clampi(style / 10, 0, SHEETS.size() - 1)
	return _cut(Assets.image("Images/" + SHEETS[k]), style, sheet_scale(k))


## A sheet's art scale (PixelArt.detect_scale of its first frame; the frames
## sit on even pixels, so they all share it). Main thread only (cached).
static func sheet_scale(k: int) -> Vector3i:
	if not _scales.has(k):
		var sheet: Image = Assets.image("Images/" + SHEETS[k])
		_scales[k] = PixelArt.detect_scale(sheet.get_region(Rect2i(Vector2i.ZERO, FRAMES[k])))
	return _scales[k]


static var _scales := {}


static func _cut(sheet: Image, style: int, scale: Vector3i) -> Image:
	var f: Vector2i = FRAMES[clampi(style / 10, 0, SHEETS.size() - 1)]
	return PixelArt.downsample(sheet.get_region(Rect2i((style % 10) * (f.x + 2), 0, f.x, f.y)), scale)


## One style processed with `o` (default: the saved settings): {image, k, px}
## where k = output pixels per art pixel and px = world size of one pixel.
static func build(style: int, o := {}) -> Dictionary:
	if o.is_empty():
		o = SpriteFx.options("tree_canopy")
	var art := frame_art(style)
	return _finish(style, art, SpriteFx.process(art, o, style))


## Every style at once (style -> build()), on worker threads (the sheets and
## their scales are fetched first: Assets' and PixelArt's caches aren't
## thread-safe).
static func build_all(o := {}, styles: Array[int] = STYLE_IDS) -> Dictionary:
	if o.is_empty():
		o = SpriteFx.options("tree_canopy")
	var sheets: Array[Image] = []
	var scales: Array[Vector3i] = []
	for style in styles:
		var k := clampi(style / 10, 0, SHEETS.size() - 1)
		sheets.append(Assets.image("Images/" + SHEETS[k]))
		scales.append(sheet_scale(k))
	var arts := []
	var results := []
	arts.resize(styles.size())
	results.resize(styles.size())
	var task := WorkerThreadPool.add_group_task(func(i: int):
		arts[i] = _cut(sheets[i], styles[i], scales[i])
		results[i] = SpriteFx.process(arts[i], o, styles[i]), styles.size())
	WorkerThreadPool.wait_for_group_task_completion(task)
	var out := {}
	for i in styles.size():
		out[styles[i]] = _finish(styles[i], arts[i], results[i])
	return out


static func _finish(style: int, art: Image, r: Dictionary) -> Dictionary:
	# Every sheet's art pixel is the same world size (an 80 px frame is SIZE
	# wide), so bigger frames make bigger canopies.
	var art_scale := float(FRAMES[clampi(style / 10, 0, SHEETS.size() - 1)].x) / art.get_width()
	r["px"] = SIZE * art_scale / (FRAME * r.k)
	return r


static func cell(style: int) -> Image:
	return build(style).image
