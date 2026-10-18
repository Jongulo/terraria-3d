class_name RopeSnake
extends Node3D
## The Snake Charmer's Flute's rope snake (Terraria's MysticSnakeCoil): it
## rises from its basket up to `height` blocks, stopping under the first
## block in its way, then holds still to be climbed like a rope (Player._climb)
## until it goes, `seconds` after it was summoned.

const CLIMB_SPEED := 5.0
## How near its middle you can hold on to it.
const REACH := 0.6
## One coil of its body: a tile (2/3 of a block).
const SEGMENT := 2.0 / 3.0
const SHEET := "Images/Projectile_754"

var height := 67.0
var life := 30.0
## How fast it rises, in blocks a second.
var grow := 30.0
var length := 0.0
var _max := -1.0
var _coils: Array[EntitySprite] = []
var _head: EntitySprite
var _basket: EntitySprite
var _body_tex: Texture2D
var _anim := 0.0


func setup(d: Dictionary) -> void:
	height = float(d.get("height", 67))
	life = float(d.get("seconds", 30))
	grow = float(d.get("grow", 30))
	add_to_group("rope_snakes")


func _ready() -> void:
	var img := Assets.image(SHEET)
	# The sheet: four head frames across the top, four body coils under them,
	# the basket at the top right.
	var heads := Image.create(18, 72, false, img.get_format())
	for i in 4:
		heads.blit_rect(img, Rect2i(i * 18, 0, 18, 18), Vector2i(0, i * 18))
	_head = EntitySprite.new()
	_head.setup(ImageTexture.create_from_image(heads), 4, Vector2(SEGMENT, SEGMENT))
	add_child(_head)
	_body_tex = ImageTexture.create_from_image(img.get_region(Rect2i(0, 18, 18, 18)))
	_basket = EntitySprite.new()
	_basket.setup(ImageTexture.create_from_image(img.get_region(Rect2i(72, 0, 18, 18))), 1, Vector2(SEGMENT, SEGMENT))
	add_child(_basket)


## How far up it can go from here: to the first block over it, at most `height`.
func _reach(world: VoxelWorld) -> float:
	var base := Vector3i(global_position.floor())
	for k in range(1, int(height) + 1):
		if world.is_solid(base + Vector3i(0, k, 0)):
			return float(k) - 0.1
	return height


func _physics_process(delta: float) -> void:
	var game := Game.current
	if _max < 0.0:
		_max = _reach(game.world)
	life -= delta
	if life <= 0.0:
		queue_free()
		return
	if length < _max:
		length = minf(_max, length + grow * delta)
		while _coils.size() * SEGMENT < length - SEGMENT:
			var c := EntitySprite.new()
			c.setup(_body_tex, 1, Vector2(SEGMENT, SEGMENT))
			add_child(c)
			c.position = Vector3(0, SEGMENT * (_coils.size() + 1), 0)
			_coils.append(c)
	_head.position = Vector3(0, maxf(SEGMENT, length - SEGMENT), 0)
	_anim += delta
	_head.set_frame(int(_anim * 8.0) % 4)
	var light_at := global_position + Vector3(0, length * 0.5, 0)
	for s in [_head, _basket] + _coils:
		s.update_light(game.world, game.sky, light_at)


## The top of the snake (its head).
func top() -> float:
	return global_position.y + length


## A player standing at `pos` (their feet) can hold on: beside it and no higher
## than its head.
func holds(pos: Vector3) -> bool:
	var d := Vector2(pos.x - global_position.x, pos.z - global_position.z).length()
	return d < REACH and pos.y >= global_position.y - 0.5 and pos.y <= top()
