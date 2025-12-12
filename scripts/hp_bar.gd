extends NinePatchRect

const ANIMATION_DURATION := 0.3

@export var min_value: float = 0.0;
@export var max_value: float = 100.0;
@export var value: float = 100.0:
	set = set_value

@onready var texture_rect: TextureRect = $TextureRect
@onready var hp_label: Label = $TextureRect/Label
var progress_shader: ShaderMaterial
var _tween: Tween

func update_texture(direction: int):
	if not progress_shader:
		return
	
	# Правильный расчет: value / max_value для визуального отображения
	# При min_value=0 и max_value=100: 10/100=0.1, 50/100=0.5, 100/100=1.0
	var fill_percent = (value - min_value) / (max_value - min_value)
	
	if (direction < 0):
		# Уменьшение HP - сразу устанавливаем fill_percent БЕЗ анимации для визуального обновления
		progress_shader.set_shader_parameter("fill_percent", fill_percent)
		
		# Принудительно обновляем, чтобы изменения были видны
		texture_rect.queue_redraw()
		
		# Показываем вспышку на краю нового значения
		progress_shader.set_shader_parameter("flash_progress", 0.0)
		var tween = get_tween()
		tween.tween_property(progress_shader, "shader_parameter/flash_progress", 1.0, ANIMATION_DURATION)
		tween.tween_callback(func():
			progress_shader.set_shader_parameter("flash_progress", -1.0)
		)
		
	elif (direction > 0):
		# Увеличение HP - показываем вспышку, затем анимируем fill_percent
		progress_shader.set_shader_parameter("flash_progress", 0.0)
		var tween = get_tween()
		tween.parallel().tween_property(progress_shader, "shader_parameter/fill_percent", fill_percent, ANIMATION_DURATION)
		tween.parallel().tween_property(progress_shader, "shader_parameter/flash_progress", 1.0, ANIMATION_DURATION * 0.5)
		tween.tween_callback(func(): progress_shader.set_shader_parameter("flash_progress", -1.0))
	else:
		# Инициализация - устанавливаем fill_percent сразу, скрываем вспышку
		progress_shader.set_shader_parameter("fill_percent", fill_percent)
		progress_shader.set_shader_parameter("flash_progress", -1.0)
	
func get_tween() -> Tween:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.set_ease(Tween.EASE_OUT)
	return _tween
	
func update_label_text():
	if hp_label:
		hp_label.text = "%d/%d" % [int(value), int(max_value)]

func _ready() -> void:
	# Ждем, пока все @onready переменные будут готовы
	await get_tree().process_frame
	var left   = patch_margin_left
	var right  = patch_margin_right
	var top    = patch_margin_top
	var bottom = patch_margin_bottom
	
	var inner_w = size.x - left - right
	var inner_h = size.y - top - bottom
	
	texture_rect.position = Vector2(left, top)
	texture_rect.size = Vector2(inner_w, inner_h)
	
	# Получаем material из TextureRect
	if texture_rect and texture_rect.material:
		progress_shader = texture_rect.material as ShaderMaterial
		if progress_shader:
			update_texture(0)
		else:
			print("⚠️ Material не является ShaderMaterial в hp_bar!")
	else:
		print("⚠️ TextureRect или material не найден в hp_bar!")
	
	# Обновляем текст Label
	update_label_text()
	
func set_value(new_value: float):
	var diff = new_value - value
	value = clampf(new_value, min_value, max_value)
	if progress_shader:
		update_texture(sign(diff))
	else:
		print("⚠️ progress_shader не найден при установке значения!")
	
	# Обновляем текст Label при изменении значения
	update_label_text()

func _unhandled_input(event: InputEvent) -> void:
	# Тест: Q для уменьшения, E для увеличения HP
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_Q:
			set_value(value - 10.0)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E:
			set_value(value + 10.0)
			get_viewport().set_input_as_handled()
