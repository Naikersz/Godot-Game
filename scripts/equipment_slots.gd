extends Control

## EquipmentSlots - inventory + equipment in HUD
## Temporarily disabled logic for rebuild; UI layout stays.

const INVENTORY_DISABLED := false

const SLOT_MAP: Dictionary = {
	"weapon": "weapon",
	"helmet": "helmet",
	"chest": "armor",
	"pants": "pants",
	"boot": "boots",
	"boots": "boots",
	"glove": "gloves",
	"gloves": "gloves",
	"shield": "off_hand",
	"off_hand": "off_hand",
	"backpack": "backpack",
	"cloak": "mantal",
	"mantal": "mantal",
	"amulet": "amulet",
	# Rings can go into ring1 and ring2; special handling in _item_fits_slot
	"ring": "ring",
	# Optionally: weapons with off_hand_allowed=true can go into off_hand
}

@onready var dim_background: ColorRect = $DimBackground
@onready var window_panel: Panel = $WindowPanel
@onready var title_label: Label = $WindowPanel/TitleBar/TitleLabel
@onready var equipment_grid: Node = $WindowPanel/EquipmentGrid
@onready var inventory_grid: GridContainer = $WindowPanel/InventoryGrid
@onready var tooltip_panel: Panel = $TooltipPanel
@onready var tooltip_label: RichTextLabel = $TooltipPanel/TooltipLabel
@onready var compare_tooltip_panel: Panel = $CompareTooltipPanel
@onready var compare_tooltip_label: RichTextLabel = $CompareTooltipPanel/CompareTooltipLabel

var slot_index: int = 0
var player_name: String = "Unknown"
var player_level: int = 1
var player_data: Dictionary = {}
var equipped_items: Dictionary = {}   # slot_name -> ItemStack or null
var inventory_items: Array = []       # Array[ItemStack or null]

# equipment_slots: slot_name -> Panel (slot node)
var equipment_slots: Dictionary = {}

# inventory_slots: index -> Panel (slot node)
var inventory_slots: Array = []

var slot_panel_script := preload("res://scripts/slot_panel.gd")
# DragState is a global class (class_name) and doesn't need to be preloaded

var _highlight_slot_name: String = ""
var _hovered_item: Dictionary = {}
var _drag_from_inventory: Dictionary = {}   # kept as fallback for inventory->world drops

# Sorting cooldown system
var _sort_cooldown_timer: float = 0.0
const SORT_COOLDOWN_TIME: float = 3.0
var _current_sort_mode: int = 0  # 0 = Level, 1 = Rarity+Level, 2 = Type+Rarity+Level
var _keep_drag_after_world_swap: bool = false  # true if world->equipment swap should keep old slot content in DragState

const INV_TRES_NAME := "inventory.tres"
const ItemStackRes := preload("res://resources/item_stack.gd")
const ItemRes := preload("res://resources/item.gd")
const ItemTypeRes := preload("res://resources/item_type.gd")
const ItemRegistryRes = preload("res://scripts/item_registry.gd")
var _registry: ItemRegistryClass = null
const MAX_BASE_SLOTS := 12

var _inventory_drag_was_dropped: bool = false

func _ready() -> void:
	# Use the currently selected save slot
	slot_index = int(Constants.current_slot_index)
	_init_ui()
	_init_slots()
	if INVENTORY_DISABLED:
		visible = false
		if tooltip_panel:
			tooltip_panel.visible = false
		if compare_tooltip_panel:
			compare_tooltip_panel.visible = false
		set_process(false)
		return
	_load_data()
	_update_all_slots()
	visible = false
	if tooltip_panel:
		tooltip_panel.visible = false
	if compare_tooltip_panel:
		compare_tooltip_panel.visible = false
	set_process(true)


func _init_ui() -> void:
	if title_label:
		title_label.text = tr("Character / Inventory")


func _init_slots() -> void:
	# Equipment: 12 slots already laid out in the scene.
	# Bind panel nodes to logical slots.
	# Logical slot names should match save fields (helmet, armor, gloves, etc.).
	var equip_paths = {
		"helmet": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer/Helmet",
		"armor": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer/Armor",
		"pants": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer/Pants",
		"boots": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer/Boots",
		"gloves": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer2/Gloves",
		"weapon": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer2/Weapon",
		"backpack": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer3/Backpack",
		"off_hand": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer3/Off-Hand",
		"mantal": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer4/Mantal",
		"amulet": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer4/Amulet",
		"ring1": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer4/Ring1",
		"ring2": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer4/Ring2",
	}

	for slot_name in equip_paths.keys():
		var path: String = equip_paths[slot_name]
		var node = get_node_or_null(path)
		if node and node is Panel:
			var panel: Panel = node
			panel.set_script(slot_panel_script)
			panel.slot_id = slot_name
			panel.slot_kind = "equipment"
			panel.manager = self
			panel.mouse_entered.connect(_on_slot_mouse_entered.bind("equipment", slot_name))
			panel.mouse_exited.connect(_on_slot_mouse_exited)
			equipment_slots[slot_name] = panel

	# Inventory: 12 panels inside the GridContainer
	inventory_slots.clear()
	var children = inventory_grid.get_children()
	for i in range(children.size()):
		if children[i] is Panel:
			var inv_panel: Panel = children[i]
			inv_panel.set_script(slot_panel_script)
			inv_panel.slot_id = str(i)
			inv_panel.slot_kind = "inventory"
			inv_panel.manager = self
			inv_panel.mouse_entered.connect(_on_slot_mouse_entered.bind("inventory", i))
			inv_panel.mouse_exited.connect(_on_slot_mouse_exited)
			inventory_slots.append(inv_panel)


func _load_data() -> void:
	var slot = Constants.SAVE_SLOTS[slot_index]
	var save_path = Constants.get_save_path(slot)
	var player_res_path = save_path.path_join("player.tres")
	var inventory_res_path = save_path.path_join(INV_TRES_NAME)

	# Load player exclusively from PlayerResource
	if ResourceLoader.exists(player_res_path):
		# Use CACHE_MODE_IGNORE to ensure we get the latest saved version
		var res = ResourceLoader.load(player_res_path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res is PlayerResource:
			player_data = {}  # optional: could mirror fields if needed
			player_name = res.player_name
			player_level = res.player_level
			equipped_items = res.equipped.duplicate(true)
			# Backpack slots
			if res.backpack_slots > 0:
				player_data["backpack_slots"] = res.backpack_slots
	else:
		# if resource is missing -> start empty
		equipped_items = {}

	# After loading: convert dictionaries into ItemStacks
	for slot_name in equipped_items.keys():
		var val = equipped_items[slot_name]
		if val is Dictionary:
			equipped_items[slot_name] = _stack_from_dict(val)
		elif val == null:
			equipped_items[slot_name] = null

	# Load inventory exclusively from InventoryResource
	var inv_res: InventoryResource = _load_inventory_res(inventory_res_path)
	if inv_res:
		inventory_items = inv_res.items.duplicate(true)
	else:
		inventory_items = []
	# Ensure at least 12 slots with null entries
	while inventory_items.size() < MAX_BASE_SLOTS:
		inventory_items.append(null)

	_debug_dump_inventory_stacks("HUD _load_data -> inventory_items aus inventory.tres")


func refresh_from_save() -> void:
	# Public method to reload inventory/equipment from save files
	# (e.g. when loot is added outside of this UI).
	# This updates the UI even when the window is hidden, so items appear
	# immediately when the inventory is opened after picking up loot.
	_load_data()
	_update_all_slots()
	# Force UI update by queueing redraws on all panels
	_queue_redraw_all_slots()

func refresh_from_inventory_resource(inv_res: InventoryResource) -> void:
	# Direct update from InventoryResource without loading from file
	# This is faster and more reliable when we already have the data
	if inv_res == null:
		print("⚠️ EquipmentSlots: refresh_from_inventory_resource called with null InventoryResource")
		return
	
	print("🔄 EquipmentSlots: refresh_from_inventory_resource called with ", inv_res.items.size(), " items")
	
	# Update inventory_items directly from the resource
	inventory_items = inv_res.items.duplicate(true)
	
	# Ensure at least 12 slots with null entries
	while inventory_items.size() < MAX_BASE_SLOTS:
		inventory_items.append(null)
	
	print("🔄 EquipmentSlots: inventory_items updated, now has ", inventory_items.size(), " items")
	
	# Update UI immediately
	_update_all_slots()
	_queue_redraw_all_slots()
	
	print("✓ EquipmentSlots: Refreshed from InventoryResource (", inventory_items.size(), " items)")


func _debug_dump_inventory_stacks(label: String) -> void:
	print("\n📦 [EquipmentSlots] ", label, " (", inventory_items.size(), " Slots)")
	for i in range(inventory_items.size()):
		var st: Variant = inventory_items[i]
		if st is ItemStack and st.item != null:
			var itm: Item = st.item
			var id := itm.id if itm.id.strip_edges() != "" else itm.name
			print("  • Slot ", i, ": id=", id, " amount=", st.amount)
		else:
			print("  • Slot ", i, ": (empty)")


func _save_data() -> void:
	print("\n💾 [EquipmentSlots] _save_data() called")
	var slot = Constants.SAVE_SLOTS[slot_index]
	var save_path = Constants.get_save_path(slot)
	var player_res_path = save_path.path_join("player.tres")
	var inventory_res_path = save_path.path_join(INV_TRES_NAME)

	# Ensure the save folder exists
	var dir = DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive("save/" + slot)
	else:
		print("❌ Error: could not open user:// directory for saving")
		return

	# Save player as Resource, JSON only for debug if used
	var player_res := PlayerResource.new()
	player_res.player_name = player_name
	player_res.player_level = player_level
	player_res.backpack_slots = _get_backpack_slots_from_equipped(equipped_items)
	player_res.equipped = equipped_items.duplicate(true)
	var res_err := ResourceSaver.save(player_res, player_res_path)
	if res_err != OK:
		print("❌ Error while saving player.tres: ", player_res_path, " err=", res_err)

	# Save inventory (Resource + optional debug JSON)
	var inv_res_out := InventoryResource.new()
	inv_res_out.items = _cleanup_stack_array(inventory_items)
	inv_res_out.merge_stacks()
	_debug_dump_inventory_stacks("HUD _save_data -> inventory_items vor merge+Speichern")
	_save_inventory_res(inventory_res_path, inv_res_out)


# Registry laden
func _get_registry() -> ItemRegistryClass:
	if _registry != null:
		return _registry
	if Engine.has_singleton("ItemRegistry"):
		_registry = Engine.get_singleton("ItemRegistry")
	else:
		_registry = ItemRegistryRes.new()
	return _registry

func _load_inventory_res(path: String) -> InventoryResource:
	if ResourceLoader.exists(path):
		# Use CACHE_MODE_IGNORE to ensure we get the latest saved version
		# This is important when items are picked up while inventory is open
		var res = ResourceLoader.load(path, "", ResourceLoader.CACHE_MODE_IGNORE)
		if res is InventoryResource:
			return res
	return null

func _save_inventory_res(path: String, inv: InventoryResource) -> void:
	var err := ResourceSaver.save(inv, path)
	if err != OK:
		print("⚠️ Could not save InventoryResource:", path, " err=", err)


# ==== Stack/Dict Helpers ====

func _stack_from_dict(item: Dictionary) -> ItemStack:
	if item == null or item.is_empty():
		return null
	var reg := _get_registry()
	if reg == null:
		return _stack_minimal(item)
	var id := String(item.get("id", ""))
	if id == "":
		id = String(item.get("name", ""))
	if id == "":
		return _stack_minimal(item)
	var itm = reg.get_item(id)
	if itm == null:
		itm = _item_minimal(item, id)
		if itm == null:
			return null
	# carry instance-level info
	var type_name := String(item.get("item_type", "")).to_lower()
	if item.has("item_level"):
		itm.item_level = int(item.get("item_level", 1))
	if item.has("requirements"):
		itm.requirements = item.get("requirements", {})
	if item.has("material"):
		itm.material = item.get("material", {})
	if item.has("enchantments") and not _is_consumable_type(type_name):
		itm.enchantments = item.get("enchantments", [])
	var st := ItemStackRes.new()
	st.item = itm
	st.amount = int(item.get("amount", 1))
	if st.amount < 1:
		st.amount = 1
	
	# Copy all metadata from Dictionary
	if item.has("item_level"):
		st.set_meta("item_level", int(item.get("item_level", 0)))
	if item.has("position"):
		st.set_meta("position", item.get("position"))
	if item.has("enchantments") and not _is_consumable_type(type_name):
		st.set_meta("enchantments", item.get("enchantments", []))
	if item.has("material") and not _is_consumable_type(type_name):
		st.set_meta("material", item.get("material", {}))
	if item.has("min_player_level"):
		st.set_meta("min_player_level", int(item.get("min_player_level", 1)))
	
	# Copy all other Dictionary keys as metadata (if present)
	for key in item.keys():
		if key in ["id", "name", "rarity", "item_type", "item_level", "description", 
				   "amount", "stackable", "max_stack", "stats", "requirements", 
				   "enchant_slots", "enchantments", "material", "min_player_level", "position"]:
			continue  # These are already handled or are item properties
		# Copy all other keys as metadata
		if not st.has_meta(key):
			st.set_meta(key, item[key])
	
	return st

func _item_minimal(dict: Dictionary, id: String) -> Item:
	var itm := ItemRes.new()
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
	var t := ItemTypeRes.new()
	t.tab_name = String(dict.get("item_type", ""))
	t.stackable = bool(dict.get("stackable", false))
	t.max_stack = int(dict.get("max_stack", (20 if t.stackable else 1)))
	itm.item_type = t
	return itm

func _stack_minimal(dict: Dictionary) -> ItemStack:
	var id := String(dict.get("id", dict.get("name", "")))
	if id == "":
		return null
	var st := ItemStackRes.new()
	st.item = _item_minimal(dict, id)
	st.amount = max(1, int(dict.get("amount", 1)))
	return st

func _dict_from_stack(st: Variant) -> Dictionary:
	if st is ItemStack and st.item:
		var itm = st.item
		var pos_meta = st.get_meta("position") if st.has_meta("position") else {}
		var item_level_meta = st.get_meta("item_level") if st.has_meta("item_level") else itm.item_level
		var type_name: String = itm.item_type.tab_name.to_lower() if itm.item_type else ""
		var ench_meta = [] if _is_consumable_type(type_name) else (itm.enchantments if itm.enchantments.size() > 0 else (st.get_meta("enchantments") if st.has_meta("enchantments") else []))
		var req_meta = itm.requirements if itm.has_method("get") else {}
		var material_meta = {} if _is_consumable_type(type_name) else (st.get_meta("material") if st.has_meta("material") else itm.material if itm.has_method("get") else {})
		var min_lvl_meta = st.get_meta("min_player_level") if st.has_meta("min_player_level") else 1
		
		# Check if it's a consumable (for stackable fallback)
		var is_consumable: bool = _is_consumable_type(type_name)
		var stackable_val: bool = itm.item_type.stackable if itm.item_type else is_consumable
		
		var result := {
			"id": itm.id,
			"name": itm.name,
			"rarity": itm.rarity,
			"item_type": itm.item_type.tab_name if itm.item_type else "",
			"item_level": item_level_meta,
			"description": itm.description,
			"material": material_meta,
			"min_player_level": min_lvl_meta,
			"amount": st.amount,
			"stackable": stackable_val,
			"max_stack": itm.item_type.max_stack if itm.item_type else (20 if is_consumable else 1),
			"stats": itm.stats,
			"requirements": req_meta,
			"enchant_slots": itm.enchant_slots,
			"enchantments": ench_meta,
			"position": pos_meta,
		}
		
		# Add all other metadata
		var all_meta_keys: Array = st.get_meta_list()
		for key in all_meta_keys:
			if key in ["item_level", "position", "enchantments", "material", "min_player_level"]:
				continue  # These were already handled
			result[key] = st.get_meta(key)
		
		return result
	return {}

func _cleanup_stack_array(arr: Array) -> Array:
	var cleaned: Array = []
	for entry in arr:
		if entry is ItemStack and entry.item != null and entry.amount > 0:
			cleaned.append(entry)
		else:
			cleaned.append(null)
	return cleaned

func _stacks_can_merge(a: ItemStack, b: ItemStack) -> bool:
	if a == null or b == null or a.item == null or b.item == null:
		return false
	if a.item != b.item:
		return false
	if a.item.item_type == null or not a.item.item_type.stackable:
		return false
	return true

func _max_stack_stack(st: ItemStack) -> int:
	if st == null or st.item == null or st.item.item_type == null:
		return 1
	return max(1, st.item.item_type.max_stack)

func _merge_stack_into_slot_stack(target_index: int, incoming: ItemStack) -> ItemStack:
	if incoming == null or incoming.item == null:
		return null
	if target_index < 0:
		return incoming
	while target_index >= inventory_items.size():
		inventory_items.append(null)
	var existing: ItemStack = null
	if inventory_items[target_index] is ItemStack:
		existing = inventory_items[target_index]
	if existing == null:
		inventory_items[target_index] = incoming
		return null
	if not _stacks_can_merge(existing, incoming):
		return incoming
	var max_s := _max_stack_stack(existing)
	var space: int = max_s - existing.amount
	if space <= 0:
		return incoming
	var add_amt: int = min(space, incoming.amount)
	existing.amount += add_amt
	incoming.amount -= add_amt
	if incoming.amount <= 0:
		return null
	return incoming


func _update_all_slots() -> void:
	_update_equipment_slots()
	_update_inventory_slots()

func _queue_redraw_all_slots() -> void:
	# Force all panels to redraw by queueing redraws
	# This ensures the UI updates immediately even when the window is already visible
	for slot_name in equipment_slots.keys():
		var panel: Panel = equipment_slots[slot_name]
		if panel:
			panel.queue_redraw()
	
	for panel in inventory_slots:
		if panel:
			panel.queue_redraw()


func _get_or_create_label(panel: Panel) -> Label:
	# Find IconLabel recursively; it may be a child of a TextureRect
	var label: Label = panel.find_child("IconLabel", true, false) as Label
	if label:
		return label

	# If no label exists at all (e.g. slot_panel.gd did not run), create it here.
	label = Label.new()
	label.name = "IconLabel"
	label.anchor_left = 0.0
	label.anchor_top = 0.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 0.0
	label.offset_top = 0.0
	label.offset_right = 0.0
	label.offset_bottom = 0.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.z_index = 10
	# Configure label appearance
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 22)
	panel.add_child(label)
	return label


func _highlight_for_item(item: Dictionary) -> void:
	_clear_highlight()
	if item.is_empty():
		return

	var slot_names: Array = _get_slot_names_for_item(item)
	if slot_names.is_empty():
		return

	_highlight_slot_name = slot_names[0] if slot_names.size() > 0 else ""

	# Highlight only compatible equipment slots (ring -> both ring slots, off_hand_allowed weapon -> weapon/off_hand)
	for slot_name_iter in equipment_slots.keys():
		var panel: Panel = equipment_slots[slot_name_iter]
		if slot_names.has(slot_name_iter):
			# Brighter golden tint for valid targets
			panel.modulate = Color(1.0, 0.9, 0.5, 1.0)
		else:
			# Reset others to normal (no dimming)
			panel.modulate = Color(1, 1, 1, 1)

	# 6b: When an equipment item is dragged, gray out inventory slots
	# if the item cannot be returned to inventory (e.g., equipment-only items)
	# Currently we allow all items in inventory, so no graying out needed.
	# If equipment-only items are introduced later, add logic here.


func _get_slot_names_for_item(item: Dictionary) -> Array:
	var t := String(item.get("item_type", "")).to_lower()
	# Rings: both slots allowed
	if t == "ring":
		return ["ring1", "ring2"]
	# 7a: allow off-hand weapons when off_hand_allowed == true
	if t == "weapon" and bool(item.get("off_hand_allowed", false)):
		return ["weapon", "off_hand"]
	# otherwise mapping according to SLOT_MAP
	var mapped = SLOT_MAP.get(t, "")
	if mapped == "":
		return []
	if mapped == "ring":
		return ["ring1", "ring2"]
	return [mapped]


func _item_fits_slot(item: Dictionary, slot_name: String) -> bool:
	var slot_names := _get_slot_names_for_item(item)
	return slot_names.has(slot_name)

func _item_fits_slot_stack(stack: ItemStack, slot_name: String) -> bool:
	if stack == null or stack.item == null:
		return false
	var dict := _dict_from_stack(stack)
	return _item_fits_slot(dict, slot_name)


func highlight_for_world_item(item: Dictionary) -> void:
	# Public wrapper method so HUD/DroppedLoot can use the same highlight logic
	# as normal inventory drag.
	_highlight_for_item(item)


func clear_world_highlight() -> void:
	_clear_highlight()


func _clear_highlight() -> void:
	if _highlight_slot_name == "":
		return
	# Redraw all equipment slots in normal colors
	_highlight_slot_name = ""
	_update_equipment_slots()


func _on_slot_mouse_entered(kind: String, id) -> void:
	var item: Dictionary = _get_item_from_slot(kind, str(id))
	if item.is_empty():
		_hovered_item = {}
		_hide_tooltip()
	else:
		_hovered_item = item
		_show_tooltip(item)


func _on_slot_mouse_exited() -> void:
	_hovered_item = {}
	_hide_tooltip()


func _update_equipment_slots() -> void:
	for slot_name in equipment_slots.keys():
		var panel: Panel = equipment_slots[slot_name]
		# If this equipment slot is the current drag source, render it as empty
		# even though the data is still stored. This mirrors world loot behavior
		# where the item becomes invisible while being dragged.
		var is_drag_source_slot: bool = DragState.active and DragState.source_kind == "equipment" and DragState.source_id == slot_name
		# Safely get item: some slots in save can be null
		var item: Dictionary = {} if is_drag_source_slot else _get_item_from_slot("equipment", slot_name)

		var has_item := item is Dictionary and not (item as Dictionary).is_empty()
		var label := _get_or_create_label(panel)
		# Simple visualization: small "icon" — first letter of name
		if has_item:
			var item_name: String = item.get("name", item.get("id", "Item"))
			# Don't use built-in tooltip_text to avoid
			# second (dark) Godot tooltip — everything is done through
			# our custom hover window.
			panel.tooltip_text = ""
			# Background in rarity color, but darker and slightly transparent
			var rarity: String = String(item.get("rarity", "normal"))
			var rarity_color: Color = _get_color_for_rarity(rarity)
			# Make color darker (0.15 = very dark) and slightly transparent (Alpha 0.4)
			var bg_color := Color(rarity_color.r * 0.15, rarity_color.g * 0.15, rarity_color.b * 0.15, 0.4)
			# Create StyleBox or use existing one
			var style_box: StyleBoxFlat = null
			if panel.has_theme_stylebox_override("panel"):
				style_box = panel.get_theme_stylebox("panel") as StyleBoxFlat
			if style_box == null:
				style_box = StyleBoxFlat.new()
			style_box.bg_color = bg_color
			panel.add_theme_stylebox_override("panel", style_box)
			panel.modulate = Color(1, 1, 1, 1)
			if label:
				label.text = item_name.substr(0, 1).to_upper()
				# Rarity color for the letter
				label.add_theme_color_override("font_color", rarity_color)
		else:
			# Empty slot: standard background
			var style_box: StyleBoxFlat = null
			if panel.has_theme_stylebox_override("panel"):
				style_box = panel.get_theme_stylebox("panel") as StyleBoxFlat
			if style_box == null:
				style_box = StyleBoxFlat.new()
			style_box.bg_color = Color(0.2, 0.2, 0.2, 0.5)
			panel.add_theme_stylebox_override("panel", style_box)
			panel.modulate = Color(1, 1, 1, 1)
			if label:
				label.text = ""
				label.add_theme_color_override("font_color", Color.WHITE)


func _update_inventory_slots() -> void:
	print("🔄 EquipmentSlots: _update_inventory_slots() called, inventory_slots.size()=", inventory_slots.size(), " inventory_items.size()=", inventory_items.size())
	for i in range(inventory_slots.size()):
		var panel: Panel = inventory_slots[i]
		if panel == null:
			continue
		var label: Label = _get_or_create_label(panel)
		# If this inventory slot is the current drag source, render it as empty
		# even though the data is still stored. This mirrors world loot behavior
		# where the item becomes invisible while being dragged.
		var is_drag_source_slot := DragState.active and DragState.source_kind == "inventory" and DragState.source_id == str(i)
		
		# Get item, but if it's a drag source, treat it as empty (like equipment slots)
		var item: Dictionary = {}
		if not is_drag_source_slot and i < inventory_items.size():
			item = _dict_from_stack(inventory_items[i])
		
		var has_item := item is Dictionary and not item.is_empty()
		
		if has_item:
			item = _order_item(item)
			var item_name: String = item.get("name", item.get("id", "Item"))
			var rarity: String = String(item.get("rarity", "normal"))
			var rarity_color: Color = _get_color_for_rarity(rarity)

			# Background in rarity color, but darker and slightly transparent
			var bg_color := Color(rarity_color.r * 0.2, rarity_color.g * 0.2, rarity_color.b * 0.2, 0.4)
			var style_box: StyleBoxFlat = null
			if panel.has_theme_stylebox_override("panel"):
				style_box = panel.get_theme_stylebox("panel") as StyleBoxFlat
			if style_box == null:
				style_box = StyleBoxFlat.new()
			style_box.bg_color = bg_color
			panel.add_theme_stylebox_override("panel", style_box)

			# No graying out anymore – always full color
			panel.modulate = Color(1, 1, 1, 1)

			if label:
				var amount: int = int(item.get("amount", 1))
				var stackable: bool = bool(item.get("stackable", false))
				# Also check if it's a consumable (if stackable is not set)
				var item_type_name: String = String(item.get("item_type", "")).to_lower()
				var is_consumable: bool = _is_consumable_type(item_type_name)
				if not stackable and is_consumable:
					stackable = true  # Consumables are always stackable
				
				if stackable and amount > 1:
					label.text = str(amount)
					label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
					label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
					label.add_theme_color_override("font_color", Color.WHITE)
					label.add_theme_font_size_override("font_size", 18)
				else:
					label.text = item_name.substr(0, 1).to_upper()
					label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
					label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
				label.add_theme_color_override("font_color", rarity_color)
				label.add_theme_font_size_override("font_size", 22)
				# Force label to update immediately
				label.queue_redraw()
		else:
			# Empty slot (including drag source slots) - standard background
			var style_box: StyleBoxFlat = null
			if panel.has_theme_stylebox_override("panel"):
				style_box = panel.get_theme_stylebox("panel") as StyleBoxFlat
			if style_box == null:
				style_box = StyleBoxFlat.new()
			style_box.bg_color = Color(0.2, 0.2, 0.2, 0.5)
			panel.add_theme_stylebox_override("panel", style_box)
			panel.modulate = Color(1, 1, 1, 1)
			if label:
				label.text = ""
				label.add_theme_color_override("font_color", Color.WHITE)
				label.queue_redraw()
		# Force panel to update immediately
		panel.queue_redraw()


func _process(delta: float) -> void:
	# Update cooldown timer
	if _sort_cooldown_timer > 0.0:
		_sort_cooldown_timer -= delta
		if _sort_cooldown_timer <= 0.0:
			_sort_cooldown_timer = 0.0
	
	if tooltip_panel and tooltip_panel.visible:
		var mouse_pos: Vector2 = get_global_mouse_position()
		var viewport_rect: Rect2 = get_viewport_rect()

		var main_size: Vector2 = tooltip_panel.size
		var compare_size: Vector2 = compare_tooltip_panel.size if compare_tooltip_panel and compare_tooltip_panel.visible else Vector2.ZERO

		# First position of main tooltip
		var tooltip_pos: Vector2 = mouse_pos + Vector2(16, 16)
		if tooltip_pos.x + main_size.x > viewport_rect.size.x:
			tooltip_pos.x = mouse_pos.x - main_size.x - 16
		if tooltip_pos.y + main_size.y > viewport_rect.size.y:
			tooltip_pos.y = mouse_pos.y - main_size.y - 16
		tooltip_panel.global_position = tooltip_pos

		# Then position of comparison: right or left of main
		if compare_tooltip_panel and compare_tooltip_panel.visible:
			var compare_pos: Vector2 = tooltip_pos + Vector2(main_size.x + 12.0, 0.0)
			# If doesn't fit on right — place on left
			if compare_pos.x + compare_size.x > viewport_rect.size.x:
				compare_pos.x = tooltip_pos.x - compare_size.x - 12.0
			# Vertically adjust so it doesn't overflow
			if compare_pos.y + compare_size.y > viewport_rect.size.y:
				compare_pos.y = max(0.0, viewport_rect.size.y - compare_size.y - 4.0)
			compare_tooltip_panel.global_position = compare_pos

	# If no active drag is present anymore, reset highlights
	if _highlight_slot_name != "" and (not DragState.active or DragState.get_item().is_empty()):
		_clear_highlight()


func _show_tooltip(item: Dictionary) -> void:
	if not tooltip_panel:
		return
	if item.is_empty():
		tooltip_panel.visible = false
		if compare_tooltip_panel:
			compare_tooltip_panel.visible = false
		return

	var text := _format_item_tooltip(item)
	tooltip_label.text = text
	# Adjust size to content: fixed width, dynamic height
	var content_h: float = tooltip_label.get_content_height()
	var padding: float = 12.0
	var width: float = max(260.0, tooltip_panel.size.x)
	tooltip_panel.size = Vector2(width, content_h + padding)
	tooltip_panel.visible = true

	_show_compare_tooltip(item)


func _hide_tooltip() -> void:
	if tooltip_panel:
		tooltip_panel.visible = false
	if compare_tooltip_panel:
		compare_tooltip_panel.visible = false


func _format_item_tooltip(item: Dictionary) -> String:
	if item.is_empty():
		return ""

	var item_name: String = item.get("name", item.get("id", tr("Unknown")))
	var item_level: int = int(item.get("item_level", 0))
	var min_level: int = int(item.get("min_player_level", 0))

	var enchantments: Array = item.get("enchantments", [])

	# Rarity color based on rarity string
	var rarity: String = String(item.get("rarity", "normal"))
	var rarity_color: Color = _get_color_for_rarity(rarity)

	var sb := "[b][color=%s]%s[/color][/b]\n" % [rarity_color.to_html(false), item_name]
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
	if not enchantments.is_empty():
		sb += "\n[b]%s[/b]\n" % tr("Enchantments:")
		for enchant in enchantments:
			if enchant is Dictionary:
				var en_name: String = String(enchant.get("name", "?"))
				var en_value = enchant.get("value", 0)
				# If name contains " %", move percent sign to number,
				# so it shows as "+3.0%" instead of "%: +3.0"
				var suffix := ""
				if en_name.ends_with(" %"):
					en_name = en_name.substr(0, en_name.length() - 2)
					suffix = "%"
				sb += "%s: +%s%s\n" % [en_name, str(en_value), suffix]

	return sb


func _show_compare_tooltip(new_item: Dictionary) -> void:
	if not compare_tooltip_panel:
		return

	# Determine slot to which item belongs
	var item_type: String = String(new_item.get("item_type", "")).to_lower()
	if item_type == "":
		compare_tooltip_panel.visible = false
		return
	var slot_name = SLOT_MAP.get(item_type, "")
	if slot_name == "" or not equipped_items.has(slot_name):
		compare_tooltip_panel.visible = false
		return

	var equipped_item: Dictionary = _get_item_from_slot("equipment", slot_name)
	if equipped_item.is_empty():
		compare_tooltip_panel.visible = false
		return

	var text := _format_compare_tooltip(new_item, equipped_item, slot_name)
	compare_tooltip_label.text = text

	var content_h: float = compare_tooltip_label.get_content_height()
	var padding: float = 12.0
	var width: float = max(260.0, compare_tooltip_panel.size.x)
	compare_tooltip_panel.size = Vector2(width, content_h + padding)
	compare_tooltip_panel.visible = true


func _format_compare_tooltip(new_item: Dictionary, old_item: Dictionary, slot_name: String) -> String:
	var new_stats: Dictionary = new_item.get("stats", {})
	var old_stats: Dictionary = old_item.get("stats", {})

	var _name_new: String = new_item.get("name", new_item.get("id", tr("New")))
	var name_old: String = old_item.get("name", old_item.get("id", tr("Current")))

	var sb := "[b]%s[/b]\n%s\n\n" % [tr("Equipped %s:") % slot_name.capitalize(), name_old]
	sb += "[b]%s[/b]\n" % tr("Change if equipped:")

	# Take union of keys from both stat sets
	var keys: Array = []
	for k in new_stats.keys():
		if not keys.has(k):
			keys.append(k)
	for k in old_stats.keys():
		if not keys.has(k):
			keys.append(k)

	for k in keys:
		var new_val: float = float(new_stats.get(k, 0))
		var old_val: float = float(old_stats.get(k, 0))
		if new_val == 0 and old_val == 0:
			continue
		var diff: float = new_val - old_val
		var line := "%s: %.2f (%s: %.2f" % [String(k).capitalize(), new_val, tr("current"), old_val]
		if abs(diff) > 0.0001:
			if diff > 0:
				line += ", [color=green]+%.2f[/color]" % diff
			else:
				line += ", [color=red]%.2f[/color]" % diff
		line += ")\n"
		sb += line

	return sb


func _get_color_for_rarity(rarity: String) -> Color:
	match rarity:
		"normal":
			return Color(1, 1, 1)       # White
		"magic":
			return Color(0.2, 0.4, 1)   # Blue
		"epic":
			return Color(0.7, 0.2, 1)   # Purple
		"legendary":
			return Color(1, 0.9, 0.2)   # Yellow
		"unique":
			return Color(1, 0.84, 0.0)  # Gold
		_:
			return Color(1, 1, 1)


## === Drag & Drop API for slot_panel.gd ===

func begin_drag_from_stack(source_kind: String, source_id: String, stack: ItemStack, source_node: Node) -> Dictionary:
	# Shared drag start for inventory / equipment / world
	if stack == null or stack.item == null or stack.amount <= 0:
		return {}

	var item := _dict_from_stack(stack)

	# Persist drag stack in TempStore
	var temp_loot_store := preload("res://core/temp_loot_store.gd")
	temp_loot_store.save_drag_stack(stack)

	# Initialize central DragState
	DragState.start(source_kind, source_id, stack, source_node)

	return {
		"item": item,
		"source_kind": source_kind,
		"source_id": source_id,
	}


func slot_get_drag_data(slot_node: Node) -> Variant:
	if INVENTORY_DISABLED:
		return null
	if not (slot_node is Panel):
		return null

	var kind: String = slot_node.slot_kind
	var id: String = slot_node.slot_id

	var stack := _get_stack_from_slot(kind, id)
	if stack == null or stack.item == null or stack.amount <= 0:
		return null

	var item := _dict_from_stack(stack)

	# Highlight matching equipment slot (if exists)
	_highlight_for_item(item)

	# Shared drag start
	var drag_data := begin_drag_from_stack(kind, id, stack, slot_node)
	if drag_data.is_empty():
		return null

	# Remove item from source slot immediately when drag starts
	# (it will be restored if drag is cancelled via restore_drag_to_origin)
	_clear_slot(kind, id)
	
	# Update UI immediately so the source slot appears empty while dragging
	_update_all_slots()

	# Simple preview (semi-transparent rectangle)
	var preview := ColorRect.new()
	preview.color = Color(1, 1, 1, 0.4)
	preview.custom_minimum_size = Vector2(48, 48)
	slot_node.set_drag_preview(preview)

	return drag_data


func slot_can_drop_data(slot_node: Node, data: Variant) -> bool:
	if INVENTORY_DISABLED:
		return false
	if not (slot_node is Panel):
		return false
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if not data.has("item"):
		return false

	var kind: String = slot_node.slot_kind
	if kind == "equipment":
		# For equipment slots, check item type
		var slot_name: String = slot_node.slot_id
		var item: Dictionary = data["item"]
		var source_kind: String = data.get("source_kind", "")
		var source_id: String = data.get("source_id", "")
		
		# Source item must fit in target slot
		if not _item_fits_slot(item, slot_name):
			return false
		
		# 7b: If equipment-to-equipment swap: also check bidirectionally
		if source_kind == "equipment" and source_id != slot_name:
			var existing_item: Dictionary = _get_item_from_slot("equipment", slot_name)
			if not existing_item.is_empty():
				# Existing item must also fit in source slot
				if not _item_fits_slot(existing_item, source_id):
					return false
		
		return true
	elif kind == "inventory":
		# Any item can be in inventory
		return true

	return false


func slot_drop_data(slot_node: Node, data: Variant) -> void:
	if INVENTORY_DISABLED:
		return
	var source_kind: String = ""
	var source_id: String = ""
	var drag_stack: ItemStack = null
	var item: Dictionary = {}
	
	# Check if drag comes from DragState (preferred - has direct ItemStack)
	if DragState.active and DragState.has_item():
		source_kind = DragState.source_kind
		source_id = DragState.source_id
		drag_stack = DragState.item_stack
		# Also keep Dictionary view for compatibility
		item = DragState.get_item()
		print("📦 slot_drop_data: DragState drag detected (kind: ", source_kind, ")")
	elif typeof(data) == TYPE_DICTIONARY and data.has("item"):
		# Fallback: Normal drag from inventory/equipment (via Godot drag system)
		source_kind = data.get("source_kind", "")
		source_id = data.get("source_id", "")
		item = data["item"]
		# Try to get stack from DragState if available
		if DragState.active and DragState.has_item():
			drag_stack = DragState.item_stack
		else:
			# Convert from Dictionary as fallback
			drag_stack = _stack_from_dict(item)
	else:
		print("📦 slot_drop_data: Invalid data")
		return

	var target_kind: String = slot_node.slot_kind
	var target_id: String = slot_node.slot_id

	# Save original world loot node before _drop_to_* changes DragState
	var world_loot_node: DroppedLoot = null
	if DragState.active and DragState.source_kind == "world" and DragState.source_node and DragState.source_node is DroppedLoot:
		world_loot_node = DragState.source_node

	if target_kind == "equipment":
		_drop_to_equipment_with_stack(target_id, source_kind, source_id, drag_stack, item)
	elif target_kind == "inventory":
		_drop_to_inventory_with_stack(int(target_id), source_kind, source_id, drag_stack, item)

	# Remember that a drag from inventory/equipment was successfully dropped on a slot
	if source_kind == "inventory" or source_kind == "equipment":
		_inventory_drag_was_dropped = true

	# Drop was successfully performed on a slot
	_drag_from_inventory = {}

	# Always remove world loot node, even on swap
	# Delete world loot node (always delete after successful drop)
	if world_loot_node:
		world_loot_node.queue_free()

	# Clear DragState after successful drop
	# (except for world swaps, where a new DragState was set for the old item)
	if not _keep_drag_after_world_swap:
		DragState.clear()
	_keep_drag_after_world_swap = false

	_clear_highlight()
	_save_data()
	_update_all_slots()


func slot_click_from_world(slot_node: Node) -> void:
	if INVENTORY_DISABLED:
		return
	# Called by slot_panel.gd on mouse click on inventory/equipment slot.
	# Here we handle any active drag (world/inventory/equipment) via click.
	if not DragState.active or not DragState.has_item():
		return

	if not (slot_node is Panel):
		print("📦 slot_click_from_world: slot_node is not a Panel")
		return

	var kind: String = slot_node.slot_kind
	var id: String = slot_node.slot_id
	var source_kind := DragState.source_kind
	var source_id := DragState.source_id
	var drag_stack := DragState.item_stack
	var item := DragState.get_item()

	# Save original world loot node before _drop_to_* changes DragState
	var world_loot_node: DroppedLoot = null
	if DragState.active and DragState.source_kind == "world" and DragState.source_node and DragState.source_node is DroppedLoot:
		world_loot_node = DragState.source_node

	if kind == "inventory":
		var index := int(id)
		_drop_to_inventory_with_stack(index, source_kind, source_id, drag_stack, item)

	elif kind == "equipment":
		_drop_to_equipment_with_stack(id, source_kind, source_id, drag_stack, item)

	else:
		print("📦 slot_click_from_world: Unknown slot type: ", kind)

	# Delete world loot node (always remove if from world)
	if world_loot_node:
		world_loot_node.queue_free()

	# Clear DragState, except when we explicitly want to keep a new DragState for a world swap (world->equipment with swap)
	if source_kind == "world" and _keep_drag_after_world_swap:
		# World swap: new DragState was already set (old item), reset flag for next iteration
		_keep_drag_after_world_swap = false
	else:
		DragState.clear()

	_save_data()
	_update_all_slots()
	_clear_highlight()


## Called by slot_panel.gd on NOTIFICATION_DRAG_END
## when a drag from an inventory slot was not validly placed anywhere.
## In this case, we drop the item as world loot near the player.
func world_drop_from_inventory() -> void:
	if INVENTORY_DISABLED:
		_drag_from_inventory = {}
		if DragState.active:
			DragState.clear()
		return

	# If an inventory/equipment drag was just successfully dropped on a slot,
	# the Godot drag has ended, but we do NOT want to automatically drop on the ground.
	# In this case just reset the flag and do nothing – DragState remains active
	# until the next click (will be cleared there if needed)
	if _inventory_drag_was_dropped:
		_inventory_drag_was_dropped = false
		return
	var source_kind: String
	var source_id: String
	var item: Dictionary

	# Prefer using central DragState
	if DragState.active and DragState.source_kind == "inventory" and not DragState.get_item().is_empty():
		source_kind = DragState.source_kind
		source_id = DragState.source_id
		item = DragState.get_item()
	elif DragState.active and DragState.source_kind == "equipment" and not DragState.get_item().is_empty():
		source_kind = DragState.source_kind
		source_id = DragState.source_id
		item = DragState.get_item()
	else:
		if _drag_from_inventory.is_empty():
			return

		source_kind = String(_drag_from_inventory.get("source_kind", ""))
		source_id = String(_drag_from_inventory.get("source_id", ""))
		item = _drag_from_inventory.get("item", {})

	# Inventory drags: drop on ground (5a)
	if source_kind == "inventory":
		if item.is_empty():
			_drag_from_inventory = {}
			if DragState.active:
				DragState.clear()
			return

		print("📦 world_drop_from_inventory: drop item from inventory slot ", source_id, " on ground")

		# Register item in TempLootStore so world loot behaves like normal drop
		var temp_store_add := preload("res://core/temp_loot_store.gd")
		var stored_item := item.duplicate(true)
		var new_loot_id := temp_store_add.add_item(stored_item)
		if new_loot_id > 0:
			item["position"] = {"loot": new_loot_id}

		# Clear slot in inventory
		_clear_slot(source_kind, source_id)
		_save_data()
		_update_all_slots()

		# Find player in current scene (9a: always current position)
		var scene := get_tree().current_scene
		if scene == null:
			_drag_from_inventory = {}
			if DragState.active:
				DragState.clear()
			return

		var player: Node2D = scene.get_node_or_null("Player")
		if player == null:
			player = scene.find_child("Player", true, false)
		if player == null:
			print("📦 world_drop_from_inventory: no player found, item not dropped")
			_drag_from_inventory = {}
			if DragState.active:
				DragState.clear()
			return

		# Create DroppedLoot in world – always at current player position
		var drop := DroppedLoot.new()
		var drop_pos := player.global_position + Vector2(0, 24)
		drop.setup_drop(drop_pos, 0, item)
		scene.add_child(drop)

		_drag_from_inventory = {}
		if DragState.active:
			DragState.clear()
		return

	# Only items from equipment can be dropped on ground
	if source_kind != "equipment" or item.is_empty():
		_drag_from_inventory = {}
		if DragState.active:
			DragState.clear()
		return

	print("📦 world_drop_from_inventory: drop item from equipment slot ", source_id, " on ground")

	# Clear slot in equipment
	_clear_slot(source_kind, source_id)
	_save_data()
	_update_all_slots()

	# Find player in current scene
	var scene2 := get_tree().current_scene
	if scene2 == null:
		_drag_from_inventory = {}
		if DragState.active:
			DragState.clear()
		return

	var player2: Node2D = scene2.get_node_or_null("Player")
	if player2 == null:
		player2 = scene2.find_child("Player", true, false)
	if player2 == null:
		print("📦 world_drop_from_inventory: no player found, item not dropped")
		_drag_from_inventory = {}
		if DragState.active:
			DragState.clear()
		return

	# Create DroppedLoot in world (yellow dot) – slightly below player position,
	# so it visually lies at "foot height".
	var drop2 := DroppedLoot.new()
	var drop_pos2 := player2.global_position + Vector2(0, 24)
	drop2.setup_drop(drop_pos2, 0, item)
	scene2.add_child(drop2)

	# Clean up drag state
	_drag_from_inventory = {}
	if DragState.active:
		DragState.clear()


## Determines the maximum inventory slot count (backpack_slots) from PlayerResource.
## Capacity is stored directly in PlayerResource and can be updated by quests etc.
## Base value is 12.
func _get_backpack_slots_from_equipped(_equipped: Dictionary) -> int:
	var default_capacity := 12
	
	# Try to read backpack_slots from player_data (set when loading)
	if player_data.has("backpack_slots"):
		var slots: int = int(player_data.get("backpack_slots", default_capacity))
		if slots > 0:
			return slots
	
	# Fallback: standard capacity
	return default_capacity

## === Helper methods ===

## Finds an item by its position (simplified by position system)
func _get_item_by_position(pos_param: String) -> Dictionary:
	if pos_param == "" or pos_param == "drag":
		return {}
	
	# Inventory items: position is slot index as string (e.g. "0", "1", "2")
	if pos_param.is_valid_int():
		var index := int(pos_param)
		if index >= 0 and index < inventory_items.size():
			var st = inventory_items[index]
			return _dict_from_stack(st)
		return {}
	
	# Equipment items: position is slot name (e.g. "boots", "helmet")
	if equipped_items.has(pos_param):
		var raw = equipped_items.get(pos_param, null)
		if raw is ItemStack:
			return _dict_from_stack(raw)
		return {}
	
	return {}


## Sets an item at a specific position (simplified by position system)
func _set_item_by_position(pos_param: String, item: Dictionary) -> void:
	if pos_param == "" or pos_param == "drag":
		return
	
	# Inventory items: position is slot index as string
	if pos_param.is_valid_int():
		var index := int(pos_param)
		if index >= 0:
			while index >= inventory_items.size():
				inventory_items.append(null)
			inventory_items[index] = _stack_from_dict(item)
		return
	
	# Equipment items: position is slot name
	if equipped_items.has(pos_param) or _is_valid_equipment_slot(pos_param):
		equipped_items[pos_param] = _stack_from_dict(item)
		return


## Clears a slot by position
func _clear_slot_by_position(pos_param: String) -> void:
	if pos_param == "" or pos_param == "drag":
		return
	
	# Inventory items
	if pos_param.is_valid_int():
		var index := int(pos_param)
		if index >= 0 and index < inventory_items.size():
			inventory_items[index] = null
		return
	
	# Equipment items
	if equipped_items.has(pos_param):
		equipped_items[pos_param] = null
		return


## Checks if a slot name is valid
func _is_valid_equipment_slot(slot_name: String) -> bool:
	return equipment_slots.has(slot_name)


## Slot Accessors (Stacks first, Dictionary views for UI)
func _get_stack_from_slot(kind: String, id: String) -> ItemStack:
	if kind == "equipment":
		if equipped_items.has(id):
			var it = equipped_items[id]
			if it is ItemStack:
				return it
		return null
	elif kind == "inventory":
		var idx := int(id)
		if idx >= 0 and idx < inventory_items.size():
			var it = inventory_items[idx]
			if it is ItemStack:
				return it
		return null
	return null

func _set_stack_to_slot(kind: String, id: String, stack: ItemStack) -> void:
	if kind == "equipment":
		equipped_items[id] = stack
	elif kind == "inventory":
		var idx := int(id)
		if idx >= 0:
			while idx >= inventory_items.size():
				inventory_items.append(null)
			inventory_items[idx] = stack

func _clear_slot(kind: String, id: String) -> void:
	_set_stack_to_slot(kind, id, null)

func _get_item_from_slot(kind: String, id: String) -> Dictionary:
	return _dict_from_stack(_get_stack_from_slot(kind, id))

func _set_item_to_slot(kind: String, id: String, item: Dictionary) -> void:
	_set_stack_to_slot(kind, id, _stack_from_dict(item))


# Restore a dragged item back to its origin (inventory/equipment/world) – used on ESC
func restore_drag_to_origin() -> void:
	if not DragState.active or DragState.get_item().is_empty():
		return

	var source_kind := DragState.source_kind
	var source_id := DragState.source_id
	var item_dict: Dictionary = DragState.get_item().duplicate(true)
	var stack := _stack_from_dict(item_dict)
	var origin_pos: Dictionary = {}
	var pos_any: Variant = item_dict.get("origin_position", {})
	if pos_any is Dictionary:
		origin_pos = pos_any

	var temp_store := preload("res://core/temp_loot_store.gd")

	if source_kind == "inventory":
		var slot_idx := -1
		if origin_pos.has("inventar_slot"):
			slot_idx = int(origin_pos.get("inventar_slot", -1)) - 1
		elif source_id != "":
			slot_idx = int(source_id)

		if slot_idx >= 0:
			if slot_idx >= inventory_items.size():
				inventory_items.resize(slot_idx + 1)
				for i in range(inventory_items.size()):
					if inventory_items[i] == null:
						inventory_items[i] = null
			inventory_items[slot_idx] = stack
			_save_data()
			_update_inventory_slots()
			temp_store.clear_drag()
			DragState.clear()
			return

	if source_kind == "equipment":
		var slot_name := source_id
		if slot_name != "":
			equipped_items[slot_name] = stack
			_save_data()
			_update_equipment_slots()
			_update_inventory_slots()
			temp_store.clear_drag()
			DragState.clear()
			return

	# Default/fallback: treat as world item and drop back to world
	var scene := get_tree().current_scene
	var player: Node2D = null
	if scene:
		player = scene.get_node_or_null("Player")
		if player == null:
			player = scene.find_child("Player", true, false)

	var drop_pos := Vector2.ZERO
	if player:
		drop_pos = player.global_position + Vector2(0, 24)

	var item_copy := item_dict.duplicate(true)
	var loot_id := temp_store.add_item(item_copy)
	if loot_id > 0:
		item_copy["position"] = {"loot": loot_id}
	else:
		item_copy["position"] = {"loot": 1}
	item_copy = _order_item(item_copy)

	if DragState.source_node and DragState.source_node is DroppedLoot:
		var dl: DroppedLoot = DragState.source_node
		dl.global_position = drop_pos
		dl.item = item_copy
		dl.gold = 0
		dl._update_label()
		dl.visible = true
	else:
		var scene2 := get_tree().current_scene
		if scene2:
			var drop := DroppedLoot.new()
			if drop_pos == Vector2.ZERO and player:
				drop_pos = player.global_position + Vector2(0, 24)
			drop.setup_drop(drop_pos, 0, item_copy)
			scene2.add_child(drop)

	temp_store.clear_drag()
	DragState.clear()


## Main drop handler that works with ItemStack directly
func _drop_to_equipment_with_stack(target_slot: String, source_kind: String, source_id: String, drag_stack: ItemStack, item_dict: Dictionary) -> void:
	# Prefer ItemStack from DragState, fallback to Dictionary conversion
	var incoming_stack: ItemStack = drag_stack
	if incoming_stack == null:
		incoming_stack = _stack_from_dict(item_dict)
	
	if incoming_stack == null or incoming_stack.item == null:
		print("📦 _drop_to_equipment_with_stack: Invalid stack")
		return
	
	# Check if item fits in slot
	var item_check: Dictionary = item_dict
	if item_check.is_empty() and incoming_stack != null:
		item_check = _dict_from_stack(incoming_stack)
	if not _item_fits_slot(item_check, target_slot):
		print("📦 _drop_to_equipment_with_stack: Item does not fit in slot ", target_slot)
		return

	var temp_store := preload("res://core/temp_loot_store.gd")

	# World -> Equipment
	if source_kind == "world":
		var prev_stack: ItemStack = null
		if equipped_items.has(target_slot) and equipped_items[target_slot] is ItemStack:
			prev_stack = equipped_items[target_slot]

		# Place new item in target slot
		equipped_items[target_slot] = incoming_stack

		if prev_stack != null:
			# Swap: old equipment goes into DragState instead of inventory/world
			var slot_node: Panel = null
			if equipment_slots.has(target_slot) and equipment_slots[target_slot] is Panel:
				slot_node = equipment_slots[target_slot]
			DragState.start("equipment", target_slot, prev_stack, slot_node)
			_keep_drag_after_world_swap = true
		else:
			# No old item → completely end drag
			DragState.clear()

		# Clean up world drag data in TempStore
		temp_store.clear_drag()
		_update_equipment_slots()
		return

	# Inventory -> Equipment
	if source_kind == "inventory":
		var source_index := int(source_id)
		if source_index < 0 or source_index >= inventory_items.size():
			return
		
		# Use actual stack from inventory slot (should match drag_stack, but use slot to be safe)
		var source_slot_stack: ItemStack = inventory_items[source_index] as ItemStack
		if source_slot_stack == null or source_slot_stack.item == null:
			# Fallback: use drag_stack if slot is empty (shouldn't happen)
			source_slot_stack = drag_stack
		if source_slot_stack == null or source_slot_stack.item == null:
			return
		
		var prev_stack2: ItemStack = null
		if equipped_items.has(target_slot) and equipped_items[target_slot] is ItemStack:
			prev_stack2 = equipped_items[target_slot]
		equipped_items[target_slot] = source_slot_stack
		inventory_items[source_index] = prev_stack2
		temp_store.clear_drag()
		_update_equipment_slots()
		_update_inventory_slots()
		return

	# Equipment -> Equipment
	if source_kind == "equipment":
		if source_id == target_slot:
			# Dropping on the same slot - restore the item (it was removed during drag start)
			equipped_items[target_slot] = incoming_stack
			temp_store.clear_drag()
			_update_equipment_slots()
			return
		
		# Use actual stack from equipment slot (should match drag_stack, but use slot to be safe)
		var source_slot_stack: ItemStack = null
		if equipped_items.has(source_id) and equipped_items[source_id] is ItemStack:
			source_slot_stack = equipped_items[source_id]
		if source_slot_stack == null or source_slot_stack.item == null:
			# Fallback: use drag_stack if slot is empty (shouldn't happen)
			source_slot_stack = drag_stack
		if source_slot_stack == null or source_slot_stack.item == null:
			return
		
		var target_stack: ItemStack = null
		if equipped_items.has(target_slot) and equipped_items[target_slot] is ItemStack:
			target_stack = equipped_items[target_slot]
		
		if not _item_fits_slot_stack(source_slot_stack, target_slot):
			return
		if target_stack != null and not _item_fits_slot_stack(target_stack, source_id):
			return
		equipped_items[target_slot] = source_slot_stack
		equipped_items[source_id] = target_stack
		temp_store.clear_drag()
		_update_equipment_slots()
		return


## Main drop handler that works with ItemStack directly
func _drop_to_inventory_with_stack(target_index: int, source_kind: String, source_id: String, drag_stack: ItemStack, item_dict: Dictionary) -> void:
	if target_index < 0:
		return

	# Ensure array is long enough
	while target_index >= inventory_items.size():
		inventory_items.append(null)
	
	# Prefer ItemStack from DragState, fallback to Dictionary conversion
	var incoming_stack: ItemStack = drag_stack
	if incoming_stack == null:
		incoming_stack = _stack_from_dict(item_dict)
	if incoming_stack == null or incoming_stack.item == null:
		print("📦 _drop_to_inventory_with_stack: Invalid stack")
		return
	
	var temp_store := preload("res://core/temp_loot_store.gd")
	var inv_service := preload("res://core/inventory_service.gd")

	if source_kind == "inventory":
		var source_index := int(source_id)
		if source_index < 0:
			return
		
		# Ensure source_index is within array bounds
		while source_index >= inventory_items.size():
			inventory_items.append(null)
		
		# Since we removed the item from the slot during drag start, the slot is now null
		# We must use drag_stack (which contains the dragged item) instead
		# First, place the drag_stack back into the source slot temporarily for move_inventory_to_inventory
		# (which expects the source slot to contain the item to move)
		var original_source_stack: ItemStack = inventory_items[source_index] as ItemStack
		inventory_items[source_index] = incoming_stack  # Temporarily place drag_stack back
		
		# Now use the move logic (this will handle move, swap, and merge correctly)
		inventory_items = inv_service.move_inventory_to_inventory(inventory_items, source_index, target_index)
		
		# Clean up drag stack in TempStore, DragState remains active until next click
		temp_store.clear_drag()
		_update_inventory_slots()
		return

	if source_kind == "equipment":
		# Source: current equipment stack (use actual stack from slot)
		var source_stack: ItemStack = null
		if equipped_items.has(source_id) and equipped_items[source_id] is ItemStack:
			source_stack = equipped_items[source_id]
		if source_stack == null:
			# Fallback: use drag_stack if slot is empty (shouldn't happen)
			source_stack = drag_stack
		if source_stack == null or source_stack.item == null:
			return

		# Target: current inventory stack (may be null)
		var prev_stack: ItemStack = null
		if target_index >= 0 and target_index < inventory_items.size() and inventory_items[target_index] is ItemStack:
			prev_stack = inventory_items[target_index]

		# First try stacking (3a/3b with stackable item)
		if _stacks_can_merge(prev_stack, source_stack):
			var leftover_e := _merge_stack_into_slot_stack(target_index, source_stack)
			# Complete merge -> clear equipment slot
			if leftover_e == null or leftover_e.amount <= 0:
				equipped_items[source_id] = null
			else:
				# Partial amount fits in inventory, remainder stays in equipment slot
				equipped_items[source_id] = leftover_e
			temp_store.clear_drag()
			_update_inventory_slots()
			_update_equipment_slots()
			return

		# No stacking possible -> real move/swap
		if prev_stack == null:
			# 3a: Equipment -> Inventory (empty slot)
			inventory_items[target_index] = source_stack
			equipped_items[source_id] = null
			temp_store.clear_drag()
			_update_inventory_slots()
			_update_equipment_slots()
			return

		# 3b: Equipment -> Inventory (occupied slot)
		# Only allow the swap if the previous inventory item fits into the equipment slot
		if _item_fits_slot_stack(prev_stack, source_id):
			inventory_items[target_index] = source_stack
			equipped_items[source_id] = prev_stack
			temp_store.clear_drag()
			_update_inventory_slots()
			_update_equipment_slots()
			return
		else:
			# ❌ Swap not possible -> don't change anything, cancel drag
			temp_store.clear_drag()
			_update_inventory_slots()
			_update_equipment_slots()
			return

	if source_kind == "world":
		var prev_stack_world: ItemStack = inventory_items[target_index] if target_index < inventory_items.size() else null

		# Case 1: slot is empty → just place and end drag
		if prev_stack_world == null:
			inventory_items[target_index] = incoming_stack
			temp_store.clear_drag()
			DragState.clear()
			_update_inventory_slots()
			return

		# Case 2: same stackable item type → try to merge
		if _stacks_can_merge(prev_stack_world, incoming_stack):
			var _leftover_w := _merge_stack_into_slot_stack(target_index, incoming_stack)
			# _leftover_w is the remaining amount from the incoming stack; merge helper already updated the slot
			temp_store.clear_drag()
			DragState.clear()
			_update_inventory_slots()
			return

		# Case 3: real swap – old inventory item goes into DragState
		inventory_items[target_index] = incoming_stack
		var slot_node: Panel = null
		if target_index >= 0 and target_index < inventory_slots.size() and inventory_slots[target_index] is Panel:
			slot_node = inventory_slots[target_index]
		DragState.start("inventory", str(target_index), prev_stack_world, slot_node)
		_keep_drag_after_world_swap = true
		temp_store.clear_drag()
		_update_inventory_slots()
		return

## Legacy wrapper for backward compatibility (converts Dictionary to stack)
func _drop_to_inventory(target_index: int, source_kind: String, source_id: String, item: Dictionary) -> void:
	var stack := _stack_from_dict(item)
	_drop_to_inventory_with_stack(target_index, source_kind, source_id, stack, item)

## Legacy wrapper for backward compatibility (converts Dictionary to stack)
func _drop_to_equipment(target_slot: String, source_kind: String, source_id: String, item: Dictionary) -> void:
	var stack := _stack_from_dict(item)
	_drop_to_equipment_with_stack(target_slot, source_kind, source_id, stack, item)


## Public method for HUD to open/close window
func toggle_visible() -> void:
	if INVENTORY_DISABLED:
		visible = not visible
		if dim_background:
			dim_background.visible = visible
		return
	visible = not visible
	if dim_background:
		dim_background.visible = visible
	if visible:
		# On each open, reload data and redraw slots,
		# so loot from save is always current.
		_load_data()
		_update_all_slots()


## === Inventory Sorting ===

## Called by slot_panel.gd on middle mouse button
func _handle_inventory_sort() -> void:
	# Before sorting, ensure we're up to date with save data
	# (e.g. after loot pickup via double click, which already changed inventory.tres).
	refresh_from_save()
	_merge_all_stacks()
	# Check if cooldown is still active (with small tolerance for floating point errors)
	var cooldown_active: bool = _sort_cooldown_timer > 0.01
	
	print("📦 Sorting requested - Cooldown: ", _sort_cooldown_timer, "s, Current mode: ", _current_sort_mode)
	
	if cooldown_active:
		# Within cooldown: switch to next sort function
		_current_sort_mode = (_current_sort_mode + 1) % 3
		print("  → Cooldown active - switching to mode ", _current_sort_mode + 1)
	else:
		# Cooldown expired: back to mode 0
		_current_sort_mode = 0
		print("  → Cooldown expired - starting at mode 1")
	
	# Reset/start cooldown (always 3 seconds)
	_sort_cooldown_timer = SORT_COOLDOWN_TIME
	
	# Perform sorting
	match _current_sort_mode:
		0:
			_sort_inventory_by_level()
		1:
			_sort_inventory_by_rarity_and_level()
		2:
			_sort_inventory_by_type_rarity_level()
	
	# Update positions and save
	_update_item_positions_after_sort()
	_save_data()
	_update_all_slots()
	
	print("  ✓ Inventory sorted (Mode ", _current_sort_mode + 1, "/3, new cooldown: ", _sort_cooldown_timer, "s)")

# Merges all stackable items and updates slots
func _merge_all_stacks() -> void:
	var merged: Array = []
	var key_map := {}
	for entry in inventory_items:
		var stack: ItemStack = null
		if entry is ItemStack and entry.item != null:
			stack = entry
		elif entry is Dictionary and not (entry as Dictionary).is_empty():
			stack = _stack_from_dict(entry)
		if stack != null and stack.item != null:
			if stack.item.item_type and stack.item.item_type.stackable:
				var key = _stack_key_from_stack(stack)
				if key == "":
					merged.append(stack)
					continue
				if not key_map.has(key):
					key_map[key] = []
				key_map[key].append(stack)
			else:
				merged.append(stack)
	# Combine stacks per key respecting max_stack
	for key in key_map.keys():
		var list: Array = key_map[key]
		var total_amt: int = 0
		var max_stack_val: int = 1
		var template: ItemStack = null
		for st in list:
			if template == null:
				template = st
			total_amt += st.amount
			max_stack_val = _max_stack_stack(st)
		while total_amt > 0 and template != null:
			var chunk_amt = min(max_stack_val, total_amt)
			var chunk: ItemStack = ItemStackRes.new()
			var type_name: String = template.item.item_type.tab_name.to_lower() if template.item and template.item.item_type else ""
			chunk.amount = chunk_amt
			if _is_consumable_type(type_name):
				# For consumables, don't transfer enchants/material meta
				var clean_item: Item = template.item.duplicate(true)
				clean_item.enchantments = []
				chunk.item = clean_item
				# Copy base metadata (without enchants/material)
				if template.has_meta("item_level"):
					chunk.set_meta("item_level", template.get_meta("item_level"))
				if template.has_meta("min_player_level"):
					chunk.set_meta("min_player_level", template.get_meta("min_player_level"))
				# Copy all other metadata (except Enchants/Material/Position)
				var all_meta_keys: Array = template.get_meta_list()
				for meta_key in all_meta_keys:
					if meta_key in ["enchantments", "material", "position"]:
						continue  # Don't copy for consumables
					if not chunk.has_meta(meta_key):
						chunk.set_meta(meta_key, template.get_meta(meta_key))
			else:
				chunk.item = template.item
				_copy_instance_meta(template, chunk)
			total_amt -= chunk_amt
			merged.append(chunk)
	# Refill inventory with merged stacks first, then empties up to capacity
	var capacity = max(_get_backpack_slots_from_equipped(equipped_items), inventory_items.size(), MAX_BASE_SLOTS)
	var new_inv: Array = []
	for st in merged:
		if new_inv.size() >= capacity:
			break
		new_inv.append(st)
	while new_inv.size() < capacity:
		new_inv.append(null)
	inventory_items = new_inv
	_update_item_positions_after_sort()

func _stack_key(item: Dictionary) -> String:
	if item == null or not (item is Dictionary) or item.is_empty():
		return ""
	var base := String(item.get("id", item.get("name", ""))).strip_edges()
	var type_name: String = String(item.get("item_type", "")).to_lower()
	# For stackable consumables (potions etc.) ignore enchants/stats so they merge
	if _is_consumable_type(type_name):
		return "%s_%s" % [base, type_name]
	var ench_hash = item.get("enchantments", []).hash()
	var stats_hash = item.get("stats", {}).hash()
	return "%s_%s_%s" % [base, str(ench_hash), str(stats_hash)]

func _stack_key_from_stack(st: ItemStack) -> String:
	if st == null or st.item == null:
		return ""
	var base: String = st.item.id if st.item.id != "" else st.item.name
	var type_name: String = st.item.item_type.tab_name.to_lower() if st.item.item_type else ""
	# For stackable consumables (potions etc.) ignore enchants/material so they merge
	if _is_consumable_type(type_name):
		return "%s_%s" % [base, type_name]

	var ench: Array = st.get_meta("enchantments") if st.has_meta("enchantments") else st.item.enchantments
	var mat_dict: Dictionary = st.get_meta("material") if st.has_meta("material") else st.item.material
	var reqs: Dictionary = st.item.requirements
	var lvl: int = st.get_meta("item_level") if st.has_meta("item_level") else st.item.item_level
	var min_lvl: int = st.get_meta("min_player_level") if st.has_meta("min_player_level") else 1
	var stats_hash: int = st.item.stats.hash()
	var ench_hash: int = ench.hash()
	var mat_hash: int = mat_dict.hash()
	var req_hash: int = reqs.hash()
	return "%s_%s_%s_%s_%s_%s" % [String(base), str(ench_hash), str(stats_hash), str(mat_hash), str(req_hash), str(lvl) + "_" + str(min_lvl)]

# Meta copier to keep instance-specific fields when splitting/merging
# Copies ALL metadata from src to dst (except position, which is set separately)
func _copy_instance_meta(src: ItemStack, dst: ItemStack) -> void:
	if src == null or dst == null:
		return
	
	# Always copy base metadata
	if src.has_meta("item_level"):
		dst.set_meta("item_level", src.get_meta("item_level"))
	if src.has_meta("min_player_level"):
		dst.set_meta("min_player_level", src.get_meta("min_player_level"))
	
	# For non-consumables, transfer enchants/material
	var type_name := src.item.item_type.tab_name.to_lower() if src.item and src.item.item_type else ""
	if not _is_consumable_type(type_name):
		if src.has_meta("enchantments"):
			dst.set_meta("enchantments", src.get_meta("enchantments"))
		if src.has_meta("material"):
			dst.set_meta("material", src.get_meta("material"))
	
	# Copy all other metadata (except position, which is set separately)
	var all_meta_keys: Array = src.get_meta_list()
	for key in all_meta_keys:
		if key == "position":
			continue  # position is set separately
		if not dst.has_meta(key):
			dst.set_meta(key, src.get_meta(key))

func _is_consumable_type(type_name: String) -> bool:
	return type_name in ["potion", "consumable", "quest", "quest_item", "flask"]


## Sorting 1: By item_level descending, at same level alphabetically by item_type
func _sort_inventory_by_level() -> void:
	var items_with_index: Array = []
	
	# Collect all items with their index
	for i in range(inventory_items.size()):
		var entry = inventory_items[i]
		var st: ItemStack = null
		if entry is ItemStack and entry.item != null:
			st = entry
		elif entry is Dictionary and not (entry as Dictionary).is_empty():
			st = _stack_from_dict(entry)
		if st != null and st.item != null:
			var dict_view = _dict_from_stack(st)
			dict_view["__stack"] = st
			items_with_index.append(dict_view)
	
	# Sort: item_level descending, then item_type alphabetically ascending
	items_with_index.sort_custom(func(a, b):
		var item_a = a
		var item_b = b
		var level_a = int(item_a.get("item_level", 0))
		var level_b = int(item_b.get("item_level", 0))
		
		# First by level (descending)
		if level_a != level_b:
			return level_a > level_b
		
		# At same level: alphabetically by item_type (ascending)
		var type_a = String(item_a.get("item_type", "")).to_lower()
		var type_b = String(item_b.get("item_type", "")).to_lower()
		return type_a < type_b
	)
	
	# Rebuild inventory: sorted items first, then empty slots
	var sorted_items: Array = []
	for entry in items_with_index:
		var stack: ItemStack = entry.get("__stack")
		if stack != null and stack.item != null:
			sorted_items.append(stack)
	
	# Add empty slots at end
	var capacity = _get_backpack_slots_from_equipped(equipped_items)
	if capacity <= 0:
		capacity = inventory_items.size()
	
	while sorted_items.size() < capacity:
		sorted_items.append(null)
	
	# Replace inventory
	inventory_items = sorted_items


## Sorting 2: Grouped by Rarity (descending), then by item_level descending
func _sort_inventory_by_rarity_and_level() -> void:
	var items_with_index: Array = []
	
	# Collect all items with their index
	for i in range(inventory_items.size()):
		var entry = inventory_items[i]
		var st: ItemStack = null
		if entry is ItemStack and entry.item != null:
			st = entry
		elif entry is Dictionary and not (entry as Dictionary).is_empty():
			st = _stack_from_dict(entry)
		if st != null and st.item != null:
			var dict_view = _dict_from_stack(st)
			dict_view["__stack"] = st
			items_with_index.append(dict_view)
	
	# Rarity values for sorting (higher = better)
	var rarity_values = {
		"unique": 5,
		"legendary": 4,
		"epic": 3,
		"magic": 2,
		"normal": 1
	}
	
	# Sort: Rarity descending, then item_level descending
	items_with_index.sort_custom(func(a, b):
		var item_a = a
		var item_b = b
		var rarity_a = String(item_a.get("rarity", "normal")).to_lower()
		var rarity_b = String(item_b.get("rarity", "normal")).to_lower()
		var rarity_val_a = rarity_values.get(rarity_a, 0)
		var rarity_val_b = rarity_values.get(rarity_b, 0)
		
		# First by Rarity (descending)
		if rarity_val_a != rarity_val_b:
			return rarity_val_a > rarity_val_b
		
		# At same rarity: by item_level (descending)
		var level_a = int(item_a.get("item_level", 0))
		var level_b = int(item_b.get("item_level", 0))
		return level_a > level_b
	)
	
	# Rebuild inventory
	var sorted_items: Array = []
	for entry in items_with_index:
		var stack: ItemStack = entry.get("__stack")
		if stack != null and stack.item != null:
			sorted_items.append(stack)
	
	# Add empty slots at end
	var capacity = _get_backpack_slots_from_equipped(equipped_items)
	if capacity <= 0:
		capacity = inventory_items.size()
	
	while sorted_items.size() < capacity:
		sorted_items.append(null)
	
	# Replace inventory
	inventory_items = sorted_items


## Sorting 3: Grouped alphabetically by item_type, then Rarity and item_level
func _sort_inventory_by_type_rarity_level() -> void:
	var items_with_index: Array = []
	
	# Collect all items with their index
	for i in range(inventory_items.size()):
		var entry = inventory_items[i]
		var st: ItemStack = null
		if entry is ItemStack and entry.item != null:
			st = entry
		elif entry is Dictionary and not (entry as Dictionary).is_empty():
			st = _stack_from_dict(entry)
		if st != null and st.item != null:
			var dict_view = _dict_from_stack(st)
			dict_view["__stack"] = st
			items_with_index.append(dict_view)
	
	# Rarity values for sorting
	var rarity_values = {
		"unique": 5,
		"legendary": 4,
		"epic": 3,
		"magic": 2,
		"normal": 1
	}
	
	# Sort: item_type alphabetically, then Rarity descending, then item_level descending
	items_with_index.sort_custom(func(a, b):
		var item_a = a
		var item_b = b
		var type_a = String(item_a.get("item_type", "")).to_lower()
		var type_b = String(item_b.get("item_type", "")).to_lower()
		
		# First by item_type (alphabetically ascending)
		if type_a != type_b:
			return type_a < type_b
		
		# At same type: by Rarity (descending)
		var rarity_a = String(item_a.get("rarity", "normal")).to_lower()
		var rarity_b = String(item_b.get("rarity", "normal")).to_lower()
		var rarity_val_a = rarity_values.get(rarity_a, 0)
		var rarity_val_b = rarity_values.get(rarity_b, 0)
		
		if rarity_val_a != rarity_val_b:
			return rarity_val_a > rarity_val_b
		
		# At same rarity: by item_level (descending)
		var level_a = int(item_a.get("item_level", 0))
		var level_b = int(item_b.get("item_level", 0))
		return level_a > level_b
	)
	
	# Rebuild inventory
	var sorted_items: Array = []
	for entry in items_with_index:
		var stack: ItemStack = entry.get("__stack")
		if stack != null and stack.item != null:
			sorted_items.append(stack)
	
	# Add empty slots at end
	var capacity = _get_backpack_slots_from_equipped(equipped_items)
	if capacity <= 0:
		capacity = inventory_items.size()
	
	while sorted_items.size() < capacity:
		sorted_items.append(null)
	
	# Replace inventory
	inventory_items = sorted_items


## Updates positions of all items after sorting
func _update_item_positions_after_sort() -> void:
	for i in range(inventory_items.size()):
		var item = inventory_items[i]
		if item is ItemStack and item.item != null:
			item.set_meta("position", {"inventar_slot": i + 1})

func _order_item(item: Dictionary) -> Dictionary:
	var ordered: Dictionary = {}
	for k in _get_order_keys():
		if item.has(k):
			ordered[k] = item[k]
	for k in item.keys():
		if not ordered.has(k):
			ordered[k] = item[k]
	return ordered

func _get_order_keys() -> Array:
	return [
		"id",
		"item_level",
		"item_type",
		"material",
		"min_player_level",
		"name",
		"amount",
		"stackable",
		"max_stack",
		"position",
		"rarity",
		"requirements",
		"stats",
		"enchant_slots",
		"enchantments",
	]

# Ensure stack-related defaults are present and sane.
func _normalize_stack_fields(item: Dictionary) -> Dictionary:
	if item == null or not (item is Dictionary):
		return {}
	var copy = item.duplicate(true)
	var item_type := String(copy.get("item_type", "")).to_lower()

	var stackable: bool = bool(copy.get("stackable", false))
	var has_stackable := copy.has("stackable")
	if not has_stackable:
		if item_type in ["weapon", "helm", "helmet", "chest", "gloves", "pants", "boots", "shield", "armor", "offhand"]:
			stackable = false
		elif item_type in ["potion", "consumable", "quest", "quest_item"]:
			stackable = true
		else:
			stackable = false
	copy["stackable"] = stackable

	var max_stack_val: int = int(copy.get("max_stack", -1))
	if not stackable:
		max_stack_val = 1
	elif max_stack_val <= 0:
		# Default stack size for potions/quest items
		max_stack_val = 20
	copy["max_stack"] = max_stack_val

	var amount_val: int = int(copy.get("amount", 0))
	if amount_val <= 0:
		amount_val = 1
	if not stackable:
		amount_val = 1
	copy["amount"] = amount_val

	return _order_item(copy)

# Two items can stack if both are marked stackable and share the same id/name key.
func _items_can_stack(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	var a_norm = _normalize_stack_fields(a)
	var b_norm = _normalize_stack_fields(b)
	if not a_norm.get("stackable", false):
		return false
	if not b_norm.get("stackable", false):
		return false
	var key_a: String = str(a_norm.get("id", a_norm.get("name", "")))
	var key_b: String = str(b_norm.get("id", b_norm.get("name", "")))
	if key_a == "" or key_b == "":
		return false
	return key_a == key_b

# Try to merge a stackable item into the target inventory slot.
# Returns the remaining item (empty dict if fully merged).
func _merge_stack_into_slot(target_index: int, item: Dictionary) -> Dictionary:
	if item == null or not (item is Dictionary) or item.is_empty():
		return {}
	if target_index < 0:
		return item
	if target_index >= inventory_items.size():
		return item
	var existing: Dictionary = {}
	if inventory_items[target_index] is Dictionary:
		existing = inventory_items[target_index]
	existing = _normalize_stack_fields(existing)
	var incoming = _normalize_stack_fields(item)

	if existing.is_empty():
		return incoming
	if not _items_can_stack(existing, incoming):
		return incoming

	var max_stack_val: int = int(existing.get("max_stack", 1))
	var current_amt: int = int(existing.get("amount", 1))
	var incoming_amt: int = int(incoming.get("amount", 1))
	var space: int = max_stack_val - current_amt
	if space <= 0:
		return incoming

	var to_move: int = min(space, incoming_amt)
	existing["amount"] = current_amt + to_move
	incoming["amount"] = incoming_amt - to_move

	inventory_items[target_index] = _order_item(existing)

	if int(incoming.get("amount", 0)) <= 0:
		return {}
	return incoming
