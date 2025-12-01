extends CanvasLayer

## HUD Scene - Универсальный UI для игровых сцен
## Содержит сумку и другие UI элементы, которые должны быть доступны во время игры

@onready var inventory_button: Button = $Control/GameHUD/LeftContainer/HBoxContainer/InventoryButton
@onready var inventory_modal: Control = $Control/Modals/InventoryModal
@onready var character_modal: Control = $Control/Modals/CharacterModal

func _ready():
	# Подключаем сигнал нажатия на кнопку сумки
	if inventory_button:
		inventory_button.pressed.connect(_on_inventory_button_pressed)
	
	# Подключаем горячую клавишу для открытия инвентаря
	set_process_input(true)

func _input(event: InputEvent):
	# Горячая клавиша I для открытия инвентаря
	if event.is_action_pressed("ui_inventory"):
		_open_inventory()
		var viewport = get_viewport()
		if viewport:
			viewport.set_input_as_handled()

func _on_inventory_button_pressed():
	_open_inventory()

func _open_inventory():
	"""Открывает/закрывает модальное окно инвентаря в HUD"""
	if inventory_modal:
		# Закрываем окно персонажа, если оно вдруг открыто
		if character_modal:
			character_modal.visible = false
		
		inventory_modal.visible = not inventory_modal.visible

func set_inventory_button_visible(visible: bool):
	"""Показывает/скрывает кнопку сумки"""
	if inventory_button:
		inventory_button.visible = visible
