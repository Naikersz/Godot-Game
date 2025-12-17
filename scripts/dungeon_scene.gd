extends Node2D

## Script for the Dungeon Scene.
## Loads the HUD and spawns temporary enemy markers.

const EnemyMarker: Script = preload("res://scripts/enemy_marker.gd")
const EnemyGeneratorScript: Script = preload("res://core/enemy_generator.gd")
const TempLootStoreRes := preload("res://core/temp_loot_store.gd")

@onready var tilemap: TileMap = $DungeonTileMap/TileMapFloor

var map_width_tiles: int = 0
var map_height_tiles: int = 0
var map_origin: Vector2i = Vector2i.ZERO

func _ready() -> void:
	TempLootStoreRes.clear() # clear temp loot on dungeon enter
	var hud_scene := preload("res://scenes/hud_scene.tscn")
	var hud = hud_scene.instantiate()
	add_child(hud)

	_init_map_bounds()
	_spawn_enemies()

func _init_map_bounds() -> void:
	if not tilemap:
		return
	var used: Rect2i = tilemap.get_used_rect()
	map_origin = used.position
	map_width_tiles = used.size.x
	map_height_tiles = used.size.y

func is_walkable_tile(cell: Vector2i) -> bool:
	if not tilemap:
		return false
	# Walkable if a tile exists on layer 0
	var real_cell: Vector2i = map_origin + cell
	return tilemap.get_cell_source_id(0, real_cell) != -1

func map_to_local(cell: Vector2i) -> Vector2:
	if not tilemap:
		return Vector2.ZERO
	# TileMap.map_to_local returns position relative to TileMap,
	# we need it in the DungeonScene coordinate system.
	var real_cell: Vector2i = map_origin + cell
	return tilemap.to_global(tilemap.map_to_local(real_cell))

func _spawn_enemies() -> void:
	# Use local instance of EnemyGenerator (no Autoload needed)
	var generator: Node = EnemyGeneratorScript.new()
	add_child(generator)  # so _ready() is called (to load JSONs)

	var player_stats: Dictionary = {}  # Placeholder for future balancing
	var enemies: Array = generator.generate_enemies_for_dungeon(self, player_stats)

	print("EnemyGenerator: generated ", enemies.size(), " enemies for ",
		Constants.current_level_type, " ", Constants.current_level_number)

	for enemy in enemies:
		if not (enemy is Dictionary):
			continue
		print("  enemy:", enemy.get("name", "Monster"), "lvl", enemy.get("level", 0),
			"rarity", enemy.get("rarity", "n/a"), "pos", enemy.get("world_pos", Vector2.ZERO))

		var marker: Node2D = EnemyMarker.new()
		marker.position = enemy.get("world_pos", Vector2.ZERO)
		marker.setup(enemy)
		add_child(marker)

func _exit_tree() -> void:
	# Clear temp loot when leaving the dungeon
	TempLootStoreRes.clear()
