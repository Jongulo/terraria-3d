class_name NPCModels
## How each enemy, boss and town NPC is shown in 3D (the NPC picker,
## ./npc_picker.sh, saves data/npc_models.json): a camera-facing billboard (as
## before), or one of the placeable methods applied to every frame of its
## sprite sheet: two crossed planes, a one-voxel cut-out, the sprite pushed
## through (extruded), carved from its front and side silhouettes (hull) or
## front and top ones (hull_top), spun round (lathe), sculpted by hand
## (claude: NPCSculpt, data/handmade_npc_models.json; others show the hull), or
## tuned in the model sculptor (tuned: TunedModels, data/tuned/; others show
## the hull), or drawn as a sprite again from shots of its voxel model from
## every angle (rendered: NPCRenders, RenderedSprite; Fallout 1's way; its
## "model" setting picks what's shot: auto, its tuned, Claude or hull model, or
## extruded, the Extruded model with its own settings). Every voxel method can
## keep one colour per voxel (one_color).
## Meshes are built at the sprite's art resolution, in blocks, bottom centre at
## the origin with the art's face toward +z and its left toward -x; each frame
## is built when first shown and kept.

const PATH := "res://data/npc_models.json"
## What the rendered method shoots (NPCRenders.source).
const RENDER_MODELS := ["auto", "extruded"]
const METHODS := ["billboard", "cross", "flat", "extruded", "hull", "hull_top", "lathe", "claude", "tuned", "rendered"]
const NOISE_METHODS := ["extruded", "hull", "hull_top", "lathe", "claude", "tuned"]
const DESCRIPTIONS := {
	"billboard": "Always faces you",
	"cross": "Two crossed planes",
	"flat": "1 voxel thick cut-out",
	"extruded": "Sprite pushed through",
	"hull": "Front + side silhouettes",
	"hull_top": "Front + top silhouettes",
	"lathe": "Outline spun around",
	"claude": "Hand-made voxels",
	"tuned": "Sculpted by you",
	"rendered": "Model shot from every angle",
}

static var methods := {}
static var extruded := {}
## kind -> the rendered method's settings ({model}).
static var rendered := {}
static var noise := {"hull": {}, "hull_top": {}, "lathe": {}, "claude": {}, "tuned": {}}
static var _loaded := false
static var _frames := {}
static var _meshes := {}
static var _materials := {}
static var _textures := {}
## Meshes being built on worker threads: key -> [task id, {arrays}].
static var _pending := {}


static func ensure_loaded() -> void:
	if not _loaded:
		load_file()


## Reads the saved choices (missing or broken file: every NPC a billboard).
static func load_file(path := PATH) -> void:
	_loaded = true
	methods = {}
	extruded = {}
	rendered = {}
	noise = {"hull": {}, "hull_top": {}, "lathe": {}, "claude": {}, "tuned": {}}
	clear_cache()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var d = JSON.parse_string(f.get_as_text())
	if not d is Dictionary:
		return
	for k in d.get("methods", {}):
		if d.methods[k] in METHODS:
			methods[k] = d.methods[k]
	if d.get("extruded") is Dictionary:
		extruded = d.extruded
	if d.get("rendered") is Dictionary:
		rendered = d.rendered
	for m in ["hull", "hull_top", "lathe", "claude", "tuned"]:
		if d.get(m) is Dictionary:
			noise[m] = d[m]


static func save(path := PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"methods": methods, "extruded": extruded, "rendered": rendered, "hull": noise.hull, "hull_top": noise.hull_top, "lathe": noise.lathe, "claude": noise.claude, "tuned": noise.tuned}, "\t", true))
	return true


static func method(kind: String) -> String:
	ensure_loaded()
	return methods.get(kind, "billboard")


static func set_method(kind: String, m: String) -> void:
	ensure_loaded()
	if m == "billboard":
		methods.erase(kind)
	else:
		methods[kind] = m


## Thickest extrusion: the art's width (a square footprint).
static func max_depth(kind: String) -> int:
	return maxi(1, frames_of(kind).art_w)


## A method's settings with defaults filled in: extruded {depth, noise,
## strength, seed, bevel, bevel_size, bevel_sides}; hull and lathe {noise,
## strength, seed}; every voxel method one_color, and the ones that work the
## sprite out themselves (Data.OUTLINE_METHODS) no_outline; rendered {model,
## outline}. The default depth is half the art's width.
static func options(kind: String, m: String) -> Dictionary:
	ensure_loaded()
	if m == "rendered":
		var model = rendered.get(kind, {}).get("model", "auto")
		return {"model": model if model in RENDER_MODELS else "auto", "outline": bool(rendered.get(kind, {}).get("outline", false))}
	var o := {"noise": "none", "strength": 0.5, "seed": 0, "one_color": false}
	if m in Data.OUTLINE_METHODS:
		o.no_outline = false
	if m == "extruded":
		var mx := max_depth(kind)
		o.merge({"depth": maxi(1, mx / 2), "bevel": "none", "bevel_size": 2, "bevel_sides": BlockModelMesh.BEVEL_SIDES})
		o.merge(extruded.get(kind, {}), true)
		o.depth = clampi(int(o.depth), 1, mx)
		if not o.bevel in Data.EXTRUDE_BEVELS:
			o.bevel = "none"
		o.bevel_size = clampi(int(o.bevel_size), 1, Data.BEVEL_MAX)
		var sides: Array = o.bevel_sides
		o.bevel_sides = BlockModelMesh.BEVEL_SIDES.filter(func(side): return side in sides)
	elif m in noise:
		o.merge(noise[m].get(kind, {}), true)
	o.seed = int(o.seed)
	o.one_color = bool(o.one_color)
	if o.has("no_outline"):
		o.no_outline = bool(o.no_outline)
	o.strength = clampf(float(o.strength), 0.0, 1.0)
	if not o.noise in Data.EXTRUDE_NOISES:
		o.noise = "none"
	return o


static func set_option(kind: String, m: String, key: String, value) -> void:
	ensure_loaded()
	var store: Dictionary = _store(m)
	var o: Dictionary = store.get(kind, {}).duplicate()
	o[key] = value
	store[kind] = o
	_forget(kind)


static func reset_options(kind: String, m: String) -> void:
	ensure_loaded()
	_store(m).erase(kind)
	_forget(kind)


## Where a method's settings are kept.
static func _store(m: String) -> Dictionary:
	if m == "extruded":
		return extruded
	return rendered if m == "rendered" else noise[m]


static func clear_cache() -> void:
	_finish_pending()
	_frames.clear()
	_meshes.clear()
	_materials.clear()
	_textures.clear()


static func _forget(kind: String) -> void:
	for k in _meshes.keys():
		if str(k).begins_with(kind + "|"):
			_meshes.erase(k)


## Its sheet cut into frames (bottoms trimmed as the billboard trims them),
## each also at art resolution, and their sizes in blocks: {images, arts, px
## (blocks per sheet pixel), apx (per art pixel), size (Vector2, blocks), art_w}.
static func frames_of(kind: String) -> Dictionary:
	if _frames.has(kind):
		return _frames[kind]
	var lk := NPC.look(kind)
	var sheet := Assets.image(NPC.image_path(kind))
	sheet.convert(Image.FORMAT_RGBA8)
	var n: int = lk.frames
	var fh := int(lk.frame_h)
	var keep := fh - maxi(0, int(lk.trim))
	var images: Array[Image] = []
	for f in n:
		images.append(sheet.get_region(Rect2i(0, f * fh, sheet.get_width(), keep)))
	var scale := PixelArt.detect_scale(images[0])
	var arts: Array[Image] = []
	for img in images:
		arts.append(PixelArt.downsample(img, scale) if scale.x > 1 else img)
	var px: float = lk.sprite_size.y / float(keep)
	var out := {"images": images, "arts": arts, "px": px, "apx": px * scale.x,
			"size": Vector2(sheet.get_width(), keep) * px, "art_w": arts[0].get_width()}
	_frames[kind] = out
	return out


static func _key(kind: String, m: String, frame: int) -> String:
	var key := "%s|%s|%d" % [kind, m, frame]
	if m in NOISE_METHODS:
		key += JSON.stringify(options(kind, m))
	return key


## Starts building every frame of a hand-made (claude) or tuned model on
## worker threads, so frames shown later (the Eye's mouth) don't stall the game.
static func prebuild(kind: String, m: String) -> void:
	var tuned := m == "tuned" and TunedModels.has(TunedModels.npc_key(kind))
	if not tuned and (m != "claude" or not NPCSculpt.has(kind)):
		return
	var tm := TunedModels.model(TunedModels.npc_key(kind)) if tuned else {}
	var fr := frames_of(kind)
	var o := options(kind, m)
	var sp := _sculpt_spec(kind, o)
	var apx: float = fr.apx
	for f in fr.arts.size():
		var key := _key(kind, m, f)
		if _meshes.has(key) or _pending.has(key):
			continue
		var art: Image = fr.arts[f]
		var job := {}
		var build := func() -> void:
			if tuned:
				job.arrays = TunedModels.arrays(tm, f, apx, o)
				return
			var faces := {}
			var body := {}
			var vox := NPCSculpt.voxels(sp, art, faces, body)
			job.arrays = BlockModelMesh.voxel_arrays(vox, art, apx, o, false, faces, NPCSculpt.solid_test(body))
			if o.one_color:
				job.arrays = TunedModels.one_color_arrays(job.arrays, false, null, apx)
		_pending[key] = [WorkerThreadPool.add_task(build), job]


## Claude's spec for an NPC, with an "outline" setting (from a tuned model's
## seed: models made before outlines were dropped) laid over it.
static func _sculpt_spec(kind: String, o: Dictionary) -> Dictionary:
	var sp := NPCSculpt.spec(kind)
	if o.has("outline"):
		sp = sp.duplicate()
		sp.outline = o.outline
	return sp


## Turns finished (or, `wait`, all) worker builds into meshes.
static func _finish_pending(wait := true) -> void:
	for key in _pending.keys():
		var p: Array = _pending[key]
		if not wait and not WorkerThreadPool.is_task_completed(p[0]):
			continue
		WorkerThreadPool.wait_for_task_completion(p[0])
		_pending.erase(key)
		_meshes[key] = {"mesh": BlockModelMesh.mesh_from_arrays(p[1].arrays), "textured": false}


## A frame's mesh for a method (not the billboard): {mesh, textured}.
static func mesh(kind: String, m: String, frame: int) -> Dictionary:
	var fr := frames_of(kind)
	frame = clampi(frame, 0, fr.arts.size() - 1)
	var key := _key(kind, m, frame)
	if _pending.has(key):
		var p: Array = _pending[key]
		WorkerThreadPool.wait_for_task_completion(p[0])
		_pending.erase(key)
		_meshes[key] = {"mesh": BlockModelMesh.mesh_from_arrays(p[1].arrays), "textured": false}
	_finish_pending(false)
	if _meshes.has(key):
		return _meshes[key]
	var art: Image = fr.arts[frame]
	if m in Data.OUTLINE_METHODS and options(kind, m).no_outline:
		art = PixelArt.without_outline(art, true)
	var apx: float = fr.apx
	var size: Vector2 = fr.size
	var out := {}
	match m:
		"cross":
			out = {"mesh": BlockModelMesh._cross(size.x, size.y, false), "textured": true}
		"flat":
			var flat := ItemMesh.build(art, "npc:%s:%d" % [kind, frame], 1.0)
			out = {"mesh": BlockModelMesh.transformed(flat, Transform3D(Basis().scaled(Vector3(apx, apx, apx)), Vector3(-size.x * 0.5, 0, 0))),
					"textured": true}
		"extruded":
			out = {"mesh": BlockModelMesh._extrude(art, apx, options(kind, m)), "textured": true}
		"rendered":
			# The model its shots are made of.
			out = mesh(kind, NPCRenders.source(kind), frame)
		"tuned" when TunedModels.has(TunedModels.npc_key(kind)):
			out = {"mesh": TunedModels.mesh(TunedModels.npc_key(kind), frame, apx, options(kind, m)), "textured": false}
		"claude" when NPCSculpt.has(kind):
			var faces := {}
			var body := {}
			var vox := NPCSculpt.voxels(_sculpt_spec(kind, options(kind, m)), art, faces, body)
			out = {"mesh": BlockModelMesh.voxel_mesh(vox, art, apx, options(kind, m), false, faces, NPCSculpt.solid_test(body)), "textured": false}
		"lathe" when absf(float(Data.npcs[kind].get("sprite_angle", 0.0))) == 90.0:
			# Its art lies on its side (the Demon Eye looks left): spun round
			# that axis, the way it points, not up through it.
			var turned := art.duplicate()
			turned.rotate_90(CLOCKWISE)  # its left on top
			var lathe := BlockModelMesh._voxels(turned, apx, m, options(kind, m), false)
			out = {"mesh": BlockModelMesh.transformed(lathe, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3(size.x * 0.5, size.y * 0.5, 0))),
					"textured": false}
		_:
			# Not made (claude) or not tuned yet: the hull.
			var vm := "hull" if m in ["claude", "tuned"] else m
			out = {"mesh": BlockModelMesh._voxels(art, apx, vm, options(kind, m), false), "textured": false}
	if m != "tuned" and m in NOISE_METHODS and options(kind, m).one_color:
		out = {"mesh": TunedModels.one_color_mesh(out.mesh, out.textured, art, apx), "textured": false}
	_meshes[key] = out
	return out


## The frame's sprite as a texture (textured meshes sample it).
static func texture(kind: String, frame: int) -> ImageTexture:
	var key := "%s|%d" % [kind, frame]
	if not _textures.has(key):
		_textures[key] = ImageTexture.create_from_image(frames_of(kind).images[frame])
	return _textures[key]


## `glass` below 1: see-through (npc_model_glass.gdshader), that opaque.
static func material(kind: String, frame: int, textured: bool, glass := 1.0) -> ShaderMaterial:
	var key := "%s|%d|%s|%s" % [kind, frame, textured, glass]
	if not _materials.has(key):
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://shaders/npc_model_glass.gdshader") if glass < 1.0 else preload("res://shaders/npc_model.gdshader")
		mat.set_shader_parameter("sprite", texture(kind, frame))
		mat.set_shader_parameter("textured", textured)
		if glass < 1.0:
			mat.set_shader_parameter("glass", glass)
		_materials[key] = mat
	return _materials[key]


## How opaque its model is in method m: Claude's King Slime is see-through
## ("glass" in its hand-made spec); everything else is solid (1).
static func glass(kind: String, m: String) -> float:
	if m == "claude" and NPCSculpt.has(kind):
		return clampf(float(NPCSculpt.spec(kind).get("glass", 1.0)), 0.05, 1.0)
	return 1.0
