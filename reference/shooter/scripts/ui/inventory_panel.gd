extends CanvasLayer
# Inventory screen (Tab). Shows the bag from a snapshot the world gives it:
# one row per item with its slot, label, quantity or magazine, and whether it
# is equipped. Issues commands only: equip(id) on a weapon row, drop(id).
# Keyboard: arrows move focus, Enter equips, Delete drops the focused row.

signal equip_requested(instance_id: String)
signal drop_requested(instance_id: String)
signal close_requested

var panel: PanelContainer
var title: Label
var rows: VBoxContainer
var row_ids: Array[String] = []
var hint: Label

func _ready() -> void:
	layer = 6
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(520, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.07, 0.96)
	style.border_color = Color(0.55, 0.6, 0.5)
	style.set_border_width_all(2)
	style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	box.add_child(rows)
	hint = Label.new()
	hint.text = "Enter / click: equip weapon     Delete / Drop: drop     Tab or Esc: close"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.7, 0.72, 0.68))
	box.add_child(hint)
	visible = false

func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey) or not event.pressed or event.echo: return
	if event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		close_requested.emit()
	elif event.physical_keycode == KEY_DELETE:
		var f := get_viewport().gui_get_focus_owner()
		for i in rows.get_child_count():
			if rows.get_child(i).is_ancestor_of(f) and i < row_ids.size():
				get_viewport().set_input_as_handled()
				drop_requested.emit(row_ids[i])
				return

# snapshot: {capacity, equipped_id, entries: [{id, label, quantity, weapon, magazine?, magazine_size?, reserve?}]}
func refresh(snap: Dictionary) -> void:
	var entries: Array = snap.entries
	title.text = "BAG  %d / %d" % [entries.size(), snap.capacity]
	for c in rows.get_children(): c.queue_free()
	row_ids.clear()
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "Empty. Loot, weapons and ammo you pick up appear here."
		rows.add_child(empty)
		return
	for i in entries.size():
		var e: Dictionary = entries[i]
		var row := HBoxContainer.new()
		var b := Button.new()
		b.custom_minimum_size = Vector2(380, 34)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var detail := ""
		if e.weapon and e.get("magazine_size", 0) > 0: detail = "  %d/%d (+%d)" % [e.magazine, e.magazine_size, e.reserve]
		elif not e.weapon and e.quantity > 1: detail = "  x%d" % e.quantity
		b.text = "%d. %s%s%s" % [i + 1, e.label, detail, "   [EQUIPPED]" if e.id == snap.equipped_id else ""]
		var id: String = e.id
		b.disabled = not e.weapon
		b.focus_mode = Control.FOCUS_ALL
		b.pressed.connect(func() -> void: equip_requested.emit(id))
		row.add_child(b)
		var d := Button.new()
		d.text = "Drop"
		d.pressed.connect(func() -> void: drop_requested.emit(id))
		row.add_child(d)
		rows.add_child(row)
		row_ids.append(id)

func row_button(i: int) -> Button:
	return rows.get_child(i).get_child(0)

func drop_button(i: int) -> Button:
	return rows.get_child(i).get_child(1)

func open(snap: Dictionary) -> void:
	refresh(snap)
	panel.reset_size()
	panel.position = ((panel.get_viewport_rect().size - panel.size) * 0.5).floor()
	visible = true
	await get_tree().process_frame if is_inside_tree() else null
	if rows.get_child_count() > 0 and rows.get_child(0).get_child_count() > 0:
		var first: Control = rows.get_child(0).get_child(0)
		first.grab_focus()

func close() -> void:
	visible = false
	var f := panel.get_viewport().gui_get_focus_owner() if panel.is_inside_tree() else null
	if f != null and panel.is_ancestor_of(f): f.release_focus()
