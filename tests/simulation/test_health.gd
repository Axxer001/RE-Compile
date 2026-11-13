extends RefCounted
# Ported 2D T10 health/damage contract checks (player body is 3D now). Called by run_simulation.gd with check().

const DamagePacket = preload("res://scripts/combat/damage_packet.gd")
const Health = preload("res://scripts/combat/health_component.gd")

static func hit(action: int, amount: float, kind := "melee", faction := "infected") -> RefCounted:
	return DamagePacket.new(action, "shambler_1", faction, amount, kind)

static func run(check: Callable, c: Node3D) -> void:
	c.session.restart()
	var h = c.player.health
	check.call(h.hp == 100.0 and h.max_hp == 100.0 and not h.dead, "player starts at 100 HP")
	var log := {"damaged": [], "died": 0}
	var on_damaged := func(_p, applied: float) -> void: log.damaged.append(applied)
	var on_died := func(_p) -> void: log.died += 1
	h.damaged.connect(on_damaged)
	h.died.connect(on_died)

	# Duplicate contacts from one action apply once; a new action applies again.
	check.call(h.apply(hit(1, 10), 0.0) == "applied" and h.hp == 90.0, "first contact applies 10")
	for i in 3:
		check.call(h.apply(hit(1, 10), 0.0) == "duplicate", "repeat contact %d of action 1 deduplicated" % i)
	check.call(h.hp == 90.0, "duplicates leave HP unchanged")
	check.call(h.apply(hit(2, 10), 0.0) == "applied" and h.hp == 80.0, "second action applies")
	var other := Health.new()
	other.faction = "player_ally"
	other.reset()
	check.call(other.apply(hit(1, 10), 0.0) == "applied", "same action id still lands on a different target")
	other.free()

	# Invalid and friendly packets are refused with no side effects.
	var bad := [DamagePacket.new(0, "x", "infected", 5), DamagePacket.new(3, "x", "infected", -5),
		DamagePacket.new(3, "x", "infected", NAN), DamagePacket.new(3, "x", "", 5),
		DamagePacket.new(3, "x", "infected", 5, "laser")]
	for p in bad:
		check.call(h.apply(p, 0.0) == "invalid", "invalid packet refused (action %d, amount %s, faction '%s', kind %s)" % [p.action_id, p.amount, p.source_faction, p.kind])
	check.call(h.apply(hit(3, 5, "melee", "player"), 0.0) == "friendly", "same-faction damage refused")
	check.call(h.hp == 80.0 and log.damaged.size() == 2, "refusals emit nothing and change nothing")
	check.call(h.apply(hit(3, 5), 0.0) == "applied", "refused action id is not burned")

	# Immunity window: declared kinds only, simulation-time bounded.
	h.grant_immunity(1.0, ["melee", "bite"])
	check.call(h.apply(hit(4, 10, "melee"), 0.5) == "immune", "melee blocked inside window")
	check.call(h.apply(hit(5, 10, "bite"), 0.99) == "immune", "bite blocked inside window")
	check.call(h.apply(hit(6, 5, "fire"), 0.5) == "applied", "fire not covered by melee immunity")
	check.call(h.apply(hit(7, 5, "blast"), 0.5) == "applied", "blast not covered by melee immunity")
	check.call(h.apply(hit(4, 10, "melee"), 1.0) == "applied", "same melee action lands once window ends")
	check.call(h.hp == 55.0, "HP after immunity sequence is 55 (%s)" % h.hp)

	# Exactly lethal latches death at 0; overkill is clipped; death emits once.
	check.call(h.apply(hit(8, 54), 2.0) == "applied" and h.hp == 1.0, "54 leaves 1 HP")
	check.call(h.apply(hit(9, 500, "blast"), 2.0) == "lethal", "overkill is lethal")
	check.call(h.hp == 0.0 and h.dead and log.damaged.back() == 1.0, "overkill clipped to remaining 1 HP")
	check.call(log.died == 1, "died emitted once")
	for kind in ["melee", "fire"]:
		check.call(h.apply(hit(10 + kind.length(), 10, kind), 3.0) == "dead", "%s after death rejected" % kind)
	check.call(log.died == 1 and h.hp == 0.0 and not h.accepts_actions(), "no second death; actions rejected")

	# Exactly-zero case on a fresh component.
	var z := Health.new()
	z.reset()
	check.call(z.apply(hit(1, 100), 0.0) == "lethal" and z.dead and z.hp == 0.0, "damage equal to HP is lethal")
	z.free()

	# Restart gives a fresh, living player.
	c.session.restart()
	check.call(h.hp == 100.0 and not h.dead and h.accepts_actions(), "restart restores 100 HP and life")
	check.call(h.apply(hit(1, 10), 0.0) == "applied", "action ids from the previous run do not carry over")
	h.damaged.disconnect(on_damaged)
	h.died.disconnect(on_died)
	c.session.restart()
