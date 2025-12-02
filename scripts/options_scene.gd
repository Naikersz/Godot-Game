extends Control

const OPTIONS_PATH := "user://options.json"

var _options: Dictionary = {}

# --- ссылки на важные контролы ---
@onready var tab_container: TabContainer = $VBoxContainer/TabContainer

# Audio
@onready var master_slider: HSlider = $VBoxContainer/TabContainer/AudioTab/ScrollContainer/AudioVBox/MasterSlider
@onready var music_slider: HSlider = $VBoxContainer/TabContainer/AudioTab/ScrollContainer/AudioVBox/MusicSlider

# Video
@onready var fullscreen_check: CheckBox = $VBoxContainer/TabContainer/VideoTab/ScrollContainer/VideoVBox/FullscreenCheck
@onready var resolution_option: OptionButton = $VBoxContainer/TabContainer/VideoTab/ScrollContainer/VideoVBox/ResolutionOption

# Dev
@onready var dev_toggle: Button = $VBoxContainer/TabContainer/DevTab/ScrollContainer/DevVBox/DevToggleButton

# Back
@onready var back_button: Button = $VBoxContainer/ButtonContainer/BackButton

func _ready() -> void:
	_load_options()

	# --- Audio init ---
	master_slider.min_value = 0
	master_slider.max_value = 100
	master_slider.value = _options.get("master_volume", 80.0)
	master_slider.value_changed.connect(_on_master_volume_changed)

	music_slider.min_value = 0
	music_slider.max_value = 100
	music_slider.value = _options.get("music_volume", 70.0)
	music_slider.value_changed.connect(_on_music_volume_changed)

	# --- Video init ---
	var is_fullscreen = bool(_options.get("fullscreen", DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN))
	fullscreen_check.set_pressed_no_signal(is_fullscreen)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)

	_fill_resolutions()
	var res_index := int(_options.get("resolution_index", 1))
	if res_index >= 0 and res_index < resolution_option.item_count:
		resolution_option.select(res_index)
		_on_resolution_selected(res_index)
	resolution_option.item_selected.connect(_on_resolution_selected)

	# --- Dev ---
	DevSettings.set_dev_mode(bool(_options.get("dev_mode", DevSettings.dev_mode)))
	dev_toggle.text = "Dev-Mode: ON" if DevSettings.dev_mode else "Dev-Mode: OFF"
	dev_toggle.pressed.connect(_on_dev_toggle_pressed)

	# --- Back ---
	back_button.pressed.connect(_on_back_pressed)

# --- Audio логика ---
func _on_master_volume_changed(value: float) -> void:
	# value 0–100 -> переводим в dB
	var db = lerp(-40.0, 0.0, value / 100.0)
	var master_bus_index = AudioServer.get_bus_index("Master")
	if master_bus_index >= 0:
		AudioServer.set_bus_volume_db(master_bus_index, db)

	_options["master_volume"] = value
	_save_options()

func _on_music_volume_changed(value: float) -> void:
	var db = lerp(-40.0, 0.0, value / 100.0)
	var music_bus_index = AudioServer.get_bus_index("Music")
	if music_bus_index >= 0:
		AudioServer.set_bus_volume_db(music_bus_index, db)

	_options["music_volume"] = value
	_save_options()

# --- Video логика ---
func _on_fullscreen_toggled(pressed: bool) -> void:
	var mode = DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

	_options["fullscreen"] = pressed
	_save_options()

func _fill_resolutions() -> void:
	# примеры разрешений
	var resolutions = [
		Vector2i(1280, 720),
		Vector2i(1600, 900),
		Vector2i(1920, 1080)
	]
	for i in resolutions.size():
		resolution_option.add_item("%d x %d" % [resolutions[i].x, resolutions[i].y], i)

func _on_resolution_selected(index: int) -> void:
	var text = resolution_option.get_item_text(index)
	var parts = text.split(" x ")
	var w = int(parts[0])
	var h = int(parts[1])
	DisplayServer.window_set_size(Vector2i(w, h))

	_options["resolution_index"] = index
	_options["resolution"] = [w, h]
	_save_options()

# --- Dev логика ---
func _on_dev_toggle_pressed() -> void:
	DevSettings.set_dev_mode(not DevSettings.dev_mode)
	dev_toggle.text = "Dev-Mode: ON" if DevSettings.dev_mode else "Dev-Mode: OFF"

	_options["dev_mode"] = DevSettings.dev_mode
	_save_options()

# --- Back ---
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


func _load_options() -> void:
	_options = {}
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

	if json.data is Dictionary:
		_options = json.data


func _save_options() -> void:
	var file := FileAccess.open(OPTIONS_PATH, FileAccess.WRITE)
	if not file:
		return

	file.store_string(JSON.stringify(_options, "\t"))
	file.close()
