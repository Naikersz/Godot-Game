extends Node
class_name ItemRegistryClass

var _items_by_id: Dictionary = {}
var _type_cache: Dictionary = {}

func _ready() -> void:
	_load_from_json_files()

func get_item(id: String) -> Item:
	if _items_by_id.has(id):
		return _items_by_id[id]
	return null

func register_item(item: Item) -> void:
	if item == null:
		return
	if item.id == "":
		item.id = item.name
	if item.id == "":
		return
	_items_by_id[item.id] = item

func _load_from_json_files() -> void:
	var data_files := [
		"res://data/weapons.json",
		"res://data/helmets.json",
		"res://data/chests.json",
		"res://data/gloves.json",
		"res://data/pants.json",
		"res://data/boots.json",
		"res://data/shields.json",
		"res://data/potion.json",
	]
	for path in data_files:
		if not FileAccess.file_exists(path):
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			continue
		var txt := file.get_as_text()
		file.close()
		var json := JSON.new()
		if json.parse(txt) != OK:
			continue
		if path.ends_with("potion.json"):
			_load_potions(json.data)
		else:
			_load_items(json.data)

func _load_items(arr: Variant) -> void:
	if not (arr is Array):
		return
	for entry in arr:
		if not (entry is Dictionary):
			continue
		var item := Item.new()
		item.id = String(entry.get("id", ""))
		item.name = String(entry.get("name", item.id))
		item.rarity = String(entry.get("rarity", "normal"))
		item.description = String(entry.get("description", ""))
		item.enchant_slots = int(entry.get("enchant_slots", 0))
		item.item_type = _get_or_make_type(entry.get("item_type", ""))
		item.stats = entry.get("base_stats", entry.get("stats", {}))
		register_item(item)

func _load_potions(data: Variant) -> void:
	if not (data is Dictionary):
		return
	var potions: Array = data.get("potions", []) as Array
	if not (potions is Array):
		return
	for entry in potions:
		if not (entry is Dictionary):
			continue
		var item := Item.new()
		item.id = String(entry.get("id", ""))
		item.name = String(entry.get("name", item.id))
		item.rarity = String(entry.get("rarity", "normal"))
		item.description = String(entry.get("description", ""))
		item.enchant_slots = 0
		item.item_type = _get_or_make_type("potion", true, 20)
		item.stats = entry.get("effects", {})
		register_item(item)

func _get_or_make_type(type_name: String, stackable: bool = false, max_stack: int = 1) -> ItemType:
	var key := type_name.to_lower()
	if _type_cache.has(key):
		return _type_cache[key]
	var t := ItemType.new()
	t.action_type = ""
	t.type_color = Color.WHITE
	t.tab_name = ""
	t.stackable = stackable
	t.max_stack = max_stack
	_type_cache[key] = t
	return t
