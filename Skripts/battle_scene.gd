extends Control

## Battle Scene - Vereinfachte Version
## Entspricht game.aw/scenes/battle_scene.py (Basis-Funktionalität)

const LootGeneratorScript = preload("res://core/loot_generator.gd")

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var back_button: Button = $VBoxContainer/BackButton
@onready var enemies_container: Control = $EnemiesContainer

var slot_index: int = 0
var level_type: String = "Feld"
var level_number: int = 1
var enemies: Array = []
var hovered_enemy_index: int = -1
var player_stats: Dictionary = {}
var loot_generator

func _ready():
	slot_index = Constants.current_slot_index
	level_type = Constants.current_level_type
	level_number = Constants.current_level_number
	
	loot_generator = LootGeneratorScript.new()
	load_player_stats()
	generate_enemies()
	create_enemy_buttons()
	
	title_label.text = "%s %d" % [level_type, level_number]
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	else:
		print("⚠️ BackButton nicht gefunden in Battle Scene!")

func load_player_stats():
	# Vereinfachte Player-Stats laden
	var slot = Constants.SAVE_SLOTS[slot_index]
	var player_path = Constants.get_player_path(slot)
	
	if FileAccess.file_exists(player_path):
		var file = FileAccess.open(player_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var json_obj = JSON.new()
			if json_obj.parse(json_string) == OK:
				var player_data = json_obj.data
				player_stats = player_data.get("stats", {})
				if player_stats.is_empty():
					player_stats = player_data.get("total_stats", {})

func generate_enemies():
	# Vereinfachte Gegner-Generierung
	# TODO: Vollständige Enemy-Generator-Logik portieren
	enemies = []
	for i in range(3):  # 3 Gegner als Beispiel
		var enemy = {
			"name": "Gegner %d" % (i + 1),
			"level": 1,
			"hp": 50,
			"max_hp": 50,
			"damage": 5,
			"defense": 2,
			"x": randf_range(100, Constants.WIDTH - 100),
			"y": randf_range(100, Constants.HEIGHT - 100)
		}
		enemies.append(enemy)

func create_enemy_buttons():
	# Entferne alte Buttons
	for child in enemies_container.get_children():
		child.queue_free()
	
	# Erstelle Buttons für jeden Gegner
	for i in range(enemies.size()):
		var enemy = enemies[i]
		var btn = Button.new()
		btn.text = enemy.get("name", "Gegner")
		btn.position = Vector2(enemy.get("x", 100), enemy.get("y", 100))
		btn.custom_minimum_size = Vector2(100, 50)
		btn.pressed.connect(_on_enemy_clicked.bind(i))
		enemies_container.add_child(btn)

func _on_enemy_clicked(enemy_index: int):
	if enemy_index >= enemies.size():
		return
	
	var enemy = enemies[enemy_index]
	
	# Berechne Schaden
	var player_damage = player_stats.get("damage", 10)
	var enemy_defense = enemy.get("defense", 0)
	var actual_damage = max(1, player_damage - enemy_defense)
	
	# Wende Schaden an
	var current_hp = enemy.get("hp", 0)
	var new_hp = max(0, current_hp - actual_damage)
	enemy["hp"] = new_hp
	
	print("⚔️ Kampf: %d Schaden - %d Verteidigung = %d Schaden" % [player_damage, enemy_defense, actual_damage])
	print("   Gegner HP: %d -> %d" % [current_hp, new_hp])
	
	# Prüfe ob Gegner tot ist
	if new_hp <= 0:
		print("   ✝️ Gegner '%s' ist gestorben!" % enemy.get("name", "Unbekannt"))
		# Loot generieren
		_handle_enemy_death(enemy)
		# Entferne Gegner
		enemies.remove_at(enemy_index)
		create_enemy_buttons()
		
		# Wenn alle Gegner tot sind
		if enemies.is_empty():
			print("🎉 Alle Gegner besiegt!")

func _handle_enemy_death(enemy: Dictionary):
	## Versucht einen Itemdrop zu generieren und speichert ihn im Inventar.
	var monster_level = enemy.get("level", 1)
	var loot_item = loot_generator.generate_loot(monster_level)
	
	if loot_item.is_empty():
		return
	
	_add_item_to_inventory(loot_item)
	var item_name = loot_item.get("name", loot_item.get("id", "Item"))
	print("💰 Loot erhalten: %s" % item_name)

func _add_item_to_inventory(item: Dictionary):
	## Speichert ein Item im globalen Inventar des aktuellen Slots.
	var slot = Constants.SAVE_SLOTS[slot_index]
	var save_path = Constants.get_save_path(slot)
	DirAccess.make_dir_recursive_absolute(save_path)
	var inventory_path = save_path.path_join("global_inventory.json")
	
	var inventory: Array = []
	if FileAccess.file_exists(inventory_path):
		var file = FileAccess.open(inventory_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var json_obj = JSON.new()
			if json_obj.parse(json_string) == OK:
				inventory = json_obj.data
	
	inventory.append(item)
	
	var file = FileAccess.open(inventory_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(inventory, "\t"))
		file.close()

func _on_back_pressed():
	print("Zurück-Button gedrückt (Battle)")
	get_tree().call_deferred("change_scene_to_file", "res://scenes/level_selection_scene.tscn")
