extends CanvasLayer
# DragState and LootPersistence are global classes (class_name)
# If Godot has not registered the class yet, use a preload workaround
const LootPersistenceScript = preload("res://scripts/loot_persistence.gd")

## HUD Scene - universal UI for gameplay scenes
## Contains backpack button, EquipmentSlots and EnemyInfoPanel

@onready var inventory_button: Button = $Control/GameHUD/LeftContainer/HBoxContainer/InventoryButton
@onready var menu_button: Button = $Control/GameHUD/TopLeftContainer/MenuButton
@onready var enemy_info_panel: Panel = $Control/GameHUD/TopLeftContainer/EnemyInfoPanel
@onready var enemy_info_label: RichTextLabel = $Control/GameHUD/TopLeftContainer/EnemyInfoPanel/EnemyInfoLabel
@onready var equipment_slots: Control = $Control/Modals/EquipmentSlots
@onready var pause_menu: Control = $Control/Modals/PauseMenu
@onready var options_modal: Control = $Control/Modals/OptionsModal
@onready var dungeon_button: Button = $Control/GameHUD/DungeonButton
@onready var level_selection_modal: Control = $Control/Modals/LevelSelectionModal

var _last_enemy_info_time: float = -1.0
var drag_icon: ColorRect = null
var drag_info_panel: Panel = null
var drag_info_label: RichTextLabel = null

func _ready() -> void:
	# IMPORTANT: HUD should not block mouse clicks on the game world.
	# The root Control in the HUD is set to MOUSE_FILTER_IGNORE.
	# Individual buttons/panels can still handle mouse input.
	if has_node("Control"):
		var root_control := $Control
		if root_control is Control:
			root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Connect inventory button
	if inventory_button:
		inventory_button.pressed.connect(_on_inventory_button_pressed)
	
	# Connect menu button
	if menu_button:
		menu_button.pressed.connect(_on_menu_button_pressed)

	# Dungeon selection button
	if dungeon_button:
		dungeon_button.pressed.connect(_on_dungeon_button_pressed)
	
	# Enable input processing for hotkeys
	set_process_input(true)
	set_process(true)

	# Drag icon that follows the mouse while dragging world loot.
	# Visual: semi-transparent white 48x48 block, similar to inventory drag preview.
	drag_icon = ColorRect.new()
	drag_icon.color = Color(1, 1, 1, 0.4)
	drag_icon.size = Vector2(48, 48)
	drag_icon.pivot_offset = drag_icon.size * 0.5
	drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_icon.visible = false
	if has_node("Control"):
		$Control.add_child(drag_icon)
	else:
		add_child(drag_icon)
	
	# Hide EnemyInfoPanel initially
	if enemy_info_panel:
		enemy_info_panel.visible = false
	if enemy_info_label:
		enemy_info_label.text = ""

	# Load persisted state for loot visibility toggle
	var saved_visible: bool = LootPersistenceScript.get_loot_always_visible()
	DroppedLoot.LOOT_ALWAYS_VISIBLE = saved_visible
	for drop in DroppedLoot.ALL_DROPS:
		if drop:
			drop.queue_redraw()

	# Always clear drag state at start (no persistence across saves)
	var temp_store := preload("res://core/temp_loot_store.gd")
	temp_store.clear_drag()
	DragState.clear()

	# Create drag info panel in the bottom-left corner (temporary debug helper)
	drag_info_panel = Panel.new()
	drag_info_panel.name = "DragInfoPanel"
	drag_info_panel.anchor_left = 0.0
	drag_info_panel.anchor_top = 1.0
	drag_info_panel.anchor_right = 0.0
	drag_info_panel.anchor_bottom = 1.0
	drag_info_panel.offset_left = 16.0
	drag_info_panel.offset_top = -200.0
	drag_info_panel.offset_right = 300.0
	drag_info_panel.offset_bottom = -16.0
	drag_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_info_panel.visible = false
	# Dark background for better readability
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = Color(0, 0, 0, 0.85)
	style_box.border_color = Color(1, 1, 1, 0.5)
	style_box.border_width_left = 2
	style_box.border_width_top = 2
	style_box.border_width_right = 2
	style_box.border_width_bottom = 2
	drag_info_panel.add_theme_stylebox_override("panel", style_box)
	if has_node("Control"):
		$Control.add_child(drag_info_panel)
	else:
		add_child(drag_info_panel)

	drag_info_label = RichTextLabel.new()
	drag_info_label.name = "DragInfoLabel"
	drag_info_label.bbcode_enabled = true
	drag_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drag_info_label.anchor_left = 0.0
	drag_info_label.anchor_top = 0.0
	drag_info_label.anchor_right = 1.0
	drag_info_label.anchor_bottom = 1.0
	drag_info_label.offset_left = 8.0
	drag_info_label.offset_top = 8.0
	drag_info_label.offset_right = -8.0
	drag_info_label.offset_bottom = -8.0
	drag_info_panel.add_child(drag_info_label)

func _input(event: InputEvent) -> void:
	# ESC to open/close pause menu (only if menu is currently closed)
	if event.is_action_pressed("ui_cancel"):
		# If a drag is active, cancel it and restore item to origin
		if DragState.active and equipment_slots and equipment_slots.has_method("restore_drag_to_origin"):
			equipment_slots.restore_drag_to_origin()
			var viewport := get_viewport()
			if viewport:
				viewport.set_input_as_handled()
			return

		# If inventory is open, close it first (without opening pause menu)
		if equipment_slots and equipment_slots.visible:
			_close_inventory()
			var viewport := get_viewport()
			if viewport:
				viewport.set_input_as_handled()
			return

		if pause_menu and not pause_menu.visible:
			_open_pause_menu()
			var viewport := get_viewport()
			if viewport:
				viewport.set_input_as_handled()
		return
	
	# Hotkey I to toggle inventory
	if event.is_action_pressed("ui_inventory"):
		_open_inventory()
		var viewport := get_viewport()
		if viewport:
			viewport.set_input_as_handled()

	# Alt+G (toggle_loot) — toggle permanent loot visibility
	if event.is_action_pressed("toggle_loot"):
		DroppedLoot.LOOT_ALWAYS_VISIBLE = not DroppedLoot.LOOT_ALWAYS_VISIBLE
		LootPersistenceScript.set_loot_always_visible(DroppedLoot.LOOT_ALWAYS_VISIBLE)
		# Redraw all active drops
		for drop in DroppedLoot.ALL_DROPS:
			if drop:
				drop.queue_redraw()

	# Evaluate left mouse clicks globally:
	# - if NO world loot is currently "in hand": check for click on loot to pick up
	# - if a world loot is currently "in hand": use click to place/drop the item
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# If Shift is held, perform immediate pickup (no drag / long-press)
				if mb.shift_pressed:
					_handle_loot_click(true)
				elif DragState.active and not DragState.get_item().is_empty():
					_handle_world_item_click()
				else:
					_handle_loot_click(false)


func _handle_loot_click(immediate_pickup: bool = false) -> void:
	# Get mouse position on screen
	var viewport := get_viewport()
	if viewport == null:
		return

	var mouse_screen_pos: Vector2 = viewport.get_mouse_position()

	# Convert to world coordinates (via active Camera2D)
	var cam := viewport.get_camera_2d()
	# In 2D we can obtain the world position of the mouse directly from the camera.
	var world_pos: Vector2 = mouse_screen_pos
	if cam:
		world_pos = cam.get_global_mouse_position()

	# Find all drops whose text area was clicked (not just by distance)
	var candidate_drops: Array = []
	
	for d in DroppedLoot.ALL_DROPS:
		if d == null:
			continue
		var drop := d as DroppedLoot
		if drop.visible == false:
			continue
		
		# Check if click is on text area of this drop
		var mouse_local := drop.to_local(world_pos)
		var show_temp := Input.is_action_pressed("show_loot") or Input.is_key_pressed(KEY_G)
		var show_visible := DroppedLoot.LOOT_ALWAYS_VISIBLE or show_temp
		
		if not show_visible:
			continue
		
		# Compute text area for this drop
		var item_text := drop.get_item_text()
		var gold_text := drop.get_gold_text()
		
		if item_text == "" and gold_text == "":
			continue
		
		var font := drop.DROP_FONT
		if font == null:
			continue
		
		var font_size: int = drop.LABEL_FONT_SIZE
		var line_height := font.get_height(font_size)
		var lines: Array[String] = []
		if item_text != "":
			lines.append(item_text)
		if gold_text != "":
			lines.append(gold_text)
		
		var max_width: float = 0.0
		for t in lines:
			var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
			if w > max_width:
				max_width = w
		
		var padding: Vector2 = Vector2(6.0, 4.0)
		var box_size: Vector2 = Vector2(max_width, line_height * lines.size()) + padding * 2.0
		var label_offset_x := drop.get_label_offset_x()
		var label_offset_y := drop.get_label_offset_y()
		var box_pos := Vector2(-box_size.x * 0.5 + label_offset_x, -box_size.y - 8.0 + label_offset_y)
		var text_rect := Rect2(box_pos, box_size)
		
		# Check if loot is in pickup range
		if not drop.is_in_pickup_range():
			continue
		
		if text_rect.has_point(mouse_local):
			candidate_drops.append(drop)
	
	# If multiple drops were found, pick the top-most (highest z_index)
	if candidate_drops.is_empty():
		return
	
	var top_drop: DroppedLoot = null
	var highest_z: float = -999999.0
	
	for drop in candidate_drops:
		var z: float = float(drop.z_index)
		# If z_index is equal, use the last-added (higher index in ALL_DROPS)
		if z > highest_z or (z == highest_z and DroppedLoot.ALL_DROPS.find(drop) > DroppedLoot.ALL_DROPS.find(top_drop)):
			highest_z = z
			top_drop = drop
	
	if top_drop != null:
		print("📦 HUD: click on loot at ", top_drop.global_position, " (z_index=", top_drop.z_index, ")")
		top_drop.handle_world_click(immediate_pickup)
		# Prevent other nodes from processing the same click again
		viewport.set_input_as_handled()


func _handle_world_item_click() -> void:
	# Only relevant if we currently hold a world item in DragState
	if not DragState.active or DragState.get_item().is_empty():
		return

	var viewport := get_viewport()
	if viewport == null:
		return

	# Mouse position in screen / HUD space
	var mouse_pos: Vector2 = viewport.get_mouse_position()

	# Try to find an inventory or equipment slot in the EquipmentSlots manager
	if equipment_slots == null:
		print("📦 HUD: world item click – no equipment_slots in HUD")
		return

	var slots: Array = []

	# Inventory slots (array of Panels)
	if "inventory_slots" in equipment_slots:
		for slot_panel in equipment_slots.inventory_slots:
			slots.append(slot_panel)

	# Equipment slots (dictionary name -> Panel)
	if "equipment_slots" in equipment_slots:
		for slot_name in equipment_slots.equipment_slots.keys():
			var panel = equipment_slots.equipment_slots[slot_name]
			slots.append(panel)

	for slot_panel in slots:
		if not (slot_panel is Panel):
			continue
		var rect: Rect2 = slot_panel.get_global_rect()
		if rect.has_point(mouse_pos):
			if slot_panel.manager and slot_panel.manager.has_method("slot_click_from_world"):
				print("📦 HUD: world item click on Inventory/Equipment-Slot, calling manager.slot_click_from_world, id=", slot_panel.slot_id)
				slot_panel.manager.slot_click_from_world(slot_panel)
				# Check if the drop was accepted (EquipmentSlots clears DRAG_ITEM/DRAG_SOURCE on success)
				if DragState.active and not DragState.get_item().is_empty() and DragState.source_kind == "world" and DragState.source_node:
					print("📦 HUD: world item click – Slot did not accept, showing loot again")
					var dl: DroppedLoot = DragState.source_node
					if dl:
						dl.item = DragState.get_item().duplicate(true)
						dl.gold = 0
						dl._update_label()
						dl.visible = true
					DragState.clear()
			else:
				print("📦 HUD: Inventory-Slot without valid manager/slot_click_from_world")
			return

	# If the click lies within the inventory/equipment window (but not on a slot),
	# do not drop the item onto the map.
	# Check the WindowPanel only, not the whole EquipmentSlots control (which covers the whole screen).
	if equipment_slots is Control:
		var window_panel := equipment_slots.get_node_or_null("WindowPanel")
		if window_panel is Panel:
			var inv_rect := (window_panel as Panel).get_global_rect()
			if inv_rect.has_point(mouse_pos):
				return

	# No inventory slot under the mouse and outside of the inventory window:
	# click outside the slots -> show loot back on the ground
	print("📦 HUD: world item click – no inventory slot under mouse, returning loot to ground")

	var scene := get_tree().current_scene
	if scene:
		# Always use current player position for drop (even while moving)
		var player: Node2D = scene.get_node_or_null("Player")
		if player == null:
			player = scene.find_child("Player", true, false)
		
		if player:
			# If there's still a world source, update it to current player position
			if DragState.source_kind == "world" and DragState.source_node:
				var dl: DroppedLoot = DragState.source_node
				if dl:
					# Update position to current player position
					var drop_pos := player.global_position + Vector2(0, 24)
					dl.global_position = drop_pos
					dl.item = DragState.get_item().duplicate(true)
					dl.item = DragState.get_item().duplicate(true)
					# Set position back to coordinates (no longer "drag")
					var temp_store := preload("res://core/temp_loot_store.gd")
					if dl.item is Dictionary and not dl.item.is_empty():
						var item_copy := dl.item.duplicate(true)
						var loot_id := temp_store.add_item(item_copy)
						if loot_id > 0:
							item_copy["position"] = {"loot": loot_id}
						else:
							item_copy["position"] = {"loot": 1}
						dl.item = item_copy
					dl.gold = 0
					dl._update_label()
					dl.visible = true
					temp_store.clear_drag()
			# Otherwise create a new DroppedLoot at the current player position
			elif DragState.has_item():
				var drop := DroppedLoot.new()
				# Always use current player position (even while moving)
				var drop_pos := player.global_position + Vector2(0, 24)
				# Copy item and convert "drag" position back to coordinates
				var temp_store := preload("res://core/temp_loot_store.gd")
				var item_copy = DragState.get_item().duplicate(true)
				if item_copy is Dictionary and not item_copy.is_empty():
					var loot_id := temp_store.add_item(item_copy)
					if loot_id > 0:
						item_copy["position"] = {"loot": loot_id}
					else:
						item_copy["position"] = {"loot": 1}
				drop.setup_drop(drop_pos, 0, item_copy)
				scene.add_child(drop)
				temp_store.clear_drag()

	# Always clear drag state and remove any highlights
	if equipment_slots and equipment_slots.has_method("clear_world_highlight"):
		equipment_slots.clear_world_highlight()

	DragState.clear()

func _on_inventory_button_pressed() -> void:
	_open_inventory()

func _on_menu_button_pressed() -> void:
	_open_pause_menu()

func _open_inventory() -> void:
	"""Opens or closes the EquipmentSlots window in the HUD."""
	if equipment_slots:
		if equipment_slots.has_method("toggle_visible"):
			equipment_slots.toggle_visible()
		else:
			equipment_slots.visible = not equipment_slots.visible

func _close_inventory() -> void:
	if equipment_slots:
		if equipment_slots.has_method("toggle_visible"):
			if equipment_slots.visible:
				equipment_slots.toggle_visible()
		else:
			equipment_slots.visible = false

func _open_pause_menu() -> void:
	"""Opens or closes the pause menu."""
	if pause_menu:
		if pause_menu.has_method("toggle_visible"):
			pause_menu.toggle_visible()
		else:
			pause_menu.visible = not pause_menu.visible

func _open_options() -> void:
	"""Opens or closes the options modal."""
	if options_modal:
		if options_modal.has_method("toggle_modal"):
			options_modal.toggle_modal()
		elif options_modal.has_method("open_modal"):
			if options_modal.visible:
				options_modal.close_modal()
			else:
				options_modal.open_modal()
		else:
			options_modal.visible = not options_modal.visible


func _on_dungeon_button_pressed() -> void:
	if level_selection_modal:
		level_selection_modal.visible = true

func set_inventory_button_visible(visible_flag: bool) -> void:
	"""Shows or hides the inventory button."""
	if inventory_button:
		inventory_button.visible = visible_flag

func set_enemy_info(text: String) -> void:
	"""Sets the enemy info text."""
	if not enemy_info_label or not enemy_info_panel:
		return
	if text != "":
		enemy_info_label.text = text
		_resize_enemy_info_panel()
		enemy_info_panel.visible = true
		_last_enemy_info_time = Time.get_ticks_msec() / 1000.0

func _process(_delta: float) -> void:
	"""Automatically hides EnemyInfoPanel after 0.5s
	   and updates the position of the world loot drag icon."""
	if enemy_info_panel:
		if enemy_info_panel.visible and _last_enemy_info_time >= 0.0:
			var now := Time.get_ticks_msec() / 1000.0
			if now - _last_enemy_info_time > 0.5:
				enemy_info_panel.visible = false
				if enemy_info_label:
					enemy_info_label.text = ""

	# Drag icon follows the mouse while world loot is "in hand"
	if drag_icon:
		if DragState.active and not DragState.get_item().is_empty():
			drag_icon.visible = true
			var viewport := get_viewport()
			if viewport:
				drag_icon.global_position = viewport.get_mouse_position()
		else:
			drag_icon.visible = false

	# Update drag info panel in the bottom-left
	if drag_info_panel and drag_info_label:
		if DragState.active and not DragState.get_item().is_empty():
			var item_text := _format_drag_item_info(DragState.get_item())
			drag_info_label.text = item_text
			drag_info_panel.visible = true
			# Adjust size to content
			drag_info_label.force_update_transform()
			var content_h := drag_info_label.get_content_height()
			var padding := 16.0
			var width := 280.0
			var height := content_h + padding
			if height < 60.0:
				height = 60.0
			drag_info_panel.size = Vector2(width, height)
		else:
			drag_info_panel.visible = false

func _resize_enemy_info_panel() -> void:
	"""Adjusts EnemyInfoPanel size based on its content."""
	if not enemy_info_panel or not enemy_info_label:
		return
	
	# Height adapts to text; width is kept from scene (panel offsets)
	enemy_info_label.force_update_transform()
	var content_h: float = enemy_info_label.get_content_height()
	var padding: float = 16.0
	var height: float = content_h + padding
	if height < 40.0:
		height = 40.0
	
	var size: Vector2 = enemy_info_panel.size
	size.y = height
	enemy_info_panel.size = size


func _format_drag_item_info(item: Dictionary) -> String:
	"""Formats item info for the drag info panel (temporary debug)."""
	if item.is_empty():
		return ""

	var item_name: String = item.get("name", item.get("id", "Unknown"))
	var item_level: int = int(item.get("item_level", 0))
	var min_level: int = int(item.get("min_player_level", 0))
	var item_type: String = String(item.get("item_type", ""))
	var rarity: String = String(item.get("rarity", "normal"))

	# Rarity color
	var rarity_color: Color = Color.WHITE
	match rarity:
		"normal":
			rarity_color = Color.WHITE
		"magic":
			rarity_color = Color(0.2, 0.4, 1)
		"epic":
			rarity_color = Color(0.7, 0.2, 1)
		"legendary":
			rarity_color = Color(1, 0.9, 0.2)
		"unique":
			rarity_color = Color(1, 0.84, 0.0)

	var sb := "[b][color=%s]%s[/color][/b]\n" % [rarity_color.to_html(false), item_name]
	sb += "%s: %s\n" % [tr("Type"), item_type]
	sb += "%s: %d\n" % [tr("Item Level"), item_level]
	if min_level > 0:
		sb += "%s: %d\n" % [tr("Requires Level"), min_level]

	# Stats
	var stats: Dictionary = item.get("stats", {})
	if not stats.is_empty():
		sb += "\n[b]%s[/b]\n" % tr("Stats:")
		for stat_name in stats.keys():
			var value = stats[stat_name]
			if value != 0:
				sb += "%s: %s\n" % [String(stat_name).capitalize(), str(value)]

	# Enchantments
	var enchantments: Array = item.get("enchantments", [])
	if not enchantments.is_empty():
		sb += "\n[b]%s[/b]\n" % tr("Enchantments:")
		for enchant in enchantments:
			if enchant is Dictionary:
				var en_name: String = String(enchant.get("name", "?"))
				var en_value = enchant.get("value", 0)
				var suffix := ""
				if en_name.ends_with(" %"):
					en_name = en_name.substr(0, en_name.length() - 2)
					suffix = "%"
				sb += "%s: +%s%s\n" % [en_name, str(en_value), suffix]

	return sb
