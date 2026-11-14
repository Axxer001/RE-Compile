extends RefCounted
# What outlives a death (Sir, handoff §10 R5, "knowledge is permanent"):
# unlocked Grimoire pages, the Adventurer Rank once earned, and each stat's
# chant difficulty tier. Everything else (level, EXP, points, chant gains,
# HP/MP, loadout, mission kills) belongs to the run and resets on death.
# Saved to user://profile.cfg by the real game; path "" (tests) saves nothing.

const PATH := "user://profile.cfg"
const START_PAGES := ["scorch_and_burn", "cultivate", "dragons_breath", "firefly", "explosion", "flight_of_the_phoenix", "call_of_the_phoenix", "rise_of_the_phoenix", "heads_or_tails", "where_are_my_coins", "let_it_ride", "all_in"] # known from the start [handoff §5]; the three Rank E spells, the Phoenix and Gambler sets for testing [Sir, 2026-11-14]

signal save_failed(error: int)

var path := ""
var unlocked: Array = START_PAGES.duplicate() # page ids
var rank := "E"
var chant_tier := {}    # stat -> chant difficulty level (P6)
# Lifetime records for the Player ID card's front (kept across deaths; wiped by New game).
const RECORDS := {"chants": 0, "best_hit": 0.0, "best_kills": 0, "total_kills": 0, "deaths": 0, "best_level": 1, "longest_run_s": 0.0}
var records := RECORDS.duplicate()
var card_no := ""       # the guild card number, drawn once per profile

func unlock(page_id: String) -> bool:
	if page_id in unlocked: return false
	unlocked.append(page_id)
	save()
	return true

func set_rank(r: String) -> void:
	rank = r
	save()

func save(to := "") -> int:
	var p: String = to if to != "" else path
	if p == "": return OK
	var cf := ConfigFile.new()
	cf.set_value("meta", "unlocked", unlocked)
	cf.set_value("meta", "rank", rank)
	cf.set_value("meta", "chant_tier", chant_tier)
	cf.set_value("meta", "records", records)
	cf.set_value("meta", "card_no", card_no)
	var err := cf.save(p + ".tmp")
	if err == OK and FileAccess.file_exists(p):
		var previous := ConfigFile.new()
		# Never replace the recovery copy with an unreadable primary.
		if previous.load(p) == OK and previous.has_section_key("meta", "unlocked"):
			err = DirAccess.copy_absolute(p, p + ".bak")
	if err == OK: err = DirAccess.rename_absolute(p + ".tmp", p)
	if err != OK:
		push_warning("Profile save failed: %s" % error_string(err))
		save_failed.emit(err)
	return err

# Missing or unreadable file: keep the fresh profile. Returns true if loaded.
func load_from(from := "") -> bool:
	var p: String = from if from != "" else path
	if p == "": return false
	var cf := ConfigFile.new()
	if cf.load(p) != OK or not cf.has_section_key("meta", "unlocked"):
		cf = ConfigFile.new()
		if cf.load(p + ".bak") != OK or not cf.has_section_key("meta", "unlocked"): return false
		push_warning("Recovered profile from backup")
	var u = cf.get_value("meta", "unlocked", START_PAGES)
	unlocked = (u as Array).duplicate() if u is Array else START_PAGES.duplicate()
	for sp in START_PAGES:
		if not sp in unlocked: unlocked.append(sp)
	rank = String(cf.get_value("meta", "rank", "E"))
	var t = cf.get_value("meta", "chant_tier", {})
	chant_tier = (t as Dictionary).duplicate() if t is Dictionary else {}
	var r = cf.get_value("meta", "records", {})
	records = RECORDS.duplicate()
	if r is Dictionary:
		for k in RECORDS: if r.has(k): records[k] = r[k]
	card_no = String(cf.get_value("meta", "card_no", ""))
	return true

func reset() -> void:
	unlocked = START_PAGES.duplicate()
	rank = "E"
	chant_tier = {}
	records = RECORDS.duplicate()
	card_no = ""

# The card number: "AG-" + a 4-digit year-like block + 5 digits, drawn once (kept).
func ensure_card_no(rng: RandomNumberGenerator) -> String:
	if card_no == "": card_no = "AG-%d-%05d" % [rng.randi_range(1000, 9999), rng.randi_range(0, 99999)]
	return card_no

# Records (in memory; saved with the profile at the next save).
func note_hit(amount: float) -> void:
	if amount > float(records.best_hit): records.best_hit = amount

func note_kill(run_kills: int) -> void:
	records.total_kills = int(records.total_kills) + 1
	records.best_kills = maxi(int(records.best_kills), run_kills)

func note_level(level: int) -> void:
	records.best_level = maxi(int(records.best_level), level)

func note_chant() -> void:
	records.chants = int(records.chants) + 1

func note_death(run_s: float) -> void:
	records.deaths = int(records.deaths) + 1
	records.longest_run_s = maxf(float(records.longest_run_s), run_s)
