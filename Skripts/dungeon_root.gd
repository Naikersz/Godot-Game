extends Node2D

# ========== НАСТРОЙКИ ==========
@export var map_width_tiles: int = 60
@export var map_height_tiles: int = 40
@export var min_room_size: int = 6
@export var max_room_size: int = 12
@export var max_depth: int = 8

# Направления для удобной проверки соседей
const N  := Vector2i(0, -1)
const S  := Vector2i(0,  1)
const W  := Vector2i(-1, 0)
const E  := Vector2i(1,  0)
const NW := Vector2i(-1, -1)
const NE := Vector2i(1, -1)
const SW := Vector2i(-1,  1)
const SE := Vector2i(1,  1)

# ========== ССЫЛКИ НА TileMapLayer (ВАЖНО: НЕ TileMap!) ==========
@onready var floor_layer: TileMapLayer = $TileMapFloor/FloorLayer
@onready var wall_layer: TileMapLayer = $TileMapFloor/WallLayer
@onready var wall_volume_layer: TileMapLayer = $TileMapFloor/ColumnsLayer
@onready var top_layer: TileMapLayer = $TileMapFloor/TopLayer  

# ========== ВНУТРЕННЯЯ КАРТА ==========
enum TileType { EMPTY, FLOOR, WALL }
enum CornerType { NONE, UL, UR, DL, DR }
var _grid: Array = []
var _rng := RandomNumberGenerator.new()

# ---------- BSP УЗЕЛ ----------
class BSPNode:
	var rect: Rect2i
	var left: BSPNode = null
	var right: BSPNode = null
	var room: Rect2i = Rect2i()

	func is_leaf() -> bool:
		return left == null and right == null

var _bsp_root: BSPNode = null


func _ready():
	_rng.randomize()
	generate_dungeon()
	_spawn_enemies_in_dungeon()


# ---------- ГЛАВНАЯ ----------
func generate_dungeon():
	_make_empty_grid()

	var root_rect := Rect2i(0, 0, map_width_tiles, map_height_tiles)
	_bsp_root = _split_space(root_rect, 0)

	_create_rooms_in_leaves(_bsp_root)
	_connect_adjacent_leaves(_bsp_root)

	_create_walls_around_floor()
	_apply_grid_to_layers()


# ---------- СОЗДАНИЕ ПУСТОЙ СЕТКИ ----------

func _make_empty_grid() -> void:
	_grid.clear()
	for y in map_height_tiles:
		var row: Array = []
		for x in map_width_tiles:
			row.append(TileType.EMPTY)
		_grid.append(row)

# ---------- BSP РАЗБИЕНИЕ ----------

func _split_space(region: Rect2i, depth: int) -> BSPNode:
	var node := BSPNode.new()
	node.rect = region

	if depth >= max_depth:
		return node

	var split_horizontally: bool

	if region.size.x > region.size.y:
		split_horizontally = false
	elif region.size.y > region.size.x:
		split_horizontally = true
	else:
		split_horizontally = _rng.randi() % 2 == 0

	if split_horizontally:
		var min_split := region.position.y + min_room_size
		var max_split := region.position.y + region.size.y - min_room_size
		if max_split <= min_split:
			return node
		var split_y := _rng.randi_range(min_split, max_split)

		var top := Rect2i(region.position.x, region.position.y,
				region.size.x, split_y - region.position.y)
		var bottom := Rect2i(region.position.x, split_y,
				region.size.x, region.position.y + region.size.y - split_y)

		node.left = _split_space(top, depth + 1)
		node.right = _split_space(bottom, depth + 1)
	else:
		var min_split_x := region.position.x + min_room_size
		var max_split_x := region.size.x + region.position.x - min_room_size
		if min_split_x >= max_split_x:
			return node

		var split_x := _rng.randi_range(min_split_x, max_split_x)

		var left_rect := Rect2i(region.position.x, region.position.y,
				split_x - region.position.x, region.size.y)
		var right_rect := Rect2i(split_x, region.position.y,
				region.position.x + region.size.x - split_x, region.size.y)

		node.left = _split_space(left_rect, depth + 1)
		node.right = _split_space(right_rect, depth + 1)

	return node

# ---------- КОМНАТЫ В ЛИСТЬЯХ ----------

func _create_rooms_in_leaves(node: BSPNode) -> void:
	if node == null:
		return

	if node.is_leaf():
		node.room = _create_room_in_region(node.rect)
		# DEBUG: смотрим, какие комнаты вообще создаются
		if node.room.size.x > 0 and node.room.size.y > 0:
			print("ROOM:", node.room)
			_carve_room(node.room)
	else:
		_create_rooms_in_leaves(node.left)
		_create_rooms_in_leaves(node.right)

func _create_room_in_region(region: Rect2i) -> Rect2i:
	var room_width := _rng.randi_range(
		min_room_size,
		min(max_room_size, region.size.x - 2)
	)
	var room_height := _rng.randi_range(
		min_room_size,
		min(max_room_size, region.size.y - 2)
	)

	if room_width <= 0 or room_height <= 0:
		return Rect2i(0, 0, 0, 0)

	var room_x := _rng.randi_range(
		region.position.x + 1,
		region.position.x + region.size.x - room_width - 1
	)
	var room_y := _rng.randi_range(
		region.position.y + 1,
		region.position.y + region.size.y - room_height - 1
	)

	return Rect2i(room_x, room_y, room_width, room_height)

func _carve_room(room: Rect2i) -> void:
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			_set_grid(Vector2i(x, y), TileType.FLOOR)

# ---------- КОРИДОРЫ МЕЖДУ КОМНАТАМИ ----------

func _connect_adjacent_leaves(node: BSPNode) -> void:
	if node == null or node.is_leaf():
		return

	_connect_adjacent_leaves(node.left)
	_connect_adjacent_leaves(node.right)

	if node.left != null and node.right != null:
		var left_room := _find_room_in_node(node.left)
		var right_room := _find_room_in_node(node.right)

		if left_room.size.x > 0 and right_room.size.x > 0:
			_connect_rooms_with_corridor(left_room, right_room)

func _find_room_in_node(node: BSPNode) -> Rect2i:
	if node == null:
		return Rect2i()

	if node.is_leaf():
		return node.room

	var left_room := _find_room_in_node(node.left)
	if left_room.size.x > 0:
		return left_room

	return _find_room_in_node(node.right)

func _connect_rooms_with_corridor(room_a: Rect2i, room_b: Rect2i) -> void:
	var center_a := Vector2i(
		room_a.position.x + room_a.size.x / 2,
		room_a.position.y + room_a.size.y / 2
	)
	var center_b := Vector2i(
		room_b.position.x + room_b.size.x / 2,
		room_b.position.y + room_b.size.y / 2
	)

	_carve_h_corridor(center_a.x, center_b.x, center_a.y)
	_carve_v_corridor(center_a.y, center_b.y, center_b.x)

func _carve_h_corridor(x1: int, x2: int, y: int) -> void:
	var x_start: int = min(x1, x2)
	var x_end: int = max(x1, x2)

	for x in range(x_start, x_end + 1):
		_set_grid(Vector2i(x, y), TileType.FLOOR)
		_set_grid(Vector2i(x, y + 1), TileType.FLOOR) # ← расширяем вниз

func _carve_v_corridor(y1: int, y2: int, x: int) -> void:
	var y_start: int = min(y1, y2)
	var y_end: int = max(y1, y2)

	for y in range(y_start, y_end + 1):
		_set_grid(Vector2i(x, y), TileType.FLOOR)
		_set_grid(Vector2i(x + 1, y), TileType.FLOOR) # ← расширяем вправо

# ---------- СОЗДАЁМ СТЕНЫ ВОКРУГ ПОЛА ----------

func _create_walls_around_floor() -> void:
	var new_walls: Array[Vector2i] = []
	
	# Проходим ТОЛЬКО по клеткам с полом
	for y in map_height_tiles:
		for x in map_width_tiles:
			var pos := Vector2i(x, y)
			if _get_grid(pos) != TileType.FLOOR:
				continue
				
			# Проверяем 8 соседей
			for dy in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					if dx == 0 and dy == 0:
						continue
					var neighbor := pos + Vector2i(dx, dy)
					
					# Если сосед за пределами или EMPTY → это место для стены
					if !_is_in_bounds(neighbor) or _get_grid(neighbor) == TileType.EMPTY:
						# Но только если там ещё НЕ пол и НЕ стена (на всякий случай)
						if _get_grid(neighbor) != TileType.FLOOR:
							new_walls.append(neighbor)
	
	# Теперь ОДНИМ проходом ставим все стены
	for wall_pos in new_walls:
		_set_grid(wall_pos, TileType.WALL)
	
	# Опционально: рамка по краям
	for x in map_width_tiles:
		if _get_grid(Vector2i(x, 0)) != TileType.FLOOR:
			_set_grid(Vector2i(x, 0), TileType.WALL)
		if _get_grid(Vector2i(x, map_height_tiles - 1)) != TileType.FLOOR:
			_set_grid(Vector2i(x, map_height_tiles - 1), TileType.WALL)
	for y in map_height_tiles:
		if _get_grid(Vector2i(0, y)) != TileType.FLOOR:
			_set_grid(Vector2i(0, y), TileType.WALL)
		if _get_grid(Vector2i(map_width_tiles - 1, y)) != TileType.FLOOR:
			_set_grid(Vector2i(map_width_tiles - 1, y), TileType.WALL)
			
func _is_in_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 && pos.y >= 0 && pos.x < map_width_tiles && pos.y < map_height_tiles
	
func _count_neighbors(pos: Vector2i) -> int:
	var dirs = [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1)
	]

	var c := 0
	for d in dirs:
		var t := _get_grid(pos + d)
		if t == TileType.FLOOR or t == TileType.WALL:
			c += 1

	return c

func _set_grid(pos: Vector2i, t: int) -> void:
	if pos.x < 0 or pos.y < 0 or pos.x >= map_width_tiles or pos.y >= map_height_tiles:
		return
	_grid[pos.y][pos.x] = t

func _get_grid(pos: Vector2i) -> int:
	if pos.x < 0 or pos.y < 0 or pos.x >= map_width_tiles or pos.y >= map_height_tiles:
		return TileType.EMPTY
	return _grid[pos.y][pos.x]

func _has_neighbor(pos: Vector2i, t: int) -> bool:
	var neighbors := [
		Vector2i(pos.x, pos.y - 1),
		Vector2i(pos.x, pos.y + 1),
		Vector2i(pos.x + 1, pos.y),
		Vector2i(pos.x - 1, pos.y)
	]
	for n in neighbors:
		if _get_grid(n) == t:
			return true
	return false
	
# ---------- РАСКЛАДКА ПО 3 УРОВНЯМ ----------
func _apply_grid_to_layers():
	floor_layer.clear()
	wall_layer.clear()
	wall_volume_layer.clear()
	top_layer.clear()

	var floor_cells: Array[Vector2i] = []
	var wall_cells: Array[Vector2i] = []

	for y in map_height_tiles:
		for x in map_width_tiles:
			var pos := Vector2i(x, y)
			match _get_grid(pos):
				TileType.FLOOR:
					floor_cells.append(pos)
				TileType.WALL:
					wall_cells.append(pos)
	
	# Простой вариант без Terrain-Connect/Auto-Tiles, damit keine TileSet-Fehler auftreten:
	# Wir setzen einfach einen gültigen Basis-Tile (source_id = 0, atlas (0,0)).

	# Пол
	for cell in floor_cells:
		floor_layer.set_cell(cell, 0, Vector2i(0, 0))

	# Стены
	for cell in wall_cells:
		wall_layer.set_cell(cell, 0, Vector2i(0, 0))

	# Опциональные Deko-Funktionen vorerst deaktiviert, um TileSet-Fehler zu vermeiden.
	# _build_wall_volume()
	# _build_pillars()
	# _build_walltops()


# ========== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ДЛЯ СПАВНА (WALKABLE + POS) ==========

func is_walkable_tile(cell: Vector2i) -> bool:
	return _get_grid(cell) == TileType.FLOOR


func cell_to_world(cell: Vector2i) -> Vector2:
	if floor_layer:
		return floor_layer.map_to_local(cell)
	return Vector2.ZERO


## Prüft zusätzlich, ob die Kachel wirklich aus dem Dungeon-Tileset/Floor stammt.
## Standardmäßig filtern wir nach source_id == 0, das ist in deinem Tileset
## der Haupt-Dungeon-Floor. Falls du später andere Quellen nutzt, kannst du
## diese Bedingung anpassen.
func is_dungeon_floor(cell: Vector2i) -> bool:
	# Vereinfachung: alles, was als FLOOR im internen Grid markiert ist,
	# zählt als Dungeon-Floor. Falls du später genauer filtern möchtest,
	# kannst du hier wieder auf get_cell_source_id() prüfen.
	return is_walkable_tile(cell)


# ========== ПРОСТАЯ ГЕНЕРАЦИЯ ПРОТИВНИКОВ В ПОДЗЕМЕЛЬЕ ==========

func _spawn_enemies_in_dungeon(count: int = 5) -> void:
	# Собираем все клетки пола
	var floor_cells: Array[Vector2i] = []
	for y in map_height_tiles:
		for x in map_width_tiles:
			var c := Vector2i(x, y)
			if is_dungeon_floor(c):
				floor_cells.append(c)

	if floor_cells.is_empty():
		return

	# Родительский узел для визуальных врагов
	# Hängen wir an die TopLayer, damit sie sicher über dem Dungeon gerendert werden.
	var enemies_root := Node2D.new()
	enemies_root.name = "Enemies"
	enemies_root.z_index = 1
	enemies_root.y_sort_enabled = true
	if top_layer:
		top_layer.add_child(enemies_root)
	else:
		add_child(enemies_root)

	# Случайно расставляем несколько "врагов" как красные квадраты
	for i in range(count):
		var idx := _rng.randi_range(0, floor_cells.size() - 1)
		var cell := floor_cells[idx]
		var world_pos := cell_to_world(cell)

		var enemy := Node2D.new()
		enemy.name = "Enemy_%d" % i
		enemy.position = world_pos
		enemy.z_index = 5
		enemies_root.add_child(enemy)

		# Roter Punkt (Körper)
		var marker := ColorRect.new()
		marker.color = Color(1, 0, 0, 0.9)
		marker.size = Vector2(10, 10)
		marker.position = Vector2(-5, -5)
		enemy.add_child(marker)

		# Grüner HP-Balken darüber
		var hp_bar := ColorRect.new()
		hp_bar.color = Color(0, 1, 0, 0.9)
		hp_bar.size = Vector2(14, 3)
		hp_bar.position = Vector2(-7, -9)
		enemy.add_child(hp_bar)

# ========== БОРТИКИ — ГЛАВНАЯ МАГИЯ 3D ==========
func _build_walltops():
	var top_cells: Array[Vector2i] = []
	
	# Проходим по всем стенам
	for pos in wall_layer.get_used_cells():
		var above := pos + Vector2i(0, -1)
		
		# Если сверху от стены — НЕ стена (пол или пустота)
		if wall_layer.get_cell_source_id(above) == -1:
			top_cells.append(pos)  # бортик в той же клетке!
	
	# Автотейлинг бортиков
	if not top_cells.is_empty():
		top_layer.set_cells_terrain_connect(top_cells, 0, 2)

func _build_wall_volume():
	var facade_cells: Array[Vector2i] = []

	# Собираем только те стены, которые находятся над полом (объёмные фасады)
	for pos in wall_layer.get_used_cells():
		var below := pos + Vector2i(0, 1)
		if _get_grid(below) == TileType.FLOOR:
			facade_cells.append(pos)

	# Используем terrain set для объёмных фасадов (source_id=0, terrain_set=0, terrain=0)
	if not facade_cells.is_empty():
		wall_volume_layer.set_cells_terrain_connect(facade_cells, 0, 0)


# ---------- КОЛОННЫ В УГЛАХ СТЕН ----------
# Используем wall_volume_layer как слой колонн (источник tileset с колоннами).
# В tileset есть источник 1 с колонной:
#  - верхняя часть: atlas (11, 0), alternative 1
#  - нижняя часть: atlas (11, 1), alternative 1
#
# В тест‑версии ставим ОДИН тип колонн во все типы внутренних углов.
func _build_pillars() -> void:
	# На всякий случай очищаем слой колонн
	wall_volume_layer.clear()

	# Берём прямоугольник, в котором реально есть стены
	var used: Rect2i = wall_layer.get_used_rect()

	# Чуть расширим, чтобы захватить клетки пола/пустоты вокруг
	used.position -= Vector2i(1, 1)
	used.size     += Vector2i(2, 2)

	for x in range(used.position.x, used.position.x + used.size.x):
		for y in range(used.position.y, used.position.y + used.size.y):
			var p := Vector2i(x, y)
			var corner := detect_outer_corner(p)

			match corner:
				CornerType.UL, CornerType.UR, CornerType.DL, CornerType.DR:
					# Тест‑версия: используем один и тот же тип колонны
					_place_column(p)
				CornerType.NONE:
					pass


func is_wall(p: Vector2i) -> bool:
	return _get_grid(p) == TileType.WALL


func detect_outer_corner(p: Vector2i) -> CornerType:
	# сама клетка должна быть НЕ стеной (пол/пусто)
	if is_wall(p):
		return CornerType.NONE

	var up    := is_wall(p + Vector2i(0, -1))
	var down  := is_wall(p + Vector2i(0, 1))
	var left  := is_wall(p + Vector2i(-1, 0))
	var right := is_wall(p + Vector2i(1, 0))

	var ul := is_wall(p + Vector2i(-1, -1))
	var ur := is_wall(p + Vector2i(1, -1))
	var dl := is_wall(p + Vector2i(-1, 1))
	var dr := is_wall(p + Vector2i(1, 1))

	# верхний левый угол комнаты
	if up and left and ul and not down:
		return CornerType.UL

	# верхний-правый
	if up and right and ur and not down:
		return CornerType.UR

	# нижний-левый
	if down and left and dl and not up:
		return CornerType.DL

	# нижний-правый
	if down and right and dr and not up:
		return CornerType.DR

	return CornerType.NONE


func _place_column(cell: Vector2i) -> void:
	# Нижняя часть колонны
	wall_volume_layer.set_cell(
		cell,
		1,                # source_id с колонной
		Vector2i(11, 1),  # нижняя часть
		1                 # alternative
	)

	# Верхняя часть колонны — тайл выше
	var top_cell := cell + Vector2i(0, -1)
	wall_volume_layer.set_cell(
		top_cell,
		1,                # тот же источник
		Vector2i(11, 0),  # верхняя часть
		1                 # alternative
	)
