extends Node
## Probe [Sir, 2026-11-22 bug: bamboo with its tops at eye level]: drives Map 1 through
## several fields per seed (exits on every edge) and measures every bamboo foot against
## the ground under it. Measurements only.
##   godot --headless --path . res://tests/simulation/probe_bamboo_feet.tscn

const World = preload("res://scripts/world/map1_world.gd")
const WALLS := ["wall", "field_edge", "no_return", "seal_wall", "exit_closed", "camp_wall", "exit_hedge", "frame"]
var c: Node3D

func _ready() -> void:
	c = load("res://scenes/main.tscn").instantiate()
	c.external_driver = true
	add_child(c)
	run.call_deferred()

func ground_under(q: Vector3) -> Variant:
	var space := c.get_world_3d().direct_space_state
	var ex: Array[RID] = []
	for i in 8:
		var rq := PhysicsRayQueryParameters3D.create(q + Vector3(0, 40, 0), q - Vector3(0, 80, 0))
		rq.exclude = ex
		var hit := space.intersect_ray(rq)
		if hit.is_empty(): return null
		var nm := String(hit.collider.name)
		if WALLS.any(func(w): return nm.begins_with(w)) or hit.collider is CharacterBody3D:
			ex.append(hit.rid)
			continue
		return hit
	return null

func scan(label: String, out: Array) -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var m = c.map1
	for mmi in m.find_children("*", "MultiMeshInstance3D", true, false):
		if not String(mmi.name) in ["Bamboo", "Treeline", "ClosedThicket"]: continue
		var par: Node3D = mmi.get_parent()
		var feet: PackedVector3Array = mmi.get_meta("feet", PackedVector3Array())
		for f in feet:
			var w: Vector3 = par.global_transform * f
			var hit = ground_under(w)
			if hit == null: continue
			var d: float = float(hit.position.y) - w.y
			if d > 10.0 and false:
				var where := ""
				for pw in m.pathways:
					if is_instance_valid(pw.node) and (pw.node == par or pw.node.is_ancestor_of(par)):
						var pr: Dictionary = World.path_project(pw.pts, w)
						where = "pathway %d from %s dir %s along %.1f gap %.1f len %.0f" % [pw.index, pw.from, str(pw.get("dir")), float(pr.along), float(pr.gap), float(pw.length)]
				out.append("%s | %s/%s foot y %.2f, ground %.2f (%s on %s) %s" % [label, par.name, mmi.name, w.y, float(hit.position.y), String(hit.collider.name), String(hit.collider.get_parent().name), where])

## What the player sees: along every pathway's lane, the floor under the player and the
## feet of stems within 12 m; a foot far below the player's floor shows its top at eye level.
func lane_scan(label: String, out: Array) -> void:
	await get_tree().physics_frame
	var m = c.map1
	var feet: Array = []
	for mmi in m.find_children("*", "MultiMeshInstance3D", true, false):
		if not String(mmi.name) in ["Bamboo", "Treeline", "ClosedThicket", "CampBamboo"]: continue
		var par: Node3D = mmi.get_parent()
		for f in (mmi.get_meta("feet", PackedVector3Array()) as PackedVector3Array): feet.append([par.global_transform * f, "%s/%s" % [par.name, mmi.name]])
	for pw in m.pathways:
		if not is_instance_valid(pw.node): continue
		var a := 0.0
		while a < float(pw.length):
			var q: Vector3 = World.path_point(pw.pts, a)
			var hit = ground_under(q)
			if hit != null:
				var fy: float = float(hit.position.y)
				for ft in feet:
					var w: Vector3 = ft[0]
					if Vector2(w.x - q.x, w.z - q.z).length() < 12.0 and fy - w.y > 15.0:
						out.append("%s | lane of pathway %d (%s, dir %s) at %.0f m: floor %.1f, a stem of %s has its foot at %.1f (%.1f m lower), %.1f m away" % [label, pw.index, pw.from, str(pw.get("dir")), a, fy, ft[1], w.y, fy - w.y, Vector2(w.x - q.x, w.z - q.z).length()])
						break
			a += 3.0

func run() -> void:
	var m = c.map1
	var rng := RandomNumberGenerator.new()
	var out: Array = []
	var stages := 0
	for sd in 100:
		c.new_map(9000 + sd)
		rng.seed = sd
		await lane_scan("seed %d camp" % sd, out)
		m._unload_camp() # as 22 m into Pathway #0
		for k in 4:
			var ch: Dictionary = m.next_chunk
			if ch.is_empty(): break
			var e := Vector3(ch.entry.x, 0, ch.entry.y)
			c.player.global_position = ch.centre + e * (World.HALF - 4.0)
			m.update(c.player.global_position, 0.0)
			await lane_scan("seed %d chunk %d closed" % [sd, k], out)
			m.start_combat()
			var cnt := 2 if rng.randf() < 0.5 else 1
			var at: Vector3 = m.end_combat(c.player.global_position, cnt)
			c.player.global_position = at
			await lane_scan("seed %d chunk %d exits %d" % [sd, k, cnt], out)
			var exits: Array = m.pathways.filter(func(q): return q.get("exit", false))
			var pw: Dictionary = exits[rng.randi() % exits.size()]
			c.player.global_position = World.path_point(pw.pts, 1.5)
			m.update(c.player.global_position, 0.0)
			await lane_scan("seed %d chunk %d just taken dir %s" % [sd, k, str(pw.dir)], out)
			c.player.global_position = World.path_point(pw.pts, World.UNLOAD_M + 1.0)
			m.update(c.player.global_position, 0.0)
			await lane_scan("seed %d chunk %d exit taken dir %s" % [sd, k, str(pw.dir)], out)
			stages += 4
	print("PROBE stages %d, sunken feet %d" % [stages, out.size()])
	var shown := {}
	for line in out:
		var key: String = line.get_slice("|", 0)
		shown[key] = int(shown.get(key, 0)) + 1
		if int(shown[key]) <= 2: print("PROBE ", line)
	print("PROBE per stage: ", shown)
	get_tree().quit()
