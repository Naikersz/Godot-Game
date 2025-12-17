extends Control

## Pause menu - modal window with game control buttons

@onready var dim_background: ColorRect = $DimBackground
@onready var window_panel: Panel = $WindowPanel
@onready var buttons_container: VBoxContainer = $WindowPanel/VBoxContainer
@onready var resume_button: Button = $WindowPanel/VBoxContainer/ResumeButton
@onready var options_button: Button = $WindowPanel/VBoxContainer/OptionsButton
@onready var main_menu_button: Button = $WindowPanel/VBoxContainer/MainMenuButton
@onready var quit_button: Button = $WindowPanel/VBoxContainer/QuitButton

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Important: menu must process events even during pause
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	_update_ui_texts()
	
	# Connect buttons
	if resume_button:
		resume_button.process_mode = Node.PROCESS_MODE_ALWAYS
		resume_button.pressed.connect(_on_resume_pressed)
		print("✅ ResumeButton connected")
	if options_button:
		options_button.process_mode = Node.PROCESS_MODE_ALWAYS
		options_button.pressed.connect(_on_options_pressed)
		print("✅ OptionsButton connected")
	if main_menu_button:
		main_menu_button.process_mode = Node.PROCESS_MODE_ALWAYS
		main_menu_button.pressed.connect(_on_main_menu_pressed)
		print("✅ MainMenuButton connected")
	if quit_button:
		quit_button.process_mode = Node.PROCESS_MODE_ALWAYS
		quit_button.pressed.connect(_on_quit_pressed)
		print("✅ QuitButton connected")
	
	print("✅ PauseMenu ready, process_mode = PROCESS_MODE_ALWAYS")

func _update_ui_texts() -> void:
	"""Updates all UI texts that use tr() - called when language changes"""
	# Set button texts with tr()
	if resume_button:
		resume_button.text = tr("Continue")
	if options_button:
		options_button.text = tr("Settings")
	if main_menu_button:
		main_menu_button.text = tr("Main Menu")
	if quit_button:
		quit_button.text = tr("Quit")

func toggle_visible() -> void:
	visible = not visible
	print("🔄 PauseMenu visible = ", visible)
	if visible:
		# Pause the game
		get_tree().paused = true
		print("⏸️ Game paused")
		# Focus on first button
		if resume_button:
			resume_button.grab_focus()
	else:
		# Resume the game
		get_tree().paused = false
		print("▶️ Game resumed")

func _on_resume_pressed() -> void:
	print("🔵 ResumeButton pressed")
	toggle_visible()

func _on_options_pressed() -> void:
	# Close pause menu and open settings modal window
	toggle_visible()
	# Find OptionsModal via path (PauseMenu and OptionsModal are in the same Modals folder)
	var options_modal = get_node_or_null("../OptionsModal")
	if options_modal:
		if options_modal.has_method("toggle_modal"):
			options_modal.toggle_modal()
		elif options_modal.has_method("open_modal"):
			options_modal.open_modal()
		else:
			options_modal.visible = true
	else:
		print("⚠️ Could not find OptionsModal at path ../OptionsModal")

func _on_main_menu_pressed() -> void:
	# Ensure the game is unpaused before leaving
	get_tree().paused = false
	# Hide the pause menu to avoid lingering overlay after scene change
	visible = false
	# Defer scene change to avoid issues when called from a paused tree
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main_menu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	# ESC closes pause menu only if it's visible
	if visible and event.is_action_pressed("ui_cancel"):
		print("🔵 ESC pressed in PauseMenu")
		toggle_visible()
		if get_viewport():
			get_viewport().set_input_as_handled()
