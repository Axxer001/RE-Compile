extends Resource
# Immutable, shared item definition (ARCHITECTURE §7). One .tres per item in
# res://data/items/<id>.tres. Runtime state (quantity, magazine, owner) never
# lives here: see item_stack.gd and weapon_instance.gd.

const DIR := "res://data/items/"
const CATEGORIES := ["weapon", "ammo", "throwable", "healing", "bag", "loot"]

@export var id := &""
@export var label := ""
@export_enum("weapon", "ammo", "throwable", "healing", "bag", "loot") var category := "weapon"
@export var icon_id := ""
@export var max_stack := 1
@export var weapon: Resource # WeaponDefinition for weapons/throwables, else null
@export var value := 0          # pesos banked when carried out (loot)
@export var weight_kg := 0.0    # per unit; slows the carrier
@export var model_path := ""    # world model (.glb); empty = placeholder box

func problems() -> Array[String]:
	var out: Array[String] = []
	if String(id) == "": out.append("missing id")
	if not category in CATEGORIES: out.append("bad category %s" % category)
	if max_stack < 1: out.append("max_stack < 1")
	if category == "weapon" and (weapon == null or max_stack != 1): out.append("weapon needs a WeaponDefinition and max_stack 1")
	if category == "loot" and value <= 0: out.append("loot needs a positive value")
	if weight_kg < 0.0: out.append("negative weight")
	if model_path != "" and not ResourceLoader.exists(model_path): out.append("missing model %s" % model_path)
	return out

# Catalog lookup. Unknown, malformed or mismatched ids return null.
static func lookup(item_id: String) -> Resource:
	if item_id == "" or not item_id.is_valid_identifier(): return null
	var path := DIR + item_id + ".tres"
	if not ResourceLoader.exists(path): return null
	var def := load(path)
	if def == null or def.get_script() != load("res://scripts/items/item_definition.gd"): return null
	if String(def.id) != item_id or not def.problems().is_empty(): return null
	return def

static func all_ids() -> Array[String]:
	var ids: Array[String] = []
	for file in DirAccess.get_files_at(DIR):
		if file.ends_with(".tres"): ids.append(file.get_basename())
	return ids
