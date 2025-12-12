extends Node
class_name InventoryManager

var inventory: InventoryResource = InventoryResource.new()
var registry: ItemRegistry = null

func _ready() -> void:
	if registry == null:
		if Engine.has_singleton("ItemRegistry"):
			registry = Engine.get_singleton("ItemRegistry")
		else:
			registry = ItemRegistry.new()
			add_child(registry)

func add_item_by_id(id: String, amount: int = 1) -> bool:
	if registry == null:
		return false
	var itm = registry.get_item(id)
	if itm == null:
		return false
	inventory.add(itm, amount)
	return true

func add_stack(itm: Item, amount: int) -> void:
	if itm == null:
		return
	inventory.add(itm, amount)

func remove_item_by_id(id: String, amount: int = 1) -> void:
	if registry == null:
		return
	var itm = registry.get_item(id)
	if itm == null:
		return
	inventory.remove(itm, amount)

func merge_stacks() -> void:
	inventory.merge_stacks()

func to_json() -> Array:
	var arr: Array = []
	for st in inventory.items:
		if st is ItemStack and st.item:
			var entry := {
				"id": st.item.id,
				"name": st.item.name,
				"item_type": st.item.item_type.tab_name if st.item.item_type else "",
				"rarity": st.item.rarity,
				"description": st.item.description,
				"enchant_slots": st.item.enchant_slots,
				"amount": st.amount,
				"stackable": st.item.item_type.stackable if st.item.item_type else false,
				"max_stack": st.item.item_type.max_stack if st.item.item_type else 1,
			}
			entry["stats"] = st.item.stats
			arr.append(entry)
		else:
			arr.append({})
	return arr

func from_json(arr: Array) -> void:
	inventory.items.clear()
	for entry in arr:
		if not (entry is Dictionary):
			inventory.items.append({})
			continue
		var id = String(entry.get("id", ""))
		var amount = int(entry.get("amount", 1))
		var itm = registry.get_item(id) if registry else null
		if itm == null:
			# fallback: skip invalid items
			inventory.items.append({})
			continue
		var st := ItemStack.new()
		st.item = itm
		st.amount = max(1, amount)
		inventory.items.append(st)

