class_name TouchPad
extends Node2D
## The run's touch controls, drawn over the HUD: a floating stick under the left thumb and round buttons under the right.

const TESTUDO_ICON := preload("res://assets/icons/testudo.png")
const LAUREL_ICON := preload("res://assets/icons/laurel.png")
const FACE := Color(0.96, 0.9, 0.76, 0.92)
const FACE_DIM := Color(0.7, 0.62, 0.5, 0.8)
const FACE_HELD := Color(1.0, 0.95, 0.82, 1.0)
const TRACK := Color(0.32, 0.26, 0.2)
const WOOD := Color(0.62, 0.42, 0.24)

var main: Node
## Each button as {id: {centre, radius}}, laid out afresh every frame for the view and the text size.
var layout := {}
## The finger steering, or -1, with where the stick's centre and the finger are.
var _stick := -1
var _base := Vector2.ZERO
var _finger := Vector2.ZERO
## The button under each finger, by touch index.
var _held := {}
## Buttons pressed since the game last looked, which it takes once each.
var _pressed := {}


## The march the stick asks for, as a gamepad's left stick would.
func move() -> Vector2:
	return Touch.stick_vector(_finger - _base, radius()) if _stick >= 0 else Vector2.ZERO


func radius() -> float:
	return Touch.fingertip * Touch.STICK_RADIUS


## Whether the button was pressed since the last look, which uses the press up.
func take(id: String) -> bool:
	return _pressed.erase(id)


## The buttons' layout for the view this frame, below the experience strip and above the favour.
func lay_out() -> void:
	var view := get_viewport_rect().size
	var safe := view - Touch.inset_tl - Touch.inset_br
	var favour: Rect2 = Hud.bottom_layout(safe).favour
	layout = Touch.button_layout(view, Touch.inset_tl, Touch.inset_br, Touch.fingertip, Touch.inset_tl.y + favour.position.y, Touch.inset_tl.y + 14.0)


func _process(_dt: float) -> void:
	# Turning a phone over moves its camera to the other side without changing the window's size.
	if Engine.get_process_frames() % 60 == 0:
		Touch.fit(get_tree().root.size, Vector2i(get_viewport_rect().size))
	lay_out()
	# A finger still down when a choice opens steers nothing once the run goes on, until it touches again.
	if main == null or main.state != "play":
		_stick = -1
		_held.clear()
	_pressed.clear()
	queue_redraw()


func _input(event: InputEvent) -> void:
	if main == null or main.state != "play":
		return
	if event is InputEventScreenTouch:
		var p: Vector2 = event.position
		if event.pressed:
			var id := Touch.button_at(layout, p)
			if id != "":
				_held[event.index] = id
				_pressed[id] = true
			elif _stick < 0 and Touch.in_stick_zone(p, get_viewport_rect().size):
				_stick = event.index
				_base = p
				_finger = p
		else:
			_held.erase(event.index)
			if event.index == _stick:
				_stick = -1
	elif event is InputEventScreenDrag and event.index == _stick:
		_finger = event.position
		_base = Touch.stick_follow(_base, _finger, radius())


func _draw() -> void:
	if main == null or main.state != "play" or main.sim == null or layout.is_empty():
		return
	var sim: Sim = main.sim
	_draw_stick(sim)
	var held := _held.values()
	for id in layout:
		var c: Vector2 = layout[id].centre
		var r: float = layout[id].radius
		match id:
			"testudo":
				var up := sim.testudo_left > 0.0
				var ready := sim.testudo_charge >= 1.0 and not up
				if ready or up:
					_glow(c, r, sim.time)
				_disc(c, r, ready or up, held.has(id))
				_ring(c, r, 1.0 if up else sim.testudo_charge, ready or up)
				_icon(TESTUDO_ICON, c, r * 1.3, ready or up)
			"pray":
				var full: bool = sim.gods.full(sim.b)
				var share := clampf(float(sim.gods.favour) / maxf(1.0, sim.gods.need(sim.b)), 0.0, 1.0)
				if full:
					_glow(c, r, sim.time)
				_disc(c, r, full, held.has(id))
				_ring(c, r, share, full)
				_icon(LAUREL_ICON, c + Vector2(0, -1), r * 1.45, full)
			"build", "wall", "bridge":
				var cost := int(sim.b[{"build": "palisade", "wall": "wall", "bridge": "bridge"}[id]].cost)
				var enough := sim.timber >= cost
				_disc(c, r, enough, held.has(id))
				var size := Ui.px if r >= 16.0 else Ui.small_px()
				_picture(id, c + Vector2(0, -r * 0.2), r, enough)
				var label := str(cost)
				var w := Ui.width_at(label, size)
				draw_string(Ui.font(), Vector2(roundf(c.x - w / 2.0), roundf(c.y + r * 0.78)), label, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Ui.INK)
			"pause":
				_disc(c, r, true, held.has(id))
				var bar := Vector2(maxf(2.0, roundf(r * 0.22)), roundf(r * 0.8))
				for side in [-1.0, 1.0]:
					draw_rect(Rect2((c + Vector2(side * bar.x * 1.1 - bar.x / 2.0, -bar.y / 2.0)).round(), bar), Ui.INK)


## The stick while a thumb is on it, and a faint one where the left thumb rests at the start of a run, to show where to steer.
func _draw_stick(sim: Sim) -> void:
	var r := radius()
	var base := _base
	var knob := _finger
	if _stick < 0:
		if sim.time > 8.0:
			return
		base = Vector2(Touch.inset_tl.x + r * 1.5, get_viewport_rect().size.y - Touch.inset_br.y - r * 1.9)
		knob = base
	var a := 1.0 if _stick >= 0 else 0.7 + 0.3 * sin(sim.time * 3.0)
	draw_circle(base, r, Color(0.08, 0.05, 0.04, 0.3 * a))
	draw_arc(base, r, 0.0, TAU, 48, Color(Ui.CREAM, 0.6 * a), 2.0)
	var off := (knob - base).limit_length(r)
	draw_circle(base + off, r * 0.42 + 1.0, Color(Ui.INK, 0.5 * a))
	draw_circle(base + off, r * 0.42, Color(Ui.PARCH, 0.75 * a))


## A button's parchment face in an ink rim, faded while it cannot be used and brighter while a finger is on it.
func _disc(c: Vector2, r: float, lit: bool, pressed: bool) -> void:
	draw_circle(c + Vector2(1, 2), r + 1.0, Color(0, 0, 0, 0.35))
	draw_circle(c, r + 1.0, Ui.INK)
	draw_circle(c, r, FACE_HELD if pressed else (FACE if lit else FACE_DIM))
	draw_arc(c, r - 2.5, 0.0, TAU, 40, Ui.PARCH_DARK, 1.0)


## A charge filling clockwise round the rim from the top, over a dark track, gold once full.
func _ring(c: Vector2, r: float, share: float, full: bool) -> void:
	draw_arc(c, r - 1.5, 0.0, TAU, 40, TRACK, 3.0)
	if share > 0.0:
		draw_arc(c, r - 1.5, -PI / 2.0, -PI / 2.0 + TAU * clampf(share, 0.0, 1.0), 40, Ui.GOLD_LIGHT if full else Ui.GOLD, 3.0)


## A pulsing light round a button that is ready, so it catches the eye at the edge of a busy screen.
func _glow(c: Vector2, r: float, now: float) -> void:
	var pulse := 0.5 + 0.5 * sin(now * 6.0)
	draw_circle(c, r + 3.0 + 3.0 * pulse, Color(1.0, 0.85, 0.4, 0.2 + 0.2 * pulse))


func _icon(tex: Texture2D, c: Vector2, side: float, lit: bool) -> void:
	var s := Vector2.ONE * roundf(side)
	draw_texture_rect(tex, Rect2((c - s / 2.0).round(), s), false, Color.WHITE if lit else Color(0.6, 0.58, 0.55))


## A drawn sign for each timber work: a few pointed stakes for the palisade, a railed row of them for the wall, planks for the bridge.
func _picture(id: String, c: Vector2, r: float, lit: bool) -> void:
	var wood := WOOD if lit else WOOD.darkened(0.3)
	var k := maxf(1.0, roundf(r / 10.0))
	match id:
		"build", "wall":
			var n := 3 if id == "build" else 5
			var w := (3.0 if id == "build" else 2.0) * k
			var step := w + k
			var x0 := roundf(c.x - (n * step - k) / 2.0)
			var foot := roundf(c.y + 4.0 * k)
			if id == "wall":
				draw_rect(Rect2(x0 - 2.0, foot - 4.0 * k - 1.0, n * step - k + 4.0, k + 2.0), Ui.INK)
			for i in n:
				var tall := (9.0 if i == 1 else 7.5) * k if id == "build" else 7.0 * k
				_stake(Vector2(x0 + i * step, foot - tall), w, tall, wood)
			if id == "wall":
				draw_rect(Rect2(x0 - 1.0, foot - 4.0 * k, n * step - k + 2.0, k), wood.darkened(0.25))
		"bridge":
			var w := 12.0 * k
			var top := roundf(c.y - 3.5 * k)
			var x := roundf(c.x - w / 2.0)
			draw_rect(Rect2(x - 1.0, top - 1.0, w + 2.0, 7.0 * k + 2.0), Ui.INK)
			for n in 4:
				draw_rect(Rect2(x + n * 3.0 * k, top, 2.0 * k, 7.0 * k), wood)
			draw_rect(Rect2(x, top + k, w, k), wood.lightened(0.3))
			draw_rect(Rect2(x, top + 5.0 * k, w, k), wood.darkened(0.3))


## One sharpened stake standing at `at`, its top left corner, in an ink outline with a lit left edge.
func _stake(at: Vector2, w: float, tall: float, wood: Color) -> void:
	var tip := ceilf(w / 2.0)
	var shape := PackedVector2Array([at + Vector2(0, tip), at + Vector2(w / 2.0, 0), at + Vector2(w, tip), at + Vector2(w, tall), at + Vector2(0, tall)])
	var outline := PackedVector2Array([at + Vector2(-1, tip), at + Vector2(w / 2.0, -1.5), at + Vector2(w + 1, tip), at + Vector2(w + 1, tall + 1), at + Vector2(-1, tall + 1)])
	draw_colored_polygon(outline, Ui.INK)
	draw_colored_polygon(shape, wood)
	draw_rect(Rect2(at + Vector2(0, tip), Vector2(maxf(1.0, w / 3.0), tall - tip)), wood.lightened(0.3))
