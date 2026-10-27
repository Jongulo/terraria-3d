class_name CharacterCreator
extends HBoxContainer
## The title screen's character creation (Terraria's UICharacterCreation): a
## name, a difficulty, a hairstyle, a clothing style and seven colours (or
## Random), with the character shown as you make them. Create writes its
## file (PlayerFile) and gives its path.

signal created(path: String)
signal cancelled

var look := PlayerLook.new()
var difficulty := PlayerFile.CLASSIC
## A hairstyle you picked yourself stays when you change clothing styles;
## till then each style brings its own (TryAutoAssigningHair).
var _hair_chosen := false
var _doll := PaperDoll.new()
var _name_edit := LineEdit.new()
var _hair_label := Label.new()
var _style_label := Label.new()
var _difficulty_text := Label.new()
var _pickers := {}
var _create := Button.new()


func _ready() -> void:
	add_theme_constant_override("separation", 24)
	alignment = BoxContainer.ALIGNMENT_CENTER
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	_doll.look = look
	_doll.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_doll.custom_minimum_size = PaperDoll.FRAME * 4.0
	left.add_child(_doll)
	var random := Button.new()
	random.name = "Random"
	random.text = "Random"
	random.tooltip_text = "A random hairstyle, clothing style and colours"
	random.pressed.connect(func():
		look = PlayerLook.random()
		_hair_chosen = true
		_refresh())
	left.add_child(random)

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	right.custom_minimum_size.x = 320
	add_child(right)
	_name_edit.name = "NameEdit"
	_name_edit.placeholder_text = "Name"
	_name_edit.max_length = PlayerFile.NAME_MAX
	_name_edit.text_changed.connect(func(_t): _refresh())
	right.add_child(_name_edit)
	var diff := OptionButton.new()
	diff.name = "DifficultyPick"
	for i in PlayerFile.DIFFICULTIES.size():
		diff.add_item(PlayerFile.DIFFICULTIES[i])
	diff.item_selected.connect(func(i):
		difficulty = i
		_refresh())
	right.add_child(diff)
	_difficulty_text.add_theme_font_size_override("font_size", 18)
	right.add_child(_difficulty_text)
	right.add_child(_stepper("Hair", _hair_label, func(step: int):
		var hairs := PlayerLook.creation_hairs()
		look.hair = hairs[posmod(hairs.find(look.hair) + step, hairs.size())]
		_hair_chosen = true))
	right.add_child(_stepper("Style", _style_label, func(step: int):
		var styles := PlayerLook.CLOTH_STYLES
		look.style = styles[posmod(styles.find(look.style) + step, styles.size())]
		if not _hair_chosen:
			look.hair = PlayerLook.STYLE_HAIR[look.style]))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	for key in PlayerLook.COLOUR_KEYS:
		var l := Label.new()
		l.text = key.capitalize()
		grid.add_child(l)
		var pick := ColorPickerButton.new()
		pick.name = "Colour_" + key
		pick.edit_alpha = false
		pick.custom_minimum_size = Vector2(120, 28)
		pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pick.color_changed.connect(func(c: Color):
			look.colours[key] = c
			_doll.queue_redraw())
		grid.add_child(pick)
		_pickers[key] = pick
	right.add_child(grid)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	var back := Button.new()
	back.name = "Back"
	back.text = "Back"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.pressed.connect(func(): cancelled.emit())
	buttons.add_child(back)
	_create.name = "Create"
	_create.text = "Create"
	_create.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_create.pressed.connect(create)
	buttons.add_child(_create)
	right.add_child(buttons)
	_refresh()


## A row: its name, ◀, what's picked, ▶ (`change` takes -1 or 1).
func _stepper(what: String, label: Label, change: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var prev := Button.new()
	prev.name = what + "Prev"
	prev.text = "<"
	var next := Button.new()
	next.name = what + "Next"
	next.text = ">"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for b in [[prev, -1], [next, 1]]:
		b[0].pressed.connect(func():
			change.call(b[1])
			_refresh())
	row.add_child(prev)
	row.add_child(label)
	row.add_child(next)
	return row


func _refresh() -> void:
	_doll.look = look
	_doll.queue_redraw()
	var hairs := PlayerLook.creation_hairs()
	_hair_label.text = "Hair %d / %d" % [hairs.find(look.hair) + 1, hairs.size()]
	var styles := PlayerLook.CLOTH_STYLES
	_style_label.text = "Clothing %d / %d" % [styles.find(look.style) + 1, styles.size()]
	for key in _pickers:
		_pickers[key].color = look.colour(key)
	_difficulty_text.text = PlayerFile.DIFFICULTY_TEXT[difficulty]
	_difficulty_text.add_theme_color_override("font_color", PlayerFile.DIFFICULTY_COLOURS[difficulty])
	_create.disabled = _name_edit.text.strip_edges() == ""


## Writes the new character and gives its file.
func create() -> void:
	var name := _name_edit.text.strip_edges()
	if name == "":
		return
	var path := PlayerFile.path_for(name)
	if PlayerFile.write(path, PlayerFile.new_data(name, difficulty, look)):
		created.emit(path)
