extends RefCounted
# Code Assembly check (handoff §5). Pure: `variant` = {lines, swap}; `order` =
# the player's arrangement as indices into variant.lines (order[k] = which
# line sits at position k). A position is right when it holds its own line,
# or a line from the same swap group (independent statements may come in any
# order among themselves). Identical lines (C++'s closing braces) are
# interchangeable: a position holding the same text is right. Returns
# {ok, wrong_indices} (positions).

static func check(variant: Dictionary, order: Array) -> Dictionary:
	var n: int = (variant.lines as Array).size()
	var wrong := []
	if order.size() != n:
		for k in n: wrong.append(k)
		return {"ok": false, "wrong_indices": wrong}
	for k in n:
		var at: int = int(order[k])
		if at == k: continue
		if _same_group(variant.get("swap", []), k, at): continue
		if at >= 0 and at < n and variant.lines[at] == variant.lines[k]: continue # the same text: indistinguishable
		wrong.append(k)
	# A swap group must still hold exactly its own lines (no duplicates slip in).
	if wrong.is_empty():
		var seen := {}
		for v in order: seen[int(v)] = true
		if seen.size() != n:
			for k in n: wrong.append(k)
	return {"ok": wrong.is_empty(), "wrong_indices": wrong}

static func _same_group(groups: Array, a: int, b: int) -> bool:
	for g in groups:
		var ints := (g as Array).map(func(x): return int(x)) # JSON numbers load as floats
		if a in ints and b in ints: return true
	return false
