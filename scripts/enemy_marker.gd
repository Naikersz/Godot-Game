extends Node2D

## Simple visual representation of an enemy:
## - Colored dot based on rarity
## - Green HP bar above it
## - Tooltip with all stats on hover (by distance to mouse)

const HOVER_RADIUS: float = 40.0
const CLICK_RADIUS: float = 32.0

const DROPPED_LOOT_PATH := "res://scripts/dropped_loot.gd"

var enemy_data: Dictionary = {}
var tooltip_label: Label


func _ready() -> void:
	set_process(true)

	# Tooltip label above enemy
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

	# Colored dot
	draw_circle(Vector2.ZERO, 6.0, color)

	# HP bar (green) above it
	var hp: int = int(enemy_data.get("hp", 1))
	var max_hp: int = int(enemy_data.get("max_hp", hp))
	if max_hp <= 0:
		max_hp = 1

	var width: float = 24.0
	var height: float = 4.0
	var ratio: float = clamp(float(hp) / float(max_hp), 0.0, 1.0)

	# Background (dark)
	var bg_rect: Rect2 = Rect2(Vector2(-width * 0.5, -14.0), Vector2(width, height))
	draw_rect(bg_rect, Color(0, 0, 0, 0.7), true)

	# Foreground (green)
	var fg_rect: Rect2 = Rect2(
		Vector2(-width * 0.5, -14.0),
		Vector2(width * ratio, height)
	)
	draw_rect(fg_rect, Color(0.0, 1.0, 0.0, 0.9), true)


func _build_stats_text() -> String:
	var sb: String = ""
	var enemy_name: String = String(enemy_data.get("name", tr("Monster")))
	var lvl: int = int(enemy_data.get("level", 1))
	var rarity: String = String(enemy_data.get("rarity", "normal"))
	var hp: int = int(enemy_data.get("hp", 1))
	var max_hp: int = int(enemy_data.get("max_hp", hp))
	var dmg: int = int(enemy_data.get("damage", 0))
	var defense: int = int(enemy_data.get("defense", 0))

	var color_hex: String = _get_color_hex_for_rarity(rarity)
	sb += "[color=%s]%s[/color] (%s %d)\n" % [color_hex, enemy_name, tr("Lvl"), lvl]
	sb += "%s: %s\n" % [tr("Rarity"), rarity.capitalize()]
	sb += "%s: %d / %d\n" % [tr("HP"), hp, max_hp]
	sb += "%s: %d   %s: %d\n" % [tr("DMG"), dmg, tr("DEF"), defense]

	var enchants: Array = enemy_data.get("enchantments", [])
	if enchants.size() > 0:
		sb += "\n%s:\n" % tr("Enchantments")
		for e in enchants:
			if not (e is Dictionary):
				continue
			var ename := String(e.get("name", e.get("id", "?")))
			var tier := int(e.get("tier", 1))
			var value := int(e.get("value", 0))
			sb += "- %s (%s%d, %d)\n" % [ename, tr("T"), tier, value]

	return sb


func _update_hud_info(text: String) -> void:
	var scene := get_tree().current_scene
	if not scene:
		return

	var hud: Node = scene.get_node_or_null("HUD")
	if hud == null:
		return

	# Safely call via call_deferred to avoid ordering issues
	# Debug output to see that hover is detected
	# print("EnemyMarker update HUD for:", enemy_data.get("name", "Monster"))
	hud.call_deferred("set_enemy_info", text)


func _get_color_for_rarity(rarity: String) -> Color:
	match rarity:
		"normal":
			return Color(1, 1, 1)       # White
		"magic":
			return Color(0.2, 0.4, 1)   # Blue
		"epic":
			return Color(0.7, 0.2, 1)   # Purple
		"legendary":
			return Color(1, 0.9, 0.2)   # Yellow
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

	# Check if click was close enough to marker
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

	# Check distance
	var max_range: float = 96.0
	var to_enemy: Vector2 = global_position - player.global_position
	if to_enemy.length() > max_range:
		return

	# Consider player facing direction
	var facing_vec: Vector2 = _get_player_facing_vector(player)
	if facing_vec == Vector2.ZERO:
		return

	var dir: Vector2 = to_enemy.normalized()
	var dot: float = dir.dot(facing_vec)
	# only hit if roughly in facing direction (> ~60° angle)
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
	# Read base values from player stats, with fallbacks
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

	# small random factor +/-20%
	var variance: float = _rng_randf_range(0.8, 1.2)
	var dmg: float = raw * variance

	# Critical hits
	if _rng_randf() < crit_chance:
		dmg *= crit_multi

	# Dev shortcut: One-hit kill if enabled
	if Engine.has_singleton("DevSettings") and Engine.get_singleton("DevSettings").one_hit_kill:
		var hp_cur := int(enemy_data.get("hp", 0))
		var hp_max := int(enemy_data.get("max_hp", hp_cur))
		return hp_cur + hp_max + 100  # safely above any possible HP

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

	# Remove marker on death
	if hp <= 0:
		_on_death()


func _on_death() -> void:
	_update_hud_info("")  # Hide info

	# Gold drop with random chance and range from gold_min/gold_max
	var gold_min: int = int(enemy_data.get("gold_min", 0))
	var gold_max: int = int(enemy_data.get("gold_max", gold_min))
	var gold: int = 0
	if gold_max > 0 and gold_max >= gold_min and _rng_randf() < 0.5: # 50% chance for gold drop
		gold = int(round(_rng_randf_range(float(gold_min), float(gold_max))))

		# Apply gold % bonus from player (e.g. from enchantments)
		var cur_scene := get_tree().current_scene
		if cur_scene and cur_scene.has_node("Player"):
			var player := cur_scene.get_node("Player")
			if player and "total_stats" in player:
				var ts = player.total_stats
				if ts is Dictionary:
					# Expects e.g. an entry "gold_find" as percentage value (5 = +5%)
					var gold_bonus_percent: float = float(ts.get("gold_find", 0.0))
					if gold_bonus_percent != 0.0:
						var factor: float = 1.0 + (gold_bonus_percent / 100.0)
						gold = int(round(float(gold) * factor))

	# Optional: Item loot via LootGenerator
	var loot := {}
	var cur_scene2 := get_tree().current_scene
	if cur_scene2 and cur_scene2.has_node("Player"):
		var level: int = int(enemy_data.get("level", 1))
		var LootGeneratorScript := preload("res://core/loot_generator.gd")
		var temp_loot_store := preload("res://core/temp_loot_store.gd")
		var loot_gen = LootGeneratorScript.new()
		loot = loot_gen.generate_loot(level)
		if loot is Dictionary and not loot.is_empty():
			var loot_id := temp_loot_store.add_item(loot)
			if loot_id > 0:
				loot["position"] = {"loot": loot_id}

	# If there's any loot, create drops on the ground
	if gold > 0 or (loot is Dictionary and not loot.is_empty()):
		print("💰 Loot from ", enemy_data.get("name", "Monster"),
			": Gold=", gold, " | Item=", loot.get("name", "no item"))

		# Show gold and item drops separately
		if gold > 0:
			_spawn_dropped_loot(gold, {})        # gold only
		if loot is Dictionary and not loot.is_empty():
			_spawn_dropped_loot(0, loot)         # item only

	queue_free()
func _spawn_dropped_loot(gold: int, loot: Dictionary) -> void:
	var scene := get_tree().current_scene
	if not scene:
		return

	var drop_script := load(DROPPED_LOOT_PATH)
	if drop_script == null:
		push_warning("DroppedLoot script not found at path: " + DROPPED_LOOT_PATH)
		return

	var drop = drop_script.new()
	# Place loot point exactly at monster's death position
	var pos := global_position
	drop.setup_drop(pos, gold, loot)
	scene.add_child(drop)
