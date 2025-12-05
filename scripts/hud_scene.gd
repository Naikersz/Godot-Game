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
var drag_info_panel: Panel = null
var drag_info_label: RichTextLabel = null

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

	# Drag-Info-Panel unten links erstellen (temporär für Debug)
	drag_info_panel = Panel.new()
	drag_info_panel.name = "DragInfoPanel"
	drag_info_panel.anchor_left = 0.0
	drag_info_panel.anchor_top = 1.0
	drag_info_panel.anchor_right = 0.0
	drag_info_panel.anchor_bottom = 1.0
	drag_info_panel.offset_left = 16.0
	drag_info_panel.offset_top = -200.0
	drag_info_panel.offset_right = 300.0
	drag_info_panel.offset_bottom = -16.0
	drag_info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_info_panel.visible = false
	# Dunkler Hintergrund für bessere Lesbarkeit
	var style_box := StyleBoxFlat.new()
	style_box.bg_color = Color(0, 0, 0, 0.85)
	style_box.border_color = Color(1, 1, 1, 0.5)
	style_box.border_width_left = 2
	style_box.border_width_top = 2
	style_box.border_width_right = 2
	style_box.border_width_bottom = 2
	drag_info_panel.add_theme_stylebox_override("panel", style_box)
	if has_node("Control"):
		$Control.add_child(drag_info_panel)
	else:
		add_child(drag_info_panel)

	drag_info_label = RichTextLabel.new()
	drag_info_label.name = "DragInfoLabel"
	drag_info_label.bbcode_enabled = true
	drag_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drag_info_label.anchor_left = 0.0
	drag_info_label.anchor_top = 0.0
	drag_info_label.anchor_right = 1.0
	drag_info_label.anchor_bottom = 1.0
	drag_info_label.offset_left = 8.0
	drag_info_label.offset_top = 8.0
	drag_info_label.offset_right = -8.0
	drag_info_label.offset_bottom = -8.0
	drag_info_panel.add_child(drag_info_label)

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

	# Alle Drops finden, die auf den Text-Bereich klicken (nicht nur nach Distanz)
	var candidate_drops: Array = []
	
	for d in DroppedLoot.ALL_DROPS:
		if d == null:
			continue
		var drop := d as DroppedLoot
		if drop.visible == false:
			continue
		
		# Prüfen ob Klick auf Text-Bereich dieses Drops
		var mouse_local := drop.to_local(world_pos)
		var show_temp := Input.is_action_pressed("show_loot") or Input.is_key_pressed(KEY_G)
		var show_visible := DroppedLoot.LOOT_ALWAYS_VISIBLE or show_temp
		
		if not show_visible:
			continue
		
		# Text-Bereich dieses Drops berechnen
		var item_text := drop.get_item_text()
		var gold_text := drop.get_gold_text()
		
		if item_text == "" and gold_text == "":
			continue
		
		var font := drop.DROP_FONT
		if font == null:
			continue
		
		var font_size: int = drop.LABEL_FONT_SIZE
		var line_height := font.get_height(font_size)
		var lines: Array[String] = []
		if item_text != "":
			lines.append(item_text)
		if gold_text != "":
			lines.append(gold_text)
		
		var max_width: float = 0.0
		for t in lines:
			var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
			if w > max_width:
				max_width = w
		
		var padding: Vector2 = Vector2(6.0, 4.0)
		var box_size: Vector2 = Vector2(max_width, line_height * lines.size()) + padding * 2.0
		var label_offset_x := drop.get_label_offset_x()
		var label_offset_y := drop.get_label_offset_y()
		var box_pos := Vector2(-box_size.x * 0.5 + label_offset_x, -box_size.y - 8.0 + label_offset_y)
		var text_rect := Rect2(box_pos, box_size)
		
		# Prüfen ob Loot in Pickup-Reichweite ist
		if not drop.is_in_pickup_range():
			continue
		
		if text_rect.has_point(mouse_local):
			candidate_drops.append(drop)
	
	# Wenn mehrere Drops gefunden wurden, das oberste (höchstes z_index) nehmen
	if candidate_drops.is_empty():
		return
	
	var top_drop: DroppedLoot = null
	var highest_z: float = -999999.0
	
	for drop in candidate_drops:
		var z: float = float(drop.z_index)
		# Wenn z_index gleich ist, nimm das zuletzt hinzugefügte (höherer Index in ALL_DROPS)
		if z > highest_z or (z == highest_z and DroppedLoot.ALL_DROPS.find(drop) > DroppedLoot.ALL_DROPS.find(top_drop)):
			highest_z = z
			top_drop = drop
	
	if top_drop != null:
		print("📦 HUD: click on loot at ", top_drop.global_position, " (z_index=", top_drop.z_index, ")")
		top_drop.handle_world_click()
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
		# Immer aktuelle Player-Position für Drop verwenden (auch während Bewegung)
		var player: Node2D = scene.get_node_or_null("Player")
		if player == null:
			player = scene.find_child("Player", true, false)
		
		if player:
			# Wenn es noch eine Welt-Quelle gibt, diese an aktueller Player-Position aktualisieren
			if DragState.source_kind == "world" and DragState.source_node:
				var dl: DroppedLoot = DragState.source_node
				if dl:
					# Position zur aktuellen Player-Position aktualisieren
					var drop_pos := player.global_position + Vector2(0, 24)
					dl.global_position = drop_pos
					dl.item = DragState.item.duplicate(true)
					dl.gold = 0
					dl._update_label()
					dl.visible = true
			# Andernfalls einen neuen DroppedLoot an der aktuellen Spielerposition erzeugen
			elif DragState.item and not DragState.item.is_empty():
				var drop := DroppedLoot.new()
				# Immer aktuelle Player-Position verwenden (auch während Bewegung)
				var drop_pos := player.global_position + Vector2(0, 24)
				drop.setup_drop(drop_pos, 0, DragState.item)
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

	# Drag-Info-Panel unten links aktualisieren
	if drag_info_panel and drag_info_label:
		if DragState.active and not DragState.item.is_empty():
			var item_text := _format_drag_item_info(DragState.item)
			drag_info_label.text = item_text
			drag_info_panel.visible = true
			# Größe an Inhalt anpassen
			drag_info_label.force_update_transform()
			var content_h := drag_info_label.get_content_height()
			var padding := 16.0
			var width := 280.0
			var height := content_h + padding
			if height < 60.0:
				height = 60.0
			drag_info_panel.size = Vector2(width, height)
		else:
			drag_info_panel.visible = false

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


func _format_drag_item_info(item: Dictionary) -> String:
	"""Formatiert Item-Info für das Drag-Info-Panel (temporär für Debug)"""
	if item.is_empty():
		return ""

	var item_name: String = item.get("name", item.get("id", "Unknown"))
	var item_level: int = int(item.get("item_level", 0))
	var min_level: int = int(item.get("min_player_level", 0))
	var item_type: String = String(item.get("item_type", ""))
	var rarity: String = String(item.get("rarity", "normal"))

	# Rarity-Farbe
	var rarity_color: Color = Color.WHITE
	match rarity:
		"normal":
			rarity_color = Color.WHITE
		"magic":
			rarity_color = Color(0.2, 0.4, 1)
		"epic":
			rarity_color = Color(0.7, 0.2, 1)
		"legendary":
			rarity_color = Color(1, 0.9, 0.2)
		"unique":
			rarity_color = Color(1, 0.84, 0.0)

	var sb := "[b][color=%s]%s[/color][/b]\n" % [rarity_color.to_html(false), item_name]
	sb += "Type: %s\n" % item_type
	sb += "Item Level: %d\n" % item_level
	if min_level > 0:
		sb += "Requires Level: %d\n" % min_level

	# Stats
	var stats: Dictionary = item.get("stats", {})
	if not stats.is_empty():
		sb += "\n[b]Stats:[/b]\n"
		for stat_name in stats.keys():
			var value = stats[stat_name]
			if value != 0:
				sb += "%s: %s\n" % [String(stat_name).capitalize(), str(value)]

	# Enchantments
	var enchantments: Array = item.get("enchantments", [])
	if not enchantments.is_empty():
		sb += "\n[b]Enchantments:[/b]\n"
		for enchant in enchantments:
			if enchant is Dictionary:
				var en_name: String = String(enchant.get("name", "?"))
				var en_value = enchant.get("value", 0)
				var suffix := ""
				if en_name.ends_with(" %"):
					en_name = en_name.substr(0, en_name.length() - 2)
					suffix = "%"
				sb += "%s: +%s%s\n" % [en_name, str(en_value), suffix]

	return sb
