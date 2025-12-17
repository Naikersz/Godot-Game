extends Panel

## Universal slot (cell) for equipment / inventory in HUD.
## All real functionality (which item is in slot, transfer, etc.)
## is implemented in the manager (`equipment_slots.gd`), here we only
## forward drag & drop events.

var slot_id: String = ""        # Slot identifier (e.g. "helmet" or inventory index "0")
var slot_kind: String = ""      # "equipment" or "inventory"
var manager: Node = null        # Manager node (EquipmentSlots)

var icon_label: Label = null    # Small text in center of slot

const LABEL_SETTINGS := preload("res://art/ui/label_settings.tres")
const HOLD_TO_DRAG_DELAY: float = 0.2

var _hold_timer: SceneTreeTimer = null
var _is_mouse_down: bool = false


func _ready() -> void:
	# Allow mouse processing for this control
	mouse_filter = Control.MOUSE_FILTER_PASS
	# Mark so we can easily recognize in HUD later if this is a SlotPanel
	set_meta("is_slot_panel", true)

	# Create / find Label for "icon"
	icon_label = get_node_or_null("IconLabel")
	if icon_label == null:
		# If there's already a TextureRect with background inside the slot,
		# we'll draw text on top of it.
		var parent_for_label: Node = self
		for child in get_children():
			if child is TextureRect:
				parent_for_label = child
				break

		icon_label = Label.new()
		icon_label.name = "IconLabel"
		# Stretch label across entire slot/texture
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
		# Make text well visible on top of slot icon
		icon_label.z_index = 10
		icon_label.add_theme_color_override("font_color", Color.WHITE)
		icon_label.add_theme_font_size_override("font_size", 24)
		# Use same font settings as rest of UI,
		# so text is guaranteed to display
		icon_label.label_settings = LABEL_SETTINGS
		parent_for_label.add_child(icon_label)


func _get_drag_data(_position: Vector2) -> Variant:
	# Godot's Control-based drag is no longer used.
	# All drags go through our own DragState and click-based logic.
	return null


func _can_drop_data(_position: Vector2, data: Variant) -> bool:
	# Godot's Control-based drop is no longer used, so never accept drops here.
	return false


func _drop_data(_position: Vector2, data: Variant) -> void:
	# No handling of Godot-Control drops anymore.
	return


func _gui_input(event: InputEvent) -> void:
	if manager == null:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Left mouse button: handle full drag & drop flow via our own click-based logic
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_is_mouse_down = true
				# Case 1: there is already an item in DragState → click tries to place it
				if DragState.active and not DragState.get_item().is_empty():
					if manager.has_method("slot_click_from_world"):
						manager.slot_click_from_world(self)
					return

				# Case 2: no DragState yet → prepare potential long-press drag,
				# mirroring the behavior used for world loot.
				if not DragState.active and manager.has_method("slot_get_drag_data"):
					if _hold_timer:
						if _hold_timer.timeout.is_connected(_on_hold_drag_timeout):
							_hold_timer.timeout.disconnect(_on_hold_drag_timeout)
						_hold_timer = null
					_hold_timer = get_tree().create_timer(HOLD_TO_DRAG_DELAY)
					if _hold_timer:
						_hold_timer.timeout.connect(_on_hold_drag_timeout)
			elif not mb.pressed:
				_is_mouse_down = false
				# Mouse released: cancel long-press drag if it has not fired yet
				if _hold_timer:
					if _hold_timer.timeout.is_connected(_on_hold_drag_timeout):
						_hold_timer.timeout.disconnect(_on_hold_drag_timeout)
					_hold_timer = null
		# Middle mouse button for inventory sorting
		elif mb.button_index == MOUSE_BUTTON_MIDDLE and mb.pressed and slot_kind == "inventory":
			if manager.has_method("_handle_inventory_sort"):
				manager._handle_inventory_sort()
				get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	# If a drag ends and was not successfully placed on a slot,
	# items from inventory/equipment should be dropped as world loot if needed.
	if what == Control.NOTIFICATION_DRAG_END and manager:
		if DragState.active and manager.has_method("world_drop_from_inventory"):
			manager.world_drop_from_inventory()


func _on_hold_drag_timeout() -> void:
	# Timer fires only once; clear reference
	_hold_timer = null
	# If mouse is no longer pressed or a drag is already active, do nothing
	if not _is_mouse_down:
		return
	if DragState.active:
		return
	if manager == null or not manager.has_method("slot_get_drag_data"):
		return
	# Long-press was successful: start drag from this slot
	manager.slot_get_drag_data(self)
