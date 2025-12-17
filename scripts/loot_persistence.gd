class_name LootPersistence
extends RefCounted

## Inventory persistence via Resource (.tres); JSON only for migration/debug (write-only).

const SAVE_KEY_LOOT_VISIBLE := "loot_always_visible"
const LOOT_SYSTEM_DISABLED := false
const ORDER_KEYS := [
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

const INV_TRES_NAME := "inventory.tres"

const ItemRegistryRes = preload("res://scripts/item_registry.gd")
const InventoryResourceRes = preload("res://resources/inventory_resource.gd")
const PlayerResourceRes = preload("res://resources/player_resource.gd")
static var _registry: ItemRegistryClass = null
static var _loot_always_visible: bool = false
static var _loot_visible_loaded: bool = false
static var _last_updated_inventory: InventoryResource = null

static func _debug_dump_inventory_dict_array(arr: Array, label: String) -> void:
	print("\n📦 [LootPersistence] ", label, " (", arr.size(), " Slots)")
	for i in range(arr.size()):
		var e: Variant = arr[i]
		if e is Dictionary and not (e as Dictionary).is_empty():
			var id := String(e.get("id", e.get("name", "")))
			var amt := int(e.get("amount", 0))
			print("  • Slot ", i, ": id=", id, " amount=", amt)
		else:
			print("  • Slot ", i, ": (empty)")

static func get_loot_always_visible() -> bool:
	# lazy-load from save path
	if not _loot_visible_loaded:
		_load_loot_visible()
	return _loot_always_visible

static func set_loot_always_visible(value: bool) -> void:
	_loot_always_visible = value
	_save_loot_visible(value)

static func _loot_visible_path_for_slot() -> String:
	var slot_index: int = int(Constants.current_slot_index)
	var save_slots: Array = Constants.SAVE_SLOTS
	if slot_index < 0 or slot_index >= save_slots.size():
		slot_index = 0
	var slot: String = String(save_slots[slot_index])
	var save_root: String = Constants.get_save_root()
	var save_path: String = save_root.path_join(slot)
	var vis_path: String = save_path.path_join("loot_visible.cfg")
	return vis_path

static func _load_loot_visible() -> void:
	var path := _loot_visible_path_for_slot()
	if FileAccess.file_exists(path):
		var f := FileAccess.open(path, FileAccess.READ)
		if f:
			var txt := f.get_as_text()
			f.close()
			_loot_always_visible = (txt.strip_edges() == "true")
	_loot_visible_loaded = true

static func _save_loot_visible(value: bool) -> void:
	var path := _loot_visible_path_for_slot()
	var dir := DirAccess.open("user://")
	if dir:
		# ensure directory exists
		var parts := path.replace("user://", "").split("/")
		var accum := "user://"
		for i in range(parts.size() - 1):
			if parts[i] == "":
				continue
			accum = accum.path_join(parts[i])
			dir.make_dir_recursive(accum)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string("true" if value else "false")
		f.close()

static func add_loot_to_player_and_inventory(gold: int, loot: Dictionary) -> bool:
	if LOOT_SYSTEM_DISABLED:
		return false

	# Current slot and save paths
	var slot_index: int = int(Constants.current_slot_index)
	var save_slots: Array = Constants.SAVE_SLOTS
	if slot_index < 0 or slot_index >= save_slots.size():
		slot_index = 0
	var slot: String = String(save_slots[slot_index])
	var save_root: String = Constants.get_save_root()
	var save_path: String = save_root.path_join(slot)
	var player_res_path: String = save_path.path_join("player.tres")
	var inventory_res_path: String = save_path.path_join(INV_TRES_NAME)

	# Ensure base save folder exists
	var dir := DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive("save/" + slot)

	# Load player resource and add gold
	var player_res: PlayerResource = null
	if ResourceLoader.exists(player_res_path):
		var loaded = ResourceLoader.load(player_res_path)
		if loaded is PlayerResource:
			player_res = loaded
	if player_res == null:
		player_res = PlayerResourceRes.new()
	# Add gold
	if gold > 0:
		player_res.gold = max(0, player_res.gold + gold)
	var pres_err := ResourceSaver.save(player_res, player_res_path)
	if pres_err != OK:
		print("⚠️ Could not save player.tres: ", player_res_path, " err=", pres_err)

	# Load inventory (Resource)
	var inventory_items: Array = []
	var inv_res: InventoryResource = _load_inventory_res(inventory_res_path)
	if inv_res:
		inventory_items = inv_res.to_dict_array()
		_debug_dump_inventory_dict_array(inventory_items, "Before pickup / loaded from inventory.tres")

	# Determine capacity (from PlayerResource, at least 12, never trim items)
	var capacity: int = max(player_res.backpack_slots, inventory_items.size(), 12)
	# Fill inventory up to capacity so index access is always safe
	while inventory_items.size() < capacity:
		inventory_items.append({})

	var item_added: bool = false

	if loot is Dictionary and not loot.is_empty():
		# Normalized copy for internal calculations;
		# keep the passed-in dictionary to return remaining amount.
		var norm_loot: Dictionary = _normalize_stack_fields(loot)
		if norm_loot.is_empty():
			return false

		var remaining_amt: int = int(norm_loot.get("amount", 1))
		var max_stack_val: int = int(norm_loot.get("max_stack", 1))
		var can_stack: bool = bool(norm_loot.get("stackable", false))
		var key: String = _stack_key(norm_loot)

		# 1) Merge into existing stacks (stackable items with a matching key)
		if can_stack and key != "":
			for i in range(min(capacity, inventory_items.size())):
				if remaining_amt <= 0:
					break
				var entry = inventory_items[i]
				if entry is Dictionary and not (entry as Dictionary).is_empty():
					var norm_entry := _normalize_stack_fields(entry)
					if bool(norm_entry.get("stackable", false)) and _stack_key(norm_entry) == key:
						var cur_amt: int = int(norm_entry.get("amount", 1))
						var entry_max: int = int(norm_entry.get("max_stack", max_stack_val))
						var space: int = entry_max - cur_amt
						if space > 0:
							var add_amt: int = min(space, remaining_amt)
							cur_amt += add_amt
							remaining_amt -= add_amt
							norm_entry["amount"] = cur_amt
							inventory_items[i] = _order_item(norm_entry)
							item_added = true

		# 2) Place remaining amount into free slots (split into multiple stacks if needed)
		if remaining_amt > 0:
			for i in range(capacity):
				if remaining_amt <= 0:
					break
				var entry = inventory_items[i]
				if not (entry is Dictionary) or (entry as Dictionary).is_empty():
					var to_place: int = (min(max_stack_val, remaining_amt) if can_stack else 1)
					var loot_copy := norm_loot.duplicate(true)
					loot_copy["amount"] = to_place
					loot_copy["position"] = {"inventar_slot": i + 1}
					loot_copy = _order_item(loot_copy)
					inventory_items[i] = loot_copy
					remaining_amt -= to_place
					item_added = true

		# 3) Write remaining amount back into the passed-in dictionary (for world loot).
		#    0 means everything was picked up.
		loot["amount"] = remaining_amt
		if remaining_amt > 0 and not item_added:
			print("⚠️ Inventory full, loot not added: ", norm_loot.get("name", norm_loot.get("id", "Item")))

	# Save inventory as Resource - WITHOUT merge_stacks(), to keep positions intact
	var inv_res_out: InventoryResource = InventoryResource.new()
	inv_res_out.from_dict_array(inventory_items, _get_registry())
	_debug_dump_inventory_dict_array(inventory_items, "After pickup / before saving to inventory.tres")
	_save_inventory_res(inventory_res_path, inv_res_out)

	if loot is Dictionary and loot.is_empty():
		item_added = true

	# Store the updated InventoryResource so UI can update directly without reloading
	_last_updated_inventory = inv_res_out
	print("📦 LootPersistence: Stored updated InventoryResource with ", inv_res_out.items.size(), " items")

	return item_added

static func _order_item(item: Dictionary) -> Dictionary:
	if item == null or not (item is Dictionary) or item.is_empty():
		return {}
	var copy = _normalize_stack_fields(item)
	var ordered: Dictionary = {}
	for k in ORDER_KEYS:
		if copy.has(k):
			ordered[k] = copy[k]
	for k in copy.keys():
		if not ordered.has(k):
			ordered[k] = copy[k]
	return ordered

static func _normalize_stack_fields(item: Dictionary) -> Dictionary:
	if item == null or not (item is Dictionary):
		return {}
	var copy = item.duplicate(true)
	var item_type := String(copy.get("item_type", "")).to_lower()
	if not copy.has("id") and copy.has("name"):
		copy["id"] = copy["name"]
	if not copy.has("name") and copy.has("id"):
		copy["name"] = copy["id"]
	copy["item_level"] = int(copy.get("item_level", copy.get("requiredLevel", 1)))
	copy["min_player_level"] = int(copy.get("min_player_level", copy.get("requiredLevel", 1)))
	if copy.get("item_level", 0) <= 0:
		copy["item_level"] = 1
	if copy.get("min_player_level", 0) <= 0:
		copy["min_player_level"] = 1
	var stackable: bool = bool(copy.get("stackable", false))
	if not copy.has("stackable"):
		if item_type in ["potion", "consumable", "quest", "quest_item"] or copy.has("effects"):
			stackable = true
		elif String(copy.get("name", "")).to_lower().contains("potion"):
			stackable = true
		elif item_type in ["weapon", "helm", "helmet", "chest", "gloves", "pants", "boots", "shield", "armor", "offhand"]:
			stackable = false
		else:
			stackable = false
	copy["stackable"] = stackable
	var max_stack_val: int = int(copy.get("max_stack", (20 if stackable else 1)))
	if not stackable:
		max_stack_val = 1
	elif String(copy.get("name", "")).to_lower().contains("potion"):
		max_stack_val = 20
	copy["max_stack"] = max_stack_val
	if item_type in ["potion", "consumable", "quest", "quest_item", "flask"]:
		# Consumables sollen keine Enchantments tragen
		copy["enchantments"] = []
	var amount_val: int = int(copy.get("amount", 1))
	if amount_val <= 0:
		amount_val = 1
	if not stackable:
		amount_val = 1
	copy["amount"] = amount_val
	return copy

static func _sanitize_item(item: Dictionary) -> Dictionary:
	var norm = _normalize_stack_fields(item)
	var id_ok := norm.has("id") and String(norm["id"]).strip_edges() != ""
	var name_ok := norm.has("name") and String(norm["name"]).strip_edges() != ""
	if not id_ok and not name_ok:
		return {}
	return norm

static func _stack_key(item: Dictionary) -> String:
	if item == null or not (item is Dictionary) or item.is_empty():
		return ""
	var base := String(item.get("id", item.get("name", ""))).strip_edges().to_lower()
	var type_name := String(item.get("item_type", "")).strip_edges().to_lower()
	if type_name in ["potion", "consumable", "quest", "quest_item"]:
		return "%s_%s" % [base, type_name]
	var ench_hash = item.get("enchantments", []).hash()
	var stats_hash = item.get("stats", {}).hash()
	return "%s_%s_%s" % [base, str(ench_hash), str(stats_hash)]

static func _get_registry() -> ItemRegistryClass:
	if _registry != null:
		return _registry
	# Try autoload first
	if Engine.has_singleton("ItemRegistry"):
		_registry = Engine.get_singleton("ItemRegistry")
	else:
		_registry = ItemRegistryRes.new()
	return _registry

static func _load_inventory_res(path: String) -> InventoryResource:
	if ResourceLoader.exists(path):
		var res = ResourceLoader.load(path)
		if res is InventoryResourceRes:
			return res
	return null

static func _save_inventory_res(path: String, inv: InventoryResource) -> void:
	var err = ResourceSaver.save(inv, path)
	if err != OK:
		print("⚠️ Could not save InventoryResource:", path, " err=", err)

static func get_last_updated_inventory() -> InventoryResource:
	# Returns the last InventoryResource that was saved
	# This allows UI to update directly without reloading from file
	return _last_updated_inventory

static func _get_inventory_capacity(player_data: Dictionary) -> int:
	# Fallback to backpack_slots or default 12
	return int(player_data.get("backpack_slots", 12))

static func _array_to_string_ordered(arr: Array) -> String:
	# Debug helper; uses JSON.stringify with tabs
	return JSON.stringify(arr, "\t")


## === Backpack slot updates (for quests/crafting/events) ===

## Sets the number of backpack slots for the current save slot directly on PlayerResource.
## Used e.g. by quests/crafting.
static func set_backpack_slots_for_current_slot(new_slots: int) -> void:
	if new_slots <= 0:
		return
	var slot_index: int = int(Constants.current_slot_index)
	var save_slots: Array = Constants.SAVE_SLOTS
	if slot_index < 0 or slot_index >= save_slots.size():
		slot_index = 0
	var slot: String = String(save_slots[slot_index])
	var save_root: String = Constants.get_save_root()
	var save_path: String = save_root.path_join(slot)
	var player_res_path: String = save_path.path_join("player.tres")

	# Load PlayerResource or create a new one
	var player_res: PlayerResource = null
	if ResourceLoader.exists(player_res_path):
		var loaded = ResourceLoader.load(player_res_path)
		if loaded is PlayerResource:
			player_res = loaded
	if player_res == null:
		player_res = PlayerResourceRes.new()

	# Keep minimum capacity 12 so UI/inventory is not too small
	var clamped_slots: int = max(12, new_slots)
	player_res.backpack_slots = clamped_slots

	var pres_err := ResourceSaver.save(player_res, player_res_path)
	if pres_err != OK:
		print("⚠️ Could not save player.tres while updating backpack slots: ", player_res_path, " err=", pres_err)


## Increase/decrease backpack slots relatively (e.g. +6 slots as a quest reward).
static func add_backpack_slots_for_current_slot(delta: int) -> void:
	if delta == 0:
		return
	var slot_index: int = int(Constants.current_slot_index)
	var save_slots: Array = Constants.SAVE_SLOTS
	if slot_index < 0 or slot_index >= save_slots.size():
		slot_index = 0
	var slot: String = String(save_slots[slot_index])
	var save_root: String = Constants.get_save_root()
	var save_path: String = save_root.path_join(slot)
	var player_res_path: String = save_path.path_join("player.tres")

	var player_res: PlayerResource = null
	if ResourceLoader.exists(player_res_path):
		var loaded = ResourceLoader.load(player_res_path)
		if loaded is PlayerResource:
			player_res = loaded
	if player_res == null:
		player_res = PlayerResourceRes.new()

	var current_slots: int = max(12, player_res.backpack_slots)
	var new_slots: int = max(12, current_slots + delta)
	player_res.backpack_slots = new_slots

	var pres_err := ResourceSaver.save(player_res, player_res_path)
	if pres_err != OK:
		print("⚠️ Could not save player.tres while changing backpack slots: ", player_res_path, " err=", pres_err)
