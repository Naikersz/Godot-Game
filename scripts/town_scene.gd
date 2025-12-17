extends Node2D

## Town Scene
## Temporary "town": TileMap + HUD inventory + modal battle menu.

@onready var tilemap: TileMap = $TownTileMap/TileMapGround
@onready var door_area: Area2D = $TownTileMap/DoorArea
@onready var player: Node2D = $Player
var level_selection_modal: Control = null

var _player_near_door: bool = false


func _ready() -> void:
	# Load HUD with inventory (as in DungeonScene)
	var hud_scene := preload("res://scenes/hud_scene.tscn")
	var hud = hud_scene.instantiate()
	add_child(hud)

	# LevelSelectionModal is optional – only get if present
	level_selection_modal = get_node_or_null("LevelSelectionModal")

	set_process(true)


func _process(_delta: float) -> void:
	# If level selection modal is open – block town interactions
	if level_selection_modal and level_selection_modal.visible:
		return

	# Check if player is close enough to tavern door
	_player_near_door = false
	if player and door_area:
		var dist := player.global_position.distance_to(door_area.global_position)
		if dist <= 24.0:
			_player_near_door = true

	if _player_near_door and Input.is_action_just_pressed("ui_interact"):
		enter_house("tavern")


func get_tilemap() -> TileMap:
	# Helper method if map access is needed from other scripts
	return tilemap


func enter_house(_house_id: String) -> void:
	# Transition to tavern interior (temporary implementation)
	get_tree().change_scene_to_file("res://scenes/tavern_interior.tscn")


func open_level_selection() -> void:
	# Open modal window for dungeon level selection
	if level_selection_modal:
		level_selection_modal.visible = true


func _on_door_body_entered(_body: Node) -> void:
	pass # Removed old door code, left empty in case of old connections.


func _on_door_body_exited(_body: Node) -> void:
	pass


func _on_door_area_body_entered(_body: Node2D) -> void:
	pass


func _on_door_area_body_exited(_body: Node2D) -> void:
	pass
