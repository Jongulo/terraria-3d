class_name SpriteFx
## How the tree and cactus sprites are processed from Terraria's art: upscale (pixel-art
## magnifier), smooth warp, then pixel noise. Settings per sprite are edited
## with the sprite editor (./sprite_editor.sh) and saved in data/sprite_fx.json;
## CanopyArt and Data (tree trunk) build their sprites through process().
##
## Warp sizes are in art pixels (one pixel of the original art), so they keep
## their look whatever the upscale; noise patches are in output pixels.

const PATH := "res://data/sprite_fx.json"
const TARGETS := ["tree_canopy", "tree_trunk", "cactus"]
## Upscale choices and how many times bigger each makes the art.
const UPSCALES := {
	"none": 1,
	"scale2x": 2, "scale2x_x2": 4,
	"eagle": 2, "eagle_x2": 4,
	"epb": 2, "epb_x2": 4,
}
const DEFAULTS := {
	"tree_canopy": {"upscale": "scale2x_x2", "warp": 0.625, "warp_size": 2.5, "warp_seed": 0, "fade": 8.0,
			"noise": "none", "noise_strength": 0.5, "noise_cell": 1, "noise_seed": 0},
	"tree_trunk": {"upscale": "scale2x_x2", "warp": 0.0, "warp_size": 2.5, "warp_seed": 0, "fade": 0.0,
			"noise": "none", "noise_strength": 0.5, "noise_cell": 1, "noise_seed": 0},
	"cactus": {"upscale": "scale2x", "warp": 0.0, "warp_size": 2.5, "warp_seed": 0, "fade": 0.0,
			"noise": "none", "noise_strength": 0.5, "noise_cell": 1, "noise_seed": 0},
}

static var _settings := {}
static var _loaded := false


## A sprite's settings, defaults filled in and values checked.
static func options(target: String) -> Dictionary:
	_ensure_loaded()
	var o: Dictionary = DEFAULTS.get(target, DEFAULTS.tree_canopy).duplicate()
	o.merge(_settings.get(target, {}), true)
	return sanitized(o)


static func sanitized(o: Dictionary) -> Dictionary:
	var s := o.duplicate()
	if not UPSCALES.has(s.upscale):
		s.upscale = "scale2x_x2"
	if not s.noise in PixelArt.NOISES:
		s.noise = "none"
	s.warp = clampf(float(s.warp), 0.0, 4.0)
	s.warp_size = clampf(float(s.warp_size), 0.5, 16.0)
	s.fade = clampf(float(s.fade), 0.0, 40.0)
	s.noise_strength = clampf(float(s.noise_strength), 0.0, 1.0)
	s.noise_cell = clampi(int(s.noise_cell), 1, 8)
	s.warp_seed = int(s.warp_seed)
	s.noise_seed = int(s.noise_seed)
	return s


static func set_options(target: String, o: Dictionary) -> void:
	_ensure_loaded()
	# Only what differs from the defaults is kept (and saved).
	var diff := {}
	var defaults: Dictionary = DEFAULTS.get(target, {})
	for k in o:
		if not defaults.has(k) or defaults[k] != o[k]:
			diff[k] = o[k]
	_settings[target] = diff


static func load_file(path := PATH) -> void:
	_settings = {}
	_loaded = true
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary:
		for t in parsed:
			if parsed[t] is Dictionary:
				_settings[t] = parsed[t]


static func save(path := PATH) -> bool:
	_ensure_loaded()
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(_settings, "\t", true))
	return true


static func _ensure_loaded() -> void:
	if not _loaded:
		load_file()


## Processes one sprite given at art resolution. `seed` varies the warp and
## noise per sprite (canopy style, trunk variant). With `tile_y` the warp
## repeats vertically and adds no top margin (stacked tree trunk tiles).
## Returns {image, k: how many output pixels per art pixel}.
static func process(art: Image, o: Dictionary, seed: int, tile_y := false) -> Dictionary:
	var k: int = UPSCALES.get(o.upscale, 1)
	var img := upscale(art, o.upscale)
	if o.warp > 0.0:
		var amp: float = o.warp * k
		img = PixelArt.warp(img, amp, o.warp_size * k, 1000 + seed + o.warp_seed * 101,
				0 if tile_y else roundi(o.fade * k), ceili(amp) + 1, tile_y)
	img = PixelArt.noise(img, o.noise, o.noise_strength, o.noise_cell, 5000 + seed + o.noise_seed * 101)
	return {"image": img, "k": k}


static func upscale(art: Image, method: String) -> Image:
	var img := art
	match method:
		"scale2x", "eagle", "epb":
			img = PixelArt.magnify2x(img, method)
		"scale2x_x2", "eagle_x2", "epb_x2":
			var m := method.trim_suffix("_x2")
			img = PixelArt.magnify2x(PixelArt.magnify2x(img, m), m)
	return img
