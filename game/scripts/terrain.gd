class_name Terrain
extends RefCounted
## The props on the field as plain data. Trees, rocks and logs are solid, so thickets and stone lines block the march
## and the legion has to steer round them; bushes and small stones are only drawn.

const CHUNK := 160.0
const REGION := 480.0
const SCATTER := ["oak", "fir", "rock", "log", "stones", "stones", "fir", "rock"]
const SOLID := {"oak": 9.0, "fir": 8.0, "rock": 10.0, "log": 9.0}

const CELL := 64.0
const GN := 28
const MAX_UNIT := 16.0

var seed_value := 0
var _anchor := Vector2i(1 << 30, 0)
var origin := Vector2.ZERO
var solid := PackedVector3Array()
var start := PackedInt32Array()
var items := PackedInt32Array()
var clear_radius := 200.0
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


func _init(run_seed: int) -> void:
	seed_value = run_seed


## Empties the field, for tests that need open ground.
func clear() -> void:
	empty = true
	_chunks.clear()
	_anchor = Vector2i(1 << 30, 0)


## Every prop whose chunk overlaps the rectangle, as [kind, position, radius] with radius 0 for the ones that do not block.
func props_in(rect: Rect2) -> Array:
	var out: Array = []
	for cx in range(floori(rect.position.x / CHUNK), floori(rect.end.x / CHUNK) + 1):
		for cy in range(floori(rect.position.y / CHUNK), floori(rect.end.y / CHUNK) + 1):
			out.append_array(chunk(cx, cy))
	return out


## The props of one chunk: its own scatter and its share of the thickets and stone lines of the region it lies in.
func chunk(cx: int, cy: int) -> Array:
	var key := Vector2i(cx, cy)
	if _chunks.has(key):
		return _chunks[key]
	if empty:
		return []
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, key])
	var out: Array = []
	for i in r.randi_range(0, 2):
		var p := Vector2((cx + r.randf()) * CHUNK, (cy + r.randf()) * CHUNK)
		if p.length() > 90.0:
			var kind: String = SCATTER[r.randi_range(0, SCATTER.size() - 1)]
			out.append([kind, p, SOLID.get(kind, 0.0)])
	var box := Rect2(Vector2(cx, cy) * CHUNK, Vector2(CHUNK, CHUNK))
	var rx := floori(box.position.x / REGION)
	var ry := floori(box.position.y / REGION)
	# A feature can reach past the edge of its own region, so the neighbouring regions are looked at too.
	for x in range(rx - 1, rx + 2):
		for y in range(ry - 1, ry + 2):
			for p in _region(x, y):
				if box.has_point(p[1]):
					out.append(p)
	_chunks[key] = out
	return out


## A region holds at most one big feature: a thicket of trees packed too close to pass between, or a line of rocks and logs.
func _region(rx: int, ry: int) -> Array:
	var key := Vector2i(rx, ry)
	if _regions.has(key):
		return _regions[key]
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, "region", key])
	var out: Array = []
	var roll := r.randf()
	var centre := (Vector2(rx, ry) + Vector2(r.randf_range(0.25, 0.75), r.randf_range(0.25, 0.75))) * REGION
	if roll < 0.45:
		var size := r.randf_range(60.0, 130.0)
		var lobe := centre + Vector2.from_angle(r.randf() * TAU) * size * 0.6
		var step := 22.0
		var y := -size * 1.6
		while y <= size * 1.6:
			var x := -size * 1.6
			while x <= size * 1.6:
				var p := centre + Vector2(x + r.randf_range(-3.0, 3.0) + (step / 2.0 if int(y / step) % 2 == 0 else 0.0), y + r.randf_range(-3.0, 3.0))
				if p.distance_to(centre) < size or p.distance_to(lobe) < size * 0.7:
					var kind := "fir" if r.randf() < 0.55 else "oak"
					out.append([kind, p, SOLID[kind]])
				x += step
			y += step
	elif roll < 0.75:
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
		if p[1].length() > clear_radius:
			kept.append(p)
	_regions[key] = kept
	return kept


## Rebuilds the grid of solid props around p when p has moved into another chunk; push_out only sees props in this grid.
func refresh(p: Vector2) -> void:
	var c := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	if c == _anchor:
		return
	_anchor = c
	origin = (Vector2(c) + Vector2(0.5, 0.5)) * CHUNK - Vector2(GN, GN) * CELL / 2.0
	solid.clear()
	var cells: Array = []
	cells.resize(GN * GN)
	for i in cells.size():
		cells[i] = PackedInt32Array()
	for pr in props_in(Rect2(origin, Vector2(GN, GN) * CELL)):
		var r: float = pr[2]
		if r <= 0.0:
			continue
		var idx := solid.size()
		solid.append(Vector3(pr[1].x, pr[1].y, r))
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


## The way to walk from p round the obstacles to the commander, or zero where the map has no answer.
func flow_at(p: Vector2) -> Vector2:
	if flow_dir.is_empty():
		return Vector2.ZERO
	var gx := floori((p.x - flow_origin.x) / FLOW_CELL)
	var gy := floori((p.y - flow_origin.y) / FLOW_CELL)
	if gx < 0 or gy < 0 or gx >= FN or gy >= FN:
		return Vector2.ZERO
	return flow_dir[gx + gy * FN]


## Moves a circle at p with radius r out of every solid prop it overlaps and returns where it ends up.
func push_out(p: Vector2, r: float) -> Vector2:
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
			p = Vector2(s.x, s.y) + (away / d if d > 0.001 else Vector2.RIGHT) * reach
	return p
