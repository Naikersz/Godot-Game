extends Control

## EquipmentSlots - inventory + equipment in HUD
## Temporarily disabled logic for rebuild; UI layout stays.

const INVENTORY_DISABLED := false

const SLOT_MAP: Dictionary = {
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
	# Ringe dürfen in ring1 und ring2, deshalb Spezialbehandlung in _item_fits_slot
	"ring": "ring",
	# Optional: Waffen, die off_hand_allowed=true haben, dürfen in off_hand
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
var equipped_items: Dictionary = {}   # slot_name -> ItemStack oder null
var inventory_items: Array = []       # Array[ItemStack oder null]

# equipment_slots: slot_name -> Panel (узел-слот)
var equipment_slots: Dictionary = {}

# inventory_slots: индекс -> Panel (узел-слот)
var inventory_slots: Array = []

var slot_panel_script := preload("res://scripts/slot_panel.gd")
# DragState ist eine globale Klasse (class_name) und muss nicht preloaded werden

var _highlight_slot_name: String = ""
var _hovered_item: Dictionary = {}
var _drag_from_inventory: Dictionary = {}   # bleibt vorerst als Fallback für Inventar->Welt-Drop

# Sortier-Cooldown-System
var _sort_cooldown_timer: float = 0.0
const SORT_COOLDOWN_TIME: float = 3.0
var _current_sort_mode: int = 0  # 0 = Level, 1 = Rarity+Level, 2 = Type+Rarity+Level

const INV_TRES_NAME := "inventory.tres"
const INV_DEBUG_NAME := "inventory_debug.json"
const ItemStackRes := preload("res://resources/item_stack.gd")
const ItemRes := preload("res://resources/item.gd")
const ItemTypeRes := preload("res://resources/item_type.gd")
const ItemRegistryRes = preload("res://scripts/item_registry.gd")
var _registry: ItemRegistryClass = null
const MAX_BASE_SLOTS := 12


func _ready() -> void:
	# Verwende den aktuell gewählten Save-Slot
	slot_index = int(Constants.current_slot_index)
	_init_ui()
	_init_slots()
	if INVENTORY_DISABLED:
		visible = false
		if tooltip_panel:
			tooltip_panel.visible = false
		if compare_tooltip_panel:
			compare_tooltip_panel.visible = false
		set_process(false)
		return
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
	var _player_path = Constants.get_player_path(slot)
	var player_res_path = save_path.path_join("player.tres")
	var _player_debug_path = save_path.path_join("player_debug.json")
	var inventory_res_path = save_path.path_join(INV_TRES_NAME)
	var _inventory_debug_path = save_path.path_join(INV_DEBUG_NAME)

	# Player bevorzugt aus Resource laden, JSON nur Migration
	var player_loaded := false
	if ResourceLoader.exists(player_res_path):
		var res = ResourceLoader.load(player_res_path)
		if res is PlayerResource:
			player_loaded = true
			player_data = {}  # optional: could mirror fields if needed
			player_name = res.player_name
			player_level = res.player_level
			equipped_items = res.equipped.duplicate(true)
			# Backpack slots
			if res.backpack_slots > 0:
				player_data["backpack_slots"] = res.backpack_slots
	# Fallback: Migration aus player.json
	if not player_loaded and FileAccess.file_exists(_player_path):
		var file = FileAccess.open(_player_path, FileAccess.READ)
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
		# wenn weder Ressource noch JSON -> leer
		if not player_loaded:
			equipped_items = {}

	# Nach Laden: Dictionaries in ItemStacks wandeln
	for slot_name in equipped_items.keys():
		var val = equipped_items[slot_name]
		if val is Dictionary:
			equipped_items[slot_name] = _stack_from_dict(val)
		elif val == null:
			equipped_items[slot_name] = null

	# Inventory: Resource zuerst, JSON nur Migration
	var inv_res: InventoryResource = _load_inventory_res(inventory_res_path)
	if inv_res:
		inventory_items = inv_res.items.duplicate(true)
	else:
		var migrated := _migrate_inventory_json(save_path.path_join("inventory.json"), equipped_items)
		inventory_items = migrated
	# Fülle auf mindestens 12 Slots mit null
	while inventory_items.size() < MAX_BASE_SLOTS:
		inventory_items.append(null)


func refresh_from_save() -> void:
	# Öffentliche Methode, um Inventar/Equipped aus den Save-Dateien neu zu laden
	# (z.B. wenn Loot außerhalb dieses UIs hinzugefügt wurde).
	_load_data()
	_update_all_slots()


func _save_data() -> void:
	var slot = Constants.SAVE_SLOTS[slot_index]
	var save_path = Constants.get_save_path(slot)
	var _player_path = Constants.get_player_path(slot)
	var player_res_path = save_path.path_join("player.tres")
	var inventory_res_path = save_path.path_join(INV_TRES_NAME)

	# Убеждаемся, что папка существует
	var dir = DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive("save/" + slot)
	else:
		print("❌ Ошибка: не удалось открыть user:// директорию для сохранения")
		return

	# Player als Resource speichern, JSON nur Debug
	var player_res := PlayerResource.new()
	player_res.player_name = player_name
	player_res.player_level = player_level
	player_res.backpack_slots = _get_backpack_slots_from_equipped(equipped_items)
	player_res.equipped = equipped_items.duplicate(true)
	var res_err = ResourceSaver.save(player_res, player_res_path)
	if res_err != OK:
		print("❌ Fehler beim Speichern player.tres: ", player_res_path, " err=", res_err)

	# Inventory speichern (Resource + Debug JSON)
	var inv_res_out := InventoryResource.new()
	inv_res_out.items = _cleanup_stack_array(inventory_items)
	inv_res_out.merge_stacks()
	_save_inventory_res(inventory_res_path, inv_res_out)


# Registry laden
func _get_registry() -> ItemRegistryClass:
	if _registry != null:
		return _registry
	if Engine.has_singleton("ItemRegistry"):
		_registry = Engine.get_singleton("ItemRegistry")
	else:
		_registry = ItemRegistryRes.new()
	return _registry

func _load_inventory_res(path: String) -> InventoryResource:
	if ResourceLoader.exists(path):
		var res = ResourceLoader.load(path)
		if res is InventoryResource:
			return res
	return null

func _save_inventory_res(path: String, inv: InventoryResource) -> void:
	var err = ResourceSaver.save(inv, path)
	if err != OK:
		print("⚠️ Konnte InventoryResource nicht speichern:", path, " err=", err)


func _migrate_inventory_json(old_path: String, equipped: Dictionary) -> Array:
	if not FileAccess.file_exists(old_path):
		return []
	var inv_file = FileAccess.open(old_path, FileAccess.READ)
	if inv_file == null:
		return []
	var inv_str = inv_file.get_as_text()
	inv_file.close()
	var inv_json: JSON = JSON.new()
	if inv_json.parse(inv_str) != OK or not (inv_json.data is Array):
		return []
	var out: Array = []
	# Align to slots based on inventar_slot and capacity
	var raw: Array = inv_json.data
	var max_slot := 0
	for entry in raw:
		if entry is Dictionary:
			var pos: Variant = entry.get("position", {})
			if pos is Dictionary and pos.has("inventar_slot"):
				max_slot = max(max_slot, int(pos.get("inventar_slot", 0)))
	var capacity := max_slot
	var backpack_slots := _get_backpack_slots_from_equipped(equipped)
	if backpack_slots > capacity:
		capacity = backpack_slots
	if capacity < MAX_BASE_SLOTS:
		capacity = MAX_BASE_SLOTS
	for i in range(capacity):
		out.append(null)
	for entry in raw:
		if entry is Dictionary:
			var ordered: Dictionary = entry
			var pos2: Variant = ordered.get("position", {})
			if pos2 is Dictionary and pos2.has("inventar_slot"):
				var idx = int(pos2.get("inventar_slot", 0)) - 1
				if idx >= 0 and idx < out.size():
					out[idx] = _stack_from_dict(ordered)
				else:
					out.append(_stack_from_dict(ordered))
			else:
				# place in first empty
				var placed := false
				for j in range(out.size()):
					if out[j] == null:
						out[j] = _stack_from_dict(ordered)
						placed = true
						break
				if not placed:
					out.append(_stack_from_dict(ordered))
	return out

# ==== Stack/Dict Helpers ====

func _stack_from_dict(item: Dictionary) -> ItemStack:
	if item == null or item.is_empty():
		return null
	var reg := _get_registry()
	if reg == null:
		return _stack_minimal(item)
	var id := String(item.get("id", ""))
	if id == "":
		id = String(item.get("name", ""))
	if id == "":
		return _stack_minimal(item)
	var itm = reg.get_item(id)
	if itm == null:
		itm = _item_minimal(item, id)
		if itm == null:
			return null
	# carry instance-level info
	var type_name := String(item.get("item_type", "")).to_lower()
	if item.has("item_level"):
		itm.item_level = int(item.get("item_level", 1))
	if item.has("requirements"):
		itm.requirements = item.get("requirements", {})
	if item.has("material"):
		itm.material = item.get("material", {})
	if item.has("enchantments") and not _is_consumable_type(type_name):
		itm.enchantments = item.get("enchantments", [])
	if item.has("min_player_level"):
		itm.set_meta("min_player_level", int(item.get("min_player_level", 1)))
	var st := ItemStackRes.new()
	st.item = itm
	st.amount = int(item.get("amount", 1))
	if st.amount < 1:
		st.amount = 1
	
	# Alle Metadaten aus Dictionary kopieren
	if item.has("item_level"):
		st.set_meta("item_level", int(item.get("item_level", 0)))
	if item.has("position"):
		st.set_meta("position", item.get("position"))
	if item.has("enchantments") and not _is_consumable_type(type_name):
		st.set_meta("enchantments", item.get("enchantments", []))
	if item.has("material") and not _is_consumable_type(type_name):
		st.set_meta("material", item.get("material", {}))
	if item.has("min_player_level"):
		st.set_meta("min_player_level", int(item.get("min_player_level", 1)))
	
	# Alle anderen Dictionary-Keys als Metadaten kopieren (falls vorhanden)
	for key in item.keys():
		if key in ["id", "name", "rarity", "item_type", "item_level", "description", 
				   "amount", "stackable", "max_stack", "stats", "requirements", 
				   "enchant_slots", "enchantments", "material", "min_player_level", "position"]:
			continue  # Diese werden bereits behandelt oder sind Item-Eigenschaften
		# Alle anderen Keys als Metadaten kopieren
		if not st.has_meta(key):
			st.set_meta(key, item[key])
	
	return st

func _item_minimal(dict: Dictionary, id: String) -> Item:
	var itm := ItemRes.new()
	itm.id = id
	itm.name = String(dict.get("name", id))
	itm.rarity = String(dict.get("rarity", "normal"))
	itm.item_level = int(dict.get("item_level", 1))
	itm.description = String(dict.get("description", ""))
	itm.enchant_slots = int(dict.get("enchant_slots", 0))
	itm.stats = dict.get("stats", {})
	itm.requirements = dict.get("requirements", {})
	itm.material = dict.get("material", {})
	itm.enchantments = dict.get("enchantments", [])
	var t := ItemTypeRes.new()
	t.tab_name = String(dict.get("item_type", ""))
	t.stackable = bool(dict.get("stackable", false))
	t.max_stack = int(dict.get("max_stack", (20 if t.stackable else 1)))
	itm.item_type = t
	return itm

func _stack_minimal(dict: Dictionary) -> ItemStack:
	var id := String(dict.get("id", dict.get("name", "")))
	if id == "":
		return null
	var st := ItemStackRes.new()
	st.item = _item_minimal(dict, id)
	st.amount = max(1, int(dict.get("amount", 1)))
	return st

func _dict_from_stack(st: Variant) -> Dictionary:
	if st is ItemStack and st.item:
		var itm = st.item
		var pos_meta = st.get_meta("position") if st.has_meta("position") else {}
		var item_level_meta = st.get_meta("item_level") if st.has_meta("item_level") else itm.item_level
		var type_name: String = itm.item_type.tab_name.to_lower() if itm.item_type else ""
		var ench_meta = [] if _is_consumable_type(type_name) else (itm.enchantments if itm.enchantments.size() > 0 else (st.get_meta("enchantments") if st.has_meta("enchantments") else []))
		var req_meta = itm.requirements if itm.has_method("get") else {}
		var material_meta = {} if _is_consumable_type(type_name) else (st.get_meta("material") if st.has_meta("material") else itm.material if itm.has_method("get") else {})
		var min_lvl_meta = st.get_meta("min_player_level") if st.has_meta("min_player_level") else 1
		
		# Prüfe, ob es ein Consumable ist (für stackable-Fallback)
		var is_consumable: bool = _is_consumable_type(type_name)
		var stackable_val: bool = itm.item_type.stackable if itm.item_type else is_consumable
		
		var result := {
			"id": itm.id,
			"name": itm.name,
			"rarity": itm.rarity,
			"item_type": itm.item_type.tab_name if itm.item_type else "",
			"item_level": item_level_meta,
			"description": itm.description,
			"material": material_meta,
			"min_player_level": min_lvl_meta,
			"amount": st.amount,
			"stackable": stackable_val,
			"max_stack": itm.item_type.max_stack if itm.item_type else (20 if is_consumable else 1),
			"stats": itm.stats,
			"requirements": req_meta,
			"enchant_slots": itm.enchant_slots,
			"enchantments": ench_meta,
			"position": pos_meta,
		}
		
		# Alle anderen Metadaten hinzufügen
		var all_meta_keys: Array = st.get_meta_list()
		for key in all_meta_keys:
			if key in ["item_level", "position", "enchantments", "material", "min_player_level"]:
				continue  # Diese wurden bereits behandelt
			result[key] = st.get_meta(key)
		
		return result
	return {}

func _cleanup_stack_array(arr: Array) -> Array:
	var cleaned: Array = []
	for entry in arr:
		if entry is ItemStack and entry.item != null and entry.amount > 0:
			cleaned.append(entry)
		else:
			cleaned.append(null)
	return cleaned

func _stacks_can_merge(a: ItemStack, b: ItemStack) -> bool:
	if a == null or b == null or a.item == null or b.item == null:
		return false
	if a.item != b.item:
		return false
	if a.item.item_type == null or not a.item.item_type.stackable:
		return false
	return true

func _max_stack_stack(st: ItemStack) -> int:
	if st == null or st.item == null or st.item.item_type == null:
		return 1
	return max(1, st.item.item_type.max_stack)

func _merge_stack_into_slot_stack(target_index: int, incoming: ItemStack) -> ItemStack:
	if incoming == null or incoming.item == null:
		return null
	if target_index < 0:
		return incoming
	while target_index >= inventory_items.size():
		inventory_items.append(null)
	var existing: ItemStack = null
	if inventory_items[target_index] is ItemStack:
		existing = inventory_items[target_index]
	if existing == null:
		inventory_items[target_index] = incoming
		return null
	if not _stacks_can_merge(existing, incoming):
		return incoming
	var max_s := _max_stack_stack(existing)
	var space: int = max_s - existing.amount
	if space <= 0:
		return incoming
	var add_amt: int = min(space, incoming.amount)
	existing.amount += add_amt
	incoming.amount -= add_amt
	if incoming.amount <= 0:
		return null
	return incoming


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

	var slot_names: Array = _get_slot_names_for_item(item)
	if slot_names.is_empty():
		return

	_highlight_slot_name = slot_names[0] if slot_names.size() > 0 else ""

	# Highlight only compatible equipment slots (ring -> both ring slots, off_hand_allowed weapon -> weapon/off_hand)
	for slot_name_iter in equipment_slots.keys():
		var panel: Panel = equipment_slots[slot_name_iter]
		if slot_names.has(slot_name_iter):
			# Brighter golden tint for valid targets
			panel.modulate = Color(1.0, 0.9, 0.5, 1.0)
		else:
			# Reset others to normal (no dimming)
			panel.modulate = Color(1, 1, 1, 1)

	# 6b: Wenn ein Equipment-Item gezogen wird, Inventar-Slots ausgrauen,
	# wenn das Item nicht zurück ins Inventar darf (z.B. Equipment-only Items)
	# Aktuell erlauben wir alle Items im Inventar, daher keine Ausgrauung nötig.
	# Falls später Equipment-only Items eingeführt werden, hier Logik ergänzen.


func _get_slot_names_for_item(item: Dictionary) -> Array:
	var t := String(item.get("item_type", "")).to_lower()
	# Ringe: beide Slots erlaubt
	if t == "ring":
		return ["ring1", "ring2"]
	# 7a: Off-Hand-Waffen erlauben, wenn off_hand_allowed == true
	if t == "weapon" and bool(item.get("off_hand_allowed", false)):
		return ["weapon", "off_hand"]
	# sonst Mapping laut SLOT_MAP
	var mapped = SLOT_MAP.get(t, "")
	if mapped == "":
		return []
	if mapped == "ring":
		return ["ring1", "ring2"]
	return [mapped]


func _item_fits_slot(item: Dictionary, slot_name: String) -> bool:
	var slot_names := _get_slot_names_for_item(item)
	return slot_names.has(slot_name)

func _item_fits_slot_stack(stack: ItemStack, slot_name: String) -> bool:
	if stack == null or stack.item == null:
		return false
	var dict := _dict_from_stack(stack)
	return _item_fits_slot(dict, slot_name)


func highlight_for_world_item(item: Dictionary) -> void:
	# Öffentliche Wrapper-Methode, damit HUD/DroppedLoot dieselbe Highlight-Logik
	# wie das normale Inventar-Drag verwenden kann.
	_highlight_for_item(item)


func clear_world_highlight() -> void:
	_clear_highlight()


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
			# Hintergrund in Rarity-Farbe, aber dunkler und leicht transparent
			var rarity: String = String(item.get("rarity", "normal"))
			var rarity_color: Color = _get_color_for_rarity(rarity)
			# Farbe dunkler machen (0.15 = sehr dunkel) und leicht transparent (Alpha 0.4)
			var bg_color := Color(rarity_color.r * 0.15, rarity_color.g * 0.15, rarity_color.b * 0.15, 0.4)
			# StyleBox erstellen oder vorhandenen verwenden
			var style_box: StyleBoxFlat = null
			if panel.has_theme_stylebox_override("panel"):
				style_box = panel.get_theme_stylebox("panel") as StyleBoxFlat
			if style_box == null:
				style_box = StyleBoxFlat.new()
			style_box.bg_color = bg_color
			panel.add_theme_stylebox_override("panel", style_box)
			panel.modulate = Color(1, 1, 1, 1)
			if label:
				label.text = item_name.substr(0, 1).to_upper()
				# Rarity-Farbe für den Buchstaben
				label.add_theme_color_override("font_color", rarity_color)
		else:
			# Leerer Slot: Standard-Hintergrund
			var style_box: StyleBoxFlat = null
			if panel.has_theme_stylebox_override("panel"):
				style_box = panel.get_theme_stylebox("panel") as StyleBoxFlat
			if style_box == null:
				style_box = StyleBoxFlat.new()
			style_box.bg_color = Color(0.2, 0.2, 0.2, 0.5)
			panel.add_theme_stylebox_override("panel", style_box)
			panel.modulate = Color(1, 1, 1, 1)
			if label:
				label.text = ""
				label.add_theme_color_override("font_color", Color.WHITE)


func _update_inventory_slots() -> void:
	for i in range(inventory_slots.size()):
		var panel: Panel = inventory_slots[i]
		var label: Label = _get_or_create_label(panel)
		if i < inventory_items.size():
			var item: Dictionary = _dict_from_stack(inventory_items[i] if i < inventory_items.size() else null)
			if not item.is_empty():
				item = _order_item(item)
				var item_name: String = item.get("name", item.get("id", "Item"))
				var rarity: String = String(item.get("rarity", "normal"))
				var rarity_color: Color = _get_color_for_rarity(rarity)

				# Hintergrund in Rarity-Farbe, aber dunkler und leicht transparent
				var bg_color := Color(rarity_color.r * 0.2, rarity_color.g * 0.2, rarity_color.b * 0.2, 0.4)
				var style_box: StyleBoxFlat = null
				if panel.has_theme_stylebox_override("panel"):
					style_box = panel.get_theme_stylebox("panel") as StyleBoxFlat
				if style_box == null:
					style_box = StyleBoxFlat.new()
				style_box.bg_color = bg_color
				panel.add_theme_stylebox_override("panel", style_box)

				# Keine Ausgrauung mehr – immer volle Farbe
				panel.modulate = Color(1, 1, 1, 1)

				if label:
					var amount: int = int(item.get("amount", 1))
					var stackable: bool = bool(item.get("stackable", false))
					# Prüfe auch, ob es ein Consumable ist (falls stackable nicht gesetzt ist)
					var item_type_name: String = String(item.get("item_type", "")).to_lower()
					var is_consumable: bool = _is_consumable_type(item_type_name)
					if not stackable and is_consumable:
						stackable = true  # Consumables sind immer stackable
					
					if stackable and amount > 1:
						label.text = str(amount)
						label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
						label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
						label.add_theme_color_override("font_color", Color.WHITE)
						label.add_theme_font_size_override("font_size", 18)
					else:
						label.text = item_name.substr(0, 1).to_upper()
						label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
						label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
						label.add_theme_color_override("font_color", rarity_color)
						label.add_theme_font_size_override("font_size", 22)
			else:
				# Пустой, но "активный" слот
				var style_box: StyleBoxFlat = null
				if panel.has_theme_stylebox_override("panel"):
					style_box = panel.get_theme_stylebox("panel") as StyleBoxFlat
				if style_box == null:
					style_box = StyleBoxFlat.new()
				style_box.bg_color = Color(0.2, 0.2, 0.2, 0.5)
				panel.add_theme_stylebox_override("panel", style_box)
				panel.modulate = Color(1, 1, 1, 1)
				if label:
					label.text = ""
					label.add_theme_color_override("font_color", Color.WHITE)
		else:
			# Слот вне диапазона инвентаря — самый тёмный
			panel.modulate = Color(0.3, 0.3, 0.3, 1)
			if label:
				label.text = ""


func _process(delta: float) -> void:
	# Cooldown-Timer aktualisieren
	if _sort_cooldown_timer > 0.0:
		_sort_cooldown_timer -= delta
		if _sort_cooldown_timer <= 0.0:
			_sort_cooldown_timer = 0.0
	
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

	# Wenn kein aktiver Drag mehr vorhanden ist, Highlights zurücksetzen
	if _highlight_slot_name != "" and (not DragState.active or DragState.get_item().is_empty()):
		_clear_highlight()


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

	var item_name: String = item.get("name", item.get("id", "Unknown"))
	var item_level: int = int(item.get("item_level", 0))
	var min_level: int = int(item.get("min_player_level", 0))

	var enchantments: Array = item.get("enchantments", [])

	# Цвет редкости на основе rarity-строки
	var rarity: String = String(item.get("rarity", "normal"))
	var rarity_color: Color = _get_color_for_rarity(rarity)

	var sb := "[b][color=%s]%s[/color][/b]\n" % [rarity_color.to_html(false), item_name]
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

	var _name_new: String = new_item.get("name", new_item.get("id", "New"))
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
	if INVENTORY_DISABLED:
		return null
	if not (slot_node is Panel):
		return null

	var kind: String = slot_node.slot_kind
	var id: String = slot_node.slot_id

	var stack := _get_stack_from_slot(kind, id)
	if stack == null or stack.item == null or stack.amount <= 0:
		return null
	var item := _dict_from_stack(stack)

	# Подсвечиваем подходящий слот экипировки (если есть)
	_highlight_for_item(item)

	var drag_data := {
		"item": item,
		"source_kind": kind,
		"source_id": id,
	}

	# If dragging from inventory, mark origin and set position to {"drag":1}, clear slot visually/persist
	if kind == "inventory":
		# Inventar-Slot leeren
		var idx: int = int(id)
		if idx >= 0 and idx < inventory_items.size():
			inventory_items[idx] = null
			_save_data()
			_update_inventory_slots()

	# Persistiere Drag als Stack
	var temp_store := preload("res://core/temp_loot_store.gd")
	temp_store.save_drag_stack(stack)

	# Zentraler DragState
	DragState.start(kind, id, stack, slot_node)

	# Простой превью (полупрозрачный прямоугольник)
	var preview := ColorRect.new()
	preview.color = Color(1, 1, 1, 0.4)
	preview.custom_minimum_size = Vector2(48, 48)
	slot_node.set_drag_preview(preview)

	return drag_data


func slot_can_drop_data(slot_node: Node, data: Variant) -> bool:
	if INVENTORY_DISABLED:
		return false
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
		var source_kind: String = data.get("source_kind", "")
		var source_id: String = data.get("source_id", "")
		
		# Source-Item muss in Ziel-Slot passen
		if not _item_fits_slot(item, slot_name):
			return false
		
		# 7b: Wenn Equipment-zu-Equipment Swap: auch bidirektional prüfen
		if source_kind == "equipment" and source_id != slot_name:
			var existing_item: Dictionary = _get_item_from_slot("equipment", slot_name)
			if not existing_item.is_empty():
				# Vorhandenes Item muss auch in Source-Slot passen
				if not _item_fits_slot(existing_item, source_id):
					return false
		
		return true
	elif kind == "inventory":
		# Любой предмет может лежать в инвентаре
		return true

	return false


func slot_drop_data(slot_node: Node, data: Variant) -> void:
	if INVENTORY_DISABLED:
		return
	var source_kind: String = ""
	var source_id: String = ""
	var item: Dictionary = {}
	
	# Prüfen ob Drag von Welt-Loot kommt (über DragState)
	if DragState.active and DragState.source_kind == "world" and not DragState.get_item().is_empty():
		# Welt-Loot Drag: Daten aus DragState nehmen
		source_kind = DragState.source_kind
		source_id = DragState.source_id
		item = DragState.get_item()
		print("📦 slot_drop_data: Welt-Loot Drag erkannt")
	elif typeof(data) == TYPE_DICTIONARY and data.has("item"):
		# Normaler Drag von Inventar/Equipment
		source_kind = data.get("source_kind", "")
		source_id = data.get("source_id", "")
		item = data["item"]
	else:
		print("📦 slot_drop_data: Ungültige Daten")
		return

	var target_kind: String = slot_node.slot_kind
	var target_id: String = slot_node.slot_id

	if target_kind == "equipment":
		_drop_to_equipment(target_id, source_kind, source_id, item)
	elif target_kind == "inventory":
		_drop_to_inventory(int(target_id), source_kind, source_id, item)

	# Drop wurde erfolgreich auf einen Slot durchgeführt
	_drag_from_inventory = {}
	
	# Welt-Loot-Node löschen (muss immer gelöscht werden, auch bei Swap)
	var world_loot_node: DroppedLoot = null
	if source_kind == "world" and DragState.source_node:
		world_loot_node = DragState.source_node
	
	# Prüfen ob ein Swap stattfand (altes Item ist jetzt im DragState)
	var swap_occurred: bool = false
	if DragState.active and DragState.source_kind != "world":
		swap_occurred = true
	
	# Welt-Loot-Node löschen
	if world_loot_node:
		world_loot_node.queue_free()
	
	# DragState nur zurücksetzen, wenn kein Swap stattfand
	# Bei Swap ist das alte Item jetzt im DragState und soll "an der Maus" bleiben
	if not swap_occurred and source_kind == "world":
		DragState.clear()

	_clear_highlight()
	_save_data()
	_update_all_slots()


func slot_click_from_world(slot_node: Node) -> void:
	if INVENTORY_DISABLED:
		return
	# Wird von slot_panel.gd bei Mausklick auf Inventar-/Equipment-Slot aufgerufen.
	# Hier behandeln wir jeden aktiven Drag (Welt/Inventar/Equipment) per Klick.
	if not DragState.active or DragState.get_item().is_empty():
		return

	if not (slot_node is Panel):
		print("📦 slot_click_from_world: slot_node ist kein Panel")
		return

	var kind: String = slot_node.slot_kind
	var id: String = slot_node.slot_id
	var source_kind := DragState.source_kind
	var source_id := DragState.source_id
	var item := DragState.get_item()

	if kind == "inventory":
		var index := int(id)
		_drop_to_inventory(index, source_kind, source_id, item)

	elif kind == "equipment":
		_drop_to_equipment(id, source_kind, source_id, item)

	else:
		print("📦 slot_click_from_world: Unbekannter Slot-Typ: ", kind)

	# Welt-Loot-Node löschen (immer entfernen, wenn aus Welt stammt)
	if source_kind == "world" and DragState.source_node and DragState.source_node is DroppedLoot:
		var dl: DroppedLoot = DragState.source_node
		dl.queue_free()

	# Drag nur dann leeren, wenn kein Swap stattfand oder Quelle Welt war.
	if not DragState.active or source_kind == "world":
		DragState.clear()

	_save_data()
	_update_all_slots()
	_clear_highlight()


## Wird vom slot_panel.gd bei NOTIFICATION_DRAG_END aufgerufen,
## wenn ein Drag von einem Inventar-Slot nirgends gültig abgelegt wurde.
## In diesem Fall droppen wir das Item als Welt-Loot in der Nähe des Spielers.
func world_drop_from_inventory() -> void:
	if INVENTORY_DISABLED:
		_drag_from_inventory = {}
		if DragState.active:
			DragState.clear()
		return
	var source_kind: String
	var source_id: String
	var item: Dictionary

	# Bevorzugt den zentralen DragState verwenden
	if DragState.active and DragState.source_kind == "inventory" and not DragState.get_item().is_empty():
		source_kind = DragState.source_kind
		source_id = DragState.source_id
		item = DragState.get_item()
	elif DragState.active and DragState.source_kind == "equipment" and not DragState.get_item().is_empty():
		source_kind = DragState.source_kind
		source_id = DragState.source_id
		item = DragState.get_item()
	else:
		if _drag_from_inventory.is_empty():
			return

		source_kind = String(_drag_from_inventory.get("source_kind", ""))
		source_id = String(_drag_from_inventory.get("source_id", ""))
		item = _drag_from_inventory.get("item", {})

	# Inventar-Drags: auf den Boden droppen (5a)
	if source_kind == "inventory":
		if item.is_empty():
			_drag_from_inventory = {}
			if DragState.active:
				DragState.clear()
			return

		print("📦 world_drop_from_inventory: drop item aus Inventar-Slot ", source_id, " auf den Boden")

		# Slot im Inventar leeren
		_clear_slot(source_kind, source_id)
		_save_data()
		_update_all_slots()

		# Spieler in der aktuellen Szene suchen (9a: immer aktuelle Position)
		var scene := get_tree().current_scene
		if scene == null:
			_drag_from_inventory = {}
			if DragState.active:
				DragState.clear()
			return

		var player: Node2D = scene.get_node_or_null("Player")
		if player == null:
			player = scene.find_child("Player", true, false)
		if player == null:
			print("📦 world_drop_from_inventory: kein Player gefunden, Item nicht gedroppt")
			_drag_from_inventory = {}
			if DragState.active:
				DragState.clear()
			return

		# DroppedLoot in der Welt erzeugen – immer bei aktueller Player-Position
		var drop := DroppedLoot.new()
		var drop_pos := player.global_position + Vector2(0, 24)
		drop.setup_drop(drop_pos, 0, item)
		scene.add_child(drop)

		_drag_from_inventory = {}
		if DragState.active:
			DragState.clear()
		return

	# Nur Items aus der Ausrüstung dürfen auf den Boden fallen gelassen werden
	if source_kind != "equipment" or item.is_empty():
		_drag_from_inventory = {}
		if DragState.active:
			DragState.clear()
		return

	print("📦 world_drop_from_inventory: drop item aus Equipment-Slot ", source_id, " auf den Boden")

	# Slot in der Ausrüstung leeren
	_clear_slot(source_kind, source_id)
	_save_data()
	_update_all_slots()

	# Spieler in der aktuellen Szene suchen
	var scene2 := get_tree().current_scene
	if scene2 == null:
		_drag_from_inventory = {}
		if DragState.active:
			DragState.clear()
		return

	var player2: Node2D = scene2.get_node_or_null("Player")
	if player2 == null:
		player2 = scene2.find_child("Player", true, false)
	if player2 == null:
		print("📦 world_drop_from_inventory: kein Player gefunden, Item nicht gedroppt")
		_drag_from_inventory = {}
		if DragState.active:
			DragState.clear()
		return

	# DroppedLoot in der Welt erzeugen (gelber Punkt) – etwas weiter unterhalb der Spielerposition,
	# damit es optisch auf "Fußhöhe" liegt.
	var drop2 := DroppedLoot.new()
	var drop_pos2 := player2.global_position + Vector2(0, 24)
	drop2.setup_drop(drop_pos2, 0, item)
	scene2.add_child(drop2)

	# Drag-Status bereinigen
	_drag_from_inventory = {}
	if DragState.active:
		DragState.clear()


## Ermittelt die maximale Inventar-Slot-Anzahl (backpack_slots) aus dem PlayerResource.
## Die Kapazität wird direkt im PlayerResource gespeichert und kann durch Quests etc. aktualisiert werden.
## Basiswert ist 12.
func _get_backpack_slots_from_equipped(equipped: Dictionary) -> int:
	var default_capacity := 12
	
	# Versuche backpack_slots aus player_data zu lesen (wird beim Laden gesetzt)
	if player_data.has("backpack_slots"):
		var slots: int = int(player_data.get("backpack_slots", default_capacity))
		if slots > 0:
			return slots
	
	# Fallback: Standard-Kapazität
	return default_capacity

## === Вспомогательные методы ===

## Findet ein Item über seine Position (vereinfacht durch Positions-System)
func _get_item_by_position(pos_param: String) -> Dictionary:
	if pos_param == "" or pos_param == "drag":
		return {}
	
	# Inventar-Items: Position ist Slot-Index als String (z.B. "0", "1", "2")
	if pos_param.is_valid_int():
		var index := int(pos_param)
		if index >= 0 and index < inventory_items.size():
			var st = inventory_items[index]
			return _dict_from_stack(st)
		return {}
	
	# Equipment-Items: Position ist Slotname (z.B. "boots", "helmet")
	if equipped_items.has(pos_param):
		var raw = equipped_items.get(pos_param, null)
		if raw is ItemStack:
			return _dict_from_stack(raw)
		return {}
	
	return {}


## Setzt ein Item an eine bestimmte Position (vereinfacht durch Positions-System)
func _set_item_by_position(pos_param: String, item: Dictionary) -> void:
	if pos_param == "" or pos_param == "drag":
		return
	
	# Inventar-Items: Position ist Slot-Index als String
	if pos_param.is_valid_int():
		var index := int(pos_param)
		if index >= 0:
			while index >= inventory_items.size():
				inventory_items.append(null)
			inventory_items[index] = _stack_from_dict(item)
		return
	
	# Equipment-Items: Position ist Slotname
	if equipped_items.has(pos_param) or _is_valid_equipment_slot(pos_param):
		equipped_items[pos_param] = _stack_from_dict(item)
		return


## Leert einen Slot über Position
func _clear_slot_by_position(pos_param: String) -> void:
	if pos_param == "" or pos_param == "drag":
		return
	
	# Inventar-Items
	if pos_param.is_valid_int():
		var index := int(pos_param)
		if index >= 0 and index < inventory_items.size():
			inventory_items[index] = null
		return
	
	# Equipment-Items
	if equipped_items.has(pos_param):
		equipped_items[pos_param] = null
		return


## Prüft ob ein Slotname gültig ist
func _is_valid_equipment_slot(slot_name: String) -> bool:
	return equipment_slots.has(slot_name)


## Slot Accessors (Stacks first, Dictionary views for UI)
func _get_stack_from_slot(kind: String, id: String) -> ItemStack:
	if kind == "equipment":
		if equipped_items.has(id):
			var it = equipped_items[id]
			if it is ItemStack:
				return it
		return null
	elif kind == "inventory":
		var idx := int(id)
		if idx >= 0 and idx < inventory_items.size():
			var it = inventory_items[idx]
			if it is ItemStack:
				return it
		return null
	return null

func _set_stack_to_slot(kind: String, id: String, stack: ItemStack) -> void:
	if kind == "equipment":
		equipped_items[id] = stack
	elif kind == "inventory":
		var idx := int(id)
		if idx >= 0:
			while idx >= inventory_items.size():
				inventory_items.append(null)
			inventory_items[idx] = stack

func _clear_slot(kind: String, id: String) -> void:
	_set_stack_to_slot(kind, id, null)

func _get_item_from_slot(kind: String, id: String) -> Dictionary:
	return _dict_from_stack(_get_stack_from_slot(kind, id))

func _set_item_to_slot(kind: String, id: String, item: Dictionary) -> void:
	_set_stack_to_slot(kind, id, _stack_from_dict(item))


# Restore a dragged item back to its origin (inventory/equipment/world) – used on ESC
func restore_drag_to_origin() -> void:
	if not DragState.active or DragState.get_item().is_empty():
		return

	var source_kind := DragState.source_kind
	var source_id := DragState.source_id
	var item_dict: Dictionary = DragState.get_item().duplicate(true)
	var stack := _stack_from_dict(item_dict)
	var origin_pos: Dictionary = {}
	var pos_any: Variant = item_dict.get("origin_position", {})
	if pos_any is Dictionary:
		origin_pos = pos_any

	var temp_store := preload("res://core/temp_loot_store.gd")

	if source_kind == "inventory":
		var slot_idx := -1
		if origin_pos.has("inventar_slot"):
			slot_idx = int(origin_pos.get("inventar_slot", -1)) - 1
		elif source_id != "":
			slot_idx = int(source_id)

		if slot_idx >= 0:
			if slot_idx >= inventory_items.size():
				inventory_items.resize(slot_idx + 1)
				for i in range(inventory_items.size()):
					if inventory_items[i] == null:
						inventory_items[i] = null
			inventory_items[slot_idx] = stack
			_save_data()
			_update_inventory_slots()
			temp_store.clear_drag()
			DragState.clear()
			return

	if source_kind == "equipment":
		var slot_name := source_id
		if slot_name != "":
			equipped_items[slot_name] = stack
			_save_data()
			_update_equipment_slots()
			_update_inventory_slots()
			temp_store.clear_drag()
			DragState.clear()
			return

	# Default/fallback: treat as world item and drop back to world
	var scene := get_tree().current_scene
	var player: Node2D = null
	if scene:
		player = scene.get_node_or_null("Player")
		if player == null:
			player = scene.find_child("Player", true, false)

	var drop_pos := Vector2.ZERO
	if player:
		drop_pos = player.global_position + Vector2(0, 24)

	var item_copy := item_dict.duplicate(true)
	var loot_id := temp_store.add_item(item_copy)
	if loot_id > 0:
		item_copy["position"] = {"loot": loot_id}
	else:
		item_copy["position"] = {"loot": 1}
	item_copy = _order_item(item_copy)

	if DragState.source_node and DragState.source_node is DroppedLoot:
		var dl: DroppedLoot = DragState.source_node
		dl.global_position = drop_pos
		dl.item = item_copy
		dl.gold = 0
		dl._update_label()
		dl.visible = true
	else:
		var scene2 := get_tree().current_scene
		if scene2:
			var drop := DroppedLoot.new()
			if drop_pos == Vector2.ZERO and player:
				drop_pos = player.global_position + Vector2(0, 24)
			drop.setup_drop(drop_pos, 0, item_copy)
			scene2.add_child(drop)

	temp_store.clear_drag()
	DragState.clear()


func _drop_to_equipment(target_slot: String, source_kind: String, source_id: String, item: Dictionary) -> void:
	# Prüfen ob Item in Slot passt
	if not _item_fits_slot(item, target_slot):
		print("📦 _drop_to_equipment: Item passt nicht in Slot ", target_slot)
		return

	var incoming_stack := _stack_from_dict(item)
	if incoming_stack == null:
		return

	var temp_store := preload("res://core/temp_loot_store.gd")

	# Welt -> Equipment
	if source_kind == "world":
		var prev_stack: ItemStack = null
		if equipped_items.has(target_slot) and equipped_items[target_slot] is ItemStack:
			prev_stack = equipped_items[target_slot]
		equipped_items[target_slot] = incoming_stack
		if prev_stack != null:
			var slot_node: Node = null
			if equipment_slots.has(target_slot):
				slot_node = equipment_slots[target_slot]
			temp_store.save_drag_stack(prev_stack)
			DragState.start("equipment", target_slot, prev_stack, slot_node)
		else:
			temp_store.clear_drag()
			DragState.clear()
		_update_equipment_slots()
		return

	# Inventory -> Equipment
	if source_kind == "inventory":
		var source_index := int(source_id)
		if source_index < 0 or source_index >= inventory_items.size():
			return
		var prev_stack2: ItemStack = null
		if equipped_items.has(target_slot) and equipped_items[target_slot] is ItemStack:
			prev_stack2 = equipped_items[target_slot]
		equipped_items[target_slot] = incoming_stack
		inventory_items[source_index] = prev_stack2
		temp_store.clear_drag()
		DragState.clear()
		_update_equipment_slots()
		_update_inventory_slots()
		return

	# Equipment -> Equipment
	if source_kind == "equipment":
		if source_id == target_slot:
			return
		var source_stack: ItemStack = null
		var target_stack: ItemStack = null
		if equipped_items.has(source_id) and equipped_items[source_id] is ItemStack:
			source_stack = equipped_items[source_id]
		if equipped_items.has(target_slot) and equipped_items[target_slot] is ItemStack:
			target_stack = equipped_items[target_slot]
		if source_stack == null:
			return
		if not _item_fits_slot_stack(source_stack, target_slot):
			return
		if target_stack != null and not _item_fits_slot_stack(target_stack, source_id):
			return
		equipped_items[target_slot] = source_stack
		equipped_items[source_id] = target_stack
		temp_store.clear_drag()
		DragState.clear()
		_update_equipment_slots()
		return


func _drop_to_inventory(target_index: int, source_kind: String, source_id: String, item: Dictionary) -> void:
	if target_index < 0:
		return

	# Убедимся, что массив достаточно длинный
	while target_index >= inventory_items.size():
		inventory_items.append(null)

	# Eingehenden Stack bauen
	var incoming_stack := _stack_from_dict(item)
	if incoming_stack == null:
		return

	var temp_store := preload("res://core/temp_loot_store.gd")

	if source_kind == "inventory":
		var source_index := int(source_id)
		if source_index < 0 or source_index >= inventory_items.size():
			return
		# Drop auf denselben Slot: Stack zurücklegen
		if source_index == target_index:
			inventory_items[target_index] = incoming_stack
			temp_store.clear_drag()
			DragState.clear()
			_update_inventory_slots()
			return

		# Merge-Versuch
		var leftover := _merge_stack_into_slot_stack(target_index, incoming_stack)
		inventory_items[source_index] = null
		if leftover == null:
			temp_store.clear_drag()
			DragState.clear()
			_update_inventory_slots()
			return
		# Sonst Swap
		var prev_stack: ItemStack = inventory_items[target_index] as ItemStack
		inventory_items[target_index] = leftover
		inventory_items[source_index] = null
		if prev_stack != null:
			temp_store.save_drag_stack(prev_stack)
			var slot_node: Node = null
			if target_index < inventory_slots.size():
				slot_node = inventory_slots[target_index]
			DragState.start("inventory", str(source_index), prev_stack, slot_node)
		else:
			temp_store.clear_drag()
			DragState.clear()
		_update_inventory_slots()
		return

	if source_kind == "equipment":
		var prev_stack: ItemStack = inventory_items[target_index] as ItemStack
		# Merge wenn gleicher Stack möglich
		var leftover2 := _merge_stack_into_slot_stack(target_index, incoming_stack)
		if leftover2 == null:
			equipped_items[source_id] = null
			temp_store.clear_drag()
			DragState.clear()
			_update_inventory_slots()
			_update_equipment_slots()
			return
		# Platzieren
		inventory_items[target_index] = leftover2
		# Zurücktauschen nur wenn passt
		if _item_fits_slot_stack(prev_stack, source_id):
			equipped_items[source_id] = prev_stack
		else:
			equipped_items[source_id] = null
		temp_store.clear_drag()
		DragState.clear()
		_update_inventory_slots()
		_update_equipment_slots()
		return

	if source_kind == "world":
		var prev_stack_world: ItemStack = inventory_items[target_index]
		var leftover_w := _merge_stack_into_slot_stack(target_index, incoming_stack)
		if leftover_w == null:
			temp_store.clear_drag()
			DragState.clear()
			_update_inventory_slots()
			return
		inventory_items[target_index] = leftover_w
		if prev_stack_world != null:
			temp_store.save_drag_stack(prev_stack_world)
			var slot_node2: Node = null
			if target_index < inventory_slots.size():
				slot_node2 = inventory_slots[target_index]
			DragState.start("inventory", str(target_index), prev_stack_world, slot_node2)
		else:
			temp_store.clear_drag()
			DragState.clear()
		_update_inventory_slots()
		return


## Публичный метод для HUD, чтобы открыть/закрыть окно
func toggle_visible() -> void:
	if INVENTORY_DISABLED:
		visible = not visible
		if dim_background:
			dim_background.visible = visible
		return
	visible = not visible
	if dim_background:
		dim_background.visible = visible
	if visible:
		# При каждом открытии перечитываем данные и перерисовываем слоты,
		# чтобы лут из сейва всегда был актуален.
		_load_data()
		_update_all_slots()


## === Inventar-Sortierung ===

## Wird von slot_panel.gd bei mittlerer Maustaste aufgerufen
func _handle_inventory_sort() -> void:
	_merge_all_stacks()
	# Prüfen ob Cooldown noch aktiv ist (mit kleiner Toleranz für Fließkomma-Fehler)
	var cooldown_active: bool = _sort_cooldown_timer > 0.01
	
	print("📦 Sortierung angefordert - Cooldown: ", _sort_cooldown_timer, "s, Aktueller Modus: ", _current_sort_mode)
	
	if cooldown_active:
		# Innerhalb des Cooldowns: zur nächsten Sortierfunktion wechseln
		_current_sort_mode = (_current_sort_mode + 1) % 3
		print("  → Cooldown aktiv - wechsle zu Modus ", _current_sort_mode + 1)
	else:
		# Cooldown abgelaufen: zurück zu Modus 0
		_current_sort_mode = 0
		print("  → Cooldown abgelaufen - starte bei Modus 1")
	
	# Cooldown zurücksetzen/starten (immer auf 3 Sekunden)
	_sort_cooldown_timer = SORT_COOLDOWN_TIME
	
	# Sortierung durchführen
	match _current_sort_mode:
		0:
			_sort_inventory_by_level()
		1:
			_sort_inventory_by_rarity_and_level()
		2:
			_sort_inventory_by_type_rarity_level()
	
	# Positionen aktualisieren und speichern
	_update_item_positions_after_sort()
	_save_data()
	_update_all_slots()
	
	print("  ✓ Inventar sortiert (Modus ", _current_sort_mode + 1, "/3, neuer Cooldown: ", _sort_cooldown_timer, "s)")

# Führt alle stackbaren Items zusammen und aktualisiert die Slots
func _merge_all_stacks() -> void:
	var merged: Array = []
	var key_map := {}
	for entry in inventory_items:
		var stack: ItemStack = null
		if entry is ItemStack and entry.item != null:
			stack = entry
		elif entry is Dictionary and not (entry as Dictionary).is_empty():
			stack = _stack_from_dict(entry)
		if stack != null and stack.item != null:
			if stack.item.item_type and stack.item.item_type.stackable:
				var key = _stack_key_from_stack(stack)
				if key == "":
					merged.append(stack)
					continue
				if not key_map.has(key):
					key_map[key] = []
				key_map[key].append(stack)
			else:
				merged.append(stack)
	# Combine stacks per key respecting max_stack
	for key in key_map.keys():
		var list: Array = key_map[key]
		var total_amt: int = 0
		var max_stack_val: int = 1
		var template: ItemStack = null
		for st in list:
			if template == null:
				template = st
			total_amt += st.amount
			max_stack_val = _max_stack_stack(st)
		while total_amt > 0 and template != null:
			var chunk_amt = min(max_stack_val, total_amt)
			var chunk: ItemStack = ItemStackRes.new()
			var type_name: String = template.item.item_type.tab_name.to_lower() if template.item and template.item.item_type else ""
			chunk.amount = chunk_amt
			if _is_consumable_type(type_name):
				# Für Verbrauchsgüter keine Enchants/Material-Meta übernehmen
				var clean_item: Item = template.item.duplicate(true)
				clean_item.enchantments = []
				chunk.item = clean_item
				# Basis-Metadaten kopieren (ohne Enchants/Material)
				if template.has_meta("item_level"):
					chunk.set_meta("item_level", template.get_meta("item_level"))
				if template.has_meta("min_player_level"):
					chunk.set_meta("min_player_level", template.get_meta("min_player_level"))
				# Alle anderen Metadaten kopieren (außer Enchants/Material/Position)
				var all_meta_keys: Array = template.get_meta_list()
				for meta_key in all_meta_keys:
					if meta_key in ["enchantments", "material", "position"]:
						continue  # Für Consumables nicht kopieren
					if not chunk.has_meta(meta_key):
						chunk.set_meta(meta_key, template.get_meta(meta_key))
			else:
				chunk.item = template.item
				_copy_instance_meta(template, chunk)
			total_amt -= chunk_amt
			merged.append(chunk)
	# Refill inventory with merged stacks first, then empties up to capacity
	var capacity = max(_get_backpack_slots_from_equipped(equipped_items), inventory_items.size(), MAX_BASE_SLOTS)
	var new_inv: Array = []
	for st in merged:
		if new_inv.size() >= capacity:
			break
		new_inv.append(st)
	while new_inv.size() < capacity:
		new_inv.append(null)
	inventory_items = new_inv
	_update_item_positions_after_sort()

func _stack_key(item: Dictionary) -> String:
	if item == null or not (item is Dictionary) or item.is_empty():
		return ""
	var base := String(item.get("id", item.get("name", ""))).strip_edges()
	var type_name: String = String(item.get("item_type", "")).to_lower()
	# Für stackbare Verbrauchsitems (Potions etc.) Enchants/Stats ignorieren, damit sie mergen
	if _is_consumable_type(type_name):
		return "%s_%s" % [base, type_name]
	var ench_hash = item.get("enchantments", []).hash()
	var stats_hash = item.get("stats", {}).hash()
	return "%s_%s_%s" % [base, str(ench_hash), str(stats_hash)]

func _stack_key_from_stack(st: ItemStack) -> String:
	if st == null or st.item == null:
		return ""
	var base: String = st.item.id if st.item.id != "" else st.item.name
	var type_name: String = st.item.item_type.tab_name.to_lower() if st.item.item_type else ""
	# Für stackbare Verbrauchsitems (Potions etc.) Enchants/Material ignorieren, damit sie mergen
	if _is_consumable_type(type_name):
		return "%s_%s" % [base, type_name]

	var ench: Array = st.get_meta("enchantments") if st.has_meta("enchantments") else st.item.enchantments
	var mat_dict: Dictionary = st.get_meta("material") if st.has_meta("material") else st.item.material
	var reqs: Dictionary = st.item.requirements
	var lvl: int = st.get_meta("item_level") if st.has_meta("item_level") else st.item.item_level
	var min_lvl: int = st.get_meta("min_player_level") if st.has_meta("min_player_level") else 1
	var stats_hash: int = st.item.stats.hash()
	var ench_hash: int = ench.hash()
	var mat_hash: int = mat_dict.hash()
	var req_hash: int = reqs.hash()
	return "%s_%s_%s_%s_%s_%s" % [String(base), str(ench_hash), str(stats_hash), str(mat_hash), str(req_hash), str(lvl) + "_" + str(min_lvl)]

# Meta copier to keep instance-specific fields when splitting/merging
# Kopiert ALLE Metadaten von src nach dst (außer position, die separat gesetzt wird)
func _copy_instance_meta(src: ItemStack, dst: ItemStack) -> void:
	if src == null or dst == null:
		return
	
	# Basis-Metadaten immer kopieren
	if src.has_meta("item_level"):
		dst.set_meta("item_level", src.get_meta("item_level"))
	if src.has_meta("min_player_level"):
		dst.set_meta("min_player_level", src.get_meta("min_player_level"))
	
	# Für nicht-Verbrauchsgüter Enchants/Material übernehmen
	var type_name := src.item.item_type.tab_name.to_lower() if src.item and src.item.item_type else ""
	if not _is_consumable_type(type_name):
		if src.has_meta("enchantments"):
			dst.set_meta("enchantments", src.get_meta("enchantments"))
		if src.has_meta("material"):
			dst.set_meta("material", src.get_meta("material"))
	
	# Alle anderen Metadaten kopieren (außer position, die separat gesetzt wird)
	var all_meta_keys: Array = src.get_meta_list()
	for key in all_meta_keys:
		if key == "position":
			continue  # position wird separat gesetzt
		if not dst.has_meta(key):
			dst.set_meta(key, src.get_meta(key))

func _is_consumable_type(type_name: String) -> bool:
	return type_name in ["potion", "consumable", "quest", "quest_item", "flask"]


## Sortierung 1: Nach item_level absteigend, bei gleichem Level alphabetisch nach item_type
func _sort_inventory_by_level() -> void:
	var items_with_index: Array = []
	
	# Alle Items mit ihrem Index sammeln
	for i in range(inventory_items.size()):
		var entry = inventory_items[i]
		var st: ItemStack = null
		if entry is ItemStack and entry.item != null:
			st = entry
		elif entry is Dictionary and not (entry as Dictionary).is_empty():
			st = _stack_from_dict(entry)
		if st != null and st.item != null:
			var dict_view = _dict_from_stack(st)
			dict_view["__stack"] = st
			items_with_index.append(dict_view)
	
	# Sortieren: item_level absteigend, dann item_type alphabetisch aufsteigend
	items_with_index.sort_custom(func(a, b):
		var item_a = a
		var item_b = b
		var level_a = int(item_a.get("item_level", 0))
		var level_b = int(item_b.get("item_level", 0))
		
		# Zuerst nach Level (absteigend)
		if level_a != level_b:
			return level_a > level_b
		
		# Bei gleichem Level: alphabetisch nach item_type (aufsteigend)
		var type_a = String(item_a.get("item_type", "")).to_lower()
		var type_b = String(item_b.get("item_type", "")).to_lower()
		return type_a < type_b
	)
	
	# Inventar neu aufbauen: sortierte Items zuerst, dann leere Slots
	var sorted_items: Array = []
	for entry in items_with_index:
		var stack: ItemStack = entry.get("__stack")
		if stack != null and stack.item != null:
			# Sicherstellen, dass Amount korrekt übertragen wird
			var amount: int = int(entry.get("amount", stack.amount))
			if amount != stack.amount:
				stack.amount = amount
			sorted_items.append(stack)
	
	# Leere Slots am Ende hinzufügen
	var capacity = _get_backpack_slots_from_equipped(equipped_items)
	if capacity <= 0:
		capacity = inventory_items.size()
	
	while sorted_items.size() < capacity:
		sorted_items.append(null)
	
	# Inventar ersetzen
	inventory_items = sorted_items


## Sortierung 2: Nach Rarity gruppiert (absteigend), dann nach item_level absteigend
func _sort_inventory_by_rarity_and_level() -> void:
	var items_with_index: Array = []
	
	# Alle Items mit ihrem Index sammeln
	for i in range(inventory_items.size()):
		var entry = inventory_items[i]
		var st: ItemStack = null
		if entry is ItemStack and entry.item != null:
			st = entry
		elif entry is Dictionary and not (entry as Dictionary).is_empty():
			st = _stack_from_dict(entry)
		if st != null and st.item != null:
			var dict_view = _dict_from_stack(st)
			dict_view["__stack"] = st
			items_with_index.append(dict_view)
	
	# Rarity-Werte für Sortierung (höher = besser)
	var rarity_values = {
		"unique": 5,
		"legendary": 4,
		"epic": 3,
		"magic": 2,
		"normal": 1
	}
	
	# Sortieren: Rarity absteigend, dann item_level absteigend
	items_with_index.sort_custom(func(a, b):
		var item_a = a
		var item_b = b
		var rarity_a = String(item_a.get("rarity", "normal")).to_lower()
		var rarity_b = String(item_b.get("rarity", "normal")).to_lower()
		var rarity_val_a = rarity_values.get(rarity_a, 0)
		var rarity_val_b = rarity_values.get(rarity_b, 0)
		
		# Zuerst nach Rarity (absteigend)
		if rarity_val_a != rarity_val_b:
			return rarity_val_a > rarity_val_b
		
		# Bei gleicher Rarity: nach item_level (absteigend)
		var level_a = int(item_a.get("item_level", 0))
		var level_b = int(item_b.get("item_level", 0))
		return level_a > level_b
	)
	
	# Inventar neu aufbauen
	var sorted_items: Array = []
	for entry in items_with_index:
		var stack: ItemStack = entry.get("__stack")
		if stack != null and stack.item != null:
			# Sicherstellen, dass Amount korrekt übertragen wird
			var amount: int = int(entry.get("amount", stack.amount))
			if amount != stack.amount:
				stack.amount = amount
			sorted_items.append(stack)
	
	# Leere Slots am Ende hinzufügen
	var capacity = _get_backpack_slots_from_equipped(equipped_items)
	if capacity <= 0:
		capacity = inventory_items.size()
	
	while sorted_items.size() < capacity:
		sorted_items.append(null)
	
	# Inventar ersetzen
	inventory_items = sorted_items


## Sortierung 3: Nach item_type alphabetisch gruppiert, dann Rarity und item_level
func _sort_inventory_by_type_rarity_level() -> void:
	var items_with_index: Array = []
	
	# Alle Items mit ihrem Index sammeln
	for i in range(inventory_items.size()):
		var entry = inventory_items[i]
		var st: ItemStack = null
		if entry is ItemStack and entry.item != null:
			st = entry
		elif entry is Dictionary and not (entry as Dictionary).is_empty():
			st = _stack_from_dict(entry)
		if st != null and st.item != null:
			var dict_view = _dict_from_stack(st)
			dict_view["__stack"] = st
			items_with_index.append(dict_view)
	
	# Rarity-Werte für Sortierung
	var rarity_values = {
		"unique": 5,
		"legendary": 4,
		"epic": 3,
		"magic": 2,
		"normal": 1
	}
	
	# Sortieren: item_type alphabetisch, dann Rarity absteigend, dann item_level absteigend
	items_with_index.sort_custom(func(a, b):
		var item_a = a
		var item_b = b
		var type_a = String(item_a.get("item_type", "")).to_lower()
		var type_b = String(item_b.get("item_type", "")).to_lower()
		
		# Zuerst nach item_type (alphabetisch aufsteigend)
		if type_a != type_b:
			return type_a < type_b
		
		# Bei gleichem Type: nach Rarity (absteigend)
		var rarity_a = String(item_a.get("rarity", "normal")).to_lower()
		var rarity_b = String(item_b.get("rarity", "normal")).to_lower()
		var rarity_val_a = rarity_values.get(rarity_a, 0)
		var rarity_val_b = rarity_values.get(rarity_b, 0)
		
		if rarity_val_a != rarity_val_b:
			return rarity_val_a > rarity_val_b
		
		# Bei gleicher Rarity: nach item_level (absteigend)
		var level_a = int(item_a.get("item_level", 0))
		var level_b = int(item_b.get("item_level", 0))
		return level_a > level_b
	)
	
	# Inventar neu aufbauen
	var sorted_items: Array = []
	for entry in items_with_index:
		var stack: ItemStack = entry.get("__stack")
		if stack != null and stack.item != null:
			# Sicherstellen, dass Amount korrekt übertragen wird
			var amount: int = int(entry.get("amount", stack.amount))
			if amount != stack.amount:
				stack.amount = amount
			sorted_items.append(stack)
	
	# Leere Slots am Ende hinzufügen
	var capacity = _get_backpack_slots_from_equipped(equipped_items)
	if capacity <= 0:
		capacity = inventory_items.size()
	
	while sorted_items.size() < capacity:
		sorted_items.append(null)
	
	# Inventar ersetzen
	inventory_items = sorted_items


## Aktualisiert die Positionen aller Items nach der Sortierung
func _update_item_positions_after_sort() -> void:
	for i in range(inventory_items.size()):
		var item = inventory_items[i]
		if item is ItemStack and item.item != null:
			item.set_meta("position", {"inventar_slot": i + 1})

func _order_item(item: Dictionary) -> Dictionary:
	var ordered: Dictionary = {}
	for k in _get_order_keys():
		if item.has(k):
			ordered[k] = item[k]
	for k in item.keys():
		if not ordered.has(k):
			ordered[k] = item[k]
	return ordered

func _get_order_keys() -> Array:
	return [
		"id",
		"item_level",
		"item_type",
		"material",
		"min_player_level",
		"name",
		"amount",
		"stackable",
		"max_stack",
		"position",
		"rarity",
		"requirements",
		"stats",
		"enchant_slots",
		"enchantments",
	]

# Ensure stack-related defaults are present and sane.
func _normalize_stack_fields(item: Dictionary) -> Dictionary:
	if item == null or not (item is Dictionary):
		return {}
	var copy = item.duplicate(true)
	var item_type := String(copy.get("item_type", "")).to_lower()

	var stackable: bool = bool(copy.get("stackable", false))
	var has_stackable := copy.has("stackable")
	if not has_stackable:
		if item_type in ["weapon", "helm", "helmet", "chest", "gloves", "pants", "boots", "shield", "armor", "offhand"]:
			stackable = false
		elif item_type in ["potion", "consumable", "quest", "quest_item"]:
			stackable = true
		else:
			stackable = false
	copy["stackable"] = stackable

	var max_stack_val: int = int(copy.get("max_stack", -1))
	if not stackable:
		max_stack_val = 1
	elif max_stack_val <= 0:
		# Default stack size for potions/quest items
		max_stack_val = 20
	copy["max_stack"] = max_stack_val

	var amount_val: int = int(copy.get("amount", 0))
	if amount_val <= 0:
		amount_val = 1
	if not stackable:
		amount_val = 1
	copy["amount"] = amount_val

	return _order_item(copy)

# Two items can stack if both are marked stackable and share the same id/name key.
func _items_can_stack(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return false
	var a_norm = _normalize_stack_fields(a)
	var b_norm = _normalize_stack_fields(b)
	if not a_norm.get("stackable", false):
		return false
	if not b_norm.get("stackable", false):
		return false
	var key_a: String = str(a_norm.get("id", a_norm.get("name", "")))
	var key_b: String = str(b_norm.get("id", b_norm.get("name", "")))
	if key_a == "" or key_b == "":
		return false
	return key_a == key_b

# Try to merge a stackable item into the target inventory slot.
# Returns the remaining item (empty dict if fully merged).
func _merge_stack_into_slot(target_index: int, item: Dictionary) -> Dictionary:
	if item == null or not (item is Dictionary) or item.is_empty():
		return {}
	if target_index < 0:
		return item
	if target_index >= inventory_items.size():
		return item
	var existing: Dictionary = {}
	if inventory_items[target_index] is Dictionary:
		existing = inventory_items[target_index]
	existing = _normalize_stack_fields(existing)
	var incoming = _normalize_stack_fields(item)

	if existing.is_empty():
		return incoming
	if not _items_can_stack(existing, incoming):
		return incoming

	var max_stack_val: int = int(existing.get("max_stack", 1))
	var current_amt: int = int(existing.get("amount", 1))
	var incoming_amt: int = int(incoming.get("amount", 1))
	var space: int = max_stack_val - current_amt
	if space <= 0:
		return incoming

	var to_move: int = min(space, incoming_amt)
	existing["amount"] = current_amt + to_move
	incoming["amount"] = incoming_amt - to_move

	inventory_items[target_index] = _order_item(existing)

	if int(incoming.get("amount", 0)) <= 0:
		return {}
	return incoming
