class_name Horde
extends RefCounted
## The enemy side of a run: every barbarian as packed arrays on a flat grid, their behaviours, elites, the chieftain, thrown spears, chests and supply carts.

const CELL := 32.0
const GW := 48
const MELEE := 0
const RANGED := 1
const CHARGER := 2
const BEAST := 3
const BEHAVIOURS := {"melee": MELEE, "ranged": RANGED, "charger": CHARGER, "beast": BEAST}
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
var e_stun := PackedFloat32Array()
var e_slow := PackedFloat32Array()
var e_push := PackedVector2Array()
var e_tag := PackedByteArray()
var e_cd := PackedFloat32Array()
var e_dash := PackedFloat32Array()
var e_dir := PackedVector2Array()
var e_haste := PackedFloat32Array()
var next_id := 1
var chieftain_id := -1

# The horde is sorted into a flat grid of cells around the commander, rebuilt every update.
var g_origin := Vector2i.ZERO
var g_start := PackedInt32Array()
var g_items := PackedInt32Array()

var ordinary: Array = []
var elites: Array = []
var chief_kind := ""
var spawn_acc := 0.0
var next_surge := 0.0
var next_cart := 0.0
var frame := 0
var haste_mult := 1.0
var cleave_cd := 0.0
var cry_cd := 0.0
var sp_pos := PackedVector2Array()
var sp_vel := PackedVector2Array()
var sp_dmg := PackedFloat32Array()
var sp_life := PackedFloat32Array()
var chests: Array = []
var elite_ids: Array = []
var chief_dead := false
var hard := false
var sim_ref: WeakRef
var carts: Array = []


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
		elif beh == CHARGER:
			every = float(ch.every)
			mult = float(ch.speed_mult)
			secs = float(ch.seconds)
			burst = float(info.dps) * float(ch.burst_seconds)
		k_dash_every.append(every)
		k_dash_mult.append(mult)
		k_dash_secs.append(secs)
		k_burst.append(burst)
	ordinary = content.province_enemies(province)
	for id in content.provinces[province].elites:
		if content.ready("enemies", id):
			elites.append(id)
	var chief: String = content.provinces[province].chieftain
	chief_kind = chief if content.ready("enemies", chief) else ""
	next_surge = float(b.surge_every)
	next_cart = float(b.cart.every)
	var attacks: Dictionary = content.enemies[chief].get("attacks", {})
	cleave_cd = float(attacks.get("cleave", {}).get("every", 5.0)) * 0.5
	cry_cd = float(attacks.get("war_cry", {}).get("every", 18.0)) * 0.5


## Adds an enemy and returns its index. Elites, and the chieftain, keep their listed health for the whole run.
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
		hp *= 1.0 + float(b.enemy_health_growth) * time
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
	e_burn.append(0.0)
	e_burn_dps.append(0.0)
	e_burn_src.append(-1)
	e_flash.append(0.0)
	e_phase.append(rng.randi_range(0, 7))
	e_fighting.append(0)
	e_stun.append(0.0)
	e_slow.append(1.0)
	e_push.append(Vector2.ZERO)
	e_tag.append(tag)
	var beh := k_beh[kind]
	var wait := 0.0
	if k_dash_every[kind] > 0.0:
		wait = k_dash_every[kind] * rng.randf()
	elif beh == RANGED:
		wait = float(b.ranged.every) * (0.5 + 0.5 * rng.randf())
	e_cd.append(wait)
	e_dash.append(0.0)
	e_dir.append(Vector2.ZERO)
	e_haste.append(0.0)
	return e_id.size() - 1


func ring_point() -> Vector2:
	var a := rng.randf() * TAU
	return commander.pos + Vector2(cos(a) * 1.15, sin(a) * 0.75) * b.spawn_radius


## An ordinary enemy of the province: the first listed at first, the others more often as the run goes on.
func _pick_ordinary() -> String:
	if ordinary.size() == 1:
		return ordinary[0]
	var later := float(b.spawn_mix.later_start) + time / float(b.spawn_mix.later_seconds)
	if rng.randf() < later:
		return ordinary[1] if ordinary.size() == 2 else ordinary[rng.randi_range(1, ordinary.size() - 1)]
	return ordinary[0]


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
	var counts := PackedInt32Array()
	counts.resize(GW * GW + 1)
	var cell_of := PackedInt32Array()
	cell_of.resize(n)
	for i in n:
		var c := cidx(e_pos[i])
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


func update(dt: float, sim: Sim) -> void:
	# The sim can swap in a changed balance table, so the horde reads the current one.
	b = sim.b
	time = sim.time
	_spawn(dt, sim)
	_chieftain(dt, sim)
	_move(dt, sim)
	_spears(dt, sim)
	_carts(dt, sim)
	_chests(sim)


func _spawn(dt: float, sim: Sim) -> void:
	spawn_acc += (b.spawn_per_second_start + b.spawn_per_second_growth * time) * (float(b.hard.spawn_mult) if hard else 1.0) * dt
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		if e_pos.size() < int(b.max_enemies) and not ordinary.is_empty():
			spawn(_pick_ordinary(), ring_point())
	if time >= next_surge:
		next_surge += b.surge_every
		# A surge comes from one side as a crowd, so the legion can see it coming and turn.
		var side := rng.randf() * TAU
		var n := int(b.surge_size_start + b.surge_size_growth * time)
		for i in n:
			if e_pos.size() >= int(b.max_enemies) or ordinary.is_empty():
				break
			var a := side + rng.randf_range(-0.6, 0.6)
			var r: float = b.spawn_radius + rng.randf_range(0.0, 80.0)
			spawn(_pick_ordinary(), commander.pos + Vector2(cos(a) * 1.15, sin(a) * 0.75) * r)
		if not elites.is_empty():
			for i in int(b.elites_per_surge):
				var a := side + rng.randf_range(-0.3, 0.3)
				spawn(elites[rng.randi_range(0, elites.size() - 1)], commander.pos + Vector2(cos(a) * 1.15, sin(a) * 0.75) * b.spawn_radius, true)
	if chieftain_id == -1 and chief_kind != "" and time >= b.chieftain_at:
		spawn(chief_kind, ring_point())
	if time >= next_cart:
		next_cart += float(b.cart.every)
		if content.available.has("prop:supply_cart"):
			spawn_cart()


func chieftain_index() -> int:
	return e_id.find(chieftain_id) if chieftain_id != -1 and not chief_dead else -1


## The chieftain's cleave and war cry, each on its own timer; his charge is the dash every enemy of that kind has.
func _chieftain(dt: float, sim: Sim) -> void:
	var ci := chieftain_index()
	if ci < 0:
		return
	var atk: Dictionary = content.enemies[kind_ids[e_kind[ci]]].get("attacks", {})
	if atk.is_empty():
		return
	cleave_cd -= dt
	cry_cd -= dt
	if cleave_cd <= 0.0:
		cleave_cd = float(atk.cleave.every) if cleave(ci, sim) else float(atk.cleave.retry)
	if cry_cd <= 0.0:
		war_cry(ci, sim)
		cry_cd = float(atk.war_cry.every)


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
		target.hp -= dmg
		u.flash = 0.12
		hit_any = true
	if hit_any:
		sim.effects.append({"kind": "cleave", "pos": e_pos[ci], "dir": dir, "t": 0.0, "radius": reach, "arc": float(atk.arc)})
		sim.shake = maxf(sim.shake, float(sim.b.shake.chieftain))
		sim.legion.remove_fallen(sim)
	return hit_any


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
	sim.shake = maxf(sim.shake, float(sim.b.shake.chieftain))


func _move(dt: float, sim: Sim) -> void:
	var recycle: float = b.recycle_radius
	var cpos: Vector2 = commander.pos
	var legion_reach := sim.legion_reach
	var reach2 := legion_reach * legion_reach
	var shield: float = b.testudo_damage_taken if sim.testudo_left > 0.0 else 1.0
	var phase := frame % 3
	var slow_recover: float = b.slow_recover
	var wall := 1.0 - float(b.drills.shield_wall) * sim.rank("shield_wall")
	var throw_every: float = b.ranged.every
	var dash_min: float = b.charger.min_distance
	var dash_max: float = b.charger.max_distance
	var sep_range: float = b.separation_range
	var u_grid := sim.u_grid
	var units := sim.units
	for i in e_pos.size():
		var kind := e_kind[i]
		var p := e_pos[i]
		var to := cpos - p
		var d := to.length()
		if d > recycle and e_tag[i] != CHIEF:
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
		var spd := k_speed[kind] * slow
		if e_haste[i] > 0.0:
			e_haste[i] -= dt
			spd *= haste_mult
		var v := to / maxf(d, 0.001) * spd
		var dashing := false
		if k_beh[kind] == RANGED:
			if d <= k_range[kind] + legion_reach:
				v = Vector2.ZERO
				e_cd[i] -= dt
				if e_cd[i] <= 0.0:
					e_cd[i] = throw_every
					_throw(p, to / maxf(d, 0.001), k_dps[kind] * throw_every)
		elif k_dash_every[kind] > 0.0:
			if e_dash[i] > 0.0:
				e_dash[i] -= dt
				dashing = true
				v = e_dir[i] * spd * k_dash_mult[kind]
			else:
				e_cd[i] -= dt
				if e_cd[i] <= 0.0 and d > dash_min and d < dash_max:
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
		if k_beh[kind] != RANGED and d < legion_reach + r and (to.length_squared() < reach2 or e_tag[i] == CHIEF):
			var k := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
			var target_unit := -1
			var best := INF
			for cx in range(k.x - 1, k.x + 2):
				for cy in range(k.y - 1, k.y + 2):
					var ucell: Variant = u_grid.get(Vector2i(cx, cy))
					if ucell == null:
						continue
					for ui in ucell:
						var dd: float = (units[ui].pos - p).length()
						if dd < Sim.UNIT_RADIUS + r + 2.0 and dd < best:
							best = dd
							target_unit = ui
			if target_unit >= 0:
				var u: Dictionary = sim.legion.shield(units[target_unit])
				var guard := shield * (wall if u.get("place", "") == "front" else 1.0)
				u.hp -= k_dps[kind] * dt * guard
				if dashing:
					u.hp -= k_burst[kind] * guard
					e_dash[i] = 0.0
				u.flash = 0.08
				e_fighting[i] = 1
				var out: Vector2 = p - u.pos
				if out.length() > 0.001:
					push += out.normalized() * maxf(0.0, Sim.UNIT_RADIUS + r - out.length()) * 2.0
				v = Vector2.ZERO
		e_pos[i] = p + v * dt + push * 0.6
		if v != Vector2.ZERO:
			e_face[i] = to / maxf(d, 0.001) if not dashing else e_dir[i]
		if e_flash[i] > 0.0:
			e_flash[i] -= dt
	sim.legion.remove_fallen(sim)


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
				var k := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
				for cx in range(k.x - 1, k.x + 2):
					for cy in range(k.y - 1, k.y + 2):
						var ucell: Variant = sim.u_grid.get(Vector2i(cx, cy))
						if ucell == null or gone:
							continue
						for ui in ucell:
							var u: Dictionary = sim.units[ui]
							if (u.pos - p).length() < hit_radius:
								var target: Dictionary = sim.legion.shield(u)
								target.hp -= sp_dmg[i]
								u.flash = 0.08
								gone = true
								struck = true
								break
		if gone:
			var last := sp_pos.size() - 1
			sp_pos[i] = sp_pos[last]; sp_pos.resize(last)
			sp_vel[i] = sp_vel[last]; sp_vel.resize(last)
			sp_dmg[i] = sp_dmg[last]; sp_dmg.resize(last)
			sp_life[i] = sp_life[last]; sp_life.resize(last)
		i -= 1
	if struck:
		sim.legion.remove_fallen(sim)


## A supply cart rolls across the field in a straight line, passing near the commander.
func spawn_cart() -> void:
	var cfg: Dictionary = b.cart
	var from := ring_point()
	var aim: Vector2 = commander.pos + Vector2(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0)) * float(cfg.aim_scatter)
	carts.append({"pos": from, "vel": (aim - from).normalized() * float(cfg.speed), "t": 0.0})


func _carts(dt: float, sim: Sim) -> void:
	if carts.is_empty():
		return
	var cfg: Dictionary = b.cart
	var keep: Array = []
	for cart in carts:
		cart.pos += cart.vel * dt
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
	if e_tag[i] == ELITE:
		elite_ids.erase(e_id[i])
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
	e_stun[i] = e_stun[last]; e_stun.resize(last)
	e_slow[i] = e_slow[last]; e_slow.resize(last)
	e_push[i] = e_push[last]; e_push.resize(last)
	e_tag[i] = e_tag[last]; e_tag.resize(last)
	e_cd[i] = e_cd[last]; e_cd.resize(last)
	e_dash[i] = e_dash[last]; e_dash.resize(last)
	e_dir[i] = e_dir[last]; e_dir.resize(last)
	e_haste[i] = e_haste[last]; e_haste.resize(last)
