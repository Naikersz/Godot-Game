class_name LootPersistence
extends RefCounted

## Inventory persistence über Resource (.tres); JSON nur Migration/Debug (Write-only)

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

static func get_loot_always_visible() -> bool:
	# lazy-load aus Save-Pfad
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
	var dir = DirAccess.open("user://")
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

	# Slot und Pfade
	var slot_index: int = int(Constants.current_slot_index)
	var save_slots: Array = Constants.SAVE_SLOTS
	if slot_index < 0 or slot_index >= save_slots.size():
		slot_index = 0
	var slot: String = String(save_slots[slot_index])
	var save_root: String = Constants.get_save_root()
	var save_path: String = save_root.path_join(slot)
	var player_path: String = Constants.get_player_path(slot)
	var player_res_path: String = save_path.path_join("player.tres")
	var inventory_res_path: String = save_path.path_join(INV_TRES_NAME)

	# Ordner sicherstellen
	var dir = DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive("save/" + slot)

	# Player laden (Resource) + Gold addieren; optional Migration aus JSON
	var player_res: PlayerResource = null
	if ResourceLoader.exists(player_res_path):
		var loaded = ResourceLoader.load(player_res_path)
		if loaded is PlayerResource:
			player_res = loaded
	if player_res == null:
		player_res = PlayerResourceRes.new()
		# Migration aus alter JSON, falls vorhanden
		if FileAccess.file_exists(player_path):
			var p_file = FileAccess.open(player_path, FileAccess.READ)
			if p_file:
				var json_string = p_file.get_as_text()
				p_file.close()
				var json_obj: JSON = JSON.new()
				if json_obj.parse(json_string) == OK and json_obj.data is Dictionary:
					var pd: Dictionary = json_obj.data
					player_res.player_name = String(pd.get("name", ""))
					player_res.player_level = int(pd.get("level", 1))
					player_res.backpack_slots = int(pd.get("backpack_slots", 12))
					player_res.gold = int(pd.get("gold", 0))
					if pd.has("equipped") and pd["equipped"] is Dictionary:
						player_res.equipped = pd["equipped"]
	# Gold hinzufügen
	if gold > 0:
		player_res.gold = max(0, player_res.gold + gold)
	var pres_err := ResourceSaver.save(player_res, player_res_path)
	if pres_err != OK:
		print("⚠️ Konnte player.tres nicht speichern: ", player_res_path, " err=", pres_err)
	# Alte JSON optional entfernen, damit keine Doppelquelle mehr existiert
	if FileAccess.file_exists(player_path):
		DirAccess.remove_absolute(player_path)

	# Inventar laden (Resource)
	var inventory_items: Array = []
	var inv_res: InventoryResource = _load_inventory_res(inventory_res_path)
	if inv_res:
		inventory_items = inv_res.to_dict_array()

	# Kapazität bestimmen (aus PlayerResource, mindestens 12, niemals Items wegtrimmen)
	var capacity: int = max(player_res.backpack_slots, inventory_items.size(), 12)
	# Inventar auf Kapazität auffüllen, damit Index-Zugriff sicher ist
	while inventory_items.size() < capacity:
		inventory_items.append({})

	var item_added: bool = false

	if loot is Dictionary and not loot.is_empty():
		loot = _sanitize_item(loot)
		if loot.is_empty():
			return false
		var placed := false

		# Stacks mergen - für stackbare Items
		var remaining: Dictionary = _normalize_stack_fields(loot.duplicate(true))
		var key: String = _stack_key(remaining)
		if key != "" and bool(remaining.get("stackable", false)):
			var inc_amt: int = int(remaining.get("amount", 1))
			for i in range(min(capacity, inventory_items.size())):
				if inc_amt <= 0:
					break
				var entry = inventory_items[i]
				if entry is Dictionary and not (entry as Dictionary).is_empty():
					var norm = _normalize_stack_fields(entry)
					if bool(norm.get("stackable", false)) and _stack_key(norm) == key:
						var max_s: int = int(norm.get("max_stack", 1))
						var cur_amt: int = int(norm.get("amount", 1))
						var space: int = max_s - cur_amt
						if space > 0:
							var add_amt: int = min(space, inc_amt)
							cur_amt += add_amt
							inc_amt -= add_amt
							norm["amount"] = cur_amt
							inventory_items[i] = _order_item(norm)
							item_added = true
			remaining["amount"] = inc_amt
			loot = remaining
			# Wenn alles gemergt wurde, speichern und zurückkehren
			if int(loot.get("amount", 0)) <= 0:
				var inv_res_merge: InventoryResource = InventoryResource.new()
				inv_res_merge.from_dict_array(inventory_items, _get_registry())
				# KEIN merge_stacks() hier - würde Items neu anordnen und Positionen zerstören
				_save_inventory_res(inventory_res_path, inv_res_merge)
				return true

		# Restliches Item in ersten freien Slot platzieren
		for i in range(capacity):
			var entry = inventory_items[i]
			if not (entry is Dictionary) or (entry as Dictionary).is_empty():
				var loot_copy = loot.duplicate(true)
				if loot_copy is Dictionary and not loot_copy.is_empty():
					loot_copy["position"] = {"inventar_slot": i + 1}
					loot_copy = _order_item(loot_copy)
				inventory_items[i] = loot_copy
				placed = true
				break

		if not placed:
			print("⚠️ Inventory full, loot not added: ", loot.get("name", loot.get("id", "Item")))

		item_added = placed

	# Inventar speichern (Resource) - OHNE merge_stacks(), damit Positionen erhalten bleiben
	var inv_res_out: InventoryResource = InventoryResource.new()
	inv_res_out.from_dict_array(inventory_items, _get_registry())
	_save_inventory_res(inventory_res_path, inv_res_out)

	if loot is Dictionary and loot.is_empty():
		item_added = true

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
	var base := String(item.get("id", item.get("name", ""))).strip_edges()
	var type_name := String(item.get("item_type", "")).to_lower()
	if type_name in ["potion", "consumable", "quest", "quest_item"]:
		return "%s_%s" % [base, type_name]
	var ench_hash = item.get("enchantments", []).hash()
	var stats_hash = item.get("stats", {}).hash()
	return "%s_%s_%s" % [base, str(ench_hash), str(stats_hash)]

static func _get_registry() -> ItemRegistryClass:
	if _registry != null:
		return _registry
	# Versuche Autoload
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
		print("⚠️ Konnte InventoryResource nicht speichern:", path, " err=", err)

static func _migrate_inventory_json(old_path: String) -> Array:
	if not FileAccess.file_exists(old_path):
		return []
	var inv_file = FileAccess.open(old_path, FileAccess.READ)
	if inv_file == null:
		return []
	var inv_str = inv_file.get_as_text()
	inv_file.close()
	var inv_json: JSON = JSON.new()
	if inv_json.parse(inv_str) != OK or not (inv_json.data is Array):
		return []
	var out: Array = []
	for entry in inv_json.data:
		if entry is Dictionary:
			out.append(_order_item(entry))
		else:
			out.append(entry)
	return out

static func _get_inventory_capacity(player_data: Dictionary) -> int:
	# Rückfall auf backpack_slots oder Standard 12
	return int(player_data.get("backpack_slots", 12))

static func _array_to_string_ordered(arr: Array) -> String:
	# Debug-Ausgabe; nutzt JSON.stringify mit Tabs
	return JSON.stringify(arr, "\t")
