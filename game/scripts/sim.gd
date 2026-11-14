class_name Sim
extends RefCounted
## One run: the legion, the horde, missiles, coins and levels, as plain data so it runs and tests without a scene.

const CELL := 32.0
const GW := 48
const UNIT_RADIUS := 7.0
## Kinds that happen many times an update are counted and reported once per update; the rest are reported as they happen.
const COUNTED := ["hit", "kill", "coin", "arrow", "pilum", "bolt"]
const EVENT_CAP := 64
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
## The demo's time limit in seconds (0 for none), and whether the run ended by reaching it.
var demo_seconds := 0.0
var demo_over := false
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
# How many barbarians were locked in melee with the legion on the last update.
var pressing := 0

var horde: Horde
var terrain: Terrain
var objectives := Objectives.new()
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

## What the sound reads: {kind, pos} and, for counted kinds, how many (n). The reader clears the list.
var events: Array = []
var shots: Array = []
var c_pos := PackedVector2Array()
var c_val := PackedInt32Array()
var c_pull := PackedByteArray()
var c_born := PackedFloat32Array()
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
var damage_by_source: Dictionary:
	get:
		return _fold_damage()
var history: Array = []
var numbers: Array = []
var show_numbers := false
var shake := 0.0
var _next_sample := 0.0
var _damage_named := {}
var _damage := PackedFloat64Array()
var _src_ids := {}
var _src_names: Array = []
var _last_hp := 0.0
var _tally_n := PackedInt32Array([0, 0, 0, 0, 0, 0])
var _tally_pos := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _chieftain_heard := false
## Logs from felled trees, spent on palisades.
var timber := 0
## When a palisade was last asked for without the timber for it, for the notice.
var palisade_refused_at := -1.0


func _init(balance: Dictionary, game_content: Content, options := {}) -> void:
	province = options.get("province", "germania")
	commander_id = options.get("commander", "tribune")
	if not game_content.commanders.has(commander_id):
		commander_id = "tribune"
	hard = options.get("hard", false)
	endless = options.get("endless", false)
	decimatio = options.get("decimatio", false)
	demo_seconds = float(options.get("demo_seconds", 0.0))
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
	terrain = Terrain.new(rng.seed, b.forest)
	terrain.clear_radius = float(b.get("terrain_clear_radius", 200.0))
	terrain.fell_seconds = float(b.felling.seconds)
	objectives.place_start(self, options.get("objectives_near", false))
	terrain.refresh(legion.commander.pos)
	horde.hard = hard
	horde.sim_ref = weakref(self)
	rerolls = int(b.rerolls) + int(kit.get("rerolls", 0)) + int(_bonus_amount("rerolls"))
	banishes = int(b.banishes) + int(_bonus_amount("banishes"))
	xp_next = int(b.xp_first)
	decimate_next = float(b.decimatio.every)
	_next_sample = float(b.history_every)
	_build_sources()
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
	# Barbarians locked in melee hold the legion back, so marching into a crowd bogs it down instead of passing through.
	var held := maxf(float(b.press.slowest), 1.0 - float(b.press.per_enemy) * pressing)
	return v * held * (b.testudo_speed if testudo_left > 0.0 else 1.0)


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
	terrain.clock = time
	if testudo_pressed and testudo_charge >= 1.0 and testudo_left <= 0.0:
		event("testudo", commander.pos)
		testudo_left = b.testudo_hold + 1.0 * rank("testudo")
		testudo_charge = 0.0
		shake = maxf(shake, float(b.shake.testudo))
	if testudo_left > 0.0:
		testudo_left -= dt
	else:
		testudo_charge = minf(1.0, testudo_charge + dt / maxf(5.0, b.testudo_recharge - 2.0 * rank("testudo") - _bonus_amount("testudo_charge")))
	_move_legion(dt, move)
	_rebuild_grids()
	objectives.before_horde(self)
	horde.update(dt, self)
	objectives.update(dt, self)
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
	if not _chieftain_heard and horde.chieftain_id != -1:
		_chieftain_heard = true
		event("chieftain", commander.pos)
	_flush_events()
	if commander.hp <= 0.0:
		over = true
		# A chieftain already slain in an endless run keeps the win.
		victory = endless_since >= 0.0
	elif not over and demo_seconds > 0.0 and time >= demo_seconds:
		over = true
		victory = true
		demo_over = true


## Reports something rare at once. The list is capped so a reader that never clears it cannot grow it.
func event(kind: String, pos: Vector2) -> void:
	if events.size() < EVENT_CAP:
		events.append({"kind": kind, "pos": pos})


## Counts something frequent; `flush` turns each count into one event at the end of the update.
func tally(kind_index: int, pos: Vector2) -> void:
	_tally_n[kind_index] += 1
	_tally_pos[kind_index] = pos


func _flush_events() -> void:
	for i in COUNTED.size():
		if _tally_n[i] > 0:
			if events.size() < EVENT_CAP:
				events.append({"kind": COUNTED[i], "pos": _tally_pos[i], "n": _tally_n[i]})
			_tally_n[i] = 0


## Gives every weapon and soldier type an int id once, so a harm is a plain array add.
func _build_sources() -> void:
	var names: Array = ["commander"]
	for kind in ["recruits", "arms", "forged"]:
		names.append_array(content.get(kind).keys())
	for n in names:
		_src_ids[n] = _src_names.size()
		_src_names.append(n)
	_damage.resize(_src_names.size())


## The damage per source id, named; read when the summary or a test asks for it.
func _fold_damage() -> Dictionary:
	for i in _src_names.size():
		if _damage[i] > 0.0:
			_damage_named[_src_names[i]] = _damage[i]
	return _damage_named


## The run's history sample, and the screen shake that follows the commander being hurt.
func _track(dt: float) -> void:
	if time >= _next_sample:
		_next_sample += float(b.history_every)
		history.append({"t": time, "legion": soldiers.size() + 1, "kills": kills})
	if commander.hp < _last_hp:
		shake = maxf(shake, float(b.shake.hurt))
		event("hurt", commander.pos)
	_last_hp = commander.hp


func _move_legion(dt: float, move: Vector2) -> void:
	moving = move.length() > 0.15
	if moving:
		var dir := move.normalized() if move.length() > 1.0 else move
		commander.pos += dir * speed() * dt
		facing_angle = lerp_angle(facing_angle, move.angle(), minf(1.0, dt * 5.0))
		commander.facing = move.normalized()
	commander.pos = terrain.push_out(commander.pos, UNIT_RADIUS, dt)
	terrain.rot_posts(time)
	terrain.refresh(commander.pos)
	terrain.update_flow(commander.pos)
	commander.moving = moving
	commander.anim += dt * 10.0
	legion.follow(dt, self)
	for so in soldiers:
		so.pos = terrain.push_out(so.pos, UNIT_RADIUS, dt)
	var fallen := terrain.fell_ready()
	if fallen > 0:
		timber += fallen * int(b.felling.timber)
		event("fell", commander.pos)
		terrain.refresh(commander.pos)


## The commander and the soldiers standing in the formation, not those out on a sortie.
func units_in_formation() -> Array:
	var out: Array = [commander]
	for so in soldiers:
		if so.sortie == 0:
			out.append(so)
	return out


## Where the palisade's stakes go: a shallow arc across the legion's facing, `ahead` px beyond its front rank, its ends bowed back.
func palisade_points() -> Array:
	var cfg: Dictionary = b.palisade
	var dir := Vector2.from_angle(facing_angle)
	var front := 0.0
	for u in units_in_formation():
		front = maxf(front, (u.pos - commander.pos).dot(dir))
	var n := int(cfg.stakes)
	var out: Array = []
	for k in n:
		var t := (k - (n - 1) / 2.0) / maxf(1.0, (n - 1) / 2.0)
		out.append(commander.pos + dir * (front + float(cfg.ahead) - float(cfg.bow) * t * t) + dir.orthogonal() * t * (n - 1) / 2.0 * float(cfg.gap))
	return out


## Spends timber on a line of stakes ahead of the legion, leaving out any place a man stands; without the timber it is refused.
func build_palisade() -> bool:
	var cfg: Dictionary = b.palisade
	if timber < int(cfg.cost):
		event("back", commander.pos)
		palisade_refused_at = time
		return false
	timber -= int(cfg.cost)
	var radius := float(cfg.radius)
	for p in palisade_points():
		var free := true
		for u in [commander] + soldiers:
			free = free and u.pos.distance_to(p) >= radius + UNIT_RADIUS
		if free:
			terrain.add_post(p, radius, time + float(cfg.seconds))
	terrain.refresh(commander.pos)
	event("palisade", commander.pos)
	return true


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
func _harm(i: int, dmg: float, src: int) -> float:
	var full := dmg * (1.0 + _bonus_amount("damage"))
	var taken := minf(full, maxf(horde.e_hp[i], 0.0))
	horde.e_hp[i] -= full
	if src >= 0:
		_damage[src] += taken
	return taken


## The id of a source name, or -1 when it has none.
func src_id(src: String) -> int:
	return _src_ids.get(src, -1)


## A small number rises from the enemy; the count alive is capped so a big fight stays readable.
func _number(i: int, taken: float) -> void:
	if not show_numbers or numbers.size() >= int(b.damage_numbers.cap) or taken < 0.5:
		return
	numbers.append({"pos": horde.e_pos[i] + Vector2((horde.e_id[i] * 7) % 9 - 4, -12), "v": roundi(taken), "t": 0.0})


func hit(i: int, dmg: float, burn_dps: float = 0.0, src := "") -> void:
	_number(i, _harm(i, dmg, src_id(src)))
	tally(0, horde.e_pos[i])
	horde.e_flash[i] = 0.1
	if burn_dps > 0.0:
		var greek: float = float(b.greek_fire.burn_mult) if rank("greek_fire") > 0 else 1.0
		ignite(i, burn_dps * greek, burn_seconds(), "fire_arrows")


## Sets an enemy alight; the burn takes its health on the next update and is counted for `src`.
func ignite(i: int, dps: float, seconds: float, src := "") -> void:
	horde.e_burn[i] = maxf(horde.e_burn[i], seconds)
	horde.e_burn_dps[i] = maxf(horde.e_burn_dps[i], dps)
	horde.e_burn_src[i] = src_id(src)


## Harm from standing in fire: it takes health and shows the flames without lighting a new burn.
func scorch(i: int, dmg: float, src := "") -> void:
	_number(i, _harm(i, dmg, src_id(src)))
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
	var counted := COUNTED.find(kind)
	if counted >= 0:
		tally(counted, from)
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
	tally(1, horde.e_pos[i])
	killed_kinds[id] = true
	var pay := float(content.enemies[id].coins) * (1.0 + float(b.drills.plunder) * rank("plunder") + _bonus_amount("denarii")) * (float(b.hard.denarii_mult) if hard else 1.0)
	# A fraction of a coin is paid as the same chance of one more.
	var value := int(pay) + (1 if pay > floorf(pay) and rng.randf() < pay - floorf(pay) else 0)
	if value > 0:
		drop_coin(horde.e_pos[i], value)
	effects.append({"kind": "death", "pos": horde.e_pos[i], "t": 0.0, "type": id, "facing": horde.e_face[i]})
	if horde.e_tag[i] == Horde.ELITE:
		horde.drop_chest(horde.e_pos[i])
	if horde.e_id[i] == horde.chieftain_id:
		win(horde.e_pos[i])
	horde.remove_at(i)


## The chieftain's death or the fort's gate wins the run; an endless run keeps going and counts the win once.
func win(pos: Vector2) -> void:
	victory = true
	event("victory", pos)
	if not endless:
		over = true
	elif endless_since < 0.0:
		endless_since = time


## The denarii the run banks: those carried and the purses of the objectives done.
func banked_denarii() -> int:
	return denarii + objectives.purse


## Leaves a coin on the field. Past the cap, the oldest coins still lying there are merged into one of their total value.
func drop_coin(pos: Vector2, value: int) -> void:
	c_pos.append(pos)
	c_val.append(value)
	c_pull.append(0)
	c_born.append(time)
	if c_pos.size() <= int(b.max_coins):
		return
	var lying: Array = []
	for i in c_pos.size():
		if c_pull[i] == 0:
			lying.append(i)
	lying.sort_custom(func(x: int, y: int) -> bool: return c_born[x] < c_born[y])
	var merge := lying.slice(0, int(b.coin_merge))
	if merge.size() < 2:
		return
	var total := 0
	for i in merge:
		total += c_val[i]
	var keep: int = merge[0]
	c_val[keep] = total
	merge.remove_at(0)
	# Removing from the highest index down keeps the lower indices valid.
	merge.sort()
	for k in range(merge.size() - 1, -1, -1):
		var i: int = merge[k]
		var last := c_pos.size() - 1
		c_pos[i] = c_pos[last]
		c_val[i] = c_val[last]
		c_pull[i] = c_pull[last]
		c_born[i] = c_born[last]
		c_pos.resize(last)
		c_val.resize(last)
		c_pull.resize(last)
		c_born.resize(last)


func _coins(dt: float) -> void:
	var r2 := pickup_radius() * pickup_radius()
	var far := legion_reach + pickup_radius()
	var far2 := far * far
	var i := c_pos.size() - 1
	while i >= 0:
		var to: Vector2 = commander.pos - c_pos[i]
		if c_pull[i] == 0 and (to.length_squared() < r2 or (to.length_squared() < far2 and _unit_near(c_pos[i], r2))):
			c_pull[i] = 1
		if c_pull[i] == 1:
			var d := to.length()
			if d < 6.0:
				tally(2, commander.pos)
				gain(c_val[i])
				var last := c_pos.size() - 1
				c_pos[i] = c_pos[last]
				c_val[i] = c_val[last]
				c_pull[i] = c_pull[last]
				c_born[i] = c_born[last]
				c_pos.resize(last)
				c_val.resize(last)
				c_pull.resize(last)
				c_born.resize(last)
			else:
				c_pos[i] += to / d * minf(d, 220.0 * dt)
		i -= 1


## Whether any soldier stands within the pickup radius of p, so the whole legion gathers coins for the commander.
func _unit_near(p: Vector2, r2: float) -> bool:
	var k := _cell(p)
	var span := ceili(sqrt(r2) / CELL)
	for cx in range(k.x - span, k.x + span + 1):
		for cy in range(k.y - span, k.y + span + 1):
			var cell: Variant = u_grid.get(Vector2i(cx, cy))
			if cell == null:
				continue
			for ui in cell:
				if (units[ui].pos - p).length_squared() < r2:
					return true
	return false


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
		event("level", commander.pos)


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
	# The commander slowly recovers on his own, so stray axes wear him down only while the fighting is thick.
	if commander.hp > 0.0:
		commander.hp = minf(commander.max_hp, commander.hp + float(b.get("commander_regen", 0.0)) * dt)
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
