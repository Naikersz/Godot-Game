extends Node

## Global game constants
## Mirrors game.aw/core/constants.py

const WIDTH = 1600
const HEIGHT = 900

const SAVE_SLOTS = ["save1", "save2", "save3"]

## Currently selected save slot index (set when loading/creating a save)
var current_slot_index: int = 0

## Current level type and number (used e.g. by the battle / dungeon scenes)
## Start with neutral values so we don't always default to "Forest 1".
var current_level_type: String = ""
var current_level_number: int = 0

## Returns the path to the save root folder
func get_save_root() -> String:
	return "user://save"

## Returns the path to a specific save slot
func get_save_path(slot: String) -> String:
	return get_save_root().path_join(slot)

## Returns the path to the player.json of a slot
func get_player_path(slot: String) -> String:
	return get_save_path(slot).path_join("player.json")

