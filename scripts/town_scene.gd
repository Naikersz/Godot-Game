extends Node2D

## Town Scene
## Временный "город": TileMap + HUD‑инвентарь + модальное меню боя.

@onready var tilemap: TileMap = $TownTileMap/TileMapGround
@onready var door_area: Area2D = $TownTileMap/DoorArea
@onready var player: Node2D = $Player
var level_selection_modal: Control = null

var _player_near_door: bool = false


func _ready() -> void:
	# Загружаем HUD с инвентарём (как в DungeonScene)
	var hud_scene := preload("res://scenes/hud_scene.tscn")
	var hud = hud_scene.instantiate()
	add_child(hud)

	# LevelSelectionModal ist optional – nur holen, wenn vorhanden.
	level_selection_modal = get_node_or_null("LevelSelectionModal")

	set_process(true)


func _process(_delta: float) -> void:
	# Если открыт модальный выбор уровня – блокируем взаимодействия города
	if level_selection_modal and level_selection_modal.visible:
		return

	# Проверяем, стоит ли игрок достаточно близко к двери в таверну
	_player_near_door = false
	if player and door_area:
		var dist := player.global_position.distance_to(door_area.global_position)
		if dist <= 24.0:
			_player_near_door = true

	if _player_near_door and Input.is_action_just_pressed("ui_interact"):
		enter_house("tavern")


func get_tilemap() -> TileMap:
	# Вспомогательный метод, если понадобится доступ к карте из других скриптов
	return tilemap


func enter_house(_house_id: String) -> void:
	# Переход во внутренность таверны (временная реализация)
	get_tree().change_scene_to_file("res://scenes/tavern_interior.tscn")


func open_level_selection() -> void:
	# Открыть модальное окно выбора уровня подземелья
	if level_selection_modal:
		level_selection_modal.visible = true


func _on_door_body_entered(_body: Node) -> void:
	pass # Удалённый старый код двери, оставлен пустым на случай старых связей.


func _on_door_body_exited(_body: Node) -> void:
	pass


func _on_door_area_body_entered(_body: Node2D) -> void:
	pass


func _on_door_area_body_exited(_body: Node2D) -> void:
	pass
