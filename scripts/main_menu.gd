extends Control

## Entspricht game.aw/scenes/main_menu.py

const PlayerResourceRes = preload("res://resources/player_resource.gd")
const InventoryResourceRes = preload("res://resources/inventory_resource.gd")

@onready var title_label: Label = $LabelMenu/Label
@onready var button_container: VBoxContainer = $Boxcontainer/MenuContainer/StartButton
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
		var save_path = Constants.get_save_path(slot)
		var player_res_path = save_path.path_join("player.tres")
		# Prüfe neue Resource-Datei
		if ResourceLoader.exists(player_res_path):
			return true
		# Fallback: Prüfe alte JSON-Datei (Migration)
		var legacy_player_path = Constants.get_player_path(slot)
		if FileAccess.file_exists(legacy_player_path):
			return true
	return false

## Callback: Spielstand laden
func _on_load_game_pressed():
	var load_menu_scene = preload("res://scenes/load_menu.tscn")
	get_tree().change_scene_to_packed(load_menu_scene)

## Callback: Neues Spiel starten
func _on_new_game_pressed():
	# Erstelle neuen Spielstand in Slot 1
	var slot = Constants.SAVE_SLOTS[0]
	var slot_path = Constants.get_save_path(slot)
	
	# Ordner für Save erstellen
	var dir = DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive("save/" + slot)
	else:
		print("❌ Fehler: Konnte user:// Verzeichnis nicht öffnen")
		return
	
	# PlayerResource erstellen
	var player_res := PlayerResourceRes.new()
	player_res.player_name = "Neuer Held"
	player_res.player_level = 1
	player_res.backpack_slots = 12
	player_res.equipped = {}
	player_res.gold = 0
	var player_res_path = slot_path.path_join("player.tres")
	var pres_err = ResourceSaver.save(player_res, player_res_path)
	if pres_err != OK:
		print("❌ Fehler: Konnte player.tres nicht erstellen: ", player_res_path, " err=", pres_err)
		return
	print("🆕 Neues Spiel gestartet in Slot 1!")
	print("📁 Gespeichert in: ", OS.get_user_data_dir().path_join("save").path_join(slot))
	
	# Leeres InventoryResource erstellen
	var inventory_res_path = slot_path.path_join("inventory.tres")
	var inv_res := InventoryResourceRes.new()
	var inv_err = ResourceSaver.save(inv_res, inventory_res_path)
	if inv_err != OK:
		print("⚠️ Konnte inventory.tres nicht erstellen: ", inventory_res_path, " err=", inv_err)
	
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
