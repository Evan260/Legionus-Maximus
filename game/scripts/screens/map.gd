class_name MapScreen
extends RefCounted
## The map: a painted map of the frontier with the legion's road from Rome through every province in the order they open,
## each province a node showing whether it is won, open, locked or not drawn yet, and a panel with the chosen one's records and modes.

const MODES := [["hard", "Hard"], ["endless", "Endless"], ["decimatio", "Decimatio"]]
## Where each province lies on the painted map, in the picture's own pixels (256 by 144).
const PLACES := {"roma": Vector2(118, 98), "germania": Vector2(100, 22), "britannia": Vector2(34, 15), "gaul": Vector2(40, 47),
	"dacia": Vector2(203, 27), "parthia": Vector2(226, 84)}
const PICTURE := Vector2(256, 144)
const NODE_R := 9.0
const ROAD := Color(0.72, 0.12, 0.1)
const SHADE := Color(0.06, 0.04, 0.03, 0.72)

var main: Node
## The province the panel describes: the last node focused, kept while focus is on the panel's buttons.
var selected := ""
var _picture: Texture2D


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


## A point of the painted map in screen pixels.
static func spot(id: String) -> Vector2:
	var r := picture_rect()
	return (r.position + PLACES.get(id, PICTURE / 2.0) * r.size / PICTURE).round()


## The panel with the selected province's records and modes, in the sea at the bottom left.
static func panel_rect() -> Rect2:
	return Rect2(8, 222, 264, 110) if Ui.scale == 1 else Rect2(8, 160, 268, 172)


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
	var labels := _labels(c, ui, ids)
	_panel(c, ui, selected)
	_header(c, ui, labels)
	_links(ui, ids)


## The road from Rome through every province: solid where the legion has marched, dashes beyond, moving towards the next to win.
func _road(c: CanvasItem, ids: Array, now: float) -> void:
	var from := spot("roma")
	var walked := true
	for i in ids.size():
		var to := spot(ids[i])
		var pts := road_points(from, to, 0.18 if i % 2 == 0 else -0.18)
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
		from = to
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
			var pulse := 0.5 + 0.5 * sin(now * 4.0)
			c.draw_circle(p, NODE_R + 4.0 + 4.0 * pulse, Color(1.0, 0.85, 0.4, 0.45 - 0.3 * pulse))
			c.draw_circle(p, NODE_R + 2.0, Ui.INK)
			c.draw_circle(p, NODE_R, Ui.GOLD.lerp(Ui.GOLD_LIGHT, pulse))
			c.draw_circle(p, NODE_R - 3.0, Ui.RED)
		"locked":
			c.draw_circle(p, NODE_R + 2.0, Color(0.1, 0.07, 0.05, 0.85))
			c.draw_circle(p, NODE_R, Color(0.42, 0.38, 0.34))
			c.draw_circle(p, NODE_R - 3.0, Color(0.27, 0.24, 0.21))
	if main.run_setup.province == id and state != "fog":
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


## Each province's name and state on a dark plate by its node, clear of the other nodes, plates and the panel.
## With large text only the selected province's state is written; the panel says the rest.
func _labels(c: CanvasItem, ui: Ui, ids: Array) -> Array:
	var placed: Array = [panel_rect().grow(4.0), Rect2(spot("roma") - Vector2(12, 46), Vector2(24, 58))]
	for id in ids:
		var p := spot(id)
		placed.append(Rect2(p - Vector2.ONE * (NODE_R + 4.0), Vector2.ONE * (NODE_R + 4.0) * 2.0))
		if main.run_setup.province == id:
			placed.append(Rect2(p + Vector2(NODE_R, -46), Vector2(22, 46)))
	var plates: Array = []
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
		var at: Rect2 = tries[0]
		for t in tries:
			t.position.x = clampf(t.position.x, 6.0, Ui.W - t.size.x - 6.0)
			t.position.y = clampf(t.position.y, 4.0, Ui.H - t.size.y - 20.0)
			var clash := false
			for q in placed:
				clash = clash or q.intersects(t.grow(2.0))
			if not clash:
				at = t
				break
		placed.append(at.grow(2.0))
		plates.append(at)
		var state := state_of(id)
		c.draw_rect(at.grow(3.0), SHADE)
		var name_col := Ui.GOLD_LIGHT if state == "won" or state == "open" else Color(0.78, 0.74, 0.68)
		ui.text(c, name, Vector2(at.position.x, at.position.y + Ui.px), name_col, HORIZONTAL_ALIGNMENT_CENTER, at.size.x)
		if two:
			var col := Ui.CREAM if state == "open" else (Color(0.6, 0.85, 0.5) if state == "won" else Color(0.72, 0.66, 0.6))
			ui.fit_text(c, line, room, Vector2(at.position.x, at.position.y + Ui.px + Ui.leading()), col, HORIZONTAL_ALIGNMENT_CENTER, at.size.x)
	return plates


## The title and the key hints on dark strips, so they read over the painted map.
func _header(c: CanvasItem, ui: Ui, plates: Array) -> void:
	var title := tr("Map").to_upper()
	var tw := Ui.width_at(title, Ui.px)
	var r := Rect2(Ui.W - tw - 24.0, 6, tw + 16.0, Ui.leading() + 6.0)
	for p in plates:
		if p.grow(3.0).intersects(r):
			r.position.y = Ui.H - 2.0 * Ui.leading() - 30.0
	ui.panel(c, r)
	ui.text(c, title, Vector2(r.position.x + 8, r.position.y + 3 + Ui.px), Ui.BROWN)
	var hint := Controls.hint("pick")
	var size := Ui.fit_size(hint, Ui.W - 16.0)
	c.draw_rect(Rect2(0, Ui.H - Ui.lead_for(size) - 6.0, Ui.W, Ui.lead_for(size) + 6.0), SHADE)
	ui.text(c, hint, Vector2(0, Ui.H - 6), Ui.CREAM, HORIZONTAL_ALIGNMENT_CENTER, Ui.W, true, size)


## The parchment panel for one province: its name and state, description, records and the mode switches.
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
	# With large text the description is left out so the records and switches fit beside the map.
	if not big:
		y = ui.wrap_fit(c, info.text, Vector2(x, y), w, Ui.BROWN, 2) + 1.0
	if state == "fog" or state == "locked":
		return
	var rec := Profile.record_of(id)
	var results: Array = [tr("Best time %s") % clock(rec.best_time) if rec.best_time > 0.0 else tr("Not won yet")]
	results.append(tr("Hard won") if rec.hard_won else tr("Hard not won"))
	if rec.endless_best > 0.0:
		results.append(tr("Endless %s") % clock(rec.endless_best))
	for line in Ui.pack(results, "  " if big else "   ", w).slice(0, 2):
		ui.fit_text(c, line, w, Vector2(x, y), Ui.INK)
		y += Ui.leading()
	var bh := 14.0 if not big else 22.0
	var bottom := r.end.y - 6.0 - bh
	if not rec.won:
		ui.fit_text(c, tr("Win here to open these"), w, Vector2(x, bottom - 4.0), Ui.MUTED)
		return
	var columns := 3 if not big else 1
	var bw := (w - (columns - 1) * 4.0) / columns
	var rows := MODES.size() / columns
	for k in MODES.size():
		var on: bool = setup[MODES[k][0]] and setup.province == id
		var at := Vector2(x + (k % columns) * (bw + 4.0), bottom - (rows - 1 - k / columns) * (bh + 4.0))
		var b := Rect2(at, Vector2(bw, bh))
		ui.button(c, b, "%s:%s" % [MODES[k][0], id], "")
		var box := Rect2(b.position + Vector2(5.0, (bh - Ui.px) / 2.0), Vector2.ONE * Ui.px)
		c.draw_rect(box, Ui.INK, false, 1.0)
		if on:
			c.draw_rect(box.grow(-2.0), Ui.RED)
		var room := b.size.x - Ui.px - 14.0
		ui.fit_text(c, tr(MODES[k][1]), room, Vector2(box.end.x + 4.0, b.position.y + bh / 2.0 + Ui.px * 3 / 8), Ui.INK)


## Keys and pad move along the road from node to node; down goes into the panel's switches and back up to the node.
func _links(ui: Ui, ids: Array) -> void:
	var switches: Array = []
	if state_of(selected) in ["won", "open"] and Profile.record_of(selected).won:
		for m in MODES:
			switches.append("%s:%s" % [m[0], selected])
	for i in ids.size():
		var here: String = "prov:" + ids[i]
		if i > 0:
			ui.link(here, Vector2.LEFT, "prov:" + ids[i - 1])
			ui.link(here, Vector2.UP, "prov:" + ids[i - 1])
		if i < ids.size() - 1:
			ui.link(here, Vector2.RIGHT, "prov:" + ids[i + 1])
		ui.link(here, Vector2.DOWN, switches[0] if not switches.is_empty() and ids[i] == selected else (("prov:" + ids[i + 1]) if i < ids.size() - 1 else here))
	var across := Ui.scale == 1
	for k in switches.size():
		var back := Vector2.UP if across else Vector2.LEFT
		ui.link(switches[k], back, "prov:" + selected)
		var prev := Vector2.LEFT if across else Vector2.UP
		var next := Vector2.RIGHT if across else Vector2.DOWN
		ui.link(switches[k], prev, switches[k - 1] if k > 0 else "prov:" + selected)
		ui.link(switches[k], next, switches[k + 1] if k < switches.size() - 1 else switches[k])
