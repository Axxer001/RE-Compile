extends CanvasLayer
# Phone overlay (P): Map, Journal and Hints tabs. Draws only from a snapshot
# given by the world (rooms, visited, player, terminals, van, and - with intel -
# loot and Shamblers); locked tools say how to unlock them.

signal close_requested

const MAP_SIZE := Vector2(520, 290)

var panel: PanelContainer
var tabs: TabContainer
var map_view: Control
var journal: Label
var hints: Label
var snap := {}

func _ready() -> void:
	layer = 6
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 440)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.09, 0.97)
	style.set_corner_radius_all(18)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	tabs = TabContainer.new()
	panel.add_child(tabs)
	map_view = Control.new()
	map_view.name = "Map"
	map_view.custom_minimum_size = MAP_SIZE
	map_view.draw.connect(_draw_map)
	tabs.add_child(map_view)
	journal = _page("Journal")
	hints = _page("Hints")
	visible = false

func _page(nm: String) -> Label:
	var scroll := ScrollContainer.new()
	scroll.name = nm
	tabs.add_child(scroll)
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(540, 0)
	scroll.add_child(l)
	return l

func _input(event: InputEvent) -> void:
	# Tab/P/Esc while open: P closes (the GUI would otherwise eat keys).
	if visible and event.is_action_pressed("phone") and not event.is_echo():
		get_viewport().set_input_as_handled()
		close_requested.emit()

# snapshot: {rooms: {id: {min, max, label}}, bounds: [min, max], visited, player: Vector3,
#  yaw, terminals: [Vector3], van: Vector3, intel: bool, loot: [Vector3], enemies: [Vector3],
#  journal: [{title, text}], hints_unlocked: bool, hints: [String]}
# Centred on the viewport (anchors do not apply directly under a CanvasLayer).
func _centre() -> void:
	panel.reset_size()
	panel.position = ((panel.get_viewport_rect().size - panel.size) * 0.5).floor()

func open(snapshot: Dictionary) -> void:
	refresh(snapshot)
	_centre()
	visible = true
	tabs.current_tab = 0
	tabs.get_tab_bar().grab_focus()

func refresh(snapshot: Dictionary) -> void:
	snap = snapshot
	var jt := ""
	for e in snapshot.journal: jt += "%s\n%s\n\n" % [e.title.to_upper(), e.text]
	journal.text = jt if jt != "" else "No notes yet. Read whiteboards, sticky notes and terminals."
	if snapshot.hints_unlocked:
		hints.text = "\n\n".join(snapshot.hints) if not snapshot.hints.is_empty() else "No puzzle hints yet."
	else:
		hints.text = "LOCKED - find the sticky note in Computer Lab 2, or buy hints at the van."
	map_view.queue_redraw()

func close() -> void:
	visible = false
	var f := panel.get_viewport().gui_get_focus_owner() if panel.is_inside_tree() else null
	if f != null and panel.is_ancestor_of(f): f.release_focus()

func _to_map(p: Vector3) -> Vector2:
	var b: Array = snap.bounds
	var span: Vector2 = b[1] - b[0]
	var k := minf(MAP_SIZE.x / span.x, MAP_SIZE.y / span.y)
	return Vector2(p.x - b[0].x, p.z - b[0].y) * k + Vector2(4, 4)

func _draw_map() -> void:
	if snap.is_empty(): return
	for id in snap.rooms:
		var r: Dictionary = snap.rooms[id]
		var a := _to_map(Vector3(r.min.x, 0, r.min.y))
		var b := _to_map(Vector3(r.max.x, 0, r.max.y))
		var fill := Color(0.2, 0.35, 0.28) if snap.visited.has(id) else Color(0.14, 0.15, 0.17)
		map_view.draw_rect(Rect2(a, b - a), fill)
		map_view.draw_rect(Rect2(a, b - a), Color(0.6, 0.7, 0.65), false, 2.0)
		map_view.draw_string(ThemeDB.fallback_font, a + Vector2(6, 16), r.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.85, 0.8))
	map_view.draw_circle(_to_map(snap.van), 6, Color(0.3, 0.9, 0.4))
	for t in snap.terminals: map_view.draw_rect(Rect2(_to_map(t) - Vector2(5, 5), Vector2(10, 10)), Color(0.3, 0.75, 1.0))
	if snap.intel:
		for l in snap.loot: map_view.draw_circle(_to_map(l), 4, Color(0.95, 0.8, 0.3))
		for e in snap.enemies: map_view.draw_circle(_to_map(e), 5, Color(0.95, 0.25, 0.2))
	var pp := _to_map(snap.player)
	var fwd := Vector2(-sin(snap.yaw), -cos(snap.yaw))
	map_view.draw_colored_polygon(PackedVector2Array([pp + fwd * 10, pp + fwd.orthogonal() * 5, pp - fwd.orthogonal() * 5]), Color.WHITE)
