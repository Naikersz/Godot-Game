extends CanvasLayer

## HUD Scene - Универсальный UI для игровых сцен
## Содержит сумку и другие UI элементы, которые должны быть доступны во время игры

@onready var inventory_button: Button = $Control/GameHUD/LeftContainer/HBoxContainer/InventoryButton
@onready var equipment_slots: Control = $Control/Modals/EquipmentSlots


func _ready() -> void:
	# Подключаем сигнал нажатия на кнопку сумки
	if inventory_button:
		inventory_button.pressed.connect(_on_inventory_button_pressed)
	
	# Подключаем горячую клавишу для открытия инвентаря
	set_process_input(true)


func _input(event: InputEvent) -> void:
	# Горячая клавиша I для открытия/закрытия инвентаря
	# Используем глобальный Input, чтобы не вызывать метод у каждого события.
	if Input.is_action_just_pressed("ui_inventory"):
		_open_inventory()
		var viewport := get_viewport()
		if viewport:
			viewport.set_input_as_handled()


func _on_inventory_button_pressed() -> void:
	_open_inventory()


func _open_inventory() -> void:
	"""Открывает/закрывает окно EquipmentSlots в HUD"""
	if equipment_slots:
		if equipment_slots.has_method("toggle_visible"):
			equipment_slots.toggle_visible()
		else:
			equipment_slots.visible = not equipment_slots.visible


func set_inventory_button_visible(visible: bool) -> void:
	"""Показывает/скрывает кнопку сумки"""
	if inventory_button:
		inventory_button.visible = visible
