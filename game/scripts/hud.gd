class_name Hud
extends Node2D
## Everything drawn over the field: the top bar, the testudo charge, the favour of the gods, the chieftain's health and the level-up and god choices.
## The title, pause, summary, settings and camp are screens drawn through the shared Ui.

const W := 640.0
const H := 360.0
const INK := Color(0.16, 0.1, 0.08)
const CREAM := Color(1.0, 0.95, 0.82)
const PARCH := Color(0.96, 0.9, 0.76)
const PARCH_DARK := Color(0.82, 0.7, 0.52)
const GOLD := Color(0.91, 0.69, 0.25)
const GOLD_LIGHT := Color(1.0, 0.89, 0.59)
const RED := Color(0.72, 0.18, 0.14)
const BROWN_TEXT := Color(0.5, 0.36, 0.22)

const EDGE := 26.0
## How far above its foot an objective's name is written when it is on screen, clear of its sprite.
const LABEL_RISE := {"camp": 56.0, "column": 50.0, "grove": 40.0, "fort": 76.0}

var main: Node
var ui: Ui
var icons := {}
var choice_rects: Array = []


## The level-up icon of an id, loaded the first time it is drawn.
func icon_of(id: String) -> Texture2D:
	if not icons.has(id):
		var path := "res://assets/icons/%s.png" % main.sim.content.icon_key(id)
		icons[id] = load(path) if ResourceLoader.exists(path) else null
	return icons[id]


func _process(_dt: float) -> void:
	queue_redraw()


func text(s: String, pos: Vector2, col: Color = CREAM, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, shade := true) -> void:
	if shade:
		draw_string(Ui.font(), pos + Vector2(Ui.scale, Ui.scale), s, align, width, Ui.px, INK)
	draw_string(Ui.font(), pos, s, align, width, Ui.px, col)


func wrap_text(s: String, pos: Vector2, width: float, col: Color) -> void:
	var y := pos.y
	for line in Ui.lines_of(s, width):
		text(line, Vector2(pos.x, y), col, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
		y += Ui.leading()


func panel(r: Rect2, fill: Color = PARCH) -> void:
	draw_rect(r.grow(1), INK)
	draw_rect(r, fill)
	draw_rect(Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 4)), PARCH_DARK, false, 1.0)


func _draw() -> void:
	if main == null:
		return
	Ui.fit_view(get_viewport_rect().size)
	_scene()
	draw_set_transform(Vector2.ZERO)
	_card()


## An achievement card sliding in at the top right, a parchment panel with a laurel, over whatever is on screen.
func _card() -> void:
	var card: Dictionary = Steamworks.card
	if not Steamworks.card_visible(main.state):
		return
	var big := Ui.scale > 1
	var W := Ui.view.x
	var w := 190.0 if not big else 280.0
	var room := w - 40.0
	# A long name takes a second line, and the card grows to hold it.
	var name_lines := mini(Ui.block(str(card.name).to_upper(), room, 2).lines, 2)
	var h := 16.0 + (1.0 + name_lines) * Ui.leading() + (4.0 if big else 0.0)
	var slide := Steamworks.card_slide()
	var r := Rect2(lerpf(W + 2.0, W - 6.0 - w, slide), 44.0 if not big else 68.0, w, h)
	panel(r)
	_laurel(r.position + Vector2(18.0, h / 2.0))
	var tx := r.position.x + 34.0
	ui.fit_text(self, tr("Achievement").to_upper(), room, Vector2(tx, r.position.y + 6.0 + Ui.px * 3 / 4), BROWN_TEXT)
	ui.wrap_fit(self, str(card.name).to_upper(), Vector2(tx, r.position.y + 6.0 + Ui.px * 3 / 4 + Ui.leading()), room, INK, 2)


## A small wreath of gold leaves around a dot.
func _laurel(c: Vector2) -> void:
	for side in [-1.0, 1.0]:
		for i in 6:
			var a := deg_to_rad(120.0 + 20.0 * i)
			var p := c + Vector2(cos(a) * side, -sin(a)) * 8.0
			draw_rect(Rect2(floorf(p.x) - 1.0, floorf(p.y) - 1.0, 3, 3), GOLD if i % 2 == 0 else GOLD_LIGHT)
			draw_rect(Rect2(floorf(p.x) - 1.0, floorf(p.y) + 2.0, 3, 1), INK)
	draw_rect(Rect2(c.x - 2.0, c.y - 2.0, 4, 4), RED)


func _scene() -> void:
	var sim: Sim = main.sim
	if main.screens.has(main.state):
		if main.state == "pause" or main.state == "over":
			_top_bar(sim)
		ui.begin()
		draw_set_transform(Ui.offset)
		main.screens[main.state].draw(self, ui)
		ui.end()
		return
	_top_bar(sim)
	_objective_arrows(sim)
	_god_banner(sim)
	if main.state == "choose" or main.state == "pray":
		_choices(sim)


func _top_bar(sim: Sim) -> void:
	var W := Ui.view.x
	var H := Ui.view.y
	var big := Ui.scale > 1
	draw_rect(Rect2(8, 6, W - 16, 7), INK)
	var fill := (W - 18) * clampf(float(sim.xp) / sim.xp_next, 0.0, 1.0)
	draw_rect(Rect2(9, 7, fill, 5), GOLD)
	draw_rect(Rect2(9, 7, fill, 1), GOLD_LIGHT)
	var secs := int(sim.time)
	var y1 := 16.0 + 8.0 * Ui.scale
	var y2 := y1 + (11.0 if not big else 20.0)
	text((tr("Level %d") % sim.level).to_upper(), Vector2(10, y1))
	text("%02d:%02d" % [secs / 60, secs % 60], Vector2(0, y1), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W)
	text((tr("Legion %d") % (sim.soldiers.size() + 1)).to_upper(), Vector2(0, y1), CREAM, HORIZONTAL_ALIGNMENT_RIGHT, W - 10)
	text((tr("Kills %d") % sim.kills).to_upper(), Vector2(0, y2), CREAM, HORIZONTAL_ALIGNMENT_RIGHT, W - 10)
	# The testudo charge sits bottom left, gold when it is ready.
	var ready := sim.testudo_charge >= 1.0 and sim.testudo_left <= 0.0
	var shield := icon_of("testudo")
	if shield != null:
		draw_texture(shield, Vector2(8, H - 42), Color.WHITE if ready or sim.testudo_left > 0.0 else Color(0.5, 0.5, 0.5))
	draw_rect(Rect2(8, H - 9, 34, 4), INK)
	var charge := 1.0 if sim.testudo_left > 0.0 else sim.testudo_charge
	draw_rect(Rect2(9, H - 8, 32 * charge, 2), GOLD if ready or sim.testudo_left > 0.0 else PARCH_DARK)
	text((tr("Testudo") if sim.testudo_left <= 0.0 else tr("Hold!")).to_upper(), Vector2(46, H - 6), GOLD_LIGHT if ready or sim.testudo_left > 0.0 else Color(0.7, 0.66, 0.6))
	_timber(sim, H)
	_favour(sim, W, H)
	var ci := sim.horde.chieftain_index()
	var y3 := y1 + (11.0 if not big else 22.0)
	if ci >= 0:
		text(tr("The chieftain").to_upper(), Vector2(0, y3), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)
		draw_rect(Rect2(W / 2 - 101, y3 + 4, 202, 6), INK)
		draw_rect(Rect2(W / 2 - 100, y3 + 5, 200 * clampf(sim.horde.e_hp[ci] / sim.horde.e_max[ci], 0, 1), 4), RED)
	elif sim.endless and sim.endless_since >= 0.0:
		var extra := int(sim.endless_seconds())
		text((tr("Endless  +%d:%02d") % [extra / 60, extra % 60]).to_upper(), Vector2(0, y3), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)
	elif sim.time > float(sim.b.chieftain_at) - 30.0 and sim.horde.chieftain_id == -1:
		text(tr("The chieftain is coming"), Vector2(0, y3), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)


## The logs of timber the legion carries, above the testudo's name, gold once there are enough for a palisade, and the notice when there are not.
func _timber(sim: Sim, H: float) -> void:
	var atlas: Atlas = main.world.atlas
	var cost := int(sim.b.palisade.cost)
	var enough := sim.timber >= cost
	var y := H - 8.0 - Ui.leading() - 4.0
	if atlas != null and atlas.props.has("timber"):
		var f := atlas.prop_frame("timber")
		var r: Rect2 = f[0]
		draw_texture_rect_region(atlas.texture, Rect2(Vector2(46, y - r.size.y + 2.0), r.size), r, Color.WHITE if enough else Color(0.75, 0.72, 0.68))
	text(str(sim.timber), Vector2(66, y), GOLD_LIGHT if enough else CREAM)
	if sim.palisade_refused_at >= 0.0 and sim.time - sim.palisade_refused_at < float(sim.b.palisade.notice_seconds):
		var line := (tr("Not enough timber: %d needed") % cost).to_upper()
		text(line, Vector2(0, Ui.view.y * 0.7), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, Ui.view.x)


## The favour of the gods at the bottom right: a wreath over a bar that fills with kills, glowing with the key to call them once full.
func _favour(sim: Sim, W: float, H: float) -> void:
	var gods := sim.gods
	var ready := gods.full(sim.b)
	var share := clampf(float(gods.favour) / maxf(1.0, gods.need(sim.b)), 0.0, 1.0)
	var c := Vector2(W - 25.0, H - 24.0)
	if ready:
		var pulse := 0.5 + 0.5 * sin(sim.time * 6.0)
		draw_circle(c, 14.0 + 3.0 * pulse, Color(1.0, 0.85, 0.4, 0.18 + 0.2 * pulse))
		draw_circle(c, 9.0, Color(1.0, 0.95, 0.7, 0.35 + 0.3 * pulse))
	_laurel(c)
	draw_rect(Rect2(W - 42, H - 9, 34, 4), INK)
	draw_rect(Rect2(W - 41, H - 8, 32 * share, 2), GOLD_LIGHT if ready else GOLD)
	text(tr("Favour").to_upper(), Vector2(0, H - 6), GOLD_LIGHT if ready else Color(0.7, 0.66, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, W - 46)
	if ready and main.state == "play":
		text(Controls.hint("pray").to_upper(), Vector2(0, H - 6 - Ui.leading()), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_RIGHT, W - 46)


## The name of the god just called, written large across the screen as his power lands.
func _god_banner(sim: Sim) -> void:
	var last: Dictionary = sim.gods.last
	if last.is_empty() or main.state != "play":
		return
	var age := sim.time - float(last.at)
	var secs := float(sim.b.gods.banner_seconds)
	if age > secs or not sim.content.gods.has(last.id):
		return
	var a := clampf(minf(age * 4.0, (secs - age) * 2.0), 0.0, 1.0)
	var size := Ui.px * 3
	var name := str(sim.content.gods[last.id].name).to_upper()
	var y := Ui.view.y * 0.24
	draw_string(Ui.font(), Vector2(3, y + 3), name, HORIZONTAL_ALIGNMENT_CENTER, Ui.view.x, size, Color(INK, a))
	draw_string(Ui.font(), Vector2(0, y), name, HORIZONTAL_ALIGNMENT_CENTER, Ui.view.x, size, Color(GOLD_LIGHT, a))


## The name of an objective or the fort, as the arrows and notices show it.
func objective_name(kind: String) -> String:
	match kind:
		"camp":
			return tr("Barbarian camp")
		"column":
			return tr("Stranded column")
		"grove":
			return tr("Sacred grove")
	return tr("Roman fort")


func _notice_text(kind: String) -> String:
	match kind:
		"camp":
			return tr("The eagle is ours again")
		"column":
			return tr("The column joins the legion")
		"grove":
			return tr("The sacred grove burns")
		"chieftain":
			return tr("The chieftain falls: now hold the fort")
		"roar":
			return tr("The chieftain roars in fury")
	return tr("A Roman fort is in sight: hold it")


## Arrows at the edge of the screen to each objective not yet done and to the fort, with name and distance, and a notice when one is done.
func _objective_arrows(sim: Sim) -> void:
	var view := Ui.view
	var big := Ui.scale > 1
	var top := 16.0 + 8.0 * Ui.scale + (22.0 if big else 11.0) + 14.0
	var metre := float(sim.b.objectives.metre_px)
	var placed: Array = []
	var labels: Array = []
	# The arrows go down first, so the labels written after them step round every arrow.
	for t in sim.objectives.targets():
		var off: Vector2 = t[1] - sim.commander.pos
		if Rect2(Vector2.ZERO, view).grow(-EDGE).has_point(view / 2.0 + off):
			labels.append([t[0], view / 2.0 + off - Vector2(0, LABEL_RISE.get(t[0], 50.0)), ""])
			continue
		var at := edge_point(view, off, top)
		var dir := off.normalized()
		# The arrow pulses gently so it catches the eye at the edge of a busy screen.
		var pulse := 1.0 + 0.12 * sin(sim.time * 5.0)
		var side := dir.orthogonal() * (10.0 + 3.0 * Ui.scale) * pulse
		var back := at - dir * (22.0 + 6.0 * Ui.scale) * pulse
		var tip := PackedVector2Array([at + dir * 3.0, back + side * 1.35 - dir * 3.0, back - side * 1.35 - dir * 3.0])
		draw_colored_polygon(tip, INK)
		draw_colored_polygon(PackedVector2Array([at, back + side, back - side]), RED if t[0] == "fort" else GOLD)
		draw_colored_polygon(PackedVector2Array([at - dir * 3.0, back + side * 0.45, back]), GOLD_LIGHT if t[0] != "fort" else Color(0.95, 0.45, 0.35))
		var box := Rect2(tip[0], Vector2.ZERO)
		for q in tip:
			box = box.expand(q)
		placed.append(box)
		labels.append([t[0], back - dir * 8.0, tr("%d m") % int(off.length() / metre), dir])
	var note: Dictionary = sim.objectives.notice
	if not note.is_empty() and sim.time - float(note.at) < float(sim.b.objectives.notice_seconds):
		var line := _notice_text(note.kind).to_upper()
		var nw := Ui.width_at(line, Ui.px)
		var r := _free_spot(Rect2((view.x - nw) / 2.0, view.y * 0.7 - Ui.px, nw, Ui.leading()), placed, view, top)
		text(line, Vector2(r.position.x, r.position.y + Ui.px), GOLD_LIGHT)
	for l in labels:
		var name := objective_name(l[0]).to_upper()
		var w := maxf(Ui.width_at(name, Ui.px), Ui.width_at(l[2], Ui.px))
		if l[2] == "":
			var r := _free_spot(Rect2(l[1].x - w / 2.0, l[1].y - Ui.px, w, Ui.leading()), placed, view, top)
			text(name, Vector2(r.position.x, r.position.y + Ui.px), GOLD_LIGHT)
			continue
		var h := Ui.leading() * 2.0
		var dir: Vector2 = l[3]
		var centre: Vector2 = l[1] - dir * (w / 2.0 * absf(dir.x) + h / 2.0 * absf(dir.y))
		var r := _free_spot(Rect2(centre - Vector2(w, h) / 2.0, Vector2(w, h)), placed, view, top)
		text(name, Vector2(r.position.x, r.position.y + Ui.px), GOLD_LIGHT if l[0] != "fort" else CREAM, HORIZONTAL_ALIGNMENT_CENTER, w)
		text(l[2], Vector2(r.position.x, r.position.y + Ui.px + Ui.leading()), CREAM, HORIZONTAL_ALIGNMENT_CENTER, w)


## Keeps a label on screen and moves it off any label already written, towards the middle of the screen.
static func _free_spot(r: Rect2, placed: Array, view: Vector2, top: float) -> Rect2:
	r.position.x = clampf(r.position.x, 4.0, view.x - r.size.x - 4.0)
	r.position.y = clampf(r.position.y, top, view.y - r.size.y - 4.0)
	var step := (r.size.y + 2.0) * (1.0 if r.get_center().y < view.y / 2.0 else -1.0)
	for i in placed.size() + 1:
		var clash := false
		for p in placed:
			clash = clash or p.intersects(r)
		if not clash:
			break
		r.position.y += step
	placed.append(r)
	return r


func _choices(sim: Sim) -> void:
	if main.choices.is_empty():
		return
	var big := Ui.scale > 1
	draw_set_transform(Ui.offset)
	Ui.veil(self, 0.5)
	var head_y := 38.0 if big else 74.0
	var praying: bool = main.state == "pray"
	if praying:
		text(tr("The gods hear you").to_upper(), Vector2(0, head_y), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)
	# With large text the top bar already says the level, so only the supplies heading is added.
	elif not big or sim.pending_levels == 0:
		text((tr("Level %d") % sim.level if sim.pending_levels > 0 else tr("Supplies")).to_upper(), Vector2(0, head_y), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)
	if not big:
		text(tr("Call one") if praying else tr("Choose one"), Vector2(0, 86), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W)
	choice_rects.clear()
	var n: int = main.choices.size()
	var gap := 8.0 if n > 3 else 12.0
	var bw := minf(176.0 if not big else 200.0, (W - 24.0 - (n - 1) * gap) / n)
	var x0 := (W - n * bw - (n - 1) * gap) / 2.0
	var top := 48.0 if big else 100.0
	var card_h := 250.0 if big else 170.0
	var icon_px := 40.0 if big else 64.0
	var step := 20.0 if big else 11.0
	for i in n:
		var id: String = main.choices[i]
		var r := Rect2(x0 + i * (bw + gap), top, bw, card_h)
		choice_rects.append(r)
		var picked: bool = i == main.selected
		if picked:
			draw_rect(r.grow(3), GOLD)
		panel(r, CREAM if picked else PARCH)
		var info: Dictionary = sim.content.gods[id] if praying else sim.content.upgrade(id)
		var icon := icon_of(id)
		if icon != null:
			draw_texture_rect(icon, Rect2(r.position.x + bw / 2 - icon_px / 2, r.position.y + 8, icon_px, icon_px), false)
		var y := r.position.y + (icon_px + 22.0 if big else 86.0)
		ui.fit_text(self, (tr("God") if praying else tr(sim.content.group_of(id))).to_upper(), bw - 8, Vector2(r.position.x, y), Color(0.5, 0.36, 0.22), HORIZONTAL_ALIGNMENT_CENTER, bw)
		# A long name takes two lines, and the level and description move down by the extra one.
		var shown := mini(Ui.block(info.name.to_upper(), bw - 8, 2).lines, 2)
		ui.wrap_fit(self, info.name.to_upper(), Vector2(r.position.x, y + step + 1), bw - 8, INK, 2, HORIZONTAL_ALIGNMENT_CENTER, bw)
		var extra_y := (shown - 1) * step
		if praying:
			wrap_text(info.text, Vector2(r.position.x + 9, y + 2 * step + 6 + extra_y), bw - 18, INK)
			continue
		text(Upgrades.level_text(sim, id), Vector2(r.position.x, y + 2 * step + 2 + extra_y), RED, HORIZONTAL_ALIGNMENT_CENTER, bw, false)
		wrap_text(Upgrades.describe(sim, id), Vector2(r.position.x + 9, y + 3 * step + 6 + extra_y), bw - 18, INK)
	var hint_y := top + card_h + (22.0 if big else 16.0)
	if praying:
		ui.fit_text(self, Controls.hint("gods") if not big else tr("Call one"), W - 16.0, Vector2(0, hint_y), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W, true)
		return
	ui.fit_text(self, Controls.hint("level") if not big else tr("Take one"), W - 16.0, Vector2(0, hint_y), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W, true)
	var extras: Array = []
	if sim.rerolls > 0:
		extras.append(Controls.hint("reroll", sim.rerolls))
	if sim.banishes > 0:
		extras.append(Controls.hint("banish", sim.banishes))
	if not extras.is_empty():
		ui.fit_text(self, "     ".join(extras), W - 16.0, Vector2(0, hint_y + (20.0 if big else 13.0)), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W, true)


func choice_at(p: Vector2) -> int:
	for i in choice_rects.size():
		if choice_rects[i].has_point(p):
			return i
	return -1


## Where the arrow to a target `off` from the screen centre stands, on the edge of the room below `top`, or INF when it is on screen.
static func edge_point(view: Vector2, off: Vector2, top: float) -> Vector2:
	var room := Rect2(EDGE, top, view.x - 2.0 * EDGE, view.y - top - EDGE)
	var centre := view / 2.0
	if room.has_point(centre + off):
		return Vector2.INF
	var t := INF
	if off.x > 0.0:
		t = (room.end.x - centre.x) / off.x
	elif off.x < 0.0:
		t = (room.position.x - centre.x) / off.x
	if off.y > 0.0:
		t = minf(t, (room.end.y - centre.y) / off.y)
	elif off.y < 0.0:
		t = minf(t, (room.position.y - centre.y) / off.y)
	return centre + off * t
