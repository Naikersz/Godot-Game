extends Resource
class_name Item

@export var id: String = ""
@export var name: String = ""
@export var rarity: String = "normal"
@export var description: String = ""
@export var item_type: ItemType
@export var item_level: int = 1
@export var stats: Dictionary = {}
@export var requirements: Dictionary = {}
@export var material: Dictionary = {}
@export var enchant_slots: int = 0
@export var enchantments: Array = []
@export var icon_path: String = ""

