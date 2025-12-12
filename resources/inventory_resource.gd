extends Resource
class_name InventoryResource

@export var items: Array = [] # Array[ItemStack]
@export var default_items: Array = [] # Array[ItemStack]

func init_default() -> void:
	items.clear()
	for st in default_items:
		if st is ItemStack:
			var dup := ItemStack.new()
			dup.item = st.item
			dup.amount = st.amount
			items.append(dup)

func add(item: Item, count: int = 1) -> void:
	if item == null or count <= 0:
		return
	for st in items:
		if st is ItemStack and st.item == item and _is_stackable(item):
			var max_s: int = _max_stack(item)
			var space: int = max_s - st.amount
			if space > 0:
				var add_amt: int = min(space, count)
				st.amount += add_amt
				count -= add_amt
				if count <= 0:
					return
	if count > 0:
		var ns := ItemStack.new()
		ns.item = item
		ns.amount = min(count, _max_stack(item))
		items.append(ns)

func remove(item: Item, count: int = 1) -> void:
	if item == null or count <= 0:
		return
	for st in items:
		if st is ItemStack and st.item == item:
			st.amount -= count
			if st.amount <= 0:
				items.erase(st)
			return

func merge_stacks() -> void:
	# Merges only stacks that are truly identical on a per-instance basis
	var map: Dictionary = {}
	for st in items:
		if st is ItemStack and st.item:
			if not _is_stackable(st.item):
				# Non-stackable stay as-is
				if not map.has("__unique__"):
					map["__unique__"] = []
				map["__unique__"].append(st)
				continue
			var key := _stack_key(st)
			if key == "":
				key = st.item.id
			if key == "":
				continue
			if not map.has(key):
				map[key] = []
			map[key].append(st)

	var merged: Array = []
	# Preserve non-stackable / unique keyed items
	if map.has("__unique__"):
		for st in map["__unique__"]:
			merged.append(st)
		map.erase("__unique__")

	for key in map.keys():
		var list: Array = map[key]
		if list.is_empty():
			continue
		var template: ItemStack = list[0]
		var total: int = 0
		for st in list:
			total += st.amount
		var max_s: int = _max_stack(template.item)
		while total > 0:
			var chunk := ItemStack.new()
			chunk.item = template.item
			chunk.amount = min(max_s, total)
			_copy_instance_meta(template, chunk)
			total -= chunk.amount
			merged.append(chunk)
	items = merged

func to_dict_array() -> Array:
	var arr: Array = []
	for st in items:
		if st is ItemStack and st.item:
			var itm: Item = st.item
			if itm.id.strip_edges() == "" and itm.name.strip_edges() == "":
				# Skip placeholder items without identity
				arr.append({})
				continue
			var item_level: int = st.get_meta("item_level") if st.has_meta("item_level") else itm.item_level
			var type_name: String = itm.item_type.tab_name.to_lower() if itm.item_type else ""
			var is_consumable: bool = _is_consumable_type(type_name)
			var ench: Array = [] if is_consumable else (st.get_meta("enchantments") if st.has_meta("enchantments") else itm.enchantments)
			var material: Dictionary = {} if is_consumable else (st.get_meta("material") if st.has_meta("material") else itm.material)
			var min_lvl: int = st.get_meta("min_player_level") if st.has_meta("min_player_level") else 1
			var position: Dictionary = st.get_meta("position") if st.has_meta("position") else {}
			var entry := {
				"id": itm.id,
				"name": itm.name,
				"rarity": itm.rarity,
				"description": itm.description,
				"enchant_slots": itm.enchant_slots,
				"amount": st.amount,
				"stats": itm.stats,
				"stackable": itm.item_type.stackable if itm.item_type else false,
				"max_stack": itm.item_type.max_stack if itm.item_type else 1,
				"item_type": itm.item_type.tab_name if itm.item_type else "",
				"item_level": item_level,
				"enchantments": ench,
				"requirements": itm.requirements,
				"material": material,
				"min_player_level": min_lvl,
				"position": position,
			}
			arr.append(entry)
		else:
			arr.append({})
	return arr

func from_dict_array(arr: Array, registry: ItemRegistry) -> void:
	items.clear()
	for entry in arr:
		if not (entry is Dictionary):
			items.append(null)
			continue
		var id: String = String(entry.get("id", ""))
		if id.strip_edges() == "":
			id = String(entry.get("name", "")).strip_edges()
		if id == "":
			# Ignore placeholder entries with no id/name
			items.append(null)
			continue
		var amount: int = int(entry.get("amount", 1))
		var item_level: int = int(entry.get("item_level", 1))
		var type_name: String = String(entry.get("item_type", "")).to_lower()
		var is_consumable: bool = _is_consumable_type(type_name)
		var ench: Array = [] if is_consumable else entry.get("enchantments", [])
		var reqs: Dictionary = entry.get("requirements", {})
		var material: Dictionary = {} if is_consumable else entry.get("material", {})
		var min_lvl: int = int(entry.get("min_player_level", 1))
		var pos: Variant = entry.get("position", {})
		var itm: Item = null
		if registry:
			itm = registry.get_item(id)
		if itm == null:
			# Build minimal item if not found
			itm = Item.new()
			itm.id = id
			itm.name = String(entry.get("name", id))
			itm.rarity = String(entry.get("rarity", "normal"))
			itm.description = String(entry.get("description", ""))
			itm.enchant_slots = int(entry.get("enchant_slots", 0))
			itm.stats = entry.get("stats", {})
			itm.item_level = item_level
			itm.requirements = reqs
			itm.material = material
			itm.enchantments = ench
			var t := ItemType.new()
			t.tab_name = String(entry.get("item_type", ""))
			t.stackable = bool(entry.get("stackable", false))
			t.max_stack = int(entry.get("max_stack", (20 if t.stackable else 1)))
			itm.item_type = t
		else:
			# Clone instance-level fields so we don't overwrite registry singletons
			itm = itm.duplicate(true)
			itm.item_level = item_level
			itm.requirements = reqs
			itm.material = material
			itm.enchantments = ench
		var st := ItemStack.new()
		st.item = itm
		st.amount = max(1, amount)
		st.set_meta("item_level", item_level)
		st.set_meta("enchantments", ench)
		st.set_meta("material", material)
		st.set_meta("min_player_level", min_lvl)
		if pos != null:
			st.set_meta("position", pos)
		items.append(st)

func _is_stackable(it: Item) -> bool:
	if it == null:
		return false
	if it.item_type and it.item_type.stackable:
		return true
	return false

func _max_stack(it: Item) -> int:
	if it == null:
		return 1
	if it.item_type and it.item_type.stackable:
		return max(1, it.item_type.max_stack)
	return 1

# === Helpers to keep instance-specific data (enchantments, materials, etc.) intact ===
func _stack_key(st: ItemStack) -> String:
	if st == null or st.item == null:
		return ""
	var itm: Item = st.item
	var type_name: String = itm.item_type.tab_name.to_lower() if itm.item_type else ""
	if type_name in ["potion", "consumable", "quest", "quest_item"]:
		return "%s_%s" % [itm.id, type_name]
	var ench: Array = st.get_meta("enchantments") if st.has_meta("enchantments") else itm.enchantments
	var stats: Dictionary = itm.stats
	var reqs: Dictionary = itm.requirements
	var material: Dictionary = st.get_meta("material") if st.has_meta("material") else itm.material
	var lvl: int = st.get_meta("item_level") if st.has_meta("item_level") else itm.item_level
	var min_lvl: int = st.get_meta("min_player_level") if st.has_meta("min_player_level") else 1
	# Use JSON to build a stable key that differentiates enchanted/unique variants
	return "%s|%s|%s|%s|%s|%s|%s" % [
		itm.id,
		JSON.stringify(ench),
		JSON.stringify(stats),
		JSON.stringify(reqs),
		JSON.stringify(material),
		str(lvl),
		str(min_lvl)
	]

func _is_consumable_type(type_name: String) -> bool:
	return type_name in ["potion", "consumable", "quest", "quest_item", "flask"]

func _copy_instance_meta(src: ItemStack, dst: ItemStack) -> void:
	if src == null or dst == null:
		return
	if src.has_meta("item_level"):
		dst.set_meta("item_level", src.get_meta("item_level"))
	if src.has_meta("enchantments"):
		dst.set_meta("enchantments", src.get_meta("enchantments"))
	if src.has_meta("material"):
		dst.set_meta("material", src.get_meta("material"))
	if src.has_meta("min_player_level"):
		dst.set_meta("min_player_level", src.get_meta("min_player_level"))
	if src.has_meta("position"):
		dst.set_meta("position", src.get_meta("position"))
