class_name Viewmodel
extends Node3D
## The held item in first person, Minecraft style: the item's sprite extruded
## into a 1-voxel-thick model (ItemMesh), held in the right hand. The hand node
## carries the arm animation (swing, equip, bob); the item node carries the grip
## pose for its kind of item.
##
## Poses come from data/viewmodel.json (written by the viewmodel editor,
## res://editor/viewmodel_editor.tscn); anything missing falls back to the
## built-in defaults below. A grip is a Dictionary:
##   position [x,y,z]  offset from the hand, camera space (metres)
##   rotation [x,y,z]  Euler degrees (Godot YXZ order)
##   scale             multiplier on the kind's base size
##   swing_axis [x,y,z], swing_angle   rotation applied by the swing animation

const CONFIG_PATH := "res://data/viewmodel.json"
## Where the right hand rests, relative to the camera (default).
const HAND_POS := Vector3(0.26, -0.29, -0.42)
const EQUIP_TIME := 0.18
const KINDS := ["sword", "pickaxe", "axe", "shortsword", "spear", "gun", "bow", "staff", "fishing", "item"]
## Base size per kind: [pixels per metre-ish divisor, min, max] for the longest sprite side.
const SIZES := {
	"sword": [64.0, 0.3, 0.62], "pickaxe": [64.0, 0.3, 0.62], "axe": [64.0, 0.3, 0.62],
	"shortsword": [64.0, 0.3, 0.62], "staff": [64.0, 0.3, 0.62], "spear": [56.0, 0.4, 0.8],
	"gun": [70.0, 0.22, 0.5], "bow": [70.0, 0.22, 0.5], "fishing": [64.0, 0.3, 0.45], "item": [90.0, 0.18, 0.3],
}

## {"hand": [x,y,z], "kinds": {kind: grip}, "items": {internal name: grip}}
static var config := {}
static var _config_loaded := false
## Set by the editor: no walking bob or equip animation.
static var editing := false

var player: Player
var _hand := Node3D.new()
var _item := MeshInstance3D.new()
## A held torch's flickering flame (TorchFlames.item_flame), on the item.
var _flame := MeshInstance3D.new()
var _flame_info := {}
var _ember_dust := -1
var _mat := ShaderMaterial.new()
var _item_name := ""
## Its prefix (Prefixes): a size prefix scales it.
var _item_prefix := 0
var _item_px := Vector2i.ONE
var _style := ""
var _t := 1.0
var _duration := 1.0
var _bob := 0.0
## 0 = lowered out of view, 1 = fully raised (Minecraft's equip animation).
var _equip := 1.0
var _swing_axis := Vector3.RIGHT
var _swing_angle := -60.0


static func load_config(path := CONFIG_PATH) -> void:
	_config_loaded = true
	config = {"kinds": {}, "items": {}}
	var f := FileAccess.open(path, FileAccess.READ)
	if f:
		var parsed = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			config.merge(parsed, true)


static func save_config(path := CONFIG_PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(config, "\t", false))
	return true


static func _ensure_config() -> void:
	if not _config_loaded:
		load_config()


static func hand_position() -> Vector3:
	_ensure_config()
	var h: Array = config.get("hand", [])
	return Vector3(h[0], h[1], h[2]) if h.size() == 3 else HAND_POS


static func kind_of(def: Dictionary) -> String:
	match def.get("type", ""):
		"tool":
			return "axe" if def.has("axe") and not def.has("pick") and not def.has("hammer") else "pickaxe"
		"melee":
			if def.has("yoyo") or def.has("flail"):
				return "item"
			if def.has("spear"):
				return "spear"
			return "shortsword" if def.get("style") == "thrust" else "sword"
		"ranged":
			return "bow" if def.get("ammo") == "WoodenArrow" else "gun"
		"magic":
			return "staff"
		"fishing_pole":
			return "fishing"
		_:
			return "item"


## The grip an item uses: its own override, else its kind's, else the default.
static func grip_for(item: String) -> Dictionary:
	_ensure_config()
	if config.items.has(item):
		return config.items[item]
	var kind := kind_of(Data.item(item))
	if config.kinds.has(kind):
		return config.kinds[kind]
	return default_grip(kind)


## Built-in poses. Blades point up and in toward the crosshair with their face
## turned toward the viewer; guns and staffs point ahead. Built from two targets:
## the sprite axis that should point along `dir` (camera space), with the sprite
## face turned toward `face` as far as that allows.
static func default_grip(kind: String) -> Dictionary:
	var tip_axis := Vector3(1, 1, 0)  # Terraria weapons point up-right
	var dir := Vector3.UP
	var offset := Vector3.ZERO
	var face := -HAND_POS.normalized()
	match kind:
		"sword", "pickaxe", "axe":
			face = Vector3(-0.8, 0.1, 0.6)
			dir = Vector3(-0.2, 0.85, -0.45)
		"shortsword":
			dir = Vector3(-0.3, 0.3, -0.9)
		"spear":
			# Held low, pointing ahead.
			dir = Vector3(-0.25, 0.2, -0.95)
			offset = Vector3(0.0, -0.04, 0.0)
		"gun", "bow":
			tip_axis = Vector3(1, 0, 0)  # barrel / arrow direction
			dir = Vector3(-0.22, 0.08, -1.0)
			offset = Vector3(-0.02, 0.1, 0.0)
		"staff":
			dir = Vector3(-0.3, 0.5, -0.8)
		"fishing":
			# Held out low on the right, the tip forward and up over the water
			# (seen from its back: a thin sprite can't show its face with the
			# tip pointing away).
			dir = Vector3(-0.15, 0.55, -0.82)
			face = Vector3(1.0, 0.0, 0.2)
			offset = Vector3(0.02, -0.06, 0.0)
		_:
			tip_axis = Vector3(0, 1, 0)
			dir = Vector3(0.05, 1.0, 0.15)
			offset = Vector3(-0.06, 0.02, 0.0)
	var basis := aim_basis(tip_axis.normalized(), dir.normalized(), face.normalized())
	var swing_axis := Vector3.RIGHT
	var swing_angle := -60.0
	if kind in ["sword", "pickaxe", "axe"]:
		# Rotating about the face normal chops forward within the blade's plane,
		# keeping the face visible (Minecraft style).
		swing_axis = basis.z.normalized()
		swing_angle = 100.0
	if kind == "axe":
		# Axe heads would trail a forward chop; spin half a turn about the handle.
		basis = basis * Basis(tip_axis.normalized(), PI)
	var e := basis.get_euler()
	return {
		"position": round_vec(offset, 0.0001),
		"rotation": round_vec(e * (180.0 / PI), 0.001),
		"scale": 1.0,
		"swing_axis": round_vec(swing_axis, 0.0001),
		"swing_angle": swing_angle,
	}


## Stored values are rounded so the JSON file round-trips exactly.
static func round_vec(v: Vector3, step: float) -> Array:
	return [snappedf(v.x, step), snappedf(v.y, step), snappedf(v.z, step)]


## Rotation taking the sprite axis `local_axis` to `dir`, with the sprite's face
## normal (+z) as close to `toward_viewer` as possible.
static func aim_basis(local_axis: Vector3, dir: Vector3, toward_viewer: Vector3) -> Basis:
	var local_up := Vector3(0, 0, 1).cross(local_axis)
	var local := Basis(local_axis, local_up, Vector3(0, 0, 1))
	var normal := (toward_viewer - dir * toward_viewer.dot(dir)).normalized()
	var world := Basis(dir, normal.cross(dir), normal)
	return world * local.transposed()


static func vec(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


## Item transform (relative to the hand) for a grip and sprite size.
static func grip_transform(grip: Dictionary, kind: String, px: Vector2i) -> Transform3D:
	var longest := float(maxi(px.x, px.y))
	var size: Array = SIZES.get(kind, SIZES.item)
	var length := clampf(longest / size[0], size[1], size[2]) * float(grip.get("scale", 1.0))
	var r := vec(grip.rotation) * (PI / 180.0)
	var basis := Basis.from_euler(r)
	var s := length / longest  # mesh units are pixels
	return Transform3D(basis.scaled_local(Vector3(s, s, s)), vec(grip.position))


# ------------------------------------------------------------------ instance

func _ready() -> void:
	_ensure_config()
	_mat.shader = preload("res://shaders/viewmodel.gdshader")
	_item.material_override = _mat
	_item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hand)
	_hand.add_child(_item)
	_flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_flame.visible = false
	_item.add_child(_flame)


func play(style: String, duration: float) -> void:
	_style = style
	_duration = maxf(duration, 0.05)
	_t = 0.0


## `carried`: the light the player carries (a held torch, a Mining Helmet).
func update_light(light: Color, sky: SkySystem, carried := Color.BLACK) -> void:
	var sun := light.a * sky.sky_light
	var l := Vector3(maxf(maxf(light.r, sun * sky.sky_tint.r), carried.r), maxf(maxf(light.g, sun * sky.sky_tint.g), carried.g),
			maxf(maxf(light.b, sun * sky.sky_tint.b), carried.b))
	_mat.set_shader_parameter("light", Vector3(maxf(l.x * l.x, 0.08), maxf(l.y * l.y, 0.08), maxf(l.z * l.z, 0.08)))


## Sets the light directly (editor preview without a sky).
func set_light_rgb(l: Vector3) -> void:
	_mat.set_shader_parameter("light", l)


## Stops any running use animation (the editor does this before transforming).
func stop_animation() -> void:
	_t = 1.0


## The item node and hand node (the editor transforms these).
func item_node() -> MeshInstance3D:
	return _item


func hand_node() -> Node3D:
	return _hand


## Where a pixel of the held item's sprite (image coordinates) is in the
## world (a fishing line leaves the pole's tip).
func item_point(px: Vector2) -> Vector3:
	return _item.global_transform * Vector3(px.x, _item_px.y - px.y, 0.0)


func _process(delta: float) -> void:
	var s = player.inventory.slots[player.selected]
	var item: String = "" if s == null else s.item
	var pre := 0 if s == null else int(s.get("prefix", 0))
	if item != _item_name or pre != _item_prefix:
		_item_prefix = pre
		_switch_to(item)
	# A yoyo or flail that's out isn't in your hand, and a spear is out in the world (Spear).
	# A boomerang in the air leaves your hand empty, unless you can throw another.
	var idef := Data.item(item) if item != "" else {}
	var thrown := idef.has("boomerang") and player.boomerangs_out(idef) >= int(idef.boomerang.get("max", 1))
	_item.visible = item != "" and not player.yoyo_out() and not player.flail_out() and not player.slash_out() and not player.whip_out() and not idef.has("spear") and not thrown
	# A held torch puffs embers too (Terraria: 1 tick in 40).
	if _item.visible and _ember_dust >= 0 and not editing and Game.current != null and randf() < delta * 60.0 / 40.0:
		var top: Vector2 = _flame_info.get("top", Vector2.ZERO)
		Game.current.torch_flames.spawn_ember(_item.global_transform * Vector3(top.x, top.y, 0.0), _ember_dust, 1.0 / 64.0)
	_equip = 1.0 if editing else minf(1.0, _equip + delta / EQUIP_TIME)
	_t = minf(1.0, _t + delta / _duration)
	var moving := not editing and Vector2(player.velocity.x, player.velocity.z).length() > 0.5 and player.on_floor
	_bob += delta * (9.0 if moving else 1.5)
	_animate_hand(moving)


func _switch_to(item: String) -> void:
	_item_name = item
	_t = 1.0  # the new item doesn't inherit the old one's animation
	_equip = 0.0
	if item == "":
		return
	var id := Data.item_id(item)
	var img := Assets.item_image(id)
	_item_px = img.get_size()
	_item.mesh = ItemMesh.build_art(img, str(id))
	_mat.set_shader_parameter("sprite", Assets.item_texture(id))
	_flame_info = TorchFlames.item_flame(id)
	_ember_dust = TorchFlames.item_ember(item)
	_flame.visible = not _flame_info.is_empty()
	if _flame.visible:
		# In item pixels, just in front of the item's face (it's one art
		# pixel thick), over where Terraria draws the held torch's flame.
		var q := QuadMesh.new()
		q.size = _flame_info.size
		_flame.mesh = q
		_flame.material_override = _flame_info.material
		var k := float(PixelArt.detect_scale(img).x)
		_flame.position = Vector3(_flame_info.centre.x, _flame_info.centre.y, k * 0.5 + 0.05)
	refresh_pose()


## Re-reads the current item's grip (after the config changed).
func refresh_pose() -> void:
	if _item_name == "":
		return
	var grip := grip_for(_item_name)
	_item.transform = grip_transform(grip, kind_of(Data.item(_item_name)), _item_px)
	# A size prefix (Large, Massive, Tiny...) makes it bigger or smaller.
	var size := float(Prefixes.of(_item_name, _item_prefix).get("scale", 1.0)) if _item_prefix > 0 else 1.0
	_item.transform.basis = _item.transform.basis.scaled(Vector3.ONE * size)
	_swing_axis = vec(grip.get("swing_axis", [1, 0, 0])).normalized()
	_swing_angle = float(grip.get("swing_angle", -60.0))


## Minecraft's arm transforms: swing = sin curves driving the configured swing
## rotation, plus equip drop and walking bob.
func _animate_hand(moving: bool) -> void:
	var pos := hand_position()
	var b := Basis()
	var p := _t if _t < 1.0 else 0.0
	match _style if _t < 1.0 else "":
		"swing", "throw":
			# Fast strike, slow recovery (Minecraft's sin(sqrt(p)) curve), with
			# the hand pushing slightly forward and in.
			var f1 := sin(sqrt(p) * PI)
			var f := sin(p * PI)
			pos += Vector3(-0.06 * f1, 0.05 * f1 + 0.03 * sin(sqrt(p) * TAU), -0.1 * f)
			b = Basis(_swing_axis, deg_to_rad(_swing_angle * f1))
		"thrust":
			var k := sin(p * PI)
			pos += Vector3(-0.1 * k, 0.03 * k, -0.28 * k)
		"hold":
			# Recoil: kick back and up, then settle.
			var k := sin(minf(p * 3.0, 1.0) * PI) if p < 0.34 else 0.0
			pos += Vector3(0.0, 0.01 * k, 0.07 * k)
			b = Basis(Vector3.RIGHT, deg_to_rad(12.0 * k))
		"drink":
			# Bring the item to the mouth and bob it, like eating in Minecraft.
			var k := minf(1.0, sin(p * PI) * 2.5)
			pos = pos.lerp(Vector3(0.07, -0.2, -0.5), k) + Vector3(0.0, absf(cos(p * 12.0)) * 0.02 * k, 0.0)
			b = Basis(Vector3.UP, deg_to_rad(-25.0 * k)) * Basis(Vector3.RIGHT, deg_to_rad(15.0 * k))
		"punch":
			var k := sin(p * PI)
			pos += Vector3(-0.08 * k, 0.04 * k, -0.18 * k)
	# Equip: the new item rises from below the screen.
	pos.y -= 0.45 * (1.0 - _equip) * (1.0 - _equip)
	if not editing:
		# Walking bob (swaying figure-eight), damped while standing still.
		var amp := 1.0 if moving else 0.25
		pos += Vector3(cos(_bob * 0.5) * 0.012, -absf(sin(_bob * 0.5)) * 0.018, 0.0) * amp
	_hand.transform = Transform3D(b, pos)


## Use animation style for an item (matches Player.use_item).
static func use_style(def: Dictionary) -> String:
	if def.has("yoyo") or def.has("boomerang") or def.has("flail"):
		return "throw"
	return def.get("style", "hold" if def.get("type") in ["ranged", "magic"] else "swing")
