extends Node2D

## Script für die Dungeon-Szene.
## Hier kann später Logik für UI, Pausenmenü usw. ergänzt werden.

func _ready() -> void:
	var hud_scene = preload("res://scenes/hud_scene.tscn")
	var hud = hud_scene.instantiate()
	add_child(hud)
