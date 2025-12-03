extends RefCounted

## Gemeinsame Tooltip-Helfer für Items (Inventar, Dropped Loot, etc.).

static func build_item_tooltip(
	item: Dictionary,
	equipped_items: Dictionary,
	slot_map: Dictionary,
	slot_names: Dictionary = {}
) -> String:
	if item.is_empty():
		return ""

	var base_text := "[b]%s[/b]\n" % item.get("name", item.get("id", "Unbekannt"))
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
		slot_name = slot_map.get(item_type, "")

	if slot_name != "" and equipped_items.has(slot_name):
		var equipped_item = equipped_items.get(slot_name)
		if equipped_item is Dictionary and not (equipped_item as Dictionary).is_empty():
			var eq_stats: Dictionary = (equipped_item as Dictionary).get("stats", {})
			if not eq_stats.is_empty():
				var slot_display: String = slot_names.get(slot_name, slot_name.capitalize())
				base_text += "\n[b]Vergleich mit ausgerüstetem %s:[/b]\n" % slot_display
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
			if enchant is Dictionary:
				var enchant_name = enchant.get("name", "?")
				var enchant_value = enchant.get("value", 0)
				base_text += "%s: +%s\n" % [enchant_name, str(enchant_value)]

	return base_text
