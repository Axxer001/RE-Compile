extends Node3D
# The player's fighting: equipment (1-4), attack (LMB: click for melee and
# semi-auto, hold for automatic), reload (R), throwables (hold G
# to aim with a landing marker, release to throw; T cycles; RMB cancels).
# Dodging is the movement dash now (Shift, fps_controller.gd).
# Every action goes through the shared CombatController (one action at a time,
# costs paid at commit). The held-weapon view is presentation only.

const CombatController = preload("res://scripts/combat/combat_controller.gd")
const ItemDefinition = preload("res://scripts/items/item_definition.gd")
const WeaponView = preload("res://scripts/combat/weapon_view.gd")
const ArmsRig = preload("res://scripts/combat/arms_rig.gd")

const THROW_CLIP := 0.44   # release point after G is let go (PZ throw release 30%)
const THROW_RECOVERY := 0.5
const THROW_COST := 10.0

var world: Node3D          # main (session, player, enemies, hazards, noise)
var combat: CombatController
var view: Node3D           # WeaponView on the camera
var arms: Node3D           # ArmsRig on the camera: hands on the gun's Grip/Support markers
var planted := false       # hands planted on a ledge or wall (mantle / climb)
var attack_was := false
var reload_was := false
var dodge_was := false
var throw_was := false
var cancel_was := false
var aiming_throw := false
var throw_item := ""       # selected throwable item id
var marker: MeshInstance3D # landing preview
var drawn_id := ""         # weapon instance last seen equipped
var draw_until := 0.0      # session time the held weapon is ready

func setup(main: Node3D) -> void:
	world = main
	var p: CharacterBody3D = world.player
	combat = CombatController.new(p.health, p.endurance)
	combat.origin_fn = func() -> Vector3: return p.eye_position()
	combat.targets_fn = world.combat_targets
	combat.los_fn = world.clear_line
	combat.ray_fn = world.weapon_ray
	# Dodge motion slides along whatever it touches (floor contact must not eat it).
	combat.motion_fn = func(dir: Vector3, metres: float) -> void:
		var col := p.move_and_collide(dir * metres)
		if col != null:
			var rest := col.get_remainder().slide(col.get_normal())
			if rest.length() > 0.0001: p.move_and_collide(rest)
	combat.committed.connect(_on_commit)
	combat.hit.connect(func(_id: String, _r: String, _a: int) -> void: world.sfx.play("hit", p.eye_position() - p.camera.global_transform.basis.z * 1.2))
	p.health.died.connect(func(_pk) -> void: combat.on_death())
	view = WeaponView.new()
	p.camera.add_child(view)
	arms = ArmsRig.new()
	arms.name = "Arms"
	p.camera.add_child(arms)
	arms.visible = false
	marker = MeshInstance3D.new()
	var tm := TorusMesh.new(); tm.inner_radius = 0.25; tm.outer_radius = 0.32
	marker.mesh = tm
	var mm := StandardMaterial3D.new()
	mm.albedo_color = Color(1.0, 0.8, 0.3)
	mm.emission_enabled = true
	mm.emission = Color(0.8, 0.5, 0.1)
	marker.material_override = mm
	marker.visible = false
	world.add_child(marker)

func reset() -> void:
	combat.reset()
	attack_was = false; reload_was = false; dodge_was = false; throw_was = false; cancel_was = false
	aiming_throw = false
	throw_item = ""
	marker.visible = false
	if planted and arms != null:
		for side in ["r", "l"]: arms.release_hand(side)
	planted = false
	if view != null: view.visible = true
	drawn_id = ""
	draw_until = 0.0

func weapon() -> Resource:
	var w: RefCounted = world.session.inventory.equipped_weapon()
	return w.definition if w != null else null

func aim_dir() -> Vector3:
	return -world.player.camera.global_transform.basis.z

# Equip the n-th weapon in the bag; refused while an action is in progress.
func equip_slot(n: int) -> bool:
	var inv: RefCounted = world.session.inventory
	var id: String = inv.weapon_at(n)
	if id == "" or combat.busy(): return false
	return inv.equip(id)

func attack_action() -> Dictionary:
	var a: Dictionary = weapon().action()
	if weapon().is_ranged():
		a["instance"] = world.session.inventory.equipped_weapon()
		a["cone"] = weapon().spread_at(world.player.aim_t)
		a["head_mult"] = weapon().headshot_mult
	return a

# True while the newly equipped weapon is still being drawn.
func drawing(now: float) -> bool:
	return now < draw_until

func simulate(intent: Dictionary, delta: float, now: float) -> void:
	# Drawing: any change of the equipped weapon (keys, inventory screen,
	# pickup) starts its draw time.
	var eq: String = world.session.inventory.equipped_id
	if eq != drawn_id:
		drawn_id = eq
		var w0 := weapon()
		draw_until = now + (w0.draw_s if w0 != null else 0.0)
	_try_throw(intent.get("throw", false), intent.get("aim", false), now)
	_try_attack(intent.get("attack", false), now)
	_try_reload(intent.get("reload", false), now)
	combat.advance(delta, now)
	if aiming_throw:
		marker.visible = true
		marker.global_position = throw_landing() + Vector3(0, 0.02, 0)
	else:
		marker.visible = false

func _try_attack(down: bool, now := 0.0) -> String:
	var pressed := down and not attack_was
	attack_was = down
	var w := weapon()
	var auto: bool = w != null and w.fire_mode == "auto"
	combat.repeat = auto and down and not drawing(now)
	if auto and down and not combat.busy(): pressed = true
	if not pressed or aiming_throw: return ""
	if w != null and drawing(now): return "rejected:drawing"
	if w == null:
		world.show_notice("No weapon equipped (1-4).")
		return "rejected:unarmed"
	var r: String = combat.request(attack_action(), aim_dir())
	if r == "rejected:empty": world.show_notice("Click. Empty - press R to reload.")
	return r

func _try_reload(down: bool, now := 0.0) -> String:
	var pressed := down and not reload_was
	reload_was = down
	var w := weapon()
	if not pressed or w == null or not w.is_ranged(): return ""
	if drawing(now): return "rejected:drawing"
	var r: String = combat.request(w.reload_action(world.session.inventory.equipped_weapon(), world.session.inventory))
	match r:
		"rejected:full": world.show_notice("Magazine full.")
		"rejected:no_ammo": world.show_notice("No %s." % ItemDefinition.lookup(w.ammo_type).label)
	return r

# Dodge along the movement input (camera-relative), or backwards when still.
func _try_dodge(down: bool, move: Vector2) -> String:
	var pressed := down and not dodge_was
	dodge_was = down
	if not pressed: return ""
	var b: Basis = world.player.global_transform.basis
	var dir := (b.x * move.x - b.z * move.y) if move.length_squared() > 0.0 else b.z
	return combat.request(CombatController.DODGE, Vector3(dir.x, 0, dir.z).normalized())

# Throwables in the bag, in bag order.
func available_throwables() -> Array[String]:
	var out: Array[String] = []
	var inv: RefCounted = world.session.inventory
	for e in inv.entries:
		if inv.is_weapon(e): continue
		var id := String(e.definition.id)
		if e.definition.category == "throwable" and not id in out: out.append(id)
	return out

func cycle_throwable() -> String:
	var ids := available_throwables()
	throw_item = "" if ids.is_empty() else ids[(ids.find(throw_item) + 1) % ids.size()]
	world.show_notice("Nothing to throw." if throw_item == "" else "Throwable: %s" % ItemDefinition.lookup(throw_item).label)
	return throw_item

# Where a throw would land: along the aim up to the item's range, pulled back
# from the first wall, dropped to the floor.
func throw_landing() -> Vector3:
	var def := ItemDefinition.lookup(throw_item)
	var reach: float = def.weapon.range_tiles if def != null else 8.0
	var from: Vector3 = world.player.eye_position()
	var dir := aim_dir()
	var flat := Vector3(dir.x, 0, dir.z).normalized()
	var to := from + flat * reach * clampf(0.55 + dir.y, 0.15, 1.0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [world.player.get_rid()])
	var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
	var land: Vector3 = to if hit.is_empty() else (hit.position - flat * 0.3)
	return Vector3(land.x, 0.0, land.z)

func _try_throw(down: bool, cancel_down: bool, now: float) -> String:
	var pressed := down and not throw_was
	var released := not down and throw_was
	throw_was = down
	var cancel := cancel_down and not cancel_was
	cancel_was = cancel_down
	if cancel and (aiming_throw or (combat.phase == CombatController.Phase.WINDUP and combat.action.has("throw"))):
		if aiming_throw: aiming_throw = false
		else: combat.interrupt()
		world.show_notice("Throw cancelled.")
		return "cancelled"
	if pressed:
		var ids := available_throwables()
		if not throw_item in ids: throw_item = ids[0] if not ids.is_empty() else ""
		if throw_item == "":
			world.show_notice("Nothing to throw.")
			return "rejected:none"
		aiming_throw = true
		return "aiming"
	if released and aiming_throw:
		aiming_throw = false
		var land := throw_landing()
		var r: String = combat.request({"id": "throw", "windup": THROW_CLIP, "active": 0.0, "recovery": THROW_RECOVERY,
			"cost": THROW_COST, "throw": {"item": throw_item, "to": land}}, aim_dir())
		return r
	return ""

# Commit hooks: noise for attacks, the throw leaving the hand (spawn first,
# then take exactly one item; roll back if it cannot be taken).
func _on_commit(a: Dictionary, _id: int) -> void:
	var now: float = world.session.run.time
	if a.has("weapon"):
		world.noise.emit_noise(world.player.global_position, a.weapon.noise_radius_tiles, "attack", "player", now)
		var at: Vector3 = world.player.eye_position()
		if a.weapon.category == "ranged":
			var id := String(a.weapon.id)
			world.sfx.play("rifle" if id == "assault_rifle" else ("shotgun" if id == "shotgun" else "pistol"), at)
			world.muzzle_flash()
		else:
			world.sfx.play("swing", at)
			# Melee movement: a lunge along the aim, or a punch boost back off
			# geometry within reach.
			var reach: float = a.weapon.reach_tiles + 0.3
			var q := PhysicsRayQueryParameters3D.create(at, at + aim_dir() * reach, 1, [world.player.get_rid()])
			var hit := world.get_world_3d().direct_space_state.intersect_ray(q)
			world.player.melee_impulse(aim_dir(), hit.normal if not hit.is_empty() else Vector3.ZERO)
	if a.has("reload"):
		world.sfx.play("reload", world.player.eye_position())
	if a.has("throw"):
		var spec: Dictionary = a.throw
		var inv: RefCounted = world.session.inventory
		if inv.count(spec.item) < 1: return
		var rec: Dictionary = world.hazards.launch(spec.item, world.player.eye_position() - Vector3(0, 0.2, 0), spec.to, now)
		if inv.take_units(spec.item, 1) != 1:
			world.hazards.throws.erase(rec)
			if is_instance_valid(rec.node): rec.node.queue_free()
		var def := ItemDefinition.lookup(spec.item)
		world.noise.emit_noise(world.player.global_position, def.weapon.noise_radius_tiles * 0.3, "throw", "player", now)

# Arms show on models with Grip markers (the real guns and the knife); the
# code-built bat, katana and throwables keep their hand block. One-handed
# knife; the support hand drops away during a reload.
func _sync_arms() -> void:
	if arms == null or arms.skeleton == null: return
	# Mantle / climb: both palms planted on the ledge or wall, the gun put away.
	var contact: Dictionary = world.player.hand_contact()
	if not contact.is_empty():
		arms.visible = true
		view.visible = false
		for side in ["r", "l"]: arms.plant_hand(side, contact.point, contact.normal)
		planted = true
		return
	if planted:
		planted = false
		view.visible = true
		for side in ["r", "l"]: arms.release_hand(side)
	var gripped: bool = view.model != null and view.marker("Grip") != null
	arms.visible = gripped
	if view.model != null and view.model.get_child_count() > 0:
		(view.model.get_child(0) as Node3D).visible = not gripped # the old hand block
	if gripped and arms.view != view: arms.hold(view)
	elif not gripped and arms.view != null: arms.hold(null)
	var one_handed: bool = view.current == "knife"
	arms.set_weight("l", 0.0 if one_handed else 1.0 - view.reload_dip)

func publish() -> void:
	view.show_weapon(weapon(), throw_item if aiming_throw else "")
	view.ads_t = world.player.aim_t
	view.pose(combat, aiming_throw)
	_sync_arms() # after pose: it reads this frame's reload dip
