extends Node

## Dev-Settings Manager
## Entspricht game.aw/core/dev_settings.py

var dev_mode: bool = false
var enemy_count: int = 5
var enchantment_min: int = 0
var enchantment_max: int = 0
var monster_level_min: int = 1
var monster_level_max: int = 10
var enemy_magic_count: int = 0
var enemy_epic_count: int = 0

func get_settings() -> Dictionary:
	return {
		"dev_mode": dev_mode,
		"enemy_count": enemy_count,
		"enemy_magic_count": enemy_magic_count,
		"enemy_epic_count": enemy_epic_count,
		"enchantment_min": enchantment_min,
		"enchantment_max": enchantment_max,
		"monster_level_min": monster_level_min,
		"monster_level_max": monster_level_max
	}

func set_settings(settings: Dictionary):
	if settings.has("dev_mode"):
		dev_mode = settings["dev_mode"]
	if settings.has("enemy_count"):
		enemy_count = settings["enemy_count"]
	if settings.has("enemy_magic_count"):
		enemy_magic_count = settings["enemy_magic_count"]
	if settings.has("enemy_epic_count"):
		enemy_epic_count = settings["enemy_epic_count"]
	if settings.has("enchantment_min"):
		enchantment_min = settings["enchantment_min"]
	if settings.has("enchantment_max"):
		enchantment_max = settings["enchantment_max"]
	if settings.has("monster_level_min"):
		monster_level_min = settings["monster_level_min"]
	if settings.has("monster_level_max"):
		monster_level_max = settings["monster_level_max"]

func set_dev_mode(enabled: bool):
	dev_mode = enabled

