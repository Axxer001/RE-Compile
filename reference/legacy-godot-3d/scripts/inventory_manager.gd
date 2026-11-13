class_name InventoryManager
extends RefCounted

signal inventory_changed()
signal active_weapon_changed(weapon: WeaponData)

enum BagTier { POCKETS = 4, SLINGBAG = 8, BACKPACK = 12 }

var current_tier: BagTier = BagTier.POCKETS
var max_slots: int = BagTier.POCKETS
var items: Array[Resource] = []
var active_weapon_index: int = -1

func _init(tier: BagTier = BagTier.POCKETS) -> void:
	set_tier(tier)

func set_tier(tier: BagTier) -> void:
	current_tier = tier
	max_slots = tier as int
	if items.size() > max_slots:
		items.resize(max_slots)
	inventory_changed.emit()

func upgrade_bag(new_tier: BagTier) -> bool:
	if (new_tier as int) > (current_tier as int):
		set_tier(new_tier)
		return true
	return false

func add_item(item: Resource) -> bool:
	if items.size() >= max_slots:
		return false
	items.append(item)
	if item is WeaponData and active_weapon_index == -1:
		active_weapon_index = items.size() - 1
		active_weapon_changed.emit(item as WeaponData)
	inventory_changed.emit()
	return true

func remove_item_at(index: int) -> Resource:
	if index < 0 or index >= items.size():
		return null
	var removed = items[index]
	items.remove_at(index)
	if active_weapon_index == index:
		_find_next_weapon()
	elif active_weapon_index > index:
		active_weapon_index -= 1
	inventory_changed.emit()
	return removed

func select_weapon_slot(slot_index: int) -> bool:
	if slot_index >= 0 and slot_index < items.size():
		if items[slot_index] is WeaponData:
			active_weapon_index = slot_index
			active_weapon_changed.emit(items[slot_index] as WeaponData)
			return true
	return false

func cycle_weapon(forward: bool = true) -> void:
	if items.is_empty():
		return
	var weapon_indices: Array[int] = []
	for i in range(items.size()):
		if items[i] is WeaponData:
			weapon_indices.append(i)
	if weapon_indices.is_empty():
		active_weapon_index = -1
		return
		
	var current_pos = weapon_indices.find(active_weapon_index)
	if current_pos == -1:
		active_weapon_index = weapon_indices[0]
	else:
		if forward:
			current_pos = (current_pos + 1) % weapon_indices.size()
		else:
			current_pos = (current_pos - 1 + weapon_indices.size()) % weapon_indices.size()
		active_weapon_index = weapon_indices[current_pos]
		
	active_weapon_changed.emit(items[active_weapon_index] as WeaponData)

func _find_next_weapon() -> void:
	for i in range(items.size()):
		if items[i] is WeaponData:
			active_weapon_index = i
			active_weapon_changed.emit(items[i] as WeaponData)
			return
	active_weapon_index = -1
	active_weapon_changed.emit(null)

func get_active_weapon() -> WeaponData:
	if active_weapon_index >= 0 and active_weapon_index < items.size():
		return items[active_weapon_index] as WeaponData
	return null
