class_name FaelingSprite
extends Node3D
## The Faeling (Shimmerfly) as Terraria draws it (Main.DrawNPCDirect_Faeling):
## its sheet is 4 columns of 5 frames, layered: the glowing core (column 2,
## its first frame, white), the wings (column 1, white, half see-through),
## the body (column 0) in a rainbow colour going round every 360 ticks (each
## Faeling at its own place in it), and a sparkle (column 3, one of its
## frames) pulsing over it all. All of it lit by nothing but itself.

const COLUMNS := 4
const ROWS := 5
## Ticks a hue goes round (timeForVisualEffects / 360).
const HUE_TICKS := 360.0

var _core := EntitySprite.new()
var _wings := EntitySprite.new()
var _body := EntitySprite.new()
var _sparkle := EntitySprite.new()
var _offset := 0.0
var _sparkle_row := 0
var _fade := 1.0
static var _columns := {}


## `size`: a frame's size in blocks; `id`: which Faeling (its colour's offset,
## Terraria's whoAmI).
func setup(sheet: String, size: Vector2, id: int) -> void:
	_offset = fmod(id * 0.11, 1.0)
	_sparkle_row = id % ROWS
	for i in 4:
		var s: EntitySprite = [_core, _wings, _body, _sparkle][i]
		s.setup(column(sheet, [2, 1, 0, 3][i]), ROWS, size, true)
		s.position.z = i * 0.002
		add_child(s)
		s.set_glow()
	_core.set_frame(0)
	_sparkle.set_frame(_sparkle_row)
	_wings.set_fade(0.5)


## One column of a sheet as its own texture (cached).
static func column(sheet: String, col: int) -> Texture2D:
	var key := "%s#%d" % [sheet, col]
	if not _columns.has(key):
		var img := Assets.texture(sheet).get_image()
		var w := img.get_width() / COLUMNS
		_columns[key] = ImageTexture.create_from_image(img.get_region(Rect2i(col * w, 0, w, img.get_height())))
	return _columns[key]


func set_frame(f: int) -> void:
	_body.set_frame(f % ROWS)
	_wings.set_frame(f % ROWS)


func _process(_delta: float) -> void:
	var t := Engine.get_process_frames() / 1.0
	var hue := PlayerLook.hsl(fmod(_offset + t / HUE_TICKS, 1.0), 1.0, 0.65)
	_body.set_tint(Color(hue.r, hue.g, hue.b))
	# The sparkle: 0-0.6 bright, its size 0.8 +- 0.3, both pulsing (here its
	# brightness thins it out: the sprites have no blending).
	var bright := clampf(sin(t / 60.0) * 0.3 + 0.3, 0.0, 1.0)
	_sparkle.set_tint(hue.lerp(Color.WHITE, 0.5))
	_sparkle.set_fade(bright * _fade / 0.6)
	var pulse := 0.8 + sin(t / 15.0 * TAU) * 0.3
	_sparkle.scale = Vector3(_core.scale.x * pulse, _core.scale.y * pulse, 1.0)


func set_flip(f: bool) -> void:
	for s in [_core, _wings, _body, _sparkle]:
		s.set_flip(f)


func set_rotation_angle(a: float) -> void:
	for s in [_core, _wings, _body, _sparkle]:
		s.set_rotation_angle(a)


func set_fade(v: float) -> void:
	_fade = v
	_core.set_fade(v)
	_body.set_fade(v)
	_wings.set_fade(v * 0.5)


func set_flash(v: float) -> void:
	for s in [_core, _wings, _body, _sparkle]:
		s.set_flash(v)


func set_tint(_c: Color) -> void:
	pass


func set_glow() -> void:
	pass


func update_light(_world, _sky, _at: Vector3) -> void:
	pass


func set_xray(_on: bool, _colour := Color(0, 0, 0, 0)) -> void:
	pass


func set_trim_bottom(_px: float, _frame_height: float) -> void:
	pass
