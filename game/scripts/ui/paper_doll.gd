class_name PaperDoll
extends Control
## The player as Terraria draws them, standing and facing right, wearing
## their armor: shown in the inventory beside the armor slots (in first
## person you never see yourself), and alone (a look, no player) in the
## character creator. Built from Terraria's player layers (PlayerLook: its
## clothing style's Player_<style>_N, tinted with its colours) and the
## armor's equip sprites; a 1.4 body is a composite sheet of 40x56 cells
## (torso, arms and shoulders apart).

const FRAME := Vector2(40, 56)
## Composite cells (column, row) of a standing pose.
const TORSO := Vector2i(0, 0)
const FRONT_ARM := Vector2i(2, 0)
const FRONT_SHOULDER := Vector2i(0, 1)
const BACK_ARM := Vector2i(2, 2)
const BACK_SHOULDER := Vector2i(1, 1)

var player: Player
## Drawn without a player (the character creator): this look, no armor.
var look: PlayerLook
## The player's height in the world (Player.half.y), which the standing
## figure is drawn at: so one art pixel of the player is this / its height.
const PLAYER_HEIGHT := 1.8
static var _standing: Image


## A new character standing in plain clothes (Terraria's default look),
## cropped to the figure (texture pixels, as in Terraria's sheets): the
## player's size in the world, whatever they look like.
static func standing_image() -> Image:
	if _standing != null:
		return _standing
	var lk := PlayerLook.new()
	var img := Image.create(40, 56, false, Image.FORMAT_RGBA8)
	for layer in [[7, BACK_ARM, "skin"], [10, null, "skin"], [11, null, "pants"], [12, null, "shoes"], [3, TORSO, "skin"],
			[4, TORSO, "undershirt"], [6, TORSO, "shirt"], [0, null, "skin"], [1, null, ""], [2, null, "eyes"],
			["hair", null, "hair"], [7, FRONT_ARM, "skin"], [8, FRONT_ARM, "undershirt"], [13, FRONT_ARM, "shirt"], [9, FRONT_ARM, "skin"]]:
		var src: Image = lk.hair_texture().get_image() if layer[0] is String else lk.layer_image(layer[0])
		var cell = layer[1]
		var at := Vector2i(cell) * Vector2i(FRAME) if cell != null else Vector2i.ZERO
		if at.x + 40 > src.get_width() or at.y + 56 > src.get_height():
			continue
		var tint: Color = Color.WHITE if layer[2] == "" else lk.colour(layer[2])
		for y in 56:
			for x in 40:
				var c := src.get_pixel(at.x + x, at.y + y)
				if c.a > 0.0:
					img.set_pixel(x, y, Color(c.r * tint.r, c.g * tint.g, c.b * tint.b, c.a))
	_standing = img.get_region(img.get_used_rect())
	return _standing


## How big one of the player's texture pixels is in the world (metres): the
## standing figure is PLAYER_HEIGHT tall.
static func player_pixel_size() -> float:
	return PLAYER_HEIGHT / standing_image().get_height()


func _draw() -> void:
	var lk := player.look if player != null else look
	if lk == null:
		return
	var head := _worn("head")
	var body := _worn("body")
	var legs := _worn("legs")
	var head_tex := Assets.armor_texture("head", head) if head != "" else null
	var body_tex := Assets.armor_texture("body", body) if body != "" else null
	var legs_tex := Assets.armor_texture("legs", legs) if legs != "" else null
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.1, 0.22, 0.35))
	var skin := lk.colour("skin")
	var shirt := lk.colour("shirt")
	var undershirt := lk.colour("undershirt")
	var rows := lk.torso_rows()
	# Back arm, behind everything.
	_cell(lk.layer_texture(7), BACK_ARM, skin)
	if body_tex == null:
		_cell(lk.layer_texture(8), BACK_ARM, undershirt)
		_cell(lk.layer_texture(13), BACK_ARM, shirt)
	else:
		_cell(body_tex, BACK_ARM)
		_cell(body_tex, BACK_SHOULDER + rows)
	# Legs (a long coat or dress over them, unless armor covers the body).
	_frame(lk.layer_texture(10), skin)
	if legs_tex == null:
		_frame(lk.layer_texture(11), lk.colour("pants"))
		_frame(lk.layer_texture(12), lk.colour("shoes"))
	else:
		_frame(legs_tex)
	if body_tex == null and lk.has_long_coat():
		_frame(lk.layer_texture(14), shirt)
	# Torso.
	_cell(lk.layer_texture(3), TORSO + rows, skin)
	if body_tex == null:
		_cell(lk.layer_texture(4), TORSO + rows, undershirt)
		_cell(lk.layer_texture(6), TORSO + rows, shirt)
	else:
		_cell(body_tex, TORSO + rows)
	# Head: face, eyes, hair (hats keep a trimmed fringe), helmet.
	_frame(lk.layer_texture(0), skin)
	_frame(lk.layer_texture(1))
	_frame(lk.layer_texture(2), lk.colour("eyes"))
	var hair: String = Data.item(head).get("hair", "") if head != "" else "full"
	if hair == "full":
		_frame(lk.hair_texture(), lk.colour("hair"))
	elif hair == "hat":
		_frame(lk.hair_texture(true), lk.colour("hair"))
	if head_tex != null:
		_frame(head_tex)
	# Front arm and hand.
	_cell(lk.layer_texture(7), FRONT_ARM, skin)
	if body_tex == null:
		_cell(lk.layer_texture(8), FRONT_ARM, undershirt)
		_cell(lk.layer_texture(13), FRONT_ARM, shirt)
	else:
		_cell(body_tex, FRONT_ARM)
		_cell(body_tex, FRONT_SHOULDER + rows)
	_cell(lk.layer_texture(9), FRONT_ARM, skin)


func _worn(slot: String) -> String:
	if player == null:
		return ""
	var s = player.armor.slots[Data.ARMOR_SLOTS.find(slot)]
	return "" if s == null else s.item


## The first 40x56 frame of a strip sheet (head, hair, legs).
func _frame(tex: Texture2D, tint := Color.WHITE) -> void:
	_draw_region(tex, Rect2(Vector2.ZERO, FRAME), tint)


## A cell of a composite sheet (torso, arms).
func _cell(tex: Texture2D, cell: Vector2i, tint := Color.WHITE) -> void:
	_draw_region(tex, Rect2(Vector2(cell) * FRAME, FRAME), tint)


func _draw_region(tex: Texture2D, region: Rect2, tint: Color) -> void:
	if tex == null or region.end.x > tex.get_width() or region.end.y > tex.get_height():
		return
	draw_texture_rect_region(tex, Rect2(Vector2.ZERO, size), region, tint)
