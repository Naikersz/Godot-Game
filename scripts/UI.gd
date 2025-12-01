extends MarginContainer

var rng := RandomNumberGenerator.new()
@onready var hp_bar := $VBoxContainer/HpBar

func _on_button_pressed() -> void:
	hp_bar.value = rng.randf_range(0.0, 100.0)

func _ready() -> void:
	rng.randomize()
