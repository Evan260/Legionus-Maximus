class_name Upgrades
extends RefCounted
## The level-up choices: which are on offer, how far each goes and what it does to the run. Names and texts live in content.json.

## The names of the numbers an arm's level changes, by their key in balance.json, in the order they are listed.
const STAT_NAMES := {"damage": "Damage", "dps": "Damage", "every": "Every", "throwers": "Thrown", "count": "Torches", "dogs": "Hounds",
	"radius": "Radius", "life": "Lasts", "push": "Push", "slow": "Enemy speed"}
## How those numbers are written: in seconds, per second or as a share of the enemy's speed; the rest are plain.
const STAT_UNITS := {"dps": "/s", "every": "s", "life": "s", "slow": "%"}
## What each forged arm adds, as [name, key in balance.json, how it is written].
const FORGED_STATS := {
	"hooked_pila": [["Pin", "pin", "s"], ["Pierce", "extra_pierce", "+"]],
	"greek_fire": [["Burn", "burn_mult", "x"], ["Burns for", "seconds", "s"], ["Fire radius", "zone_radius_mult", "x"], ["Fire damage", "zone_dps_mult", "x"]],
	"siege_train": [["Every", "every_mult", "x"], ["Bolts", "extra_bolts", "+"], ["Stones", "extra_stones", "+"]],
	"hunting_horn": [["Hounds", "extra_dogs", "+"], ["Rush", "rush_seconds", "s"], ["Hound speed", "speed_mult", "x"]],
	"burning_eagle": [["Damage", "damage_mult", "x"], ["Burn", "burn_dps", "/s"], ["Torch reach", "torch_radius_mult", "x"], ["Torch damage", "torch_dps_mult", "x"]],
	"fortified_camp": [["Stake damage", "stake_dps_mult", "x"], ["Enemy speed", "slow", "%"], ["Oil radius", "oil_radius_mult", "x"], ["Oil lasts", "oil_life_mult", "x"]],
}

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
	return choices_at(sim.rank("fortune"))


static func choices_at(fortune: int) -> int:
	return 3 + fortune


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
		var line: Array = []
		for id in pool:
			if sim.content.recruits.has(id):
				recruits.append(id)
				if int(sim.content.recruits[id].per_pick) > 1:
					line.append(id)
		# That recruit brings a pair of fighting men whenever one can, so the legion grows as fast as ever; the single specialists come among the other choices.
		if not line.is_empty():
			recruits = line
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
				weights[id] = 4.5 * luck
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


## What a choice does now and at its next level, as [name, now, next] read from the numbers the game plays with. A choice not yet taken has no now; a number the pick does not change has no next.
static func stat_lines(sim: Sim, id: String) -> Array:
	return _stat_lines(sim, id).map(func(s: Array) -> Array: return [str(s[0]), s[1], s[2]])


static func _stat_lines(sim: Sim, id: String) -> Array:
	match sim.content.group_of(id):
		"Recruit":
			return _recruit_lines(sim, id)
		"Forged":
			var out: Array = []
			var cfg: Dictionary = sim.b[id]
			for s in FORGED_STATS.get(id, []):
				out.append([_word(s[0]), "", _written(float(cfg[s[1]]), s[2])])
			return out
		"Arms":
			return _arm_lines(sim, id)
	return _drill_lines(sim, id)


static func _arm_lines(sim: Sim, id: String) -> Array:
	var cfg: Dictionary = sim.b[id]
	var r := sim.rank(id)
	var out: Array = []
	for key in STAT_NAMES:
		if cfg.has(key + "_per_level"):
			var unit: String = STAT_UNITS.get(key, "")
			out.append(_ranked(_word(STAT_NAMES[key]), r, func(k: int) -> String: return _written(Arms.lv(cfg, key, k), unit)))
	if id == "pilum":
		out.append(_ranked(TranslationServer.translate("Pierce"), r, func(k: int) -> String: return str(Arms.pila_pierce(k))))
	return out


static func _drill_lines(sim: Sim, id: String) -> Array:
	var d: Dictionary = sim.b.drills
	var r := sim.rank(id)
	var share := func(per: float) -> Callable: return func(k: int) -> String: return _written(per * k, "+%")
	match id:
		"march":
			return [_ranked(TranslationServer.translate("Speed"), r, share.call(float(d.march)))]
		"lorica":
			return [_ranked(TranslationServer.translate("Health"), r, share.call(float(sim.b.legion.lorica_hp)))]
		"shield_wall":
			return [_ranked(TranslationServer.translate("Damage taken"), r, share.call(-float(d.shield_wall)))]
		"discipline":
			return [_ranked(TranslationServer.translate("Attack speed"), r, share.call(float(d.discipline)))]
		"gladius":
			return [_ranked(TranslationServer.translate("Swords"), r, share.call(float(d.gladius))), _ranked(TranslationServer.translate("Arrows"), r, share.call(float(d.gladius) * 0.5))]
		"better_bows":
			return [_ranked(TranslationServer.translate("Range"), r, share.call(float(d.better_bows)))]
		"reach":
			return [_ranked(TranslationServer.translate("Pickup reach"), r, share.call(float(d.reach)))]
		"rations":
			return [_ranked(TranslationServer.translate("Healing"), r, func(k: int) -> String: return _written(float(d.rations) * k, "/s"))]
		"close_order":
			return [_ranked(TranslationServer.translate("Formation speed"), r, share.call(float(d.close_order)))]
		"testudo":
			return [_ranked(TranslationServer.translate("Testudo holds"), r, func(k: int) -> String: return _written(sim.testudo_hold_at(k), "s")),
				_ranked(TranslationServer.translate("Recharge"), r, func(k: int) -> String: return _written(sim.testudo_recharge_at(k), "s"))]
		"plunder":
			return [_ranked(TranslationServer.translate("Denarii"), r, share.call(float(d.plunder)))]
		"veterans":
			return [_ranked(TranslationServer.translate("Health per kill"), r, func(k: int) -> String: return _written(float(d.veterans_gain) * k, "+")),
				_ranked(TranslationServer.translate("Most health"), r, share.call(float(d.veterans_cap)))]
		"reserves":
			var times: Array = d.reserves_seconds
			return [_ranked(TranslationServer.translate("Replaced after"), r, func(k: int) -> String: return _written(float(times[mini(k, times.size()) - 1]), "s"))]
		"fortune":
			return [_ranked(TranslationServer.translate("Choices"), r, func(k: int) -> String: return str(choices_at(k)))]
		"glory":
			return [_ranked(TranslationServer.translate("Experience"), r, share.call(float(d.glory)))]
	return []


static func _recruit_lines(sim: Sim, id: String) -> Array:
	var info: Dictionary = sim.content.recruits[id]
	var n := sim.count(id)
	var room := maxi(0, sim.legion.cap - sim.soldiers.size())
	var out: Array = [[TranslationServer.translate("In the legion"), str(n), str(n + mini(int(info.per_pick), room))]]
	var blow := sim.legion.blow(id, sim)
	if blow > 0.0:
		out.append([TranslationServer.translate("Damage"), _written(blow, ""), ""])
	out.append([TranslationServer.translate("Health"), _written(sim.max_hp_of(id), ""), ""])
	match id:
		"standard_bearer":
			out.append([TranslationServer.translate("Attack speed"), _written(float(info.speed_bonus), "+%"), ""])
		"medicus":
			out.append([TranslationServer.translate("Heals"), _written(float(info.heal), ""), ""])
		"centurion":
			out.append([TranslationServer.translate("Stun"), _written(float(info.stun), "s"), ""])
	var picks := int(sim.legion.picks.get(id, 0))
	var most := int(sim.b.promotion_picks)
	if picks < most:
		out.append([TranslationServer.translate("Promotion"), "%d/%d" % [picks, most], "%d/%d" % [picks + 1, most]])
	return out


## A line for a number that grows with the rank, with no now for a choice not yet taken.
static func _ranked(name: String, r: int, at: Callable) -> Array:
	return [name, at.call(r) if r > 0 else "", at.call(r + 1)]


static func _word(name: String) -> String:
	return TranslationServer.translate(name)


## A number as the panel writes it: whole when it is whole, with its unit.
static func _written(v: float, unit: String) -> String:
	if unit == "%":
		return "%d%%" % roundi(v * 100.0)
	if unit == "+%":
		return ("+" if v >= 0.0 else "-") + "%d%%" % roundi(absf(v) * 100.0)
	var s := str(roundi(v)) if is_equal_approx(v, roundf(v)) else String.num(v, 2 if absf(v) < 1.0 else 1)
	match unit:
		"s":
			return TranslationServer.translate("%s s") % s
		"/s":
			return TranslationServer.translate("%s/s") % s
		"x":
			return "x" + s
		"+":
			return "+" + s
	return s


## How a forged arm comes about: for an arm, the arm it is forged with, that arm's rank and the forged arm; for a forged arm, what it is made from.
static func forge_lines(sim: Sim, id: String) -> Array:
	var c := sim.content
	if c.forged.has(id):
		var from: Array = c.forged[id].from
		return [TranslationServer.translate("Made from %s and %s") % [c.arms[from[0]].name, c.arms[from[1]].name]]
	var out: Array = []
	for f in c.forged:
		var info: Dictionary = c.forged[f]
		if not info.get("implemented", false) or not info.from.has(id):
			continue
		for other in info.from:
			if other != id:
				out.append(TranslationServer.translate("With %s (%d/%d) forges %s") % [c.arms[other].name, sim.rank(other), int(c.arms[other].max), info.name])
	return out


## A reroll or banish pressed by key or button: the choices after it, and the selection kept on one of them.
static func press(sim: Sim, id: String, current: Array, selected: int) -> Dictionary:
	var out := current
	if id == "reroll":
		out = reroll(sim, current)
	elif id == "banish" and not current.is_empty():
		out = banish(sim, current[clampi(selected, 0, current.size() - 1)], current)
	return {"choices": out, "selected": keep_in(selected, out)}
