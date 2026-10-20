class_name Hud
extends CanvasLayer
## Terraria-style interface built from the game's own UI textures and fonts.

const SLOT := 46.0
const GAP := 4.0
const ORIGIN := Vector2(20, 24)
const HEART_HP := 20

var player: Player
var inventory_open := false
## The sign editor is open (writing on a sign).
var sign_open := false
var _sign := PanelContainer.new()
var _sign_edit := TextEdit.new()
var _sign_pos := Vector3i.ZERO
var _sign_read := PanelContainer.new()
var _sign_read_label := Label.new()
var paused := false

var _root := Control.new()
var _slots: Array[ItemSlot] = []
var _accessory_slots: Array[ItemSlot] = []
var _armor_slots: Array[ItemSlot] = []
## Terraria's hook equipment slot, under the defense shield.
var _hook_slot: ItemSlot
var _defense := DefenseIcon.new()
var _doll := PaperDoll.new()
## Talking to a town NPC: who (null when not), the chat box, and their shop.
var chat_npc: NPC = null
var _chat := PanelContainer.new()
var _chat_title := Label.new()
var _chat_text := Label.new()
var _chat_buttons := HBoxContainer.new()
var shop_open := false
var _shop_panel := Control.new()
var _shop_inv := Inventory.new(40)
var _shop_slots: Array[ItemSlot] = []
var _shop_title := Label.new()
var _shop_money := Label.new()
var _shop_hint: Label
## The Goblin Tinkerer's reforging (Terraria's reforge menu): its one slot,
## the cost and the hammer.
var reforge_open := false
var _reforge_panel := Control.new()
var _reforge_inv := Inventory.new(1)
var _reforge_slot: ItemSlot
var _reforge_cost := HBoxContainer.new()
var _reforge_button := TextureButton.new()
var _reforge_money := Label.new()
## After a best reforge the hammer rests a second (Main.reforgeCooldown),
## or until the mouse leaves it.
var _reforge_cooldown := 0.0
var _housing_button := Button.new()
var _housing := PanelContainer.new()
var _housing_text := Label.new()
var _chest_slots: Array[ItemSlot] = []
var _chest_panel := Control.new()
var _chest: Inventory
var _chest_pos := Vector3i.ZERO
var _cursor_stack = null
var _cursor_icon := TextureRect.new()
var _cursor_count := Label.new()
var _item_name := Label.new()
var _life_label := Label.new()
var _hearts := Control.new()
var _stars := Control.new()
var _clock := Label.new()
var _info := Label.new()
var _crosshair := Control.new()
var _messages := VBoxContainer.new()
var _pickups := VBoxContainer.new()
var _pickup_labels := {}
var _tooltip := PanelContainer.new()
var _tooltip_label := Label.new()
## The tooltip's prefix lines (green good, red bad) and the price under them.
var _tooltip_mods := VBoxContainer.new()
var _tooltip_extra := Label.new()
var _crafting := VBoxContainer.new()
var _crafting_scroll := ScrollContainer.new()
var _craft_title := Label.new()
var _boss_bar := ProgressBar.new()
## The Goblin Army's progress, bottom right while you're near it (Terraria's
## invasion progress bar, with its Extra_9 icon).
var _invasion := HBoxContainer.new()
var _invasion_bar := ProgressBar.new()
var _invasion_label: Label
var _boss_label := Label.new()
var _death := Control.new()
var _death_label := Label.new()
var _pause := PanelContainer.new()
var _loading := ColorRect.new()
var _loading_label := Label.new()
var _loading_bar := ProgressBar.new()
var _flash := ColorRect.new()
var _options: OptionsMenu
var _liquid_tint := ColorRect.new()
var _bubbles := HBoxContainer.new()
var _buffs := HBoxContainer.new()
var _buff_timer := 0.0
var _stations := {}
## Creative mode: every item, by category and search, in place of crafting.
const CREATIVE_TABS := {
	"All": [],
	"Blocks": ["block"],
	"Tools": ["tool", "bucket", "tool_use", "hook"],
	"Weapons": ["melee", "ranged", "magic", "thrown", "ammo"],
	"Accessories": ["accessory"],
	"Armor": ["armor"],
	"Consumables": ["consumable", "summon"],
	"Materials": ["material", "coin"],
	"Inventory": null,  # the main inventory instead of the palette
}
var _creative_panel := Control.new()
var _creative_search := LineEdit.new()
var _creative_grid := GridContainer.new()
var _creative_tab := "All"
var _creative_tab_buttons := {}
var _creative_scroll := ScrollContainer.new()
## The palette's items, as an inventory of full stacks the slots show.
var palette := Inventory.new(0)
var _mode_button := Button.new()
var _station_timer := 0.0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var theme := Theme.new()
	theme.default_font = Assets.font("Mouse_Text")
	theme.default_font_size = 22
	theme.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.9))
	theme.set_constant("shadow_offset_x", "Label", 2)
	theme.set_constant("shadow_offset_y", "Label", 2)
	_root.theme = theme
	add_child(_root)
	Settings.track_ui_scale(_root)
	_build_flash()
	_build_hud()
	_build_inventory()
	_build_overlays()
	_build_sign_ui()
	_build_town_ui()


func bind(p: Player) -> void:
	player = p
	for i in 50:
		_slots[i].inventory = p.inventory
	for i in 5:
		_accessory_slots[i].inventory = p.accessories
	for i in 3:
		_armor_slots[i].inventory = p.armor
	_hook_slot.inventory = p.hook_slot
	_defense.player = p
	_doll.player = p
	p.stats_changed.connect(_refresh)
	_refresh()


# ------------------------------------------------------------------ building

func _label(parent: Control, text: String, pos: Vector2, size := 22) -> Label:
	var l := Label.new()
	l.text = text
	l.position = pos
	l.add_theme_font_size_override("font_size", size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _slot(parent: Control, inv_index: int, pos: Vector2, back := "Inventory_Back") -> ItemSlot:
	var s := ItemSlot.new()
	s.index = inv_index
	s.background = Assets.texture("Images/" + back)
	s.position = pos
	s.size = Vector2(SLOT, SLOT)
	s.hud = self
	parent.add_child(s)
	return s


## Anchors a control to the top-right corner, `offset` from it (x negative),
## keeping its size. (Setting `position` would place it in the parent's
## current coordinates instead, ignoring the anchor.)
func _pin_top_right(c: Control, offset: Vector2) -> void:
	var sz := c.size
	c.anchor_left = 1.0
	c.anchor_right = 1.0
	c.anchor_top = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = offset.x
	c.offset_right = offset.x + sz.x
	c.offset_top = offset.y
	c.offset_bottom = offset.y + sz.y


func _build_flash() -> void:
	# Underwater / in-lava screen tint, beneath the rest of the HUD.
	_liquid_tint.set_anchors_preset(Control.PRESET_FULL_RECT)
	_liquid_tint.color = Color(0, 0, 0, 0)
	_liquid_tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_liquid_tint)
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.color = Color(1, 0, 0, 0)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_flash)


func _build_hud() -> void:
	for i in 50:
		var row := i / 10
		var col := i % 10
		var s := _slot(_root, i, ORIGIN + Vector2(col * (SLOT + GAP), row * (SLOT + GAP) + (8 if row > 0 else 0)))
		s.hotbar_number = (col + 1) % 10 if row == 0 else -1
		s.visible = row == 0
		_slots.append(s)
	_item_name.position = ORIGIN + Vector2(0, -24)
	_buffs.position = ORIGIN + Vector2(0, SLOT + 10)
	_buffs.add_theme_constant_override("separation", 6)
	_buffs.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_buffs)
	_item_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_item_name)

	# Right-hand column: life text, hearts, clock and depth (Terraria's info area).
	var right := VBoxContainer.new()
	right.anchor_left = 1.0
	right.anchor_right = 1.0
	right.offset_left = -340.0
	right.offset_right = -50.0
	right.offset_top = 6.0
	right.add_theme_constant_override("separation", 2)
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(right)
	_life_label = _label(right, "Life", Vector2.ZERO)
	_hearts.custom_minimum_size = Vector2(260, 54)
	_hearts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_hearts)
	# Breath bubbles, shown while underwater (Terraria draws them over the player).
	_bubbles.add_theme_constant_override("separation", 2)
	_bubbles.custom_minimum_size = Vector2(0, 24)
	_bubbles.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right.add_child(_bubbles)
	_clock = _label(right, "", Vector2.ZERO, 20)
	_info = _label(right, "", Vector2.ZERO, 18)
	_stars.anchor_left = 1.0
	_stars.anchor_right = 1.0
	_stars.offset_left = -36.0
	_stars.offset_top = 34.0
	_stars.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_stars)

	# Crosshair.
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r in [Rect2(-9, -1, 18, 2), Rect2(-1, -9, 2, 18)]:
		var shadow := ColorRect.new()
		shadow.color = Color(0, 0, 0, 0.6)
		shadow.position = r.position - Vector2(1, 1)
		shadow.size = r.size + Vector2(2, 2)
		shadow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crosshair.add_child(shadow)
	for r in [Rect2(-9, -1, 18, 2), Rect2(-1, -9, 2, 18)]:
		var bar := ColorRect.new()
		bar.color = Color(1, 1, 1, 0.9)
		bar.position = r.position
		bar.size = r.size
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_crosshair.add_child(bar)
	_root.add_child(_crosshair)

	_messages.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_messages.position = Vector2(20, -230)
	_messages.size = Vector2(800, 200)
	_messages.alignment = BoxContainer.ALIGNMENT_END
	_messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_messages)

	_pickups.set_anchors_preset(Control.PRESET_CENTER)
	_pickups.position = Vector2(-200, 60)
	_pickups.size = Vector2(400, 160)
	_pickups.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_pickups)

	_boss_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_boss_bar.position = Vector2(-300, -70)
	_boss_bar.size = Vector2(600, 22)
	_boss_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.12, 0.12)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.1, 0.05, 0.05, 0.8)
	bg.border_color = Color(0.9, 0.8, 0.6)
	bg.set_border_width_all(2)
	_boss_bar.add_theme_stylebox_override("fill", fill)
	_boss_bar.add_theme_stylebox_override("background", bg)
	_boss_bar.visible = false
	_invasion.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_invasion.position = Vector2(-330, -120)
	_invasion.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_invasion.visible = false
	var icon := TextureRect.new()
	icon.texture = Assets.texture("Images/Extra_9")
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2(40, 40)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_invasion.add_child(icon)
	var col := VBoxContainer.new()
	_invasion.add_child(col)
	_invasion_label = _label(col, "Goblin Army", Vector2.ZERO, 18)
	_invasion_bar.custom_minimum_size = Vector2(260, 14)
	_invasion_bar.show_percentage = false
	var ifill := StyleBoxFlat.new()
	ifill.bg_color = Color(0.69, 0.29, 1.0)
	var ibg := StyleBoxFlat.new()
	ibg.bg_color = Color(0.1, 0.05, 0.15, 0.8)
	ibg.border_color = Color(0.85, 0.75, 1.0)
	ibg.set_border_width_all(2)
	_invasion_bar.add_theme_stylebox_override("fill", ifill)
	_invasion_bar.add_theme_stylebox_override("background", ibg)
	col.add_child(_invasion_bar)
	_root.add_child(_invasion)
	_root.add_child(_boss_bar)
	_boss_label = _label(_boss_bar, "", Vector2(0, -28))
	_boss_label.size = Vector2(600, 26)
	_boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_inventory() -> void:
	for i in 5:
		var s := _slot(_root, i, Vector2.ZERO, "Inventory_Back3")
		_pin_top_right(s, Vector2(-90, 170 + i * (SLOT + GAP)))
		s.accept = "accessory"
		s.visible = false
		_accessory_slots.append(s)
	# Armor: a column left of the accessories (Terraria's head, body, legs),
	# the defense shield under it and you, wearing it, beside them.
	for i in 3:
		var s := _slot(_root, i, Vector2.ZERO, "Inventory_Back3")
		_pin_top_right(s, Vector2(-90 - (SLOT + GAP), 170 + i * (SLOT + GAP)))
		s.accept = Data.ARMOR_SLOTS[i]
		s.empty_icon = i * 2  # rows of Extra_54's first column: head, body, legs
		s.visible = false
		_armor_slots.append(s)
	# The hook slot under the defense shield, beside the last accessory, with
	# Terraria's hook silhouette.
	_hook_slot = _slot(_root, 0, Vector2.ZERO, "Inventory_Back3")
	_pin_top_right(_hook_slot, Vector2(-90 - (SLOT + GAP), 170 + 4 * (SLOT + GAP)))
	_hook_slot.accept = "hook"
	_hook_slot.empty_icon = 1
	_hook_slot.empty_icon_column = 1
	_hook_slot.tooltip_empty = "Hook"
	_hook_slot.visible = false
	_defense.hud = self
	_defense.size = Vector2(SLOT, SLOT)
	_defense.visible = false
	_root.add_child(_defense)
	_pin_top_right(_defense, Vector2(-90 - (SLOT + GAP), 170 + 3 * (SLOT + GAP) + 2))
	_doll.size = PaperDoll.FRAME * 2.0
	_doll.visible = false
	_doll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_doll)
	_pin_top_right(_doll, Vector2(-90 - (SLOT + GAP) - 12 - _doll.size.x, 170))

	_chest_panel.position = ORIGIN + Vector2(0, 5 * (SLOT + GAP) + 24)
	_chest_panel.visible = false
	_chest_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_chest_panel)
	_label(_chest_panel, "Chest", Vector2(0, 0))
	for i in Chests.SIZE:
		var s := _slot(_chest_panel, i, Vector2((i % 10) * (SLOT + GAP), 28 + (i / 10) * (SLOT + GAP)), "Inventory_Back5")
		_chest_slots.append(s)
	var x := 10 * (SLOT + GAP) + 10
	for b in [["Loot All", _loot_all], ["Deposit All", _deposit_all]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.flat = true
		btn.position = Vector2(x, 34 + (0 if b[0] == "Loot All" else 34))
		btn.pressed.connect(b[1])
		_chest_panel.add_child(btn)

	_build_creative_panel()

	_craft_title = _label(_root, "Crafting", Vector2.ZERO)
	_craft_title.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_craft_title.position = Vector2(20, -380)
	_craft_title.visible = false
	_crafting_scroll.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_crafting_scroll.position = Vector2(20, -350)
	_crafting_scroll.size = Vector2(SLOT + 30, 330)
	_crafting_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_crafting_scroll.visible = false
	_crafting.add_theme_constant_override("separation", int(GAP))
	_crafting_scroll.add_child(_crafting)
	_root.add_child(_crafting_scroll)

	_tooltip.visible = false
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.25, 0.85)
	sb.set_content_margin_all(8)
	sb.set_corner_radius_all(4)
	_tooltip.add_theme_stylebox_override("panel", sb)
	var tip_box := VBoxContainer.new()
	tip_box.add_theme_constant_override("separation", 0)
	_tooltip.add_child(tip_box)
	_tooltip_label.add_theme_font_size_override("font_size", 20)
	tip_box.add_child(_tooltip_label)
	_tooltip_mods.add_theme_constant_override("separation", 0)
	tip_box.add_child(_tooltip_mods)
	_tooltip_extra.add_theme_font_size_override("font_size", 20)
	tip_box.add_child(_tooltip_extra)
	_root.add_child(_tooltip)

	_cursor_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_cursor_icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_cursor_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_cursor_icon.size = Vector2(SLOT, SLOT)
	_cursor_count.add_theme_font_override("font", Assets.font("Item_Stack"))
	_cursor_count.add_theme_font_size_override("font_size", 18)
	_cursor_count.position = Vector2(6, 22)
	_cursor_icon.add_child(_cursor_count)
	_root.add_child(_cursor_icon)


func _build_creative_panel() -> void:
	# Under the hotbar, like Minecraft's creative screen (the main inventory
	# has its own tab).
	_creative_panel.position = ORIGIN + Vector2(0, SLOT + GAP + 24)
	_creative_panel.visible = false
	_creative_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_creative_panel)
	_label(_creative_panel, "Creative", Vector2(0, 0))
	_creative_search.placeholder_text = "Search items"
	_creative_search.position = Vector2(110, -2)
	_creative_search.size = Vector2(260, 32)
	_creative_search.text_changed.connect(func(_t): _fill_palette())
	_creative_panel.add_child(_creative_search)
	var tabs := HBoxContainer.new()
	tabs.position = Vector2(0, 34)
	tabs.add_theme_constant_override("separation", 4)
	_creative_panel.add_child(tabs)
	for t in CREATIVE_TABS:
		var b := Button.new()
		b.text = t
		b.toggle_mode = true
		b.add_theme_font_size_override("font_size", 18)
		b.pressed.connect(func():
			_creative_tab = t
			_fill_palette()
			_show_inventory_side())
		tabs.add_child(b)
		_creative_tab_buttons[t] = b
	_creative_scroll.position = Vector2(0, 74)
	_creative_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_creative_panel.add_child(_creative_scroll)
	_creative_grid.columns = 10
	_creative_grid.add_theme_constant_override("h_separation", int(GAP))
	_creative_grid.add_theme_constant_override("v_separation", int(GAP))
	_creative_scroll.add_child(_creative_grid)
	_root.resized.connect(_fit_palette)


## As many palette rows as fit on screen (at least one).
func _fit_palette() -> void:
	var top := _creative_panel.position.y + _creative_scroll.position.y
	var rows := clampi(floori((_root.size.y - top - 12.0) / (SLOT + GAP)), 1, 10)
	_creative_scroll.size = Vector2(10 * (SLOT + GAP) + 16, rows * (SLOT + GAP))


## Items shown in the creative palette: the tab's types, matching the search,
## grouped by tab order, then by name.
func creative_items() -> Array:
	var types: Array = CREATIVE_TABS[_creative_tab] if CREATIVE_TABS[_creative_tab] != null else []
	var order: Array = []
	for t in CREATIVE_TABS.values():
		if t != null:
			order.append_array(t)
	var query := _creative_search.text.strip_edges().to_lower()
	var out := Data.items.keys().filter(func(k):
		var d: Dictionary = Data.items[k]
		return (types.is_empty() or d.get("type", "") in types) \
				and (query == "" or String(d.get("name", k)).to_lower().contains(query)))
	out.sort_custom(func(a, b):
		var ta: int = order.find(Data.items[a].get("type", ""))
		var tb: int = order.find(Data.items[b].get("type", ""))
		return ta < tb if ta != tb else String(Data.items[a].name) < String(Data.items[b].name))
	return out


func _fill_palette() -> void:
	for t in _creative_tab_buttons:
		_creative_tab_buttons[t].set_pressed_no_signal(t == _creative_tab)
	var items := creative_items()
	palette = Inventory.new(items.size())
	for i in items.size():
		palette.slots[i] = Inventory.stack(items[i], palette.max_stack(items[i]))
	for c in _creative_grid.get_children():
		c.queue_free()
	for i in items.size():
		var sl := ItemSlot.new()
		sl.index = i
		sl.inventory = palette
		sl.background = Assets.texture("Images/Inventory_Back10")
		sl.custom_minimum_size = Vector2(SLOT, SLOT)
		sl.size = Vector2(SLOT, SLOT)
		sl.hud = self
		_creative_grid.add_child(sl)


## Minecraft's creative inventory: click takes a full stack (right click one,
## Shift+click straight into the inventory); clicking with something on the
## cursor deletes it.
func _palette_clicked(slot: ItemSlot, button: int) -> void:
	var s = palette.slots[slot.index]
	if _cursor_stack != null:
		_cursor_stack = null
		Audio.play("Grab", 0.4)
	elif s != null:
		if Input.is_key_pressed(KEY_SHIFT):
			player.inventory.add(s.item, s.count)
		else:
			_cursor_stack = Inventory.stack(s.item, 1 if button == MOUSE_BUTTON_RIGHT else s.count)
		Audio.play("Grab", 0.5)
	_refresh()


## After the game mode changes: life and mana shown only in survival, and
## the open inventory swaps crafting for the creative palette (or back).
func mode_changed() -> void:
	if inventory_open:
		_show_inventory_side()
	_mode_button.text = "Game mode: " + ("Creative" if Game.current.creative else "Survival")
	_refresh()


func _show_inventory_side() -> void:
	var creative: bool = Game.current.creative
	_crafting_scroll.visible = not creative
	_craft_title.visible = not creative
	_creative_panel.visible = creative and _chest == null
	# The palette covers the main inventory rows unless its tab is chosen.
	var palette_shown := _creative_panel.visible and _creative_tab != "Inventory"
	# Tabs under the hotbar over the palette; under the inventory on its tab.
	_creative_panel.position = ORIGIN + Vector2(0, (SLOT + GAP if palette_shown else 5 * (SLOT + GAP)) + 24)
	_creative_scroll.visible = palette_shown
	_creative_search.visible = palette_shown
	for sl in _slots:
		sl.visible = sl.index < 10 or not palette_shown
	if palette_shown:
		_fit_palette()
		if _creative_grid.get_child_count() == 0:
			_fill_palette()


func _build_overlays() -> void:
	_death.set_anchors_preset(Control.PRESET_FULL_RECT)
	_death.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_death.add_child(dim)
	_death_label.add_theme_font_override("font", Assets.font("Death_Text"))
	_death_label.add_theme_font_size_override("font_size", 64)
	_death_label.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	_death_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_death_label.set_anchors_preset(Control.PRESET_CENTER)
	_death_label.position = Vector2(-400, -60)
	_death_label.size = Vector2(800, 120)
	_death.add_child(_death_label)
	_root.add_child(_death)

	_pause.visible = false
	_pause.anchor_left = 0.5
	_pause.anchor_right = 0.5
	_pause.anchor_top = 0.5
	_pause.anchor_bottom = 0.5
	_pause.offset_left = -170.0
	_pause.offset_right = 170.0
	_pause.offset_top = -170.0
	_pause.offset_bottom = 170.0
	_pause.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_pause.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.15, 0.35, 0.92)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(16)
	_pause.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_pause.add_child(box)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 32)
	box.add_child(title)
	for b in [["Resume", toggle_pause], ["Settings", open_options], ["Save", func(): Game.current.save_world()],
			["Save & Exit", func(): Game.current.quit_to_menu(true)]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		box.add_child(btn)
	# Game mode (Minecraft's /gamemode): switches this world, saved with it.
	_mode_button.name = "GameMode"
	_mode_button.pressed.connect(func(): Game.current.set_creative(not Game.current.creative))
	box.add_child(_mode_button)
	box.move_child(_mode_button, 2)
	_root.add_child(_pause)

	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.color = Color(0.05, 0.07, 0.15)
	_loading.visible = false
	_loading_label.set_anchors_preset(Control.PRESET_CENTER)
	_loading_label.position = Vector2(-400, -60)
	_loading_label.size = Vector2(800, 40)
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 32)
	_loading.add_child(_loading_label)
	_loading_bar.set_anchors_preset(Control.PRESET_CENTER)
	_loading_bar.position = Vector2(-250, 0)
	_loading_bar.size = Vector2(500, 20)
	_loading_bar.max_value = 1.0
	_loading_bar.show_percentage = false
	_loading.add_child(_loading_bar)
	_root.add_child(_loading)


# ------------------------------------------------------------------ updates

func _process(delta: float) -> void:
	_flash.color.a = maxf(0.0, _flash.color.a - delta * 1.5)
	var mouse := _root.get_local_mouse_position()
	_cursor_icon.position = mouse + Vector2(4, 4)
	_tooltip.position = tooltip_position(mouse, _tooltip.size, _root.size)
	_reforge_cooldown = maxf(0.0, _reforge_cooldown - delta)
	if player == null:
		return
	if _death.visible:
		_death_label.text = "You were slain...\n%d" % ceili(player.respawn_timer)
	var game := Game.current
	var b := game.boss_status() if game else {}
	_invasion.visible = game != null and game.invasion.near(player.global_position)
	if _invasion.visible:
		_invasion_bar.value = game.invasion.progress() * 100.0
		_invasion_label.text = "Goblin Army  %d%%" % int(game.invasion.progress() * 100.0)
	_boss_bar.visible = not b.is_empty()
	if not b.is_empty():
		_boss_bar.value = float(b.life) / b.max * 100.0
		_boss_label.text = "%s  %d/%d" % [b.name, b.life, b.max]
	_info.text = info_text()
	_update_liquid_ui(delta)
	if inventory_open:
		_station_timer -= delta
		if _station_timer <= 0.0:
			_station_timer = 0.5
			var st: Dictionary = game.nearby_stations()
			if st != _stations:
				_stations = st
				_refresh_crafting()
	_crosshair.visible = not inventory_open and not paused and player.alive and not sign_open and chat_npc == null
	_update_sign_read()
	_update_chat()


func _update_liquid_ui(delta: float) -> void:
	var tint := Color(0, 0, 0, 0)
	if player.head_liquid == Player.LIQ_WATER:
		tint = Color(0.1, 0.25, 0.7, 0.32)
	elif player.head_liquid == Player.LIQ_LAVA:
		tint = Color(1.0, 0.35, 0.05, 0.6)
	elif player.head_liquid == Player.LIQ_HONEY:
		tint = Color(1.0, 0.72, 0.1, 0.5)
	_liquid_tint.color = _liquid_tint.color.lerp(tint, minf(1.0, delta * 12.0))
	# Bubbles: one per tenth of breath, only while short of air; else the
	# Lava Charm's flames while its time runs down (Terraria's breath meter).
	var want := 0 if player.breath >= Player.BREATH_MAX else ceili(player.breath / Player.BREATH_MAX * 10.0)
	var icon := "Images/Bubble"
	var lava_max := player.stat("lava_time")
	if lava_max > 0.0 and player.lava_time < lava_max and (want == 0 or player.in_liquid == Player.LIQ_LAVA):
		want = ceili(player.lava_time / lava_max * 10.0)
		icon = "Images/Flame"
	if _bubbles.get_child_count() != want or (want > 0 and _bubbles.get_child(0).texture != Assets.texture(icon)):
		for c in _bubbles.get_children():
			_bubbles.remove_child(c)
			c.queue_free()
		for i in want:
			var b := TextureRect.new()
			b.texture = Assets.texture(icon)
			b.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_bubbles.add_child(b)
	_buff_timer -= delta
	if _buff_timer <= 0.0:
		_buff_timer = 0.25
		_draw_buffs()


func _draw_buffs() -> void:
	for c in _buffs.get_children():
		c.queue_free()
	for b in player.buffs():
		var box := VBoxContainer.new()
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.texture = Assets.texture("Images/Buff_%d" % b[0])
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.tooltip_text = b[1]
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
		var t := Label.new()
		t.text = "%ds" % ceili(b[2])
		t.add_theme_font_size_override("font_size", 16)
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(t)
		_buffs.add_child(box)


## Radar: enemies within 2000 px (Terraria's accThirdEye count).
const RADAR_RANGE := 2000.0 / 24.0
## Feet a block (a foot is half a tile).
const FEET := 3.0


## What your informational accessories show (Terraria's Main.DrawInfoAccs):
## the Depth Meter, the Compass and the Radar, a line each.
func info_text() -> String:
	var game := Game.current
	var info := player.info_accessories()
	var lines: PackedStringArray = []
	if info.has("depth"):
		lines.append(depth_text())
	if info.has("compass"):
		lines.append(compass_text())
	if info.has("radar"):
		var n := 0
		for npc in game.npcs():
			if not npc.def.ai in ["town", "dummy"] and not npc.untouchable \
					and int(npc.def.get("life", 0)) > 5 and npc.center().distance_to(player.center()) < RADAR_RANGE:
				n += 1
		lines.append("No enemies nearby" if n == 0 else "1 enemy nearby!" if n == 1 else "%d enemies nearby!" % n)
	return "\n".join(lines)


## The Depth Meter: feet under (or over) the surface from your feet, and the
## layer: "123' Caverns", "Level Surface".
func depth_text() -> String:
	var game := Game.current
	var y := player.global_position.y
	var feet := int((game.surface_level - y) * FEET)
	var layer := "Underworld" if y < game.underworld_level else "Caverns" if y < game.cavern_level \
			else "Underground" if feet > 0 else "Surface" if y < game.space_level() else "Space"
	return ("Level" if feet == 0 else "%d'" % absi(feet)) + " " + layer


## The Compass: feet east or west of the world's middle (and, here in 3D,
## north or south of it): "45' East, 120' North", "Center".
func compass_text() -> String:
	var size: Vector3i = Game.current.world.get_size()
	var x := int((player.global_position.x - size.x * 0.5) * FEET)
	var z := int((player.global_position.z - size.z * 0.5) * FEET)
	var parts: PackedStringArray = []
	if x != 0:
		parts.append("%d' %s" % [absi(x), "East" if x > 0 else "West"])
	if z != 0:
		parts.append("%d' %s" % [absi(z), "South" if z > 0 else "North"])
	return "Center" if parts.is_empty() else ", ".join(parts)


func set_clock(text: String) -> void:
	_clock.text = text


func _refresh() -> void:
	if player == null:
		return
	for s in _slots:
		s.selected = s.index == player.selected
		s.queue_redraw()
	for s in _equipment_slots():
		s.queue_redraw()
	_defense.queue_redraw()
	_doll.queue_redraw()
	for s in _chest_slots:
		s.queue_redraw()
	var held := player.held()
	_item_name.text = held.get("name", "") if not inventory_open else "Inventory"
	_life_label.text = "Life: %d/%d" % [maxi(player.life, 0), player.life_max]
	# Creative mode, like Minecraft's, has no life or mana to show.
	_life_label.visible = not player.creative
	_hearts.visible = not player.creative
	_stars.visible = not player.creative
	_draw_hearts()
	_draw_stars()
	if inventory_open and not player.creative:
		_refresh_crafting()
	_update_cursor()


func _draw_hearts() -> void:
	for c in _hearts.get_children():
		c.queue_free()
	var count := player.life_max / HEART_HP
	var tex := Assets.texture("Images/Heart")
	for i in count:
		var fill := clampf(float(player.life - i * HEART_HP) / HEART_HP, 0.0, 1.0)
		var t := TextureRect.new()
		t.texture = tex
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.position = Vector2((i % 10) * 26, (i / 10) * 26)
		t.modulate = Color(1, 1, 1, 0.25 + 0.75 * fill)
		t.scale = Vector2.ONE * (0.6 + 0.4 * fill)
		t.pivot_offset = Vector2(11, 11)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_hearts.add_child(t)


func _draw_stars() -> void:
	for c in _stars.get_children():
		c.queue_free()
	var tex := Assets.texture("Images/Mana")
	for i in player.mana_cap() / 20:
		var fill := clampf(float(player.mana - i * 20) / 20.0, 0.0, 1.0)
		var t := TextureRect.new()
		t.texture = tex
		t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		t.position = Vector2(0, i * 26)
		t.modulate = Color(1, 1, 1, 0.25 + 0.75 * fill)
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_stars.add_child(t)


func flash_damage() -> void:
	_flash.color.a = 0.25


func message(text: String, color := Color.WHITE) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_messages.add_child(l)
	while _messages.get_child_count() > 8:
		_messages.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(7.0)
	tw.tween_property(l, "modulate:a", 0.0, 1.5)
	tw.tween_callback(l.queue_free)


## "Wood (3)" under the crosshair; repeated pickups of one item merge into one line.
func pickup(item: String, count: int, prefix := 0) -> void:
	var key := item if prefix == 0 else "%s#%d" % [item, prefix]
	var entry: Array = _pickup_labels.get(key, [])
	var l: Label
	if entry.is_empty() or not is_instance_valid(entry[0]):
		l = Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 20)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pickups.add_child(l)
		entry = [l, 0, null]
	l = entry[0]
	entry[1] += count
	l.text = Prefixes.of(item, prefix).get("name", item) + (" (%d)" % entry[1] if entry[1] > 1 else "")
	l.modulate.a = 1.0
	if entry[2]:
		entry[2].kill()
	var tw := l.create_tween()
	tw.tween_interval(1.5)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(func():
		_pickup_labels.erase(key)
		l.queue_free())
	entry[2] = tw
	_pickup_labels[key] = entry


func show_loading(text: String) -> void:
	_loading.visible = true
	_loading_label.text = text


func set_loading_progress(p: float) -> void:
	_loading_bar.value = p


func hide_loading() -> void:
	_loading.visible = false


func show_error(text: String) -> void:
	_loading.visible = true
	_loading_label.text = text


func show_death() -> void:
	_death.visible = true
	close_inventory()


func hide_death() -> void:
	_death.visible = false


# ------------------------------------------------------------------ menus

func _set_mouse_free(free: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if free else Input.MOUSE_MODE_CAPTURED
	player.input_enabled = not free


func toggle_pause() -> void:
	paused = not paused
	_mode_button.text = "Game mode: " + ("Creative" if Game.current.creative else "Survival")
	_pause.visible = paused
	get_tree().paused = paused
	_set_mouse_free(paused)


func _unhandled_input(event: InputEvent) -> void:
	# The game node is paused with the tree, so the HUD handles unpausing.
	if paused and event.is_action_pressed("pause") and not event.is_echo():
		if _options:
			_options.close()
		else:
			toggle_pause()
		get_viewport().set_input_as_handled()


func open_options() -> void:
	_pause.visible = false
	_options = OptionsMenu.new()
	_root.add_child(_options)
	_options.closed.connect(func():
		_options = null
		_pause.visible = paused)


func toggle_inventory() -> void:
	if inventory_open:
		close_inventory()
	else:
		_open_inventory()


func _open_inventory() -> void:
	if not player.alive:
		return
	inventory_open = true
	for s in _slots:
		s.visible = true
	for s in _equipment_slots():
		s.visible = true
	_defense.visible = true
	_doll.visible = true
	_housing_button.visible = true
	_show_inventory_side()
	_stations = Game.current.nearby_stations()
	Audio.play("Menu_Open")
	_set_mouse_free(true)
	_refresh()


func close_inventory() -> void:
	if not inventory_open:
		return
	inventory_open = false
	for s in _slots:
		s.visible = s.index < 10
	for s in _equipment_slots():
		s.visible = false
	_defense.visible = false
	_doll.visible = false
	_housing_button.visible = false
	_housing.visible = false
	if shop_open:
		shop_open = false
		_shop_panel.visible = false
		close_chat()
	if reforge_open:
		_close_reforge()
		close_chat()
	_crafting_scroll.visible = false
	_craft_title.visible = false
	_creative_panel.visible = false
	_creative_search.release_focus()
	_chest_panel.visible = false
	_chest = null
	_tooltip.visible = false
	# Whatever is on the cursor goes back into the inventory (or onto the ground).
	if _cursor_stack != null:
		var left := player.inventory.add_stack(_cursor_stack)
		if left > 0:
			Game.current.spawn_item(_cursor_stack.item, left, player.center() + player.forward(), Vector3.ZERO, 0.0, int(_cursor_stack.get("prefix", 0)))
		_cursor_stack = null
	Audio.play("Menu_Close")
	_set_mouse_free(false)
	_refresh()


func open_chest(inv: Inventory, pos: Vector3i) -> void:
	if not inventory_open:
		_open_inventory()
	_chest = inv
	_chest_pos = pos
	for s in _chest_slots:
		s.inventory = inv
	_chest_panel.visible = true
	_show_inventory_side()
	_refresh()


func _loot_all() -> void:
	if _chest == null:
		return
	for i in _chest.slots.size():
		var s = _chest.slots[i]
		if s != null:
			var left := player.inventory.add_stack(s)
			_chest.slots[i] = null if left == 0 else Inventory.stack(s.item, left, int(s.get("prefix", 0)))
	Audio.play("Grab")
	_refresh()


func _deposit_all() -> void:
	if _chest == null:
		return
	# Like Terraria, the hotbar stays put.
	for i in range(10, 50):
		var s = player.inventory.slots[i]
		if s != null:
			var left := _chest.add_stack(s)
			player.inventory.slots[i] = null if left == 0 else Inventory.stack(s.item, left, int(s.get("prefix", 0)))
	Audio.play("Grab")
	_refresh()


# ------------------------------------------------------------------ slots

## Terraria cursor rules: left click picks up/places/merges/swaps; right click takes one.
func slot_clicked(slot: ItemSlot, button: int) -> void:
	var inv: Inventory = slot.inventory
	if inv == null:
		return
	if inv == palette:
		_palette_clicked(slot, button)
		return
	if inv == _shop_inv:
		_shop_clicked(slot, button)
		return
	if not inventory_open:
		if slot.index < 10 and inv == player.inventory:
			player.select(slot.index)
		return
	var s = inv.slots[slot.index]
	if Input.is_key_pressed(KEY_SHIFT) and button == MOUSE_BUTTON_LEFT and s != null:
		_quick_move(slot)
		return
	# Right-clicking armor, an accessory or a hook puts it on, like Terraria.
	if button == MOUSE_BUTTON_RIGHT and s != null and _cursor_stack == null and slot.accept == "" \
			and Data.item(s.item).get("type") in ["armor", "accessory", "hook"]:
		equip(inv, slot.index)
		return
	if button == MOUSE_BUTTON_RIGHT:
		if s == null:
			return
		if _cursor_stack == null:
			_cursor_stack = Inventory.stack(s.item, 0, int(s.get("prefix", 0)))
		elif _cursor_stack.item != s.item or _cursor_stack.count >= inv.max_stack(s.item) or s.has("prefix") or _cursor_stack.has("prefix"):
			return
		_cursor_stack.count += 1
		inv.consume_slot(slot.index)
	else:
		if _cursor_stack != null and not slot_accepts(slot.accept, _cursor_stack.item):
			return
		if _cursor_stack == null:
			inv.slots[slot.index] = null
			_cursor_stack = s
		elif s == null:
			inv.slots[slot.index] = _cursor_stack
			_cursor_stack = null
		elif s.item == _cursor_stack.item and int(s.get("prefix", 0)) == int(_cursor_stack.get("prefix", 0)) and int(s.count) < inv.max_stack(s.item):
			var room := inv.max_stack(s.item) - int(s.count)
			var n := mini(room, int(_cursor_stack.count))
			s.count += n
			_cursor_stack.count -= n
			if _cursor_stack.count <= 0:
				_cursor_stack = null
		else:
			inv.slots[slot.index] = _cursor_stack
			_cursor_stack = s
	Audio.play("Grab", 0.5)
	inv.changed.emit()
	_refresh()


func _quick_move(slot: ItemSlot) -> void:
	var from: Inventory = slot.inventory
	var s = from.slots[slot.index]
	var to: Inventory
	if shop_open and from == player.inventory:
		sell(from, slot.index)
		return
	# Reforging, Shift-click swaps an item into the reforge slot.
	if reforge_open and from == player.inventory and Prefixes.can_have(s.item):
		from.slots[slot.index] = _reforge_inv.slots[0]
		_reforge_inv.slots[0] = s
		from.changed.emit()
		_reforge_inv.changed.emit()
		Audio.play("Grab", 0.5)
		_refresh()
		return
	if from == _reforge_inv:
		to = player.inventory
	elif _chest != null:
		to = player.inventory if from == _chest else _chest
	elif from == player.accessories or from == player.armor or from == player.hook_slot:
		to = player.inventory
	elif Data.item(s.item).get("type") in ["armor", "accessory", "hook"]:
		equip(from, slot.index)
		return
	else:
		return
	var left := to.add_stack(s)
	from.slots[slot.index] = null if left == 0 else Inventory.stack(s.item, left, int(s.get("prefix", 0)))
	from.changed.emit()
	Audio.play("Grab", 0.5)
	_refresh()


## The accessory, armor and hook slots.
func _equipment_slots() -> Array[ItemSlot]:
	var all: Array[ItemSlot] = _accessory_slots + _armor_slots
	all.append(_hook_slot)
	return all


## Whether an equipment slot ("accessory", "head", "body", "legs", "hook"; ""
## for any other slot) takes this item.
static func slot_accepts(accept: String, item: String) -> bool:
	var def := Data.item(item)
	if accept == "accessory":
		return def.get("type") == "accessory"
	if accept == "hook":
		return def.get("type") == "hook"
	if accept == "reforge":
		return Prefixes.can_have(item)
	if accept != "":
		return def.get("type") == "armor" and def.get("slot") == accept
	return true


## Puts on the armor piece, accessory or hook in `inv`'s slot `index`: armor
## goes to its slot, an accessory to the first free one (else the first), a
## hook to the hook slot; what was there takes its place.
func equip(inv: Inventory, index: int) -> void:
	var s = inv.slots[index]
	if s == null:
		return
	var def := Data.item(s.item)
	var to: Inventory
	var i := 0
	if def.get("type") == "armor":
		to = player.armor
		i = Data.ARMOR_SLOTS.find(def.get("slot"))
	elif def.get("type") == "accessory":
		to = player.accessories
		i = maxi(0, to.slots.find(null))
	elif def.get("type") == "hook":
		to = player.hook_slot
	if to == null or i < 0:
		return
	inv.slots[index] = to.slots[i]
	to.slots[i] = s
	inv.changed.emit()
	to.changed.emit()
	Audio.play("Grab", 0.5)
	_refresh()


func _update_cursor() -> void:
	if _cursor_stack == null:
		_cursor_icon.texture = null
		_cursor_count.text = ""
	else:
		_cursor_icon.texture = Assets.item_texture(Data.item_id(_cursor_stack.item))
		_cursor_count.text = str(_cursor_stack.count) if _cursor_stack.count > 1 else ""


## Where the tooltip box goes: below and right of the mouse, flipped to its
## left (or above it) when it would run past the window's edge.
static func tooltip_position(mouse: Vector2, box: Vector2, area: Vector2) -> Vector2:
	var at := mouse + Vector2(22, 18)
	if at.x + box.x > area.x:
		at.x = mouse.x - box.x - 10.0
	if at.y + box.y > area.y:
		at.y = mouse.y - box.y - 10.0
	return Vector2(clampf(at.x, 0.0, maxf(0.0, area.x - box.x)), clampf(at.y, 0.0, maxf(0.0, area.y - box.y)))


func show_tooltip(stack, slot: ItemSlot = null) -> void:
	if stack == null and slot != null and slot.tooltip_empty != "" and inventory_open:
		_set_tooltip(slot.tooltip_empty)
		return
	if stack == null or not inventory_open:
		_tooltip.visible = false
		return
	var def := Data.item_of(stack)
	# Prices while a shop is open: what it costs, or what you'd get for it.
	var price := ""
	if shop_open and slot != null:
		if slot.inventory == _shop_inv:
			price = "Buy price: " + Inventory.money_text(Data.value(stack.item))
		elif slot.inventory == player.inventory:
			var v := sell_price(stack.item, int(stack.get("prefix", 0))) * int(stack.count)
			price = "Sell price: " + Inventory.money_text(v) if v > 0 else "No value"
	_set_tooltip(item_tooltip(def, stack.count), Prefixes.tooltip_lines(def), price)


## Terraria's colours for a prefix's good and bad tooltip lines.
const PREFIX_GOOD := Color8(120, 190, 120)
const PREFIX_BAD := Color8(190, 120, 120)


## Shows the tooltip: its text, then prefix lines ([text, good]) and a price.
func _set_tooltip(text: String, mods := [], extra := "") -> void:
	_tooltip_label.text = text
	for c in _tooltip_mods.get_children():
		_tooltip_mods.remove_child(c)
		c.queue_free()
	for m in mods:
		var l := Label.new()
		l.text = m[0]
		l.add_theme_font_size_override("font_size", 20)
		l.add_theme_color_override("font_color", PREFIX_GOOD if m[1] else PREFIX_BAD)
		_tooltip_mods.add_child(l)
	_tooltip_extra.text = extra
	_tooltip_extra.visible = extra != ""
	_tooltip.visible = true
	_tooltip.reset_size()


static func item_tooltip(def: Dictionary, count := 1) -> String:
	var lines: Array[String] = [def.get("name", "?") + (" (%d)" % count if count > 1 else "")]
	if def.has("damage") and def.get("type") != "ammo":
		var kind: String = {"melee": "melee", "tool": "melee", "ranged": "ranged", "magic": "magic", "thrown": "thrown"}.get(def.type, "")
		# Flails show what they do thrown: twice their damage (Terraria's
		# ToolTipDamageMultiplier).
		lines.append("%d %s damage" % [int(def.damage) * (2 if def.has("flail") else 1), kind])
	elif def.get("type") == "ammo":
		lines.append("%d ranged damage" % def.damage)
		lines.append("Ammo")
	var weapon: bool = def.get("type") in ["melee", "ranged", "magic", "tool", "thrown"] and def.has("damage")
	if weapon:
		# Your chance with this weapon (Terraria's: its crit plus yours).
		var crit := 4.0 + float(def.get("crit", 0))
		if Game.current != null and Game.current.player != null:
			crit = Game.current.player.crit_chance(def) * 100.0
		lines.append("%d%% critical strike chance" % roundi(crit))
	if def.has("use_time") and def.get("type") in ["melee", "ranged", "magic", "tool", "thrown"]:
		# Terraria's words for its use time (useAnimation), in ticks.
		var t := int(def.get("use_animation", def.use_time))
		var words := [[8, "Insanely fast"], [20, "Very fast"], [25, "Fast"], [30, "Average"], [35, "Slow"], [45, "Very slow"], [55, "Extremely slow"]]
		var word := "Snail"
		for w in words:
			if t <= w[0]:
				word = w[1]
				break
		lines.append(word + " speed")
	if weapon:
		var kb := float(def.get("knockback", 0))
		var kb_words := [[1.5, "Extremely weak"], [3.0, "Very weak"], [4.0, "Weak"], [6.0, "Average"], [7.0, "Strong"], [9.0, "Very strong"], [11.0, "Extremely strong"]]
		var kb_word := "Insane"
		for w in kb_words:
			if kb <= w[0]:
				kb_word = w[1]
				break
		lines.append("No knockback" if kb == 0.0 else kb_word + " knockback")
	if def.has("pick"):
		lines.append("%d%% pickaxe power" % def.pick)
	if def.has("axe"):
		lines.append("%d%% axe power" % def.axe)
	if def.has("hammer"):
		lines.append("%d%% hammer power" % def.hammer)
		lines.append("Hit a block with water or lava behind it to make a waterfall")
	if def.has("mana") and def.get("type") == "magic":
		lines.append("Uses %d mana" % def.mana)
	if def.has("heal"):
		lines.append("Restores %d life" % def.heal)
	if def.has("max_life"):
		lines.append("Permanently increases maximum life by 20")
	if def.has("max_mana"):
		lines.append("Permanently increases maximum mana by 20")
	if def.get("type") == "consumable" or def.get("consumable", false):
		lines.append("Consumable")
	if def.get("type") == "block":
		lines.append("Can be placed")
	if def.get("type") in ["accessory", "armor"]:
		if def.get("type") == "armor" or def.has("defense"):
			lines.append("%d defense" % int(def.get("defense", 0)))
		lines.append("Equipable")
	if def.has("tooltip"):
		lines.append(def.tooltip)
	elif def.get("type") in ["accessory", "armor"] and Assets.item_tooltip(def.get("internal", "")) != "":
		lines.append(Assets.item_tooltip(def.internal))
	# Terraria shows the set bonus on the pieces of the set you are wearing.
	if def.get("type") == "armor" and Game.current != null and Game.current.player != null:
		var worn: Dictionary = Game.current.player.armor_set()
		if not worn.is_empty() and def.get("internal") in [worn.head, worn.body, worn.legs]:
			lines.append("Set bonus: " + set_bonus_text(worn))
	if def.get("type") == "summon":
		lines.append("Summons the Eye of Cthulhu")
	if def.get("type") == "material":
		lines.append("Material")
	return "\n".join(lines)


## A set's bonus in Terraria's words ("2 defense", ...).
static func set_bonus_text(a: Dictionary) -> String:
	var text := Assets.set_bonus_text(a.get("text", ""))
	if text == "" and a.has("defense"):
		text = "%d defense" % a.defense
	return text.replace("\n", "; ")


# ------------------------------------------------------------------ crafting

func _can_craft(r: Dictionary) -> bool:
	for st in r.get("stations", [r.station] if r.has("station") else []):
		if not _stations.has(st):
			return false
	for ing in r.ingredients:
		if player.inventory.count_spec(ing) < int(r.ingredients[ing]):
			return false
	return true


func _refresh_crafting() -> void:
	for c in _crafting.get_children():
		c.queue_free()
	for r in Data.recipes:
		if not _can_craft(r):
			continue
		var b := RecipeButton.new()
		b.recipe = r
		b.hud = self
		b.custom_minimum_size = Vector2(SLOT, SLOT)
		_crafting.add_child(b)


func craft(r: Dictionary) -> void:
	if not _can_craft(r):
		return
	# Crafted items go onto the cursor, stacking with what's already there.
	if _cursor_stack != null and (_cursor_stack.item != r.result or _cursor_stack.count + r.count > player.inventory.max_stack(r.result)):
		return
	for ing in r.ingredients:
		player.inventory.remove_spec(ing, int(r.ingredients[ing]))
	if _cursor_stack == null:
		# Crafted one at a time, it rolls a prefix (Terraria's Recipe.Create).
		_cursor_stack = Inventory.stack(r.result, r.count, Prefixes.roll(Data.item(r.result)) if r.count == 1 else 0)
	else:
		_cursor_stack.count += r.count
	Audio.play("Grab")
	_refresh()


func recipe_tooltip(r: Dictionary) -> void:
	var lines := [item_tooltip(Data.item(r.result), r.count), "", "Requires:"]
	for ing in r.ingredients:
		var names: Array = Array(ing.split("|")).map(func(n): return Data.item(n).get("name", n))
		lines.append("  %d %s" % [r.ingredients[ing], "Any Wood" if ing == Data.ANY_WOOD else " or ".join(names)])
	for st in r.get("stations", [r.station] if r.has("station") else []):
		if st in ["water", "honey", "lava"]:
			lines.append("  by %s" % st.capitalize())
		else:
			lines.append("  at a %s" % (st.replace("_", " ").capitalize() if st != "bottles" else "Placed Bottle"))
	_set_tooltip("\n".join(lines))


func show_text_tooltip(text: String) -> void:
	_set_tooltip(text)


func hide_tooltip() -> void:
	_tooltip.visible = false


# ------------------------------------------------------------------ controls

class ItemSlot extends Control:
	var hud: Hud
	var inventory: Inventory
	var index := 0
	var background: Texture2D
	var hotbar_number := -1
	var selected := false
	## What it takes: "" anything, else "accessory", "head", "body", "legs" or "hook".
	var accept := ""
	## Row of Extra_54 (in column empty_icon_column) drawn faded while empty
	## (-1 none): Terraria's silhouettes for the armor and hook slots.
	var empty_icon := -1
	var empty_icon_column := 0
	## Named in a tooltip while empty ("": none).
	var tooltip_empty := ""

	func _ready() -> void:
		mouse_entered.connect(func(): hud.show_tooltip(_stack(), self))
		mouse_exited.connect(func(): hud.show_tooltip(null))

	func _stack():
		return null if inventory == null else inventory.slots[index]

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			hud.slot_clicked(self, event.button_index)
			hud.show_tooltip(_stack(), self)
			accept_event()

	func _draw() -> void:
		var bg := Assets.texture("Images/Inventory_Back14") if selected else background
		draw_texture_rect(bg, Rect2(Vector2.ZERO, size), false, Color(1, 1, 1, 0.85))
		var s = _stack()
		if s != null:
			var tex := Assets.item_texture(Data.item_id(s.item))
			var ts := Vector2(tex.get_size())
			var fit := minf(1.0, (size.x - 14.0) / maxf(ts.x, ts.y))
			var draw_size := ts * fit
			draw_texture_rect(tex, Rect2((size - draw_size) * 0.5, draw_size), false)
			if s.count > 1:
				draw_string(Assets.font("Item_Stack"), Vector2(8, size.y - 6), str(s.count), HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		elif empty_icon >= 0:
			var icon := Rect2(empty_icon_column * 34, empty_icon * 34, 32, 32)
			draw_texture_rect_region(Assets.texture("Images/Extra_54"), Rect2((size - icon.size) * 0.5, icon.size), icon, Color(1, 1, 1, 0.55))
		if hotbar_number >= 0:
			draw_string(Assets.font("Item_Stack"), Vector2(5, 15), str(hotbar_number), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 1, 1, 0.8))


## Terraria's defense shield (Extra_58) with your total defense on it; the
## tooltip names it and the set bonus you have.
class DefenseIcon extends Control:
	var hud: Hud
	var player: Player

	func _ready() -> void:
		mouse_entered.connect(func(): hud.show_text_tooltip(tooltip()))
		mouse_exited.connect(func(): hud.hide_tooltip())

	func tooltip() -> String:
		var lines := ["%d Defense" % player.defense()]
		var a := player.armor_set()
		if not a.is_empty():
			lines.append("Set bonus: " + Hud.set_bonus_text(a))
		return "\n".join(lines)

	func _draw() -> void:
		if player == null:
			return
		var region := Rect2(0, 0, 52, 48)
		var at := (size - region.size) * 0.5
		draw_texture_rect_region(Assets.texture("Images/Extra_58"), Rect2(at, region.size), region)
		# Terraria's DrawDefenseCounter: the mouse text font, shadowed.
		var font := Assets.font("Mouse_Text")
		var text := str(player.defense())
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
		# White with a dark outline, like Terraria's (DrawDefenseCounter's
		# shadowed text), so it reads on the light shield.
		var at_text := Vector2((size.x - w) * 0.5, size.y * 0.5 + 8)
		# (A bitmap font: the outline is the text drawn dark round it.)
		for d in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2), Vector2(0, 2)]:
			draw_string(font, at_text + d, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.08, 0.08, 0.14))
		draw_string(font, at_text, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)


class RecipeButton extends Control:
	var hud: Hud
	var recipe: Dictionary

	func _ready() -> void:
		mouse_entered.connect(func(): hud.recipe_tooltip(recipe))
		mouse_exited.connect(func(): hud.hide_tooltip())

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			hud.craft(recipe)
			accept_event()

	func _draw() -> void:
		draw_texture_rect(Assets.texture("Images/Inventory_Back4"), Rect2(Vector2.ZERO, custom_minimum_size), false, Color(1, 1, 1, 0.85))
		var tex := Assets.item_texture(Data.item_id(recipe.result))
		var ts := Vector2(tex.get_size())
		var fit := minf(1.0, (custom_minimum_size.x - 14.0) / maxf(ts.x, ts.y))
		var draw_size := ts * fit
		draw_texture_rect(tex, Rect2((custom_minimum_size - draw_size) * 0.5, draw_size), false)
		if recipe.count > 1:
			draw_string(Assets.font("Item_Stack"), Vector2(8, custom_minimum_size.y - 6), str(recipe.count), HORIZONTAL_ALIGNMENT_LEFT, -1, 18)


# ------------------------------------------------------------------ town

func _build_town_ui() -> void:
	# The chat box: top centre, like Terraria's. Name, what they say, buttons.
	_chat.visible = false
	_chat.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_chat.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_chat.position.y = 70
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.15, 0.4, 0.9)
	sb.border_color = Color(0.05, 0.06, 0.18, 0.95)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(12)
	_chat.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_chat.add_child(box)
	_chat_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.35))
	box.add_child(_chat_title)
	_chat_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chat_text.custom_minimum_size.x = 440
	_chat_text.add_theme_font_size_override("font_size", 20)
	box.add_child(_chat_text)
	_chat_buttons.add_theme_constant_override("separation", 16)
	box.add_child(_chat_buttons)
	_root.add_child(_chat)

	# The shop: below the inventory, where a chest opens.
	_shop_panel.position = ORIGIN + Vector2(0, 5 * (SLOT + GAP) + 24)
	_shop_panel.visible = false
	_shop_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_shop_panel)
	_shop_title = _label(_shop_panel, "Shop", Vector2(0, 0))
	_shop_money = _label(_shop_panel, "", Vector2(0, 0), 18)
	_shop_money.modulate = Color(1.0, 0.9, 0.5)
	_shop_hint = _label(_shop_panel, "Click: buy (Shift: into your inventory). Sell: click the shop holding an item, or Shift-click it.", Vector2.ZERO, 16)
	_shop_hint.modulate = Color(1, 1, 1, 0.75)
	for i in _shop_inv.slots.size():
		var sl := _slot(_shop_panel, i, Vector2((i % 10) * (SLOT + GAP), 28 + (i / 10) * (SLOT + GAP)), "Inventory_Back6")
		sl.inventory = _shop_inv
		_shop_slots.append(sl)

	_build_reforge_panel()

	# Housing: who lives where, and checking the room you're in.
	_housing_button.text = "Housing"
	_housing_button.visible = false
	_root.add_child(_housing_button)
	_pin_top_right(_housing_button, Vector2(-90 - (SLOT + GAP) - 12 - PaperDoll.FRAME.x * 2.0, 170 + PaperDoll.FRAME.y * 2.0 + 8))
	_housing_button.pressed.connect(func():
		_housing.visible = not _housing.visible
		if _housing.visible:
			_refresh_housing())
	_housing.visible = false
	_housing.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_housing.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_housing.position.y = 60
	_housing.add_theme_stylebox_override("panel", sb)
	var hbox := VBoxContainer.new()
	_housing.add_child(hbox)
	_housing_text.add_theme_font_size_override("font_size", 18)
	_housing_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_housing_text.custom_minimum_size.x = 440
	hbox.add_child(_housing_text)
	var check := Button.new()
	check.text = "Check this room"
	check.pressed.connect(func(): _refresh_housing(check_room()))
	hbox.add_child(check)
	_root.add_child(_housing)


## Starts talking to a town NPC (right-click): what they say, and buttons.
func open_chat(npc: NPC, line := "") -> void:
	if paused or sign_open or not player.alive:
		return
	if inventory_open:
		close_inventory()
	if chat_npc != null:
		chat_npc.talking = false
	chat_npc = npc
	npc.talking = true
	_chat_title.text = npc.title()
	_chat_text.text = line if line != "" else npc.talk_line()
	for c in _chat_buttons.get_children():
		_chat_buttons.remove_child(c)
		c.queue_free()
	var buttons := []
	var town_def: Dictionary = npc.def.get("town", {})
	if town_def.has("shop"):
		buttons.append("Shop")
	buttons.append_array(town_def.get("buttons", []))
	if not Game.current.sky.is_day:
		buttons.append_array(npc.def.get("night_buttons", []))
	buttons.append("Close")
	for name in buttons:
		var b := Button.new()
		b.text = name
		b.flat = true
		b.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
		b.pressed.connect(chat_button.bind(name))
		_chat_buttons.add_child(b)
	_chat.visible = true
	_chat.reset_size()
	_chat.position.x = (_root.size.x - _chat.size.x) * 0.5
	_set_mouse_free(true)
	Audio.play("Menu_Open")


## A chat button: Shop, Help (the Guide), Heal (the Nurse), Status (the Dryad), Close.
func chat_button(name: String) -> void:
	if chat_npc == null:
		return
	match name:
		"Shop":
			open_shop()
		"Reforge":
			open_reforge()
		"Help":
			_chat_text.text = chat_npc.next_help()
		"Heal":
			_chat_text.text = Game.current.town.nurse_heal()
		"Status":
			_chat_text.text = Game.current.town.dryad_status()
		"Curse":
			var old_man := chat_npc
			close_chat()
			Game.current.curse_old_man(old_man)
			return
		"Close":
			close_chat()
	Audio.play("Menu_Tick")


func close_chat() -> void:
	if chat_npc == null:
		return
	if is_instance_valid(chat_npc):
		chat_npc.talking = false
	chat_npc = null
	_chat.visible = false
	if shop_open or reforge_open:
		close_inventory()
	elif not inventory_open:
		_set_mouse_free(false)
		Audio.play("Menu_Close")


## Terraria's coin colours (Colors.CoinPlatinum...), largest first.
const COIN_COLORS := [Color8(220, 220, 198), Color8(224, 201, 92), Color8(181, 192, 193), Color8(246, 138, 96)]


func _build_reforge_panel() -> void:
	# Where the shop opens, below the inventory.
	_reforge_panel.position = ORIGIN + Vector2(0, 5 * (SLOT + GAP) + 24)
	_reforge_panel.visible = false
	_reforge_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_reforge_panel)
	_label(_reforge_panel, "Reforge", Vector2(0, 0))
	_reforge_money.position = Vector2(110, 3)
	_reforge_money.add_theme_font_size_override("font_size", 18)
	_reforge_money.modulate = Color(1.0, 0.9, 0.5)
	_reforge_panel.add_child(_reforge_money)
	_reforge_slot = _slot(_reforge_panel, 0, Vector2(0, 28))
	_reforge_slot.inventory = _reforge_inv
	_reforge_slot.accept = "reforge"
	_reforge_cost.position = Vector2(SLOT + 14, 28)
	_reforge_cost.add_theme_constant_override("separation", 8)
	_reforge_cost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_reforge_panel.add_child(_reforge_cost)
	_reforge_button.texture_normal = Assets.texture("Images/UI/Reforge_0")
	_reforge_button.texture_hover = Assets.texture("Images/UI/Reforge_1")
	_reforge_button.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_reforge_button.position = Vector2(SLOT + 20, 28 + 30)
	_reforge_button.pressed.connect(reforge)
	_reforge_button.mouse_entered.connect(func(): show_text_tooltip("Reforge"))
	_reforge_button.mouse_exited.connect(func():
		_reforge_cooldown = 0.0
		hide_tooltip())
	_reforge_panel.add_child(_reforge_button)
	_reforge_inv.changed.connect(_refresh_reforge)


## The Goblin Tinkerer's Reforge button: the reforge slot opens with your
## inventory, where his shop would.
func open_reforge() -> void:
	if chat_npc == null:
		return
	var npc := chat_npc
	_chat.visible = false
	_open_inventory()
	chat_npc = npc
	reforge_open = true
	_reforge_panel.visible = true
	_refresh_reforge()


## What reforging the item in the slot costs: a third of its value (with its
## prefix), at least a copper (Main.DrawInventory's reforge price).
func reforge_cost() -> int:
	var s = _reforge_inv.slots[0]
	if s == null:
		return 0
	return maxi(1, Prefixes.value(s.item, int(s.get("prefix", 0))) * int(s.count) / 3)


## Pays and rerolls the item's prefix (Main.ReforgeItemInReforgeSlot): its new
## name pops up, with Terraria's sound, or the best-reforge one when it got
## the most valuable prefix it can have. False if there's nothing to reforge
## or you can't afford it.
func reforge() -> bool:
	var s = _reforge_inv.slots[0]
	if s == null or _reforge_cooldown > 0.0 or not player.inventory.pay(reforge_cost()):
		return false
	var def := Data.item(s.item)
	var pre := Prefixes.roll(def, Prefixes.REFORGE)
	_reforge_inv.slots[0] = Inventory.stack(s.item, int(s.count), pre)
	pickup(s.item, int(s.count), pre)
	if Prefixes.multipliers(def, pre).get("value", 0.0) == Prefixes.best_value(def):
		Audio.play("Custom/best_reforge", 1.0, 0.1)
		_reforge_cooldown = 1.0
	else:
		Audio.play("Item_37")
	_reforge_inv.changed.emit()
	_refresh()
	return true


func _refresh_reforge() -> void:
	_reforge_slot.queue_redraw()
	_reforge_money.text = "Your money: " + Inventory.money_text(player.inventory.money()) if player != null else ""
	for c in _reforge_cost.get_children():
		_reforge_cost.remove_child(c)
		c.queue_free()
	var s = _reforge_inv.slots[0]
	_reforge_button.visible = s != null
	if s == null:
		_label(_reforge_cost, "Place an item here to reforge", Vector2.ZERO, 20)
		return
	_label(_reforge_cost, "Cost:", Vector2.ZERO, 20)
	var amount := reforge_cost()
	for k in Inventory.COINS.size():
		var n := amount / Inventory.COIN_VALUES[k]
		amount -= n * Inventory.COIN_VALUES[k]
		if n > 0:
			var l := _label(_reforge_cost, "%d %s" % [n, ["platinum", "gold", "silver", "copper"][k]], Vector2.ZERO, 20)
			l.add_theme_color_override("font_color", COIN_COLORS[k])


## Before saving: what's on the cursor or in the reforge slot goes into your
## inventory, so it's saved (Terraria's SaveTemporaryItemSlotContents).
func stow_temporary_items() -> void:
	for s in [_cursor_stack, _reforge_inv.slots[0]]:
		if s != null and player.inventory.add_stack(s) == 0:
			if s == _cursor_stack:
				_cursor_stack = null
			else:
				_reforge_inv.slots[0] = null
	_refresh_reforge()
	_refresh()


## Ends reforging: what's in the slot goes back into your inventory (or onto
## the ground).
func _close_reforge() -> void:
	reforge_open = false
	_reforge_panel.visible = false
	var s = _reforge_inv.slots[0]
	if s != null:
		_reforge_inv.slots[0] = null
		var left := player.inventory.add_stack(s)
		if left > 0:
			Game.current.spawn_item(s.item, left, player.center() + player.forward(), Vector3.ZERO, 0.0, int(s.get("prefix", 0)))


## Walking away (or the NPC gone) ends the chat.
func _update_chat() -> void:
	if chat_npc == null:
		return
	if not is_instance_valid(chat_npc) or chat_npc.center().distance_to(player.center()) > 7.0 or not player.alive:
		close_chat()


## The NPC's shop, in place of the chest panel, with the inventory open.
func open_shop() -> void:
	if chat_npc == null:
		return
	var npc := chat_npc
	_chat.visible = false
	_open_inventory()
	chat_npc = npc
	shop_open = true
	_shop_inv.slots.fill(null)
	var i := 0
	for entry in npc.def.get("town", {}).get("shop", []):
		var item: String = entry if entry is String else entry[0]
		if entry is Array and entry[1] == "night" and Game.current.sky.is_day:
			continue
		_shop_inv.slots[i] = Inventory.stack(item, 1)
		i += 1
	_shop_title.text = "Shop: " + npc.title()
	# Only the rows it needs.
	var rows := maxi(1, ceili(i / 10.0))
	for sl in _shop_slots:
		sl.visible = sl.index < rows * 10
	_shop_hint.position = Vector2(0, 28 + rows * (SLOT + GAP))
	_shop_panel.visible = true
	_refresh_shop()


func _refresh_shop() -> void:
	_shop_money.text = "Your money: " + Inventory.money_text(player.inventory.money())
	_shop_money.position = Vector2(_shop_title.get_minimum_size().x + 30, 3)
	for sl in _shop_slots:
		sl.queue_redraw()


## A fifth of the item's value (with its prefix), like Terraria's (coins
## aren't sold).
static func sell_price(item: String, prefix := 0) -> int:
	if item in Inventory.COINS:
		return 0
	return Prefixes.value(item, prefix) / 5


## Sells the stack in `inv`'s slot `index` to the open shop.
func sell(inv: Inventory, index: int) -> bool:
	var s = inv.slots[index]
	if s == null or sell_price(s.item, int(s.get("prefix", 0))) <= 0:
		return false
	player.inventory.add_money(sell_price(s.item, int(s.get("prefix", 0))) * int(s.count))
	inv.slots[index] = null
	inv.changed.emit()
	Audio.play("Coins")
	_refresh_shop()
	_refresh()
	return true


## Buying (click: onto the cursor; Shift: into the inventory) or selling what
## the cursor holds (click the shop with it).
func _shop_clicked(slot: ItemSlot, _button: int) -> void:
	if _cursor_stack != null:
		var price := sell_price(_cursor_stack.item, int(_cursor_stack.get("prefix", 0))) * int(_cursor_stack.count)
		if price > 0:
			player.inventory.add_money(price)
			_cursor_stack = null
			Audio.play("Coins")
		_refresh_shop()
		_refresh()
		return
	var s = _shop_inv.slots[slot.index]
	if s == null:
		return
	buy(s.item, Input.is_key_pressed(KEY_SHIFT))


## Buys one `item` at its value. Returns false if you can't afford it (or
## the cursor holds something else).
func buy(item: String, to_inventory := false) -> bool:
	if not to_inventory and _cursor_stack != null and (_cursor_stack.item != item or _cursor_stack.count >= player.inventory.max_stack(item)):
		return false
	if not player.inventory.pay(Data.value(item)):
		message("You can't afford that", Color(1.0, 0.6, 0.5))
		return false
	if to_inventory:
		var left := player.inventory.add(item, 1)
		if left > 0:
			Game.current.spawn_item(item, left, player.center() + player.forward())
	elif _cursor_stack == null:
		_cursor_stack = Inventory.stack(item, 1)
	else:
		_cursor_stack.count += 1
	Audio.play("Coins")
	_refresh_shop()
	_refresh()
	return true


## Checks the room you're standing in (Housing.check): its verdict.
func check_room() -> String:
	var at := Vector3i((player.global_position + Vector3(0, 0.5, 0)).floor())
	var h := Housing.check(Game.current.world, at)
	Game.current.town.prune()
	if h.ok:
		for n in Game.current.town.residents.values():
			if n.home_key == h.key:
				return "This housing is occupied by %s." % n.title()
	return h.reason


func _refresh_housing(extra := "") -> void:
	var lines := []
	var town: Town = Game.current.town
	town.prune()
	for kind in Town.ROSTER:
		if town.residents.has(kind):
			var n: NPC = town.residents[kind]
			lines.append("%s: %s" % [n.title(), ("lives at %d, %d, %d" % [n.home_spot.x, n.home_spot.y, n.home_spot.z]) if n.home_key != "" else "homeless"])
	if lines.is_empty():
		lines.append("Nobody lives here yet.")
	var req: String = Assets.ids.get("names", {}).get("town", {}).get("HousingText", {}).get("HousingRequirements", "")
	lines.append("")
	lines.append(req)
	if extra != "":
		lines.append("")
		lines.append("This room: " + extra)
	_housing_text.text = "\n".join(lines)
	_housing.reset_size()
	_housing.position.x = (_root.size.x - _housing.size.x) * 0.5


# ------------------------------------------------------------------ signs

func _build_sign_ui() -> void:
	# The editor: centred, a text box with Save / Cancel (Escape cancels).
	_sign.visible = false
	_sign.set_anchors_preset(Control.PRESET_CENTER)
	_sign.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_sign.grow_vertical = Control.GROW_DIRECTION_BOTH
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.12, 0.15, 0.35, 0.92)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	_sign.add_theme_stylebox_override("panel", sb)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_sign.add_child(box)
	var title := Label.new()
	title.text = "Sign"
	title.add_theme_font_size_override("font_size", 24)
	box.add_child(title)
	_sign_edit.custom_minimum_size = Vector2(380, 150)
	_sign_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_sign_edit.add_theme_font_size_override("font_size", 18)
	box.add_child(_sign_edit)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	for b in [["Cancel", func(): close_sign(false)], ["Save", func(): close_sign(true)]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		row.add_child(btn)
	box.add_child(row)
	_root.add_child(_sign)
	# Reading: what the sign under the crosshair says.
	_sign_read.visible = false
	_sign_read.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sign_read.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_sign_read.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var rb := StyleBoxFlat.new()
	rb.bg_color = Color(0.1, 0.1, 0.25, 0.85)
	rb.set_content_margin_all(10)
	rb.set_corner_radius_all(4)
	_sign_read.add_theme_stylebox_override("panel", rb)
	_sign_read_label.add_theme_font_size_override("font_size", 20)
	_sign_read_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sign_read_label.custom_minimum_size.x = 320
	_sign_read_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sign_read.add_child(_sign_read_label)
	_root.add_child(_sign_read)


## Opens the editor for the sign at `pos`, showing what's on it.
func open_sign(pos: Vector3i, text: String) -> void:
	if inventory_open or paused or not player.alive:
		return
	sign_open = true
	_sign_pos = pos
	_sign_edit.text = text
	_sign.visible = true
	_set_mouse_free(true)
	_sign_edit.grab_focus()
	_sign_edit.set_caret_line(_sign_edit.get_line_count() - 1)
	_sign_edit.set_caret_column(_sign_edit.get_line(_sign_edit.get_line_count() - 1).length())
	Audio.play("Menu_Open")


## Closes the sign editor, keeping what was written if `save`.
func close_sign(save: bool) -> void:
	if not sign_open:
		return
	if save:
		Game.current.set_sign_text(_sign_pos, _sign_edit.text)
	sign_open = false
	_sign.visible = false
	_sign_edit.release_focus()
	_set_mouse_free(false)
	Audio.play("Menu_Close")


## Shows the text of the sign under the crosshair (below it, like a tooltip).
func _update_sign_read() -> void:
	var show := false
	if not sign_open and not inventory_open and not paused and player.alive and not player.target.is_empty():
		if Data.block(int(player.target.id)).get("interact") == "sign":
			var text: String = Game.current.sign_text(player.target.block)
			if text != "":
				_sign_read_label.text = text
				show = true
	_sign_read.visible = show
	if show:
		_sign_read.position = Vector2((_root.size.x - _sign_read.size.x) * 0.5, _root.size.y * 0.5 + 40)
