extends Control

## Mirrors game.aw/scenes/main_menu.py

const PlayerResourceRes = preload("res://resources/player_resource.gd")
const InventoryResourceRes = preload("res://resources/inventory_resource.gd")

@onready var title_label: Label = $LabelMenu/Label
@onready var button_container: VBoxContainer = $BoxContainer/MenuContainer
@onready var new_game_button: Button = $BoxContainer/MenuContainer/StartButton
@onready var load_game_button: Button = $BoxContainer/MenuContainer/LoadGameButton
@onready var options_button: Button = $BoxContainer/MenuContainer/OptionsButton
@onready var quit_button: Button = $BoxContainer/MenuContainer/ExitButton

var has_saves: bool = false

func _ready():
	_update_ui_texts()
	
	# Check if any savegame exists
	has_saves = any_save_exists()
	
	# Show either "New Game" or "Load Game" depending on save status
	if has_saves:
		load_game_button.visible = true
		new_game_button.visible = false
	else:
		load_game_button.visible = false
		new_game_button.visible = true
	
	# Connect button callbacks
	load_game_button.pressed.connect(_on_load_game_pressed)
	new_game_button.pressed.connect(_on_new_game_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_pressed)

func _update_ui_texts() -> void:
	"""Updates all UI texts that use tr() - called when language changes"""
	# Set button texts with tr()
	if new_game_button:
		new_game_button.text = tr("Start")
	if load_game_button:
		load_game_button.text = tr("Load Game")
	if options_button:
		options_button.text = tr("Options")
	if quit_button:
		quit_button.text = tr("Exit")

## Returns true if at least one save slot has a player.tres
func any_save_exists() -> bool:
	for slot in Constants.SAVE_SLOTS:
		var save_path = Constants.get_save_path(slot)
		var player_res_path = save_path.path_join("player.tres")
		# Check new resource-based save file
		if ResourceLoader.exists(player_res_path):
			return true
	return false

## Callback: load existing savegame
func _on_load_game_pressed():
	var load_menu_scene = preload("res://scenes/load_menu.tscn")
	get_tree().change_scene_to_packed(load_menu_scene)

## Callback: start a new game
func _on_new_game_pressed():
	# Create a new save in slot 1
	var slot = Constants.SAVE_SLOTS[0]
	var slot_path = Constants.get_save_path(slot)
	
	# Create save directory
	var dir = DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive("save/" + slot)
	else:
		print("❌ Error: could not open user:// directory")
		return
	
	# Create PlayerResource
	var player_res := PlayerResourceRes.new()
	player_res.player_name = tr("New Hero")
	player_res.player_level = 1
	player_res.backpack_slots = 12
	player_res.equipped = {}
	player_res.gold = 0
	var player_res_path = slot_path.path_join("player.tres")
	var pres_err := ResourceSaver.save(player_res, player_res_path)
	if pres_err != OK:
		print("❌ Error: could not create player.tres at: ", player_res_path, " err=", pres_err)
		return
	print("🆕 New game started in slot 1!")
	print("📁 Saved at: ", OS.get_user_data_dir().path_join("save").path_join(slot))
	
	# Create empty InventoryResource
	var inventory_res_path = slot_path.path_join("inventory.tres")
	var inv_res := InventoryResourceRes.new()
	var inv_err := ResourceSaver.save(inv_res, inventory_res_path)
	if inv_err != OK:
		print("⚠️ Could not create inventory.tres at: ", inventory_res_path, " err=", inv_err)
	
	# Set current slot index
	Constants.current_slot_index = 0
	
	# Switch to town scene
	var town_scene = preload("res://scenes/town_scene.tscn")
	if town_scene:
		get_tree().change_scene_to_packed(town_scene)
	else:
		print("⚠️ Town scene not found!")

## Callback: open options
func _on_options_pressed():
	var options_scene = preload("res://scenes/options_scene.tscn")
	if options_scene:
		get_tree().change_scene_to_packed(options_scene)
	else:
		print("⚠️ Options scene not found!")

## Callback: quit game
func _on_quit_pressed():
	get_tree().quit()
