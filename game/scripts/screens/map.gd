class_name MapScreen
extends RefCounted
## The map: the painted frontier with the legion's road from Rome through the provinces in the order they open, and a panel for the one selected.

## The difficulties, easiest first, with their names.
const LEVELS := [["easy", "Easy"], ["medium", "Medium"], ["hard", "Hard"]]
## The modes a province opens once it is won.
const MODES := [["endless", "Endless"], ["decimatio", "Decimatio"]]
## The record table's columns: each difficulty's fastest win, fastest win with Decimatio and longest Endless run.
const TIMES := [["win", "Victory"], ["decimatio", "Decimatio"], ["endless", "Endless"]]
## The painted map's projection, the same as tools/art/make_map.py: equirectangular from 11.5°W and 58.9°N, with longitude scaled by cos 42°.
const WEST := -11.5
const NORTH := 58.9
const PX_PER_DEG := 13.8
const LON_SCALE := 0.7431448
## Where each province lies, as longitude and latitude; Parthia sits north of Ctesiphon (33°N) and Aegyptus out at sea north of the Nile delta (31°N), to stay above the key hints at the map's foot.
const PLACES := {"roma": Vector2(12.5, 41.9), "germania": Vector2(9.0, 51.5), "britannia": Vector2(-1.0, 52.0), "gaul": Vector2(2.5, 47.0),
	"dacia": Vector2(24.5, 46.0), "parthia": Vector2(44.5, 35.2), "hispania": Vector2(-4.5, 40.2), "aegyptus": Vector2(30.5, 35.0),
	"sarmatia": Vector2(32.5, 47.8)}
## The towns, passes and sea lanes each march goes by, as longitude and latitude, so the road keeps to the land except where it sails.
const ROUTES := {
	"roma>germania": [Vector2(11.0, 45.4), Vector2(11.5, 47.0), Vector2(10.9, 48.4), Vector2(8.3, 50.0)],
	"germania>gaul": [Vector2(6.95, 50.9), Vector2(6.6, 49.75), Vector2(4.0, 49.25)],
	"gaul>britannia": [Vector2(0.7, 47.4), Vector2(1.1, 49.4), Vector2(0.4, 50.5)],
	"britannia>hispania": [Vector2(-2.8, 50.7), Vector2(-5.5, 49.4), Vector2(-7.0, 47.0), Vector2(-7.4, 45.6), Vector2(-6.0, 43.9), Vector2(-5.8, 43.3),
		Vector2(-5.6, 41.6)],
	"hispania>aegyptus": [Vector2(-1.0, 37.6), Vector2(3.0, 37.4), Vector2(8.5, 37.6), Vector2(11.8, 37.4), Vector2(15.0, 36.3), Vector2(20.0, 35.2),
		Vector2(25.0, 34.6), Vector2(28.5, 34.7)],
	"aegyptus>parthia": [Vector2(33.0, 34.6), Vector2(35.8, 34.5), Vector2(38.3, 34.6), Vector2(40.5, 34.6), Vector2(42.8, 35.0)],
	"parthia>dacia": [Vector2(43.2, 36.4), Vector2(41.2, 37.1), Vector2(38.8, 37.3), Vector2(36.0, 37.7), Vector2(34.6, 37.9), Vector2(32.9, 39.9),
		Vector2(29.0, 41.0), Vector2(24.5, 43.7)],
	"dacia>sarmatia": [Vector2(26.8, 46.5), Vector2(28.6, 46.9), Vector2(30.4, 47.4)],
}
const PICTURE := Vector2(640, 360)
const NODE_R := 9.0
const ROAD := Color(0.72, 0.12, 0.1)
const SHADE := Color(0.06, 0.04, 0.03, 0.72)

var main: Node
## The province the panel describes: the last node focused, kept while focus is on the panel's buttons.
var selected := ""
var _picture: Texture2D
# The road's marks for the provinces they were laid along.
var _marks_for: Array = []
var _marks: Array = []


func _init(owner_node: Node) -> void:
	main = owner_node


func activate(id: String) -> void:
	var parts := id.split(":")
	var setup: Dictionary = main.run_setup
	if parts[0] == "prov":
		selected = parts[1]
		if parts[1] != setup.province:
			setup.province = parts[1]
			for m in MODES:
				setup[m[0]] = false
		Profile.data.choices.province = setup.province
		Profile.save()
	elif parts[0] in Sim.DIFFICULTIES:
		if parts[1] != setup.province:
			activate("prov:" + parts[1])
		setup.difficulty = parts[0]
		Profile.data.choices.difficulty = parts[0]
		Profile.save()
	elif Profile.record_of(parts[1]).won:
		if parts[1] != setup.province:
			activate("prov:" + parts[1])
		setup[parts[0]] = not setup[parts[0]]


## The panel follows keys and a gamepad from province to province, but the pointer only by a click, so passing over the map leaves the difficulty being set where it is.
func follow_focus(ui: Ui) -> void:
	var id := ui.focus.trim_prefix("prov:")
	if ui.focus.begins_with("prov:") and not ui.pointer_focus and main.content.provinces.has(id):
		selected = id


static func clock(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


## A province the legion can march to: drawn, and unlocked by winning the one before it.
func is_open(id: String) -> bool:
	return main.content.ready("provinces", id) and Profile.province_unlocked(id)


## What opens a locked province: winning the drawn one before it, or its art when that is all it waits for.
func locked_text(id: String) -> String:
	var before: String = main.content.province_before(id)
	if main.content.ready("provinces", id) and before != "" and not Profile.record_of(before).won:
		return tr("Win in %s to open") % main.content.provinces[before].name
	return tr("Not ready yet")


## The provinces on the road, in the order they open.
func road() -> Array:
	var ids: Array = []
	for id in main.content.provinces:
		if Game.province_allowed(id, main.balance):
			ids.append(id)
	return ids


## The state of a province's node: won, open, locked, or fog for one that is not drawn yet.
func state_of(id: String) -> String:
	if not main.content.ready("provinces", id):
		return "fog"
	if not is_open(id):
		return "locked"
	return "won" if Profile.record_of(id).won else "open"


## The short line under a node's name.
func state_text(id: String) -> String:
	match state_of(id):
		"won":
			return tr("Hard won") if Profile.record_of(id).hard_won else tr("Won")
		"open":
			return tr("Marching here") if main.run_setup.province == id else tr("March here")
	return locked_text(id)


## Where the map is drawn: the whole 640 by 360 box.
static func picture_rect() -> Rect2:
	return Rect2(0, 0, Ui.W, Ui.H)


## A longitude and latitude on the painted map in screen pixels.
static func project(lon_lat: Vector2) -> Vector2:
	var r := picture_rect()
	var at := Vector2((lon_lat.x - WEST) * LON_SCALE, NORTH - lon_lat.y) * PX_PER_DEG
	return r.position + at * r.size / PICTURE


## A province's place on the painted map in screen pixels.
static func spot(id: String) -> Vector2:
	if not PLACES.has(id):
		return (picture_rect().get_center()).round()
	return project(PLACES[id]).round()


## The panel with the selected province's records and modes, over the sea and the steppe at the top right; with large text it is wide and short, so Dacia and Sarmatia stay in sight below it.
static func panel_rect() -> Rect2:
	return Rect2(Ui.W - 254, 8, 246, 36.0 + 8.0 * Ui.leading()) if Ui.scale == 1 else Rect2(296, 8, Ui.W - 304, 126)


## The road from one province to the next: a smooth curve through the towns on its route, or a bent line where it has none.
static func route(from_id: String, to_id: String, bend: float) -> PackedVector2Array:
	var vias: Array = ROUTES.get(from_id + ">" + to_id, [])
	if vias.is_empty():
		return road_points(spot(from_id), spot(to_id), bend)
	var stops: Array = [spot(from_id)]
	for v in vias:
		stops.append(project(v))
	stops.append(spot(to_id))
	var out := PackedVector2Array()
	for i in stops.size() - 1:
		var p0: Vector2 = stops[maxi(i - 1, 0)]
		var p1: Vector2 = stops[i]
		var p2: Vector2 = stops[i + 1]
		var p3: Vector2 = stops[mini(i + 2, stops.size() - 1)]
		for k in 8:
			var t := k / 8.0
			out.append(0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t * t + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t * t * t))
	out.append(stops[stops.size() - 1])
	return out


## The points of the curved road from one place to the next, bending to alternate sides so the march winds.
static func road_points(a: Vector2, b: Vector2, bend: float) -> PackedVector2Array:
	var mid := (a + b) / 2.0 + (b - a).orthogonal() * bend
	var out := PackedVector2Array()
	for i in 25:
		var t := i / 24.0
		out.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
	return out


func draw(c: CanvasItem, ui: Ui) -> void:
	var content: Content = main.content
	var setup: Dictionary = main.run_setup
	var now := Time.get_ticks_msec() / 1000.0
	var ids := road()
	if selected == "" or not ids.has(selected):
		selected = setup.province if ids.has(setup.province) else ids[0]
	follow_focus(ui)
	Ui.veil(c, 0.85)
	if _picture == null:
		_picture = load("res://assets/map.png")
	c.draw_texture_rect(_picture, picture_rect(), false)
	_road(c, ids, now)
	# The chosen province's node goes first so it has focus when the map opens.
	var order: Array = ids.duplicate()
	order.erase(setup.province)
	order.push_front(setup.province)
	for id in order:
		_node(c, ui, id, now)
	_fog(c, ids, now)
	_labels(c, ui, ids)
	_panel(c, ui, selected)
	_header(c, ui)
	_links(ui, ids)
	if Touch.phone:
		ui.corner_back(c)


## The road from Rome through every province: solid where the legion has marched, dashes beyond, moving towards the next to win.
func _road(c: CanvasItem, ids: Array, now: float) -> void:
	var from := "roma"
	var walked := true
	for i in ids.size():
		var pts := route(from, ids[i], 0.18 if i % 2 == 0 else -0.18)
		var won: bool = state_of(ids[i]) == "won"
		var next: bool = walked and not won
		if walked and won:
			c.draw_polyline(pts, Color(0.1, 0.05, 0.03), 4.0)
			c.draw_polyline(pts, ROAD, 2.0)
		else:
			_dashes(c, pts, Color(0.1, 0.05, 0.03), 4.0, now * 14.0 if next else 0.0)
			_dashes(c, pts, ROAD if next else Color(0.42, 0.3, 0.22), 2.0, now * 14.0 if next else 0.0)
		# A province not drawn yet is passed through, so the march still leads on to the next one that is.
		walked = walked and (won or state_of(ids[i]) == "fog")
		from = ids[i]
	_rome(c)


## Dashes along a line, `shift` pixels along so they march.
static func _dashes(c: CanvasItem, pts: PackedVector2Array, col: Color, width: float, shift: float) -> void:
	var dash := 7.0
	var gap := 5.0
	var run := -fmod(shift, dash + gap)
	for i in pts.size() - 1:
		var a := pts[i]
		var b := pts[i + 1]
		var length := a.distance_to(b)
		var d := 0.0
		while d < length:
			var phase := fposmod(run + d, dash + gap)
			var step := minf(length - d, (dash - phase) if phase < dash else (dash + gap - phase))
			if phase < dash:
				c.draw_line(a.lerp(b, d / length), a.lerp(b, (d + step) / length), col, width)
			d += maxf(step, 0.5)
		run += length


## Rome, where every march starts: a gold eagle on a red disc.
func _rome(c: CanvasItem) -> void:
	var p := spot("roma")
	c.draw_circle(p, NODE_R + 2.0, Ui.INK)
	c.draw_circle(p, NODE_R, Ui.GOLD)
	c.draw_circle(p, NODE_R - 3.0, Ui.RED)
	var atlas: Atlas = main.world.atlas
	if atlas != null and atlas.props.has("eagle_standard"):
		var f: Rect2 = atlas.prop_frame("eagle_standard")[0]
		c.draw_texture_rect_region(atlas.texture, Rect2(p + Vector2(-f.size.x / 2.0, -f.size.y + 4.0), f.size), f)


## A province's node, drawn by its state, with a button over it.
func _node(c: CanvasItem, ui: Ui, id: String, now: float) -> void:
	var p := spot(id)
	var state := state_of(id)
	var hit := Rect2(p - Vector2.ONE * (NODE_R + 6.0), Vector2.ONE * (NODE_R + 6.0) * 2.0)
	# The panel's buttons take every click that lands on the panel.
	ui.register(hit, "prov:" + id, state == "won" or state == "open", not panel_rect().intersects(hit))
	var chosen: bool = main.run_setup.province == id and (state == "won" or state == "open")
	# The province the legion marches to next glows, so a click on another visibly moves the choice there.
	if chosen:
		var glow := 0.5 + 0.5 * sin(now * 4.0)
		c.draw_circle(p, NODE_R + 5.0 + 4.0 * glow, Color(1.0, 0.85, 0.4, 0.5 - 0.3 * glow))
		c.draw_arc(p, NODE_R + 4.0, 0.0, TAU, 32, Ui.GOLD, 2.0)
	if ui.focus == "prov:" + id:
		c.draw_arc(p, NODE_R + 6.0, 0.0, TAU, 32, Ui.GOLD_LIGHT, 2.0)
	match state:
		"won":
			c.draw_circle(p, NODE_R + 2.0, Ui.INK)
			c.draw_circle(p, NODE_R, Color(0.2, 0.42, 0.16))
			_laurel(c, p)
			_check(c, p)
			if Profile.record_of(id).hard_won:
				_pennant(c, p + Vector2(NODE_R - 1.0, -NODE_R - 2.0))
		"open":
			c.draw_circle(p, NODE_R + 2.0, Ui.INK)
			c.draw_circle(p, NODE_R, Ui.GOLD_LIGHT if chosen else Ui.GOLD)
			c.draw_circle(p, NODE_R - 3.0, Ui.RED)
		"locked":
			c.draw_circle(p, NODE_R + 2.0, Color(0.1, 0.07, 0.05, 0.85))
			c.draw_circle(p, NODE_R, Color(0.42, 0.38, 0.34))
			c.draw_circle(p, NODE_R - 3.0, Color(0.27, 0.24, 0.21))
	if chosen:
		_banner(c, p)


## Clouds over the provinces not drawn yet, drifting a little.
func _fog(c: CanvasItem, ids: Array, now: float) -> void:
	for id in ids:
		if state_of(id) != "fog":
			continue
		var p := spot(id)
		for k in 9:
			var a := k * 2.4
			var drift := Vector2(sin(now * 0.4 + k), cos(now * 0.3 + k * 1.7)) * 2.0
			var at := p + Vector2(cos(a), sin(a) * 0.55) * (8.0 + (k % 3) * 9.0) + drift
			var size := 15.0 - (k % 3) * 2.5
			c.draw_circle(at + Vector2(0, 2), size, Color(0.45, 0.48, 0.55, 0.35))
			c.draw_circle(at, size, Color(0.93, 0.94, 0.96, 0.82))


## A wreath of gold leaves round a won node.
static func _laurel(c: CanvasItem, p: Vector2) -> void:
	for side in [-1.0, 1.0]:
		for i in 6:
			var a := deg_to_rad(115.0 + 22.0 * i)
			var q := p + Vector2(cos(a) * side, -sin(a)) * (NODE_R + 3.0)
			c.draw_rect(Rect2(floorf(q.x) - 1.0, floorf(q.y) - 1.0, 3, 3), Ui.GOLD if i % 2 == 0 else Ui.GOLD_LIGHT)
			c.draw_rect(Rect2(floorf(q.x) - 1.0, floorf(q.y) + 2.0, 3, 1), Ui.INK)


static func _check(c: CanvasItem, p: Vector2) -> void:
	var pts := PackedVector2Array([p + Vector2(-4, 0), p + Vector2(-1, 3), p + Vector2(4, -3)])
	c.draw_polyline(pts, Ui.INK, 4.0)
	c.draw_polyline(pts, Ui.CREAM, 2.0)


## The red pennant of a province won on Hard.
static func _pennant(c: CanvasItem, p: Vector2) -> void:
	c.draw_line(p, p + Vector2(0, 12), Ui.INK, 2.0)
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(-1, -1), p + Vector2(10, 3), p + Vector2(-1, 7)]), Ui.INK)
	c.draw_colored_polygon(PackedVector2Array([p + Vector2(1, 0), p + Vector2(7, 3), p + Vector2(1, 5)]), Ui.RED)


## The legion's standard planted by the province it marches to next.
func _banner(c: CanvasItem, p: Vector2) -> void:
	var atlas: Atlas = main.world.atlas
	if atlas == null or not atlas.props.has("eagle_standard"):
		return
	var f: Rect2 = atlas.prop_frame("eagle_standard")[0]
	c.draw_texture_rect_region(atlas.texture, Rect2(p + Vector2(NODE_R + 1.0, -f.size.y + 3.0), f.size), f)


## Each province's name and state on a dark plate by its node, clear of the rest; with large text only the selected one's state is written.
func _labels(c: CanvasItem, ui: Ui, ids: Array) -> void:
	var placed: Array = [panel_rect().grow(4.0), Rect2(spot("roma") - Vector2(12, 46), Vector2(24, 58))]
	for id in ids:
		var p := spot(id)
		placed.append(Rect2(p - Vector2.ONE * (NODE_R + 4.0), Vector2.ONE * (NODE_R + 4.0) * 2.0))
		if main.run_setup.province == id:
			placed.append(Rect2(p + Vector2(NODE_R, -46), Vector2(22, 46)))
	var marks := _road_marks(ids)
	var room := 200.0 if Ui.scale == 1 else 260.0
	for id in ids:
		var name: String = main.content.provinces[id].name.to_upper()
		var line := state_text(id)
		var two: bool = Ui.scale == 1 or id == selected
		var w := maxf(Ui.width_at(name, Ui.px), Ui.width_at(line, Ui.fit_size(line, room)) if two else 0.0)
		w = minf(w, room)
		var h := Ui.leading() * (2.0 if two else 1.0)
		var p := spot(id)
		var tries: Array = [Rect2(p.x - w / 2.0, p.y + NODE_R + 6.0, w, h), Rect2(p.x - w / 2.0, p.y - NODE_R - 6.0 - h, w, h),
			Rect2(p.x + NODE_R + 8.0, p.y - h / 2.0, w, h), Rect2(p.x - NODE_R - 8.0 - w, p.y - h / 2.0, w, h),
			Rect2(p.x - w / 2.0, p.y - NODE_R - 10.0 - 2.0 * h, w, h)]
		var at := plate_spot(tries, placed, marks)
		placed.append(at.grow(2.0))
		var state := state_of(id)
		c.draw_rect(at.grow(3.0), SHADE)
		var name_col := Ui.GOLD_LIGHT if state == "won" or state == "open" else Color(0.78, 0.74, 0.68)
		ui.text(c, name, Vector2(at.position.x, at.position.y + Ui.px), name_col, HORIZONTAL_ALIGNMENT_CENTER, at.size.x)
		if two:
			var col := Ui.CREAM if state == "open" else (Color(0.6, 0.85, 0.5) if state == "won" else Color(0.72, 0.66, 0.6))
			ui.fit_text(c, line, room, Vector2(at.position.x, at.position.y + Ui.px + Ui.leading()), col, HORIZONTAL_ALIGNMENT_CENTER, at.size.x)


## Where a plate goes of the `tries`, each held on the map above the key hints: of the sides clear of the `placed` plates and nodes, the one
## covering the fewest of the road's `marks`, or, when none is clear, the one that covers the others least.
static func plate_spot(tries: Array, placed: Array, marks: Array) -> Rect2:
	var at := Rect2()
	var least := INF
	var fallback := Rect2()
	var least_cover := INF
	for t: Rect2 in tries:
		t.position.x = clampf(t.position.x, 6.0, Ui.W - t.size.x - 6.0)
		t.position.y = clampf(t.position.y, 4.0, Ui.H - t.size.y - 20.0)
		var cover := 0.0
		for q: Rect2 in placed:
			cover += q.intersection(t.grow(2.0)).get_area()
		if cover > 0.0:
			if cover < least_cover:
				least_cover = cover
				fallback = t
			continue
		var covered := 0
		var wide: Rect2 = t.grow(3.0)
		for m in marks:
			covered += 1 if wide.has_point(m) else 0
		if covered < least:
			least = covered
			at = t
	return at if least < INF else fallback


## Points every few pixels along the road from Rome through the provinces, which the plates try not to cover.
func _road_marks(ids: Array) -> Array:
	# The road only changes with the provinces on it, so its marks are kept between frames.
	if ids == _marks_for:
		return _marks
	var out: Array = []
	var from := "roma"
	for i in ids.size():
		var pts := route(from, ids[i], 0.18 if i % 2 == 0 else -0.18)
		for k in pts.size() - 1:
			var steps := maxi(1, ceili(pts[k].distance_to(pts[k + 1]) / 4.0))
			for j in steps:
				out.append(pts[k].lerp(pts[k + 1], float(j) / steps))
		from = ids[i]
	_marks_for = ids.duplicate()
	_marks = out
	return out


## The key hints on a dark strip, so they read over the painted map.
func _header(c: CanvasItem, ui: Ui) -> void:
	var hint := Controls.hint("pick")
	if hint == "":
		return
	var size := Ui.fit_size(hint, Ui.W - 16.0)
	c.draw_rect(Rect2(0, Ui.H - Ui.lead_for(size) - 6.0, Ui.W, Ui.lead_for(size) + 6.0), SHADE)
	ui.text(c, hint, Vector2(0, Ui.H - 6), Ui.CREAM, HORIZONTAL_ALIGNMENT_CENTER, Ui.W, true, size)


## Whether the panel holds the whole record table; with large text it shows only the chosen difficulty's row.
static func full_table() -> bool:
	return Ui.scale == 1


## The widths of the record table's columns across `width`: the difficulties' names, then one for each of TIMES, which share the room left.
static func table_columns(width: float) -> Array:
	var names := 0.0
	for l in LEVELS:
		names = maxf(names, Ui.width_at(TranslationServer.translate(l[1]), Ui.px))
	var out: Array = [names + 8.0]
	var spare: float = width - out[0]
	for t in TIMES:
		out.append(maxf(Ui.width_at(TranslationServer.translate(t[1]), Ui.px), Ui.width_at("99:59", Ui.px)))
		spare -= out[out.size() - 1]
	for k in range(1, out.size()):
		out[k] += maxf(spare, 0.0) / TIMES.size()
	return out


## The width of each of the chosen difficulty's times across the large panel, with its name above it.
static func time_column(width: float) -> float:
	return width / TIMES.size()


## A row for each difficulty: its name, then each of TIMES as a clock, or "-" where it has none.
func record_rows(id: String) -> Array:
	var rows: Array = []
	for l in LEVELS:
		var row: Array = [tr(l[1])]
		for t in TIMES:
			var seconds: float = Profile.mode_time(id, l[0], t[0])
			row.append(clock(seconds) if seconds > 0.0 else "-")
		rows.append(row)
	return rows


## The parchment panel for one province: its name and state, records, the difficulty and, once it is won, the mode switches.
func _panel(c: CanvasItem, ui: Ui, id: String) -> void:
	var content: Content = main.content
	var info: Dictionary = content.provinces[id]
	var setup: Dictionary = main.run_setup
	var big := Ui.scale > 1
	var r := panel_rect()
	ui.panel(c, r)
	var x := r.position.x + 8.0
	var w := r.size.x - 16.0
	var y := r.position.y + 6.0 + Ui.px
	var state := state_of(id)
	ui.fit_text(c, info.name.to_upper(), w, Vector2(x, y), Ui.INK if state != "fog" and state != "locked" else Ui.MUTED)
	y += Ui.leading()
	var shut := state == "fog" or state == "locked"
	# With large text the plate by the node already says whether the province is won or open.
	if not big or shut:
		var tag := state_text(id).to_upper()
		ui.fit_text(c, tag, w, Vector2(x, y), Ui.RED if state == "open" else Ui.BROWN)
		y += Ui.leading()
	y += 2.0
	if shut:
		return
	var rec := Profile.record_of(id)
	# A province not yet won has no times, so the large panel leaves them out.
	if not big or rec.won:
		_records(c, ui, id, x, y, w)
	var bh := 14.0 if not big else 22.0
	# Below the difficulty there is room for the mode switches or for the two lines that say how to open them.
	var below := bh if big and rec.won else maxf(bh, 2.0 * Ui.leading())
	var top := r.end.y - 6.0 - below - 4.0 - bh
	_levels(c, ui, id, Rect2(x, top, w, bh))
	top += bh + 4.0
	if not rec.won:
		ui.wrap_fit(c, tr("Win here to open Endless and Decimatio"), Vector2(x, top + Ui.px - 1.0), w, Ui.MUTED, 2)
		return
	var bw := (w - (MODES.size() - 1) * 4.0) / MODES.size()
	for k in MODES.size():
		var on: bool = setup[MODES[k][0]] and setup.province == id
		var at := Vector2(x + k * (bw + 4.0), top)
		var b := Rect2(at, Vector2(bw, bh))
		ui.button(c, b, "%s:%s" % [MODES[k][0], id], "")
		var box := Rect2(b.position + Vector2(5.0, (bh - Ui.px) / 2.0), Vector2.ONE * Ui.px)
		c.draw_rect(box, Ui.INK, false, 1.0)
		if on:
			c.draw_rect(box.grow(-2.0), Ui.RED)
		var room := b.size.x - Ui.px - 14.0
		ui.fit_text(c, tr(MODES[k][1]), room, Vector2(box.end.x + 4.0, b.position.y + bh / 2.0 + Ui.px * 3 / 8), Ui.INK)


## The best times from `y` down: a row for each difficulty with the chosen one marked, or with large text the chosen one's alone, across.
func _records(c: CanvasItem, ui: Ui, id: String, x: float, y: float, w: float) -> void:
	var rows := record_rows(id)
	var chosen := maxi(0, Sim.DIFFICULTIES.find(main.run_setup.difficulty))
	if not full_table():
		var col := time_column(w)
		for j in TIMES.size():
			var t: String = rows[chosen][j + 1]
			var at := Vector2(x + j * col, y)
			ui.fit_text(c, tr(TIMES[j][1]), col - 4.0, at, Ui.BROWN, HORIZONTAL_ALIGNMENT_CENTER, col)
			ui.text(c, t, at + Vector2(0, Ui.leading()), Ui.MUTED if t == "-" else Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, col)
		return
	var cols := table_columns(w)
	var at := x + float(cols[0])
	for j in TIMES.size():
		ui.fit_text(c, tr(TIMES[j][1]), cols[j + 1], Vector2(at, y), Ui.BROWN, HORIZONTAL_ALIGNMENT_CENTER, cols[j + 1])
		at += cols[j + 1]
	y += Ui.leading()
	for k in rows.size():
		if k == chosen:
			c.draw_rect(Rect2(x - 3.0, y - Ui.px - 1.0, w + 6.0, Ui.leading()), Color(Ui.RED, 0.18))
		ui.fit_text(c, rows[k][0], cols[0] - 4.0, Vector2(x, y), Ui.RED if k == chosen else Ui.INK)
		at = x + float(cols[0])
		for j in TIMES.size():
			var t: String = rows[k][j + 1]
			ui.text(c, t, Vector2(at, y), Ui.MUTED if t == "-" else Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, cols[j + 1])
			at += cols[j + 1]
		y += Ui.leading()


## The three-way difficulty choice across `row`, the chosen one filled red.
func _levels(c: CanvasItem, ui: Ui, id: String, row: Rect2) -> void:
	var widths := level_widths(row.size.x)
	var x := row.position.x
	for k in LEVELS.size():
		var bw: float = widths[k]
		var b := Rect2(Vector2(x, row.position.y), Vector2(bw, row.size.y))
		x += bw + 4.0
		ui.button(c, b, "%s:%s" % [LEVELS[k][0], id], "")
		var chosen: bool = main.run_setup.difficulty == LEVELS[k][0]
		if chosen:
			c.draw_rect(b.grow(-2.0), Ui.RED)
		ui.fit_text(c, tr(LEVELS[k][1]), bw - 4.0, Vector2(b.position.x, b.position.y + b.size.y / 2.0 + Ui.px * 3 / 8), Ui.CREAM if chosen else Ui.INK,
			HORIZONTAL_ALIGNMENT_CENTER, bw)


## The widths of the three difficulty buttons in a row `width` wide: each name's own width and an even share of the room left, so a long name keeps its size.
static func level_widths(width: float) -> Array:
	var room := width - (LEVELS.size() - 1) * 4.0
	var names: Array = LEVELS.map(func(l: Array) -> float: return Ui.width_at(TranslationServer.translate(l[1]), Ui.px))
	var spare := room
	for n in names:
		spare -= n
	if spare < 0.0:
		return LEVELS.map(func(_l: Array) -> float: return room / LEVELS.size())
	return names.map(func(n: float) -> float: return n + spare / LEVELS.size())


## Keys and pad move along the road from node to node; up goes into the panel at the chosen difficulty, down from there to the mode switches and back to the node.
func _links(ui: Ui, ids: Array) -> void:
	var node := "prov:" + selected
	var levels: Array = []
	var switches: Array = []
	if state_of(selected) in ["won", "open"]:
		for l in LEVELS:
			levels.append("%s:%s" % [l[0], selected])
		if Profile.record_of(selected).won:
			for m in MODES:
				switches.append("%s:%s" % [m[0], selected])
	var chosen: String = levels[maxi(0, Sim.DIFFICULTIES.find(main.run_setup.difficulty))] if not levels.is_empty() else ""
	for i in ids.size():
		var here: String = "prov:" + ids[i]
		var before: String = ("prov:" + ids[i - 1]) if i > 0 else here
		var after: String = ("prov:" + ids[i + 1]) if i < ids.size() - 1 else here
		ui.link(here, Vector2.LEFT, before)
		ui.link(here, Vector2.RIGHT, after)
		ui.link(here, Vector2.DOWN, after)
		ui.link(here, Vector2.UP, chosen if chosen != "" and ids[i] == selected else before)
	for k in levels.size():
		ui.link(levels[k], Vector2.LEFT, levels[maxi(k - 1, 0)])
		ui.link(levels[k], Vector2.RIGHT, levels[mini(k + 1, levels.size() - 1)])
		ui.link(levels[k], Vector2.UP, levels[k])
		ui.link(levels[k], Vector2.DOWN, switches[0] if not switches.is_empty() else node)
	for k in switches.size():
		ui.link(switches[k], Vector2.UP, chosen)
		ui.link(switches[k], Vector2.DOWN, node)
		ui.link(switches[k], Vector2.LEFT, switches[maxi(k - 1, 0)])
		ui.link(switches[k], Vector2.RIGHT, switches[mini(k + 1, switches.size() - 1)])
