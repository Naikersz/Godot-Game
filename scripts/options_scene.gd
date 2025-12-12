extends Control

## Универсальный компонент настроек - работает как отдельная сцена и как модальное окно

const OPTIONS_PATH := "user://settings.cfg"

var _settings: SettingsStore = null
var _is_modal: bool = false  # Режим модального окна

# --- ссылки на важные контролы ---
@onready var dim_background: ColorRect = $DimBackground
@onready var texture_rect: TextureRect = $TextureRect
@onready var tab_container: TabContainer = $VBoxContainer/TabContainer

# Audio
@onready var master_slider: HSlider = $VBoxContainer/TabContainer/AudioTab/ScrollContainer/AudioVBox/MasterSlider
@onready var music_slider: HSlider = $VBoxContainer/TabContainer/AudioTab/ScrollContainer/AudioVBox/MusicSlider

# Video
@onready var fullscreen_check: CheckBox = $VBoxContainer/TabContainer/VideoTab/ScrollContainer/VideoVBox/FullscreenCheck
@onready var resolution_option: OptionButton = $VBoxContainer/TabContainer/VideoTab/ScrollContainer/VideoVBox/ResolutionOption

# Dev
@onready var dev_toggle: Button = $VBoxContainer/TabContainer/DevTab/ScrollContainer/DevVBox/DevToggleButton

# Back
@onready var back_button: Button = $VBoxContainer/ButtonContainer/BackButton

func _ready() -> void:
	_settings = SettingsStore.new()
	add_child(_settings)
	_settings.load_settings()
	
	# Определяем режим работы:
	# Если это текущая сцена (get_tree().current_scene == self), то это отдельная сцена
	# Если есть родитель и это не текущая сцена, то это модальное окно
	var tree = get_tree()
	var current_scene = tree.current_scene if tree else null
	var parent = get_parent()
	_is_modal = (parent != null) and (current_scene != self)
	
	print("🔍 OptionsScene инициализация:")
	print("   parent: ", parent)
	print("   current_scene: ", current_scene)
	print("   self: ", self)
	print("   _is_modal: ", _is_modal)
	
	# Настраиваем видимость элементов в зависимости от режима
	if _is_modal:
		# Модальный режим: показываем затемнённый фон, скрываем фоновую текстуру
		if dim_background:
			dim_background.visible = true
		if texture_rect:
			texture_rect.visible = false
		# Обрабатываем события даже во время паузы
		process_mode = Node.PROCESS_MODE_ALWAYS
		mouse_filter = Control.MOUSE_FILTER_STOP
	else:
		# Режим отдельной сцены: скрываем затемнённый фон, показываем фоновую текстуру
		if dim_background:
			dim_background.visible = false
		if texture_rect:
			texture_rect.visible = true

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

	# --- Dev ---
	if dev_toggle:
		DevSettings.set_dev_mode(_settings.dev_mode)
		dev_toggle.text = "Dev-Mode: ON" if DevSettings.dev_mode else "Dev-Mode: OFF"
		dev_toggle.pressed.connect(_on_dev_toggle_pressed)

	# --- Back ---
	if back_button:
		back_button.pressed.connect(_on_back_pressed)

# --- Audio логика ---
func _on_master_volume_changed(value: float) -> void:
	# value 0–100 -> переводим в dB
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

# --- Video логика ---
func _on_fullscreen_toggled(pressed: bool) -> void:
	var mode = DisplayServer.WINDOW_MODE_FULLSCREEN if pressed else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(mode)

	# Legacy placeholder removed; using SettingsStore instead
	_settings.fullscreen = pressed
	_settings.save_settings()

func _fill_resolutions() -> void:
	# примеры разрешений
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

# --- Dev логика ---
func _on_dev_toggle_pressed() -> void:
	DevSettings.set_dev_mode(not DevSettings.dev_mode)
	dev_toggle.text = "Dev-Mode: ON" if DevSettings.dev_mode else "Dev-Mode: OFF"

	# Legacy placeholder removed; using SettingsStore instead
	_settings.dev_mode = DevSettings.dev_mode
	_settings.save_settings()

# --- Back ---
func _on_back_pressed() -> void:
	# Сохраняем настройки перед выходом
	_settings.save_settings()
	
	print("🔙 Кнопка 'Назад' нажата. Режим: ", "модальный" if _is_modal else "отдельная сцена")
	
	if _is_modal:
		# В модальном режиме просто закрываем окно
		close_modal()
	else:
		# В режиме отдельной сцены возвращаемся в главное меню
		print("🔄 Переход в главное меню...")
		# Используем прямой вызов с небольшой задержкой
		var tree = get_tree()
		if tree:
			# Ждём один кадр перед сменой сцены
			await get_tree().process_frame
			tree.change_scene_to_file("res://scenes/main_menu.tscn")
		else:
			print("❌ Ошибка: get_tree() вернул null")

## Методы для работы в модальном режиме
func open_modal() -> void:
	"""Открывает настройки в модальном режиме"""
	_is_modal = true
	visible = true
	if dim_background:
		dim_background.visible = true
	if texture_rect:
		texture_rect.visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Обновляем значения при открытии
	_load_options()
	_update_ui_values()

func close_modal() -> void:
	"""Закрывает модальное окно настроек"""
	visible = false

func toggle_modal() -> void:
	"""Переключает видимость модального окна"""
	if visible:
		close_modal()
	else:
		open_modal()

func _update_ui_values() -> void:
	"""Обновляет значения UI элементов из загруженных настроек"""
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
	if dev_toggle:
		DevSettings.set_dev_mode(_settings.dev_mode)
		dev_toggle.text = "Dev-Mode: ON" if DevSettings.dev_mode else "Dev-Mode: OFF"

func _unhandled_input(event: InputEvent) -> void:
	# ESC закрывает окно настроек только в модальном режиме
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
