extends Control

## Load Menu Szene
## Entspricht game.aw/scenes/load_menu.py

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var slots_container: VBoxContainer = $VBoxContainer/SlotsContainer
@onready var back_button: Button = $VBoxContainer/BackButton

var slot_buttons: Array[Button] = []
var slots_data: Array = []

func _ready():
	# Save-Ordner sicherstellen
	var save_root = Constants.get_save_root()
	DirAccess.make_dir_recursive_absolute(save_root)
	
	build_menu()
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	else:
		print("⚠️ BackButton nicht gefunden in Load Menu!")

func build_menu():
	# Alte Buttons entfernen
	for child in slots_container.get_children():
		child.queue_free()
	
	slot_buttons.clear()
	slots_data.clear()
	
	# Für jeden Slot einen Button erstellen
	for i in range(Constants.SAVE_SLOTS.size()):
		var slot = Constants.SAVE_SLOTS[i]
		var slot_path = Constants.get_save_path(slot)
		
		# Slot-Ordner sicherstellen
		DirAccess.make_dir_recursive_absolute(slot_path)
		
		# Player-Daten laden (Slot-Name übergeben)
		var player_data = load_player_data(slot)
		slots_data.append(player_data)
		
		# Button erstellen
		var slot_button = Button.new()
		slot_button.custom_minimum_size = Vector2(700, 140)
		
		if player_data:
			slot_button.text = "%d. Spiel laden" % (i + 1)
			slot_button.pressed.connect(_on_load_slot.bind(i))
		else:
			slot_button.text = "Neues Spiel starten"
			slot_button.pressed.connect(_on_new_game.bind(i))
		
		slots_container.add_child(slot_button)
		slot_buttons.append(slot_button)

func load_player_data(slot_name: String) -> Dictionary:
	var player_path = Constants.get_player_path(slot_name)
	
	if not FileAccess.file_exists(player_path):
		return {}
	
	var file = FileAccess.open(player_path, FileAccess.READ)
	if not file:
		return {}
	
	var json_string = file.get_as_text()
	file.close()
	
	var json_obj = JSON.new()
	var parse_result = json_obj.parse(json_string)
	
	if parse_result != OK:
		return {}
	
	var data = json_obj.data
	return {
		"name": data.get("name", "Unbekannt"),
		"level": data.get("level", 1),
		"class_name": data.get("class_name", "???")
	}

func _on_load_slot(slot_index: int):
	Constants.current_slot_index = slot_index
	var town_scene = preload("res://scenes/town_scene.tscn")
	if town_scene:
		get_tree().change_scene_to_packed(town_scene)
	else:
		print("⚠️ Town-Szene nicht gefunden!")

func _on_new_game(slot_index: int):
	var slot = Constants.SAVE_SLOTS[slot_index]
	var slot_path = Constants.get_save_path(slot)
	DirAccess.make_dir_recursive_absolute(slot_path)
	
	var player_data = {
		"name": "Neuer Held",
		"class_id": "warrior",
		"class_name": "Krieger",
		"level": 1,
		"experience": 0
	}
	
	var player_path = Constants.get_player_path(slot)
	var file = FileAccess.open(player_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(player_data, "\t"))
		file.close()
		print("🆕 Neuer Spielstand erstellt in Slot %d" % (slot_index + 1))
	
	# Slot-Index setzen
	Constants.current_slot_index = slot_index
	
	# Menü neu aufbauen
	build_menu()
	
	# Zur Town-Szene wechseln
	var town_scene = preload("res://scenes/town_scene.tscn")
	if town_scene:
		get_tree().change_scene_to_packed(town_scene)
	else:
		print("⚠️ Town-Szene nicht gefunden!")

func _on_back_pressed():
	print("Zurück-Button gedrückt (Load Menu)")
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main_menu.tscn")
