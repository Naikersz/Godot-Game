extends CanvasLayer

## HUD Scene - Универсальный UI для игровых сцен
## Содержит сумку и другие UI элементы, которые должны быть доступны во время игры

@onready var inventory_button: Button = $UIContainer/TopLeftContainer/InventoryButton

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
	"""Открывает сцену инвентаря"""
	var inventory_scene = preload("res://scenes/inventory_scene.tscn")
	if inventory_scene:
		get_tree().change_scene_to_packed(inventory_scene)
	else:
		print("⚠️ Inventory-Szene nicht gefunden!")

func set_inventory_button_visible(visible: bool):
	"""Показывает/скрывает кнопку сумки"""
	if inventory_button:
		inventory_button.visible = visible
