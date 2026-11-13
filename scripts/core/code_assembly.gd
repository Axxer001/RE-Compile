extends RefCounted
# Code Assembly question bank (Sir R2, handoff §10): every attempt draws a
# fresh variant on the page's topic, never the previous attempt's, shuffled so
# it never starts out solved. Banks: data/puzzles/code_assembly.json (made by
# tools/make_code_assembly_bank.py, which compiles every variant as C++ with
# g++ -fsyntax-only). One beginner C++ lesson per page [Sir, 2026-11-14].

const Validator = preload("res://scripts/core/code_order_validator.gd")
const BANK_PATH := "res://data/puzzles/code_assembly.json"

static var _bank: Dictionary = {}

static func bank() -> Dictionary:
	if _bank.is_empty():
		var f := FileAccess.open(BANK_PATH, FileAccess.READ)
		if f != null:
			var j = JSON.parse_string(f.get_as_text())
			if j is Dictionary: _bank = j
	return _bank

static func variants(page_id: String) -> Array:
	return bank().get(page_id, {}).get("variants", [])

static func topic(page_id: String) -> String:
	return String(bank().get(page_id, {}).get("topic", ""))

# The variant shown on the unlocked page: the Tech Spec block (variant 0).
static func shown(page_id: String) -> Dictionary:
	var v := variants(page_id)
	return v[0] if not v.is_empty() else {}

# A new attempt: {page, index, variant, order} with index != last_index and an
# order that is not already solved.
static func draw(page_id: String, rng: RandomNumberGenerator, last_index := -1) -> Dictionary:
	var vs := variants(page_id)
	if vs.is_empty(): return {}
	var idx := rng.randi_range(0, vs.size() - 1)
	if vs.size() > 1:
		while idx == last_index: idx = rng.randi_range(0, vs.size() - 1)
	var v: Dictionary = vs[idx]
	return {"page": page_id, "index": idx, "variant": v, "order": shuffled(v, rng)}

static func shuffled(v: Dictionary, rng: RandomNumberGenerator) -> Array:
	var n: int = (v.lines as Array).size()
	var order := range(n)
	for attempt in 64:
		for i in range(n - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = order[i]; order[i] = order[j]; order[j] = t
		if not Validator.check(v, order).ok: return order
	# Fallback (never needed for n >= 2): reverse is never solved unless all swappable.
	order = range(n)
	order.reverse()
	return order
