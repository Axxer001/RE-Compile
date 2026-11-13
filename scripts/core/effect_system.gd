extends RefCounted
# Timed status effects (GDD §3.3). Rules: different effects coexist; re-applying
# the same effect to the same target refreshes its duration, potency unchanged;
# every effect keeps its own timer. Damage-over-time ticks are returned as
# events for the world to turn into DamagePackets (so health dedup still works).

const DEFS := {
	# id: {name, kind (buff/debuff), text (describe() fills {placeholders}),
	#      dps_pct (of the source's Magic Pow at apply time), tick_s}
	# Cultivate, Concuss and Sage Arts are not timed here (stat modifiers and a
	# passive) but share the same descriptions for the Effects tab [R14].
	"Burn": {"name": "Burn", "kind": "debuff", "dps_pct": 0.02, "tick_s": 1.0,
		"text": "Takes {dps} fire damage every second (2% of the caster's Magic Pow)."},
	"Scorched Slow": {"name": "Scorched Slow", "kind": "debuff",
		"text": "Moves {slow}% slower. A new hit refreshes it; it does not stack."},
	"Cultivate": {"name": "Cultivate", "kind": "buff",
		"text": "+{pow}% Magic Pow, +{mastery}% Spell Mastery, +{atk}% Atk Spd."},
	"Concuss": {"name": "Concussed", "kind": "debuff",
		"text": "Mov Spd and Atk Spd -{pct}% (a Blighted Sprite's pounce)."},
	"Sage Arts": {"name": "Sage Arts", "kind": "buff",
		"text": "Out of combat: +{hp}% max HP and +{mp}% max MP every second."},
}

# Plain-words description with live numbers [R14]: `vals` fills the
# {placeholders} (e.g. {"dps": 2.0}); unknown effects describe themselves by name.
static func describe(effect_id: String, vals := {}) -> String:
	var d: Dictionary = DEFS.get(effect_id, {})
	var t: String = d.get("text", effect_id)
	for k in vals: t = t.replace("{%s}" % k, str(vals[k]))
	return t

static func display_name(effect_id: String) -> String:
	return String(DEFS.get(effect_id, {}).get("name", effect_id))

static func kind_of(effect_id: String) -> String:
	return String(DEFS.get(effect_id, {}).get("kind", "debuff"))

var active := {}   # target_id -> {effect_id -> {until, next_tick, source, pow, serial}}
var _serial := 0

# Returns "applied" (new) or "refreshed".
func apply(target_id: String, effect_id: String, duration_s: float, now: float, source := "", magic_pow := 100.0) -> String:
	var per: Dictionary = active.get(target_id, {})
	active[target_id] = per
	if per.has(effect_id):
		var e: Dictionary = per[effect_id]
		# Refresh: never shorten, keep potency and tick phase.
		e.until = maxf(e.until, now + duration_s)
		return "refreshed"
	_serial += 1
	var tick: float = DEFS.get(effect_id, {}).get("tick_s", 1.0)
	per[effect_id] = {"until": now + duration_s, "next_tick": now + tick, "source": source, "pow": magic_pow, "serial": _serial}
	return "applied"

func has(target_id: String, effect_id: String, now: float) -> bool:
	var per: Dictionary = active.get(target_id, {})
	return per.has(effect_id) and now < per[effect_id].until

func remaining(target_id: String, effect_id: String, now: float) -> float:
	return maxf(0.0, active.get(target_id, {}).get(effect_id, {}).get("until", 0.0) - now) if has(target_id, effect_id, now) else 0.0

func clear_target(target_id: String) -> void:
	active.erase(target_id)

# Advances to `now`; returns damage events
#   {target, effect, amount, source, action_id}
# action_id is unique per tick, so HealthComponent applies each tick once.
func tick(now: float) -> Array:
	var out := []
	for target in active.keys():
		var per: Dictionary = active[target]
		for eid in per.keys():
			var e: Dictionary = per[eid]
			var d: Dictionary = DEFS.get(eid, {})
			if d.has("dps_pct"):
				while e.next_tick <= now and e.next_tick <= e.until + 0.0001:
					var amount: float = e.pow * d.dps_pct * d.tick_s
					out.append({"target": target, "effect": eid, "amount": amount, "source": e.source,
						"action_id": "%s#%d@%.3f" % [eid, e.serial, e.next_tick]})
					e.next_tick += d.tick_s
			if now >= e.until: per.erase(eid)
		if per.is_empty(): active.erase(target)
	return out
