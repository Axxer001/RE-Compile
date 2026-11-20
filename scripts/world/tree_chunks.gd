extends Node3D

var chunks: Dictionary
var far: Dictionary
var loaded := {}
var pending: Array = []
var build: Callable
var cell_size := 10.0
var detail_distance := 40.0
var last_focus := Vector2(INF, INF)

func setup(data: Dictionary, impostors: Dictionary, builder: Callable, size_m: float, distance_m: float, focus: Vector2) -> void:
	chunks = data
	far = impostors
	build = builder
	cell_size = size_m
	detail_distance = distance_m
	refresh(focus)
	while not pending.is_empty(): build_next()

func _process(_dt: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null: return
	refresh(Vector2(camera.global_position.x, camera.global_position.z))
	# shortcut: budget is checked between whole cells; profile teleport spikes before enabling by default.
	var deadline := Time.get_ticks_usec() + 1500
	while not pending.is_empty():
		build_next()
		if Time.get_ticks_usec() >= deadline: break

func refresh(focus: Vector2) -> void:
	if focus.distance_squared_to(last_focus) < 4.0: return
	last_focus = focus
	var load_radius := detail_distance + cell_size * 2.0 + 16.0
	var keep_radius := load_radius + cell_size * 2.0
	for key in loaded.keys():
		if center(key).distance_to(focus) > keep_radius:
			fallback(key, false)
			loaded[key].free()
			loaded.erase(key)
	pending.clear()
	for key in chunks:
		if not loaded.has(key) and center(key).distance_to(focus) <= load_radius:
			pending.append(key)
	pending.sort_custom(func(a, b): return center(a).distance_squared_to(focus) < center(b).distance_squared_to(focus))

func center(key: Vector2i) -> Vector2:
	return (Vector2(key) + Vector2(0.5, 0.5)) * cell_size

func build_next() -> void:
	var key: Vector2i = pending.pop_front()
	var group := Node3D.new()
	group.name = "chunk_%d_%d" % [key.x, key.y]
	add_child(group)
	for kind in chunks[key]: build.call(group, kind, chunks[key][kind], kind, false, detail_distance)
	loaded[key] = group
	fallback(key, true)

func fallback(key: Vector2i, detailed: bool) -> void:
	for instance in far.get(key, []):
		instance.visibility_range_begin = maxf(0.0, detail_distance - 8.0) if detailed else 0.0

func set_distance(value: float) -> void:
	detail_distance = value
	for group in loaded.values():
		for geometry in group.get_children(): geometry.visibility_range_end = value
	for key in far: fallback(key, loaded.has(key))
	last_focus = Vector2(INF, INF)
