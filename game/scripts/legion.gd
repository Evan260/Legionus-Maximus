class_name Legion
extends RefCounted
## The commander and his soldiers: who is in the legion, where each stands in the formation and what each type does.

var commander := {}
var soldiers: Array = []
var picks := {}
var fallen: Array = []
var revive_timer := 0.0
var reserves: Array = []

var _b: Dictionary
var _content: Content
var _rng: RandomNumberGenerator
var _ranks: Dictionary
var _cap := 100
var _l: Dictionary


func _init(balance: Dictionary, game_content: Content, random: RandomNumberGenerator, ranks: Dictionary) -> void:
	_b = balance
	_content = game_content
	_rng = random
	_ranks = ranks
	_cap = int(balance.legion_cap)
	_l = balance.legion
	var cu: Dictionary = _content.base_commander
	commander = {"type": "commander", "pos": Vector2.ZERO, "hp": float(cu.hp), "max_hp": float(cu.hp), "cd": 0.0,
		"anim": 0.0, "facing": Vector2.RIGHT, "moving": false, "flash": 0.0, "haste": 1.0}


func count(type: String) -> int:
	var n := 0
	for s in soldiers:
		if s.type == type:
			n += 1
	return n


func promoted(type: String) -> bool:
	return int(picks.get(type, 0)) >= int(_b.promotion_picks)


## A stat of a recruit type, taken from its promotion when it has been promoted and the promotion changes it.
func stat(type: String, key: String, fallback: float = 0.0) -> float:
	var info: Dictionary = _content.recruits[type]
	if promoted(type) and info.promotion.has(key):
		return float(info.promotion[key])
	return float(info.get(key, fallback))


func max_hp_of(type: String) -> float:
	var hp := float(_content.unit(type).hp) * (1.0 + float(_l.lorica_hp) * float(_ranks.get("lorica", 0)))
	if type != "commander" and promoted(type):
		hp *= float(_content.recruits[type].promotion.get("hp_mult", 1.0))
	return hp


## One soldier of a type, or false when the legion is full.
func add(type: String) -> bool:
	if soldiers.size() >= _cap:
		return false
	var info: Dictionary = _content.recruits[type]
	var hp := max_hp_of(type)
	soldiers.append({"type": type, "info": info, "place": info.place, "pos": commander.pos, "target": commander.pos,
		"hp": hp, "max_hp": hp, "cd": _rng.randf() * 0.5, "anim": _rng.randf() * 8.0, "facing": Vector2.RIGHT,
		"moving": false, "flash": 0.0, "haste": 1.0, "guard": null, "sortie": 0, "struck": {}})
	return true


## One choice at a level-up: the soldiers a pick brings, and the promotion on the fifth.
func pick(type: String) -> void:
	picks[type] = int(picks.get(type, 0)) + 1
	for i in int(_content.recruits[type].per_pick):
		add(type)
	if int(picks[type]) == int(_b.promotion_picks):
		refresh_health(type)


## Health caps follow drills and promotions; a soldier keeps what the rise gave him.
func refresh_health(type: String) -> void:
	for s in soldiers:
		if s.type == type:
			var old: float = s.max_hp
			s.max_hp = max_hp_of(type) + float(s.get("vet", 0.0))
			s.hp = minf(s.max_hp, s.hp + s.max_hp - old)


## Places in the legion's own frame, +x ahead, one for each soldier in the order of the soldiers array.
func formation() -> Array:
	var groups := {"front": [], "rear": [], "flank": [], "middle": []}
	for i in soldiers.size():
		groups[soldiers[i].place].append(i)
	var out: Array = []
	out.resize(soldiers.size())
	var front_half := float(_l.flank_min_front)
	var front_places := _block(groups.front.size(), float(_l.front_start), 1.0)
	for k in front_places.size():
		out[groups.front[k]] = front_places[k]
		front_half = maxf(front_half, absf(front_places[k].y))
	var rear_places := _block(groups.rear.size(), float(_l.rear_start), -1.0)
	for k in rear_places.size():
		out[groups.rear[k]] = rear_places[k]
	# Flanks stand beyond both the front ranks and the middle men, so no place is shared.
	if not groups.middle.is_empty():
		front_half = maxf(front_half, float(_l.middle_across) + float(_l.middle_step) * ((groups.middle.size() - 1) / 2))
	for k in groups.flank.size():
		var side := 1.0 if k % 2 == 0 else -1.0
		var pair: int = k / 2
		var rows := int(_l.flank_rows)
		out[groups.flank[k]] = Vector2(float(_l.flank_x) - float(_l.flank_row_gap) * (pair % rows),
			side * (front_half + float(_l.flank_gap) + float(_l.flank_col_gap) * (pair / rows)))
	for k in groups.middle.size():
		var side := 1.0 if k % 2 == 0 else -1.0
		out[groups.middle[k]] = Vector2(float(_l.middle_x), side * (float(_l.middle_across) + float(_l.middle_step) * (k / 2)))
	return out


func _block(n: int, start: float, way: float) -> Array:
	var out: Array = []
	var cols := clampi(ceili(sqrt(n * float(_l.cols_factor))), int(_l.cols_min), int(_l.cols_max))
	var placed := 0
	var row := 0
	while placed < n:
		var in_row := mini(cols, n - placed)
		for c in in_row:
			# Alternate ranks sit half a place across, so the men behind see past the men in front.
			var across := (c - (in_row - 1) / 2.0) * float(_l.col_gap) + (float(_l.stagger) if row % 2 == 1 and in_row < cols else 0.0)
			out.append(Vector2(start + way * row * float(_l.row_gap), across))
		placed += in_row
		row += 1
	return out


func slot_of(s: Dictionary, angle: float) -> Vector2:
	var places := formation()
	for i in soldiers.size():
		if is_same(soldiers[i], s):
			return places[i].rotated(angle)
	return Vector2.ZERO


func place_all(angle: float) -> void:
	var places := formation()
	for i in soldiers.size():
		soldiers[i].pos = commander.pos + places[i].rotated(angle)
		soldiers[i].target = soldiers[i].pos


## Every soldier walks to his place in the formation; riders out on a sortie are moved by update.
func follow(dt: float, sim: Sim) -> void:
	var places := formation()
	var step := sim.speed() * float(_l.follow_speed) * (1.0 + float(_b.drills.close_order) * sim.rank("close_order")) * dt
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		var target: Vector2 = commander.pos + places[i].rotated(sim.facing_angle)
		s.target = target
		s.anim += dt * 10.0
		if s.sortie != 0:
			continue
		var to: Vector2 = target - s.pos
		var d := to.length()
		s.moving = d > 1.5
		if d > 0.01:
			s.pos += to / d * minf(d, step)
		s.facing = to.normalized() if d > 3.0 else commander.facing
	assign_guards()


## Men in the rear and middle are covered by the nearest front-rank soldier within reach.
func assign_guards() -> void:
	var fronts: Array = []
	for s in soldiers:
		if s.place == "front":
			fronts.append(s)
	for s in soldiers:
		s.guard = null
		if s.place != "rear" and s.place != "middle":
			continue
		var best := float(_l.guard_reach)
		for f in fronts:
			var d: float = (f.pos - s.pos).length()
			if d < best:
				best = d
				s.guard = f


## Whoever takes a blow aimed at this unit.
func shield(u: Dictionary) -> Dictionary:
	var g: Variant = u.get("guard")
	return g if g != null else u


## Soldiers who fall out are taken off the roll; the medicus can call them back.
func remove_fallen(sim: Sim) -> void:
	var alive: Array = []
	for s in soldiers:
		if s.hp > 0.0:
			alive.append(s)
		else:
			if fallen.size() < int(_l.fallen_kept):
				fallen.append(s.type)
			if sim.rank("reserves") > 0:
				var times: Array = _b.drills.reserves_seconds
				reserves.append({"type": s.type, "t": float(times[mini(sim.rank("reserves"), times.size()) - 1])})
			sim.effects.append({"kind": "fallen", "pos": s.pos, "t": 0.0, "type": s.type, "facing": s.facing})
	soldiers = alive


func update(dt: float, sim: Sim) -> void:
	_auras()
	_reserves(dt)
	var medici: Array = []
	for s in soldiers:
		var info: Dictionary = s.info
		match info.attack:
			"melee":
				sim.melee(s, _melee_damage(s.type), float(info.reach), float(info.cooldown), dt)
			"shout":
				sim.melee(s, _melee_damage(s.type), float(info.reach), float(info.cooldown), dt)
				_shout(s, dt, sim)
			"missile":
				_missile(s, dt, sim)
			"sortie":
				_sortie(s, dt, sim)
			"bolt":
				_ballista(s, dt, sim)
			"heal":
				medici.append(s)
				_heal(s, dt, sim)
	_revive(medici, dt, sim)


## A fallen soldier's replacement arrives at the commander's side once his time is up.
func _reserves(dt: float) -> void:
	if reserves.is_empty():
		return
	var waiting: Array = []
	for r in reserves:
		r.t -= dt
		if r.t > 0.0:
			waiting.append(r)
		elif add(r.type):
			fallen.erase(r.type)
			soldiers[-1].pos = commander.pos
		else:
			waiting.append(r)
	reserves = waiting


## Every soldier grows a little tougher when the legion kills, up to a cap.
func veterans(n: int, sim: Sim) -> void:
	var rank := sim.rank("veterans")
	if rank <= 0:
		return
	var gain := float(_b.drills.veterans_gain) * rank * n
	for s in soldiers:
		var base: float = float(_content.unit(s.type).hp)
		var room: float = base * float(_b.drills.veterans_cap) * rank - float(s.get("vet", 0.0))
		var g := minf(gain, maxf(0.0, room))
		s.vet = float(s.get("vet", 0.0)) + g
		s.max_hp += g
		s.hp += g


func _melee_damage(type: String) -> float:
	var info: Dictionary = _content.recruits[type]
	var mult := float(info.promotion.get("damage_mult", 1.0)) if promoted(type) else 1.0
	return float(info.damage) * mult


func _auras() -> void:
	commander.haste = 1.0
	for s in soldiers:
		s.haste = 1.0
	for s in soldiers:
		if s.info.attack != "aura":
			continue
		var reach := stat(s.type, "aura_radius", 0.0)
		if reach <= 0.0:
			reach = stat(s.type, "radius")
		var boost := 1.0 + stat(s.type, "speed_bonus")
		var r2 := reach * reach
		if (commander.pos - s.pos).length_squared() <= r2:
			commander.haste = maxf(commander.haste, boost)
		for o in soldiers:
			if (o.pos - s.pos).length_squared() <= r2:
				o.haste = maxf(o.haste, boost)


func _missile(s: Dictionary, dt: float, sim: Sim) -> void:
	var info: Dictionary = s.info
	s.cd -= dt * sim.attack_rate() * s.haste
	if s.cd > 0.0:
		return
	var t := sim.nearest_enemy(s.pos, float(info.range) * sim.range_mult())
	if t < 0:
		return
	s.cd = float(info.cooldown)
	# Missiles get half the gladius bonus because the drill trains sword work.
	var dmg := float(info.damage) * (1.0 + 0.2 * sim.rank("gladius") * 0.5)
	if s.type == "archer":
		var fire := sim.rank("fire_arrows")
		sim.shoot("arrow", s.pos, sim.horde.e_pos[t], float(info.arrow_speed), dmg, int(stat(s.type, "pierce")),
			(_b.fire_arrows.dps + _b.fire_arrows.dps_per_level * (fire - 1)) if fire > 0 else 0.0)
	else:
		sim.shoot("stone", s.pos, sim.horde.e_pos[t], float(info.stone_speed), dmg, 0, 0.0,
			{"knock": float(info.knockback), "bounces": int(stat(s.type, "bounces")), "bounce_reach": float(info.bounce_reach)})


func _ballista(s: Dictionary, dt: float, sim: Sim) -> void:
	var info: Dictionary = s.info
	s.cd -= dt * sim.attack_rate() * s.haste
	if s.cd > 0.0:
		return
	var reach := float(info.range) * sim.range_mult()
	var t := sim.nearest_enemy(s.pos, reach)
	if t < 0:
		return
	s.cd = float(info.cooldown)
	sim.shoot("bolt", s.pos, sim.horde.e_pos[t], float(info.bolt_speed), float(info.damage), int(info.pierce), 0.0,
		{"life": reach / float(info.bolt_speed), "explode": stat(s.type, "explode_radius")})


func _shout(s: Dictionary, dt: float, sim: Sim) -> void:
	s.shout = float(s.get("shout", float(s.info.shout_every))) - dt * s.haste
	if s.shout > 0.0:
		return
	s.shout = float(s.info.shout_every)
	var radius := float(s.info.shout_radius) * stat(s.type, "shout_scale", 1.0)
	for j in sim.enemies_near(s.pos, radius):
		sim.horde.e_stun[j] = maxf(sim.horde.e_stun[j], float(s.info.stun))
	sim.effects.append({"kind": "shout", "pos": s.pos, "t": 0.0, "radius": radius})


func _heal(s: Dictionary, dt: float, sim: Sim) -> void:
	var info: Dictionary = s.info
	var r2 := float(info.radius) * float(info.radius)
	var worst: Variant = null
	var worst_ratio := 1.0
	for u in [commander] + soldiers:
		var ratio: float = u.hp / u.max_hp
		if ratio < worst_ratio and (u.pos - s.pos).length_squared() <= r2:
			worst_ratio = ratio
			worst = u
	s.cd -= dt
	if worst == null:
		return
	worst.hp = minf(worst.max_hp, worst.hp + float(info.heal) * dt)
	if s.cd <= 0.0:
		s.cd = float(info.cooldown)
		sim.effects.append({"kind": "heal", "pos": worst.pos, "t": 0.0})


func _revive(medici: Array, dt: float, sim: Sim) -> void:
	if medici.is_empty() or fallen.is_empty() or not promoted("medicus"):
		return
	revive_timer += dt
	if revive_timer < float(_l.revive_interval) / stat("medicus", "revives_per_minute", 1.0):
		return
	revive_timer = 0.0
	var m: Dictionary = medici[0]
	if add(fallen[-1]):
		fallen.pop_back()
		soldiers[-1].pos = m.pos
		sim.effects.append({"kind": "heal", "pos": m.pos, "t": 0.0})


func _sortie(s: Dictionary, dt: float, sim: Sim) -> void:
	var info: Dictionary = s.info
	var speed := float(info.ride_speed)
	var strike := float(info.strike_reach)
	if s.sortie == 0:
		s.cd -= dt * sim.attack_rate() * s.haste
		if s.cd <= 0.0 and sim.nearest_enemy(s.pos, float(info.reach)) >= 0:
			s.sortie = 1
			s.struck = {}
		return
	if s.sortie == 1:
		var t := sim.nearest_enemy(s.pos, float(info.reach) + 30.0)
		if t < 0:
			s.sortie = 2
			return
		var to: Vector2 = sim.horde.e_pos[t] - s.pos
		var d := to.length()
		var move := minf(d, speed * dt)
		if d > 0.001:
			s.pos += to / d * move
			s.facing = to / d
		s.moving = true
		var dmg := float(info.damage) * (1.0 + 0.2 * sim.rank("gladius"))
		if promoted(s.type):
			for j in sim.enemies_near(s.pos, strike):
				if not s.struck.has(sim.horde.e_id[j]):
					s.struck[sim.horde.e_id[j]] = true
					sim.hit(j, dmg)
		if d - move <= strike:
			if not s.struck.has(sim.horde.e_id[t]):
				sim.hit(t, dmg)
			sim.effects.append({"kind": "slash", "pos": s.pos, "to": sim.horde.e_pos[t], "t": 0.0})
			s.cd = float(info.cooldown)
			s.sortie = 2
		return
	var back: Vector2 = s.target - s.pos
	var d := back.length()
	s.moving = true
	if d <= 5.0:
		s.sortie = 0
		return
	s.pos += back / d * minf(d, speed * dt)
	s.facing = back / d
