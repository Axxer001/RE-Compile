extends Node
# GPU render suite (needs a real renderer, not --headless).
#   godot --path . res://tests/render/baseline.tscn -- --out=<dir>
# Captures the first-person view and checks it changes for the right reasons.
# Emits one `RESULT {json}` line.

const OutfitBuilderRef = preload("res://scripts/actors/outfit_builder.gd")
const SUITE := "render"
var checks := 0
var failures: Array[String] = []
var captures: Array[String] = []
var out_dir := "res://"
var fixture := ""

func check(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)
		printerr("FAIL: ", label)

func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_dir = arg.trim_prefix("--out=").replace("\\", "/").trim_suffix("/") + "/"
		elif arg.begins_with("--fixture="):
			fixture = arg.trim_prefix("--fixture=")
	if DisplayServer.get_name() == "headless":
		failures.append("render suite requires a GPU display server, got headless")
		finish()
		return
	if fixture == "hang":
		return
	var main: Node3D = load("res://scenes/main.tscn").instantiate()
	main.external_driver = true
	main.fixed_map_seed = 7 # captures compare views: one fixed forest [R11]
	add_child(main)
	run.call_deferred(main)

func frame() -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw

func shot(name: String) -> Image:
	var img := get_viewport().get_texture().get_image()
	var path := out_dir + name
	check(img.save_png(path) == OK, "saved " + name)
	captures.append(path)
	return img

# Mean luminance over a centred box (fraction of the image).
static func luma(img: Image, frac := 0.3) -> float:
	var w := img.get_width(); var h := img.get_height()
	var x0 := int(w * (0.5 - frac / 2)); var y0 := int(h * (0.5 - frac / 2))
	var total := 0.0; var n := 0
	for y in range(y0, int(h * (0.5 + frac / 2)), 8):
		for x in range(x0, int(w * (0.5 + frac / 2)), 8):
			total += img.get_pixel(x, y).get_luminance(); n += 1
	return total / maxf(1.0, n)

# Two captures differ for a real reason: at least 20 sampled pixels change
# luminance by more than 0.06. (Exact comparison is useless since M3: the lo-fi
# film grain changes every frame, which made every such check pass.)
const DISTINCT_LUMA := 0.025
static func distinct(a: Image, b: Image) -> bool:
	return changed_pixels(a, b) > 20

# Samples (every 4 px) whose colour differs at all: the 16-bit step is below DISTINCT_LUMA.
static func exact_diff(a: Image, b: Image) -> int:
	var diff := 0
	for y in range(0, a.get_height(), 4):
		for x in range(0, a.get_width(), 4):
			if a.get_pixel(x, y) != b.get_pixel(x, y): diff += 1
	return diff

static func changed_pixels(a: Image, b: Image) -> int:
	var diff := 0
	for y in range(0, a.get_height(), 16):
		for x in range(0, a.get_width(), 16):
			if absf(a.get_pixel(x, y).get_luminance() - b.get_pixel(x, y).get_luminance()) > DISTINCT_LUMA: diff += 1
	return diff

func place(c: Node3D, at: Vector3, yaw_deg: float, pitch_deg := 0.0) -> void:
	c.player.global_position = at
	c.player.velocity = Vector3.ZERO
	c.player.yaw = deg_to_rad(yaw_deg)
	c.player.pitch = deg_to_rad(pitch_deg)
	c.player.apply_look()
	c.publish(0.0)
	var gf: Node3D = c.find_child("GrassField", true, false)
	if gf: gf.update(999) # the grass round the new spot, built at once (in play it grows in over a few frames)

func _esc_event() -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_ESCAPE; e.keycode = KEY_ESCAPE; e.pressed = true
	return e

func run(c: Node3D) -> void:
	var colour16_on: bool = c.art.post.get_shader_parameter("colour16")
	c.art.set_grain(0.0) # deterministic captures (grain is checked on its own below)
	c.art.set_colour16(false) # comparisons at full colour depth: 16-bit merges the darkest night tones (checked on its own below)
	var env_r: Environment = (c.find_children("*", "WorldEnvironment", true, false)[0] as WorldEnvironment).environment
	if env_r.sky and env_r.sky.sky_material is ShaderMaterial: (env_r.sky.sky_material as ShaderMaterial).set_shader_parameter("wind_speed", Vector2.ZERO) # still clouds: deterministic captures
	await frame()
	# The Dark Forest from the camp, looking north up the path [P7].
	c.park_enemies()
	place(c, c.spawn.at, 0.0)
	await frame()
	var room := shot("fp-camp.png")
	var stats := {"min": 1.0, "max": 0.0}
	for y in range(0, room.get_height(), 24):
		for x in range(0, room.get_width(), 24):
			var l := room.get_pixel(x, y).get_luminance()
			stats.min = minf(stats.min, l); stats.max = maxf(stats.max, l)
	# Film grain animates every frame, so comparisons run with it off (set in
	# run() below). Here: grain on -> consecutive frames differ; grain off ->
	# two captures of the same view are identical (distinct() is meaningful).
	c.art.set_grain(0.05)
	await frame()
	var g1 := shot("fp-grain-1.png")
	await frame()
	await frame()
	var g2 := shot("fp-grain-2.png")
	check(changed_pixels(g1, g2) > 20, "film grain animates when on (%d changed samples)" % changed_pixels(g1, g2))
	c.art.set_grain(0.0)
	var flames: Node3D = c.find_child("CampFlames", true, false)
	if flames: flames.visible = false # its flames animate every frame; the stills test the screen pipeline
	var still_fire: OmniLight3D = c.find_child("CampFire", true, false)
	var flick: Variant = still_fire.get_meta("flicker", false) if still_fire else false
	if still_fire: still_fire.set_meta("flicker", false) # and its light flickers (the fire stones show it)
	await frame()
	var still1 := shot("fp-still-1.png")
	await frame()
	var still2 := shot("fp-still-2.png")
	if flames: flames.visible = true
	if still_fire: still_fire.set_meta("flicker", flick)
	check(changed_pixels(still1, still2) == 0, "grain off: an unchanged view captures identically (%d changed)" % changed_pixels(still1, still2))
	check(stats.max - stats.min > 0.15, "first-person view has real contrast (%.2f..%.2f)" % [stats.min, stats.max])
	# Cultivate from the first person: a soft cyan aura by the hands, never a screen-filling flash.
	place(c, Vector3(75, 0, 55), 0.0)
	c.pcombat.cultivate_until = -INF
	await frame()
	var cult_off := shot("fp-cultivate-off.png")
	c.pcombat.cultivate_until = c.session.run.time + 5.0
	c.publish(0.0)
	for i in 12: await frame() # the motes spawn over a few frames
	var cult_on := shot("fp-cultivate.png")
	var ae: Node3D = c.pcombat.aura_embers
	var cult_dbg := "vis %s inside %s glob %s emit %s cam %s" % [ae.visible, ae.is_visible_in_tree(), ae.global_position, ae.find_children("*", "GPUParticles3D", true, false).map(func(g): return [g.emitting, g.amount, g.visible]), c.player.camera.global_position]
	var covered: int = changed_pixels(cult_on, cult_off)
	var total: int = (cult_on.get_width() / 16) * (cult_on.get_height() / 16)
	c.pcombat.cultivate_until = -INF
	c.publish(0.0)
	check(covered > 0 and covered < total * 0.12, "Cultivate's aura changes %d of %d screen samples (under 12%%: it does not obscure the view) %s" % [covered, total, cult_dbg if covered == 0 else ""])

	# The three Rank E spells [2026-11-14]: their effects are drawn.
	var pcs: Node3D = c.pcombat
	var sp: RefCounted = c.spells
	c.park_enemies()
	place(c, Vector3(75, 0, 55), 0.0)
	await frame()
	var calm := shot("fp-spell-calm.png")
	pcs.equip("spell_1", c.session.grimoire.page("dragons_breath"))
	pcs.equip("spell_2", c.session.grimoire.page("firefly"))
	pcs.equip("spell_3", c.session.grimoire.page("explosion"))
	pcs.mp = pcs.max_mp(c.session.run.time)
	sp.start_breath(c.session.grimoire.page("dragons_breath"), "spell_1", c.session.run.time)
	var t_b := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t_b < 1200: await frame() # a full flame lifetime: the cone at its steady state
	var breath_shot := shot("fp-dragons-breath.png")
	# Side view: the flames already in the air stay where they are (world space).
	for gp in c.find_children("*", "GPUParticles3D", true, false):
		if gp.get_parent() != null and String(gp.get_parent().name) == "DragonsBreath": gp.emitting = false
	place(c, Vector3(75 + 14, 0, 55 - 9), 90.0) # 14 m east of the cone's middle, looking west across it
	await frame()
	shot("fp-dragons-breath-side.png")
	var covered_b: int = changed_pixels(calm, breath_shot)
	var total_b: int = (calm.get_width() / 16) * (calm.get_height() / 16)
	sp.reset()
	var foe: CharacterBody3D = c.enemies.values()[0]
	foe.reset_to(Vector3(75, 0, 43), 0.0)
	foe.inert = true
	await frame()
	sp.start_firefly(c.session.grimoire.page("firefly"), c.session.run.time)
	for i in 8:
		sp.tick(1.0 / 60.0, c.session.run.time + i / 60.0)
		await frame()
	var firefly_shot := shot("fp-firefly.png")
	sp.reset()
	c.park_enemies()
	c.vfx.cataclysm(Vector3(75, 0, 15), c.session.run.time) # 40 m up the path
	for i in 12: await frame()
	var cata_shot := shot("fp-explosion.png")
	c.vfx.reset()
	check(covered_b < total_b * 0.5, "Dragon's Breath leaves most of the view clear (%d of %d samples change)" % [covered_b, total_b])
	check(distinct(calm, breath_shot) and distinct(calm, firefly_shot) and distinct(calm, cata_shot), "Dragon's Breath, Firefly's missiles and Explosion's 50 m eruption are drawn")

	# The Phoenix set: Flight's 50 m landing ring from 30 m up, Call's three areas.
	c.park_enemies()
	var sv: RefCounted = c.spells
	var ring_at := Vector3(75, 0, 70)
	var big: Node3D = c.vfx.ring(ring_at, sv.FLIGHT.ring_r, Color(1.0, 0.45, 0.1))
	place(c, ring_at + Vector3(0, 30, 0), 0.0, -60.0)
	await frame()
	await frame()
	var phx_shot := shot("fp-phoenix-ring.png")
	big.visible = false
	await frame()
	var ring_none := shot("fp-phoenix-ring-off.png")
	big.queue_free()
	var areas: Array = []
	for off in [Vector3(-8, 0, -12), Vector3(0, 0, -18), Vector3(9, 0, -13)]: areas.append(c.vfx.ring(Vector3(75, 0, 70) + off, sv.CALL.area_r, Color(1.0, 0.35, 0.1)))
	place(c, Vector3(75, 0, 72), 0.0, -18.0)
	await frame()
	await frame()
	var call_shot := shot("fp-phoenix-call-rings.png")
	for n in areas: n.queue_free()
	check(distinct(phx_shot, ring_none) and distinct(ring_none, call_shot), "Flight's landing ring and Call's area rings are drawn")

	# The Gambler set [2026-11-14]: Heads' coin, Tails' giant coin and its burst,
	# Pocket Change and Heavy Pockets on enemies, the die, the Jackpot, Addiction.
	c.park_enemies()
	var gb: RefCounted = c.gambler
	var gs_at := Vector3(75, 0, 72)
	place(c, gs_at, 0.0, -4.0)
	await frame()
	var g_calm := shot("fp-gambler-calm.png")
	var eye_g: Vector3 = c.player.camera.global_position
	var fwd_g: Vector3 = -c.player.camera.global_transform.basis.z
	var heads_c: Dictionary = gb.throw("heads", eye_g + fwd_g * 1.5 + Vector3(0.15, -0.15, 0), fwd_g, 1.0, 100.0, null, c.session.run.time)
	var tails_c: Dictionary = gb.throw("tails", eye_g + fwd_g * 7.0 + Vector3(-1.5, -0.5, 0), fwd_g, 1.0, 100.0, eye_g + fwd_g * 30.0, c.session.run.time)
	for i in 4:
		gb.tick(1.0 / 60.0, c.session.run.time + i / 60.0)
		await frame()
	var coins_shot := shot("fp-gambler-coins.png")
	check(heads_c.node != null and tails_c.node != null and distinct(g_calm, coins_shot), "Heads' coin and Tails' giant coin are drawn in flight")
	gb.reset()
	c.vfx.tails_blast(gs_at + Vector3(0, 0, -22), c.session.run.time)
	for i in 10: await frame()
	var tails_shot := shot("fp-gambler-tails.png")
	c.vfx.reset()
	var gfoes: Array = c.enemies.values().slice(0, 2)
	gfoes[0].reset_to(gs_at + Vector3(-2.5, 0, -7), 180.0)
	gfoes[1].reset_to(gs_at + Vector3(2.5, 0, -7), 180.0)
	for f in gfoes: f.inert = true
	await frame()
	var foes_plain := shot("fp-gambler-foes.png")
	c.effects.apply(gfoes[0].enemy_id, "Pocket Change", 10.0, c.session.run.time, "player", 100.0)
	c.effects.apply(gfoes[1].enemy_id, "Heavy Pockets", 10.0, c.session.run.time, "player", 100.0)
	c.publish(0.0)
	for i in 6: await frame()
	var marks_shot := shot("fp-gambler-pocket-heavy.png")
	check(distinct(g_calm, tails_shot) and exact_diff(foes_plain, marks_shot) > 30 and gfoes[0].has_meta("gfx_pocket_change") and gfoes[0].get_meta("gfx_pocket_change").visible and gfoes[1].has_meta("gfx_pile") and gfoes[1].get_meta("gfx_pile").visible, "Tails' gold burst, Pocket Change over an enemy, Heavy Pockets' ring and coin pile at the feet are drawn")
	c.effects.clear_target(gfoes[0].enemy_id)
	c.effects.clear_target(gfoes[1].enemy_id)
	c.park_enemies()
	c.publish(0.0)
	await frame()
	var hud_g: CanvasLayer = c.hud
	var r6: Dictionary = gb.roll(c.session.run.time, 6)
	gb.land(c.session.run.time)
	hud_g.die.update(r6, r6.time + 0.3) # mid-tumble
	await frame()
	var tumble_shot := shot("fp-gambler-die-tumble.png")
	c.publish(0.0)
	hud_g.die.update(r6, r6.time + 1.2) # settled on the 6
	await frame()
	var die_shot := shot("fp-gambler-die-jackpot.png")
	var die_rect: Rect2 = hud_g.die.get_global_rect()
	var to_img: Vector2 = Vector2(die_shot.get_width(), die_shot.get_height()) / hud_g.die.get_viewport_rect().size # HUD units -> capture pixels
	die_rect = Rect2(die_rect.position * to_img, die_rect.size * to_img)
	var die_px := 0
	for y in range(int(die_rect.position.y), int(die_rect.end.y), 4):
		for x in range(int(die_rect.position.x), int(die_rect.end.x), 4):
			if die_shot.get_pixel(x, y).get_luminance() > 0.7: die_px += 1
	check(hud_g.die.visible and die_px > 40 and distinct(tumble_shot, die_shot) and hud_g.gold_flash.visible, "Let it Ride's die is drawn on the HUD (%d ivory samples), tumbles, then lands; the Jackpot flashes gold" % die_px)
	gb.roll(c.session.run.time, 1)
	gb.land(c.session.run.time)
	gb.roll(c.session.run.time, 2)
	gb.land(c.session.run.time)
	c.session.run.time += 1.0 # past the gold flash
	c.publish(0.0)
	for i in 3: await frame()
	var addict_shot := shot("fp-gambler-addiction.png")
	var sat := func(img: Image) -> float:
		var tot := 0.0
		var n := 0
		for y in range(0, img.get_height(), 16):
			for x in range(0, img.get_width(), 16):
				var px := img.get_pixel(x, y)
				tot += maxf(px.r, maxf(px.g, px.b)) - minf(px.r, minf(px.g, px.b))
				n += 1
		return tot / maxf(1.0, n)
	var purple := func(img: Image) -> float:
		var tot := 0.0
		var n := 0
		for y in range(0, img.get_height(), 16):
			for x in range(0, img.get_width(), 16):
				var px := img.get_pixel(x, y)
				tot += px.b - px.g
				n += 1
		return tot / maxf(1.0, n)
	check(hud_g.addict_tint.visible and purple.call(addict_shot) > purple.call(g_calm), "Gambling Addiction tints the view purple and desaturates it (blue-green %.3f vs %.3f; chroma %.3f vs %.3f)" % [purple.call(addict_shot), purple.call(g_calm), sat.call(addict_shot), sat.call(g_calm)])
	gb.reset()
	c.notices.clear() # the rolls' notices (the sky check below counts bright points)
	c.publish(0.0)
	await frame()
	# Every Gambler buff aura at once [Sir, 2026-11-14]: they must leave the first-person view clear.
	place(c, gs_at, 0.0, 0.0)
	await frame()
	var aura_off := shot("fp-gambler-auras-off.png")
	for k in ["gamblers_high", "jackpot", "all_in", "all_in_won"]: c._player_gfx(k, true)
	for i in 8: await frame()
	var aura_on := shot("fp-gambler-auras-on.png")
	var w_a := aura_on.get_width()
	var h_a := aura_on.get_height()
	var centre := 0
	var centre_n := 0
	for y in range(int(h_a * 0.15), int(h_a * 0.75), 8): # the view above the action bar
		for x in range(int(w_a * 0.2), int(w_a * 0.8), 8):
			centre_n += 1
			if absf(aura_on.get_pixel(x, y).get_luminance() - aura_off.get_pixel(x, y).get_luminance()) > DISTINCT_LUMA: centre += 1
	for k in ["gamblers_high", "jackpot", "all_in", "all_in_won"]: c._player_gfx(k, false)
	c.player.pitch = deg_to_rad(-60.0) # looking down at the feet, the auras show
	c.player.apply_look()
	await frame()
	var down_off := shot("fp-gambler-auras-down-off.png")
	for k in ["gamblers_high", "jackpot", "all_in", "all_in_won"]: c._player_gfx(k, true)
	for i in 8: await frame()
	var down_on := shot("fp-gambler-auras-down-on.png")
	for k in ["gamblers_high", "jackpot", "all_in", "all_in_won"]: c._player_gfx(k, false)
	check(centre < centre_n * 0.05 and distinct(down_off, down_on), "the Gambler buff auras keep the view clear (%d of %d centre samples change) and show round the feet" % [centre, centre_n])

	# The Training Field [2026-11-14]: the portal beside the camp, then the daytime field.
	var tfield: Node3D = c.training
	var TFs = tfield.get_script()
	c.park_enemies()
	place(c, TFs.FOREST_PORTAL + Vector3(-6, 0, 0), -90.0) # in the camp, facing east at the portal
	await frame()
	await frame()
	var portal_shot := shot("fp-portal.png")
	var night_l := luma(portal_shot, 0.6)
	tfield.enter()
	var views := [["fp-field-arrival.png", TFs.ARRIVE, 0.0, 0.0], ["fp-field-dummies.png", Vector3(50, 0, 188), 0.0, -3.0],
		["fp-field-range.png", Vector3(150, 0, 192), 0.0, 2.0], ["fp-field-rocks.png", Vector3(165, 0, 60), 0.0, 8.0],
		["fp-field-drills.png", Vector3(65, 0, 100), 0.0, 5.0], ["fp-field-cluster.png", TFs.CLUSTER_AT + Vector3(0, 0, 13), 0.0, -6.0]]
	var day_l := 0.0
	for v in views:
		place(c, TFs.ORIGIN + v[1], v[2], v[3])
		await frame()
		await frame()
		var img := shot(v[0])
		if v[0] == "fp-field-arrival.png": day_l = luma(img, 0.6)
	tfield.leave()
	c.park_enemies()
	check(day_l > night_l + 0.1, "the Training Field is in daylight (view luma %.3f, the forest at night %.3f)" % [day_l, night_l])

	# Phase 4: a lost page is a Fantasy Props scroll, glowing on the forest floor.
	var qs: Vector3 = c.page_spots.quick_step
	place(c, qs + Vector3(0, 0, 1.6), 0.0, -30.0)
	await frame()
	var page_shot := shot("fp-page-scroll.png")
	var pg_node: Node3D = c.page_pickups.quick_step
	pg_node.visible = false
	await frame()
	var no_page := shot("fp-page-hidden.png")
	pg_node.visible = true
	check(distinct(page_shot, no_page), "a lost page (the scroll) is visible on the forest floor")
	# Phase 3: the Binbun night sky, looking up from the camp.
	place(c, c.spawn.at, 0.0, 55.0)
	await frame()
	var sky_shot := shot("fp-sky.png")
	var bright := 0
	for y in range(sky_shot.get_height() / 9, sky_shot.get_height() / 2, 4): # the sky, below the HUD bars
		for x in range(sky_shot.get_width() / 6, sky_shot.get_width() * 5 / 6, 4):
			if sky_shot.get_pixel(x, y).get_luminance() > 0.5: bright += 1
	check(bright < 10, "no stars in the night sky (%d bright points)" % bright)
	check(luma(sky_shot, 0.6) > 0.005 and luma(sky_shot, 0.6) < 0.25, "the night sky overhead is dark but not black (luma %.3f)" % luma(sky_shot, 0.6))
	# Pixel look [Sir, 2026-11-13]: the world view at 1/3 resolution, nearest-neighbour
	# up, 16-bit colour dithered on its grid; the post layer grades the world below the HUD.
	var lo: CanvasLayer = c.lofi
	var full := Vector2i(get_viewport().get_visible_rect().size)
	var grid: Vector2 = c.art.post.get_shader_parameter("low_res")
	check(lo.viewport.size == full / c.LOFI_SHRINK and lo.container.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST and grid == Vector2(lo.viewport.size) and colour16_on and not lo.grain.visible, "pixel look: world view %s of %s, nearest filter, 16-bit dither on its grid; old grain layer off" % [lo.viewport.size, full])
	c.art.set_colour16(true)
	await frame()
	var c16a := shot("fp-colour16.png")
	c.art.set_colour16(false)
	await frame()
	var c24 := shot("fp-colour24.png")
	check(exact_diff(c16a, c24) > exact_diff(c24, c24) + 1000, "16-bit colour on: the frame differs from full depth in %d samples" % exact_diff(c16a, c24))
	check(lo.camera.global_transform.is_equal_approx(c.player.camera.global_transform) and get_viewport().disable_3d, "view camera mirrors the player camera; root 3D off")
	var art_layers: Array = c.art.find_children("*", "CanvasLayer", true, false).map(func(l): return l.layer)
	check(art_layers.size() == 1 and art_layers[0] > lo.layer and art_layers[0] < c.hud.layer and c.hud.layer < c.grimoire_panel.layer, "post layer %s sits above the world (%d) and below the HUD (%d) and panels" % [art_layers, lo.layer, c.hud.layer])
	var sunl: DirectionalLight3D = c.find_children("*", "DirectionalLight3D", true, false)[0]
	check(sunl.light_energy < 0.5 and c.lamps.size() == 1 and c.lamps[0].name == "CampFire", "night grade: weak moon (%.2f), the campfire the one practical light" % sunl.light_energy)
	# The campfire lights the camp: facing it, the view is brighter with it lit.
	var fire_l: OmniLight3D = c.lamps[0]
	place(c, c.spawn.at, 0.0, -12.0)
	await frame()
	var lit := shot("fp-campfire.png")
	fire_l.visible = false
	await frame()
	var dark := shot("fp-campfire-out.png")
	fire_l.visible = true
	check(luma(lit) > luma(dark) + 0.01, "the campfire lights the camp (%.3f lit, %.3f out)" % [luma(lit), luma(dark)])

	# Crouch lowers the eye: the same view shifts.
	place(c, c.spawn.at, 0.0)
	await frame()
	var stand := shot("fp-stand.png")
	c.player.crouching = true
	c.player._apply_height(c.player.CROUCH_HEIGHT)
	await frame()
	var low := shot("fp-crouch.png")
	check(absf(c.player.eye_position().y - 0.78) < 0.02 and distinct(stand, low), "crouched eye at 0.78 m (0.9 m hitbox [spec]) and the view drops")
	c.session.restart()

	# P3: the Blighted Sprite is a realistic-proportion body that animates (not a T-pose).
	c.park_enemies(["sprite_1"]) # one still Sprite in front of the camera
	var sh: CharacterBody3D = c.enemies["sprite_1"]
	place(c, sh.global_position + Vector3(0, 0, -2.4), 180.0, -8.0) # 2.4 m north of it, facing it
	await frame()
	var with_enemy := shot("fp-sprite.png")
	sh.visible = false
	await frame()
	var without := shot("fp-sprite-hidden.png")
	sh.visible = true
	check(distinct(with_enemy, without), "Blighted Sprite visible in the forest")
	# Its HP bar shows once it is hurt [spec P3].
	sh.health.apply(preload("res://scripts/combat/damage_packet.gd").new(95001, "test", "player", 40.0, "blast"), c.session.run.time)
	await frame()
	var hurt := shot("fp-sprite-hp-bar.png")
	check(sh.hp_bar.visible and changed_pixels(with_enemy, hurt) >= 4, "a hurt Sprite shows its HP bar (%d changed samples)" % changed_pixels(with_enemy, hurt))
	sh.health.reset()
	var sk: Skeleton3D = sh.model.find_children("*", "Skeleton3D", true, false)[0]
	var bone := sk.find_bone("pelvis")
	sh.anim.play("walk")
	sh.anim.seek(0.1, true)
	var p1 := sk.get_bone_pose_position(bone)
	sh.anim.seek(0.4, true)
	var p2 := sk.get_bone_pose_position(bone)
	check(bone >= 0 and not p1.is_equal_approx(p2), "Quaternius walk clip drives the body skeleton")
	var skin: BaseMaterial3D = OutfitBuilderRef.body_mesh(sh.model).get_surface_override_material(0)
	check(skin != null and skin.albedo_color.is_equal_approx(sh.SKIN_TINT) and skin.emission_enabled, "the Sprite wears its blighted violet skin")
	await frame()
	shot("fp-sprite-run.png")
	c.session.restart()

	# Forest views, as the player first sees them.
	c.park_enemies()
	place(c, Vector3(75.0, 0, 70.0), 0.0, -4.0) # the stones: 1/2/3 m ledges, from the south
	await frame()
	var stones := shot("fp-stones.png")
	place(c, Vector3(75.0, 0, 108.0), 0.0, 2.0) # the crossing and the paths out of it
	await frame()
	var crossing := shot("fp-crossing.png")
	place(c, Vector3(45.0, 0, 50.0), 0.0, 0.0) # the north-west glade (Ring of Fire)
	await frame()
	shot("fp-ring-glade.png")
	place(c, Vector3(90.0, 0, 115.0), -60.0, 4.0) # off the path, into the trees
	await frame()
	shot("fp-deep-trees.png")
	# Settings menu: the pause menu and the settings panel draw above the art post layer.
	var pm: CanvasLayer = c.pause_menu
	c._unhandled_key_input(_esc_event())
	await frame()
	var menu_shot := shot("fp-pause-menu.png")
	pm.buttons.settings.pressed.emit()
	await frame()
	var settings_shot := shot("fp-settings.png")
	pm.panel.show_tab("graphics")
	await frame()
	var gfx_shot := shot("fp-settings-graphics.png")
	check(distinct(settings_shot, gfx_shot), "the Settings panel's Graphics tab is drawn")
	pm.panel.show_tab("controls")
	var post_layers: Array = c.art.find_children("*", "CanvasLayer", true, false).map(func(l): return l.layer)
	check(pm.visible and pm.layer > post_layers.max() and pm.panel.layer > pm.layer and distinct(menu_shot, settings_shot), "pause menu (layer %d) and settings panel (%d) drawn above the post layer %s" % [pm.layer, pm.panel.layer, post_layers])
	pm.back(); pm.back()
	await frame()
	check(distinct(stones, crossing) and luma(stones) > 0.02 and luma(crossing) > 0.02, "forest clearings render lit and distinct (%.3f, %.3f)" % [luma(stones), luma(crossing)])
	c.session.restart()

	# P7 HUD: bars, action bar and mission drawn over the world; the death panel centred.
	c.park_enemies()
	place(c, c.spawn.at, 0.0)
	c.hud.visible = false
	await frame()
	var no_hud := shot("fp-no-hud.png")
	c.hud.visible = true
	c.player.health.hp = 55.0
	c.publish(0.0)
	await frame()
	var with_hud := shot("fp-hud.png")
	var screen := get_viewport().get_visible_rect().size
	var bar_r := Rect2(c.hud.hp_bar.back.global_position, c.hud.hp_bar.back.size)
	var ab: Control = c.hud.find_child("ActionBar", true, false)
	var ab_r := Rect2(ab.global_position, ab.size)
	check(changed_pixels(no_hud, with_hud) >= 10 and Rect2(Vector2.ZERO, screen).encloses(bar_r) and Rect2(Vector2.ZERO, screen).encloses(ab_r) and ab_r.position.y > screen.y * 0.75, "the HUD draws on screen: bars top-left %s, action bar bottom-centre %s" % [bar_r, ab_r])
	c.player.health.reset()
	c.show_death_panel()
	await frame()
	shot("fp-death-panel.png")
	var bx: Control = c.death_panel.box
	var boff: Vector2 = (bx.position + bx.size * 0.5) - screen * 0.5
	check(boff.length() < 4.0 and Rect2(Vector2.ZERO, screen).encloses(Rect2(bx.position, bx.size)), "death panel centred on screen (off by %s)" % boff)
	c.death_panel.hide_panel()
	c.session.restart()

	# Fire zones (the base for fireball AOE and Burn) light the floor.
	c.park_enemies()
	place(c, Vector3(75, 0, 55), 0.0)
	c.player.pitch = deg_to_rad(-25.0) # looking down at the floor where the fire goes
	c.player.apply_look()
	await frame()
	var bare := shot("fp-unarmed.png")
	c.hazards._ignite(Vector3(75, 0, 53), c.session.run.time, {"targets": []})
	c.publish(0.0)
	await frame()
	var fire := shot("fp-fire.png")
	check(luma(fire) > luma(bare) + 0.01, "a fire zone lights the floor (%.3f -> %.3f)" % [luma(bare), luma(fire)])
	c.session.restart()

	# P2: a fireball in flight is drawn and lights its surroundings; a special's burst too.
	c.park_enemies()
	place(c, Vector3(75, 0, 55), 0.0)
	await frame()
	var clear_view := shot("fp-no-fireball.png")
	var cam: Camera3D = c.player.camera
	var fwd := -cam.global_transform.basis.z
	c.projectiles.launch("basic", cam.global_position + fwd * 3.0, fwd, {"damage": 0.0})
	await frame()
	var fb := shot("fp-fireball.png")
	check(distinct(clear_view, fb) and luma(fb) > luma(clear_view) + 0.005, "a basic fireball is drawn ahead (%.3f -> %.3f)" % [luma(clear_view), luma(fb)])
	await frame()
	await frame()
	shot("fp-fireball-trail.png") # the trail behind it
	c.projectiles.reset()
	c.projectiles._burst(cam.global_position + fwd * 6.0 + Vector3(0, -1.2, 0), "special", c.session.run.time)
	await frame()
	var burst := shot("fp-special-burst.png")
	c.projectiles.tick(0.0, c.session.run.time + 0.3, {"targets": []}) # the light flash is over
	c.vfx.tick(c.session.run.time + 0.3)
	await frame()
	var scorch := shot("fp-scorch.png")
	check(c.vfx.live_decals() >= 1 and distinct(clear_view, scorch), "a blast leaves a scorch mark on the ground")
	check(luma(burst) > luma(clear_view) + 0.02, "a special's burst lights the scene (%.3f -> %.3f)" % [luma(clear_view), luma(burst)])
	c.projectiles.reset()
	# P4: Ring of Fire orbs circle the player (an orb in front of the camera at this phase).
	var pl: CharacterBody3D = c.player
	var rg: Dictionary = c.projectiles.summon_ring(func() -> Vector3: return pl.global_position, c.session.run.time, 10.0, 0.0)
	c.player.pitch = deg_to_rad(-15.0)
	c.player.apply_look()
	c.projectiles.tick(0.0, c.session.run.time + 0.6, {"targets": []}) # place the orbs (one ends up ahead)
	await frame()
	var ring_shot := shot("fp-ring-of-fire.png")
	check(distinct(clear_view, ring_shot) and luma(ring_shot) > luma(clear_view) + 0.005, "Ring of Fire orbs are drawn round the player (%.3f -> %.3f)" % [luma(clear_view), luma(ring_shot)])
	c.projectiles.reset()
	# The full first-person body: looking down shows it; hidden, the same view differs.
	var body: Node3D = c.player.get_node_or_null("Body")
	place(c, Vector3(75, 0, 55), 0.0, -75.0)
	await frame()
	var with_body := shot("fp-body-down.png")
	if body: body.visible = false
	await frame()
	var no_body := shot("fp-body-hidden.png")
	if body: body.visible = true
	check(body != null and distinct(with_body, no_body), "looking down shows the player's own body")
	c.player.pitch = 0.0
	c.player.apply_look()
	# P5: the Grimoire overlay (Tab), browse and Code Assembly views, centred and on screen.
	c.session.grimoire.find("quick_step")
	c.session.handle_action("grimoire")
	await frame()
	await frame()
	shot("fp-grimoire-contents.png")
	c.grimoire_panel.select_page("scorch_and_burn")
	await frame()
	await frame()
	var gshot := shot("fp-grimoire.png")
	for lp in ["dragons_breath", "quick_step"]: # the lesson and its breakdown, scrolled into view
		c.grimoire_panel.select_page(lp)
		await frame()
		await frame()
		var pb: ScrollContainer = c.grimoire_panel.panel.find_child("PageBody", true, false)
		if pb: pb.scroll_vertical = int(pb.get_v_scroll_bar().max_value)
		await frame()
		shot("fp-lesson-%s.png" % lp)
	c.grimoire_panel.select_page("scorch_and_burn")
	await frame()
	await frame()
	var gpn: Control = c.grimoire_panel.panel
	var scr := Vector2(get_viewport().get_visible_rect().size)
	var grect := Rect2(gpn.position, gpn.size)
	check(c.grimoire_panel.visible and distinct(clear_view, gshot) and Rect2(Vector2.ZERO, scr).encloses(grect), "the Grimoire draws on screen (%s in %s)" % [grect, scr])
	c.grimoire_panel.start_assembly("quick_step")
	await frame()
	await frame()
	var ashot := shot("fp-code-assembly.png")
	grect = Rect2(gpn.position, gpn.size)
	check(distinct(gshot, ashot) and Rect2(Vector2.ZERO, scr).encloses(grect), "the Code Assembly view draws on screen (%s)" % grect)
	c.grimoire_panel.show_tab("player_id")
	await frame()
	await frame()
	var id_front := shot("fp-player-id.png")
	c.grimoire_panel.flip_card()
	await frame()
	await frame()
	var id_back := shot("fp-player-id-back.png")
	var cf: Control = c.grimoire_panel.panel.find_child("CardFace", true, false)
	check(cf != null and distinct(id_front, id_back) and Rect2(Vector2.ZERO, scr).encloses(Rect2(cf.global_position, cf.size)) and c.grimoire_panel.panel.find_child("StatTable", true, false) != null, "the Player ID card flips: front (portrait, records) and back (the stats table), on screen")
	c.grimoire_panel.flip_card()
	c.session.stats.unspent = 0
	c.grimoire_panel.start_chant("magic_pow")
	await frame()
	await frame()
	var cshot := shot("fp-spell-chant.png")
	grect = Rect2(gpn.position, gpn.size)
	check(c.grimoire_panel.mode == "chant" and distinct(ashot, cshot) and Rect2(Vector2.ZERO, scr).encloses(grect), "the Spell Chant view draws on screen (%s)" % grect)
	c.session.handle_action("grimoire")
	c.session.restart()
	c.session.restart()

	# The Effects list on T, with a buff on: its icon sits in a 48 px tile.
	c.pcombat.ready_at.erase("skill_1")
	c.pcombat.use_slot("skill_1", Vector2.ZERO, c.session.run.time)
	c.session.handle_action("effects_tab")
	c.publish(0.0)
	await frame()
	await frame()
	shot("fp-effects-t.png")
	var tile: Control = c.effects_panel.list.find_child("Tile", true, false)
	check(tile != null and tile.size.x <= 52.0 and tile.size.y <= 52.0, "the T panel's icon draws at its 48 px tile (%s)" % (str(tile.size) if tile else "none"))
	c.session.handle_action("effects_tab")
	c.session.restart()

	# The Sprites are posed at level start (never a T-pose).
	check(c.enemies.values().all(func(e): return e.anim.is_playing()), "every Sprite starts the level posed by an animation")
	c.session.restart()
	finish()

func finish() -> void:
	if fixture == "missing-pass":
		get_tree().quit(0)
		return
	if fixture == "fail":
		check(false, "injected fixture failure")
	var status := "PASS" if failures.is_empty() else "FAIL"
	print("RESULT ", JSON.stringify({"suite": SUITE, "status": status, "checks": checks, "failures": failures, "captures": captures}))
	get_tree().quit(0 if failures.is_empty() else 1)
