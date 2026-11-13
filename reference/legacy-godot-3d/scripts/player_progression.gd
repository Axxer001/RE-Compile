extends Node

signal stats_updated()
signal upgrade_point_gained(total_points: int)

# Upgrade points earned from retrieving research files
var upgrade_points: int = 0
var files_retrieved: int = 0

# Core RPG / Survival Attributes
var hp_level: int = 0         # Base HP: 100 + (lvl * 15)
var def_level: int = 0        # Defense: 0 + (lvl * 2) flat damage reduction
var atk_level: int = 0        # Attack: + (lvl * 10%) bonus weapon damage
var atk_spd_level: int = 0    # Attack Speed: - (lvl * 8%) cooldown reduction
var mov_spd_level: int = 0    # Movement Speed: + (lvl * 5%) walk/sprint speed

func add_research_file() -> void:
	files_retrieved += 1
	upgrade_points += 1
	upgrade_point_gained.emit(upgrade_points)
	stats_updated.emit()

func upgrade_stat(stat_name: String) -> bool:
	if upgrade_points <= 0:
		return false
		
	match stat_name:
		"HP":
			hp_level += 1
		"DEF":
			def_level += 1
		"ATK":
			atk_level += 1
		"ATK_SPD":
			atk_spd_level += 1
		"MOV_SPD":
			mov_spd_level += 1
		_:
			return false
			
	upgrade_points -= 1
	stats_updated.emit()
	return true

func get_max_hp() -> float:
	return 100.0 + (hp_level * 15.0)

func get_defense() -> float:
	return def_level * 2.0

func get_atk_multiplier() -> float:
	return 1.0 + (atk_level * 0.10)

func get_atk_speed_multiplier() -> float:
	# Cooldown multiplier: lower = faster
	return max(0.4, 1.0 - (atk_spd_level * 0.08))

func get_mov_speed_multiplier() -> float:
	return 1.0 + (mov_spd_level * 0.05)
