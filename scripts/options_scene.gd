extends Control

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
	# --- Audio init ---
	master_slider.min_value = 0
	master_slider.max_value = 100
	master_slider.value = 80   # тут можешь подгружать своё сохранение
	master_slider.value_changed.connect(_on_master_volume_changed)

	music_slider.min_value = 0
	music_slider.max_value = 100
	music_slider.value = 70
	music_slider.value_changed.connect(_on_music_volume_changed)

	# --- Video init ---
	var is_fullscreen = DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
	fullscreen_check.set_pressed_no_signal(is_fullscreen)
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)

	_fill_resolutions()
	resolution_option.item_selected.connect(_on_resolution_selected)

	# --- Dev ---
	dev_toggle.text = "Dev-Modus: AN" if DevSettings.dev_mode else "Dev-Modus: AUS"
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
	# тут же можешь сохранять значение в свой Settings/DevSettings

func _on_music_volume_changed(value: float) -> void:
	var db = lerp(-40.0, 0.0, value / 100.0)
	var music_bus_index = AudioServer.get_bus_index("Music")
	if music_bus_index >= 0:
		AudioServer.set_bus_volume_db(music_bus_index, db)

# --- Video логика ---
func _on_fullscreen_toggled(pressed: bool) -> void:
	var mode = DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

func _fill_resolutions() -> void:
	# примеры разрешений
	var resolutions = [
		Vector2i(1280, 720),
		Vector2i(1600, 900),
		Vector2i(1920, 1080)
	]
	for i in resolutions.size():
		resolution_option.add_item("%d x %d" % [resolutions[i].x, resolutions[i].y], i)
	# можно выбрать текущую по сохранённым настройкам

func _on_resolution_selected(index: int) -> void:
	var text = resolution_option.get_item_text(index)
	var parts = text.split(" x ")
	var w = int(parts[0])
	var h = int(parts[1])
	DisplayServer.window_set_size(Vector2i(w, h))

# --- Dev логика ---
func _on_dev_toggle_pressed() -> void:
	DevSettings.set_dev_mode(not DevSettings.dev_mode)
	dev_toggle.text = "Dev-Modus: AN" if DevSettings.dev_mode else "Dev-Modus: AUS"

# --- Back ---
func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
