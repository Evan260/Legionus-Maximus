class_name Legion
extends RefCounted
## The commander and his soldiers: who is in the legion, where each stands in the formation and what each type does.

var commander := {}
var soldiers: Array = []
var picks := {}
var fallen: Array = []
var revive_timer := 0.0
var reserves: Array = []
var commander_hp_add := 0.0
var commander_hp_mult := 1.0
## Every soldier's health is multiplied by this, from the quartermaster.
var soldier_hp_mult := 1.0

var _b: Dictionary
var _content: Content
var _rng: RandomNumberGenerator
var _ranks: Dictionary
## How many soldiers the legion can hold.
var cap := 100
var _l: Dictionary
# The attack rate for this update, read once since every soldier's cooldown runs on it.
var _rate := 1.0
# The roll formation() last placed and the places it gave, reused while the roll is the same.
var _form_roll: Array = []
var _form_places: Array = []
# The soldiers' indices in row-major order of the places they were last sorted for, front row first and left to right.
var _order: Array = []
var _order_of: Array = []
## How far in from the fort's gate the towers reach, so a man is only in the yard once past them.
const GATE_DEPTH := 30.0
# The commander and soldiers below full health this update, in roll order, gathered for the medici; only they can be the worst hurt.
var _hurt: Array = []
var _hurt_ready := false


func _init(balance: Dictionary, game_content: Content, random: RandomNumberGenerator, ranks: Dictionary) -> void:
	_b = balance
	_content = game_content
	_rng = random
	_ranks = ranks
	cap = int(balance.legion_cap)
	_l = balance.legion
	var cu: Dictionary = _content.base_commander
	commander = {"type": "commander", "pos": Vector2.ZERO, "hp": float(cu.hp), "max_hp": float(cu.hp), "cd": 0.0,
		"anim": 0.0, "facing": Vector2.RIGHT, "moving": false, "flash": 0.0, "haste": 1.0, "struck_at": -1e9, "strike_dir": Vector2.RIGHT}


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
	var base := float(_content.unit(type).hp)
	if type == "commander":
		base = (base + commander_hp_add) * commander_hp_mult
	var hp := base * (1.0 + float(_l.lorica_hp) * float(_ranks.get("lorica", 0)))
	if type != "commander":
		hp *= soldier_hp_mult
	if type != "commander" and promoted(type):
		hp *= float(_content.recruits[type].promotion.get("hp_mult", 1.0))
	return hp


## One soldier of a type, or false when the legion is full.
func add(type: String) -> bool:
	if soldiers.size() >= cap:
		return false
	var info: Dictionary = _content.recruits[type]
	var hp := max_hp_of(type)
	soldiers.append({"type": type, "info": info, "place": info.place, "pos": commander.pos, "target": commander.pos,
		"hp": hp, "max_hp": hp, "cd": _rng.randf() * 0.5, "anim": _rng.randf() * 8.0, "facing": Vector2.RIGHT,
		"moving": false, "flash": 0.0, "haste": 1.0, "guard": null, "sortie": 0, "struck": {}, "struck_at": -1e9,
		"strike_dir": Vector2.RIGHT})
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
	if _form_roll.size() == soldiers.size():
		var same := true
		for i in soldiers.size():
			if not is_same(_form_roll[i], soldiers[i]):
				same = false
				break
		if same:
			return _form_places
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
		front_half = maxf(front_half, absf(rear_places[k].y))
	# Flanks stand beyond the front ranks, the rear block and the middle men, so no place is shared.
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
	_form_roll = soldiers.duplicate()
	_form_places = out
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
	var column := _column(places, sim)
	var fort: Dictionary = sim.objectives.fort
	var step := sim.speed() * float(_l.follow_speed) * (1.0 + float(_b.drills.close_order) * sim.rank("close_order")) * dt
	for i in soldiers.size():
		var s: Dictionary = soldiers[i]
		var target: Vector2 = column[i] if not column.is_empty() else commander.pos + places[i].rotated(sim.facing_angle)
		if not fort.is_empty():
			target = _via_gate(i, s.pos, target, fort)
		s.target = target
		s.anim += dt * 10.0
		if s.sortie != 0:
			continue
		var to: Vector2 = target - s.pos
		var d := to.length()
		s.moving = d > 1.5 or sim.moving
		if d > 0.01:
			var way := to / d
			# A soldier whose place lies across a ravine follows the route map round it or over a bridge; each looks every fourth update.
			if (i + sim.horde.frame) % 4 == 0:
				s.across = sim.terrain.crosses_ravine(s.pos, target)
			if s.get("across", false):
				var f := sim.terrain.flow_at(s.pos)
				if f != Vector2.ZERO:
					way = f
			s.pos += way * minf(d, step)
		s.facing = to.normalized() if d > 3.0 else commander.facing
	assign_guards()


## Where the men head instead of their formation places, one place on the field each, or [] for the formation: a block filling the fort while the commander is inside it, or rows that fit a bridge's deck or the fort's gate while the legion crosses or comes up to one.
func _column(places: Array, sim: Sim) -> Array:
	if soldiers.is_empty():
		return []
	var fort: Dictionary = sim.objectives.fort
	if not fort.is_empty() and sim.objectives.in_fort(commander.pos, sim):
		return _fort_block(places, fort)
	var lanes := _lanes(sim)
	if lanes.is_empty():
		return []
	var width := 0.0
	var front := -INF
	for p in places:
		width = maxf(width, absf(p.y))
		front = maxf(front, p.x)
	var facing := Vector2.from_angle(sim.facing_angle)
	for lane in lanes:
		var room: float = lane.half_w - Sim.UNIT_RADIUS - 1.0
		if width <= room:
			continue
		var files := _files(room)
		var file_gap: float = float(files[1]) - float(files[0]) if files.size() > 1 else 0.0
		var lead := (ceili(float(soldiers.size()) / files.size()) + 1) * float(_l.row_gap) + float(lane.lead)
		var off: Vector2 = commander.pos - lane.pos
		var along: float = off.dot(lane.dir)
		var side: Vector2 = lane.dir.orthogonal()
		var ahead: bool = absf(along) <= lane.half_len + lead if lane.both_ways else along >= -lead and along <= lane.half_len
		if not ahead or absf(off.dot(side)) > lane.side:
			continue
		var way := 1.0 if facing.dot(lane.dir) >= 0.0 else -1.0
		if not lane.both_ways and way < 0.0:
			continue
		var order := _row_major(places)
		var out: Array = []
		out.resize(soldiers.size())
		var k := 0
		var row := 0
		while k < order.size():
			var x := front - row * float(_l.row_gap)
			row += 1
			# The row level with the commander is left empty, since he walks in it.
			if absf(x) < float(_l.row_gap) * 0.6:
				continue
			var in_row := mini(files.size(), order.size() - k)
			for c in in_row:
				out[order[k]] = lane.pos + lane.dir * (along + way * x) + side * (c - (in_row - 1) / 2.0) * file_gap
				k += 1
		return out
	return []


## The bridges' decks and the fort's gate as lanes the legion files through: centre, direction, half length and half width, how far to the side the commander may be, and the extra lead.
func _lanes(sim: Sim) -> Array:
	var out: Array = []
	for br in sim.terrain.bridges:
		out.append({"pos": br.pos, "dir": br.dir, "half_len": br.half_len, "half_w": br.half_w, "side": br.half_w + float(_l.bridge_side),
			"lead": float(_l.bridge_lead), "both_ways": true})
	var fort: Dictionary = sim.objectives.fort
	if not fort.is_empty() and not sim.objectives.fort_reached:
		out.append({"pos": fort.pos, "dir": Vector2.UP, "half_len": float(fort.half), "half_w": float(fort.gate_half), "side": float(fort.half),
			"lead": float(_l.gate_lead), "both_ways": false})
	return out


## The files across a lane `room` either side of its middle, as offsets from it, closed up when the full gap would leave too few.
func _files(room: float) -> Array:
	var gap := float(_l.col_gap)
	var cols := maxi(1, floori(2.0 * room / float(_l.file_gap_min)) + 1)
	if cols > 1:
		gap = minf(gap, 2.0 * room / (cols - 1))
	var out: Array = []
	for c in cols:
		out.append((c - (cols - 1) / 2.0) * gap)
	return out


## The width and depth of the square block that `n` men stand in inside the fort.
static func block_size(n: int, l: Dictionary) -> Vector2:
	var cols := maxi(1, ceili(sqrt(float(n))))
	var rows := ceili(float(n) / cols)
	return Vector2((cols - 1) * float(l.col_gap), (rows - 1) * float(l.row_gap))


## A square block centred in the fort, the men taking its places in the order they stand in the formation, front row to the north.
func _fort_block(places: Array, fort: Dictionary) -> Array:
	var n := soldiers.size()
	var cols := maxi(1, ceili(sqrt(float(n))))
	var size := block_size(n, _l)
	var order := _row_major(places)
	var out: Array = []
	out.resize(n)
	for k in n:
		var row: int = k / cols
		var in_row := mini(cols, n - row * cols)
		out[order[k]] = fort.centre + Vector2((k % cols - (in_row - 1) / 2.0) * float(_l.col_gap), row * float(_l.row_gap) - size.y / 2.0)
	return out


## Whether p is in the fort's yard; the passage between the gate towers counts as outside.
static func _in_yard(p: Vector2, fort: Dictionary) -> bool:
	var off: Vector2 = p - fort.centre
	var half: float = fort.half
	if absf(off.x) >= half or off.y >= half:
		return false
	return not (absf(off.x) <= float(fort.gate_half) and off.y > half - GATE_DEPTH)


## Where a man whose target lies on the other side of the fort's walls walks now: into line with the gate on his own side, then straight through it.
func _via_gate(k: int, p: Vector2, target: Vector2, fort: Dictionary) -> Vector2:
	var inside := _in_yard(p, fort)
	if inside == _in_yard(target, fort):
		return target
	var foot: Vector2 = fort.pos
	var room: float = float(fort.gate_half) - Sim.UNIT_RADIUS - 1.0
	var dx := p.x - foot.x
	var near := foot.y - GATE_DEPTH - 4.0 if inside else foot.y + GATE_DEPTH
	var far := foot.y + GATE_DEPTH if inside else foot.y - GATE_DEPTH - 4.0
	if absf(dx) <= room + 0.5 and (inside or p.y >= foot.y - GATE_DEPTH):
		return Vector2(foot.x + clampf(dx, -room, room), far)
	var files := _files(room)
	return Vector2(foot.x + float(files[k % files.size()]), near)


## The soldiers' indices sorted by their places, front row first and each row from left to right, so a man keeps his turn in the column.
func _row_major(places: Array) -> Array:
	if is_same(_order_of, places) and _order.size() == places.size():
		return _order
	var order: Array = range(places.size())
	order.sort_custom(func(a: int, z: int) -> bool:
		if not is_equal_approx(places[a].x, places[z].x):
			return places[a].x > places[z].x
		return places[a].y < places[z].y)
	_order = order
	_order_of = places
	return order


## Men in the rear and middle are covered by the nearest front-rank soldier within reach.
func assign_guards() -> void:
	var fronts: Array = []
	for s in soldiers:
		if s.place == "front":
			fronts.append(s)
	var at := PackedVector2Array()
	at.resize(fronts.size())
	for k in fronts.size():
		at[k] = fronts[k].pos
	var reach := float(_l.guard_reach)
	for s in soldiers:
		s.guard = null
		if s.place != "rear" and s.place != "middle":
			continue
		var best := reach
		var p: Vector2 = s.pos
		for k in at.size():
			var d: float = (at[k] - p).length()
			if d < best:
				best = d
				s.guard = fronts[k]


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
	_rate = sim.attack_rate()
	_hurt_ready = false
	for s in soldiers:
		# A soldier struck by a sling stone reels and cannot fight until he gathers himself.
		if s.get("dazed", 0.0) > 0.0:
			s.dazed -= dt
			continue
		# A soldier frightened by a painted warrior's battle cry strikes more slowly until he steadies.
		if s.get("afraid", 0.0) > 0.0:
			s.afraid -= dt
			s.haste *= 1.0 - float(s.fear)
		var info: Dictionary = s.info
		match info.attack:
			"melee":
				# A man still waiting out his cooldown only counts it down, so his blow is worked out only when he can strike.
				if s.cd - dt * _rate * s.haste > 0.0:
					s.cd -= dt * _rate * s.haste
				else:
					sim.melee(s, _melee_damage(s.type), float(info.reach), float(info.cooldown), dt)
			"shout":
				if s.cd - dt * _rate * s.haste > 0.0:
					s.cd -= dt * _rate * s.haste
				else:
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


## A man brought back must not also return later as a reserve.
func drop_reserve(type: String) -> void:
	for r in reserves:
		if r.type == type:
			reserves.erase(r)
			return


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
	var at := PackedVector2Array()
	at.resize(soldiers.size())
	for k in soldiers.size():
		soldiers[k].haste = 1.0
		at[k] = soldiers[k].pos
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
		var p: Vector2 = s.pos
		for k in at.size():
			if (at[k] - p).length_squared() <= r2:
				soldiers[k].haste = maxf(soldiers[k].haste, boost)


func _missile(s: Dictionary, dt: float, sim: Sim) -> void:
	var info: Dictionary = s.info
	s.cd -= dt * _rate * s.haste
	if s.cd > 0.0:
		return
	var t := sim.nearest_enemy(s.pos, float(info.range) * sim.range_mult())
	if t < 0:
		return
	s.cd = float(info.cooldown)
	sim.strike(s, sim.horde.e_pos[t])
	# Missiles get half the gladius bonus because the drill trains sword work.
	var dmg := float(info.damage) * (1.0 + 0.2 * sim.rank("gladius") * 0.5)
	if s.type == "archer":
		var fire := sim.rank("fire_arrows")
		sim.shoot("arrow", s.pos, sim.horde.e_pos[t], float(info.arrow_speed), dmg, int(stat(s.type, "pierce")),
			(_b.fire_arrows.dps + _b.fire_arrows.dps_per_level * (fire - 1)) if fire > 0 else 0.0, {"src": "archer"})
	else:
		sim.shoot("stone", s.pos, sim.horde.e_pos[t], float(info.stone_speed), dmg, 0, 0.0,
			{"knock": float(info.knockback), "bounces": int(stat(s.type, "bounces")), "bounce_reach": float(info.bounce_reach), "src": s.type})


func _ballista(s: Dictionary, dt: float, sim: Sim) -> void:
	var info: Dictionary = s.info
	s.cd -= dt * _rate * s.haste
	if s.cd > 0.0:
		return
	var reach := float(info.range) * sim.range_mult()
	var t := sim.nearest_enemy(s.pos, reach)
	if t < 0:
		return
	s.cd = float(info.cooldown)
	sim.strike(s, sim.horde.e_pos[t])
	sim.shoot("bolt", s.pos, sim.horde.e_pos[t], float(info.bolt_speed), float(info.damage), int(info.pierce), 0.0,
		{"life": reach / float(info.bolt_speed), "explode": stat(s.type, "explode_radius"), "src": s.type})


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
	if not _hurt_ready:
		_hurt_ready = true
		_hurt.clear()
		for u in [commander] + soldiers:
			if u.hp / u.max_hp < 1.0:
				_hurt.append(u)
	for u in _hurt:
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
		sim.strike(s, worst.pos)
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
		drop_reserve(fallen.pop_back())
		soldiers[-1].pos = m.pos
		sim.effects.append({"kind": "heal", "pos": m.pos, "t": 0.0})


func _sortie(s: Dictionary, dt: float, sim: Sim) -> void:
	var info: Dictionary = s.info
	var speed := float(info.ride_speed)
	var strike := float(info.strike_reach)
	if s.sortie == 0:
		s.cd -= dt * _rate * s.haste
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
					sim.hit(j, dmg, 0.0, s.type, s.pos)
		if d - move <= strike:
			sim.strike(s, sim.horde.e_pos[t])
			if not s.struck.has(sim.horde.e_id[t]):
				sim.hit(t, dmg, 0.0, s.type, s.pos)
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
