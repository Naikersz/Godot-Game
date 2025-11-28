extends Node2D   # ← ЭТО ОБЯЗАТЕЛЬНО

func _ready() -> void:
	var level_scene: PackedScene = preload("res://scenes/level_town.tscn")
	var level = level_scene.instantiate()
	add_child(level)   # ← здесь self = Node2D, у него есть add_child()
