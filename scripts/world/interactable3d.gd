extends StaticBody3D
# A simple E-target on the interactable layer (rays find it, bodies do not
# collide): readable notes and the van terminal. `kind` tells the world what
# to do; an optional visual (box or Kenney model) is added by the caller.

var kind := ""   # "note" | "van"
var target_id := ""

func setup(k: String, id: String, at: Vector3, size: Vector3) -> void:
	kind = k
	target_id = id
	name = id
	position = at
	collision_layer = 0b100
	collision_mask = 0
	set_meta("interact", self)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	col.shape = box
	col.position.y = size.y * 0.5
	add_child(col)
