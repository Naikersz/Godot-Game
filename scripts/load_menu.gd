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
	var dir = DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive("save")
	
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
		
		# Slot-Ordner sicherstellen
		var dir = DirAccess.open("user://")
		if dir:
			dir.make_dir_recursive("save/" + slot)
		
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
	
	# Убеждаемся, что файл инвентаря существует
	var slot = Constants.SAVE_SLOTS[slot_index]
	var save_path = Constants.get_save_path(slot)
	var inventory_path = save_path.path_join("global_inventory.json")
	
	if not FileAccess.file_exists(inventory_path):
		# Создаём папку и файл инвентаря, если их нет
		var dir = DirAccess.open("user://")
		if dir:
			dir.make_dir_recursive("save/" + slot)
		var inv_file = FileAccess.open(inventory_path, FileAccess.WRITE)
		if inv_file:
			inv_file.store_string(JSON.stringify([], "\t"))
			inv_file.close()
			print("📦 Создан файл инвентаря при загрузке: ", inventory_path)
	
	var town_scene = preload("res://scenes/town_scene.tscn")
	if town_scene:
		get_tree().change_scene_to_packed(town_scene)
	else:
		print("⚠️ Town-Szene nicht gefunden!")

func _on_new_game(slot_index: int):
	var slot = Constants.SAVE_SLOTS[slot_index]
	var slot_path = Constants.get_save_path(slot)
	
	# Создаем папку для сохранения
	var dir = DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive("save/" + slot)
	else:
		print("❌ Ошибка: не удалось открыть user:// директорию")
		return
	
	var player_data = {
		"name": "Neuer Held",
		"class_id": "warrior",
		"class_name": "Krieger",
		"level": 1,
		"experience": 0,
		"equipped": {}
	}
	
	var player_path = Constants.get_player_path(slot)
	var file = FileAccess.open(player_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(player_data, "\t"))
		file.close()
		print("🆕 Neuer Spielstand erstellt in Slot %d" % (slot_index + 1))
		print("📁 Сохранено в: ", OS.get_user_data_dir().path_join("save").path_join(slot))
	else:
		print("❌ Ошибка: не удалось создать файл player.json")
		print("   Путь: ", player_path)
		return
	
	# Создаем пустой inventory файл
	var inventory_path = slot_path.path_join("global_inventory.json")
	var inv_file = FileAccess.open(inventory_path, FileAccess.WRITE)
	if inv_file:
		inv_file.store_string(JSON.stringify([], "\t"))
		inv_file.close()
		print("📦 Создан пустой инвентарь")
	
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
