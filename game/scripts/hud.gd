extends Node2D
## Everything drawn over the field: the top bar, the testudo charge, the chieftain's health, the level-up choices,
## pause, the title and the summary at the end.

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
var font: Font
var logo: Texture2D
var icons := {}
var choice_rects: Array = []


func _ready() -> void:
	font = load("res://assets/fonts/Silkscreen-Regular.ttf")
	logo = load("res://assets/logo.png")


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
		draw_string(font, pos + Vector2(1, 1), s, align, width, 8, INK)
	draw_string(font, pos, s, align, width, 8, col)


func wrap_text(s: String, pos: Vector2, width: float, col: Color) -> void:
	var words := s.split(" ")
	var line := ""
	var y := pos.y
	for w in words:
		var trial := w if line == "" else line + " " + w
		if font.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x > width and line != "":
			text(line, Vector2(pos.x, y), col, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
			line = w
			y += 10.0
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
	match main.state:
		"title":
			_title()
			return
		"over":
			_top_bar(sim)
			_summary(sim)
			return
	_top_bar(sim)
	if main.state == "choose":
		_choices(sim)
	elif main.state == "pause":
		draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.45))
		panel(Rect2(W / 2 - 90, H / 2 - 32, 180, 64))
		text("PAUSED", Vector2(0, H / 2 - 12), INK, HORIZONTAL_ALIGNMENT_CENTER, W, false)
		text("Esc  resume", Vector2(0, H / 2 + 4), INK, HORIZONTAL_ALIGNMENT_CENTER, W, false)
		text("Q  give up the run", Vector2(0, H / 2 + 16), INK, HORIZONTAL_ALIGNMENT_CENTER, W, false)


func _top_bar(sim: Sim) -> void:
	draw_rect(Rect2(8, 6, W - 16, 7), INK)
	var fill := (W - 18) * clampf(float(sim.xp) / sim.xp_next, 0.0, 1.0)
	draw_rect(Rect2(9, 7, fill, 5), GOLD)
	draw_rect(Rect2(9, 7, fill, 1), GOLD_LIGHT)
	var secs := int(sim.time)
	text("LEVEL %d" % sim.level, Vector2(10, 24))
	text("%02d:%02d" % [secs / 60, secs % 60], Vector2(0, 24), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W)
	text("LEGION %d" % (sim.soldiers.size() + 1), Vector2(0, 24), CREAM, HORIZONTAL_ALIGNMENT_RIGHT, W - 10)
	text("KILLS %d" % sim.kills, Vector2(0, 35), CREAM, HORIZONTAL_ALIGNMENT_RIGHT, W - 10)
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
	if ci >= 0:
		text("THE CHIEFTAIN", Vector2(0, 48), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)
		draw_rect(Rect2(W / 2 - 101, 52, 202, 6), INK)
		draw_rect(Rect2(W / 2 - 100, 53, 200 * clampf(sim.horde.e_hp[ci] / sim.horde.e_max[ci], 0, 1), 4), RED)
	elif sim.time > float(sim.b.chieftain_at) - 30.0 and sim.horde.chieftain_id == -1:
		text("The chieftain is coming", Vector2(0, 48), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)


func _choices(sim: Sim) -> void:
	if main.choices.is_empty():
		return
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.5))
	text("LEVEL %d" % sim.level if sim.pending_levels > 0 else "SUPPLIES", Vector2(0, 74), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)
	text("Choose one", Vector2(0, 86), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W)
	choice_rects.clear()
	var n: int = main.choices.size()
	var gap := 8.0 if n > 3 else 12.0
	var bw := minf(176.0, (W - 24.0 - (n - 1) * gap) / n)
	var x0 := (W - n * bw - (n - 1) * gap) / 2.0
	for i in n:
		var id: String = main.choices[i]
		var r := Rect2(x0 + i * (bw + gap), 100, bw, 170)
		choice_rects.append(r)
		var picked: bool = i == main.selected
		if picked:
			draw_rect(r.grow(3), GOLD)
		panel(r, CREAM if picked else PARCH)
		var info: Dictionary = sim.content.upgrade(id)
		var icon := icon_of(id)
		if icon != null:
			draw_texture_rect(icon, Rect2(r.position.x + bw / 2 - 32, r.position.y + 10, 64, 64), false)
		text(sim.content.group_of(id).to_upper(), Vector2(r.position.x, r.position.y + 86), Color(0.5, 0.36, 0.22), HORIZONTAL_ALIGNMENT_CENTER, bw, false)
		text(info.name.to_upper(), Vector2(r.position.x, r.position.y + 98), INK, HORIZONTAL_ALIGNMENT_CENTER, bw, false)
		text(Upgrades.level_text(sim, id), Vector2(r.position.x, r.position.y + 109), RED, HORIZONTAL_ALIGNMENT_CENTER, bw, false)
		wrap_text(Upgrades.describe(sim, id), Vector2(r.position.x + 9, r.position.y + 122), bw - 18, INK)
	text("A / D to choose     Space to take it", Vector2(0, 286), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W)
	var extras: Array = []
	if sim.rerolls > 0:
		extras.append("R / Y  reroll (%d)" % sim.rerolls)
	if sim.banishes > 0:
		extras.append("B / X  banish (%d)" % sim.banishes)
	if not extras.is_empty():
		text("     ".join(extras), Vector2(0, 299), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)


func _title() -> void:
	draw_texture(logo, Vector2(((W - logo.get_width()) / 2.0), 52))
	panel(Rect2(W / 2 - 130, 186, 260, 104))
	var lines := [
		"WASD or arrows  march",
		"Space  testudo: shields up, 80% less harm",
		"Esc  pause",
		"",
		"Your soldiers fight on their own.",
		"Survive 10 minutes and kill the chieftain.",
	]
	for i in lines.size():
		text(lines[i], Vector2(0, 202 + i * 11), INK, HORIZONTAL_ALIGNMENT_CENTER, W, false)
	if int(Time.get_ticks_msec() / 500) % 2 == 0:
		text("PRESS SPACE TO MARCH", Vector2(0, 314), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)


func _summary(sim: Sim) -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0, 0, 0, 0.5))
	panel(Rect2(W / 2 - 120, 90, 240, 170))
	var head := "VICTORY" if sim.victory else "THE COMMANDER HAS FALLEN"
	text(head, Vector2(0, 112), RED if not sim.victory else Color(0.45, 0.32, 0.1), HORIZONTAL_ALIGNMENT_CENTER, W, false)
	var secs := int(sim.time)
	var rows := [
		["Time", "%02d:%02d" % [secs / 60, secs % 60]],
		["Level", str(sim.level)],
		["Barbarians killed", str(sim.kills)],
		["Legion at the end", str(sim.soldiers.size() + 1)],
		["Denarii", str(sim.denarii)],
	]
	for i in rows.size():
		text(rows[i][0], Vector2(W / 2 - 100, 140 + i * 14), INK, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
		text(rows[i][1], Vector2(0, 140 + i * 14), INK, HORIZONTAL_ALIGNMENT_RIGHT, W / 2 + 100, false)
	text("Space  march again", Vector2(0, 228), INK, HORIZONTAL_ALIGNMENT_CENTER, W, false)
	text("Esc  title", Vector2(0, 242), INK, HORIZONTAL_ALIGNMENT_CENTER, W, false)


func choice_at(p: Vector2) -> int:
	for i in choice_rects.size():
		if choice_rects[i].has_point(p):
			return i
	return -1
