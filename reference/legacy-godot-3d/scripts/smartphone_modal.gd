extends Control

signal stats_closed()

@onready var points_label: Label = $PhoneBody/Screen/Content/Header/PointsLabel
@onready var files_label: Label = $PhoneBody/Screen/Content/Header/FilesLabel

# Stat value labels
@onready var hp_val: Label = $PhoneBody/Screen/Content/StatsList/HPRow/Value
@onready var def_val: Label = $PhoneBody/Screen/Content/StatsList/DefRow/Value
@onready var atk_val: Label = $PhoneBody/Screen/Content/StatsList/AtkRow/Value
@onready var atk_spd_val: Label = $PhoneBody/Screen/Content/StatsList/AtkSpdRow/Value
@onready var mov_spd_val: Label = $PhoneBody/Screen/Content/StatsList/MovSpdRow/Value

# Upgrade buttons
@onready var hp_btn: Button = $PhoneBody/Screen/Content/StatsList/HPRow/UpgradeBtn
@onready var def_btn: Button = $PhoneBody/Screen/Content/StatsList/DefRow/UpgradeBtn
@onready var atk_btn: Button = $PhoneBody/Screen/Content/StatsList/AtkRow/UpgradeBtn
@onready var atk_spd_btn: Button = $PhoneBody/Screen/Content/StatsList/AtkSpdRow/UpgradeBtn
@onready var mov_spd_btn: Button = $PhoneBody/Screen/Content/StatsList/MovSpdRow/UpgradeBtn
@onready var close_btn: Button = $PhoneBody/Screen/Content/CloseBtn

var progression: Node

func _ready() -> void:
	visible = false
	progression = get_node_or_null("/root/PlayerProgression")
	if progression:
		progression.stats_updated.connect(refresh_ui)
		
	if hp_btn: hp_btn.pressed.connect(func(): _upgrade("HP"))
	if def_btn: def_btn.pressed.connect(func(): _upgrade("DEF"))
	if atk_btn: atk_btn.pressed.connect(func(): _upgrade("ATK"))
	if atk_spd_btn: atk_spd_btn.pressed.connect(func(): _upgrade("ATK_SPD"))
	if mov_spd_btn: mov_spd_btn.pressed.connect(func(): _upgrade("MOV_SPD"))
	if close_btn: close_btn.pressed.connect(toggle_phone)

func toggle_phone() -> void:
	visible = not visible
	if visible:
		refresh_ui()
	else:
		stats_closed.emit()

func _upgrade(stat: String) -> void:
	if progression and progression.has_method("upgrade_stat"):
		progression.upgrade_stat(stat)

func refresh_ui() -> void:
	if progression == null:
		return
		
	points_label.text = "UPGRADE POINTS: %d" % progression.upgrade_points
	files_label.text = "FILES RECOVERED: %d" % progression.files_retrieved
	
	hp_val.text = "%.0f (Lv %d)" % [progression.get_max_hp(), progression.hp_level]
	def_val.text = "+%.0f (Lv %d)" % [progression.get_defense(), progression.def_level]
	atk_val.text = "+%.0f%% (Lv %d)" % [(progression.get_atk_multiplier() - 1.0) * 100.0, progression.atk_level]
	atk_spd_val.text = "-%.0f%% (Lv %d)" % [(1.0 - progression.get_atk_speed_multiplier()) * 100.0, progression.atk_spd_level]
	mov_spd_val.text = "+%.0f%% (Lv %d)" % [(progression.get_mov_speed_multiplier() - 1.0) * 100.0, progression.mov_spd_level]
	
	var can_upgrade: bool = progression.upgrade_points > 0
	hp_btn.disabled = not can_upgrade
	def_btn.disabled = not can_upgrade
	atk_btn.disabled = not can_upgrade
	atk_spd_btn.disabled = not can_upgrade
	mov_spd_btn.disabled = not can_upgrade
