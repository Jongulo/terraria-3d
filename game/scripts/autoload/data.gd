extends Node
## Game data: blocks (and their texture array), items, recipes and NPCs.

const LAYER_SIZE := 96
## Terraria tiles shown across one cube face (per side): 2 means each face is a
## 2x2 mosaic of tiles, so terrain pixels match the placeable models' voxels.
## A face can override it with "per_face" in blocks.json.
const TILES_PER_FACE := 2
## Terraria texture pixels per block (16 per tile): placeable sprites are drawn
## at this scale, i.e. their real in-game size relative to the terrain.
const PIXELS_PER_BLOCK := 16 * TILES_PER_FACE
const NO_TEX := 65535
const RENDER := {"none": 0, "cube": 1, "cutout": 2, "cross": 3, "model": 5}
## How placeable sprite blocks are turned into 3D (picked per block with the
## placeable picker, saved in data/placeables.json). "panels" and "cross" are
## drawn by the chunk mesher; the rest are block models (BlockModels).
const PLACEABLE_METHODS := ["panels", "cross", "billboard", "flat", "extruded", "hull", "hull_top", "lathe", "claude", "tuned", "rendered"]
## Hand-made voxel models for the "claude" method, by block name (data/handmade_models.json).
var handmade_models := {}
const PLACEABLES_PATH := "res://data/placeables.json"
## Side noise for the "extruded" method (see BlockModelMesh._extrude).
const EXTRUDE_NOISES := ["none", "speckle", "grain", "palette"]
## Methods with settings: pixel noise and one colour per voxel (extruded also
## has depth and bevel).
const NOISE_METHODS := ["extruded", "hull", "hull_top", "lathe", "claude", "tuned"]
## The voxel methods that work the sprite out by themselves, which can cut its
## dark outline away first ("no_outline": PixelArt.without_outline).
const OUTLINE_METHODS := ["extruded", "hull", "hull_top", "lathe"]
## What the "rendered" method shoots: "auto" (the tuned model, else Claude's,
## else the hull), or one of the voxel methods, with its own settings. A block
## switched to rendered from a voxel method shoots that one (set_block_method).
const RENDER_MODELS := ["auto", "extruded", "flat", "hull", "hull_top", "lathe", "claude", "tuned"]
## Bevel profiles for the "extruded" method's front and back edges.
const EXTRUDE_BEVELS := ["none", "chamfer", "round", "cove", "step"]
## Bevel size limit, in art voxels.
const BEVEL_MAX := 6

## Block id -> definition Dictionary (index 0 is air).
var blocks: Array[Dictionary] = []
var block_ids := {}
## Placeables that are not world blocks (tree canopies): shown in the placeable
## picker and drawn by their chosen method, but never registered with the world.
## Their ids start at DECORATION_BASE, so block(id) and block_id(name) work.
const DECORATION_BASE := 60000
var decoration_blocks: Array[Dictionary] = []
## Block ids that count toward each biome ("biome" in blocks.json).
var biome_blocks := {}
## Block ids that give a buff when near ("near_buff": the Bast Statue's
## CatBast), as buff -> PackedInt32Array.
var near_buff_ids := {}
var block_textures: Texture2DArray
## The layers past MAX_LAYERS, in a second array (voxel_common.gdshaderinc's
## block_tex picks the array): up to twice as many in all.
var block_textures_2: Texture2DArray
## Each block texture layer's art pixels across a block (Terraria's art is
## drawn at 2x, and the layers are upscaled to LAYER_SIZE): the shaders look
## the sun's shadow up once per art pixel (shaders/sun_shadow.gdshaderinc).
## One float a layer, in a row (an RF texture, LAYER_TEXELS_WIDTH wide).
var layer_texels: ImageTexture
const LAYER_TEXELS_WIDTH := 256
## Block name -> chosen placeable method (only blocks that differ from their default).
var placeable_methods := {}
## Block name -> extruded settings that differ from the defaults
## ({depth: voxels, noise, strength: 0..1, seed, bevel, bevel_size, bevel_sides:
## the edges and faces bevelled, BlockModelMesh.BEVEL_SIDES}).
## Depth and bevel size are in art voxels (one per pixel of the original art).
var extrude_settings := {}
## Method ("hull", "lathe", "claude", "tuned") -> block name -> settings that differ
## from the defaults ({noise, strength, seed, one_color}).
var noise_settings := {"hull": {}, "hull_top": {}, "lathe": {}, "claude": {}, "tuned": {}}
## Block name -> the "rendered" method's settings that differ from the
## defaults ({model: what's shot, RENDER_MODELS}, outline).
var rendered_settings := {}
## Block name -> model transform keys that differ from the defaults
## ({offset: [x, y, z] art pixels, rotation: [x, y, z] degrees, scale}).
var transform_settings := {}
const TRANSFORM_DEFAULTS := {"offset": [0, 0, 0], "rotation": [0, 0, 0], "scale": 1.0}
## Older placeables files measured depth/bevel in texture pixels.
var _placeables_units := "art"

## Internal item name -> definition (with "id", "name", "max_stack", ...).
var items := {}
## Recipes asking for Wood take any of these (Terraria's "Any Wood").
const ANY_WOOD := "Wood|BorealWood|RichMahogany|Ebonwood|Shadewood|PalmWood|AshWood"
## Terraria item id -> internal name.
var item_by_id := {}
## Armor sets from items.json "armor_sets" (and the metal tiers): {head, body,
## legs, text: Terraria's set bonus text key, and the bonus stats}.
var armor_sets: Array[Dictionary] = []
const ARMOR_SLOTS := ["head", "body", "legs"]
var recipes: Array[Dictionary] = []
var npcs := {}
var loot := {}
## Block name -> the dust Terraria's tile makes when hit or broken:
## {dust: [[DustID, share], ...], hit: n, kill: n} (tools/terraria_dust.py).
var tile_dust := {}
## NPC name -> what it breaks into and bleeds (tools/terraria_gore.py):
## {gores: [[[Gore id, dx, dy, vx, vy, scale], ...] per roll], death_dust, hit_dust}.
var npc_gore := {}
## What Shimmer does to items (tools/terraria_shimmer.py, Terraria's
## ItemID.Sets): {transform: {item: item}, counts_as, counts_as_decraft:
## {item: item}, post_moonlord: [item...]}.
var shimmer := {}
## Item -> the recipe Shimmer takes it apart by (Terraria's
## ItemID.Sets.IsCrafted: its last recipe that isn't notDecraftable; and
## IsCraftedCrimson / IsCraftedCorruption: its last recipe of that evil):
## {"any" / "crimson" / "corruption": {count, ingredients: [[item, n]...],
## alchemy: made at a Placed Bottle, shimmer: Terraria's own results instead}}.
var decrafts := {}


func _ready() -> void:
	if not Assets.available():
		return
	handmade_models = _read_json("res://data/handmade_models.json")
	handmade_models.erase("_doc")
	_load_blocks()
	_load_items()
	npcs = _read_json("res://data/npcs.json")
	loot = _read_json("res://data/loot.json")
	load_npc_scales()
	# "_doc" entries are notes for people editing the files, not data.
	for d in [npcs, loot]:
		for k in d.keys().filter(func(k): return k.begins_with("_")):
			d.erase(k)


func _read_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("missing " + path)
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null:
		push_error("invalid JSON in " + path)
		return {}
	return parsed


# ------------------------------------------------------------------ blocks

func block_id(name: String) -> int:
	return block_ids.get(name, 0)


## What a block is, its styles being the same thing (blocks.json
## "variant_of": flowers_7 is flowers).
func kind_of(id: int) -> String:
	var b := block(id)
	return b.get("variant_of", b.get("name", ""))


## A random one of a block's styles (itself or one of its variant_of blocks).
func random_style(name: String) -> int:
	if _styles.is_empty():
		for i in range(1, blocks.size()):
			var k: String = blocks[i].get("variant_of", blocks[i].name)
			if not _styles.has(k):
				_styles[k] = []
			_styles[k].append(i)
	var ids: Array = _styles.get(name, [block_id(name)])
	return ids[randi() % ids.size()]


var _styles := {}


func block(id: int) -> Dictionary:
	if id >= DECORATION_BASE:
		return decoration_blocks[id - DECORATION_BASE] if id - DECORATION_BASE < decoration_blocks.size() else {}
	return blocks[id] if id > 0 and id < blocks.size() else {}


## Texture array layers a GPU is sure to allow (Vulkan's maxImageArrayLayers):
## the blocks' textures fill one array, then a second (block_textures_2).
const MAX_LAYERS := 2048
## Terraria's Main.tileCut: the tiles a swung weapon or the player's
## projectiles break (grass, flowers, plants, vines, cobwebs, herbs, pots, lily
## pads, cattails...). A block is one of them when its art is that tile's sheet.
const TILE_CUT := [3, 24, 28, 32, 51, 52, 61, 62, 69, 71, 73, 74, 82, 83, 84, 110, 113, 115, 184, 201, 205, 231, 236, 254,
		352, 382, 444, 454, 484, 485, 518, 519, 528, 529, 549, 636, 637, 638, 654, 655, 711]


func _load_blocks() -> void:
	var defs: Array = _read_json("res://data/blocks.json").get("blocks", [])
	load_placeables()
	var layers: Array[Image] = []
	var texels := PackedFloat32Array()
	var layer_runs := {}  # a face's pictures (Data._load_blocks) -> its first layer
	blocks = [{"name": "air", "render": 0}]
	for def in defs:
		var d: Dictionary = def.duplicate()
		var tex: Dictionary = d.get("tex", {})
		var all = tex.get("all")
		var faces := {
			"top": tex.get("top", all) if tex.has("top") else all,
			"side": tex.get("side", all) if tex.has("side") else all,
			"bottom": tex.get("bottom", all) if tex.has("bottom") else all,
		}
		if faces.side != null and faces.side.get("fill_top", false) and faces.top != null:
			# The side's grass takes the top's texture (_fill_from_top).
			faces.side = faces.side.duplicate()
			faces.side["fill"] = faces.top
		var variants := 1
		for face in faces.values():
			if face != null:
				variants = maxi(variants, int(face.get("variants", face.frames.size())))
		var render: int = RENDER[d.get("render", "cube")]
		# Its Terraria tile id (the sheet its art comes from), and Main.tileCut.
		var art = all if all != null else faces.side if faces.side != null else faces.top
		if art != null and str(art.sheet).begins_with("Tiles_"):
			d["tile_id"] = int(str(art.sheet).split("_")[1])
			d["cut"] = int(d.tile_id) in TILE_CUT
		var made := []  # [face, first layer]: faces sharing one texture ("all") share its layers
		for face_name in faces:
			var face = faces[face_name]
			if face == null:
				d["tex_" + face_name] = NO_TEX
				continue
			var shared := -1
			for m in made:
				if is_same(m[0], face):
					shared = m[1]
			if shared >= 0:
				d["tex_" + face_name] = shared
			else:
				var run: Array[Image] = []
				var run_texels := PackedFloat32Array()
				for v in variants:
					if render == 1:
						run.append(_cube_layer(face, v))
						# Its tiles' art pixels, per_face of them across.
						var tile := _stitch(face, face.frames[0])
						run_texels.append(float(int(face.get("per_face", TILES_PER_FACE)) * tile.get_width()) / PixelArt.detect_scale(tile).x)
					else:
						var frame: Array = face.frames[v % face.frames.size()]
						run.append(_crop_layer(face, frame, false))
						run_texels.append(float(_pixels_per_block(face)) / PixelArt.detect_scale(_stitch(face, frame)).x)
				# The same pictures as another block's face (a chest's wooden
				# top, a table's): those layers again, so the array keeps
				# under the GPU's limit.
				var key := ""
				for img in run:
					key += "%s:%d;" % [img.get_size(), hash(img.get_data())]
				key += str(run_texels)
				var first: int = layer_runs.get(key, -1)
				if first < 0:
					first = layers.size()
					layer_runs[key] = first
					layers.append_array(run)
					texels.append_array(run_texels)
				d["tex_" + face_name] = first
				made.append([face, first])
			if face_name == "side" and render != 1:
				# The original sprite and its world pixel size, for block models,
				# plus the sprite at its art resolution (voxel models use that).
				# Every variant's sprite (batched billboards pick one per block).
				var sprites: Array[Image] = []
				for v in variants:
					sprites.append(_stitch(face, face.frames[v % face.frames.size()]))
				_set_sprites(d, sprites, float(_pixels_per_block(face)), face.get("sprite_fx", ""))
				if d.has("anim"):
					_set_anim_frames(d, face)
		var side_layer: int = d.get("tex_side", NO_TEX)
		if side_layer == NO_TEX:
			side_layer = d.get("tex_top", 0)
		d["color"] = _average_color(layers[side_layer]) if side_layer < layers.size() else Color(0.5, 0.4, 0.3)
		var top_layer: int = d.get("tex_top", NO_TEX)
		d["color_top"] = _average_color(layers[top_layer]) if top_layer < layers.size() else d.color
		d["base_render"] = render
		d["render_id"] = render
		d["variants"] = variants
		if is_placeable(d):
			d["method"] = placeable_methods.get(d.get("settings", d.name), default_method(d))
			d["render_id"] = render_for(d)
		if d.get("track", false):
			# Minecart track: a block model shaped by the track beside it
			# (BlockModels, Tracks).
			d["method"] = "track"
			d["render_id"] = 5
		block_ids[d.name] = blocks.size()
		blocks.append(d)

	_add_decoration_blocks()
	biome_blocks = {}
	for id in range(1, blocks.size()):
		if blocks[id].has("biome"):
			if not biome_blocks.has(blocks[id].biome):
				biome_blocks[blocks[id].biome] = []
			biome_blocks[blocks[id].biome].append(id)
	near_buff_ids = {}
	for id in range(1, blocks.size()):
		if blocks[id].has("near_buff"):
			var b: String = blocks[id].near_buff
			if not near_buff_ids.has(b):
				near_buff_ids[b] = PackedInt32Array()
			near_buff_ids[b].append(id)
	_migrate_placeables()
	if layers.size() > 2 * MAX_LAYERS:
		push_error("block textures: %d layers, more than two arrays hold (%d): blocks would draw white" % [layers.size(), 2 * MAX_LAYERS])
	for img in layers:
		img.generate_mipmaps()
	block_textures = Texture2DArray.new()
	block_textures.create_from_images(layers.slice(0, MAX_LAYERS))
	# (Never empty: a layer of the first when nothing's past it.)
	block_textures_2 = Texture2DArray.new()
	block_textures_2.create_from_images(layers.slice(MAX_LAYERS) if layers.size() > MAX_LAYERS else layers.slice(0, 1))
	var rows := maxi(1, ceili(float(texels.size()) / LAYER_TEXELS_WIDTH))
	texels.resize(rows * LAYER_TEXELS_WIDTH)
	layer_texels = ImageTexture.create_from_image(Image.create_from_data(LAYER_TEXELS_WIDTH, rows, false, Image.FORMAT_RF, texels.to_byte_array()))


## A sprite block's sprites (one per variant) and the sizes derived from them.
## With `fx` they are first processed by SpriteFx with those settings (the
## originals are kept in raw_sprites, so rebuild_sprite_fx() can redo it).
func _set_sprites(d: Dictionary, sprites: Array[Image], ppb: float, fx: String) -> void:
	var fx_k := 1
	if fx != "":
		d["raw_sprites"] = sprites.duplicate()
		d["fx"] = fx
		d["fx_ppb"] = ppb
		var o := SpriteFx.options(fx)
		var art_k := PixelArt.detect_scale(sprites[0]).x  # texture px per art px
		var out: Array[Image] = []
		for v in sprites.size():
			var r := SpriteFx.process(PixelArt.downsample(sprites[v], PixelArt.detect_scale(sprites[v])), o, v, true)
			fx_k = r.k
			out.append(r.image)
		sprites = out
		ppb = ppb * fx_k / art_k
	d["sprites"] = sprites
	d["sprite"] = sprites[0]
	d["sprite_px"] = 1.0 / ppb
	# Wider or taller than a block: the chunk mesher can't draw it, so
	# panels/cross are drawn as block models instead.
	d["oversize"] = d.sprite.get_width() > ppb or d.sprite.get_height() > ppb
	var scale := PixelArt.detect_scale(d.sprite)
	if fx != "":
		scale = Vector3i(fx_k, fx_k / 2, fx_k / 2)  # back to the original art pixels
	d["art"] = PixelArt.downsample(d.sprite, scale)
	d["art_scale"] = scale.x
	d["art_px"] = d.sprite_px * scale.x


## An animated placeable's frames (Terraria's tile animation, its "anim":
## frames, stride: how far down the sheet each frame is, ticks: how long each
## shows): anim_sprites and anim_arts, frame 0 being the block's sprite.
func _set_anim_frames(d: Dictionary, face: Dictionary) -> void:
	var first: Array = face.frames[0]
	var sprites: Array[Image] = []
	var arts: Array[Image] = []
	var scale := PixelArt.detect_scale(d.sprite)  # the same on every frame of a sheet
	for k in int(d.anim.frames):
		var img: Image = _stitch(face, [int(first[0]), int(first[1]) + k * int(d.anim.stride)]) if k > 0 else d.sprite
		sprites.append(img)
		arts.append(PixelArt.downsample(img, scale) if k > 0 else d.art)
	d["anim_sprites"] = sprites
	d["anim_arts"] = arts


## A pulsing light's colour now (a block's or item's "pulse": Terraria's
## Demon Torch, Main.demonTorch going 0 -> 1 -> 0 by `step` a tick, the light
## from a to b).
static func pulse_color(pulse: Dictionary) -> Color:
	var phase := fmod(Time.get_ticks_msec() * 0.06 * float(pulse.get("step", 0.01)), 2.0)
	var d := phase if phase <= 1.0 else 2.0 - phase
	var a: Array = pulse.a
	var b: Array = pulse.b
	return Color(lerpf(a[0], b[0], d), lerpf(a[1], b[1], d), lerpf(a[2], b[2], d))


## How many frames a block's animation has (1: not animated).
static func anim_frames(d: Dictionary) -> int:
	return d.anim_sprites.size() if d.has("anim_sprites") else 1


## The frame a block's animation is on now: all of a kind animate together,
## like Terraria's (Main.tileFrame), at its ticks per frame.
static func anim_frame_now(d: Dictionary) -> int:
	var n := anim_frames(d)
	if n <= 1:
		return 0
	return int(Time.get_ticks_msec() * 0.06 / float(d.anim.ticks)) % n


## Re-processes every SpriteFx sprite (tree trunks and canopies) with the
## current SpriteFx settings (after they change; tests).
func rebuild_sprite_fx() -> void:
	for d in blocks:
		if d.has("fx"):
			var raw: Array[Image] = []
			raw.assign(d.raw_sprites)
			_set_sprites(d, raw, d.fx_ppb, d.fx)
			if is_placeable(d):
				d.render_id = render_for(d)
	_add_decoration_blocks()
	BlockModelMesh.clear_cache()


## Tree canopies as placeables: every style (each of Terraria's Tree_Tops
## sheets has 3 trees) is listed in the picker and the model sculptor with its
## own method, settings and model: "tree_canopy" (style 0), "tree_canopy@<style>".
## Default method: cross, as Terraria-style canopies have always been drawn.
func _add_decoration_blocks() -> void:
	decoration_blocks = []
	var all := CanopyArt.build_all()
	for style in CanopyArt.STYLE_IDS:
		var name := CanopyArt.block_name(style)
		var built: Dictionary = all[style]
		var img: Image = built.image
		var k: int = built.k
		var d := {"name": name, "base_render": 3, "decoration": true, "solid": false,
				"tex_top": NO_TEX, "tex_side": NO_TEX, "tex_bottom": NO_TEX, "variants": 1,
				"sprite": img, "sprite_px": built.px, "oversize": true}
		# Voxel methods work per pixel of the original art (k times coarser),
		# sampled from the middle of each k x k block of the processed canopy.
		d["art"] = PixelArt.downsample(img, Vector3i(k, k / 2, k / 2))
		d["art_scale"] = k
		d["art_px"] = d.sprite_px * k
		d["color"] = _average_color(img)
		d["canopy_style"] = style
		d["label"] = "Canopy: %s %d" % [CanopyArt.sheet_label(style / 10), style % 10 + 1]
		d["method"] = placeable_methods.get(name, default_method(d))
		d["render_id"] = render_for(d)
		block_ids[name] = DECORATION_BASE + decoration_blocks.size()
		decoration_blocks.append(d)
	_add_stair_blocks()


## Platform stairs (a platform hammered into a ramp): each platform's hidden
## twin "<platform>_stair", drawn like Terraria's (WorldGen.TileFrameImportant,
## TileDrawing.DrawBasicTile): every stair tile is its sheet's stair frame
## (Tiles_19 frame 8: two treads, low left, high right), and under a stair that
## goes on down diagonally Terraria draws its beam (frame 9) in the tile below.
## A block holds two stair tiles up its diagonal (rising toward +x), the beam
## under the upper one, and the lower one's beam, which hangs half a block below
## the block (stair_drop) to meet the next stair down, so a staircase is one
## piece. It shares the platform's method and settings, but not its transform
## (the plank's lift).
const STAIR_FRAME_X := 144
const STAIR_BEAM_X := 162


func _add_stair_blocks() -> void:
	for b in blocks:
		if not b.get("platform", false) or not b.has("sprite"):
			continue
		var face = b.get("tex", {}).get("all")
		if face == null:
			continue
		var sheet := Assets.image("Images/" + face.sheet)
		var row := int(face.frames[0][1])
		var img := Image.create(32, 48, false, Image.FORMAT_RGBA8)
		img.blit_rect(sheet, Rect2i(STAIR_FRAME_X, row, 16, 16), Vector2i(0, 16))
		img.blit_rect(sheet, Rect2i(STAIR_FRAME_X, row, 16, 16), Vector2i(16, 0))
		img.blit_rect(sheet, Rect2i(STAIR_BEAM_X, row, 16, 16), Vector2i(16, 16))
		img.blit_rect(sheet, Rect2i(STAIR_BEAM_X, row, 16, 16), Vector2i(0, 32))
		var name: String = b.name + "_stair"
		var d := {"name": name, "base_render": 3, "decoration": true, "solid": false, "stair": true,
				"tex_top": NO_TEX, "tex_side": NO_TEX, "tex_bottom": NO_TEX, "variants": 1,
				"sprite": img, "sprite_px": b.sprite_px, "oversize": false, "hidden": true,
				"settings": b.name, "no_transform": true, "color": b.get("color", Color(0.5, 0.4, 0.3)),
				"stair_drop": 16.0 * float(b.sprite_px)}
		var scale := PixelArt.detect_scale(img)
		d["art"] = PixelArt.downsample(img, scale)
		d["art_scale"] = scale.x
		d["art_px"] = d.sprite_px * scale.x
		d["method"] = b.get("method", default_method(b))
		d["render_id"] = 5
		block_ids[name] = DECORATION_BASE + decoration_blocks.size()
		decoration_blocks.append(d)


## Mean colour of the opaque pixels (used for block dust).
func _average_color(img: Image) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for y in range(0, img.get_height(), 3):
		for x in range(0, img.get_width(), 3):
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				sum += c
				n += 1
	return Color(sum.r / n, sum.g / n, sum.b / n) if n > 0 else Color(0.5, 0.4, 0.3)


## A cube face texture: a mosaic of `per_face` x `per_face` tiles, each a
## different frame of the face's sheet (Terraria's surrounded-tile frames tile
## seamlessly). The bottom row can use another crop ("lower"), e.g. dirt under a
## grass edge on grass block sides. `variant` varies which frames are used.
func _cube_layer(face: Dictionary, variant: int) -> Image:
	var n: int = int(face.get("per_face", TILES_PER_FACE))
	var out := Image.create(LAYER_SIZE, LAYER_SIZE, false, Image.FORMAT_RGBA8)
	var cell := LAYER_SIZE / n
	for cy in n:
		for cx in n:
			var spec: Dictionary = face
			if n > 1 and cy == n - 1 and face.has("lower"):
				spec = face.lower
			var frames: Array = spec.frames
			if spec.has("cells"):
				# Per-cell frames (row by row), e.g. Terraria's corner pieces.
				frames = spec.cells[mini(cy * n + cx, spec.cells.size() - 1)]
			# Spread variants and cells over the frames so neighbours differ.
			var fi := (variant * 7 + cx * 3 + cy * 5 + cx * cy) % frames.size()
			var turns := 0
			if spec.get("rotate", false):
				# Direction-free art (seen from above): random frame and quarter turn.
				var h := absi(hash(Vector3i(variant, cx, cy)))
				fi = h % frames.size()
				turns = (h / frames.size()) % 4
			var tile := _stitch(spec, frames[fi])
			if spec.has("fill"):
				tile = _fill_from_top(tile, face, absi(hash(Vector3i(variant, cx, cy + 17))))
			if spec != face.get("lower") and face.has("lower") and tile.get_height() < tile.get_width():
				tile = _pad_with_lower(tile, face.lower, fi)
			if spec.has("strip"):
				tile = _restrip(tile, spec.strip, variant * 31 + cx * 7 + cy * 13)
			if spec.has("recolor"):
				tile = _recolor(tile, spec.recolor)
			for t in turns:
				tile.rotate_90(CLOCKWISE)
			tile.resize(cell, cell, Image.INTERPOLATE_NEAREST)
			out.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(cx * cell, cy * cell))
	if face.has("outline"):
		_paint_outline(out, face, n, variant)
	return out


## A grass block side's grass in the top's texture: each pixel of the edge
## tile that is grass (nearer the top's colours than the soil's, "lower") takes
## the pixel of a top tile (a frame and quarter turn picked by `pick`, recoloured
## like the top), except the darkest grass pixels - the dark tips of Terraria's
## drips - which take the top's darkest colour, so the drip shape still shows.
func _fill_from_top(tile: Image, face: Dictionary, pick: int) -> Image:
	var top: Dictionary = face.fill
	var frames: Array = top.frames
	var src := _stitch(top, frames[pick % frames.size()])
	var ramp: Array = top.get("recolor", [])
	if not ramp.is_empty():
		src = _recolor(src, ramp)
	for t in (pick / frames.size()) % 4:
		src.rotate_90(CLOCKWISE)
	var grass_cols: Array = ramp.map(func(h): return Color(h))
	if grass_cols.is_empty():
		grass_cols = _palette(src)
	var soil_cols: Array = []
	if face.has("lower"):
		for f in face.lower.frames:
			soil_cols.append_array(_palette(_stitch(face.lower, f)))
	var nearest := func(c: Color, cols: Array) -> float:
		var best := INF
		for o in cols:
			best = minf(best, Vector3(c.r - o.r, c.g - o.g, c.b - o.b).length_squared())
		return best
	var grass := {}  # pixel colour -> true, for the edge's grass colours
	var darkest := Color(1, 1, 1)
	for c in _palette(tile):
		if nearest.call(c, grass_cols) < nearest.call(c, soil_cols):
			grass[c.to_rgba32()] = true
			if c.get_luminance() < darkest.get_luminance():
				darkest = c
	var dark_fill: Color = grass_cols.reduce(func(a, b): return a if a.get_luminance() < b.get_luminance() else b)
	var out: Image = tile.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.5 and grass.has(c.to_rgba32()):
				out.set_pixel(x, y, dark_fill if c == darkest else src.get_pixel(x % src.get_width(), y % src.get_height()))
	return out


## A short tile (a grass edge, cropped below its blades) made square with the
## bottom rows of a `lower` tile under it, instead of being stretched: its
## pixels stay square like the top's, and the dirt runs on seamlessly into the
## lower tile below (Terraria's middle frames tile with each other).
func _pad_with_lower(tile: Image, lower: Dictionary, pick: int) -> Image:
	var w := tile.get_width()
	var h := tile.get_height()
	var under := _stitch(lower, lower.frames[pick % lower.frames.size()])
	if lower.has("recolor"):
		under = _recolor(under, lower.recolor)
	under.resize(w, w * under.get_height() / under.get_width(), Image.INTERPOLATE_NEAREST)
	var out := Image.create(w, w, false, Image.FORMAT_RGBA8)
	out.blit_rect(tile, Rect2i(0, 0, w, h), Vector2i.ZERO)
	out.blit_rect(under, Rect2i(0, under.get_height() - (w - h), w, w - h), Vector2i(0, h))
	return out


## The distinct opaque colours of an image.
func _palette(img: Image) -> Array:
	var cols := {}
	for y in img.get_height():
		for x in img.get_width():
			var c := img.get_pixel(x, y)
			if c.a > 0.5:
				cols[c.to_rgba32()] = c
	return cols.values()


## Maps a tile's colours, darkest to lightest, onto `ramp` (hex colours, also
## darkest to lightest): e.g. Terraria's leaf block in the grass greens.
func _recolor(tile: Image, ramp: Array) -> Image:
	var cols := {}
	for y in tile.get_height():
		for x in tile.get_width():
			var c := tile.get_pixel(x, y)
			if c.a > 0.5:
				cols[c.to_rgba32()] = c
	var sorted: Array = cols.values()
	sorted.sort_custom(func(a: Color, b: Color): return a.get_luminance() < b.get_luminance())
	var map := {}
	for i in sorted.size():
		map[sorted[i].to_rgba32()] = Color(ramp[mini(ramp.size() - 1, i * ramp.size() / sorted.size())])
	var out: Image = tile.duplicate()
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			if c.a > 0.5:
				out.set_pixel(x, y, map[c.to_rgba32()])
	return out


## Puts the tile's own outline on the face's real left and right edges (one art
## pixel wide), e.g. a tree trunk's dark sides at the corners of the trunk
## block, while the inside of the face stays seamless. "outline": [left x, right x]
## are the outline columns relative to the frame, read from the sheet itself (so
## they may lie outside the cropped tile, like a trunk's right outline).
func _paint_outline(out: Image, face: Dictionary, n: int, variant: int) -> void:
	var frames: Array = face.frames
	var cell := LAYER_SIZE / n
	var sheet := Assets.image("Images/" + face.sheet)
	for cy in n:
		var frame: Array = frames[(variant + cy) % frames.size()]
		var tile := _stitch(face, frame)
		var k: int = PixelArt.detect_scale(tile).x
		var tile_w := tile.get_width()
		var tile_h := tile.get_height()
		var px_per_tex := float(cell) / tile_w  # layer pixels per texture pixel
		var width := int(round(k * px_per_tex))  # one art pixel
		for side in 2:
			var src_x: int = int(face.outline[side])
			var x0 := 0 if side == 0 else LAYER_SIZE - width
			for y in cell:
				var c := sheet.get_pixel(int(frame[0]) + src_x, int(frame[1]) + mini(tile_h - 1, int(y * float(tile_h) / cell)))
				for x in width:
					out.set_pixel(x0 + x, cy * cell + y, c)


## Rebuilds a tile from just the columns [strip[0], strip[1]) of its art (e.g.
## the bark between a tree trunk tile's dark outlines), arranged in a shuffled
## order across the whole tile width so it tiles seamlessly sideways. Works in
## art columns (2 texture pixels for Terraria's 2x art) to keep pixels square.
func _restrip(tile: Image, strip: Array, seed: int) -> Image:
	var k: int = PixelArt.detect_scale(tile).x
	var first := int(strip[0]) / k
	var count := maxi(1, (int(strip[1]) - int(strip[0])) / k)
	var w := tile.get_width()
	var out := Image.create(w, tile.get_height(), false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var last := -1
	for col in w / k:
		var pick := rng.randi() % count
		if pick == last:
			pick = (pick + 1) % count  # avoid wide flat stripes
		last = pick
		var src := (first + pick) * k
		out.blit_rect(tile, Rect2i(src, 0, k, tile.get_height()), Vector2i(col * k, 0))
	return out


## One frame of a Terraria tile sheet, stitched from its tiles (skipping the
## 2 px padding between them).
func _stitch(face: Dictionary, frame: Array) -> Image:
	var sheet := Assets.image("Images/" + face.sheet)
	var tile: Array = face.get("tile", [16, 16])
	var tiles: Array = face.get("tiles", [1, 1])
	var stride: int = face.get("stride", 18)
	if frame.size() > 0 and frame[0] is Array:
		# Tiles from anywhere on the sheet, stacked top to bottom.
		var stack := Image.create(int(tile[0]), int(tile[1]) * frame.size(), false, Image.FORMAT_RGBA8)
		for k in frame.size():
			stack.blit_rect(sheet, Rect2i(int(frame[k][0]), int(frame[k][1]), int(tile[0]), int(tile[1])), Vector2i(0, k * int(tile[1])))
		return stack
	var sprite := Image.create(int(tile[0]) * int(tiles[0]), int(tile[1]) * int(tiles[1]), false, Image.FORMAT_RGBA8)
	for ty in int(tiles[1]):
		for tx in int(tiles[0]):
			var src := Rect2i(int(frame[0]) + tx * stride, int(frame[1]) + ty * stride, int(tile[0]), int(tile[1]))
			sprite.blit_rect(sheet, src, Vector2i(tx * int(tile[0]), ty * int(tile[1])))
	return sprite


## Sprite pixels per block: PIXELS_PER_BLOCK (real Terraria size), or the
## face's "pixels_per_block" (tree trunks: one tile per block).
func _pixels_per_block(face: Dictionary) -> int:
	return int(face.get("pixels_per_block", PIXELS_PER_BLOCK))


## Layer pixels per sprite pixel: sprites keep their in-game size instead of
## being fitted to the block.
func _sprite_scale(face: Dictionary, _size: Vector2i) -> int:
	return LAYER_SIZE / _pixels_per_block(face)


## Crops one variant from a Terraria tile sheet into a LAYER_SIZE square image.
## Cube faces are stretched to fill; sprites keep integer scaling, bottom-centred.
func _crop_layer(face: Dictionary, frame: Array, fill: bool) -> Image:
	var sprite := _stitch(face, frame)
	var w := sprite.get_width()
	var h := sprite.get_height()
	if fill:
		sprite.resize(LAYER_SIZE, LAYER_SIZE, Image.INTERPOLATE_NEAREST)
		return sprite
	var scale := _sprite_scale(face, sprite.get_size())
	sprite.resize(w * scale, h * scale, Image.INTERPOLATE_NEAREST)
	var out := Image.create(LAYER_SIZE, LAYER_SIZE, false, Image.FORMAT_RGBA8)
	out.blit_rect(sprite, Rect2i(Vector2i.ZERO, sprite.get_size()), Vector2i((LAYER_SIZE - w * scale) / 2, LAYER_SIZE - h * scale))
	return out


# ------------------------------------------------------------------ placeables

## Sprite blocks (not full cubes) can be shown with any placeable method,
## unless their look is fixed ("fixed_method": glass panes).
func is_placeable(d: Dictionary) -> bool:
	return d.get("base_render", 1) in [2, 3] and d.has("sprite") and not d.get("fixed_method", false)


func default_method(d: Dictionary) -> String:
	if d.has("default_method"):
		return d.default_method
	return "cross" if d.get("base_render", 2) == 3 else "panels"


## Render kind for a placeable: its method's, except that oversize sprites are
## always block models.
func render_for(d: Dictionary) -> int:
	var r := method_render(d.get("method", "panels"))
	# Wall torches hang off the wall, and a transform moves the model: those
	# are always block models (the chunk mesher draws panels/cross in place).
	# Animated ones too: their frames are swapped on the models.
	return 5 if d.get("oversize", false) or d.get("wall", false) or has_transform(d) or d.has("anim_sprites") else r


static func method_render(method: String) -> int:
	match method:
		"panels": return 2
		"cross": return 3
		_: return 5


func placeable_blocks() -> Array:
	var list := blocks.filter(func(b): return is_placeable(b) and not b.get("hidden", false)).map(func(b): return b.name)
	for d in decoration_blocks:
		if not d.get("hidden", false):
			list.append(d.name)
	return list


func load_placeables(path := PLACEABLES_PATH) -> void:
	placeable_methods = {}
	extrude_settings = {}
	noise_settings = {"hull": {}, "hull_top": {}, "lathe": {}, "claude": {}, "tuned": {}}
	rendered_settings = {}
	transform_settings = {}
	_placeables_units = "art"
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			for k in parsed.get("methods", {}):
				if parsed.methods[k] in PLACEABLE_METHODS:
					placeable_methods[k] = parsed.methods[k]
			_placeables_units = parsed.get("units", "texture")
			var ex = parsed.get("extruded", {})
			if ex is Dictionary:
				for k in ex:
					if ex[k] is Dictionary:
						extrude_settings[k] = ex[k]
			for m in ["hull", "hull_top", "lathe", "claude", "tuned"]:
				var section = parsed.get(m, {})
				if section is Dictionary:
					for k in section:
						if section[k] is Dictionary:
							noise_settings[m][k] = section[k]
			var rs = parsed.get("rendered", {})
			if rs is Dictionary:
				for k in rs:
					if rs[k] is Dictionary:
						rendered_settings[k] = rs[k]
			var tr = parsed.get("transform", {})
			if tr is Dictionary:
				for k in tr:
					if tr[k] is Dictionary:
						transform_settings[k] = tr[k]
			if not parsed.get("canopies_split", false):
				_split_canopies()


## Files from before every canopy had its own choices kept one set for all of
## them ("tree_canopy"'s): each canopy starts with a copy of it, so nothing
## changes until it's chosen apart (saving marks the file "canopies_split").
func _split_canopies() -> void:
	var stores: Array = [placeable_methods, extrude_settings, rendered_settings, transform_settings] + noise_settings.values()
	for style in CanopyArt.STYLE_IDS:
		var name := CanopyArt.block_name(style)
		if name == "tree_canopy":
			continue
		for store in stores:
			if store.has("tree_canopy") and not store.has(name):
				var v = store.tree_canopy
				store[name] = v.duplicate(true) if v is Dictionary else v


## How a placeable is named in the pickers: its label (canopies: which art),
## else its name.
func placeable_label(name: String) -> String:
	return block(block_id(name)).get("label", name.replace("_", " ").capitalize())


## How big each NPC appears (the NPC scale editor, ./npc_scale_editor.sh):
## kind -> {scale: times its size in npcs.json, hitbox: whether its hitbox
## grows with it (else only the sprite does)}.
const NPC_SCALES_PATH := "res://data/npc_scales.json"
var npc_scales := {}


func load_npc_scales(path := NPC_SCALES_PATH) -> void:
	npc_scales = {}
	var d := _read_json(path) if FileAccess.file_exists(path) else {}
	for k in d:
		if not k.begins_with("_") and d[k] is Dictionary:
			npc_scales[k] = d[k]


## An NPC's scale settings, defaults filled in.
func npc_scale(kind: String) -> Dictionary:
	var s: Dictionary = npc_scales.get(kind, {})
	return {"scale": clampf(float(s.get("scale", 1.0)), 0.1, 10.0), "hitbox": bool(s.get("hitbox", true))}


## Sets an NPC's scale (only what differs from the defaults is kept).
func set_npc_scale(kind: String, scale: float, hitbox := true) -> void:
	if is_equal_approx(scale, 1.0) and hitbox:
		npc_scales.erase(kind)
	else:
		npc_scales[kind] = {"scale": snappedf(scale, 0.01), "hitbox": hitbox}


func save_npc_scales(path := NPC_SCALES_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	var out := {"_doc": "NPC display sizes from ./npc_scale_editor.sh: scale multiplies the size in npcs.json; hitbox false scales only the sprite."}
	var keys := npc_scales.keys()
	keys.sort()
	for k in keys:
		out[k] = npc_scales[k]
	f.store_string(JSON.stringify(out, "\t", false))
	return true


func save_placeables(path := PLACEABLES_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	var out := {"units": "art", "canopies_split": true, "methods": placeable_methods, "extruded": extrude_settings,
			"hull": noise_settings.hull, "hull_top": noise_settings.hull_top, "lathe": noise_settings.lathe, "claude": noise_settings.claude, "tuned": noise_settings.tuned}
	if not rendered_settings.is_empty():
		out["rendered"] = rendered_settings
	if not transform_settings.is_empty():
		out["transform"] = transform_settings
	f.store_string(JSON.stringify(out, "\t", true))
	return true


## Converts depth/bevel sizes saved in texture pixels to art voxels (once the
## sprites, and so their art scales, are known).
func _migrate_placeables() -> void:
	if _placeables_units == "art":
		return
	for name in extrude_settings:
		var k: int = block(block_id(name)).get("art_scale", 1)
		var o: Dictionary = extrude_settings[name]
		for key in ["depth", "bevel_size"]:
			if o.has(key):
				o[key] = maxi(1, roundi(float(o[key]) / k))
	_placeables_units = "art"


## Thickest extrusion for a block, in art voxels: one full block (or, for
## decorations bigger than a block, their width).
func extrude_max_depth(name: String) -> int:
	var d := block(block_id(name))
	var full := roundi(1.0 / float(d.get("art_px", 1.0 / 16.0)))
	if d.get("decoration", false) and d.has("art"):
		full = maxi(full, d.art.get_width())
	return maxi(1, full)


## Extruded settings for a block, with defaults filled in. The default depth is
## the art's width, so its footprint is square.
func extrude_options(name: String) -> Dictionary:
	var d := block(block_id(name))
	var width: int = d.art.get_width() if d.has("art") else 8
	var o := {"depth": mini(width, extrude_max_depth(name)), "noise": "none", "strength": 0.5, "seed": 0,
			"bevel": "none", "bevel_size": 2, "one_color": false, "no_outline": false}
	o.merge(extrude_settings.get(name, {}), true)
	o.no_outline = bool(o.no_outline)
	o.depth = clampi(int(o.depth), 1, extrude_max_depth(name))
	o.seed = int(o.seed)
	o.strength = clampf(float(o.strength), 0.0, 1.0)
	o.one_color = bool(o.one_color)
	if not o.noise in EXTRUDE_NOISES:
		o.noise = "none"
	if not o.bevel in EXTRUDE_BEVELS:
		o.bevel = "none"
	o.bevel_size = clampi(int(o.bevel_size), 1, BEVEL_MAX)
	# Which sides get the bevel, in BlockModelMesh.BEVEL_SIDES order.
	var sides: Array = o.get("bevel_sides", BlockModelMesh.BEVEL_SIDES)
	o.bevel_sides = BlockModelMesh.BEVEL_SIDES.filter(func(side): return side in sides)
	return o


func set_extrude_option(name: String, key: String, value) -> void:
	var o: Dictionary = extrude_settings.get(name, {}).duplicate()
	o[key] = value
	extrude_settings[name] = o


## Settings for any noise method: extruded's full set, or hull/lathe/claude/tuned
## noise and one colour per voxel.
func method_options(name: String, method: String) -> Dictionary:
	if method == "extruded":
		return extrude_options(name)
	if method == "rendered":
		var model = rendered_settings.get(name, {}).get("model", "auto")
		return {"model": model if model in RENDER_MODELS else "auto", "outline": bool(rendered_settings.get(name, {}).get("outline", false))}
	var o := {"noise": "none", "strength": 0.5, "seed": 0, "one_color": false}
	if method in OUTLINE_METHODS:
		o.no_outline = false
	o.merge(noise_settings.get(method, {}).get(name, {}), true)
	o.seed = int(o.seed)
	o.one_color = bool(o.one_color)
	if o.has("no_outline"):
		o.no_outline = bool(o.no_outline)
	o.strength = clampf(float(o.strength), 0.0, 1.0)
	if not o.noise in EXTRUDE_NOISES:
		o.noise = "none"
	return o


func set_method_option(name: String, method: String, key: String, value) -> void:
	if method == "extruded":
		set_extrude_option(name, key, value)
		return
	var store: Dictionary = rendered_settings if method == "rendered" else noise_settings[method]
	var o: Dictionary = store.get(name, {}).duplicate()
	o[key] = value
	store[name] = o


func reset_method_options(name: String, method: String) -> void:
	if method == "extruded":
		extrude_settings.erase(name)
	elif method == "rendered":
		rendered_settings.erase(name)
	else:
		noise_settings[method].erase(name)


## A block's model transform settings, defaults filled in and values checked:
## {offset: [x, y, z] in art pixels, rotation: [x, y, z] degrees, scale}.
func transform_options(name: String) -> Dictionary:
	var saved: Dictionary = transform_settings.get(name, {})
	var defaults := transform_defaults(name)
	var o := {}
	for key in ["offset", "rotation"]:
		var v = saved.get(key, defaults[key])
		o[key] = [float(v[0]), float(v[1]), float(v[2])] if v is Array and v.size() == 3 else [0.0, 0.0, 0.0]
	o.scale = clampf(float(saved.get("scale", defaults.scale)), 0.05, 8.0)
	return o


## A block's transform before any picker changes: TRANSFORM_DEFAULTS, with its
## blocks.json "transform" on top (a platform's plank lifted to the top of its
## block, where you stand).
func transform_defaults(name: String) -> Dictionary:
	var o := TRANSFORM_DEFAULTS.duplicate()
	o.merge(block(block_id(name)).get("transform", {}), true)
	return o


## Changes one transform setting ("offset"/"rotation" take [x, y, z]); only
## what differs from the defaults is kept. Twins (canopy styles) follow.
func set_transform_option(name: String, key: String, value) -> void:
	var o: Dictionary = transform_settings.get(name, {}).duplicate()
	var default = transform_defaults(name)[key]
	if (value is Array and Vector3(value[0], value[1], value[2]) == Vector3(default[0], default[1], default[2])) \
			or (not value is Array and is_equal_approx(float(value), float(default))):
		o.erase(key)
	else:
		o[key] = value
	if o.is_empty():
		transform_settings.erase(name)
	else:
		transform_settings[name] = o
	_refresh_render(name)


func reset_transform(name: String) -> void:
	transform_settings.erase(name)
	_refresh_render(name)


## True if a block's model is moved, turned or scaled.
func has_transform(d: Dictionary) -> bool:
	if d.get("no_transform", false):
		return false
	return transform_settings.has(d.get("settings", d.get("name", ""))) or d.has("transform")


## A block's model transform (about the bottom centre of its block, before the
## block's own facing): scale, then rotation (Y, X, Z order), then offset.
func block_transform(d: Dictionary) -> Transform3D:
	if not has_transform(d):
		return Transform3D()
	var o := transform_options(d.get("settings", d.name))
	var r: Array = o.rotation
	var basis := Basis.from_euler(Vector3(deg_to_rad(r[0]), deg_to_rad(r[1]), deg_to_rad(r[2])), EULER_ORDER_YXZ)
	var px := float(d.get("art_px", d.get("sprite_px", 1.0 / 16.0)))
	var off: Array = o.offset
	return Transform3D(basis * Basis.from_scale(Vector3.ONE * o.scale), Vector3(off[0], off[1], off[2]) * px)


func _refresh_render(name: String) -> void:
	for d in blocks + decoration_blocks:
		if d.get("name", "") == name or d.get("settings", "") == name:
			if d.has("render_id"):
				d.render_id = render_for(d)


## Back to built-in defaults in memory (tests; the saved file is untouched).
func reset_placeables() -> void:
	extrude_settings = {}
	noise_settings = {"hull": {}, "hull_top": {}, "lathe": {}, "claude": {}, "tuned": {}}
	rendered_settings = {}
	transform_settings = {}
	for name in placeable_blocks():
		set_block_method(name, default_method(block(block_id(name))))
	placeable_methods = {}


## Changes how a placeable block is drawn (re-register blocks with the world
## after). Switched to "rendered" from a voxel method, its shots are of that
## method's model.
func set_block_method(name: String, method: String) -> void:
	var d := block(block_id(name))
	if d.is_empty() or not is_placeable(d):
		return
	var was: String = d.get("method", default_method(d))
	if method == "rendered" and was != "rendered" and was in RENDER_MODELS:
		set_method_option(name, "rendered", "model", was)
	d.method = method
	d.render_id = render_for(d)
	# Hidden twins (canopy styles) follow the listed block.
	for twin in blocks + decoration_blocks:
		if twin.get("settings", "") == name:
			twin.method = method
			twin.render_id = render_for(twin)
	if method == default_method(d):
		placeable_methods.erase(name)
	else:
		placeable_methods[name] = method


## Everything chosen for a placeable in the picker (its settings name's):
## its method, every method's settings and its transform, to paste onto
## another (paste_placeable). Missing entries are its defaults.
func copy_placeable(name: String) -> Dictionary:
	var out := {}
	for k in _placeable_stores():
		var store: Dictionary = _placeable_stores()[k]
		if store.has(name):
			var v = store[name]
			out[k] = v.duplicate(true) if v is Dictionary else v
	return out


## Makes a placeable's choices those copied from another (copy_placeable):
## the method, each method's settings and the transform, what the copy didn't
## have going back to the defaults. A Claude or tuned method the block has no
## model for isn't taken (it keeps its own). Returns whether the method was.
func paste_placeable(name: String, copied: Dictionary, has_model: Callable) -> bool:
	var stores := _placeable_stores()
	for k in stores:
		if k == "methods":
			continue
		var store: Dictionary = stores[k]
		if copied.has(k):
			store[name] = copied[k].duplicate(true)
		else:
			store.erase(name)
	var d := block(block_id(name))
	var method: String = copied.get("methods", default_method(d))
	if method in ["claude", "tuned"] and not has_model.call(name, method):
		return false
	set_block_method(name, method)
	return true


## The picker's stores of choices by name: methods, extruded, the noise
## methods', rendered, transform.
func _placeable_stores() -> Dictionary:
	var out := {"methods": placeable_methods, "extruded": extrude_settings, "rendered": rendered_settings, "transform": transform_settings}
	for m in noise_settings:
		out[m] = noise_settings[m]
	return out


func register_blocks(world: VoxelWorld) -> void:
	for id in range(1, blocks.size()):
		var b := blocks[id]
		var emit: Array = b.get("emit", [0, 0, 0])
		world.define_block(id, {
			"name": b.name,
			"render": b.render_id,
			"solid": b.get("solid", true),
			"opaque": b.get("opaque", b.render_id == 1),
			"tex_top": b.tex_top,
			"tex_side": b.tex_side,
			"tex_bottom": b.tex_bottom,
			"variants": b.variants,
			"emit": Color(emit[0], emit[1], emit[2]),
			"platform": b.get("platform", false),
			"sun_through": b.get("sun_through", false),
			# A plant or bit of debris whose crossed sprite is mirrored in some
			# cells (the chunk mesher; BlockModels turns and mirrors the rest).
			"vary": b.get("vary", false),
			# One of that block's styles (worldgen's scatter_styles).
			"variant_of": block_id(b.variant_of) if b.has("variant_of") else 0,
			# Grass (its side is dirt under a grass fringe): sides down a slope
			# show the grass top, like OptiFine's Better Grass (Fancy).
			# (Not Planter Boxes: soil over wood, but no grass top to show.)
			"better_grass": b.get("tex", {}).get("side", {}).get("fill_top", false) if b.get("tex", {}).get("side") is Dictionary else false,
			# Far terrain draws blocks in these (lod.rs).
			"color_top": b.get("color_top", b.get("color", Color(0.5, 0.5, 0.5))),
			"color_side": b.get("color", Color(0.5, 0.5, 0.5)),
		})


# ------------------------------------------------------------------ items

func item(name: String) -> Dictionary:
	return items.get(name, {})


## A stack's item, with its prefix if it has one (Prefixes.of); {} for none.
func item_of(stack) -> Dictionary:
	if stack == null:
		return {}
	var pre := int(stack.get("prefix", 0))
	return Prefixes.of(stack.item, pre) if pre > 0 else item(stack.item)


func item_id(name: String) -> int:
	return int(Assets.ids.ItemID.get(name, 0))


## An animated item's animation (Terraria's item animations: its sprite is
## frames stacked down the sheet): {frames, ticks, ping_pong}, or {}.
func item_anim(id: int) -> Dictionary:
	if _item_anims.is_empty():
		_item_anims[-1] = {}
		for n in items:
			if items[n].has("anim"):
				_item_anims[item_id(n)] = items[n].anim
	return _item_anims.get(id, {})


## Which frame an animated item shows `seconds` in (ping-pong goes back and
## forth: 0..n-1..1).
static func item_frame(anim: Dictionary, seconds: float) -> int:
	var n := int(anim.get("frames", 1))
	if n <= 1:
		return 0
	var step := int(seconds * 60.0 / float(anim.get("ticks", 5)))
	if anim.get("ping_pong", false):
		var k := step % (2 * n - 2)
		return k if k < n else 2 * n - 2 - k
	return step % n


var _item_anims := {}


func _add_item(name: String, def: Dictionary) -> void:
	var d := def.duplicate()
	d["internal"] = name
	d["id"] = item_id(name)
	if d.id == 0:
		push_warning("unknown Terraria item " + name)
	d["name"] = Assets.item_name(name)
	d["max_stack"] = d.get("max_stack", 1 if d.get("type", "material") in ["melee", "ranged", "magic", "tool", "accessory", "armor", "fishing_pole", "pet", "mount"] else 9999)
	# Terraria's autoReuse: tools, buckets and blocks keep going while held;
	# weapons and consumables take a fresh click each time.
	d["auto_reuse"] = d.get("auto_reuse", d.get("type", "material") in ["tool", "bucket", "block"])
	items[name] = d
	item_by_id[d.id] = name


func _load_items() -> void:
	var data := _read_json("res://data/items.json")
	for name in data.items:
		_add_item(name, data.items[name])

	# Expand metal tiers into tools, weapons and armor (their recipes are
	# Terraria's, below).
	for t in data.tiers:
		var m: String = t.metal
		var speed: float = t.get("speed", 1.0)
		_add_item(m + "Ore", {"type": "block", "place": m.to_lower() + "_ore", "value": t.get("ore_value", 0)})
		_add_item(m + "Bar", {"type": "material"})
		_add_item(m + "Pickaxe", {"type": "tool", "pick": t.pick, "damage": t.tool_damage, "use_time": int(t.get("pick_speed", 15 / speed)), "knockback": 2, "style": "swing"})
		_add_item(m + "Axe", {"type": "tool", "axe": t.axe, "damage": t.tool_damage + 1, "use_time": int(t.get("axe_speed", 21 / speed)), "knockback": 4.5, "style": "swing"})
		_add_item(m + "Hammer", {"type": "tool", "hammer": t.pick + 5, "damage": t.tool_damage + 3, "use_time": int(23 / speed), "knockback": 5.5, "style": "swing"})
		_add_item(m + "Broadsword", {"type": "melee", "damage": t.sword, "use_time": int(20 / speed), "knockback": 5, "style": "swing"})
		_add_item(m + "Shortsword", {"type": "melee", "damage": t.sword - 2, "use_time": int(12 / speed), "knockback": 4, "style": "thrust"})
		_add_item(m + "Bow", {"type": "ranged", "damage": t.bow, "use_time": int(27 / speed), "knockback": 0, "style": "hold", "ammo": "WoodenArrow", "shoot_speed": 34})
		# Armor: Helmet, Chainmail, Greaves, and the set's extra defense.
		if t.has("armor"):
			var pieces := [m + "Helmet", m + "Chainmail", m + "Greaves"]
			for i in 3:
				_add_item(pieces[i], {"type": "armor", "slot": ARMOR_SLOTS[i], "defense": t.armor[i]})
			var sd := int(t.set_defense)
			armor_sets.append({"head": pieces[0], "body": pieces[1], "legs": pieces[2], "defense": sd,
					"text": "Platinum" if sd >= 4 else ("MetalTier2" if sd == 3 else "MetalTier1")})

	for a in data.get("armor_sets", []):
		armor_sets.append(a)
	_load_terraria_recipes()
	shimmer = _read_json(Assets.ROOT + "shimmer.json") if FileAccess.file_exists(Assets.ROOT + "shimmer.json") else {}
	_load_tile_dust()
	_load_npc_gore()
	# Stand-ins (items.json "recipes"): only for items none of whose Terraria
	# recipes can be made yet (an ingredient or station this game lacks).
	var craftable := {}
	for r in recipes:
		craftable[r.result] = true
	for r in data.recipes:
		if not craftable.has(r.result):
			recipes.append(r)
	for r in recipes:
		r["count"] = int(r.get("count", 1))
		# Terraria's "Any Wood": every kind of wood counts as Wood (not in
		# "exact" recipes, like the Wooden Door's).
		if r.ingredients.has("Wood") and not r.get("exact", false):
			r.ingredients[ANY_WOOD] = r.ingredients["Wood"]
			r.ingredients.erase("Wood")
		if not items.has(r.result):
			push_warning("recipe for unknown item " + r.result)


## Terraria's crafting stations (TileID names) and the blocks here that are them.
const TERRARIA_STATIONS := {
	"WorkBenches": "work_bench", "Furnaces": "furnace", "Anvils": "iron_anvil", "Sawmill": "sawmill",
	"Loom": "loom", "DemonAltar": "demon_altar", "Bottles": "bottles", "Solidifier": "solidifier",
	"TinkerersWorkbench": "tinkerers_workshop", "Campfire": "campfire", "Hellforge": "hellforge",
	"CookingPots": "cooking_pot", "ImbuingStation": "imbuing_station",
}
## Terraria's "near a liquid" recipe conditions: the liquid counts as a
## station when it's within reach (Game.nearby_stations).
const LIQUID_FLAGS := {"needWater": "water", "needHoney": "honey", "needLava": "lava"}
## Terraria's recipe groups: which ingredient they widen, and to what.
const TERRARIA_GROUPS := {
	"Wood": ["Wood", ANY_WOOD], "IronBar": ["IronBar", "IronBar|LeadBar"],
	"SilverBar": ["SilverBar", "SilverBar|TungstenBar"], "GoldBar": ["GoldBar", "GoldBar|PlatinumBar"],
	"Sand": ["SandBlock", "SandBlock|EbonsandBlock|CrimsandBlock"],
	"Stone": ["StoneBlock", "StoneBlock|EbonstoneBlock|CrimstoneBlock"],
}
## Recipe conditions this game doesn't have (graveyards, the Torch God...).
const UNMET_FLAGS := ["needGraveyardBiome", "needTorchGodsFavor", "needMechdusa", "needSnowBiome"]
var TERRARIA_RECIPES: String = Assets.ROOT + "recipes.json"
var TILE_DUST: String = Assets.ROOT + "tile_dust.json"
var NPC_GORE: String = Assets.ROOT + "npc_gore.json"


func _load_npc_gore() -> void:
	var f := FileAccess.open(NPC_GORE, FileAccess.READ)
	if f == null:
		push_warning("no NPC gore (run ./extract_assets.sh)")
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		npc_gore = d.get("npcs", {})


func _load_tile_dust() -> void:
	var f := FileAccess.open(TILE_DUST, FileAccess.READ)
	if f == null:
		push_warning("no tile dust (run ./extract_assets.sh)")
		return
	var d = JSON.parse_string(f.get_as_text())
	if d is Dictionary:
		tile_dust = d.get("blocks", {})


## Records a Terraria recipe as its item's way apart in Shimmer
## (Recipe.UpdateWhichItemsAreCrafted: the last one wins).
func _add_decraft(t: Dictionary) -> void:
	if not items.has(t.result):
		return
	var r := {"count": int(t.count), "ingredients": t.ingredients, "alchemy": t.tiles.size() > 0 and t.tiles[0] == "Bottles"}
	if t.has("shimmer"):
		r["shimmer"] = t.shimmer
	var d: Dictionary = decrafts.get(t.result, {})
	if not "notDecraftable" in t.flags:
		d["any"] = r
	for evil in ["crimson", "corruption"]:
		if evil in t.flags:
			d[evil] = r
	if not d.is_empty():
		decrafts[t.result] = d


## Terraria's own recipes (tools/terraria_recipes.py, from the user's
## Terraria.exe), for every item here, where everything they take (items,
## stations) is in this game too.
func _load_terraria_recipes() -> void:
	var f := FileAccess.open(TERRARIA_RECIPES, FileAccess.READ)
	if f == null:
		push_warning("no Terraria recipes (run ./extract_assets.sh)")
		return
	var list = JSON.parse_string(f.get_as_text())
	if not list is Array:
		return
	for t in list:
		_add_decraft(t)
		if not items.has(t.result) or t.ingredients.is_empty() or t.flags.any(func(fl): return fl in UNMET_FLAGS):
			continue
		# (Terraria's coin exchanges: here coins join up by themselves.)
		if item(t.result).get("type") == "coin":
			continue
		var stations := []
		var ok := true
		for tile in t.tiles:
			if not TERRARIA_STATIONS.has(tile):
				ok = false
			else:
				stations.append(TERRARIA_STATIONS[tile])
		for fl in t.flags:
			if LIQUID_FLAGS.has(fl):
				stations.append(LIQUID_FLAGS[fl])
		var ings := {}
		for ing in t.ingredients:
			var name: String = ing[0]
			if not items.has(name):
				ok = false
				break
			for g in t.groups:
				if TERRARIA_GROUPS.has(g) and TERRARIA_GROUPS[g][0] == name:
					name = TERRARIA_GROUPS[g][1]
			ings[name] = int(ing[1]) + int(ings.get(name, 0))
		if not ok:
			continue
		var r := {"result": t.result, "count": int(t.count), "ingredients": ings, "exact": true, "terraria": true}
		if stations.size() == 1:
			r["station"] = stations[0]
		elif stations.size() > 1:
			r["station"] = stations[0]
			r["stations"] = stations
		recipes.append(r)


## An item's price in copper coins (Terraria's value: shops sell at it, buy
## at a fifth): its own "value", else what its recipe's ingredients are worth
## (per item made), else 0.
func value(name: String) -> int:
	if _values.has(name):
		return _values[name]
	_values[name] = 0  # (a recipe loop counts as worthless)
	var v := 0
	var def := item(name)
	if def.has("value"):
		v = int(def.value)
	else:
		for r in recipes:
			if r.result == name:
				var total := 0.0
				for ing in r.ingredients:
					var first: String = ing.split("|")[0]
					total += value(first) * int(r.ingredients[ing])
				v = int(round(total / maxi(1, int(r.count))))
				break
	_values[name] = v
	return v

var _values := {}


## The item that places a block (else what it drops): creative pick block.
func block_item(block_id: int) -> String:
	var name: String = block(block_id).get("name", "")
	for k in items:
		if items[k].get("place", "") == name:
			return k
	return block_drop(block_id)


## Item that a block drops when mined.
func block_drop(block_id: int) -> String:
	return block(block_id).get("drop", "")


## Block texture layer `layer`'s picture, from whichever array holds it.
func layer_image(layer: int) -> Image:
	if layer >= MAX_LAYERS:
		return block_textures_2.get_layer_data(layer - MAX_LAYERS)
	return block_textures.get_layer_data(layer)
