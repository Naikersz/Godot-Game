# Интеграция сумки в игру

## Архитектура

Создана отдельная сцена **`hud_scene.tscn`** для UI элементов (сумка, HP и т.д.), которую можно использовать во всех игровых сценах.

### Структура файлов:
- `scenes/hud_scene.tscn` - Сцена HUD с кнопкой сумки
- `scripts/hud_scene.gd` - Скрипт для управления HUD
- `art/images/Backpack.png` - Текстура сумки

## Как использовать

### Вариант 1: Добавить HUD в существующую сцену (рекомендуется)

В любой игровой сцене (dungeon_scene, town_scene и т.д.) добавьте HUD как дочерний узел:

```gdscript
# В _ready() функции сцены
func _ready():
    var hud_scene = preload("res://scenes/hud_scene.tscn")
    var hud = hud_scene.instantiate()
    add_child(hud)
```

### Вариант 2: Использовать как autoload (для глобального доступа)

Если нужно, чтобы HUD был доступен везде, добавьте в `project.godot`:

```ini
[autoload]
HUD="*res://scenes/hud_scene.tscn"
```

## Функциональность

### Что уже работает:
1. ✅ Кнопка сумки с иконкой `Backpack.png`
2. ✅ Открытие инвентаря по клику на кнопку
3. ✅ Горячая клавиша `I` для открытия инвентаря
4. ✅ Tooltip "Инвентарь (I)" при наведении

### Что можно добавить:
- Индикатор количества предметов на сумке
- Анимация при наведении
- Звуковой эффект при открытии
- Другие UI элементы (мини-карта, квесты и т.д.)

## Пример интеграции в dungeon_scene

```gdscript
extends Node2D

var hud_instance: CanvasLayer

func _ready():
    # Добавляем HUD
    var hud_scene = preload("res://scenes/hud_scene.tscn")
    hud_instance = hud_scene.instantiate()
    add_child(hud_instance)
```

## Пример интеграции в town_scene

```gdscript
extends Control

var hud_instance: CanvasLayer

func _ready():
    # Добавляем HUD (опционально, так как там уже есть кнопка инвентаря)
    var hud_scene = preload("res://scenes/hud_scene.tscn")
    hud_instance = hud_scene.instantiate()
    add_child(hud_instance)
    
    # Можно скрыть кнопку сумки в HUD, если есть своя кнопка
    if hud_instance:
        hud_instance.set_inventory_button_visible(false)
```

## Настройка горячей клавиши

Горячая клавиша уже настроена в `project.godot`:
- Действие: `ui_inventory`
- Клавиша: `I`

Чтобы изменить клавишу, откройте Project → Project Settings → Input Map и измените `ui_inventory`.

