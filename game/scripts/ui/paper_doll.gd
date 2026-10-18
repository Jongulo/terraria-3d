class_name PaperDoll
extends Control
## The player as Terraria draws them, standing and facing right, wearing
## their armor: shown in the inventory beside the armor slots (in first
## person you never see yourself). Built from Terraria's player layers
## (Player_0_N, tinted with a new character's default colours) and the
## armor's equip sprites; a 1.4 body is a composite sheet of 40x56 cells
## (torso, arms and shoulders apart).

const FRAME := Vector2(40, 56)
## Terraria's default new-character colours.
const SKIN := Color8(255, 125, 90)
const HAIR := Color8(215, 90, 55)
const EYES := Color8(105, 90, 75)
const SHIRT := Color8(175, 165, 140)
const UNDERSHIRT := Color8(160, 180, 215)
const PANTS := Color8(255, 230, 175)
const SHOES := Color8(160, 105, 60)
## Composite cells (column, row) of a standing pose.
const TORSO := Vector2i(0, 0)
const FRONT_ARM := Vector2i(2, 0)
const FRONT_SHOULDER := Vector2i(0, 1)
const BACK_ARM := Vector2i(2, 2)
const BACK_SHOULDER := Vector2i(1, 1)

var player: Player
## The player's height in the world (Player.half.y), which the standing
## figure is drawn at: so one art pixel of the player is this / its height.
const PLAYER_HEIGHT := 1.8
static var _standing: Image


## The player standing in plain clothes, cropped to the figure (texture
## pixels, as in Terraria's sheets).
static func standing_image() -> Image:
	if _standing != null:
		return _standing
	var img := Image.create(40, 56, false, Image.FORMAT_RGBA8)
	for layer in [[7, BACK_ARM, SKIN], [10, null, SKIN], [11, null, PANTS], [12, null, SHOES], [3, TORSO, SKIN],
			[4, TORSO, UNDERSHIRT], [6, TORSO, SHIRT], [0, null, SKIN], [1, null, Color.WHITE], [2, null, EYES],
			["hair", null, HAIR], [7, FRONT_ARM, SKIN], [8, FRONT_ARM, UNDERSHIRT], [13, FRONT_ARM, SHIRT], [9, FRONT_ARM, SKIN]]:
		var src: Image = Assets.image("Images/Player_Hair_1" if layer[0] is String else "Images/Player_0_%d" % layer[0])
		var cell = layer[1]
		var at := Vector2i(cell) * Vector2i(FRAME) if cell != null else Vector2i.ZERO
		if at.x + 40 > src.get_width() or at.y + 56 > src.get_height():
			continue
		var tint: Color = layer[2]
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
	if player == null:
		return
	var head := _worn("head")
	var body := _worn("body")
	var legs := _worn("legs")
	var head_tex := Assets.armor_texture("head", head) if head != "" else null
	var body_tex := Assets.armor_texture("body", body) if body != "" else null
	var legs_tex := Assets.armor_texture("legs", legs) if legs != "" else null
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.08, 0.1, 0.22, 0.35))
	# Back arm, behind everything.
	_cell(_skin(7), BACK_ARM, SKIN)
	if body_tex == null:
		_cell(_skin(8), BACK_ARM, UNDERSHIRT)
		_cell(_skin(13), BACK_ARM, SHIRT)
	else:
		_cell(body_tex, BACK_ARM)
		_cell(body_tex, BACK_SHOULDER)
	# Legs.
	_frame(_skin(10), SKIN)
	if legs_tex == null:
		_frame(_skin(11), PANTS)
		_frame(_skin(12), SHOES)
	else:
		_frame(legs_tex)
	# Torso.
	_cell(_skin(3), TORSO, SKIN)
	if body_tex == null:
		_cell(_skin(4), TORSO, UNDERSHIRT)
		_cell(_skin(6), TORSO, SHIRT)
	else:
		_cell(body_tex, TORSO)
	# Head: face, eyes, hair (hats keep a trimmed fringe), helmet.
	_frame(_skin(0), SKIN)
	_frame(_skin(1))
	_frame(_skin(2), EYES)
	var hair: String = Data.item(head).get("hair", "") if head != "" else "full"
	if hair == "full":
		_frame(Assets.texture("Images/Player_Hair_1"), HAIR)
	elif hair == "hat":
		_frame(Assets.texture("Images/Player_HairAlt_1"), HAIR)
	if head_tex != null:
		_frame(head_tex)
	# Front arm and hand.
	_cell(_skin(7), FRONT_ARM, SKIN)
	if body_tex == null:
		_cell(_skin(8), FRONT_ARM, UNDERSHIRT)
		_cell(_skin(13), FRONT_ARM, SHIRT)
	else:
		_cell(body_tex, FRONT_ARM)
		_cell(body_tex, FRONT_SHOULDER)
	_cell(_skin(9), FRONT_ARM, SKIN)


func _worn(slot: String) -> String:
	var s = player.armor.slots[Data.ARMOR_SLOTS.find(slot)]
	return "" if s == null else s.item


func _skin(layer: int) -> Texture2D:
	return Assets.texture("Images/Player_0_%d" % layer)


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
