extends RefCounted
# T16 item definition / instance checks. Called by run_simulation.gd with check().

const ItemDefinition = preload("res://scripts/items/item_definition.gd")
const ItemStack = preload("res://scripts/items/item_stack.gd")
const WeaponInstance = preload("res://scripts/items/weapon_instance.gd")
const WeaponDefinition = preload("res://scripts/items/weapon_definition.gd")
const RunState = preload("res://scripts/core/run_state.gd")

static func exported(res: Resource) -> Dictionary:
	var out := {}
	for p in res.get_property_list():
		if p.usage & PROPERTY_USAGE_STORAGE and p.name != "script": out[p.name] = res.get(p.name)
	return out

static func run(check: Callable, c: Node3D) -> void:
	var run_state := RunState.new()

	# Catalog lookup: shared immutable definitions; unknown ids rejected.
	var bat := ItemDefinition.lookup("baseball_bat")
	check.call(bat != null and bat.weapon != null and bat.weapon.damage_hp == 15.0, "baseball_bat item resolves to its weapon definition")
	check.call(ItemDefinition.lookup("baseball_bat") == bat, "lookups share one definition object")
	for bad in ["", "nope", "../weapons/baseball_bat", "baseball bat", "BASEBALL_BAT"]:
		check.call(ItemDefinition.lookup(bad) == null, "unknown item id '%s' rejected" % bad)
	check.call(not ItemStack.create("nope", 1, run_state).ok and not WeaponInstance.create("nope", run_state).ok, "unknown ids rejected by both factories")
	check.call(not ItemStack.create("baseball_bat", 1, run_state).ok, "weapons cannot be stacks")
	check.call(not WeaponInstance.create("ammo_9mm", run_state).ok, "ammo cannot be a weapon instance")
	for field in ["magazine", "quantity", "instance_id", "owner"]:
		check.call(not (field in bat) and not (field in bat.weapon), "definitions carry no runtime '%s' field" % field)

	# Two identical weapons stay independent; the definition never changes.
	var pistol_def := WeaponDefinition.new()
	pistol_def.id = &"test_pistol"
	pistol_def.category = "ranged"
	pistol_def.magazine_size = 15
	var pistol_item := ItemDefinition.new()
	pistol_item.id = &"test_pistol"
	pistol_item.weapon = pistol_def
	var before := exported(pistol_def)
	var a := WeaponInstance.from_definition(pistol_item, run_state)
	var b := WeaponInstance.from_definition(pistol_item, run_state)
	check.call(a.instance_id != b.instance_id and a.definition == b.definition, "two pistols: distinct ids, one shared definition")
	check.call(a.magazine == 15 and b.magazine == 15, "new weapons start with a full magazine")
	a.magazine -= 4
	check.call(a.magazine == 11 and b.magazine == 15, "firing one pistol leaves the other's magazine alone")
	check.call(exported(pistol_def) == before and pistol_def.magazine_size == 15, "definition unchanged after instance use")
	var bat_before := exported(bat.weapon)
	var bat_w: Dictionary = WeaponInstance.create("baseball_bat", run_state)
	check.call(bat_w.ok and bat_w.weapon.magazine == 0 and not bat_w.weapon.uses_ammo(), "bat instance has no magazine")
	check.call(exported(bat.weapon) == bat_before, "bat definition unchanged")

	# Stacks: bounds, partial transfers, unique ids.
	for amount in [0, -1, 61]:
		check.call(not ItemStack.create("ammo_9mm", amount, run_state).ok, "stack of %d rejected (1..60)" % amount)
	var s: RefCounted = ItemStack.create("ammo_9mm", 50, run_state).stack
	check.call(s.add(25) == 10 and s.quantity == 60, "add reports the 10 units that fit")
	check.call(s.take(70) == 60 and s.quantity == 0, "take reports what was actually removed")
	var ids := {}
	for i in 50:
		ids[WeaponInstance.create("baseball_bat", run_state).weapon.instance_id] = true
		ids[ItemStack.create("ammo_9mm", 1, run_state).stack.instance_id] = true
	check.call(ids.size() == 100, "100 instances, 100 distinct ids (%d)" % ids.size())
	check.call(RunState.new().next_instance_id("wpn") == "wpn_1", "each run starts its own id sequence")

	# Input: router bindings come from the project InputMap; R is reload only.
	var router = c.session.input
	check.call(router.keys.get("reload") == KEY_R and not router.keys.has("restart"), "R bound to reload, no restart action")
	check.call(router.buttons.get("attack") == MOUSE_BUTTON_LEFT and router.buttons.get("aim") == MOUSE_BUTTON_RIGHT and router.keys.get("sprint") == KEY_SHIFT and router.keys.get("jump") == KEY_SPACE and router.keys.get("bullet_time") == KEY_Q, "attack/aim/sprint/jump/bullet time from InputMap (R1b key map: Shift sprints)")
