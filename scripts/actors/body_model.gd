extends RefCounted
# Shared look for human-shaped enemies: a Quaternius base body (realistic
# proportions), a skin tint, clothes built from the body's own skinned mesh
# (outfit_builder.gd) and the Universal Animation Library clips.

const OutfitBuilder = preload("res://scripts/actors/outfit_builder.gd")
const BODY_MALE := "res://assets/quaternius/base_characters/Superhero_Male_FullBody.gltf"
const BODY_FEMALE := "res://assets/quaternius/base_characters/Superhero_Female_FullBody.gltf"
# Universal Animation Library 1 + 2 (CC0, the same 65-bone rig as the bodies).
const ANIMS := "res://assets/quaternius/animations/UAL1_Standard.glb"
const ANIMS_2 := "res://assets/quaternius/animations_2/UAL2_Standard.glb"
# clip key -> [library clip, loops]. The first eight keys are the original set
# (kept for existing callers); the rest are player locomotion and casting
# (player_body.gd) and the Sprite's zombie set (blighted_sprite.gd).
const CLIPS := {"idle": ["Idle", true], "walk": ["Walk", true], "jog": ["Jog_Fwd", true], "crawl": ["Crouch_Fwd", true],
	"crouch": ["Crouch_Idle", true], "bite": ["Punch_Jab", false], "hit": ["Hit_Chest", false], "death": ["Death01", false],
	# player movement
	"run": ["Sprint", true], "jump_start": ["NinjaJump_Start", false], "jump_air": ["NinjaJump_Idle", true],
	"land": ["NinjaJump_Land", false], "slide_start": ["Slide_Start", false], "slide": ["Slide", true],
	"slide_exit": ["Slide_Exit", false], "climb": ["ClimbUp_1m", false], "roll": ["Roll", false],
	# casting (attacks wire later)
	"cast_enter": ["Spell_Simple_Enter", false], "cast_idle": ["Spell_Simple_Idle", true],
	"cast_shoot": ["Spell_Simple_Shoot", false], "cast_exit": ["Spell_Simple_Exit", false], "throw": ["OverhandThrow", false],
	# Blighted Sprite
	"zombie_idle": ["Zombie_Idle", true], "zombie_walk": ["Zombie_Walk_Fwd", true], "zombie_scratch": ["Zombie_Scratch", false],
	"knockback": ["Hit_Knockback", false]}

static var _lib: AnimationLibrary

static func library() -> AnimationLibrary:
	if _lib != null: return _lib
	_lib = AnimationLibrary.new()
	var players: Array[AnimationPlayer] = []
	var sources: Array[Node] = []
	for path in [ANIMS, ANIMS_2]:
		if not ResourceLoader.exists(path): continue
		var src: Node = (load(path) as PackedScene).instantiate()
		sources.append(src)
		players.append(src.find_children("*", "AnimationPlayer", true, false)[0])
	for key in CLIPS:
		for ap in players:
			if ap.has_animation(CLIPS[key][0]):
				var a: Animation = ap.get_animation(CLIPS[key][0]).duplicate()
				a.loop_mode = Animation.LOOP_LINEAR if CLIPS[key][1] else Animation.LOOP_NONE
				_lib.add_animation(key, a)
				break
	for src in sources: src.free()
	return _lib

# Returns {model, anim}. outfit: garment -> material (see OutfitBuilder.fabric).
static func build(parent: Node3D, female: bool, skin_tint: Color, outfit: Dictionary, scale := 1.0, emission := Color.BLACK) -> Dictionary:
	var model: Node3D = (load(BODY_FEMALE if female else BODY_MALE) as PackedScene).instantiate()
	model.name = "Model"
	model.rotation.y = PI # Quaternius bodies face +Z; actors face -Z
	model.scale = Vector3.ONE * scale
	parent.add_child(model)
	var body := OutfitBuilder.body_mesh(model)
	var skin: BaseMaterial3D = body.mesh.surface_get_material(0).duplicate()
	skin.albedo_color = skin_tint
	if emission != Color.BLACK:
		skin.emission_enabled = true
		skin.emission = emission
	body.set_surface_override_material(0, skin)
	OutfitBuilder.dress(model, outfit)
	var anim := AnimationPlayer.new()
	anim.name = "Anim"
	model.add_child(anim)
	anim.root_node = NodePath("..")
	anim.add_animation_library("", library())
	return {"model": model, "anim": anim}
