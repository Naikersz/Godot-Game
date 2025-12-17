extends Control

## Level Selection Scene
## Entspricht game.aw/scenes/level_selection_scene.py

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var categories_container: HBoxContainer = $VBoxContainer/CategoriesContainer
@onready var forest_label: Label = $VBoxContainer/CategoriesContainer/ForestLabel
@onready var cave_label: Label = $VBoxContainer/CategoriesContainer/CaveLabel
@onready var buttons_container: HBoxContainer = $VBoxContainer/ButtonsContainer
@onready var forest_buttons_container: VBoxContainer = $VBoxContainer/ButtonsContainer/ForestButtonsContainer
@onready var cave_buttons_container: VBoxContainer = $VBoxContainer/ButtonsContainer/CaveButtonsContainer
@onready var back_button: Button = $VBoxContainer/BackButton

var slot_index: int = 0

func _ready():
	_update_ui_texts()
	
	slot_index = Constants.current_slot_index
	create_buttons()
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	else:
		print("⚠️ BackButton not found in Level Selection!")

func _update_ui_texts() -> void:
	"""Updates all UI texts that use tr() - called when language changes"""
	# Set UI texts with tr()
	if title_label:
		title_label.text = tr("Level Selection")
	if forest_label:
		forest_label.text = tr("Forest")
	if cave_label:
		cave_label.text = tr("Cave")
	if back_button:
		back_button.text = tr("Back")
	
	# Recreate buttons to update their texts
	create_buttons()

func create_buttons():
	# Remove existing buttons first to avoid duplicates
	if forest_buttons_container:
		for child in forest_buttons_container.get_children():
			child.queue_free()
	if cave_buttons_container:
		for child in cave_buttons_container.get_children():
			child.queue_free()
	
	# Forest buttons (left side)
	for i in range(1, 6):
		var btn = Button.new()
		btn.text = tr("Forest %d") % i
		btn.custom_minimum_size = Vector2(200, 50)
		btn.pressed.connect(_on_forest_button_pressed.bind(i))
		forest_buttons_container.add_child(btn)
	
	# Cave buttons (right side)
	for i in range(1, 6):
		var btn = Button.new()
		btn.text = tr("Cave %d") % i
		btn.custom_minimum_size = Vector2(200, 50)
		btn.pressed.connect(_on_cave_button_pressed.bind(i))
		cave_buttons_container.add_child(btn)

func _on_forest_button_pressed(level_number: int):
	start_battle("Forest", level_number)

func _on_cave_button_pressed(level_number: int):
	start_battle("Cave", level_number)

func start_battle(level_type: String, level_number: int):
	print("⚔️ %s %d started!" % [level_type, level_number])
	# Store level information in Constants
	Constants.current_level_type = level_type
	Constants.current_level_number = level_number
	
	# Load the dungeon scene, which contains dungeon + player
	get_tree().call_deferred("change_scene_to_file", "res://scenes/dungeon_scene.tscn")

func _on_back_pressed():
	print("Back button pressed (Level Selection)")
	# If this scene is the root (loaded directly) — return to TownScene.
	# If it's instantiated as a modal window inside another scene (HUD),
	# then simply hide it.
	if self == get_tree().current_scene:
		get_tree().call_deferred("change_scene_to_file", "res://scenes/town_scene.tscn")
	else:
		visible = false
