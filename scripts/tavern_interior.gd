extends Node2D

## Tavern Interior Scene
## Tavern interior: TileMap + same HUD inventory.

@onready var tilemap: TileMap = $InteriorTileMap/TileMapGround
@onready var player: Node2D = $Player
@onready var exit_area: Area2D = $InteriorTileMap/TileMapGround/Area2D

var _player_near_exit: bool = false


func _ready() -> void:
	# Load HUD with inventory (as in TownScene / DungeonScene)
	var hud_scene := preload("res://scenes/hud_scene.tscn")
	var hud = hud_scene.instantiate()
	add_child(hud)

	set_process(true)


func _process(_delta: float) -> void:
	# Check if player is close enough to exit
	_player_near_exit = false
	if player and exit_area:
		var dist := player.global_position.distance_to(exit_area.global_position)
		if dist <= 24.0:
			_player_near_exit = true

	if _player_near_exit and Input.is_action_just_pressed("ui_interact"):
		exit_to_town()


func get_tilemap() -> TileMap:
	return tilemap


func exit_to_town() -> void:
	# Transition back to town
	get_tree().change_scene_to_file("res://scenes/town_scene.tscn")




func _on_area_2d_body_entered(_body: Node2D) -> void:
	# Old callback from Area2D — no longer required, left for compatibility
	pass


func _on_area_2d_body_exited(_body: Node2D) -> void:
	pass
