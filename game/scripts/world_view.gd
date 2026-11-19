extends Node2D
## Draws the field around the commander: ground, scattered props, coins, the legion and the horde in depth order,
## then missiles and effects.

# How far the wheat tile is laid past each field for its frayed edge, and how many fields the shader holds (its `fields` array).
const FIELD_FRAY := 20.0
const FIELD_SHAPES := 32


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
var _rects: Array[Rect2] = []
var _dests := PackedVector2Array()
var _mods := PackedColorArray()
var _sizes := PackedVector2Array()
# The trees being chopped this frame, as [position, seconds of chopping], for their progress bars.
var _felling: Array = []
# Per enemy kind of the current sim: its art name, whether it has an attack drawn, and its shadow's width.
var _kinds_of: Sim
var _k_type := PackedStringArray()
var _k_attack := PackedByteArray()
var _k_shadow := PackedFloat32Array()
# How much larger than its art each kind is drawn, such as the war elephant.
var _k_scale := PackedFloat32Array()
# Every enemy kind's walk, attack and stance frames, so drawing the horde reads arrays instead of the atlas's JSON: slot (kind * 3 + action) * 8 + direction gives where its frames start in _f_rect, how many there are and the anchor.
var _f_start := PackedInt32Array()
var _f_count := PackedInt32Array()
var _f_anchor := PackedVector2Array()
var _f_rect: Array[Rect2] = []
# Each prop kind's frame from the atlas, looked up once.
var _prop_frames := {}
# The rocky lip drawn along every ravine.
var ravine_edge: Texture2D
# The ice laid along every frozen stream, repeated across the world.
var ice: Texture2D
# Soldiers reeling from a sling stone, and the camels bringing the shah's riders fresh arrows, marked over their heads this frame.
var _dazed := PackedVector2Array()
var _train_marks := PackedVector2Array()
# The ground and the wheat fields are drawn by two layers behind this node, so the wheat can have a shader of its own that frays its edges.
var _floor := Node2D.new()
var _wheat := Node2D.new()


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
	ravine_edge = load("res://assets/ravine_edge.png")
	ice = load("res://assets/ice.png")
	# The ravine lip repeats along each gorge; every other picture is drawn inside its own rectangle, so repeating changes nothing for it.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	for layer in [_floor, _wheat]:
		layer.show_behind_parent = true
		add_child(layer)
	_floor.draw.connect(_draw_floor)
	var fray := ShaderMaterial.new()
	fray.shader = load("res://scripts/wheat_field.gdshader")
	_wheat.material = fray
	_wheat.draw.connect(_draw_fields)


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
			# Neptune's earthquake shakes the screen harder than any blow.
			var reach := int(sim.b.gods.neptune.shake_pixels) if sim.gods.quake > 0.0 else int(sim.b.shake.pixels)
			jolt = Vector2(_shake_rng.randi_range(-reach, reach), _shake_rng.randi_range(-reach, reach))
		# The shake dies away here, not in the sim, so it still ends while the run is paused or over.
		sim.shake = maxf(0.0, sim.shake - dt)
		sim.gods.quake = maxf(0.0, sim.gods.quake - dt)
		position = (get_viewport_rect().size / 2.0 - sim.commander.pos).round() + jolt
		queue_redraw()
		_floor.queue_redraw()
		_wheat.queue_redraw()


func _add(y: float, rect: Rect2, dest: Vector2, mod: Color, moving := false, size := Vector2.ZERO) -> void:
	_keys.append((int(y) + 100000) * 65536 + _rects.size())
	_rects.append(rect)
	_dests.append(_snap(dest) if moving else dest.round())
	_mods.append(mod)
	_sizes.append(rect.size if size == Vector2.ZERO else size)


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
	_draw_ravines(view_for(top_left).grow(80.0))
	_draw_fort_ring(view_for(top_left))
	_draw_ground_zones(view_for(top_left))
	_draw_god_ground()
	_draw_scorch(view_for(top_left))
	_draw_warnings()
	_keys.clear()
	_rects.clear()
	_dests.clear()
	_mods.clear()
	_sizes.clear()
	var white := Color.WHITE
	var margin := 80.0
	var view := Rect2(top_left - Vector2(margin, margin), screen + Vector2(margin, margin) * 2.0)

	# Half see-through, so the tree still reads as a tree over the commander.
	var see_through := Color(1, 1, 1, 0.5)
	var him := Rect2(cam - Vector2(5, 26), Vector2(10, 26))
	var chops: Dictionary = sim.terrain.chops
	var shaking := float(sim.b.felling.shake_seconds)
	_felling.clear()
	# The chunks are read in place, in the order props_in() would join them.
	for cx in range(floori(view.position.x / Terrain.CHUNK), floori(view.end.x / Terrain.CHUNK) + 1):
		for cy in range(floori(view.position.y / Terrain.CHUNK), floori(view.end.y / Terrain.CHUNK) + 1):
			for pr in sim.terrain.chunk(cx, cy):
				# A piece with no kind is an unseen blocker, such as the inside of the fort's gate towers.
				if pr[0] == "":
					continue
				var f: Array = _prop_frames.get(pr[0], [])
				if f.is_empty():
					f = atlas.prop_frame(pr[0])
					_prop_frames[pr[0]] = f
				var at: Vector2 = pr[1]
				if pr[0] == "dune" or pr[0] == "bog" or pr[0] == "heather":
					# Dunes, bog pools and heather are walked over, so they are drawn on the ground under everything that stands on them.
					_add(at.y - 60000.0, f[0], at - f[1], white)
					continue
				if not chops.is_empty() and chops.has(at) and sim.time - float(chops[at][1]) < shaking:
					_felling.append([at, float(chops[at][0])])
					at += Vector2(roundf(sin(sim.time * 45.0 + at.x) * 1.2), 0)
				var mod := white
				# A tree standing in front of the commander is seen through, so he is not lost once the legion cuts into a ridge.
				# Only the middle of the picture counts, since the empty margins round a canopy hide nothing.
				if pr[2] > 0.0 and at.y > cam.y and _solid_part(Rect2(at - f[1], f[0].size)).intersects(him):
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
	var cursed := Color(0.78, 0.55, 1.0)
	var stunned := Color(0.78, 0.74, 0.62)
	var cheering := sim.triumph_left > 0.0
	_dazed.clear()
	_train_marks.clear()
	for u in [sim.commander] + sim.soldiers:
		var f := _cheer_frame(u) if cheering and not u.moving else _legion_frame(u)
		var mod := white
		if u.get("dazed", 0.0) > 0.0:
			_dazed.append(u.pos)
		if u.flash > 0.0:
			mod = Color(1.0, 0.55, 0.55)
		elif sim.horde.curse_left > 0.0:
			mod = cursed
		elif u.get("afraid", 0.0) > 0.0:
			mod = Color(0.72, 0.8, 1.0)
		elif sim.horde.blast_left > 0.0:
			mod = stunned
		elif sim.testudo_left > 0.0:
			mod = gold
		draw_texture(shadow, _snap(u.pos - Vector2(8, 3)))
		var hop := Vector2.ZERO
		if cheering and not u.moving:
			hop.y = -absf(sin(sim.triumph_t * float(sim.b.triumph.cheer) + float(u.anim))) * float(sim.b.triumph.hop)
		_add(u.pos.y, f[0], u.pos - f[1] + hop, mod, true)

	if _kinds_of != sim:
		_index_kinds()
	var h: Horde = sim.horde
	var strike_secs := Atlas.ATTACK_FRAMES / Atlas.ATTACK_FPS
	var loop_t := sim.time * Atlas.ATTACK_FPS
	for i in h.e_pos.size():
		var p: Vector2 = h.e_pos[i]
		if not view.has_point(p):
			continue
		var kind := h.e_kind[i]
		var slot := kind * 24 + Sim.dir_index(h.e_face[i])
		var fi: int
		var since := sim.time - h.e_strike[i]
		if _k_attack[kind] == 1 and since >= 0.0 and since < strike_secs:
			slot += 8
			fi = int(since * Atlas.ATTACK_FPS)
		# The chieftain's blows are his cleave and slam, so only lesser men swing on and on while locked in melee.
		elif _k_attack[kind] == 1 and h.e_fighting[i] == 1 and h.e_tag[i] != Horde.CHIEF:
			slot += 8
			fi = posmod(int(loop_t + h.e_phase[i]), _f_count[slot])
		elif (h.e_fighting[i] == 1 or h.e_pace[i] < Horde.STILL_PACE) and _f_count[slot + 16] > 0:
			# A barbarian held in place, or fighting between blows with no swing of his own, shows his stance instead of a frozen stride.
			slot += 16
			fi = 0
		else:
			fi = posmod(int(sim.time * 11.0 + h.e_phase[i] if h.e_fighting[i] == 0 else float(h.e_phase[i])), _f_count[slot])
		var rect := _f_rect[_f_start[slot] + fi]
		var anchor := _f_anchor[slot]
		var mod := white
		if h.e_flash[i] > 0.0:
			mod = Color(1.0, 0.5, 0.45)
		elif h.e_fury[i] > 1.0:
			mod = Color(1.0, 0.42 + 0.12 * sin(sim.time * 10.0), 0.36)
		elif h.e_burn[i] > 0.0:
			mod = Color(1.0, 0.78, 0.6)
		var sw := _k_shadow[kind]
		if sw <= 16.0:
			draw_texture(shadow, _snap(p - Vector2(8, 3)))
		else:
			draw_texture_rect(shadow, Rect2(_snap(p - Vector2(sw / 2.0, sw * 0.1875)), Vector2(sw, sw * 0.375)), false)
		var sc := _k_scale[kind]
		if sc != 1.0:
			_add(p.y, rect, p - anchor * sc, mod, true, rect.size * sc)
		else:
			_add(p.y, rect, p - anchor, mod, true)
		if not h.arrow_storm.is_empty() and h.arrow_storm.train.has(h.e_id[i]):
			_train_marks.append(p)

	for e in sim.effects:
		if e.kind == "death" or e.kind == "fallen":
			var f := atlas.unit_frame(e.type, "idle", Sim.dir_name(e.facing), 0.0)
			var a: float = 1.0 - e.t / 0.45
			var sc := _scale_of(e.type)
			_add(e.pos.y, f[0], e.pos - f[1] * sc + Vector2(0, e.t * 8.0), Color(0.75, 0.35, 0.3, a), false, f[0].size * sc)
		elif e.kind == "plunge":
			# The body shrinks and darkens as it drops into the gorge; a boss shudders at the lip first.
			var f := atlas.unit_frame(e.type, "idle", Sim.dir_name(e.facing), 0.0)
			var k: float = e.t / Sim.PLUNGE_SECONDS
			var rect: Rect2 = f[0]
			var size := rect.size * (1.0 - 0.8 * k)
			var into: Vector2 = e.get("into", Vector2(0, 30))
			var mid: Vector2 = e.pos - f[1] + rect.size / 2.0 + into * k * k
			if e.get("big", false):
				mid.x += sin(e.t * 70.0) * 3.0 * (1.0 - k)
			_add(mid.y, rect, mid - size / 2.0, Color(0.9 - 0.85 * k, 0.8 - 0.76 * k, 0.75 - 0.71 * k, 1.0 - k * k * k), false, size)

	_add_arm_sprites(view)
	_add_chests_and_carts(view)
	_add_objectives(view)
	_add_flames(view)
	_draw_coins(view)
	_keys.sort()
	var tex := atlas.texture
	for key in _keys:
		var idx := int(key % 65536)
		draw_texture_rect_region(tex, Rect2(_dests[idx], _sizes[idx]), _rects[idx], _mods[idx])

	_draw_shots(tex)
	_draw_spears()
	_draw_dazed_and_trains()
	_draw_boss_heads(view)
	_draw_lobs(tex)
	_draw_effects()
	_draw_triumph_wave()
	_draw_objective_marks(view)
	_draw_numbers()
	_draw_torches()
	_draw_bars()
	_draw_felling()
	_draw_gods(top_left, screen)


## A legion soldier's frame: his attack while a strike plays, otherwise his walk or stance.
func _legion_frame(u: Dictionary) -> Array:
	var since: float = sim.time - float(u.get("struck_at", -1e9))
	if since < Atlas.ATTACK_FRAMES / Atlas.ATTACK_FPS:
		var f := atlas.attack_frame(u.type, Sim.dir_name(u.strike_dir), since)
		if not f.is_empty():
			return f
	return atlas.unit_frame(u.type, "move" if u.moving else "idle", Sim.dir_name(u.facing), u.anim)


## The province's ground repeated under the whole screen.
func _draw_floor() -> void:
	if not sim:
		return
	var screen := get_viewport_rect().size
	var top_left: Vector2 = sim.commander.pos - screen / 2.0
	if sim.province != _ground_of:
		_ground_of = sim.province
		ground = load(Content.ground_path(_ground_of))
	var gw := ground.get_width()
	var gh := ground.get_height()
	var gx0 := floori(top_left.x / gw)
	var gy0 := floori(top_left.y / gh)
	for gx in range(gx0, gx0 + ceili(screen.x / gw) + 2):
		for gy in range(gy0, gy0 + ceili(screen.y / gh) + 2):
			_floor.draw_texture(ground, Vector2(gx * gw, gy * gh))


## Gaul's wheat fields: the wheat tile repeated over each field, lined up with the world so neighbouring fields share their rows.
## The tile is laid a little past each field and wheat_field.gdshader thins it out towards a wavering edge.
func _draw_fields() -> void:
	if not sim:
		return
	var cam: Vector2 = sim.commander.pos
	var view := view_for(cam - get_viewport_rect().size / 2.0)
	var fields := sim.terrain.fields_in(view.grow(FIELD_FRAY * 4.0))
	if fields.is_empty() or not atlas.props.has("wheat_field"):
		return
	var shapes := PackedVector4Array()
	for f in fields:
		if shapes.size() < FIELD_SHAPES:
			shapes.append(_field_shape(f, fields))
	_wheat.material.set_shader_parameter("fields", shapes)
	_wheat.material.set_shader_parameter("count", shapes.size())
	var src: Rect2 = atlas.prop_frame("wheat_field")[0]
	var tw := src.size.x
	var th := src.size.y
	for f in fields:
		var area: Rect2 = f.grow(FIELD_FRAY).intersection(view)
		for tx in range(floori(area.position.x / tw), floori((area.end.x - 0.01) / tw) + 1):
			for ty in range(floori(area.position.y / th), floori((area.end.y - 0.01) / th) + 1):
				var tile := Rect2(tx * tw, ty * th, tw, th).intersection(area)
				if tile.size.x <= 0.0 or tile.size.y <= 0.0:
					continue
				_wheat.draw_texture_rect_region(atlas.texture, tile, Rect2(src.position + tile.position - Vector2(tx * tw, ty * th), tile.size))


## A field as the shader's x, y, width, height, pushed into any field whose side it lies along, so the seam of an L-shaped field gets no edge.
func _field_shape(f: Rect2, fields: Array) -> Vector4:
	var r := f
	for g: Rect2 in fields:
		if g == f:
			continue
		var along_y := f.position.y >= g.position.y - 0.5 and f.end.y <= g.end.y + 0.5
		var along_x := f.position.x >= g.position.x - 0.5 and f.end.x <= g.end.x + 0.5
		if along_y and absf(f.position.x - g.end.x) < 0.5:
			r = r.grow_individual(FIELD_FRAY * 3.0, 0, 0, 0)
		elif along_y and absf(f.end.x - g.position.x) < 0.5:
			r = r.grow_individual(0, 0, FIELD_FRAY * 3.0, 0)
		elif along_x and absf(f.position.y - g.end.y) < 0.5:
			r = r.grow_individual(0, FIELD_FRAY * 3.0, 0, 0)
		elif along_x and absf(f.end.y - g.position.y) < 0.5:
			r = r.grow_individual(0, 0, 0, FIELD_FRAY * 3.0)
	return Vector4(r.position.x, r.position.y, r.size.x, r.size.y)


## The gold ring of the triumph running out from the commander, with a second fainter one behind it.
func _draw_triumph_wave() -> void:
	if sim.triumph_left <= 0.0:
		return
	var reach := sim.triumph_t * float(sim.b.triumph.wave_speed)
	if reach > 700.0:
		return
	var a := clampf(1.0 - reach / 700.0, 0.0, 1.0)
	draw_arc(sim.commander.pos, reach, 0.0, TAU, 96, Color(1.0, 0.89, 0.59, a), 3.0)
	if reach > 30.0:
		draw_arc(sim.commander.pos, reach - 24.0, 0.0, TAU, 96, Color(0.91, 0.69, 0.25, a * 0.5), 2.0)


## A soldier cheering the win: he turns to the front and swings his weapon or raises his shield again and again, each in his own time.
func _cheer_frame(u: Dictionary) -> Array:
	var period := Atlas.ATTACK_FRAMES / Atlas.ATTACK_FPS * 1.6
	var f := atlas.attack_frame(u.type, "south", fmod(sim.triumph_t + float(u.anim) * 0.37, period))
	if not f.is_empty():
		return f
	return atlas.unit_frame(u.type, "idle", "south", 0.0)


func _index_kinds() -> void:
	_kinds_of = sim
	var h: Horde = sim.horde
	_k_type.resize(h.kind_ids.size())
	_k_attack.resize(h.kind_ids.size())
	_k_shadow.resize(h.kind_ids.size())
	_k_scale.resize(h.kind_ids.size())
	for k in h.kind_ids.size():
		_k_type[k] = h.kind_ids[k]
		_k_attack[k] = 1 if atlas.units.has(h.kind_ids[k]) and atlas.units[h.kind_ids[k]].has("attack") else 0
		# A small barbarian keeps the 16 px shadow; a boss's grows with his body.
		_k_shadow[k] = maxf(16.0, h.k_radius[k] * 2.4)
		_k_scale[k] = _scale_of(h.kind_ids[k])
	var slots := h.kind_ids.size() * 24
	_f_start.resize(slots)
	_f_count.resize(slots)
	_f_anchor.resize(slots)
	_f_rect.clear()
	for k in h.kind_ids.size():
		var unit: Dictionary = atlas.units.get(h.kind_ids[k], {})
		for a in 3:
			var action: String = ["move", "attack", "idle"][a]
			for d in 8:
				var slot := (k * 3 + a) * 8 + d
				_f_start[slot] = _f_rect.size()
				_f_count[slot] = 0
				if not unit.has(action):
					continue
				var anim: Dictionary = unit[action][Sim.DIRS[d]]
				for f in anim.frames:
					_f_rect.append(Rect2(f[0], f[1], f[2], f[3]))
				_f_count[slot] = anim.frames.size()
				_f_anchor[slot] = Vector2(anim.anchor[0], anim.anchor[1])


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
			var f := atlas.attack_frame("war_dog", Sim.dir_name(d.face), sim.time - float(d.bit))
			if f.is_empty():
				f = atlas.unit_frame("war_dog", action, Sim.dir_name(d.face), d.run * 12.0)
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
		if l.get("rock", false):
			# A rock falls from the heights onto its ring.
			var fall: float = clampf(l.t / l.dur, 0.0, 1.0)
			_lob_sprite(tex, "rock", l.to + Vector2(0, -(1.0 - fall * fall) * 220.0 + 10.0))
			continue
		if l.get("slam", false) or l.get("sky", false):
			continue
		var k: float = l.t / l.dur
		var ground: Vector2 = l.from.lerp(l.to, k)
		if l.get("volley", false):
			# A volley is three arrows flying high, each pointing along its arc.
			var dark := Color(0.2, 0.13, 0.08)
			for n in 3:
				var g2: Vector2 = ground + Vector2((n - 1) * 4.0, (n % 2) * 3.0)
				var at: Vector2 = g2 + Vector2(0, -sin(k * PI) * 60.0)
				var ahead: Vector2 = (l.to - l.from).normalized() + Vector2(0, -cos(k * PI) * 2.0)
				draw_line(at, at + ahead.normalized() * 6.0, dark, 1.0)
			continue
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
	for id in h.boss:
		var st: Dictionary = h.boss[id]
		if st.get("rush_warn", 0.0) > 0.0:
			_draw_lane(st.rush_from, st.rush_dir, st.rush_len, st.rush_width, clampf(1.0 - st.rush_warn / st.rush_total, 0.0, 1.0))
	if not h.sweep.is_empty():
		var k: float = clampf(h.sweep.t / h.sweep.dur, 0.0, 1.0)
		var a: float = h.sweep.dir.angle()
		var half: float = h.sweep.arc / 2.0
		var cone := PackedVector2Array([h.sweep.pos])
		var fill := PackedVector2Array([h.sweep.pos])
		for n in 17:
			var ang: float = a - half + h.sweep.arc * n / 16.0
			cone.append(h.sweep.pos + Vector2.from_angle(ang) * h.sweep.reach)
			fill.append(h.sweep.pos + Vector2.from_angle(ang) * h.sweep.reach * maxf(k, 0.05))
		draw_colored_polygon(cone, Color(0.75, 0.12, 0.08, 0.12 + 0.18 * k))
		draw_colored_polygon(fill, Color(0.95, 0.35, 0.15, 0.25))
		cone.append(h.sweep.pos)
		draw_polyline(cone, Color(0.95, 0.25, 0.15, 0.85), 1.0)
	if not h.drive.is_empty() and h.drive.t < h.drive.warn:
		_draw_path(h.drive.pts, h.drive.lens, h.drive.width, clampf(h.drive.t / h.drive.warn, 0.0, 1.0))
	for st in h.storms:
		_draw_storm(st)
	for l in sim.horde.foe_lobs:
		var k: float = clampf(l.t / l.dur, 0.0, 1.0)
		if l.get("sky", false):
			# Fire from the sky is marked by an orange ring with a glow gathering over it.
			draw_circle(l.to, l.radius, Color(0.85, 0.35, 0.05, 0.14 + 0.2 * k))
			draw_arc(l.to, l.radius, 0.0, TAU, 32, Color(1.0, 0.6, 0.15, 0.9), 1.0)
			draw_circle(l.to, l.radius * k, Color(1.0, 0.7, 0.25, 0.3))
			draw_circle(l.to + Vector2(0, -60.0 * (1.0 - k)), 3.0 + 3.0 * k, Color(1.0, 0.8, 0.35, 0.4 + 0.5 * k))
			continue
		draw_circle(l.to, l.radius, Color(0.75, 0.12, 0.08, 0.12 + 0.18 * k))
		draw_arc(l.to, l.radius, 0.0, TAU, 32, Color(0.95, 0.25, 0.15, 0.85), 1.0)
		draw_circle(l.to, l.radius * k, Color(0.95, 0.35, 0.15, 0.25))
	for m in h.marks:
		var k: float = clampf(m.t / m.dur, 0.0, 1.0)
		var at: Vector2 = m.pos
		if m.kind == "mend":
			var pi := h.e_id.find(m.id)
			if pi >= 0:
				at = h.e_pos[pi]
			draw_circle(at, m.radius, Color(0.2, 0.75, 0.3, 0.06 + 0.1 * k))
			draw_arc(at, m.radius, 0.0, TAU, 64, Color(0.45, 1.0, 0.5, 0.9), 1.0)
			draw_arc(at, m.radius * k, 0.0, TAU, 64, Color(0.6, 1.0, 0.6, 0.8), 2.0)
		elif m.kind == "fire":
			draw_circle(at, m.radius, Color(0.75, 0.25, 0.05, 0.12 + 0.18 * k))
			draw_arc(at, m.radius, 0.0, TAU, 40, Color(1.0, 0.55, 0.15, 0.95), 1.0)
			draw_circle(at, m.radius * k, Color(1.0, 0.5, 0.15, 0.3))
		elif m.kind == "blizzard":
			draw_circle(at, m.radius, Color(0.75, 0.88, 1.0, 0.12 + 0.18 * k))
			draw_arc(at, m.radius, 0.0, TAU, 48, Color(0.85, 0.95, 1.0, 0.95), 1.0)
			draw_circle(at, m.radius * k, Color(0.9, 0.96, 1.0, 0.3))
		else:
			draw_circle(at, m.radius, Color(0.45, 0.12, 0.6, 0.15 + 0.2 * k))
			draw_arc(at, m.radius, 0.0, TAU, 40, Color(0.8, 0.45, 1.0, 0.95), 1.0)
			draw_circle(at, m.radius * k, Color(0.7, 0.3, 0.95, 0.3))
			for n in 3:
				var a := sim.time * 2.0 + n * TAU / 3.0
				draw_arc(at, m.radius * 0.6, a, a + 1.2, 8, Color(0.85, 0.55, 1.0, 0.8), 1.0)


## The lane of a coming charge, filling from where it starts as it nears.
func _draw_lane(from: Vector2, dir: Vector2, length: float, width: float, k: float) -> void:
	var end := from + dir * length
	var edge := dir.orthogonal() * width / 2.0
	draw_line(from, end, Color(0.75, 0.12, 0.08, 0.12 + 0.18 * k), width)
	draw_line(from + edge, end + edge, Color(0.95, 0.25, 0.15, 0.85), 1.0)
	draw_line(from - edge, end - edge, Color(0.95, 0.25, 0.15, 0.85), 1.0)
	draw_line(end + edge, end - edge, Color(0.95, 0.25, 0.15, 0.85), 1.0)
	draw_line(from, from.lerp(end, k), Color(0.95, 0.35, 0.15, 0.25), width)


## A curved charge path, drawn like a lane along each of its pieces and filling from where it starts as it nears.
func _draw_path(pts: PackedVector2Array, lens: PackedFloat32Array, width: float, k: float) -> void:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for n in pts.size():
		var along: Vector2 = (pts[mini(n + 1, pts.size() - 1)] - pts[maxi(n - 1, 0)]).normalized()
		left.append(pts[n] + along.orthogonal() * width / 2.0)
		right.append(pts[n] - along.orthogonal() * width / 2.0)
	draw_polyline(pts, Color(0.75, 0.12, 0.08, 0.12 + 0.18 * k), width)
	draw_polyline(left, Color(0.95, 0.25, 0.15, 0.85), 1.0)
	draw_polyline(right, Color(0.95, 0.25, 0.15, 0.85), 1.0)
	draw_line(left[left.size() - 1], right[right.size() - 1], Color(0.95, 0.25, 0.15, 0.85), 1.0)
	var reach := lens[lens.size() - 1] * k
	var filled := PackedVector2Array([pts[0]])
	for n in range(1, pts.size()):
		if lens[n] <= reach:
			filled.append(pts[n])
		else:
			filled.append(pts[n - 1].lerp(pts[n], (reach - lens[n - 1]) / maxf(lens[n] - lens[n - 1], 0.001)))
			break
	if filled.size() > 1:
		draw_polyline(filled, Color(0.95, 0.35, 0.15, 0.25), width)


## A priest's blizzard: a pale ring of driving snow, fading in and out. The warrior queen's burning land is a scorched ring of flickering fire.
func _draw_storm(st: Dictionary) -> void:
	var fade: float = clampf((st.life - st.t) / 1.0, 0.0, 1.0) * clampf(st.t / 0.3, 0.0, 1.0)
	var p: Vector2 = st.pos
	var r: float = st.radius
	if st.get("fire", false):
		var beat := int(sim.time * 10.0)
		draw_circle(p, r, Color(0.2, 0.07, 0.03, 0.5 * fade))
		draw_arc(p, r, 0.0, TAU, 48, Color(1.0, 0.45, 0.1, 0.7 * fade), 1.0)
		var n := int(r / 2.5) + 3
		for i in n:
			var a := i * 2.4
			var d := r * sqrt((i + 0.5) / n) * 0.92
			var base := p + Vector2(cos(a) * d, sin(a) * d)
			var h := 2 + (beat + i * 3) % 4
			draw_rect(Rect2(base.round() + Vector2(0, -h), Vector2(2, h)), Color(1.0, 0.5, 0.12, 0.9 * fade))
			draw_rect(Rect2(base.round() + Vector2(0, -h + 1), Vector2(1, maxi(1, h - 2))), Color(1.0, 0.86, 0.35, 0.9 * fade))
		return
	draw_circle(p, r, Color(0.82, 0.9, 1.0, 0.22 * fade))
	draw_arc(p, r, 0.0, TAU, 48, Color(0.92, 0.97, 1.0, 0.8 * fade), 1.0)
	for n in 3:
		var a: float = -sim.time * 2.5 + n * TAU / 3.0
		draw_arc(p, r * 0.7, a, a + 1.0, 8, Color(1.0, 1.0, 1.0, 0.6 * fade), 1.0)
	for n in 28:
		var a := float(n) * 2.39996
		var d := r * sqrt((n + 0.5) / 28.0)
		var drift := fmod(sim.time * (30.0 + n % 5 * 6.0) + n * 13.0, 24.0)
		var q := p + Vector2(cos(a) * d - drift * 0.5, sin(a) * d + drift - 12.0)
		if q.distance_to(p) < r:
			draw_rect(Rect2(q.round(), Vector2(1, 1)), Color(1.0, 1.0, 1.0, 0.9 * fade))


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
				_add(cart.pos.y, f[0], cart.pos - f[1], Color(1, 1, 1, sim.horde.cart_alpha(cart)))


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
				var fade := sim.objectives.cart_alpha(o, sim.time)
				if fade > 0.0:
					_add_prop("supply_cart", o.pos, Color(1, 1, 1, fade))
				for g in o.guards:
					var f := _legion_frame(g)
					draw_texture(shadow, (g.pos - Vector2(8, 3)).round())
					_add(g.pos.y, f[0], g.pos - f[1], Color(1.0, 0.55, 0.55) if g.flash > 0.0 else Color.WHITE)
			"grove":
				_add_prop("altar", o.pos, Color(0.45, 0.4, 0.38) if o.done else Color.WHITE)


func _add_prop(key: String, pos: Vector2, mod: Color) -> void:
	if atlas.props.has(key):
		var f := atlas.prop_frame(key)
		_add(pos.y, f[0], pos - f[1], mod)


## The grove's ring filling while the commander holds it.
func _draw_objective_marks(view: Rect2) -> void:
	var cfg: Dictionary = sim.b.objectives.grove
	for o in sim.objectives.list:
		if o.kind == "grove" and not o.done and view.grow(120.0).has_point(o.pos):
			_hold_ring(o.pos, float(cfg.inside), o.hold / float(cfg.hold))


## The fort's ring on the ground of its yard, under the walls and towers, filling while the commander holds it.
func _draw_fort_ring(view: Rect2) -> void:
	var fort: Dictionary = sim.objectives.fort
	if not fort.is_empty() and not sim.objectives.fort_reached and view.grow(120.0).has_point(fort.centre):
		_hold_ring(fort.centre, float(fort.half) * 0.7, float(fort.hold) / float(sim.b.fort.hold))


## A faint ring round a place to hold, filling clockwise from the top as the hold goes on.
func _hold_ring(at: Vector2, radius: float, k: float) -> void:
	draw_arc(at, radius, 0.0, TAU, 48, Color(1.0, 0.89, 0.59, 0.35), 1.0)
	if k > 0.0:
		k = clampf(k, 0.0, 1.0)
		draw_arc(at, radius, -PI / 2.0, -PI / 2.0 + TAU * k, 48, Color(0.16, 0.1, 0.08, 0.8), 4.0)
		draw_arc(at, radius, -PI / 2.0, -PI / 2.0 + TAU * k, 48, Color(1.0, 0.6, 0.18), 2.0)


## The flames on the camp's burning huts and the grove's burning oaks and altar, sorted with the sprites so soldiers in front stand over them.
func _add_flames(view: Rect2) -> void:
	if not atlas.props.has("flame"):
		return
	var cfg: Dictionary = sim.b.objectives.grove
	for n in sim.horde.storms.size():
		var st: Dictionary = sim.horde.storms[n]
		if not st.get("fire", false) or not view.grow(st.radius).has_point(st.pos):
			continue
		var fade: float = clampf((st.life - st.t) / 1.0, 0.0, 1.0) * clampf(st.t / 0.3, 0.0, 1.0)
		for k in 5:
			var off: Vector2 = Vector2.from_angle(k * 2.4 + n) * st.radius * (0.25 + 0.15 * k) * Vector2(1.0, 0.7)
			_add_flame(st.pos + off, Vector2.ZERO, n * 5 + k, k, fade)
	for o in sim.objectives.list:
		if not view.grow(120.0).has_point(o.pos):
			continue
		if o.kind == "camp" and o.burnt_at >= 0.0 and not o.razed:
			var left := float(sim.b.objectives.camp.burn_seconds) - (sim.time - float(o.burnt_at))
			for i in o.huts.size():
				for k in 3:
					_add_flame(o.huts[i], [Vector2(-12, -14), Vector2(0, -22), Vector2(12, -12)][k], i, k, clampf(left / 1.5, 0.0, 1.0))
		elif o.kind == "grove" and o.done and sim.time - o.burnt_at < float(cfg.burn_seconds):
			var fade := clampf((float(cfg.burn_seconds) - (sim.time - o.burnt_at)) / 2.0, 0.0, 1.0)
			for i in o.oaks.size():
				_add_flame(o.oaks[i], Vector2(0, -30), i, 0, fade)
			_add_flame(o.pos, Vector2(0, -8), o.oaks.size(), 0, fade)


## One flame of the atlas's flickering sheet at `ground` + `at`, sorted just in front of the thing standing at `ground`.
## The part of a tree's picture that is canopy and trunk: a fifth in from each side and a tenth down from the top.
static func _solid_part(r: Rect2) -> Rect2:
	return Rect2(r.position + Vector2(r.size.x * 0.2, r.size.y * 0.1), Vector2(r.size.x * 0.6, r.size.y * 0.9))


func _add_flame(ground: Vector2, at: Vector2, seed_i: int, k: int, fade: float) -> void:
	var fl: Dictionary = atlas.props.flame
	var f: Array = fl.frames[(int(sim.time * 10.0) + seed_i * 3 + k) % fl.frames.size()]
	var anchor := Vector2(fl.anchor[0], fl.anchor[1])
	_add(ground.y + 1.0, Rect2(f[0], f[1], f[2], f[3]), ground + at - anchor, Color(1, 1, 1, fade))


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


## Axes thrown by the horde spin end over end, drawn large and outlined so they read like the archers' arrows.
func _draw_spears() -> void:
	var h: Horde = sim.horde
	var ink := Color(0.16, 0.1, 0.08)
	for i in h.sp_pos.size():
		var p: Vector2 = h.sp_pos[i]
		var dir: Vector2 = h.sp_vel[i].normalized()
		if h.sp_kind[i] == 1:
			# The Dacian archers' arrows are fletched dark red, so they never pass for the legion's own.
			_big_shot(p, dir, 16.0, false, Color(0.32, 0.2, 0.12), Color(0.62, 0.16, 0.12))
			continue
		if h.sp_kind[i] == 2:
			# A sling stone is a small grey pebble with a faint trail.
			draw_line(p - dir * 10.0, p - dir * 2.0, Color(1.0, 1.0, 0.9, 0.2), 2.0)
			draw_rect(Rect2(p.round() - Vector2(1, 1), Vector2(3, 3)), ink)
			draw_rect(Rect2(p.round() - Vector2(1, 1), Vector2(2, 2)), Color(0.72, 0.7, 0.66))
			continue
		draw_line(p - dir * 20.0, p - dir * 4.0, Color(1.0, 1.0, 0.85, 0.22), 4.0)
		var spin := Vector2.from_angle(sim.time * 18.0 + float(i) * 1.7)
		var side := spin.orthogonal()
		var butt := p - spin * 7.0
		var head := p + spin * 6.0
		draw_line(butt, head, ink, 4.0)
		draw_line(butt, head, Color(0.55, 0.36, 0.2), 2.0)
		var blade := PackedVector2Array([head + side * 1.0, head + side * 6.0 + spin * 3.0, head + side * 7.0 - spin * 3.0, head - spin * 2.0])
		draw_colored_polygon(blade, ink)
		var inner := PackedVector2Array([head + side * 1.5, head + side * 5.0 + spin * 1.8, head + side * 5.5 - spin * 1.8, head - spin * 1.0])
		draw_colored_polygon(inner, Color(0.85, 0.86, 0.88))


## How much larger than its art an enemy kind is drawn; 1 for every other kind and for the legion's soldiers.
func _scale_of(type: String) -> float:
	return float(sim.content.enemies.get(type, {}).get("scale", 1.0))


## Spinning stars over a soldier reeling from a sling stone, and a bundle of arrows over each camel of a train bringing them.
func _draw_dazed_and_trains() -> void:
	for p in _dazed:
		for n in 3:
			var a := sim.time * 6.0 + n * TAU / 3.0
			var q := (p + Vector2(cos(a) * 7.0, -32.0 + sin(a) * 2.0)).round()
			draw_rect(Rect2(q - Vector2(2, 1), Vector2(5, 3)), Color(0.16, 0.1, 0.08))
			draw_rect(Rect2(q - Vector2(1, 2), Vector2(3, 5)), Color(0.16, 0.1, 0.08))
			draw_rect(Rect2(q - Vector2(1, 0), Vector2(3, 1)), Color(1.0, 0.9, 0.4))
			draw_rect(Rect2(q - Vector2(0, 1), Vector2(1, 3)), Color(1.0, 0.9, 0.4))
	for p in _train_marks:
		var top := (p + Vector2(-3, -40)).round()
		draw_rect(Rect2(top - Vector2(1, 1), Vector2(8, 10)), Color(0.16, 0.1, 0.08))
		for k in 3:
			draw_line(top + Vector2(k * 2 + 1, 0), top + Vector2(k * 2 + 1, 8), Color(0.85, 0.7, 0.4), 1.0)
		draw_rect(Rect2(top + Vector2(0, 7), Vector2(6, 1)), Color(0.62, 0.16, 0.12))


## Over each boss: a raised shield in front of a war band leader and a health bar; the HUD writes the elite's name over it.
func _draw_boss_heads(view: Rect2) -> void:
	var h: Horde = sim.horde
	var ids: Array = h.elite_ids.duplicate()
	var ci := h.chieftain_index()
	if ci >= 0:
		ids.append(h.e_id[ci])
	for id in ids:
		var i := h.e_id.find(id)
		if i < 0 or not view.has_point(h.e_pos[i]):
			continue
		var type: String = h.kind_ids[h.e_kind[i]]
		var p: Vector2 = h.e_pos[i]
		var tall: float = (atlas.units[type].idle.south.frames[0][3] if atlas.units.has(type) else 40.0) * _scale_of(type)
		var st: Dictionary = h.boss.get(id, {})
		if not st.is_empty() and st.duel > 0.0:
			# The champion's ring, with an arc that shrinks as the duel runs out.
			var left: float = st.duel / float(sim.content.enemies[type].duel.seconds)
			draw_arc(st.duel_at, st.duel_r, 0.0, TAU, 64, Color(0.16, 0.1, 0.08, 0.8), 4.0)
			draw_arc(st.duel_at, st.duel_r, 0.0, TAU, 64, Color(1.0, 0.82, 0.3, 0.9), 2.0)
			draw_arc(st.duel_at, st.duel_r - 4.0, -PI / 2.0, -PI / 2.0 + TAU * left, 48, Color(1.0, 0.95, 0.7, 0.8), 1.0)
		if h.e_tag[i] == Horde.CHIEF and h.sworn_cut > 0.0 and h.guards_alive >= h.sworn_min:
			# While the sworn guard stands the king is wrapped in a pale golden ring.
			var r0 := h.k_radius[h.e_kind[i]] + 10.0
			draw_arc(p + Vector2(0, -tall * 0.35), r0, 0.0, TAU, 40, Color(1.0, 0.85, 0.4, 0.35 + 0.2 * sin(sim.time * 4.0)), 2.0)
		if not st.is_empty() and st.shield > 0.0:
			var a: float = st.shield_dir.angle()
			var half := float(sim.content.enemies[type].shield_wall.arc) / 2.0
			var c := p + Vector2(0, -tall * 0.3)
			var r := h.k_radius[h.e_kind[i]] + 14.0
			draw_arc(c, r, a - half, a + half, 20, Color(0.16, 0.1, 0.08, 0.9), 8.0)
			draw_arc(c, r, a - half, a + half, 20, Color(0.55, 0.85, 1.0), 5.0)
			draw_arc(c, r + 1.0, a - half * 0.85, a + half * 0.85, 16, Color(1.0, 1.0, 0.95), 2.0)
		# The chieftain's health has its own bar under the clock, and his head often stands up there beside it.
		if h.e_tag[i] == Horde.CHIEF:
			continue
		var w := 32.0
		var bar: Vector2 = (p + Vector2(-w / 2.0, -tall - 3.0)).round()
		draw_rect(Rect2(bar - Vector2(1, 1), Vector2(w + 2, 5)), Color(0.16, 0.1, 0.08))
		draw_rect(Rect2(bar, Vector2(w * clampf(h.e_hp[i] / h.e_max[i], 0.0, 1.0), 3)), Color(0.85, 0.22, 0.18))


func _draw_shots(tex: Texture2D) -> void:
	var pil := atlas.prop_frame("pilum")
	for s in sim.shots:
		var dir: Vector2 = s.vel.normalized()
		match s.kind:
			"arrow":
				_big_shot(s.pos, dir, 18.0, s.burn > 0.0, Color(0.55, 0.36, 0.2), Color(0.85, 0.2, 0.15))
			"pilum":
				# The pilum is drawn pointing up and to the right, so it is turned from that angle.
				draw_set_transform(s.pos, dir.angle() + PI / 4.0)
				var r: Rect2 = pil[0]
				draw_texture_rect_region(tex, Rect2(-r.size / 2.0, r.size), r)
				draw_set_transform(Vector2.ZERO)
			"stone":
				draw_line(s.pos - dir * 16.0, s.pos, Color(1.0, 1.0, 0.85, 0.25), 4.0)
				draw_circle(s.pos, 4.0, Color(0.16, 0.1, 0.08))
				draw_circle(s.pos, 3.0, Color(0.68, 0.66, 0.6))
				draw_circle(s.pos + Vector2(-1, -1), 1.2, Color(0.92, 0.9, 0.85))
			"bolt":
				_big_shot(s.pos, dir, 24.0, false, Color(0.36, 0.24, 0.14), Color(0.9, 0.85, 0.75))


## A missile drawn far larger than life, outlined and trailing a streak, so every shot reads in a crowded fight.
func _big_shot(pos: Vector2, dir: Vector2, length: float, fire: bool, wood: Color, feather: Color) -> void:
	var ink := Color(0.16, 0.1, 0.08)
	var side := dir.orthogonal()
	var tail := pos - dir * length
	var neck := pos - dir * 5.0
	if fire:
		var flick := 0.8 + 0.2 * sin(sim.time * 40.0 + pos.x)
		draw_line(tail - dir * 20.0, neck, Color(1.0, 0.45, 0.1, 0.35 * flick), 7.0)
		draw_line(tail - dir * 10.0, neck, Color(1.0, 0.8, 0.3, 0.5 * flick), 3.0)
	else:
		draw_line(tail - dir * 18.0, tail, Color(1.0, 1.0, 0.85, 0.28), 4.0)
	draw_line(tail, neck, ink, 4.0)
	draw_line(tail, neck, wood, 2.0)
	for k in [-1.0, 1.0]:
		draw_line(tail + dir * 5.0, tail - dir * 1.0 + side * 4.0 * k, ink, 3.0)
		draw_line(tail + dir * 5.0, tail - dir * 1.0 + side * 4.0 * k, feather, 1.5)
	draw_colored_polygon(PackedVector2Array([pos + dir * 4.0, neck - dir * 1.0 + side * 4.5, neck - dir * 1.0 - side * 4.5]), ink)
	draw_colored_polygon(PackedVector2Array([pos + dir * 2.5, neck + side * 3.0, neck - side * 3.0]), Color(0.9, 0.9, 0.88))
	if fire:
		draw_circle(pos, 4.5, Color(1.0, 0.6, 0.15, 0.55))
		draw_circle(pos, 2.0, Color(1.0, 0.95, 0.6))


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
		elif e.kind == "whirl":
			var k: float = e.t / 0.45
			for n in 3:
				var a: float = k * TAU * 1.5 + n * TAU / 3.0
				draw_arc(e.pos, e.radius * (0.5 + 0.5 * k), a, a + 1.4, 10, Color(1.0, 0.85, 0.7, 1.0 - k), 2.0)
		elif e.kind == "skyfire":
			# Fire falling from the sky: a column of flame and an orange swirl spreading over the ring.
			var k: float = e.t / 0.45
			draw_circle(e.pos, e.radius * (0.5 + 0.5 * k), Color(1.0, 0.55, 0.12, 0.45 * (1.0 - k)))
			draw_line(e.pos + Vector2(0, -90.0 * (1.0 - k)), e.pos, Color(1.0, 0.8, 0.35, 0.8 * (1.0 - k)), 6.0 * (1.0 - k) + 1.0)
			for n in 3:
				var a: float = k * TAU * 1.5 + n * TAU / 3.0
				draw_arc(e.pos, e.radius * (0.4 + 0.6 * k), a, a + 1.4, 10, Color(1.0, 0.6, 0.15, 1.0 - k), 2.0)
		elif e.kind == "mend":
			var k: float = e.t / 0.45
			draw_arc(e.pos, e.radius * (0.3 + 0.7 * k), 0.0, TAU, 64, Color(0.5, 1.0, 0.55, 1.0 - k), 3.0)
		elif e.kind == "curse":
			var k: float = e.t / 0.45
			draw_circle(e.pos, e.radius * (0.6 + 0.6 * k), Color(0.65, 0.3, 0.95, 0.45 * (1.0 - k)))
		elif e.kind == "volley":
			# Arrows stand in the ground where a volley fell, then fade.
			var k: float = e.t / 0.45
			var col := Color(0.2, 0.13, 0.08, 1.0 - k)
			for n in 5:
				var at: Vector2 = e.pos + Vector2.from_angle(n * 2.4) * e.radius * 0.6 * float(n % 3) / 2.0
				draw_line(at, at + Vector2(1, -5), col, 1.0)
		elif e.kind == "smoke":
			var k: float = e.t / 0.45
			for n in 6:
				var dir := Vector2.from_angle(n * TAU / 6.0 + 0.3)
				draw_circle(e.pos + Vector2(0, -12) + dir * (4.0 + 10.0 * k), 5.0 + 3.0 * k, Color(0.55, 0.53, 0.58, 0.8 * (1.0 - k)))
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


## What the gods leave under the legion: the glow of Mars's frenzy and the pool of Apollo's light.
func _draw_god_ground() -> void:
	var gods := sim.gods
	if gods.frenzy_left > 0.0:
		var fade := clampf(gods.frenzy_left / 0.8, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(sim.time * 9.0)
		for u in [sim.commander] + sim.soldiers:
			var p: Vector2 = u.pos + Vector2(0, -2)
			draw_set_transform(p, 0.0, Vector2(1.0, 0.55))
			draw_circle(Vector2.ZERO, 15.0 + 3.0 * pulse, Color(0.9, 0.15, 0.06, 0.5 * fade))
			draw_circle(Vector2.ZERO, 9.0, Color(1.0, 0.75, 0.25, 0.6 * fade))
		draw_set_transform(Vector2.ZERO)
	if gods.light_left > 0.0:
		var k := gods.light_left / float(sim.b.gods.apollo.light_seconds)
		var r := sim.legion_reach + 40.0
		draw_circle(sim.commander.pos, r * (1.2 - 0.2 * k), Color(1.0, 0.9, 0.45, 0.4 * k))
		draw_circle(sim.commander.pos, r * 0.6, Color(1.0, 0.97, 0.75, 0.45 * k))


## The gods' powers over the field: Jupiter's bolts, Neptune's wave, Vulcan's falling fire, Mars's embers, Apollo's beams and the white flash.
func _draw_gods(top_left: Vector2, screen: Vector2) -> void:
	var gods := sim.gods
	var g: Dictionary = sim.b.gods
	var whole := Rect2(top_left - Vector2(8, 8), screen + Vector2(16, 16))
	if gods.storm_left > 0.0:
		draw_rect(whole, Color(0.04, 0.05, 0.16, 0.4 * clampf(gods.storm_left / 0.5, 0.0, 1.0)))
	if not gods.wave.is_empty():
		var k := minf(1.0, float(gods.wave.t) / float(g.neptune.wave_seconds))
		var r := float(g.neptune.radius) * k
		var c: Vector2 = gods.wave.pos
		draw_circle(c, r, Color(0.35, 0.6, 0.9, 0.16 * (1.0 - k)))
		draw_arc(c, r - 6.0, 0.0, TAU, 96, Color(0.25, 0.18, 0.1, 0.6 * (1.0 - k * 0.5)), 20.0)
		draw_arc(c, r, 0.0, TAU, 96, Color(0.45, 0.75, 1.0, 1.0 - k * 0.5), 9.0)
		draw_arc(c, r + 2.0, 0.0, TAU, 96, Color(0.95, 1.0, 1.0, 1.0 - k * 0.5), 3.0)
		draw_arc(c, r * 0.85, 0.0, TAU, 96, Color(0.85, 0.95, 1.0, 0.8 * (1.0 - k)), 2.0)
		draw_arc(c, r * 0.6, 0.0, TAU, 96, Color(0.5, 0.75, 1.0, 0.5 * (1.0 - k)), 2.0)
		# Cracks run out across the ground behind the wave.
		for i in 14:
			var dir := Vector2.from_angle(i * TAU / 14.0 + 0.3)
			var side := dir.orthogonal() * (6.0 if i % 2 == 0 else -6.0)
			var pts := PackedVector2Array([c + dir * 20.0, c + dir * r * 0.35 + side, c + dir * r * 0.65 - side, c + dir * r * 0.9])
			draw_polyline(pts, Color(0.2, 0.13, 0.07, 0.7 * (1.0 - k * 0.5)), 2.0)
	if gods.burn_left > 0.0:
		var heat := clampf(gods.burn_left / 1.0, 0.0, 1.0) * 0.16
		draw_rect(Rect2(top_left, screen), Color(1.0, 0.35, 0.05, heat))
	for m in gods.meteors:
		if m.t < 0.0:
			continue
		var k: float = m.t / float(g.vulcan.fall_seconds)
		var from: Vector2 = m.to + Vector2(-90.0, -280.0)
		var p: Vector2 = from.lerp(m.to, k)
		var back: Vector2 = from.lerp(m.to, maxf(0.0, k - 0.35))
		draw_line(back, p, Color(1.0, 0.45, 0.1, 0.7), 5.0)
		draw_line(back.lerp(p, 0.5), p, Color(1.0, 0.85, 0.35, 0.9), 2.0)
		draw_circle(p, 6.0, Color(1.0, 0.5, 0.12))
		draw_circle(p, 3.0, Color(1.0, 0.95, 0.6))
	if gods.frenzy_left > 0.0:
		var fade := clampf(gods.frenzy_left / 0.8, 0.0, 1.0)
		var pulse := 0.5 + 0.5 * sin(sim.time * 7.0)
		draw_arc(sim.commander.pos, sim.legion_reach + 4.0 + 3.0 * pulse, 0.0, TAU, 64, Color(0.95, 0.2, 0.08, 0.7 * fade), 4.0)
		draw_arc(sim.commander.pos, sim.legion_reach + 4.0 + 3.0 * pulse, 0.0, TAU, 64, Color(1.0, 0.8, 0.3, 0.9 * fade), 1.0)
		# A red edge round the screen keeps the frenzy in sight wherever the eye is.
		var edge := Rect2(top_left, screen)
		for band in 4:
			var w := 6.0 + band * 6.0
			var col := Color(0.8, 0.08, 0.04, (0.22 - band * 0.05) * fade * (0.7 + 0.3 * pulse))
			draw_rect(Rect2(edge.position, Vector2(edge.size.x, w)), col)
			draw_rect(Rect2(edge.position + Vector2(0, edge.size.y - w), Vector2(edge.size.x, w)), col)
			draw_rect(Rect2(edge.position, Vector2(w, edge.size.y)), col)
			draw_rect(Rect2(edge.position + Vector2(edge.size.x - w, 0), Vector2(w, edge.size.y)), col)
		var units: Array = [sim.commander] + sim.soldiers
		for n in units.size():
			var u: Dictionary = units[n]
			for e in 2:
				var life := fmod(sim.time * 1.3 + n * 0.37 + e * 0.5, 1.0)
				var q: Vector2 = u.pos + Vector2(((n * 7 + e * 5) % 13) - 6.0, -8.0 - life * 26.0)
				draw_rect(Rect2(q.round(), Vector2(2, 3)), Color(1.0, 0.45 + 0.45 * e, 0.12, (1.0 - life) * fade))
	if gods.light_left > 0.0:
		var k := gods.light_left / float(g.apollo.light_seconds)
		draw_rect(whole, Color(1.0, 0.85, 0.4, 0.22 * k))
		var units: Array = [sim.commander] + sim.soldiers
		for n in mini(units.size(), 60):
			var p: Vector2 = units[n].pos
			draw_rect(Rect2(p.x - 3.0, top_left.y, 6.0, p.y - top_left.y), Color(1.0, 0.92, 0.55, 0.22 * k))
			draw_rect(Rect2(p.x - 1.0, top_left.y, 2.0, p.y - top_left.y), Color(1.0, 1.0, 0.85, 0.4 * k))
	var bolt_life := float(g.jupiter.bolt_seconds)
	for bolt in gods.bolts:
		var a := 1.0 - float(bolt.t) / bolt_life
		var rng := RandomNumberGenerator.new()
		rng.seed = int(bolt.seed)
		var to: Vector2 = bolt.to
		var start := Vector2(to.x + rng.randf_range(-60.0, 60.0), top_left.y - 8.0)
		var pts := PackedVector2Array([start])
		var steps := 9
		for i in range(1, steps):
			var t := float(i) / steps
			pts.append(start.lerp(to, t) + Vector2(rng.randf_range(-16.0, 16.0), rng.randf_range(-4.0, 4.0)))
		pts.append(to)
		draw_polyline(pts, Color(0.55, 0.7, 1.0, 0.45 * a), 7.0)
		draw_polyline(pts, Color(0.85, 0.92, 1.0, 0.9 * a), 3.0)
		draw_polyline(pts, Color(1.0, 1.0, 1.0, a), 1.0)
		var fork: int = 2 + rng.randi() % 5
		var branch := PackedVector2Array([pts[fork]])
		for i in 3:
			branch.append(branch[-1] + Vector2(rng.randf_range(-22.0, 22.0), rng.randf_range(10.0, 26.0)))
		draw_polyline(branch, Color(0.85, 0.92, 1.0, 0.7 * a), 1.0)
		draw_circle(to, 14.0 * a + 4.0, Color(0.8, 0.9, 1.0, 0.45 * a))
		draw_circle(to, 6.0, Color(1.0, 1.0, 1.0, a))
	if gods.flash > 0.0:
		draw_rect(whole, Color(1.0, 1.0, 1.0, minf(gods.flash, 0.85)))


## Every ravine in view: black depths under a rocky lip that falls away into them, then the bridges laid over them.
func _draw_ravines(view: Rect2) -> void:
	var item := get_canvas_item()
	var empty_uv := PackedVector2Array()
	for st in sim.terrain.streams_in(view):
		for piece in st.pieces:
			if not piece.has("mesh"):
				piece.mesh = _ice_mesh(piece)
			var g: Array = piece.mesh
			RenderingServer.canvas_item_add_triangle_array(item, g[0], g[1], g[2], g[3], PackedInt32Array(), PackedFloat32Array(), ice.get_rid())
			draw_polyline(g[4], Color(0.93, 0.96, 1.0, 0.85), 3.0)
			draw_polyline(g[4], Color(0.35, 0.45, 0.6, 0.7), 1.0)
	for rv in sim.terrain.ravines_in(view):
		for piece in rv.pieces:
			# Each piece keeps its triangles once worked out, since a ravine never changes.
			if not piece.has("mesh"):
				piece.mesh = _gorge_mesh(piece)
			var g: Array = piece.mesh
			RenderingServer.canvas_item_add_triangle_array(item, g[0], g[1], g[2], empty_uv)
			RenderingServer.canvas_item_add_triangle_array(item, g[3], g[4], g[5], g[6], PackedInt32Array(), PackedFloat32Array(), ravine_edge.get_rid())
	for br in sim.terrain.bridges:
		if view.has_point(br.pos):
			_draw_bridge(br)


## The triangles of one frozen stream piece, the ice laid in world space so it lines up across pieces, and its bank as a closed line.
func _ice_mesh(piece: Dictionary) -> Array:
	var o := _outline(piece)
	var centres: PackedVector2Array = o[0]
	var outs: PackedVector2Array = o[1]
	var widths: PackedFloat32Array = o[2]
	var m := centres.size()
	var tex := Vector2(ice.get_width(), ice.get_height())
	var pts := PackedVector2Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var bank := PackedVector2Array()
	for k in m:
		var edge := centres[k] + outs[k] * widths[k]
		pts.append(edge)
		bank.append(edge)
	for k in m:
		pts.append(centres[k])
	for q in pts:
		cols.append(Color.WHITE)
		uvs.append(q / tex)
	for k in m:
		var j := (k + 1) % m
		idx.append_array([m + k, k, j, m + k, j, m + j])
	bank.append(bank[0])
	return [idx, pts, cols, uvs, bank]


## A gorge or stream piece's outline: down one side, round the far end, back up the other side and round the near end, as centres, outward directions and widths.
func _outline(piece: Dictionary) -> Array:
	var pts: PackedVector2Array = piece.pts
	var half: PackedFloat32Array = piece.half
	var n := pts.size()
	var centres := PackedVector2Array()
	var outs := PackedVector2Array()
	var widths := PackedFloat32Array()
	var normals := PackedVector2Array()
	for i in n:
		var along := (pts[mini(i + 1, n - 1)] - pts[maxi(i - 1, 0)]).normalized()
		normals.append(along.orthogonal())
	var cap := 8
	for i in n:
		centres.append(pts[i])
		outs.append(normals[i])
		widths.append(half[i])
	for k in range(1, cap):
		centres.append(pts[n - 1])
		outs.append(normals[n - 1].rotated(-PI * k / cap))
		widths.append(half[n - 1])
	for i in range(n - 1, -1, -1):
		centres.append(pts[i])
		outs.append(-normals[i])
		widths.append(half[i])
	for k in range(1, cap):
		centres.append(pts[0])
		outs.append(-normals[0].rotated(-PI * k / cap))
		widths.append(half[0])
	return [centres, outs, widths]


## The triangles of one ravine piece: the dark fill of its whole outline, and the strip of rocky lip along it.
func _gorge_mesh(piece: Dictionary) -> Array:
	var pts: PackedVector2Array = piece.pts
	var o := _outline(piece)
	var centres: PackedVector2Array = o[0]
	var outs: PackedVector2Array = o[1]
	var widths: PackedFloat32Array = o[2]
	var m := centres.size()
	var dark := Color(0.035, 0.025, 0.03)
	var fill_pts := PackedVector2Array()
	var fill_cols := PackedColorArray()
	var fill_idx := PackedInt32Array()
	fill_pts.append(pts[0])
	fill_cols.append(dark)
	for k in m:
		fill_pts.append(centres[k] + outs[k] * (widths[k] + 2.0))
		fill_cols.append(dark)
	# The fill is laid in quads from the middle line out to the outline, so a bent gorge never folds its own polygon over itself.
	for k in m:
		fill_pts.append(centres[k])
		fill_cols.append(dark)
	for k in m:
		var j := (k + 1) % m
		fill_idx.append_array([m + 1 + k, k + 1, j + 1, m + 1 + k, j + 1, m + 1 + j])
	var tex_w := float(ravine_edge.get_width())
	var lip_pts := PackedVector2Array()
	var lip_cols := PackedColorArray()
	var lip_uvs := PackedVector2Array()
	var lip_idx := PackedInt32Array()
	var s := 0.0
	var last := Vector2.ZERO
	for k in m + 1:
		var c := k % m
		var w := widths[c]
		var outer := centres[c] + outs[c] * (w + 12.0 * minf(1.0, w / 30.0))
		var inner := centres[c] + outs[c] * maxf(w - 48.0, 0.0)
		if k > 0:
			s += outer.distance_to(last)
		last = outer
		lip_pts.append_array([outer, inner])
		lip_cols.append_array([Color.WHITE, Color.WHITE])
		lip_uvs.append_array([Vector2(s / tex_w, 0.0), Vector2(s / tex_w, 1.0)])
		if k > 0:
			var b := lip_pts.size() - 4
			lip_idx.append_array([b, b + 2, b + 1, b + 1, b + 2, b + 3])
	return [fill_idx, fill_pts, fill_cols, lip_idx, lip_pts, lip_cols, lip_uvs]


## A plank bridge: two side beams with planks laid across them and a post at each corner.
func _draw_bridge(br: Dictionary) -> void:
	var d: Vector2 = br.dir
	var side := d.orthogonal()
	var hl: float = br.half_len
	var hw: float = br.half_w
	var c: Vector2 = br.pos
	var ink := Color(0.16, 0.1, 0.08)
	var beam := Color(0.33, 0.21, 0.11)
	var planks := [Color(0.62, 0.43, 0.24), Color(0.55, 0.37, 0.2), Color(0.66, 0.47, 0.27)]
	draw_colored_polygon(PackedVector2Array([c - d * hl + side * (hw + 2), c + d * hl + side * (hw + 2), c + d * hl - side * (hw + 2), c - d * hl - side * (hw + 2)]), ink)
	var t := -hl + 1.0
	var k := 0
	while t < hl - 1.0:
		var a := c + d * t
		var z := c + d * minf(t + 4.0, hl - 1.0)
		var jag := float((k * 7) % 3) - 1.0
		var col: Color = planks[(k * 5) % 3]
		draw_colored_polygon(PackedVector2Array([a + side * (hw + jag), z + side * (hw + jag), z - side * (hw - jag), a - side * (hw - jag)]), col)
		draw_line(z + side * (hw - 1), z - side * (hw - 1), Color(0.3, 0.19, 0.1), 1.0)
		t += 5.0
		k += 1
	for edge in [-1.0, 1.0]:
		var e: Vector2 = side * edge * (hw - 1.5)
		draw_line(c - d * hl + e, c + d * hl + e, beam, 3.0)
		for end in [-1.0, 1.0]:
			var post: Vector2 = (c + d * (hl - 3.0) * end + side * edge * (hw + 1.0)).round()
			draw_rect(Rect2(post - Vector2(3, 3), Vector2(6, 6)), ink)
			draw_rect(Rect2(post - Vector2(2, 2), Vector2(4, 4)), beam)
