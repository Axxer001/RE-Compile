extends RefCounted
# Settings > Graphics [Sir, 2026-11-14]: presets, each setting applied live,
# clamping, save/load, the Graphics tab; window, VSync and frame cap are left
# alone while a test drives the world.

const Forest = preload("res://scripts/world/dark_forest.gd")
const SettingsPanel = preload("res://scripts/ui/settings_panel.gd")

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	var st: RefCounted = s.settings
	st.reset()
	await tree.process_frame
	var g: Dictionary = st.gfx
	check.call(g.preset == "high" and int(g.pixel_scale) == 3 and bool(g.vsync) and int(g.fps_cap) == 0 and is_equal_approx(float(g.fov), 90.0) and int(g.shadows) == 2 and bool(g.volumetric_fog) and is_equal_approx(float(g.tree_distance), 40.0) and int(g.effects) == 2 and bool(g.colour16) and int(g.film_grain) == 2 and bool(g.camera_shake), "graphics defaults: High preset, pixel scale 3x, VSync on, no cap, 90 deg FOV, the game as it was")
	var win0: Vector2i = DisplayServer.window_get_size()
	var fps0: int = Engine.max_fps

	# The Low preset, applied live.
	st.set_value("gfx_preset", "low")
	await tree.process_frame
	var moon: DirectionalLight3D = c.find_child("Moon", true, false)
	var kit: Node = c.find_child("KitTrees", true, false)
	var kit_end := -1.0
	if kit:
		var gis: Array = kit.find_children("*", "GeometryInstance3D", true, false)
		if not gis.is_empty(): kit_end = (gis[0] as GeometryInstance3D).visibility_range_end
	var gf: Node = c.find_child("GrassField", true, false)
	check.call(g.preset == "low" and int(g.shadows) == 0 and not bool(g.volumetric_fog) and is_equal_approx(st.grass_distance, 20.0) and moon != null and not moon.shadow_enabled and c.vfx.lite_basic and c.projectiles.lit_max == 2 and is_equal_approx(c.vfx.particle_ratio, 0.35) and (kit == null or is_equal_approx(kit_end, 20.0)) and (gf == null or is_equal_approx(gf.fade_end, 20.0)), "Low preset: shadows off, volumetric fog off, trees and grass at 20 m, light spell effects (2 fireball lights, 35%% particles)")
	st.set_value("gfx_preset", "high")
	await tree.process_frame
	check.call(moon.shadow_enabled and is_equal_approx(moon.directional_shadow_max_distance, 50.0) and not c.vfx.lite_basic and c.projectiles.lit_max == 8 and is_equal_approx(Forest.near_end, 40.0), "High preset restores shadows (50 m), full effects and 40 m trees")
	# A quality setting changed by hand makes the preset Custom.
	st.set_value("gfx_shadows", 1)
	check.call(g.preset == "custom" and int(g.shadows) == 1 and is_equal_approx(moon.directional_shadow_max_distance, 25.0), "changing one quality setting makes the preset Custom (low shadows: 25 m)")
	# Look and display settings.
	st.set_value("gfx_pixel_scale", 2)
	st.set_value("gfx_fov", 100.0)
	st.set_value("gfx_colour16", false)
	st.set_value("gfx_film_grain", 0)
	st.set_value("gfx_camera_shake", false)
	await tree.process_frame
	var lo: CanvasLayer = c.lofi
	check.call(lo.container.stretch_shrink == 2 and is_equal_approx(c.player.tuning.fov, 100.0) and not c.art.post.get_shader_parameter("colour16") and is_equal_approx(float(c.art.post.get_shader_parameter("grain")), 0.0) and not lo.kicks_enabled, "pixel scale 2x, FOV 100, 16-bit colour off, no film grain, no camera shake: all applied at once")
	check.call(DisplayServer.window_get_size() == win0 and Engine.max_fps == fps0, "window size, VSync and frame cap are not touched while a test drives the game")
	# Clamps.
	st.set_value("gfx_pixel_scale", 9)
	st.set_value("gfx_fov", 20.0)
	st.set_value("gfx_fps_cap", 77)
	st.set_value("gfx_tree_distance", 500.0)
	check.call(int(g.pixel_scale) == 4 and is_equal_approx(float(g.fov), 70.0) and int(g.fps_cap) == 0 and is_equal_approx(float(g.tree_distance), 60.0), "out-of-range values are clamped (pixel scale 4, FOV 70, frame cap unlimited, trees 60 m)")
	# Save and load.
	st.set_value("gfx_window_mode", 1)
	st.set_value("gfx_window_size", 2)
	var path := "user://test_graphics_settings.cfg"
	check.call(st.save(path) == OK, "graphics settings save")
	var t: RefCounted = st.get_script().new()
	t.load_from(path)
	check.call(int(t.gfx.window_mode) == 1 and int(t.gfx.window_size) == 2 and int(t.gfx.pixel_scale) == 4 and t.gfx.preset == "custom" and not bool(t.gfx.camera_shake), "graphics settings round-trip through the settings file")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	# The Graphics tab.
	var panel: CanvasLayer = SettingsPanel.new()
	c.add_child(panel)
	panel.setup(st)
	panel.open()
	panel.show_tab("graphics")
	var keys := ["preset", "window_mode", "window_size", "pixel_scale", "vsync", "fps_cap", "fov", "shadows", "volumetric_fog", "tree_distance", "grass_distance", "effects", "colour16", "film_grain", "camera_shake"]
	var all_there: bool = keys.all(func(k): return panel.gfx_widgets.has(k))
	var shown: bool = panel.graphics_box.get_parent().visible and panel.controls_nodes.all(func(n): return not n.visible)
	var ob: OptionButton = panel.gfx_widgets.preset
	ob.select(1)
	ob.item_selected.emit(1) # Medium
	await tree.process_frame
	check.call(all_there and shown and g.preset == "medium" and int(g.shadows) == 1 and is_equal_approx(float(g.tree_distance), 30.0) and int(g.effects) == 1, "Settings has a Graphics tab with all 15 settings; picking Medium applies it")
	panel.show_tab("controls")
	check.call(not panel.graphics_box.get_parent().visible and panel.controls_nodes.all(func(n): return n.visible), "the Controls & Audio tab hides the graphics rows")
	panel.queue_free()
	st.reset()
	await tree.process_frame
