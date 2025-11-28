extends Control

## Options Scene
## Entspricht game.aw/scenes/options_scene.py

@onready var title_label: Label = $VBoxContainer/TitleLabel
@onready var info_label: Label = $VBoxContainer/InfoLabel
@onready var dev_button: Button = $VBoxContainer/ButtonContainer/DevButton
@onready var back_button: Button = $VBoxContainer/ButtonContainer/BackButton

func _ready():
	update_dev_button_text()
	if dev_button:
		dev_button.pressed.connect(_on_dev_button_pressed)
	if back_button:
		back_button.pressed.connect(_on_back_button_pressed)
	else:
		print("⚠️ BackButton nicht gefunden in Options!")

func update_dev_button_text():
	var mode_text = "AN" if DevSettings.dev_mode else "AUS"
	dev_button.text = "Dev-Modus: %s" % mode_text

func _on_dev_button_pressed():
	DevSettings.set_dev_mode(not DevSettings.dev_mode)
	update_dev_button_text()
	print("Dev-Modus ist jetzt: %s" % DevSettings.dev_mode)

func _on_back_button_pressed():
	print("Zurück-Button gedrückt (Options)")
	get_tree().call_deferred("change_scene_to_file", "res://scenes/main_menu.tscn")
