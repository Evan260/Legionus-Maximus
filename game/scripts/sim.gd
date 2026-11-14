class_name Sim
extends RefCounted
## One run: the legion, the horde, missiles, coins and levels, as plain data so it runs and tests without a scene.

const CELL := 32.0
const KINDS := ["barbarian_club", "barbarian_spear", "chieftain"]
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

var commander := {}
var soldiers: Array = []
var facing_angle := 0.0
var moving := false

var e_id := PackedInt32Array()
var e_pos := PackedVector2Array()
var e_face := PackedVector2Array()
var e_hp := PackedFloat32Array()
var e_max := PackedFloat32Array()
var e_kind := PackedInt32Array()
var e_burn := PackedFloat32Array()
var e_burn_dps := PackedFloat32Array()
var e_flash := PackedFloat32Array()
var e_phase := PackedInt32Array()
var e_fighting := PackedByteArray()
var next_id := 1
var chieftain_id := -1

var shots: Array = []
var c_pos := PackedVector2Array()
var c_val := PackedInt32Array()
var c_pull := PackedByteArray()
var effects: Array = []

var spawn_acc := 0.0
var next_surge := 0.0
var pilum_timer := 0.0
var scorpio_timer := 0.0
var testudo_left := 0.0
var testudo_charge := 1.0

# The horde is sorted into a flat grid of cells around the commander, rebuilt every update.
const GW := 48
var g_origin := Vector2i.ZERO
var g_start := PackedInt32Array()
var g_items := PackedInt32Array()
var e_push := PackedVector2Array()
var k_radius := PackedFloat32Array()
var k_speed := PackedFloat32Array()
var k_dps := PackedFloat32Array()
var frame := 0
var legion_reach := 0.0
var u_grid := {}
var units: Array = []


func _init(balance: Dictionary, seed_value: int = 0) -> void:
	b = balance
	rng.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	var cu: Dictionary = b.units.commander
	commander = {"type": "commander", "pos": Vector2.ZERO, "hp": float(cu.hp), "max_hp": float(cu.hp), "cd": 0.0,
		"anim": 0.0, "facing": Vector2.RIGHT, "moving": false, "flash": 0.0}
	for kind in KINDS:
		k_radius.append(float(b.enemies[kind].radius))
		k_speed.append(float(b.enemies[kind].speed))
		k_dps.append(float(b.enemies[kind].dps))
	xp_next = int(b.xp_first)
	next_surge = float(b.surge_every)
	for i in int(b.start_legionaries):
		add_soldier("legionary")
	for i in int(b.start_archers):
		add_soldier("archer")
	for s in soldiers:
		s.pos = commander.pos + slot_of(s)


func rank(id: String) -> int:
	return int(ranks.get(id, 0))


func count(type: String) -> int:
	var n := 0
	for s in soldiers:
		if s.type == type:
			n += 1
	return n


func max_hp_of(type: String) -> float:
	return float(b.units[type].hp) * (1.0 + 0.2 * rank("lorica"))


func add_soldier(type: String) -> void:
	var hp := max_hp_of(type)
	soldiers.append({"type": type, "pos": commander.pos, "hp": hp, "max_hp": hp, "cd": rng.randf() * 0.5,
		"anim": rng.randf() * 8.0, "facing": Vector2.RIGHT, "moving": false, "flash": 0.0})


## Places in the formation, in the legion's own frame where +x is the way it faces.
static func formation(n_legionaries: int, n_archers: int) -> Array:
	var out: Array = []
	out.append_array(_block(n_legionaries, 22.0, 1.0))
	out.append_array(_block(n_archers, -20.0, -1.0))
	return out


static func _block(n: int, start: float, way: float) -> Array:
	var out: Array = []
	var cols := clampi(ceili(sqrt(n * 1.6)), 3, 9)
	var placed := 0
	var row := 0
	while placed < n:
		var in_row := mini(cols, n - placed)
		for c in in_row:
			# Alternate ranks sit half a place across, so the men behind see past the men in front.
			var across := (c - (in_row - 1) / 2.0) * 16.0 + (8.0 if row % 2 == 1 and in_row < cols else 0.0)
			out.append(Vector2(start + way * row * 15.0, across))
		placed += in_row
		row += 1
	return out


func slot_of(s: Dictionary) -> Vector2:
	var places := formation(count("legionary"), count("archer"))
	var li := 0
	var ai := count("legionary")
	for o in soldiers:
		if is_same(o, s):
			return places[li if s.type == "legionary" else ai].rotated(facing_angle)
		if o.type == "legionary":
			li += 1
		else:
			ai += 1
	return Vector2.ZERO


func speed() -> float:
	var v: float = b.units.commander.speed * (1.0 + 0.08 * rank("march"))
	return v * (b.testudo_speed if testudo_left > 0.0 else 1.0)


func attack_rate() -> float:
	return 1.0 + 0.12 * rank("discipline")


func pickup_radius() -> float:
	return b.pickup_radius * (1.0 + 0.3 * rank("reach"))


func update(dt: float, move: Vector2, testudo_pressed: bool) -> void:
	if over:
		return
	time += dt
	if testudo_pressed and testudo_charge >= 1.0 and testudo_left <= 0.0:
		testudo_left = b.testudo_hold + 1.0 * rank("testudo")
		testudo_charge = 0.0
	if testudo_left > 0.0:
		testudo_left -= dt
	else:
		testudo_charge = minf(1.0, testudo_charge + dt / maxf(5.0, b.testudo_recharge - 2.0 * rank("testudo")))
	_move_legion(dt, move)
	_rebuild_grids()
	_spawn(dt)
	_move_enemies(dt)
	_legion_attacks(dt)
	_arms(dt)
	_move_shots(dt)
	_burns(dt)
	_remove_dead()
	_coins(dt)
	_effects(dt)
	_regen(dt)
	if commander.hp <= 0.0:
		over = true
		victory = false


func _move_legion(dt: float, move: Vector2) -> void:
	moving = move.length() > 0.15
	if moving:
		var dir := move.normalized() if move.length() > 1.0 else move
		commander.pos += dir * speed() * dt
		facing_angle = lerp_angle(facing_angle, move.angle(), minf(1.0, dt * 5.0))
		commander.facing = move.normalized()
	commander.moving = moving
	commander.anim += dt * 10.0
	var places := formation(count("legionary"), count("archer"))
	var li := 0
	var ai := count("legionary")
	for s in soldiers:
		var off: Vector2 = places[li] if s.type == "legionary" else places[ai]
		if s.type == "legionary":
			li += 1
		else:
			ai += 1
		var target: Vector2 = commander.pos + off.rotated(facing_angle)
		var to: Vector2 = target - s.pos
		var d := to.length()
		var step := speed() * 1.5 * dt
		s.moving = d > 1.5
		if d > 0.01:
			s.pos += to / d * minf(d, step)
		s.facing = to.normalized() if d > 3.0 else commander.facing
		s.anim += dt * 10.0


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func _cidx(p: Vector2) -> int:
	var cx := floori(p.x / CELL) - g_origin.x
	var cy := floori(p.y / CELL) - g_origin.y
	if cx < 0 or cy < 0 or cx >= GW or cy >= GW:
		return -1
	return cx + cy * GW


func _rebuild_grids() -> void:
	frame += 1
	var n := e_pos.size()
	g_origin = Vector2i(floori(commander.pos.x / CELL) - GW / 2, floori(commander.pos.y / CELL) - GW / 2)
	var counts := PackedInt32Array()
	counts.resize(GW * GW + 1)
	var cell_of := PackedInt32Array()
	cell_of.resize(n)
	for i in n:
		var c := _cidx(e_pos[i])
		cell_of[i] = c
		if c >= 0:
			counts[c + 1] += 1
	for c in range(1, GW * GW + 1):
		counts[c] += counts[c - 1]
	g_items.resize(counts[GW * GW])
	var fill := counts.duplicate()
	for i in n:
		var c := cell_of[i]
		if c >= 0:
			g_items[fill[c]] = i
			fill[c] += 1
	g_start = counts
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


func enemy_hp_for(kind: int) -> float:
	var base: float = b.enemies[KINDS[kind]].hp
	if kind == 2:
		return base
	return base * (1.0 + b.enemy_health_growth * time)


func spawn_enemy(kind: int, pos: Vector2) -> void:
	e_id.append(next_id)
	if kind == 2:
		chieftain_id = next_id
	next_id += 1
	e_pos.append(pos)
	e_face.append((commander.pos - pos).normalized())
	var hp := enemy_hp_for(kind)
	e_hp.append(hp)
	e_max.append(hp)
	e_kind.append(kind)
	e_burn.append(0.0)
	e_burn_dps.append(0.0)
	e_flash.append(0.0)
	e_phase.append(rng.randi_range(0, 7))
	e_fighting.append(0)
	e_push.append(Vector2.ZERO)


func _ring_point() -> Vector2:
	var a := rng.randf() * TAU
	return commander.pos + Vector2(cos(a) * 1.15, sin(a) * 0.75) * b.spawn_radius


func _random_kind() -> int:
	return 1 if rng.randf() < 0.25 + time / 1200.0 else 0


func _spawn(dt: float) -> void:
	spawn_acc += (b.spawn_per_second_start + b.spawn_per_second_growth * time) * dt
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		if e_pos.size() < int(b.max_enemies):
			spawn_enemy(_random_kind(), _ring_point())
	if time >= next_surge:
		next_surge += b.surge_every
		# A surge comes from one side as a crowd, so the legion can see it coming and turn.
		var side := rng.randf() * TAU
		var n := int(b.surge_size_start + b.surge_size_growth * time)
		for i in n:
			if e_pos.size() >= int(b.max_enemies):
				break
			var a := side + rng.randf_range(-0.6, 0.6)
			var r: float = b.spawn_radius + rng.randf_range(0.0, 80.0)
			spawn_enemy(_random_kind(), commander.pos + Vector2(cos(a) * 1.15, sin(a) * 0.75) * r)
	if chieftain_id == -1 and time >= b.chieftain_at:
		spawn_enemy(2, _ring_point())


func _move_enemies(dt: float) -> void:
	var recycle: float = b.recycle_radius
	var cpos: Vector2 = commander.pos
	var reach2 := legion_reach * legion_reach
	var shield: float = b.testudo_damage_taken if testudo_left > 0.0 else 1.0
	var phase := frame % 3
	for i in e_pos.size():
		var kind := e_kind[i]
		var p := e_pos[i]
		var to := cpos - p
		var d := to.length()
		if d > recycle and kind != 2:
			# Barbarians left far behind come round again from ahead, so the field never empties.
			e_pos[i] = cpos - to * (b.spawn_radius / d)
			continue
		var r := k_radius[kind]
		var v := to / maxf(d, 0.001) * k_speed[kind]
		var push := e_push[i]
		# Spacing from neighbours is worked out for a third of the horde each update, in turn.
		if i % 3 == phase:
			push = Vector2.ZERO
			var c := _cidx(p)
			if c >= 0:
				var kx := c % GW
				var ky := c / GW
				var seen := 0
				for cy in range(maxi(0, ky - 1), mini(GW, ky + 2)):
					for cx in range(maxi(0, kx - 1), mini(GW, kx + 2)):
						var cell := cx + cy * GW
						for t in range(g_start[cell], g_start[cell + 1]):
							var j := g_items[t]
							if j == i:
								continue
							var away := p - e_pos[j]
							var dd := away.length_squared()
							var min_d := r + k_radius[e_kind[j]]
							if dd < min_d * min_d and dd > 0.0001:
								var dl := sqrt(dd)
								push += away / dl * (min_d - dl)
								seen += 1
								if seen > 5:
									break
			e_push[i] = push
		e_fighting[i] = 0
		if d < legion_reach + r and (to.length_squared() < reach2 or kind == 2):
			var k := _cell(p)
			var target_unit := -1
			var best := INF
			for cx in range(k.x - 1, k.x + 2):
				for cy in range(k.y - 1, k.y + 2):
					var ucell: Variant = u_grid.get(Vector2i(cx, cy))
					if ucell == null:
						continue
					for ui in ucell:
						var dd: float = (units[ui].pos - p).length()
						if dd < UNIT_RADIUS + r + 2.0 and dd < best:
							best = dd
							target_unit = ui
			if target_unit >= 0:
				var u: Dictionary = units[target_unit]
				u.hp -= k_dps[kind] * dt * shield
				u.flash = 0.08
				e_fighting[i] = 1
				var out: Vector2 = p - u.pos
				if out.length() > 0.001:
					push += out.normalized() * maxf(0.0, UNIT_RADIUS + r - out.length()) * 2.0
				v = Vector2.ZERO
		e_pos[i] = p + v * dt + push * 0.6
		if v != Vector2.ZERO:
			e_face[i] = v / k_speed[kind]
		if e_flash[i] > 0.0:
			e_flash[i] -= dt
	var alive: Array = []
	for s in soldiers:
		if s.hp > 0.0:
			alive.append(s)
		else:
			effects.append({"kind": "fallen", "pos": s.pos, "t": 0.0, "type": s.type, "facing": s.facing})
	soldiers = alive


func nearest_enemy(p: Vector2, reach: float) -> int:
	var c := _cidx(p)
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


func hit(i: int, dmg: float, burn_dps: float = 0.0) -> void:
	e_hp[i] -= dmg
	e_flash[i] = 0.1
	if burn_dps > 0.0:
		e_burn[i] = b.fire_arrows.seconds
		e_burn_dps[i] = maxf(e_burn_dps[i], burn_dps)


func _melee(u: Dictionary, dmg: float, reach: float, cooldown: float, dt: float) -> void:
	u.cd -= dt * attack_rate()
	if u.cd > 0.0:
		return
	var t := nearest_enemy(u.pos, reach + 6.0)
	if t < 0:
		return
	hit(t, dmg * (1.0 + 0.2 * rank("gladius")))
	u.cd = cooldown
	effects.append({"kind": "slash", "pos": u.pos, "to": e_pos[t], "t": 0.0})


func _legion_attacks(dt: float) -> void:
	var cu: Dictionary = b.units.commander
	_melee(commander, cu.damage, cu.reach, cu.cooldown, dt)
	var lu: Dictionary = b.units.legionary
	var au: Dictionary = b.units.archer
	for s in soldiers:
		if s.type == "legionary":
			_melee(s, lu.damage, lu.reach, lu.cooldown, dt)
		else:
			s.cd -= dt * attack_rate()
			if s.cd > 0.0:
				continue
			var t := nearest_enemy(s.pos, au.range)
			if t < 0:
				continue
			s.cd = au.cooldown
			var fire := rank("fire_arrows")
			_shoot("arrow", s.pos, e_pos[t], au.arrow_speed, au.damage * (1.0 + 0.2 * rank("gladius") * 0.5), 0,
				(b.fire_arrows.dps + b.fire_arrows.dps_per_level * (fire - 1)) if fire > 0 else 0.0)


func _shoot(kind: String, from: Vector2, to: Vector2, spd: float, dmg: float, pierce: int, burn: float = 0.0) -> void:
	var dir := (to - from).normalized()
	shots.append({"kind": kind, "pos": from + dir * 6.0, "vel": dir * spd, "dmg": dmg, "pierce": pierce,
		"burn": burn, "life": 1.4, "hit": {}})


func _arms(dt: float) -> void:
	var pr := rank("pilum")
	if pr > 0:
		pilum_timer -= dt
		if pilum_timer <= 0.0:
			var p: Dictionary = b.pilum
			pilum_timer = p.every + p.every_per_level * (pr - 1)
			var throwers := int(p.throwers + p.throwers_per_level * (pr - 1))
			var thrown := 0
			var order := soldiers.duplicate()
			order.shuffle()
			order.push_front(commander)
			for s in order:
				if thrown >= throwers:
					break
				if s.type == "archer":
					continue
				var t := nearest_enemy(s.pos, p.range)
				if t >= 0:
					_shoot("pilum", s.pos, e_pos[t], p.speed, p.damage + p.damage_per_level * (pr - 1), 1 + pr / 2)
					thrown += 1
	var sr := rank("scorpio")
	if sr > 0:
		scorpio_timer -= dt
		if scorpio_timer <= 0.0:
			var sc: Dictionary = b.scorpio
			scorpio_timer = sc.every + sc.every_per_level * (sr - 1)
			var best := -1
			var best_hp := 0.0
			var reach2: float = sc.range * sc.range
			for i in e_pos.size():
				if e_hp[i] > best_hp and (e_pos[i] - commander.pos).length_squared() < reach2:
					best_hp = e_hp[i]
					best = i
			if best >= 0:
				_shoot("bolt", commander.pos, e_pos[best], sc.speed, sc.damage + sc.damage_per_level * (sr - 1), int(sc.pierce))


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
					if s.hit.has(e_id[j]) or e_hp[j] <= 0.0:
						continue
					var r := k_radius[e_kind[j]] + 3.0
					if (e_pos[j] - s.pos).length_squared() < r * r:
						hit(j, s.dmg, s.burn)
						s.hit[e_id[j]] = true
						s.pierce -= 1
						if s.pierce < 0:
							spent = true
							break
		if not spent and s.life > 0.0:
			keep.append(s)
	shots = keep


func _burns(dt: float) -> void:
	for i in e_pos.size():
		if e_burn[i] > 0.0:
			e_burn[i] -= dt
			e_hp[i] -= e_burn_dps[i] * dt


func _remove_dead() -> void:
	var i := e_pos.size() - 1
	while i >= 0:
		if e_hp[i] <= 0.0:
			_kill(i)
		i -= 1


func _kill(i: int) -> void:
	var kind := e_kind[i]
	kills += 1
	var value := int(b.enemies[KINDS[kind]].coins)
	if value > 0:
		c_pos.append(e_pos[i])
		c_val.append(value)
		c_pull.append(0)
	effects.append({"kind": "death", "pos": e_pos[i], "t": 0.0, "type": KINDS[kind], "facing": e_face[i]})
	if e_id[i] == chieftain_id:
		over = true
		victory = true
	# Packed arrays are copied when changed through a list, so each one is moved down by name.
	var last := e_pos.size() - 1
	e_id[i] = e_id[last]; e_id.resize(last)
	e_pos[i] = e_pos[last]; e_pos.resize(last)
	e_face[i] = e_face[last]; e_face.resize(last)
	e_hp[i] = e_hp[last]; e_hp.resize(last)
	e_max[i] = e_max[last]; e_max.resize(last)
	e_kind[i] = e_kind[last]; e_kind.resize(last)
	e_burn[i] = e_burn[last]; e_burn.resize(last)
	e_burn_dps[i] = e_burn_dps[last]; e_burn_dps.resize(last)
	e_flash[i] = e_flash[last]; e_flash.resize(last)
	e_phase[i] = e_phase[last]; e_phase.resize(last)
	e_fighting[i] = e_fighting[last]; e_fighting.resize(last)
	e_push[i] = e_push[last]; e_push.resize(last)


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
	xp += value
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
	for u in [commander] + soldiers:
		if u.flash > 0.0:
			u.flash -= dt


func _regen(dt: float) -> void:
	var r := 0.6 * rank("rations")
	if r <= 0.0:
		return
	for u in [commander] + soldiers:
		u.hp = minf(u.max_hp, u.hp + r * dt)


func chieftain_index() -> int:
	return e_id.find(chieftain_id) if chieftain_id != -1 else -1


static func dir_name(v: Vector2) -> String:
	var idx := posmod(roundi(v.angle() / (PI / 4.0)), 8)
	return DIRS[idx]
