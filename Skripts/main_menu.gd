extends Control

## Hauptmenü-Szene
## Entspricht game.aw/scenes/main_menu.py

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var button_container: VBoxContainer = $VBoxContainer/ButtonContainer
@onready var load_game_button: Button = $VBoxContainer/ButtonContainer/LoadGameButton
@onready var new_game_button: Button = $VBoxContainer/ButtonContainer/NewGameButton
@onready var options_button: Button = $VBoxContainer/ButtonContainer/OptionsButton
@onready var quit_button: Button = $VBoxContainer/ButtonContainer/QuitButton

var has_saves: bool = false

func _ready():
	# Prüfe ob Saves existieren
	has_saves = any_save_exists()
	
	# Buttons je nach Save-Status anzeigen
	if has_saves:
		load_game_button.visible = true
		new_game_button.visible = false
	else:
		load_game_button.visible = false
		new_game_button.visible = true
	
	# Button-Callbacks verbinden
	load_game_button.pressed.connect(_on_load_game_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

## Prüft ob mindestens ein Save existiert
func any_save_exists() -> bool:
	for slot in Constants.SAVE_SLOTS:
		var player_path = Constants.get_player_path(slot)
		if FileAccess.file_exists(player_path):
			return true
	return false

## Callback: Spielstand laden
func _on_load_game_pressed():
	var load_menu_scene = preload("res://scenes/load_menu.tscn")
	get_tree().change_scene_to_packed(load_menu_scene)

## Callback: Neues Spiel starten
func _on_new_game_pressed():
	# Erstelle neuen Spielstand in Slot 1
	var slot_path = Constants.get_save_path(Constants.SAVE_SLOTS[0])
	DirAccess.make_dir_recursive_absolute(slot_path)
	
	var player_data = {
		"name": "Neuer Held",
		"class_id": "warrior",
		"class_name": "Krieger",
		"level": 1,
		"experience": 0
	}
	
	var player_path = Constants.get_player_path(Constants.SAVE_SLOTS[0])
	var file = FileAccess.open(player_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(player_data, "\t"))
		file.close()
		print("🆕 Neues Spiel gestartet in Slot 1!")
	
	# Slot-Index setzen
	Constants.current_slot_index = 0
	
	# Wechsle zur Town-Szene
	var town_scene = preload("res://scenes/town_scene.tscn")
	if town_scene:
		get_tree().change_scene_to_packed(town_scene)
	else:
		print("⚠️ Town-Szene nicht gefunden!")

## Callback: Optionen
func _on_options_pressed():
	var options_scene = preload("res://scenes/options_scene.tscn")
	if options_scene:
		get_tree().change_scene_to_packed(options_scene)
	else:
		print("⚠️ Options-Szene nicht gefunden!")

## Callback: Spiel beenden
func _on_quit_pressed():
	get_tree().quit()
