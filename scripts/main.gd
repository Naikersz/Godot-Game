extends Node2D   # ← THIS IS REQUIRED

var _settings: SettingsStore = null

func _ready() -> void:
	# IMPORTANT: Set language FIRST before anything else
	# This prevents Godot from using system locale
	TranslationServer.set_locale("en")  # Default fallback
	
	# Create and load SettingsStore
	_settings = SettingsStore.new()
	add_child(_settings)
	_settings.load_settings()
	
	# Initialize translation system (this will override with saved language)
	_setup_translations()
	
	_apply_global_options()

	# On start, only load the main menu
	var menu_scene: PackedScene = preload("res://scenes/main_menu.tscn")
	var menu = menu_scene.instantiate()
	add_child(menu)   # self is Node2D (Main) and can take MainMenu as a child.


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
	
	# Resolution from index (if available)
	# Note: resolution_index is used in options_scene.gd
	# Here we can set the resolution based on the index if needed

	# Dev-Mode
	DevSettings.set_dev_mode(_settings.dev_mode)
	
	# Language
	_setup_translations()


func _setup_translations() -> void:
	"""Loads and applies translation files based on settings"""
	if _settings == null:
		return
	
	# Load translation CSV file by parsing it directly
	var translation_file := "res://translations.csv"
	var translation: Translation = Translation.new()
	
	var file := FileAccess.open(translation_file, FileAccess.READ)
	if file == null:
		print("⚠️ Main: Could not open translation file: ", translation_file)
		return
	
	# Read CSV header
	var header := file.get_csv_line()
	if header.size() < 4:
		print("⚠️ Main: Invalid CSV header in translation file")
		file.close()
		return
	
	var lang_codes := [header[1], header[2], header[3]]  # en, de, ru
	print("✓ Main: Loading translations for languages: ", lang_codes)
	
	# Read data lines
	var line_count := 0
	while not file.eof_reached():
		var line := file.get_csv_line()
		if line.size() >= 4 and line[0] != "keys" and line[0] != "":  # Skip header and empty lines
			var key := line[0]
			for i in range(1, 4):
				if i - 1 < lang_codes.size() and line[i] != "":
					translation.add_message(key, line[i], lang_codes[i - 1])
			line_count += 1
	
	file.close()
	
	if line_count > 0:
		TranslationServer.add_translation(translation)
		print("✓ Main: Translation file loaded (", line_count, " entries)")
	else:
		print("⚠️ Main: No translations found in file")
	
	# Set language from settings (default to "en" if not set)
	var lang := "en"
	if _settings:
		lang = _settings.language if _settings.language != "" else "en"
		# Ensure language is valid
		if lang != "en" and lang != "de" and lang != "ru":
			print("⚠️ Main: Invalid language code '", lang, "', defaulting to 'en'")
			lang = "en"
	
	TranslationServer.set_locale(lang)
	print("✓ Main: Language set to: ", lang)
