extends RefCounted
# Settings hookup in the running game (docs/settings-menu-plan.md): the
# session owns Settings and never loads the player's file under a test
# runner; a rebind reaches the InputRouter (both slots work); mouse look goes
# through the settings (hip, ADS, invert Y); Esc opens the pause menu, Esc in Settings goes back first, Resume
# and Restart work. Everything is put back to defaults at the end.

const DT := 1.0 / 60.0
const InputRouter = preload("res://scripts/core/input_router.gd")

static func esc() -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = KEY_ESCAPE; e.keycode = KEY_ESCAPE; e.pressed = true
	return e

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.restart()
	await tree.physics_frame
	var st: RefCounted = s.settings
	var p: CharacterBody3D = c.player
	check.call(st != null and p.settings == st and tree.current_scene != c, "the session owns Settings; under a test runner main is not the current scene, so no user file is loaded")
	check.call(is_equal_approx(st.hip, st.DEFAULT_HIP) and st.bindings == st.defaults and st.path == "", "test run uses default settings and saves nothing (path empty)")

	# A rebind reaches the router; both slots trigger the action.
	var keys := {}
	var saved_k: Callable = s.input.key_source
	s.input.key_source = func(k: int) -> bool: return keys.get(k, false)
	st.rebind("jump", 1, {"type": "key", "code": KEY_F9})
	keys[KEY_F9] = true
	var by_f9: bool = s.input.down("jump")
	keys.clear(); keys[KEY_SPACE] = true
	var by_space: bool = s.input.down("jump")
	keys.clear()
	check.call(by_f9 and by_space, "jump on Space and on its second slot (F9) after a rebind")
	var f9 := InputEventKey.new(); f9.physical_keycode = KEY_F9; f9.pressed = true
	st.rebind("grimoire", 1, {"type": "key", "code": KEY_F8})
	var f8 := InputEventKey.new(); f8.physical_keycode = KEY_F8; f8.pressed = true
	check.call(s.input.action_for_event(f8) == "grimoire", "a rebound discrete action (grimoire on F8) is recognised")
	var wheel := InputEventMouseButton.new(); wheel.button_index = MOUSE_BUTTON_XBUTTON1; wheel.pressed = true
	st.rebind("interact", 1, {"type": "mouse", "button": MOUSE_BUTTON_XBUTTON1})
	check.call(s.input.action_for_event(wheel) == "interact", "a mouse side button can be bound")
	# Tab toggles the Grimoire overlay in the router (the session shows it once the world has show_grimoire, P5).
	var tab := InputEventKey.new(); tab.physical_keycode = KEY_TAB; tab.pressed = true
	var g_open: String = s.input.press(s.input.action_for_event(tab))
	var g_ctx: bool = s.input.context == s.input.Context.OVERLAY and s.input.overlay == "grimoire" and not s.input.look_enabled()
	var g_close: String = s.input.press("grimoire")
	check.call(g_open == "grimoire_opened" and g_ctx and g_close == "overlay_closed" and s.input.context == s.input.Context.GAMEPLAY, "Tab opens the Grimoire overlay (look off) and Tab again closes it")
	st.reset()
	check.call(not s.input.down("jump") and s.input.keys.get("jump") == KEY_SPACE and s.input.action_for_event(f9) == "", "reset: the router is back on the project bindings")

	# Mouse wheel and extra buttons [Sir: "bind mouse wheel and additional mouse buttons"].
	var notch := func(btn: int) -> void:
		var e := InputEventMouseButton.new(); e.button_index = btn; e.pressed = true
		c._unhandled_input(e)
	st.rebind("jump", 1, {"type": "mouse", "button": MOUSE_BUTTON_WHEEL_DOWN})
	notch.call(MOUSE_BUTTON_WHEEL_DOWN)
	var first: bool = s.input.sample().jump
	var second: bool = s.input.sample().jump
	check.call(first and not second, "jump on Wheel Down: one notch is a one-tick press")
	notch.call(MOUSE_BUTTON_WHEEL_DOWN); notch.call(MOUSE_BUTTON_WHEEL_DOWN)
	var two: Array = [s.input.sample().jump, s.input.sample().jump]
	check.call(two == [true, false], "two notches in one tick are one press")
	st.rebind("move_forward", 1, {"type": "mouse", "button": MOUSE_BUTTON_WHEEL_UP})
	notch.call(MOUSE_BUTTON_WHEEL_UP)
	var mv: Vector2 = s.input.sample().move
	check.call(mv.y > 0.0 and s.input.sample().move == Vector2.ZERO, "forward on Wheel Up feeds the move vector for that tick (tap strafe)")
	st.rebind("crouch", 1, {"type": "mouse", "button": MOUSE_BUTTON_WHEEL_RIGHT})
	notch.call(MOUSE_BUTTON_WHEEL_RIGHT)
	check.call(s.input.sample().crouch, "wheel tilt binds too (crouch on Wheel Right)")
	var mkeys := {}
	var saved_mouse: Callable = s.input.mouse_source
	s.input.mouse_source = func(b: int) -> bool: return mkeys.get(b, false)
	st.rebind("dash", 1, {"type": "mouse", "button": MOUSE_BUTTON_XBUTTON1})
	mkeys[MOUSE_BUTTON_XBUTTON1] = true
	var held_a: bool = s.input.sample().dash
	var held_b: bool = s.input.sample().dash
	mkeys.clear()
	check.call(held_a and held_b and not s.input.sample().dash, "side button 8 on dash is held while pressed")
	s.input.mouse_source = saved_mouse
	st.reset()

	# Mouse look through the settings: hip, ADS blend, invert Y.
	st.set_value("hip", 0.2)
	var hip_deg: Vector2 = st.look_degrees(Vector2(100, 0), 0.0, p.tuning.fov, p.tuning.ads_fov)
	var ads_deg: Vector2 = st.look_degrees(Vector2(100, 0), 1.0, p.tuning.fov, p.tuning.ads_fov)
	var yaw0: float = p.yaw
	p.look_from_mouse(Vector2(100, 0))
	p.apply_look()
	var turned: float = rad_to_deg(yaw0 - p.yaw)
	st.set_value("invert_y", true)
	var pitch0: float = p.pitch
	p.look_from_mouse(Vector2(0, 50))
	p.apply_look()
	var inverted: bool = p.pitch > pitch0 # moving the mouse down looks up
	st.set_value("invert_y", false)
	check.call(inverted, "invert Y reaches the controller")
	check.call(is_equal_approx(hip_deg.x, 20.0) and ads_deg.x < hip_deg.x and absf(turned - 20.0) < 0.01, "look: 100 px at hip 0.2 = 20 deg; aimed is slower (%.2f); applied %.2f" % [ads_deg.x, turned])
	st.reset()
	check.call(is_equal_approx(st.hip, st.DEFAULT_HIP), "reset restores the sensitivity")

	# Pause menu: Esc opens; Settings; Esc goes back to the menu; Esc resumes.
	var pm: CanvasLayer = c.pause_menu
	c._unhandled_key_input(esc())
	check.call(s.paused() and pm.visible and pm.root.visible, "Esc: paused, pause menu open")
	pm.buttons.settings.pressed.emit()
	check.call(pm.panel.visible and not pm.root.visible, "Settings opens the panel")
	c._unhandled_key_input(esc())
	check.call(s.paused() and pm.visible and pm.root.visible and not pm.panel.visible, "Esc in Settings goes back to the menu, still paused")
	c._unhandled_key_input(esc())
	check.call(not s.paused() and not pm.visible and s.input.context == InputRouter.Context.GAMEPLAY, "Esc in the menu resumes")
	# Resume and Restart buttons.
	c._unhandled_key_input(esc())
	pm.buttons.resume.pressed.emit()
	check.call(not s.paused() and not pm.visible, "Resume unpauses")
	p.global_position = Vector3(30, 0, 30)
	c._unhandled_key_input(esc())
	pm.buttons.restart.pressed.emit()
	await tree.physics_frame
	check.call(not s.paused() and not pm.visible and p.global_position.distance_to(c.spawn.at) < 0.05, "Restart: unpaused, back at spawn")
	# While the panel captures a key, Esc belongs to the capture, not the menu.
	c._unhandled_key_input(esc())
	pm.buttons.settings.pressed.emit()
	pm.panel._begin_capture("reload", 0)
	c._unhandled_key_input(esc())
	check.call(pm.panel.visible and s.paused(), "while capturing a rebind, Esc does not close or resume")
	pm.panel.capture = {}
	pm.back(); pm.back()
	check.call(not s.paused(), "back out to the game")
	st.reset()
	s.input.key_source = saved_k
	s.restart()
	await tree.physics_frame
