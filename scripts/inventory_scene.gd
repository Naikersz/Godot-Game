extends Control

## Inventory Scene - Neu aufgebaut mit Slots und Tooltips

const SLOT_MAP = {
	"weapon": "weapon",
	"helmet": "helmet",
	"chest": "chest",
	"pants": "pants",
	"boot": "boots",
	"boots": "boots",
	"glove": "gloves",
	"gloves": "gloves",
	"shield": "shield"
}

# Slot-Positionen im Grid (x, y)
const EQUIPMENT_SLOTS = {
	"helmet": Vector2(1, 0),      # Oben Mitte
	"chest": Vector2(1, 1),       # Mitte
	"pants": Vector2(1, 2),       # Unten Mitte
	"gloves": Vector2(0, 1),       # Links
	"boots": Vector2(2, 1),       # Rechts
	"weapon": Vector2(0, 0),      # Oben Links
	"shield": Vector2(2, 0),      # Oben Rechts (oder zweite Hand)
}

const SLOT_SIZE = 80
const INVENTORY_GRID_COLS = 8
const INVENTORY_GRID_ROWS = 6

const SLOT_NAMES_DE = {
	"helmet": "Helm",
	"chest": "Brust",
	"pants": "Hose",
	"gloves": "Handschuhe",
	"boots": "Stiefel",
	"weapon": "Waffe",
	"shield": "Schild"
}

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var subtitle_label: Label = $VBoxContainer/SubtitleLabel
@onready var error_label: Label = $VBoxContainer/ErrorLabel
@onready var content_container: HBoxContainer = $VBoxContainer/ContentContainer
@onready var equipped_panel: Panel = $VBoxContainer/ContentContainer/EquippedPanel
@onready var equipped_grid: GridContainer = $VBoxContainer/ContentContainer/EquippedPanel/EquippedGrid
@onready var inventory_panel: Panel = $VBoxContainer/ContentContainer/InventoryPanel
@onready var inventory_grid: GridContainer = $VBoxContainer/ContentContainer/InventoryPanel/InventoryGrid
@onready var info_label: Label = $VBoxContainer/InfoLabel
@onready var button_container: VBoxContainer = $VBoxContainer/ButtonContainer
@onready var equip_button: Button = $VBoxContainer/ButtonContainer/EquipButton
@onready var unequip_button: Button = $VBoxContainer/ButtonContainer/UnequipButton
@onready var reload_button: Button = $VBoxContainer/ButtonContainer/ReloadButton
@onready var back_button: Button = $VBoxContainer/ButtonContainer/BackButton
@onready var tooltip_panel: Panel = $TooltipPanel
@onready var tooltip_label: RichTextLabel = $TooltipPanel/TooltipLabel

var slot_index: int = 0
var player_name: String = "Unbekannt"
var player_level: int = 1
var equipped_items: Dictionary = {}
var inventory_items: Array = []
var error_message: String = ""
var info_message: String = ""
var selected_inventory_index: int = -1
var selected_equipped_slot: String = ""
var player_data: Dictionary = {}
var slot_buttons: Dictionary = {}  # slot_name -> Button
var inventory_buttons: Array = []  # Array von Buttons
var hovered_item: Dictionary = {}  # Aktuell gehovertes Item
var hovered_slot: String = ""      # Aktuell gehoverter Slot
var total_stats: Dictionary = {}   # Vollständig berechnete Basis-Stats

func _ready():
	slot_index = Constants.current_slot_index
	load_data()
	create_equipment_grid()
	create_inventory_grid()
	update_display()
	
	if equip_button:
		equip_button.pressed.connect(_on_equip_pressed)
	if unequip_button:
		unequip_button.pressed.connect(_on_unequip_pressed)
	if reload_button:
		reload_button.pressed.connect(_on_reload_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_pressed)
	
	tooltip_panel.visible = false

func load_data():
	var slot = Constants.SAVE_SLOTS[slot_index]
	var save_path = Constants.get_save_path(slot)
	var player_path = Constants.get_player_path(slot)
	var inventory_path = save_path.path_join("global_inventory.json")
	
	# Player laden
	if FileAccess.file_exists(player_path):
		var file = FileAccess.open(player_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var json_obj = JSON.new()
			if json_obj.parse(json_string) == OK:
				var raw_data = json_obj.data
				if raw_data is Dictionary:
					player_data = raw_data
					player_name = player_data.get("name", "Unbekannt")
					player_level = player_data.get("level", player_data.get("stats", {}).get("level", 1))
					var raw_equipped = player_data.get("equipped", {})
					if raw_equipped is Dictionary:
						equipped_items = raw_equipped
					else:
						equipped_items = {}

					# Vollständig berechnete Stats aus player.json (falls vorhanden)
					var raw_total = player_data.get("total_stats", {})
					if raw_total is Dictionary:
						total_stats = raw_total
					else:
						total_stats = {}
				else:
					error_message = "Spielerdatei hat ein unerwartetes Format."
			else:
				error_message = "Spielerdatei ist beschädigt."
		else:
			error_message = "Spielerdatei konnte nicht gelesen werden."
	else:
		error_message = "Spielerdatei fehlt."
	
	# Inventar laden
	if FileAccess.file_exists(inventory_path):
		var file = FileAccess.open(inventory_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var json_obj = JSON.new()
			if json_obj.parse(json_string) == OK:
				inventory_items = json_obj.data
			else:
				inventory_items = []
				error_message = "Inventardatei ist beschädigt."
		else:
			inventory_items = []
	else:
		inventory_items = []

func create_equipment_grid():
	# Grid auf 3x3 setzen
	equipped_grid.columns = 3
	
	# Erstelle alle Slots (3x3 Grid)
	for y in range(3):
		for x in range(3):
			var pos = Vector2(x, y)
			var slot_name = _get_slot_at_position(pos)
			
			var slot_button = Button.new()
			slot_button.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
			slot_button.name = "Slot_%s" % slot_name if slot_name else "Empty_%d_%d" % [x, y]
			
			if slot_name:
				var slot_display_name = SLOT_NAMES_DE.get(slot_name, slot_name.capitalize())
				slot_button.tooltip_text = slot_display_name
				slot_buttons[slot_name] = slot_button
				slot_button.pressed.connect(_on_equipped_slot_selected.bind(slot_name))
				slot_button.mouse_entered.connect(_on_slot_hover_entered.bind(slot_name))
				slot_button.mouse_exited.connect(_on_slot_hover_exited)
				slot_button.flat = false
			else:
				slot_button.disabled = true
				slot_button.modulate = Color(0.3, 0.3, 0.3, 0.3)
				slot_button.flat = true
			
			equipped_grid.add_child(slot_button)

func create_inventory_grid():
	inventory_grid.columns = INVENTORY_GRID_COLS
	
	# Erstelle leere Slots für das Inventar
	for i in range(INVENTORY_GRID_COLS * INVENTORY_GRID_ROWS):
		var slot_button = Button.new()
		slot_button.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot_button.name = "InvSlot_%d" % i
		slot_button.disabled = true
		slot_button.modulate = Color(0.2, 0.2, 0.2, 0.5)
		inventory_grid.add_child(slot_button)
		inventory_buttons.append(slot_button)

func _get_slot_at_position(pos: Vector2) -> String:
	for slot_name in EQUIPMENT_SLOTS.keys():
		if EQUIPMENT_SLOTS[slot_name] == pos:
			return slot_name
	return ""

func update_display():
	title_label.text = "Inventar"
	subtitle_label.text = "%s  |  Level %d" % [player_name, player_level]
	
	if error_message:
		error_label.text = error_message
		error_label.visible = true
	else:
		error_label.visible = false

	# Zeige zusammengefasste Basis-Stats, falls vorhanden
	if not total_stats.is_empty():
		var sb := "[b]Gesamt-Stats:[/b]\n"
		sb += "Leben: %d / %d\n" % [
			int(total_stats.get("health", total_stats.get("max_health", 0))),
			int(total_stats.get("max_health", 0))
		]
		sb += "Schaden: %d\n" % int(total_stats.get("damage", 0))
		sb += "Verteidigung: %d\n" % int(total_stats.get("defense", 0))
		sb += "Mag. Verteidigung: %d\n" % int(total_stats.get("magic_defense", 0))
		sb += "Rüstung: %d\n" % int(total_stats.get("armour", 0))
		sb += "Ausweichen: %d\n" % int(total_stats.get("evasion", 0))
		sb += "Energie-Schild: %d\n" % int(total_stats.get("energy_shield", 0))
		sb += "Blockchance: %d\n" % int(total_stats.get("block_chance", 0))
		sb += "Angriffsgeschw.: %.2f\n" % float(total_stats.get("attack_speed", 1.0))
		sb += "Bewegungsgeschw.: %d\n" % int(total_stats.get("movement_speed", 0))
		sb += "\nAttribute:\n"
		sb += "Stärke: %d\n" % int(total_stats.get("strength", 0))
		sb += "Intelligenz: %d\n" % int(total_stats.get("intelligence", 0))
		sb += "Geschicklichkeit: %d\n" % int(total_stats.get("dexterity", 0))
		sb += "Geschwindigkeit: %d\n" % int(total_stats.get("speed", 0))
		info_label.text = sb
	else:
		info_label.text = info_message
	
	update_equipped_display()
	update_inventory_display()

func update_equipped_display():
	# Aktualisiere alle Equipment-Slots
	for slot_name in EQUIPMENT_SLOTS.keys():
		if not slot_buttons.has(slot_name):
			continue
		
		var slot_button = slot_buttons[slot_name]
		var item = equipped_items.get(slot_name)
		
		if item and not item.is_empty():
			# Item ist angelegt
			var item_name = item.get("name", item.get("id", "Item"))
			slot_button.text = item_name.substr(0, 1).to_upper()  # Erster Buchstabe als Symbol
			slot_button.modulate = Color.WHITE if slot_name != selected_equipped_slot else Color(0.5, 0.7, 1.0)
		else:
			# Slot ist leer - zeige Slot-Namen
			var slot_display_name = SLOT_NAMES_DE.get(slot_name, slot_name.capitalize())
			slot_button.text = slot_display_name.substr(0, 1)  # Erster Buchstabe des Slot-Namens
			slot_button.modulate = Color(0.5, 0.5, 0.5, 0.7) if slot_name != selected_equipped_slot else Color(0.5, 0.7, 1.0)

func update_inventory_display():
	# Entferne alle alten Buttons
	for button in inventory_buttons:
		button.queue_free()
	inventory_buttons.clear()
	
	# Erstelle neue Buttons für alle Slots
	for i in range(INVENTORY_GRID_COLS * INVENTORY_GRID_ROWS):
		var slot_button = Button.new()
		slot_button.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot_button.name = "InvSlot_%d" % i
		slot_button.flat = true
		
		if i < inventory_items.size():
			# Item vorhanden
			var item = inventory_items[i]
			var item_name = item.get("name", item.get("id", "Item"))
			slot_button.text = item_name.substr(0, 1).to_upper()  # Erster Buchstabe als Symbol
			slot_button.disabled = false
			slot_button.flat = false
			slot_button.modulate = Color.WHITE if i != selected_inventory_index else Color(0.5, 1.0, 0.7)
			
			slot_button.pressed.connect(_on_inventory_item_selected.bind(i))
			slot_button.mouse_entered.connect(_on_item_hover_entered.bind(item))
			slot_button.mouse_exited.connect(_on_item_hover_exited)
		else:
			# Leerer Slot
			slot_button.disabled = true
			slot_button.modulate = Color(0.2, 0.2, 0.2, 0.5)
		
		inventory_grid.add_child(slot_button)
		inventory_buttons.append(slot_button)

func _on_equipped_slot_selected(slot: String):
	selected_equipped_slot = slot
	selected_inventory_index = -1
	info_message = "Slot '%s' ausgewählt." % slot
	info_label.text = info_message
	update_equipped_display()
	update_inventory_display()

func _on_inventory_item_selected(index: int):
	selected_inventory_index = index
	selected_equipped_slot = ""
	if index < inventory_items.size():
		var item = inventory_items[index]
		var item_name = item.get("name", item.get("id", "Item"))
		info_message = "Inventar-Item '%s' ausgewählt." % item_name
		info_label.text = info_message
	update_equipped_display()
	update_inventory_display()

func _on_slot_hover_entered(slot: String):
	hovered_slot = slot
	var item = equipped_items.get(slot)
	if item and not item.is_empty():
		hovered_item = item
		_show_tooltip(item)
	else:
		hovered_item = {}
		_hide_tooltip()

func _on_slot_hover_exited():
	hovered_slot = ""
	hovered_item = {}
	_hide_tooltip()

func _on_item_hover_entered(item: Dictionary):
	hovered_item = item
	_show_tooltip(item)

func _on_item_hover_exited():
	hovered_item = {}
	_hide_tooltip()

func _show_tooltip(item: Dictionary):
	if item.is_empty():
		return
	
	var tooltip_text_local = _format_item_tooltip(item)
	tooltip_label.text = tooltip_text_local
	tooltip_panel.visible = true

func _hide_tooltip():
	tooltip_panel.visible = false

func _format_item_tooltip(item: Dictionary) -> String:
	if item.is_empty():
		return ""
	
	var base_text = "[b]%s[/b]\n" % item.get("name", item.get("id", "Unbekannt"))
	base_text += "Level: %s\n" % str(item.get("item_level", "?"))
	base_text += "Typ: %s\n" % item.get("item_type", "?")

	# Stats des Hover-Items
	var stats: Dictionary = item.get("stats", {})
	if not stats.is_empty():
		base_text += "\n[b]Stats:[/b]\n"
		for stat_name in stats.keys():
			var value = stats[stat_name]
			if value != 0:
				base_text += "%s: %s\n" % [stat_name.capitalize(), str(value)]

	# Vergleich mit ausgerüstetem Item (falls vorhanden und Slot eindeutig bestimmbar)
	var slot_name := ""
	if item.has("item_type"):
		var item_type: String = String(item.get("item_type", ""))
		slot_name = SLOT_MAP.get(item_type, "")

	if slot_name != "" and equipped_items.has(slot_name):
		var equipped_item = equipped_items.get(slot_name)
		if equipped_item is Dictionary and not (equipped_item as Dictionary).is_empty():
			var eq_stats: Dictionary = (equipped_item as Dictionary).get("stats", {})
			if not eq_stats.is_empty():
				base_text += "\n[b]Vergleich mit ausgerüstetem %s:[/b]\n" % SLOT_NAMES_DE.get(slot_name, slot_name.capitalize())
				for stat_name in stats.keys():
					var new_val = int(stats.get(stat_name, 0))
					var old_val = int(eq_stats.get(stat_name, 0))
					if new_val == 0 and old_val == 0:
						continue
					var diff = new_val - old_val
					var line = "%s: %d (aktuell: %d" % [stat_name.capitalize(), new_val, old_val]
					if diff > 0:
						line += ", [color=green]+%d[/color]" % diff
					elif diff < 0:
						line += ", [color=red]%d[/color]" % diff
					line += ")\n"
					base_text += line

	# Requirements
	var requirements = item.get("requirements", {})
	if not requirements.is_empty():
		base_text += "\n[b]Anforderungen:[/b]\n"
		for req_name in requirements.keys():
			var value = requirements[req_name]
			if value != 0:
				base_text += "%s: %s\n" % [req_name.capitalize(), str(value)]

	# Enchantments
	var enchantments = item.get("enchantments", [])
	if not enchantments.is_empty():
		base_text += "\n[b]Verzauberungen:[/b]\n"
		for enchant in enchantments:
			var enchant_name = enchant.get("name", "?")
			var enchant_value = enchant.get("value", 0)
			base_text += "%s: +%s\n" % [enchant_name, str(enchant_value)]

	return base_text

func _process(_delta):
	if tooltip_panel.visible:
		var mouse_pos = get_global_mouse_position()
		var tooltip_pos = mouse_pos + Vector2(20, 20)
		
		# Stelle sicher, dass Tooltip nicht außerhalb des Bildschirms ist
		if tooltip_pos.x + tooltip_panel.size.x > Constants.WIDTH:
			tooltip_pos.x = mouse_pos.x - tooltip_panel.size.x - 20
		if tooltip_pos.y + tooltip_panel.size.y > Constants.HEIGHT:
			tooltip_pos.y = mouse_pos.y - tooltip_panel.size.y - 20
		
		tooltip_panel.position = tooltip_pos

func _on_equip_pressed():
	if selected_inventory_index < 0 or selected_inventory_index >= inventory_items.size():
		info_message = "Kein Inventar-Item ausgewählt."
		info_label.text = info_message
		return
	
	var item = inventory_items[selected_inventory_index]
	var item_type = item.get("item_type", "")
	var target_slot = resolve_slot(item_type)
	
	if target_slot.is_empty():
		info_message = "Für diesen Item-Typ existiert kein Slot."
		info_label.text = info_message
		return
	
	# Item aus Inventar entfernen und anlegen
	item = inventory_items.pop_at(selected_inventory_index)
	var prev_item = equipped_items.get(target_slot)
	equipped_items[target_slot] = item
	if prev_item:
		inventory_items.append(prev_item)
	
	selected_inventory_index = -1
	persist_changes()
	var equipped_name = item.get("name", item.get("id", "Item"))
	info_message = "%s wurde ausgerüstet." % equipped_name
	info_label.text = info_message
	update_display()

func _on_unequip_pressed():
	if selected_equipped_slot.is_empty():
		info_message = "Kein Ausrüstungs-Slot ausgewählt."
		info_label.text = info_message
		return
	
	var item = equipped_items.get(selected_equipped_slot)
	if not item or item.is_empty():
		info_message = "Dieser Slot ist leer."
		info_label.text = info_message
		return
	
	inventory_items.append(item)
	equipped_items[selected_equipped_slot] = null
	persist_changes()
	var unequipped_name = item.get("name", item.get("id", "Item"))
	info_message = "%s abgelegt." % unequipped_name
	info_label.text = info_message
	selected_equipped_slot = ""
	update_display()

func _on_reload_pressed():
	selected_equipped_slot = ""
	selected_inventory_index = -1
	info_message = ""
	load_data()
	update_display()

func _on_back_pressed():
	print("Zurück-Button gedrückt (Inventory)")
	get_tree().call_deferred("change_scene_to_file", "res://scenes/town_scene.tscn")

func persist_changes():
	var slot = Constants.SAVE_SLOTS[slot_index]
	var save_path = Constants.get_save_path(slot)
	var player_path = Constants.get_player_path(slot)
	var inventory_path = save_path.path_join("global_inventory.json")
	
	# Player speichern
	if not player_data.is_empty():
		player_data["equipped"] = equipped_items
		var player_file = FileAccess.open(player_path, FileAccess.WRITE)
		if player_file:
			player_file.store_string(JSON.stringify(player_data, "\t"))
			player_file.close()
	
	# Inventar speichern
	var inv_file = FileAccess.open(inventory_path, FileAccess.WRITE)
	if inv_file:
		inv_file.store_string(JSON.stringify(inventory_items, "\t"))
		inv_file.close()

func resolve_slot(item_type: String) -> String:
	if item_type.is_empty():
		return ""
	return SLOT_MAP.get(item_type.to_lower(), "")
