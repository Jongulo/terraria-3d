class_name Starfall
extends Node
## Fallen Stars, like Terraria's (WorldGen.SpawnFallingObjects, Star.NightSetup):
## every tick of the night a star may fall, 10 in 8000 for a small world
## (more on wider ones, like Terraria's widths: about 40 a night on a small
## world), times the night's starfall: 1 night in 10 a Starfall (3 to 5
## times), otherwise 1 in 3 a little more (1 to 1.5 times). A star starts
## high in the top 5% of the sky anywhere over the world, heading down at a
## slant; 1 in 15 is a lucky star, falling within 40 blocks of you and
## drifting your way (if you're above ground). Each waits 3 seconds, then
## falls (FallingStar) and lands as a Fallen Star, which fades at sunrise.

## Terraria's star speed: 12 pixels a tick, in blocks a second.
const STAR_SPEED := 12.0 * 60.0 / 16.0

var game: Game
## Tonight's starfall (Terraria's starfallBoost).
var boost := 1.0
var _last_time := -1.0


func setup(g: Game) -> void:
	game = g
	game.sky.dusk.connect(night_setup)
	if not game.sky.is_day:
		night_setup()


## Terraria's Star.NightSetup: how many stars fall tonight.
func night_setup() -> void:
	boost = 1.0
	if randi() % 10 == 0:
		boost = randi_range(300, 500) * 0.01
	elif randi() % 3 == 0:
		boost = randi_range(100, 150) * 0.01


## Wider worlds get more, like Terraria's (a small world is 4200 tiles wide).
func world_scale() -> float:
	return float(game.world.get_size().x) / float(Game.WORLD_SIZES.small.x)


## Chance of a star each tick.
func chance() -> float:
	return 10.0 * world_scale() * boost / 8000.0


func _process(_delta: float) -> void:
	if game == null or game.state != Game.State.PLAYING or game.sky.is_day:
		_last_time = -1.0
		return
	var t := game.sky.time
	var ticks := 1 if _last_time < 0.0 or t < _last_time else int(t) - int(_last_time)
	_last_time = t
	for i in mini(ticks, 120):
		if randf() < chance():
			spawn()


## One star: where it starts and which way it falls. Returns it (or null if
## it would start inside a block).
func spawn(lucky := randi() % 15 == 0) -> FallingStar:
	var size: Vector3i = game.world.get_size()
	var pos := Vector3(randf_range(8.0, size.x - 8.0), size.y - 1.0 - randf() * size.y * 0.05, randf_range(8.0, size.z - 8.0))
	var player := game.player
	var p := player.global_position
	lucky = lucky and player.alive and p.y >= game.world.surface_y(int(p.x), int(p.z)) - 8
	if lucky:
		var r := randf_range(1.0, 40.0)
		var a := randf() * TAU
		pos.x = clampf(p.x + cos(a) * randf_range(-r, r), 1.0, size.x - 1.0)
		pos.z = clampf(p.z + sin(a) * randf_range(-r, r), 1.0, size.z - 1.0)
	if game.world.is_solid(Vector3i(pos.floor())):
		return null
	# Terraria: (-100..100, 100..300) scaled to the star's speed.
	var along := randf_range(-100.0, 100.0)
	var down := randf_range(100.0, 300.0)
	var way := Vector3.RIGHT.rotated(Vector3.UP, randf() * TAU)
	if lucky:
		# Slower sideways, and toward you.
		along = absf(along) * 0.35
		var to := Vector3(p.x - pos.x, 0.0, p.z - pos.z)
		way = to.normalized() if to.length() > 0.01 else way
	var star := FallingStar.new()
	star.velocity = (way * along + Vector3.DOWN * down).normalized() * STAR_SPEED
	game.entities.add_child(star)
	star.global_position = pos
	return star
