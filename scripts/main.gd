extends Node2D   # ← ЭТО ОБЯЗАТЕЛЬНО

func _ready() -> void:
	# Beim Start nur das Hauptmenü laden
	var menu_scene: PackedScene = preload("res://scenes/main_menu.tscn")
	var menu = menu_scene.instantiate()
	add_child(menu)   # self ist Node2D (Main) und kann das MainMenu als Kind aufnehmen.
