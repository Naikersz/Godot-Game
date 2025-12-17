extends Control

## Universal settings component - works as a separate scene and as a modal window

const OPTIONS_PATH := "user://settings.cfg"

var _settings: SettingsStore = null
var _is_modal: bool = false  # Modal window mode

# --- references to important controls ---
@onready var dim_background: ColorRect = $DimBackground
@onready var texture_rect: TextureRect = $TextureRect
@onready var tab_container: TabContainer = $VBoxContainer/TabContainer

# Audio
@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var master_label: Label = $VBoxContainer/TabContainer/AudioTab/ScrollContainer/AudioVBox/MasterLabel
@onready var music_label: Label = $VBoxContainer/TabContainer/AudioTab/ScrollContainer/AudioVBox/MusicLabel
@onready var master_slider: HSlider = $VBoxContainer/TabContainer/AudioTab/ScrollContainer/AudioVBox/MasterSlider
@onready var music_slider: HSlider = $VBoxContainer/TabContainer/AudioTab/ScrollContainer/AudioVBox/MusicSlider

# Video
@onready var fullscreen_label: Label = $VBoxContainer/TabContainer/VideoTab/ScrollContainer/VideoVBox/FullscreenLabel
@onready var resolution_label: Label = $VBoxContainer/TabContainer/VideoTab/ScrollContainer/VideoVBox/ResolutionLabel
@onready var language_label: Label = $VBoxContainer/TabContainer/VideoTab/ScrollContainer/VideoVBox/LanguageLabel
@onready var fullscreen_check: CheckBox = $VBoxContainer/TabContainer/VideoTab/ScrollContainer/VideoVBox/FullscreenCheck
@onready var resolution_option: OptionButton = $VBoxContainer/TabContainer/VideoTab/ScrollContainer/VideoVBox/ResolutionOption

# Localization
@onready var language_option: OptionButton = $VBoxContainer/TabContainer/VideoTab/ScrollContainer/VideoVBox/LanguageOption

# Dev
@onready var dev_info_label: Label = $VBoxContainer/TabContainer/DevTab/ScrollContainer/DevVBox/DevInfoLabel
@onready var dev_toggle: Button = $VBoxContainer/TabContainer/DevTab/ScrollContainer/DevVBox/DevToggleButton

# Back
@onready var back_button: Button = $VBoxContainer/ButtonContainer/BackButton

func _ready() -> void:
	_settings = SettingsStore.new()
	add_child(_settings)
	_settings.load_settings()
	
	# Determine operation mode:
	# If this is the current scene (get_tree().current_scene == self), then it's a separate scene
	# If there's a parent and this is not the current scene, then it's a modal window
	var tree = get_tree()
	var current_scene = tree.current_scene if tree else null
	var parent = get_parent()
	_is_modal = (parent != null) and (current_scene != self)
	
	print("🔍 OptionsScene initialization:")
	print("   parent: ", parent)
	print("   current_scene: ", current_scene)
	print("   self: ", self)
	print("   _is_modal: ", _is_modal)
	
	# Configure element visibility based on mode
	if _is_modal:
		# Modal mode: show dimmed background, hide background texture
		if dim_background:
			dim_background.visible = true
		if texture_rect:
			texture_rect.visible = false
		# Process events even during pause
		process_mode = Node.PROCESS_MODE_ALWAYS
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		# Separate scene mode: hide dimmed background, show background texture
		if dim_background:
			dim_background.visible = false
		if texture_rect:
			texture_rect.visible = true

	# Set UI texts with tr()
	if title_label:
		title_label.text = tr("Options")
	if master_label:
		master_label.text = tr("Master Volume")
	if music_label:
		music_label.text = tr("Music Volume")
	if fullscreen_label:
		fullscreen_label.text = tr("Fullscreen")
	if resolution_label:
		resolution_label.text = tr("Resolution")
	if language_label:
		language_label.text = tr("Language")
	if dev_info_label:
		dev_info_label.text = tr("Dev-Mode: shows extra Balancing-Panel in Level Selection")
	if back_button:
		back_button.text = tr("Back")

	# --- Audio init ---
	if master_slider:
		master_slider.min_value = 0
		master_slider.max_value = 100
		master_slider.value = _settings.master_volume
		master_slider.value_changed.connect(_on_master_volume_changed)

	if music_slider:
		music_slider.min_value = 0
		music_slider.max_value = 100
		music_slider.value = _settings.music_volume
		music_slider.value_changed.connect(_on_music_volume_changed)

	# --- Video init ---
	if fullscreen_check:
		var is_fullscreen = _settings.fullscreen
		fullscreen_check.set_pressed_no_signal(is_fullscreen)
		fullscreen_check.toggled.connect(_on_fullscreen_toggled)

	if resolution_option:
		_fill_resolutions()
		var res_index := _settings.resolution_index
		if res_index >= 0 and res_index < resolution_option.item_count:
			resolution_option.select(res_index)
			_on_resolution_selected(res_index)
		resolution_option.item_selected.connect(_on_resolution_selected)

	# --- Localization ---
	if language_option:
		_fill_languages()
		var lang_index := _get_language_index(_settings.language)
		if lang_index >= 0 and lang_index < language_option.item_count:
			language_option.select(lang_index)
		language_option.item_selected.connect(_on_language_selected)

	# --- Dev ---
	if dev_toggle:
		DevSettings.set_dev_mode(_settings.dev_mode)
		_update_dev_toggle_text()
		dev_toggle.pressed.connect(_on_dev_toggle_pressed)

	# --- Back ---
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

# --- Audio logic ---
func _on_master_volume_changed(value: float) -> void:
	# value 0–100 -> convert to dB
	var db = lerp(-40.0, 0.0, value / 100.0)
	var master_bus_index = AudioServer.get_bus_index("Master")
	if master_bus_index >= 0:
		AudioServer.set_bus_volume_db(master_bus_index, db)

	# Legacy placeholder removed; using SettingsStore instead
	_settings.master_volume = value
	_settings.save_settings()

func _on_music_volume_changed(value: float) -> void:
	var db = lerp(-40.0, 0.0, value / 100.0)
	var music_bus_index = AudioServer.get_bus_index("Music")
	if music_bus_index >= 0:
		AudioServer.set_bus_volume_db(music_bus_index, db)

	# Legacy placeholder removed; using SettingsStore instead
	_settings.music_volume = value
	_settings.save_settings()

# --- Video logic ---
func _on_fullscreen_toggled(pressed: bool) -> void:
	var mode = DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

	# Legacy placeholder removed; using SettingsStore instead
	_settings.fullscreen = pressed
	_settings.save_settings()

func _fill_resolutions() -> void:
	# example resolutions
	var resolutions = [
		Vector2i(1280, 720),
		Vector2i(1600, 900),
		Vector2i(1920, 1080)
	]
	for i in resolutions.size():
		resolution_option.add_item("%d x %d" % [resolutions[i].x, resolutions[i].y], i)

func _on_resolution_selected(index: int) -> void:
	var text = resolution_option.get_item_text(index)
	var parts = text.split(" x ")
	var w = int(parts[0])
	var h = int(parts[1])
	DisplayServer.window_set_size(Vector2i(w, h))

	_settings.resolution_index = index
	_settings.save_settings()

# --- Localization logic ---
func _fill_languages() -> void:
	"""Fills the language option button with available languages"""
	if not language_option:
		return
	
	var languages = [
		{"code": "en", "name": "English"},
		{"code": "de", "name": "Deutsch"},
		{"code": "ru", "name": "Русский"}
	]
	
	for i in languages.size():
		language_option.add_item(languages[i].name, i)
		language_option.set_item_metadata(i, languages[i].code)

func _get_language_index(lang_code: String) -> int:
	"""Returns the index of a language code in the option button"""
	if not language_option:
		return 0
	
	for i in language_option.item_count:
		var meta = language_option.get_item_metadata(i)
		if meta == lang_code:
			return i
	return 0

func _on_language_selected(index: int) -> void:
	"""Handles language selection change"""
	if not language_option:
		return
	
	var lang_code = language_option.get_item_metadata(index)
	if lang_code == null or lang_code == "":
		return
	
	_settings.language = lang_code
	_settings.save_settings()
	
	# Apply language change immediately
	TranslationServer.set_locale(lang_code)
	print("✓ Options: Language changed to: ", lang_code)
	
	# Update UI texts that use tr() in this scene
	_update_ui_texts()
	
	# Update all other visible scenes
	_update_all_scene_texts()

func _update_ui_texts() -> void:
	"""Updates all UI texts that use tr() after language change"""
	if title_label:
		title_label.text = tr("Options")
	if master_label:
		master_label.text = tr("Master Volume")
	if music_label:
		music_label.text = tr("Music Volume")
	if fullscreen_label:
		fullscreen_label.text = tr("Fullscreen")
	if resolution_label:
		resolution_label.text = tr("Resolution")
	if language_label:
		language_label.text = tr("Language")
	if dev_info_label:
		dev_info_label.text = tr("Dev-Mode: shows extra Balancing-Panel in Level Selection")
	if dev_toggle:
		_update_dev_toggle_text()
	if back_button:
		back_button.text = tr("Back")

func _update_dev_toggle_text() -> void:
	"""Updates dev toggle button text and adjusts size dynamically"""
	if not dev_toggle:
		return
	
	var new_text := tr("Dev-Mode: ON") if DevSettings.dev_mode else tr("Dev-Mode: OFF")
	dev_toggle.text = new_text
	
	# Adjust size after text is set (use call_deferred to ensure font is ready)
	call_deferred("_adjust_dev_toggle_size")

func _adjust_dev_toggle_size() -> void:
	"""Adjusts dev toggle button size to fit text content"""
	if not dev_toggle:
		return
	
	# Get font and font size from theme
	var font = dev_toggle.get_theme_font("font")
	var font_size = dev_toggle.get_theme_font_size("font_size")
	
	# Fallback to default if not found
	if font == null:
		font = ThemeDB.fallback_font
	if font_size <= 0:
		font_size = 16
	
	# Calculate text width
	var text_width := 0.0
	if font and dev_toggle.text != "":
		var string_size = font.get_string_size(dev_toggle.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
		text_width = string_size.x
	
	# Add padding (left + right) and ensure minimum width
	var padding := 60.0  # Extra padding for button styling
	var min_width := 250.0  # Minimum button width
	var calculated_width := text_width + padding
	
	# Set button width (keep height from scene or use default)
	var current_height := dev_toggle.size.y if dev_toggle.size.y > 0 else 96.0
	dev_toggle.custom_minimum_size = Vector2(max(calculated_width, min_width), current_height)

func _update_all_scene_texts() -> void:
	"""Updates UI texts in all visible scenes after language change"""
	var tree = get_tree()
	if not tree:
		return
	
	# Update current scene
	var current_scene = tree.current_scene
	if current_scene:
		_update_scene_texts(current_scene)
	
	# Update all nodes in the scene tree that might have translatable texts
	_update_node_recursive(get_tree().root)

func _update_node_recursive(node: Node) -> void:
	"""Recursively updates all nodes that might need text updates"""
	if node.has_method("_update_ui_texts"):
		node._update_ui_texts()
	elif node.has_method("update_ui_texts"):
		node.update_ui_texts()
	
	for child in node.get_children():
		_update_node_recursive(child)

func _update_scene_texts(scene: Node) -> void:
	"""Updates texts in a specific scene"""
	if scene.has_method("_update_ui_texts"):
		scene._update_ui_texts()
	elif scene.has_method("update_ui_texts"):
		scene.update_ui_texts()

# --- Dev logic ---
func _on_dev_toggle_pressed() -> void:
	DevSettings.set_dev_mode(not DevSettings.dev_mode)
	_update_dev_toggle_text()

	# Legacy placeholder removed; using SettingsStore instead
	_settings.dev_mode = DevSettings.dev_mode
	_settings.save_settings()

# --- Back ---
func _on_back_pressed() -> void:
	# Save settings before exiting
	_settings.save_settings()
	
	print("🔙 Back button pressed. Mode: ", "modal" if _is_modal else "separate scene")
	
	if _is_modal:
		# In modal mode, simply close the window
		close_modal()
	else:
		# In separate scene mode, return to main menu
		print("🔄 Transitioning to main menu...")
		# Use direct call with small delay
		var tree = get_tree()
		if tree:
			# Wait one frame before changing scene
			await get_tree().process_frame
			tree.change_scene_to_file("res://scenes/main_menu.tscn")
		else:
			print("❌ Error: get_tree() returned null")

## Methods for working in modal mode
func open_modal() -> void:
	"""Opens settings in modal mode"""
	_is_modal = true
	visible = true
	if dim_background:
		dim_background.visible = true
	if texture_rect:
		texture_rect.visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Update values when opening
	_load_options()
	_update_ui_values()

func close_modal() -> void:
	"""Closes the settings modal window"""
	visible = false

func toggle_modal() -> void:
	"""Toggles visibility of the modal window"""
	if visible:
		close_modal()
	else:
		open_modal()

func _update_ui_values() -> void:
	"""Updates UI element values from loaded settings"""
	if master_slider:
		master_slider.value = _settings.master_volume
	if music_slider:
		music_slider.value = _settings.music_volume
	if fullscreen_check:
		var is_fullscreen = _settings.fullscreen
		fullscreen_check.set_pressed_no_signal(is_fullscreen)
	if resolution_option:
		var res_index := _settings.resolution_index
		if res_index >= 0 and res_index < resolution_option.item_count:
			resolution_option.select(res_index)
	if language_option:
		var lang_index := _get_language_index(_settings.language)
		if lang_index >= 0 and lang_index < language_option.item_count:
			language_option.select(lang_index)
	if dev_toggle:
		DevSettings.set_dev_mode(_settings.dev_mode)
		_update_dev_toggle_text()

func _unhandled_input(event: InputEvent) -> void:
	# ESC closes settings window only in modal mode
	if _is_modal and visible and event.is_action_pressed("ui_cancel"):
		close_modal()
		if get_viewport():
			get_viewport().set_input_as_handled()


func _load_options() -> void:
	# Deprecated; kept for compatibility if called elsewhere.
	if _settings == null:
		_settings = SettingsStore.new()
		add_child(_settings)
	_settings.load_settings()
	_update_ui_values()

func _save_options() -> void:
	# Deprecated; kept for compatibility if called elsewhere.
	if _settings != null:
		_settings.save_settings()
