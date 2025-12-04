extends CanvasLayer
const DragState := preload("res://scripts/drag_state.gd")
const LootPersistence := preload("res://scripts/loot_persistence.gd")

## HUD Scene - Универсальный UI для игровых сцен
## Содержит сумку, EquipmentSlots и EnemyInfoPanel

@onready var inventory_button: Button = $Control/GameHUD/LeftContainer/HBoxContainer/InventoryButton
@onready var menu_button: Button = $Control/GameHUD/TopLeftContainer/MenuButton
@onready var enemy_info_panel: Panel = $Control/GameHUD/TopLeftContainer/EnemyInfoPanel
@onready var enemy_info_label: RichTextLabel = $Control/GameHUD/TopLeftContainer/EnemyInfoPanel/EnemyInfoLabel
@onready var equipment_slots: Control = $Control/Modals/EquipmentSlots
@onready var pause_menu: Control = $Control/Modals/PauseMenu
@onready var options_modal: Control = $Control/Modals/OptionsModal
@onready var dungeon_button: Button = $Control/GameHUD/DungeonButton
@onready var level_selection_modal: Control = $Control/Modals/LevelSelectionModal

var _last_enemy_info_time: float = -1.0
var drag_icon: ColorRect = null

func _ready() -> void:
	# WICHTIG: HUD soll die Mausklicks auf die Spielwelt nicht blockieren.
	# Das Root-Control im HUD wird daher auf MOUSE_FILTER_IGNORE gesetzt.
	# Einzelne Buttons/Panels können weiterhin ihre eigene Mauslogik haben.
	if has_node("Control"):
		var root_control := $Control
		if root_control is Control:
			root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Подключаем сигнал нажатия на кнопку сумки
	if inventory_button:
		inventory_button.pressed.connect(_on_inventory_button_pressed)
	
	# Подключаем сигнал нажатия на кнопку меню
	if menu_button:
		menu_button.pressed.connect(_on_menu_button_pressed)

	# Кнопка выбора подземелья
	if dungeon_button:
		dungeon_button.pressed.connect(_on_dungeon_button_pressed)
	
	# Подключаем горячую клавишу для открытия инвентаря
	set_process_input(true)
	set_process(true)

	# Drag-Icon, das beim Welt-Loot-"Drag" der Maus folgt.
	# Optik an das Inventar-Drag-Preview (slot_get_drag_data) angelehnt:
	# halbtransparenter, weißer 48x48-Block.
	drag_icon = ColorRect.new()
	drag_icon.color = Color(1, 1, 1, 0.4)
	drag_icon.size = Vector2(48, 48)
	drag_icon.pivot_offset = drag_icon.size * 0.5
	drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_icon.visible = false
	if has_node("Control"):
		$Control.add_child(drag_icon)
	else:
		add_child(drag_icon)
	
	# EnemyInfoPanel initial ausblenden
	if enemy_info_panel:
		enemy_info_panel.visible = false
	if enemy_info_label:
		enemy_info_label.text = ""

	# Persistierten Status für Loot-Anzeige laden
	var saved_visible := LootPersistence.get_loot_always_visible()
	DroppedLoot.LOOT_ALWAYS_VISIBLE = saved_visible
	for drop in DroppedLoot.ALL_DROPS:
		if drop:
			drop.queue_redraw()

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

	# Alt+G (toggle_loot) — включить/выключить постоянный показ лута
	if event.is_action_pressed("toggle_loot"):
		DroppedLoot.LOOT_ALWAYS_VISIBLE = not DroppedLoot.LOOT_ALWAYS_VISIBLE
		LootPersistence.set_loot_always_visible(DroppedLoot.LOOT_ALWAYS_VISIBLE)
		# Перерисовать все активные дропы
		for drop in DroppedLoot.ALL_DROPS:
			if drop:
				drop.queue_redraw()

	# Linksklicks global auswerten:
	# - wenn aktuell KEIN Welt-Loot "in der Hand" ist: Klick auf Loot zum Aufheben prüfen
	# - wenn bereits ein Welt-Loot "in der Hand" ist: Klick benutzt, um Item zu platzieren/abzulegen
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				if DragState.active and not DragState.item.is_empty():
					_handle_world_item_click()
				else:
					_handle_loot_click()


func _handle_loot_click() -> void:
	# Bildschirm-Position der Maus holen
	var viewport := get_viewport()
	if viewport == null:
		return

	var mouse_screen_pos: Vector2 = viewport.get_mouse_position()

	# In Welt-Koordinaten umrechnen (über aktive Kamera2D)
	var cam := viewport.get_camera_2d()
	# In 2D können wir die Weltposition der Maus direkt von der Kamera holen.
	var world_pos: Vector2 = mouse_screen_pos
	if cam:
		world_pos = cam.get_global_mouse_position()

	var closest_drop: DroppedLoot = null
	var closest_dist := 999999.0

	for d in DroppedLoot.ALL_DROPS:
		if d == null:
			continue
		var drop := d as DroppedLoot
		var dist := drop.global_position.distance_to(world_pos)
		if dist < 40.0 and dist < closest_dist:
			closest_dist = dist
			closest_drop = drop

	if closest_drop != null:
		print("📦 HUD: click on loot at ", closest_drop.global_position)
		closest_drop.handle_world_click()
		# Verhindern, dass andere Knoten denselben Klick nochmals verarbeiten
		viewport.set_input_as_handled()


func _handle_world_item_click() -> void:
	# Nur relevant, wenn wir ein Item aus der Welt "in der Hand" haben
	if not DragState.active or DragState.item.is_empty():
		return

	var viewport := get_viewport()
	if viewport == null:
		return

	# Mausposition im Bildschirm / HUD
	var mouse_pos: Vector2 = viewport.get_mouse_position()

	# Versuchen, einen Inventar- oder Equipment-Slot im EquipmentSlots-Manager zu finden
	if equipment_slots == null:
		print("📦 HUD: world item click – kein equipment_slots im HUD")
		return

	var slots: Array = []

	# Inventar-Slots (Array von Panels)
	if "inventory_slots" in equipment_slots:
		for slot_panel in equipment_slots.inventory_slots:
			slots.append(slot_panel)

	# Equipment-Slots (Dictionary name -> Panel)
	if "equipment_slots" in equipment_slots:
		for slot_name in equipment_slots.equipment_slots.keys():
			var panel = equipment_slots.equipment_slots[slot_name]
			slots.append(panel)

	for slot_panel in slots:
		if not (slot_panel is Panel):
			continue
		var rect: Rect2 = slot_panel.get_global_rect()
		if rect.has_point(mouse_pos):
			if slot_panel.manager and slot_panel.manager.has_method("slot_click_from_world"):
				print("📦 HUD: world item click auf Inventory/Equipment-Slot, rufe manager.slot_click_from_world, id=", slot_panel.slot_id)
				slot_panel.manager.slot_click_from_world(slot_panel)
				# Prüfen, ob der Drop erfolgreich war (EquipmentSlots leert DRAG_ITEM/DRAG_SOURCE im Erfolgsfall)
				if DragState.active and not DragState.item.is_empty() and DragState.source_kind == "world" and DragState.source_node:
					print("📦 HUD: world item click – Slot hat nicht akzeptiert, Loot wieder anzeigen")
					var dl: DroppedLoot = DragState.source_node
					if dl:
						dl.item = DragState.item.duplicate(true)
						dl.gold = 0
						dl._update_label()
						dl.visible = true
					DragState.clear()
			else:
				print("📦 HUD: Inventory-Slot ohne gültigen manager/slot_click_from_world")
			return

	# Kein Inventar-Slot unter der Maus: Klick außerhalb der Slots – Loot wieder am Boden anzeigen
	print("📦 HUD: world item click – kein Inventar-Slot unter Maus, Loot zurück auf den Boden")

	var scene := get_tree().current_scene
	if scene:
		# Wenn es noch eine Welt-Quelle gibt, diese nutzen
		if DragState.source_kind == "world" and DragState.source_node:
			var dl: DroppedLoot = DragState.source_node
			if dl:
				dl.item = DragState.item.duplicate(true)
				dl.gold = 0
				dl._update_label()
				dl.visible = true
		# Andernfalls einen neuen DroppedLoot an der Spielerposition erzeugen
		elif DragState.item and not DragState.item.is_empty():
			var player: Node2D = scene.get_node_or_null("Player")
			if player == null:
				player = scene.find_child("Player", true, false)
			if player:
				var drop := DroppedLoot.new()
				drop.setup_drop(player.global_position, 0, DragState.item)
				scene.add_child(drop)

	# Drag-Zustand immer zurücksetzen und Highlights entfernen
	if equipment_slots and equipment_slots.has_method("clear_world_highlight"):
		equipment_slots.clear_world_highlight()

	DragState.clear()

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


func _on_dungeon_button_pressed() -> void:
	if level_selection_modal:
		level_selection_modal.visible = true

func set_inventory_button_visible(visible_flag: bool) -> void:
	"""Показывает/скрывает кнопку сумки"""
	if inventory_button:
		inventory_button.visible = visible_flag

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
	"""Автоматически скрывает EnemyInfoPanel через 0.5 секунды
	   и обновляет Position des Welt-Loot-Drag-Icons."""
	if enemy_info_panel:
		if enemy_info_panel.visible and _last_enemy_info_time >= 0.0:
			var now := Time.get_ticks_msec() / 1000.0
			if now - _last_enemy_info_time > 0.5:
				enemy_info_panel.visible = false
				if enemy_info_label:
					enemy_info_label.text = ""

	# Drag-Icon folgt der Maus, solange Welt-Loot "in der Hand" ist
	if drag_icon:
		if DragState.active and not DragState.item.is_empty():
			drag_icon.visible = true
			var viewport := get_viewport()
			if viewport:
				drag_icon.global_position = viewport.get_mouse_position()
		else:
			drag_icon.visible = false

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
