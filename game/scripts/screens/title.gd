class_name TitleScreen
extends RefCounted
## The title: the logo, the controls, and the buttons that continue the game, start a new one, load one or open the settings,
## over the province's field drifting slowly by while the legion marches across it.

const LOGO := preload("res://assets/logo.png")
# The world view, for the part of a picture that can hide a man.
const WORLD_VIEW := preload("res://scripts/world_view.gd")
# The painted icon beside each control; the wall, the bridge and the pause are drawn as the touch buttons draw them.
const ICONS := {"march": "march", "testudo": "testudo", "build": "stakes", "pray": "laurel", "fight": "gladius"}
# How fast the camera drifts over the field and the column marches, in pixels a second.
const DRIFT := 6.0
const PACE := 16.0
const COLUMN_GAP := 16.0
# Props drawn flat on the ground, which the column walks over.
const GROUND := ["dune", "bog", "heather", "dry_grass", "hut_ruin"]
# How far apart the camera's trial starts lie across and down from the commander, how many each way, how many of the column's passes each is tried on,
# and how many passes are weighed before only the first pass is tried, so the title opens without a pause.
const START_STEP := Vector2(300.0, 40.0)
const START_SHIFTS := Vector2i(2, 15)
const START_PASSES := 2
const START_TRIES := 80
# A far-off bird's pixels with its wings raised and lowered.
const BIRD_UP := [Vector2(-4, -3), Vector2(-3, -2), Vector2(-2, -1), Vector2(-1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 0), Vector2(2, -1), Vector2(3, -2), Vector2(4, -3)]
const BIRD_DOWN := [Vector2(-4, 1), Vector2(-3, 0), Vector2(-2, -1), Vector2(-1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 0), Vector2(2, -1), Vector2(3, 0), Vector2(4, 1)]
# What the box for Google Play's reviewer code says to a wrong code; the box is in English, since only the reviewers see it.
const WRONG := "That code isn't right."

var main: Node
## Whether the box for Google Play's reviewer code is open, what has been typed into it, and whether the last code was wrong.
var reviewing := false
var code := ""
var wrong := false
# The field the drift began on, the seconds shown of it, the clock when last drawn, where the camera looks and how far the column has gone.
var _field: Sim
var _t := 0.0
var _last := 0.0
var _eye := Vector2.ZERO
var _gone := 0.0
# The pass the column is on and how far above the foot of the screen it marches on that pass.
var _pass := -1
var _lift := 16.0
# Where the buttons end, which the column keeps below.
var _buttons_end := Ui.H


func _init(owner_node: Node) -> void:
	main = owner_node


func activate(id: String) -> void:
	match id:
		"continue":
			main.go_to_camp()
		"new":
			# A game is never written over, so with every slot taken one has to be deleted first.
			if Profile.new_game() > 0:
				main.use_profile()
				main.go_to_camp()
		"load":
			main.open_saves()
		"settings":
			main.open_settings("title")
		"wishlist":
			Steamworks.open_store()
		"unlock":
			FullGame.buy()
		"review_field":
			Ui.keyboard(true, code)
		"review_ok":
			enter_code()
		"review_cancel":
			close_review()


## A tap at `at` on the logo, where five quick ones open the box for Google Play's reviewer code while the full game is locked; true when it opens.
func knock(at: Vector2, now: float) -> bool:
	if reviewing or not logo_rect().has_point(at) or not FullGame.review_tap(now):
		return false
	reviewing = true
	code = ""
	wrong = false
	main.ui.focus = "review_ok"
	Ui.keyboard(true, code)
	return true


## Takes every key pressed while the box is open, so letters go into the code and never move the menu; true when the event was used.
func capture(event: InputEvent) -> bool:
	if not reviewing or not event is InputEventKey or not event.pressed:
		return false
	match event.keycode:
		KEY_ESCAPE:
			if not event.echo:
				Audio.play("back")
				close_review()
		KEY_BACKSPACE:
			code = code.left(-1)
		KEY_ENTER, KEY_KP_ENTER:
			if not event.echo:
				enter_code()
		_:
			if event.unicode >= 32 and code.length() < 20:
				code += char(event.unicode)
	return true


func enter_code() -> void:
	if FullGame.redeem(code):
		close_review()
	else:
		wrong = true


func close_review() -> void:
	reviewing = false
	code = ""
	wrong = false
	Ui.keyboard(false)
	main.ui.focus = ""


## The title's buttons as [id, label, enabled]: Continue with a game open, New game, Load while any slot holds a game, the settings,
## and last the demo's wishlist on Steam or, on a phone that has not bought the full game, the unlock in its place.
static func buttons(balance: Dictionary) -> Array:
	var out: Array = []
	if Profile.slot > 0:
		out.append(["continue", TranslationServer.translate("Continue"), true])
	out.append(["new", TranslationServer.translate("New game"), Profile.free_slot() > 0])
	if range(1, Profile.SLOTS + 1).any(Profile.slot_taken):
		out.append(["load", TranslationServer.translate("Load"), true])
	out.append(["settings", TranslationServer.translate("Settings"), true])
	if FullGame.locked():
		out.append(["unlock", Ui.unlock_label(), true])
	elif Game.is_demo() and int(balance.demo.store_app_id) > 0 and not Touch.phone and not FullGame.sold_here():
		out.append(["wishlist", TranslationServer.translate("Wishlist on Steam"), true])
	return out


## The controls the title shows, in reading order, each {id, caps, label}: the keys or pad buttons from the player's bindings,
## the four marching keys as a cluster, and none on a phone, whose buttons show their pictures instead.
static func controls() -> Array:
	var cap := func(action: String) -> Array: return [] if Touch.phone else [Controls.shown(action)]
	var march: Array = []
	if not Touch.phone:
		march = [Controls.pad_name(JOY_BUTTON_LEFT_STICK)] if Controls.pad_in_use else ["up", "left", "down", "right"].map(Controls.key_of)
	return [
		{"id": "march", "caps": march, "label": TranslationServer.translate("Drag to march") if Touch.phone else TranslationServer.translate("Move")},
		{"id": "fight", "caps": [], "label": TranslationServer.translate("Soldiers fight on their own")},
		{"id": "testudo", "caps": cap.call("testudo"), "label": TranslationServer.translate("Testudo")},
		{"id": "build", "caps": cap.call("build"), "label": TranslationServer.translate("Palisade")},
		{"id": "wall", "caps": cap.call("wall"), "label": TranslationServer.translate("Wall")},
		{"id": "bridge", "caps": cap.call("bridge"), "label": TranslationServer.translate("Bridge")},
		{"id": "pray", "caps": cap.call("pray"), "label": TranslationServer.translate("Call the gods")},
		{"id": "pause", "caps": cap.call("pause"), "label": TranslationServer.translate("Pause")},
	]


static func logo_top() -> float:
	return 6.0 if Ui.scale > 1 else 26.0


static func logo_rect() -> Rect2:
	return Rect2(Vector2((Ui.W - LOGO.get_width()) / 2.0, logo_top()), LOGO.get_size())


## The box for Google Play's reviewer code, in the logo's place so it stays above a phone's keyboard: the box, its field, OK and Cancel.
static func review_rects() -> Dictionary:
	var bh := 24.0 if Ui.scale == 1 else 30.0
	var bw := 80.0 if Ui.scale == 1 else 120.0
	var w := minf(Ui.W - 40.0, 400.0 if Ui.scale == 1 else 560.0)
	var box := Rect2(roundf((Ui.W - w) / 2.0), logo_top(), w, 22.0 + Ui.leading() * 2.0 + bh)
	var row := box.end.y - 8.0 - bh
	var cancel := Rect2(box.end.x - 8.0 - bw, row, bw, bh)
	var ok := Rect2(cancel.position.x - 8.0 - bw, row, bw, bh)
	return {"box": box, "field": Rect2(box.position.x + 8.0, row, ok.position.x - box.position.x - 16.0, bh), "ok": ok, "cancel": cancel}


## The title's buttons under the box of controls: side by side with large text, else two to a row with the last one centred when it is alone.
static func button_rects(box: Rect2, n: int) -> Array:
	var rects: Array = []
	if Ui.scale > 1:
		var bw := minf(200.0, (Ui.W - 40.0 - (n - 1) * 10.0) / n)
		var x0 := (Ui.W - n * bw - (n - 1) * 10.0) / 2.0
		var y := box.end.y + 6.0
		for i in n:
			rects.append(Rect2(x0 + i * (bw + 10.0), y, bw, clampf(Ui.H - 2.0 - y, 22.0, 30.0)))
	else:
		for i in n:
			var alone: bool = i == n - 1 and i % 2 == 0
			var x := Ui.W / 2 - 85.0 if alone else Ui.W / 2 - 175.0 + (i % 2) * 180.0
			rects.append(Rect2(x, box.end.y + 10.0 + (i / 2) * 30.0, 170.0, 24.0))
	return rects


## The title's buttons when the last is a phone's unlock, whose price makes its label long: with normal text it takes a row of its own
## across both columns, and with large text each button in the row is as wide as its label needs, with the room left shared out.
static func unlock_rects(box: Rect2, labels: Array) -> Array:
	var n := labels.size()
	if Ui.scale == 1:
		var rects := button_rects(box, n - 1)
		rects.append(Rect2(Ui.W / 2 - 175.0, rects[-1].end.y + 6.0, 350.0, 24.0))
		return rects
	var room := Ui.W - 40.0 - (n - 1) * 10.0
	var needs: Array = labels.map(func(s: String) -> float: return Ui.width_at(s, Ui.px) + 14.0)
	var order: Array = range(n - 1)
	order.sort_custom(func(a: int, z: int) -> bool: return needs[a] > needs[z])
	# Labels step down to the smaller size until the row fits, the unlock first and then the widest, as each does when drawn.
	for k: int in [n - 1] + order:
		if _sum(needs) <= room:
			break
		needs[k] = Ui.width_at(labels[k], Ui.small_px()) + 14.0
	var total := _sum(needs)
	var widths: Array = needs.map(func(w: float) -> float: return floorf(w * room / total if total > room else w + (room - total) / n))
	var x := (Ui.W - _sum(widths) - (n - 1) * 10.0) / 2.0
	var y := box.end.y + 6.0
	var rects: Array = []
	for w: float in widths:
		rects.append(Rect2(roundf(x), y, w, clampf(Ui.H - 2.0 - y, 22.0, 30.0)))
		x += w + 10.0
	return rects


static func _sum(values: Array) -> float:
	return values.reduce(func(a: float, b: float) -> float: return a + b, 0.0)


## Where the controls go: the box under the logo, each control's cell with its caps, icon and label, and the goal under them.
## Normal text sets three columns and large text two, each as wide as its widest control, spread out when the goal needs more room
## and squeezed to the screen when they need more; the first row is tall enough for the marching keys and a label on two lines.
static func grid(balance: Dictionary) -> Dictionary:
	var k := float(Ui.scale)
	var cols := 2 if Ui.scale > 1 else 3
	var pad := 3.0 + 2.0 * k
	var gap := 2.0 * k
	var space := 3.0 * k
	var col_gap := 12.0 * k
	var ch := float(Ui.px) + 3.0 * k + 1.0
	var side := 16.0 if Ui.scale == 1 else 24.0
	# The drawn wall is a little wider than an icon.
	var slot := maxf(side, 14.0 * k + 4.0)
	var r := 7.0 * k
	var lead := Ui.lead_for(Ui.px)
	var list := controls()
	var groups: Array = []
	for e in list:
		groups.append(_group(e.caps, ch, k) if not Touch.phone else {"caps": [], "size": Vector2(r * 2.0 + 2.0, r * 2.0 + 2.0)})
	var rows := ceili(list.size() / float(cols))
	var row_h: Array = []
	for row in rows:
		var h := maxf(ch * 2.0 + k, lead * 2.0) if row == 0 else (side if not Touch.phone else r * 2.0 + 2.0)
		for i in range(row * cols, mini(list.size(), (row + 1) * cols)):
			h = maxf(h, groups[i].size.y)
		row_h.append(h)
	var key_w: Array = []
	var col_w: Array = []
	for col in cols:
		var keys := 0.0
		var words := 0.0
		for i in range(col, list.size(), cols):
			keys = maxf(keys, groups[i].size.x)
			words = maxf(words, _two_line_width(list[i].label) if i < cols else Ui.width_at(list[i].label, Ui.px))
		key_w.append(keys)
		col_w.append(keys + space + (0.0 if Touch.phone else slot + space) + ceilf(words) + 1.0)
	var room := Ui.W - 40.0
	var goal := Game.goal_text(balance)
	var natural: float = col_w.reduce(func(a: float, b: float) -> float: return a + b, 0.0) + col_gap * (cols - 1) + pad * 2.0
	var width := minf(maxf(natural, Ui.width_at(goal, Ui.px) + pad * 2.0 + 16.0), room)
	for col in cols:
		col_w[col] = floorf(col_w[col] + (width - natural) / cols) if natural <= room else floorf((room - pad * 2.0 - col_gap * (cols - 1)) / cols)
	var box := Rect2(roundf((Ui.W - width) / 2.0), logo_top() + LOGO.get_height() + 3.0, width, 0.0)
	var cells: Array = []
	var y := box.position.y + pad
	for row in rows:
		var x := box.position.x + pad
		for col in cols:
			var i: int = row * cols + col
			if i >= list.size():
				break
			var e: Dictionary = list[i]
			var rect := Rect2(x, y, col_w[col], row_h[row])
			x += col_w[col] + col_gap
			var mid := roundf(rect.get_center().y)
			var cell := {"id": e.id, "label": e.label, "rect": rect, "lines": maxi(1, floori(rect.size.y / lead)), "caps": []}
			var key_end: float = rect.position.x + key_w[col]
			var g: Dictionary = groups[i]
			var at := Vector2(key_end - g.size.x, roundf(mid - g.size.y / 2.0))
			for cap in g.caps:
				cell.caps.append([Rect2(cap[0].position + at, cap[0].size), cap[1]])
			var label_x := key_end + space
			if Touch.phone:
				cell.disc = [Vector2(rect.position.x + r + 1.0, mid), r]
			else:
				cell.icon = Rect2(key_end + space + (slot - side) / 2.0, mid - side / 2.0, side, side)
				label_x = key_end + space + slot + space
			cell.label_x = label_x
			# A label on two lines is broken where its lines come out even, not wherever the first one fills.
			cell.room = rect.end.x - label_x if cell.lines < 2 else minf(rect.end.x - label_x, _two_line_width(e.label))
			cells.append(cell)
		y += row_h[row] + gap
	var size := Ui.px
	for cell in cells:
		size = mini(size, Ui.block(cell.label, cell.room, cell.lines).size)
	var goal_width := box.size.x - pad * 2.0
	var goal_size: int = Ui.block(goal, goal_width, 2).size
	var goal_lines := even_lines(goal, goal_width, goal_size)
	box.size.y = y - box.position.y + 1.0 + gap + goal_lines.size() * Ui.lead_for(goal_size) + pad - 2.0
	return {"box": box, "cells": cells, "size": size, "rule_y": y, "goal": goal_lines, "goal_size": goal_size, "goal_y": y + 1.0 + gap, "goal_width": goal_width}


## A text wrapped to `width`, and when it takes two lines, broken where the two come out about even rather than leaving a word alone below.
static func even_lines(s: String, width: float, size: int) -> Array:
	var lines := Ui.lines_of(s, width, size)
	if lines.size() != 2:
		return lines
	var low := width / 2.0
	var high := width
	while high - low > 1.0:
		var mid := (low + high) / 2.0
		if Ui.lines_of(s, mid, size).size() <= 2:
			high = mid
		else:
			low = mid
	return Ui.lines_of(s, high, size)


## The narrowest a label of three words or more (six letters in Chinese and Japanese) can be set on two lines; a shorter one stays on one.
static func _two_line_width(s: String) -> float:
	var han := Lang.is_han() and not s.is_valid_ascii_identifier()
	var parts: Array = Array(s.split("")) if han else Array(s.split(" "))
	var sep := "" if han else " "
	var best := Ui.width_at(s, Ui.px)
	if parts.size() < (6 if han else 3):
		return best + 2.0
	for i in range(1, parts.size()):
		if han and not Ui.can_break(parts[i - 1], parts[i]):
			continue
		best = minf(best, maxf(Ui.width_at(sep.join(parts.slice(0, i)), Ui.px), Ui.width_at(sep.join(parts.slice(i)), Ui.px)))
	return best + 2.0


## A control's keys laid out from the top left: the four marching keys as an upturned T, else one cap.
static func _group(caps: Array, ch: float, k: float) -> Dictionary:
	var widths := caps.map(func(s: String) -> float: return maxf(ch, roundf(Ui.width_at(s, Ui.px)) + 6.0 * k))
	var out: Array = []
	if caps.size() == 4:
		var x := 0.0
		for i in [1, 2, 3]:
			out.append([Rect2(x, ch + k, widths[i], ch), caps[i]])
			x += widths[i] + k
		var under: Rect2 = out[1][0]
		out.push_front([Rect2(roundf(under.get_center().x - widths[0] / 2.0), 0.0, widths[0], ch), caps[0]])
	elif caps.size() == 1:
		out.append([Rect2(0.0, 0.0, widths[0], ch), caps[0]])
	if out.is_empty():
		return {"caps": out, "size": Vector2.ZERO}
	var bounds: Rect2 = out[0][0]
	for cap in out:
		bounds = bounds.merge(cap[0])
	for cap in out:
		cap[0].position -= bounds.position
	return {"caps": out, "size": bounds.size}


func draw(c: CanvasItem, ui: Ui) -> void:
	var big := Ui.scale > 1
	var g := grid(main.balance)
	var box: Rect2 = g.box
	var ids := buttons(main.balance)
	var labels: Array = ids.map(func(b: Array) -> String: return str(b[1]).to_upper())
	var rects := unlock_rects(box, labels) if ids[-1][0] == "unlock" else button_rects(box, ids.size())
	_buttons_end = rects[-1].end.y
	var t := _animate()
	_clouds(c, t)
	_birds(c, t)
	if reviewing:
		_draw_review(c, ui)
		return
	var logo_pos := logo_rect().position
	c.draw_texture(LOGO, logo_pos)
	# A phone selling the full game shows its limits without calling itself a demo, which App Review refuses.
	if Game.is_demo() and not FullGame.sold_here():
		var tag := Rect2(logo_pos.x + LOGO.get_width() - 56.0, logo_pos.y + LOGO.get_height() - 8.0, 56.0, 8.0 + 8.0 * Ui.scale)
		ui.panel(c, tag)
		ui.text(c, tr("Demo").to_upper(), Vector2(tag.position.x, Ui.label_y(tag, tr("Demo").to_upper())), Ui.RED, HORIZONTAL_ALIGNMENT_CENTER, tag.size.x)
	_draw_controls(c, ui, g)
	for i in ids.size():
		ui.button(c, rects[i], ids[i][0], labels[i], "", ids[i][2], null, true)
	if ui.focus == "new" and not ui.is_enabled("new"):
		_full_note(c, ui, rects[ids.map(func(b: Array) -> String: return b[0]).find("new")])


func _draw_review(c: CanvasItem, ui: Ui) -> void:
	var r := review_rects()
	var box: Rect2 = r.box
	ui.panel(c, box)
	var y := box.position.y + 6.0 + Ui.px
	ui.text(c, "REVIEWER CODE", Vector2(box.position.x, y), Ui.BROWN, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	if wrong:
		ui.text(c, WRONG, Vector2(box.position.x, y + Ui.leading()), Ui.RED, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	ui.register(r.field, "review_field")
	ui.field(c, r.field, code.to_upper(), "XXXX-XXXX-XXXX")
	ui.button(c, r.ok, "review_ok", "OK", "", true, null, true)
	ui.button(c, r.cancel, "review_cancel", "CANCEL", "", true, null, true)


## The box of controls: each one's keys, icon and label, a rule, and the goal of the run under them.
func _draw_controls(c: CanvasItem, ui: Ui, g: Dictionary) -> void:
	var box: Rect2 = g.box
	ui.panel(c, box)
	var size: int = g.size
	var lead := Ui.lead_for(size)
	for cell in g.cells:
		for cap in cell.caps:
			_keycap(c, ui, cap[0], cap[1])
		if cell.has("disc"):
			_touch_button(c, ui, cell.id, cell.disc[0], cell.disc[1])
		else:
			_icon(c, ui, cell.id, cell.icon)
		var lines := Ui.lines_of(cell.label, cell.room, size)
		if lines.size() > cell.lines:
			lines = lines.slice(0, cell.lines - 1) + [Ui.clip(" ".join(lines.slice(cell.lines - 1)), cell.room, size)]
		var mid: float = cell.rect.get_center().y
		for i in lines.size():
			var y := roundf(mid - (lines.size() - 1) * lead / 2.0 + i * lead + size * 3 / 8.0)
			ui.text(c, lines[i], Vector2(cell.label_x, y), Ui.INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, false, size)
	var rule_y: float = g.rule_y
	c.draw_rect(Rect2(box.position.x + 8.0, rule_y, box.size.x - 16.0, 1.0), Ui.PARCH_DARK)
	var goal_size: int = g.goal_size
	for i in g.goal.size():
		var y: float = g.goal_y + goal_size + i * Ui.lead_for(goal_size) - 1.0
		ui.text(c, g.goal[i], Vector2(box.position.x, y), Ui.BROWN, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, false, goal_size)


## A key drawn as a small raised cap: its name on a pale face over a darker lip, in an ink outline.
func _keycap(c: CanvasItem, ui: Ui, r: Rect2, name: String) -> void:
	var lip := float(Ui.scale) + 1.0
	c.draw_rect(r.grow(1.0), Ui.INK)
	c.draw_rect(r, Ui.BROWN)
	var face := Rect2(r.position, Vector2(r.size.x, r.size.y - lip))
	c.draw_rect(face, Ui.CREAM)
	c.draw_rect(Rect2(face.position.x, face.end.y - 1.0, face.size.x, 1.0), Ui.PARCH_DARK)
	ui.text(c, name, Vector2(r.position.x, Ui.label_y(face, name)), Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, false, Ui.px)


func _icon(c: CanvasItem, ui: Ui, id: String, r: Rect2) -> void:
	if ICONS.has(id):
		c.draw_texture_rect(ui.icon(ICONS[id]), r, false)
	else:
		TouchPad.picture(c, id, r.get_center(), 10.0 * Ui.scale, true)


## A control as a phone shows it: the stick for the march, the gladius alone for the fighting, and the round buttons of a run.
func _touch_button(c: CanvasItem, ui: Ui, id: String, at: Vector2, r: float) -> void:
	match id:
		"march":
			c.draw_circle(at, r, Color(0.08, 0.05, 0.04, 0.3))
			c.draw_arc(at, r, 0.0, TAU, 32, Ui.BROWN, 1.0)
			c.draw_circle(at + Vector2(r * 0.3, -r * 0.2), r * 0.42 + 1.0, Ui.INK)
			c.draw_circle(at + Vector2(r * 0.3, -r * 0.2), r * 0.42, Ui.CREAM)
		"fight":
			c.draw_texture_rect(ui.icon(ICONS[id]), Rect2((at - Vector2(r, r)).round(), Vector2(r, r) * 2.0), false)
		"testudo", "pray":
			TouchPad.disc(c, at, r, true, false)
			var s := roundf(r * (1.3 if id == "testudo" else 1.45))
			c.draw_texture_rect(ui.icon(ICONS[id]), Rect2((at - Vector2(s, s) / 2.0).round(), Vector2(s, s)), false)
		_:
			TouchPad.disc(c, at, r, true, false)
			TouchPad.picture(c, id, at, r, true)


## Moves the field behind the title on: the camera drifts across the province unless the player has turned screen shake off,
## the grass sways, and the legion marches in a column along the foot of the screen. Returns the seconds shown so far.
func _animate() -> float:
	var world: Node = main.world
	var sim: Sim = world.sim
	if sim == null:
		return 0.0
	var drift := DRIFT if bool(Profile.setting("shake")) else 0.0
	if sim != _field:
		_field = sim
		_t = 0.0
		_last = main.clock
		_eye = start_eye(sim.terrain, world.atlas, sim.commander.pos, 1 + sim.soldiers.size(), drift, _buttons_end)
		_gone = Ui.view.x / 2.0 + 40.0
		_pass = -1
	# Time spent in the settings does not count, so the field does not leap on the way back.
	var dt := minf(main.clock - _last, 0.1)
	_last = main.clock
	_t += dt
	sim.time = _t
	_eye.x += drift * dt
	_gone += (PACE + drift) * dt
	world.eye_sim = sim
	world.eye_at = _eye
	_march(sim, _eye, _t, drift)
	return _t


## The legion in a column marching left under the buttons, coming round again once the last man has passed,
## each time along the line with the least of it behind trees and the fewest rocks in its way, and staying away while every line crosses a ravine.
func _march(sim: Sim, eye: Vector2, t: float, drift: float) -> void:
	var men: Array = [sim.commander] + sim.soldiers
	var span := Ui.view.x + 80.0 + men.size() * COLUMN_GAP
	var pass_n := floori(_gone / span)
	var head := eye.x + Ui.view.x / 2.0 + 40.0 - fposmod(_gone, span)
	var foot := eye.y + Ui.view.y / 2.0
	if pass_n != _pass:
		_pass = pass_n
		var route := _route(head, span, men.size(), drift)
		_lift = _open_line(sim.terrain, main.world.atlas, route.x, route.y, foot, _room(_buttons_end)).x
	for i in men.size():
		var u: Dictionary = men[i]
		u.pos = Vector2(head + i * COLUMN_GAP, foot - _lift if _lift >= 0.0 else foot + 200.0)
		u.facing = Vector2.LEFT
		u.moving = true
		u.anim = t * 8.0


## Where the camera starts: as near `at` as lets the column's first passes march with nothing tall in front of them.
static func start_eye(terrain: Terrain, atlas: Atlas, at: Vector2, men: int, drift: float, buttons_end: float) -> Vector2:
	var best := at
	var most := 0
	var tries := START_TRIES
	for i in START_SHIFTS.x * 2 + 1:
		for j in START_SHIFTS.y * 2 + 1:
			var eye := at + Vector2(_nth_shift(i) * START_STEP.x, _nth_shift(j) * START_STEP.y)
			var clear := _clear_passes(terrain, atlas, eye, men, drift, buttons_end, START_PASSES if tries > 0 else 1)
			tries -= clear + 1
			if clear == START_PASSES:
				return eye
			if clear > most:
				most = clear
				best = eye
			if tries <= 0 and most > 0:
				return best
	return best


## How many of the column's first `passes` passes, counted from the first, find a line with nothing tall in front when the camera starts at `eye`.
static func _clear_passes(terrain: Terrain, atlas: Atlas, eye: Vector2, men: int, drift: float, buttons_end: float, passes: int) -> int:
	var span := Ui.view.x + 80.0 + men * COLUMN_GAP
	for k in passes:
		# The first pass sets off with its head in the middle of the screen, and each later one from just past the right edge.
		var head := eye.x
		if k > 0:
			head += drift * (k * span - Ui.view.x / 2.0 - 40.0) / (PACE + drift) + Ui.view.x / 2.0 + 40.0
		var route := _route(head, span, men, drift)
		var line := _open_line(terrain, atlas, route.x, route.y, eye.y + Ui.view.y / 2.0, _room(buttons_end))
		if line.x < 0.0 or line.y > 0.0:
			return k
	return passes


## The steps of the `i`th trial start from the commander: 0, 1, -1, 2, -2 and so on.
static func _nth_shift(i: int) -> float:
	return ceili(i / 2.0) * (1.0 if i % 2 == 1 else -1.0)


## The stretch of field, as its left and right ends, that the column crosses on a pass setting off with its head at `head` while the camera drifts.
static func _route(head: float, span: float, men: int, drift: float) -> Vector2:
	return Vector2(head - PACE * span / (PACE + drift) - 20.0, head + men * COLUMN_GAP + 20.0)


## The highest above the foot of the screen the column may march and still keep below the buttons.
static func _room(buttons_end: float) -> float:
	return Ui.view.y - (buttons_end + Ui.offset.y) - 34.0


## The line between `from` and `to` with the least of it behind trees, rocks and houses in front, then the fewest props on it, then the lowest, as how far above `foot`
## it lies (at most `highest`, or -1 when every line crosses a ravine or a canal or there is no room under the buttons) and how much of it lies behind them.
static func _open_line(terrain: Terrain, atlas: Atlas, from: float, to: float, foot: float, highest: float) -> Vector2:
	var lifts := []
	var lift := 14.0
	while lift <= highest:
		if terrain.ravines_in(Rect2(from, foot - lift - 10.0, to - from, 44.0)).is_empty():
			lifts.append(lift)
		lift += 8.0
	if lifts.is_empty():
		return Vector2(-1.0, 0.0)
	# Each prop as its foot, whether it stands taller than a man, and the middle of its picture.
	var near := []
	var area := Rect2(from - 60.0, foot - highest - 10.0, to - from + 120.0, highest + 130.0)
	for pr in terrain.props_in(area):
		if pr[0] == "" or not area.has_point(pr[1]) or pr[0] in GROUND:
			continue
		var f: Array = atlas.prop_frame(pr[0])
		var tall: bool = pr[0] != "log" and f[0].size.y > 26.0
		near.append([pr[1], tall, WORLD_VIEW._solid_part(Rect2(pr[1] - f[1], f[0].size))])
	var best := Vector2(-1.0, 0.0)
	var fewest := 0
	for at: float in lifts:
		var band := Rect2(from, foot - at - 10.0, to - from, 44.0)
		var men := Rect2(from - 5.0, foot - at - 26.0, to - from + 10.0, 26.0)
		var hidden := 0.0
		var n := 0
		for p in near:
			if p[1] and p[0].y > foot - at and p[2].intersects(men):
				hidden += p[2].intersection(men).size.x
			elif band.has_point(p[0]):
				n += 1
		if best.x < 0.0 or hidden < best.y or hidden == best.y and n < fewest:
			best = Vector2(at, hidden)
			fewest = n
	return best


## Cloud shadows passing slowly over the field, each a few faint overlapping rounds so its middle is darkest.
func _clouds(c: CanvasItem, t: float) -> void:
	var area := Rect2(-Ui.offset, Ui.view)
	for n in 3:
		var w := 200.0 + 60.0 * n
		var x := area.position.x - w / 2.0 + fposmod(t * (3.0 + 1.5 * n) + n * 290.0, area.size.x + w)
		var y := area.position.y + area.size.y * float([0.12, 0.92, 0.6][n])
		for j in 6:
			var a := float(j) * 1.7 + n
			var p := Vector2(x + cos(a) * w * 0.26, y + sin(a * 1.3) * w * 0.1).round()
			c.draw_circle(p, roundf(w * (0.14 + 0.04 * (j % 3))), Color(0.04, 0.05, 0.1, 0.09))


## Now and then three birds fly up across the screen in a loose line, flapping, with their shadows on the ground below them.
func _birds(c: CanvasItem, t: float) -> void:
	var area := Rect2(-Ui.offset, Ui.view)
	var every := 24.0
	var flight := 14.0
	var pass_n := floori(t / every)
	var s := t - pass_n * every - 3.0
	if s < 0.0 or s > flight:
		return
	var y0 := area.position.y + area.size.y * (0.75 + 0.2 * fposmod(sin(pass_n * 12.9898 + 1.0) * 43758.5453, 1.0))
	var speed := (area.size.x + 100.0) / flight
	for b in 3:
		var p := Vector2(area.position.x - 50.0 + s * speed - b * 11.0, y0 + b * 6.0 - s * speed * 0.35).round()
		var up := (int(t * 7.0) + b) % 2 == 0
		_bird(c, p + Vector2(16, 30), up, Color(0, 0, 0, 0.22))
		_bird(c, p, up, Ui.CREAM)


func _bird(c: CanvasItem, p: Vector2, up: bool, col: Color) -> void:
	for dot in (BIRD_UP if up else BIRD_DOWN):
		c.draw_rect(Rect2(p + dot, Vector2.ONE), col)


## The note over a refused New game: every slot holds a game, and one has to be deleted first.
func _full_note(c: CanvasItem, ui: Ui, under: Rect2) -> void:
	var note := tr("You already keep three games. Delete one in Load to start another.")
	var w := minf(Ui.W - 40.0, 320.0 if Ui.scale == 1 else 480.0)
	var lines := Ui.lines_of(note, w - 12.0)
	var h := lines.size() * Ui.leading() + 8.0
	var box := Rect2(clampf(under.get_center().x - w / 2.0, 20.0, Ui.W - 20.0 - w), under.position.y - h - 4.0, w, h)
	ui.panel(c, box, Ui.CREAM)
	for i in lines.size():
		ui.text(c, lines[i], Vector2(box.position.x, box.position.y + 4.0 + Ui.px + i * Ui.leading()), Ui.RED, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
