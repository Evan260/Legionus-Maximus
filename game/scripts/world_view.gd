extends Node2D
## Draws the field around the commander: ground, scattered props, coins, the legion and the horde in depth order,
## then missiles and effects.


var sim: Sim
var atlas: Atlas
var ground: Texture2D
var _ground_of := "germania"
var shadow: Texture2D
var shake_on := true
var digits: Texture2D
var _cam := Vector2.ZERO
var _shake_rng := RandomNumberGenerator.new()

var _keys := PackedInt64Array()
var _rects: Array = []
var _dests := PackedVector2Array()
var _mods := PackedColorArray()
# The trees being chopped this frame, as [position, seconds of chopping], for their progress bars.
var _felling: Array = []


func _ready() -> void:
	ground = load(Content.ground_path("germania"))
	var img := Image.create(16, 6, false, Image.FORMAT_RGBA8)
	for y in 6:
		for x in 16:
			var dx := (x - 7.5) / 8.0
			var dy := (y - 2.5) / 3.0
			if dx * dx + dy * dy <= 1.0:
				img.set_pixel(x, y, Color(0.08, 0.06, 0.03, 0.38))
	shadow = ImageTexture.create_from_image(img)
	digits = _digit_texture()


## The ten digits as 3 by 5 pixel shapes in one strip, four pixels apart.
func _digit_texture() -> Texture2D:
	var shapes := ["111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001",
		"111100111001111", "111100111101111", "111001010010010", "111101111101111", "111101111001111"]
	var strip := Image.create(40, 5, false, Image.FORMAT_RGBA8)
	for d in 10:
		for i in 15:
			if shapes[d][i] == "1":
				strip.set_pixel(d * 4 + i % 3, i / 3, Color.WHITE)
	return ImageTexture.create_from_image(strip)


func _process(dt: float) -> void:
	if sim:
		var jolt := Vector2.ZERO
		if shake_on and sim.shake > 0.0:
			var reach := int(sim.b.shake.pixels)
			jolt = Vector2(_shake_rng.randi_range(-reach, reach), _shake_rng.randi_range(-reach, reach))
		# The shake dies away here, not in the sim, so it still ends while the run is paused or over.
		sim.shake = maxf(0.0, sim.shake - dt)
		position = (get_viewport_rect().size / 2.0 - sim.commander.pos).round() + jolt
		queue_redraw()


func _add(y: float, rect: Rect2, dest: Vector2, mod: Color, moving := false) -> void:
	_keys.append((int(y) + 100000) * 65536 + _rects.size())
	_rects.append(rect)
	_dests.append(_snap(dest) if moving else dest.round())
	_mods.append(mod)


## Rounds a moving unit to the pixel relative to the camera, so men marching beside the commander keep a steady gap on a diagonal.
func _snap(p: Vector2) -> Vector2:
	return (p - _cam).round() + _cam.round()


func _draw() -> void:
	if not sim:
		return
	var cam: Vector2 = sim.commander.pos
	_cam = cam
	var screen := get_viewport_rect().size
	var top_left := cam - screen / 2.0
	if sim.province != _ground_of:
		_ground_of = sim.province
		ground = load(Content.ground_path(_ground_of))
	var gw := ground.get_width()
	var gh := ground.get_height()
	var gx0 := floori(top_left.x / gw)
	var gy0 := floori(top_left.y / gh)
	for gx in range(gx0, gx0 + ceili(screen.x / gw) + 2):
		for gy in range(gy0, gy0 + ceili(screen.y / gh) + 2):
			draw_texture(ground, Vector2(gx * gw, gy * gh))

	_draw_ground_zones(view_for(top_left))
	_draw_scorch(view_for(top_left))
	_draw_warnings()
	_keys.clear()
	_rects.clear()
	_dests.clear()
	_mods.clear()
	var white := Color.WHITE
	var margin := 80.0
	var view := Rect2(top_left - Vector2(margin, margin), screen + Vector2(margin, margin) * 2.0)

	var see_through := Color(1, 1, 1, 0.15)
	var him := Rect2(cam - Vector2(12, 40), Vector2(24, 40))
	var chops: Dictionary = sim.terrain.chops
	var shaking := float(sim.b.felling.shake_seconds)
	_felling.clear()
	for pr in sim.terrain.props_in(view):
		# A piece with no kind is an unseen blocker, such as the inside of the fort's gate towers.
		if pr[0] == "":
			continue
		var f := atlas.prop_frame(pr[0])
		var at: Vector2 = pr[1]
		if not chops.is_empty() and chops.has(at) and sim.time - float(chops[at][1]) < shaking:
			_felling.append([at, float(chops[at][0])])
			at += Vector2(roundf(sin(sim.time * 45.0 + at.x) * 1.2), 0)
		var mod := white
		# A tree standing in front of the commander is seen through, so he is not lost once the legion cuts into a ridge.
		if pr[2] > 0.0 and at.y > cam.y and Rect2(at - f[1], f[0].size).intersects(him):
			mod = see_through
		# The gate fades only half way, so the fort still reads while the commander walks under it.
		elif pr[0] == "fort_gate" and at.y > cam.y and Rect2(at - f[1], f[0].size).intersects(him):
			mod = Color(1, 1, 1, 0.55)
		_add(pr[1].y, f[0], at - f[1], mod)
	if not sim.terrain.posts.is_empty():
		var sf := atlas.prop_frame("stake")
		var fade := float(sim.b.palisade.fade)
		for post in sim.terrain.posts:
			if view.has_point(post[1]):
				_add(post[1].y, sf[0], post[1] - sf[1], Color(1, 1, 1, clampf((post[3] - sim.time) / fade, 0.0, 1.0)))


	var gold := Color(1.0, 0.92, 0.7)
	for u in [sim.commander] + sim.soldiers:
		var action := "move" if u.moving else "idle"
		var f := atlas.unit_frame(u.type, action, Sim.dir_name(u.facing), u.anim)
		var mod := white
		if u.flash > 0.0:
			mod = Color(1.0, 0.55, 0.55)
		elif sim.testudo_left > 0.0:
			mod = gold
		draw_texture(shadow, _snap(u.pos - Vector2(8, 3)))
		_add(u.pos.y, f[0], u.pos - f[1], mod, true)

	for i in sim.horde.e_pos.size():
		var p: Vector2 = sim.horde.e_pos[i]
		if not view.has_point(p):
			continue
		var type: String = sim.horde.kind_ids[sim.horde.e_kind[i]]
		var t := sim.time * 11.0 + sim.horde.e_phase[i]
		var f := atlas.unit_frame(type, "move", Sim.dir_name(sim.horde.e_face[i]), t if sim.horde.e_fighting[i] == 0 else float(sim.horde.e_phase[i]))
		var mod := white
		if sim.horde.e_flash[i] > 0.0:
			mod = Color(1.0, 0.5, 0.45)
		elif sim.horde.e_burn[i] > 0.0:
			mod = Color(1.0, 0.78, 0.6)
		draw_texture(shadow, _snap(p - Vector2(8, 3)))
		_add(p.y, f[0], p - f[1], mod, true)

	for e in sim.effects:
		if e.kind == "death" or e.kind == "fallen":
			var f := atlas.unit_frame(e.type, "idle", Sim.dir_name(e.facing), 0.0)
			var a: float = 1.0 - e.t / 0.45
			_add(e.pos.y, f[0], e.pos - f[1] + Vector2(0, e.t * 8.0), Color(0.75, 0.35, 0.3, a))

	_add_arm_sprites(view)
	_add_chests_and_carts(view)
	_add_objectives(view)
	_draw_coins(view)
	_keys.sort()
	var tex := atlas.texture
	for key in _keys:
		var idx := int(key % 65536)
		draw_texture_rect_region(tex, Rect2(_dests[idx], _rects[idx].size), _rects[idx], _mods[idx])

	_draw_shots(tex)
	_draw_spears()
	_draw_elite_names(view)
	_draw_lobs(tex)
	_draw_effects()
	_draw_objective_marks(view)
	_draw_numbers()
	_draw_torches()
	_draw_bars()
	_draw_felling()


func view_for(top_left: Vector2) -> Rect2:
	return Rect2(top_left - Vector2(80, 80), get_viewport_rect().size + Vector2(160, 160))


## Burning ground, oil and the ditch of the stake ring, drawn on the ground under everything that stands on it.
func _draw_ground_zones(view: Rect2) -> void:
	var beat := int(sim.time * 10.0)
	for z in sim.arms.ground_zones():
		var p: Vector2 = z.pos
		var r: float = z.radius
		if z.kind != "stakes" and not view.grow(r).has_point(p):
			continue
		var fade := clampf((z.life - z.t) / 0.6, 0.0, 1.0) if z.has("life") else 1.0
		match z.kind:
			"fire":
				draw_circle(p, r, Color(0.2, 0.07, 0.03, 0.42 * fade))
				var n := int(r / 2.5) + 3
				for i in n:
					var a := i * 2.4
					var d := r * sqrt((i + 0.5) / n) * 0.92
					var base := p + Vector2(cos(a) * d, sin(a) * d)
					var h := 2 + (beat + i * 3) % 4
					draw_rect(Rect2(base.round() + Vector2(0, -h), Vector2(2, h)), Color(1.0, 0.5, 0.12, 0.9 * fade))
					draw_rect(Rect2(base.round() + Vector2(0, -h + 1), Vector2(1, maxi(1, h - 2))), Color(1.0, 0.86, 0.35, 0.9 * fade))
			"oil":
				draw_circle(p, r, Color(0.07, 0.06, 0.05, 0.6 * fade))
				draw_arc(p, r * 0.6, 3.5 + sin(sim.time * 2.0) * 0.2, 4.7, 10, Color(0.45, 0.5, 0.65, 0.55 * fade), 1.0)
				draw_arc(p, r * 0.3, 0.2, 1.4, 8, Color(0.45, 0.5, 0.65, 0.4 * fade), 1.0)
			"stakes":
				# The ditch is the dark band the stakes stand in.
				draw_arc(p, r, 0.0, TAU, 72, Color(0.2, 0.13, 0.07, 0.5), 5.0)


## Sprites that stand on the field and sort with the legion: caltrops, stakes and war dogs, drawn when their art exists.
func _add_arm_sprites(view: Rect2) -> void:
	if atlas.props.has("caltrops"):
		var f := atlas.prop_frame("caltrops")
		for z in sim.arms.zones:
			if z.kind == "caltrops" and view.has_point(z.pos):
				_add(z.pos.y - 8.0, f[0], z.pos - f[1], Color(1, 1, 1, clampf((z.life - z.t) / 0.6, 0.0, 1.0)))
	if atlas.props.has("stake") and not sim.arms.stakes.is_empty():
		var f := atlas.prop_frame("stake")
		var st: Dictionary = sim.arms.stakes
		var n := int(st.radius * TAU / 14.0)
		for i in n:
			var p: Vector2 = st.pos + Vector2.from_angle(i * TAU / n) * st.radius
			if view.has_point(p):
				_add(p.y, f[0], p - f[1], Color.WHITE)
	if atlas.units.has("war_dog"):
		var action := "move" if atlas.units.war_dog.has("move") else "idle"
		for d in sim.arms.dogs:
			var f := atlas.unit_frame("war_dog", action, Sim.dir_name(d.face), d.run * 12.0)
			draw_texture(shadow, (d.pos - Vector2(8, 3)).round())
			_add(d.pos.y, f[0], d.pos - f[1], Color.WHITE)


func _draw_lobs(tex: Texture2D) -> void:
	for l in sim.arms.lobs:
		var k: float = l.t / l.dur
		var ground: Vector2 = l.from.lerp(l.to, k)
		var p: Vector2 = ground + Vector2(0, -sin(k * PI) * 34.0)
		draw_rect(Rect2((ground + Vector2(-1, 0)).round(), Vector2(3, 1)), Color(0.08, 0.06, 0.03, 0.4))
		match l.kind:
			"stone":
				_lob_sprite(tex, "onager_stone", p)
			"pot":
				_lob_sprite(tex, "fire_pot", p)
			"oil":
				var q := p.round()
				draw_rect(Rect2(q + Vector2(-2, -3), Vector2(4, 5)), Color(0.36, 0.2, 0.1))
				draw_rect(Rect2(q + Vector2(-1, -4), Vector2(2, 1)), Color(0.5, 0.3, 0.16))
				draw_rect(Rect2(q + Vector2(-1, -2), Vector2(1, 3)), Color(0.55, 0.36, 0.2))
	for l in sim.horde.foe_lobs:
		if l.get("slam", false):
			continue
		var k: float = l.t / l.dur
		var ground: Vector2 = l.from.lerp(l.to, k)
		_lob_sprite(tex, "fire_pot", ground + Vector2(0, -sin(k * PI) * 40.0))


## Red rings on the ground where the war priests' pots will land and round the chieftain's slam, and the line of his coming charge, each filling in as it nears.
func _draw_warnings() -> void:
	var h := sim.horde
	if h.charge_warn > 0.0 and h.chieftain_index() >= 0:
		var k := clampf(1.0 - h.charge_warn / h.charge_total, 0.0, 1.0)
		var end := h.charge_from + h.charge_dir * h.charge_len
		var edge := h.charge_dir.orthogonal() * h.charge_width / 2.0
		draw_line(h.charge_from, end, Color(0.75, 0.12, 0.08, 0.12 + 0.18 * k), h.charge_width)
		draw_line(h.charge_from + edge, end + edge, Color(0.95, 0.25, 0.15, 0.85), 1.0)
		draw_line(h.charge_from - edge, end - edge, Color(0.95, 0.25, 0.15, 0.85), 1.0)
		draw_line(end + edge, end - edge, Color(0.95, 0.25, 0.15, 0.85), 1.0)
		draw_line(h.charge_from, h.charge_from.lerp(end, k), Color(0.95, 0.35, 0.15, 0.25), h.charge_width)
	for l in sim.horde.foe_lobs:
		var k: float = clampf(l.t / l.dur, 0.0, 1.0)
		draw_circle(l.to, l.radius, Color(0.75, 0.12, 0.08, 0.12 + 0.18 * k))
		draw_arc(l.to, l.radius, 0.0, TAU, 32, Color(0.95, 0.25, 0.15, 0.85), 1.0)
		draw_circle(l.to, l.radius * k, Color(0.95, 0.35, 0.15, 0.25))


func _lob_sprite(tex: Texture2D, key: String, p: Vector2) -> void:
	if not atlas.props.has(key):
		return
	var f := atlas.prop_frame(key)
	draw_texture_rect_region(tex, Rect2((p - f[1]).round(), f[0].size), f[0])


func _draw_torches() -> void:
	var beat := int(sim.time * 14.0)
	var big := sim.rank("burning_eagle") > 0
	var points: Array = sim.arms.torch_points(sim)
	for i in points.size():
		var p: Vector2 = points[i].round()
		var flick := (beat + i * 5) % 3
		draw_circle(p + Vector2(0, -6), 9.0 + flick, Color(1.0, 0.6, 0.2, 0.22))
		draw_rect(Rect2(p + Vector2(-1, -5), Vector2(2, 7)), Color(0.3, 0.2, 0.1))
		var hot := Color(0.45, 0.8, 1.0) if big else Color(1.0, 0.5, 0.12)
		draw_rect(Rect2(p + Vector2(-2, -10 - flick), Vector2(5, 5 + flick)), hot)
		draw_rect(Rect2(p + Vector2(-1, -9 - flick), Vector2(2, 4)), Color(1.0, 0.92, 0.55))


func _draw_coins(view: Rect2) -> void:
	# A denarius is drawn as a full coin sprite with a dark rim, bobbing and glinting, so it stands out from the grass.
	if not atlas.props.has("coin"):
		return
	var f := atlas.prop_frame("coin")
	var tex := atlas.texture
	var size: Vector2 = f[0].size
	var gold := Color(1.35, 1.12, 0.5)
	var rim := Color(0.18, 0.1, 0.04, 0.85)
	for i in sim.c_pos.size():
		var p: Vector2 = sim.c_pos[i]
		if not view.has_point(p):
			continue
		var bob := roundf(sin(sim.time * 4.0 + i * 1.7) * 1.0)
		var at := (p - size / 2.0 + Vector2(0, bob - 2.0)).round()
		draw_rect(Rect2(at + Vector2(1, size.y - 1), Vector2(size.x - 2, 2)), Color(0.05, 0.04, 0.02, 0.35))
		draw_texture_rect_region(tex, Rect2(at + Vector2(-1, 0), size), f[0], rim)
		draw_texture_rect_region(tex, Rect2(at + Vector2(1, 0), size), f[0], rim)
		draw_texture_rect_region(tex, Rect2(at + Vector2(0, -1), size), f[0], rim)
		draw_texture_rect_region(tex, Rect2(at + Vector2(0, 1), size), f[0], rim)
		draw_texture_rect_region(tex, Rect2(at, size), f[0], gold)
		if int(sim.time * 5.0 + i * 3) % 11 == 0:
			draw_rect(Rect2(at + Vector2(3, 2), Vector2(2, 2)), Color(1, 1, 0.92))


## Chests left by elites and supply carts, when their art is drawn.
func _add_chests_and_carts(view: Rect2) -> void:
	if atlas.props.has("chest"):
		var f := atlas.prop_frame("chest")
		for ch in sim.horde.chests:
			if view.has_point(ch.pos):
				_add(ch.pos.y, f[0], ch.pos - f[1], Color.WHITE)
	if atlas.props.has("supply_cart"):
		var f := atlas.prop_frame("supply_cart")
		for cart in sim.horde.carts:
			if view.has_point(cart.pos):
				_add(cart.pos.y, f[0], cart.pos - f[1], Color.WHITE)


## The eagle in the camp, the stranded column's cart and guards, and the grove's altar; huts, oaks and the fort are terrain.
func _add_objectives(view: Rect2) -> void:
	for o in sim.objectives.list:
		if not view.grow(60.0).has_point(o.pos):
			continue
		match o.kind:
			"camp":
				if not o.done:
					_add_prop("eagle_standard", o.pos, Color.WHITE)
			"column":
				_add_prop("supply_cart", o.pos, Color.WHITE)
				for g in o.guards:
					var f := atlas.unit_frame("legionary", "idle", Sim.dir_name(g.facing), g.anim)
					draw_texture(shadow, (g.pos - Vector2(8, 3)).round())
					_add(g.pos.y, f[0], g.pos - f[1], Color(1.0, 0.55, 0.55) if g.flash > 0.0 else Color.WHITE)
			"grove":
				_add_prop("altar", o.pos, Color(0.45, 0.4, 0.38) if o.done else Color.WHITE)


func _add_prop(key: String, pos: Vector2, mod: Color) -> void:
	if atlas.props.has(key):
		var f := atlas.prop_frame(key)
		_add(pos.y, f[0], pos - f[1], mod)


## The grove's and the fort's rings filling while the commander holds them, and the grove's oaks and the camp's huts burning.
func _draw_objective_marks(view: Rect2) -> void:
	var cfg: Dictionary = sim.b.objectives.grove
	var fort: Dictionary = sim.objectives.fort
	if not fort.is_empty() and not sim.objectives.fort_reached and view.grow(120.0).has_point(fort.centre):
		_hold_ring(fort.centre, float(sim.b.fort.half) * 0.7, float(fort.hold) / float(sim.b.fort.hold))
	for o in sim.objectives.list:
		if o.kind == "camp" and o.burnt_at >= 0.0 and not o.razed and view.grow(120.0).has_point(o.pos):
			var left := float(sim.b.objectives.camp.burn_seconds) - (sim.time - float(o.burnt_at))
			for i in o.huts.size():
				_flames(o.huts[i] + Vector2(0, -18), i, clampf(left / 1.5, 0.0, 1.0), 2.0)
		if o.kind != "grove" or not view.grow(120.0).has_point(o.pos):
			continue
		if not o.done:
			_hold_ring(o.pos, float(cfg.inside), o.hold / float(cfg.hold))
		elif sim.time - o.burnt_at < float(cfg.burn_seconds):
			var fade := clampf((float(cfg.burn_seconds) - (sim.time - o.burnt_at)) / 2.0, 0.0, 1.0)
			var spots: Array = o.oaks + [o.pos]
			for i in spots.size():
				_flames(spots[i] + Vector2(0, -30 if i < o.oaks.size() else -8), i, fade, 1.0)


## A faint ring round a place to hold, filling clockwise from the top as the hold goes on.
func _hold_ring(at: Vector2, radius: float, k: float) -> void:
	draw_arc(at, radius, 0.0, TAU, 48, Color(1.0, 0.89, 0.59, 0.35), 1.0)
	if k > 0.0:
		k = clampf(k, 0.0, 1.0)
		draw_arc(at, radius, -PI / 2.0, -PI / 2.0 + TAU * k, 48, Color(0.16, 0.1, 0.08, 0.8), 4.0)
		draw_arc(at, radius, -PI / 2.0, -PI / 2.0 + TAU * k, 48, Color(1.0, 0.6, 0.18), 2.0)


## Flickering pixel flames standing on base, `size` times the grove's, faded by `fade`.
func _flames(base: Vector2, seed_i: int, fade: float, size: float) -> void:
	var beat := int(sim.time * 12.0)
	var n := 3 if size <= 1.0 else 5
	var spread := maxf(1.0, size / 1.4)
	var w := roundf(5.0 * spread)
	for f in n:
		var p: Vector2 = (base + Vector2((f - (n - 1) / 2.0) * 7.0 * spread + (beat + seed_i) % 3 - 1, -(f % 2) * 10.0 * spread)).round()
		var h := roundf((5 + (beat + seed_i * 3 + f) % 5) * size)
		draw_rect(Rect2(p + Vector2(-floorf(w / 2.0), -h), Vector2(w, h)), Color(1.0, 0.45, 0.1, 0.9 * fade))
		draw_rect(Rect2(p + Vector2(-floorf(w / 2.0) + 1.0, -h + 2.0), Vector2(maxf(1.0, w - 2.0), maxf(1.0, h - 3.0))), Color(1.0, 0.85, 0.35, 0.9 * fade))


## Scorched ground where a camp's huts burnt, drawn on the ground under everything else.
func _draw_scorch(view: Rect2) -> void:
	for o in sim.objectives.list:
		if o.kind != "camp" or o.burnt_at < 0.0 or not view.grow(60.0).has_point(o.pos):
			continue
		var k := clampf((sim.time - float(o.burnt_at)) / float(sim.b.objectives.camp.burn_seconds), 0.0, 1.0)
		for h in o.huts:
			draw_set_transform(h + Vector2(0, -4), 0.0, Vector2(1.0, 0.55))
			draw_circle(Vector2.ZERO, 22.0, Color(0.12, 0.09, 0.07, 0.45 * k))
			draw_circle(Vector2.ZERO, 14.0, Color(0.07, 0.05, 0.04, 0.6 * k))
			draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Spears thrown by the horde are drawn as short pixel lines.
func _draw_spears() -> void:
	var h: Horde = sim.horde
	for i in h.sp_pos.size():
		var dir: Vector2 = h.sp_vel[i].normalized()
		draw_line(h.sp_pos[i] - dir * 7.0, h.sp_pos[i], Color(0.45, 0.3, 0.16), 1.0)
		draw_rect(Rect2(h.sp_pos[i].round(), Vector2(1, 1)), Color(0.85, 0.85, 0.8))


## An elite's name stands over its head in small text.
func _draw_elite_names(view: Rect2) -> void:
	var h: Horde = sim.horde
	for id in h.elite_ids:
		var i := h.e_id.find(id)
		if i < 0 or not view.has_point(h.e_pos[i]):
			continue
		var label: String = sim.content.enemies[h.kind_ids[h.e_kind[i]]].name
		var at: Vector2 = (h.e_pos[i] + Vector2(-60, -34)).round()
		draw_string(Ui.font(), at + Vector2(1, 1), label, HORIZONTAL_ALIGNMENT_CENTER, 120, Lang.base_px(), Color(0.16, 0.1, 0.08))
		draw_string(Ui.font(), at, label, HORIZONTAL_ALIGNMENT_CENTER, 120, Lang.base_px(), Color(1.0, 0.89, 0.59))


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
			"stone":
				draw_rect(Rect2((s.pos - dir * 3.0).round(), Vector2(1, 1)), Color(0.75, 0.74, 0.7, 0.5))
				draw_rect(Rect2(s.pos.round(), Vector2(2, 2)), Color(0.62, 0.6, 0.56))
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
		elif e.kind == "shout" or e.kind == "boom":
			var k: float = e.t / 0.45
			var col := Color(1.0, 0.85, 0.4, 1.0 - k) if e.kind == "shout" else Color(1.0, 0.55, 0.2, 1.0 - k)
			draw_arc(e.pos, e.radius * (0.4 + 0.6 * k), 0.0, TAU, 24, col, 1.0)
		elif e.kind == "trumpet":
			var k: float = e.t / 0.45
			draw_arc(e.pos, e.radius * (0.3 + 0.7 * k), 0.0, TAU, 32, Color(1.0, 0.9, 0.5, 1.0 - k), 2.0)
			draw_arc(e.pos, e.radius * (0.15 + 0.7 * k), 0.0, TAU, 32, Color(1.0, 1.0, 0.85, (1.0 - k) * 0.7), 1.0)
		elif e.kind == "flash":
			var k: float = e.t / 0.45
			draw_circle(e.pos, e.radius * (0.4 + 0.6 * k), Color(1.0, 0.97, 0.7, 0.34 * (1.0 - k)))
			draw_arc(e.pos, e.radius * (0.4 + 0.6 * k), 0.0, TAU, 40, Color(1.0, 1.0, 0.9, 1.0 - k), 2.0)
			for ray in 8:
				var dir := Vector2.from_angle(ray * TAU / 8.0 + 0.4)
				draw_line(e.pos + dir * e.radius * 0.2 * (1.0 + k), e.pos + dir * e.radius * (0.35 + 0.65 * k), Color(1.0, 0.95, 0.6, 1.0 - k), 1.0)
		elif e.kind == "cleave":
			var k: float = e.t / 0.45
			var a: float = e.dir.angle()
			draw_arc(e.pos, e.radius * (0.6 + 0.4 * k), a - e.arc / 2.0, a + e.arc / 2.0, 12, Color(1.0, 0.8, 0.6, 1.0 - k), 2.0)
		elif e.kind == "cry":
			var k: float = e.t / 0.45
			draw_arc(e.pos, e.radius * (0.2 + 0.8 * k), 0.0, TAU, 48, Color(0.9, 0.25, 0.2, 1.0 - k), 2.0)
		elif e.kind == "spark":
			var k: float = e.t / 0.45
			draw_rect(Rect2((e.pos + Vector2(-1, -1 - k * 4.0)).round(), Vector2(2, 2)), Color(1.0, 0.95, 0.6, 1.0 - k))
		elif e.kind == "heal":
			var k: float = e.t / 0.45
			var h: Vector2 = (e.pos + Vector2(-1, -14.0 - k * 8.0)).round()
			var green := Color(0.5, 1.0, 0.55, 1.0 - k)
			draw_rect(Rect2(h + Vector2(1, 0), Vector2(1, 3)), green)
			draw_rect(Rect2(h + Vector2(0, 1), Vector2(3, 1)), green)
	for i in sim.horde.e_pos.size():
		if sim.horde.e_burn[i] > 0.0:
			var p: Vector2 = sim.horde.e_pos[i] + Vector2(-2 + (int(sim.time * 20.0 + i) % 4), -22)
			draw_rect(Rect2(p.round(), Vector2(1, 2)), Color(1, 0.6, 0.15, 0.9))
			draw_rect(Rect2((p + Vector2(2, 2)).round(), Vector2(1, 1)), Color(1, 0.85, 0.3, 0.9))
		if sim.horde.e_stun[i] > 0.0:
			var q: Vector2 = sim.horde.e_pos[i] + Vector2(-3 + (int(sim.time * 12.0 + i) % 7), -26)
			draw_rect(Rect2(q.round(), Vector2(2, 2)), Color(1, 0.95, 0.45))


## Damage numbers rise from the enemy that was hit and fade out.
func _draw_numbers() -> void:
	var life := float(sim.b.damage_numbers.seconds)
	var rise := float(sim.b.damage_numbers.rise)
	for n in sim.numbers:
		var text := str(n.v)
		var k: float = n.t / life
		var at: Vector2 = (n.pos + Vector2(-(text.length() * 4 - 1) / 2.0, -rise * k)).round()
		var a := clampf((1.0 - k) * 3.0, 0.0, 1.0)
		for pass_index in 2:
			var tint := Ui.INK if pass_index == 0 else Ui.CREAM
			tint.a = a
			var o := Vector2(1, 1) if pass_index == 0 else Vector2.ZERO
			for i in text.length():
				var d := text.unicode_at(i) - 48
				draw_texture_rect_region(digits, Rect2(at + o + Vector2(i * 4, 0), Vector2(3, 5)), Rect2(d * 4, 0, 3, 5), tint)


func _draw_bars() -> void:
	var c: Dictionary = sim.commander
	var w := 20.0
	var p: Vector2 = (c.pos + Vector2(-w / 2.0, 5)).round()
	draw_rect(Rect2(p - Vector2(1, 1), Vector2(w + 2, 4)), Color(0.16, 0.1, 0.08))
	draw_rect(Rect2(p, Vector2(w * clampf(c.hp / c.max_hp, 0.0, 1.0), 2)), Color(0.85, 0.22, 0.18))


## A small bar over each tree being cut, filling as it nears its fall.
func _draw_felling() -> void:
	var secs := float(sim.b.felling.seconds)
	for f in _felling:
		var p: Vector2 = (f[0] + Vector2(-8, -30)).round()
		draw_rect(Rect2(p - Vector2(1, 1), Vector2(18, 4)), Color(0.16, 0.1, 0.08))
		draw_rect(Rect2(p, Vector2(16.0 * clampf(f[1] / secs, 0.0, 1.0), 2)), Color(0.91, 0.69, 0.25))
