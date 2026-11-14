extends Node2D
## Everything drawn over the field: the top bar, the testudo charge, the chieftain's health and the level-up choices.
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

var main: Node
var ui: Ui
var font: Font
var icons := {}
var choice_rects: Array = []


func _ready() -> void:
	font = load("res://assets/fonts/Silkscreen-Regular.ttf")


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
		draw_string(font, pos + Vector2(Ui.scale, Ui.scale), s, align, width, Ui.px, INK)
	draw_string(font, pos, s, align, width, Ui.px, col)


func wrap_text(s: String, pos: Vector2, width: float, col: Color) -> void:
	var words := s.split(" ")
	var line := ""
	var y := pos.y
	for w in words:
		var trial := w if line == "" else line + " " + w
		if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, Ui.px).x > width and line != "":
			text(line, Vector2(pos.x, y), col, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
			line = w
			y += Ui.leading()
		else:
			line = trial
	if line != "":
		text(line, Vector2(pos.x, y), col, HORIZONTAL_ALIGNMENT_LEFT, -1, false)


func panel(r: Rect2, fill: Color = PARCH) -> void:
	draw_rect(r.grow(1), INK)
	draw_rect(r, fill)
	draw_rect(Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 4)), PARCH_DARK, false, 1.0)


func _draw() -> void:
	if main == null:
		return
	var sim: Sim = main.sim
	if main.screens.has(main.state):
		if main.state == "pause" or main.state == "over":
			_top_bar(sim)
		ui.begin()
		main.screens[main.state].draw(self, ui)
		ui.end()
		return
	_top_bar(sim)
	if main.state == "choose":
		_choices(sim)


func _top_bar(sim: Sim) -> void:
	var big := Ui.scale > 1
	draw_rect(Rect2(8, 6, W - 16, 7), INK)
	var fill := (W - 18) * clampf(float(sim.xp) / sim.xp_next, 0.0, 1.0)
	draw_rect(Rect2(9, 7, fill, 5), GOLD)
	draw_rect(Rect2(9, 7, fill, 1), GOLD_LIGHT)
	var secs := int(sim.time)
	var y1 := 16.0 + 8.0 * Ui.scale
	var y2 := y1 + (11.0 if not big else 20.0)
	text("LEVEL %d" % sim.level, Vector2(10, y1))
	text("%02d:%02d" % [secs / 60, secs % 60], Vector2(0, y1), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W)
	text("LEGION %d" % (sim.soldiers.size() + 1), Vector2(0, y1), CREAM, HORIZONTAL_ALIGNMENT_RIGHT, W - 10)
	text("KILLS %d" % sim.kills, Vector2(0, y2), CREAM, HORIZONTAL_ALIGNMENT_RIGHT, W - 10)
	# The testudo charge sits bottom left, gold when it is ready.
	var ready := sim.testudo_charge >= 1.0 and sim.testudo_left <= 0.0
	var shield := icon_of("testudo")
	if shield != null:
		draw_texture(shield, Vector2(8, H - 42), Color.WHITE if ready or sim.testudo_left > 0.0 else Color(0.5, 0.5, 0.5))
	draw_rect(Rect2(8, H - 9, 34, 4), INK)
	var charge := 1.0 if sim.testudo_left > 0.0 else sim.testudo_charge
	draw_rect(Rect2(9, H - 8, 32 * charge, 2), GOLD if ready or sim.testudo_left > 0.0 else PARCH_DARK)
	text("TESTUDO" if sim.testudo_left <= 0.0 else "HOLD!", Vector2(46, H - 6), GOLD_LIGHT if ready or sim.testudo_left > 0.0 else Color(0.7, 0.66, 0.6))
	var ci := sim.horde.chieftain_index()
	var y3 := y1 + (11.0 if not big else 22.0)
	if ci >= 0:
		text("THE CHIEFTAIN", Vector2(0, y3), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)
		draw_rect(Rect2(W / 2 - 101, y3 + 4, 202, 6), INK)
		draw_rect(Rect2(W / 2 - 100, y3 + 5, 200 * clampf(sim.horde.e_hp[ci] / sim.horde.e_max[ci], 0, 1), 4), RED)
	elif sim.endless and sim.endless_since >= 0.0:
		var extra := int(sim.endless_seconds())
		text("ENDLESS  +%d:%02d" % [extra / 60, extra % 60], Vector2(0, y3), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)
	elif sim.time > float(sim.b.chieftain_at) - 30.0 and sim.horde.chieftain_id == -1:
		text("The chieftain is coming", Vector2(0, y3), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)


func _choices(sim: Sim) -> void:
	if main.choices.is_empty():
		return
	var big := Ui.scale > 1
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.5))
	var head_y := 38.0 if big else 74.0
	# With large text the top bar already says the level, so only the supplies heading is added.
	if not big or sim.pending_levels == 0:
		text("LEVEL %d" % sim.level if sim.pending_levels > 0 else "SUPPLIES", Vector2(0, head_y), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)
	if not big:
		text("Choose one", Vector2(0, 86), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W)
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
		var info: Dictionary = sim.content.upgrade(id)
		var icon := icon_of(id)
		if icon != null:
			draw_texture_rect(icon, Rect2(r.position.x + bw / 2 - icon_px / 2, r.position.y + 8, icon_px, icon_px), false)
		var y := r.position.y + (icon_px + 22.0 if big else 86.0)
		text(ui.clip(sim.content.group_of(id).to_upper(), bw - 8), Vector2(r.position.x, y), Color(0.5, 0.36, 0.22), HORIZONTAL_ALIGNMENT_CENTER, bw, false)
		text(ui.clip(info.name.to_upper(), bw - 8), Vector2(r.position.x, y + step + 1), INK, HORIZONTAL_ALIGNMENT_CENTER, bw, false)
		text(Upgrades.level_text(sim, id), Vector2(r.position.x, y + 2 * step + 2), RED, HORIZONTAL_ALIGNMENT_CENTER, bw, false)
		wrap_text(Upgrades.describe(sim, id), Vector2(r.position.x + 9, y + 3 * step + 6), bw - 18, INK)
	var hint_y := top + card_h + (22.0 if big else 16.0)
	text("A / D to choose     Space to take it" if not big else "Take one", Vector2(0, hint_y), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W)
	var extras: Array = []
	if sim.rerolls > 0:
		extras.append("R / Y  reroll (%d)" % sim.rerolls)
	if sim.banishes > 0:
		extras.append("B / X  banish (%d)" % sim.banishes)
	if not extras.is_empty():
		text("     ".join(extras), Vector2(0, hint_y + (20.0 if big else 13.0)), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)


func choice_at(p: Vector2) -> int:
	for i in choice_rects.size():
		if choice_rects[i].has_point(p):
			return i
	return -1
