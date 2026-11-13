extends RefCounted
# One owned weapon (per-run, mutable). The magazine belongs to this instance:
# two identical pistols keep independent ammunition, and the shared
# WeaponDefinition never holds current ammo (ARCHITECTURE §7).

const ItemDefinition = preload("res://scripts/items/item_definition.gd")

var instance_id := ""
var item: Resource       # ItemDefinition (category weapon/throwable)
var definition: Resource # WeaponDefinition
var magazine := 0

# {ok, weapon, error}. New weapons start with a full magazine (0 for melee).
static func create(item_id: String, run: RefCounted) -> Dictionary:
	var def := ItemDefinition.lookup(item_id)
	if def == null: return {"ok": false, "error": "unknown item %s" % item_id}
	if def.category != "weapon": return {"ok": false, "error": "%s is not a weapon" % item_id}
	return {"ok": true, "weapon": from_definition(def, run)}

static func from_definition(item_def: Resource, run: RefCounted) -> RefCounted:
	var w := new()
	w.instance_id = run.next_instance_id("wpn")
	w.item = item_def
	w.definition = item_def.weapon
	w.magazine = item_def.weapon.magazine_size
	return w

func uses_ammo() -> bool:
	return definition.magazine_size > 0
