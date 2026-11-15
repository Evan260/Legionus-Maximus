class_name Arms
extends RefCounted
## The legion-wide weapons and their forged forms. Each fires on its own timer from the ranks in the sim; every number is in balance.json.

# A ground zone is named for its kind; fire is the burning ground the fire pots leave.
const ZONE_WEAPON := {"fire": "fire_pots", "oil": "oil_jars"}

var zones: Array = []
var lobs: Array = []
var dogs: Array = []
var stakes := {}
var torch_angle := 0.0
var timers := {}

var _rng: RandomNumberGenerator
var _laid := 0.0
var _last_pos := Vector2.ZERO
var _has_last := false
var _stake_tick := 0.0
var _torch_tick := 0.0


func _init(random: RandomNumberGenerator) -> void:
	_rng = random


## A weapon stat at a rank: its base value plus the per-level rise for every level above the first.
static func lv(cfg: Dictionary, key: String, rank: int) -> float:
	return float(cfg[key]) + float(cfg.get(key + "_per_level", 0.0)) * (rank - 1)


func update(dt: float, sim: Sim) -> void:
	_pilum(dt, sim)
	_scorpio(dt, sim)
	_onager(dt, sim)
	_caltrops(dt, sim)
	_stakes(dt, sim)
	_fire_pots(dt, sim)
	_oil_jars(dt, sim)
	_war_dogs(dt, sim)
	_trumpets(dt, sim)
	_eagle(dt, sim)
	_torches(dt, sim)
	_lobs(dt, sim)
	_zones(dt, sim)


## Burning ground, oil, caltrops and the stake ring, as {kind, pos, radius, t} for drawing.
func ground_zones() -> Array:
	var out := zones.duplicate()
	if not stakes.is_empty():
		out.append(stakes)
	return out


## Where each torch is now, circling the formation.
func torch_points(sim: Sim) -> Array:
	var out: Array = []
	var r := sim.rank("torches")
	if r <= 0:
		return out
	var cfg: Dictionary = sim.b.torches
	var n := int(lv(cfg, "count", r))
	var ring := maxf(float(cfg.radius) * _flame(sim), sim.legion_reach - 6.0)
	for i in n:
		out.append(sim.commander.pos + Vector2.from_angle(torch_angle + i * TAU / n) * ring)
	return out


func stones_per_throw(sim: Sim) -> int:
	return int(sim.b.onager.stones) + (int(sim.b.siege_train.extra_stones) if sim.rank("siege_train") > 0 else 0)


func dog_count(sim: Sim) -> int:
	var n := int(lv(sim.b.war_dogs, "dogs", sim.rank("war_dogs")))
	return n + (int(sim.b.hunting_horn.extra_dogs) if sim.rank("hunting_horn") > 0 else 0)


func stake_dps(sim: Sim) -> float:
	var dps := lv(sim.b.stakes, "dps", sim.rank("stakes"))
	return dps * (float(sim.b.fortified_camp.stake_dps_mult) if sim.rank("fortified_camp") > 0 else 1.0)


## A patch on the ground that acts on whatever stands in it until its life is over.
func add_zone(kind: String, pos: Vector2, radius: float, life: float, dps: float, extra: Dictionary = {}) -> void:
	var z := {"kind": kind, "pos": pos, "radius": radius, "t": 0.0, "life": life, "dps": dps, "tick": 0.2, "next": 0.0, "slow": 1.0, "pin": 0.0, "src": ZONE_WEAPON.get(kind, kind)}
	z.merge(extra, true)
	zones.append(z)


func _flame(sim: Sim) -> float:
	return float(sim.b.burning_eagle.torch_radius_mult) if sim.rank("burning_eagle") > 0 else 1.0


## True once the weapon's timer has run out; the caller sets the next delay.
func _go(id: String, dt: float) -> bool:
	var t: float = timers.get(id, 0.5) - dt
	timers[id] = t
	return t <= 0.0


## The nearest enemy within reach in front of the legion, since the front ranks throw the way they face.
func _nearest_ahead(sim: Sim, from: Vector2, reach: float) -> int:
	var ahead := Vector2.from_angle(sim.facing_angle)
	var best := -1
	var best_d := INF
	for t in sim.enemies_near(from, reach):
		var to: Vector2 = sim.horde.e_pos[t] - from
		if to.dot(ahead) <= 0.0:
			continue
		var d := to.length_squared()
		if d < best_d:
			best_d = d
			best = t
	return best


func _pilum(dt: float, sim: Sim) -> void:
	var pr := sim.rank("pilum")
	if pr <= 0 or not _go("pilum", dt):
		return
	var p: Dictionary = sim.b.pilum
	timers.pilum = lv(p, "every", pr)
	var hooked := sim.rank("hooked_pila") > 0
	var pierce := 1 + pr / 2 + (int(sim.b.hooked_pila.extra_pierce) if hooked else 0)
	var extra := {"pin": float(sim.b.hooked_pila.pin)} if hooked else {}
	var throwers := int(lv(p, "throwers", pr))
	var thrown := 0
	var order := sim.soldiers.duplicate()
	# Shuffled with the run's own dice so a seed always plays the same run.
	for k in range(order.size() - 1, 0, -1):
		var j := _rng.randi_range(0, k)
		var t: Variant = order[k]
		order[k] = order[j]
		order[j] = t
	order.push_front(sim.commander)
	for s in order:
		if thrown >= throwers:
			break
		if sim.content.unit(s.type).get("place", "front") != "front":
			continue
		var t := _nearest_ahead(sim, s.pos, float(p.range))
		if t >= 0:
			sim.shoot("pilum", s.pos, sim.horde.e_pos[t], p.speed, lv(p, "damage", pr), pierce, 0.0, extra)
			thrown += 1


func _scorpio(dt: float, sim: Sim) -> void:
	var sr := sim.rank("scorpio")
	if sr <= 0 or not _go("scorpio", dt):
		return
	var sc: Dictionary = sim.b.scorpio
	var siege := sim.rank("siege_train") > 0
	timers.scorpio = lv(sc, "every", sr) * (float(sim.b.siege_train.every_mult) if siege else 1.0)
	var best := -1
	var best_hp := 0.0
	var cpos: Vector2 = sim.commander.pos
	for i in sim.enemies_near(cpos, float(sc.range)):
		if sim.horde.e_hp[i] > best_hp:
			best_hp = sim.horde.e_hp[i]
			best = i
	if best < 0:
		return
	var dmg := lv(sc, "damage", sr)
	sim.shoot("bolt", cpos, sim.horde.e_pos[best], sc.speed, dmg, int(sc.pierce), 0.0, {"src": "scorpio"})
	if siege:
		# The siege train fans extra bolts either side of the main one.
		var fan := float(sim.b.siege_train.bolt_fan)
		for k in int(sim.b.siege_train.extra_bolts):
			var turn := fan * (k / 2 + 1) * (1.0 if k % 2 == 0 else -1.0)
			sim.shoot("bolt", cpos, cpos + (sim.horde.e_pos[best] - cpos).rotated(turn), sc.speed, dmg, int(sc.pierce), 0.0, {"src": "scorpio"})


func _onager(dt: float, sim: Sim) -> void:
	var r := sim.rank("onager")
	if r <= 0 or not _go("onager", dt):
		return
	var cfg: Dictionary = sim.b.onager
	var siege := sim.rank("siege_train") > 0
	timers.onager = lv(cfg, "every", r) * (float(sim.b.siege_train.every_mult) if siege else 1.0)
	var aim: Variant = _thickest(sim, float(cfg.range))
	if aim == null:
		timers.onager = 0.3
		return
	for i in stones_per_throw(sim):
		var jitter := Vector2.from_angle(_rng.randf() * TAU) * _rng.randf() * float(cfg.spread) if i > 0 else Vector2.ZERO
		lobs.append({"kind": "stone", "from": sim.commander.pos, "to": aim + jitter, "t": 0.0, "dur": float(cfg.flight),
			"radius": lv(cfg, "radius", r), "dmg": lv(cfg, "damage", r), "scatter": float(cfg.scatter)})


## The middle of the thickest crowd within reach of the commander, or null when there is none.
func _thickest(sim: Sim, reach: float) -> Variant:
	var c := sim._cidx(sim.commander.pos)
	if c < 0:
		return null
	var gw := Sim.GW
	var kx := c % gw
	var ky := c / gw
	var rings := ceili(reach / Sim.CELL)
	var best := 0
	var best_cell := Vector2i.ZERO
	var gs := sim.g_start
	for cy in range(maxi(1, ky - rings), mini(gw - 1, ky + rings + 1)):
		for cx in range(maxi(1, kx - rings), mini(gw - 1, kx + rings + 1)):
			var n := 0
			# Three neighbouring cells of a row are one run of the sorted grid.
			for dy in range(-1, 2):
				var row := (cy + dy) * gw + cx
				n += gs[row + 2] - gs[row - 1]
			if n > best:
				var mid := Vector2((sim.g_origin.x + cx + 0.5) * Sim.CELL, (sim.g_origin.y + cy + 0.5) * Sim.CELL)
				if mid.distance_to(sim.commander.pos) <= reach:
					best = n
					best_cell = Vector2i(cx, cy)
	if best == 0:
		return null
	var sum := Vector2.ZERO
	var count := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell := (best_cell.y + dy) * gw + best_cell.x + dx
			for t in range(gs[cell], gs[cell + 1]):
				sum += sim.horde.e_pos[sim.g_items[t]]
				count += 1
	return sum / count


func _caltrops(dt: float, sim: Sim) -> void:
	var r := sim.rank("caltrops")
	if r <= 0:
		return
	var cfg: Dictionary = sim.b.caltrops
	var pos: Vector2 = sim.commander.pos
	if _has_last:
		_laid += pos.distance_to(_last_pos)
	_has_last = true
	_last_pos = pos
	var dir := Vector2.from_angle(sim.facing_angle)
	var hooked := sim.rank("hooked_pila") > 0
	while _laid >= float(cfg.spacing):
		_laid -= float(cfg.spacing)
		var n := 0
		for z in zones:
			if z.kind == "caltrops":
				n += 1
		if n >= int(cfg.max):
			continue
		var spot := pos - dir * float(cfg.behind) + dir.orthogonal() * _rng.randf_range(-14.0, 14.0)
		add_zone("caltrops", spot, lv(cfg, "radius", r), lv(cfg, "life", r), lv(cfg, "dps", r),
			{"tick": float(cfg.tick), "pin": float(cfg.pin) if hooked else 0.0})


func _stakes(dt: float, sim: Sim) -> void:
	var r := sim.rank("stakes")
	if r <= 0:
		return
	var cfg: Dictionary = sim.b.stakes
	var ring := lv(cfg, "radius", r)
	var band := float(cfg.band)
	var cpos: Vector2 = sim.commander.pos
	stakes = {"kind": "stakes", "pos": cpos, "radius": ring, "t": sim.time}
	_stake_tick -= dt
	var pulse := _stake_tick <= 0.0
	if pulse:
		_stake_tick = float(cfg.tick)
	if not pulse:
		return
	var camp := sim.rank("fortified_camp") > 0
	var dmg := stake_dps(sim) * float(cfg.tick)
	for j in sim.enemies_near(cpos, ring + band):
		if absf((sim.horde.e_pos[j] - cpos).length() - ring) > band:
			continue
		sim.hit(j, dmg, 0.0, "stakes")
		if camp:
			sim.horde.e_slow[j] = minf(sim.horde.e_slow[j], float(sim.b.fortified_camp.slow))


func _fire_pots(dt: float, sim: Sim) -> void:
	var r := sim.rank("fire_pots")
	if r <= 0 or not _go("fire_pots", dt):
		return
	var cfg: Dictionary = sim.b.fire_pots
	timers.fire_pots = lv(cfg, "every", r)
	var ahead: Vector2 = sim.commander.pos + Vector2.from_angle(sim.facing_angle) * float(cfg.ahead)
	var t := sim.nearest_enemy(ahead, float(cfg.range))
	if t < 0:
		timers.fire_pots = 0.3
		return
	var greek := sim.rank("greek_fire") > 0
	var g: Dictionary = sim.b.greek_fire
	lobs.append({"kind": "pot", "from": sim.commander.pos, "to": sim.horde.e_pos[t], "t": 0.0, "dur": float(cfg.flight),
		"radius": lv(cfg, "radius", r) * (float(g.zone_radius_mult) if greek else 1.0),
		"life": lv(cfg, "life", r) * (float(g.zone_life_mult) if greek else 1.0),
		"dps": lv(cfg, "dps", r) * (float(g.zone_dps_mult) if greek else 1.0), "tick": float(cfg.tick)})


func _oil_jars(dt: float, sim: Sim) -> void:
	var r := sim.rank("oil_jars")
	if r <= 0 or not _go("oil_jars", dt):
		return
	var cfg: Dictionary = sim.b.oil_jars
	timers.oil_jars = lv(cfg, "every", r)
	var aim: Variant = _thickest(sim, float(cfg.range))
	if aim == null:
		timers.oil_jars = 0.3
		return
	var camp := sim.rank("fortified_camp") > 0
	var f: Dictionary = sim.b.fortified_camp
	lobs.append({"kind": "oil", "from": sim.commander.pos, "to": aim, "t": 0.0, "dur": float(cfg.flight),
		"radius": lv(cfg, "radius", r) * (float(f.oil_radius_mult) if camp else 1.0),
		"life": lv(cfg, "life", r) * (float(f.oil_life_mult) if camp else 1.0), "slow": lv(cfg, "slow", r)})


func _war_dogs(dt: float, sim: Sim) -> void:
	if sim.rank("war_dogs") <= 0:
		dogs.clear()
		return
	var cfg: Dictionary = sim.b.war_dogs
	var n := dog_count(sim)
	var cpos: Vector2 = sim.commander.pos
	while dogs.size() < n:
		dogs.append({"pos": cpos, "tid": -1, "idx": -1, "cd": 0.0, "look": 0.0, "face": Vector2.RIGHT, "run": 0.0, "bit": -1e9})
	var rush: float = timers.get("rush", 0.0) - dt
	timers.rush = rush
	var speed := float(cfg.speed) * (float(sim.b.hunting_horn.speed_mult) if rush > 0.0 else 1.0)
	var dmg := lv(cfg, "damage", sim.rank("war_dogs"))
	for k in n:
		var d: Dictionary = dogs[k]
		d.cd -= dt
		d.look -= dt
		d.run += dt
		var ti: int = d.idx
		# The horde's arrays are reordered when an enemy dies, so the target is checked by its id.
		if ti >= 0 and (ti >= sim.horde.e_id.size() or sim.horde.e_id[ti] != d.tid or sim.horde.e_hp[ti] <= 0.0):
			ti = -1
		if ti < 0 and d.look <= 0.0:
			d.look = float(cfg.look_every)
			ti = sim.nearest_enemy(d.pos, float(cfg.search))
			if ti >= 0 and sim.horde.e_pos[ti].distance_to(cpos) > float(cfg.leash):
				ti = -1
			if ti >= 0:
				d.tid = sim.horde.e_id[ti]
		d.idx = ti
		var goal: Vector2
		if ti >= 0:
			goal = sim.horde.e_pos[ti]
		else:
			goal = cpos + Vector2.from_angle(sim.facing_angle + PI + (k - n / 2.0) * 0.5) * float(cfg.home)
		var to: Vector2 = goal - d.pos
		var dist := to.length()
		if ti >= 0 and dist <= float(cfg.strike):
			if d.cd <= 0.0:
				d.cd = float(cfg.cooldown)
				d.bit = sim.time
				if dist > 0.001:
					d.face = to / dist
				sim.hit(ti, dmg, 0.0, "war_dogs", d.pos)
		elif dist > 2.0:
			d.pos += to / dist * minf(dist, speed * dt)
			d.face = to / dist


func _trumpets(dt: float, sim: Sim) -> void:
	var r := sim.rank("trumpets")
	if r <= 0 or not _go("trumpets", dt):
		return
	var cfg: Dictionary = sim.b.trumpets
	timers.trumpets = lv(cfg, "every", r)
	var radius := lv(cfg, "radius", r)
	var push := lv(cfg, "push", r)
	var cpos: Vector2 = sim.commander.pos
	for j in sim.enemies_near(cpos, radius):
		var away: Vector2 = sim.horde.e_pos[j] - cpos
		var d := away.length()
		var dir := away / d if d > 0.001 else Vector2.RIGHT
		sim.horde.e_pos[j] += dir * push * (1.0 - 0.5 * d / radius)
		sim.horde.e_stun[j] = maxf(sim.horde.e_stun[j], float(cfg.stun))
	sim.effects.append({"kind": "trumpet", "pos": cpos, "t": 0.0, "radius": radius})
	if sim.rank("hunting_horn") > 0:
		# The call sends the pack off at once and hard.
		timers.rush = float(sim.b.hunting_horn.rush_seconds)
		for d in dogs:
			d.look = 0.0
			d.cd = 0.0


func _eagle(dt: float, sim: Sim) -> void:
	var r := sim.rank("eagle")
	if r <= 0 or not _go("eagle", dt):
		return
	var cfg: Dictionary = sim.b.eagle
	timers.eagle = lv(cfg, "every", r)
	var burning := sim.rank("burning_eagle") > 0
	var f: Dictionary = sim.b.burning_eagle
	var radius := lv(cfg, "radius", r)
	var dmg := lv(cfg, "damage", r) * (float(f.damage_mult) if burning else 1.0)
	for j in sim.enemies_near(sim.commander.pos, radius):
		sim.hit(j, dmg, 0.0, "eagle")
		if burning:
			sim.ignite(j, float(f.burn_dps), float(f.burn_seconds), "eagle")
	sim.effects.append({"kind": "flash", "pos": sim.commander.pos, "t": 0.0, "radius": radius})


func _torches(dt: float, sim: Sim) -> void:
	var r := sim.rank("torches")
	if r <= 0:
		return
	var cfg: Dictionary = sim.b.torches
	torch_angle += float(cfg.speed) * dt
	_torch_tick -= dt
	if _torch_tick > 0.0:
		return
	_torch_tick = float(cfg.tick)
	var burning := sim.rank("burning_eagle") > 0
	var dps := lv(cfg, "dps", r) * (float(sim.b.burning_eagle.torch_dps_mult) if burning else 1.0)
	var reach := float(cfg.reach) * _flame(sim)
	for p in torch_points(sim):
		for j in sim.enemies_near(p, reach):
			sim.ignite(j, dps, float(cfg.burn_seconds), "torches")


func _lobs(dt: float, sim: Sim) -> void:
	if lobs.is_empty():
		return
	var flying: Array = []
	for l in lobs:
		l.t += dt
		if l.t < l.dur:
			flying.append(l)
			continue
		match l.kind:
			"stone":
				_land_stone(l, sim)
			"pot":
				add_zone("fire", l.to, l.radius, l.life, l.dps, {"tick": l.tick})
			"oil":
				add_zone("oil", l.to, l.radius, l.life, 0.0, {"slow": l.slow})
	lobs = flying


func _land_stone(l: Dictionary, sim: Sim) -> void:
	for j in sim.enemies_near(l.to, l.radius):
		sim.hit(j, l.dmg, 0.0, "onager")
		var away: Vector2 = sim.horde.e_pos[j] - l.to
		var d := away.length()
		var dir := away / d if d > 0.001 else Vector2.from_angle(_rng.randf() * TAU)
		sim.horde.e_pos[j] += dir * float(l.scatter) * (1.0 - 0.5 * d / l.radius)
	sim.effects.append({"kind": "boom", "pos": l.to, "t": 0.0, "radius": l.radius})


func _zones(dt: float, sim: Sim) -> void:
	if zones.is_empty():
		return
	var keep: Array = []
	for z in zones:
		z.t += dt
		if z.t >= z.life:
			continue
		keep.append(z)
		if z.kind == "oil":
			for j in sim.enemies_near(z.pos, z.radius):
				sim.horde.e_slow[j] = minf(sim.horde.e_slow[j], z.slow)
			continue
		z.next -= dt
		if z.next > 0.0:
			continue
		z.next += z.tick
		for j in sim.enemies_near(z.pos, z.radius):
			if z.kind == "fire":
				sim.scorch(j, z.dps * z.tick, z.src)
			else:
				sim.hit(j, z.dps * z.tick, 0.0, z.src)
				if z.pin > 0.0:
					sim.horde.e_stun[j] = maxf(sim.horde.e_stun[j], z.pin)
	zones = keep
