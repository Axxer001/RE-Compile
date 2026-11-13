extends RefCounted
# M4 loop checks: quota cycle maths, the van shop, phone unlocks, both hacking
# terminals (wrong, lockout + alarm, solve), notes, research delivery and
# loss, ending the night, chapter complete, being fired, and overlays.

const DT := 1.0 / 60.0
const Career = preload("res://scripts/core/career.gd")
const Puzzles = preload("res://scripts/world/hack_puzzles.gd")
const InputRouter = preload("res://scripts/core/input_router.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func key(k: int) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = k; e.keycode = k; e.pressed = true
	return e

static func run(check: Callable, c: Node3D) -> void:
	var tree: SceneTree = c.get_tree()

	# ---- career: quota cycle --------------------------------------------------
	var k := Career.new(7)
	check.call(k.quota == 600 and k.night_in_cycle == 1 and k.cycle == 1, "career starts: night 1 of cycle 1, quota PHP 600")
	check.call(k.end_night().result == "next_night" and k.end_night().result == "next_night" and k.night_in_cycle == 3, "nights 1 and 2 roll on without judging the quota")
	k.banked_cycle = 600
	var r: Dictionary = k.end_night()
	check.call(r.result == "next_cycle" and k.cycle == 2 and k.night_in_cycle == 1 and k.quota == 900 and k.banked_cycle == 0, "quota met exactly on night 3: next cycle, quota x1.5 = 900")
	k.end_night(); k.end_night()
	k.banked_cycle = 899
	check.call(k.end_night().result == "fired" and k.fired, "PHP 899 of 900 on the last night: fired")

	# ---- career: shop -----------------------------------------------------------
	k = Career.new(7)
	k.banked = 200
	var b := k.buy("sling")
	check.call(not b.ok and k.banked == 200 and k.start_bag == 4, "not enough money: refused, nothing changes")
	k.banked = 1000
	check.call(k.buy("sling").ok and k.banked == 750 and k.start_bag == 8, "sling bought: PHP 250, nights start with 8 slots")
	check.call(not k.buy("sling").ok and k.banked == 750, "the same item cannot be bought twice")
	check.call(k.buy("backpack").ok and k.start_bag == 12 and k.banked == 250, "backpack upgrades to 12")
	k = Career.new(7)
	k.banked = 2000
	k.buy("backpack")
	check.call(not k.buy("sling").ok and k.start_bag == 12, "a smaller bag is never bought after a bigger one")
	check.call(not k.phone.has("hints") and k.buy("hack_hints").ok and k.phone.has("hints"), "hints bought: phone hints unlocked")
	check.call(not k.buy("nope").ok, "unknown shop item refused")

	# ---- phone ------------------------------------------------------------------
	var ph = k.phone
	var fresh = Career.new(1).phone
	check.call(fresh.has("map") and fresh.has("journal") and not fresh.has("intel") and not fresh.has("hints"), "phone: map and journal from the start; intel and hints locked")
	check.call(fresh.unlock("intel") and not fresh.unlock("intel") and not fresh.unlock("bogus"), "unlocking is once, known tools only")
	check.call(fresh.add_entry("a", "A", "x") and not fresh.add_entry("a", "A", "x") and fresh.journal.size() == 1, "journal entries are unique")

	# ---- puzzles ----------------------------------------------------------------
	check.call(Puzzles.lab_password(1234) == "CCS-2234" and Puzzles.lab_password(1234) == Puzzles.lab_password(1234), "lab password is fixed by the career seed (CCS-2234)")
	var seen := {}
	for sd in [0, 1, 2]: seen[Puzzles.office_puzzle(sd).title] = true
	check.call(seen.size() == 3, "three different office puzzles across seeds")
	for v in Puzzles.OFFICE_VARIANTS:
		check.call(v.options.size() == 3 and v.answer >= 0 and v.answer < 3 and int(v.options[v.answer]) <= v.lines.size(), "puzzle '%s' answer is one of its 3 options" % v.title)

	# ---- in the world --------------------------------------------------------------
	var s = c.session
	c.career = Career.new(1234)
	s.restart()
	await tree.physics_frame
	var keys := {}
	var saved_k: Callable = s.input.key_source
	s.input.key_source = func(kk: int) -> bool: return keys.get(kk, false)
	# Out of play for these checks (the alarm would otherwise bring it); restart revives it.
	c.enemies["shambler_1"].health.apply(DamagePacket.new(97000, "test", "player", 500, "test"), s.run.time)
	c.tracer.rest_until = INF # the Tracer would (rightly) drop on a player idling at a lit terminal
	var lab: Node3D = c.terminals["terminal_lab"]
	var office: Node3D = c.terminals["terminal_office"]
	check.call(lab.kind == "password" and office.kind == "choice" and not lab.solved and not office.solved, "two terminals: lab password, office code puzzle")

	# Crosshair + E opens the lab terminal.
	c.doors["door_lab"].set_open(true)
	c.player.global_position = Vector3(16.6, 0, 1.6)
	c.player.yaw = 0.0
	c.player.pitch = deg_to_rad(-35.0)
	c.player.apply_look()
	await tree.physics_frame
	check.call(c.target_in_view().target == lab, "crosshair finds the lab terminal")
	keys[KEY_E] = true; s.step(DT); keys.erase(KEY_E); s.step(DT)
	check.call(s.input.context == InputRouter.Context.OVERLAY and s.input.overlay == "terminal" and c.terminal_panel.visible, "E opens the terminal overlay")
	var at: Vector3 = c.player.global_position
	keys[KEY_W] = true; steps(c, 0.5); keys.erase(KEY_W)
	check.call(c.player.global_position.distance_to(at) < 0.01, "typing in the terminal never moves the player")

	# Wrong, wrong, lockout with an alarm; locked; then the right password.
	c.terminal_panel.submitted.emit("CCS-0000")
	check.call(lab.attempts == 1 and not lab.solved and "2 attempt" in c.terminal_status, "wrong password: 2 attempts left")
	c.terminal_panel.submitted.emit("guess")
	var before_alarm: int = c.noise.last_id()
	c.terminal_panel.submitted.emit("ccs-9999")
	var alarm: Dictionary = c.noise.events.back() if not c.noise.events.is_empty() else {"kind": "none", "radius": 0.0}
	check.call(lab.locked(s.run.time) and c.noise.last_id() == before_alarm + 1 and alarm.kind == "alarm" and alarm.radius == Puzzles.ALARM_RADIUS, "third wrong answer: 15 s lockout and a 10 m alarm")
	c.terminal_panel.submitted.emit("CCS-2234")
	check.call(not lab.solved and "Locked" in c.terminal_status, "the right password is refused while locked out")
	steps(c, Puzzles.LOCKOUT_S + 0.1)
	c.terminal_panel.submitted.emit(" ccs-2234 ")
	check.call(lab.solved and c.run_research == ["research_lab"] and c.career.phone.has("intel") and not c.career.phone.entry("lab_hacked").is_empty(), "right password (any case, spaces trimmed): research copied, intel unlocked, journal entry (solved %s, research %s, intel %s, ctx %d, status %s)" % [lab.solved, c.run_research, c.career.phone.has("intel"), s.input.context, c.terminal_status])
	check.call(c.career.research.is_empty(), "research is not delivered until it reaches the van")
	s.handle_event(key(KEY_ESCAPE))
	check.call(s.input.context == InputRouter.Context.GAMEPLAY and not c.terminal_panel.visible, "Esc logs out of the terminal")

	# Hints: none until the grading note is read; then the office puzzle shows one.
	c.open_terminal(office)
	check.call(c.terminal_view(office).hint == "", "no hint before the grading note")
	s.handle_event(key(KEY_ESCAPE))
	c.read_note("note_grading")
	check.call(c.career.phone.has("hints") and c.terminal_view(office).hint == office.puzzle.hint, "grading note unlocks hints; the office terminal shows its hint")
	c.read_note("note_whiteboard")
	check.call("CCS-2234" in c.career.phone.entry("note_whiteboard").text, "whiteboard note puts the password in the journal")
	c.open_terminal(office)
	var wrong := (int(office.puzzle.answer) + 1) % 3
	c.terminal_panel.submitted.emit(str(wrong))
	check.call(not office.solved and office.attempts == 1, "office: wrong line refused")
	c.terminal_panel.submitted.emit(str(office.puzzle.answer))
	check.call(office.solved and c.run_research.size() == 2 and not c.career.phone.entry("office_hacked").is_empty(), "office: right line, second research file copied")
	s.handle_event(key(KEY_ESCAPE))

	# Phone: P opens and closes; intel shows loot and the Shambler.
	s.handle_event(key(KEY_P))
	var snap: Dictionary = c.phone_snapshot()
	check.call(s.input.overlay == "phone" and c.phone_panel.visible and snap.intel and snap.loot.size() == c.pickups.size() and snap.enemies.size() == 1 and snap.enemies[0] == c.proctor.global_position, "P opens the phone; intel shows loot and the Proctor, and leaves dead Shamblers off")
	check.call(snap.visited.has("computer_lab"), "the map remembers rooms visited tonight")
	s.handle_event(key(KEY_P))
	check.call(s.input.context == InputRouter.Context.GAMEPLAY and not c.phone_panel.visible, "P again closes the phone")

	# Death before delivery: the research is lost and the terminals reset.
	c.player.health.apply(DamagePacket.new(97001, "test", "infected", 500, "test"), s.run.time)
	check.call(c.last_night.died and c.last_night.lost_research == 2 and c.career.research.is_empty() and c.death_panel.visible, "death before the van: both research files lost")
	c.death_panel.button.pressed.emit()
	await tree.physics_frame
	check.call(c.run_research.is_empty() and not lab.solved and not office.solved and c.career.phone.has("intel"), "next night: terminals locked again, phone unlocks kept")

	# Deliver at the van, then end the night: chapter complete.
	c.terminal_panel.close()
	lab.solved = true; office.solved = true
	c.run_research = ["research_lab", "research_office"]
	c.player.global_position = Vector3(9.5, 0, 0.8)
	c.player.pitch = deg_to_rad(-80.0)
	c.player.apply_look()
	await tree.physics_frame
	keys[KEY_E] = true; steps(c, 1.1); keys.erase(KEY_E); s.step(DT)
	check.call(c.career.has_all_research() and c.run_research.is_empty(), "holding E in the bay delivers the research")
	c.career.banked = 400
	c.open_van()
	check.call(s.input.overlay == "van" and c.van_panel.visible, "van terminal opens")
	c.van_panel.buy_requested.emit("sling")
	check.call(c.career.start_bag == 8 and c.career.banked == 150 and "Bought" in c.van_message, "buying the sling in the van")
	var night_before: int = c.career.nights
	c.van_panel.end_night_requested.emit()
	check.call(c.last_night.chapter and c.career.chapter_complete and c.death_panel.visible and c.death_panel.title.text == "CHAPTER 01 COMPLETE" and s.input.context == InputRouter.Context.EXTRACTION, "ending the night with both files: CHAPTER 01 COMPLETE")
	check.call(c.career.nights == night_before + 1, "ending the night counts a night")
	c.death_panel.button.pressed.emit()
	await tree.physics_frame
	check.call(s.inventory.capacity == 8 and s.input.context == InputRouter.Context.GAMEPLAY, "next night starts with the bought 8-slot bag")

	# Fired: the last night of a cycle under quota; the button starts a new career.
	c.career.night_in_cycle = Career.NIGHTS_PER_CYCLE
	c.career.banked_cycle = 0
	c.open_van()
	c.van_panel.end_night_requested.emit()
	check.call(c.death_panel.title.text == "FIRED" and c.after_panel == "new_career", "under quota on the last night: FIRED")
	c.death_panel.button.pressed.emit()
	await tree.physics_frame
	check.call(c.career.banked == 0 and c.career.nights == 0 and c.career.research.is_empty() and s.inventory.capacity == 4, "a new career starts from zero")

	s.input.key_source = saved_k
	s.restart()
	await tree.physics_frame
