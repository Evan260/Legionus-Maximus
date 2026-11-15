class_name Gods
extends RefCounted
## The favour of the gods, which fills as barbarians die, and the five gods the legion can call once it is full.
## Every number is under "gods" in balance.json; the sim calls `update` each step and the views draw what is kept here.

const IDS := ["jupiter", "neptune", "mars", "vulcan", "apollo"]

var favour := 0
var calls := 0
## The gods called this run, so the tablinum can show them.
var called := {}
## The god last called and when, for the name written across the screen.
var last := {}
var storm_left := 0.0
var frenzy_left := 0.0
var burn_left := 0.0
var light_left := 0.0
var wave := {}
var bolts: Array = []
var meteors: Array = []
var flash := 0.0
var quake := 0.0

var _strike_acc := 0.0
var _thrown := {}
var _boss_taken := {}


## The kills the next call needs: more after every call.
func need(b: Dictionary) -> int:
	return int(b.gods.favour_first) + int(b.gods.favour_step) * calls


func full(b: Dictionary) -> bool:
	return favour >= need(b)


## Whether a god's power is still at work, when kills add no favour so one call cannot pay for the next.
func busy() -> bool:
	return storm_left > 0.0 or frenzy_left > 0.0 or burn_left > 0.0 or not wave.is_empty()


func on_kill(b: Dictionary) -> void:
	if not busy():
		favour = mini(favour + 1, need(b))


## Three different gods that are drawn, or none while the favour is not full.
static func offers(sim: Sim) -> Array:
	if not sim.gods.full(sim.b):
		return []
	var pool: Array = []
	for id in IDS:
		if sim.content.ready("gods", id):
			pool.append(id)
	for i in range(pool.size() - 1, 0, -1):
		var j := sim.rng.randi_range(0, i)
		var t: Variant = pool[i]
		pool[i] = pool[j]
		pool[j] = t
	return pool.slice(0, 3)


## Whether a point on the field is on the screen round the commander.
static func on_screen(sim: Sim, p: Vector2) -> bool:
	var half: Array = sim.b.gods.view_half
	var off: Vector2 = p - sim.commander.pos
	return absf(off.x) <= float(half[0]) and absf(off.y) <= float(half[1])


## The living barbarians on screen, by index.
static func targets(sim: Sim) -> Array:
	var out: Array = []
	var h := sim.horde
	for i in h.e_pos.size():
		if h.e_hp[i] > 0.0 and on_screen(sim, h.e_pos[i]):
			out.append(i)
	return out


## Spends the favour and calls a god at once.
func invoke(sim: Sim, id: String) -> void:
	var g: Dictionary = sim.b.gods
	favour = 0
	calls += 1
	called[id] = true
	last = {"id": id, "at": sim.time}
	_boss_taken.clear()
	match id:
		"jupiter":
			storm_left = float(g.jupiter.seconds)
			_strike_acc = 0.0
			flash = float(g.jupiter.flash)
			sim.shake = maxf(sim.shake, float(sim.b.shake.chieftain))
			sim.event("chieftain", sim.commander.pos)
		"neptune":
			wave = {"pos": sim.commander.pos, "t": 0.0}
			_thrown.clear()
			quake = float(g.neptune.shake_seconds)
			sim.shake = maxf(sim.shake, quake)
			sim.event("testudo", sim.commander.pos)
			sim.event("roar", sim.commander.pos)
		"mars":
			frenzy_left = float(g.mars.seconds)
			sim.event("victory", sim.commander.pos)
			sim.event("drum", sim.commander.pos)
		"vulcan":
			_vulcan(sim, g.vulcan)
			sim.event("surge", sim.commander.pos)
		"apollo":
			_apollo(sim, g.apollo)
			sim.event("level", sim.commander.pos)


## A god's damage to one barbarian, a share of its own health so it fells the toughest late barbarian too.
func strike(sim: Sim, i: int, share: float, src: String) -> void:
	sim.hit(i, share * sim.horde.e_max[i], 0.0, src)


## How much of a god's harm a boss takes: at most `boss_share` of his health over one call.
func boss_cap(sim: Sim, i: int, dmg: float) -> float:
	var h := sim.horde
	if h.e_tag[i] == Horde.ORDINARY:
		return dmg
	var id := h.e_id[i]
	var room := float(sim.b.gods.boss_share) * h.e_max[i] - float(_boss_taken.get(id, 0.0))
	var take := clampf(dmg, 0.0, maxf(room, 0.0))
	_boss_taken[id] = float(_boss_taken.get(id, 0.0)) + take
	return take


func update(dt: float, sim: Sim) -> void:
	flash = maxf(0.0, flash - dt * 2.5)
	light_left = maxf(0.0, light_left - dt)
	frenzy_left = maxf(0.0, frenzy_left - dt)
	burn_left = maxf(0.0, burn_left - dt)
	if not bolts.is_empty():
		var keep: Array = []
		for bolt in bolts:
			bolt.t += dt
			if bolt.t < float(sim.b.gods.jupiter.bolt_seconds):
				keep.append(bolt)
		bolts = keep
	if storm_left > 0.0:
		_storm(dt, sim)
	if not wave.is_empty() or not _thrown.is_empty():
		_quake(dt, sim)
	if not meteors.is_empty():
		_rain(dt, sim)


## Jupiter's bolts fall on living barbarians on screen, each felling the one it strikes and those beside him.
func _storm(dt: float, sim: Sim) -> void:
	var cfg: Dictionary = sim.b.gods.jupiter
	storm_left -= dt
	_strike_acc += dt * float(cfg.strikes_per_second)
	var n := int(_strike_acc)
	if n <= 0:
		return
	_strike_acc -= n
	var list := targets(sim)
	var h := sim.horde
	for k in n:
		var i := -1
		while i < 0 and not list.is_empty():
			var pick := sim.rng.randi_range(0, list.size() - 1)
			if h.e_hp[list[pick]] > 0.0:
				i = list[pick]
			list[pick] = list[-1]
			list.pop_back()
		# With nobody left to strike, the bolts still fall on open ground so the storm rages on.
		var at: Vector2 = h.e_pos[i] if i >= 0 else sim.commander.pos + Vector2(sim.rng.randf_range(-1.0, 1.0) * float(sim.b.gods.view_half[0]), sim.rng.randf_range(-1.0, 1.0) * float(sim.b.gods.view_half[1]))
		for j in sim.enemies_near(at, float(cfg.splash)):
			strike(sim, j, float(cfg.share), "jupiter")
		if i >= 0 and h.e_hp[i] > 0.0:
			strike(sim, i, float(cfg.share), "jupiter")
		bolts.append({"to": at, "t": 0.0, "seed": sim.rng.randi()})
		sim.tally(5, at)
	flash = maxf(flash, 0.25)


## Neptune's wave runs out from the legion; each barbarian it passes is thrown away from it and stunned.
func _quake(dt: float, sim: Sim) -> void:
	var cfg: Dictionary = sim.b.gods.neptune
	var h := sim.horde
	var drag := float(cfg.throw_drag)
	if not wave.is_empty():
		wave.t += dt
		var r := float(cfg.radius) * minf(1.0, float(wave.t) / float(cfg.wave_seconds))
		var r2 := r * r
		var centre: Vector2 = wave.pos
		for i in h.e_pos.size():
			var off := h.e_pos[i] - centre
			if off.length_squared() > r2 or _thrown.has(h.e_id[i]) or not on_screen(sim, h.e_pos[i]):
				continue
			# The speed that, slowed by the drag, carries a barbarian the throw distance.
			var v := off.normalized() * float(cfg.throw) * drag
			if h.e_tag[i] != Horde.ORDINARY:
				v *= float(cfg.boss_throw_mult)
			_thrown[h.e_id[i]] = v
			h.e_stun[i] = maxf(h.e_stun[i], float(cfg.stun))
		if float(wave.t) >= float(cfg.wave_seconds):
			wave = {}
	var fade := exp(-drag * dt)
	for id in _thrown.keys():
		_thrown[id] *= fade
		if (_thrown[id] as Vector2).length() < 5.0:
			_thrown.erase(id)
	if _thrown.is_empty():
		return
	for i in h.e_pos.size():
		var v: Variant = _thrown.get(h.e_id[i])
		if v != null:
			h.e_pos[i] += v * dt


## Vulcan sets every barbarian on screen alight and sends fire falling, some of it leaving burning ground.
func _vulcan(sim: Sim, cfg: Dictionary) -> void:
	var secs := float(cfg.burn_seconds)
	var h := sim.horde
	for i in targets(sim):
		sim.ignite(i, float(cfg.burn_share) * h.e_max[i] / secs, secs, "vulcan")
	burn_left = secs
	var half: Array = sim.b.gods.view_half
	var c: Vector2 = sim.commander.pos
	var n := int(cfg.meteors)
	for k in n:
		var spot := c + Vector2(sim.rng.randf_range(-1.0, 1.0) * float(half[0]) * 0.9, sim.rng.randf_range(-1.0, 1.0) * float(half[1]) * 0.9)
		meteors.append({"to": spot, "t": -sim.rng.randf() * float(cfg.rain_seconds), "patch": k < int(cfg.patches)})


func _rain(dt: float, sim: Sim) -> void:
	var cfg: Dictionary = sim.b.gods.vulcan
	var fall := float(cfg.fall_seconds)
	var keep: Array = []
	for m in meteors:
		m.t += dt
		if m.t < fall:
			keep.append(m)
			continue
		sim.effects.append({"kind": "boom", "pos": m.to, "t": 0.0, "radius": float(cfg.patch_radius)})
		sim.event("fell", m.to)
		if m.patch:
			sim.arms.add_zone("fire", m.to, float(cfg.patch_radius), float(cfg.patch_life), float(cfg.patch_dps), {"tick": 0.2, "src": "vulcan"})
	meteors = keep
	sim.shake = maxf(sim.shake, 0.1)


## Apollo heals every man to full and brings back the most recently fallen, as the medicus does.
func _apollo(sim: Sim, cfg: Dictionary) -> void:
	var legion := sim.legion
	for u in [sim.commander] + sim.soldiers:
		u.hp = u.max_hp
		sim.effects.append({"kind": "heal", "pos": u.pos, "t": 0.0})
	for k in int(cfg.revive):
		if legion.fallen.is_empty() or not legion.add(legion.fallen[-1]):
			break
		var type: String = legion.fallen.pop_back()
		legion.soldiers[-1].pos = sim.commander.pos
		# A man brought back must not also return later as a reserve.
		for r in legion.reserves:
			if r.type == type:
				legion.reserves.erase(r)
				break
	light_left = float(cfg.light_seconds)
