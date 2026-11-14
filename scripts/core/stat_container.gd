extends RefCounted
# Player stats (GDD §3.2, Tech Spec §1.1). Base + allocated points, then timed
# modifiers (Cultivate etc.) on top. Pure data, headless-testable.

signal changed

const STATS := ["max_hp", "max_mp", "magic_pow", "mov_spd", "atk_spd", "spell_mastery"]
const BASE := {"max_hp": 100.0, "max_mp": 100.0, "magic_pow": 100.0, "mov_spd": 10.0, "atk_spd": 5.0, "spell_mastery": 0.0}
# Max HP / MP / Pow: flat +5 per point or chant [Sir R3, "Flat 5"; was 15 / 10 / 5]; the rest per Tech Spec §1.1.
const PER_POINT := {"max_hp": 5.0, "max_mp": 5.0, "magic_pow": 5.0, "mov_spd": 0.25, "atk_spd": 0.20, "spell_mastery": 0.015}
# A successful Spell Chant adds CHANT_GAIN x TIER_MULT[the chant's tier], separate
# from stat points [Sir R10, replaces the R9 table]; clamped at the hard caps.
const CHANT_GAIN := {"max_hp": 5.0, "max_mp": 5.0, "magic_pow": 5.0, "mov_spd": 0.4, "atk_spd": 0.25, "spell_mastery": 0.015}
const TIER_MULT := {1: 1.0, 2: 1.15, 3: 1.3, 4: 1.5}
const HARD_CAP := {"mov_spd": 22.0, "atk_spd": 12.0, "spell_mastery": 0.65}
const MASTERY_SOFT := 0.45     # past this, each point gives half (S3)
const MASTERY_SOFT_RATE := 0.5

var points := {}         # stat -> allocated points
var chant_points := {}   # stat -> successful chants (refunded as 1 point each on reset [R4])
var chant_gain := {}     # stat -> total flat gain from those chants (tier-dependent [R10])
var unspent := 0
var modifiers: Array = []  # {id, stat, mul, flat, until}
# Gambling Addiction [Sir, 2026-11-14]: while set, no buff of any source lands:
# a modifier that raises a stat is refused (BUFF_BLOCK_EXEMPT excepted) and a
# chant gains nothing.
var buff_block := false
const BUFF_BLOCK_EXEMPT := ["addiction"]
var buffs_refused := 0

func _init() -> void:
	for s in STATS:
		points[s] = 0
		chant_points[s] = 0
		chant_gain[s] = 0.0

# Flat gain from successful chants, added after points [R9].
func chant_bonus(stat: String) -> float:
	return float(chant_gain[stat])

static func gain_for(stat: String, tier: int) -> float:
	return float(CHANT_GAIN[stat]) * float(TIER_MULT.get(tier, 1.0))

# Value from points and chant gains (no buffs), capped.
func base_value(stat: String) -> float:
	return minf(_points_value(stat) + chant_bonus(stat), HARD_CAP.get(stat, INF))

# Value from allocated points only.
func _points_value(stat: String) -> float:
	var p: int = points[stat]
	var v: float
	if stat == "spell_mastery":
		var soft_pts := int(round(MASTERY_SOFT / PER_POINT.spell_mastery))  # 30 points reach 45% (round: 0.45/0.015 is 30.000…1 in floats)
		var lin := mini(p, soft_pts)
		v = lin * PER_POINT.spell_mastery
		if p > soft_pts: v += (p - soft_pts) * PER_POINT.spell_mastery * MASTERY_SOFT_RATE
	else:
		v = BASE[stat] + p * PER_POINT[stat]
	return minf(v, HARD_CAP.get(stat, INF))

# Final value at time `now`: multipliers compound on base, flats add after.
func value(stat: String, now := 0.0) -> float:
	var v := base_value(stat)
	var mul := 1.0
	var flat := 0.0
	var post := 1.0
	for m in modifiers:
		if m.stat == stat and now < m.until:
			mul *= m.mul
			flat += m.flat
			post *= float(m.get("post", 1.0))
	return minf((v * mul + flat) * post, HARD_CAP.get(stat, INF)) # post: applied last (Gambling Addiction's Pow x0.1)

func allocate(stat: String) -> bool:
	if unspent <= 0 or not stat in STATS: return false
	if base_value(stat) >= HARD_CAP.get(stat, INF): return false
	unspent -= 1
	points[stat] += 1
	changed.emit()
	return true

# A stat can still rise (not at its hard cap): a capped stat refuses a chant before it starts [R9].
func can_rise(stat: String) -> bool:
	return stat in STATS and base_value(stat) < HARD_CAP.get(stat, INF) and not buff_block

# Spell Chant reward [R10]: CHANT_GAIN x the tier multiplier (no unspent point used).
func grant_point(stat: String, tier := 1) -> bool:
	if not can_rise(stat): return false
	chant_points[stat] += 1
	chant_gain[stat] += gain_for(stat, tier)
	changed.emit()
	return true

# Reset stats [Sir R4]: every stat back to base; each allocated point is
# refunded, and each chant gain converts into one point. Returns the points refunded.
func reset_stats() -> int:
	var refund := 0
	for stat in STATS:
		refund += int(points[stat]) + int(chant_points[stat]) # allocated points, plus one per chant [R4]
		points[stat] = 0
		chant_points[stat] = 0
		chant_gain[stat] = 0.0
	unspent += refund
	changed.emit()
	return refund

func allocated(stat: String) -> int:
	return int(points[stat])

# Timed modifier set; re-adding the same id refreshes it (no stacking).
func add_modifier(id: String, stat: String, mul: float, flat: float, until: float, post := 1.0) -> bool:
	if buff_block and not id in BUFF_BLOCK_EXEMPT and (mul > 1.0 or flat > 0.0 or post > 1.0):
		buffs_refused += 1
		return false
	modifiers = modifiers.filter(func(m): return not (m.id == id and m.stat == stat))
	modifiers.append({"id": id, "stat": stat, "mul": mul, "flat": flat, "until": until, "post": post})
	changed.emit()
	return true

func expire(now: float) -> void:
	var before := modifiers.size()
	modifiers = modifiers.filter(func(m): return now < m.until)
	if modifiers.size() != before: changed.emit()

# Tech Spec §1.2: linear reduction, hard-capped at 65%.
func cooldown(base_s: float, mastery_applies: bool, now := 0.0) -> float:
	if not mastery_applies: return base_s
	return base_s * (1.0 - minf(value("spell_mastery", now), HARD_CAP.spell_mastery))

# Seconds between basic attacks.
func attack_interval(now := 0.0) -> float:
	return 1.0 / maxf(0.01, value("atk_spd", now))

func snapshot() -> Dictionary:
	return {"points": points.duplicate(), "unspent": unspent}

# Ends every modifier from these sources now (Let it Ride's low roll strips buffs).
func remove_sources(ids: Array) -> void:
	var before := modifiers.size()
	modifiers = modifiers.filter(func(m): return not (m.id in ids))
	if modifiers.size() != before: changed.emit()
