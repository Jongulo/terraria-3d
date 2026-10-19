extends Node
## Runtime access to assets extracted from the user's Terraria install
## (see extract_assets.sh). Files are read straight from disk, not imported,
## and cached by name.

const ROOT := "res://assets/terraria/"

## Terraria ID tables and English names (from tools/terraria_ids.py).
var ids: Dictionary = {}

var _images := {}
var _textures := {}
var _streams := {}
var _fonts := {}


func _ready() -> void:
	var f := FileAccess.open(ROOT + "ids.json", FileAccess.READ)
	if f == null:
		push_error("Terraria assets are missing. Run ./extract_assets.sh first.")
		return
	ids = JSON.parse_string(f.get_as_text())


func available() -> bool:
	return not ids.is_empty()


func disk_path(rel: String) -> String:
	return ProjectSettings.globalize_path(ROOT + rel)


## `name` like "Images/Item_1" (no extension).
func image(name: String) -> Image:
	if not _images.has(name):
		var img := Image.load_from_file(disk_path(name + ".png"))
		if img == null:
			push_warning("missing image " + name)
			img = Image.create(16, 16, false, Image.FORMAT_RGBA8)
		_images[name] = img
	return _images[name]


func texture(name: String) -> Texture2D:
	if not _textures.has(name):
		_textures[name] = ImageTexture.create_from_image(image(name))
	return _textures[name]


## An item's icon: its sprite, or an animated item's first frame (its
## sheet is frames stacked down it; item_sheet has them all).
func item_texture(id: int) -> Texture2D:
	if Data.item_anim(id).is_empty():
		return texture("Images/Item_%d" % id)
	var key := "item_frame:%d" % id
	if not _textures.has(key):
		_textures[key] = ImageTexture.create_from_image(item_image(id))
	return _textures[key]


func item_image(id: int) -> Image:
	var img := image("Images/Item_%d" % id)
	var n := int(Data.item_anim(id).get("frames", 1))
	if n <= 1:
		return img
	var key := "item_frame:%d" % id
	if not _images.has(key):
		var h := img.get_height() / n
		_images[key] = img.get_region(Rect2i(0, 0, img.get_width(), h))
	return _images[key]


## The whole sheet of an item (every frame of an animated one).
func item_sheet(id: int) -> Texture2D:
	return texture("Images/Item_%d" % id)


func sound(name: String) -> AudioStream:
	var key := "s:" + name
	if not _streams.has(key):
		var path := disk_path("Sounds/" + name + ".wav")
		_streams[key] = AudioStreamWAV.load_from_file(path) if FileAccess.file_exists(path) else null
	return _streams[key]


## `name` like "Music_1"; streams loop.
func music(name: String) -> AudioStream:
	var key := "m:" + name
	if not _streams.has(key):
		var path := disk_path("Music/" + name + ".ogg")
		var stream: AudioStreamOggVorbis = null
		if FileAccess.file_exists(path):
			stream = AudioStreamOggVorbis.load_from_file(path)
			stream.loop = true
		_streams[key] = stream
	return _streams[key]


## Builds a bitmap FontFile from Terraria's paged sprite font. Only pages with
## Latin characters are loaded.
func font(name: String) -> Font:
	if _fonts.has(name):
		return _fonts[name]
	var f := FileAccess.open(ROOT + "Fonts/" + name + ".json", FileAccess.READ)
	if f == null:
		return ThemeDB.fallback_font
	var meta: Dictionary = JSON.parse_string(f.get_as_text())
	var ff := FontFile.new()
	var size: int = int(meta.line_spacing)
	var key := Vector2i(size, 0)
	ff.fixed_size = size
	ff.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_ENABLED
	var ascent := size * 0.78
	ff.set_cache_ascent(0, size, ascent)
	ff.set_cache_descent(0, size, size - ascent)

	var page_slot := {}
	for c in meta.chars:
		var code := int(c.char)
		if code > 0x24F:
			continue
		var page := int(c.page)
		if not page_slot.has(page):
			page_slot[page] = page_slot.size()
			var img := Image.load_from_file(disk_path("Fonts/%s/page_%d.png" % [name, page]))
			ff.set_texture_image(0, key, page_slot[page], img)
		var g: Array = c.glyph
		var crop: Array = c.crop
		var kern: Array = c.kerning
		ff.set_glyph_texture_idx(0, key, code, page_slot[page])
		ff.set_glyph_uv_rect(0, key, code, Rect2(g[0], g[1], g[2], g[3]))
		ff.set_glyph_size(0, key, code, Vector2(g[2], g[3]))
		ff.set_glyph_offset(0, key, code, Vector2(kern[0] + crop[0], crop[1] - ascent))
		ff.set_glyph_advance(0, size, code, Vector2(kern[0] + kern[1] + kern[2] + float(meta.spacing), 0))
	_fonts[name] = ff
	return ff


## English display name for an internal item name ("CopperPickaxe" -> "Copper Pickaxe").
func item_name(internal: String) -> String:
	return ids.get("names", {}).get("items", {}).get(internal, internal)


## Terraria's English tooltip for an item ("" if it has none).
func item_tooltip(internal: String) -> String:
	return ids.get("names", {}).get("tooltips", {}).get(internal, "")


## Terraria's English set bonus text (ArmorSetBonus.<key>).
func set_bonus_text(key: String) -> String:
	return ids.get("names", {}).get("set_bonuses", {}).get(key, "")


## The equipped look of an armor piece (slot head / body / legs): Terraria's
## Armor_Head_N, Armor/Armor_N (1.4's composite body sheet) or Armor_Legs_N, or
## null.
func armor_texture(slot: String, internal: String) -> Texture2D:
	var table: String = {"head": "ArmorHead", "body": "ArmorBody", "legs": "ArmorLegs"}[slot]
	var n = ids.get(table, {}).get(internal)
	if n == null:
		return null
	var path: String = {"head": "Images/Armor_Head_%d", "body": "Images/Armor/Armor_%d", "legs": "Images/Armor_Legs_%d"}[slot] % int(n)
	return texture(path) if FileAccess.file_exists(disk_path(path + ".png")) else null


func npc_name(internal: String) -> String:
	var own = Data.npcs.get(internal, {}).get("name")
	return own if own != null else ids.get("names", {}).get("npcs", {}).get(internal, internal)
