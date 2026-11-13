extends RefCounted
# Regression for the 2026-11-14 casting optimisation: target_along now marches
# only the stretch of the segment inside the capsule's bounding sphere. It must
# return exactly what the full 5 cm march returned, for crosshair-length (100 m)
# and per-tick (under 1 m) segments: hits, misses, grazes, starts inside a
# capsule, targets behind the origin or past the end, and zero-length axes.
const PS = preload("res://scripts/combat/projectile_service.gd")

# The pre-optimisation implementation, kept here as the reference.
static func full_march(o: Vector3, d: Vector3, len: float, tg: Dictionary, extra := 0.0) -> float:
	var r: float = float(tg.radius) + extra
	if not tg.has("a"): return PS.segment_sphere(o, d, len, tg.pos, r)
	var n := maxi(1, ceili(len / 0.05))
	for i in n + 1:
		var t := len * float(i) / float(n)
		if PS.axis_distance(o + d * t, tg.a, tg.b) <= r:
			if i == 0: return 0.0
			var lo := len * float(i - 1) / float(n)
			var hi := t
			for k in 8:
				var mid := (lo + hi) * 0.5
				if PS.axis_distance(o + d * mid, tg.a, tg.b) <= r: hi = mid
				else: lo = mid
			return hi
	return -1.0

static func run(check: Callable, _c: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261114
	var cases := 0
	var hits := 0
	var bad := []
	for i in 4000:
		var o := Vector3(rng.randf_range(-20, 20), rng.randf_range(0.5, 2.5), rng.randf_range(-20, 20))
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.2, 0.2), rng.randf_range(-1, 1)).normalized()
		var len: float = [100.0, 40.0, 0.17, 0.5, 3.0][i % 5]
		var base := o + d * rng.randf_range(-5.0, len + 5.0) + Vector3(rng.randf_range(-1.2, 1.2), 0, rng.randf_range(-1.2, 1.2))
		base.y = 0.0
		var rad := rng.randf_range(0.2, 0.5)
		var h := 0.0 if i % 97 == 0 else rng.randf_range(1.2, 2.0) # a few zero-length axes
		var tg := {"radius": rad, "pos": base + Vector3(0, 1, 0), "a": base + Vector3(0, rad, 0), "b": base + Vector3(0, rad + h, 0)}
		var extra: float = [0.0, 0.2, 0.5][i % 3]
		if i % 211 == 0: o = tg.a # starting inside the capsule
		var want := full_march(o, d, len, tg, extra)
		var got := PS.target_along(o, d, len, tg, extra)
		cases += 1
		if want >= 0.0: hits += 1
		if got != want and bad.size() < 3: bad.append("case %d: ref %s got %s" % [i, want, got])
	check.call(bad.is_empty() and hits > 400 and cases - hits > 400, "target_along (culled march) equals the full 5 cm march on %d segments (%d hits, %d misses) %s" % [cases, hits, cases - hits, str(bad)])
	var o2 := Vector3.ZERO
	var tg2 := {"radius": 0.4, "pos": Vector3(0, 1, -50), "a": Vector3(0, 0.4, -50), "b": Vector3(0, 1.6, -50)}
	var t0 := Time.get_ticks_usec()
	for i in 200: PS.target_along(o2, Vector3(0, 0, -1), 100.0, tg2)
	var fast_us := (Time.get_ticks_usec() - t0) / 200.0
	t0 = Time.get_ticks_usec()
	for i in 20: full_march(o2, Vector3(0, 0, -1), 100.0, tg2)
	var ref_us := (Time.get_ticks_usec() - t0) / 20.0
	check.call(fast_us * 5.0 < ref_us, "a 100 m crosshair test of one enemy: %.1f us (full march %.1f us)" % [fast_us, ref_us])
