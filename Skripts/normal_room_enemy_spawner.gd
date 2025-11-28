extends Node2D

## normal_room_enemy_spawner.gd
## Генерирует врагов внутри NormalRoom1 с использованием EnemyGenerator.gd

const EnemyGeneratorScript := preload("res://Skripts/enemy_generator.gd")
const LootGeneratorScript := preload("res://core/loot_generator.gd")

@export var field_number: int = 1

@onready var tilemap_layer: TileMapLayer = $TileMap/TileMapLayer
@onready var dev_toggle_button: Button = $CanvasLayer/DevToggleButton
@onready var dev_overlay: Control = $CanvasLayer/DevOverlay
@onready var dev_enemy_label: Label = $CanvasLayer/DevOverlay/Panel/VBoxContainer/EnemyCountLabel
@onready var dev_minus_button: Button = $CanvasLayer/DevOverlay/Panel/VBoxContainer/HBoxButtons/MinusButton
@onready var dev_plus_button: Button = $CanvasLayer/DevOverlay/Panel/VBoxContainer/HBoxButtons/PlusButton
@onready var dev_magic_label: Label = $CanvasLayer/DevOverlay/Panel/VBoxContainer/MagicLabel
@onready var dev_magic_minus_button: Button = $CanvasLayer/DevOverlay/Panel/VBoxContainer/MagicButtons/MagicMinusButton
@onready var dev_magic_plus_button: Button = $CanvasLayer/DevOverlay/Panel/VBoxContainer/MagicButtons/MagicPlusButton
@onready var dev_epic_label: Label = $CanvasLayer/DevOverlay/Panel/VBoxContainer/EpicLabel
@onready var dev_epic_minus_button: Button = $CanvasLayer/DevOverlay/Panel/VBoxContainer/EpicButtons/EpicMinusButton
@onready var dev_epic_plus_button: Button = $CanvasLayer/DevOverlay/Panel/VBoxContainer/EpicButtons/EpicPlusButton
@onready var dev_level_min_label: Label = $CanvasLayer/DevOverlay/Panel/VBoxContainer/LevelMinLabel
@onready var dev_level_min_minus_button: Button = $CanvasLayer/DevOverlay/Panel/VBoxContainer/LevelMinButtons/LevelMinMinusButton
@onready var dev_level_min_plus_button: Button = $CanvasLayer/DevOverlay/Panel/VBoxContainer/LevelMinButtons/LevelMinPlusButton
@onready var dev_level_max_label: Label = $CanvasLayer/DevOverlay/Panel/VBoxContainer/LevelMaxLabel
@onready var dev_level_max_minus_button: Button = $CanvasLayer/DevOverlay/Panel/VBoxContainer/LevelMaxButtons/LevelMaxMinusButton
@onready var dev_level_max_plus_button: Button = $CanvasLayer/DevOverlay/Panel/VBoxContainer/LevelMaxButtons/LevelMaxPlusButton
@onready var dev_apply_button: Button = $CanvasLayer/DevOverlay/Panel/VBoxContainer/ApplyButton
@onready var dev_close_button: Button = $CanvasLayer/DevOverlay/Panel/VBoxContainer/CloseButton

var dev_enemy_count: int = 0 # normale
var dev_magic_count: int = 0
var dev_epic_count: int = 0
var dev_level_min: int = 1
var dev_level_max: int = 10

var enemy_generator: Node = null
var enemies_root: Node2D = null
var enemy_data_map: Dictionary = {}
var player: Node2D = null
var player_stats: Dictionary = {}
var level_type: String = "Feld"
var loot_generator
var slot_index: int = 0
@onready var enemy_info_label: RichTextLabel = $CanvasLayer/EnemyInfoLabel
@onready var level_label: Label = $CanvasLayer/LevelLabel
@onready var win_overlay: Control = $CanvasLayer/WinOverlay
@onready var win_retry_button: Button = $CanvasLayer/WinOverlay/Panel/VBoxContainer/Buttons/RetryButton
@onready var win_next_button: Button = $CanvasLayer/WinOverlay/Panel/VBoxContainer/Buttons/NextButton
@onready var win_exit_button: Button = $CanvasLayer/WinOverlay/Panel/VBoxContainer/Buttons/ExitButton
@onready var loot_label: Label = $CanvasLayer/LootLabel
@onready var loot_timer: Timer = $CanvasLayer/LootTimer


func _ready() -> void:
	enemy_generator = EnemyGeneratorScript.new()
	loot_generator = LootGeneratorScript.new()
	slot_index = Constants.current_slot_index
	# Versuche Player im Baum zu finden (globaler Player-Node)
	player = get_tree().get_root().find_child("Player", true, false)

	# Level-Infos aus den globalen Constants übernehmen (von Levelauswahl gesetzt)
	level_type = Constants.current_level_type
	field_number = Constants.current_level_number

	_load_player_stats()

	_setup_dev_overlay()
	_update_level_label()
	_regenerate_enemies()


func _load_player_stats() -> void:
	# Gleiche vereinfachte Logik wie in scenes/battle_scene.gd
	player_stats = {}
	var slot = Constants.SAVE_SLOTS[slot_index]
	var player_path = Constants.get_player_path(slot)

	if FileAccess.file_exists(player_path):
		var file = FileAccess.open(player_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()
			var json_obj = JSON.new()
			if json_obj.parse(json_string) == OK:
				var player_data = json_obj.data
				player_stats = player_data.get("stats", {})
				if player_stats.is_empty():
					player_stats = player_data.get("total_stats", {})


func _setup_dev_overlay() -> void:
	# Dev-Toggle-Button
	if dev_toggle_button:
		dev_toggle_button.pressed.connect(_on_dev_toggle_pressed)
		# Nur anzeigen, wenn Dev-Modus generell aktiv ist
		dev_toggle_button.visible = DevSettings.dev_mode

	if dev_overlay == null:
		return

	# Initiale Werte aus DevSettings holen
	var settings := DevSettings.get_settings()
	dev_enemy_count = int(settings.get("enemy_count", 3))
	dev_magic_count = int(settings.get("enemy_magic_count", 1))
	dev_epic_count = int(settings.get("enemy_epic_count", 0))
	dev_level_min = int(settings.get("monster_level_min", 1))
	dev_level_max = int(settings.get("monster_level_max", 10))

	_update_dev_labels()

	# Sichtbarkeit abhängig vom Dev-Modus und gemerktem Overlay-Status
	dev_overlay.visible = DevSettings.dev_mode and DevSettings.dev_overlay_visible

	# Buttons verbinden
	if dev_minus_button:
		dev_minus_button.pressed.connect(_on_dev_minus_pressed)
	if dev_plus_button:
		dev_plus_button.pressed.connect(_on_dev_plus_pressed)
	if dev_magic_minus_button:
		dev_magic_minus_button.pressed.connect(_on_dev_magic_minus_pressed)
	if dev_magic_plus_button:
		dev_magic_plus_button.pressed.connect(_on_dev_magic_plus_pressed)
	if dev_epic_minus_button:
		dev_epic_minus_button.pressed.connect(_on_dev_epic_minus_pressed)
	if dev_epic_plus_button:
		dev_epic_plus_button.pressed.connect(_on_dev_epic_plus_pressed)
	if dev_level_min_minus_button:
		dev_level_min_minus_button.pressed.connect(_on_dev_level_min_minus_pressed)
	if dev_level_min_plus_button:
		dev_level_min_plus_button.pressed.connect(_on_dev_level_min_plus_pressed)
	if dev_level_max_minus_button:
		dev_level_max_minus_button.pressed.connect(_on_dev_level_max_minus_pressed)
	if dev_level_max_plus_button:
		dev_level_max_plus_button.pressed.connect(_on_dev_level_max_plus_pressed)
	if dev_apply_button:
		dev_apply_button.pressed.connect(_on_dev_apply_pressed)
	if dev_close_button:
		dev_close_button.pressed.connect(_on_dev_close_pressed)

	# Win-Overlay Buttons
	if win_retry_button:
		win_retry_button.pressed.connect(_on_win_retry_pressed)
	if win_next_button:
		win_next_button.pressed.connect(_on_win_next_pressed)
	if win_exit_button:
		win_exit_button.pressed.connect(_on_win_exit_pressed)
	if loot_timer:
		loot_timer.timeout.connect(_on_loot_timer_timeout)


func _update_dev_labels() -> void:
	if dev_enemy_label:
		dev_enemy_label.text = "Normale: %d" % dev_enemy_count
	if dev_magic_label:
		dev_magic_label.text = "Magische: %d" % dev_magic_count
	if dev_epic_label:
		dev_epic_label.text = "Epische: %d" % dev_epic_count
	if dev_level_min_label:
		dev_level_min_label.text = "Level-Minimum: %d" % dev_level_min
	if dev_level_max_label:
		dev_level_max_label.text = "Level-Maximum: %d" % dev_level_max


func _update_level_label() -> void:
	if level_label:
		var prefix := level_type
		if prefix == "":
			prefix = "Level"
		level_label.text = "%s %d" % [prefix, field_number]


func _regenerate_enemies() -> void:
	# Alte Gegner entfernen
	if enemies_root and is_instance_valid(enemies_root):
		enemies_root.queue_free()
	enemy_data_map.clear()

	# Container für Gegner anlegen
	enemies_root = Node2D.new()
	enemies_root.name = "Enemies"
	add_child(enemies_root)

	var enemies_data: Array = []
	if DevSettings.dev_mode:
		enemies_data = _generate_dev_enemies()
	else:
		enemies_data = enemy_generator.generate_field_enemies(field_number, {})
	_spawn_enemies(enemies_data)


func _generate_dev_enemies() -> Array:
	var enemies: Array = []

	var lvl_min := dev_level_min
	var lvl_max := dev_level_max
	if lvl_max < lvl_min:
		lvl_max = lvl_min

	# Normale Gegner (keine Verzauberungen)
	for i in range(dev_enemy_count):
		var e_norm: Dictionary = enemy_generator.generate_enemy("", 0, lvl_min, lvl_max)
		if not e_norm.is_empty():
			enemies.append(e_norm)

	# Magische Gegner (1–3 Verzauberungen)
	for i in range(dev_magic_count):
		var ench_magic := randi_range(1, 3)
		var e_magic: Dictionary = enemy_generator.generate_enemy("", ench_magic, lvl_min, lvl_max)
		if not e_magic.is_empty():
			enemies.append(e_magic)

	# Epische Gegner (4–6 Verzauberungen)
	for i in range(dev_epic_count):
		var ench_epic := randi_range(4, 6)
		var e_epic: Dictionary = enemy_generator.generate_enemy("", ench_epic, lvl_min, lvl_max)
		if not e_epic.is_empty():
			enemies.append(e_epic)

	return enemies


func _spawn_enemies(enemies_data: Array) -> void:
	if tilemap_layer == null:
		push_warning("normal_room_enemy_spawner: TileMapLayer nicht gefunden, spawne um (0,0)")
		for i in range(enemies_data.size()):
			var pos := Vector2(randf_range(-50, 50), randf_range(-50, 50))
			_create_enemy_visual(pos, enemies_data[i])
		return

	var used_rect: Rect2i = tilemap_layer.get_used_rect()

	for enemy_data in enemies_data:
		var tries := 50
		var world_pos := Vector2.ZERO
		var found := false

		while tries > 0 and not found:
			var cx := randi_range(used_rect.position.x, used_rect.position.x + used_rect.size.x - 1)
			var cy := randi_range(used_rect.position.y, used_rect.position.y + used_rect.size.y - 1)
			var cell := Vector2i(cx, cy)
			if _is_floor_cell(cell):
				world_pos = tilemap_layer.map_to_local(cell)
				found = true
			tries -= 1

		if found:
			_create_enemy_visual(world_pos, enemy_data)


func _is_floor_cell(cell: Vector2i) -> bool:
	if tilemap_layer == null:
		return false

	# Muss ein Tile sein
	if tilemap_layer.get_cell_source_id(cell) == -1:
		return false

	# Floor-Heuristik: Tile + alle 4 Nachbarn sind ebenfalls Tiles
	var dirs := [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
	]
	for d in dirs:
		var n: Vector2i = cell + d
		if tilemap_layer.get_cell_source_id(n) == -1:
			return false

	return true


func _on_dev_minus_pressed() -> void:
	dev_enemy_count = max(1, dev_enemy_count - 1)
	DevSettings.enemy_count = dev_enemy_count
	_update_dev_labels()


func _on_dev_plus_pressed() -> void:
	dev_enemy_count += 1
	DevSettings.enemy_count = dev_enemy_count
	_update_dev_labels()


func _on_dev_magic_minus_pressed() -> void:
	dev_magic_count = max(0, dev_magic_count - 1)
	DevSettings.enemy_magic_count = dev_magic_count
	_update_dev_labels()


func _on_dev_magic_plus_pressed() -> void:
	dev_magic_count += 1
	DevSettings.enemy_magic_count = dev_magic_count
	_update_dev_labels()


func _on_dev_epic_minus_pressed() -> void:
	dev_epic_count = max(0, dev_epic_count - 1)
	DevSettings.enemy_epic_count = dev_epic_count
	_update_dev_labels()


func _on_dev_epic_plus_pressed() -> void:
	dev_epic_count += 1
	DevSettings.enemy_epic_count = dev_epic_count
	_update_dev_labels()


func _on_dev_level_min_minus_pressed() -> void:
	dev_level_min = max(1, dev_level_min - 1)
	if dev_level_max < dev_level_min:
		dev_level_max = dev_level_min
	DevSettings.monster_level_min = dev_level_min
	DevSettings.monster_level_max = dev_level_max
	_update_dev_labels()


func _on_dev_level_min_plus_pressed() -> void:
	dev_level_min += 1
	if dev_level_max < dev_level_min:
		dev_level_max = dev_level_min
	DevSettings.monster_level_min = dev_level_min
	DevSettings.monster_level_max = dev_level_max
	_update_dev_labels()


func _on_dev_level_max_minus_pressed() -> void:
	dev_level_max = max(dev_level_min, dev_level_max - 1)
	DevSettings.monster_level_min = dev_level_min
	DevSettings.monster_level_max = dev_level_max
	_update_dev_labels()


func _on_dev_level_max_plus_pressed() -> void:
	dev_level_max += 1
	DevSettings.monster_level_min = dev_level_min
	DevSettings.monster_level_max = dev_level_max
	_update_dev_labels()


func _on_dev_apply_pressed() -> void:
	_regenerate_enemies()


func _on_dev_close_pressed() -> void:
	if dev_overlay:
		dev_overlay.visible = false


func _on_dev_toggle_pressed() -> void:
	if not DevSettings.dev_mode:
		# Wenn globaler Dev-Modus aus ist, einfach ignorieren
		return
	if dev_overlay:
		dev_overlay.visible = not dev_overlay.visible
		DevSettings.dev_overlay_visible = dev_overlay.visible


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		# Verwende globale Mausposition (Weltkoordinaten), damit es mit der Kamera stimmt
		var global_mouse: Vector2 = get_global_mouse_position()
		_update_enemy_hover_info(global_mouse)

	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var click_pos: Vector2 = get_global_mouse_position()
		_handle_enemy_click(click_pos)


func _get_enemy_under_point(world_pos: Vector2, radius: float = 16.0) -> Node2D:
	var radius_sq := radius * radius
	for enemy in enemy_data_map.keys():
		if not is_instance_valid(enemy):
			continue
		var e_pos: Vector2 = enemy.global_position
		var dist_sq := (world_pos - e_pos).length_squared()
		if dist_sq <= radius_sq:
			return enemy
	return null


func _handle_enemy_click(world_pos: Vector2) -> void:
	if player == null:
		return

	var enemy: Node2D = _get_enemy_under_point(world_pos, 16.0)
	if enemy == null:
		return

	# Prüfe Distanz zum Spieler (Nahkampfradius)
	var p_pos: Vector2 = player.global_position
	if p_pos.distance_to(enemy.global_position) > 64.0:
		return

	# Blickrichtung prüfen
	if not _is_player_facing_enemy(enemy.global_position):
		return

	_apply_attack_to_enemy(enemy)


func _is_player_facing_enemy(enemy_pos: Vector2) -> bool:
	# Hol dir die Blickrichtung aus dem Player-Script (last_facing oder facing)
	if player == null:
		return false

	var facing: String = "down"
	if player.has_method("get"):
		# Versuche erst last_facing (für Idle), sonst facing.
		# get() gibt null zurück, wenn die Property nicht existiert.
		var lf = player.get("last_facing")
		var f = player.get("facing")
		if lf != null:
			facing = String(lf)
		elif f != null:
			facing = String(f)

	var p_pos: Vector2 = player.global_position
	var dir: Vector2 = (enemy_pos - p_pos)
	if dir.length() == 0.0:
		return true
	dir = dir.normalized()

	# Dominante Achse bestimmen
	if abs(dir.x) > abs(dir.y):
		# Horizontal dominiert
		if dir.x > 0.0:
			return facing == "right"
		else:
			return facing == "left"
	else:
		# Vertikal dominiert
		if dir.y > 0.0:
			return facing == "down"
		else:
			return facing == "up"


func _update_enemy_hover_info(mouse_pos: Vector2) -> void:
	if enemies_root == null or enemy_info_label == null:
		return

	var hovered_enemy: Node2D = null
	var radius_squared := 16.0 * 16.0

	for enemy in enemy_data_map.keys():
		if not is_instance_valid(enemy):
			continue
		var world_pos: Vector2 = enemy.global_position
		var dist_sq := (mouse_pos - world_pos).length_squared()
		if dist_sq <= radius_squared:
			hovered_enemy = enemy
			break

	if hovered_enemy == null:
		enemy_info_label.visible = false
		return

	var data: Dictionary = enemy_data_map.get(hovered_enemy, {})
	if data.is_empty():
		enemy_info_label.visible = false
		return

	var stats: Dictionary = data.get("final_stats", data.get("generated_stats", {}))
	var enchants: Array = data.get("enchantments", [])
	var enchant_count: int = enchants.size()
	var loot_quality: String = String(data.get("loot_quality", "")).to_lower()
	var is_unique: bool = bool(data.get("is_unique", false)) or loot_quality == "unique"

	# Namensfarbe wie in battle_scene.py
	var name_color: String = "#FFFFFF" # WHITE
	if is_unique:
		name_color = "#D27800"         # DARK_ORANGE
	elif enchant_count >= 5:
		name_color = "#FFD700"         # GOLD
	elif enchant_count >= 3:
		name_color = "#BA55D3"         # PURPLE
	elif enchant_count >= 1:
		name_color = "#6495ED"         # BLUE

	var sb := ""
	var name_text := String(data.get("name", data.get("id", "Enemy")))
	sb += "[color=%s][b]%s[/b][/color]\n" % [name_color, name_text]
	sb += "Level: %d\n" % int(data.get("level", 1))
	var current_hp: int = int(data.get("current_hp", stats.get("hp", stats.get("max_hp", 0))))
	var max_hp_hover: int = int(stats.get("max_hp", current_hp))
	sb += "HP: %d / %d\n" % [current_hp, max_hp_hover]
	sb += "Damage: %d\n" % int(stats.get("damage", 0))
	sb += "Defense: %d\n" % int(stats.get("defense", 0))
	sb += "Attack Speed: %.2f\n" % float(stats.get("attack_speed", 0.0))
	sb += "Evasion: %d\n" % int(stats.get("evasion", 0))

	if enchants.size() > 0:
		sb += "\n[b]Verzauberungen:[/b]\n"
		for e in enchants:
			var etype := String(e.get("type", ""))
			var val: Variant = e.get("value", 0)
			sb += "- %s: %s\n" % [etype, str(val)]

	enemy_info_label.bbcode_text = sb
	enemy_info_label.visible = true


func _apply_attack_to_enemy(enemy: Node2D) -> void:
	if not enemy_data_map.has(enemy):
		return

	var data: Dictionary = enemy_data_map[enemy]
	var stats: Dictionary = data.get("final_stats", data.get("generated_stats", {}))

	# Aktuelle HP im Datensatz initialisieren
	if not data.has("current_hp"):
		data["current_hp"] = int(stats.get("hp", stats.get("max_hp", 0)))

	var enemy_hp: int = int(data.get("current_hp", 0))
	var enemy_def: int = int(stats.get("defense", 0))

	# Spieler-Schaden aus gespeicherten Stats (wie in Battle-Szene)
	var p_dmg: int = int(player_stats.get("damage", 10))
	var damage_done: int = max(1, p_dmg - enemy_def)

	var new_hp: int = max(0, enemy_hp - damage_done)
	data["current_hp"] = new_hp

	# HP-Balken aktualisieren
	var max_hp: int = int(stats.get("max_hp", enemy_hp))
	if max_hp > 0:
		var ratio: float = clamp(float(new_hp) / float(max_hp), 0.0, 1.0)
		var bar_fg := enemy.get_node_or_null("HPBar")
		if bar_fg != null and bar_fg is ColorRect:
			bar_fg.size.x = 18.0 * ratio

	# Gegner entfernen, wenn HP 0
	if new_hp <= 0:
		_handle_enemy_death(data)
		enemy.queue_free()
		enemy_data_map.erase(enemy)
		_check_all_enemies_defeated()


func _handle_enemy_death(enemy_data: Dictionary) -> void:
	if loot_generator == null:
		_show_loot_message("Kein Loot")
		return

	var monster_level: int = int(enemy_data.get("level", 1))
	var loot_item: Dictionary = loot_generator.generate_loot(monster_level)
	if loot_item.is_empty():
		_show_loot_message("Kein Loot")
		return

	_add_item_to_inventory(loot_item)
	var item_name := String(loot_item.get("name", loot_item.get("id", "Item")))
	print("💰 Dungeon-Loot erhalten: %s" % item_name)

	_show_loot_message("Loot erhalten: %s" % item_name)


func _add_item_to_inventory(item: Dictionary) -> void:
	# Gleiche Logik wie in scenes/battle_scene.gd
	var slot = Constants.SAVE_SLOTS[slot_index]
	var save_path = Constants.get_save_path(slot)
	DirAccess.make_dir_recursive_absolute(save_path)
	var inventory_path = save_path.path_join("global_inventory.json")

	var inventory: Array = []
	if FileAccess.file_exists(inventory_path):
		var file_r = FileAccess.open(inventory_path, FileAccess.READ)
		if file_r:
			var json_string = file_r.get_as_text()
			file_r.close()
			var json_obj = JSON.new()
			if json_obj.parse(json_string) == OK:
				inventory = json_obj.data

	inventory.append(item)

	var file_w = FileAccess.open(inventory_path, FileAccess.WRITE)
	if file_w:
		file_w.store_string(JSON.stringify(inventory, "\t"))
		file_w.close()


func _show_loot_message(text: String) -> void:
	if loot_label:
		loot_label.text = text
		loot_label.visible = true
	if loot_timer:
		loot_timer.start()


func _on_loot_timer_timeout() -> void:
	if loot_label:
		loot_label.visible = false


func _check_all_enemies_defeated() -> void:
	if enemy_data_map.is_empty():
		if win_overlay:
			win_overlay.visible = true


func _create_enemy_visual(pos: Vector2, enemy_data: Dictionary) -> void:
	var enemy := Node2D.new()
	enemy.name = String(enemy_data.get("name", "Enemy"))
	enemy.position = pos
	enemy.z_index = 5
	if enemies_root:
		enemies_root.add_child(enemy)
	else:
		add_child(enemy)

	# Roter Punkt
	var marker := ColorRect.new()
	marker.color = Color(1, 0, 0, 0.9)
	marker.size = Vector2(10, 10)
	marker.position = Vector2(-5, -5)
	enemy.add_child(marker)

	# HP-Balken basierend auf Stats
	var stats: Dictionary = enemy_data.get("final_stats", enemy_data.get("generated_stats", {}))
	var max_hp := int(stats.get("max_hp", stats.get("hp", 10)))
	var hp := int(stats.get("hp", max_hp))
	var hp_ratio := 1.0
	if max_hp > 0:
		hp_ratio = clamp(float(hp) / float(max_hp), 0.0, 1.0)

	var bar_bg := ColorRect.new()
	bar_bg.color = Color(0.1, 0.1, 0.1, 0.9)
	bar_bg.size = Vector2(18, 4)
	bar_bg.position = Vector2(-9, -11)
	enemy.add_child(bar_bg)

	var bar_fg := ColorRect.new()
	bar_fg.name = "HPBar"
	bar_fg.color = Color(0, 1, 0, 0.9)
	bar_fg.size = Vector2(18 * hp_ratio, 4)
	bar_fg.position = Vector2(-9, -11)
	enemy.add_child(bar_fg)

	# Daten merken für Hover
	enemy_data_map[enemy] = enemy_data


func _on_win_retry_pressed() -> void:
	if win_overlay:
		win_overlay.visible = false
	_regenerate_enemies()


func _on_win_next_pressed() -> void:
	# Nächstes Level wählen:
	# Nach Feld 5 geht es mit Cave 1 weiter.
	if level_type == "Feld":
		if field_number < 5:
			field_number += 1
		else:
			level_type = "Cave"
			field_number = 1
	else:
		# In Caves einfach weiterzählen
		field_number += 1

	Constants.current_level_type = level_type
	Constants.current_level_number = field_number
	_update_level_label()
	if win_overlay:
		win_overlay.visible = false
	_regenerate_enemies()


func _on_win_exit_pressed() -> void:
	# Zurück zur Stadt-Szene
	get_tree().call_deferred("change_scene_to_file", "res://scenes/town_scene.tscn")
