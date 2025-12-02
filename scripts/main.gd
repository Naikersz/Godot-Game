extends Node2D   # ← ЭТО ОБЯЗАТЕЛЬНО

const OPTIONS_PATH := "user://options.json"

func _ready() -> void:
	_apply_global_options()

	# Beim Start nur das Hauptmenü laden
	var menu_scene: PackedScene = preload("res://scenes/main_menu.tscn")
	var menu = menu_scene.instantiate()
	add_child(menu)   # self ist Node2D (Main) und kann das MainMenu als Kind aufnehmen.


func _apply_global_options() -> void:
	if not FileAccess.file_exists(OPTIONS_PATH):
		return

	var file := FileAccess.open(OPTIONS_PATH, FileAccess.READ)
	if not file:
		return

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_string) != OK:
		return

	if not (json.data is Dictionary):
		return

	var data: Dictionary = json.data

	# Audio
	var master_volume := float(data.get("master_volume", 80.0))
	var music_volume := float(data.get("music_volume", 70.0))

	var master_bus_index = AudioServer.get_bus_index("Master")
	if master_bus_index >= 0:
		var master_db = lerp(-40.0, 0.0, master_volume / 100.0)
		AudioServer.set_bus_volume_db(master_bus_index, master_db)

	var music_bus_index = AudioServer.get_bus_index("Music")
	if music_bus_index >= 0:
		var music_db = lerp(-40.0, 0.0, music_volume / 100.0)
		AudioServer.set_bus_volume_db(music_bus_index, music_db)

	# Video
	var fullscreen := bool(data.get("fullscreen", false))
	var mode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

	if data.has("resolution") and data["resolution"] is Array and data["resolution"].size() == 2:
		var w := int(data["resolution"][0])
		var h := int(data["resolution"][1])
		if w > 0 and h > 0:
			DisplayServer.window_set_size(Vector2i(w, h))

	# Dev-Mode
	if data.has("dev_mode"):
		DevSettings.set_dev_mode(bool(data["dev_mode"]))
