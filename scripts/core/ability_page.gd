extends Resource
# One Grimoire page (GDD §3.1, Tech Spec §3.2). Immutable data; unlock state and
# loadout live in the player's Grimoire, not here.

enum Kind { ATTACK, SKILL, SPELL, PASSIVE }
const RANKS := ["E", "D", "C", "B", "A", "S"]

@export var id := &""
@export var title := ""
@export var kind: Kind = Kind.ATTACK
@export_multiline var description := ""
@export var rank_req := "E"            # minimum Adventurer Rank to equip/use
@export var mp_cost := 0.0
@export var cooldown_s := 0.0          # 0 = none (basic attack uses Atk Spd)
@export var mastery_applies := false   # spells and cooldown-based specials
@export var damage_pct := 0.0          # of Magic Pow, per hit
@export var effect_id := ""
@export var effect_s := 0.0
@export var duration_s := 0.0          # buffs, orbitals
# Special attack (ATTACK pages only): the powered-up half of the same page.
@export_multiline var special_description := ""
@export var special_damage_pct := 0.0
@export var special_cooldown_s := 0.0
@export var special_effect_s := 0.0
# Teaching content.
@export var code_lines: PackedStringArray = []   # correct order
@export_multiline var lesson := ""
@export_multiline var hints := ""
@export var concepts: PackedStringArray = []     # chant concept tags this page teaches

static func rank_index(rank: String) -> int:
	return RANKS.find(rank)

func rank_ok(player_rank: String) -> bool:
	return rank_index(player_rank) >= rank_index(rank_req)

func kind_name() -> String:
	return ["Basic & Special Attack", "Skill", "Spell", "Passive"][kind]
