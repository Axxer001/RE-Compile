extends RefCounted
# Level, EXP, Adventurer Rank and stat-point income (GDD §3.4, Tech Spec §1.3).
# Points land in a StatContainer's `unspent`.

signal leveled(level: int, points: int)
signal ranked(rank: String, points: int)
signal exp_gained(amount: int, source: String)

const AbilityPage = preload("res://scripts/core/ability_page.gd")
const EXP := {"kill": 25, "page_unlock": 150, "chant_base": 60, "chant_streak": 5, "rank_up": 300}
const PAGE_UNLOCK_POINTS := 3
const RANK_MISSIONS := {"E": {"kills": 20}} # E -> D for the MVP

var stats: RefCounted
var level := 1
var exp := 0          # progress toward the next level
var rank := "E"
var kills := 0
var chant_streak := 0

func _init(stat_container: RefCounted) -> void:
	stats = stat_container

static func exp_required(l: int) -> int:
	return int(floor(100.0 * pow(float(l), 1.4)))

# Points for reaching level `l`: 1 + 1 per 10 levels (lvl 10-19 -> 2 ...).
static func points_for_level(l: int) -> int:
	return 1 + int(l / 10)

# Points for promoting into `new_rank`: 5 x its index (E->D 5, D->C 10, ...).
static func points_for_rank(new_rank: String) -> int:
	return 5 * AbilityPage.rank_index(new_rank)

func add_exp(amount: int, source := "") -> void:
	exp += amount
	exp_gained.emit(amount, source)
	while exp >= exp_required(level):
		exp -= exp_required(level)
		_level_up(true)

func _level_up(grant_points: bool) -> void:
	level += 1
	var pts := points_for_level(level) if grant_points else 0
	stats.unspent += pts
	leveled.emit(level, pts)

func on_kill(exp_value := EXP.kill) -> void:
	kills += 1
	add_exp(exp_value, "kill")
	_check_rank()

func on_page_unlocked() -> void:
	stats.unspent += PAGE_UNLOCK_POINTS
	add_exp(EXP.page_unlock, "page_unlock")

# Spell Chant success [Sir R9/R10]: the stat's chant gain (x the tier) only: no EXP, no
# level, no stat point. The streak is still counted (shown, no reward).
func on_chant_success(stat: String, tier := 1) -> bool:
	if not stats.grant_point(stat, tier): return false
	chant_streak += 1
	return true

func on_chant_fail() -> void:
	chant_streak = 0

func mission() -> Dictionary:
	var m: Dictionary = RANK_MISSIONS.get(rank, {})
	if m.is_empty(): return {}
	return {"text": "Defeat %d enemies" % m.kills, "progress": mini(kills, m.kills), "target": m.kills}

func _check_rank() -> void:
	var m: Dictionary = RANK_MISSIONS.get(rank, {})
	if m.is_empty() or kills < m.kills: return
	rank = AbilityPage.RANKS[AbilityPage.rank_index(rank) + 1]
	var pts := points_for_rank(rank)
	stats.unspent += pts
	ranked.emit(rank, pts)
	add_exp(EXP.rank_up, "rank_up")

func snapshot() -> Dictionary:
	return {"level": level, "exp": exp, "rank": rank, "kills": kills, "streak": chant_streak}
