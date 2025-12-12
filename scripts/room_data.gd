extends Node

## Метаданные комнаты для генерации подземелий
## Присвойте этот скрипт узлу RoomData в каждой комнате-префабе

@export var room_type: String = "normal"  # "start", "normal", "boss", "treasure", "corridor"
@export var room_size: Vector2i = Vector2i(15, 15)  # Размер комнаты в тайлах (64x64 каждый)
@export var connections: Array[String] = []  # ["north", "south", "east", "west"] - направления выходов
@export var spawn_count: int = 3  # Количество точек спавна врагов
@export var difficulty: int = 1  # Сложность комнаты (1-10)
@export var room_id: String = ""  # Уникальный ID комнаты (опционально)

# Ссылки на узлы комнаты (будут инициализированы автоматически)
@onready var floor_tilemap: TileMap = get_node_or_null("../Floor")
@onready var walls_tilemap: TileMap = get_node_or_null("../Walls")
@onready var spawn_points: Node2D = get_node_or_null("../SpawnPoints")
@onready var doors: Node2D = get_node_or_null("../Doors")
@onready var room_area: Area2D = get_node_or_null("../RoomArea")

func _ready():
	# Автоматически определяем connections из наличия дверей
	if connections.is_empty() and doors:
		_update_connections_from_doors()

func _update_connections_from_doors():
	"""Автоматически определяет connections на основе наличия дверей"""
	connections.clear()
	var door_names = ["North", "South", "East", "West"]
	for door_name in door_names:
		var door = doors.get_node_or_null("Door" + door_name)
		if door and door.get_child_count() > 0:
			connections.append(door_name.to_lower())

func get_spawn_positions() -> Array[Vector2]:
	"""Возвращает массив позиций для спавна врагов"""
	var positions: Array[Vector2] = []
	if not spawn_points:
		return positions
	
	for child in spawn_points.get_children():
		if child is Marker2D:
			# Используем global_position относительно корня комнаты
			positions.append(child.position)
	return positions

func get_door_position(direction: String) -> Vector2:
	"""Возвращает позицию двери по направлению (относительно корня комнаты)"""
	if not doors:
		return Vector2.ZERO
	
	var door_name = "Door" + direction.capitalize()
	var door = doors.get_node_or_null(door_name)
	if door:
		return door.position
	return Vector2.ZERO

func has_connection(direction: String) -> bool:
	"""Проверяет, есть ли выход в указанном направлении"""
	return direction.to_lower() in connections

func get_room_bounds() -> Rect2:
	"""Возвращает границы комнаты в пикселях"""
	var tile_size = 64  # Размер тайла из Tilesett.tres
	var pixel_size = Vector2(room_size.x * tile_size, room_size.y * tile_size)
	return Rect2(Vector2.ZERO, pixel_size)

func get_center_position() -> Vector2:
	"""Возвращает центральную позицию комнаты"""
	var bounds = get_room_bounds()
	return bounds.get_center()

