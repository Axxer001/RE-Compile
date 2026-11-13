extends RefCounted
# Ground navigation for standing enemies (ported idea from the 2D build's
# AStarGrid2D). A 0.25 m grid over the floor plan; a cell is blocked when an
# agent-sized circle would overlap a solid box whose height range meets the
# agent's body (0.1-1.7 m). Solids come from the level data and door panels,
# analytically, so a rebuild never depends on physics-server timing. Diagonal
# steps are allowed only when both orthogonal neighbours are free (no corner
# cutting). Rebuilt when a door changes; `revision` counts rebuilds.

const CELL := 0.25
const AGENT_RADIUS := 0.3
const BODY_LOW := 0.1
const BODY_HIGH := 1.7
var body_high := BODY_HIGH # per grid: a crouching player fits under 1.3 m, a standing enemy does not

var origin := Vector2.ZERO   # world x/z of cell (0, 0) corner
var size := Vector2i.ZERO
var astar := AStarGrid2D.new()
var revision := 0

func setup(min_xz: Vector2, max_xz: Vector2) -> void:
	origin = min_xz
	size = Vector2i(ceili((max_xz.x - min_xz.x) / CELL), ceili((max_xz.y - min_xz.y) / CELL))
	astar.region = Rect2i(Vector2i.ZERO, size)
	astar.cell_size = Vector2(CELL, CELL)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()

func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori((p.x - origin.x) / CELL), floori((p.z - origin.y) / CELL))

func centre_of(c: Vector2i) -> Vector3:
	return Vector3(origin.x + (c.x + 0.5) * CELL, 0.0, origin.y + (c.y + 0.5) * CELL)

func in_bounds(c: Vector2i) -> bool:
	return astar.is_in_boundsv(c)

func blocked(c: Vector2i) -> bool:
	return not in_bounds(c) or astar.is_point_solid(c)

# Distance from a point to a box footprint (x/z), or INF if heights miss the body.
func _footprint_gap(p: Vector2, box: AABB) -> float:
	if box.end.y <= BODY_LOW or box.position.y >= body_high: return INF
	var dx := maxf(maxf(box.position.x - p.x, 0.0), p.x - box.end.x)
	var dz := maxf(maxf(box.position.z - p.y, 0.0), p.y - box.end.z)
	return sqrt(dx * dx + dz * dz)

# solids: world-space AABBs (walls, furniture, door panels).
# Each box marks only the cells within AGENT_RADIUS of its footprint, so the
# cost follows the solids' area, not the whole (120 x 80 m) grid.
func rebuild(solids: Array) -> void:
	astar.fill_solid_region(astar.region, false)
	for box in solids:
		var b: AABB = box
		if b.end.y <= BODY_LOW or b.position.y >= body_high: continue
		var lo := cell_of(Vector3(b.position.x - AGENT_RADIUS, 0, b.position.z - AGENT_RADIUS))
		var hi := cell_of(Vector3(b.end.x + AGENT_RADIUS, 0, b.end.z + AGENT_RADIUS))
		for x in range(maxi(lo.x, 0), mini(hi.x, size.x - 1) + 1):
			var px := origin.x + (x + 0.5) * CELL
			var dx := maxf(maxf(b.position.x - px, 0.0), px - b.end.x)
			for y in range(maxi(lo.y, 0), mini(hi.y, size.y - 1) + 1):
				var c := Vector2i(x, y)
				if astar.is_point_solid(c): continue
				var pz := origin.y + (y + 0.5) * CELL
				var dz := maxf(maxf(b.position.z - pz, 0.0), pz - b.end.z)
				if sqrt(dx * dx + dz * dz) < AGENT_RADIUS: astar.set_point_solid(c, true)
	revision += 1

# Nearest free cell to p (spiral search), or (-1, -1).
func nearest_free(p: Vector3, max_ring := 4) -> Vector2i:
	var c := cell_of(p)
	if not blocked(c): return c
	for r in range(1, max_ring + 1):
		var best := Vector2i(-1, -1)
		var best_d := INF
		for dx in range(-r, r + 1):
			for dy in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r: continue
				var n := c + Vector2i(dx, dy)
				if blocked(n): continue
				var d := centre_of(n).distance_to(Vector3(p.x, 0, p.z))
				if d < best_d:
					best_d = d
					best = n
		if best.x >= 0: return best
	return Vector2i(-1, -1)

# {ok, path: Array[Vector3] (y = 0), reason, revision}. The last waypoint is
# the exact goal when its cell is free.
func find_path(from: Vector3, to: Vector3) -> Dictionary:
	var a := nearest_free(from)
	var b := nearest_free(to)
	if a.x < 0: return {"ok": false, "path": [], "reason": "start blocked", "revision": revision}
	if b.x < 0: return {"ok": false, "path": [], "reason": "goal blocked", "revision": revision}
	var ids := astar.get_id_path(a, b)
	if ids.is_empty(): return {"ok": false, "path": [], "reason": "no route", "revision": revision}
	var path: Array[Vector3] = []
	for i in range(1, ids.size()): path.append(centre_of(ids[i]))
	if b == cell_of(to) and not path.is_empty(): path[path.size() - 1] = Vector3(to.x, 0, to.z)
	return {"ok": true, "path": path, "reason": "", "revision": revision}
