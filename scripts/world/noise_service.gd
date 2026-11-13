extends RefCounted
# Short-lived gameplay noise events (ARCHITECTURE "NoiseService"). Independent of
# audio: muting sound never makes the player silent to the AI. Listeners hear
# an event's origin (last-known position), not the emitter's live location.
# Sound passes through walls/doors in this MVP; only distance matters.

signal noise_emitted(event: Dictionary)

const LIFETIME_S := 1.0
var events: Array[Dictionary] = [] # {id, origin: Vector3 metres, radius (m), kind, source_id, time}
var _next_id := 1

# Highest id issued so far (ids never repeat, even across reset()).
func last_id() -> int:
	return _next_id - 1

func reset() -> void:
	events.clear()

func emit_noise(origin: Vector3, radius_m: float, kind: String, source_id: String, now: float) -> Dictionary:
	var event := {"id": _next_id, "origin": origin, "radius": radius_m, "kind": kind, "source_id": source_id, "time": now}
	_next_id += 1
	events.append(event)
	noise_emitted.emit(event)
	return event

func prune(now: float) -> void:
	events = events.filter(func(e): return now - e.time <= LIFETIME_S)

# Loudest-then-newest event audible at `listener` newer than `after_id`.
func heard(listener: Vector2, after_id: int, ignore_source := "") -> Dictionary:
	var best := {}
	for e in events:
		if e.id <= after_id or e.source_id == ignore_source: continue
		if listener.distance_to(e.origin) > e.radius: continue
		if best.is_empty() or e.radius > best.radius or (e.radius == best.radius and e.id > best.id):
			best = e
	return best
