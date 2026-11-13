extends RefCounted
# M1 scavenge checks: world pickups through the crosshair, full bag, bag
# upgrade, carry weight, scanner, drop, van extraction/banking, death penalty.

const DT := 1.0 / 60.0
const ItemStack = preload("res://scripts/items/item_stack.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")

static func find(c: Node3D, item_id: String) -> Node3D:
	for id in c.pickups:
		var p: Node3D = c.pickups[id]
		var name: String = p.bag_id if p.bag_id != "" else String(p.definition().id)
		if name == item_id: return p
	return null

# Stand `back` metres from a floor item, facing it, crosshair on it.
static func aim_at(c: Node3D, target: Vector3, from: Vector3) -> void:
	var p: CharacterBody3D = c.player
	p.global_position = from
	p.velocity = Vector3.ZERO
	var flat := Vector2(target.x - from.x, target.z - from.z)
	p.yaw = atan2(-flat.x, -flat.y)
	var eye_y: float = from.y + p.height() - p.EYE_BELOW_TOP
	p.pitch = -atan2(eye_y - (target.y + 0.15), flat.length())
	p.apply_look()

static func press(c: Node3D, keys: Dictionary, key: int) -> void:
	keys[key] = true; c.session.step(DT)
	keys.erase(key); c.session.step(DT)

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.restart()
	await tree.physics_frame
	var keys := {}
	var saved: Callable = s.input.key_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	var bag: RefCounted = s.inventory
	check.call(c.pickups.size() == preload("res://scripts/world/greybox.gd").LOOT.size() and bag.entries.is_empty() and bag.capacity == 4, "run start: every level item on the floor (%d), empty 4-slot bag" % c.pickups.size())
	var start_bank: int = c.career.banked

	# Crosshair + E takes exactly the item looked at; holding E takes one.
	var laptop := find(c, "faculty_laptop")
	aim_at(c, laptop.global_position, Vector3(6.5, 0, 7.5))
	await tree.physics_frame
	check.call(c.target_in_view().target == laptop, "crosshair finds the laptop on the floor")
	keys[KEY_E] = true
	for i in 20: s.step(DT)
	keys.erase(KEY_E); s.step(DT)
	check.call(bag.count("faculty_laptop") == 1 and not c.pickups.has(laptop.pickup_id) and bag.entries.size() == 1, "E takes the laptop once while held")
	await tree.physics_frame

	# Fill the bag (4): analyser, drive, monitor A; monitor B is refused and stays.
	for item in ["signal_analyser", "research_drive", "crt_monitor"]:
		check.call(c.take_pickup(find(c, item)) == "taken", "took %s" % item)
	var mon_b := find(c, "crt_monitor")
	check.call(bag.entries.size() == 4 and c.take_pickup(mon_b) == "rejected:full" and c.pickups.has(mon_b.pickup_id), "full bag: second monitor stays on the floor")
	check.call(c.take_pickup(find(c, "sling")) == "bag" and bag.capacity == 8, "sling raises the bag to 8")
	check.call(c.take_pickup(mon_b) == "taken" and bag.loot_value() == 480, "second monitor fits; carrying PHP 480")

	# Carry weight: 22.7 kg -> factor 0.646: slower walk, no sprint.
	var kg: float = bag.carried_weight()
	check.call(absf(kg - 22.7) < 0.01 and absf(c.carry_factor(kg) - 0.646) < 0.001, "22.7 kg carried, speed factor 0.646")
	c.player.global_position = Vector3(4, 0, 9.5)
	c.player.yaw = 0.0; c.player.pitch = 0.0; c.player.apply_look()
	await tree.physics_frame
	var a: Vector3 = c.player.global_position
	keys[KEY_W] = true; keys[KEY_SHIFT] = true
	for i in 60: s.step(DT)
	keys.erase(KEY_W); keys.erase(KEY_SHIFT)
	var moved := Vector2(c.player.global_position.x - a.x, c.player.global_position.z - a.z).length()
	check.call(not c.player.sprinting and moved > 2.0 and moved <= 3.5 * 0.646 + 0.01, "loaded: Shift does not sprint, walk ~2.26 m/s (%.2f)" % moved)
	check.call(c.carry_factor(3.0) == 1.0 and c.carry_factor(100.0) == 0.5, "carry factor: free under 5 kg, floor 0.5")
	for i in 20: s.step(DT)

	# Drop (X): last entry goes in front, same instance; never through a wall.
	var last: RefCounted = bag.entries.back()
	c.player.global_position = Vector3(2, 0, 0.6)
	c.player.yaw = 0.0; c.player.apply_look() # facing the north wall, 0.5 m away
	await tree.physics_frame
	press(c, keys, KEY_X)
	var dropped: Node3D = null
	for id in c.pickups:
		if c.pickups[id].entry == last: dropped = c.pickups[id]
	check.call(dropped != null and bag.find(last.instance_id) == null, "X drops the last item as a world pickup (same instance)")
	check.call(dropped != null and dropped.global_position.z > 0.1, "drop near a wall stays in the room (z %.2f)" % (dropped.global_position.z if dropped else -1.0))
	await tree.physics_frame
	check.call(c.take_pickup(dropped) == "taken", "dropped item can be picked up again")

	# Extraction: outside the bay holding E does nothing.
	bag.try_add(ItemStack.create("ammo_9mm", 30, s.run).stack)
	c.player.global_position = Vector3(9.5, 0, 3.0)
	c.player.yaw = 0.0; c.player.pitch = 0.0; c.player.apply_look()
	await tree.physics_frame
	keys[KEY_E] = true
	for i in 90: s.step(DT)
	keys.erase(KEY_E); s.step(DT)
	check.call(c.career.banked == start_bank and bag.loot_value() == 480, "holding E outside the bay banks nothing")
	c.player.global_position = Vector3(9.5, 0, 0.8)
	c.player.pitch = deg_to_rad(-80) # look at the floor: nothing under the crosshair
	c.player.apply_look()
	await tree.physics_frame
	check.call(c.in_extraction(c.player.global_position), "player stands in the loading bay")
	keys[KEY_E] = true
	for i in 30: s.step(DT)
	keys.erase(KEY_E); s.step(DT)
	check.call(c.career.banked == start_bank and c.extract_progress == 0.0, "releasing E at 0.5 s resets loading")
	keys[KEY_E] = true
	for i in 61: s.step(DT)
	keys.erase(KEY_E); s.step(DT)
	check.call(c.career.banked == start_bank + 480 and bag.loot_entries().is_empty() and bag.count("ammo_9mm") == 30 and bag.count("faculty_laptop") == 0, "1 s hold banks PHP 480; ammo stays in the bag")
	var banked_once: int = c.career.banked
	keys[KEY_E] = true
	for i in 90: s.step(DT)
	keys.erase(KEY_E); s.step(DT)
	check.call(c.career.banked == banked_once, "nothing left to load: no double banking")

	# Scanner: restart, ping from spawn (4, 7) finds 6 loot items within 12 m:
	# 5 in the classroom/corridor + the office drive (11.7 m); not the lab laptop
	# (12.7 m) and not the sling (no value).
	s.restart()
	await tree.physics_frame
	check.call(c.career.banked == banked_once and c.pickups.size() == preload("res://scripts/world/greybox.gd").LOOT.size(), "restart: money kept, floor items restored")
	var heard: int = c.noise.events.size()
	press(c, keys, KEY_C)
	var total := 0
	for r in c.last_scan: total += r.value
	check.call(c.last_scan.size() == 6 and total == 600 and c.noise.events.size() == heard + 1 and c.noise.events.back().kind == "scan", "C scans 6 items (PHP 600) and makes a noise (%d, %d)" % [c.last_scan.size(), total])
	check.call(c.last_scan[0].distance <= c.last_scan[c.last_scan.size() - 1].distance, "scan results nearest first")
	var before_ready: float = c.scan_ready_at
	press(c, keys, KEY_C)
	check.call(c.scan_ready_at == before_ready and c.notice == "Scanner recharging.", "second scan within 2 s is refused")
	for i in 130: s.step(DT)
	press(c, keys, KEY_C)
	check.call(c.scan_ready_at > before_ready, "scan available again after the cooldown")

	# Death: carried loot is lost and 10% of the bank is fined.
	c.take_pickup(find(c, "faculty_laptop"))
	var bank_before: int = c.career.banked
	c.player.health.apply(DamagePacket.new(95001, "test", "infected", 500, "test"), s.run.time)
	check.call(c.last_death.fine == int(floor(bank_before * 0.1)) and c.last_death.lost_value == 150 and c.career.banked == bank_before - c.last_death.fine, "death: lose the PHP 150 carried, fine PHP %d" % c.last_death.get("fine", -1))
	s.restart()
	await tree.physics_frame
	check.call(s.inventory.entries.is_empty() and c.career.banked == bank_before - c.last_death.fine, "after death: empty bag, fined bank kept")
	s.input.key_source = saved
