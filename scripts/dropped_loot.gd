class_name DroppedLoot
extends Area2D

## Repräsentiert einen Loot-Drop (Item + Gold) auf dem Boden.
## Beim Berühren durch den Player wird der Loot ins globale Inventar übernommen.

const LootPersistence := preload("res://scripts/loot_persistence.gd")
const DROP_FONT := preload("res://art/fonts/ThaleahFat.ttf")
const LABEL_FONT_SIZE: int = 14

static var ALL_DROPS: Array = []
static var DRAG_ITEM: Dictionary = {}
static var DRAG_SOURCE: DroppedLoot = null

var gold: int = 0
var item: Dictionary = {}

var label: RichTextLabel
var _item_text: String = ""
var _gold_text: String = ""
var _rarity: String = "normal"
var _label_offset_x: float = 0.0
var _label_offset_y: float = 0.0
var _loot_always_visible: bool = false
var _picked_up: bool = false
var _last_click_time: float = 0.0
const DOUBLE_CLICK_MAX_DELAY: float = 0.3


func _ready() -> void:
	# Damit der Drop über dem Boden gezeichnet wird
	z_index = 100

	# Mausklicks auf dieses Area2D erlauben
	input_pickable = true

	# Kollisionsform für Klick-/Hover-Bereich
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	# Etwas größer, damit auch Klicks auf die Textbox darüber erfasst werden
	circle.radius = 64.0
	shape.shape = circle
	add_child(shape)

	# Label für Item-/Gold-Anzeige (als Kind dieses 2D-Nodes, nicht als UI-Layout)
	_ensure_label()

	connect("body_entered", _on_body_entered)
	connect("input_event", _on_input_event)

	ALL_DROPS.append(self)
	_reflow_all_labels()


func setup_drop(world_pos: Vector2, gold_amount: int, item_dict: Dictionary) -> void:
	# Position wird von enemy_marker (Spawner) bereits passend gestapelt
	global_position = world_pos
	gold = gold_amount
	item = item_dict
	visible = true
	_ensure_label()
	_update_label()
	_reflow_all_labels()


func _exit_tree() -> void:
	ALL_DROPS.erase(self)
	_reflow_all_labels()


func _ensure_label() -> void:
	if label == null:
		label = RichTextLabel.new()
		label.bbcode_enabled = true
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.position = Vector2(0, -20)  # leicht über dem Boden
		label.size = Vector2(200, 24)
		add_child(label)


func _update_label() -> void:
	_item_text = ""
	_gold_text = ""
	_rarity = "normal"
	_label_offset_x = 0.0
	_label_offset_y = 0.0

	if item is Dictionary and not item.is_empty():
		var item_name: String = String(item.get("name", item.get("id", "Item")))
		_rarity = String(item.get("rarity", "normal"))
		_item_text = item_name

	if gold > 0:
		_gold_text = "%d Gold" % gold

	# Label nicht mehr verwenden, Render erfolgt in _draw
	if label:
		label.visible = false

	queue_redraw()
	_reflow_all_labels()


func _draw() -> void:
	# Kleiner Kreis als Loot-Marker (immer sichtbar)
	draw_circle(Vector2.ZERO, 4.0, Color(1.0, 1.0, 0.0, 0.9))

	# Sichtbarkeitslogik:
	# - G (physische Taste) gehalten  -> temporär anzeigen
	# - toggle_loot (z.B. Alt+G, InputMap) toggelt _loot_always_visible
	var show_temp := Input.is_key_pressed(KEY_G)
	var show := _loot_always_visible or show_temp
	if not show:
		return

	var font := DROP_FONT
	if font == null:
		return

	var font_size: int = LABEL_FONT_SIZE
	var line_height := font.get_height(font_size)

	var lines: Array[String] = []
	if _item_text != "":
		lines.append(_item_text)
	if _gold_text != "":
		lines.append(_gold_text)
	if lines.is_empty():
		return

	var max_width: float = 0.0
	for t in lines:
		# Godot 4: get_string_size(text, alignment, width, font_size)
		var w := font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size).x
		if w > max_width:
			max_width = w

	var padding: Vector2 = Vector2(6.0, 4.0)
	var box_size: Vector2 = Vector2(max_width, line_height * lines.size()) + padding * 2.0
	var box_pos := Vector2(-box_size.x * 0.5 + _label_offset_x, -box_size.y - 8.0 + _label_offset_y)

	# Hintergrundbox
	draw_rect(Rect2(box_pos, box_size), Color(0, 0, 0, 0.8), true)
	# Rand
	draw_rect(Rect2(box_pos, box_size), Color(1, 1, 1, 0.8), false, 1.0)

	# Textzeilen (links mit gleichem Innenabstand, dadurch links/rechts symmetrisch)
	var y := box_pos.y + padding.y + line_height

	if _item_text != "":
		var item_color := _get_color_for_rarity(_rarity)
		var x_item := box_pos.x + padding.x
		var baseline_item := y - font.get_descent(font_size)
		draw_string(font, Vector2(x_item, baseline_item), _item_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, item_color)
		y += line_height

	if _gold_text != "":
		var gold_color := Color(1.0, 0.84, 0.0)
		var x_gold := box_pos.x + padding.x
		var baseline_gold := y - font.get_descent(font_size)
		draw_string(font, Vector2(x_gold, baseline_gold), _gold_text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, gold_color)


func _process(_delta: float) -> void:
	# Jede Frame neu zeichnen, damit Tastenzustand (z.B. G gehalten) wirksam wird
	queue_redraw()

	var mouse_pos := get_global_mouse_position()
	# kleiner Radius um den Punkt / Text
	if mouse_pos.distance_to(global_position) > 32.0:
		return

	var tooltip_text := _format_item_tooltip_inventory_style(item)
	if tooltip_text == "":
		return

	var scene := get_tree().current_scene
	if not scene:
		return
	var hud := scene.get_node_or_null("HUD")
	if hud and hud.has_method("set_enemy_info"):
		hud.set_enemy_info(tooltip_text)


func _format_item_tooltip_inventory_style(item_data: Dictionary) -> String:
	if item_data.is_empty():
		return ""

	var base_text := "[b]%s[/b]\n" % item_data.get("name", item_data.get("id", "Unbekannt"))
	base_text += "Level: %s\n" % str(item_data.get("item_level", "?"))
	base_text += "Typ: %s\n" % item_data.get("item_type", "?")

	# Stats des Items
	var stats: Dictionary = item_data.get("stats", {})
	if not stats.is_empty():
		base_text += "\n[b]Stats:[/b]\n"
		for stat_name in stats.keys():
			var value = stats[stat_name]
			if value != 0:
				base_text += "%s: %s\n" % [stat_name.capitalize(), str(value)]

	# Requirements
	var requirements = item_data.get("requirements", {})
	if not requirements.is_empty():
		base_text += "\n[b]Anforderungen:[/b]\n"
		for req_name in requirements.keys():
			var req_val = requirements[req_name]
			if req_val != 0:
				base_text += "%s: %s\n" % [req_name.capitalize(), str(req_val)]

	# Enchantments
	var enchantments = item_data.get("enchantments", [])
	if not enchantments.is_empty():
		base_text += "\n[b]Verzauberungen:[/b]\n"
		for enchant in enchantments:
			if enchant is Dictionary:
				var enchant_name = enchant.get("name", "?")
				var enchant_value = enchant.get("value", 0)
				base_text += "%s: +%s\n" % [enchant_name, str(enchant_value)]

	return base_text


static func _reflow_all_labels() -> void:
	var font := DROP_FONT
	if font == null:
		return

	# Liste aller aktiven Drops sortieren (stabile Reihenfolge)
	var drops: Array = ALL_DROPS.duplicate()
	drops.sort_custom(func(a, b):
		var da := a as DroppedLoot
		var db := b as DroppedLoot
		if da.global_position.y == db.global_position.y:
			return da.global_position.x < db.global_position.x
		return da.global_position.y < db.global_position.y
	)

	var processed: Array = []

	for d in drops:
		if d == null:
			continue

		var drop := d as DroppedLoot

		# Textzeilen für diese Instanz ermitteln
		var text_item: String = drop._item_text
		var text_gold: String = drop._gold_text

		var lines: Array[String] = []
		if text_item != "":
			lines.append(text_item)
		if text_gold != "":
			lines.append(text_gold)
		if lines.is_empty():
			drop._label_offset_y = 0.0
			continue

		var max_width: float = 0.0
		for t in lines:
			# Godot 4: get_string_size(text, alignment, width, font_size)
			var w: float = font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1.0, LABEL_FONT_SIZE).x
			if w > max_width:
				max_width = w

		var line_height: float = font.get_height(LABEL_FONT_SIZE)
		var padding := Vector2(6.0, 4.0)
		var box_size := Vector2(max_width, line_height * lines.size()) + padding * 2.0

		var base_box_pos := Vector2(-box_size.x * 0.5, -box_size.y - 8.0)
		var rect := Rect2(drop.global_position + base_box_pos, box_size)

		# Solange an bestehende Boxen anstößt, weiter nach oben schieben
		var found_overlap := true
		while found_overlap:
			found_overlap = false
			for r in processed:
				if rect.intersects(r):
					found_overlap = true
					rect.position.y = r.position.y - box_size.y - 4.0
					break

		# Offset relativ zur Basisposition speichern
		drop._label_offset_y = rect.position.y - (drop.global_position.y + base_box_pos.y)
		processed.append(rect)


func _on_body_entered(body: Node) -> void:
	if not body:
		return
	# Sehr einfache Erkennung: wir nehmen an, dass der Spieler-Node "Player" heißt.
	if body.name != "Player":
		return

	# Kein Auto-Loot mehr beim Überlaufen: nur Klick/Doppelklick sammelt ein.
	pass


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


func _pickup() -> void:
	if _picked_up:
		return
	_picked_up = true
	LootPersistence.add_loot_to_player_and_inventory(gold, item)
	queue_free()


func _on_input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return

	var now: float = float(Time.get_ticks_msec()) / 1000.0
	if now - _last_click_time <= DOUBLE_CLICK_MAX_DELAY:
		# Doppelklick: Item/Geld einsammeln wie beim drüberlaufen
		_pickup()
	else:
		# Einfachklick: Item als "aus Welt aufgenommen" merken,
		# damit es im Inventar-Slot per Klick platziert werden kann.
		if item is Dictionary and not item.is_empty():
			DRAG_ITEM = item.duplicate(true)
			DRAG_SOURCE = self

	_last_click_time = now
