class_name DragState
extends RefCounted

## Zentrale Drag-Struktur für Welt-/Inventar-/Equipment-Interaktionen.
## Jetzt ItemStack-basiert; Debug-JSON bleibt write-only.

const ItemRegistryRes = preload("res://scripts/item_registry.gd")
const ItemStackRes = preload("res://resources/item_stack.gd")
const ItemRes = preload("res://resources/item.gd")
const ItemTypeRes = preload("res://resources/item_type.gd")

static var active: bool = false
static var item_stack: ItemStack = null   # aktuell "an der Maus" (Resource)
static var source_kind: String = ""       # "world", "inventory", "equipment"
static var source_id: String = ""         # bei inventory: Index, bei equipment: Slotname, bei world: optional
static var source_node: Node = null       # z.B. DroppedLoot-Node oder Panel


static func start(kind: String, id: String, drag_item: Variant, node: Node) -> void:
	# drag_item kann Dictionary (Altbestand) oder ItemStack sein
	var stack := _to_item_stack(drag_item)
	if stack == null:
		clear()
		return

	active = true
	item_stack = stack
	source_kind = kind
	source_id = id
	source_node = node
	# Persistieren (Resource + Debug JSON) über TempLootStore
	var tls := preload("res://core/temp_loot_store.gd")
	tls.save_drag_stack(stack)


static func clear() -> void:
	active = false
	item_stack = null
	source_kind = ""
	source_id = ""
	source_node = null
	# Persistierten Drag-Zustand leeren
	var tls := preload("res://core/temp_loot_store.gd")
	tls.clear_drag()

# Kompatibilität: liefert eine Dictionary-Ansicht für UI/Tooltip
static func get_item_dict() -> Dictionary:
	if item_stack == null:
		return {}
	return _stack_to_dict(item_stack)

# Kompatibilität für bisherigen Code (Dictionary-View)
static func get_item() -> Dictionary:
	return get_item_dict()

static func has_item() -> bool:
	return active and item_stack != null and item_stack.item != null and item_stack.amount > 0

# Hilfsfunktionen
static func _to_item_stack(v: Variant) -> ItemStack:
	if v is ItemStack:
		return v
	if v is Dictionary:
		var st = _stack_from_dict(v)
		return st
	return null

static func _stack_from_dict(item: Dictionary) -> ItemStack:
	if item.is_empty():
		return null
	var id := String(item.get("id", item.get("name", "")))
	if id == "":
		return null
	var itm := ItemRes.new()
	itm.id = id
	itm.name = String(item.get("name", id))
	itm.rarity = String(item.get("rarity", "normal"))
	itm.description = String(item.get("description", ""))
	itm.enchant_slots = int(item.get("enchant_slots", 0))
	itm.item_level = int(item.get("item_level", 1))
	itm.stats = item.get("stats", {})
	itm.enchantments = item.get("enchantments", [])
	itm.requirements = item.get("requirements", {})
	itm.material = item.get("material", {})
	var t := ItemTypeRes.new()
	t.tab_name = String(item.get("item_type", ""))
	t.stackable = bool(item.get("stackable", false))
	t.max_stack = int(item.get("max_stack", (20 if t.stackable else 1)))
	itm.item_type = t
	var st := ItemStackRes.new()
	st.item = itm
	st.amount = int(item.get("amount", 1))
	if item.has("item_level"):
		st.set_meta("item_level", int(item.get("item_level", 0)))
	if item.has("enchantments"):
		st.set_meta("enchantments", item.get("enchantments", []))
	if item.has("position"):
		st.set_meta("position", item.get("position"))
	return st

static func _stack_to_dict(st: ItemStack) -> Dictionary:
	if st == null or st.item == null:
		return {}
	var item_level_meta = st.get_meta("item_level") if st.has_meta("item_level") else st.item.item_level
	var ench_meta = st.get_meta("enchantments") if st.has_meta("enchantments") else st.item.enchantments
	var pos_meta = st.get_meta("position") if st.has_meta("position") else {"drag": 1}
	var material_meta = st.get_meta("material") if st.has_meta("material") else st.item.material if st.item.has_method("get") else {}
	var min_lvl_meta = st.get_meta("min_player_level") if st.has_meta("min_player_level") else 1
	return {
		"id": st.item.id,
		"name": st.item.name,
		"rarity": st.item.rarity,
		"item_type": st.item.item_type.tab_name if st.item.item_type else "",
		"item_level": item_level_meta,
		"description": st.item.description,
		"material": material_meta,
		"min_player_level": min_lvl_meta,
		"amount": st.amount,
		"stackable": st.item.item_type.stackable if st.item.item_type else false,
		"max_stack": st.item.item_type.max_stack if st.item.item_type else 1,
		"stats": st.item.stats,
		"requirements": st.item.requirements if st.item.has_method("get") else {},
		"enchant_slots": st.item.enchant_slots,
		"enchantments": ench_meta,
		"position": pos_meta,
	}

static func _get_registry() -> ItemRegistry:
	if Engine.has_singleton("ItemRegistry"):
		return Engine.get_singleton("ItemRegistry")
	if ItemRegistryRes != null:
		return ItemRegistryRes.new()
	return null
