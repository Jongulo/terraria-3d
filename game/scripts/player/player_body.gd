class_name PlayerBody
extends Node3D
## You, seen in third person (Player's camera views): Terraria's player drawn
## as a billboard, like the NPCs, from its layers (Player_0_N, a new
## character's default colours, as PaperDoll) and the armor you wear. Its
## sheet is drawn on the GPU (an offscreen viewport, again after the armor
## changes): ARMS arm poses times Terraria's 20 leg frames (0 standing, 5 in
## the air, 6-19 walking). The arm poses are the composite sheets' front arm:
## hanging, then the four of a swing (up behind, up ahead, ahead, down ahead).
## The item in use is drawn at the hand, swung through Terraria's arc or held
## along your aim. In first person it only casts your shadow.

const FRAME := Vector2i(40, 56)
const LEG_FRAMES := 20
## The front arm's cell in the composite sheets for each arm pose.
const ARM_CELLS := [Vector2i(2, 0), Vector2i(3, 0), Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0)]
const ARMS := 5
## Terraria's walk: legFrameCounter += |vx| * 1.3, a frame per 8 (px/tick).
const WALK_FRAMES_PER_BLOCK := 60.0 / 2.5 * 1.3 / 8.0
## Item sprites whose blade or shaft runs corner to corner (Terraria draws
## them pointing up and ahead), and those that point straight ahead (guns, bows).
const DIAGONAL := ["sword", "pickaxe", "axe", "shortsword", "spear", "staff", "fishing"]

var player: Player
var sprite := EntitySprite.new()
var item := EntitySprite.new()
var _viewport := SubViewport.new()
var _sheet := _Sheet.new()
var _px := 1.0 / 30.0
var _trim := 0.0
var _walk := 0.0
var _facing_right := true
var _item_name := ""
var _item_size := Vector2.ONE
## Each arm pose's hand (frame pixels, facing right), found in the arm sheet.
static var _hands: Array = []


func _ready() -> void:
	_viewport.size = Vector2i(FRAME.x, FRAME.y * ARMS * LEG_FRAMES)
	_viewport.transparent_bg = true
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	_sheet.player = player
	_sheet.size = Vector2(_viewport.size)
	_sheet.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_viewport.add_child(_sheet)
	add_child(_viewport)
	_px = PaperDoll.player_pixel_size()
	_trim = _bottom_margin()
	sprite.setup(_viewport.get_texture(), ARMS * LEG_FRAMES, Vector2(FRAME.x, FRAME.y - _trim) * _px)
	sprite.set_trim_bottom(_trim, FRAME.y)
	add_child(sprite)
	item.visible = false
	add_child(item)
	player.armor.changed.connect(redraw)
	_find_hands()


## Draws the sheet again (the armor changed).
func redraw() -> void:
	_sheet.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## Shown (third person), or only casting your shadow (first person).
func set_seen(seen: bool) -> void:
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if seen else GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	item.visible = item.visible and seen


## Rows of empty space under the feet in a frame (the standing legs').
static func _bottom_margin() -> float:
	var img: Image = Assets.image("Images/Player_0_10")
	var r := img.get_region(Rect2i(0, 0, FRAME.x, FRAME.y)).get_used_rect()
	return float(FRAME.y - r.end.y)


## Each arm pose's hand: the arm's pixel furthest from the shoulder (the
## hanging arm's top).
static func _find_hands() -> void:
	if not _hands.is_empty():
		return
	var img: Image = Assets.image("Images/Player_0_7")
	var hang := img.get_region(Rect2i(ARM_CELLS[0] * FRAME, FRAME)).get_used_rect()
	var shoulder := Vector2(hang.get_center().x, hang.position.y + 1)
	for cell in ARM_CELLS:
		var best := shoulder
		var best_d := -1.0
		for y in FRAME.y:
			for x in FRAME.x:
				if img.get_pixel(cell.x * FRAME.x + x, cell.y * FRAME.y + y).a > 0.5:
					var d := Vector2(x, y).distance_squared_to(shoulder)
					if d > best_d:
						best_d = d
						best = Vector2(x + 0.5, y + 0.5)
		_hands.append(best)


## Poses the body for this frame: `view` is the camera drawing it.
func update(delta: float, view: Camera3D, game) -> void:
	var v := Vector3(player.velocity.x, 0, player.velocity.z)
	var right := view.global_basis.x
	# Facing: the way you move across the view, else the way you aim.
	var across := v.dot(right) if v.length() > 0.5 else player.forward().dot(right)
	if absf(across) > 0.05:
		_facing_right = across > 0.0
	sprite.set_flip(not _facing_right)
	var legs := 0
	if not player.on_floor and player.mount == "":
		legs = 5
	elif v.length() > 0.3 and player.mount == "":
		_walk = fmod(_walk + v.length() * WALK_FRAMES_PER_BLOCK * delta, 14.0)
		legs = 6 + int(_walk)
	var use: Array = player.viewmodel.use_state()
	var style: String = use[0]
	var p: float = use[1]
	var arm := 0
	var held := player.held()
	var showing := false
	var angle := 0.0  # where the item points on the screen (radians, 0: ahead)
	var aim := asin(clampf(player.forward().y, -1.0, 1.0))
	match style:
		"swing", "throw":
			arm = 1 + mini(3, int(p * 4.0))
			angle = lerpf(deg_to_rad(135.0), deg_to_rad(-45.0), p)
			showing = style == "swing"
		"hold":
			arm = 2 if aim > 0.6 else (3 if aim > -0.3 else 4)
			angle = aim
			showing = true
		"thrust", "punch":
			arm = 3
			angle = 0.0
			showing = style == "thrust"
		"drink":
			arm = 2
			angle = deg_to_rad(60.0)
			showing = true
		_:
			# A held torch (anything with a flame) is held up, as Terraria does.
			if not held.is_empty() and TorchFlames.item_flame(Data.item_id(player.inventory.slots[player.selected].item)).size() > 0:
				arm = 2
				angle = deg_to_rad(70.0)
				showing = true
	sprite.set_frame(arm * LEG_FRAMES + legs)
	var light_at := player.global_position + Vector3(0, 1.0, 0)
	sprite.update_light(game.world, game.sky, light_at)
	sprite.set_flash(1.0 if player._since_hurt < 0.12 else 0.0)
	_update_item(showing and player.yoyo_out() == false and not player.slash_out() and not player.whip_out(), arm, angle, view, game, light_at)


func _update_item(show: bool, arm: int, angle: float, view: Camera3D, game, light_at: Vector3) -> void:
	var s = player.inventory.slots[player.selected]
	var name: String = "" if s == null else s.item
	item.visible = show and name != "" and sprite.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if not item.visible:
		return
	if name != _item_name:
		_item_name = name
		var id := Data.item_id(name)
		var tex := Assets.item_texture(id)
		var img := Assets.item_image(id)
		# Items at the size Terraria draws them next to the player (2 texture
		# pixels to an art pixel, as the player's own sheets).
		_item_size = Vector2(img.get_size()) * _px
		item.setup(tex, 1, _item_size, true, true)
		item.set_frame(0)
	var kind := Viewmodel.kind_of(Data.item(name))
	var diagonal := kind in DIAGONAL
	# The sprite's own pointing (up and ahead for diagonal ones), mirrored
	# when you face left; the grip at its back end.
	var native := deg_to_rad(45.0) if diagonal else 0.0
	# (A bow is held at its middle, a gun by its back end.)
	var grip := Vector2(-0.5, -0.5) if diagonal else (Vector2.ZERO if kind == "bow" else Vector2(-0.3, -0.1))
	var dir := angle
	if not _facing_right:
		native = PI - native
		dir = PI - angle
		grip.x = -grip.x
	item.set_flip(not _facing_right)
	var rot := dir - native
	item.set_rotation_angle(rot)
	var g := Vector2(grip.x * _item_size.x, grip.y * _item_size.y).rotated(rot)
	# The hand, in the view plane (the sprite turns round the vertical only).
	var hand: Vector2 = _hands[arm]
	var hx := (hand.x - FRAME.x * 0.5) * _px * (1.0 if _facing_right else -1.0)
	var hy := (FRAME.y - _trim - hand.y) * _px
	var right := view.global_basis.x
	var up := view.global_basis.y
	var flat_right := Vector3(right.x, 0, right.z).normalized()
	var at := global_position + flat_right * hx + Vector3.UP * hy
	item.global_position = at - right * g.x - up * g.y + (view.global_position - at).normalized() * 0.02
	item.update_light(game.world, game.sky, light_at)


## The sheet: every arm pose with every leg frame, stacked down (pose-major).
class _Sheet extends Control:
	var player: Player

	func _draw() -> void:
		if player == null:
			return
		var head := _worn("head")
		var body := _worn("body")
		var legs := _worn("legs")
		var head_tex := Assets.armor_texture("head", head) if head != "" else null
		var body_tex := Assets.armor_texture("body", body) if body != "" else null
		var legs_tex := Assets.armor_texture("legs", legs) if legs != "" else null
		var hair: String = Data.item(head).get("hair", "") if head != "" else "full"
		var hair_tex: Texture2D = null
		if hair == "full":
			hair_tex = Assets.texture("Images/Player_Hair_1")
		elif hair == "hat":
			hair_tex = Assets.texture("Images/Player_HairAlt_1")
		var bob := _bobs()
		for arm in PlayerBody.ARMS:
			var front: Vector2i = PlayerBody.ARM_CELLS[arm]
			for f in PlayerBody.LEG_FRAMES:
				var at := Vector2(0, (arm * PlayerBody.LEG_FRAMES + f) * PlayerBody.FRAME.y)
				var up := Vector2(0, bob[f])
				# Back arm, behind everything.
				_cell(_skin(7), Vector2i(2, 2), at + up, PaperDoll.SKIN)
				if body_tex == null:
					_cell(_skin(8), Vector2i(2, 2), at + up, PaperDoll.UNDERSHIRT)
					_cell(_skin(13), Vector2i(2, 2), at + up, PaperDoll.SHIRT)
				else:
					_cell(body_tex, Vector2i(2, 2), at + up)
					_cell(body_tex, Vector2i(1, 1), at + up)
				# Legs (their walk frames move by themselves).
				_strip(_skin(10), f, at, PaperDoll.SKIN)
				if legs_tex == null:
					_strip(_skin(11), f, at, PaperDoll.PANTS)
					_strip(_skin(12), f, at, PaperDoll.SHOES)
				else:
					_strip(legs_tex, f, at)
				# Torso.
				_cell(_skin(3), Vector2i(0, 0), at + up, PaperDoll.SKIN)
				if body_tex == null:
					_cell(_skin(4), Vector2i(0, 0), at + up, PaperDoll.UNDERSHIRT)
					_cell(_skin(6), Vector2i(0, 0), at + up, PaperDoll.SHIRT)
				else:
					_cell(body_tex, Vector2i(0, 0), at + up)
				# Head (its frames bob with the walk), hair, helmet.
				_strip(_skin(0), f, at, PaperDoll.SKIN)
				_strip(_skin(1), f, at)
				_strip(_skin(2), f, at, PaperDoll.EYES)
				if hair_tex != null:
					_strip(hair_tex, 0, at + up, PaperDoll.HAIR)
				if head_tex != null:
					_strip(head_tex, f, at)
				# Front arm and hand.
				_cell(_skin(7), front, at + up, PaperDoll.SKIN)
				if body_tex == null:
					_cell(_skin(8), front, at + up, PaperDoll.UNDERSHIRT)
					_cell(_skin(13), front, at + up, PaperDoll.SHIRT)
				else:
					_cell(body_tex, front, at + up)
					_cell(body_tex, Vector2i(0, 1), at + up)
				_cell(_skin(9), front, at + up, PaperDoll.SKIN)

	## How far each leg frame lifts the body (pixels, up negative): the head
	## sheet's frames have Terraria's walking bob in them.
	func _bobs() -> Array:
		var img: Image = Assets.image("Images/Player_0_0")
		var base := img.get_region(Rect2i(0, 0, PlayerBody.FRAME.x, PlayerBody.FRAME.y)).get_used_rect().position.y
		var out := []
		for f in PlayerBody.LEG_FRAMES:
			var y0 := f * PlayerBody.FRAME.y
			if y0 + PlayerBody.FRAME.y > img.get_height():
				out.append(0)
				continue
			out.append(img.get_region(Rect2i(0, y0, PlayerBody.FRAME.x, PlayerBody.FRAME.y)).get_used_rect().position.y - base)
		return out

	func _worn(slot: String) -> String:
		var s = player.armor.slots[Data.ARMOR_SLOTS.find(slot)]
		return "" if s == null else s.item

	func _skin(layer: int) -> Texture2D:
		return Assets.texture("Images/Player_0_%d" % layer)

	## Frame `f` of a strip sheet (head, hair, legs, helmets).
	func _strip(tex: Texture2D, f: int, at: Vector2, tint := Color.WHITE) -> void:
		var region := Rect2(Vector2(0, f * PlayerBody.FRAME.y), Vector2(PlayerBody.FRAME))
		if tex == null or region.end.y > tex.get_height() + 2:
			region.position.y = 0
		_region(tex, region, at, tint)

	## A cell of a composite sheet (torso, arms).
	func _cell(tex: Texture2D, cell: Vector2i, at: Vector2, tint := Color.WHITE) -> void:
		_region(tex, Rect2(Vector2(cell * PlayerBody.FRAME), Vector2(PlayerBody.FRAME)), at, tint)

	func _region(tex: Texture2D, region: Rect2, at: Vector2, tint: Color) -> void:
		if tex == null or region.end.x > tex.get_width():
			return
		region.end.y = minf(region.end.y, tex.get_height())
		draw_texture_rect_region(tex, Rect2(at, region.size), region, tint)
