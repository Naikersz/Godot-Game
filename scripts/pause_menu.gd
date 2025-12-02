extends Control

## Меню паузы - модальное окно с кнопками управления игрой

@onready var dim_background: ColorRect = $DimBackground
@onready var window_panel: Panel = $WindowPanel
@onready var buttons_container: VBoxContainer = $WindowPanel/VBoxContainer
@onready var resume_button: Button = $WindowPanel/VBoxContainer/ResumeButton
@onready var save_button: Button = $WindowPanel/VBoxContainer/SaveButton
@onready var options_button: Button = $WindowPanel/VBoxContainer/OptionsButton
@onready var main_menu_button: Button = $WindowPanel/VBoxContainer/MainMenuButton
@onready var quit_button: Button = $WindowPanel/VBoxContainer/QuitButton

func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Важно: меню должно обрабатывать события даже во время паузы
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Убеждаемся, что все кнопки тоже обрабатывают события во время паузы
	if resume_button:
		resume_button.process_mode = Node.PROCESS_MODE_ALWAYS
		resume_button.pressed.connect(_on_resume_pressed)
		print("✅ ResumeButton подключен")
	if save_button:
		save_button.process_mode = Node.PROCESS_MODE_ALWAYS
		save_button.pressed.connect(_on_save_pressed)
		print("✅ SaveButton подключен")
	if options_button:
		options_button.process_mode = Node.PROCESS_MODE_ALWAYS
		options_button.pressed.connect(_on_options_pressed)
		print("✅ OptionsButton подключен")
	if main_menu_button:
		main_menu_button.process_mode = Node.PROCESS_MODE_ALWAYS
		main_menu_button.pressed.connect(_on_main_menu_pressed)
		print("✅ MainMenuButton подключен")
	if quit_button:
		quit_button.process_mode = Node.PROCESS_MODE_ALWAYS
		quit_button.pressed.connect(_on_quit_pressed)
		print("✅ QuitButton подключен")
	
	print("✅ PauseMenu готов, process_mode = PROCESS_MODE_ALWAYS")

func toggle_visible() -> void:
	visible = not visible
	print("🔄 PauseMenu visible = ", visible)
	if visible:
		# Паузим игру
		get_tree().paused = true
		print("⏸️ Игра на паузе")
		# Фокус на первую кнопку
		if resume_button:
			resume_button.grab_focus()
	else:
		# Возобновляем игру
		get_tree().paused = false
		print("▶️ Игра возобновлена")

func _on_resume_pressed() -> void:
	print("🔵 ResumeButton нажата")
	toggle_visible()

func _on_save_pressed() -> void:
	# TODO: Реализовать сохранение игры
	print("💾 Сохранение игры...")
	# Временно просто закрываем меню
	toggle_visible()

func _on_options_pressed() -> void:
	# Закрываем меню паузы и открываем модальное окно настроек
	toggle_visible()
	# Находим OptionsModal через путь (PauseMenu и OptionsModal находятся в одной папке Modals)
	var options_modal = get_node_or_null("../OptionsModal")
	if options_modal:
		if options_modal.has_method("toggle_modal"):
			options_modal.toggle_modal()
		elif options_modal.has_method("open_modal"):
			options_modal.open_modal()
		else:
			options_modal.visible = true
	else:
		print("⚠️ Не удалось найти OptionsModal по пути ../OptionsModal")

func _on_main_menu_pressed() -> void:
	# Возобновляем игру перед переходом в меню
	get_tree().paused = false
	# Переходим в главное меню
	var main_menu_scene = preload("res://scenes/main_menu.tscn")
	if main_menu_scene:
		get_tree().change_scene_to_packed(main_menu_scene)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _unhandled_input(event: InputEvent) -> void:
	# ESC закрывает меню паузы только если оно видимо
	if visible and event.is_action_pressed("ui_cancel"):
		print("🔵 ESC нажата в PauseMenu")
		toggle_visible()
		if get_viewport():
			get_viewport().set_input_as_handled()

