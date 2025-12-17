class_name TempLootStore
extends RefCounted

const PATH_RES := "user://temp_loot.tres"
const DRAG_PATH_RES := "user://drag.tres"
const SimpleArrayResourceRes = preload("res://resources/array_resource.gd")
const SimpleDictResourceRes = preload("res://resources/dictionary_resource.gd")
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

static func clear() -> void:
	_save_array([])
	_clear_drag()

static func get_next_loot_id() -> int:
	var data := load_all()
	return data.size() + 1

static func add_item(item: Dictionary) -> int:
	if item.is_empty():
		return -1
	var data := load_all()
	var loot_id := _next_free_loot_id(data)
	var item_copy := _sanitize_item(item)
	if item_copy.is_empty():
		return -1
	item_copy["position"] = {"loot": loot_id}
	item_copy = _order_item(item_copy)
	data.append(item_copy)
	_save_array(data)
	return loot_id

static func move_loot_to_drag(loot_id: int) -> Dictionary:
	var data := load_all()
	var moved: Dictionary = {}
	var remaining: Array = []
	for entry in data:
		if not (entry is Dictionary):
			remaining.append(entry)
			continue
		var pos: Variant = entry.get("position", {})
		if pos is Dictionary and int(pos.get("loot", -1)) == loot_id and moved.is_empty():
			moved = _sanitize_item(entry)
			if moved.is_empty():
				continue
			moved["position"] = {"drag": 1}
			# Ensure enchant fields are at the end
			moved = _order_item(moved)
		else:
			remaining.append(entry)
	_save_array(remaining)
	if not moved.is_empty():
		_save_drag(moved)
	return moved

static func remove_loot(loot_id: int) -> void:
	var data := load_all()
	var remaining: Array = []
	for entry in data:
		if not (entry is Dictionary):
			remaining.append(entry)
			continue
		var pos: Variant = entry.get("position", {})
		if pos is Dictionary and int(pos.get("loot", -1)) == loot_id:
			# skip this entry (remove)
			continue
		remaining.append(entry)
	_save_array(remaining)

## Note: inventory_temp.tres was removed; TempLootStore now only manages loot and drag temp data.

static func _next_free_loot_id(data: Array) -> int:
	# Find the smallest positive integer not yet used as loot id.
	var used := {}
	for entry in data:
		if entry is Dictionary:
			var pos: Variant = entry.get("position", {})
			if pos is Dictionary and pos.has("loot"):
				var lid := int(pos.get("loot", -1))
				if lid > 0:
					used[lid] = true
	var candidate := 1
	while used.has(candidate):
		candidate += 1
	return candidate

static func load_drag() -> Dictionary:
	if ResourceLoader.exists(DRAG_PATH_RES):
		var res = ResourceLoader.load(DRAG_PATH_RES)
		if res is DictionaryResource or res is SimpleDictResourceRes:
			var data: Dictionary = res.data
			if data is Dictionary:
				return _order_item(data)
	return {}

static func save_drag(item: Dictionary) -> void:
	"""Public function to save an item to drag.json"""
	_save_drag(item)

static func save_drag_stack(stack) -> void:
	# Expects ItemStack; converts for debug/resource
	if stack == null:
		_clear_drag()
		return
	var dict := _stack_to_dict(stack)
	_save_drag(dict)

static func clear_drag() -> void:
	_clear_drag()

static func load_all() -> Array:
	return _load_array_res(PATH_RES)

static func _save_array(arr: Array) -> void:
	_save_array_res(PATH_RES, arr)

static func _load_array_res(path_res: String) -> Array:
	if ResourceLoader.exists(path_res):
		var res = ResourceLoader.load(path_res)
		if res is SimpleArrayResourceRes:
			var arr = (res as SimpleArrayResourceRes).data
			if arr is Array:
				var ordered: Array = []
				for entry in arr:
					if entry is Dictionary:
						ordered.append(_order_item(entry))
					else:
						ordered.append(entry)
				return ordered
	return []
static func _save_array_res(path_res: String, arr: Array) -> void:
	var res := SimpleArrayResourceRes.new()
	res.data = arr
	var err = ResourceSaver.save(res, path_res)
	if err != OK:
		print("⚠️ TempLootStore: Could not save resource: ", path_res, " err=", err)

static func _order_item(item: Dictionary) -> Dictionary:
	var copy = item.duplicate(true)
	var item_type := String(copy.get("item_type", "")).to_lower()
	# Fallback defaults to avoid "Unknown"/level 0 items
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
	var has_stackable := copy.has("stackable")
	if not has_stackable:
		if item_type in ["potion", "consumable", "quest", "quest_item"] or copy.has("effects"):
			stackable = true
		elif item_type in ["weapon", "helm", "helmet", "chest", "gloves", "pants", "boots", "shield", "armor", "offhand"]:
			stackable = false
		else:
			stackable = false
	copy["stackable"] = stackable
	var max_stack_val: int = int(copy.get("max_stack", (20 if stackable else 1)))
	if not stackable:
		max_stack_val = 1
	copy["max_stack"] = max_stack_val
	var amount_val: int = int(copy.get("amount", 1))
	if amount_val <= 0:
		amount_val = 1
	if not stackable:
		amount_val = 1
	copy["amount"] = amount_val

	var ordered: Dictionary = {}
	for k in ORDER_KEYS:
		if copy.has(k):
			ordered[k] = copy[k]
	for k in copy.keys():
		if not ordered.has(k):
			ordered[k] = copy[k]
	return ordered

static func _sanitize_item(item: Dictionary) -> Dictionary:
	var norm = _order_item(item)
	var id_ok := norm.has("id") and String(norm["id"]).strip_edges() != ""
	var name_ok := norm.has("name") and String(norm["name"]).strip_edges() != ""
	if not id_ok and not name_ok:
		return {}
	return norm

static func _save_drag(item: Dictionary) -> void:
	var res := SimpleDictResourceRes.new()
	res.data = item
	var err = ResourceSaver.save(res, DRAG_PATH_RES)
	if err != OK:
		print("⚠️ TempLootStore: Could not save drag resource: ", DRAG_PATH_RES, " err=", err)

static func _clear_drag() -> void:
	var res := SimpleDictResourceRes.new()
	res.data = {}
	var err = ResourceSaver.save(res, DRAG_PATH_RES)
	if err != OK:
		print("⚠️ TempLootStore: Could not save drag resource: ", DRAG_PATH_RES, " err=", err)

# Helper functions for ItemStack conversion (write-only)
static func _stack_to_dict(stack) -> Dictionary:
	if stack == null:
		return {}
	# If already Dictionary
	if stack is Dictionary:
		return _order_item(stack)
	# ItemStack expects fields item, amount
	if not (stack is ItemStack):
		return {}
	var itm = stack.item
	if itm == null:
		return {}
	var item_level_meta = stack.get_meta("item_level") if stack.has_meta("item_level") else (itm.item_level if itm.has_method("get") else 1)
	var ench_meta = stack.get_meta("enchantments") if stack.has_meta("enchantments") else (itm.enchantments if itm.has_method("get") else [])
	var pos_meta = stack.get_meta("position") if stack.has_meta("position") else {"drag": 1}
	var material_meta = stack.get_meta("material") if stack.has_meta("material") else (itm.material if itm.has_method("get") else {})
	var min_lvl_meta = stack.get_meta("min_player_level") if stack.has_meta("min_player_level") else 1
	var dict := {
		"id": itm.id,
		"name": itm.name,
		"rarity": itm.rarity,
		"item_type": itm.item_type.tab_name if itm.item_type else "",
		"item_level": item_level_meta,
		"description": itm.description,
		"material": material_meta,
		"min_player_level": min_lvl_meta,
		"amount": stack.amount,
		"stackable": itm.item_type.stackable if itm.item_type else false,
		"max_stack": itm.item_type.max_stack if itm.item_type else 1,
		"stats": itm.stats,
		"requirements": itm.requirements if itm.has_method("get") else {},
		"enchant_slots": itm.enchant_slots,
		"enchantments": ench_meta,
		"position": pos_meta,
	}
	
	# Add all other metadata
	var all_meta_keys: Array = stack.get_meta_list()
	for key in all_meta_keys:
		if key in ["item_level", "position", "enchantments", "material", "min_player_level"]:
			continue  # These were already handled
		dict[key] = stack.get_meta(key)
	
	return _order_item(dict)
