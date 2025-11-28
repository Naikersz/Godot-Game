extends Node

## Konstanten für das Spiel
## Entspricht game.aw/core/constants.py

const WIDTH = 1600
const HEIGHT = 900

const SAVE_SLOTS = ["save1", "save2", "save3"]

## Aktueller Slot-Index (wird beim Laden/Erstellen gesetzt)
var current_slot_index: int = 0

## Aktueller Level-Typ und Nummer (für Battle Scene)
var current_level_type: String = "Feld"
var current_level_number: int = 1

## Gibt den Pfad zum Save-Ordner zurück
func get_save_root() -> String:
	return "user://save"

## Gibt den Pfad zu einem spezifischen Save-Slot zurück
func get_save_path(slot: String) -> String:
	return get_save_root().path_join(slot)

## Gibt den Pfad zur player.json eines Slots zurück
func get_player_path(slot: String) -> String:
	return get_save_path(slot).path_join("player.json")

