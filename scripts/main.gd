extends Node2D   # ← ЭТО ОБЯЗАТЕЛЬНО

var _settings: SettingsStore = null

func _ready() -> void:
	# SettingsStore erstellen und laden
	_settings = SettingsStore.new()
	add_child(_settings)
	_settings.load_settings()
	
	_apply_global_options()

	# Beim Start nur das Hauptmenü laden
	var menu_scene: PackedScene = preload("res://scenes/main_menu.tscn")
	var menu = menu_scene.instantiate()
	add_child(menu)   # self ist Node2D (Main) und kann das MainMenu als Kind aufnehmen.


func _apply_global_options() -> void:
	if _settings == null:
		return
	
	# Audio
	var master_volume := _settings.master_volume
	var music_volume := _settings.music_volume

	var master_bus_index = AudioServer.get_bus_index("Master")
	if master_bus_index >= 0:
		var master_db = lerp(-40.0, 0.0, master_volume / 100.0)
		AudioServer.set_bus_volume_db(master_bus_index, master_db)

	var music_bus_index = AudioServer.get_bus_index("Music")
	if music_bus_index >= 0:
		var music_db = lerp(-40.0, 0.0, music_volume / 100.0)
		AudioServer.set_bus_volume_db(music_bus_index, music_db)

	# Video
	var fullscreen := _settings.fullscreen
	var mode = DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)
	
	# Resolution aus Index (falls vorhanden)
	# Note: resolution_index wird in options_scene.gd verwendet
	# Hier können wir die Auflösung basierend auf dem Index setzen, falls nötig

	# Dev-Mode
	DevSettings.set_dev_mode(_settings.dev_mode)
