class_name Upgrades
extends RefCounted
## The level-up choices: which are on offer, how far each goes and what it does to the run. Names and texts live in content.json.

static func available(sim: Sim) -> Array:
	var out: Array = []
	for kind in Content.GROUPS:
		for id in sim.content.get(kind):
			if _offerable(sim, kind, id):
				out.append(id)
	return out


static func _offerable(sim: Sim, kind: String, id: String) -> bool:
	var info: Dictionary = sim.content.get(kind)[id]
	if not info.get("implemented", false) or not sim.content.ready(kind, id):
		return false
	if kind == "recruits":
		return sim.soldiers.size() < int(sim.b.legion_cap)
	if id == "fire_arrows" and sim.count("archer") == 0:
		return false
	return sim.rank(id) < int(info.get("max", 0))


static func offers(sim: Sim, n: int = 3) -> Array:
	var pool := available(sim)
	var picks: Array = []
	# Recruits come up more often, since a growing legion is the heart of the game.
	var weights := {}
	for id in pool:
		weights[id] = 3.0 if sim.content.group_of(id) == "Recruit" else (2.0 if sim.content.group_of(id) == "Arms" else 1.0)
	while picks.size() < n and not pool.is_empty():
		var total := 0.0
		for id in pool:
			total += weights[id]
		var roll := sim.rng.randf() * total
		for id in pool:
			roll -= weights[id]
			if roll <= 0.0:
				picks.append(id)
				pool.erase(id)
				break
	return picks


static func level_text(sim: Sim, id: String) -> String:
	if sim.content.group_of(id) == "Recruit":
		return "%d in the legion" % sim.count(id)
	var r := sim.rank(id)
	return "New" if r == 0 else "Level %d" % (r + 1)


static func describe(sim: Sim, id: String) -> String:
	var info: Dictionary = sim.content.upgrade(id)
	if sim.rank(id) > 0 and info.has("more"):
		return info.get("more", "")
	return info.get("text", "")


static func apply(sim: Sim, id: String) -> void:
	if sim.content.recruits.has(id):
		sim.legion.pick(id)
	else:
		sim.ranks[id] = sim.rank(id) + 1
		if id == "lorica":
			for u in [sim.commander] + sim.soldiers:
				var base: float = sim.content.unit(u.type).hp
				u.max_hp = sim.max_hp_of(u.type)
				u.hp = minf(u.max_hp, u.hp + base * 0.2)
		elif id == "pilum" and sim.rank("pilum") == 1:
			sim.pilum_timer = 0.5
		elif id == "scorpio" and sim.rank("scorpio") == 1:
			sim.scorpio_timer = 0.5
	if sim.pending_levels > 0:
		sim.pending_levels -= 1
