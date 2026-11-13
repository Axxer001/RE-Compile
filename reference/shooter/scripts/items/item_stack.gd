extends RefCounted
# One owned stack of a single item definition (per-run, mutable). Identified by
# a stable instance id so inventory/equipment never refer to slot indices.
# Weapons are never stacks; see weapon_instance.gd.

const ItemDefinition = preload("res://scripts/items/item_definition.gd")

var instance_id := ""
var definition: Resource
var quantity := 0

# {ok, stack, error}. Rejects unknown ids, weapons, and quantities outside 1..max_stack.
static func create(item_id: String, amount: int, run: RefCounted) -> Dictionary:
	var def := ItemDefinition.lookup(item_id)
	if def == null: return {"ok": false, "error": "unknown item %s" % item_id}
	if def.category == "weapon": return {"ok": false, "error": "%s is a weapon; use WeaponInstance" % item_id}
	if amount < 1 or amount > def.max_stack: return {"ok": false, "error": "quantity %d outside 1..%d" % [amount, def.max_stack]}
	var stack := new()
	stack.instance_id = run.next_instance_id("stk")
	stack.definition = def
	stack.quantity = amount
	return {"ok": true, "stack": stack}

func space() -> int:
	return definition.max_stack - quantity

# Moves up to `amount` units into this stack; returns how many moved.
func add(amount: int) -> int:
	var moved := clampi(amount, 0, space())
	quantity += moved
	return moved

# Removes up to `amount`; returns how many were removed. Empty stacks are the
# owner's to delete (quantity 0 is never kept in an inventory).
func take(amount: int) -> int:
	var moved := clampi(amount, 0, quantity)
	quantity -= moved
	return moved
