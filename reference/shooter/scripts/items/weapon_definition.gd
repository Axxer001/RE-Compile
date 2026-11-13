extends Resource
# Immutable weapon definition (shared by every instance; holds no ammo or state).
# Distances in tiles, times in seconds, damage in HP. Ranged weapons fire an
# instant ray at commit (ARCHITECTURE §5); windup+active+recovery is the shot
# interval. Reload: windup = reload_s * RELOAD_COMMIT, the transfer point.

@export var id := &""
@export var label := ""
@export_enum("melee", "ranged", "throwable") var category := "melee"
@export var damage_kind := "melee" # DamagePacket kind (melee, bite, ...)
@export var damage_hp := 0.0
@export var reach_tiles := 1.0
@export var arc_degrees := 90.0
@export var windup_s := 0.25    # commit = hit frame
@export var active_s := 0.1     # impact window after commit
@export var recovery_s := 0.65
@export var endurance_cost := 10.0
@export var noise_radius_tiles := 4.0
@export var magazine_size := 0   # rounds per instance magazine; 0 = no ammo
@export var ammo_type := ""      # item id of its ammunition
@export var range_tiles := 0.0   # ranged: ray length
@export var pellets := 1         # ranged: rays per shot (one round per shot)
@export var spread_deg := 0.0    # ranged: total fan of the pellets
@export_enum("semi", "auto") var fire_mode := "semi"
@export var reload_s := 0.0      # ranged: tactical reload (rounds left in the magazine)
@export var reload_empty_s := 0.0 # ranged: reload from empty (0 = same as reload_s)
# Handling (2026-11-10): our own values, in proportion to the apex-study
# weapon definitions (rifle slow and heavy, pistol quick and light).
@export var draw_s := 0.3         # after equipping: no attack or reload until drawn
@export var ads_s := 0.25         # time to aim in (aim out is ADS_OUT x this)
@export var ads_move_scale := 0.7 # walk/sprint speed multiplier while fully aimed
@export var headshot_mult := 1.0  # ranged: damage multiplier for a head hit
@export var spread_hip_deg := 0.0 # ranged: random cone (half-angle) per shot from the hip...
@export var spread_ads_deg := 0.0 # ...and fully aimed (blended by aim progress)
@export var reload_clip := ""
@export var aim_clip := ""      # ranged: standing pose while equipped
@export var attack_clip := ""   # survivor clip key in data/animations/catalog.json
@export var held_mesh_id := ""  # assets/weapons/<id>.json
@export var source_note := ""   # where the numbers came from

# Action definition consumed by CombatController.
func action() -> Dictionary:
	return {"id": String(id), "windup": windup_s, "active": active_s, "recovery": recovery_s,
		"cost": endurance_cost, "weapon": self, "auto": fire_mode == "auto"}

const RELOAD_COMMIT := 0.8 # fraction of the reload at which rounds move
const ADS_OUT := 0.85      # aim-out time as a fraction of ads_s

# Reload time for this instance: from empty takes reload_empty_s when set.
func reload_time(instance: RefCounted) -> float:
	return reload_empty_s if instance.magazine == 0 and reload_empty_s > 0.0 else reload_s

# Spread cone half-angle at aim progress t (0 hip, 1 fully aimed).
func spread_at(t: float) -> float:
	return lerpf(spread_hip_deg, spread_ads_deg, clampf(t, 0.0, 1.0))

func is_ranged() -> bool:
	return category == "ranged"

# Reload action for one weapon instance; `inventory` supplies reserve rounds.
func reload_action(instance: RefCounted, inventory: RefCounted) -> Dictionary:
	var t := reload_time(instance)
	return {"id": String(id) + "_reload", "clip": reload_clip, "windup": t * RELOAD_COMMIT, "active": 0.0,
		"recovery": t * (1.0 - RELOAD_COMMIT), "cost": 0.0, "reload": {"instance": instance, "inventory": inventory}}

func total_s() -> float:
	return windup_s + active_s + recovery_s
