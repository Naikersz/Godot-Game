extends ColorRect

func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	size = get_viewport_rect().size
	color = Color(0, 0, 0, 0.6)
