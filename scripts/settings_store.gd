extends Node
class_name SettingsStore

# Lightweight settings persistence using ConfigFile (settings.cfg in user://)

const CONFIG_PATH := "user://settings.cfg"

var master_volume: float = 80.0
var music_volume: float = 70.0
var fullscreen: bool = false
var resolution_index: int = 0
var loot_always_visible: bool = false
var dev_mode: bool = false
var language: String = "en"  # Language code: "en", "de", "ru"

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	var cfg := ConfigFile.new()
	var err := cfg.load(CONFIG_PATH)
	var is_first_run := (err == ERR_FILE_NOT_FOUND)
	
	if err != OK and err != ERR_FILE_NOT_FOUND:
		print("⚠️ SettingsStore: could not load settings.cfg, err=", err)
		return
	
	# Load settings with defaults (language defaults to "en")
	master_volume = cfg.get_value("audio", "master_volume", master_volume)
	music_volume = cfg.get_value("audio", "music_volume", music_volume)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	resolution_index = cfg.get_value("video", "resolution_index", resolution_index)
	loot_always_visible = cfg.get_value("gameplay", "loot_always_visible", loot_always_visible)
	dev_mode = cfg.get_value("dev", "dev_mode", dev_mode)
	language = cfg.get_value("localization", "language", "en")  # Default to "en" if not set
	
	# Ensure language is valid, fallback to "en" if invalid
	if language != "en" and language != "de" and language != "ru":
		print("⚠️ SettingsStore: Invalid language code '", language, "', defaulting to 'en'")
		language = "en"
	
	# On first run, save default settings (including language="en")
	if is_first_run:
		print("✓ SettingsStore: First run detected, saving default settings (language: en)")
		save_settings()

func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "master_volume", master_volume)
	cfg.set_value("audio", "music_volume", music_volume)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "resolution_index", resolution_index)
	cfg.set_value("gameplay", "loot_always_visible", loot_always_visible)
	cfg.set_value("dev", "dev_mode", dev_mode)
	cfg.set_value("localization", "language", language)
	var err := cfg.save(CONFIG_PATH)
	if err != OK:
		print("⚠️ SettingsStore: could not save settings.cfg, err=", err)

