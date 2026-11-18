class_name Terrain
extends RefCounted
## The props on the field as plain data. Trees, rocks and logs are solid, so forest ridges and stone lines block the march
## and the legion has to steer round them or fell its way through; stumps and small stones are only drawn.
## Ravines are winding gorges nobody can cross except over a land bridge or a bridge the legion lays.

const CHUNK := 160.0
const REGION := 480.0
const SCATTER := ["oak", "fir", "rock", "log", "stones", "stones", "fir", "rock"]
const SOLID := {"oak": 9.0, "fir": 8.0, "pine": 8.0, "palm": 8.0, "rock": 10.0, "log": 9.0, "ruined_wall": 14.0}
const TREES := {"oak": true, "fir": true, "pine": true, "palm": true}

const CELL := 64.0
const GN := 28
const MAX_UNIT := 16.0
# Where a felled tree or rotted stake goes in the solid list, far beyond any field.
const GONE := 1.0e9

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
## The province's own scatter and features from balance.json `fields`; empty for Germania's forest.
var field: Dictionary
## A mountain province's scatter, ridge tree and rock lines from balance.json `mountains`, laid over the forest numbers.
var mountain: Dictionary
## The frozen stream numbers from balance.json `streams`; with none the field has no ice.
var stream_cfg: Dictionary
## A desert province's scatter, oases, ruined walls and dunes from balance.json `deserts`, in place of ridges and lines.
var desert: Dictionary
## A moorland province's scatter, stone circles, bog pools and heather from balance.json `moors`, with a few forest ridges.
var moor: Dictionary
# The middle and reach of the stone circle of each moorland region that has one, kept free of the trees of ridges nearby.
var _henges := {}
# The frozen stream of each stream region once worked out, {} for a region without one, and streams laid by hand.
var _streams := {}
var _laid_streams: Array = []
# The way round obstacles towards the commander: one step direction per FLOW_CELL square, or none where no way exists.
const FLOW_CELL := 32.0
const FN := 56
const STEPS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
var flow_origin := Vector2.ZERO
var flow_dir := PackedVector2Array()
## 1 for every route map square a prop or ravine closes.
var blocked := PackedByteArray()
var _flow_goal := Vector2i(1 << 30, 0)
# The eight steps of the route map as flat offsets, x and y parts, and the way back along each.
var _step_off := PackedInt32Array()
var _step_dx := PackedInt32Array()
var _step_dy := PackedInt32Array()
var _step_back := PackedVector2Array()
var _edge := PackedByteArray()
var _queue := PackedInt32Array()
var empty := false
var _chunks := {}
var _regions := {}
# The wheat fields of each farmland region, as rectangles, and each farmland region as first laid out.
var _fields := {}
var _raw := {}
var _buckets := {}
var _extra_at := {}
var _ready_to_fall: Array = []
## The ravine numbers from balance.json; with none the field has no ravines.
var ravine_cfg: Dictionary
## Bridges laid by the legion, as {pos: middle, dir: along the deck, half_len, half_w}; they last the whole run.
var bridges: Array = []
## How many times a prop, a field, a ravine or a bridge's side has moved the commander or a soldier, for the tests.
var legion_shoves := 0
# The ravine of each ravine region once worked out, {} for a region without one.
var _ravines := {}
# Ravines laid by hand, for tests and looks.
var _laid: Array = []
# The ravine segments near the commander as (ax, ay, bx, by) with the half widths at each end, and the grid cells listing them.
const RAVINE_REACH := 40.0
var rv_seg := PackedVector4Array()
var rv_half := PackedVector2Array()
var rv_start := PackedInt32Array()
var rv_items := PackedInt32Array()
# The wheat fields near the commander as the solid rectangles (x0, y0, x1, y1) nobody may enter, and the grid cells listing them.
const FIELD_REACH := 64.0
var fd_rect := PackedVector4Array()
var fd_start := PackedInt32Array()
var fd_items := PackedInt32Array()


func _init(run_seed: int, forest_cfg: Dictionary, ravines_cfg := {}) -> void:
	seed_value = run_seed
	forest = forest_cfg
	ravine_cfg = ravines_cfg


## Empties the field, for tests that need open ground.
func clear() -> void:
	empty = true
	extras.clear()
	_extra_at.clear()
	posts.clear()
	_chunks.clear()
	_laid.clear()
	_laid_streams.clear()
	bridges.clear()
	_anchor = Vector2i(1 << 30, 0)


## How many seconds of chopping the tree at p has taken.
func chop_of(p: Vector2) -> float:
	return chops[p][0] if chops.has(p) else 0.0


## Cuts down the tree at p, leaving its stump, and takes it out of the solid grid at once.
func fell(p: Vector2) -> void:
	felled[p] = true
	chops.erase(p)
	var props: Array = _chunks.get(Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK)), [])
	for i in props.size():
		if props[i][1] == p and TREES.has(props[i][0]):
			props[i] = ["stump", p, 0.0]
	for k in solid.size():
		if solid_tree[k] == 1 and solid[k].x == p.x and solid[k].y == p.y:
			_drop_solid(k)
			return


## Takes entry k out of the solid grid without rebuilding it: the entry moves far off the field, where it touches nothing.
func _drop_solid(k: int) -> void:
	var sv := solid[k]
	solid[k] = Vector3(GONE, GONE, 0.0)
	solid_tree[k] = 0
	var reach := sv.z
	var x0 := clampi(floori((sv.x - reach - flow_origin.x) / FLOW_CELL), 0, FN - 1)
	var x1 := clampi(floori((sv.x + reach - flow_origin.x) / FLOW_CELL), 0, FN - 1)
	var y0 := clampi(floori((sv.y - reach - flow_origin.y) / FLOW_CELL), 0, FN - 1)
	var y1 := clampi(floori((sv.y + reach - flow_origin.y) / FLOW_CELL), 0, FN - 1)
	var changed := false
	for gx in range(x0, x1 + 1):
		for gy in range(y0, y1 + 1):
			var centre := flow_origin + (Vector2(gx, gy) + Vector2(0.5, 0.5)) * FLOW_CELL
			if blocked[gx + gy * FN] == 1 and _covers(sv, centre) and not _blocks(centre, gx, gy):
				blocked[gx + gy * FN] = 0
				changed = true
	if changed:
		_flow_goal = Vector2i(1 << 30, 0)


## Whether a solid prop covers any part of the flow square with this centre.
static func _covers(sv: Vector3, centre: Vector2) -> bool:
	var dx := maxf(0.0, absf(centre.x - sv.x) - FLOW_CELL / 2.0)
	var dy := maxf(0.0, absf(centre.y - sv.y) - FLOW_CELL / 2.0)
	return dx * dx + dy * dy < sv.z * sv.z


## Whether a solid prop or a ravine blocks the flow square (gx, gy) with this centre, as _mark_blocked decides it.
func _blocks(centre: Vector2, gx: int, gy: int) -> bool:
	var cx := floori((centre.x - origin.x) / CELL)
	var cy := floori((centre.y - origin.y) / CELL)
	if cx >= 0 and cy >= 0 and cx < GN and cy < GN:
		var cell := cx + cy * GN
		for t in range(start[cell], start[cell + 1]):
			if _covers(solid[items[t]], centre):
				return true
	for k in rv_seg.size():
		var sg := rv_seg[k]
		var reach := maxf(rv_half[k].x, rv_half[k].y) + 8.0
		var x0 := clampi(floori((minf(sg.x, sg.z) - reach - flow_origin.x) / FLOW_CELL), 0, FN - 1)
		var x1 := clampi(floori((maxf(sg.x, sg.z) + reach - flow_origin.x) / FLOW_CELL), 0, FN - 1)
		var y0 := clampi(floori((minf(sg.y, sg.w) - reach - flow_origin.y) / FLOW_CELL), 0, FN - 1)
		var y1 := clampi(floori((maxf(sg.y, sg.w) + reach - flow_origin.y) / FLOW_CELL), 0, FN - 1)
		if gx >= x0 and gx <= x1 and gy >= y0 and gy <= y1 and _seg_edge(k, centre) < 8.0 and on_bridge(centre) < 0:
			return true
	for rc in fd_rect:
		if _square_in_field(rc, centre.x, centre.y):
			return true
	return false


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
	# The list stays in rotting order, since stakes driven later can rot sooner than a palisade's.
	var at := posts.size()
	while at > 0 and posts[at - 1][3] > until:
		at -= 1
	posts.insert(at, ["stake", p, radius, until])
	_anchor = Vector2i(1 << 30, 0)


## Takes out the stakes whose time has come and returns whether any went.
func rot_posts(now: float) -> bool:
	var gone := false
	while not posts.is_empty() and posts[0][3] <= now:
		var post: Array = posts.pop_front()
		gone = true
		# Stakes are listed after every other prop, so the search runs from the end.
		for k in range(solid.size() - 1, -1, -1):
			if solid[k].x == post[1].x and solid[k].y == post[1].y and solid_tree[k] == 0:
				_drop_solid(k)
				break
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
	var scatter: Array = field.get("scatter", mountain.get("scatter", desert.get("scatter", moor.get("scatter", SCATTER))))
	for i in r.randi_range(0, 2):
		var p := Vector2((cx + r.randf()) * CHUNK, (cy + r.randf()) * CHUNK)
		if p.length() > 90.0:
			var kind: String = scatter[r.randi_range(0, scatter.size() - 1)]
			if not _in_clearing(p) and not _by_ravine(p):
				out.append(_standing(kind, p))
	var rx := floori(box.position.x / REGION)
	var ry := floori(box.position.y / REGION)
	# A ridge reaches up to two regions past its own; where two ridges cover one lattice square they grow the same tree, kept once.
	var seen := {}
	var henges: Array = []
	for x in range(rx - 2, rx + 3):
		for y in range(ry - 2, ry + 3):
			for p in _bucket(x, y).get(key, []):
				if not seen.has(p[1]):
					seen[p[1]] = true
					out.append(_standing(p[0], p[1]) if TREES.has(p[0]) else p)
			if _henges.has(Vector2i(x, y)):
				henges.append(_henges[Vector2i(x, y)])
	if not henges.is_empty():
		out = out.filter(func(p: Array) -> bool: return not (TREES.has(p[0]) or p[0] == "stump") or not _near_henge(p[1], henges))
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
	if not field.is_empty():
		_regions[key] = _farmland(key)
		return _regions[key]
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, "region", key])
	var out: Array = []
	var roll := r.randf()
	var centre := (Vector2(rx, ry) + Vector2(r.randf_range(0.25, 0.75), r.randf_range(0.25, 0.75))) * REGION
	var ridges := float(mountain.get("ridge_chance", moor.get("ridge_chance", forest.ridge_chance)))
	if not desert.is_empty():
		out = _desert_feature(r, roll, centre)
	elif not moor.is_empty():
		out = _ridge(r, centre) if roll < ridges else _moor_feature(r, roll - ridges, centre)
	elif roll < ridges:
		out = _ridge(r, centre)
	elif roll < ridges + float(mountain.get("line_chance", forest.line_chance)):
		var dir := Vector2.from_angle(r.randf() * PI)
		var span: Array = mountain.get("line_length", [160.0, 320.0])
		var length := r.randf_range(float(span[0]), float(span[1]))
		var kinds: Array = mountain.get("line_kinds", [])
		var t := -length / 2.0
		while t <= length / 2.0:
			var p := centre + dir * t + dir.orthogonal() * sin(t / 40.0) * 10.0
			var kind: String = kinds[r.randi_range(0, kinds.size() - 1)] if not kinds.is_empty() else ("rock" if r.randf() < 0.65 else "log")
			out.append([kind, p, SOLID[kind]])
			t += 20.0
	var kept: Array = []
	for p in out:
		if p[1].length() > clear_radius and not _in_clearing(p[1]) and not _by_ravine(p[1]):
			kept.append(p)
	_regions[key] = kept
	return kept


## A desert region holds an oasis of palms, a ruined mud-brick wall, a spread of dunes or open sand.
func _desert_feature(r: RandomNumberGenerator, roll: float, centre: Vector2) -> Array:
	var cfg := desert
	var out: Array = []
	var oasis := float(cfg.oasis_chance)
	var wall := oasis + float(cfg.wall_chance)
	if roll < oasis:
		var n := r.randi_range(int(cfg.palms[0]), int(cfg.palms[1]))
		var gap := float(cfg.palm_gap)
		for k in n * 4:
			if out.size() >= n:
				break
			var p := centre + Vector2.from_angle(r.randf() * TAU) * sqrt(r.randf()) * float(cfg.oasis_radius)
			var spaced := true
			for q in out:
				spaced = spaced and q[1].distance_to(p) >= gap
			if spaced:
				out.append(["palm", p, SOLID.palm])
	elif roll < wall:
		var dir := Vector2.from_angle(r.randf() * PI)
		var length := r.randf_range(float(cfg.wall_length[0]), float(cfg.wall_length[1]))
		var step := float(cfg.wall_step)
		# Some walls have fallen in one place, leaving a breach the legion can march through.
		var breach := r.randf_range(-0.25, 0.25) * length if r.randf() < float(cfg.wall_gap_chance) else INF
		var t := -length / 2.0
		while t <= length / 2.0:
			if absf(t - breach) > float(cfg.wall_gap) / 2.0:
				out.append(["ruined_wall", centre + dir * t + dir.orthogonal() * sin(t / 70.0) * 8.0, SOLID.ruined_wall])
			t += step
	elif roll < wall + float(cfg.dune_chance):
		for k in r.randi_range(int(cfg.dunes[0]), int(cfg.dunes[1])):
			out.append(["dune", centre + Vector2(r.randf_range(-1.0, 1.0), r.randf_range(-0.6, 0.6)) * float(cfg.dune_spread), 0.0])
	return out


## Whether p stands on the soft sand of a dune, which slows the legion's march.
func on_dune(p: Vector2) -> bool:
	if desert.is_empty():
		return false
	var size: Array = desert.dune_size
	var rx := float(size[0])
	var ry := float(size[1])
	for pr in props_in(Rect2(p - Vector2(rx, ry), Vector2(rx * 2.0, ry * 3.0))):
		if pr[0] != "dune":
			continue
		# A dune's drawn mound sits above the point it stands on, so its middle is half a mound higher.
		var off: Vector2 = p - pr[1] + Vector2(0.0, ry)
		if (off.x * off.x) / (rx * rx) + (off.y * off.y) / (ry * ry) <= 1.0:
			return true
	return false


## A moorland region holds a stone circle, a spread of bog pools, a patch of heather or open moor.
## A circle is a ring of standing stones round a clear middle, each group of stones solid, with an opening on one side.
func _moor_feature(r: RandomNumberGenerator, roll: float, centre: Vector2) -> Array:
	var cfg := moor
	var out: Array = []
	var circle := float(cfg.circle_chance)
	var bogs := circle + float(cfg.bog_chance)
	if roll < circle:
		var n := int(cfg.circle_count)
		var turn := r.randf() * TAU
		_henges[Vector2i(floori(centre.x / REGION), floori(centre.y / REGION))] = [centre, float(cfg.circle_radius) + float(cfg.circle_clear)]
		for k in range(int(cfg.circle_gap), n):
			var at := centre + Vector2.from_angle(turn + TAU * k / n) * float(cfg.circle_radius)
			var group: Array = [["stone_circle", at, 0.0]]
			for off in cfg.circle_stones:
				group.append(["", at + Vector2(float(off[0]), float(off[1])), float(cfg.stone_radius)])
			# A group of stones is kept or left out whole, so no stone stands solid without its picture.
			var ok := true
			for g in group:
				ok = ok and g[1].length() > clear_radius and not _in_clearing(g[1]) and not _by_ravine(g[1])
			if ok:
				out.append_array(group)
	elif roll < bogs:
		for k in r.randi_range(int(cfg.bogs[0]), int(cfg.bogs[1])):
			out.append(["bog", centre + Vector2(r.randf_range(-1.0, 1.0), r.randf_range(-0.6, 0.6)) * float(cfg.bog_spread), 0.0])
	elif roll < bogs + float(cfg.heather_chance):
		for k in r.randi_range(int(cfg.heathers[0]), int(cfg.heathers[1])):
			out.append(["heather", centre + Vector2(r.randf_range(-1.0, 1.0), r.randf_range(-0.7, 0.7)) * float(cfg.heather_spread), 0.0])
	return out


func _near_henge(p: Vector2, henges: Array) -> bool:
	for hg in henges:
		if p.distance_to(hg[0]) < hg[1]:
			return true
	return false


## Whether p stands in a bog pool, which slows the legion's march more than sand.
func in_bog(p: Vector2) -> bool:
	if moor.is_empty():
		return false
	var size: Array = moor.bog_size
	var rx := float(size[0])
	var ry := float(size[1])
	var lift := float(moor.bog_lift)
	for pr in props_in(Rect2(p - Vector2(rx, ry), Vector2(rx * 2.0, ry * 2.0 + lift))):
		if pr[0] != "bog":
			continue
		# The pool's water lies above the point the picture stands on.
		var off: Vector2 = p - pr[1] + Vector2(0.0, lift)
		if (off.x * off.x) / (rx * rx) + (off.y * off.y) / (ry * ry) <= 1.0:
			return true
	return false


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
		var kind: String = mountain.get("tree", "fir" if ((h >> 16) & 255) / 255.0 < firs else "oak")
		out.append([kind, at, SOLID[kind]])
	return out


## A farmland region holds a few villages with hedges off their sides and fields beside them, a hedgerow running east and west, or a large field of wheat.
## A piece of a feature that falls in a clearing or by a ravine takes its whole village or hedge bush with it, so nothing is left half solid.
func _farmland(key: Vector2i) -> Array:
	var raw: Dictionary = _farm_raw(key)
	var earlier := _earlier_houses(key)
	var kept: Array = []
	for g in raw.groups:
		var ok := true
		for p in g:
			if p[1].length() <= clear_radius or _in_clearing(p[1]) or _by_ravine(p[1]) or (p[0] == "roundhouse" and _house_clash(p[1], earlier)):
				ok = false
				break
		if ok:
			kept.append_array(g)
	kept.append_array(_hedge_ends(kept))
	var fields: Array = []
	for parts in raw.fields:
		fields.append_array(_placed_field(key, parts))
	_fields[key] = fields
	return kept


## A rounded end just behind each stretch of hedge with no stretch beside it, so a hedge stops softly at its ends, its gate and where it was cleared.
func _hedge_ends(pieces: Array) -> Array:
	var span := float(field.hedge_span)
	var cap := float(field.hedge_cap)
	var at := {}
	for p in pieces:
		if p[0] == "hedge":
			at[Vector2i(p[1].round())] = true
	var out: Array = []
	for p in pieces:
		if p[0] != "hedge":
			continue
		for side in [-1.0, 1.0]:
			if not at.has(Vector2i((p[1] + Vector2(side * span, 0.0)).round())):
				out.append(["hedge_end_right" if side > 0.0 else "hedge_end_left", p[1] + Vector2(side * cap, -1.0), 0.0])
	return out


## The roundhouses of the regions near this one that come before it, whose villages win where two would stand in each other.
func _earlier_houses(key: Vector2i) -> Array:
	var out: Array = []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var other := key + Vector2i(dx, dy)
			if other.y > key.y or (other.y == key.y and other.x >= key.x):
				continue
			for g in _farm_raw(other).groups:
				for p in g:
					if p[0] == "roundhouse":
						out.append(p[1])
	return out


## True when a roundhouse at p would be drawn into one of `houses`.
func _house_clash(p: Vector2, houses: Array) -> bool:
	var gap: Array = field.house_spacing
	for h in houses:
		if absf(h.x - p.x) < float(gap[0]) and absf(h.y - p.y) < float(gap[1]):
			return true
	return false


## A farmland region as first laid out, before anything round it is weighed: {groups: the villages' and hedges' pieces, fields: each field's parts}.
func _farm_raw(key: Vector2i) -> Dictionary:
	if _raw.has(key):
		return _raw[key]
	var r := RandomNumberGenerator.new()
	r.seed = hash([seed_value, "region", key])
	var roll := r.randf()
	var centre := (Vector2(key) + Vector2(r.randf_range(0.25, 0.75), r.randf_range(0.25, 0.75))) * REGION
	var f := field
	var groups: Array = []
	var fields: Array = []
	if roll < float(f.village_chance):
		var n := r.randi_range(int(f.villages[0]), int(f.villages[1]))
		var a0 := r.randf() * TAU
		for k in n:
			var at := centre
			if k > 0:
				at += Vector2.from_angle(a0 + TAU * (k - 1) / maxf(n - 1, 1)) * r.randf_range(float(f.village_gap[0]), float(f.village_gap[1]))
			groups.append(_village(at))
			if r.randf() < float(f.village_hedge):
				var side := 1.0 if r.randf() < 0.5 else -1.0
				groups.append_array(_hedge_line(r, at + Vector2(side * float(f.village_reach), 0.0), side, r.randi_range(2, 4), false))
		var reach: Array = f.village_field_reach
		for k in r.randi_range(int(f.village_fields[0]), int(f.village_fields[1])):
			for attempt in int(f.field_tries):
				var parts := _fit_field(_wheat_field(r, centre + Vector2.from_angle(r.randf() * TAU) * r.randf_range(float(reach[0]), float(reach[1])), f.village_field_size), groups, fields)
				if not parts.is_empty():
					fields.append(parts)
					break
	elif roll < float(f.village_chance) + float(f.hedge_chance):
		var length := r.randf_range(float(f.hedge_length[0]), float(f.hedge_length[1]))
		groups.append_array(_hedge_line(r, centre - Vector2(length / 2.0, 0.0), 1.0, int(length / float(f.hedge_span)), r.randf() < float(f.gate_chance)))
	elif roll < float(f.village_chance) + float(f.hedge_chance) + float(f.wheat_chance):
		fields.append(_wheat_field(r, centre, f.field_size))
	_raw[key] = {"groups": groups, "fields": fields}
	return _raw[key]


## A field cut back from every blocker of these groups and every one of these fields until a lane the legion can march down is left
## round its solid ground, or [] when too little wheat would be left; a strip off its corner goes whole, or not at all.
func _fit_field(parts: Array, groups: Array, fields: Array) -> Array:
	var inset := float(field.field_inset)
	var main: Rect2 = parts[0].grow(-inset)
	var cut := _cut_back(main, groups, fields)
	if cut.size == Vector2.ZERO:
		return []
	if cut != main or parts.size() == 1:
		return [cut.grow(inset)]
	var wing: Rect2 = parts[1].grow(-inset)
	return parts if _cut_back(wing, groups, fields) == wing else [parts[0]]


## A field's solid ground cut back, one side at a time and always the side that keeps the most, until it keeps the lane from everything given.
func _cut_back(body: Rect2, groups: Array, fields: Array) -> Rect2:
	var lane := float(field.field_lane)
	var inset := float(field.field_inset)
	var least: Array = field.field_least
	var keep: Array = []
	for g in groups:
		for p in g:
			if p[2] > 0.0:
				keep.append([Rect2(p[1], Vector2.ZERO), lane + p[2]])
	for other in fields:
		for o in other:
			keep.append([o.grow(-inset), lane])
	for k in keep:
		var ob: Rect2 = k[0]
		var gap: float = k[1]
		if _rect_gap(body, ob) >= gap:
			continue
		var best := Rect2()
		for c in [Rect2(Vector2(ob.end.x + gap, body.position.y), Vector2(body.end.x - ob.end.x - gap, body.size.y)),
				Rect2(body.position, Vector2(ob.position.x - gap - body.position.x, body.size.y)),
				Rect2(Vector2(body.position.x, ob.end.y + gap), Vector2(body.size.x, body.end.y - ob.end.y - gap)),
				Rect2(body.position, Vector2(body.size.x, ob.position.y - gap - body.position.y))]:
			var fits: bool = c.size.x + inset * 2.0 >= float(least[0]) and c.size.y + inset * 2.0 >= float(least[1])
			if fits and body.encloses(c) and c.get_area() > best.get_area():
				best = c
		if best.size == Vector2.ZERO:
			return Rect2()
		body = best
	return body


## How far apart two rectangles are, 0 where they touch or overlap.
static func _rect_gap(a: Rect2, b: Rect2) -> float:
	var dx := maxf(0.0, maxf(a.position.x - b.end.x, b.position.x - a.end.x))
	var dy := maxf(0.0, maxf(a.position.y - b.end.y, b.position.y - a.end.y))
	return sqrt(dx * dx + dy * dy)


## A region's field as it stands once the regions round it are weighed: cut back to keep a lane from their villages and hedges and from
## the fields of the regions listed before it, and left out where it would touch the start, a clearing or a ravine.
func _placed_field(key: Vector2i, parts: Array) -> Array:
	var groups: Array = []
	var fields: Array = []
	for x in range(key.x - 2, key.x + 3):
		for y in range(key.y - 2, key.y + 3):
			var other := Vector2i(x, y)
			if other == key:
				continue
			var raw: Dictionary = _farm_raw(other)
			groups.append_array(raw.groups)
			if y < key.y or (y == key.y and x < key.x):
				fields.append_array(raw.fields)
	var out := _fit_field(parts, groups, fields)
	for part in out:
		for q in [part.position, part.end, Vector2(part.position.x, part.end.y), Vector2(part.end.x, part.position.y), part.get_center()]:
			if q.length() <= clear_radius + 40.0 or _in_clearing(q) or _by_ravine(q):
				return []
	return out


## One village: a cluster of roundhouses, each drawn with no solid of its own and made solid by unseen circles over its wall.
func _village(at: Vector2) -> Array:
	var g: Array = []
	for h in field.village_houses:
		var house := at + Vector2(float(h[0]), float(h[1]))
		g.append(["roundhouse", house, 0.0])
		for c in field.house_blockers:
			g.append(["", house + Vector2(float(c[0]), float(c[1])), float(c[2])])
	return g


## A hedgerow running east (dir 1) or west (dir -1) from `from`: bushes side by side, each with a row of unseen circles so nothing slips through, and with `gate` one bush left out.
func _hedge_line(r: RandomNumberGenerator, from: Vector2, dir: float, count: int, gate: bool) -> Array:
	var span := float(field.hedge_span)
	var n := int(field.hedge_blockers)
	var gap_at := r.randi_range(1, count - 2) if gate and count > 3 else -1
	var groups: Array = []
	for k in count:
		if k == gap_at:
			continue
		var at := from + Vector2(dir * span * (k + 0.5), 0.0)
		var g: Array = [["hedge", at, 0.0]]
		for j in n:
			g.append(["", at + Vector2(-span / 2.0 + span * (j + 0.5) / n, -6.0), float(field.hedge_radius)])
		groups.append(g)
	return groups


## A field of standing wheat centred on `at`, sized from [[least, most width], [least, most height]], as one rectangle or, sometimes,
## with a second strip off one corner so it reads as a worked field rather than a box.
func _wheat_field(r: RandomNumberGenerator, at: Vector2, size: Array) -> Array:
	var w := snappedf(r.randf_range(float(size[0][0]), float(size[0][1])), 4.0)
	var h := snappedf(r.randf_range(float(size[1][0]), float(size[1][1])), 4.0)
	var parts: Array = [Rect2((at - Vector2(w, h) / 2.0).snapped(Vector2(4, 4)), Vector2(w, h))]
	if r.randf() < float(field.get("field_wing", 0.0)):
		var main: Rect2 = parts[0]
		var ww := snappedf(w * r.randf_range(0.35, 0.6), 4.0)
		var wh := snappedf(h * r.randf_range(0.4, 0.7), 4.0)
		var right := r.randf() < 0.5
		var down := r.randf() < 0.5
		var x := main.end.x if right else main.position.x - ww
		var y := main.end.y - wh if down else main.position.y
		parts.append(Rect2(x, y, ww, wh))
	return parts


## Every wheat field that reaches into the rectangle.
func fields_in(rect: Rect2) -> Array:
	var out: Array = []
	if field.is_empty() or empty:
		return out
	var wide := rect.grow(REGION * 0.75)
	for rx in range(floori(wide.position.x / REGION), floori(wide.end.x / REGION) + 1):
		for ry in range(floori(wide.position.y / REGION), floori(wide.end.y / REGION) + 1):
			var key := Vector2i(rx, ry)
			if not _fields.has(key):
				_region(rx, ry)
			for f in _fields[key]:
				if f.intersects(rect) and not _cleared(f):
					out.append(f)
	return out


## Whether a clearing laid after the field was made covers any of it.
func _cleared(f: Rect2) -> bool:
	for c in clearings:
		var near := Vector2(clampf(c[0].x, f.position.x, f.end.x), clampf(c[0].y, f.position.y, f.end.y))
		if near.distance_to(c[0]) < c[1]:
			return true
	return false


## Clears a circle of ground that may already be built and stands the run's own pieces in it.
func add_clearing(centre: Vector2, radius: float, pieces: Array) -> void:
	clearings.append([centre, radius])
	for key in _ravines:
		if not _ravines[key].is_empty() and edge_of(_ravines[key], centre) < radius:
			_ravines[key] = {}
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


## The solid ground of these wheat fields as (x0, y0, x1, y1): each field drawn a little smaller, so its ragged edge can be brushed past,
## and the strip off a field's corner reaching into the field it belongs to, so the two hold together with no seam between them.
func field_solids(fields: Array) -> PackedVector4Array:
	var inset := float(field.field_inset)
	var join := inset + float(field.field_corner)
	var out := PackedVector4Array()
	for f: Rect2 in fields:
		var x0 := f.position.x + inset
		var y0 := f.position.y + inset
		var x1 := f.end.x - inset
		var y1 := f.end.y - inset
		for g: Rect2 in fields:
			if g == f:
				continue
			var along_y := f.position.y >= g.position.y - 0.5 and f.end.y <= g.end.y + 0.5
			var along_x := f.position.x >= g.position.x - 0.5 and f.end.x <= g.end.x + 0.5
			if along_y and absf(f.position.x - g.end.x) < 0.5:
				x0 -= join
			elif along_y and absf(f.end.x - g.position.x) < 0.5:
				x1 += join
			elif along_x and absf(f.position.y - g.end.y) < 0.5:
				y0 -= join
			elif along_x and absf(f.end.y - g.position.y) < 0.5:
				y1 += join
		out.append(Vector4(x0, y0, x1, y1))
	return out


## Lists the wheat fields' solid ground near the commander in every grid cell it could touch a unit or a boss from.
func _grid_fields(area: Rect2) -> void:
	fd_rect = PackedVector4Array() if field.is_empty() or empty else field_solids(fields_in(area))
	fd_start.resize(GN * GN + 1)
	fd_start.fill(0)
	fd_items.clear()
	if fd_rect.is_empty():
		return
	var cells: Array = []
	cells.resize(GN * GN)
	for i in cells.size():
		cells[i] = PackedInt32Array()
	for idx in fd_rect.size():
		var rc := fd_rect[idx]
		var x0 := clampi(floori((rc.x - FIELD_REACH - origin.x) / CELL), 0, GN - 1)
		var x1 := clampi(floori((rc.z + FIELD_REACH - origin.x) / CELL), 0, GN - 1)
		var y0 := clampi(floori((rc.y - FIELD_REACH - origin.y) / CELL), 0, GN - 1)
		var y1 := clampi(floori((rc.w + FIELD_REACH - origin.y) / CELL), 0, GN - 1)
		for gx in range(x0, x1 + 1):
			for gy in range(y0, y1 + 1):
				cells[gx + gy * GN].append(idx)
	for i in cells.size():
		fd_start[i] = fd_items.size()
		fd_items.append_array(cells[i])
	fd_start[GN * GN] = fd_items.size()


## Whether a field's solid ground, a rectangle with rounded corners, covers any of the flow square centred on (cx, cy).
func _square_in_field(rc: Vector4, cx: float, cy: float) -> bool:
	var c := minf(float(field.field_corner), minf(rc.z - rc.x, rc.w - rc.y) / 2.0)
	var dx := maxf(0.0, maxf(rc.x + c - cx, cx - rc.z + c) - FLOW_CELL / 2.0)
	var dy := maxf(0.0, maxf(rc.y + c - cy, cy - rc.w + c) - FLOW_CELL / 2.0)
	return dx * dx + dy * dy < c * c


## Moves a circle out of one field's solid ground, a rectangle with rounded corners, the shortest way.
func _out_of_rect(rc: Vector4, p: Vector2, r: float) -> Vector2:
	var c := minf(float(field.field_corner), minf(rc.z - rc.x, rc.w - rc.y) / 2.0)
	var x0 := rc.x + c
	var y0 := rc.y + c
	var x1 := rc.z - c
	var y1 := rc.w - c
	var qx := clampf(p.x, x0, x1)
	var qy := clampf(p.y, y0, y1)
	var dx := p.x - qx
	var dy := p.y - qy
	var d2 := dx * dx + dy * dy
	var reach := c + r
	if d2 >= reach * reach:
		return p
	if d2 > 0.000001:
		var d := sqrt(d2)
		return Vector2(qx + dx / d * reach, qy + dy / d * reach)
	var left := p.x - x0
	var right := x1 - p.x
	var up := p.y - y0
	var down := y1 - p.y
	var least := minf(minf(left, right), minf(up, down))
	if least == left:
		return Vector2(x0 - reach, p.y)
	if least == right:
		return Vector2(x1 + reach, p.y)
	if least == up:
		return Vector2(p.x, y0 - reach)
	return Vector2(p.x, y1 + reach)


## The way along a wheat field's side for a man at p walking almost straight into it along `dir`: the way his step leans, or towards
## the nearer end of the side when it leans neither way. Zero when no field stands in his way.
func round_field(p: Vector2, r: float, dir: Vector2) -> Vector2:
	if fd_rect.is_empty():
		return Vector2.ZERO
	var gx := floori((p.x - origin.x) / CELL)
	var gy := floori((p.y - origin.y) / CELL)
	if gx < 0 or gy < 0 or gx >= GN or gy >= GN:
		return Vector2.ZERO
	var cell := gx + gy * GN
	for t in range(fd_start[cell], fd_start[cell + 1]):
		var rc := fd_rect[fd_items[t]]
		var out := _out_of_rect(rc, p, r + 1.0)
		if out == p:
			continue
		var n := (out - p).normalized()
		if n.dot(dir) > -0.9:
			return Vector2.ZERO
		var along := n.orthogonal()
		var lean := along.dot(dir)
		if absf(lean) > 0.05:
			return along * signf(lean)
		var mid := Vector2((rc.x + rc.z) / 2.0, (rc.y + rc.w) / 2.0)
		return along if along.dot(mid - p) < 0.0 else -along
	return Vector2.ZERO


## Moves a circle out of the wheat fields near the commander; a second pass settles one pushed from a field into the strip joined to it.
func field_push(p: Vector2, r: float) -> Vector2:
	if fd_rect.is_empty():
		return p
	var gx := floori((p.x - origin.x) / CELL)
	var gy := floori((p.y - origin.y) / CELL)
	if gx < 0 or gy < 0 or gx >= GN or gy >= GN:
		return p
	var cell := gx + gy * GN
	for k in 2:
		var before := p
		for t in range(fd_start[cell], fd_start[cell + 1]):
			p = _out_of_rect(fd_rect[fd_items[t]], p, r)
		if p == before:
			break
	return p


## Moves a circle anywhere on the field out of the wheat, for placing things beyond the grid round the commander.
func out_of_fields(p: Vector2, r: float) -> Vector2:
	if field.is_empty() or empty:
		return p
	var solids := field_solids(fields_in(Rect2(p, Vector2.ZERO).grow(r + float(field.field_corner) + 40.0)))
	for k in 3:
		var before := p
		for rc in solids:
			p = _out_of_rect(rc, p, r)
		if p == before:
			break
	return p


## Whether a circle at p overlaps any wheat field's solid ground.
func in_field(p: Vector2, r := 0.0) -> bool:
	return out_of_fields(p, r) != p


## Rebuilds the grid of solid props around p when p has moved into another chunk; push_out only sees props in this grid.
func refresh(p: Vector2) -> void:
	var c := Vector2i(floori(p.x / CHUNK), floori(p.y / CHUNK))
	if c == _anchor:
		return
	_anchor = c
	origin = (Vector2(c) + Vector2(0.5, 0.5)) * CHUNK - Vector2(GN, GN) * CELL / 2.0
	solid.clear()
	solid_tree.clear()
	var area := Rect2(origin, Vector2(GN, GN) * CELL)
	var all := props_in(area)
	for post in posts:
		if area.has_point(post[1]):
			all.append(post)
	# Each prop is listed in every cell it could touch a unit from, so a lookup reads one cell only.
	# The cells are counted first and then filled in prop order, which keeps every cell's list in that order.
	var box := PackedInt32Array()
	start.resize(GN * GN + 1)
	start.fill(0)
	for pr in all:
		var r: float = pr[2]
		if r <= 0.0:
			continue
		solid.append(Vector3(pr[1].x, pr[1].y, r))
		solid_tree.append(1 if TREES.has(pr[0]) and not _extra_at.has(pr[1]) else 0)
		var reach := r + MAX_UNIT
		var x0 := clampi(floori((pr[1].x - reach - origin.x) / CELL), 0, GN - 1)
		var x1 := clampi(floori((pr[1].x + reach - origin.x) / CELL), 0, GN - 1)
		var y0 := clampi(floori((pr[1].y - reach - origin.y) / CELL), 0, GN - 1)
		var y1 := clampi(floori((pr[1].y + reach - origin.y) / CELL), 0, GN - 1)
		box.append(x0)
		box.append(x1)
		box.append(y0)
		box.append(y1)
		for gx in range(x0, x1 + 1):
			for gy in range(y0, y1 + 1):
				start[gx + gy * GN + 1] += 1
	for i in range(1, GN * GN + 1):
		start[i] += start[i - 1]
	items.resize(start[GN * GN])
	var fill := start.duplicate()
	for idx in solid.size():
		for gx in range(box[idx * 4], box[idx * 4 + 1] + 1):
			for gy in range(box[idx * 4 + 2], box[idx * 4 + 3] + 1):
				var cell := gx + gy * GN
				items[fill[cell]] = idx
				fill[cell] += 1
	_grid_ravines(area)
	_grid_fields(area)
	_mark_blocked()


## Marks every flow square a barbarian cannot stand in because a solid prop covers it.
func _mark_blocked() -> void:
	flow_origin = origin + (Vector2(GN, GN) * CELL - Vector2(FN, FN) * FLOW_CELL) / 2.0
	blocked.resize(FN * FN)
	blocked.fill(0)
	var cxs := PackedFloat32Array()
	var cys := PackedFloat32Array()
	cxs.resize(FN)
	cys.resize(FN)
	for k in FN:
		var centre := flow_origin + (Vector2(k, k) + Vector2(0.5, 0.5)) * FLOW_CELL
		cxs[k] = centre.x
		cys[k] = centre.y
	# A square is closed when a prop covers any of it, so a thin line of rocks between two rows of square centres still closes a row.
	for sv in solid:
		var reach := sv.z
		var x0 := clampi(floori((sv.x - reach - flow_origin.x) / FLOW_CELL), 0, FN - 1)
		var x1 := clampi(floori((sv.x + reach - flow_origin.x) / FLOW_CELL), 0, FN - 1)
		var y0 := clampi(floori((sv.y - reach - flow_origin.y) / FLOW_CELL), 0, FN - 1)
		var y1 := clampi(floori((sv.y + reach - flow_origin.y) / FLOW_CELL), 0, FN - 1)
		var r2 := reach * reach
		for gx in range(x0, x1 + 1):
			var dx := maxf(0.0, absf(cxs[gx] - sv.x) - FLOW_CELL / 2.0)
			for gy in range(y0, y1 + 1):
				var dy := maxf(0.0, absf(cys[gy] - sv.y) - FLOW_CELL / 2.0)
				if dx * dx + dy * dy < r2:
					blocked[gx + gy * FN] = 1
	for k in rv_seg.size():
		var sg := rv_seg[k]
		var reach := maxf(rv_half[k].x, rv_half[k].y) + 8.0
		var x0 := clampi(floori((minf(sg.x, sg.z) - reach - flow_origin.x) / FLOW_CELL), 0, FN - 1)
		var x1 := clampi(floori((maxf(sg.x, sg.z) + reach - flow_origin.x) / FLOW_CELL), 0, FN - 1)
		var y0 := clampi(floori((minf(sg.y, sg.w) - reach - flow_origin.y) / FLOW_CELL), 0, FN - 1)
		var y1 := clampi(floori((maxf(sg.y, sg.w) + reach - flow_origin.y) / FLOW_CELL), 0, FN - 1)
		for gx in range(x0, x1 + 1):
			for gy in range(y0, y1 + 1):
				var centre := flow_origin + (Vector2(gx, gy) + Vector2(0.5, 0.5)) * FLOW_CELL
				if blocked[gx + gy * FN] == 0 and _seg_edge(k, centre) < 8.0 and on_bridge(centre) < 0:
					blocked[gx + gy * FN] = 1
	for rc in fd_rect:
		var x0 := clampi(floori((rc.x - flow_origin.x) / FLOW_CELL), 0, FN - 1)
		var x1 := clampi(floori((rc.z - flow_origin.x) / FLOW_CELL), 0, FN - 1)
		var y0 := clampi(floori((rc.y - flow_origin.y) / FLOW_CELL), 0, FN - 1)
		var y1 := clampi(floori((rc.w - flow_origin.y) / FLOW_CELL), 0, FN - 1)
		for gx in range(x0, x1 + 1):
			for gy in range(y0, y1 + 1):
				if _square_in_field(rc, cxs[gx], cys[gy]):
					blocked[gx + gy * FN] = 1
	_flow_goal = Vector2i(1 << 30, 0)


## Works out, for every open square, which way leads round the obstacles to the commander; redone when he moves to another square.
func update_flow(goal: Vector2) -> void:
	var g := Vector2i(floori((goal.x - flow_origin.x) / FLOW_CELL), floori((goal.y - flow_origin.y) / FLOW_CELL))
	if g == _flow_goal or g.x < 0 or g.y < 0 or g.x >= FN or g.y >= FN:
		return
	_flow_goal = g
	if _step_off.is_empty():
		for st in STEPS:
			_step_off.append(st.x + st.y * FN)
			_step_dx.append(st.x)
			_step_dy.append(st.y)
			_step_back.append(-Vector2(st).normalized())
		_edge.resize(FN * FN)
		for c in FN * FN:
			_edge[c] = 1 if c % FN == 0 or c / FN == 0 or c % FN == FN - 1 or c / FN == FN - 1 else 0
	var off := _step_off
	var sdx := _step_dx
	var sdy := _step_dy
	var back := _step_back
	var edge := _edge
	flow_dir.resize(FN * FN)
	flow_dir.fill(Vector2.ZERO)
	# Each square's state: bit 1 once reached, bit 2 when blocked.
	var state := blocked.duplicate()
	for c in FN * FN:
		state[c] <<= 1
	_queue.resize(FN * FN)
	var queue := _queue
	queue[0] = g.x + g.y * FN
	state[queue[0]] |= 1
	var head := 0
	var tail := 1
	while head < tail:
		var c := queue[head]
		head += 1
		var at_edge := edge[c] == 1
		for k in 8:
			if at_edge:
				var nx := c % FN + sdx[k]
				var ny := c / FN + sdy[k]
				if nx < 0 or ny < 0 or nx >= FN or ny >= FN:
					continue
			var n := c + off[k]
			if state[n] != 0:
				continue
			# A diagonal step may not cut the corner of a blocked square.
			if k >= 4 and (state[c + sdy[k] * FN] >= 2 or state[c + sdx[k]] >= 2):
				continue
			state[n] = 1
			flow_dir[n] = back[k]
			queue[tail] = n
			tail += 1
	# A barbarian caught among trees stands in blocked squares, so the map also spreads from open ground through the trees, pointing back out.
	# It starts again from the open squares in the order they were reached, so a blocked square points to the open one nearest the goal.
	head = 0
	while head < tail:
		var c := queue[head]
		head += 1
		var at_edge := edge[c] == 1
		for k in 8:
			if at_edge:
				var nx := c % FN + sdx[k]
				var ny := c / FN + sdy[k]
				if nx < 0 or ny < 0 or nx >= FN or ny >= FN:
					continue
			var n := c + off[k]
			if state[n] & 1 == 1:
				continue
			state[n] |= 1
			flow_dir[n] = back[k]
			queue[tail] = n
			tail += 1


## Whether p is clear of the forest, as far as the map round the commander knows; beyond it everything counts as open.
func is_open(p: Vector2) -> bool:
	var gx := floori((p.x - flow_origin.x) / FLOW_CELL)
	var gy := floori((p.y - flow_origin.y) / FLOW_CELL)
	if blocked.is_empty() or gx < 0 or gy < 0 or gx >= FN or gy >= FN:
		return true
	return blocked[gx + gy * FN] == 0


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
	var from := p
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
	if fd_start[cell] < fd_start[cell + 1]:
		p = field_push(p, r)
	if rv_start[cell] < rv_start[cell + 1]:
		p = ravine_push(p, r)
	if chop > 0.0 and p != from:
		legion_shoves += 1
	return p


## Chopping by a barbarian pressed against the tree at `at`, which never earns the legion a log.
func horde_chop(at: Vector2, dt: float) -> void:
	_chop(at, dt, 0.0)


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
	return ravine_push(field_push(p, r), r, true)


## Adds dt of chopping to the tree at at, `by_legion` of it done by the legion.
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


## The ravine of a region, kept `inset` inside it so two never come close: {pieces: [{pts, half}], box}, or {} for none.
func ravine(rx: int, ry: int) -> Dictionary:
	var key := Vector2i(rx, ry)
	if _ravines.has(key):
		return _ravines[key]
	var out := {}
	if not ravine_cfg.is_empty() and not empty:
		var r := RandomNumberGenerator.new()
		r.seed = hash([seed_value, "ravine", key])
		if r.randf() < float(ravine_cfg.chance):
			var size := float(ravine_cfg.region)
			var inner := Rect2(Vector2(rx, ry) * size, Vector2.ONE * size).grow(-float(ravine_cfg.inset) - float(ravine_cfg.width[1]) / 2.0)
			for k in int(ravine_cfg.tries):
				var made := _gorge_line(r, inner, ravine_cfg)
				if _fits(made, inner, ravine_cfg):
					out = made
					break
	_ravines[key] = out
	return out


## A winding gorge centred somewhere in `inner`, narrowing at its ends, sometimes broken by a natural land bridge.
func _gorge_line(r: RandomNumberGenerator, inner: Rect2, cfg: Dictionary) -> Dictionary:
	var ds := float(cfg.step)
	var length := r.randf_range(float(cfg.length[0]), float(cfg.length[1]))
	var w_lo := float(cfg.width[0]) / 2.0
	var w_hi := float(cfg.width[1]) / 2.0
	var max_turn := float(cfg.turn)
	var heading := r.randf() * TAU
	var turn := r.randf_range(-1.0, 1.0) * max_turn
	var line := PackedVector2Array([Vector2.ZERO])
	var p := Vector2.ZERO
	for i in int(length / ds):
		turn = clampf(turn + r.randf_range(-1.0, 1.0) * float(cfg.wander) * ds, -max_turn, max_turn)
		heading += turn * ds
		p += Vector2.from_angle(heading) * ds
		line.append(p)
	var centre := Vector2(r.randf_range(inner.position.x, inner.end.x), r.randf_range(inner.position.y, inner.end.y))
	var shift := centre - (line[0] + line[line.size() - 1]) / 2.0
	var taper := float(cfg.end_taper)
	var end_w := float(cfg.end_width)
	var cut_from := INF
	var cut_to := -INF
	if r.randf() < float(cfg.land_bridge_chance):
		var mid := r.randf_range(0.35, 0.65) * length
		# The narrowed ends and their cracks on either side reach into the gap, so the gap in the line is wider than the ground left between them.
		var gap := r.randf_range(float(cfg.land_bridge[0]), float(cfg.land_bridge[1])) + 2.0 * 2.2 * w_hi * end_w
		cut_from = mid - gap / 2.0
		cut_to = mid + gap / 2.0
	var width := r.randf_range(w_lo, w_hi)
	var drift := 0.0
	var pieces: Array = []
	var pts := PackedVector2Array()
	var half := PackedFloat32Array()
	for i in line.size():
		drift = clampf(drift + r.randf_range(-0.6, 0.6), -1.5, 1.5)
		width = clampf(width + drift, w_lo, w_hi)
		var along := i * ds
		if along > cut_from and along < cut_to:
			if pts.size() > 1:
				pieces.append({"pts": pts, "half": half})
			pts = PackedVector2Array()
			half = PackedFloat32Array()
			continue
		var to_end := minf(along, length - along)
		if cut_to > cut_from:
			to_end = minf(to_end, absf(along - (cut_from if along <= cut_from else cut_to)))
		pts.append(line[i] + shift)
		half.append(width * clampf(end_w + (1.0 - end_w) * to_end / taper, end_w, 1.0))
	if pts.size() > 1:
		pieces.append({"pts": pts, "half": half})
	return _with_box(_cracked({"pieces": pieces}))


## Each end of every piece runs on as a narrowing crack, so a gorge closes to a point, and the drop the legion and horde meet is the one drawn.
static func _cracked(rv: Dictionary) -> Dictionary:
	for piece in rv.pieces:
		var pts: PackedVector2Array = piece.pts.duplicate()
		var half: PackedFloat32Array = piece.half.duplicate()
		for end in 2:
			var k := 0 if end == 0 else pts.size() - 1
			var dir := (pts[k] - pts[1 if end == 0 else k - 1]).normalized()
			var w := half[k]
			for j in range(1, 4):
				var at := pts[k] + dir * w * 0.4 * j
				if end == 0:
					pts.insert(0, at)
					half.insert(0, w * (1.0 - j / 3.5))
				else:
					pts.append(at)
					half.append(w * (1.0 - j / 3.5))
		piece.pts = pts
		piece.half = half
	return rv


func _with_box(rv: Dictionary) -> Dictionary:
	var box := Rect2(rv.pieces[0].pts[0], Vector2.ZERO)
	var widest := 0.0
	for piece in rv.pieces:
		for q in piece.pts:
			box = box.expand(q)
		for h in piece.half:
			widest = maxf(widest, h)
	rv.box = box.grow(widest)
	return rv


## Whether a gorge or stream stays inside its room, clear of the start and of every clearing, and a stream clear of the ravines.
func _fits(rv: Dictionary, inner: Rect2, cfg: Dictionary) -> bool:
	var start_clear := float(cfg.start_clear)
	var gap := float(cfg.get("ravine_gap", -1.0))
	for piece in rv.pieces:
		for i in piece.pts.size():
			var q: Vector2 = piece.pts[i]
			if not inner.has_point(q) or q.length() < start_clear + piece.half[i]:
				return false
			if gap >= 0.0 and i % 4 == 0 and ravine_edge(q, piece.half[i] + gap + 200.0) < piece.half[i] + gap:
				return false
	for c in clearings:
		if edge_of(rv, c[0]) < c[1]:
			return false
	return true


## Lays a ravine by hand, given as pieces of {pts, half}, for tests and looks.
func add_ravine(pieces: Array) -> void:
	_laid.append(_with_box(_cracked({"pieces": pieces})))
	_anchor = Vector2i(1 << 30, 0)


## Every ravine whose ground reaches into the rectangle.
func ravines_in(rect: Rect2) -> Array:
	var out: Array = []
	for rv in _laid:
		if rv.box.intersects(rect):
			out.append(rv)
	if ravine_cfg.is_empty() or empty:
		return out
	var size := float(ravine_cfg.region)
	for rx in range(floori(rect.position.x / size), floori(rect.end.x / size) + 1):
		for ry in range(floori(rect.position.y / size), floori(rect.end.y / size) + 1):
			var rv := ravine(rx, ry)
			if not rv.is_empty() and rv.box.intersects(rect):
				out.append(rv)
	return out


## How far p is from the nearest ravine's lip, negative over the drop, ignoring bridges; INF when none is within `within`.
func ravine_edge(p: Vector2, within := 600.0) -> float:
	var best := INF
	for rv in ravines_in(Rect2(p - Vector2.ONE * within, Vector2.ONE * within * 2.0)):
		best = minf(best, edge_of(rv, p))
	return best


## How far p is from one ravine's lip, negative over the drop.
static func edge_of(rv: Dictionary, p: Vector2) -> float:
	var best := INF
	for piece in rv.pieces:
		var pts: PackedVector2Array = piece.pts
		var half: PackedFloat32Array = piece.half
		for i in pts.size() - 1:
			var a := pts[i]
			var ab := pts[i + 1] - a
			var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
			best = minf(best, p.distance_to(a + ab * t) - lerpf(half[i], half[i + 1], t))
	return best


## Whether p is in the band of open ground kept round every ravine and every frozen stream.
func _by_ravine(p: Vector2) -> bool:
	if not stream_cfg.is_empty() and stream_edge(p, float(stream_cfg.band) + float(stream_cfg.width[1])) < float(stream_cfg.band):
		return true
	if ravine_cfg.is_empty():
		return false
	var band := float(ravine_cfg.band)
	return ravine_edge(p, band + float(ravine_cfg.width[1])) < band


## The frozen stream of a stream region, laid out like a gorge but kept clear of the ravines: {pieces: [{pts, half}], box}, or {} for none.
func stream(rx: int, ry: int) -> Dictionary:
	var key := Vector2i(rx, ry)
	if _streams.has(key):
		return _streams[key]
	var out := {}
	if not stream_cfg.is_empty() and not empty:
		var r := RandomNumberGenerator.new()
		r.seed = hash([seed_value, "stream", key])
		if r.randf() < float(stream_cfg.chance):
			var size := float(stream_cfg.region)
			var inner := Rect2(Vector2(rx, ry) * size, Vector2.ONE * size).grow(-float(stream_cfg.inset) - float(stream_cfg.width[1]) / 2.0)
			for k in int(stream_cfg.tries):
				var made := _gorge_line(r, inner, stream_cfg)
				if _fits(made, inner, stream_cfg):
					out = made
					break
	_streams[key] = out
	return out


## Lays a frozen stream by hand, given as pieces of {pts, half}, for tests and looks.
func add_stream(pieces: Array) -> void:
	_laid_streams.append(_with_box(_cracked({"pieces": pieces})))


## Every frozen stream whose ice reaches into the rectangle.
func streams_in(rect: Rect2) -> Array:
	var out: Array = []
	for st in _laid_streams:
		if st.box.intersects(rect):
			out.append(st)
	if stream_cfg.is_empty() or empty:
		return out
	var size := float(stream_cfg.region)
	for rx in range(floori(rect.position.x / size), floori(rect.end.x / size) + 1):
		for ry in range(floori(rect.position.y / size), floori(rect.end.y / size) + 1):
			var st := stream(rx, ry)
			if not st.is_empty() and st.box.intersects(rect):
				out.append(st)
	return out


## How far p is from the nearest frozen stream's bank, negative on the ice; INF when none is within `within`.
func stream_edge(p: Vector2, within := 300.0) -> float:
	var best := INF
	for st in streams_in(Rect2(p - Vector2.ONE * within, Vector2.ONE * within * 2.0)):
		best = minf(best, edge_of(st, p))
	return best


## Whether p stands on the ice of a frozen stream.
func on_ice(p: Vector2) -> bool:
	if stream_cfg.is_empty() and _laid_streams.is_empty():
		return false
	return stream_edge(p, 160.0) < 0.0


## Lists the ravine segments near the commander in every grid cell they could touch a unit from, as the solid props are.
func _grid_ravines(area: Rect2) -> void:
	rv_seg.clear()
	rv_half.clear()
	var cells: Array = []
	cells.resize(GN * GN)
	for i in cells.size():
		cells[i] = PackedInt32Array()
	for rv in ravines_in(area):
		for piece in rv.pieces:
			var pts: PackedVector2Array = piece.pts
			# Collision reads every third point of the line, which strays under a pixel from the curve and lists a third as many segments per cell.
			for i in range(0, pts.size() - 1, 3):
				var j := mini(i + 3, pts.size() - 1)
				var a := pts[i]
				var z := pts[j]
				var reach := maxf(piece.half[i], piece.half[j]) + RAVINE_REACH
				var x0 := floori((minf(a.x, z.x) - reach - origin.x) / CELL)
				var x1 := floori((maxf(a.x, z.x) + reach - origin.x) / CELL)
				var y0 := floori((minf(a.y, z.y) - reach - origin.y) / CELL)
				var y1 := floori((maxf(a.y, z.y) + reach - origin.y) / CELL)
				if x1 < 0 or y1 < 0 or x0 >= GN or y0 >= GN:
					continue
				var idx := rv_seg.size()
				rv_seg.append(Vector4(a.x, a.y, z.x, z.y))
				rv_half.append(Vector2(piece.half[i], piece.half[j]))
				for gx in range(maxi(x0, 0), mini(x1, GN - 1) + 1):
					for gy in range(maxi(y0, 0), mini(y1, GN - 1) + 1):
						cells[gx + gy * GN].append(idx)
	rv_start.resize(GN * GN + 1)
	rv_items.clear()
	for i in cells.size():
		rv_start[i] = rv_items.size()
		rv_items.append_array(cells[i])
	rv_start[GN * GN] = rv_items.size()


## How far p is from the lip along one listed ravine segment, negative over the drop.
func _seg_edge(k: int, p: Vector2) -> float:
	var sg := rv_seg[k]
	var a := Vector2(sg.x, sg.y)
	var ab := Vector2(sg.z, sg.w) - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
	return p.distance_to(a + ab * t) - lerpf(rv_half[k].x, rv_half[k].y, t)


## Moves a circle out of the ravines near the commander, or keeps it between a bridge's sides; `wide` is for the bosses.
func ravine_push(p: Vector2, r: float, wide := false) -> Vector2:
	if rv_start.is_empty():
		return p
	var gx := floori((p.x - origin.x) / CELL)
	var gy := floori((p.y - origin.y) / CELL)
	var span := ceili(maxf(0.0, r - RAVINE_REACH) / CELL) if wide else 0
	if gx + span < 0 or gy + span < 0 or gx - span >= GN or gy - span >= GN:
		return p
	var deck := -2
	for cx in range(maxi(gx - span, 0), mini(gx + span, GN - 1) + 1):
		for cy in range(maxi(gy - span, 0), mini(gy + span, GN - 1) + 1):
			var cell := cx + cy * GN
			for t in range(rv_start[cell], rv_start[cell + 1]):
				var k := rv_items[t]
				var sg := rv_seg[k]
				var a := Vector2(sg.x, sg.y)
				var ab := Vector2(sg.z, sg.w) - a
				var u := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
				var q := a + ab * u
				var reach := lerpf(rv_half[k].x, rv_half[k].y, u) + r
				var away := p - q
				var d2 := away.length_squared()
				if d2 >= reach * reach:
					continue
				if deck == -2:
					deck = on_bridge(p)
				if deck >= 0:
					return _keep_on(bridges[deck], p, r)
				var d := sqrt(d2)
				p = q + (away / d if d > 0.001 else ab.orthogonal().normalized()) * reach
	return p


## The bridge whose deck p stands on, or -1.
func on_bridge(p: Vector2) -> int:
	for i in bridges.size():
		var br: Dictionary = bridges[i]
		var off: Vector2 = p - br.pos
		if absf(off.dot(br.dir)) <= br.half_len and absf(off.dot(br.dir.orthogonal())) <= br.half_w:
			return i
	return -1


## Keeps a circle on a bridge's deck, between its sides.
func _keep_on(br: Dictionary, p: Vector2, r: float) -> Vector2:
	var side: Vector2 = br.dir.orthogonal()
	var across: float = (p - br.pos).dot(side)
	var room := maxf(0.0, br.half_w - r)
	return p - side * (across - clampf(across, -room, room))


## Whether p is over the drop of a ravine near the commander, by more than `depth`, and not on a bridge.
func over_ravine(p: Vector2, depth := 0.0) -> bool:
	if rv_start.is_empty():
		return false
	var gx := floori((p.x - origin.x) / CELL)
	var gy := floori((p.y - origin.y) / CELL)
	if gx < 0 or gy < 0 or gx >= GN or gy >= GN:
		return false
	var cell := gx + gy * GN
	for t in range(rv_start[cell], rv_start[cell + 1]):
		if _seg_edge(rv_items[t], p) < -depth:
			return on_bridge(p) < 0
	return false


## Whether the straight walk from a to b passes over a ravine's drop near the commander.
func crosses_ravine(a: Vector2, b: Vector2) -> bool:
	if rv_items.is_empty():
		return false
	var n := ceili(a.distance_to(b) / 10.0)
	for i in range(1, n + 1):
		var p := a.lerp(b, float(i) / n)
		var gx := floori((p.x - origin.x) / CELL)
		var gy := floori((p.y - origin.y) / CELL)
		if gx < 0 or gy < 0 or gx >= GN or gy >= GN:
			continue
		var cell := gx + gy * GN
		if rv_start[cell] < rv_start[cell + 1] and over_ravine(p):
			return true
	return false


## The ravine straight ahead along `dir` as [distance to the drop, distance to the far lip], or [] when none is in reach.
func span_ahead(from: Vector2, dir: Vector2, reach: float, longest: float) -> Array:
	var near := -1.0
	var t := 0.0
	while t <= reach:
		if ravine_edge(from + dir * t) < 0.0:
			near = t
			break
		t += 4.0
	if near < 0.0:
		return []
	t = near
	while t <= near + longest:
		if ravine_edge(from + dir * t) >= 0.0:
			return [near, t]
		t += 4.0
	return []


## Lays a bridge with its deck from a to b, `half_w` either side of the line between them.
func add_bridge(a: Vector2, b: Vector2, half_w: float) -> void:
	bridges.append({"pos": (a + b) / 2.0, "dir": (b - a).normalized(), "half_len": a.distance_to(b) / 2.0, "half_w": half_w})
	_anchor = Vector2i(1 << 30, 0)
