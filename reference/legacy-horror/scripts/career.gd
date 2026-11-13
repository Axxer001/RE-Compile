extends RefCounted
# Everything that outlives a single night: money, the quota cycle, research
# recovered, shop purchases and the phone. The session creates a fresh
# RunState and Inventory every night; the Career survives. Every money change
# goes through bank(), buy() or fine_for_death() and is logged.

const PhoneState = preload("res://scripts/core/phone_state.gd")

const DEATH_FINE_FRACTION := 0.10 # of banked money (Sir: death costs loot + a fine)
const NIGHTS_PER_CYCLE := 3
const QUOTA_START := 600
const QUOTA_GROWTH := 1.5
const RESEARCH_IDS := ["research_lab", "research_office"]
# Van shop: price in PHP and what it does.
const SHOP := {
	"sling": {"label": "Sling bag (start nights with 8 slots)", "price": 250, "bag": 8},
	"backpack": {"label": "Backpack (start nights with 12 slots)", "price": 500, "bag": 12},
	"hack_hints": {"label": "Hacking hints for the phone", "price": 150, "unlock": "hints"},
}

var banked := 0          # pesos, all-time balance
var banked_cycle := 0    # pesos delivered during the current quota cycle
var nights := 0          # nights finished (any way)
var cycle := 1
var night_in_cycle := 1  # 1..NIGHTS_PER_CYCLE
var quota := QUOTA_START
var research := {}       # research id -> true, once delivered to the van
var start_bag := 4       # bag slots at the start of each night (shop)
var owned := {}          # shop id -> true
var fired := false
var chapter_complete := false
var phone := PhoneState.new()
var seed := 0            # fixes per-career puzzle answers
var log: Array[Dictionary] = [] # {kind, amount, ...}

func _init(seed_value := -1) -> void:
	seed = seed_value if seed_value >= 0 else randi()

# Adds the value of delivered loot; returns the amount banked.
func bank(entries: Array) -> int:
	var amount := 0
	var ids := []
	for e in entries:
		amount += int(e.definition.value) * int(e.quantity)
		ids.append(e.instance_id)
	banked += amount
	banked_cycle += amount
	log.append({"kind": "bank", "amount": amount, "items": ids, "night": nights})
	return amount

# Research delivered to the van (story progress, never sold). Returns the new ids.
func bank_research(ids: Array) -> Array:
	var fresh := []
	for id in ids:
		if id in RESEARCH_IDS and not research.has(id):
			research[id] = true
			fresh.append(id)
	if not fresh.is_empty(): log.append({"kind": "research", "ids": fresh, "night": nights})
	return fresh

func has_all_research() -> bool:
	return RESEARCH_IDS.all(func(id): return research.has(id))

# Death fine: a fraction of banked money, rounded down, never below zero.
func fine_for_death() -> int:
	var amount := int(floor(banked * DEATH_FINE_FRACTION))
	banked -= amount
	log.append({"kind": "fine", "amount": amount, "night": nights})
	return amount

# {ok, reason}. All-or-nothing; a bag never downgrades; one-off items once.
func buy(item: String) -> Dictionary:
	if not SHOP.has(item): return {"ok": false, "reason": "unknown item"}
	var spec: Dictionary = SHOP[item]
	if owned.has(item): return {"ok": false, "reason": "already owned"}
	if spec.has("bag") and spec.bag <= start_bag: return {"ok": false, "reason": "you already have a bigger bag"}
	if banked < spec.price: return {"ok": false, "reason": "not enough money"}
	banked -= spec.price
	owned[item] = true
	if spec.has("bag"): start_bag = spec.bag
	if spec.has("unlock"): phone.unlock(spec.unlock)
	log.append({"kind": "buy", "item": item, "amount": spec.price, "night": nights})
	return {"ok": true, "reason": ""}

# Closes the current night. {result: "next_night" | "next_cycle" | "fired",
# quota, delivered}. The quota is judged only at the end of a cycle's last night.
func end_night() -> Dictionary:
	nights += 1
	var delivered := banked_cycle
	var judged := quota
	if night_in_cycle < NIGHTS_PER_CYCLE:
		night_in_cycle += 1
		return {"result": "next_night", "quota": judged, "delivered": delivered}
	if banked_cycle >= quota:
		cycle += 1
		night_in_cycle = 1
		quota = int(round(quota * QUOTA_GROWTH / 10.0)) * 10
		banked_cycle = 0
		return {"result": "next_cycle", "quota": judged, "delivered": delivered}
	fired = true
	return {"result": "fired", "quota": judged, "delivered": delivered}

func nights_left_in_cycle() -> int:
	return NIGHTS_PER_CYCLE - night_in_cycle + 1
