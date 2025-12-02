extends Node2D

## Einfache visuelle Darstellung eines Gegners:
## - Farbiger Punkt je nach Rarity
## - Grüne HP-Leiste darüber
## - Tooltip mit allen Stats beim Hovern (per Distanz zur Maus)

const HOVER_RADIUS: float = 40.0
const CLICK_RADIUS: float = 32.0

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
		_update_hud_info("")  # Info ausblenden
		queue_free()
