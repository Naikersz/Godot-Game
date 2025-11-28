extends Control

## Town Scene
## Entspricht game.aw/scenes/town_scene.py

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var button_container: VBoxContainer = $VBoxContainer/ButtonContainer
@onready var inventory_button: Button = $VBoxContainer/ButtonContainer/InventoryButton
@onready var smith_button: Button = $VBoxContainer/ButtonContainer/SmithButton
@onready var shop_button: Button = $VBoxContainer/ButtonContainer/ShopButton
@onready var fight_button: Button = $VBoxContainer/ButtonContainer/FightButton
@onready var exit_button: Button = $VBoxContainer/ButtonContainer/ExitButton

func _ready():
	# Slot-Index aus Constants lesen
	var slot_index = Constants.current_slot_index
	# Button-Callbacks verbinden
	inventory_button.pressed.connect(_on_inventory_pressed)
	smith_button.pressed.connect(_on_smith_pressed)
	shop_button.pressed.connect(_on_shop_pressed)
	fight_button.pressed.connect(_on_fight_pressed)
	exit_button.pressed.connect(_on_exit_pressed)

func _on_inventory_pressed():
	var inventory_scene = preload("res://scenes/inventory_scene.tscn")
	if inventory_scene:
		get_tree().change_scene_to_packed(inventory_scene)
	else:
		print("⚠️ Inventory-Szene nicht gefunden!")

func _on_smith_pressed():
	print("🛠 Schmied geöffnet!")

func _on_shop_pressed():
	print("🛒 Shop geöffnet!")

func _on_fight_pressed():
	print("⚔️ Kampf gestartet!")
	var level_selection = preload("res://scenes/level_selection_scene.tscn")
	if level_selection:
		get_tree().change_scene_to_packed(level_selection)
	else:
		print("⚠️ Level Selection-Szene nicht gefunden!")

func _on_exit_pressed():
	print("⬅ Zurück zum Hauptmenü aus Town-Szene")
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main_menu.tscn")
