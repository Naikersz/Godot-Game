# Item Transfer Rules (Übergaberegeln)

## Overview
All item transfers go through `DragState`, which stores:
- `source_kind`: "world", "inventory", or "equipment"
- `source_id`: slot index (inventory) or slot name (equipment)
- `item_stack`: The item being transferred

## Allowed Transfers

### ✅ Always Allowed
1. **World → Inventory**: Any item from world can go to inventory
2. **Inventory → Inventory**: Items can be moved/stacked within inventory
3. **Equipment → Inventory**: Any equipped item can be unequipped to inventory

### ✅ Conditional (Slot Compatibility Check)
4. **World → Equipment**: Only if `_item_fits_slot(item, slot_name)` returns true
5. **Inventory → Equipment**: Only if `_item_fits_slot(item, slot_name)` returns true
6. **Equipment → Equipment**: Only if:
   - Source item fits target slot: `_item_fits_slot(source_item, target_slot)`
   - Target item (if exists) fits source slot: `_item_fits_slot(target_item, source_slot)`

## Slot Compatibility Rules (`_item_fits_slot`)

Items are checked against `SLOT_MAP`:
- `weapon` → "weapon" slot
- `helmet` → "helmet" slot
- `chest` → "armor" slot
- `pants` → "pants" slot
- `boots` → "boots" slot
- `gloves` → "gloves" slot
- `shield` → "off_hand" slot
- `ring` → "ring1" OR "ring2" (both allowed)
- `weapon` with `off_hand_allowed=true` → "weapon" OR "off_hand"

## Transfer Mechanisms

### 1. Drag & Drop (`slot_drop_data`)
- User drags item and drops on target slot
- Checks `slot_can_drop_data()` first
- Calls `_drop_to_equipment()` or `_drop_to_inventory()`

### 2. Click Transfer (`slot_click_from_world`)
- User clicks on slot while dragging from world
- Same validation as drag & drop
- Used for world → inventory/equipment transfers

### 3. Double-Click Pickup (`_pickup` in DroppedLoot)
- Automatically adds item to inventory via `LootPersistence`
- No drag state involved
- UI updates via `refresh_from_inventory_resource()`

## Swap Behavior

When dropping on an occupied slot:
- **World → Equipment**: Old item goes to DragState (can be dragged further)
- **Inventory → Equipment**: Old item goes to source inventory slot
- **Equipment → Equipment**: Items swap positions (bidirectional check required)
- **World → Inventory**: Old item goes to DragState if slot was occupied

## Stacking Rules

- Stackable items (potions, consumables) can merge in inventory
- `_merge_stack_into_slot_stack()` handles merging logic
- Max stack size from `item_type.max_stack`

## Restrictions

### ❌ Not Allowed
- Items that don't fit slot type (checked by `_item_fits_slot`)
- Equipment-to-equipment swaps where items don't fit bidirectionally
- Dropping non-stackable items on existing stacks

### ⚠️ Special Cases
- **Rings**: Can go to either `ring1` or `ring2`
- **Off-hand weapons**: Can go to `weapon` or `off_hand` if `off_hand_allowed=true`
- **World drops**: Always deleted after successful transfer (even on swap)

## Implementation Notes

- All transfers save data via `_save_data()` after completion
- UI updates via `_update_all_slots()` after transfer
- DragState is cleared after successful transfer (unless swap occurred)
- World loot nodes are always `queue_free()` after transfer

