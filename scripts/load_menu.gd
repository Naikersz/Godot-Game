extends Control

## Load Menu scene
## Mirrors game.aw/scenes/load_menu.py

const PlayerResourceRes = preload("res://resources/player_resource.gd")
const InventoryResourceRes = preload("res://resources/inventory_resource.gd")

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var slots_container: VBoxContainer = $VBoxContainer/SlotsContainer
@onready var back_button: Button = $VBoxContainer/BackButton
@onready var confirm_dialog: ConfirmationDialog = get_node_or_null("DeleteConfirmDialog")

var slot_buttons: Array[Button] = []
var slots_data: Array = []
var _pending_delete_slot: int = -1

func _ready():
	# Ensure save folder exists
	var dir = DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive("save")
	
	if not confirm_dialog:
		confirm_dialog = ConfirmationDialog.new()
		confirm_dialog.name = "DeleteConfirmDialog"
		confirm_dialog.dialog_text = "Delete this save?"
		add_child(confirm_dialog)
	confirm_dialog.get_ok_button().text = "Delete"
	confirm_dialog.get_cancel_button().text = "Cancel"
	confirm_dialog.canceled.connect(_on_delete_canceled)
	confirm_dialog.confirmed.connect(_on_delete_confirmed)
	
	build_menu()
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	else:
		print("⚠️ BackButton nicht gefunden in Load Menu!")

func build_menu():
	# Remove old buttons
	for child in slots_container.get_children():
		child.queue_free()
	
	slot_buttons.clear()
	slots_data.clear()
	
	# Create a button for each slot
	for i in range(Constants.SAVE_SLOTS.size()):
		var slot = Constants.SAVE_SLOTS[i]
		
		# Ensure slot folder exists
		var dir = DirAccess.open("user://")
		if dir:
			dir.make_dir_recursive("save/" + slot)
		
		# Load player data (pass slot name)
		var player_data = load_player_data(slot)
		slots_data.append(player_data)
		
		# Container for slot button + delete
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.theme = theme
		slots_container.add_child(row)
		
		# Create main button
		var slot_button = Button.new()
		slot_button.custom_minimum_size = Vector2(700, 140)
		slot_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		if player_data:
			var hero_name: String = String(player_data.get("name", "Hero"))
			var hero_level: int = int(player_data.get("level", 1))
			slot_button.text = "Load %s (Lv %d)" % [hero_name, hero_level]
			slot_button.pressed.connect(_on_load_slot.bind(i))
		else:
			slot_button.text = "Start new game"
			slot_button.pressed.connect(_on_new_game.bind(i))
		
		row.add_child(slot_button)
		slot_buttons.append(slot_button)
		
		# Show delete button only if a save exists
		if player_data:
			var delete_button := Button.new()
			delete_button.text = "Delete"
			delete_button.custom_minimum_size = Vector2(200, 140)
			delete_button.pressed.connect(_on_request_delete_slot.bind(i))
			row.add_child(delete_button)

func load_player_data(slot_name: String) -> Dictionary:
	var player_res_path = Constants.get_save_path(slot_name).path_join("player.tres")
	var legacy_player_path = Constants.get_player_path(slot_name)

	# Neue Resource bevorzugen
	if ResourceLoader.exists(player_res_path):
		var res = ResourceLoader.load(player_res_path)
		if res is PlayerResourceRes:
			var pr: PlayerResource = res
			return {
				"name": pr.player_name if pr.player_name != "" else "Unbekannt",
				"level": pr.player_level,
				"class_name": "???"
			}

	# Legacy JSON (Migration nur Anzeige)
	if FileAccess.file_exists(legacy_player_path):
		var file = FileAccess.open(legacy_player_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var json_obj = JSON.new()
			if json_obj.parse(json_string) == OK and json_obj.data is Dictionary:
				var data: Dictionary = json_obj.data
				return {
					"name": data.get("name", "Unbekannt"),
					"level": data.get("level", 1),
					"class_name": data.get("class_name", "???")
				}
	return {}

func _on_load_slot(slot_index: int):
	Constants.current_slot_index = slot_index
	
	# Ensure inventory resource exists
	var slot = Constants.SAVE_SLOTS[slot_index]
	var save_path = Constants.get_save_path(slot)
	var inventory_res_path = save_path.path_join("inventory.tres")
	if not ResourceLoader.exists(inventory_res_path):
		var dir = DirAccess.open("user://")
		if dir:
			dir.make_dir_recursive("save/" + slot)
		var inv_res := InventoryResourceRes.new()
		var err = ResourceSaver.save(inv_res, inventory_res_path)
		if err != OK:
			print("⚠️ Konnte inventory.tres nicht erstellen: ", inventory_res_path, " err=", err)
	
	var town_scene = preload("res://scenes/town_scene.tscn")
	if town_scene:
		get_tree().change_scene_to_packed(town_scene)
	else:
		print("⚠️ Town-Szene nicht gefunden!")

func _on_new_game(slot_index: int):
	var slot = Constants.SAVE_SLOTS[slot_index]
	var slot_path = Constants.get_save_path(slot)
	
	# Create save folder
	var dir = DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive("save/" + slot)
	else:
		print("❌ Error: could not open user:// directory")
		return
	
	# Create PlayerResource
	var player_res := PlayerResourceRes.new()
	player_res.player_name = "New Hero"
	player_res.player_level = 1
	player_res.backpack_slots = 12
	player_res.equipped = {}
	var player_res_path = slot_path.path_join("player.tres")
	var pres_err = ResourceSaver.save(player_res, player_res_path)
	if pres_err != OK:
		print("❌ Error: could not create player.tres at ", player_res_path, " err=", pres_err)
		return
	print("🆕 New save created in slot %d" % (slot_index + 1))
	print("📁 Saved to: ", OS.get_user_data_dir().path_join("save").path_join(slot))
	
	# Create empty inventory resource
	var inventory_res_path = slot_path.path_join("inventory.tres")
	var inv_res := InventoryResourceRes.new()
	var inv_err = ResourceSaver.save(inv_res, inventory_res_path)
	if inv_err != OK:
		print("⚠️ Konnte inventory.tres nicht erstellen: ", inventory_res_path, " err=", inv_err)
	
	# Set slot index
	Constants.current_slot_index = slot_index
	
	# Rebuild menu
	build_menu()
	
	# Switch to town scene
	var town_scene = preload("res://scenes/town_scene.tscn")
	if town_scene:
		get_tree().change_scene_to_packed(town_scene)
	else:
		print("⚠️ Town scene not found!")

func _on_back_pressed():
	print("Back button pressed (Load Menu)")
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main_menu.tscn")

# Request delete with confirmation
func _on_request_delete_slot(slot_index: int) -> void:
	_pending_delete_slot = slot_index
	if confirm_dialog:
		var player_data: Dictionary = slots_data[slot_index] if slot_index < slots_data.size() else {}
		var hero_name: String = String(player_data.get("name", Constants.SAVE_SLOTS[slot_index]))
		confirm_dialog.dialog_text = "Delete save '%s'?" % hero_name
		confirm_dialog.popup_centered()
	else:
		_on_delete_confirmed() # fallback without dialog

func _on_delete_canceled() -> void:
	_pending_delete_slot = -1

func _on_delete_confirmed() -> void:
	if _pending_delete_slot < 0:
		return
	var slot_index := _pending_delete_slot
	_pending_delete_slot = -1
	var slot: String = Constants.SAVE_SLOTS[slot_index]
	var slot_path: String = Constants.get_save_path(slot)
	_delete_directory_recursive(slot_path)
	build_menu()

func _delete_directory_recursive(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir:
		dir.list_dir_begin()
		while true:
			var entry_name: String = dir.get_next()
			if entry_name == "":
				break
			if entry_name == "." or entry_name == "..":
				continue
			var child_path := path.path_join(entry_name)
			if dir.current_is_dir():
				_delete_directory_recursive(child_path)
			else:
				var remove_file_result := DirAccess.remove_absolute(child_path)
				if remove_file_result != OK:
					print("⚠️ Konnte Datei nicht löschen: ", child_path, " (", remove_file_result, ")")
		dir.list_dir_end()
	
	var remove_dir_result := DirAccess.remove_absolute(path)
	if remove_dir_result != OK and remove_dir_result != ERR_DOES_NOT_EXIST:
		print("⚠️ Konnte Ordner nicht löschen: ", path, " (", remove_dir_result, ")")
