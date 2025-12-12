extends RefCounted

## Loot generator

const DROP_CHANCE = 0.5
const ENCHANT_ROLL_CHANCE = 0.05

const ITEM_FILES = [
	"weapons.json",
	"helmets.json",
	"chests.json",
	"gloves.json",
	"pants.json",
	"boots.json",
	"shields.json",
	"potion.json",
]

var item_pool: Array = []
var enchantments: Array = []

func _init():
	_load_all_items()
	_load_enchantments()

func _load_all_items():
	item_pool.clear()
	for filename in ITEM_FILES:
		if filename == "potion.json":
			var potions = _load_potions(filename)
			item_pool.append_array(potions)
		else:
			var items = _load_json_file(filename)
			item_pool.append_array(items)

func _load_enchantments():
	enchantments = _load_json_file("enchantments.json")

func _load_json_file(filename: String) -> Array:
	var data_path = "res://data"
	var path = data_path.path_join(filename)
	
	if not FileAccess.file_exists(path):
		print("[LootGenerator] Missing file: %s" % path)
		return []
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("[LootGenerator] Could not open file: %s" % path)
		return []
	
	var json_string = file.get_as_text()
	file.close()
	
	var json_obj = JSON.new()
	var parse_result = json_obj.parse(json_string)
	
	if parse_result != OK:
		print("[LootGenerator] Invalid JSON: %s" % path)
		return []
	
	return json_obj.data

# Load and convert potion entries to internal item format
func _load_potions(filename: String) -> Array:
	var data_path = "res://data"
	var path = data_path.path_join(filename)
	if not FileAccess.file_exists(path):
		print("[LootGenerator] Missing potion file: %s" % path)
		return []
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("[LootGenerator] Could not open potion file: %s" % path)
		return []
	var json_string = file.get_as_text()
	file.close()
	var json_obj = JSON.new()
	if json_obj.parse(json_string) != OK or not (json_obj.data is Dictionary):
		print("[LootGenerator] Invalid potion JSON: %s" % path)
		return []
	var potions_arr: Array = []
	if json_obj.data.has("potions") and json_obj.data["potions"] is Array:
		for entry in json_obj.data["potions"]:
			if not (entry is Dictionary):
				continue
			var potion: Dictionary = {
				"id": entry.get("id", ""),
				"name": entry.get("name", ""),
				"item_type": "potion",
				"rarity": entry.get("rarity", "normal"),
				"requiredLevel": entry.get("requiredLevel", 1),
				"effects": entry.get("effects", {}),
				"description": entry.get("description", ""),
				"enchant_slots": 0,
				"material": {},
			}
			potions_arr.append(potion)
	return potions_arr

func generate_loot(monster_level: int) -> Dictionary:
	## Generates an item appropriate for a monster level.
	## May return an empty dictionary when no drop was rolled.
	if randf() > DROP_CHANCE:
		return {}
	
	var candidate = _pick_item_for_level(monster_level)
	if candidate.is_empty():
		return {}
	
	var rolled_item = _build_item(candidate)
	rolled_item["enchantments"] = _roll_enchantments(
		rolled_item.get("item_level", monster_level),
		rolled_item.get("enchant_slots", 0),
		candidate.get("possible_enchantments", [])
	)

	# Rarity anhand der Anzahl der gewürfelten Enchantments bestimmen
	var rarity: String = "normal"
	var enchant_count: int = 0
	if rolled_item.has("enchantments") and rolled_item["enchantments"] is Array:
		enchant_count = (rolled_item["enchantments"] as Array).size()

	if enchant_count == 0:
		rarity = "normal"
	elif enchant_count <= 2:
		rarity = "magic"
	elif enchant_count <= 4:
		rarity = "epic"
	else:
		rarity = "legendary"

	rolled_item["rarity"] = rarity
	
	return _ordered_item_dict(rolled_item)

func _pick_item_for_level(monster_level: int) -> Dictionary:
	if monster_level <= 0:
		monster_level = 1
	
	var allowed_diff = max(1, int(monster_level * 0.05))
	var min_level = max(1, monster_level - allowed_diff)
	var max_level = monster_level
	
	var candidates: Array = []
	for item in item_pool:
		var item_level = item.get("item_level", 1)
		if min_level <= item_level and item_level <= max_level:
			candidates.append(item)
	
	if candidates.is_empty():
		return {}
	
	return candidates[randi() % candidates.size()]

func _build_item(template: Dictionary) -> Dictionary:
	var is_potion := String(template.get("item_type", "")).to_lower() == "potion"
	var item = {
		"id": template.get("id"),
		"name": template.get("name"),
		"item_type": template.get("item_type"),
		"item_level": template.get("item_level", template.get("requiredLevel", 1)),
		"min_player_level": template.get("min_player_level", template.get("requiredLevel", 1)),
		"material": template.get("material", {}),
		"requirements": _roll_range_block(template.get("requirements", {})),
		"stats": (template.get("effects", {}) if is_potion else _roll_range_block(template.get("base_stats", {}))),
		# Stack props
		"amount": 1,
		"stackable": is_potion,
		"max_stack": (20 if is_potion else 1),
		"rarity": template.get("rarity", "normal"),
		"description": template.get("description", ""),
	}
	# Append enchant slots at the end to keep enchant-related fields last
	item["enchant_slots"] = template.get("enchant_slots", 0)
	return item

# Ensure enchant fields appear last in the resulting dictionary (for JSON/debug output).
func _ordered_item_dict(item: Dictionary) -> Dictionary:
	var ordered: Dictionary = {}
	var keys_in_order := [
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
	for k in keys_in_order:
		if item.has(k):
			ordered[k] = item[k]
	
	# Include any other fields not explicitly listed, preserving their existing order.
	for k in item.keys():
		if not ordered.has(k):
			ordered[k] = item[k]
	return ordered

func _roll_range_block(block: Dictionary) -> Dictionary:
	## Expects keys in the format xyz_min/xyz_max and rolls final values for them.
	var rolled: Dictionary = {}
	
	for key in block.keys():
		if not key.ends_with("_min"):
			continue
		
		var base_key = key.substr(0, key.length() - 4)  # strip "_min"
		var min_val = block[key]
		var max_key = base_key + "_max"
		var max_val = block.get(max_key, min_val)
		
		# Immer Integer würfeln – auch wenn die JSON floats enthält
		var min_i := int(round(float(min_val)))
		var max_i := int(round(float(max_val)))
		if max_i < min_i:
			max_i = min_i
		var rolled_value := randi_range(min_i, max_i)
		rolled[base_key] = rolled_value
	
	return rolled

func _roll_enchantments(item_level: int, max_slots: int, allowed_ids: Array) -> Array:
	if max_slots <= 0:
		return []
	
	var candidates: Array = []
	for enchant in enchantments:
		var min_level = enchant.get("item_level_min", 1)
		var max_level = enchant.get("item_level_max", 999)
		if min_level <= item_level and item_level <= max_level:
			candidates.append(enchant)
	
	if not allowed_ids.is_empty():
		var allowed_set = {}
		for id in allowed_ids:
			allowed_set[id] = true
		
		var filtered: Array = []
		for enchant in candidates:
			if allowed_set.has(enchant.get("id")):
				filtered.append(enchant)
		candidates = filtered
	
	# Shuffle
	for i in range(candidates.size() - 1, 0, -1):
		var j = randi() % (i + 1)
		var temp = candidates[i]
		candidates[i] = candidates[j]
		candidates[j] = temp
	
	var results: Array = []
	var tier_cap = _max_tier_for_level(item_level)
	
	for enchant in candidates:
		if results.size() >= max_slots:
			break
		if randf() > ENCHANT_ROLL_CHANCE:
			continue
		
		var value_min = enchant.get("value_min", 0)
		var value_max = enchant.get("value_max", value_min)
		var base_value = randi_range(value_min, value_max) if value_max > value_min else value_min
		
		var rolled_tier = randi_range(1, tier_cap)
		var final_value = base_value * rolled_tier
		
		results.append({
			"id": enchant.get("id"),
			"name": enchant.get("name"),
			"type": enchant.get("type"),
			"value": final_value,
			"rolled_tier": rolled_tier
		})
	
	return results

static func _max_tier_for_level(level: int) -> int:
	if level <= 0:
		return 1
	# Vermeide Integer-Divisions-Warnung, arbeite explizit mit float
	return 1 + int((float(level) - 1.0) / 20.0)
