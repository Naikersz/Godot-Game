extends RefCounted

## Loot Generator
## Entspricht game.aw/core/loot_generator.py

const DROP_CHANCE = 0.5
const ENCHANT_ROLL_CHANCE = 0.05

const ITEM_FILES = [
	"weapons.json",
	"helmets.json",
	"chests.json",
	"gloves.json",
	"pants.json",
	"boots.json",
	"shields.json"
]

var item_pool: Array = []
var enchantments: Array = []

func _init():
	_load_all_items()
	_load_enchantments()

func _load_all_items():
	item_pool.clear()
	for filename in ITEM_FILES:
		var items = _load_json_file(filename)
		item_pool.append_array(items)

func _load_enchantments():
	enchantments = _load_json_file("enchantments.json")

func _load_json_file(filename: String) -> Array:
	var data_path = "res://data"
	var path = data_path.path_join(filename)
	
	if not FileAccess.file_exists(path):
		print("[LootGenerator] Datei fehlt: %s" % path)
		return []
	
	var file = FileAccess.open(path, FileAccess.READ)
	if not file:
		print("[LootGenerator] Konnte Datei nicht öffnen: %s" % path)
		return []
	
	var json_string = file.get_as_text()
	file.close()
	
	var json_obj = JSON.new()
	var parse_result = json_obj.parse(json_string)
	
	if parse_result != OK:
		print("[LootGenerator] Ungültiges JSON: %s" % path)
		return []
	
	return json_obj.data

func generate_loot(monster_level: int) -> Dictionary:
	## Generiert ein Item, das zu einem Gegnerlevel passt. Kann leer zurückgeben, wenn kein Drop gerollt wurde.
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
	
	return rolled_item

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
	var item = {
		"id": template.get("id"),
		"name": template.get("name"),
		"item_type": template.get("item_type"),
		"item_level": template.get("item_level", 1),
		"min_player_level": template.get("min_player_level", 1),
		"material": template.get("material", {}),
		"enchant_slots": template.get("enchant_slots", 0),
		"requirements": _roll_range_block(template.get("requirements", {})),
		"stats": _roll_range_block(template.get("base_stats", {}))
	}
	return item

func _roll_range_block(block: Dictionary) -> Dictionary:
	## Erwartet Keys im Format xyz_min/xyz_max und erzeugt fertige Werte.
	var rolled: Dictionary = {}
	
	for key in block.keys():
		if not key.ends_with("_min"):
			continue
		
		var base_key = key.substr(0, key.length() - 4)  # Entfernt "_min"
		var min_val = block[key]
		var max_key = base_key + "_max"
		var max_val = block.get(max_key, min_val)
		
		var rolled_value
		if typeof(min_val) == TYPE_FLOAT or typeof(max_val) == TYPE_FLOAT:
			rolled_value = randf_range(float(min_val), float(max_val))
		else:
			rolled_value = randi_range(int(min_val), int(max_val))
		
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
	return 1 + ((level - 1) / 20) as int

