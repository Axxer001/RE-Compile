extends RefCounted
# Ported 2D T17 bag rules (world pickups return in M1). Called by run_simulation.gd with check().

const Inventory = preload("res://scripts/items/inventory.gd")
const ItemStack = preload("res://scripts/items/item_stack.gd")
const WeaponInstance = preload("res://scripts/items/weapon_instance.gd")
const RunState = preload("res://scripts/core/run_state.gd")

static func bat(run: RefCounted) -> RefCounted:
	return WeaponInstance.create("baseball_bat", run).weapon

static func ammo(n: int, run: RefCounted) -> RefCounted:
	return ItemStack.create("ammo_9mm", n, run).stack

static func run(check: Callable, c: Node3D) -> void:
	var r := RunState.new()

	# Capacity boundaries per tier: cap-1 and cap fit, cap+1 is refused intact.
	for cap in Inventory.TIERS:
		var inv := Inventory.new()
		if cap > 4: inv.upgrade_bag(8)
		if cap > 8: inv.upgrade_bag(12)
		check.call(inv.capacity == cap, "tier %d reached" % cap)
		var ok := 0
		for i in cap - 1:
			if inv.try_add(bat(r)).ok: ok += 1
		check.call(ok == cap - 1 and inv.free_slots() == 1, "%d of %d slots filled" % [cap - 1, cap])
		check.call(inv.try_add(bat(r)).ok and inv.free_slots() == 0, "slot %d of %d accepted" % [cap, cap])
		var extra := bat(r)
		var res: Dictionary = inv.try_add(extra)
		check.call(not res.ok and res.reason == "full" and inv.entries.size() == cap and inv.find(extra.instance_id) == null, "item %d refused at capacity %d" % [cap + 1, cap])
		var a := ammo(5, r)
		check.call(not inv.try_add(a).ok and a.quantity == 5, "full bag leaves a new stack untouched (cap %d)" % cap)

	# Partial stacks: merge first, remainder takes a slot; full bag keeps remainder.
	var inv := Inventory.new()
	inv.try_add(ammo(50, r))
	var res: Dictionary = inv.try_add(ammo(25, r))
	check.call(res.ok and res.moved == 25 and inv.count("ammo_9mm") == 75 and inv.entries.size() == 2, "50+25 -> 60 + 15 in two slots")
	for i in 2: inv.try_add(bat(r))
	var more := ammo(55, r)
	res = inv.try_add(more)
	check.call(not res.ok and res.moved == 45 and res.remaining == 10 and more.quantity == 10 and inv.count("ammo_9mm") == 120, "full bag: 45 merged, 10 stay on the incoming stack")
	check.call(inv.count("ammo_9mm") + more.quantity == 130, "no units created or lost (130)")
	check.call(not inv.try_add(inv.entries[0]).ok and inv.count("ammo_9mm") == 120, "same entry cannot be added twice")

	# Equip by id; dropping the equipped weapon unequips and never shifts.
	var b1 := bat(r)
	var b2 := bat(r)
	inv = Inventory.new()
	inv.try_add(b1); inv.try_add(b2)
	check.call(inv.equip(b2.instance_id) and inv.equipped_id == b2.instance_id, "equip by instance id")
	check.call(not inv.equip("nope") and inv.equipped_id == b2.instance_id, "unknown id leaves equipment")
	var s := ammo(3, r)
	inv.try_add(s)
	check.call(not inv.equip(s.instance_id), "stacks cannot be equipped")
	var placed := []
	check.call(not inv.drop(b2.instance_id, func(_e) -> bool: return false) and inv.find(b2.instance_id) != null and inv.equipped_id == b2.instance_id, "failed pickup spawn rolls back the drop")
	check.call(inv.drop(b2.instance_id, func(e) -> bool: placed.append(e); return true), "drop equipped weapon")
	check.call(inv.equipped_id == "" and inv.find(b1.instance_id) != null and placed == [b2], "drop unequips; other weapon not equipped; pickup holds the same instance")

	# Bag upgrades are monotonic and never truncate.
	inv = Inventory.new()
	inv.upgrade_bag(12)
	for i in 12: inv.try_add(bat(r))
	for bad in [8, 4, 12, 10, 16, 0]:
		check.call(not inv.upgrade_bag(bad) and inv.capacity == 12 and inv.entries.size() == 12, "bag change to %d rejected, 12 items kept" % bad)
	inv = Inventory.new()
	check.call(inv.upgrade_bag(12) and not inv.upgrade_bag(8), "pockets -> backpack, then sling refused")
