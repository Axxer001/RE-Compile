extends RefCounted
# Sir's R15 / R15a (handoff §10): the level-up and rank-up banner. Right
# numbers; a burst of level-ups is one banner for the whole jump; on the 20th
# kill the rank banner plays before the level-up it brings; one banner at a
# time; each hides after its time; it blocks nothing and keeps clear of the
# HUD corners.

const DT := 1.0 / 60.0
const InputRouter = preload("res://scripts/core/input_router.gd")

static func steps(c: Node3D, seconds: float) -> void:
	for i in int(round(seconds / DT)): c.session.step(DT)

static func run(check: Callable, c: Node3D) -> void:
	var s = c.session
	var tree: SceneTree = c.get_tree()
	s.meta.reset()
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	var b: CanvasLayer = c.banner
	var pr: RefCounted = s.progression

	# One level-up.
	pr.add_exp(pr.exp_required(1), "test")
	s.step(DT)
	check.call(b.showing() and b.text() == "LEVEL UP|Lv 1  ->  Lv 2|+1 stat point" and b.queue.is_empty() and c.notices.is_empty(), "a level-up: 'LEVEL UP', 'Lv 1 -> Lv 2', '+1 stat point' (no small notice) [R15] (%s)" % b.text())
	check.call(s.input.context == InputRouter.Context.GAMEPLAY and not s.paused() and b.root.mouse_filter == Control.MOUSE_FILTER_IGNORE, "it neither pauses nor takes input")
	var hud: CanvasLayer = c.hud
	steps(c, 0.35)
	var r: Rect2 = b.rect()
	var tl := Rect2(hud.hp_bar.back.global_position, hud.hp_bar.back.size).merge(Rect2(hud.status.global_position, hud.status.size))
	var tr := Rect2(hud.mission.global_position, hud.mission.size)
	check.call(r.size.x > 200.0 and not r.intersects(tl) and not r.intersects(tr) and absf(r.get_center().x - hud.status.get_viewport_rect().size.x * 0.5) < 2.0, "top centre, clear of the HUD corners (%s)" % r)
	steps(c, 0.3 + 2.5 + 0.4)
	check.call(not b.showing() and not b.root.visible, "it hides after 0.3 s in + 2.5 s + 0.4 s out")

	# R15a: three level-ups in one tick are one banner for the whole jump.
	b.clear()
	pr.level = 3
	pr.exp = 0
	var need: int = pr.exp_required(3) + pr.exp_required(4) + pr.exp_required(5)
	pr.add_exp(need, "test")
	s.step(DT)
	check.call(pr.level == 6 and b.text() == "LEVEL UP|Lv 3  ->  Lv 6|+3 stat points" and b.queue.is_empty(), "three level-ups at once: one banner, 'Lv 3 -> Lv 6', '+3 stat points' [R15a] (%s)" % b.text())
	# Another while it is up updates it in place.
	steps(c, 1.0)
	pr.add_exp(pr.exp_required(6), "test")
	s.step(DT)
	check.call(b.text() == "LEVEL UP|Lv 3  ->  Lv 7|+4 stat points" and b.queue.is_empty(), "a level-up while it shows updates it in place (%s)" % b.text())
	steps(c, 4.0)

	# The 20th kill: the rank banner first, then the level-ups it brings, one at a time.
	b.clear()
	s.restart()
	await tree.physics_frame
	c.park_enemies()
	b.clear()
	pr = s.progression
	pr.kills = 19
	pr.exp = pr.exp_required(1) - 10 # the kill's own 25 EXP levels up before the rank-up lands
	pr.on_kill()
	s.step(DT)
	var first: String = b.text()
	var waiting: Array = b.queue.map(func(q): return q.kind)
	check.call(pr.rank == "D" and first.begins_with("ADVENTURER RANK UP|E  ->  D|+5 stat points   +300 EXP") and first.contains("Now equippable: Ring of Fire, Sage Arts") and waiting == ["level"], "the 20th kill: the gold rank banner (E -> D, +5 points, +300 EXP, Ring of Fire and Sage Arts) plays first, the level-up waits (%s)" % first)
	check.call(b.title.get_theme_font_size("font_size") > 30, "the rank banner is the bigger variant")
	steps(c, 0.3 + 3.3)
	var still_rank: bool = b.text().begins_with("ADVENTURER RANK UP")
	steps(c, 0.2 + 0.4)
	check.call(still_rank, "the rank banner holds 3.5 s (a level banner 2.5 s)")
	s.step(DT)
	var second: String = b.text()
	check.call(second.begins_with("LEVEL UP|Lv 1  ->  Lv ") and b.queue.is_empty(), "then the level-up banner, alone (%s)" % second)
	steps(c, 3.5)
	check.call(not b.showing(), "and then nothing")
	s.meta.reset()
	s.restart()
	await tree.physics_frame
