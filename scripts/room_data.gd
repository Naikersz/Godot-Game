extends Node

## Room metadata for dungeon generation
## Assign this script to a RoomData node in each room prefab

@export var room_type: String = "normal"  # "start", "normal", "boss", "treasure", "corridor"
@export var room_size: Vector2i = Vector2i(15, 15)  # Room size in tiles (64x64 each)
@export var connections: Array[String] = []  # ["north", "south", "east", "west"] - exit directions
@export var spawn_count: int = 3  # Number of enemy spawn points
@export var difficulty: int = 1  # Room difficulty (1-10)
@export var room_id: String = ""  # Unique room ID (optional)

# References to room nodes (will be initialized automatically)
@onready var floor_tilemap: TileMap = get_node_or_null("../Floor")
@onready var walls_tilemap: TileMap = get_node_or_null("../Walls")
@onready var spawn_points: Node2D = get_node_or_null("../SpawnPoints")
@onready var doors: Node2D = get_node_or_null("../Doors")
@onready var room_area: Area2D = get_node_or_null("../RoomArea")

func _ready():
	# Automatically determine connections from door presence
	if connections.is_empty() and doors:
		_update_connections_from_doors()

func _update_connections_from_doors():
	"""Automatically determines connections based on door presence"""
	connections.clear()
	var door_names = ["North", "South", "East", "West"]
	for door_name in door_names:
		var door = doors.get_node_or_null("Door" + door_name)
		if door and door.get_child_count() > 0:
			connections.append(door_name.to_lower())

func get_spawn_positions() -> Array[Vector2]:
	"""Returns an array of positions for enemy spawning"""
	var positions: Array[Vector2] = []
	if not spawn_points:
		return positions
	
	for child in spawn_points.get_children():
		if child is Marker2D:
			# Use global_position relative to room root
			positions.append(child.position)
	return positions

func get_door_position(direction: String) -> Vector2:
	"""Returns door position by direction (relative to room root)"""
	if not doors:
		return Vector2.ZERO
	
	var door_name = "Door" + direction.capitalize()
	var door = doors.get_node_or_null(door_name)
	if door:
		return door.position
	return Vector2.ZERO

func has_connection(direction: String) -> bool:
	"""Checks if there is an exit in the specified direction"""
	return direction.to_lower() in connections

func get_room_bounds() -> Rect2:
	"""Returns room bounds in pixels"""
	var tile_size = 64  # Tile size from Tileset.tres
	var pixel_size = Vector2(room_size.x * tile_size, room_size.y * tile_size)
	return Rect2(Vector2.ZERO, pixel_size)

func get_center_position() -> Vector2:
	"""Returns the central position of the room"""
	var bounds = get_room_bounds()
	return bounds.get_center()

