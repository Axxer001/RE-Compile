extends RefCounted
# Approved hostile presentation for the Dark Forest asset swap [2026-11-24].
# Each builder instances one approved GLB and hands the actor its own AnimationPlayer.
# The glTF importer already publishes the clips under the names the actors' _animate()
# asks for: it strips the authoring "_loop" suffix and sets the loop mode from it, so
# no clip is renamed, duplicated or re-timed here. Gameplay (controllers, collision,
# damage, drops, state machine, attack windows) is untouched by the swap.
#
# Rollback: revert scripts/actors/{blighted_sprite,forest_ghoul,kostas_mortus}.gd and
# delete assets/hostiles/ + this file.

const SPRITE_PATH := "res://assets/hostiles/blighted_sprite.glb"
const GHOUL_PATH := "res://assets/hostiles/forest_ghoul.glb"
const MORTUS_PATH := "res://assets/hostiles/kostas_mortus.glb"

# The clips each actor selects, as imported ("idle" is the authoring idle_loop,
# "air" the air_loop, "stride" the stride_loop, ...).
const SPRITE_CLIPS := ["idle", "walk", "run", "strike", "death", "pounce_start", "air", "climb"]
const GHOUL_CLIPS := ["idle", "walk", "jog", "climb", "draw", "aim", "shoot", "death"]
# rush and impact are bound and available; the actor plays neither (the
# velocity-driven charge owns the body's movement, and the knockback fires once
# from the existing gameplay path rather than from the clip's method key).
const MORTUS_CLIPS := ["idle", "stride", "charge", "run", "rush", "strike", "impact", "death"]

# Instances the model under `parent` (actors face -Z; the GLBs face +Z) and returns
# {model, anim, skins}. A missing clip is reported loudly instead of failing later
# inside _animate().
static func build(path: String, clips: Array, parent: Node3D) -> Dictionary:
	var model: Node3D = (load(path) as PackedScene).instantiate()
	model.name = "Model"
	model.rotation.y = PI
	parent.add_child(model)
	var found := model.find_children("*", "AnimationPlayer", true, false)
	if found.is_empty():
		push_error("%s has no AnimationPlayer" % path)
		return {"model": model, "anim": null, "skins": []}
	var anim := found[0] as AnimationPlayer
	for key in clips:
		if not anim.has_animation(key):
			push_error("%s is missing the clip %s" % [path, key])
	return {"model": model, "anim": anim, "skins": skins(model)}

# One duplicated material per surface, nearest-filtered like the rest of the game.
# Returned so a burn or slow glows on every surface, not just the first.
static func skins(model: Node) -> Array:
	var out: Array = []
	for n in model.find_children("*", "MeshInstance3D", true, false):
		var mi := n as MeshInstance3D
		if mi.mesh == null: continue
		for s in mi.mesh.get_surface_count():
			var m := mi.mesh.surface_get_material(s)
			if not m is BaseMaterial3D: continue
			var dup := (m as BaseMaterial3D).duplicate()
			dup.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			mi.set_surface_override_material(s, dup)
			out.append(dup)
	return out
