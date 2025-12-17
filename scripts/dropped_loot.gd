class_name DroppedLoot
extends Area2D

## Represents a loot drop (item + gold) on the ground.
## When picked up by the player, the loot is transferred into the global inventory.

# DragState and LootPersistence are global classes (class_name)
const DROP_FONT := preload("res://art/fonts/ThaleahFat.ttf")
const LABEL_FONT_SIZE: int = 14
const PICKUP_RADIUS: float = 55.0  # "arm's length" - radius in pixels in which loot can be picked up
const LOOT_ICON := preload("res://art/images/Loot.png")
const GOLD_ICON := preload("res://art/images/Gold.png")
const ItemResource = preload("res://resources/item.gd")
const ItemTypeResource = preload("res://resources/item_type.gd")

const LOOT_SYSTEM_DISABLED := false
static var ALL_DROPS: Array = []
static var LOOT_ALWAYS_VISIBLE: bool = false

var gold: int = 0
var item: Dictionary = {}   # legacy view (kept for UI/debug)
var item_stack: ItemStack = null
var _registry: ItemRegistryClass = null

func _dict_from_stack(st: ItemStack) -> Dictionary:
	if st == null or st.item == null:
		return {}
	var pos_meta = st.get_meta("position") if st.has_meta("position") else {}
	return {
		"id": st.item.id,
		"name": st.item.name,
		"rarity": st.item.rarity,
		"item_type": st.item.item_type.tab_name if st.item.item_type else "",
		"item_level": st.get_meta("item_level") if st.has_meta("item_level") else st.item.item_level,
		"description": st.item.description,
		"amount": st.amount,
		"stackable": st.item.item_type.stackable if st.item.item_type else false,
		"max_stack": st.item.item_type.max_stack if st.item.item_type else 1,
		"stats": st.item.stats,
		"requirements": st.item.requirements if st.item.has_method("get") else {},
		"material": st.get_meta("material") if st.has_meta("material") else st.item.material if st.item.has_method("get") else {},
		"enchant_slots": st.item.enchant_slots,
		"enchantments": st.get_meta("enchantments") if st.has_meta("enchantments") else st.item.enchantments,
		"position": pos_meta,
	}

func _stack_from_dict(dict: Dictionary) -> ItemStack:
	if dict == null or dict.is_empty():
		return null
	if _registry == null:
		if Engine.has_singleton("ItemRegistry"):
			_registry = Engine.get_singleton("ItemRegistry")
	# Fallback to minimal item build if registry is missing or item is unknown
	var id := String(dict.get("id", dict.get("name", "")))
	if id == "":
		return null
	var itm = null
	if _registry != null:
		itm = _registry.get_item(id)
	if itm == null:
		itm = _item_minimal(dict, id)
		if itm == null:
			return null
	# carry instance fields
	if dict.has("item_level"):
		itm.item_level = int(dict.get("item_level", 1))
	if dict.has("enchantments"):
		itm.enchantments = dict.get("enchantments", [])
	if dict.has("requirements"):
		itm.requirements = dict.get("requirements", {})
	if dict.has("material"):
		itm.material = dict.get("material", {})
	if dict.has("position"):
		# Position not in item, but as meta on stack
		pass
	var st := ItemStack.new()
	st.item = itm
	st.amount = max(1, int(dict.get("amount", 1)))
	
	# Copy known metadata
	if dict.has("item_level"):
		st.set_meta("item_level", int(dict.get("item_level", 1)))
	if dict.has("enchantments"):
		st.set_meta("enchantments", dict.get("enchantments", []))
	if dict.has("requirements"):
		st.set_meta("requirements", dict.get("requirements", {}))
	if dict.has("material"):
		st.set_meta("material", dict.get("material", {}))
	if dict.has("position"):
		st.set_meta("position", dict.get("position"))
	if dict.has("min_player_level"):
		st.set_meta("min_player_level", int(dict.get("min_player_level", 1)))
	
	# Copy all other Dictionary keys as metadata (if present)
	for key in dict.keys():
		if key in ["id", "name", "rarity", "item_type", "item_level", "description", 
				   "amount", "stackable", "max_stack", "stats", "requirements", 
				   "enchant_slots", "enchantments", "material", "min_player_level", "position"]:
			continue  # These are already handled or are item properties
		# Copy all other keys as metadata
		if not st.has_meta(key):
			st.set_meta(key, dict[key])
	
	return st

func _item_minimal(dict: Dictionary, id: String) -> Item:
	var itm := ItemResource.new()
	itm.id = id
	itm.name = String(dict.get("name", id))
	itm.rarity = String(dict.get("rarity", "normal"))
	itm.item_level = int(dict.get("item_level", 1))
	itm.description = String(dict.get("description", ""))
	itm.enchant_slots = int(dict.get("enchant_slots", 0))
	itm.stats = dict.get("stats", {})
	itm.requirements = dict.get("requirements", {})
	itm.material = dict.get("material", {})
	itm.enchantments = dict.get("enchantments", [])
	var t := ItemTypeResource.new()
	t.tab_name = String(dict.get("item_type", ""))
	t.stackable = bool(dict.get("stackable", false))
	t.max_stack = int(dict.get("max_stack", (20 if t.stackable else 1)))
	itm.item_type = t
	return itm

var label: RichTextLabel
var _item_text: String = ""
var _gold_text: String = ""
var _rarity: String = "normal"
var _label_offset_x: float = 0.0
var _label_offset_y: float = 0.0

# Getters for external access
func get_item_text() -> String:
	return _item_text

func get_gold_text() -> String:
	return _gold_text

func get_label_offset_x() -> float:
	return _label_offset_x

func get_label_offset_y() -> float:
	return _label_offset_y

var _picked_up: bool = false
const HOLD_TO_DRAG_DELAY: float = 0.2
var _hold_timer: SceneTreeTimer = null
var _is_hovered: bool = false
var _hover_scale: float = 1.0
var _hover_tween: Tween = null
var _circle_color: Color = Color(1.0, 1.0, 0.0, 0.9)
var _loot_sprite: Sprite2D = null
var _gold_sprite: Sprite2D = null


func _get_player() -> Node2D:
	"""Helper to find the player node."""
	var scene := get_tree().current_scene
	if scene == null:
		return null
	var player: Node2D = scene.get_node_or_null("Player")
	if player == null:
		player = scene.find_child("Player", true, false)
	return player


func is_in_pickup_range() -> bool:
	"""Checks if this loot is within pickup range of the player."""
	var player := _get_player()
	if player == null:
		return false
	var dist := global_position.distance_to(player.global_position)
	return dist <= PICKUP_RADIUS


func _ready() -> void:
	if LOOT_SYSTEM_DISABLED:
		visible = false
		return
	# Ensure the drop is rendered above the ground
	z_index = 100

	# Allow mouse clicks on this Area2D
	input_pickable = true

	# CollisionShape for click/hover area
	# Dynamically adjusted in _update_collision_shape() to only cover the text area
	var shape := CollisionShape2D.new()
	var rect_shape := RectangleShape2D.new()
	shape.shape = rect_shape
	shape.name = "ClickCollision"
	add_child(shape)
	_update_collision_shape()

	# Label for item/gold display (as child of this 2D node, not UI layout)
	_ensure_label()

	# Connect signals correctly in Godot 4
	body_entered.connect(_on_body_entered)
	input_event.connect(_on_input_event)

	# Create loot icon sprite (items only)
	_loot_sprite = Sprite2D.new()
	_loot_sprite.texture = LOOT_ICON
	_loot_sprite.scale = Vector2(0.4, 0.4)
	_loot_sprite.z_index = 99  # below text, above ground
	_loot_sprite.visible = false  # controlled by _update_loot_icon()
	add_child(_loot_sprite)

	# Create gold icon sprite (gold only)
	_gold_sprite = Sprite2D.new()
	_gold_sprite.texture = GOLD_ICON
	_gold_sprite.scale = Vector2(0.36, 0.36)  # 10% smaller than loot icon (0.4 * 0.9)
	_gold_sprite.z_index = 99  # below text, above ground
	_gold_sprite.visible = false  # controlled by _update_loot_icon()
	add_child(_gold_sprite)

	# Registry (autoload) for stack conversion
	if Engine.has_singleton("ItemRegistry"):
		_registry = Engine.get_singleton("ItemRegistry")
	else:
		_registry = null

	# Fallback: if only legacy item is present, build a stack from it
	if item_stack == null and item is Dictionary and not item.is_empty():
		item_stack = _stack_from_dict(item)

	ALL_DROPS.append(self)
	_reflow_all_labels()
	# Update loot icon if setup_drop() was already called
	_update_loot_icon()


func setup_drop(world_pos: Vector2, gold_amount: int, item_dict: Dictionary) -> void:
	# Position is already stacked nicely by enemy_marker (spawner)
	global_position = world_pos
	gold = gold_amount
	item = item_dict
	item_stack = _stack_from_dict(item_dict)
	
	# Only set position field if there is no existing loot/drag tag
	if item is Dictionary and not item.is_empty():
		var pos_info: Variant = item.get("position", null)
		var has_loot_or_drag: bool = pos_info is Dictionary and (pos_info.has("loot") or pos_info.has("drag"))
		if not has_loot_or_drag:
			var pos_str: String = "%d,%d" % [int(world_pos.x), int(world_pos.y)]
			item["position"] = pos_str
	
	visible = true
	_ensure_label()
	_update_label()
	_reflow_all_labels()
	# Update loot icon after setup (if sprite already exists)
	# If _ready() hasn't been called yet, it will be updated there
	if _loot_sprite != null:
		_update_loot_icon()


func _exit_tree() -> void:
	ALL_DROPS.erase(self)
	_reflow_all_labels()


func _ensure_label() -> void:
	if label == null:
		label = RichTextLabel.new()
		label.bbcode_enabled = true
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.position = Vector2(0, -20)  # slightly above ground
		label.size = Vector2(200, 24)
		add_child(label)


func _update_label() -> void:
	_item_text = ""
	_gold_text = ""
	_rarity = "normal"
	_label_offset_x = 0.0
	_label_offset_y = 0.0

	if item_stack != null and item_stack.item != null:
		var item_name: String = item_stack.item.name
		if item_name == "":
			item_name = item_stack.item.id
		_rarity = String(item_stack.item.rarity)
		var amount: int = int(item_stack.amount)
		if amount > 1:
			_item_text = "%s x%d" % [item_name, amount]
		else:
			_item_text = item_name
	elif item is Dictionary and not item.is_empty():
		var item_name2: String = String(item.get("name", item.get("id", "Item")))
		_rarity = String(item.get("rarity", "normal"))
		var amount2: int = int(item.get("amount", 1))
		if amount2 > 1:
			_item_text = "%s x%d" % [item_name2, amount2]
		else:
			_item_text = item_name2

	if gold > 0:
		_gold_text = "%d Gold" % gold

	# Do not use label for rendering any more; drawing happens in _draw
	if label:
		label.visible = false

	queue_redraw()
	_reflow_all_labels()
	_update_collision_shape()
	_update_loot_icon()


func _draw() -> void:
	# Icons are displayed as Sprite2D, not drawn here
	# No yellow dot needed anymore

	# Visibility logic:
	# - show_loot (e.g. G) / G held -> show temporarily
	# - toggle_loot (e.g. Alt+G, InputMap) toggles LOOT_ALWAYS_VISIBLE
	var show_temp := Input.is_action_pressed("show_loot") or Input.is_key_pressed(KEY_G)
	var show_visible := LOOT_ALWAYS_VISIBLE or show_temp
	if not show_visible:
		return

	var font := DROP_FONT
	if font == null:
		return

	var font_size: int = LABEL_FONT_SIZE
	var line_height := font.get_height(font_size)

	var lines: Array[String] = []
	if _item_text != "":
		lines.append(_item_text)
	if _gold_text != "":
		lines.append(_gold_text)
	if lines.is_empty():
		return

	var max_width: float = 0.0
	for t in lines:
		# Godot 4: get_string_size(text, alignment, width, font_size)
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		if w > max_width:
			max_width = w

	var padding: Vector2 = Vector2(6.0, 4.0)
	var base_box_size: Vector2 = Vector2(max_width, line_height * lines.size()) + padding * 2.0
	# Apply hover zoom (7.5% larger)
	var box_size: Vector2 = base_box_size * _hover_scale
	var box_pos := Vector2(-box_size.x * 1 + _label_offset_x, -box_size.y - 8.0 + _label_offset_y)

	# Background in rarity color, but darker and slightly transparent
	var bg_color := Color(0, 0, 0, 0.8)  # Fallback: black
	var border_color := Color(1, 1, 1)  # Fallback: white
	if _item_text != "":
		var rarity_color := _get_color_for_rarity(_rarity)
		border_color = rarity_color
		# Background in rarity color, but darker (0.15) and slightly transparent (Alpha 0.4)
		bg_color = Color(rarity_color.r * 0.15, rarity_color.g * 0.15, rarity_color.b * 0.15, 0.4)
	elif _gold_text != "":
		border_color = Color(1.0, 0.84, 0.0)  # Gold color for gold drops
		bg_color = Color(1.0 * 0.15, 0.84 * 0.15, 0.0 * 0.15, 0.4)  # Dark gold
	
	# Hover effect: slightly brighter
	var bg_alpha := bg_color.a
	var border_alpha := 0.8
	if _is_hovered:
		bg_alpha = min(bg_color.a + 0.1, 0.6)
		border_alpha = 1.0
	
	var hover_font_size: int = int(round(font_size * _hover_scale))
	# Background box with rarity color
	draw_rect(Rect2(box_pos, box_size), Color(bg_color.r, bg_color.g, bg_color.b, bg_alpha), true)
	# Border with rarity color
	draw_rect(Rect2(box_pos, box_size), Color(border_color.r, border_color.g, border_color.b, border_alpha), false, 1.0)

	# Text lines (left with same padding, making left/right symmetric)
	var y := box_pos.y + padding.y * _hover_scale + line_height * _hover_scale

	if _item_text != "":
		var item_color := _get_color_for_rarity(_rarity)
		var x_item := box_pos.x + padding.x * _hover_scale
		var baseline_item := y - font.get_descent(font_size) * _hover_scale
		draw_string(font, Vector2(x_item, baseline_item), _item_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, hover_font_size, item_color)
		y += line_height * _hover_scale

	if _gold_text != "":
		var gold_color := Color(1.0, 0.84, 0.0)
		var x_gold := box_pos.x + padding.x * _hover_scale
		var baseline_gold := y - font.get_descent(font_size) * _hover_scale
		draw_string(font, Vector2(x_gold, baseline_gold), _gold_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, hover_font_size, gold_color)


func _process(_delta: float) -> void:
	# Redraw every frame so input state (e.g. G held) is reflected
	queue_redraw()

	var mouse_pos := get_global_mouse_position()
	var mouse_local := to_local(mouse_pos)
	
	# Check whether the mouse is over the text area
	var show_temp := Input.is_action_pressed("show_loot") or Input.is_key_pressed(KEY_G)
	var show_visible := LOOT_ALWAYS_VISIBLE or show_temp
	var is_hovering_text := false
	
	if show_visible and (_item_text != "" or _gold_text != ""):
		var font := DROP_FONT
		if font != null:
			var font_size: int = LABEL_FONT_SIZE
			var line_height := font.get_height(font_size)
			var lines: Array[String] = []
			if _item_text != "":
				lines.append(_item_text)
			if _gold_text != "":
				lines.append(_gold_text)
			
			var max_width: float = 0.0
			for t in lines:
				var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
				if w > max_width:
					max_width = w
			
			var padding: Vector2 = Vector2(6.0, 4.0)
			var box_size: Vector2 = Vector2(max_width, line_height * lines.size()) + padding * 2.0
			var box_pos := Vector2(-box_size.x * 0.5 + _label_offset_x, -box_size.y - 8.0 + _label_offset_y)
			var text_rect := Rect2(box_pos, box_size)
			
			is_hovering_text = text_rect.has_point(mouse_local)
	
	# Update hover status
	if is_hovering_text and not _is_hovered:
		_start_hover_animation()
	elif not is_hovering_text and _is_hovered:
		_stop_hover_animation()
	
	# Show tooltip near the drop if close to the player
	if mouse_pos.distance_to(global_position) <= 32.0:
		var tooltip_text := _format_item_tooltip_inventory_style(item)
		if tooltip_text != "":
			var scene := get_tree().current_scene
			if scene:
				var hud := scene.get_node_or_null("HUD")
				if hud and hud.has_method("set_enemy_info"):
					hud.set_enemy_info(tooltip_text)


func _format_item_tooltip_inventory_style(item_data: Dictionary) -> String:
	if item_data.is_empty():
		return ""

	var base_text := "[b]%s[/b]\n" % item_data.get("name", item_data.get("id", "Unknown"))
	base_text += "%s: %s\n" % [tr("Level"), str(item_data.get("item_level", "?"))]
	base_text += "%s: %s\n" % [tr("Type"), item_data.get("item_type", "?")]

	# Item stats
	var stats: Dictionary = item_data.get("stats", {})
	if not stats.is_empty():
		base_text += "\n[b]%s[/b]\n" % tr("Stats:")
		for stat_name in stats.keys():
			var value = stats[stat_name]
			if value != 0:
				base_text += "%s: %s\n" % [stat_name.capitalize(), str(value)]

	# Requirements
	var requirements = item_data.get("requirements", {})
	if not requirements.is_empty():
		base_text += "\n[b]%s[/b]\n" % tr("Requirements:")
		for req_name in requirements.keys():
			var req_val = requirements[req_name]
			if req_val != 0:
				base_text += "%s: %s\n" % [req_name.capitalize(), str(req_val)]

	# Enchantments
	var enchantments = item_data.get("enchantments", [])
	if not enchantments.is_empty():
		base_text += "\n[b]%s[/b]\n" % tr("Enchantments:")
		for enchant in enchantments:
			if enchant is Dictionary:
				var enchant_name = enchant.get("name", "?")
				var enchant_value = enchant.get("value", 0)
				base_text += "%s: +%s\n" % [enchant_name, str(enchant_value)]

	return base_text


static func _reflow_all_labels() -> void:
	var font := DROP_FONT
	if font == null:
		return

	# Sort list of all active drops (stable order)
	var drops: Array = ALL_DROPS.duplicate()
	drops.sort_custom(func(a, b):
		var da := a as DroppedLoot
		var db := b as DroppedLoot
		if da.global_position.y == db.global_position.y:
			return da.global_position.x < db.global_position.x
		return da.global_position.y < db.global_position.y
	)

	var processed: Array = []

	for d in drops:
		if d == null:
			continue

		var drop := d as DroppedLoot

		# Determine text lines for this instance
		var text_item: String = drop._item_text
		var text_gold: String = drop._gold_text

		var lines: Array[String] = []
		if text_item != "":
			lines.append(text_item)
		if text_gold != "":
			lines.append(text_gold)
		if lines.is_empty():
			drop._label_offset_y = 0.0
			continue

		var max_width: float = 0.0
		for t in lines:
			# Godot 4: get_string_size(text, alignment, width, font_size)
			var w: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_FONT_SIZE).x
			if w > max_width:
				max_width = w

		var line_height: float = font.get_height(LABEL_FONT_SIZE)
		var padding := Vector2(6.0, 4.0)
		var box_size := Vector2(max_width, line_height * lines.size()) + padding * 2.0

		var base_box_pos := Vector2(-box_size.x * 0.5, -box_size.y - 8.0)
		var rect := Rect2(drop.global_position + base_box_pos, box_size)

		# While overlapping existing boxes, push label further up
		var found_overlap := true
		while found_overlap:
			found_overlap = false
			for r in processed:
				if rect.intersects(r):
					found_overlap = true
					rect.position.y = r.position.y - box_size.y - 4.0
					break

		# Store offset relative to base position
		drop._label_offset_y = rect.position.y - (drop.global_position.y + base_box_pos.y)
		processed.append(rect)
		# Update CollisionShape when offset has changed
		drop._update_collision_shape()


func _on_body_entered(body: Node) -> void:
	if not body:
		return
	# Simple detection: assume the player node is named "Player".
	if body.name != "Player":
		return

	# No auto-loot on contact: only click/double-click picks up.
	pass


func _get_color_for_rarity(rarity: String) -> Color:
	match rarity:
		"normal":
			return Color(1, 1, 1)       # white
		"magic":
			return Color(0.2, 0.4, 1)   # blue
		"epic":
			return Color(0.7, 0.2, 1)   # purple
		"legendary":
			return Color(1, 0.9, 0.2)   # yellow
		"unique":
			return Color(1, 0.84, 0.0)  # gold
		_:
			return Color(1, 1, 1)


func _get_color_hex_for_rarity(rarity: String) -> String:
	var c: Color = _get_color_for_rarity(rarity)
	return "#" + c.to_html(false)


func _update_collision_shape() -> void:
	# CollisionShape only for the text area, not for any dot/icon
	var shape_node := get_node_or_null("ClickCollision")
	if not shape_node or not (shape_node is CollisionShape2D):
		return
	
	var shape := shape_node as CollisionShape2D
	if not (shape.shape is RectangleShape2D):
		return
	
	var rect_shape := shape.shape as RectangleShape2D
	
	# Calculate text/icon area (similar to _draw/_on_input_event)
	var font := DROP_FONT
	var font_size: int = LABEL_FONT_SIZE
	var line_height: float = 14.0
	if font != null:
		line_height = font.get_height(font_size)
	var lines: Array[String] = []
	if _item_text != "":
		lines.append(_item_text)
	if _gold_text != "":
		lines.append(_gold_text)
	var has_item := item_stack != null and item_stack.item != null and item_stack.amount > 0
	var has_gold := gold > 0
	if lines.is_empty() and (has_item or has_gold):
		lines.append(" ")
	var max_width: float = 0.0
	if font != null:
		for t in lines:
			var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
			if w > max_width:
				max_width = w
	if max_width == 0.0 and (has_item or has_gold):
		max_width = 32.0
	if lines.is_empty():
		rect_shape.size = Vector2(0, 0)
		return
	var padding: Vector2 = Vector2(6.0, 4.0)
	var box_size: Vector2 = Vector2(max_width, line_height * lines.size()) + padding * 2.0
	rect_shape.size = box_size
	shape.position = Vector2(0, -box_size.y - 8.0 + _label_offset_y)


func _start_hover_animation() -> void:
	_is_hovered = true
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.parallel().tween_property(self, "_hover_scale", 1.05, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# Loot icon: larger and darker on hover
	if _loot_sprite and _loot_sprite.visible:
		_hover_tween.parallel().tween_property(_loot_sprite, "scale", Vector2(0.5, 0.5), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_hover_tween.parallel().tween_property(_loot_sprite, "modulate", Color(0.8, 0.8, 0.8, 1), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# Gold icon: larger and darker on hover
	if _gold_sprite and _gold_sprite.visible:
		_hover_tween.parallel().tween_property(_gold_sprite, "scale", Vector2(0.45, 0.45), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_hover_tween.parallel().tween_property(_gold_sprite, "modulate", Color(0.8, 0.8, 0.8, 1), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _stop_hover_animation() -> void:
	_is_hovered = false
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween()
	_hover_tween.parallel().tween_property(self, "_hover_scale", 1.0, 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# Loot icon: back to normal size and brightness
	if _loot_sprite and _loot_sprite.visible:
		_hover_tween.parallel().tween_property(_loot_sprite, "scale", Vector2(0.35, 0.35), 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_hover_tween.parallel().tween_property(_loot_sprite, "modulate", Color(1, 1, 1, 1), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# Gold icon: back to normal size and brightness
	if _gold_sprite and _gold_sprite.visible:
		_hover_tween.parallel().tween_property(_gold_sprite, "scale", Vector2(0.36, 0.36), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		_hover_tween.parallel().tween_property(_gold_sprite, "modulate", Color(1, 1, 1, 1), 0.25).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _set_circle_color(color: Color) -> void:
	_circle_color = color
	queue_redraw()


func _update_loot_icon() -> void:
	# Loot icon for items, gold icon for gold
	if _loot_sprite == null or _gold_sprite == null:
		return
	
	var has_item := item_stack != null and item_stack.item != null and item_stack.amount > 0
	if not has_item and item is Dictionary and not item.is_empty():
		has_item = true
	var has_gold := gold > 0
	
	# Loot icon for items
	if has_item:
		_loot_sprite.visible = true
		_gold_sprite.visible = false
		# Animation is controlled by _start_hover_animation/_stop_hover_animation
		if not _is_hovered:
			_loot_sprite.scale = Vector2(0.4, 0.4)
			_loot_sprite.modulate = Color(1, 1, 1, 1)
	elif has_gold:
		# Only gold, no item -> show gold icon
		_loot_sprite.visible = false
		_gold_sprite.visible = true
		# Animation is controlled by _start_hover_animation/_stop_hover_animation
		if not _is_hovered:
			_gold_sprite.scale = Vector2(0.36, 0.36)  # 10% smaller than loot icon
			_gold_sprite.modulate = Color(1, 1, 1, 1)
	else:
		# Nothing present -> hide both icons
		_loot_sprite.visible = false
		_gold_sprite.visible = false


func _pickup() -> void:
	if _picked_up:
		return
	
	# Check if loot is still in pickup range (may have changed during drag)
	if not is_in_pickup_range():
		print("📦 DroppedLoot: Loot too far away during pickup")
		_picked_up = false
		return
	
	if item_stack == null and item is Dictionary and not item.is_empty():
		item_stack = _stack_from_dict(item)
	# Gold-only can be picked up without ItemStack
	var allow_gold_only := (item_stack == null or item_stack.item == null) and gold > 0
	if item_stack == null and not allow_gold_only:
		print("📦 DroppedLoot: No ItemStack present, pickup aborted")
		return

	var temp_store := preload("res://core/temp_loot_store.gd")
	var pos_info: Variant = item.get("position", {})
	var loot_id := -1
	if pos_info is Dictionary and pos_info.has("loot"):
		loot_id = int(pos_info["loot"])
	var loot_dict: Dictionary = {}
	if loot_id > 0:
		# Use same path as drag: first move to drag, then take over
		var moved = temp_store.move_loot_to_drag(loot_id)
		if moved is Dictionary and not moved.is_empty():
			loot_dict = moved
			item_stack = _stack_from_dict(moved)
		else:
			loot_dict = _dict_from_stack(item_stack) if item_stack != null else {}
	else:
		loot_dict = _dict_from_stack(item_stack) if item_stack != null else {}
	# Persist to inventory via LootPersistence (orders fields and sets inventar_slot)
	var added := LootPersistence.add_loot_to_player_and_inventory(gold, loot_dict)
	var updated_inv_res: InventoryResource = LootPersistence.get_last_updated_inventory()
	print("📦 DroppedLoot: updated_inv_res is null: ", updated_inv_res == null)
	if updated_inv_res:
		print("📦 DroppedLoot: updated_inv_res has ", updated_inv_res.items.size(), " items")

	# How many items remain?
	var leftover_amt: int = int(loot_dict.get("amount", 0))
	var has_item_on_ground: bool = item_stack != null and item_stack.item != null

	# Case 1: Nothing could be added to inventory at all
	if not added or (has_item_on_ground and leftover_amt >= item_stack.amount):
		print("📦 DroppedLoot: Inventory full, item remains on ground")
		_picked_up = false
		# Re-add to temp loot so it doesn't get lost (if it was originally there)
		if loot_id > 0:
			temp_store.add_item(_dict_from_stack(item_stack))
		# Ensure no drag state remains active
		if DragState.active:
			var temp_store_drag := preload("res://core/temp_loot_store.gd")
			temp_store_drag.clear_drag()
			DragState.clear()
		return

	# Case 2: Partially picked up, remainder left -> update world loot
	if leftover_amt > 0 and has_item_on_ground:
		print("📦 DroppedLoot: Partially picked up, remainder on ground: ", leftover_amt)
		item_stack.amount = leftover_amt
		item = loot_dict
		gold = 0  # Gold was completely added
		_update_label()
		_picked_up = false
		temp_store.clear_drag()
		DragState.clear()
		# Update UI (HUD inventory) - use direct update if available
		var scene := get_tree().current_scene
		if scene:
			var hud := scene.get_node_or_null("HUD")
			print("📦 DroppedLoot: hud is null: ", hud == null)
			if hud and hud.has_node("Control/Modals/EquipmentSlots"):
				var eq := hud.get_node("Control/Modals/EquipmentSlots")
				print("📦 DroppedLoot: eq is null: ", eq == null)
				print("📦 DroppedLoot: eq.has_method('refresh_from_inventory_resource'): ", eq.has_method("refresh_from_inventory_resource") if eq else false)
				if eq and updated_inv_res and eq.has_method("refresh_from_inventory_resource"):
					# Direct update from the InventoryResource we just saved - no file loading needed!
					print("📦 DroppedLoot: Updating UI directly from InventoryResource")
					eq.refresh_from_inventory_resource(updated_inv_res)
				elif eq and eq.has_method("refresh_from_save"):
					# Fallback to file-based refresh
					print("📦 DroppedLoot: Updating UI from file (fallback)")
					eq.call_deferred("refresh_from_save")
				else:
					print("⚠️ DroppedLoot: No update method available!")
		return

	# Case 3: Everything was picked up -> remove drop
	_picked_up = true
	temp_store.clear_drag()
	DragState.clear()

	# Update UI immediately (HUD inventory) - use direct update if available
	var scene2 := get_tree().current_scene
	if scene2:
		var hud := scene2.get_node_or_null("HUD")
		print("📦 DroppedLoot: hud is null (complete pickup): ", hud == null)
		if hud and hud.has_node("Control/Modals/EquipmentSlots"):
			var eq := hud.get_node("Control/Modals/EquipmentSlots")
			print("📦 DroppedLoot: eq is null (complete pickup): ", eq == null)
			print("📦 DroppedLoot: eq.has_method('refresh_from_inventory_resource') (complete pickup): ", eq.has_method("refresh_from_inventory_resource") if eq else false)
			if eq and updated_inv_res and eq.has_method("refresh_from_inventory_resource"):
				# Direct update from the InventoryResource we just saved - no file loading needed!
				print("📦 DroppedLoot: Updating UI directly from InventoryResource (complete pickup)")
				eq.refresh_from_inventory_resource(updated_inv_res)
			elif eq and eq.has_method("refresh_from_save"):
				# Fallback to file-based refresh
				print("📦 DroppedLoot: Updating UI from file (fallback, complete pickup)")
				eq.call_deferred("refresh_from_save")
			else:
				print("⚠️ DroppedLoot: No update method available (complete pickup)!")

	queue_free()


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	# Shift + Left Click → immediate pickup (replaces former double-click behavior)
	if mb.shift_pressed:
		handle_world_click(true)
		return

	# Only activate drag via item name, not via yellow dot
	# Check if click was on text area
	var mouse_world_pos := get_global_mouse_position()
	var click_local_pos := to_local(mouse_world_pos)
	
	# Calculate text area (similar to _draw)
	var font := DROP_FONT
	if font == null:
		return
	
	var font_size: int = LABEL_FONT_SIZE
	var line_height := font.get_height(font_size)
	var lines: Array[String] = []
	if _item_text != "":
		lines.append(_item_text)
	if _gold_text != "":
		lines.append(_gold_text)
	
	var max_width: float = 0.0
	for t in lines:
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		if w > max_width:
			max_width = w
	var has_item := item_stack != null and item_stack.item != null and item_stack.amount > 0
	var has_gold := gold > 0
	if max_width == 0.0 and (has_item or has_gold):
		max_width = 32.0
	if lines.is_empty() and (has_item or has_gold):
		lines.append(" ")
	
	var padding: Vector2 = Vector2(6.0, 4.0)
	var box_size: Vector2 = Vector2(max_width, line_height * lines.size()) + padding * 2.0
	var box_pos := Vector2(-box_size.x * 0.5 + _label_offset_x, -box_size.y - 8.0 + _label_offset_y)
	var text_rect := Rect2(box_pos, box_size)
	
	# Check if click is within text area or on icons
	var hit_text := text_rect.has_point(click_local_pos)
	var hit_icon := false
	if _loot_sprite and _loot_sprite.visible and _loot_sprite.texture:
		var tex_size_item: Vector2 = _loot_sprite.texture.get_size() * _loot_sprite.scale
		var rect_item := Rect2(-tex_size_item * 0.5, tex_size_item)
		hit_icon = rect_item.has_point(click_local_pos)
	if _gold_sprite and _gold_sprite.visible and _gold_sprite.texture and not hit_icon:
		var tex_size: Vector2 = _gold_sprite.texture.get_size() * _gold_sprite.scale
		var gold_rect := Rect2(-tex_size * 0.5, tex_size)
		hit_icon = gold_rect.has_point(click_local_pos)
	if not hit_text and not hit_icon:
		return  # Click outside -> no drag/pickup
	
	print("📦 DroppedLoot: Mouse click on item name at ", global_position)
	handle_world_click()


## Called by HUD or its own input_event when this drop is clicked.
## immediate_pickup=true → pick up immediately (used for Shift+LeftClick)
func handle_world_click(immediate_pickup: bool = false) -> void:
	# Check if loot is in pickup range
	if not is_in_pickup_range():
		print("📦 DroppedLoot: Loot too far away (Distance: ", global_position.distance_to(_get_player().global_position), " > ", PICKUP_RADIUS, ")")
		return

	if item_stack == null and item is Dictionary and not item.is_empty():
		item_stack = _stack_from_dict(item)
	
	if immediate_pickup:
		print("📦 DroppedLoot: Shift+LeftClick -> immediate pickup")
		_cancel_hold_timer()
		# pickup writes to inventory; DO NOT start drag
		_pickup()
		return

	# Normal click: start timer for long-press drag
	_start_hold_drag_timer()


func _start_hold_drag_timer() -> void:
	_cancel_hold_timer()

	# No ItemStack -> no drag
	if item_stack == null and item is Dictionary and not item.is_empty():
		item_stack = _stack_from_dict(item)
	if item_stack == null or item_stack.item == null or item_stack.amount <= 0:
		return

	_hold_timer = get_tree().create_timer(HOLD_TO_DRAG_DELAY)
	if _hold_timer:
		_hold_timer.timeout.connect(_on_hold_drag_timeout)


func _cancel_hold_timer() -> void:
	if _hold_timer:
		if _hold_timer.timeout.is_connected(_on_hold_drag_timeout):
			_hold_timer.timeout.disconnect(_on_hold_drag_timeout)
		_hold_timer = null  # Timer is automatically freed by Tree


func _on_hold_drag_timeout() -> void:
	_hold_timer = null

	# If already picked up or mouse button no longer pressed, cancel
	if _picked_up:
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		return
	
	# Check if loot is still in pickup range
	if not is_in_pickup_range():
		print("📦 DroppedLoot: Loot too far away for drag")
		return

	print("📦 DroppedLoot: long press -> prepare drag")
	if item_stack == null:
		item_stack = _stack_from_dict(item)
	if item_stack == null:
		return
	# Move from temp loot storage into drag storage with position {"drag":1}
	var temp_loot_store := preload("res://core/temp_loot_store.gd")
	var pos_info: Variant = item.get("position", {})
	var loot_id := -1
	if pos_info is Dictionary and pos_info.has("loot"):
		loot_id = int(pos_info["loot"])
	if loot_id >= 0:
		var moved = temp_loot_store.move_loot_to_drag(loot_id)
		if moved is Dictionary and not moved.is_empty():
			item = moved
			item_stack = _stack_from_dict(moved)
		else:
			# Fallback: set drag position and persist
			temp_loot_store.save_drag_stack(item_stack)
	else:
		# Fallback: only save drag
		temp_loot_store.save_drag_stack(item_stack)

	# "Pick up" world loot for drag & drop:
	# - zentraler Drag über EquipmentSlots.begin_drag_from_stack (Godot-Style)
	# - sichtbare Instanz am Boden ausblenden
	var drag_data: Dictionary = {}
	var scene := get_tree().current_scene
	var eq: Node = null
	if scene:
		var hud := scene.get_node_or_null("HUD")
		if hud and hud.has_node("Control/Modals/EquipmentSlots"):
			eq = hud.get_node("Control/Modals/EquipmentSlots")

	if eq != null and eq.has_method("begin_drag_from_stack"):
		drag_data = eq.begin_drag_from_stack("world", "", item_stack, self)
	else:
		# Fallback: direkt DragState + Payload setzen, falls HUD/EquipmentSlots nicht vorhanden
		temp_loot_store.save_drag_stack(item_stack)
		DragState.start("world", "", item_stack, self)
		drag_data = {
			"item": _dict_from_stack(item_stack),
			"source_kind": "world",
			"source_id": "",
		}

	visible = false

	# Inform EquipmentSlots UI about the new world drag so that
	# matching equipment slots are visually highlighted.
	if eq != null:
		if eq.has_method("highlight_for_world_item"):
			eq.highlight_for_world_item(drag_data.get("item", {}))
