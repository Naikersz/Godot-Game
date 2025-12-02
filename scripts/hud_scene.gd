extends CanvasLayer

## HUD Scene - Универсальный UI для игровых сцен
## Содержит сумку, EquipmentSlots и EnemyInfoPanel

@onready var inventory_button: Button = $Control/GameHUD/LeftContainer/HBoxContainer/InventoryButton
@onready var menu_button: Button = $Control/GameHUD/TopLeftContainer/MenuButton
@onready var enemy_info_panel: Panel = $Control/GameHUD/TopLeftContainer/EnemyInfoPanel
@onready var enemy_info_label: RichTextLabel = $Control/GameHUD/TopLeftContainer/EnemyInfoPanel/EnemyInfoLabel
@onready var equipment_slots: Control = $Control/Modals/EquipmentSlots
@onready var pause_menu: Control = $Control/Modals/PauseMenu
@onready var options_modal: Control = $Control/Modals/OptionsModal

var _last_enemy_info_time: float = -1.0

func _ready() -> void:
	# Подключаем сигнал нажатия на кнопку сумки
	if inventory_button:
		inventory_button.pressed.connect(_on_inventory_button_pressed)
	
	# Подключаем сигнал нажатия на кнопку меню
	if menu_button:
		menu_button.pressed.connect(_on_menu_button_pressed)
	
	# Подключаем горячую клавишу для открытия инвентаря
	set_process_input(true)
	set_process(true)
	
	# EnemyInfoPanel initial ausblenden
	if enemy_info_panel:
		enemy_info_panel.visible = false
	if enemy_info_label:
		enemy_info_label.text = ""

func _input(event: InputEvent) -> void:
	# ESC для открытия/закрытия меню паузы (только если меню закрыто)
	if event.is_action_pressed("ui_cancel"):
		if pause_menu and not pause_menu.visible:
			_open_pause_menu()
			var viewport := get_viewport()
			if viewport:
				viewport.set_input_as_handled()
		return
	
	# Горячая клавиша I для открытия/закрытия инвентаря
	if event.is_action_pressed("ui_inventory"):
		_open_inventory()
		var viewport := get_viewport()
		if viewport:
			viewport.set_input_as_handled()

func _on_inventory_button_pressed() -> void:
	_open_inventory()

func _on_menu_button_pressed() -> void:
	_open_pause_menu()

func _open_inventory() -> void:
	"""Открывает/закрывает окно EquipmentSlots в HUD"""
	if equipment_slots:
		if equipment_slots.has_method("toggle_visible"):
			equipment_slots.toggle_visible()
		else:
			equipment_slots.visible = not equipment_slots.visible

func _open_pause_menu() -> void:
	"""Открывает/закрывает меню паузы"""
	if pause_menu:
		if pause_menu.has_method("toggle_visible"):
			pause_menu.toggle_visible()
		else:
			pause_menu.visible = not pause_menu.visible

func _open_options() -> void:
	"""Открывает/закрывает модальное окно настроек"""
	if options_modal:
		if options_modal.has_method("toggle_modal"):
			options_modal.toggle_modal()
		elif options_modal.has_method("open_modal"):
			if options_modal.visible:
				options_modal.close_modal()
			else:
				options_modal.open_modal()
		else:
			options_modal.visible = not options_modal.visible

func set_inventory_button_visible(visible: bool) -> void:
	"""Показывает/скрывает кнопку сумки"""
	if inventory_button:
		inventory_button.visible = visible

func set_enemy_info(text: String) -> void:
	"""Устанавливает текст информации о враге"""
	if not enemy_info_label or not enemy_info_panel:
		return
	if text != "":
		enemy_info_label.text = text
		_resize_enemy_info_panel()
		enemy_info_panel.visible = true
		_last_enemy_info_time = Time.get_ticks_msec() / 1000.0

func _process(_delta: float) -> void:
	"""Автоматически скрывает EnemyInfoPanel через 0.5 секунды"""
	if not enemy_info_panel:
		return
	if not enemy_info_panel.visible:
		return
	if _last_enemy_info_time < 0.0:
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_enemy_info_time > 0.5:
		enemy_info_panel.visible = false
		if enemy_info_label:
			enemy_info_label.text = ""

func _resize_enemy_info_panel() -> void:
	"""Изменяет размер EnemyInfoPanel в зависимости от содержимого"""
	if not enemy_info_panel or not enemy_info_label:
		return
	
	# Высота подстраивается под текст, ширина остается из сцены (Panel-Offsets)
	enemy_info_label.force_update_transform()
	var content_h: float = enemy_info_label.get_content_height()
	var padding: float = 16.0
	var height: float = content_h + padding
	if height < 40.0:
		height = 40.0
	
	var size: Vector2 = enemy_info_panel.size
	size.y = height
	enemy_info_panel.size = size
