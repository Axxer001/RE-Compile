extends "res://scripts/actors/forest_ghoul.gd"
const Replacement = preload("res://assets/infected_hostiles/forest_ghoul.glb")

func _build_model() -> void:
	model = Replacement.instantiate()
	model.name = "Model"
	model.rotation.y = PI
	add_child(model)
	anim = model.find_children("*", "AnimationPlayer", true, false)[0]
	var body := OutfitBuilder.body_mesh(model)
	_skin = body.mesh.surface_get_material(0).duplicate()
	body.set_surface_override_material(0, _skin)
	_skin_emission = _skin.emission
	_skin_energy = _skin.emission_energy_multiplier
	_add_eyes()
	var skeleton: Skeleton3D = model.find_children("*", "Skeleton3D", true, false)[0]
	var eyes: BoneAttachment3D = eye_mesh.get_parent() as BoneAttachment3D
	var bind := skeleton.get_bone_global_rest(skeleton.find_bone("Head")).affine_inverse()
	for eye in eyes.get_children():
		eye.position = bind * Vector3(-0.032 if eye.name == "EyeL" else 0.032, 1.699, 0.078)
		eye.scale = Vector3.ONE * 0.38
