extends CanvasLayer

@onready var label: Label = Label.new()

func _ready() -> void:
	# Label konfigurieren (unten mittig)
	label.name = "SceneOverlayLabel"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.position = Vector2(0, 0)
	label.anchor_left = 0.0
	label.anchor_right = 1.0
	label.anchor_top = 1.0
	label.anchor_bottom = 1.0
	label.offset_left = 0.0
	label.offset_right = 0.0
	label.offset_bottom = -10.0
	label.offset_top = -30.0
	label.text = ""
	add_child(label)

	set_layer(100) # weit vorne

func _process(_delta: float) -> void:
	var current = get_tree().current_scene
	if current:
		var scene_name: String = String(current.name)

		# Nur in der Dungeon-Szene (DungeonScene) Level-Infos anzeigen
		if scene_name == "DungeonScene":
			var lt := String(Constants.current_level_type)
			var ln := int(Constants.current_level_number)
			# Nur wenn sinnvolle Werte gesetzt sind, das Level anhängen
			if lt != "" and ln > 0:
				label.text = "Scene: %s  |  %s %d" % [scene_name, lt, ln]
			else:
				label.text = "Scene: %s" % scene_name
		else:
			# In allen anderen Szenen nur den Szenen-Namen anzeigen
			label.text = "Scene: %s" % scene_name
	else:
		label.text = ""
