class_name DragState
extends RefCounted

## Zentrale Drag-Struktur für Welt-/Inventar-/Equipment-Interaktionen.
## Ziel: Einheitliches Verhalten für Loot, Inventar und Ausrüstung.

static var active: bool = false
static var item: Dictionary = {}          # aktuell "an der Maus"
static var source_kind: String = ""       # "world", "inventory", "equipment"
static var source_id: String = ""         # bei inventory: Index, bei equipment: Slotname, bei world: optional
static var source_node: Node = null       # z.B. DroppedLoot-Node oder Panel


static func start(kind: String, id: String, drag_item: Dictionary, node: Node) -> void:
	if not (drag_item is Dictionary) or drag_item.is_empty():
		clear()
		return

	active = true
	item = drag_item.duplicate(true)
	source_kind = kind
	source_id = id
	source_node = node


static func clear() -> void:
	active = false
	item = {}
	source_kind = ""
	source_id = ""
	source_node = null


