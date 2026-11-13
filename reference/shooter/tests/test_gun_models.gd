extends RefCounted
# Real gun models in the first-person view (assets/quaternius/guns/viewmodels):
# the pistol, rifle, shotgun and knife come from the scenes (the rest stay
# code-built); fully aimed, the Sight marker sits on the camera axis; aimed
# bob is smaller; the muzzle flash moves to the Muzzle marker; floor pickups
# keep the guns at true size.

const DT := 1.0 / 60.0
const WeaponView = preload("res://scripts/combat/weapon_view.gd")
const WeaponInstance = preload("res://scripts/items/weapon_instance.gd")

static func steps(c: Node3D, n: int) -> void:
	for i in n: c.session.step(DT)

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.restart()
	await tree.physics_frame
	var v := WeaponView.new()
	var from_scene := []
	for id in ["pistol", "assault_rifle", "shotgun", "knife", "baseball_bat", "katana"]:
		var n: Node3D = v._build(id)
		if n.has_meta("real_scale") and n.find_child("Sight", true, false) != null and n.find_child("Muzzle", true, false) != null: from_scene.append(id)
		n.free()
	v.free()
	check.call(from_scene == ["pistol", "assault_rifle", "shotgun", "knife"], "guns and the knife come from the gun-pack scenes with anchors; bat and katana stay code-built (%s)" % [from_scene])

	# In play: aim the rifle; the Sight marker lands on the camera axis.
	var keys := {}
	var saved_m: Callable = s.input.mouse_source
	s.input.mouse_source = func(b: int) -> bool: return keys.get(b, false)
	var rifle: RefCounted = WeaponInstance.create("assault_rifle", s.run).weapon
	s.inventory.upgrade_bag(12)
	s.inventory.try_add(rifle)
	s.inventory.equip(rifle.instance_id)
	steps(c, 40)
	var view: Node3D = c.pcombat.view
	var cam: Camera3D = c.player.camera
	await tree.process_frame
	keys[MOUSE_BUTTON_RIGHT] = true
	steps(c, 40)
	for i in 40: await tree.process_frame # the view springs toward its target in _process
	var sight: Marker3D = view.marker("Sight")
	var in_cam: Vector3 = cam.global_transform.affine_inverse() * sight.global_position
	check.call(sight != null and Vector2(in_cam.x, in_cam.y).length() < 0.01 and absf(-in_cam.z - WeaponView.ADS_DIST) < 0.02, "rifle aimed: the Sight sits on the camera axis %.2f m ahead (off by %.4f m)" % [-in_cam.z, Vector2(in_cam.x, in_cam.y).length()])
	# Aimed bob is smaller than hip bob.
	var dev := {}
	for t in [0.0, 1.0]:
		var w := WeaponView.new()
		w.show_weapon(null, "")
		w._settle_reset()
		w.ads_t = t
		var mx := 0.0
		for i in 180: mx = maxf(mx, w.step_feel(DT, Vector3(0, 0, -6.0), Vector3.RIGHT, true, 0.0, 0.0, 1.6).origin.distance_to(w.rest.origin))
		dev[t] = mx
		w.free()
	check.call(dev[1.0] < dev[0.0] * 0.3, "aimed bob is much smaller (%.4f vs %.4f)" % [dev[1.0], dev[0.0]])
	# Muzzle flash at the Muzzle marker.
	keys[MOUSE_BUTTON_LEFT] = true
	steps(c, 2)
	keys.erase(MOUSE_BUTTON_LEFT)
	await tree.process_frame
	var mz: Marker3D = view.marker("Muzzle")
	check.call(c.muzzle.visible and c.muzzle.global_position.distance_to(mz.global_position) < 0.05, "the muzzle flash sits at the gun's Muzzle marker (%.3f m away)" % c.muzzle.global_position.distance_to(mz.global_position))
	keys.clear()
	# Arms rig: on the rifle's Grip/Support, the old hand block hidden.
	steps(c, 30)
	for i in 6: await tree.process_frame
	var arms: Node3D = c.pcombat.arms
	var hand_block: Node3D = view.model.get_child(0)
	var er: float = arms.wrist_global("r").distance_to(arms.targets.r.global_position)
	check.call(arms.visible and arms.view == view and not hand_block.visible and er < 0.02, "rifle: arms on the gun (right wrist %.3f m from the grip), hand block hidden" % er)
	# Reload: the support hand lets go during the dip.
	rifle.magazine = 10
	s.inventory.try_add(preload("res://scripts/items/item_stack.gd").create("ammo_556", 30, s.run).stack)
	keys[KEY_R] = true
	var saved_k: Callable = s.input.key_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	steps(c, 2)
	keys.erase(KEY_R)
	steps(c, int(rifle.definition.reload_s * 0.5 / DT))
	var l_mid: float = arms.weight.l
	steps(c, int(rifle.definition.reload_s / DT))
	check.call(l_mid < 0.3 and arms.weight.l > 0.99, "reload: the support hand lets go mid-reload (weight %.2f) and comes back" % l_mid)
	s.input.key_source = saved_k
	# Mantle with the rifle out: both palms planted on the ledge, the gun put away; back on the gun after.
	var pl: CharacterBody3D = c.player
	pl.global_position = Vector3(86, 0, 43.4)
	pl.velocity = Vector3.ZERO
	pl.yaw = 0.0; pl.pitch = 0.0; pl.apply_look(); pl.reset_movement()
	await tree.physics_frame
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	steps(c, 2)
	keys[KEY_W] = true
	keys[KEY_SPACE] = true; s.step(DT); keys.erase(KEY_SPACE)
	var planted_seen := false
	var near := INF
	var edge_err := 0.0 # worst tick: the contact must stay on the edge throughout
	for i in 50:
		s.step(DT)
		await tree.process_frame
		if pl.state == pl.Move.MANTLE and c.pcombat.planted:
			planted_seen = planted_seen or (not view.visible and arms.manual.r and arms.manual.l)
			var ct: Dictionary = pl.hand_contact()
			near = minf(near, arms.targets.r.global_position.distance_to(ct.point))
			edge_err = maxf(edge_err, Vector2(ct.point.y - 1.0, ct.point.z - 43.0).length()) # the 1 m ledge's top edge (face at z 43)
		if pl.state == pl.Move.GROUND and pl.global_position.y > 0.9 and i > 10: break
	keys.erase(KEY_W)
	steps(c, 3)
	await tree.process_frame
	check.call(planted_seen and near < 0.25 and edge_err < 0.1, "mantle: hands planted on the ledge's top edge (contact %.2f m off the edge, target %.2f m from it), gun hidden" % [edge_err, near])
	check.call(view.visible and not arms.manual.r and not arms.manual.l and arms.view == view, "after the mantle: the hands are back on the gun")
	s.input.key_source = saved_k
	# Knife: one-handed. Bat: code-built, hand block, no arms.
	for wid in ["knife", "baseball_bat"]:
		var w2: RefCounted = WeaponInstance.create(wid, s.run).weapon
		s.inventory.try_add(w2)
		s.inventory.equip(w2.instance_id)
		steps(c, 30)
		for i in 3: await tree.process_frame
		if wid == "knife": check.call(arms.visible and arms.weight.l == 0.0, "knife: arms shown, one-handed (left hand free)")
		else: check.call(not arms.visible and view.model.get_child(0).visible and arms.view == null, "bat: no arms rig, the code-built hand block stays")
	s.input.mouse_source = saved_m
	# Floor pickups keep real guns at true size.
	var pk: Node3D = c.place_pickup(WeaponInstance.create("pistol", s.run).weapon, Vector3(60, 0, 50))
	var floor_model: Node3D = pk.find_child("Model", true, false)
	check.call(floor_model != null and floor_model.scale.is_equal_approx(Vector3.ONE), "a pistol on the floor is at true size (scale %s)" % [floor_model.scale if floor_model else Vector3.ZERO])
	s.restart()
	await tree.physics_frame
