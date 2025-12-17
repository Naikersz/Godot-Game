# Item Transfer Checklist - Systematische Auflistung

## Übergabemöglichkeiten (ohne Doppelklick)

### Gruppe 1: Welt → Inventar/Equipment

#### 1a. Welt → Inventar (leerer Slot)
**Ablauf:**
1. DragState.start("world", "", item_stack, dropped_loot_node)
2. User zieht Item auf Inventar-Slot
3. `slot_drop_data()` wird aufgerufen
4. `_drop_to_inventory()` mit `source_kind="world"`
5. `_merge_stack_into_slot_stack()` prüft Stacking
6. Wenn kein Stack: `inventory_items[target_index] = incoming_stack`
7. `DragState.clear()`
8. `_save_data()` + `_update_all_slots()`
9. World loot node wird `queue_free()`

**Status:** ✅ Sollte funktionieren
**Potenzielle Probleme:** Keine

---

#### 1b. Welt → Inventar (belegter Slot - Swap)
**Ablauf:**
1. DragState.start("world", "", item_stack, dropped_loot_node)
2. User zieht Item auf belegten Inventar-Slot
3. `slot_drop_data()` wird aufgerufen
4. `_drop_to_inventory()` mit `source_kind="world"`
5. `prev_stack_world = inventory_items[target_index]` (altes Item)
6. `_merge_stack_into_slot_stack()` prüft Stacking
7. Wenn kein Stack: `inventory_items[target_index] = leftover_w`
8. **Wenn `prev_stack_world != null`:** 
   - `DragState.start("inventory", str(target_index), prev_stack_world, slot_node2)`
   - Altes Item bleibt im DragState (kann weitergezogen werden)
9. World loot node wird `queue_free()`

**Status:** ⚠️ Zu prüfen - Altes Item geht in DragState
**Potenzielle Probleme:** Altes Item könnte verloren gehen, wenn DragState nicht weiter verwendet wird

---

#### 1c. Welt → Equipment (leerer Slot)
**Ablauf:**
1. DragState.start("world", "", item_stack, dropped_loot_node)
2. User zieht Item auf Equipment-Slot
3. `slot_can_drop_data()` prüft `_item_fits_slot()`
4. `slot_drop_data()` wird aufgerufen
5. `_drop_to_equipment()` mit `source_kind="world"`
6. `equipped_items[target_slot] = incoming_stack`
7. `DragState.clear()`
8. `_save_data()` + `_update_equipment_slots()`
9. World loot node wird `queue_free()`

**Status:** ✅ Sollte funktionieren
**Potenzielle Probleme:** Keine

---

#### 1d. Welt → Equipment (belegter Slot - Swap)
**Ablauf:**
1. DragState.start("world", "", item_stack, dropped_loot_node)
2. User zieht Item auf belegten Equipment-Slot
3. `slot_can_drop_data()` prüft bidirektional (beide Items müssen passen)
4. `slot_drop_data()` wird aufgerufen
5. `_drop_to_equipment()` mit `source_kind="world"`
6. `prev_stack = equipped_items[target_slot]` (altes Item)
7. `equipped_items[target_slot] = incoming_stack`
8. **Wenn `prev_stack != null`:**
   - `DragState.start("equipment", target_slot, prev_stack, slot_node)`
   - Altes Item bleibt im DragState (kann weitergezogen werden)
9. World loot node wird `queue_free()`

**Status:** ⚠️ Zu prüfen - Altes Item geht in DragState
**Potenzielle Probleme:** Altes Item könnte verloren gehen, wenn DragState nicht weiter verwendet wird

---

### Gruppe 2: Inventar → Inventar/Equipment

#### 2a. Inventar → Inventar (leerer Slot - Verschieben)
**Ablauf:**
1. User startet Drag von Inventar-Slot
2. `slot_get_drag_data()` erstellt Dictionary mit `source_kind="inventory"`, `source_id=index`
3. User zieht auf leeren Inventar-Slot
4. `slot_drop_data()` wird aufgerufen
5. `_drop_to_inventory()` mit `source_kind="inventory"`
6. `inv_service.move_inventory_to_inventory()` verschiebt Item
7. `DragState.clear()`
8. `_save_data()` + `_update_inventory_slots()`

**Status:** ✅ Sollte funktionieren
**Potenzielle Probleme:** Keine

---

#### 2b. Inventar → Inventar (belegter Slot - Swap)
**Ablauf:**
1. User startet Drag von Inventar-Slot
2. `slot_get_drag_data()` erstellt Dictionary
3. User zieht auf belegten Inventar-Slot
4. `slot_drop_data()` wird aufgerufen
5. `_drop_to_inventory()` mit `source_kind="inventory"`
6. `inv_service.move_inventory_to_inventory()` handled Swap intern
7. `DragState.clear()`
8. `_save_data()` + `_update_inventory_slots()`

**Status:** ✅ Sollte funktionieren (InventoryService handled Swap)
**Potenzielle Probleme:** Keine

---

#### 2c. Inventar → Inventar (Stacking)
**Ablauf:**
1. User startet Drag von stackablem Item (z.B. Potion)
2. User zieht auf Slot mit gleichem Item
3. `_merge_stack_into_slot_stack()` merged Stacks
4. Wenn komplett gemerged: `leftover = null`, Item verschwindet aus Source
5. Wenn teilweise: `leftover` bleibt im Source-Slot

**Status:** ✅ Sollte funktionieren
**Potenzielle Probleme:** Keine

---

#### 2d. Inventar → Equipment (leerer Slot)
**Ablauf:**
1. User startet Drag von Inventar-Slot
2. `slot_get_drag_data()` erstellt Dictionary
3. User zieht auf leeren Equipment-Slot
4. `slot_can_drop_data()` prüft `_item_fits_slot()`
5. `slot_drop_data()` wird aufgerufen
6. `_drop_to_equipment()` mit `source_kind="inventory"`
7. `equipped_items[target_slot] = incoming_stack`
8. `inventory_items[source_index] = null` (Slot wird geleert)
9. `DragState.clear()`
10. `_save_data()` + `_update_all_slots()`

**Status:** ✅ Sollte funktionieren
**Potenzielle Probleme:** Keine

---

#### 2e. Inventar → Equipment (belegter Slot - Swap)
**Ablauf:**
1. User startet Drag von Inventar-Slot
2. User zieht auf belegten Equipment-Slot
3. `slot_can_drop_data()` prüft bidirektional
4. `slot_drop_data()` wird aufgerufen
5. `_drop_to_equipment()` mit `source_kind="inventory"`
6. `prev_stack2 = equipped_items[target_slot]` (altes Equipment)
7. `equipped_items[target_slot] = incoming_stack`
8. `inventory_items[source_index] = prev_stack2` (altes Equipment ins Inventar)
9. `DragState.clear()`
10. `_save_data()` + `_update_all_slots()`

**Status:** ✅ Sollte funktionieren
**Potenzielle Probleme:** Keine

---

### Gruppe 3: Equipment → Inventar/Equipment

#### 3a. Equipment → Inventar (leerer Slot)
**Ablauf:**
1. User startet Drag von Equipment-Slot
2. `slot_get_drag_data()` erstellt Dictionary mit `source_kind="equipment"`, `source_id=slot_name`
3. User zieht auf leeren Inventar-Slot
4. `slot_drop_data()` wird aufgerufen
5. `_drop_to_inventory()` mit `source_kind="equipment"`
6. `_merge_stack_into_slot_stack()` prüft Stacking
7. Wenn kein Stack: `inventory_items[target_index] = leftover2`
8. `equipped_items[source_id] = null` (Equipment-Slot wird geleert)
9. `DragState.clear()`
10. `_save_data()` + `_update_all_slots()`

**Status:** ✅ Sollte funktionieren
**Potenzielle Probleme:** Keine

---

#### 3b. Equipment → Inventar (belegter Slot - Swap)
**Ablauf:**
1. User startet Drag von Equipment-Slot
2. User zieht auf belegten Inventar-Slot
3. `slot_drop_data()` wird aufgerufen
4. `_drop_to_inventory()` mit `source_kind="equipment"`
5. `prev_stack = inventory_items[target_index]` (altes Inventar-Item)
6. `_merge_stack_into_slot_stack()` prüft Stacking
7. Wenn kein Stack: `inventory_items[target_index] = leftover2`
8. **Swap-Back-Logik:**
   - Wenn `_item_fits_slot_stack(prev_stack, source_id)`: `equipped_items[source_id] = prev_stack`
   - Sonst: `equipped_items[source_id] = null` ⚠️ **ITEM VERLOREN!**
9. `DragState.clear()`
10. `_save_data()` + `_update_all_slots()`

**Status:** ❌ **PROBLEM!** Item wird gelöscht, wenn es nicht ins Equipment passt
**Potenzielle Probleme:** Altes Inventar-Item geht verloren, wenn es nicht in Equipment-Slot passt

---

#### 3c. Equipment → Equipment (Swap)
**Ablauf:**
1. User startet Drag von Equipment-Slot A
2. User zieht auf Equipment-Slot B
3. `slot_can_drop_data()` prüft bidirektional:
   - `_item_fits_slot(source_item, target_slot)`
   - `_item_fits_slot(target_item, source_slot)`
4. `slot_drop_data()` wird aufgerufen
5. `_drop_to_equipment()` mit `source_kind="equipment"`
6. `equipped_items[target_slot] = source_stack`
7. `equipped_items[source_id] = target_stack` (oder null wenn leer)
8. `DragState.clear()`
9. `_save_data()` + `_update_equipment_slots()`

**Status:** ✅ Sollte funktionieren
**Potenzielle Probleme:** Keine (bidirektionaler Check verhindert Probleme)

---

### Gruppe 4: Inventar/Equipment → Welt

#### 4a. Inventar → Welt (Drop on Ground)
**Ablauf:**
1. User startet Drag von Inventar-Slot
2. User zieht Item außerhalb des Inventars
3. `NOTIFICATION_DRAG_END` wird ausgelöst
4. `world_drop_from_inventory()` wird aufgerufen
5. `_clear_slot(source_kind, source_id)` löscht Item aus Inventar
6. `_save_data()` + `_update_all_slots()`
7. `DroppedLoot` wird bei Player-Position erstellt
8. `DragState.clear()`

**Status:** ✅ Sollte funktionieren
**Potenzielle Probleme:** Keine

---

#### 4b. Equipment → Welt (Drop on Ground)
**Ablauf:**
1. User startet Drag von Equipment-Slot
2. User zieht Item außerhalb des Inventars
3. `NOTIFICATION_DRAG_END` wird ausgelöst
4. `world_drop_from_inventory()` wird aufgerufen
5. `_clear_slot(source_kind, source_id)` löscht Item aus Equipment
6. `_save_data()` + `_update_all_slots()`
7. `DroppedLoot` wird bei Player-Position erstellt
8. `DragState.clear()`

**Status:** ✅ Sollte funktionieren
**Potenzielle Probleme:** Keine

---

## Zusammenfassung der Probleme

### ❌ Bekannte Probleme:

1. **3b. Equipment → Inventar (belegter Slot):** 
   - Wenn altes Inventar-Item nicht ins Equipment passt, wird es gelöscht
   - **Fix:** Item sollte zurück ins Inventar oder in DragState

2. **1b/1d. Welt → Inventar/Equipment (Swap):**
   - Altes Item geht in DragState, könnte verloren gehen wenn nicht weiter verwendet
   - **Fix:** Prüfen ob DragState korrekt gehandled wird

### ⚠️ Zu prüfen:

- Alle Swap-Szenarien mit DragState
- Stacking-Logik bei verschiedenen Übergaben
- Bidirektionale Checks bei Equipment-Swaps

