extends Control

## Level Selection Scene
## Entspricht game.aw/scenes/level_selection_scene.py

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var categories_container: HBoxContainer = $VBoxContainer/CategoriesContainer
@onready var feld_label: Label = $VBoxContainer/CategoriesContainer/FeldLabel
@onready var cave_label: Label = $VBoxContainer/CategoriesContainer/CaveLabel
@onready var buttons_container: HBoxContainer = $VBoxContainer/ButtonsContainer
@onready var feld_buttons_container: VBoxContainer = $VBoxContainer/ButtonsContainer/FeldButtonsContainer
@onready var cave_buttons_container: VBoxContainer = $VBoxContainer/ButtonsContainer/CaveButtonsContainer
@onready var back_button: Button = $VBoxContainer/BackButton

var slot_index: int = 0

func _ready():
	slot_index = Constants.current_slot_index
	create_buttons()
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	else:
		print("⚠️ BackButton nicht gefunden in Level Selection!")

func create_buttons():
	# Feld-Buttons (links)
	for i in range(1, 6):
		var btn = Button.new()
		btn.text = "Feld %d" % i
		btn.custom_minimum_size = Vector2(200, 50)
		btn.pressed.connect(_on_feld_button_pressed.bind(i))
		feld_buttons_container.add_child(btn)
	
	# Cave-Buttons (rechts)
	for i in range(1, 6):
		var btn = Button.new()
		btn.text = "Cave %d" % i
		btn.custom_minimum_size = Vector2(200, 50)
		btn.pressed.connect(_on_cave_button_pressed.bind(i))
		cave_buttons_container.add_child(btn)

func _on_feld_button_pressed(level_number: int):
	start_battle("Feld", level_number)

func _on_cave_button_pressed(level_number: int):
	start_battle("Cave", level_number)

func start_battle(level_type: String, level_number: int):
	print("⚔️ %s %d gestartet!" % [level_type, level_number])
	# Level-Informationen in Constants speichern
	Constants.current_level_type = level_type
	Constants.current_level_number = level_number
	
	# Lade die LevelTown-Szene, die Dungeon + Player enthält.
	get_tree().call_deferred("change_scene_to_file", "res://scenes/level_town.tscn")

func _on_back_pressed():
	print("Zurück-Button gedrückt (Level Selection)")
	get_tree().call_deferred("change_scene_to_file", "res://scenes/town_scene.tscn")
