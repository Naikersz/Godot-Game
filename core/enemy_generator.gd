extends Node

## Enemy generator based on:
## - data/monster.json              (monster base stats)
## - data/dungeon_content.json      (per-dungeon enemy counts and level ranges)
## - data/monster_enchantments.json (possible monster affixes)
##
## Expects the dungeon node to provide:
## - Properties: map_width_tiles, map_height_tiles
## - Methods:    is_walkable_tile(Vector2i), map_to_local(Vector2i)

const MONSTER_PATH: String = "res://data/monster.json"
const DUNGEON_CONTENT_PATH: String = "res://data/dungeon_content.json"
const MONSTER_ENCHANTMENTS_PATH: String = "res://data/monster_enchantments.json"

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

var _monster_defs: Array = []
var _dungeon_content: Dictionary = {}
var _enchant_defs: Array = []


func _ready() -> void:
	_rng.randomize()
	_load_monsters()
	_load_dungeon_content()
	_load_enchantments()


func _load_monsters() -> void:
	_monster_defs.clear()
	if not FileAccess.file_exists(MONSTER_PATH):
		printerr("EnemyGenerator: monster.json not found at ", MONSTER_PATH)
		return

	var file := FileAccess.open(MONSTER_PATH, FileAccess.READ)
	if not file:
		return
	var text: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		printerr("EnemyGenerator: failed to parse monster.json")
		return
	if json.data is Array:
		_monster_defs = json.data


func _load_dungeon_content() -> void:
	_dungeon_content.clear()
	if not FileAccess.file_exists(DUNGEON_CONTENT_PATH):
		printerr("EnemyGenerator: dungeon_content.json not found at ", DUNGEON_CONTENT_PATH)
		return

	var file := FileAccess.open(DUNGEON_CONTENT_PATH, FileAccess.READ)
	if not file:
		return
	var text: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		printerr("EnemyGenerator: failed to parse dungeon_content.json")
		return
	if json.data is Dictionary:
		_dungeon_content = json.data


func _load_enchantments() -> void:
	_enchant_defs.clear()
	if not FileAccess.file_exists(MONSTER_ENCHANTMENTS_PATH):
		printerr("EnemyGenerator: monster_enchantments.json not found at ", MONSTER_ENCHANTMENTS_PATH)
		return

	var file := FileAccess.open(MONSTER_ENCHANTMENTS_PATH, FileAccess.READ)
	if not file:
		return
	var text: String = file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(text) != OK:
		printerr("EnemyGenerator: failed to parse monster_enchantments.json")
		return
	if json.data is Array:
		_enchant_defs = json.data


## Creates a list of enemy dictionaries for the current dungeon.
## _player_stats is reserved for future balancing logic.
func generate_enemies_for_dungeon(dungeon: Node, _player_stats: Dictionary) -> Array:
	var enemies: Array = []
	if dungeon == null:
		return enemies

	# Key like "Forest_1" / "Cave_2" from Constants
	var key: String = "%s_%d" % [Constants.current_level_type, Constants.current_level_number]
	if not _dungeon_content.has(key):
		printerr("EnemyGenerator: no dungeon_content entry for ", key)
		return enemies

	var config: Dictionary = _dungeon_content[key]
	var monsters_cfg: Dictionary = config.get("Monsters", {})

	var counts: Dictionary = {
		"normal": int(monsters_cfg.get("normal", 0)),
		"magic": int(monsters_cfg.get("magic", 0)),
		"epic": int(monsters_cfg.get("epic", 0)),
		"legendary": int(monsters_cfg.get("legendary", 0)),
		"unique": int(monsters_cfg.get("unique", 0))
	}

	var min_level: int = int(monsters_cfg.get("min_level", 1))
	var max_level: int = int(monsters_cfg.get("max_level", 1))
	if max_level < min_level:
		max_level = min_level

	var walkable_cells: Array[Vector2i] = _collect_walkable_cells(dungeon)
	if walkable_cells.is_empty():
		printerr("EnemyGenerator: no walkable cells in dungeon")
		return enemies

	# Enchantment limits from dungeon_content (enchant_slots & optional whitelist of IDs)
	var ench_cfg: Dictionary = config.get("EnchantmentSlots", {})
	var max_enchant_slots: int = int(ench_cfg.get("enchant_slots", 0))
	var allowed_enchant_ids: Array = []
	if ench_cfg.has("possible_enchantments") and ench_cfg["possible_enchantments"] is Array:
		allowed_enchant_ids = ench_cfg["possible_enchantments"]

	for rarity in counts.keys():
		var count: int = counts[rarity]
		for i in range(count):
			var cell_index: int = _rng.randi_range(0, walkable_cells.size() - 1)
			var cell: Vector2i = walkable_cells[cell_index]
			var world_pos: Vector2 = dungeon.map_to_local(cell)

			var lvl: int = _rng.randi_range(min_level, max_level)
			var monster_def: Dictionary = _pick_monster_def_for_level(lvl)
			if monster_def.is_empty():
				continue

			var enemy: Dictionary = _build_enemy(
				monster_def,
				lvl,
				String(rarity),
				cell,
				world_pos,
				max_enchant_slots,
				allowed_enchant_ids
			)
			enemies.append(enemy)

	return enemies


func _collect_walkable_cells(dungeon: Node) -> Array[Vector2i]:
	var walkable_cells: Array[Vector2i] = []
	if not dungeon.has_method("is_walkable_tile"):
		return walkable_cells

	var h: int = int(dungeon.map_height_tiles)
	var w: int = int(dungeon.map_width_tiles)

	for y in range(h):
		for x in range(w):
			var cell: Vector2i = Vector2i(x, y)
			if dungeon.is_walkable_tile(cell):
				walkable_cells.append(cell)
	return walkable_cells


func _pick_monster_def_for_level(level: int) -> Dictionary:
	if _monster_defs.is_empty():
		return {}

	var candidates: Array = []
	for m in _monster_defs:
		if not (m is Dictionary):
			continue
		var base_level: int = int(m.get("level", 1))
		if base_level <= level:
			candidates.append(m)

	if candidates.is_empty():
		# Fallback: pick any monster
		return _monster_defs[_rng.randi_range(0, _monster_defs.size() - 1)]

	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _build_enemy(
	monster_def: Dictionary,
	level: int,
	rarity: String,
	cell: Vector2i,
	world_pos: Vector2,
	max_enchant_slots: int,
	allowed_enchant_ids: Array
) -> Dictionary:
	var stats: Dictionary = monster_def.get("stats", {})

	var hp_min: int = int(stats.get("hp_min", 1))
	var hp_max: int = int(stats.get("hp_max", hp_min))
	var dmg_min: int = int(stats.get("damage_min", 1))
	var dmg_max: int = int(stats.get("damage_max", dmg_min))
	var def_min: int = int(stats.get("defense_min", 0))
	var def_max: int = int(stats.get("defense_max", def_min))
	var gold_min: int = int(monster_def.get("gold_min", 0))
	var gold_max: int = int(monster_def.get("gold_max", gold_min))

	# Roll all Kampf-Stats als ints (Gold wird erst beim Tod mit Drop-Chance gewürfelt)
	var hp: int = _rng.randi_range(hp_min, hp_max)
	var damage: int = _rng.randi_range(dmg_min, dmg_max)
	var defense: int = _rng.randi_range(def_min, def_max)

	var enemy: Dictionary = {
		"id": monster_def.get("id", "unknown"),
		"name": monster_def.get("name", "Monster"),
		"rarity": rarity,
		"level": level,
		"hp": hp,
		"max_hp": hp,
		"damage": damage,
		"defense": defense,
		"gold_min": gold_min,
		"gold_max": gold_max,
		"cell": cell,
		"world_pos": world_pos,
		"enchantments": _roll_enchantments(level, rarity, max_enchant_slots, allowed_enchant_ids)
	}
	return enemy


func _roll_enchantments(
	level: int,
	rarity: String,
	max_enchant_slots: int,
	allowed_ids: Array
) -> Array:
	var result: Array = []
	if _enchant_defs.is_empty():
		return result

	# Rarity-based slot ranges
	var rarity_min: int = 0
	var rarity_max: int = 0
	match rarity:
		"normal":
			rarity_min = 0
			rarity_max = 0           # no enchants
		"magic":
			rarity_min = 1
			rarity_max = 2           # 1–2
		"epic":
			rarity_min = 3
			rarity_max = 4           # 3–4
		"legendary":
			rarity_min = 5
			rarity_max = 6           # 5–6
		"unique":
			rarity_min = 5
			rarity_max = 6           # base range, but no further slot/enchant restrictions
		_:
			rarity_min = 0
			rarity_max = 0

	# Unique Monster haben keine Beschränkung durch dungeon_content.enchant_slots
	var effective_max: int = rarity_max
	# Dungeon-Limit nur für nicht-legendary / nicht-unique anwenden
	if rarity != "unique" and rarity != "legendary":
		effective_max = min(rarity_max, max_enchant_slots)

	if effective_max <= 0:
		return result

	var effective_min: int = min(rarity_min, effective_max)
	var slots: int = _rng.randi_range(effective_min, effective_max)

	for i in range(slots):
		# Unique Monster haben keine Whitelist-Einschränkung
		var def: Dictionary = _pick_enchant_def_for_level(
			level,
			[] if rarity == "unique" else allowed_ids
		)
		if def.is_empty():
			continue
		var rolled: Dictionary = _roll_enchant_instance(def, level)
		result.append(rolled)

	return result


func _pick_enchant_def_for_level(level: int, allowed_ids: Array) -> Dictionary:
	var candidates: Array = []
	for e in _enchant_defs:
		if not (e is Dictionary):
			continue
		var min_lvl: int = int(e.get("min_level", 1))
		if level < min_lvl:
			continue
		if not allowed_ids.is_empty() and not (e.get("id", "") in allowed_ids):
			continue
		candidates.append(e)

	if candidates.is_empty():
		return {}
	return candidates[_rng.randi_range(0, candidates.size() - 1)]


func _roll_enchant_instance(def: Dictionary, level: int) -> Dictionary:
	var base_min: int = int(def.get("value_min", 0))
	var base_max: int = int(def.get("value_max", base_min))

	# Max tier based on level:
	#  1–20 -> max_tier = 1
	# 21–40 -> max_tier = 2
	# 41–60 -> max_tier = 3
	# etc. in 20-level steps (use float division to avoid integer-division warning)
	var max_tier: int = 1 + int((level - 1) / 20.0)
	if max_tier < 1:
		max_tier = 1

	# Actual tier randomly between 1 and max_tier
	var tier: int = _rng.randi_range(1, max_tier)

	var value_min: int = base_min * tier
	var value_max: int = base_max * tier
	if value_max < value_min:
		value_max = value_min

	var value: int = _rng.randi_range(value_min, value_max)

	return {
		"id": def.get("id", ""),
		"name": def.get("name", ""),
		"type": def.get("type", ""),
		"tier": tier,
		"value": value
	}
