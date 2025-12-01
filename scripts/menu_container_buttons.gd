extends VBoxContainer  # или тот тип, который у тебя у MenuContainer

func _ready():
	for child in get_children():
		if child is Button:
			# Устанавливаем фиксированный размер
			child.custom_minimum_size = Vector2(384, 96)
			# Запрещаем изменение размера
			child.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			child.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			# Обрезаем текст, если он не помещается
			child.clip_text = true
var ls := LabelSettings.new()
func shadow():
	ls.shadow_enabled = true
	ls.shadow_color = Color(0, 0, 0, 0.5)
	ls.shadow_offset = Vector2(1, 1)
