class_name MapScreen
extends RefCounted
## The map: the painted frontier with the legion's road from Rome through the provinces in the order they open, and a panel for the one selected.

## The difficulties, easiest first, with their names.
const LEVELS := [["easy", "Easy"], ["medium", "Medium"], ["hard", "Hard"]]
## The modes a province opens once it is won.
const MODES := [["endless", "Endless"], ["decimatio", "Decimatio"]]
## The painted map's projection, the same as tools/art/make_map.py: equirectangular from 11.5°W and 58.9°N, with longitude scaled by cos 42°.
const WEST := -11.5
const NORTH := 58.9
const PX_PER_DEG := 13.8
const LON_SCALE := 0.7431448
## Where each province lies, as longitude and latitude; Parthia sits north of Ctesiphon (33°N) and Aegyptus out at sea north of the Nile delta (31°N), to stay above the key hints at the map's foot.
const PLACES := {"roma": Vector2(12.5, 41.9), "germania": Vector2(9.0, 51.5), "britannia": Vector2(-1.0, 52.0), "gaul": Vector2(2.5, 47.0),
	"dacia": Vector2(24.5, 46.0), "parthia": Vector2(44.5, 35.2), "hispania": Vector2(-4.5, 40.2), "aegyptus": Vector2(30.5, 35.0)}
## The towns, passes and sea lanes each march goes by, as longitude and latitude, so the road keeps to the land except where it sails.
const ROUTES := {
	"roma>germania": [Vector2(11.0, 45.4), Vector2(11.5, 47.0), Vector2(10.9, 48.4), Vector2(8.3, 50.0)],
	"germania>gaul": [Vector2(6.95, 50.9), Vector2(6.6, 49.75), Vector2(4.0, 49.25)],
	"gaul>dacia": [Vector2(6.0, 47.2), Vector2(8.2, 47.5), Vector2(12.1, 48.9), Vector2(16.9, 48.1), Vector2(19.0, 47.5), Vector2(20.5, 44.8),
		Vector2(22.6, 44.6)],
	"dacia>parthia": [Vector2(24.5, 43.7), Vector2(29.0, 41.0), Vector2(32.9, 39.9), Vector2(34.6, 37.8), Vector2(36.2, 36.2), Vector2(37.9, 37.05),
		Vector2(40.4, 35.7), Vector2(42.6, 35.3)],
	"parthia>britannia": [Vector2(36.0, 36.1), Vector2(32.5, 34.3), Vector2(24.5, 34.4), Vector2(15.0, 36.0), Vector2(11.0, 38.3), Vector2(8.0, 38.6),
		Vector2(6.5, 40.6), Vector2(5.0, 43.2), Vector2(4.8, 45.8), Vector2(3.0, 48.5), Vector2(1.6, 50.7), Vector2(0.6, 51.2)],
	"britannia>hispania": [Vector2(-0.8, 50.8), Vector2(-3.0, 49.9), Vector2(-6.0, 48.3), Vector2(-7.4, 45.6), Vector2(-6.0, 43.9), Vector2(-5.8, 43.3),
		Vector2(-5.6, 41.6)],
	"hispania>aegyptus": [Vector2(-1.0, 37.6), Vector2(3.0, 37.4), Vector2(8.5, 37.6), Vector2(11.8, 37.4), Vector2(15.0, 36.3), Vector2(20.0, 35.2),
		Vector2(25.0, 34.6), Vector2(28.5, 34.7)],
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
		if parts[1] != setup.province:
			setup.province = parts[1]
			for m in MODES:
				setup[m[0]] = false
		Profile.data.settings.province = setup.province
		Profile.save()
	elif parts[0] in Sim.DIFFICULTIES:
		if parts[1] != setup.province:
			activate("prov:" + parts[1])
		setup.difficulty = parts[0]
		Profile.data.settings.difficulty = parts[0]
		Profile.save()
	elif Profile.record_of(parts[1]).won:
		if parts[1] != setup.province:
			activate("prov:" + parts[1])
		setup[parts[0]] = not setup[parts[0]]


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


## The panel with the selected province's records and modes, over the steppe at the top right.
static func panel_rect() -> Rect2:
	return Rect2(Ui.W - 254, 8, 246, 38.0 + 5.0 * Ui.leading()) if Ui.scale == 1 else Rect2(Ui.W - 260, 8, 252, 172)


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
	if ui.focus.begins_with("prov:") and ids.has(ui.focus.trim_prefix("prov:")):
		selected = ui.focus.trim_prefix("prov:")
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


## The road from Rome through every province: solid where the legion has marched, dashes beyond, moving towards the next to win.
func _road(c: CanvasItem, ids: Array, now: float) -> void:
	var from := "roma"
	var walked := true
	for i in ids.size():
		var pts := route(from, ids[i], 0.18 if i % 2 == 0 else -0.18)
		var won: bool = state_of(ids[i]) == "won"
		var next: bool = walked and not won
		if walked and won:
			c.draw_polyline(pts, Color(0.1, 0.05, 0.03), 6.0)
			c.draw_polyline(pts, ROAD, 3.0)
		else:
			_dashes(c, pts, Color(0.1, 0.05, 0.03), 5.0, now * 14.0 if next else 0.0)
			_dashes(c, pts, ROAD if next else Color(0.42, 0.3, 0.22), 3.0, now * 14.0 if next else 0.0)
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
	ui.register(hit, "prov:" + id, state == "won" or state == "open")
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
			Rect2(p.x + NODE_R + 8.0, p.y - h / 2.0, w, h), Rect2(p.x - NODE_R - 8.0 - w, p.y - h / 2.0, w, h)]
		# Of the sides clear of other plates and nodes, a plate takes the one that covers the least of the road.
		var at: Rect2 = tries[0]
		var least := INF
		for t in tries:
			t.position.x = clampf(t.position.x, 6.0, Ui.W - t.size.x - 6.0)
			t.position.y = clampf(t.position.y, 4.0, Ui.H - t.size.y - 20.0)
			var clash := false
			for q in placed:
				clash = clash or q.intersects(t.grow(2.0))
			if clash:
				continue
			var covered := 0
			var wide: Rect2 = t.grow(3.0)
			for m in marks:
				covered += 1 if wide.has_point(m) else 0
			if covered < least:
				least = covered
				at = t
		placed.append(at.grow(2.0))
		var state := state_of(id)
		c.draw_rect(at.grow(3.0), SHADE)
		var name_col := Ui.GOLD_LIGHT if state == "won" or state == "open" else Color(0.78, 0.74, 0.68)
		ui.text(c, name, Vector2(at.position.x, at.position.y + Ui.px), name_col, HORIZONTAL_ALIGNMENT_CENTER, at.size.x)
		if two:
			var col := Ui.CREAM if state == "open" else (Color(0.6, 0.85, 0.5) if state == "won" else Color(0.72, 0.66, 0.6))
			ui.fit_text(c, line, room, Vector2(at.position.x, at.position.y + Ui.px + Ui.leading()), col, HORIZONTAL_ALIGNMENT_CENTER, at.size.x)


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
	var size := Ui.fit_size(hint, Ui.W - 16.0)
	c.draw_rect(Rect2(0, Ui.H - Ui.lead_for(size) - 6.0, Ui.W, Ui.lead_for(size) + 6.0), SHADE)
	ui.text(c, hint, Vector2(0, Ui.H - 6), Ui.CREAM, HORIZONTAL_ALIGNMENT_CENTER, Ui.W, true, size)


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
	var tag := state_text(id).to_upper()
	ui.fit_text(c, tag, w, Vector2(x, y), Ui.RED if state == "open" else Ui.BROWN)
	y += Ui.leading() + 2.0
	if state == "fog" or state == "locked":
		return
	var rec := Profile.record_of(id)
	var results: Array = [tr("Best time %s") % clock(rec.best_time) if rec.best_time > 0.0 else tr("Not won yet")]
	results.append(tr("Hard won") if rec.hard_won else tr("Hard not won"))
	if rec.endless_best > 0.0:
		results.append(tr("Endless %s") % clock(rec.endless_best))
	for line in Ui.pack(results, "  ", w).slice(0, 1 if not big else 2):
		ui.fit_text(c, line, w, Vector2(x, y), Ui.INK)
		y += Ui.leading()
	var bh := 14.0 if not big else 22.0
	var mode_rows := 1 if not big else MODES.size()
	# Below the difficulty there is room for the mode switches or for the two lines that say how to open them.
	var below := maxf(mode_rows * bh + (mode_rows - 1) * 4.0, 2.0 * Ui.leading())
	var top := r.end.y - 6.0 - below - 4.0 - bh
	_levels(c, ui, id, Rect2(x, top, w, bh))
	top += bh + 4.0
	if not rec.won:
		ui.wrap_fit(c, tr("Win here to open Endless and Decimatio"), Vector2(x, top + Ui.px - 1.0), w, Ui.MUTED, 2)
		return
	var columns := MODES.size() if not big else 1
	var bw := (w - (columns - 1) * 4.0) / columns
	for k in MODES.size():
		var on: bool = setup[MODES[k][0]] and setup.province == id
		var at := Vector2(x + (k % columns) * (bw + 4.0), top + (k / columns) * (bh + 4.0))
		var b := Rect2(at, Vector2(bw, bh))
		ui.button(c, b, "%s:%s" % [MODES[k][0], id], "")
		var box := Rect2(b.position + Vector2(5.0, (bh - Ui.px) / 2.0), Vector2.ONE * Ui.px)
		c.draw_rect(box, Ui.INK, false, 1.0)
		if on:
			c.draw_rect(box.grow(-2.0), Ui.RED)
		var room := b.size.x - Ui.px - 14.0
		ui.fit_text(c, tr(MODES[k][1]), room, Vector2(box.end.x + 4.0, b.position.y + bh / 2.0 + Ui.px * 3 / 8), Ui.INK)


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
	var across := Ui.scale == 1
	for k in switches.size():
		if across:
			ui.link(switches[k], Vector2.UP, chosen)
			ui.link(switches[k], Vector2.DOWN, node)
			ui.link(switches[k], Vector2.LEFT, switches[maxi(k - 1, 0)])
			ui.link(switches[k], Vector2.RIGHT, switches[mini(k + 1, switches.size() - 1)])
		else:
			ui.link(switches[k], Vector2.UP, switches[k - 1] if k > 0 else chosen)
			ui.link(switches[k], Vector2.DOWN, switches[k + 1] if k < switches.size() - 1 else node)
			ui.link(switches[k], Vector2.LEFT, node)
			ui.link(switches[k], Vector2.RIGHT, switches[k])
