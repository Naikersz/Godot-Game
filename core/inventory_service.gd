extends Node
class_name InventoryService

## Central inventory service:
## - encapsulates stack/move logic for inventory ItemStacks
## - ideally registered as Autoload

const ItemStackRes := preload("res://resources/item_stack.gd")

## === Public API ===

## Attempts to move an ItemStack from src_index to dst_index within the same inventory array.
## - inventory: Array[ItemStack or null]
## - Returns the updated array (for chaining) and modifies it in-place.
static func move_inventory_to_inventory(inventory: Array, src_index: int, dst_index: int) -> Array:
	if src_index == dst_index:
		return inventory
	if src_index < 0 or dst_index < 0:
		return inventory
	if src_index >= inventory.size() or dst_index >= inventory.size():
		return inventory

	var src: ItemStack = inventory[src_index] as ItemStack
	var dst: ItemStack = inventory[dst_index] as ItemStack

	# Nothing to move
	if not (src is ItemStack) or src.item == null or src.amount <= 0:
		return inventory

	# Target slot empty -> direct move
	if dst == null:
		inventory[dst_index] = src
		inventory[src_index] = null
		return inventory

	# Target has item: try merging first
	if _stacks_can_merge(src, dst):
		var leftover := _merge_stack_into(dst, src)
		if leftover == null or leftover.amount <= 0:
			# everything merged, clear source
			inventory[src_index] = null
		else:
			# source keeps remainder
			inventory[src_index] = leftover
		return inventory

	# No merge possible -> swap
	inventory[src_index] = dst
	inventory[dst_index] = src
	return inventory


## Merges all stackable items in an inventory array.
## - Removes empty/invalid entries
## - Returns a new, "cleaned" array of the same length (with nulls at the end).
static func merge_all_stacks(inventory: Array) -> Array:
	var merged: Array = []
	var key_map := {}

	for entry in inventory:
		var st: ItemStack = null
		if entry is ItemStack and entry.item != null and entry.amount > 0:
			st = entry
		if st == null:
			continue
		if _is_stackable(st):
			var key := _stack_key(st)
			if key == "":
				merged.append(st)
				continue
			if not key_map.has(key):
				key_map[key] = []
			key_map[key].append(st)
		else:
			merged.append(st)

	# merge per key
	for key in key_map.keys():
		var list: Array = key_map[key]
		if list.is_empty():
			continue
		var template: ItemStack = list[0]
		var total_amt: int = 0
		for st in list:
			total_amt += st.amount
		var max_stack_val: int = _max_stack(template)
		while total_amt > 0:
			var chunk_amt: int = min(max_stack_val, total_amt)
			var chunk: ItemStack = ItemStackRes.new()
			chunk.item = template.item
			chunk.amount = chunk_amt
			_copy_instance_meta(template, chunk)
			merged.append(chunk)
			total_amt -= chunk_amt

	# maintain capacity
	var capacity := inventory.size()
	var result: Array = []
	for st in merged:
		if result.size() >= capacity:
			break
		result.append(st)
	while result.size() < capacity:
		result.append(null)
	return result


## === Internal Helpers ===

static func _is_stackable(st: ItemStack) -> bool:
	if st == null or st.item == null:
		return false
	if st.item.item_type == null:
		return false
	return st.item.item_type.stackable

static func _max_stack(st: ItemStack) -> int:
	if st == null or st.item == null or st.item.item_type == null:
		return 1
	return max(1, st.item.item_type.max_stack)

static func _stacks_can_merge(a: ItemStack, b: ItemStack) -> bool:
	if a == null or b == null or a.item == null or b.item == null:
		return false
	if a.item != b.item:
		return false
	if not _is_stackable(a) or not _is_stackable(b):
		return false
	return true

## Merges src into dst as far as possible; returns remainder stack (or null).
static func _merge_stack_into(dst: ItemStack, src: ItemStack) -> ItemStack:
	if not _stacks_can_merge(src, dst):
		return src
	var max_s := _max_stack(dst)
	var space: int = max_s - dst.amount
	if space <= 0:
		return src
	var add_amt: int = min(space, src.amount)
	dst.amount += add_amt
	src.amount -= add_amt
	if src.amount <= 0:
		return null
	return src

## Creates a key that describes which stacks can be merged.
static func _stack_key(st: ItemStack) -> String:
	if st == null or st.item == null:
		return ""
	# simple version: only distinguish by Item resource
	return str(st.item.get_instance_id())

## Copies meta data from src to dst (Level, Enchants, etc.).
static func _copy_instance_meta(src: ItemStack, dst: ItemStack) -> void:
	if src == null or dst == null:
		return
	for key in src.get_meta_list():
		dst.set_meta(key, src.get_meta(key))
