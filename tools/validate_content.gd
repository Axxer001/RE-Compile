extends SceneTree
# Content suite: static data integrity, no gameplay execution.
#   godot --headless --path . -s res://tools/validate_content.gd
# Emits one `RESULT {json}` line. --fixture=fail|missing-pass|hang for harness self-tests.

const SUITE := "content"
const LEDGER := "res://docs/asset-licenses.md"
var checks := 0
var failures: Array[String] = []

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)

func _initialize() -> void:
	var fixture := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--fixture="):
			fixture = arg.trim_prefix("--fixture=")
	if fixture == "hang":
		return
	validate_project()
	validate_input_map()
	validate_asset_ledger()
	validate_pages()
	validate_forest_seeds()
	if fixture == "fail":
		check(false, "injected fixture failure")
	if fixture == "missing-pass":
		quit(0)
		return
	var status := "PASS" if failures.is_empty() else "FAIL"
	print("RESULT ", JSON.stringify({"suite": SUITE, "status": status, "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)

# The Dark Forest generator [Sir R11]: 1,000 seeds all give a valid map, and
# tree density varies between them. (The engine-side checks, real navigation,
# build time and per-run seeds, are in the simulation suite.)
const FOREST_SEEDS := 1000
func validate_forest_seeds() -> void:
	var Forest = load("res://scripts/world/dark_forest.gd")
	var bad := []
	var fewest := 1000000
	var most := 0
	var near_start := INF
	var near_pages := INF
	var near_zone := INF
	var zone_path := INF
	for sd in FOREST_SEEDS:
		var m: Dictionary = Forest.generate(sd)
		if m.is_empty():
			bad.append("seed %d: generation failed" % sd)
			continue
		var v: Array = Forest.rule_violations(m)
		if not v.is_empty() and bad.size() < 3: bad.append("seed %d: %s" % [sd, v[0]])
		# The distance rules again, written out here (not read back from the generator's own check).
		var start := Vector2(75, 134)
		var pg: Array = m.pages.values()
		for i in pg.size():
			var a := Vector2(pg[i].x, pg[i].z)
			near_start = minf(near_start, a.distance_to(start))
			for j in range(i + 1, pg.size()): near_pages = minf(near_pages, a.distance_to(Vector2(pg[j].x, pg[j].z)))
			for z in m.zones: near_zone = minf(near_zone, a.distance_to(Vector2(z.at.x, z.at.z)))
		for z in m.zones: zone_path = minf(zone_path, Forest.centreline_dist(Vector2(z.at.x, z.at.z)))
		fewest = mini(fewest, m.trees.size())
		most = maxi(most, m.trees.size())
	check(bad.is_empty(), "%d forest seeds all pass R11's rules (reachable; pages >= 25 m from the start, >= 20 m apart, >= 15 m from zones; nothing within 3 m of a path or in the camp) %s" % [FOREST_SEEDS, str(bad)])
	check(near_start >= 25.0 and near_pages >= 20.0 and near_zone >= 15.0 and zone_path >= 3.0, "over %d seeds, the closest: page to start %.1f m (>= 25), page to page %.1f (>= 20), page to zone %.1f (>= 15), zone to a path %.1f (>= 3)" % [FOREST_SEEDS, near_start, near_pages, near_zone, zone_path])
	check(most > fewest + 100 and fewest > 400, "forest tree density varies by seed (%d to %d trees)" % [fewest, most])

# Grimoire pages and their Code Assembly banks (P5).
func validate_pages() -> void:
	var Lib = load("res://scripts/core/page_library.gd")
	var CA = load("res://scripts/core/code_assembly.gd")
	var Page = load("res://scripts/core/ability_page.gd")
	for id in Lib.IDS:
		var p: Resource = Lib.make(id)
		check(p != null and p.title != "" and p.description != "" and p.lesson != "" and p.hints != "" and not p.concepts.is_empty(), "page %s: title, description, lesson, tip and concepts present" % id)
		check(p != null and p.kind in [Page.Kind.ATTACK, Page.Kind.SKILL, Page.Kind.SPELL, Page.Kind.PASSIVE] and Page.rank_index(p.rank_req) >= 0, "page %s: a valid kind and rank" % id)
		var vs: Array = CA.variants(id)
		check(vs.size() >= 8 and CA.topic(id) != "", "page %s: at least 8 Code Assembly variants on a named topic (%d)" % [id, vs.size()])
		check(p != null and not p.code_lines.is_empty() and Array(p.code_lines) == CA.shown(id).get("lines", []), "page %s: its shown code is bank variant 0" % id)
		var shapes_ok := true
		for v in vs:
			if (v.lines as Array).size() < 3: shapes_ok = false
			for g in v.get("swap", []):
				for k in g:
					if int(k) < 0 or int(k) >= (v.lines as Array).size(): shapes_ok = false
		check(shapes_ok, "page %s: every variant has 3+ lines and valid swap groups" % id)
		# C++ [Sir, 2026-11-14]: every variant is a whole program; nothing Python is left.
		var cpp_ok := true
		var py_left := []
		for v in vs:
			var ls: Array = v.lines
			if not String(ls[0]).begins_with("#include") or not "int main() {" in ls or String(ls[ls.size() - 1]) != "}" or not ls.any(func(l): return String(l).strip_edges() == "return 0;"): cpp_ok = false
			for l in ls:
				if RegEx.create_from_string("^\\s*(case\\s.+|default):\\s*$").search(String(l)) != null: continue # C++ switch labels end in a colon
				if RegEx.create_from_string("^\\s*(def|class|elif|import)\\b|:\\s*$|\\bprint\\(").search(String(l)) != null: py_left.append(l)
		check(cpp_ok and py_left.is_empty(), "page %s: every variant is a C++ program (#include ... int main() { ... return 0; }), no Python %s" % [id, str(py_left.slice(0, 2))])
	# One beginner C++ lesson per page, in course order.
	var order_ok := true
	for i in Lib.IDS.size():
		if not String(Lib.TEACH[Lib.IDS[i]][0]).begins_with(Lib.LESSONS[i] + ":"): order_ok = false
	check(order_ok and Lib.LESSONS == ["C++ Intro", "C++ Get Started", "C++ Syntax", "C++ Output", "C++ Comments", "C++ Variables", "C++ User Input", "C++ Data Types", "C++ Operators", "C++ Strings", "C++ Math", "C++ Booleans", "C++ If...Else", "C++ Switch", "C++ While Loop"], "pages teach C++ in course order: %s" % ", ".join(Lib.LESSONS))

func validate_project() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/main.tscn", "main scene is scenes/main.tscn")
	check(ResourceLoader.exists("res://scenes/main.tscn") and ResourceLoader.exists("res://scenes/player/player.tscn"), "main and player scenes exist")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "forward_plus", "desktop renderer is Forward+")
	check(ProjectSettings.get_setting("rendering/renderer/rendering_method.mobile") == "mobile", "mobile override uses the Mobile renderer (Android stretch)")
	check(int(ProjectSettings.get_setting("physics/common/physics_ticks_per_second")) == 60, "fixed 60 Hz simulation tick")

# Every control exists, has exactly one binding, and no input is shared.
func validate_input_map() -> void:
	var Router = load("res://scripts/core/input_router.gd")
	var seen := {}
	for action in Router.ACTIONS:
		check(InputMap.has_action(action), "InputMap action %s exists" % action)
		if not InputMap.has_action(action): continue
		var events := InputMap.action_get_events(action)
		check(events.size() == 1, "action %s has exactly one binding (%d)" % [action, events.size()])
		for e in events:
			var key := ("key:%d" % e.physical_keycode) if e is InputEventKey else ("mouse:%d" % e.button_index)
			check(not seen.has(key), "%s for %s not also bound to %s" % [key, action, seen.get(key, "")])
			seen[key] = action
	# Grimoire key map (docs/pivot-grimoire-plan.md §3).
	var want := {"dash": KEY_SHIFT, "skill_1": KEY_E, "skill_2": KEY_Q, "spell_1": KEY_1, "spell_2": KEY_2, "spell_3": KEY_3, "interact": KEY_F, "grimoire": KEY_TAB}
	for a in want: check(InputMap.has_action(a) and InputMap.action_get_events(a)[0].physical_keycode == want[a], "%s is %s" % [a, OS.get_keycode_string(want[a])])
	check(InputMap.action_get_events("attack")[0].button_index == MOUSE_BUTTON_LEFT and InputMap.action_get_events("special")[0].button_index == MOUSE_BUTTON_RIGHT, "LMB basic attack, RMB special attack")
	for gone in ["sprint", "aim", "reload", "throw", "cycle_throwable", "bullet_time", "flashlight", "slot_4", "drop", "inventory"]:
		check(not InputMap.has_action(gone), "shooter action %s is retired" % gone)

# Each folder under assets/ (two levels) must be named in the licence ledger.
func validate_asset_ledger() -> void:
	var ledger := FileAccess.get_file_as_string(LEDGER)
	check(ledger.length() > 0, "licence ledger exists")
	for top in DirAccess.get_directories_at("res://assets"):
		var subs := DirAccess.get_directories_at("res://assets/" + top)
		if subs.is_empty():
			check(ledger.contains("assets/%s/" % top), "assets/%s is in the licence ledger" % top)
		for sub in subs:
			check(ledger.contains("assets/%s/%s/" % [top, sub]), "assets/%s/%s is in the licence ledger" % [top, sub])
