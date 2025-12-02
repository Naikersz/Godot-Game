extends Control

## EquipmentSlots - инвентарь + экипировка в HUD
## Логика основана на `inventory_scene.gd`, но адаптирована
## под структуру сцены HUD и drag & drop.

const SLOT_MAP := {
	"weapon": "weapon",
	"helmet": "helmet",
	"chest": "armor",
	"pants": "pants",
	"boot": "boots",
	"boots": "boots",
	"glove": "gloves",
	"gloves": "gloves",
	"shield": "off_hand",
	"off_hand": "off_hand",
	"backpack": "backpack",
	"cloak": "mantal",
	"mantal": "mantal",
	"amulet": "amulet",
	"ring": "ring1",
}

@onready var dim_background: ColorRect = $DimBackground
@onready var window_panel: Panel = $WindowPanel
@onready var title_label: Label = $WindowPanel/TitleBar/TitleLabel
@onready var equipment_grid: Node = $WindowPanel/EquipmentGrid
@onready var inventory_grid: GridContainer = $WindowPanel/InventoryGrid
@onready var tooltip_panel: Panel = $TooltipPanel
@onready var tooltip_label: RichTextLabel = $TooltipPanel/TooltipLabel
@onready var compare_tooltip_panel: Panel = $CompareTooltipPanel
@onready var compare_tooltip_label: RichTextLabel = $CompareTooltipPanel/CompareTooltipLabel

var slot_index: int = 0
var player_name: String = "Unknown"
var player_level: int = 1
var player_data: Dictionary = {}
var equipped_items: Dictionary = {}   # slot_name -> item dict
var inventory_items: Array = []       # список предметов (до 12 штук, остальное можно игнорировать)

# equipment_slots: slot_name -> Panel (узел-слот)
var equipment_slots: Dictionary = {}

# inventory_slots: индекс -> Panel (узел-слот)
var inventory_slots: Array = []

var slot_panel_script := preload("res://scripts/slot_panel.gd")

var _highlight_slot_name: String = ""
var _hovered_item: Dictionary = {}


func _ready() -> void:
	# Пока что жёстко работаем с первым слотом ("save1"),
	# как ты и писал. Если позже нужно сделать выбор слота,
	# можно вернуть Constants.current_slot_index.
	slot_index = 0
	_init_ui()
	_init_slots()
	_load_data()
	_update_all_slots()
	visible = false
	if tooltip_panel:
		tooltip_panel.visible = false
	if compare_tooltip_panel:
		compare_tooltip_panel.visible = false
	set_process(true)


func _init_ui() -> void:
	if title_label:
		title_label.text = "Character / Inventory"


func _init_slots() -> void:
	# Оборудование: 12 слотов, уже размечены в сцене.
	# Привязываем по имени ноды к логическому слоту.
	# Имена логических слотов стараемся делать такими же,
	# какие используются в save-файлах (helmet, armor, gloves, и т.п.)
	var equip_paths = {
		"helmet": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer/Helmet",
		"armor": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer/Armor",
		"pants": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer/Pants",
		"boots": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer/Boots",
		"gloves": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer2/Gloves",
		"weapon": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer2/Weapon",
		"backpack": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer3/Backpack",
		"off_hand": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer3/Off-Hand",
		"mantal": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer4/Mantal",
		"amulet": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer4/Amulet",
		"ring1": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer4/Ring1",
		"ring2": "WindowPanel/EquipmentGrid/HBoxContainer/VBoxContainer4/Ring2",
	}

	for slot_name in equip_paths.keys():
		var path: String = equip_paths[slot_name]
		var node = get_node_or_null(path)
		if node and node is Panel:
			var panel: Panel = node
			panel.set_script(slot_panel_script)
			panel.slot_id = slot_name
			panel.slot_kind = "equipment"
			panel.manager = self
			panel.mouse_entered.connect(_on_slot_mouse_entered.bind("equipment", slot_name))
			panel.mouse_exited.connect(_on_slot_mouse_exited)
			equipment_slots[slot_name] = panel

	# Инвентарь: 12 панелей внутри GridContainer
	inventory_slots.clear()
	var children = inventory_grid.get_children()
	for i in range(children.size()):
		if children[i] is Panel:
			var inv_panel: Panel = children[i]
			inv_panel.set_script(slot_panel_script)
			inv_panel.slot_id = str(i)
			inv_panel.slot_kind = "inventory"
			inv_panel.manager = self
			inv_panel.mouse_entered.connect(_on_slot_mouse_entered.bind("inventory", i))
			inv_panel.mouse_exited.connect(_on_slot_mouse_exited)
			inventory_slots.append(inv_panel)


func _load_data() -> void:
	var slot = Constants.SAVE_SLOTS[slot_index]
	var save_path = Constants.get_save_path(slot)
	var player_path = Constants.get_player_path(slot)
	var inventory_path = save_path.path_join("global_inventory.json")

	# Player (полностью копируем поведение из inventory_scene.gd)
	if FileAccess.file_exists(player_path):
		var file = FileAccess.open(player_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var json_obj: JSON = JSON.new()
			if json_obj.parse(json_string) == OK:
				var raw_data = json_obj.data
				if raw_data is Dictionary:
					player_data = raw_data
					player_name = player_data.get("name", "Unknown")
					player_level = player_data.get(
						"level",
						player_data.get("stats", {}).get("level", 1)
					)
					var raw_equipped = player_data.get("equipped", {})
					if raw_equipped is Dictionary:
						equipped_items = raw_equipped
					else:
						equipped_items = {}
				else:
					equipped_items = {}
			else:
				equipped_items = {}
		else:
			equipped_items = {}
	else:
		equipped_items = {}

	# Inventory (как в inventory_scene.gd — без проверки типа)
	if FileAccess.file_exists(inventory_path):
		var inv_file = FileAccess.open(inventory_path, FileAccess.READ)
		if inv_file:
			var json_string_inv = inv_file.get_as_text()
			inv_file.close()
			var json_obj_inv: JSON = JSON.new()
			if json_obj_inv.parse(json_string_inv) == OK:
				inventory_items = json_obj_inv.data
			else:
				inventory_items = []
		else:
			inventory_items = []
	else:
		inventory_items = []


func _save_data() -> void:
	var slot = Constants.SAVE_SLOTS[slot_index]
	var save_path = Constants.get_save_path(slot)
	var player_path = Constants.get_player_path(slot)
	var inventory_path = save_path.path_join("global_inventory.json")

	# Player
	if not player_data.is_empty():
		player_data["equipped"] = equipped_items
		var file = FileAccess.open(player_path, FileAccess.WRITE)
		if file:
			file.store_string(JSON.stringify(player_data, "\t"))
			file.close()

	# Inventory
	var inv_file = FileAccess.open(inventory_path, FileAccess.WRITE)
	if inv_file:
		inv_file.store_string(JSON.stringify(inventory_items, "\t"))
		inv_file.close()


func _update_all_slots() -> void:
	_update_equipment_slots()
	_update_inventory_slots()


func _get_or_create_label(panel: Panel) -> Label:
	# Ищем IconLabel рекурсивно, потому что он может быть дочерним у TextureRect
	var label: Label = panel.find_child("IconLabel", true, false) as Label
	if label:
		return label

	# Если лейбла нет вообще (например, slot_panel.gd не отработал),
	# создаём его здесь.
	label = Label.new()
	label.name = "IconLabel"
	label.anchor_left = 0.0
	label.anchor_top = 0.0
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 0.0
	label.offset_top = 0.0
	label.offset_right = 0.0
	label.offset_bottom = 0.0
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.z_index = 10
	# Настройка внешнего вида текста
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", 22)
	panel.add_child(label)
	return label


func _highlight_for_item(item: Dictionary) -> void:
	_clear_highlight()
	if item.is_empty():
		return
	var item_type: String = String(item.get("item_type", "")).to_lower()
	if item_type == "":
		return
	var slot_name = SLOT_MAP.get(item_type, "")
	if slot_name == "" or not equipment_slots.has(slot_name):
		return
	_highlight_slot_name = slot_name

	# При перетаскивании:
	# - один подходящий слот делаем светлым,
	# - остальные 11 сильно темним.
	for name in equipment_slots.keys():
		var panel: Panel = equipment_slots[name]
		if name == slot_name:
			# Жёлтоватый оттенок, чтобы было видно, куда подходит предмет
			panel.modulate = Color(1.0, 0.95, 0.7, 1.0)
		else:
			panel.modulate = Color(0.25, 0.25, 0.25, 1.0)


func _clear_highlight() -> void:
	if _highlight_slot_name == "":
		return
	# Переотрисовываем все слоты экипировки в нормальных цветах
	_highlight_slot_name = ""
	_update_equipment_slots()


func _on_slot_mouse_entered(kind: String, id) -> void:
	var item: Dictionary = _get_item_from_slot(kind, str(id))
	if item.is_empty():
		_hovered_item = {}
		_hide_tooltip()
	else:
		_hovered_item = item
		_show_tooltip(item)


func _on_slot_mouse_exited() -> void:
	_hovered_item = {}
	_hide_tooltip()


func _update_equipment_slots() -> void:
	for slot_name in equipment_slots.keys():
		var panel: Panel = equipment_slots[slot_name]
		# Безопасно получаем предмет: некоторые слоты в save могут быть null
		var item: Dictionary = _get_item_from_slot("equipment", slot_name)

		var has_item := item is Dictionary and not (item as Dictionary).is_empty()
		var label := _get_or_create_label(panel)
		# Простая визуализация: маленькая "иконка" — первая буква имени
		if has_item:
			var item_name: String = item.get("name", item.get("id", "Item"))
			# Не используем встроенный tooltip_text, чтобы не было
			# второго (тёмного) тултипа Godot — всё делаем через
			# наше кастомное hover‑окно.
			panel.tooltip_text = ""
			panel.modulate = Color(1, 1, 1, 1)
			if label:
				label.text = item_name.substr(0, 1).to_upper()
		else:
			panel.modulate = Color(0.8, 0.8, 0.8, 1)
			if label:
				label.text = ""


func _update_inventory_slots() -> void:
	for i in range(inventory_slots.size()):
		var panel: Panel = inventory_slots[i]
		var label: Label = _get_or_create_label(panel)
		if i < inventory_items.size():
			var item: Dictionary = inventory_items[i]
			if item is Dictionary and not (item as Dictionary).is_empty():
				var item_name: String = item.get("name", item.get("id", "Item"))
				# Занятый слот делаем заметно светлее
				panel.modulate = Color(1, 1, 1, 1)
				if label:
					label.text = item_name.substr(0, 1).to_upper()
			else:
				# Пустой, но "активный" слот
				panel.modulate = Color(0.55, 0.55, 0.55, 1)
				if label:
					label.text = ""
		else:
			# Слот вне диапазона инвентаря — самый тёмный
			panel.modulate = Color(0.3, 0.3, 0.3, 1)
			if label:
				label.text = ""


func _process(_delta: float) -> void:
	if tooltip_panel and tooltip_panel.visible:
		var mouse_pos: Vector2 = get_global_mouse_position()
		var viewport_rect: Rect2 = get_viewport_rect()

		var main_size: Vector2 = tooltip_panel.size
		var compare_size: Vector2 = compare_tooltip_panel.size if compare_tooltip_panel and compare_tooltip_panel.visible else Vector2.ZERO

		# Сначала позиция основного тултипа
		var tooltip_pos: Vector2 = mouse_pos + Vector2(16, 16)
		if tooltip_pos.x + main_size.x > viewport_rect.size.x:
			tooltip_pos.x = mouse_pos.x - main_size.x - 16
		if tooltip_pos.y + main_size.y > viewport_rect.size.y:
			tooltip_pos.y = mouse_pos.y - main_size.y - 16
		tooltip_panel.global_position = tooltip_pos

		# Затем позиция сравнения: справа или слева от основного
		if compare_tooltip_panel and compare_tooltip_panel.visible:
			var compare_pos: Vector2 = tooltip_pos + Vector2(main_size.x + 12.0, 0.0)
			# Если справа не влезает — ставим слева
			if compare_pos.x + compare_size.x > viewport_rect.size.x:
				compare_pos.x = tooltip_pos.x - compare_size.x - 12.0
			# Вертикально подстраиваем, чтобы не вылезал
			if compare_pos.y + compare_size.y > viewport_rect.size.y:
				compare_pos.y = max(0.0, viewport_rect.size.y - compare_size.y - 4.0)
			compare_tooltip_panel.global_position = compare_pos


func _show_tooltip(item: Dictionary) -> void:
	if not tooltip_panel:
		return
	if item.is_empty():
		tooltip_panel.visible = false
		if compare_tooltip_panel:
			compare_tooltip_panel.visible = false
		return

	var text := _format_item_tooltip(item)
	tooltip_label.text = text
	# Подгоняем размер под содержимое: фиксированная ширина, динамическая высота
	var content_h: float = tooltip_label.get_content_height()
	var padding: float = 12.0
	var width: float = max(260.0, tooltip_panel.size.x)
	tooltip_panel.size = Vector2(width, content_h + padding)
	tooltip_panel.visible = true

	_show_compare_tooltip(item)


func _hide_tooltip() -> void:
	if tooltip_panel:
		tooltip_panel.visible = false
	if compare_tooltip_panel:
		compare_tooltip_panel.visible = false


func _format_item_tooltip(item: Dictionary) -> String:
	if item.is_empty():
		return ""

	var name: String = item.get("name", item.get("id", "Unknown"))
	var item_level: int = int(item.get("item_level", 0))
	var min_level: int = int(item.get("min_player_level", 0))

	var enchantments: Array = item.get("enchantments", [])

	# Цвет редкости на основе rarity-строки
	var rarity: String = String(item.get("rarity", "normal"))
	var rarity_color: Color = _get_color_for_rarity(rarity)

	var sb := "[b][color=%s]%s[/color][/b]\n" % [rarity_color.to_html(false), name]
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
	if not enchantments.is_empty():
		sb += "\n[b]Enchantments:[/b]\n"
		for enchant in enchantments:
			if enchant is Dictionary:
				var en_name: String = String(enchant.get("name", "?"))
				var en_value = enchant.get("value", 0)
				# Если в названии есть " %", переносим знак процента к числу,
				# чтобы показывалось как "+3.0%" вместо "%: +3.0"
				var suffix := ""
				if en_name.ends_with(" %"):
					en_name = en_name.substr(0, en_name.length() - 2)
					suffix = "%"
				sb += "%s: +%s%s\n" % [en_name, str(en_value), suffix]

	return sb


func _show_compare_tooltip(new_item: Dictionary) -> void:
	if not compare_tooltip_panel:
		return

	# Определяем слот, к которому относится предмет
	var item_type: String = String(new_item.get("item_type", "")).to_lower()
	if item_type == "":
		compare_tooltip_panel.visible = false
		return
	var slot_name = SLOT_MAP.get(item_type, "")
	if slot_name == "" or not equipped_items.has(slot_name):
		compare_tooltip_panel.visible = false
		return

	var equipped_item: Dictionary = _get_item_from_slot("equipment", slot_name)
	if equipped_item.is_empty():
		compare_tooltip_panel.visible = false
		return

	var text := _format_compare_tooltip(new_item, equipped_item, slot_name)
	compare_tooltip_label.text = text

	var content_h: float = compare_tooltip_label.get_content_height()
	var padding: float = 12.0
	var width: float = max(260.0, compare_tooltip_panel.size.x)
	compare_tooltip_panel.size = Vector2(width, content_h + padding)
	compare_tooltip_panel.visible = true


func _format_compare_tooltip(new_item: Dictionary, old_item: Dictionary, slot_name: String) -> String:
	var new_stats: Dictionary = new_item.get("stats", {})
	var old_stats: Dictionary = old_item.get("stats", {})

	var name_new: String = new_item.get("name", new_item.get("id", "New"))
	var name_old: String = old_item.get("name", old_item.get("id", "Current"))

	var sb := "[b]Equipped %s:[/b]\n%s\n\n" % [slot_name.capitalize(), name_old]
	sb += "[b]Change if equipped:[/b]\n"

	# Берём объединение ключей из обоих наборов статов
	var keys: Array = []
	for k in new_stats.keys():
		if not keys.has(k):
			keys.append(k)
	for k in old_stats.keys():
		if not keys.has(k):
			keys.append(k)

	for k in keys:
		var new_val: float = float(new_stats.get(k, 0))
		var old_val: float = float(old_stats.get(k, 0))
		if new_val == 0 and old_val == 0:
			continue
		var diff: float = new_val - old_val
		var line := "%s: %.2f (current: %.2f" % [String(k).capitalize(), new_val, old_val]
		if abs(diff) > 0.0001:
			if diff > 0:
				line += ", [color=green]+%.2f[/color]" % diff
			else:
				line += ", [color=red]%.2f[/color]" % diff
		line += ")\n"
		sb += line

	return sb


func _get_color_for_rarity(rarity: String) -> Color:
	match rarity:
		"normal":
			return Color(1, 1, 1)       # Weiß
		"magic":
			return Color(0.2, 0.4, 1)   # Blau
		"epic":
			return Color(0.7, 0.2, 1)   # Lila
		"legendary":
			return Color(1, 0.9, 0.2)   # Gelb
		"unique":
			return Color(1, 0.84, 0.0)  # Gold
		_:
			return Color(1, 1, 1)


## === Drag & Drop API для slot_panel.gd ===

func slot_get_drag_data(slot_node: Node) -> Variant:
	if not (slot_node is Panel):
		return null

	var kind: String = slot_node.slot_kind
	var id: String = slot_node.slot_id

	var item: Dictionary = _get_item_from_slot(kind, id)
	if item == null:
		return null
	if not (item is Dictionary) or (item as Dictionary).is_empty():
		return null

	# Подсвечиваем подходящий слот экипировки (если есть)
	_highlight_for_item(item)

	var drag_data := {
		"item": item,
		"source_kind": kind,
		"source_id": id,
	}

	# Простой превью (полупрозрачный прямоугольник)
	var preview := ColorRect.new()
	preview.color = Color(1, 1, 1, 0.4)
	preview.custom_minimum_size = Vector2(48, 48)
	slot_node.set_drag_preview(preview)

	return drag_data


func slot_can_drop_data(slot_node: Node, data: Variant) -> bool:
	if not (slot_node is Panel):
		return false
	if typeof(data) != TYPE_DICTIONARY:
		return false
	if not data.has("item"):
		return false

	var kind: String = slot_node.slot_kind
	if kind == "equipment":
		# Для слотов экипировки проверяем тип предмета
		var slot_name: String = slot_node.slot_id
		var item: Dictionary = data["item"]
		var item_type: String = String(item.get("item_type", "")).to_lower()
		var target_slot: String = SLOT_MAP.get(item_type, "")
		return target_slot == slot_name or target_slot == ""
	elif kind == "inventory":
		# Любой предмет может лежать в инвентаре
		return true

	return false


func slot_drop_data(slot_node: Node, data: Variant) -> void:
	if typeof(data) != TYPE_DICTIONARY:
		return
	if not data.has("item"):
		return

	var target_kind: String = slot_node.slot_kind
	var target_id: String = slot_node.slot_id

	var source_kind: String = data.get("source_kind", "")
	var source_id: String = data.get("source_id", "")
	var item: Dictionary = data["item"]

	if target_kind == "equipment":
		_drop_to_equipment(target_id, source_kind, source_id, item)
	elif target_kind == "inventory":
		_drop_to_inventory(int(target_id), source_kind, source_id, item)

	_clear_highlight()
	_save_data()
	_update_all_slots()


## === Вспомогательные методы ===

func _get_item_from_slot(kind: String, id: String) -> Dictionary:
	if kind == "equipment":
		var raw = equipped_items.get(id, null)
		if raw is Dictionary:
			return raw
		return {}
	elif kind == "inventory":
		var index := int(id)
		if index >= 0 and index < inventory_items.size():
			var raw_inv = inventory_items[index]
			if raw_inv is Dictionary:
				return raw_inv
			return {}
	return {}


func _set_item_to_slot(kind: String, id: String, item: Dictionary) -> void:
	if kind == "equipment":
		equipped_items[id] = item
	elif kind == "inventory":
		var index := int(id)
		if index >= 0:
			while index >= inventory_items.size():
				inventory_items.append({})
			inventory_items[index] = item


func _clear_slot(kind: String, id: String) -> void:
	if kind == "equipment":
		equipped_items[id] = {}
	elif kind == "inventory":
		var index := int(id)
		if index >= 0 and index < inventory_items.size():
			inventory_items[index] = {}


func _drop_to_equipment(target_slot: String, source_kind: String, source_id: String, item: Dictionary) -> void:
	# Если перетаскиваем из инвентаря в экипировку
	if source_kind == "inventory":
		var source_index := int(source_id)
		if source_index < 0 or source_index >= inventory_items.size():
			return

		# Меняем местами с текущим предметом в слоте (если есть)
		var prev_raw = equipped_items.get(target_slot, null)
		var prev_item: Dictionary = {}
		if prev_raw is Dictionary:
			prev_item = prev_raw

		equipped_items[target_slot] = item

		if not prev_item.is_empty():
			inventory_items[source_index] = prev_item
		else:
			inventory_items[source_index] = {}

	# Перемещение внутри экипировки
	elif source_kind == "equipment":
		if source_id == target_slot:
			return
		var source_raw = equipped_items.get(source_id, null)
		var target_raw = equipped_items.get(target_slot, null)
		var source_item: Dictionary = {}
		var target_item: Dictionary = {}
		if source_raw is Dictionary:
			source_item = source_raw
		if target_raw is Dictionary:
			target_item = target_raw
		equipped_items[target_slot] = source_item
		equipped_items[source_id] = target_item


func _drop_to_inventory(target_index: int, source_kind: String, source_id: String, item: Dictionary) -> void:
	if target_index < 0:
		return

	# Убедимся, что массив достаточно длинный
	while target_index >= inventory_items.size():
		inventory_items.append({})

	# Из экипировки в инвентарь
	if source_kind == "equipment":
		var prev_item: Dictionary = {}
		if target_index < inventory_items.size() and inventory_items[target_index] is Dictionary:
			prev_item = inventory_items[target_index]
		inventory_items[target_index] = item
		equipped_items[source_id] = prev_item

	# Внутри инвентаря
	elif source_kind == "inventory":
		var source_index := int(source_id)
		if source_index < 0 or source_index >= inventory_items.size():
			return
		if source_index == target_index:
			return
		var tmp = inventory_items[target_index]
		inventory_items[target_index] = inventory_items[source_index]
		inventory_items[source_index] = tmp


## Публичный метод для HUD, чтобы открыть/закрыть окно
func toggle_visible() -> void:
	visible = not visible
	if dim_background:
		dim_background.visible = visible
	if visible:
		# При каждом открытии перечитываем данные и перерисовываем слоты,
		# чтобы лут из сейва всегда был актуален.
		_load_data()
		_update_all_slots()
