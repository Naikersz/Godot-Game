extends Node

## Einfacher Gegner-Generator für Dungeon (B)
##
## Nutzt die Kartengröße und is_walkable_tile() des Dungeon-Nodes,
## um zufällige begehbare Positionen zu finden.

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()


## Erzeugt eine Liste von Gegner-Dictionaries für einen Dungeon.
## dungeon: Node mit Eigenschaften map_width_tiles, map_height_tiles,
##          Methoden is_walkable_tile(Vector2i) und map_to_local(Vector2i).
## player_stats: aktuell noch nicht genutzt, aber für spätere Balancing-Logik vorgesehen.
func generate_enemies_for_dungeon(dungeon: Node, player_stats: Dictionary, count: int = 5) -> Array:
	var enemies: Array = []
	if dungeon == null:
		return enemies

	var walkable_cells: Array[Vector2i] = []

	# Sammle alle begehbaren Zellen
	for y in range(dungeon.map_height_tiles):
		for x in range(dungeon.map_width_tiles):
			var cell := Vector2i(x, y)
			if dungeon.is_walkable_tile(cell):
				walkable_cells.append(cell)

	if walkable_cells.is_empty():
		return enemies

	for i in range(count):
		var cell_index := _rng.randi_range(0, walkable_cells.size() - 1)
		var cell := walkable_cells[cell_index]
		var world_pos: Vector2 = dungeon.map_to_local(cell)

		var enemy := {
			"name": "Gegner %d" % (i + 1),
			"level": 1,
			"hp": 50,
			"max_hp": 50,
			"damage": 5,
			"defense": 2,
			"cell": cell,
			"world_pos": world_pos
		}
		enemies.append(enemy)

	return enemies


