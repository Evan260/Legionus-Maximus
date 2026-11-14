class_name Upgrades
extends RefCounted
## The level-up choices: what each one is called, how far it goes and what it does to the run.

const ALL := {
	"legionary": {"name": "Legionaries", "group": "Recruit", "max": 0,
		"text": "Two legionaries join the front ranks."},
	"archer": {"name": "Archers", "group": "Recruit", "max": 0,
		"text": "Two archers join the rear and shoot the nearest enemy."},
	"pilum": {"name": "Pilum volley", "group": "Arms", "max": 5,
		"text": "Legionaries throw pila at the nearest enemies every few seconds.",
		"more": "More pila, thrown more often, that hit harder and pass through."},
	"fire_arrows": {"name": "Burning arrows", "group": "Arms", "max": 5,
		"text": "Arrows set enemies alight for three seconds.", "more": "The fire burns hotter."},
	"scorpio": {"name": "Scorpio", "group": "Arms", "max": 5,
		"text": "A bolt thrower shoots the strongest enemy in range, through everyone in its way.",
		"more": "Heavier bolts, loosed more often."},
	"march": {"name": "Forced march", "group": "Drill", "max": 5, "text": "The legion moves 8% faster."},
	"lorica": {"name": "Lorica", "group": "Drill", "max": 5,
		"text": "Every soldier has 20% more health, and is healed by as much."},
	"discipline": {"name": "Discipline", "group": "Drill", "max": 5, "text": "Every soldier attacks 12% faster."},
	"gladius": {"name": "Sharpened gladii", "group": "Drill", "max": 5, "text": "Swords hit 20% harder, arrows 10%."},
	"reach": {"name": "Long reach", "group": "Drill", "max": 3, "text": "Coins are picked up from 30% further away."},
	"rations": {"name": "Rations", "group": "Drill", "max": 3, "text": "Every soldier slowly heals."},
	"testudo": {"name": "Testudo practice", "group": "Drill", "max": 4,
		"text": "The testudo recharges 2 seconds sooner and holds 1 second longer."},
}


static func available(sim: Sim) -> Array:
	var out: Array = []
	for id in ALL:
		var info: Dictionary = ALL[id]
		if id == "legionary":
			if sim.count("legionary") < int(sim.b.max_legionaries):
				out.append(id)
		elif id == "archer":
			if sim.count("archer") < int(sim.b.max_archers):
				out.append(id)
		elif id == "fire_arrows" and sim.count("archer") == 0:
			continue
		elif sim.rank(id) < int(info.max):
			out.append(id)
	return out


static func offers(sim: Sim, n: int = 3) -> Array:
	var pool := available(sim)
	var picks: Array = []
	# Recruits come up more often, since a growing legion is the heart of the game.
	var weights := {}
	for id in pool:
		weights[id] = 3.0 if ALL[id].group == "Recruit" else (2.0 if ALL[id].group == "Arms" else 1.0)
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
	if ALL[id].group == "Recruit":
		return "%d in the legion" % sim.count(id)
	var r := sim.rank(id)
	return "New" if r == 0 else "Level %d" % (r + 1)


static func describe(sim: Sim, id: String) -> String:
	var info: Dictionary = ALL[id]
	if sim.rank(id) > 0 and info.has("more"):
		return info.more
	return info.text


static func apply(sim: Sim, id: String) -> void:
	match id:
		"legionary":
			for i in 2:
				if sim.count("legionary") < int(sim.b.max_legionaries):
					sim.add_soldier("legionary")
		"archer":
			for i in 2:
				if sim.count("archer") < int(sim.b.max_archers):
					sim.add_soldier("archer")
		_:
			sim.ranks[id] = sim.rank(id) + 1
			if id == "lorica":
				for u in [sim.commander] + sim.soldiers:
					var base: float = sim.b.units[u.type].hp
					u.max_hp = base * (1.0 + 0.2 * sim.rank("lorica"))
					u.hp = minf(u.max_hp, u.hp + base * 0.2)
			elif id == "pilum" and sim.rank("pilum") == 1:
				sim.pilum_timer = 0.5
			elif id == "scorpio" and sim.rank("scorpio") == 1:
				sim.scorpio_timer = 0.5
	if sim.pending_levels > 0:
		sim.pending_levels -= 1
