extends CanvasLayer
# Level-up and rank-up announcements [Sir R15, R15a]: a banner at top centre,
# our own design (Control nodes, JetBrains Mono, a glowing divider, a chime).
#   LEVEL UP / "Lv 3 -> Lv 4" / "+1 stat point"
#   ADVENTURER RANK UP (bigger, gold) / "E -> D" / the rewards
# 0.3 s in (fade and slide down), hold 2.5 s (3.5 s for a rank), 0.4 s out.
# One at a time; the rest wait in a queue, and a rank up goes ahead of any
# queued level banner (so it plays before the level-ups it triggers).
# Level-ups in a burst merge [R15a]: one that arrives while a level banner is
# queued or showing, or within 1 s of the last one, joins it, so the banner
# shows the whole jump ("Lv 3 -> Lv 6", "+3 stat points"), updated in place.
# Presentation only: no input, no pause; main ticks it from publish().

signal shown(item: Dictionary) # a banner starts (main plays the chime)

const IN_S := 0.3
const HOLD_S := 2.5
const RANK_HOLD_S := 3.5
const OUT_S := 0.4
const MERGE_S := 1.0
const TOP_Y := 18.0
const SLIDE := 24.0
const GOLD := Color(1.0, 0.82, 0.38)
const PALE := Color(0.86, 0.92, 1.0)

var queue: Array = []        # items waiting: {kind: "level"|"rank", ...}
var current := {}            # the item on screen ({} = none)
var t := 0.0                 # time into the current banner
var since_level := INF       # seconds since the last level-up arrived
var root: Control
var box: VBoxContainer
var title: Label
var line: Label
var divider: ColorRect
var rewards: Label
var font: Font

func _ready() -> void:
	layer = 2 # over the HUD, under the panels
	font = load("res://assets/fonts/JetBrainsMono-Regular.ttf")
	root = Control.new()
	root.name = "Banner"
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var back := PanelContainer.new()
	back.name = "Back"
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.03, 0.05, 0.78)
	sb.set_content_margin_all(14)
	sb.content_margin_left = 48
	sb.content_margin_right = 48
	back.add_theme_stylebox_override("panel", sb)
	root.add_child(back)
	box = VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(box)
	title = _label(30)
	divider = ColorRect.new()
	divider.custom_minimum_size = Vector2(360, 2)
	divider.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(divider)
	line = _label(22)
	rewards = _label(16)
	root.visible = false

func _label(px: int) -> Label:
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", px)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(l)
	return l

# A level-up from `from` to `to` with `points` stat points; merges into a
# level banner that is showing or queued, or arrived less than 1 s ago.
func push_level(from: int, to: int, points: int) -> void:
	var target := {}
	if current.get("kind", "") == "level" and t < IN_S + HOLD_S: target = current
	else:
		for q in queue:
			if q.kind == "level": target = q
	if target.is_empty() and since_level < MERGE_S and current.get("kind", "") == "level": target = current
	since_level = 0.0
	if not target.is_empty():
		target.to = to
		target.points = int(target.points) + points
		if is_same(target, current):
			_fill(current)
			t = minf(t, IN_S) # stays up a full hold from now
		return
	queue.append({"kind": "level", "from": from, "to": to, "points": points})

# A rank-up; goes ahead of any level banner still waiting.
func push_rank(from: String, to: String, reward_lines: Array) -> void:
	var item := {"kind": "rank", "from": from, "to": to, "rewards": reward_lines}
	var at := queue.size()
	for i in queue.size():
		if queue[i].kind == "level":
			at = i
			break
	queue.insert(at, item)

func tick(delta: float) -> void:
	since_level += delta
	if current.is_empty():
		if queue.is_empty(): return
		current = queue.pop_front()
		t = 0.0
		_fill(current)
		root.visible = true
		shown.emit(current)
	t += delta
	var hold: float = RANK_HOLD_S if current.kind == "rank" else HOLD_S
	var a := 1.0
	if t < IN_S: a = t / IN_S
	elif t > IN_S + hold: a = 1.0 - (t - IN_S - hold) / OUT_S
	a = clampf(a, 0.0, 1.0)
	root.modulate.a = a
	_place(a)
	if t >= IN_S + hold + OUT_S:
		current = {}
		root.visible = false

func _place(a: float) -> void:
	var back: Control = root.get_node("Back")
	back.reset_size()
	var w := root.get_viewport_rect().size.x
	back.position = Vector2(floorf((w - back.size.x) * 0.5), TOP_Y - SLIDE * (1.0 - a))

func _fill(it: Dictionary) -> void:
	if it.kind == "rank":
		title.text = "ADVENTURER RANK UP"
		title.add_theme_font_size_override("font_size", 38)
		title.add_theme_color_override("font_color", GOLD)
		line.text = "%s  ->  %s" % [it.from, it.to]
		line.add_theme_color_override("font_color", GOLD)
		rewards.text = "   ".join(it.rewards)
		divider.color = Color(GOLD, 0.9)
		divider.custom_minimum_size.x = 480
	else:
		title.text = "LEVEL UP"
		title.add_theme_font_size_override("font_size", 30)
		title.add_theme_color_override("font_color", PALE)
		line.text = "Lv %d  ->  Lv %d" % [it.from, it.to]
		line.add_theme_color_override("font_color", Color(1, 1, 1))
		rewards.text = "+%d stat point%s" % [it.points, "" if int(it.points) == 1 else "s"]
		divider.color = Color(0.55, 0.8, 1.0, 0.9)
		divider.custom_minimum_size.x = 360

func showing() -> bool:
	return not current.is_empty()

# What is on screen, as text (tests).
func text() -> String:
	return "" if current.is_empty() else "%s|%s|%s" % [title.text, line.text, rewards.text]

func clear() -> void:
	queue.clear()
	current = {}
	root.visible = false
	since_level = INF

func rect() -> Rect2:
	var back: Control = root.get_node("Back")
	return Rect2(back.position, back.size)
