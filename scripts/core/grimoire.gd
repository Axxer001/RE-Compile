extends RefCounted
# The Grimoire's page state for one run (GDD §3.1, handoff §5). A page is
# unknown (not shown), found (listed, locked: solve its Code Assembly), or
# unlocked (full page, equippable). Unlocked pages are permanent (MetaProfile);
# a page found but not yet unlocked is lost with the run.

const PageLibrary = preload("res://scripts/core/page_library.gd")

signal page_found(id: String)
signal page_unlocked(id: String)

var meta: RefCounted
var pages := {}     # id -> AbilityPage
var found := {}     # id -> true

func _init(meta_profile: RefCounted) -> void:
	meta = meta_profile
	for id in PageLibrary.IDS: pages[id] = PageLibrary.make(id)
	for id in meta.unlocked: found[id] = true

func page(id: String) -> Resource:
	return pages.get(id)

func is_found(id: String) -> bool:
	return found.has(id)

func is_unlocked(id: String) -> bool:
	return id in meta.unlocked

# Listed pages in library order (unfound pages never appear).
func listed() -> Array:
	return PageLibrary.IDS.filter(func(id): return found.has(id))

func find(id: String) -> bool:
	if not pages.has(id) or found.has(id): return false
	found[id] = true
	page_found.emit(id)
	return true

# Marks a found page unlocked (once). The caller grants the reward.
func unlock(id: String) -> bool:
	if not found.has(id) or is_unlocked(id): return false
	meta.unlock(id)
	page_unlocked.emit(id)
	return true
