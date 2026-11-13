extends CanvasLayer
# Van terminal overlay: quota status, research delivered, the shop and
# "End the night". Issues commands only (buy, end_night, close); the career
# decides prices, funds and outcomes.

signal buy_requested(item: String)
signal end_night_requested
signal close_requested

var panel: PanelContainer
var status: Label
var shop_box: VBoxContainer
var shop_buttons := {} # item id -> Button
var end_button: Button
var message: Label

func _ready() -> void:
	layer = 6
	panel = PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 460)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.08, 0.07, 0.05, 0.97)
	style.border_color = Color(0.85, 0.7, 0.35)
	style.set_border_width_all(2)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = "SALVAGE CONTRACT  -  VAN TERMINAL"
	title.add_theme_font_size_override("font_size", 22)
	box.add_child(title)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(status)
	var shop_title := Label.new()
	shop_title.text = "SHOP"
	box.add_child(shop_title)
	shop_box = VBoxContainer.new()
	box.add_child(shop_box)
	message = Label.new()
	message.add_theme_color_override("font_color", Color(1.0, 0.7, 0.4))
	box.add_child(message)
	end_button = Button.new()
	end_button.text = "End the night (leave in the van)"
	end_button.custom_minimum_size = Vector2(0, 44)
	end_button.pressed.connect(func() -> void: end_night_requested.emit())
	box.add_child(end_button)
	var close := Button.new()
	close.text = "Back (Esc)"
	close.pressed.connect(func() -> void: close_requested.emit())
	box.add_child(close)
	visible = false

# view: {night, nights_per_cycle, cycle, quota, delivered, banked, research, research_total,
#  carrying_value, carrying_research, shop: [{id, label, price, owned, affordable, allowed}], message}
func refresh(view: Dictionary) -> void:
	status.text = "Night %d of %d  (cycle %d)\nQuota this cycle: PHP %d / %d\nBank: PHP %d\nResearch delivered: %d of %d\nCarrying: PHP %d of loot, %d research file(s) - delivered when you leave." % [
		view.night, view.nights_per_cycle, view.cycle, view.delivered, view.quota, view.banked,
		view.research, view.research_total, view.carrying_value, view.carrying_research]
	for item in view.shop:
		var b: Button = shop_buttons.get(item.id)
		if b == null:
			b = Button.new()
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			var id: String = item.id
			b.pressed.connect(func() -> void: buy_requested.emit(id))
			shop_box.add_child(b)
			shop_buttons[item.id] = b
		b.text = "%s  -  PHP %d%s" % [item.label, item.price, "  (owned)" if item.owned else ""]
		b.disabled = item.owned or not item.affordable or not item.allowed
	message.text = view.get("message", "")

# Centred on the viewport (anchors do not apply directly under a CanvasLayer).
func _centre() -> void:
	panel.reset_size()
	panel.position = ((panel.get_viewport_rect().size - panel.size) * 0.5).floor()

func open(view: Dictionary) -> void:
	refresh(view)
	_centre()
	visible = true
	end_button.grab_focus()

func close() -> void:
	visible = false
	var f := panel.get_viewport().gui_get_focus_owner() if panel.is_inside_tree() else null
	if f != null and panel.is_ancestor_of(f): f.release_focus()
