extends RefCounted
# M5b roster: the Tracer (ceiling stalker), the Proctor (follows research,
# locks doors) and Blackout (late-night dark hunter, repelled by the beam).

const DT := 1.0 / 60.0
const Tracer = preload("res://scripts/actors/tracer.gd")
const Proctor = preload("res://scripts/actors/proctor.gd")
const Blackout = preload("res://scripts/actors/blackout.gd")
const ItemStack = preload("res://scripts/items/item_stack.gd")
const WeaponInstance = preload("res://scripts/items/weapon_instance.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func place(c: Node3D, at: Vector3, yaw_deg: float) -> void:
	var p: CharacterBody3D = c.player
	p.global_position = at
	p.velocity = Vector3.ZERO
	p.yaw = deg_to_rad(yaw_deg)
	p.pitch = 0.0
	p.apply_look()

# A fresh night with only the enemy under test active.
static func fresh(c: Node3D, tree: SceneTree, keep: String) -> void:
	c.session.restart()
	await tree.physics_frame
	c.enemies["shambler_1"].health.apply(DamagePacket.new(CombatId.next(), "test", "player", 500, "test"), c.session.run.time)
	if keep != "tracer": c.tracer.rest_until = INF
	c.proctor.enabled = keep == "proctor"
	if keep != "proctor":
		c.proctor.position = Vector3(17.6, 0, 1.2) # out of the way and out of play

class CombatId:
	static var n := 99000
	static func next() -> int:
		n += 1
		return n

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	var keys := {}
	var saved_k: Callable = s.input.key_source
	var saved_m: Callable = s.input.mouse_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	s.input.mouse_source = func(b: int) -> bool: return keys.get(b, false)

	# ---- Tracer ------------------------------------------------------------------
	await fresh(c, tree, "tracer")
	var t: CharacterBody3D = c.tracer
	c.proctor.position = Vector3(17.6, 0, 1.2)
	place(c, Vector3(4, 0, 7), 0.0) # under a classroom lamp
	await tree.physics_frame
	check.call(c.lit_at(c.player.global_position) and not t.is_down() and not t.visible, "Tracer starts unseen in the ceiling; the spot is lit")
	steps(c, 3.9)
	check.call(not t.warned_now and not t.is_down(), "3.9 s still: nothing yet")
	steps(c, 0.2)
	check.call(t.warned_now and "scrapes" in c.notice, "4 s still under a light: scraping warning")
	steps(c, 2.0)
	var behind: Vector3 = c.player.global_position + c.player.global_transform.basis.z * 1.5
	check.call(t.is_down() and t.visible and Vector2(t.global_position.x - behind.x, t.global_position.z - behind.z).length() < 0.05, "6 s still: it drops 1.5 m behind the player")
	steps(c, 0.85)
	check.call(t.bites == 1 and c.player.health.hp == 80.0, "it bites once after 0.8 s for 20 HP")
	steps(c, 1.6)
	check.call(not t.is_down() and not t.visible, "then it climbs back into the ducts")
	steps(c, 7.0)
	check.call(not t.is_down() and t.bites == 1, "it rests for 20 s before it can drop again")
	# Moving every few seconds keeps it away; darkness keeps it away.
	await fresh(c, tree, "tracer")
	place(c, Vector3(4, 0, 7), 0.0)
	await tree.physics_frame
	for i in 4:
		steps(c, 3.0)
		keys[KEY_W] = true; steps(c, 0.3); keys.erase(KEY_W)
		place(c, Vector3(4, 0, 7), 0.0)
	check.call(not t.is_down() and not t.warned_now, "moving every 3 s: it never drops")
	c.dark_rooms["classroom_104"] = true
	steps(c, 8.0)
	check.call(not c.lit_at(c.player.global_position) and not t.is_down(), "standing still in the dark: it never drops")
	# Dodge out of reach during the drop's windup; shoot it while it is down.
	await fresh(c, tree, "tracer")
	place(c, Vector3(4, 0, 7), 0.0)
	await tree.physics_frame
	steps(c, 6.05)
	check.call(t.is_down(), "dropped again on a fresh night")
	place(c, Vector3(4, 0, 4.0), 0.0) # 3 m away before the bite lands
	steps(c, 1.0)
	check.call(t.bites == 1 and c.player.health.hp == 100.0, "stepping away before 0.8 s: the bite misses")
	await fresh(c, tree, "tracer")
	place(c, Vector3(4, 0, 7), 180.0) # facing south: the Tracer drops behind (north)... face it after
	await tree.physics_frame
	steps(c, 6.05)
	var pistol: RefCounted = WeaponInstance.create("pistol", s.run).weapon
	s.inventory.try_add(pistol)
	s.inventory.equip(pistol.instance_id)
	var to_t: Vector3 = t.global_position - c.player.global_position
	c.player.yaw = atan2(-to_t.x, -to_t.z)
	c.player.pitch = -atan2(c.player.eye_position().y - 0.6, Vector2(to_t.x, to_t.z).length())
	c.player.apply_look()
	await tree.physics_frame
	for i in 2:
		keys[MOUSE_BUTTON_LEFT] = true; s.step(DT); keys.erase(MOUSE_BUTTON_LEFT); steps(c, 0.3)
	check.call(t.health.dead and t.state == Tracer.State.DEAD, "two pistol shots kill it while it is down (60 HP)")
	steps(c, 10.0)
	check.call(not t.is_down() and t.state == Tracer.State.DEAD, "a dead Tracer stays dead for the night")

	# ---- Proctor -----------------------------------------------------------------
	await fresh(c, tree, "proctor")
	var pr: CharacterBody3D = c.proctor
	var start: Vector3 = pr.global_position
	steps(c, 4.0)
	check.call(pr.global_position.distance_to(start) > 3.0 and pr.state == Proctor.State.PATROL, "the Proctor walks its patrol route")
	steps(c, 6.0)
	check.call(c.doors["door_lab"].is_open, "it opens the lab door with its keys on patrol")
	# Seen without research: ignored.
	await fresh(c, tree, "proctor")
	place(c, Vector3(9.5, 0, 5.5), 180.0) # in the corridor, ahead of its route
	await tree.physics_frame
	steps(c, 2.0)
	check.call(pr.can_see(c.player, c.clear_line) and pr.state == Proctor.State.PATROL, "seen without research: it ignores the player")
	# Seen with research: follows at a distance and locks the nearest door.
	await fresh(c, tree, "proctor")
	c.doors["door_104_east"].set_open(false)
	s.inventory.try_add(ItemStack.create("research_drive", 1, s.run).stack)
	place(c, Vector3(9.5, 0, 5.2), 180.0)
	await tree.physics_frame
	steps(c, 0.5)
	check.call(pr.state == Proctor.State.FOLLOW, "seen carrying a research drive: it follows")
	var closest := INF
	for i in 180:
		s.step(DT)
		closest = minf(closest, Vector2(pr.global_position.x - c.player.global_position.x, pr.global_position.z - c.player.global_position.z).length())
	check.call(closest > 2.6 and c.player.health.hp == 100.0, "it keeps its distance (closest %.2f m) and never harms" % closest)
	var d104: Node3D = c.doors["door_104_east"]
	check.call(d104.locked and not d104.is_open and pr.locks.has(d104), "it locks the door nearest the player")
	place(c, Vector3(8.5, 0, 5.0), 90.0) # corridor side, facing the locked door
	await tree.physics_frame
	keys[KEY_E] = true; s.step(DT); keys.erase(KEY_E); s.step(DT)
	check.call(not d104.is_open and c.notice == "It's locked.", "E on the locked door: it stays shut")
	# Lose it: out of sight for 5 s (inside the lab with the door shut behind).
	c.doors["door_lab"].set_open(false)
	c.doors["door_lab"].locked = false
	place(c, Vector3(16.0, 0, 3.0), 0.0)
	await tree.physics_frame
	steps(c, 5.5)
	check.call(pr.state == Proctor.State.PATROL and not d104.locked and pr.locks.is_empty(), "out of sight for 5 s: back to patrol, doors unlocked")
	check.call(c.combat_targets().all(func(x): return x.id != "proctor"), "the Proctor cannot be targeted by weapons or blasts")

	# ---- Blackout ----------------------------------------------------------------
	await fresh(c, tree, "")
	var b: CharacterBody3D = c.blackout
	s.run.time = c.BLACKOUT_AT - 1.0
	steps(c, 0.5)
	check.call(b.state == Blackout.State.DORMANT and c.dark_rooms.is_empty() and c.lit_at(Vector3(9.5, 0, 2.5)), "before 9 minutes: lights on, Blackout dormant")
	steps(c, 0.6)
	check.call(c.dark_rooms.has("east_corridor") and not c.lit_at(Vector3(9.5, 0, 2.5)) and b.active() and "failing" in c.notice, "at 9 minutes: the corridor goes dark and Blackout arrives")
	steps(c, 15.0)
	check.call(c.dark_rooms.has("computer_lab") and not c.dark_rooms.has("faculty_office"), "15 s later: the lab goes dark, the office not yet")
	# It will not step into a lit room (the classroom is still lit).
	c.doors["door_104_east"].set_open(true)
	c.nav_dirty = true
	place(c, Vector3(5.0, 0, 5.0), -90.0)
	b.global_position = Vector3(9.5, 0, 5.0)
	await tree.physics_frame
	steps(c, 4.0)
	check.call(b.global_position.x > 7.8 and c.player.health.hp == 100.0, "it stops at the lit classroom's door (x %.2f)" % b.global_position.x)
	# All dark: it closes and strikes; the beam drives it back.
	s.run.time = c.BLACKOUT_AT + 60.0
	steps(c, 0.1)
	check.call(c.dark_rooms.size() == 4, "every room dark after 45 s")
	b.global_position = Vector3(9.5, 0, 1.5)
	place(c, Vector3(9.5, 0, 6.0), 0.0) # corridor, facing it, flashlight off
	c.player.flashlight.visible = false
	await tree.physics_frame
	steps(c, 2.5)
	check.call(b.strikes >= 1 and c.player.health.hp <= 65.0, "in the dark with no light: it reaches the player and strikes for 35 (hp %.0f)" % c.player.health.hp)
	c.player.health.reset()
	b.state = Blackout.State.HUNT
	b.global_position = Vector3(9.5, 0, 1.5)
	place(c, Vector3(9.5, 0, 6.0), 0.0)
	c.player.pitch = deg_to_rad(-8.0)
	c.player.apply_look()
	c.player.flashlight.visible = true
	await tree.physics_frame
	var gap0: float = b.global_position.distance_to(c.player.global_position)
	steps(c, 1.0)
	check.call(b.recoils >= 1 and b.global_position.distance_to(c.player.global_position) > gap0 and c.player.health.hp == 100.0, "the flashlight beam on it: it backs away")
	b.health.apply(DamagePacket.new(CombatId.next(), "player", "player", 150.0, "bullet"), s.run.time)
	check.call(b.state == Blackout.State.DEAD and not b.active(), "150 HP of damage drives it off for good")
	s.restart()
	await tree.physics_frame
	check.call(c.dark_rooms.is_empty() and b.state == Blackout.State.DORMANT and c.lit_at(Vector3(9.5, 0, 2.5)) and not c.doors["door_104_east"].locked, "a new night: lights back, Blackout dormant, doors unlocked")

	c.proctor.enabled = true
	s.input.key_source = saved_k
	s.input.mouse_source = saved_m
	s.restart()
	await tree.physics_frame
