class_name Sim
extends RefCounted
## One run: the legion, the horde, missiles, coins and levels, as plain data so it runs and tests without a scene.

const CELL := 32.0
const GW := 48
const UNIT_RADIUS := 7.0
const DIRS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]

var b: Dictionary
var rng := RandomNumberGenerator.new()

var time := 0.0
var level := 1
var xp := 0
var xp_next := 0
var kills := 0
var denarii := 0
var pending_levels := 0
var over := false
var victory := false
var ranks := {}

var legion: Legion
var commander: Dictionary:
	get:
		return legion.commander
var soldiers: Array:
	get:
		return legion.soldiers
	set(value):
		legion.soldiers = value
var facing_angle := 0.0
var moving := false

var horde: Horde
var province := "germania"
var free_choices := 0
var g_origin: Vector2i:
	get:
		return horde.g_origin
var g_start: PackedInt32Array:
	get:
		return horde.g_start
var g_items: PackedInt32Array:
	get:
		return horde.g_items
var chieftain_id: int:
	get:
		return horde.chieftain_id

var shots: Array = []
var c_pos := PackedVector2Array()
var c_val := PackedInt32Array()
var c_pull := PackedByteArray()
var effects: Array = []

var arms: Arms
var rerolls := 0
var banishes := 0
var banished: Array = []
var xp_carry := 0.0
var testudo_left := 0.0
var testudo_charge := 1.0

var legion_reach := 0.0
var u_grid := {}
var units: Array = []
var content: Content
var commander_id := "tribune"
var hard := false
var endless := false
var decimatio := false
var bonuses := {}
var decimate_next := 0.0
var endless_since := -1.0
var peak_soldiers := 0
var killed_kinds := {}
var damage_by_source := {}
var history: Array = []
var numbers: Array = []
var show_numbers := false
var shake := 0.0
var _next_sample := 0.0
var _last_hp := 0.0


func _init(balance: Dictionary, game_content: Content, options := {}) -> void:
	province = options.get("province", "germania")
	commander_id = options.get("commander", "tribune")
	if not game_content.commanders.has(commander_id):
		commander_id = "tribune"
	hard = options.get("hard", false)
	endless = options.get("endless", false)
	decimatio = options.get("decimatio", false)
	bonuses = options.get("profile_bonuses", {})
	b = balance
	content = game_content
	var seed_value := int(options.get("seed", 0))
	rng.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	var kit: Dictionary = content.commanders[commander_id]
	legion = Legion.new(b, content, rng, ranks)
	arms = Arms.new(rng)
	legion.commander_hp_add = _bonus_amount("start_health")
	legion.commander_hp_mult = float(kit.get("hp_mult", 1.0))
	legion.commander.max_hp = legion.max_hp_of("commander")
	legion.commander.hp = legion.commander.max_hp
	horde = Horde.new(b, content, rng, legion.commander, province)
	horde.hard = hard
	horde.sim_ref = weakref(self)
	rerolls = int(b.rerolls) + int(kit.get("rerolls", 0)) + int(_bonus_amount("rerolls"))
	banishes = int(b.banishes) + int(_bonus_amount("banishes"))
	xp_next = int(b.xp_first)
	decimate_next = float(b.decimatio.every)
	_next_sample = float(b.history_every)
	var kit_types: Array = []
	for key in kit.starts:
		if key.begins_with("arm:"):
			ranks[key.trim_prefix("arm:")] = int(kit.starts[key])
		else:
			kit_types.append(key)
			for i in int(kit.starts[key]):
				add_soldier(key)
	if decimatio:
		var i := 0
		while soldiers.size() < int(b.decimatio.start_soldiers):
			add_soldier(kit_types[i % kit_types.size()] if not kit_types.is_empty() else "legionary")
			i += 1
	for i in int(_bonus_amount("start_soldiers")):
		add_soldier("legionary")
	legion.place_all(facing_angle)
	_last_hp = commander.hp


## The rank the profile holds in a quartermaster upgrade.
func _bonus(id: String) -> int:
	return int(bonuses.get(id, 0))


## What a quartermaster upgrade adds, its rank times its step.
func _bonus_amount(id: String) -> float:
	if not content.quartermaster.has(id):
		return 0.0
	return float(_bonus(id)) * float(content.quartermaster[id].per_rank)


func rank(id: String) -> int:
	return int(ranks.get(id, 0))


func count(type: String) -> int:
	return legion.count(type)


func max_hp_of(type: String) -> float:
	return legion.max_hp_of(type)


func add_soldier(type: String) -> void:
	legion.add(type)


func slot_of(soldier: Dictionary) -> Vector2:
	return legion.slot_of(soldier, facing_angle)


func speed() -> float:
	var v: float = content.base_commander.speed * (1.0 + 0.08 * rank("march") + _bonus_amount("move_speed")) * float(content.commanders[commander_id].get("speed_mult", 1.0))
	return v * (b.testudo_speed if testudo_left > 0.0 else 1.0)


func range_mult() -> float:
	return 1.0 + float(b.drills.better_bows) * rank("better_bows")


## How long a fire set by an arrow burns.
func burn_seconds() -> float:
	return float(b.greek_fire.seconds) if rank("greek_fire") > 0 else float(b.fire_arrows.seconds)


func attack_rate() -> float:
	return 1.0 + 0.12 * rank("discipline")


func pickup_radius() -> float:
	return b.pickup_radius * (1.0 + 0.3 * rank("reach") + _bonus_amount("pickup_radius"))


func update(dt: float, move: Vector2, testudo_pressed: bool) -> void:
	if over:
		return
	time += dt
	if testudo_pressed and testudo_charge >= 1.0 and testudo_left <= 0.0:
		testudo_left = b.testudo_hold + 1.0 * rank("testudo")
		testudo_charge = 0.0
		shake = maxf(shake, float(b.shake.testudo))
	if testudo_left > 0.0:
		testudo_left -= dt
	else:
		testudo_charge = minf(1.0, testudo_charge + dt / maxf(5.0, b.testudo_recharge - 2.0 * rank("testudo") - _bonus_amount("testudo_charge")))
	_move_legion(dt, move)
	_rebuild_grids()
	horde.update(dt, self)
	_legion_attacks(dt)
	arms.update(dt, self)
	_move_shots(dt)
	_burns(dt)
	_remove_dead()
	_coins(dt)
	_effects(dt)
	_regen(dt)
	_decimate()
	peak_soldiers = maxi(peak_soldiers, soldiers.size())
	_track(dt)
	if commander.hp <= 0.0:
		over = true
		victory = false


## The run's history sample, and the screen shake that follows the commander being hurt.
func _track(dt: float) -> void:
	if time >= _next_sample:
		_next_sample += float(b.history_every)
		history.append({"t": time, "legion": soldiers.size() + 1, "kills": kills})
	if commander.hp < _last_hp:
		shake = maxf(shake, float(b.shake.hurt))
	_last_hp = commander.hp
	shake = maxf(0.0, shake - dt)


func _move_legion(dt: float, move: Vector2) -> void:
	moving = move.length() > 0.15
	if moving:
		var dir := move.normalized() if move.length() > 1.0 else move
		commander.pos += dir * speed() * dt
		facing_angle = lerp_angle(facing_angle, move.angle(), minf(1.0, dt * 5.0))
		commander.facing = move.normalized()
	commander.moving = moving
	commander.anim += dt * 10.0
	legion.follow(dt, self)


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func _rebuild_grids() -> void:
	horde.rebuild_grid()
	legion_reach = 0.0
	for so in soldiers:
		legion_reach = maxf(legion_reach, (so.pos - commander.pos).length())
	legion_reach += 24.0
	units = [commander]
	units.append_array(soldiers)
	u_grid.clear()
	for i in units.size():
		var k := _cell(units[i].pos)
		if not u_grid.has(k):
			u_grid[k] = []
		u_grid[k].append(i)


func _cidx(p: Vector2) -> int:
	return horde.cidx(p)


func nearest_enemy(p: Vector2, reach: float) -> int:
	return horde.nearest(p, reach)


## Indexes of the living enemies within r of p.
func enemies_near(p: Vector2, r: float) -> Array:
	return horde.near(p, r)


## Every harm to an enemy goes through here so the quartermaster's damage bonus counts for hits, burns and scorching alike.
## The health it took is added to `src`, the id of the weapon or soldier type that did it, and returned.
func _harm(i: int, dmg: float, src: String) -> float:
	var full := dmg * (1.0 + _bonus_amount("damage"))
	var taken := minf(full, maxf(horde.e_hp[i], 0.0))
	horde.e_hp[i] -= full
	if src != "":
		damage_by_source[src] = float(damage_by_source.get(src, 0.0)) + taken
	return taken


## A small number rises from the enemy; the count alive is capped so a big fight stays readable.
func _number(i: int, taken: float) -> void:
	if not show_numbers or numbers.size() >= int(b.damage_numbers.cap) or taken < 0.5:
		return
	numbers.append({"pos": horde.e_pos[i] + Vector2((horde.e_id[i] * 7) % 9 - 4, -12), "v": roundi(taken), "t": 0.0})


func hit(i: int, dmg: float, burn_dps: float = 0.0, src := "") -> void:
	_number(i, _harm(i, dmg, src))
	horde.e_flash[i] = 0.1
	if burn_dps > 0.0:
		var greek: float = float(b.greek_fire.burn_mult) if rank("greek_fire") > 0 else 1.0
		ignite(i, burn_dps * greek, burn_seconds(), "fire_arrows")


## Sets an enemy alight; the burn takes its health on the next update and is counted for `src`.
func ignite(i: int, dps: float, seconds: float, src := "") -> void:
	horde.e_burn[i] = maxf(horde.e_burn[i], seconds)
	horde.e_burn_dps[i] = maxf(horde.e_burn_dps[i], dps)
	horde.e_burn_src[i] = src


## Harm from standing in fire: it takes health and shows the flames without lighting a new burn.
func scorch(i: int, dmg: float, src := "") -> void:
	_number(i, _harm(i, dmg, src))
	horde.e_burn[i] = maxf(horde.e_burn[i], 0.4)


func melee(u: Dictionary, dmg: float, reach: float, cooldown: float, dt: float) -> void:
	u.cd -= dt * attack_rate() * u.haste
	if u.cd > 0.0:
		return
	var t := nearest_enemy(u.pos, reach + 6.0)
	if t < 0:
		return
	hit(t, dmg * (1.0 + 0.2 * rank("gladius")), 0.0, u.type)
	u.cd = cooldown
	effects.append({"kind": "slash", "pos": u.pos, "to": horde.e_pos[t], "t": 0.0})


func _legion_attacks(dt: float) -> void:
	var cu: Dictionary = content.base_commander
	melee(commander, cu.damage, cu.reach, cu.cooldown, dt)
	legion.update(dt, self)


## A missile in flight; extra can set knock, bounces, bounce_reach, explode and life.
func shoot(kind: String, from: Vector2, to: Vector2, spd: float, dmg: float, pierce: int, burn: float = 0.0, extra: Dictionary = {}) -> void:
	var dir := (to - from).normalized()
	var shot := {"kind": kind, "pos": from + dir * 6.0, "vel": dir * spd, "dmg": dmg, "pierce": pierce,
		"burn": burn, "life": 1.4, "hit": {}, "knock": 0.0, "bounces": 0, "bounce_reach": 0.0, "explode": 0.0, "pin": 0.0, "src": kind}
	shot.merge(extra, true)
	shots.append(shot)


func _move_shots(dt: float) -> void:
	var keep: Array = []
	for s in shots:
		s.pos += s.vel * dt
		s.life -= dt
		var c := _cidx(s.pos)
		var spent := c < 0
		var kx := c % GW
		var ky := c / GW
		for cy in range(maxi(0, ky - 1), mini(GW, ky + 2)):
			for cx in range(maxi(0, kx - 1), mini(GW, kx + 2)):
				if spent:
					break
				var cell := cx + cy * GW
				for t in range(g_start[cell], g_start[cell + 1]):
					var j := g_items[t]
					if s.hit.has(horde.e_id[j]) or horde.e_hp[j] <= 0.0:
						continue
					var r := horde.k_radius[horde.e_kind[j]] + 3.0
					if (horde.e_pos[j] - s.pos).length_squared() < r * r:
						hit(j, s.dmg, s.burn, s.src)
						if s.pin > 0.0:
							horde.e_stun[j] = maxf(horde.e_stun[j], s.pin)
						if s.knock > 0.0:
							horde.e_pos[j] += (horde.e_pos[j] - s.pos).normalized() * s.knock
						s.hit[horde.e_id[j]] = true
						s.pierce -= 1
						if s.pierce < 0:
							if s.bounces > 0 and _bounce(s, j):
								continue
							spent = true
							break
		if not spent and s.life > 0.0:
			keep.append(s)
		elif s.explode > 0.0:
			_explode(s.pos, s.explode, s.dmg, s.src)
	shots = keep


## Turns a spent stone toward the nearest enemy it has not struck; false when none is near.
func _bounce(s: Dictionary, from_enemy: int) -> bool:
	var best := -1
	var best_d := INF
	for j in enemies_near(horde.e_pos[from_enemy], s.bounce_reach):
		if s.hit.has(horde.e_id[j]):
			continue
		var d := (horde.e_pos[j] - horde.e_pos[from_enemy]).length_squared()
		if d < best_d:
			best_d = d
			best = j
	if best < 0:
		return false
	s.bounces -= 1
	s.pierce = 0
	s.pos = horde.e_pos[from_enemy]
	s.vel = (horde.e_pos[best] - s.pos).normalized() * s.vel.length()
	return true


func _explode(p: Vector2, radius: float, dmg: float, src: String) -> void:
	for j in enemies_near(p, radius):
		hit(j, dmg, 0.0, src)
	effects.append({"kind": "boom", "pos": p, "t": 0.0, "radius": radius})


func _burns(dt: float) -> void:
	for i in horde.e_pos.size():
		if horde.e_burn[i] > 0.0:
			horde.e_burn[i] -= dt
			_harm(i, horde.e_burn_dps[i] * dt, horde.e_burn_src[i])


func _remove_dead() -> void:
	var before := kills
	var i := horde.e_pos.size() - 1
	while i >= 0:
		if horde.e_hp[i] <= 0.0:
			_kill(i)
		i -= 1
	if kills > before:
		legion.veterans(kills - before, self)


func _kill(i: int) -> void:
	var id: String = horde.kind_ids[horde.e_kind[i]]
	kills += 1
	killed_kinds[id] = true
	var pay := float(content.enemies[id].coins) * (1.0 + float(b.drills.plunder) * rank("plunder") + _bonus_amount("denarii")) * (float(b.hard.denarii_mult) if hard else 1.0)
	# A fraction of a coin is paid as the same chance of one more.
	var value := int(pay) + (1 if pay > floorf(pay) and rng.randf() < pay - floorf(pay) else 0)
	if value > 0:
		c_pos.append(horde.e_pos[i])
		c_val.append(value)
		c_pull.append(0)
	effects.append({"kind": "death", "pos": horde.e_pos[i], "t": 0.0, "type": id, "facing": horde.e_face[i]})
	if horde.e_tag[i] == Horde.ELITE:
		horde.drop_chest(horde.e_pos[i])
	if horde.e_id[i] == horde.chieftain_id:
		if endless:
			endless_since = time
		else:
			over = true
			victory = true
	horde.remove_at(i)


func _coins(dt: float) -> void:
	var r2 := pickup_radius() * pickup_radius()
	var i := c_pos.size() - 1
	while i >= 0:
		var to: Vector2 = commander.pos - c_pos[i]
		if c_pull[i] == 0 and to.length_squared() < r2:
			c_pull[i] = 1
		if c_pull[i] == 1:
			var d := to.length()
			if d < 6.0:
				gain(c_val[i])
				var last := c_pos.size() - 1
				c_pos[i] = c_pos[last]
				c_val[i] = c_val[last]
				c_pull[i] = c_pull[last]
				c_pos.resize(last)
				c_val.resize(last)
				c_pull.resize(last)
			else:
				c_pos[i] += to / d * minf(d, 220.0 * dt)
		i -= 1


func gain(value: int) -> void:
	denarii += value
	xp_carry += value * (1.0 + float(b.drills.glory) * rank("glory") + _bonus_amount("experience"))
	xp += int(xp_carry)
	xp_carry -= int(xp_carry)
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = int(b.xp_first + b.xp_step * (level - 1))
		pending_levels += 1


func _effects(dt: float) -> void:
	var keep: Array = []
	for e in effects:
		e.t += dt
		if e.t < (0.12 if e.kind == "slash" else 0.45):
			keep.append(e)
	effects = keep
	_float_numbers(dt)
	for u in [commander] + soldiers:
		if u.flash > 0.0:
			u.flash -= dt


func _float_numbers(dt: float) -> void:
	if numbers.is_empty():
		return
	var keep: Array = []
	for n in numbers:
		n.t += dt
		if n.t < float(b.damage_numbers.seconds):
			keep.append(n)
	numbers = keep


func _regen(dt: float) -> void:
	var r := 0.6 * rank("rations")
	if r <= 0.0:
		return
	for u in [commander] + soldiers:
		u.hp = minf(u.max_hp, u.hp + r * dt)


## Decimatio: every so often one soldier in ten is taken from the legion, at least one once it has ten.
func _decimate() -> void:
	if not decimatio or time < decimate_next:
		return
	decimate_next += float(b.decimatio.every)
	var n := soldiers.size()
	var lose := n / int(b.decimatio.one_in)
	for i in lose:
		var gone: Dictionary = soldiers.pop_back()
		effects.append({"kind": "fallen", "pos": gone.pos, "t": 0.0, "type": gone.type, "facing": gone.facing})


## Seconds the legion has lasted since the chieftain fell in an endless run.
func endless_seconds() -> float:
	return maxf(0.0, time - endless_since) if endless_since >= 0.0 else 0.0


func chieftain_index() -> int:
	return horde.chieftain_index()


static func dir_name(v: Vector2) -> String:
	var idx := posmod(roundi(v.angle() / (PI / 4.0)), 8)
	return DIRS[idx]
