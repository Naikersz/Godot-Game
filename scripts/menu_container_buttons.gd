extends VBoxContainer  # or whatever type you have for MenuContainer

func _ready():
	for child in get_children():
		if child is Button:
			# Set fixed size
			child.custom_minimum_size = Vector2(384, 96)
			# Prevent size changes
			child.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			child.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			# Clip text if it doesn't fit
			child.clip_text = true
var ls := LabelSettings.new()
func shadow():
	ls.shadow_enabled = true
	ls.shadow_color = Color(0, 0, 0, 0.5)
	ls.shadow_offset = Vector2(1, 1)
