extends RefCounted
# Per-run bag (ARCHITECTURE §7). Entries are ItemStack / WeaponInstance objects
# addressed by stable instance id, never slot index. Every operation is
# all-or-nothing except stack merges, which report exactly how many units moved.

signal changed
signal equipped(instance_id: String)

const TIERS := [4, 8, 12] # pockets, sling, backpack
const BAG_TIERS := {"sling": 8, "backpack": 12} # bag item id -> slots

var capacity := 4
var entries: Array = [] # ItemStack | WeaponInstance, in pickup order
var equipped_id := ""

func is_weapon(entry: RefCounted) -> bool:
	return "magazine" in entry

func free_slots() -> int:
	return capacity - entries.size()

func find(instance_id: String) -> RefCounted:
	for e in entries:
		if e.instance_id == instance_id: return e
	return null

func equipped_weapon() -> RefCounted:
	return find(equipped_id) if equipped_id != "" else null

# Units of an item across all stacks (weapons count 1 each).
func count(item_id: String) -> int:
	var n := 0
	for e in entries:
		if is_weapon(e):
			if String(e.item.id) == item_id: n += 1
		elif String(e.definition.id) == item_id:
			n += e.quantity
	return n

# {ok, moved, remaining, reason}. Weapons need a free slot. Stacks top up
# existing stacks first; any remainder takes a free slot as the incoming stack
# itself. On a partial move the incoming stack keeps the remainder (the world
# pickup stays with it). The same object is never added twice.
func try_add(entry: RefCounted) -> Dictionary:
	if entry == null or find(entry.instance_id) != null:
		return {"ok": false, "moved": 0, "remaining": 0, "reason": "duplicate"}
	if is_weapon(entry):
		if free_slots() < 1: return {"ok": false, "moved": 0, "remaining": 1, "reason": "full"}
		entries.append(entry)
		changed.emit()
		return {"ok": true, "moved": 1, "remaining": 0, "reason": ""}
	var moved := 0
	for e in entries:
		if entry.quantity == 0: break
		if not is_weapon(e) and e.definition == entry.definition:
			moved += e.add(entry.take(e.space()))
	if entry.quantity > 0 and free_slots() > 0:
		moved += entry.quantity
		entries.append(entry)
		if moved > 0: changed.emit()
		return {"ok": true, "moved": moved, "remaining": 0, "reason": ""}
	if moved > 0: changed.emit()
	return {"ok": entry.quantity == 0, "moved": moved, "remaining": entry.quantity, "reason": "" if entry.quantity == 0 else "full"}

# Weapons only. Returns false (no change) for unknown ids or stacks.
func equip(instance_id: String) -> bool:
	var e := find(instance_id)
	if e == null or not is_weapon(e): return false
	if equipped_id != instance_id:
		equipped_id = instance_id
		equipped.emit(instance_id)
	return true

func unequip() -> void:
	if equipped_id == "": return
	equipped_id = ""
	equipped.emit("")

# Drop: `spawn_pickup(entry) -> bool` must create the world pickup first;
# ownership is removed only if it succeeded. Dropping the equipped weapon
# unequips it (never shifts equipment onto another slot).
func drop(instance_id: String, spawn_pickup: Callable) -> bool:
	var e := find(instance_id)
	if e == null: return false
	if not spawn_pickup.call(e): return false
	entries.erase(e)
	if equipped_id == instance_id: unequip()
	changed.emit()
	return true

# Read-only view for UI (plain data; the panel never holds entries).
func snapshot() -> Dictionary:
	var out := []
	for e in entries:
		var w := is_weapon(e)
		out.append({"id": e.instance_id, "label": e.item.label if w else e.definition.label,
			"quantity": 1 if w else e.quantity, "weapon": w})
	return {"capacity": capacity, "equipped_id": equipped_id, "entries": out}

# n-th weapon (1-based) in bag order, or "" (slot_1..3 shortcuts).
func weapon_at(n: int) -> String:
	for e in entries:
		if is_weapon(e):
			n -= 1
			if n == 0: return e.instance_id
	return ""

# Removes up to `amount` units of an item across its stacks (smallest first,
# so partial stacks empty out); empty stacks leave the bag. Returns units taken.
func take_units(item_id: String, amount: int) -> int:
	var stacks := entries.filter(func(e): return not is_weapon(e) and String(e.definition.id) == item_id)
	stacks.sort_custom(func(a, b): return a.quantity < b.quantity)
	var taken := 0
	for st in stacks:
		if taken >= amount: break
		taken += st.take(amount - taken)
		if st.quantity == 0: entries.erase(st)
	if taken > 0: changed.emit()
	return taken

static func definition_of(entry: RefCounted) -> Resource:
	return entry.item if "magazine" in entry else entry.definition

# Total carried weight in kg (weapons count 1 each, stacks by quantity).
func carried_weight() -> float:
	var kg := 0.0
	for e in entries:
		kg += definition_of(e).weight_kg * (1 if is_weapon(e) else e.quantity)
	return kg

# Loot entries (category "loot") and their total value in pesos.
func loot_entries() -> Array:
	return entries.filter(func(e): return not is_weapon(e) and e.definition.category == "loot")

func loot_value() -> int:
	var v := 0
	for e in loot_entries(): v += e.definition.value * e.quantity
	return v

# Removes and returns every loot entry (the van takes them); never weapons/ammo.
func unload_loot() -> Array:
	var out := loot_entries()
	for e in out: entries.erase(e)
	if not out.is_empty(): changed.emit()
	return out

# Monotonic: only a larger known tier is accepted, so items are never truncated.
func upgrade_bag(slots: int) -> bool:
	if not slots in TIERS or slots <= capacity: return false
	capacity = slots
	changed.emit()
	return true
