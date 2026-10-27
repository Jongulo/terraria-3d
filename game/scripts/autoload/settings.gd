extends Node
## User settings, persisted to user://settings.json. Read with get_value();
## set_value() notifies listeners through `changed` and saves shortly after.

signal changed(key: String)

const PATH := "user://settings.json"
const DEFAULTS := {
	"mouse_sensitivity": 0.0025,
	"invert_y": false,
	"fov": 80.0,
	"render_distance": 7,
	"far_distance": 32,
	# The 3D view's resolution as a share of the window's, and how it's
	# stretched to fit (an index into UPSCALERS).
	"render_scale": 1.0,
	"upscaling": 1,
	"ui_scale": 1.0,
	"sfx_volume": 0.8,
	"music_volume": 0.6,
	"enemy_health_bars": true,
	# First person, or third from behind or in front (Player.view_mode).
	"camera_view": 0,
	# Optional shaders (Settings → Shaders): the sun's and moon's real-time
	# shadows (SunShadows), how far they reach (blocks), their detail (1-3:
	# a 2048, 4096 or 8192 shadow map) and how much sunlight a shadow leaves.
	"shadows": false,
	"shadow_distance": 64.0,
	"shadow_detail": 2,
	"shadow_shade": 0.5,
	# Global illumination (GlobalIllumination: 0 off, 1 screen space, 2 SDFGI,
	# 3 both) and how strong the bounced light is.
	"gi": 0,
	"gi_strength": 1.0,
	"autofire": false,
	"bindings": {},
}
const UI_SCALE_MIN := 0.5
const UI_SCALE_MAX := 2.0
const RENDER_SCALE_MIN := 0.25
const RENDER_SCALE_MAX := 2.0
## The upscaling methods offered, as [name, Viewport.Scaling3DMode].
const UPSCALERS := [
	["Nearest neighbor", Viewport.SCALING_3D_MODE_NEAREST],
	["Bilinear", Viewport.SCALING_3D_MODE_BILINEAR],
	["FSR 1.0", Viewport.SCALING_3D_MODE_FSR],
	["FSR 2.2", Viewport.SCALING_3D_MODE_FSR2],
]

## False keeps changes in memory only (automated tests must not touch the user's file).
var persist := true
var values := {}
var _save_pending := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f:
		var saved = JSON.parse_string(f.get_as_text())
		if saved is Dictionary:
			values = saved
	apply_render_scale()
	changed.connect(func(key):
		if key == "render_scale" or key == "upscaling":
			apply_render_scale())


func get_value(key: String):
	return values.get(key, DEFAULTS.get(key))


func set_value(key: String, value) -> void:
	if values.get(key) == value:
		return
	values[key] = value
	_save_pending = true
	changed.emit(key)


func _process(_delta: float) -> void:
	# Coalesce slider drags into one write.
	if _save_pending:
		_save_pending = false
		save()


func save() -> void:
	if not persist:
		return
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(values, "\t"))


## Renders the window's 3D at the chosen share of its resolution, stretched
## back up (or down, above 100%) with the chosen method. The UI stays sharp.
func apply_render_scale() -> void:
	var vp := get_tree().root
	vp.scaling_3d_scale = clampf(float(get_value("render_scale")), RENDER_SCALE_MIN, RENDER_SCALE_MAX)
	vp.scaling_3d_mode = UPSCALERS[clampi(int(get_value("upscaling")), 0, UPSCALERS.size() - 1)][1]


## Lays a full-screen UI root out at the user's UI scale: the control is sized to
## the viewport divided by the scale, then scaled up, so anchors still reach the
## screen edges. Call again when the scale or window size changes.
func apply_ui_scale(root: Control) -> void:
	var s := clampf(float(get_value("ui_scale")), UI_SCALE_MIN, UI_SCALE_MAX)
	root.set_anchors_preset(Control.PRESET_TOP_LEFT)
	root.position = Vector2.ZERO
	root.scale = Vector2(s, s)
	root.size = root.get_viewport_rect().size / s


## Keeps `root` scaled for its lifetime (window resizes and setting changes).
func track_ui_scale(root: Control) -> void:
	apply_ui_scale(root)
	var vp := root.get_viewport()
	var on_resize := func(): apply_ui_scale(root)
	var on_change := func(key: String):
		if key == "ui_scale":
			apply_ui_scale(root)
	vp.size_changed.connect(on_resize)
	changed.connect(on_change)
	root.tree_exiting.connect(func():
		if vp.size_changed.is_connected(on_resize):
			vp.size_changed.disconnect(on_resize)
		if changed.is_connected(on_change):
			changed.disconnect(on_change))
