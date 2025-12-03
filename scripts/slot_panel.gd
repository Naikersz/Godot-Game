extends Panel

## Универсальный слот (ячейка) для экипировки / инвентаря в HUD.
## Весь реальный функционал (какой предмет в слоте, перенос и т.п.)
## реализован в менеджере (`equipment_slots.gd`), сюда только
## пробрасываем события drag & drop.

var slot_id: String = ""        # Идентификатор слота (например "helmet" или индекс инвентаря "0")
var slot_kind: String = ""      # "equipment" или "inventory"
var manager: Node = null        # Узел-менеджер (EquipmentSlots)

var icon_label: Label = null    # Маленький текст по центру слота

const LABEL_SETTINGS := preload("res://art/ui/label_settings.tres")


func _ready() -> void:
	# Разрешаем обработку мыши этим контролом
	mouse_filter = Control.MOUSE_FILTER_PASS

	# Создаём / находим Label для "иконки"
	icon_label = get_node_or_null("IconLabel")
	if icon_label == null:
		# Если внутри слота уже есть TextureRect с фоном,
		# будем рисовать текст поверх него.
		var parent_for_label: Node = self
		for child in get_children():
			if child is TextureRect:
				parent_for_label = child
				break

		icon_label = Label.new()
		icon_label.name = "IconLabel"
		# Растягиваем Label на весь слот/текстуру
		icon_label.anchor_left = 0.0
		icon_label.anchor_top = 0.0
		icon_label.anchor_right = 1.0
		icon_label.anchor_bottom = 1.0
		icon_label.offset_left = 0.0
		icon_label.offset_top = 0.0
		icon_label.offset_right = 0.0
		icon_label.offset_bottom = 0.0
		icon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		icon_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		# Делаем текст хорошо видимым поверх иконки слота
		icon_label.z_index = 10
		icon_label.add_theme_color_override("font_color", Color.WHITE)
		icon_label.add_theme_font_size_override("font_size", 24)
		# Подключаем те же настройки шрифта, что и в остальном UI,
		# чтобы текст гарантированно отображался
		icon_label.label_settings = LABEL_SETTINGS
		parent_for_label.add_child(icon_label)


func _get_drag_data(_position: Vector2) -> Variant:
	if manager == null:
		return null
	if not manager.has_method("slot_get_drag_data"):
		return null
	return manager.slot_get_drag_data(self)


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	if manager == null:
		return false
	if not manager.has_method("slot_can_drop_data"):
		return false
	return manager.slot_can_drop_data(self, data)


func _drop_data(_position: Vector2, data: Variant) -> void:
	if manager == null:
		return
	if not manager.has_method("slot_drop_data"):
		return
	manager.slot_drop_data(self, data)


func _gui_input(event: InputEvent) -> void:
	if manager == null:
		return
	if not manager.has_method("slot_click_from_world"):
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
			manager.slot_click_from_world(self)


func _notification(what: int) -> void:
	# Снятие подсветки, если перетаскивание было отменено (бросили не на слот)
	if what == Control.NOTIFICATION_DRAG_END and manager and manager.has_method("_clear_highlight"):
		manager._clear_highlight()
