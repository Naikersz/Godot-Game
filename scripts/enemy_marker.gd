extends Node2D

## Einfache visuelle Darstellung eines Gegners:
## - Farbiger Punkt je nach Rarity
## - Grüne HP-Leiste darüber
## - Tooltip mit allen Stats beim Hovern (per Distanz zur Maus)

const HOVER_RADIUS: float = 40.0
const CLICK_RADIUS: float = 32.0

const DROPPED_LOOT_PATH := "res://scripts/dropped_loot.gd"

var enemy_data: Dictionary = {}
var tooltip_label: Label


func _ready() -> void:
	set_process(true)

	# Tooltip-Label über dem Gegner
	tooltip_label = Label.new()
	tooltip_label.visible = false
	tooltip_label.position = Vector2(0, -28)
	tooltip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tooltip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tooltip_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	tooltip_label.set("theme_override_colors/font_color", Color.WHITE)
	tooltip_label.set("theme_override_colors/font_outline_color", Color(0, 0, 0, 0.9))
	tooltip_label.set("theme_override_constants/outline_size", 2)
	add_child(tooltip_label)


func setup(data: Dictionary) -> void:
	enemy_data = data
	queue_redraw()


func _process(_delta: float) -> void:
	if enemy_data.is_empty():
		return

	var mouse_pos: Vector2 = get_global_mouse_position()
	var dist: float = global_position.distance_to(mouse_pos)

	if dist <= HOVER_RADIUS:
		_update_hud_info(_build_stats_text())


func _draw() -> void:
	if enemy_data.is_empty():
		return

	var rarity: String = String(enemy_data.get("rarity", "normal"))
	var color: Color = _get_color_for_rarity(rarity)

	# Farbiger Punkt
	draw_circle(Vector2.ZERO, 6.0, color)

	# HP-Bar (grün) darüber
	var hp: int = int(enemy_data.get("hp", 1))
	var max_hp: int = int(enemy_data.get("max_hp", hp))
	if max_hp <= 0:
		max_hp = 1

	var width: float = 24.0
	var height: float = 4.0
	var ratio: float = clamp(float(hp) / float(max_hp), 0.0, 1.0)

	# Hintergrund (dunkel)
	var bg_rect: Rect2 = Rect2(Vector2(-width * 0.5, -14.0), Vector2(width, height))
	draw_rect(bg_rect, Color(0, 0, 0, 0.7), true)

	# Vordergrund (grün)
	var fg_rect: Rect2 = Rect2(
		Vector2(-width * 0.5, -14.0),
		Vector2(width * ratio, height)
	)
	draw_rect(fg_rect, Color(0.0, 1.0, 0.0, 0.9), true)


func _build_stats_text() -> String:
	var sb: String = ""
	var enemy_name: String = String(enemy_data.get("name", "Monster"))
	var lvl: int = int(enemy_data.get("level", 1))
	var rarity: String = String(enemy_data.get("rarity", "normal"))
	var hp: int = int(enemy_data.get("hp", 1))
	var max_hp: int = int(enemy_data.get("max_hp", hp))
	var dmg: int = int(enemy_data.get("damage", 0))
	var defense: int = int(enemy_data.get("defense", 0))

	var color_hex: String = _get_color_hex_for_rarity(rarity)
	sb += "[color=%s]%s[/color] (Lvl %d)\n" % [color_hex, enemy_name, lvl]
	sb += "Rarity: %s\n" % rarity.capitalize()
	sb += "HP: %d / %d\n" % [hp, max_hp]
	sb += "DMG: %d   DEF: %d\n" % [dmg, defense]

	var enchants: Array = enemy_data.get("enchantments", [])
	if enchants.size() > 0:
		sb += "\nEnchantments:\n"
		for e in enchants:
			if not (e is Dictionary):
				continue
			var ename := String(e.get("name", e.get("id", "?")))
			var tier := int(e.get("tier", 1))
			var value := int(e.get("value", 0))
			sb += "- %s (T%d, %d)\n" % [ename, tier, value]

	return sb


func _update_hud_info(text: String) -> void:
	var scene := get_tree().current_scene
	if not scene:
		return

	var hud: Node = scene.get_node_or_null("HUD")
	if hud == null:
		return

	# Sicher über call_deferred aufrufen, damit wir keine Reihenfolgeprobleme bekommen
	# Debug-Ausgabe, damit wir sehen, dass Hover erkannt wird
	# print("EnemyMarker update HUD for:", enemy_data.get("name", "Monster"))
	hud.call_deferred("set_enemy_info", text)


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


func _get_color_hex_for_rarity(rarity: String) -> String:
	var c: Color = _get_color_for_rarity(rarity)
	return "#" + c.to_html(false)


func _input(event: InputEvent) -> void:
	if enemy_data.is_empty():
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not mb.pressed or mb.button_index != MOUSE_BUTTON_LEFT:
		return

	# Prüfen, ob Klick nah genug am Marker war
	var mouse_pos: Vector2 = get_global_mouse_position()
	var dist: float = global_position.distance_to(mouse_pos)
	if dist > CLICK_RADIUS:
		return

	_try_player_attack()
	get_viewport().set_input_as_handled()


func _try_player_attack() -> void:
	var scene := get_tree().current_scene
	if not scene or not scene.has_node("Player"):
		return

	var player := scene.get_node("Player")
	if not player:
		return

	# Abstand prüfen
	var max_range: float = 96.0
	var to_enemy: Vector2 = global_position - player.global_position
	if to_enemy.length() > max_range:
		return

	# Blickrichtung des Spielers berücksichtigen
	var facing_vec: Vector2 = _get_player_facing_vector(player)
	if facing_vec == Vector2.ZERO:
		return

	var dir: Vector2 = to_enemy.normalized()
	var dot: float = dir.dot(facing_vec)
	# nur treffen, wenn grob in Blickrichtung (> ~60° Winkel)
	if dot < 0.5:
		return
	
	var dmg: int = _compute_player_damage_against_enemy(player)
	_apply_damage(dmg)


func _get_player_facing_vector(player) -> Vector2:
	var facing := ""
	if player.has_meta("facing"):
		facing = String(player.get_meta("facing"))
	elif "facing" in player:
		facing = String(player.facing)
	else:
		return Vector2.ZERO
	match facing:
		"up":
			return Vector2.UP
		"down":
			return Vector2.DOWN
		"left":
			return Vector2.LEFT
		"right":
			return Vector2.RIGHT
		_:
			return Vector2.ZERO


func _compute_player_damage_against_enemy(player) -> int:
	# Basiswerte aus Player-Stats lesen, mit Fallbacks
	var base_attack: int = 5
	var crit_chance: float = 0.1
	var crit_multi: float = 1.5
	var armor_pen: float = 0.0

	if "total_stats" in player:
		var ts = player.total_stats
		if ts is Dictionary:
			base_attack = int(ts.get("damage", base_attack))
			armor_pen = float(ts.get("armor_penetration", armor_pen))
			crit_chance = float(ts.get("crit_chance", crit_chance)) / 100.0
			crit_multi = float(ts.get("crit_multiplier", crit_multi))

	var enemy_def: int = int(enemy_data.get("defense", 0))
	var effective_def: float = max(0.0, float(enemy_def) * (1.0 - armor_pen))

	var raw: float = float(base_attack) - effective_def
	if raw < 1.0:
		raw = 1.0

	# kleiner Zufallsfaktor +/-20 %
	var variance: float = _rng_randf_range(0.8, 1.2)
	var dmg: float = raw * variance

	# Kritische Treffer
	if _rng_randf() < crit_chance:
		dmg *= crit_multi

	return max(1, int(round(dmg)))


func _rng_randf() -> float:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randf()


func _rng_randf_range(min_val: float, max_val: float) -> float:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	return rng.randf_range(min_val, max_val)


func _apply_damage(amount: int) -> void:
	var hp: int = int(enemy_data.get("hp", 0))
	var max_hp: int = int(enemy_data.get("max_hp", hp))
	hp = max(hp - amount, 0)
	enemy_data["hp"] = hp
	enemy_data["max_hp"] = max_hp
	queue_redraw()

	# Bei Tod Marker entfernen
	if hp <= 0:
		_on_death()


func _on_death() -> void:
	_update_hud_info("")  # Info ausblenden

	# Gold-Drop mit Zufallschance und Bereich aus gold_min/gold_max
	var gold_min: int = int(enemy_data.get("gold_min", 0))
	var gold_max: int = int(enemy_data.get("gold_max", gold_min))
	var gold: int = 0
	if gold_max > 0 and gold_max >= gold_min and _rng_randf() < 0.5: # 50% Chance auf Gold-Drop
		gold = int(round(_rng_randf_range(float(gold_min), float(gold_max))))

		# Gold-%-Bonus vom Spieler anwenden (z.B. aus Verzauberungen)
		var cur_scene := get_tree().current_scene
		if cur_scene and cur_scene.has_node("Player"):
			var player := cur_scene.get_node("Player")
			if player and "total_stats" in player:
				var ts = player.total_stats
				if ts is Dictionary:
					# Erwartet z.B. einen Eintrag "gold_find" als Prozentwert (5 = +5%)
					var gold_bonus_percent: float = float(ts.get("gold_find", 0.0))
					if gold_bonus_percent != 0.0:
						var factor: float = 1.0 + (gold_bonus_percent / 100.0)
						gold = int(round(float(gold) * factor))

	# Optional: Item-Loot über LootGenerator
	var loot := {}
	var cur_scene2 := get_tree().current_scene
	if cur_scene2 and cur_scene2.has_node("Player"):
		var level: int = int(enemy_data.get("level", 1))
		var LootGeneratorScript := preload("res://core/loot_generator.gd")
		var loot_gen = LootGeneratorScript.new()
		loot = loot_gen.generate_loot(level)

	# Wenn es überhaupt Loot gibt, erzeugen wir Drops auf dem Boden
	if gold > 0 or (loot is Dictionary and not loot.is_empty()):
		print("💰 Loot von ", enemy_data.get("name", "Monster"),
			": Gold=", gold, " | Item=", loot.get("name", "kein Item"))

		# Gold- und Item-Drops separat anzeigen
		if gold > 0:
			_spawn_dropped_loot(gold, {})        # nur Gold
		if loot is Dictionary and not loot.is_empty():
			_spawn_dropped_loot(0, loot)         # nur Item

	queue_free()


## Persistiert Gold und Item-Loot im aktuellen Save-Slot
func _add_loot_to_player_and_inventory(gold: int, loot: Dictionary) -> void:
	# Aktuellen Slot bestimmen – Constants ist als Autoload verfügbar
	var slot_index: int = int(Constants.current_slot_index)
	var save_slots: Array = Constants.SAVE_SLOTS
	if slot_index < 0 or slot_index >= save_slots.size():
		slot_index = 0

	var slot: String = String(save_slots[slot_index])

	# Pfade wie in inventory_scene.gd / equipment_slots.gd
	var save_root: String = Constants.get_save_root()
	var save_path: String = save_root.path_join(slot)
	var player_path: String = Constants.get_player_path(slot)
	var inventory_path: String = save_path.path_join("global_inventory.json")

	# Sicherstellen, dass der Save-Ordner existiert
	var dir = DirAccess.open("user://")
	if dir:
		dir.make_dir_recursive("save/" + slot)

	# --- Player laden und Gold hinzufügen ---
	var player_data: Dictionary = {}
	if FileAccess.file_exists(player_path):
		var p_file = FileAccess.open(player_path, FileAccess.READ)
		if p_file:
			var json_string = p_file.get_as_text()
			p_file.close()
			var json_obj: JSON = JSON.new()
			if json_obj.parse(json_string) == OK and json_obj.data is Dictionary:
				player_data = json_obj.data

	# Gold in player_data.add (oder fallback auf eigenes Feld) addieren
	if gold > 0:
		var current_gold: int = int(player_data.get("gold", 0))
		player_data["gold"] = current_gold + gold

	# Player zurückschreiben, falls wir Daten haben
	if not player_data.is_empty():
		var p_out = FileAccess.open(player_path, FileAccess.WRITE)
		if p_out:
			p_out.store_string(JSON.stringify(player_data, "\t"))
			p_out.close()
			print("💾 Spieler-Loot gespeichert in: ", player_path)

	# --- Inventar laden ---
	var inventory_items: Array = []
	if FileAccess.file_exists(inventory_path):
		var inv_file = FileAccess.open(inventory_path, FileAccess.READ)
		if inv_file:
			var inv_str = inv_file.get_as_text()
			inv_file.close()
			var inv_json: JSON = JSON.new()
			if inv_json.parse(inv_str) == OK and inv_json.data is Array:
				inventory_items = inv_json.data

	# Kapazität anhand des angelegten Backpacks bestimmen
	var capacity: int = _get_inventory_capacity(player_data)
	if capacity > 0 and inventory_items.size() > capacity:
		# Wenn die Liste zu lang ist, kürzen wir nur das Ende,
		# damit die ältesten Einträge (am Anfang) erhalten bleiben.
		while inventory_items.size() > capacity:
			inventory_items.remove_at(inventory_items.size() - 1)

	# Falls global_inventory.json fehlt, erstellen wir es leer
	if inventory_items.is_empty() and not FileAccess.file_exists(inventory_path):
		var inv_new = FileAccess.open(inventory_path, FileAccess.WRITE)
		if inv_new:
			inv_new.store_string(JSON.stringify([], "\t"))
			inv_new.close()

	# Item an die erste mögliche Position schreiben:
	# - zuerst nach leerem Slot innerhalb der Kapazität suchen
	# - wenn keiner frei ist und noch Platz im Array ist, am Ende einfügen
	# - wenn vollständig voll: Loot verwerfen (mit Log)
	if loot is Dictionary and not loot.is_empty():
		var placed := false

		if capacity <= 0:
			capacity = inventory_items.size()

		# 1) Nach leerem Slot suchen ({} oder kein Dictionary)
		var max_slots := capacity
		if inventory_items.size() < max_slots:
			max_slots = inventory_items.size()

		for i in range(max_slots):
			var entry = inventory_items[i]
			if not (entry is Dictionary) or (entry as Dictionary).is_empty():
				inventory_items[i] = loot
				placed = true
				break

		# 2) Falls noch Platz ist, aber das Array kürzer als capacity ist:
		if not placed and inventory_items.size() < capacity:
			# Mit leeren Dictionaries auffüllen, bis wir am Ende ein freies Feld haben
			while inventory_items.size() < capacity - 1:
				inventory_items.append({})
			inventory_items.append(loot)
			placed = true

		# 3) Wenn komplett voll: Loot geht verloren, aber Inventar bleibt stabil
		if not placed:
			print("⚠️ Inventory full, loot not added: ", loot.get("name", loot.get("id", "Item")))

	# Inventar zurückschreiben
	var inv_out = FileAccess.open(inventory_path, FileAccess.WRITE)
	if inv_out:
		inv_out.store_string(JSON.stringify(inventory_items, "\t"))
		inv_out.close()
		print("💾 Loot im globalen Inventar gespeichert: ", inventory_path)


## Ermittelt die maximale Anzahl Inventar-Slots basierend auf dem angelegten Backpack
func _get_inventory_capacity(player_data: Dictionary) -> int:
	# Default-Kapazität, falls nichts gefunden wird
	var default_capacity := 12

	if player_data.is_empty():
		return default_capacity

	var equipped = player_data.get("equipped", {})
	if not (equipped is Dictionary):
		return default_capacity

	var backpack_item = equipped.get("backpack", {})
	if not (backpack_item is Dictionary) or (backpack_item as Dictionary).is_empty():
		return default_capacity

	var backpack_id: String = String(backpack_item.get("id", ""))
	if backpack_id == "":
		return default_capacity

	# Daten aus res://data/backpack.json lesen
	if not FileAccess.file_exists("res://data/backpack.json"):
		return default_capacity

	var file = FileAccess.open("res://data/backpack.json", FileAccess.READ)
	if not file:
		return default_capacity

	var json_text := file.get_as_text()
	file.close()

	var json := JSON.new()
	if json.parse(json_text) != OK:
		return default_capacity

	if not (json.data is Array):
		return default_capacity

	for entry in json.data:
		if not (entry is Dictionary):
			continue
		if String(entry.get("id", "")) == backpack_id:
			return int(entry.get("slot_count", default_capacity))

	return default_capacity


func _spawn_dropped_loot(gold: int, loot: Dictionary) -> void:
	var scene := get_tree().current_scene
	if not scene:
		return

	var drop_script := load(DROPPED_LOOT_PATH)
	if drop_script == null:
		push_warning("DroppedLoot script not found at path: " + DROPPED_LOOT_PATH)
		return

	var drop = drop_script.new()
	# Lootpunkt genau an der Todesposition des Monsters platzieren
	drop.setup_drop(global_position, gold, loot)
	scene.add_child(drop)
