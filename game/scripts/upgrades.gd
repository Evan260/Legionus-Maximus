class_name Upgrades
extends RefCounted
## The level-up choices: which are on offer, how far each goes and what it does to the run. Names and texts live in content.json.

static func available(sim: Sim) -> Array:
	var out: Array = []
	for kind in Content.GROUPS:
		for id in sim.content.get(kind):
			if _offerable(sim, kind, id) and not sim.banished.has(id):
				out.append(id)
	return out


static func _offerable(sim: Sim, kind: String, id: String) -> bool:
	var info: Dictionary = sim.content.get(kind)[id]
	if not info.get("implemented", false) or not sim.content.ready(kind, id):
		return false
	if kind == "recruits":
		return sim.soldiers.size() < sim.legion.cap
	if kind == "forged":
		return sim.rank(id) < int(info.max) and _pair_done(sim, info)
	if id == "fire_arrows" and sim.count("archer") == 0:
		return false
	return sim.rank(id) < int(info.get("max", 0))


## A forged form is offered once both weapons it is made from are at their last level.
static func _pair_done(sim: Sim, info: Dictionary) -> bool:
	for w in info.from:
		if sim.rank(w) < int(sim.content.arms[w].max):
			return false
	return true


static func choice_count(sim: Sim) -> int:
	return 3 + sim.rank("fortune")


## n different choices from what is on offer, or as many as the run's choice count when n is not given.
static func offers(sim: Sim, n: int = -1, skip: Array = []) -> Array:
	if n < 0:
		n = choice_count(sim)
	var pool: Array = []
	for id in available(sim):
		if not skip.has(id):
			pool.append(id)
	var picks: Array = []
	# A full set of choices always holds one recruit while the legion has room, since a growing legion is the heart of the game.
	if n >= 3:
		var recruits: Array = []
		for id in pool:
			if sim.content.recruits.has(id):
				recruits.append(id)
		if not recruits.is_empty():
			var r: String = recruits[sim.rng.randi_range(0, recruits.size() - 1)]
			picks.append(r)
			pool.erase(r)
	# Recruits come up more often, since a growing legion is the heart of the game, and a forged form is a prize.
	var weights := {}
	var luck := 1.0 + sim.bonus_amount("choice_luck")
	for id in pool:
		match sim.content.group_of(id):
			"Recruit":
				weights[id] = 3.0 * luck
			"Forged":
				weights[id] = 6.0
			"Arms":
				weights[id] = 2.0 * luck
			_:
				weights[id] = 1.0
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


## The choices for a level-up screen. With nothing left to offer the waiting levels are dropped, so no screen opens.
static func next_choices(sim: Sim) -> Array:
	var picks := offers(sim)
	if picks.is_empty():
		sim.pending_levels = 0
		# A free choice with nothing to offer heals the legion instead of being lost.
		if sim.free_choices > 0:
			sim.horde.heal_legion(sim)
		sim.free_choices = 0
	return picks


## A fresh set in place of the current one, which costs a reroll; with none left the choices stay.
static func reroll(sim: Sim, current: Array) -> Array:
	if sim.rerolls <= 0:
		return current
	var fresh := offers(sim, current.size(), current)
	if fresh.is_empty():
		return current
	sim.rerolls -= 1
	return fresh


## Removes one choice from the run for good and fills its place with another; with no banish left nothing changes.
static func banish(sim: Sim, id: String, current: Array) -> Array:
	if sim.banishes <= 0 or not current.has(id):
		return current
	sim.banishes -= 1
	sim.banished.append(id)
	var out := current.duplicate()
	out.erase(id)
	out.append_array(offers(sim, 1, current))
	return out


## The selected choice, moved onto the last one when a reroll or banish left the list shorter.
static func keep_in(selected: int, choices: Array) -> int:
	return clampi(selected, 0, maxi(choices.size() - 1, 0))


static func level_text(sim: Sim, id: String) -> String:
	var group := sim.content.group_of(id)
	if group == "Recruit":
		return TranslationServer.translate("%d in the legion") % sim.count(id)
	if group == "Forged":
		return TranslationServer.translate("Forged")
	var r := sim.rank(id)
	return TranslationServer.translate("New") if r == 0 else TranslationServer.translate("Level %d") % (r + 1)


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
				u.max_hp = sim.max_hp_of(u.type) + float(u.get("vet", 0.0))
				u.hp = minf(u.max_hp, u.hp + base * 0.2)
	if sim.pending_levels > 0:
		sim.pending_levels -= 1
	elif sim.free_choices > 0:
		sim.free_choices -= 1
