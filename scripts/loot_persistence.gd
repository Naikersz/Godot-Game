extends RefCounted

## Zentrale Loot-Speicherlogik, die von DroppedLoot / EnemyMarker verwendet werden kann.

static func add_loot_to_player_and_inventory(gold: int, loot: Dictionary) -> void:
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


static func _get_inventory_capacity(player_data: Dictionary) -> int:
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
