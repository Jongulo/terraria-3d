class_name PlayerLook
extends RefCounted
## How a character looks (Terraria's character creation): a hairstyle, a
## clothing style (skinVariant) and seven colours. Drawn from Terraria's
## player layers (Images/Player_<style>_<layer>), tinted.

## Terraria's default new character.
const DEFAULT_COLOURS := {
	"hair": Color8(215, 90, 55),
	"eyes": Color8(105, 90, 75),
	"skin": Color8(255, 125, 90),
	"shirt": Color8(175, 165, 140),
	"undershirt": Color8(160, 180, 215),
	"pants": Color8(255, 230, 175),
	"shoes": Color8(160, 105, 60),
}
## The colours in the order the character creator lists them.
const COLOUR_KEYS := ["hair", "eyes", "skin", "shirt", "undershirt", "pants", "shoes"]
## Clothing styles offered (UICharacterCreation._validClothStyles): five
## male, then five female.
const CLOTH_STYLES := [0, 2, 1, 3, 8, 4, 6, 5, 7, 9]
const FEMALE_STYLES := [4, 5, 6, 7, 9]
## Each clothing style's hairstyle, taken when you pick the style before
## choosing a hairstyle yourself (UICharacterCreation's
## _defaultHairstylesForClothStyle).
const STYLE_HAIR := {0: 0, 2: 1, 1: 12, 3: 2, 8: 28, 9: 68, 7: 18, 5: 22, 6: 81, 4: 5}
## Styles with a long coat or dress (layer 14, over the legs in the shirt's
## colour: PlayerDrawLayers.DrawPlayer_15_SkinLongCoat).
const LONG_COAT_STYLES := [3, 7, 8]

## Terraria's hairstyle (0-based: Images/Player_Hair_<hair + 1>).
var hair := 0
## Terraria's skinVariant.
var style := 0
var colours := DEFAULT_COLOURS.duplicate()

static var _hairs: Array[int] = []


## The hairstyles a new character can have, in Terraria's order
## (HairstyleUnlocksHelper.RebuildList at character creation).
static func creation_hairs() -> Array[int]:
	if _hairs.is_empty():
		for i in 51:
			_hairs.append(i)
		_hairs.append_array([136, 137, 138, 139, 140, 141, 142, 143, 144, 147, 148, 149, 150, 151, 154, 155, 157, 158, 161])
		for i in range(51, 123):
			_hairs.append(i)
		_hairs.append_array([134, 135, 146, 152, 153, 156, 159, 165, 160])
		for i in range(166, 228):
			_hairs.append(i)
	return _hairs


func colour(key: String) -> Color:
	return colours.get(key, DEFAULT_COLOURS[key])


func is_female() -> bool:
	return style in FEMALE_STYLES


## How far down a composite sheet its torso and shoulders are: a female's
## two rows below a male's (PlayerDrawSet.CreateCompositeData); arms alike.
func torso_rows() -> Vector2i:
	return Vector2i(0, 2) if is_female() else Vector2i.ZERO


## Layer `layer` of its clothing style's sheets: a style without its own
## takes the female starter's (styles 5-7, 9) or the male starter's
## (PlayerDataInitializer.CopyVariant); the starter has no long coat.
func layer_path(layer: int) -> String:
	for s in [style, 4 if is_female() else 0, 0]:
		var path := "Images/Player_%d_%d" % [s, layer]
		if Assets.has(path):
			return path
		if layer == 14:
			return ""
	return ""


func layer_texture(layer: int) -> Texture2D:
	var path := layer_path(layer)
	return Assets.texture(path) if path != "" else null


func layer_image(layer: int) -> Image:
	var path := layer_path(layer)
	return Assets.image(path) if path != "" else null


## Its hair sheet; `alt`: the trimmed one under a hat.
func hair_texture(alt := false) -> Texture2D:
	return Assets.texture("Images/Player_%s_%d" % ["HairAlt" if alt else "Hair", hair + 1])


func has_long_coat() -> bool:
	return style in LONG_COAT_STYLES


func to_data() -> Dictionary:
	var c := {}
	for k in COLOUR_KEYS:
		c[k] = colour(k).to_html(false)
	return {"hair": hair, "style": style, "colours": c}


static func from_data(d: Dictionary) -> PlayerLook:
	var look := PlayerLook.new()
	look.hair = int(d.get("hair", 0))
	look.style = int(d.get("style", 0))
	var c: Dictionary = d.get("colours", {})
	for k in COLOUR_KEYS:
		if c.has(k):
			look.colours[k] = Color.html(str(c[k]))
	return look


func duplicate_look() -> PlayerLook:
	return PlayerLook.from_data(to_data())


## Terraria's Random button (UICharacterCreation.Click_RandomizePlayer): any
## hairstyle and clothing style, colours of random hue, saturation and
## lightness (no lighter than 0.15), eyes not too pale, skin a warm tone.
static func random() -> PlayerLook:
	var look := PlayerLook.new()
	var hairs := creation_hairs()
	look.hair = hairs[randi() % hairs.size()]
	var eyes := _random_colour()
	while eyes.r8 + eyes.g8 + eyes.b8 > 300:
		eyes = _random_colour()
	look.colours.eyes = eyes
	var k := minf(randi_range(60, 119) * 0.01, 1.0)
	look.colours.skin = Color8(int(randi_range(240, 254) * k), int(randi_range(110, 139) * k), int(randi_range(75, 109) * k))
	for key in ["hair", "shirt", "undershirt", "pants", "shoes"]:
		look.colours[key] = _random_colour()
	look.style = CLOTH_STYLES[randi() % CLOTH_STYLES.size()]
	return look


## UICharacterCreation.ScaledHslToRgb of a random (h, s, l).
static func _random_colour() -> Color:
	return hsl(randf(), randf(), randf() * 0.85 + 0.15)


## Main.hslToRgb.
static func hsl(h: float, s: float, l: float) -> Color:
	if s == 0.0:
		return Color(l, l, l)
	var q := l * (1.0 + s) if l < 0.5 else l + s - l * s
	var p := 2.0 * l - q
	return Color(_hue(p, q, h + 1.0 / 3.0), _hue(p, q, h), _hue(p, q, h - 1.0 / 3.0))


static func _hue(p: float, q: float, t: float) -> float:
	t = fposmod(t, 1.0)
	if t < 1.0 / 6.0:
		return p + (q - p) * 6.0 * t
	if t < 0.5:
		return q
	if t < 2.0 / 3.0:
		return p + (q - p) * (2.0 / 3.0 - t) * 6.0
	return p
