extends RefCounted
# Spell Chanting (GDD §3.4.4, Tech Spec §3.3, handoff §6 and §10 R2/R3).
# A chant blanks tokens out of code from the Grimoire's own pages; the player
# types them back. Pure and headless: the panel shows a problem and calls check().
# C++ since 2026-11-14 [Sir]: one tier per page lesson, in course order.
#   Tiers (what is masked)                  code drawn from              needs unlocked
#   1 program structure (#include, iostream, main, return)
#                                           Scorch and Burn, Cultivate   Scorch and Burn
#   2 syntax (; { } using namespace std)    Ring of Fire                 + Ring of Fire
#   3 output (cout << endl)                 Quick Step                   + Quick Step
#   4 comments (// /* */)                   Sage Arts                    + Sage Arts
#   5 variables (int double string const =) Dragon's Breath              + Dragon's Breath
#   6 user input (cin >>)                   Firefly                      + Firefly
#   7 data types (int float double bool char string auto)
#                                           Explosion                    + Explosion
#   8 operators / 9 strings / 10 math       the three Phoenix pages      + each page
#  11 booleans (bool true false == != < >)  Heads or Tails               + Heads or Tails
#  12 if / else (if else && || !)           Where are my Coins?          + Where are my Coins?
#  13 switch (switch case break default)    Let it Ride                  + Let it Ride
#  14 while loops (while do)                All In                       + All In
# Tier 1 draws only from its pages that are unlocked (Cultivate's code once Cultivate is).
# Difficulty per stat [handoff §6]: level = successful chants on that stat
# (kept in the profile); tier = min(1 + level / 2, the highest tier the
# unlocked pages allow) and blanks = 1 + level % 2. Every blank in a chant is
# of that tier [R2]. Guardrail: never a tier whose pages are not unlocked; past
# it the difficulty plateaus. Each attempt is fresh and never the last one [R2].
# Blanks are always syntax, never a number (Sir, 2026-11-12), and never text
# inside a string literal.

const CodeAssembly = preload("res://scripts/core/code_assembly.gd")
const TIER_PAGES := {1: ["scorch_and_burn"], 2: ["scorch_and_burn", "ring_of_fire"],
	3: ["scorch_and_burn", "ring_of_fire", "quick_step"],
	4: ["scorch_and_burn", "ring_of_fire", "quick_step", "sage_arts"],
	5: ["scorch_and_burn", "ring_of_fire", "quick_step", "sage_arts", "dragons_breath"],
	6: ["scorch_and_burn", "ring_of_fire", "quick_step", "sage_arts", "dragons_breath", "firefly"],
	7: ["scorch_and_burn", "ring_of_fire", "quick_step", "sage_arts", "dragons_breath", "firefly", "explosion"],
	8: ["scorch_and_burn", "ring_of_fire", "quick_step", "sage_arts", "dragons_breath", "firefly", "explosion", "flight_of_the_phoenix"],
	9: ["scorch_and_burn", "ring_of_fire", "quick_step", "sage_arts", "dragons_breath", "firefly", "explosion", "flight_of_the_phoenix", "call_of_the_phoenix"],
	10: ["scorch_and_burn", "ring_of_fire", "quick_step", "sage_arts", "dragons_breath", "firefly", "explosion", "flight_of_the_phoenix", "call_of_the_phoenix", "rise_of_the_phoenix"],
	11: ["scorch_and_burn", "ring_of_fire", "quick_step", "sage_arts", "dragons_breath", "firefly", "explosion", "flight_of_the_phoenix", "call_of_the_phoenix", "rise_of_the_phoenix", "heads_or_tails"],
	12: ["scorch_and_burn", "ring_of_fire", "quick_step", "sage_arts", "dragons_breath", "firefly", "explosion", "flight_of_the_phoenix", "call_of_the_phoenix", "rise_of_the_phoenix", "heads_or_tails", "where_are_my_coins"],
	13: ["scorch_and_burn", "ring_of_fire", "quick_step", "sage_arts", "dragons_breath", "firefly", "explosion", "flight_of_the_phoenix", "call_of_the_phoenix", "rise_of_the_phoenix", "heads_or_tails", "where_are_my_coins", "let_it_ride"],
	14: ["scorch_and_burn", "ring_of_fire", "quick_step", "sage_arts", "dragons_breath", "firefly", "explosion", "flight_of_the_phoenix", "call_of_the_phoenix", "rise_of_the_phoenix", "heads_or_tails", "where_are_my_coins", "let_it_ride", "all_in"]}
const TIER_SOURCE := {1: ["scorch_and_burn", "cultivate"], 2: ["ring_of_fire"], 3: ["quick_step"], 4: ["sage_arts"],
	5: ["dragons_breath"], 6: ["firefly"], 7: ["explosion"], 8: ["flight_of_the_phoenix"], 9: ["call_of_the_phoenix"], 10: ["rise_of_the_phoenix"],
	11: ["heads_or_tails"], 12: ["where_are_my_coins"], 13: ["let_it_ride"], 14: ["all_in"]}
const TIER_NAMES := {1: "program structure", 2: "syntax: ; { } and namespace", 3: "output: cout << endl", 4: "comments",
	5: "variables: types and =", 6: "user input: cin >>", 7: "data types", 8: "operators", 9: "strings", 10: "math functions",
	11: "booleans: bool, true/false, comparisons", 12: "if / else", 13: "switch / case", 14: "while loops"}
# The tier whose blanks are variable names (they must be readable from the rest
# of the snippet). None yet: C++ variables arrive with a later page's lesson.
const VAR_TIER := -1
# Regex per tier; the first non-empty group is the masked part.
const PATTERNS := {
	1: "(#include)|<(iostream)>|\\b(main|return)\\b",
	2: "\\b(using|namespace)\\b|\\b(std)(?=::)|(;)\\s*(?://.*)?$|([{}])",
	3: "\\b(cout|endl)\\b|(<<)",
	4: "(//)|(/\\*)|(\\*/)",
	5: "\\b(const)\\b(?=\\s+\\w+\\s+\\w+\\s*=)|\\b(int|double|string)\\b(?=\\s+[A-Za-z_]\\w*\\s*=)|\\s(=)\\s",
	6: "\\b(cin)\\b|(>>)",
	7: "\\b(int|float|double|bool|char|string|auto)\\b(?=\\s+[A-Za-z_]\\w*\\s*=)",
	8: "\\s([-+*/%])\\s|(\\+\\+|--)(?=;)|\\s([-+*/]=)\\s",
	9: "\\b(string)\\b(?=\\s+[A-Za-z_])|\\.(length)\\b|<(string)>|\\s(\\+=?)\\s",
	10: "\\b(max|min|sqrt|pow|round)\\b(?=\\()|<(cmath)>",
	11: "\\b(bool|true|false|boolalpha)\\b|\\s(==|!=|<=|>=)\\s|\\s([<>])\\s",
	12: "\\b(if|else)\\b|(&&|\\|\\|)|(!)(?=[A-Za-z_(])",
	13: "\\b(switch|case|break|default)\\b",
	14: "\\b(while|do)\\b",
}
const PLATEAU_HINT := "Unlock more pages to deepen your chants."

static func max_tier(unlocked: Array) -> int:
	var best := 0
	for t in TIER_PAGES:
		if TIER_PAGES[t].all(func(p): return p in unlocked): best = maxi(best, t)
	return best

# {tier, blanks, plateau} for a stat that has `level` successful chants.
static func difficulty(level: int, unlocked: Array) -> Dictionary:
	var want := 1 + int(level / 2)
	var cap := max_tier(unlocked)
	return {"tier": mini(want, cap), "blanks": 1 + level % 2, "plateau": want > cap}

# Every maskable token in a line for a tier: [{start, end, text}], skipping
# anything inside string literals.
static func tokens(line: String, tier: int) -> Array:
	var quoted := []
	var q := -1
	for i in line.length():
		if line[i] == "\"":
			if q < 0: q = i
			else:
				quoted.append([q, i])
				q = -1
	var re := RegEx.create_from_string(PATTERNS[tier])
	var out := []
	for m in re.search_all(line):
		var g := 0
		for k in range(1, m.get_group_count() + 1):
			if m.get_string(k) != "":
				g = k
				break
		var start := m.get_start(g)
		var inside := quoted.any(func(r): return start > r[0] and start < r[1])
		if inside: continue
		out.append({"start": start, "end": m.get_end(g), "text": m.get_string(g), "var": tier == VAR_TIER})
	return out

# All single-token candidates for a tier: [{page, variant, line, token}], from
# the tier's pages that are unlocked (all of them when `unlocked` is empty).
static func candidates(tier: int, unlocked: Array = []) -> Array:
	var out := []
	for page in TIER_SOURCE[tier]:
		if not unlocked.is_empty() and not page in unlocked: continue
		var vs := CodeAssembly.variants(page)
		for vi in vs.size():
			var lines: Array = vs[vi].lines
			for li in lines.size():
				for t in tokens(lines[li], tier):
					# A blanked variable must be readable from the rest of the snippet: used again elsewhere.
					if t.get("var", false) and not _used_elsewhere(lines, li, String(t.text)): continue
					out.append({"page": page, "variant": vi, "line": li, "token": t})
	return out

static func _used_elsewhere(lines: Array, li: int, name: String) -> bool:
	var re := RegEx.create_from_string("\\b%s\\b" % name)
	for k in lines.size():
		if k != li and re.search(String(lines[k])) != null: return true
	return false

# A fresh problem for a stat: {key, tier, blanks, plateau, page, variant, lines (with [?n]), answers}.
static func draw(level: int, unlocked: Array, rng: RandomNumberGenerator, last_key := "") -> Dictionary:
	var d := difficulty(level, unlocked)
	if d.tier < 1: return {}
	var pool := candidates(d.tier, unlocked)
	# Group by snippet (page + variant): a chant's blanks share one snippet.
	var by_snip := {}
	for cnd in pool:
		var k := "%s:%d" % [cnd.page, cnd.variant]
		if not by_snip.has(k): by_snip[k] = []
		by_snip[k].append(cnd)
	var snips: Array = by_snip.keys().filter(func(k): return by_snip[k].size() >= d.blanks)
	if snips.is_empty(): return {}
	for attempt in 32:
		var sk: String = snips[rng.randi_range(0, snips.size() - 1)]
		var picks: Array = by_snip[sk].duplicate()
		for i in range(picks.size() - 1, 0, -1):
			var j := rng.randi_range(0, i)
			var t = picks[i]; picks[i] = picks[j]; picks[j] = t
		picks = picks.slice(0, d.blanks)
		picks.sort_custom(func(a, b): return a.line < b.line or (a.line == b.line and a.token.start < b.token.start))
		var key := sk + "|" + ",".join(picks.map(func(p): return "%d.%d" % [p.line, p.token.start]))
		if key == last_key and attempt < 31: continue
		return _problem(key, d, picks)
	return {}

static func _problem(key: String, d: Dictionary, picks: Array) -> Dictionary:
	var page: String = picks[0].page
	var vi: int = picks[0].variant
	var lines: Array = (CodeAssembly.variants(page)[vi].lines as Array).duplicate()
	var answers := []
	# Replace right to left within a line so earlier offsets stay valid.
	var order := range(picks.size())
	order.sort_custom(func(a, b): return picks[a].line > picks[b].line or (picks[a].line == picks[b].line and picks[a].token.start > picks[b].token.start))
	answers.resize(picks.size())
	for idx in order:
		var p: Dictionary = picks[idx]
		var l: String = lines[p.line]
		lines[p.line] = l.substr(0, p.token.start) + "[?%d]" % (idx + 1) + l.substr(p.token.end)
		answers[idx] = String(p.token.text)
	return {"key": key, "tier": d.tier, "blanks": d.blanks, "plateau": d.plateau, "page": page, "variant": vi, "lines": lines, "answers": answers}

# Whitespace and surrounding quotes don't matter; code tokens are case-sensitive;
# a number may be written in any equal form (0.10 = 0.1).
static func normalise(s: String) -> String:
	var t := " ".join(s.strip_edges().split(" ", false))
	if t.length() >= 2 and ((t.begins_with("\"") and t.ends_with("\"")) or (t.begins_with("'") and t.ends_with("'"))):
		t = t.substr(1, t.length() - 2).strip_edges()
	return t

static func matches(given: String, want: String) -> bool:
	var g := normalise(given)
	if g == normalise(want): return true
	if want.is_valid_float() and g.is_valid_float(): return is_equal_approx(g.to_float(), want.to_float())
	return false

# {ok, wrong: [blank indices]}
static func check(problem: Dictionary, given: Array) -> Dictionary:
	var wrong := []
	for i in problem.answers.size():
		if i >= given.size() or not matches(String(given[i]), problem.answers[i]): wrong.append(i)
	return {"ok": wrong.is_empty(), "wrong": wrong}
