class_name Terrain
extends RefCounted
## The props on the field as plain data. Trees, rocks and logs are solid, so forest ridges and stone lines block the march
## and the legion has to steer round them or fell its way through; stumps and small stones are only drawn.

const CHUNK := 160.0
const REGION := 480.0
const SCATTER := ["oak", "fir", "rock", "log", "stones", "stones", "fir", "rock"]
const SOLID := {"oak": 9.0, "fir": 8.0, "rock": 10.0, "log": 9.0}
const TREES := {"oak": true, "fir": true}

const CELL := 64.0
const GN := 28
const MAX_UNIT := 16.0

var seed_value := 0
var _anchor := Vector2i(1 << 30, 0)
var origin := Vector2.ZERO
var solid := PackedVector3Array()
## 1 for each entry of `solid` that is a tree the legion can fell.
var solid_tree := PackedByteArray()
var start := PackedInt32Array()
var items := PackedInt32Array()
var clear_radius := 200.0
## Circles kept free of scatter and features, as [centre, radius]; set before the chunks they touch are built.
var clearings: Array = []
## Props the run places itself (objective huts, the grove's oaks, the fort's walls), as [kind, position, radius].
var extras: Array = []
## The palisade's stakes, as [kind, position, radius, time they rot], oldest first.
var posts: Array = []
## Trees cut down, by position; their stumps stand there whenever the chunk is built again.
var felled := {}
## Chopping done on each tree being cut, by position, as [seconds, clock of the last blow, seconds of it by the legion].
var chops := {}
## Logs from trees the legion felled since the last take_logs().
var logs := 0
## The run's time, set by the sim, so the drawing knows which trees are being cut right now.
var clock := 0.0
var fell_seconds := 3.0
## The ridge numbers from balance.json.
var forest: Dictionary
# The way round obstacles towards the commander: one step direction per FLOW_CELL square, or none where no way exists.
const FLOW_CELL := 32.0
const FN := 56
const STEPS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
var flow_origin := Vector2.ZERO
var flow_dir := PackedVector2Array()
var _blocked := PackedByteArray()
var _flow_goal := Vector2i(1 << 30, 0)
var empty := false
var _chunks := {}
var _regions := {}
var _buckets := {}
var _extra_at := {}
var _ready_to_fall: Array = []


func _init(run_seed: int, forest_cfg: Dictionary) -> void:
	seed_value = run_seed
	forest = forest_cfg


## Empties the field, for tests that need open ground.
func clear() -> void:
	empty = true
	extras.clear()
	_extra_at.clear()
	posts.clear()
	_chunks.clear()
	_anchor = Vector2i(1 << 30, 0)


## How many seconds of chopping the tree at p has taken.
func chop_of(p: Vector2) -> float:
	return chops[p][0] if chops.has(p) else 0.0


## Cuts down the tree at p, leaving its stump; the solid grid drops it on the next refresh.
func fell(p: Vector2) -> void:
	felled[p] = true
	chops.erase(p)
	var props: Array = _chunks.get(Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK)), [])
	for i in props.size():
		if props[i][1] == p and TREES.has(props[i][0]):
			props[i] = ["stump", p, 0.0]
	_anchor = Vector2i(1 << 30, 0)


## Fells every tree chopped long enough and returns how many fell; one the legion did half the chopping on adds a log.
func fell_ready() -> int:
	var n := 0
	for p in _ready_to_fall:
		if not felled.has(p):
			if chops.has(p) and chops[p][2] * 2.0 >= chops[p][0]:
				logs += 1
			fell(p)
			n += 1
	_ready_to_fall.clear()
	return n


## The logs gained since the last call.
func take_logs() -> int:
	var n := logs
	logs = 0
	return n


## Takes the run's own pieces at these positions off the field, such as a camp's burnt huts.
func remove_extras(at: Array) -> void:
	var gone := {}
	for p in at:
		gone[p] = true
		_extra_at.erase(p)
	extras = extras.filter(func(pr: Array) -> bool: return not gone.has(pr[1]))
	for p in at:
		_chunks.erase(Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK)))
	_anchor = Vector2i(1 << 30, 0)


## Drives a stake that rots at `until`; it is solid from the next refresh.
func add_post(p: Vector2, radius: float, until: float) -> void:
	posts.append(["stake", p, radius, until])
	_anchor = Vector2i(1 << 30, 0)


## Takes out the stakes whose time has come and returns whether any went.
func rot_posts(now: float) -> bool:
	var gone := false
	while not posts.is_empty() and posts[0][3] <= now:
		posts.pop_front()
		gone = true
	if gone:
		_anchor = Vector2i(1 << 30, 0)
	return gone


## Every prop whose chunk overlaps the rectangle, as [kind, position, radius] with radius 0 for the ones that do not block.
func props_in(rect: Rect2) -> Array:
	var out: Array = []
	for cx in range(floori(rect.position.x / CHUNK), floori(rect.end.x / CHUNK) + 1):
		for cy in range(floori(rect.position.y / CHUNK), floori(rect.end.y / CHUNK) + 1):
			out.append_array(chunk(cx, cy))
	return out


## The props of one chunk: its own scatter and its share of the ridges and stone lines of the regions round it.
func chunk(cx: int, cy: int) -> Array:
	var key := Vector2i(cx, cy)
	if _chunks.has(key):
		return _chunks[key]
	var box := Rect2(Vector2(cx, cy) * CHUNK, Vector2(CHUNK, CHUNK))
	var out: Array = []
	for p in extras:
		if box.has_point(p[1]):
			out.append(p)
	if empty:
		return out
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, key])
	for i in r.randi_range(0, 2):
		var p := Vector2((cx + r.randf()) * CHUNK, (cy + r.randf()) * CHUNK)
		if p.length() > 90.0:
			var kind: String = SCATTER[r.randi_range(0, SCATTER.size() - 1)]
			if not _in_clearing(p):
				out.append(_standing(kind, p))
	var rx := floori(box.position.x / REGION)
	var ry := floori(box.position.y / REGION)
	# A ridge reaches up to two regions past its own; where two ridges cover one lattice square they grow the same tree, kept once.
	var seen := {}
	for x in range(rx - 2, rx + 3):
		for y in range(ry - 2, ry + 3):
			for p in _bucket(x, y).get(key, []):
				if not seen.has(p[1]):
					seen[p[1]] = true
					out.append(_standing(p[0], p[1]))
	_chunks[key] = out
	return out


## The prop that stands at p: the one that grew there, or its stump once it has been felled.
func _standing(kind: String, p: Vector2) -> Array:
	if felled.has(p):
		return ["stump", p, 0.0]
	return [kind, p, SOLID.get(kind, 0.0)]


## A region's features sorted by the chunk each prop stands in.
func _bucket(rx: int, ry: int) -> Dictionary:
	var key := Vector2i(rx, ry)
	if _buckets.has(key):
		return _buckets[key]
	var by_chunk := {}
	for p in _region(rx, ry):
		var c := Vector2i(floori(p[1].x / CHUNK), floori(p[1].y / CHUNK))
		if not by_chunk.has(c):
			by_chunk[c] = []
		by_chunk[c].append(p)
	_buckets[key] = by_chunk
	return by_chunk


## A region holds at most one big feature: a winding ridge of trees packed too close to pass between, or a line of rocks and logs.
func _region(rx: int, ry: int) -> Array:
	var key := Vector2i(rx, ry)
	if _regions.has(key):
		return _regions[key]
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, "region", key])
	var out: Array = []
	var roll := r.randf()
	var centre := (Vector2(rx, ry) + Vector2(r.randf_range(0.25, 0.75), r.randf_range(0.25, 0.75))) * REGION
	if roll < float(forest.ridge_chance):
		out = _ridge(r, centre)
	elif roll < float(forest.ridge_chance) + float(forest.line_chance):
		var dir := Vector2.from_angle(r.randf() * PI)
		var length := r.randf_range(160.0, 320.0)
		var t := -length / 2.0
		while t <= length / 2.0:
			var p := centre + dir * t + dir.orthogonal() * sin(t / 40.0) * 10.0
			var kind := "rock" if r.randf() < 0.65 else "log"
			out.append([kind, p, SOLID[kind]])
			t += 20.0
	var kept: Array = []
	for p in out:
		if p[1].length() > clear_radius and not _in_clearing(p[1]):
			kept.append(p)
	_regions[key] = kept
	return kept


## A ridge: a centre line that bends as it goes, swept with a changing width over a lattice of trees shared by the whole field.
func _ridge(r: RandomNumberGenerator, centre: Vector2) -> Array:
	var length := r.randf_range(float(forest.length[0]), float(forest.length[1]))
	var w_lo := float(forest.width[0]) / 2.0
	var w_hi := float(forest.width[1]) / 2.0
	var max_turn := float(forest.turn)
	var ds := 10.0
	var heading := r.randf() * TAU
	var turn := r.randf_range(-1.0, 1.0) * max_turn
	var line := PackedVector2Array([Vector2.ZERO])
	var p := Vector2.ZERO
	for i in int(length / ds):
		turn = clampf(turn + r.randf_range(-1.0, 1.0) * float(forest.wander) * ds, -max_turn, max_turn)
		heading += turn * ds
		p += Vector2.from_angle(heading) * ds
		line.append(p)
	var shift := centre - (line[0] + line[line.size() - 1]) / 2.0
	var gap_from := INF
	var gap_to := -INF
	if r.randf() < float(forest.pass_chance):
		var mid := r.randf_range(0.3, 0.7) * length
		# The swept circles reach a half width into the gap from each side, so the gap in the line is that much wider.
		var half := float(forest.pass_width) / 2.0 + w_hi
		gap_from = mid - half
		gap_to = mid + half
	var width := r.randf_range(w_lo, w_hi)
	var step := float(forest.tree_step)
	var row := step * 0.866
	var taper := float(forest.end_taper)
	var cells := {}
	for i in line.size():
		width = clampf(width + r.randf_range(-2.0, 2.0), w_lo, w_hi)
		var along := i * ds
		if along > gap_from and along < gap_to:
			continue
		var w := width * clampf(minf(along, length - along) / taper * 0.6 + 0.4, 0.4, 1.0)
		var c := line[i] + shift
		for gy in range(floori((c.y - w) / row), ceili((c.y + w) / row) + 1):
			var odd := step / 2.0 if posmod(gy, 2) == 1 else 0.0
			for gx in range(floori((c.x - w - odd) / step), ceili((c.x + w - odd) / step) + 1):
				if Vector2(gx * step + odd, gy * row).distance_to(c) < w:
					cells[Vector2i(gx, gy)] = true
	var out: Array = []
	var jitter := float(forest.jitter)
	var firs := float(forest.fir_share)
	for cell in cells:
		# Jitter and kind come from the lattice square, not the ridge, so two ridges over one square grow the same tree.
		var h := hash([seed_value, cell])
		var odd := step / 2.0 if posmod(cell.y, 2) == 1 else 0.0
		var at := Vector2(cell.x * step + odd + ((h & 255) / 255.0 * 2.0 - 1.0) * jitter, cell.y * row + (((h >> 8) & 255) / 255.0 * 2.0 - 1.0) * jitter)
		var kind := "fir" if ((h >> 16) & 255) / 255.0 < firs else "oak"
		out.append([kind, at, SOLID[kind]])
	return out


## Clears a circle of ground that may already be built and stands the run's own pieces in it.
func add_clearing(centre: Vector2, radius: float, pieces: Array) -> void:
	clearings.append([centre, radius])
	extras.append_array(pieces)
	for pr in pieces:
		_extra_at[pr[1]] = true
	for key in _regions:
		_regions[key] = _regions[key].filter(func(p: Array) -> bool: return p[1].distance_to(centre) >= radius)
	_buckets.clear()
	var reach := radius
	for pr in pieces:
		reach = maxf(reach, pr[1].distance_to(centre) + 1.0)
	for cx in range(floori((centre.x - reach) / CHUNK), floori((centre.x + reach) / CHUNK) + 1):
		for cy in range(floori((centre.y - reach) / CHUNK), floori((centre.y + reach) / CHUNK) + 1):
			_chunks.erase(Vector2i(cx, cy))
	_anchor = Vector2i(1 << 30, 0)


func _in_clearing(p: Vector2) -> bool:
	for c in clearings:
		if p.distance_to(c[0]) < c[1]:
			return true
	return false


## Rebuilds the grid of solid props around p when p has moved into another chunk; push_out only sees props in this grid.
func refresh(p: Vector2) -> void:
	var c := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	if c == _anchor:
		return
	_anchor = c
	origin = (Vector2(c) + Vector2(0.5, 0.5)) * CHUNK - Vector2(GN, GN) * CELL / 2.0
	solid.clear()
	solid_tree.clear()
	var cells: Array = []
	cells.resize(GN * GN)
	for i in cells.size():
		cells[i] = PackedInt32Array()
	var area := Rect2(origin, Vector2(GN, GN) * CELL)
	var all := props_in(area)
	for post in posts:
		if area.has_point(post[1]):
			all.append(post)
	for pr in all:
		var r: float = pr[2]
		if r <= 0.0:
			continue
		var idx := solid.size()
		solid.append(Vector3(pr[1].x, pr[1].y, r))
		solid_tree.append(1 if TREES.has(pr[0]) and not _extra_at.has(pr[1]) else 0)
		# Each prop is listed in every cell it could touch a unit from, so a lookup reads one cell only.
		var reach := r + MAX_UNIT
		var x0 := clampi(floori((pr[1].x - reach - origin.x) / CELL), 0, GN - 1)
		var x1 := clampi(floori((pr[1].x + reach - origin.x) / CELL), 0, GN - 1)
		var y0 := clampi(floori((pr[1].y - reach - origin.y) / CELL), 0, GN - 1)
		var y1 := clampi(floori((pr[1].y + reach - origin.y) / CELL), 0, GN - 1)
		for gx in range(x0, x1 + 1):
			for gy in range(y0, y1 + 1):
				cells[gx + gy * GN].append(idx)
	start.resize(GN * GN + 1)
	items.clear()
	for i in cells.size():
		start[i] = items.size()
		items.append_array(cells[i])
	start[GN * GN] = items.size()
	_mark_blocked()


## Marks every flow square a barbarian cannot stand in because a solid prop covers it.
func _mark_blocked() -> void:
	flow_origin = origin + (Vector2(GN, GN) * CELL - Vector2(FN, FN) * FLOW_CELL) / 2.0
	_blocked.resize(FN * FN)
	_blocked.fill(0)
	for sv in solid:
		var reach := sv.z + 8.0
		var x0 := clampi(floori((sv.x - reach - flow_origin.x) / FLOW_CELL), 0, FN - 1)
		var x1 := clampi(floori((sv.x + reach - flow_origin.x) / FLOW_CELL), 0, FN - 1)
		var y0 := clampi(floori((sv.y - reach - flow_origin.y) / FLOW_CELL), 0, FN - 1)
		var y1 := clampi(floori((sv.y + reach - flow_origin.y) / FLOW_CELL), 0, FN - 1)
		for gx in range(x0, x1 + 1):
			for gy in range(y0, y1 + 1):
				var centre := flow_origin + (Vector2(gx, gy) + Vector2(0.5, 0.5)) * FLOW_CELL
				if centre.distance_to(Vector2(sv.x, sv.y)) < reach:
					_blocked[gx + gy * FN] = 1
	_flow_goal = Vector2i(1 << 30, 0)


## Works out, for every open square, which way leads round the obstacles to the commander; redone when he moves to another square.
func update_flow(goal: Vector2) -> void:
	var g := Vector2i(floori((goal.x - flow_origin.x) / FLOW_CELL), floori((goal.y - flow_origin.y) / FLOW_CELL))
	if g == _flow_goal or g.x < 0 or g.y < 0 or g.x >= FN or g.y >= FN:
		return
	_flow_goal = g
	flow_dir.resize(FN * FN)
	flow_dir.fill(Vector2.ZERO)
	var seen := PackedByteArray()
	seen.resize(FN * FN)
	var queue := PackedInt32Array([g.x + g.y * FN])
	seen[queue[0]] = 1
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var cx := c % FN
		var cy := c / FN
		for st in STEPS:
			var nx: int = cx + st.x
			var ny: int = cy + st.y
			if nx < 0 or ny < 0 or nx >= FN or ny >= FN:
				continue
			var n := nx + ny * FN
			if seen[n] == 1 or _blocked[n] == 1:
				continue
			# A diagonal step may not cut the corner between two blocked squares.
			if st.x != 0 and st.y != 0 and (_blocked[cx + ny * FN] == 1 or _blocked[nx + cy * FN] == 1):
				continue
			seen[n] = 1
			flow_dir[n] = -Vector2(st).normalized()
			queue.append(n)
	# A barbarian caught among trees stands in blocked squares, so the map also spreads from open ground through the trees, pointing back out.
	var escape := PackedInt32Array()
	for c in FN * FN:
		if seen[c] == 1 and _blocked[c] == 0:
			escape.append(c)
	head = 0
	while head < escape.size():
		var c := escape[head]
		head += 1
		var cx := c % FN
		var cy := c / FN
		for st in STEPS:
			var nx: int = cx + st.x
			var ny: int = cy + st.y
			if nx < 0 or ny < 0 or nx >= FN or ny >= FN:
				continue
			var n := nx + ny * FN
			if seen[n] == 1:
				continue
			seen[n] = 1
			flow_dir[n] = -Vector2(st).normalized()
			escape.append(n)


## Whether p is clear of the forest, as far as the map round the commander knows; beyond it everything counts as open.
func is_open(p: Vector2) -> bool:
	var gx := floori((p.x - flow_origin.x) / FLOW_CELL)
	var gy := floori((p.y - flow_origin.y) / FLOW_CELL)
	if _blocked.is_empty() or gx < 0 or gy < 0 or gx >= FN or gy >= FN:
		return true
	return _blocked[gx + gy * FN] == 0


## The way to walk from p round the obstacles to the commander, or zero where the map has no answer.
func flow_at(p: Vector2) -> Vector2:
	if flow_dir.is_empty():
		return Vector2.ZERO
	var gx := floori((p.x - flow_origin.x) / FLOW_CELL)
	var gy := floori((p.y - flow_origin.y) / FLOW_CELL)
	if gx < 0 or gy < 0 or gx >= FN or gy >= FN:
		return Vector2.ZERO
	return flow_dir[gx + gy * FN]


## Moves a circle at p with radius r out of every solid prop it overlaps and returns where it ends up; a legion unit passes its time step as `chop` to cut the trees it presses.
func push_out(p: Vector2, r: float, chop := 0.0) -> Vector2:
	var gx := floori((p.x - origin.x) / CELL)
	var gy := floori((p.y - origin.y) / CELL)
	if gx < 0 or gy < 0 or gx >= GN or gy >= GN:
		return p
	var cell := gx + gy * GN
	for t in range(start[cell], start[cell + 1]):
		var s := solid[items[t]]
		var away := Vector2(p.x - s.x, p.y - s.y)
		var reach := s.z + r
		var d2 := away.length_squared()
		if d2 < reach * reach:
			var d := sqrt(d2)
			if chop > 0.0 and solid_tree[items[t]] == 1 and reach - d > 0.05:
				_chop(Vector2(s.x, s.y), chop, chop)
			p = Vector2(s.x, s.y) + (away / d if d > 0.001 else Vector2.RIGHT) * reach
	return p


## Chopping by a barbarian pressed against the tree at `at`, which never earns the legion a log.
func horde_chop(at: Vector2, dt: float) -> void:
	_chop(at, dt, 0.0)


## Adds dt of chopping to the tree at at, `by_legion` of it done by the legion.
## push_out for a circle wider than MAX_UNIT, such as a boss: it reads every grid cell the circle could reach.
func push_out_wide(p: Vector2, r: float) -> Vector2:
	var extra := r - MAX_UNIT
	var x0 := floori((p.x - extra - origin.x) / CELL)
	var y0 := floori((p.y - extra - origin.y) / CELL)
	var x1 := floori((p.x + extra - origin.x) / CELL)
	var y1 := floori((p.y + extra - origin.y) / CELL)
	if x1 < 0 or y1 < 0 or x0 >= GN or y0 >= GN:
		return p
	for gx in range(maxi(x0, 0), mini(x1, GN - 1) + 1):
		for gy in range(maxi(y0, 0), mini(y1, GN - 1) + 1):
			var cell := gx + gy * GN
			for t in range(start[cell], start[cell + 1]):
				var s := solid[items[t]]
				var away := Vector2(p.x - s.x, p.y - s.y)
				var reach := s.z + r
				var d2 := away.length_squared()
				if d2 < reach * reach:
					var d := sqrt(d2)
					p = Vector2(s.x, s.y) + (away / d if d > 0.001 else Vector2.RIGHT) * reach
	return p


func _chop(at: Vector2, dt: float, by_legion: float) -> void:
	var c: Array = chops.get(at, [])
	if c.is_empty():
		c = [0.0, 0.0, 0.0]
		chops[at] = c
	c[0] += dt
	c[1] = clock
	c[2] += by_legion
	if c[0] >= fell_seconds and not _ready_to_fall.has(at):
		_ready_to_fall.append(at)
