class_name Objectives
extends RefCounted
## The run's mission as plain data: the barbarian camp, the stranded column and the sacred grove, each in a clearing some way
## off, and the Roman fort that appears late in the run.

## Seconds the rescued column's cart takes to fade away.
const CART_FADE := 1.5
const KINDS := ["camp", "column", "grove"]
## Pixels between the stakes of the fort's wall picture.
const STAKE_SPACING := 4.0

var list: Array = []
## Empty until the fort appears; then {pos: foot of the gate, gate: its opening, centre, half: half its side, gate_half: half the gap between the gate towers, hold: seconds held, entered}.
var fort := {}
var fort_reached := false
## Denarii the finished objectives add to what the run banks.
var purse := 0
var calm_until := -1.0
var calm_mult := 1.0
## The last thing done, {kind, at}, which the HUD announces for a few seconds.
var notice := {}


## Places two or three objectives round the start in well separated directions; `near` brings them close, for a look.
func place_start(sim: Sim, near := false) -> void:
	var cfg: Dictionary = sim.b.objectives
	var r := RandomNumberGenerator.new()
	r.seed = hash([sim.rng.seed, "objectives"])
	var kinds: Array = KINDS.duplicate()
	for i in range(kinds.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t: String = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = t
	var n := r.randi_range(int(cfg.count[0]), int(cfg.count[1]))
	var span: Array = cfg.near_flag if near else [cfg.near, cfg.far]
	var base := r.randf() * TAU
	var spread := float(cfg.spread)
	for i in n:
		var a := base + TAU * i / n + r.randf_range(-spread, spread)
		var at := Vector2.from_angle(a) * r.randf_range(float(span[0]), float(span[1]))
		# A spot by a ravine or a frozen stream is moved round a little at a time until it is well clear of the clearing.
		for k in 12:
			if minf(sim.terrain.ravine_edge(at), sim.terrain.stream_edge(at, 600.0)) >= float(cfg.clearing) + 40.0:
				break
			at = Vector2.from_angle(a + r.randf_range(-spread, spread)) * r.randf_range(float(span[0]), float(span[1]))
		# Canals run on across the whole field, so a spot still by one is moved to the middle of its strip of land.
		if sim.terrain.ravine_edge(at) < float(cfg.clearing) + 40.0 and sim.terrain.strip_middle(at).length() >= float(span[0]) * 0.5:
			at = sim.terrain.strip_middle(at)
		add(sim, kinds[i], at)


## Sets one objective at pos, clears its ground and stands its huts, oaks or guards there.
func add(sim: Sim, kind: String, pos: Vector2) -> Dictionary:
	var cfg: Dictionary = sim.b.objectives
	var o := {"kind": kind, "pos": pos, "done": false, "woken": false, "hold": 0.0, "band_cd": 0.0, "guards": [], "held": {}, "oaks": [], "huts": [], "burnt_at": -1.0, "razed": false, "fallen": 0}
	var pieces: Array = []
	match kind:
		"camp":
			var c: Dictionary = cfg.camp
			var n := int(c.huts)
			for k in n:
				var hut := ["hut", pos + Vector2.from_angle(pos.angle() + TAU * (k + 0.5) / n) * float(c.hut_ring), float(c.hut_radius)]
				pieces.append(hut)
				o.huts.append(hut[1])
		"column":
			var c: Dictionary = cfg.column
			var info: Dictionary = sim.content.recruits.legionary
			var hp := sim.max_hp_of("legionary")
			var n := int(c.guards)
			for k in n:
				var out := Vector2.from_angle(TAU * k / n + 0.4)
				o.guards.append({"type": "legionary", "info": info, "pos": pos + out * float(c.guard_ring), "hp": hp, "max_hp": hp, "cd": 0.0,
					"anim": k * 2.0, "facing": out, "moving": false, "flash": 0.0, "haste": 1.0, "struck_at": -1e9, "strike_dir": out})
		"grove":
			var c: Dictionary = cfg.grove
			# The grove's heart is an altar that burns, or in the desert a sacred well that is seized.
			o.centre = str(c.get("centre", {}).get(sim.province, "altar"))
			var tree := str(c.trees.get(sim.province, "oak"))
			var stones: Dictionary = c.stones.get(sim.province, {})
			var ring := float(stones.get("ring", c.ring))
			var slots := int(TAU * ring / float(stones.get("step", c.oak_step)))
			var gaps := int(c.gaps)
			var first := pos.angle() + PI
			for k in slots:
				var a := TAU * k / slots
				var open := false
				for g in gaps:
					open = open or absf(angle_difference(a, first + TAU * g / gaps)) < float(c.gap_width) / 2.0
				if open:
					continue
				var at := pos + Vector2.from_angle(a) * ring
				# A ring of trees or standing stones is scenery that the legion walks through, since a legion standing at the altar is wider than the ring.
				if stones.is_empty():
					pieces.append([tree, at, 0.0])
					o.oaks.append(at)
				else:
					pieces.append(["stone_circle", at + Vector2(float(stones.lift[0]), float(stones.lift[1])), 0.0])
	sim.terrain.add_clearing(pos, float(cfg.clearing), pieces)
	list.append(o)
	return o


## Raises the fort when its time comes, before the horde moves so the chieftain can come out between it and the legion.
func before_horde(sim: Sim) -> void:
	if fort.is_empty() and sim.time >= float(sim.b.chieftain_at):
		raise_fort(sim)


## Stands a square of solid stakes, gated in its south wall, in the most open of a few places ahead to the north.
func raise_fort(sim: Sim) -> void:
	var cfg: Dictionary = sim.b.fort
	var r := RandomNumberGenerator.new()
	r.seed = hash([sim.rng.seed, "fort"])
	var from: Vector2 = sim.commander.pos
	var best := from + Vector2.UP * float(cfg.near)
	var fewest := INF
	var sr := float(cfg.stake_radius)
	# The yard holds the largest legion this run allows, standing in its block, with room to spare, and a rim of tents round it.
	var block: Vector2 = Legion.block_size(sim.legion.cap, sim.b.legion)
	var half := maxf(float(cfg.half), maxf(block.x, block.y) / 2.0 + Sim.UNIT_RADIUS + sr + float(cfg.room_margin)) + float(cfg.tent_rim)
	# The clearing reaches past the corner towers, so no tree of the wood round the fort stands inside its walls.
	var room := maxf(float(cfg.clearing), half * 1.42 + 40.0)
	var arc := float(cfg.arc)
	for k in int(cfg.tries):
		var p := from + Vector2.from_angle(-PI / 2.0 + r.randf_range(-arc, arc)) * r.randf_range(float(cfg.near), float(cfg.far))
		if sim.terrain.ravine_edge(p) < room + 40.0:
			p = sim.terrain.strip_middle(p)
		var n := 0.0
		for pr in sim.terrain.props_in(Rect2(p - Vector2.ONE * room, Vector2.ONE * room * 2.0)):
			if pr[2] > 0.0 and pr[1].distance_to(p) < room:
				n += 1.0
		for o in list:
			if o.pos.distance_to(p) < room + float(sim.b.objectives.clearing):
				n += 100.0
		if minf(sim.terrain.ravine_edge(p), sim.terrain.stream_edge(p, 600.0)) < room + 40.0:
			n += 1000.0
		if n < fewest:
			fewest = n
			best = p
		if n == 0.0:
			break
	var foot := best + Vector2(0, half)

	var tx := float(cfg.tower_x)
	var tr := float(cfg.tower_radius)
	var ground: String = sim.content.provinces.get(sim.province, {}).get("fort_ground", "grass")
	var pieces: Array = [[fort_piece("fort_gate", ground), foot, 0.0], ["", foot + Vector2(-tx, -8), tr], ["", foot + Vector2(tx, -8), tr]]
	# The walls are solid all round but drawn as palisade pieces, so the blockers along them have no picture of their own.
	var steps := int(ceilf(2.0 * half / float(cfg.stake_gap)))
	var corners := [Vector2(-half, -half), Vector2(half, -half), Vector2(half, half), Vector2(-half, half)]
	for side in 4:
		var a: Vector2 = corners[side]
		var to: Vector2 = corners[(side + 1) % 4]
		for k in steps:
			var at: Vector2 = a.lerp(to, float(k) / steps)
			# The south wall leaves the gate's width open; its towers close the rest.
			if side == 2 and absf(at.x) < tx + tr + sr - 0.01 and at.y > 0.0:
				continue
			pieces.append(["", best + at, sr])
	for edge in [-1.0, 1.0]:
		pieces.append(["", foot + Vector2(edge * (tx + tr + sr * 0.5), 0.0), sr])
	pieces.append_array(_fort_pictures(best, half, cfg, ground))
	fort = {"pos": foot, "gate": foot + Vector2(0, -12), "centre": best, "half": half, "gate_half": tx - tr, "hold": 0.0, "entered": false}
	sim.terrain.add_clearing(best, room, pieces)
	notice = {"kind": "fort", "at": sim.time}


## The picture of a fort piece standing on a province's `fort_ground`; grass is the piece as drawn.
static func fort_piece(name: String, ground: String) -> String:
	return name if ground == "grass" or name == "tent" else "%s_%s" % [name, ground]


## The fort's palisade, corner towers and tents round a yard of `half` either side of `centre`: pictures, with a solid
## blocker under each tower and tent so nobody stands inside them.
func _fort_pictures(centre: Vector2, half: float, cfg: Dictionary, ground := "grass") -> Array:
	var out: Array = []
	# The walls stand a little above the corners so their bank tucks behind the base of the gate and the towers.
	var lift := float(cfg.wall_lift)
	for x in _wall_run(-half, half, float(cfg.wall_step)):
		out.append([fort_piece("fort_wall", ground), centre + Vector2(x, -half - lift), 0.0])
	# The front walls start under the gate's towers, so the gate hides where they end.
	var tuck := float(cfg.tower_x)
	for sx in [-1.0, 1.0]:
		for x in _wall_run(sx * tuck, sx * half, float(cfg.wall_step)):
			out.append([fort_piece("fort_wall", ground), centre + Vector2(x, half - lift), 0.0])
	# Each side wall is a strip of stakes standing one behind another, which reads as a palisade running away from the viewer.
	var y := -half - lift
	while y < half + float(cfg.side_step) / 2.0:
		for sx in [-1.0, 1.0]:
			out.append([fort_piece("fort_side", ground), centre + Vector2(sx * half, y), 0.0])
		y += float(cfg.side_step)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			out.append([fort_piece("watchtower", ground), centre + Vector2(sx * half, sy * half + 14.0), 0.0])
			out.append(["", centre + Vector2(sx * half, sy * half), float(cfg.tower_radius)])
	# Tents line the inside of the side and back walls, with the commander's tent in the middle of the back.
	var rim := float(cfg.tent_rim)
	var tent_r := float(cfg.tent_radius)
	y = -half + rim + 20.0
	while y <= half - rim:
		for sx in [-1.0, 1.0]:
			var at := centre + Vector2(sx * (half - rim * 0.75), y)
			out.append(["tent", at, 0.0])
			out.append(["", at + Vector2(0, -6), tent_r])
		y += float(cfg.tent_step)
	var x := -half + rim * 1.75
	while x <= half - rim * 1.75 + 0.5:
		if absf(x) > float(cfg.command_clear):
			var at := centre + Vector2(x, -half + rim + 4.0)
			out.append(["tent", at, 0.0])
			out.append(["", at + Vector2(0, -6), tent_r])
		x += float(cfg.tent_step)
	var head := centre + Vector2(0, -half + rim + 16.0)
	out.append([fort_piece("command_tent", ground), head, 0.0])
	out.append(["", head + Vector2(0, -12), float(cfg.command_radius)])
	return out


## The middles of wall pieces `width` wide laid edge to edge from `from` to `to`; the last is drawn back to end at `to`,
## by whole stakes so its stakes stand on the same ones it covers.
func _wall_run(from: float, to: float, width: float) -> Array:
	var out: Array = []
	var dir := signf(to - from)
	var x := from
	while absf(to - x) >= width - 0.01:
		out.append(x + dir * width / 2.0)
		x += dir * width
	var rest := absf(to - x)
	if rest > 0.01:
		out.append(x + dir * (width / 2.0 - (width - ceilf(rest / STAKE_SPACING) * STAKE_SPACING)))
	return out


## Whether p stands within the fort's walls, past the gate.
func in_fort(p: Vector2, sim: Sim) -> bool:
	if fort.is_empty():
		return false
	var inner := float(fort.half) - float(sim.b.fort.inside_margin)
	var off: Vector2 = p - fort.centre
	return absf(off.x) < inner and absf(off.y) < inner


## Where the chieftain comes out: just off screen towards the fort, so he stands in the legion's way.
func chieftain_point(sim: Sim) -> Vector2:
	if fort.is_empty():
		return sim.horde.ring_point()
	var dir: Vector2 = (fort.gate - sim.commander.pos).normalized()
	var p: Vector2 = sim.commander.pos + Vector2(dir.x * 1.15, dir.y * 0.75) * float(sim.b.spawn_radius)
	return sim.terrain.push_out(p, 12.0)


## Whether this run's grove is the desert's sacred well rather than an altar.
func well() -> bool:
	for o in list:
		if o.kind == "grove":
			return o.get("centre", "altar") == "well"
	return false


## How much of the ordinary stream still comes: less for a while after the grove burns.
func spawn_mult(t: float) -> float:
	return calm_mult if t < calm_until else 1.0


func update(dt: float, sim: Sim) -> void:
	for o in list:
		if o.done:
			if o.kind == "camp" and not o.razed:
				_burn_camp(o, sim)
			continue
		match o.kind:
			"camp":
				_camp(o, sim)
			"column":
				_column(o, dt, sim)
			"grove":
				_grove(o, dt, sim)
	if not fort.is_empty() and not fort_reached:
		_fort(dt, sim)


func _fort(dt: float, sim: Sim) -> void:
	var cfg: Dictionary = sim.b.fort
	if in_fort(sim.commander.pos, sim):
		if not fort.entered:
			fort.entered = true
			sim.event("fort", fort.centre)
		if sim.chieftain_index() >= 0:
			if notice.get("kind", "") != "fort_barred":
				notice = {"kind": "fort_barred", "at": sim.time}
			fort.hold = 0.0
			return
		fort.hold += dt
		if fort.hold >= float(cfg.hold):
			fort_reached = true
			sim.win(fort.centre)
	else:
		fort.hold = maxf(0.0, fort.hold - dt)


func _camp(o: Dictionary, sim: Sim) -> void:
	var cfg: Dictionary = sim.b.objectives.camp
	var d: float = sim.commander.pos.distance_to(o.pos)
	if not o.woken and d < float(cfg.wake):
		o.woken = true
		sim.horde.war_band_at(sim, o.pos)
		var leader := str(cfg.leader.get(sim.province, sim.horde.elites[0] if not sim.horde.elites.is_empty() else ""))
		if sim.content.ready("enemies", leader):
			sim.horde.spawn(leader, o.pos + (sim.commander.pos - o.pos).normalized() * 20.0, true)
	var touch := float(cfg.touch)
	if d < float(cfg.hut_ring):
		_take_eagle(o, sim)
		return
	if d > sim.legion_reach + touch:
		return
	for u in sim.units:
		if (u.pos - o.pos).length_squared() < touch * touch:
			_take_eagle(o, sim)
			return


func _take_eagle(o: Dictionary, sim: Sim) -> void:
	sim.free_choices += 1
	o.burnt_at = sim.time
	sim.event("fire", o.pos)
	_finish(o, sim)


## The huts burn after the eagle is taken, cave in one by one and stop blocking, then smoulder and leave walk-through ruins.
func _burn_camp(o: Dictionary, sim: Sim) -> void:
	var cfg: Dictionary = sim.b.objectives.camp
	var t := sim.time - float(o.burnt_at)
	var fell: Array = []
	while o.fallen < o.huts.size() and t >= fall_at(cfg, o.fallen):
		var at: Vector2 = o.huts[o.fallen]
		fell.append(at)
		o.fallen += 1
		sim.event("hut_fall", at)
		sim.shake = maxf(sim.shake, float(sim.b.shake.hut_fall))
	if t >= float(cfg.burn_seconds):
		o.razed = true
		sim.terrain.change_extras(o.huts, "hut_ruin", 0.0)
	elif not fell.is_empty():
		sim.terrain.change_extras(fell, "hut_charred", 0.0)
	else:
		return
	sim.terrain.refresh(sim.commander.pos)


## Seconds after the eagle is taken that hut i first catches fire.
static func catch_at(cfg: Dictionary, i: int) -> float:
	return i * float(cfg.burn.catch_stagger)


## Seconds after the eagle is taken that hut i caves in.
static func fall_at(cfg: Dictionary, i: int) -> float:
	return float(cfg.burn.collapse) + i * float(cfg.burn.collapse_stagger)


## How many of hut i's three fires are lit t seconds after the eagle is taken, while it still stands.
static func hut_flames(cfg: Dictionary, i: int, t: float) -> int:
	if t < catch_at(cfg, i):
		return 0
	return mini(3, 1 + int((t - catch_at(cfg, i)) / float(cfg.burn.spread)))


## Where hut i is in the burn t seconds after the eagle is taken: catching, blazing, collapsing, smouldering or ruins.
static func hut_stage(cfg: Dictionary, i: int, t: float) -> String:
	if t >= float(cfg.burn_seconds):
		return "ruins"
	var fall := fall_at(cfg, i)
	if t >= fall:
		return "collapsing" if t < fall + float(cfg.burn.cave) else "smouldering"
	return "blazing" if hut_flames(cfg, i, t) >= 3 else "catching"


func _column(o: Dictionary, dt: float, sim: Sim) -> void:
	var cfg: Dictionary = sim.b.objectives.column
	var d: float = sim.commander.pos.distance_to(o.pos)
	if not o.woken and d < float(cfg.wake):
		o.woken = true
		sim.horde.war_band_at(sim, o.pos + (o.pos - sim.commander.pos).normalized() * float(cfg.band_from))
	var h: Horde = sim.horde
	var info: Dictionary = sim.content.recruits.legionary
	var alive: Array = []
	var held := {}
	var rate := sim.attack_rate()
	for g in o.guards:
		g.anim += dt * 6.0
		if g.flash > 0.0:
			g.flash -= dt
		sim.melee(g, float(info.damage), float(info.reach), float(info.cooldown), dt, rate)
		for j in h.near(g.pos, Sim.UNIT_RADIUS + 14.0):
			var reach := h.k_radius[h.e_kind[j]] + Sim.UNIT_RADIUS
			var away: Vector2 = h.e_pos[j] - g.pos
			var gap := away.length()
			if gap > reach + 2.0 or h.e_tag[j] == Horde.CHIEF:
				continue
			g.hp -= h.k_dps[h.e_kind[j]] * dt
			g.flash = 0.08
			g.facing = away.normalized()
			# A barbarian who reaches a guard stays where he met him and fights, instead of sliding round him to the legion.
			var id := h.e_id[j]
			var at: Vector2 = o.held.get(id, g.pos + (away / gap if gap > 0.01 else Vector2.RIGHT) * reach)
			held[id] = at
			h.e_pos[j] = at
			h.e_fighting[j] = 1
			h.e_face[j] = -g.facing
		if g.hp > 0.0:
			alive.append(g)
		else:
			sim.effects.append({"kind": "fallen", "pos": g.pos, "t": 0.0, "type": g.type, "facing": g.facing})
	o.guards = alive
	o.held = held
	if d < float(cfg.reach):
		for g in o.guards:
			if sim.legion.add("legionary"):
				sim.soldiers[-1].pos = g.pos
		o.guards = []
		h.heal_legion(sim)
		_finish(o, sim)


func _grove(o: Dictionary, dt: float, sim: Sim) -> void:
	var cfg: Dictionary = sim.b.objectives.grove
	var quiet := notice.is_empty() or sim.time - float(notice.at) >= float(notice.get("seconds", sim.b.objectives.notice_seconds))
	if not o.get("tipped", false) and quiet and sim.commander.pos.distance_to(o.pos) < float(cfg.tip_within):
		o.tipped = true
		notice = {"kind": "grove_tip", "at": sim.time, "seconds": float(cfg.tip_seconds)}
	if sim.commander.pos.distance_to(o.pos) < float(cfg.inside):
		o.woken = true
		o.band_cd -= dt
		if o.band_cd <= 0.0:
			o.band_cd = float(cfg.band_every)
			sim.horde.war_band_at(sim, o.pos + Vector2.from_angle(sim.rng.randf() * TAU) * float(cfg.band_from))
		o.hold += dt
		if o.hold >= float(cfg.hold):
			sim.free_choices += 1
			calm_until = sim.time + float(cfg.calm_seconds)
			calm_mult = float(cfg.calm_mult)
			o.burnt_at = sim.time
			if o.get("centre", "altar") == "altar":
				sim.effects.append({"kind": "boom", "pos": o.pos, "t": 0.0, "radius": float(cfg.ring)})
			_finish(o, sim)
	else:
		o.hold = maxf(0.0, o.hold - dt)


func _finish(o: Dictionary, sim: Sim) -> void:
	o.done = true
	o.done_at = sim.time
	purse += int(sim.b.objectives.purse[o.kind])
	notice = {"kind": o.kind, "at": sim.time}
	sim.event("level", o.pos)


## How solid the stranded column's cart is drawn at `now`: whole while the column waits, fading away once it has joined the legion.
func cart_alpha(o: Dictionary, now: float) -> float:
	if not o.done:
		return 1.0
	return clampf(1.0 - (now - float(o.get("done_at", now))) / CART_FADE, 0.0, 1.0)


## The places the HUD points to: every objective not yet done, and the fort once it stands, as [kind, position].
func targets() -> Array:
	var out: Array = []
	for o in list:
		if not o.done:
			out.append([o.kind, o.pos])
	if not fort.is_empty() and not fort_reached:
		out.append(["fort", fort.gate])
	return out
