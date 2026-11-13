class_name WeaponData
extends Resource

enum WeaponCategory { MELEE, RANGED, THROWABLE }
enum RangedFireMode { SEMI_AUTO, BURST, SPREAD }

@export_group("Identity")
@export var id: String = "knife"
@export var display_name: String = "Combat Knife"
@export var category: WeaponCategory = WeaponCategory.MELEE

@export_group("Combat Stats")
@export var damage: float = 20.0
@export var knockback_force: float = 3.0
@export var stun_duration: float = 0.25
@export var stamina_cost: float = 12.0
@export var attack_duration: float = 0.18
@export var attack_cooldown: float = 0.25
@export var reach: float = 1.0
@export var noise_radius: float = 3.0

@export_group("Ranged Specific")
@export var fire_mode: RangedFireMode = RangedFireMode.SEMI_AUTO
@export var pellets: int = 1
@export var spread_angle_deg: float = 0.0
@export var current_ammo: int = 12
@export var max_ammo: int = 12
@export var range_distance: float = 25.0

@export_group("Visuals & Offsets")
@export var mesh_path: String = ""
@export var mesh_scale: Vector3 = Vector3(1.0, 1.0, 1.0)
@export var mesh_rotation_degrees: Vector3 = Vector3(0.0, 0.0, 0.0)
@export var mesh_offset: Vector3 = Vector3(0.0, 0.0, 0.0)
@export var preview_color: Color = Color.WHITE
