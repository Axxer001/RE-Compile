extends RefCounted
# Damped spring toward a target (Vector3). Presentation only: kick `v` for
# impulses, step() each frame. stiffness k, damping c; c < 2*sqrt(k) overshoots.

var x := Vector3.ZERO
var v := Vector3.ZERO
var k := 80.0
var c := 10.0

func _init(stiffness := 80.0, damping := 10.0) -> void:
	k = stiffness
	c = damping

# Semi-implicit Euler, sub-stepped so large frame times stay stable.
func step(target: Vector3, dt: float) -> Vector3:
	var steps := maxi(1, ceili(dt / 0.008))
	var h := dt / steps
	for i in steps:
		v += (k * (target - x) - c * v) * h
		x += v * h
	return x

func reset(to: Vector3) -> void:
	x = to
	v = Vector3.ZERO
