extends Node2D
## Draws the field around the commander: ground, scattered props, coins, the legion and the horde in depth order,
## then missiles and effects.

const VIEW := Vector2(640, 360)
const CHUNK := 160.0
const PROP_KINDS := ["oak", "fir", "rock", "log", "bush", "stones", "bush", "stones", "fir", "rock"]

var sim: Sim
var atlas: Atlas
var ground: Texture2D
var shadow: Texture2D
var props_cache := {}

var _keys := PackedInt64Array()
var _rects: Array = []
var _dests := PackedVector2Array()
var _mods := PackedColorArray()


func _ready() -> void:
	ground = load("res://assets/ground.png")
	var img := Image.create(16, 6, false, Image.FORMAT_RGBA8)
	for y in 6:
		for x in 16:
			var dx := (x - 7.5) / 8.0
			var dy := (y - 2.5) / 3.0
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, Color(0.08, 0.06, 0.03, 0.38))
	shadow = ImageTexture.create_from_image(img)


func _process(_dt: float) -> void:
	if sim:
		position = (VIEW / 2.0 - sim.commander.pos).round()
		queue_redraw()


func _chunk_props(cx: int, cy: int) -> Array:
	var key := Vector2i(cx, cy)
	if props_cache.has(key):
		return props_cache[key]
	var r := RandomNumberGenerator.new()
	r.seed = hash(key)
	var out: Array = []
	for i in r.randi_range(0, 2):
		var p := Vector2((cx + r.randf()) * CHUNK, (cy + r.randf()) * CHUNK)
		# The field where the legion starts stays open.
		if p.length() > 90.0:
			out.append([PROP_KINDS[r.randi_range(0, PROP_KINDS.size() - 1)], p])
	props_cache[key] = out
	return out


func _add(y: float, rect: Rect2, dest: Vector2, mod: Color) -> void:
	_keys.append((int(y) + 100000) * 65536 + _rects.size())
	_rects.append(rect)
	_dests.append(dest.round())
	_mods.append(mod)


func _draw() -> void:
	if not sim:
		return
	var cam: Vector2 = sim.commander.pos
	var top_left := cam - VIEW / 2.0
	var gw := ground.get_width()
	var gh := ground.get_height()
	var gx0 := floori(top_left.x / gw)
	var gy0 := floori(top_left.y / gh)
	for gx in range(gx0, gx0 + ceili(VIEW.x / gw) + 2):
		for gy in range(gy0, gy0 + ceili(VIEW.y / gh) + 2):
			draw_texture(ground, Vector2(gx * gw, gy * gh))

	_keys.clear()
	_rects.clear()
	_dests.clear()
	_mods.clear()
	var white := Color.WHITE
	var margin := 80.0
	var view := Rect2(top_left - Vector2(margin, margin), VIEW + Vector2(margin, margin) * 2.0)

	for cx in range(floori(view.position.x / CHUNK), floori(view.end.x / CHUNK) + 1):
		for cy in range(floori(view.position.y / CHUNK), floori(view.end.y / CHUNK) + 1):
			for pr in _chunk_props(cx, cy):
				var f := atlas.prop_frame(pr[0])
				_add(pr[1].y, f[0], pr[1] - f[1], white)


	var gold := Color(1.0, 0.92, 0.7)
	for u in [sim.commander] + sim.soldiers:
		var action := "move" if u.moving else "idle"
		var f := atlas.unit_frame(u.type, action, Sim.dir_name(u.facing), u.anim)
		var mod := white
		if u.flash > 0.0:
			mod = Color(1.0, 0.55, 0.55)
		elif sim.testudo_left > 0.0:
			mod = gold
		draw_texture(shadow, (u.pos - Vector2(8, 3)).round())
		_add(u.pos.y, f[0], u.pos - f[1], mod)

	for i in sim.e_pos.size():
		var p: Vector2 = sim.e_pos[i]
		if not view.has_point(p):
			continue
		var type: String = Sim.KINDS[sim.e_kind[i]]
		var t := sim.time * 11.0 + sim.e_phase[i]
		var f := atlas.unit_frame(type, "move", Sim.dir_name(sim.e_face[i]), t if sim.e_fighting[i] == 0 else float(sim.e_phase[i]))
		var mod := white
		if sim.e_flash[i] > 0.0:
			mod = Color(1.0, 0.5, 0.45)
		elif sim.e_burn[i] > 0.0:
			mod = Color(1.0, 0.78, 0.6)
		draw_texture(shadow, (p - Vector2(8, 3)).round())
		_add(p.y, f[0], p - f[1], mod)

	for e in sim.effects:
		if e.kind == "death" or e.kind == "fallen":
			var f := atlas.unit_frame(e.type, "idle", Sim.dir_name(e.facing), 0.0)
			var a: float = 1.0 - e.t / 0.45
			_add(e.pos.y, f[0], e.pos - f[1] + Vector2(0, e.t * 8.0), Color(0.75, 0.35, 0.3, a))

	_draw_coins(view)
	_keys.sort()
	var tex := atlas.texture
	for key in _keys:
		var idx := int(key % 65536)
		draw_texture_rect_region(tex, Rect2(_dests[idx], _rects[idx].size), _rects[idx], _mods[idx])

	_draw_shots(tex)
	_draw_effects()
	_draw_bars()


func _draw_coins(view: Rect2) -> void:
	# A denarius is a few pixels of gold with a glint that turns, so it reads as a pickup and not as ground.
	var glint := int(sim.time * 6.0)
	for i in sim.c_pos.size():
		var p: Vector2 = sim.c_pos[i].round()
		if not view.has_point(p):
			continue
		var big := sim.c_val[i] > 1
		var r := 2 if big else 1
		draw_rect(Rect2(p + Vector2(-r - 1, -r), Vector2(2 * r + 3, 2 * r + 1)), Color(0.24, 0.14, 0.06))
		draw_rect(Rect2(p + Vector2(-r, -r - 1), Vector2(2 * r + 1, 2 * r + 3)), Color(0.24, 0.14, 0.06))
		draw_rect(Rect2(p + Vector2(-r, -r), Vector2(2 * r + 1, 2 * r + 1)), Color(0.93, 0.7, 0.2))
		draw_rect(Rect2(p + Vector2(-r, -r), Vector2(r, r)), Color(1.0, 0.92, 0.55))
		if (glint + i) % 9 == 0:
			draw_rect(Rect2(p + Vector2(-r - 2, -r - 2), Vector2(1, 1)), Color(1, 1, 0.9))


func _draw_shots(tex: Texture2D) -> void:
	var pil := atlas.prop_frame("pilum")
	for s in sim.shots:
		var dir: Vector2 = s.vel.normalized()
		match s.kind:
			"arrow":
				var col := Color(0.42, 0.28, 0.16) if s.burn <= 0.0 else Color(1.0, 0.55, 0.15)
				draw_line(s.pos - dir * 6.0, s.pos, col, 1.0)
				draw_rect(Rect2((s.pos).round(), Vector2(1, 1)), Color(0.85, 0.85, 0.8))
				if s.burn > 0.0:
					draw_rect(Rect2((s.pos - dir * 2.0 + Vector2(0, -1)).round(), Vector2(1, 1)), Color(1, 0.85, 0.3))
			"pilum":
				# The pilum is drawn pointing up and to the right, so it is turned from that angle.
				draw_set_transform(s.pos, dir.angle() + PI / 4.0)
				var r: Rect2 = pil[0]
				draw_texture_rect_region(tex, Rect2(-r.size / 2.0, r.size), r)
				draw_set_transform(Vector2.ZERO)
			"bolt":
				draw_line(s.pos - dir * 11.0, s.pos, Color(0.3, 0.2, 0.12), 2.0)
				draw_line(s.pos - dir * 2.0, s.pos + dir * 2.0, Color(0.8, 0.8, 0.78), 2.0)


func _draw_effects() -> void:
	for e in sim.effects:
		if e.kind == "slash":
			var dir: Vector2 = (e.to - e.pos).normalized()
			var a: float = 1.0 - e.t / 0.12
			var c := Color(1, 1, 0.92, a)
			var mid: Vector2 = e.pos + dir * 12.0
			var side := dir.orthogonal() * 4.0
			draw_line(mid - side - dir * 2.0, mid + dir * 2.0, c, 1.0)
			draw_line(mid + dir * 2.0, mid + side - dir * 2.0, c, 1.0)
	for i in sim.e_pos.size():
		if sim.e_burn[i] > 0.0:
			var p: Vector2 = sim.e_pos[i] + Vector2(-2 + (int(sim.time * 20.0 + i) % 4), -22)
			draw_rect(Rect2(p.round(), Vector2(1, 2)), Color(1, 0.6, 0.15, 0.9))
			draw_rect(Rect2((p + Vector2(2, 2)).round(), Vector2(1, 1)), Color(1, 0.85, 0.3, 0.9))


func _draw_bars() -> void:
	var c: Dictionary = sim.commander
	var w := 20.0
	var p: Vector2 = (c.pos + Vector2(-w / 2.0, 5)).round()
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(w + 2, 4)), Color(0.16, 0.1, 0.08))
	draw_rect(Rect2(p, Vector2(w * clampf(c.hp / c.max_hp, 0.0, 1.0), 2)), Color(0.85, 0.22, 0.18))
