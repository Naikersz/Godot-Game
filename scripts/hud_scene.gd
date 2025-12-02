extends CanvasLayer

## HUD Scene - Universeller HUD für Spielszenen
## Enthält die Inventar-Schaltfläche und ein Infofeld für Gegner-Stats.

@onready var inventory_button: Button = $Control/GameHUD/LeftContainer/HBoxContainer/InventoryButton
@onready var enemy_info_panel: Panel = $Control/GameHUD/TopLeftContainer/EnemyInfoPanel
@onready var enemy_info_label: RichTextLabel = $Control/GameHUD/TopLeftContainer/EnemyInfoPanel/EnemyInfoLabel
@onready var equipment_slots: Control = $Control/Modals/EquipmentSlots

var _last_enemy_info_time: float = -1.0

func _ready() -> void:
	# Подключаем сигнал нажатия на кнопку сумки
	if inventory_button:
		inventory_button.pressed.connect(_on_inventory_button_pressed)
	
	# Gegner-Info initial ausblenden
	if enemy_info_panel:
		enemy_info_panel.visible = false
	if enemy_info_label:
		enemy_info_label.text = ""
	
	# Tastatureingaben für Inventar erlauben
	set_process_input(true)
	set_process(true)

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

func set_inventory_button_visible(visible_flag: bool) -> void:
	"""Показывает/скрывает кнопку сумки"""
	if inventory_button:
		inventory_button.visible = visible_flag

func set_enemy_info(text: String) -> void:
	if not enemy_info_label or not enemy_info_panel:
		return
	if text != "":
		enemy_info_label.text = text
		_resize_enemy_info_panel()
		enemy_info_panel.visible = true
		_last_enemy_info_time = Time.get_ticks_msec() / 1000.0

func _process(_delta: float) -> void:
	if not enemy_info_panel:
		return
	if not enemy_info_panel.visible:
		return
	if _last_enemy_info_time < 0.0:
		return

	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_enemy_info_time > 0.5:
		enemy_info_panel.visible = false
		enemy_info_label.text = ""

func _resize_enemy_info_panel() -> void:
	if not enemy_info_panel or not enemy_info_label:
		return
	
	# Höhe an Text anpassen, Breite bleibt aus der Szene (Panel-Offsets)
	enemy_info_label.force_update_transform()
	var content_h: float = enemy_info_label.get_content_height()
	var padding: float = 16.0
	var height: float = content_h + padding
	if height < 40.0:
		height = 40.0
	
	var size: Vector2 = enemy_info_panel.size
	size.y = height
	enemy_info_panel.size = size
