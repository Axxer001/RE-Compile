extends SceneTree
# Headless probe for the hostile asset swap [2026-11-24]. Builds the three real
# actors, checks the replacement model and every clip the actors' _animate() asks
# for (name, loop mode, length), resolves every animation track against the
# imported skeleton, plays each clip, then checks death and pooled reuse.
#   godot --headless --path . -s res://tests/simulation/probe_hostile_models.gd
# Prints CHECK FAIL lines plus one RESULT line; exit code 1 on any failure.

const Sprite = preload("res://scripts/actors/blighted_sprite.gd")
const Ghoul = preload("res://scripts/actors/forest_ghoul.gd")
const Mortus = preload("res://scripts/actors/kostas_mortus.gd")
const HostileModels = preload("res://scripts/actors/hostile_models.gd")
const DamagePacket = preload("res://scripts/combat/damage_packet.gd")

var failures: Array[String] = []
var checks := 0

func check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		failures.append(what)
		print("CHECK FAIL: ", what)

# Every track must land on a real node and, for bones, a real bone.
func tracks_resolve(anim: AnimationPlayer, key: String) -> String:
	var a: Animation = anim.get_animation(key)
	var root: Node = anim.get_node(anim.root_node)
	if root == null:
		return "no root node"
	for t in a.get_track_count():
		var path: NodePath = a.track_get_path(t)
		var node: Node = root.get_node_or_null(NodePath(path.get_concatenated_names()))
		if node == null:
			return "track %d: no node at %s" % [t, path]
		if path.get_subname_count() > 0 and node is Skeleton3D:
			if (node as Skeleton3D).find_bone(StringName(path.get_subname(0))) < 0:
				return "track %d: no bone %s" % [t, path.get_subname(0)]
	return ""

func probe(actor: CharacterBody3D, kind: String, keys: Array, model_path: String, forbidden: String) -> void:
	root.add_child(actor)
	actor.setup(kind + "_probe", Vector3.ZERO, 0.0)
	var model: Node3D = actor.model
	check(model != null and model.name == "Model", "%s: replacement model instanced" % kind)
	check(actor.anim != null, "%s: AnimationPlayer found" % kind)
	if actor.anim == null:
		return
	check(model.find_children("*", "MeshInstance3D", true, false).size() > 0, "%s: model has a skinned mesh" % kind)
	check(model.find_children("*", "Skeleton3D", true, false).size() == 1, "%s: exactly one skeleton" % kind)
	var old := 0
	for m in model.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (m as MeshInstance3D).mesh
		if mesh != null and "quaternius" in mesh.resource_path:
			old += 1
	check(old == 0, "%s: no Quaternius mesh rendered" % kind)
	check(model.find_children("*", forbidden, true, false).is_empty(), "%s: no '%s' left from the old builder" % [kind, forbidden])
	for key in keys:
		if not actor.anim.has_animation(key):
			check(false, "%s: clip '%s' bound" % [kind, key])
			continue
		var a: Animation = actor.anim.get_animation(key)
		check(a.get_length() > 0.0, "%s: clip '%s' has length %.2fs" % [kind, key, a.get_length()])
		var bad := tracks_resolve(actor.anim, key)
		check(bad == "", "%s: clip '%s' tracks resolve%s" % [kind, key, (" (" + bad + ")") if bad != "" else ""])
		actor.anim.play(key, 0.0)
		check(actor.anim.current_animation == key, "%s: clip '%s' plays" % [kind, key])
	check(actor.health != null, "%s: health component built" % kind)
	# Death, then pooled reuse: state, pose, speed, visibility and collision return.
	actor.health.apply(DamagePacket.new(1, "probe", "player", 1e9, "melee"), 0.0)
	check(actor.state == 5 and actor.anim.current_animation == "death", "%s: death clip plays on a lethal hit" % kind)
	actor.reset_to(Vector3(2, 0, 2), 90.0)
	check(actor.state == 0 and actor.anim.current_animation == "idle", "%s: reset returns to idle" % kind)
	check(is_equal_approx(actor.anim.speed_scale, 1.0), "%s: reset restores playback speed" % kind)
	check(actor.visible and not (actor.get_node("Shape") as CollisionShape3D).disabled, "%s: reset restores visibility and collision" % kind)
	check(actor.anim.get_animation("death").loop_mode == Animation.LOOP_NONE, "%s: death does not loop" % kind)
	for loopy in ["idle", "stride" if kind == "mortus" else "walk"]:
		if actor.anim.has_animation(loopy):
			check(actor.anim.get_animation(loopy).loop_mode == Animation.LOOP_LINEAR, "%s: '%s' loops" % [kind, loopy])
	actor.free()

# Deferred: the actors read global transforms in setup(), which needs a live tree.
func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	probe(Sprite.new(), "sprite", ["idle", "walk", "run", "strike", "death", "pounce_start", "air", "climb"], HostileModels.SPRITE_PATH, "Outfit_")
	probe(Ghoul.new(), "ghoul", ["idle", "walk", "jog", "climb", "draw", "aim", "shoot", "death"], HostileModels.GHOUL_PATH, "BowHand")
	probe(Mortus.new(), "mortus", ["idle", "stride", "charge", "run", "rush", "strike", "impact", "death"], HostileModels.MORTUS_PATH, "Eyes")

	var status := "PASS" if failures.is_empty() else "FAIL"
	print("RESULT ", JSON.stringify({"status": status, "checks": checks, "failures": failures}))
	quit(0 if failures.is_empty() else 1)
