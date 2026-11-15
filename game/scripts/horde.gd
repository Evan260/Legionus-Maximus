class_name Horde
extends RefCounted
## The enemy side of a run: every barbarian as packed arrays on a flat grid, their behaviours, elites, the chieftain, thrown spears, chests and supply carts.

const CELL := 32.0
const GW := 48
const MELEE := 0
const RANGED := 1
const CHARGER := 2
const BEAST := 3
const LOBBER := 4
const FLANKER := 5
const BEHAVIOURS := {"melee": MELEE, "ranged": RANGED, "charger": CHARGER, "beast": BEAST, "lobber": LOBBER, "flanker": FLANKER}
const ORDINARY := 0
const ELITE := 1
const CHIEF := 2

var b: Dictionary
var content: Content
var rng: RandomNumberGenerator
var commander: Dictionary
var province: String
var time := 0.0

# Per kind, indexed by e_kind. Every enemy in content.json has a slot, whether or not it is drawn yet.
var kind_ids: Array = []
var kind_of := {}
var k_radius := PackedFloat32Array()
var k_speed := PackedFloat32Array()
var k_dps := PackedFloat32Array()
var k_beh := PackedByteArray()
var k_range := PackedFloat32Array()
var k_dash_every := PackedFloat32Array()
var k_dash_mult := PackedFloat32Array()
var k_dash_secs := PackedFloat32Array()
var k_burst := PackedFloat32Array()
var k_flank_cos := PackedFloat32Array()
var k_flank_gap := PackedFloat32Array()
## The radius of the biggest kind of enemy, so searches by edge reach far enough while one that size is on the field.
var max_radius := 0.0
## How many enemies wider than Terrain.MAX_UNIT are on the field.
var big_alive := 0

# Per enemy.
var e_id := PackedInt32Array()
var e_pos := PackedVector2Array()
var e_face := PackedVector2Array()
var e_hp := PackedFloat32Array()
var e_max := PackedFloat32Array()
var e_kind := PackedInt32Array()
var e_burn := PackedFloat32Array()
var e_burn_dps := PackedFloat32Array()
var e_burn_src := PackedInt32Array()
var e_flash := PackedFloat32Array()
var e_phase := PackedInt32Array()
var e_fighting := PackedByteArray()
# When each enemy last threw, lobbed or struck a single blow, for its attack animation.
var e_strike := PackedFloat32Array()
var e_stun := PackedFloat32Array()
var e_slow := PackedFloat32Array()
var e_push := PackedVector2Array()
var e_tag := PackedByteArray()
var e_cd := PackedFloat32Array()
var e_dash := PackedFloat32Array()
# Throws left before a ranged enemy closes in to fight hand to hand.
var e_ammo := PackedInt32Array()
# Seconds left walking round an obstacle, and which way round (1 or -1).
var e_detour := PackedFloat32Array()
var e_side := PackedInt32Array()
var e_way := PackedVector2Array()
var e_dir := PackedVector2Array()
var e_haste := PackedFloat32Array()
# A bodyguard's place beside the chieftain, or zero for everyone else.
var e_guard := PackedVector2Array()
# Seconds spent failing to make headway (counting up), or, below zero, seconds left slipping through the trees to get free.
var e_stuck := PackedFloat32Array()
var next_id := 1
var chieftain_id := -1

# The horde is sorted into a flat grid of cells around the commander, rebuilt every update.
var g_origin := Vector2i.ZERO
var g_start := PackedInt32Array()
var g_items := PackedInt32Array()
# The radius of each enemy in g_items, in the same order, so spacing reads it without going through its kind.
var g_rad := PackedFloat32Array()
var g_rad_max := 0.0
var _g_cell := PackedInt32Array()
var _g_fill := PackedInt32Array()

var ordinary: Array = []
var elites: Array = []
var chief_kind := ""
var spawn_acc := 0.0
var next_surge := 0.0
var next_cart := 0.0
var next_band := 0.0
var frame := 0
var haste_mult := 1.0
var cleave_cd := 0.0
var cry_cd := 0.0
var charge_cd := 0.0
var slam_cd := 0.0
var horn_cd := 0.0
var charge_warn := 0.0
var charge_total := 0.0
var charge_from := Vector2.ZERO
var charge_dir := Vector2.ZERO
var charge_len := 0.0
var charge_width := 0.0
var charging := false
var charge_n := 0
var chief_hold := 0.0
var hold_pos := Vector2.ZERO
var sp_pos := PackedVector2Array()
var sp_vel := PackedVector2Array()
var sp_dmg := PackedFloat32Array()
var sp_life := PackedFloat32Array()
var chests: Array = []
var elite_ids: Array = []
## The elites that came on the boss timer, as opposed to an objective's defenders.
var timed_ids: Array = []
var chief_dead := false
var hard := false
var sim_ref: WeakRef
var carts: Array = []
# Burning pots thrown by war priests: each lands where a red ring marks it and hurts every Roman inside.
var foe_lobs: Array = []
# Seconds until each rallying elite, by enemy id, shouts again.
var rally_cd := {}
var next_boss := 0.0
# Telegraphs of the war priests' mending and curses, each resolving when it has filled.
var marks: Array = []
# Seconds left of a war priest's curse on the legion, and how much it slows the march.
var curse_left := 0.0
var curse_slow := 0.0
var chief_fury := false
# How much faster a raging boss moves; 1 for everyone else.
var e_fury := PackedFloat32Array()
# How hard an elite hits: softer for those who come early, harder in a rage; 1 for everyone else.
var e_power := PackedFloat32Array()
# Each elite's own ability timers and state, by enemy id, since there are only ever a few of them.
var boss := {}


func _init(balance: Dictionary, game_content: Content, random: RandomNumberGenerator, commander_unit: Dictionary, province_id: String) -> void:
	b = balance
	content = game_content
	rng = random
	commander = commander_unit
	province = province_id
	var ch: Dictionary = b.charger
	for id in content.enemies:
		var info: Dictionary = content.enemies[id]
		kind_of[id] = kind_ids.size()
		kind_ids.append(id)
		var beh: int = BEHAVIOURS.get(info.behaviour, MELEE)
		k_radius.append(float(info.radius))
		max_radius = maxf(max_radius, float(info.radius))
		k_speed.append(float(info.speed))
		k_dps.append(float(info.dps))
		k_beh.append(beh)
		k_range.append(float(info.get("range", 0.0)))
		var every := 0.0
		var mult := 1.0
		var secs := 0.0
		var burst := 0.0
		if info.has("attacks"):
			var c: Dictionary = info.attacks.charge
			every = float(c.every)
			mult = float(c.speed_mult)
			secs = float(c.seconds)
			burst = float(info.dps) * float(c.burst_mult)
		elif info.has("sprint"):
			every = float(info.sprint.every)
			mult = float(info.sprint.speed_mult)
			secs = float(info.sprint.seconds)
		elif beh == CHARGER:
			every = float(ch.every)
			mult = float(ch.speed_mult)
			secs = float(ch.seconds)
			burst = float(info.dps) * float(ch.burst_seconds)
		k_dash_every.append(every)
		k_dash_mult.append(mult)
		k_dash_secs.append(secs)
		k_burst.append(burst)
		var flank: Dictionary = info.get("flank", {})
		k_flank_cos.append(cos(float(flank.get("arrive", 0.0))))
		k_flank_gap.append(float(flank.get("gap", 1.0)))
	ordinary = content.province_enemies(province)
	for id in content.provinces[province].elites:
		if content.ready("enemies", id):
			elites.append(id)
	var chief: String = content.provinces[province].chieftain
	chief_kind = chief if content.ready("enemies", chief) else ""
	next_surge = float(b.surge_every)
	next_band = float(b.war_band.first)
	next_boss = float(b.bosses.first)
	next_cart = float(b.cart.every)
	var attacks: Dictionary = content.enemies[chief].get("attacks", {})
	cleave_cd = float(attacks.get("cleave", {}).get("every", 5.0)) * 0.5
	cry_cd = float(attacks.get("war_cry", {}).get("every", 18.0)) * 0.5
	charge_cd = float(attacks.get("charge", {}).get("every", 11.0)) * 0.5
	slam_cd = float(attacks.get("slam", {}).get("every", 9.0)) * 0.5
	horn_cd = float(attacks.get("horn", {}).get("every", 30.0)) * 0.5


## Adds an enemy and returns its index. Elites grow tougher through the run on their own curve; the chieftain keeps his listed health.
func spawn(kind_id: String, pos: Vector2, elite := false) -> int:
	var kind: int = kind_of[kind_id]
	var info: Dictionary = content.enemies[kind_id]
	var tag := ORDINARY
	if info.get("chieftain", false):
		tag = CHIEF
		chieftain_id = next_id
	elif elite or info.get("elite", false):
		tag = ELITE
		elite_ids.append(next_id)
	var hp := float(info.hp)
	if tag == ORDINARY:
		hp *= 1.0 + float(b.enemy_health_growth) * time + float(b.get("enemy_health_curve", 0.0)) * pow(time / 60.0, 2.0)
	var power := 1.0
	if tag == ELITE:
		power = early_boss_mult()
		hp *= early_boss_health() * (1.0 + float(b.bosses.health_growth) * time)
	if hard:
		hp *= float(b.hard.health_mult)
	var owner_sim: Sim = sim_ref.get_ref() if sim_ref != null else null
	var since: float = owner_sim.endless_since if owner_sim != null else -1.0
	if since >= 0.0 and tag != CHIEF:
		hp *= 1.0 + float(b.endless.health_per_minute) * floorf((time - since) / float(b.endless.step_seconds))
	e_id.append(next_id)
	next_id += 1
	e_pos.append(pos)
	e_face.append((commander.pos - pos).normalized())
	e_hp.append(hp)
	e_max.append(hp)
	e_kind.append(kind)
	if k_radius[kind] > Terrain.MAX_UNIT:
		big_alive += 1
	e_burn.append(0.0)
	e_burn_dps.append(0.0)
	e_burn_src.append(-1)
	e_flash.append(0.0)
	e_phase.append(rng.randi_range(0, 7))
	e_fighting.append(0)
	e_strike.append(-1e9)
	e_stun.append(0.0)
	e_slow.append(1.0)
	e_push.append(Vector2.ZERO)
	e_tag.append(tag)
	var beh := k_beh[kind]
	var wait := 0.0
	if tag == CHIEF:
		# The chieftain charges only after showing his path, which _chieftain starts.
		wait = INF
	elif k_dash_every[kind] > 0.0:
		wait = k_dash_every[kind] * rng.randf()
	elif beh == RANGED:
		wait = float(b.ranged.every) * (0.5 + 0.5 * rng.randf())
	e_cd.append(wait)
	e_dash.append(0.0)
	e_ammo.append(int(b.ranged.get("throws", 1 << 30)))
	e_detour.append(0.0)
	e_side.append(1)
	e_way.append(Vector2.ZERO)
	e_dir.append(Vector2.ZERO)
	e_haste.append(0.0)
	e_guard.append(Vector2.ZERO)
	e_stuck.append(0.0)
	e_fury.append(1.0)
	e_power.append(power)
	return e_id.size() - 1


## The chieftain with his bodyguard in a ring round him; returns his index.
func spawn_chieftain(pos: Vector2) -> int:
	var ci := spawn(chief_kind, pos)
	var kind: String = content.enemies[chief_kind].get("guard", "")
	if kind == "" or not content.ready("enemies", kind):
		if ordinary.is_empty():
			return ci
		kind = ordinary[0]
	var cfg: Dictionary = b.chieftain_guard
	var n := int(cfg.count)
	for k in n:
		var off := Vector2.from_angle(TAU * k / n) * float(cfg.radius)
		var j := spawn(kind, pos + off)
		e_guard[j] = off
	return ci


func ring_point() -> Vector2:
	var a := rng.randf() * TAU
	return open_point(commander.pos + Vector2(cos(a) * 1.15, sin(a) * 0.75) * b.spawn_radius)


## Where a newcomer at p arrives: p itself on open ground, or the nearest open spot round the legion when p is inside the forest.
func open_point(p: Vector2) -> Vector2:
	var owner: Sim = sim_ref.get_ref() if sim_ref != null else null
	if owner == null:
		return p
	var at := p
	for k in 8:
		if owner.terrain.is_open(at):
			return at
		at = commander.pos + (p - commander.pos).rotated(0.2 * (k / 2 + 1) * (1 if k % 2 == 0 else -1))
	return p


## An ordinary enemy for the stream: the first in the province's list most often, the rest more often as the run goes on.
## An enemy with an "arrives" time in content.json joins the stream only from that second.
func _pick_ordinary() -> String:
	var open: Array = []
	for id in ordinary:
		if float(content.enemies[id].get("arrives", 0.0)) <= time:
			open.append(id)
	if open.size() <= 1:
		return ordinary[0]
	var later := float(b.spawn_mix.later_start) + time / float(b.spawn_mix.later_seconds)
	if rng.randf() < later:
		return open[rng.randi_range(1, open.size() - 1)]
	return open[0]


func cidx(p: Vector2) -> int:
	var cx := floori(p.x / CELL) - g_origin.x
	var cy := floori(p.y / CELL) - g_origin.y
	if cx < 0 or cy < 0 or cx >= GW or cy >= GW:
		return -1
	return cx + cy * GW


func rebuild_grid() -> void:
	frame += 1
	var n := e_pos.size()
	g_origin = Vector2i(floori(commander.pos.x / CELL) - GW / 2, floori(commander.pos.y / CELL) - GW / 2)
	g_start.resize(GW * GW + 1)
	g_start.fill(0)
	_g_cell.resize(n)
	var ox := g_origin.x
	var oy := g_origin.y
	for i in n:
		var p := e_pos[i]
		var cx := floori(p.x / CELL) - ox
		var cy := floori(p.y / CELL) - oy
		var c := cx + cy * GW if cx >= 0 and cy >= 0 and cx < GW and cy < GW else -1
		_g_cell[i] = c
		if c >= 0:
			g_start[c + 1] += 1
	for c in range(1, GW * GW + 1):
		g_start[c] += g_start[c - 1]
	var total := g_start[GW * GW]
	g_items.resize(total)
	g_rad.resize(total)
	_g_fill = g_start.duplicate()
	g_rad_max = 0.0
	for i in n:
		var c := _g_cell[i]
		if c >= 0:
			var t := _g_fill[c]
			g_items[t] = i
			var rad := k_radius[e_kind[i]]
			g_rad[t] = rad
			g_rad_max = maxf(g_rad_max, rad)
			_g_fill[c] = t + 1


func update(dt: float, sim: Sim) -> void:
	# The sim can swap in a changed balance table, so the horde reads the current one.
	b = sim.b
	time = sim.time
	_spawn(dt, sim)
	_chieftain(dt, sim)
	_rally(dt, sim)
	_bosses(dt, sim)
	_move(dt, sim)
	_chieftain_after(sim)
	_bosses_after()
	_foe_lobs(dt, sim)
	_marks(dt, sim)
	_spears(dt, sim)
	_carts(dt, sim)
	_chests(sim)


func _spawn(dt: float, sim: Sim) -> void:
	spawn_acc += (b.spawn_per_second_start + b.spawn_per_second_growth * time) * (float(b.hard.spawn_mult) if hard else 1.0) * sim.objectives.spawn_mult(time) * dt
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		if e_pos.size() < int(b.max_enemies) and not ordinary.is_empty():
			spawn(_pick_ordinary(), ring_point())
	if time >= next_band:
		next_band += float(b.war_band.every)
		_war_band(sim)
	if time >= next_surge:
		next_surge += b.surge_every
		sim.event("surge", commander.pos)
		# A surge comes from one side as a crowd, so the legion can see it coming and turn.
		var side := rng.randf() * TAU
		var n := int(b.surge_size_start + b.surge_size_growth * time)
		for i in n:
			if e_pos.size() >= int(b.max_enemies) or ordinary.is_empty():
				break
			var a := side + rng.randf_range(-0.6, 0.6)
			var r: float = b.spawn_radius + rng.randf_range(0.0, 80.0)
			spawn(_pick_ordinary(), open_point(commander.pos + Vector2(cos(a) * 1.15, sin(a) * 0.75) * r))
	if time >= next_boss:
		next_boss += float(b.bosses.every)
		_boss_arrival(sim)
	if chieftain_id == -1 and chief_kind != "" and time >= b.chieftain_at:
		spawn_chieftain(sim.objectives.chieftain_point(sim))
	if time >= next_cart:
		next_cart += float(b.cart.every)
		if content.available.has("prop:supply_cart"):
			spawn_cart()


## Early bosses hit with part of their strength, growing to the full by `early_until`, so the opening stays learnable.
func early_boss_mult() -> float:
	var cfg: Dictionary = b.bosses
	return lerpf(float(cfg.early_mult), 1.0, clampf(time / float(cfg.early_until), 0.0, 1.0))


## Early bosses also come with part of their health, on their own curve so they stay tough while hitting softer.
func early_boss_health() -> float:
	var cfg: Dictionary = b.bosses
	return lerpf(float(cfg.early_health), 1.0, clampf(time / float(cfg.early_health_until), 0.0, 1.0))


## How fast early bosses use their abilities, rising to full pace by `early_until`.
func early_pace() -> float:
	var cfg: Dictionary = b.bosses
	return lerpf(float(cfg.early_pace), 1.0, clampf(time / float(cfg.early_until), 0.0, 1.0))


## Bosses come from one side on their own timer, more of them at once as the run goes on.
func _boss_arrival(sim: Sim) -> void:
	if elites.is_empty():
		return
	var cfg: Dictionary = b.bosses
	var n := mini(int(cfg.count_max), int(float(cfg.count_start) + float(cfg.count_growth) * time))
	var side := rng.randf() * TAU
	var came := false
	# Only the bosses that came on this timer count against its limit, not an objective's defender.
	timed_ids = timed_ids.filter(func(id: int) -> bool: return elite_ids.has(id))
	for k in n:
		if timed_ids.size() >= mini(int(cfg.max_alive), int(float(cfg.max_alive_start) + float(cfg.max_alive_growth) * time)):
			break
		var a := side + rng.randf_range(-0.5, 0.5)
		var at := spawn(elites[rng.randi_range(0, elites.size() - 1)], open_point(commander.pos + Vector2(cos(a) * 1.15, sin(a) * 0.75) * b.spawn_radius), true)
		timed_ids.append(e_id[at])
		came = true
	if came:
		sim.event("surge", commander.pos)


## A tight band gathers in the legion's path or closes in from behind, so marching straight on is never safe for long.
func _war_band(sim: Sim, behind := false) -> void:
	var ahead := Vector2.from_angle(sim.facing_angle)
	var dir := -ahead if behind else (ahead if rng.randf() < 0.5 else -ahead)
	war_band_at(sim, open_point(commander.pos + dir.rotated(rng.randf_range(-0.4, 0.4)) * Vector2(1.15, 0.75) * float(b.spawn_radius)))


## A war band gathered round a given point, such as the defenders of an objective; `mult` scales its size.
func war_band_at(sim: Sim, centre: Vector2, mult := 1.0) -> void:
	if ordinary.is_empty():
		return
	var wb: Dictionary = b.war_band
	var n := int((float(wb.size_start) + float(wb.size_growth) * time) * mult)
	for i in n:
		if e_pos.size() >= int(b.max_enemies):
			break
		spawn(_pick_ordinary(), centre + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, float(wb.spread)))
	sim.event("surge", commander.pos)


func chieftain_index() -> int:
	return e_id.find(chieftain_id) if chieftain_id != -1 and not chief_dead else -1


## The chieftain's cleave, war cry, charge, slam and war horn, each on its own timer.
func _chieftain(dt: float, sim: Sim) -> void:
	var ci := chieftain_index()
	if ci < 0:
		return
	var atk: Dictionary = content.enemies[kind_ids[e_kind[ci]]].get("attacks", {})
	if atk.is_empty():
		return
	var fury: Dictionary = content.enemies[kind_ids[e_kind[ci]]].get("fury", {})
	if not fury.is_empty() and not chief_fury and e_hp[ci] < e_max[ci] * float(fury.below):
		_roar(ci, sim)
	if e_stun[ci] > 0.0:
		# A stun holds his timers and calls off a charge he was warning of or running.
		charge_warn = 0.0
		charging = false
		chief_hold = 0.0
		e_dash[ci] = 0.0
		return
	var rate := float(fury.rate_mult) if chief_fury else 1.0
	cleave_cd -= dt * rate
	cry_cd -= dt * rate
	charge_cd -= dt * rate
	slam_cd -= dt * rate
	horn_cd -= dt * rate
	chief_hold = maxf(0.0, chief_hold - dt)
	if cleave_cd <= 0.0:
		cleave_cd = float(atk.cleave.every) if cleave(ci, sim) else float(atk.cleave.retry)
	if cry_cd <= 0.0:
		war_cry(ci, sim)
		cry_cd = float(atk.war_cry.every)
	if charge_warn > 0.0:
		charge_warn -= dt
		if charge_warn <= 0.0:
			e_dir[ci] = charge_dir
			e_dash[ci] = k_dash_secs[e_kind[ci]]
			charging = true
			charge_n += 1
			chief_hold = 0.0
	elif charge_cd <= 0.0 and chief_hold <= 0.0 and not charging and (commander.pos - e_pos[ci]).length() < sim.legion_reach + float(atk.charge.range):
		_warn_charge(ci, atk.charge)
	if slam_cd <= 0.0 and chief_hold <= 0.0 and not charging:
		slam_cd = float(atk.slam.every) if slam(ci, sim) else float(atk.slam.retry)
	if horn_cd <= 0.0:
		horn_cd = float(atk.horn.every)
		for k in (int(fury.bands) if chief_fury else 1):
			_war_band(sim, k == 0)


## The chieftain's second phase: below half health he roars and fights faster from then on.
func _roar(ci: int, sim: Sim) -> void:
	chief_fury = true
	sim.shake = maxf(sim.shake, float(sim.b.shake.roar))
	sim.objectives.notice = {"kind": "roar", "at": time}
	sim.event("chieftain", e_pos[ci])
	sim.effects.append({"kind": "cry", "pos": e_pos[ci], "t": 0.0, "radius": 120.0})


## Marks the chieftain's charge on the ground and holds him still until it starts.
func _warn_charge(ci: int, cfg: Dictionary) -> void:
	var kind := e_kind[ci]
	charge_cd = float(cfg.every)
	charge_warn = float(cfg.warn)
	charge_total = charge_warn
	charge_from = e_pos[ci]
	charge_dir = (commander.pos - e_pos[ci]).normalized()
	charge_len = k_speed[kind] * k_dash_mult[kind] * k_dash_secs[kind]
	charge_width = k_radius[kind] * 2.0
	_hold(ci, charge_warn)


func _hold(ci: int, seconds: float) -> void:
	chief_hold = maxf(chief_hold, seconds)
	hold_pos = e_pos[ci]


## A red ring round the chieftain that strikes everyone inside when it has filled; false when nobody is in it.
func slam(ci: int, sim: Sim) -> bool:
	var kind := e_kind[ci]
	var atk: Dictionary = content.enemies[kind_ids[kind]].attacks.slam
	var p := e_pos[ci]
	var r := float(atk.radius)
	var reach := (r + Sim.UNIT_RADIUS) * (r + Sim.UNIT_RADIUS)
	for u in sim.units:
		if (u.pos - p).length_squared() < reach:
			foe_lobs.append({"from": p, "to": p, "t": 0.0, "dur": float(atk.windup), "radius": r, "dmg": k_dps[kind] * float(atk.damage_mult), "slam": true})
			_hold(ci, float(atk.windup))
			# The chop is timed to come down as the ring fills.
			e_strike[ci] = time + float(atk.windup) - Atlas.ATTACK_FRAMES / Atlas.ATTACK_FPS
			return true
	return false


## Keeps the chieftain where he stands while he winds up, and throws aside the soldiers his charge runs into.
func _chieftain_after(sim: Sim) -> void:
	var ci := chieftain_index()
	if ci < 0:
		return
	if chief_hold > 0.0:
		e_pos[ci] = hold_pos
	if not charging:
		return
	if e_dash[ci] <= 0.0:
		charging = false
		return
	var kind := e_kind[ci]
	var throw := float(content.enemies[kind_ids[kind]].attacks.charge.throw)
	var reach := k_radius[kind] + Sim.UNIT_RADIUS + 2.0
	var side := charge_dir.orthogonal()
	var p := e_pos[ci]
	var hit_any := false
	for u in sim.units:
		var off: Vector2 = u.pos - p
		if off.length_squared() > reach * reach or u.get("thrown", -1) == charge_n:
			continue
		u.thrown = charge_n
		u.hp -= k_burst[kind] * sim.frenzy_guard()
		u.flash = 0.12
		hit_any = true
		if not is_same(u, sim.commander):
			u.pos += side * (throw if off.dot(side) >= 0.0 else -throw)
			sim.units_moved()
	if hit_any:
		sim.shake = maxf(sim.shake, float(sim.b.shake.chieftain))
		sim.legion.remove_fallen(sim)


## Hurts every soldier in an arc in front of the chieftain; false when nobody is in it.
func cleave(ci: int, sim: Sim) -> bool:
	var kind := e_kind[ci]
	var atk: Dictionary = content.enemies[kind_ids[kind]].attacks.cleave
	var reach := float(atk.reach) + k_radius[kind]
	var dir := e_face[ci]
	var half := float(atk.arc) / 2.0
	var dmg := k_dps[kind] * float(atk.damage_mult)
	var hit_any := false
	for u in sim.units:
		var to: Vector2 = u.pos - e_pos[ci]
		if to.length() > reach + 7.0 or absf(dir.angle_to(to)) > half:
			continue
		var target: Dictionary = sim.legion.shield(u)
		target.hp -= dmg * sim.frenzy_guard()
		u.flash = 0.12
		hit_any = true
	if hit_any:
		e_strike[ci] = time
		sim.effects.append({"kind": "cleave", "pos": e_pos[ci], "dir": dir, "t": 0.0, "radius": reach, "arc": float(atk.arc)})
		sim.shake = maxf(sim.shake, float(sim.b.shake.chieftain))
		sim.legion.remove_fallen(sim)
	return hit_any


## A rallying elite shouts every so often, and the barbarians around him move faster for a few seconds.
func _rally(dt: float, sim: Sim) -> void:
	for id in elite_ids:
		var i := e_id.find(id)
		if i < 0 or e_stun[i] > 0.0:
			continue
		var info: Dictionary = content.enemies[kind_ids[e_kind[i]]]
		if not info.has("rally"):
			continue
		var cfg: Dictionary = info.rally
		var left: float = rally_cd.get(id, float(cfg.every) * 0.5) - dt
		if left <= 0.0:
			left = float(cfg.every)
			var r2 := float(cfg.radius) * float(cfg.radius)
			for j in e_pos.size():
				if (e_pos[j] - e_pos[i]).length_squared() <= r2:
					e_haste[j] = float(cfg.seconds)
			haste_mult = float(cfg.speed_mult)
			sim.effects.append({"kind": "cry", "pos": e_pos[i], "t": 0.0, "radius": float(cfg.radius)})
		rally_cd[id] = left


const ABILITY_TIMERS := {"whirlwind": "whirl_cd", "shield_wall": "shield_cd", "call_band": "band_cd", "mend": "mend_cd", "curse": "curse_cd", "blink": "blink_cd"}


## The timers and state of elite i, made the first time he is asked for, each timer starting half way so a new boss acts soon.
func boss_state(i: int) -> Dictionary:
	var id := e_id[i]
	if boss.has(id):
		return boss[id]
	var info: Dictionary = content.enemies[kind_ids[e_kind[i]]]
	var st := {"hold": 0.0, "at": e_pos[i], "shield": 0.0, "shield_dir": Vector2.ZERO}
	for key in ABILITY_TIMERS:
		if info.has(key):
			st[ABILITY_TIMERS[key]] = float(info[key].every) * 0.5
	boss[id] = st
	return st


## Every elite's abilities on their own timers: the berserker's whirlwind and rage, the war band leader's shield and band, the war priest's mending, curse and blink.
func _bosses(dt: float, sim: Sim) -> void:
	curse_left = maxf(0.0, curse_left - dt)
	var paced := dt * early_pace()
	for id in elite_ids:
		var i := e_id.find(id)
		if i < 0:
			continue
		var info: Dictionary = content.enemies[kind_ids[e_kind[i]]]
		var st := boss_state(i)
		st.hold = maxf(0.0, st.hold - dt)
		st.shield = maxf(0.0, st.shield - dt)
		var p := e_pos[i]
		var gap: float = (commander.pos - p).length()
		if info.has("rage") and e_fury[i] == 1.0 and e_hp[i] < e_max[i] * float(info.rage.below):
			e_fury[i] = float(info.rage.mult)
			e_power[i] *= float(info.rage.mult)
			sim.effects.append({"kind": "cry", "pos": p, "t": 0.0, "radius": 50.0})
		if e_stun[i] > 0.0:
			continue
		if st.has("whirl_cd"):
			st.whirl_cd -= paced
			if st.whirl_cd <= 0.0 and st.hold <= 0.0:
				st.whirl_cd = _whirl(i, info.whirlwind, sim)
		if st.has("shield_cd"):
			st.shield_cd -= paced
			var cfg: Dictionary = info.shield_wall
			if st.shield_cd <= 0.0 and st.hold <= 0.0 and gap < sim.legion_reach + float(cfg.range):
				st.shield_cd = float(cfg.every)
				st.shield = float(cfg.seconds)
				st.shield_dir = (commander.pos - p).normalized()
				_hold_boss(st, p, float(cfg.seconds))
		if st.has("band_cd"):
			st.band_cd -= paced
			if st.band_cd <= 0.0:
				st.band_cd = float(info.call_band.every)
				war_band_at(sim, p, float(info.call_band.size_mult))
		if st.has("mend_cd"):
			st.mend_cd -= paced
			var cfg: Dictionary = info.mend
			if st.mend_cd <= 0.0 and st.hold <= 0.0:
				st.mend_cd = float(cfg.every)
				marks.append({"kind": "mend", "id": id, "pos": p, "t": 0.0, "dur": float(cfg.windup), "radius": float(cfg.radius), "share": float(cfg.share)})
				_hold_boss(st, p, float(cfg.windup))
		if st.has("curse_cd"):
			st.curse_cd -= paced
			var cfg: Dictionary = info.curse
			if st.curse_cd <= 0.0 and gap < float(cfg.range):
				st.curse_cd = float(cfg.every)
				marks.append({"kind": "curse", "id": id, "pos": commander.pos, "t": 0.0, "dur": float(cfg.windup), "radius": float(cfg.radius), "seconds": float(cfg.seconds), "slow": float(cfg.slow)})
				e_strike[i] = time
		if st.has("blink_cd"):
			st.blink_cd -= paced
			if st.blink_cd <= 0.0 and _blink(i, info.blink, sim):
				st.blink_cd = float(info.blink.every)


## Starts the berserker's whirlwind when a Roman is in reach and returns the seconds until he tries again.
func _whirl(i: int, cfg: Dictionary, sim: Sim) -> float:
	var p := e_pos[i]
	var r := float(cfg.radius)
	var reach := (r + Sim.UNIT_RADIUS) * (r + Sim.UNIT_RADIUS)
	for u in sim.units:
		if (u.pos - p).length_squared() < reach:
			var dur := float(cfg.windup)
			foe_lobs.append({"from": p, "to": p, "t": 0.0, "dur": dur, "radius": r, "dmg": k_dps[e_kind[i]] * float(cfg.damage_mult) * e_power[i], "slam": true, "whirl": true})
			_hold_boss(boss[e_id[i]], p, dur)
			e_strike[i] = time + dur - Atlas.ATTACK_FRAMES / Atlas.ATTACK_FPS
			return float(cfg.every)
	return float(cfg.retry)


## The war priest vanishes from a soldier at his elbow and comes out further from the legion; false when nobody is that close.
func _blink(i: int, cfg: Dictionary, sim: Sim) -> bool:
	var p := e_pos[i]
	var near := float(cfg.near) + k_radius[e_kind[i]]
	var close := false
	for u in sim.units:
		if (u.pos - p).length_squared() < near * near:
			close = true
			break
	if not close:
		return false
	var cpos: Vector2 = commander.pos
	var away := (p - cpos).normalized() if p != cpos else Vector2.RIGHT
	var to := sim.terrain.push_out(p + away.rotated(rng.randf_range(-0.6, 0.6)) * float(cfg.distance), k_radius[e_kind[i]])
	sim.effects.append({"kind": "smoke", "pos": p, "t": 0.0})
	sim.effects.append({"kind": "smoke", "pos": to, "t": 0.0})
	e_pos[i] = to
	boss[e_id[i]].at = to
	return true


func _hold_boss(st: Dictionary, at: Vector2, seconds: float) -> void:
	st.hold = maxf(st.hold, seconds)
	st.at = at


## Keeps an elite where he stands while he winds up or holds his shield, facing the way his shield points.
func _bosses_after() -> void:
	for id in elite_ids:
		var st: Dictionary = boss.get(id, {})
		if st.is_empty() or st.hold <= 0.0:
			continue
		var i := e_id.find(id)
		if i < 0:
			continue
		e_pos[i] = st.at
		if st.shield > 0.0:
			e_face[i] = st.shield_dir


## The share of a blow from `from` that reaches enemy i: a war band leader's raised shield stops most of a blow from in front.
func guard_mult(i: int, from: Vector2) -> float:
	if e_tag[i] != ELITE or not from.is_finite():
		return 1.0
	var st: Dictionary = boss.get(e_id[i], {})
	if st.is_empty() or st.shield <= 0.0:
		return 1.0
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[i]]].shield_wall
	var to := from - e_pos[i]
	if to.length_squared() < 0.0001 or absf(st.shield_dir.angle_to(to)) > float(cfg.arc) / 2.0:
		return 1.0
	return 1.0 - float(cfg.cut)


## The war priests' green and purple rings: mending heals those round him, and a curse slows the legion if the commander is still in it.
func _marks(dt: float, sim: Sim) -> void:
	if marks.is_empty():
		return
	var left: Array = []
	for m in marks:
		m.t += dt
		if m.t < m.dur:
			left.append(m)
			continue
		if m.kind == "mend":
			var pi := e_id.find(m.id)
			if pi < 0:
				continue
			var c := e_pos[pi]
			var r2: float = m.radius * m.radius
			for j in e_pos.size():
				if j != pi and (e_pos[j] - c).length_squared() <= r2:
					e_hp[j] = minf(e_max[j], e_hp[j] + e_max[j] * m.share)
			sim.effects.append({"kind": "mend", "pos": c, "t": 0.0, "radius": m.radius})
		elif m.kind == "curse":
			if (commander.pos - m.pos).length() < m.radius:
				curse_left = m.seconds
				curse_slow = m.slow
			sim.effects.append({"kind": "curse", "pos": m.pos, "t": 0.0, "radius": m.radius})
	marks = left


## A war priest throws a burning pot at the thickest knot of Romans and returns the seconds until his next throw.
func _lob_at_ranks(i: int, sim: Sim) -> float:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[i]]].lob
	var best: Vector2 = commander.pos
	var most := -1
	for k in mini(12, sim.units.size()):
		var u: Dictionary = sim.units[rng.randi_range(0, sim.units.size() - 1)]
		var near := 0
		for o in sim.units:
			if (o.pos - u.pos).length_squared() < float(cfg.radius) * float(cfg.radius):
				near += 1
		if near > most:
			most = near
			best = u.pos
	foe_lobs.append({"from": e_pos[i], "to": best, "t": 0.0, "dur": float(cfg.flight), "radius": float(cfg.radius), "dmg": float(cfg.damage) * e_power[i]})
	e_strike[i] = time
	if best != e_pos[i]:
		e_face[i] = (best - e_pos[i]).normalized()
	return float(cfg.every) / early_pace()


func _foe_lobs(dt: float, sim: Sim) -> void:
	if foe_lobs.is_empty():
		return
	var flying: Array = []
	var shield: float = (b.testudo_damage_taken if sim.testudo_left > 0.0 else 1.0) * sim.frenzy_guard()
	for l in foe_lobs:
		l.t += dt
		if l.t < l.dur:
			flying.append(l)
			continue
		for u in sim.units:
			if (u.pos - l.to).length() < l.radius + Sim.UNIT_RADIUS:
				u.hp -= l.dmg * shield
				u.flash = 0.12
		sim.effects.append({"kind": "whirl" if l.get("whirl", false) else "boom", "pos": l.to, "t": 0.0, "radius": l.radius})
		sim.shake = maxf(sim.shake, float(sim.b.shake.hurt))
	foe_lobs = flying
	sim.legion.remove_fallen(sim)


## The chieftain's shout: every enemy near him moves faster for a few seconds.
func war_cry(ci: int, sim: Sim) -> void:
	var atk: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.war_cry
	haste_mult = float(atk.speed_mult)
	var r2 := float(atk.radius) * float(atk.radius)
	var centre := e_pos[ci]
	for i in e_pos.size():
		if (e_pos[i] - centre).length_squared() <= r2:
			e_haste[i] = float(atk.seconds)
	sim.effects.append({"kind": "cry", "pos": centre, "t": 0.0, "radius": float(atk.radius)})
	sim.event("chieftain", centre)
	sim.shake = maxf(sim.shake, float(sim.b.shake.chieftain))


func _move(dt: float, sim: Sim) -> void:
	var recycle: float = b.recycle_radius
	var cpos: Vector2 = commander.pos
	var legion_reach := sim.legion_reach
	var reach2 := legion_reach * legion_reach
	var shield: float = (b.testudo_damage_taken if sim.testudo_left > 0.0 else 1.0) * sim.frenzy_guard()
	var phase := frame % 3
	var slow_recover: float = b.slow_recover
	var wall := 1.0 - float(b.drills.shield_wall) * sim.rank("shield_wall")
	var throw_every: float = b.ranged.every
	var dash_min: float = b.charger.min_distance
	var dash_max: float = b.charger.max_distance
	var sep_range: float = b.separation_range
	var units := sim.units
	var ug_near := sim.ug_near
	var ug_start := sim.ug_start
	var ug_items := sim.ug_items
	var ug_all_in := sim.ug_all_in
	var ox := g_origin.x
	var oy := g_origin.y
	var t_origin := sim.terrain.origin
	var t_start := sim.terrain.start
	var t_items := sim.terrain.items
	var t_solid := sim.terrain.solid
	var t_tree := sim.terrain.solid_tree
	var rv_start := sim.terrain.rv_start
	var chop_rate: float = b.felling.barbarian_rate * dt
	var t_cell := Terrain.CELL
	var t_n := Terrain.GN
	var f_dir := sim.terrain.flow_dir
	var f_ready := not f_dir.is_empty()
	var f_origin := sim.terrain.flow_origin
	var f_cell := Terrain.FLOW_CELL
	var f_n := Terrain.FN
	var held := 0
	var solid_range: float = b.get("solid_range", 400.0)
	var detour_seconds: float = b.detour.seconds
	var stuck_after: float = b.detour.stuck_after
	var stuck_slip: float = b.detour.stuck_slip
	var rear := -Vector2.from_angle(sim.facing_angle)
	var ci := chieftain_index()
	var chief_pos := e_pos[ci] if ci >= 0 else Vector2.ZERO
	var through := ci if charging else -1
	var gs := g_start
	var gi := g_items
	var gr := g_rad
	for i in e_pos.size():
		var kind := e_kind[i]
		var p := e_pos[i]
		var to := cpos - p
		var d := to.length()
		if d > recycle and e_tag[i] != CHIEF and e_guard[i] == Vector2.ZERO:
			# Barbarians left far behind come round again from ahead, so the field never empties.
			e_pos[i] = cpos - to * (b.spawn_radius / d)
			continue
		if e_stun[i] > 0.0:
			e_stun[i] -= dt
			e_fighting[i] = 0
			if e_flash[i] > 0.0:
				e_flash[i] -= dt
			continue
		var r := k_radius[kind]
		var slow := e_slow[i]
		if slow < 1.0:
			e_slow[i] = minf(1.0, slow + dt * slow_recover)
		var spd := k_speed[kind] * slow * e_fury[i]
		var power := e_power[i]
		if e_haste[i] > 0.0:
			e_haste[i] -= dt
			spd *= haste_mult
		var v := to / maxf(d, 0.001) * spd
		var beh := k_beh[kind]
		var circling := false
		if beh == FLANKER:
			var n := -to / maxf(d, 0.001)
			if n.dot(rear) < k_flank_cos[kind]:
				# A flanker walks round the legion just outside its reach, turning the shorter way towards its rear.
				circling = true
				var gap := k_flank_gap[kind]
				var turn := 1.0 if n.x * rear.y - n.y * rear.x > 0.0 else -1.0
				var radial := clampf((legion_reach + gap - d) / gap, -2.0, 1.0)
				v = (Vector2(-n.y, n.x) * turn + n * radial).normalized() * spd
		var g := e_guard[i]
		if g != Vector2.ZERO:
			var gto := chief_pos + g - p
			var gl := gto.length()
			v = gto * (minf(spd, gl / dt) / gl) if gl > 0.5 else Vector2.ZERO
		var dashing := false
		var lobber := beh == LOBBER
		var throwing := (beh == RANGED and e_ammo[i] > 0) or lobber
		if throwing:
			if d <= k_range[kind] + legion_reach:
				v = Vector2.ZERO
				e_cd[i] -= dt
				if lobber and e_cd[i] <= 0.0:
					e_cd[i] = _lob_at_ranks(i, sim)
				elif e_cd[i] <= 0.0:
					e_cd[i] = throw_every
					# A thrower aims at the nearest Roman, so the outer ranks take the axes before the commander does.
					var aim := to
					var best := d * d
					for u in units:
						var off: Vector2 = u.pos - p
						if off.length_squared() < best:
							best = off.length_squared()
							aim = off
					_throw(p, aim.normalized(), k_dps[kind] * throw_every)
					e_ammo[i] -= 1
					e_strike[i] = time
					e_face[i] = aim.normalized()
		elif k_dash_every[kind] > 0.0:
			if e_dash[i] > 0.0:
				e_dash[i] -= dt
				dashing = true
				v = e_dir[i] * spd * k_dash_mult[kind]
			else:
				e_cd[i] -= dt
				if e_cd[i] <= 0.0 and d > dash_min and d < dash_max and not circling:
					e_cd[i] = k_dash_every[kind]
					e_dir[i] = to / maxf(d, 0.001)
					e_dash[i] = k_dash_secs[kind]
		var push := e_push[i]
		# Spacing from neighbours is worked out for a third of the horde each update, in turn.
		# Enemies beyond the screen are not spaced apart, since nobody can see them bunch up.
		if i % 3 == phase and d < sep_range:
			push = Vector2.ZERO
			var c := cidx(p)
			if c >= 0:
				var kx := c % GW
				var ky := c / GW
				var seen := 0
				# A boss wider than a grid square looks further for the barbarians he would overlap.
				var ring := 1 if r + r <= CELL else 2
				# Only the cells within reach of the widest neighbour on the field can hold one he overlaps.
				var reach := r + g_rad_max
				var x0 := maxi(maxi(0, kx - ring), floori((p.x - reach) / CELL) - g_origin.x)
				var x1 := mini(mini(GW - 1, kx + ring), floori((p.x + reach) / CELL) - g_origin.x)
				var y0 := maxi(maxi(0, ky - ring), floori((p.y - reach) / CELL) - g_origin.y)
				var y1 := mini(mini(GW - 1, ky + ring), floori((p.y + reach) / CELL) - g_origin.y)
				for cy in range(y0, y1 + 1):
					for cx in range(x0, x1 + 1):
						var cell := cx + cy * GW
						# The enemy himself is in the list too, but at no distance he fails the test below.
						for t in range(gs[cell], gs[cell + 1]):
							var away := p - e_pos[gi[t]]
							var dd := away.length_squared()
							var min_d := r + gr[t]
							if dd < min_d * min_d and dd > 0.0001:
								var dl := sqrt(dd)
								push += away / dl * (min_d - dl)
								seen += 1
								if seen > 5:
									break
						if seen > 5:
							break
					if seen > 5:
						break
			e_push[i] = push
		elif i % 3 == phase:
			# A push worked out earlier is dropped once the enemy is beyond the spacing range.
			e_push[i] = Vector2.ZERO
			push = Vector2.ZERO
		e_fighting[i] = 0
		if not throwing and i != through and d < legion_reach + r and (to.length_squared() < reach2 or e_tag[i] == CHIEF):
			var target_unit := -1
			var span := 1 if r + Sim.UNIT_RADIUS + 2.0 <= CELL else ceili((r + Sim.UNIT_RADIUS + 2.0) / CELL)
			var kx := floori(p.x / CELL) - ox
			var ky := floori(p.y / CELL) - oy
			if not ug_all_in:
				target_unit = _nearest_unit(p, r, span, sim)
			elif r > Sim.NEAR_RADIUS or kx < 0 or ky < 0 or kx >= GW or ky >= GW or ug_near[kx + ky * GW] == 1:
				# Only the cells within striking reach of p can hold the unit he strikes.
				var hit_r := Sim.UNIT_RADIUS + r + 2.0
				var best := INF
				for cx in range(maxi(0, maxi(kx - span, floori((p.x - hit_r) / CELL) - ox)), mini(GW, mini(kx + span, floori((p.x + hit_r) / CELL) - ox) + 1)):
					for cy in range(maxi(0, maxi(ky - span, floori((p.y - hit_r) / CELL) - oy)), mini(GW, mini(ky + span, floori((p.y + hit_r) / CELL) - oy) + 1)):
						var cell := cx + cy * GW
						for t in range(ug_start[cell], ug_start[cell + 1]):
							var ui := ug_items[t]
							var dd: float = (units[ui].pos - p).length()
							if dd < hit_r and dd < best:
								best = dd
								target_unit = ui
			if target_unit >= 0:
				var u: Dictionary = sim.legion.shield(units[target_unit])
				var guard := shield * (wall if u.get("place", "") == "front" else 1.0)
				u.hp -= k_dps[kind] * dt * guard * power
				if dashing:
					u.hp -= k_burst[kind] * guard * power
					e_dash[i] = 0.0
				u.flash = 0.08
				e_fighting[i] = 1
				var foe: Vector2 = units[target_unit].pos - p
				if foe.length_squared() > 0.000001:
					e_face[i] = foe.normalized()
				held += 1
				var out: Vector2 = p - u.pos
				if out.length() > 0.001:
					push += out.normalized() * maxf(0.0, Sim.UNIT_RADIUS + r - out.length()) * 2.0
				v = Vector2.ZERO
		if e_detour[i] > 0.0:
			e_detour[i] -= dt
			if v != Vector2.ZERO:
				var way := e_way[i]
				var fx := floori((p.x - f_origin.x) / f_cell)
				var fy := floori((p.y - f_origin.y) / f_cell)
				if f_ready and fx >= 0 and fy >= 0 and fx < f_n and fy < f_n and f_dir[fx + fy * f_n] != Vector2.ZERO:
					way = f_dir[fx + fy * f_n]
				v = way * spd
		var np := p + v * dt + push * 0.6
		# Trees and rocks push the barbarian back out, read straight from the terrain grid since this runs for the whole horde.
		# Barbarians well off the screen pass through, since nobody sees them and the check is costly for a full horde.
		var gx := floori((np.x - t_origin.x) / t_cell)
		var gy := floori((np.y - t_origin.y) / t_cell)
		if d < solid_range and e_stuck[i] >= 0.0 and gx >= 0 and gy >= 0 and gx < t_n and gy < t_n:
			var gc := gx + gy * t_n
			for t in range(t_start[gc], t_start[gc + 1]):
				var so := t_solid[t_items[t]]
				var ax := np.x - so.x
				var ay := np.y - so.y
				var reach := so.z + r
				var d2 := ax * ax + ay * ay
				if d2 < reach * reach and d2 > 0.000001:
					var dl := sqrt(d2)
					np = Vector2(so.x + ax / dl * reach, so.y + ay / dl * reach)
					if v != Vector2.ZERO and t_tree[t_items[t]] == 1:
						sim.terrain.horde_chop(Vector2(so.x, so.y), chop_rate)
					# A barbarian walking into a tree or rock slides along it on the side that leads towards the legion, and keeps that side a while.
					if v != Vector2.ZERO:
						var along := Vector2(-ay, ax) / dl
						if e_detour[i] <= 0.0:
							e_side[i] = 1 if along.dot(to) >= 0.0 else -1
						e_way[i] = along * e_side[i]
						e_detour[i] = detour_seconds
			if r > Terrain.MAX_UNIT:
				np = sim.terrain.push_out_wide(np, r)
		# Every barbarian in the grid is held at a ravine's lip every other update, which is enough since one step is shorter than his radius.
		if (i + frame) % 2 == 0 and gx >= 0 and gy >= 0 and gx < t_n and gy < t_n and rv_start[gx + gy * t_n] < rv_start[gx + gy * t_n + 1]:
			var kept := sim.terrain.ravine_push(np, r, r > Terrain.MAX_UNIT)
			if kept != np:
				if v != Vector2.ZERO:
					var out_of := (kept - np).normalized()
					var along := Vector2(-out_of.y, out_of.x)
					if e_detour[i] <= 0.0:
						e_side[i] = 1 if along.dot(to) >= 0.0 else -1
					e_way[i] = along * e_side[i]
					e_detour[i] = detour_seconds
				np = kept
		# A barbarian wedged among trees who makes no headway for a while slips through them for a moment to get free.
		if e_stuck[i] < 0.0:
			e_stuck[i] = minf(0.0, e_stuck[i] + dt)
		elif v != Vector2.ZERO and (np - p).length_squared() < v.length_squared() * dt * dt * 0.0625:
			e_stuck[i] += dt
			if e_stuck[i] > stuck_after:
				e_stuck[i] = -stuck_slip
		elif e_stuck[i] > 0.0:
			e_stuck[i] = maxf(0.0, e_stuck[i] - dt)
		e_pos[i] = np
		if v != Vector2.ZERO:
			e_face[i] = e_dir[i] if dashing else (v.normalized() if circling else to / maxf(d, 0.001))
		if e_flash[i] > 0.0:
			e_flash[i] -= dt
	sim.pressing = held
	sim.legion.remove_fallen(sim)


## The index in sim.units of the nearest unit close enough for an enemy at p of radius r to strike, or -1, from the cells the units stood in when the grids were built.
func _nearest_unit(p: Vector2, r: float, span: int, sim: Sim) -> int:
	var units := sim.units
	var target_unit := -1
	var best := INF
	var k := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	var cells := sim.unit_cells()
	for cx in range(k.x - span, k.x + span + 1):
		for cy in range(k.y - span, k.y + span + 1):
			var ucell: Variant = cells.get(Vector2i(cx, cy))
			if ucell == null:
				continue
			for ui in ucell:
				var dd: float = (units[ui].pos - p).length()
				if dd < Sim.UNIT_RADIUS + r + 2.0 and dd < best:
					best = dd
					target_unit = ui
	return target_unit


func _throw(from: Vector2, dir: Vector2, dmg: float) -> void:
	var cfg: Dictionary = b.ranged
	sp_pos.append(from + dir * 6.0)
	sp_vel.append(dir * float(cfg.spear_speed))
	sp_dmg.append(dmg)
	sp_life.append(float(cfg.spear_life))


## Thrown spears fly straight; the raised testudo stops them at the edge of the legion, and otherwise the first soldier they touch is hurt.
func _spears(dt: float, sim: Sim) -> void:
	var n := sp_pos.size()
	if n == 0:
		return
	var blocked := sim.testudo_left > 0.0
	var reach: float = sim.legion_reach
	var cpos: Vector2 = commander.pos
	var hit_radius := Sim.UNIT_RADIUS + float(b.ranged.spear_radius)
	var scan := reach + hit_radius
	var scan2 := scan * scan
	var reach2 := reach * reach
	var struck := false
	var i := n - 1
	while i >= 0:
		var p := sp_pos[i] + sp_vel[i] * dt
		sp_pos[i] = p
		var life := sp_life[i] - dt
		sp_life[i] = life
		var gone := life <= 0.0
		var gap2 := (p - cpos).length_squared()
		if not gone and gap2 <= scan2:
			if blocked and gap2 < reach2:
				sim.effects.append({"kind": "spark", "pos": p, "t": 0.0})
				gone = true
			else:
				var ui := _spear_target(p, hit_radius, sim)
				if ui >= 0:
					var u: Dictionary = sim.units[ui]
					var target: Dictionary = sim.legion.shield(u)
					target.hp -= sp_dmg[i] * sim.frenzy_guard()
					u.flash = 0.08
					gone = true
					struck = true
		if gone:
			var last := sp_pos.size() - 1
			sp_pos[i] = sp_pos[last]; sp_pos.resize(last)
			sp_vel[i] = sp_vel[last]; sp_vel.resize(last)
			sp_dmg[i] = sp_dmg[last]; sp_dmg.resize(last)
			sp_life[i] = sp_life[last]; sp_life.resize(last)
		i -= 1
	if struck:
		sim.legion.remove_fallen(sim)


## The first unit, in grid order, within hit_radius of a spear at p, or -1.
func _spear_target(p: Vector2, hit_radius: float, sim: Sim) -> int:
	var kx := floori(p.x / CELL) - g_origin.x
	var ky := floori(p.y / CELL) - g_origin.y
	if sim.ug_all_in:
		for cx in range(maxi(0, kx - 1), mini(GW, kx + 2)):
			for cy in range(maxi(0, ky - 1), mini(GW, ky + 2)):
				var cell := cx + cy * GW
				for t in range(sim.ug_start[cell], sim.ug_start[cell + 1]):
					if (sim.units[sim.ug_items[t]].pos - p).length() < hit_radius:
						return sim.ug_items[t]
		return -1
	var cells := sim.unit_cells()
	for cx in range(kx + g_origin.x - 1, kx + g_origin.x + 2):
		for cy in range(ky + g_origin.y - 1, ky + g_origin.y + 2):
			var ucell: Variant = cells.get(Vector2i(cx, cy))
			if ucell == null:
				continue
			for ui in ucell:
				if (sim.units[ui].pos - p).length() < hit_radius:
					return ui
	return -1


## A supply cart rolls across the field in a straight line, passing near the commander.
## A stranded supply cart stands somewhere on screen for the legion to reach before it is plundered.
func spawn_cart() -> void:
	var cfg: Dictionary = b.cart
	var at: Vector2 = commander.pos + Vector2.from_angle(rng.randf() * TAU) * Vector2(1.6, 1.0) * rng.randf_range(float(cfg.near), float(cfg.far))
	var owner_sim: Sim = sim_ref.get_ref() if sim_ref != null else null
	if owner_sim != null:
		at = owner_sim.terrain.push_out(at, float(cfg.radius))
	carts.append({"pos": at, "t": 0.0})


func _carts(dt: float, sim: Sim) -> void:
	if carts.is_empty():
		return
	var cfg: Dictionary = b.cart
	var keep: Array = []
	for cart in carts:
		cart.t += dt
		if cart.t > float(cfg.life):
			continue
		var touched := false
		for u in sim.units:
			if (u.pos - cart.pos).length() < float(cfg.radius):
				touched = true
				break
		if touched:
			open_cart(sim)
		else:
			keep.append(cart)
	carts = keep


## Breaking a cart gives one of three rewards; the choice is named so a test can ask for each.
func open_cart(sim: Sim, reward := "") -> void:
	if reward == "":
		reward = ["free_choice", "heal", "magnet"][rng.randi_range(0, 2)]
	match reward:
		"free_choice":
			sim.free_choices += 1
		"heal":
			heal_legion(sim)
		"magnet":
			sim.c_pull.fill(1)


func heal_legion(sim: Sim) -> void:
	for u in [sim.commander] + sim.soldiers:
		u.hp = u.max_hp
	sim.effects.append({"kind": "heal", "pos": commander.pos, "t": 0.0})


## An elite leaves a chest when the chest is drawn.
func drop_chest(pos: Vector2) -> void:
	if content.available.has("prop:chest"):
		chests.append({"pos": pos})


func _chests(sim: Sim) -> void:
	if chests.is_empty():
		return
	var r: float = b.chest.radius
	var keep: Array = []
	for ch in chests:
		if (ch.pos - commander.pos).length() < r:
			sim.free_choices += 1
		else:
			keep.append(ch)
	chests = keep


func nearest(p: Vector2, reach: float) -> int:
	var c := cidx(p)
	if c < 0:
		return -1
	var kx := c % GW
	var ky := c / GW
	var rings := ceili(reach / CELL)
	var best := -1
	var best_d := reach * reach
	for cy in range(maxi(0, ky - rings), mini(GW, ky + rings + 1)):
		for cx in range(maxi(0, kx - rings), mini(GW, kx + rings + 1)):
			var cell := cx + cy * GW
			for t in range(g_start[cell], g_start[cell + 1]):
				var j := g_items[t]
				var dd := (e_pos[j] - p).length_squared()
				if dd < best_d and e_hp[j] > 0.0:
					best_d = dd
					best = j
	return best


## The living enemy whose edge is nearest p within reach, so a soldier pressed against a big boss can strike him.
func nearest_edge(p: Vector2, reach: float) -> int:
	var c := cidx(p)
	if c < 0:
		return -1
	var kx := c % GW
	var ky := c / GW
	# Melee soldiers search every update, so the wide search is kept for while a boss is on the field.
	var rings := ceili((reach + (max_radius if big_alive > 0 else 6.0)) / CELL)
	var best := -1
	var best_d := reach
	for cy in range(maxi(0, ky - rings), mini(GW, ky + rings + 1)):
		for cx in range(maxi(0, kx - rings), mini(GW, kx + rings + 1)):
			var cell := cx + cy * GW
			for t in range(g_start[cell], g_start[cell + 1]):
				var j := g_items[t]
				var dd := (e_pos[j] - p).length() - k_radius[e_kind[j]]
				if dd < best_d and e_hp[j] > 0.0:
					best_d = dd
					best = j
	return best


## Indexes of the living enemies within r of p.
func near(p: Vector2, r: float) -> Array:
	var out: Array = []
	var c := cidx(p)
	if c < 0:
		return out
	var kx := c % GW
	var ky := c / GW
	var rings := ceili(r / CELL)
	var r2 := r * r
	for cy in range(maxi(0, ky - rings), mini(GW, ky + rings + 1)):
		for cx in range(maxi(0, kx - rings), mini(GW, kx + rings + 1)):
			var cell := cx + cy * GW
			for t in range(g_start[cell], g_start[cell + 1]):
				var j := g_items[t]
				if e_hp[j] > 0.0 and (e_pos[j] - p).length_squared() <= r2:
					out.append(j)
	return out


## Takes enemy i out by moving the last one into its place, array by array.
func remove_at(i: int) -> void:
	if e_id[i] == chieftain_id:
		chief_dead = true
		e_guard.fill(Vector2.ZERO)
	if e_tag[i] == ELITE:
		elite_ids.erase(e_id[i])
		boss.erase(e_id[i])
		rally_cd.erase(e_id[i])
	if k_radius[e_kind[i]] > Terrain.MAX_UNIT:
		big_alive -= 1
	var last := e_pos.size() - 1
	e_id[i] = e_id[last]; e_id.resize(last)
	e_pos[i] = e_pos[last]; e_pos.resize(last)
	e_face[i] = e_face[last]; e_face.resize(last)
	e_hp[i] = e_hp[last]; e_hp.resize(last)
	e_max[i] = e_max[last]; e_max.resize(last)
	e_kind[i] = e_kind[last]; e_kind.resize(last)
	e_burn[i] = e_burn[last]; e_burn.resize(last)
	e_burn_dps[i] = e_burn_dps[last]; e_burn_dps.resize(last)
	e_burn_src[i] = e_burn_src[last]
	e_burn_src.resize(last)
	e_flash[i] = e_flash[last]; e_flash.resize(last)
	e_phase[i] = e_phase[last]; e_phase.resize(last)
	e_fighting[i] = e_fighting[last]; e_fighting.resize(last)
	e_strike[i] = e_strike[last]; e_strike.resize(last)
	e_stun[i] = e_stun[last]; e_stun.resize(last)
	e_slow[i] = e_slow[last]; e_slow.resize(last)
	e_push[i] = e_push[last]; e_push.resize(last)
	e_tag[i] = e_tag[last]; e_tag.resize(last)
	e_cd[i] = e_cd[last]; e_cd.resize(last)
	e_dash[i] = e_dash[last]; e_dash.resize(last)
	e_ammo[i] = e_ammo[last]; e_ammo.resize(last)
	e_detour[i] = e_detour[last]; e_detour.resize(last)
	e_side[i] = e_side[last]; e_side.resize(last)
	e_way[i] = e_way[last]; e_way.resize(last)
	e_dir[i] = e_dir[last]; e_dir.resize(last)
	e_haste[i] = e_haste[last]; e_haste.resize(last)
	e_guard[i] = e_guard[last]; e_guard.resize(last)
	e_stuck[i] = e_stuck[last]; e_stuck.resize(last)
	e_fury[i] = e_fury[last]; e_fury.resize(last)
	e_power[i] = e_power[last]; e_power.resize(last)
