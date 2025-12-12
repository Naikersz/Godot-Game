extends Node2D

## Tavern Interior Scene
## Внутренность таверны: TileMap + тот же HUD‑инвентарь.

@onready var tilemap: TileMap = $TileMapGround
@onready var player: Node2D = $Player
@onready var exit_area: Area2D = $TileMapGround/Area2D
@onready var fog_background: ColorRect = $BackgroundLayer/FogBackground

var _player_near_exit: bool = false
var _target_tile_color: Color = Color(0.15, 0.1, 0.08, 1.0)
var _current_fog_color: Color = Color(0.15, 0.1, 0.08, 1.0)
var _color_transition_speed: float = 0.5  # Скорость перехода цвета (меньше = медленнее)


func _ready() -> void:
	# Загружаем HUD с инвентарём (как в TownScene / DungeonScene)
	var hud_scene := preload("res://scenes/hud_scene.tscn")
	var hud = hud_scene.instantiate()
	add_child(hud)

	# Инициализируем цвета тумана
	_target_tile_color = Color(0.15, 0.1, 0.08, 1.0)
	_current_fog_color = Color(0.15, 0.1, 0.08, 1.0)

	set_process(true)


func _process(_delta: float) -> void:
	# Проверяем, стоит ли игрок достаточно близко к выходу
	_player_near_exit = false
	if player and exit_area:
		var dist := player.global_position.distance_to(exit_area.global_position)
		if dist <= 24.0:
			_player_near_exit = true

	if _player_near_exit and Input.is_action_just_pressed("ui_interact"):
		exit_to_town()
	
	# Получаем цвет тайла под персонажем
	if player and tilemap:
		_update_tile_color()
	
	# Плавный переход цвета тумана
	_update_fog_color(_delta)


func get_tilemap() -> TileMap:
	return tilemap


func exit_to_town() -> void:
	# Переход назад в город
	get_tree().change_scene_to_file("res://scenes/town_scene.tscn")




func _on_area_2d_body_entered(_body: Node2D) -> void:
	# Старый коллбек от Area2D — теперь не обязателен, оставлен на всякий случай
	pass


func _on_area_2d_body_exited(_body: Node2D) -> void:
	pass


func _update_tile_color() -> void:
	if not player or not tilemap:
		return
	
	var player_pos := player.global_position
	var tile_coords := tilemap.local_to_map(tilemap.to_local(player_pos))
	
	# Получаем данные тайла
	var source_id := tilemap.get_cell_source_id(0, tile_coords)
	if source_id == -1:
		# Если нет тайла, используем базовый цвет
		_target_tile_color = Color(0.15, 0.1, 0.08, 1.0)
		return
	
	var atlas_coords := tilemap.get_cell_atlas_coords(0, tile_coords)
	var tile_set := tilemap.tile_set
	if not tile_set:
		return
	
	var source := tile_set.get_source(source_id)
	if not source or not source is TileSetAtlasSource:
		return
	
	var atlas_source := source as TileSetAtlasSource
	var texture := atlas_source.texture
	if not texture:
		_target_tile_color = Color(0.15, 0.1, 0.08, 1.0)
		return
	
	# Получаем изображение текстуры и вычисляем средний цвет тайла
	var image: Image
	if texture is ImageTexture:
		image = (texture as ImageTexture).get_image()
	elif texture is CompressedTexture2D:
		# Для CompressedTexture2D нужно использовать другой подход
		# Пробуем получить через get_data()
		image = texture.get_image()
	
	if not image or image.is_empty():
		_target_tile_color = Color(0.15, 0.1, 0.08, 1.0)
		return
	
	var tile_size := tile_set.tile_size
	var tile_x := atlas_coords.x * tile_size.x
	var tile_y := atlas_coords.y * tile_size.y
	
	# Вычисляем средний цвет тайла (берем несколько точек)
	var total_r: float = 0.0
	var total_g: float = 0.0
	var total_b: float = 0.0
	var sample_count: int = 0
	
	var samples := [Vector2i(8, 8), Vector2i(24, 8), Vector2i(40, 8),
					Vector2i(8, 24), Vector2i(24, 24), Vector2i(40, 24),
					Vector2i(8, 40), Vector2i(24, 40), Vector2i(40, 40)]
	
	for sample_offset in samples:
		var sample_pos := Vector2i(tile_x + sample_offset.x, tile_y + sample_offset.y)
		if sample_pos.x >= 0 and sample_pos.x < image.get_width() and \
		   sample_pos.y >= 0 and sample_pos.y < image.get_height():
			var pixel_color := image.get_pixel(sample_pos.x, sample_pos.y)
			total_r += pixel_color.r
			total_g += pixel_color.g
			total_b += pixel_color.b
			sample_count += 1
	
	if sample_count > 0:
		var avg_color := Color(
			total_r / sample_count,
			total_g / sample_count,
			total_b / sample_count,
			1.0
		)
		
		# Определяем яркость для адаптации тумана
		var brightness := avg_color.get_luminance()
		
		# Если яркий тайл - светлеем, если темный - темнеем, если цветной - переходим в его цвет
		if brightness > 0.6:
			# Светлый тайл - светлеем, сохраняя коричневую палитру
			_target_tile_color = Color(
				clamp(avg_color.r * 0.7 + 0.3, 0.0, 1.0),
				clamp(avg_color.g * 0.7 + 0.25, 0.0, 1.0),
				clamp(avg_color.b * 0.7 + 0.2, 0.0, 1.0),
				1.0
			)
		elif brightness < 0.3:
			# Темный тайл - темнеем
			_target_tile_color = Color(
				clamp(avg_color.r * 0.8, 0.05, 1.0),
				clamp(avg_color.g * 0.8, 0.04, 1.0),
				clamp(avg_color.b * 0.8, 0.03, 1.0),
				1.0
			)
		else:
			# Цветной тайл - переходим в его цвет с небольшой коричневой примесью
			_target_tile_color = Color(
				clamp(avg_color.r * 0.8 + 0.2 * 0.15, 0.0, 1.0),
				clamp(avg_color.g * 0.8 + 0.2 * 0.1, 0.0, 1.0),
				clamp(avg_color.b * 0.8 + 0.2 * 0.08, 0.0, 1.0),
				1.0
			)
	else:
		_target_tile_color = Color(0.15, 0.1, 0.08, 1.0)


func _update_fog_color(delta: float) -> void:
	if not fog_background or not fog_background.material:
		return
	
	var material := fog_background.material as ShaderMaterial
	if not material:
		return
	
	# Плавная интерполяция текущего цвета к целевому
	_current_fog_color = _current_fog_color.lerp(_target_tile_color, _color_transition_speed * delta)
	
	# Обновляем цвета в шейдере
	material.set_shader_parameter("fog_color", _current_fog_color)
	
	# Светлая версия цвета (для fog_color_light)
	var light_color := Color(
		min(_current_fog_color.r * 1.4, 1.0),
		min(_current_fog_color.g * 1.4, 1.0),
		min(_current_fog_color.b * 1.4, 1.0),
		1.0
	)
	material.set_shader_parameter("fog_color_light", light_color)
