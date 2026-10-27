class_name PerfOverlay
extends PanelContainer
## The performance overlay (the "perf_overlay" control, F10 as Terraria's
## frame rate): frames a second, frame times (the average and the worst of
## the last second), CPU (the last second's average) and GPU time, what the renderer drew, memory, the
## chunks and what's about in the world. Its text is redone 4 times a second;
## the GPU timing is only switched on while it shows.

const REFRESH := 0.25
## Its gap from the bottom right corner.
const MARGIN := Vector2(12, 12)

var _label := Label.new()
var _wait := 0.0
## The last second's frames: [frame time, process time, physics time], in
## seconds.
var _frames: Array[Vector3] = []


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.55)
	bg.set_content_margin_all(8.0)
	bg.set_corner_radius_all(4)
	add_theme_stylebox_override("panel", bg)
	_label.add_theme_font_size_override("font_size", 16)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_label)


func toggle() -> void:
	visible = not visible
	_frames.clear()
	_wait = 0.0
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), visible)
	if visible:
		refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_frames.append(Vector3(delta, Performance.get_monitor(Performance.TIME_PROCESS),
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)))
	var total := 0.0
	for f in _frames:
		total += f.x
	while total > 1.0 and _frames.size() > 1:
		total -= _frames.pop_front().x
	_wait -= delta
	if _wait <= 0.0:
		_wait = REFRESH
		refresh()


func refresh() -> void:
	var avg := Vector3.ZERO
	var worst := 0.0
	for f in _frames:
		avg += f
		worst = maxf(worst, f.x)
	avg = avg / maxf(_frames.size(), 1.0)
	var vp := get_viewport().get_viewport_rid()
	var lines := [
		"%d FPS   frame %.1f ms (worst %.1f)" % [Engine.get_frames_per_second(), avg.x * 1000.0, worst * 1000.0],
		"CPU %.1f ms (physics %.1f)   render %.1f ms   GPU %.1f ms" % [
			avg.y * 1000.0, avg.z * 1000.0,
			RenderingServer.viewport_get_measured_render_time_cpu(vp),
			RenderingServer.viewport_get_measured_render_time_gpu(vp)],
		"3D at %s (%d%%, %s)" % [
			_resolution(), roundi(get_tree().root.scaling_3d_scale * 100.0),
			Settings.UPSCALERS[clampi(int(Settings.get_value("upscaling")), 0, Settings.UPSCALERS.size() - 1)][0]],
		"Draw calls %d   objects %d   primitives %s" % [
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
			_count(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))],
		"Memory %s   video %s   nodes %d" % [
			String.humanize_size(int(Performance.get_monitor(Performance.MEMORY_STATIC))),
			String.humanize_size(int(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED))),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)],
	]
	var game := Game.current
	if game != null and game.state == Game.State.PLAYING:
		lines.append("Chunks %d (meshing %d)" % [game.renderer.loaded_count(), game.renderer.pending_count()])
		var shots := 0
		var items := 0
		var minions := 0
		for e in game.entities.get_children():
			if e is Projectile:
				shots += 1
			elif e is ItemDrop:
				items += 1
			elif e is Minion:
				minions += 1
		lines.append("NPCs %d   projectiles %d   items %d   minions %d   lights %d" % [
			game.npcs().size(), shots, items, minions, game.dynamic_lights.count()])
	_label.text = "\n".join(lines)
	# (Placed by hand in the bottom right corner: the HUD's root has no size
	# yet when it's built, which throws off anchors.)
	reset_size()
	position = get_parent_area_size() - size - MARGIN


## 1234567 as "1.23M", 12345 as "12.3K".
static func _count(n: float) -> String:
	if n >= 1e6:
		return "%.2fM" % (n / 1e6)
	if n >= 1e4:
		return "%.1fK" % (n / 1e3)
	return str(int(n))


## The size the 3D is drawn at, as "1280×720".
func _resolution() -> String:
	var root := get_tree().root
	var s := Vector2(root.size) * root.scaling_3d_scale
	return "%d×%d" % [roundi(s.x), roundi(s.y)]
