class_name GlobalIllumination
extends Node
## Optional global illumination (Settings → Shaders): light bounced off
## what's lit nearby - a torch's glow on the cave around it, the sunlit grass
## tinting a wall green. Godot's own, on top of the game's light (which stays
## as it was):
## - Screen space (SSIL): from what's on screen; cheap, follows every change
##   at once, gone at the screen's edges.
## - SDFGI: from the world round you, off screen too, the sun's bounce
##   kept out of caves; it takes the blocks in as you move, so a tunnel you
##   dig shows in it once you've moved on a little.
## - Both.
## The shaders give the GI their colour to land on and their light to bounce
## (sun_shadow.gdshaderinc); the environment's ambient is black, so the GI is
## all it adds. With the shadows on, the sun reaches the GI through their
## light, as bright and as tinted as the sky's sunlight.

const OFF := 0
const SSIL := 1
const SDFGI := 2
const BOTH := 3
const NAMES := ["Off", "Screen space", "SDFGI", "SDFGI + screen space"]

var sky: SkySystem
var sun_shadows: SunShadows
var mode := OFF


func _ready() -> void:
	Settings.changed.connect(_on_setting_changed)
	_apply()


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("gi_on", false)


func _on_setting_changed(key: String) -> void:
	if key.begins_with("gi"):
		_apply()


func _apply() -> void:
	mode = clampi(int(Settings.get_value("gi")), OFF, BOTH)
	var strength := float(Settings.get_value("gi_strength"))
	var env: Environment = sky.env if sky != null else null
	if env != null:
		env.sdfgi_enabled = mode in [SDFGI, BOTH]
		env.ssil_enabled = mode in [SSIL, BOTH]
		# Blocks a metre across: cells half that, four cascades out (about
		# 200 blocks); the sky's light is the game's sun channel already.
		env.sdfgi_min_cell_size = 0.5
		env.sdfgi_cascades = 4
		env.sdfgi_use_occlusion = true
		env.sdfgi_read_sky_light = false
		env.sdfgi_energy = strength
		env.sdfgi_bounce_feedback = 0.5
		env.ssil_radius = 6.0
		env.ssil_intensity = strength
		env.ssil_sharpness = 0.98
	RenderingServer.global_shader_parameter_set("gi_on", mode != OFF)


func _process(_delta: float) -> void:
	# The shadows' light carries the sun into the SDFGI: the sky's sunlight
	# (dark at night, tinted at dawn) is its colour and bounce.
	var light: DirectionalLight3D = sun_shadows._light if sun_shadows != null else null
	if light != null and sky != null:
		light.light_color = sky.sky_tint
		light.light_indirect_energy = sky.sky_light if mode in [SDFGI, BOTH] else 0.0
