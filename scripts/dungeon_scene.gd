extends Node2D

## Script für die Dungeon-Szene.
## Lädt das HUD und spawnt temporäre Gegner-Markierungen.

const EnemyMarker: Script = preload("res://scripts/enemy_marker.gd")
const EnemyGeneratorScript: Script = preload("res://core/enemy_generator.gd")

@onready var tilemap: TileMap = $DungeonTileMap/TileMapFloor

var map_width_tiles: int = 0
var map_height_tiles: int = 0
var map_origin: Vector2i = Vector2i.ZERO

func _ready() -> void:
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
	# Begehbar, wenn auf Layer 0 ein Tile existiert
	var real_cell: Vector2i = map_origin + cell
	return tilemap.get_cell_source_id(0, real_cell) != -1

func map_to_local(cell: Vector2i) -> Vector2:
	if not tilemap:
		return Vector2.ZERO
	# TileMap.map_to_local gibt Position relativ zur TileMap zurück,
	# wir brauchen sie im Koordinatensystem der DungeonScene.
	var real_cell: Vector2i = map_origin + cell
	return tilemap.to_global(tilemap.map_to_local(real_cell))

func _spawn_enemies() -> void:
	# Lokale Instanz des EnemyGenerators verwenden (kein Autoload nötig)
	var generator: Node = EnemyGeneratorScript.new()
	add_child(generator)  # damit _ready() aufgerufen wird (zum Laden der JSONs)

	var player_stats: Dictionary = {}  # Platzhalter für späteres Balancing
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
