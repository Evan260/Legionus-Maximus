extends Node2D
## Draws the field around the commander: ground, scattered props, coins, the legion and the horde in depth order,
## then missiles and effects.

# How far the wheat tile is laid past each field for its frayed edge, and how many fields the shader holds (its `fields` array).
const FIELD_FRAY := 20.0
const FIELD_SHAPES := 32
# Ground pictures sort 60000 px above where they lie, so every depth key from here up belongs to something standing.
const STANDING_KEY := 70000 * 65536
# How many stain shapes are painted for each size and direction.
const STAIN_SHAPES := 4


var sim: Sim
var atlas: Atlas
var ground: Texture2D
var _ground_of := "germania"
var shadow: Texture2D
var shake_on := true
var digits: Texture2D
var _cam := Vector2.ZERO
var _shake_rng := RandomNumberGenerator.new()
# Each bolt's jags are drawn again from its own seed every frame.
var _bolt_rng := RandomNumberGenerator.new()

var _keys := PackedInt64Array()
var _rects: Array[Rect2] = []
var _dests := PackedVector2Array()
var _mods := PackedColorArray()
var _sizes := PackedVector2Array()
# The toppling dead are drawn through transforms of their own, kept in _turns by sprite index; every one lies between _turn_lo and _turn_hi.
var _turns := {}
var _turn_lo := 0
var _turn_hi := 0
# Whether each kind of enemy stands on four legs or rides, so it rolls onto its side when it dies.
var _all_fours := {}
# The stain pictures, painted once, with each size's cell width and the row it starts at.
var _stain_sheet: Texture2D
var _stain_cells: Array[int] = []
var _stain_rows: Array[int] = []
# The trees being chopped this frame, as [position, seconds of chopping], for their progress bars.
var _felling: Array = []
# Per enemy kind of the current sim: its art name, whether it has an attack drawn, and its shadow's width.
var _kinds_of: Sim
var _k_type := PackedStringArray()
var _k_attack := PackedByteArray()
var _k_shadow := PackedFloat32Array()
# How much larger than its art each kind is drawn, such as the war elephant.
var _k_scale := PackedFloat32Array()
# How far each kind's picture can reach from where it stands, so a big one is still drawn while part of it is on screen.
var _k_reach := PackedFloat32Array()
var _max_reach := 0.0
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
# The water of every canal, repeated across the world like the ice and drifting along the canals through water.gdshader on its own layer.
var water: Texture2D
# Seconds the legion has been cheering, kept here so it runs on once the run is over and the sim stops.
var _cheer_t := 0.0
var _water := Node2D.new()
# Soldiers reeling from a sling stone, and the camels bringing the shah's riders fresh arrows, marked over their heads this frame.
var _dazed := PackedVector2Array()
var _train_marks := PackedVector2Array()
# The ground and the wheat fields are drawn by two layers behind this node, so the wheat can have a shader of its own that frays its edges.
var _floor := Node2D.new()
var _wheat := Node2D.new()
var _wheat_tile: Texture2D
# The legion's armour and cloth tiers drawn now, and tiers set from the command line for a look, or -1 to follow the upgrades.
var _livery := Vector2i(-1, -1)
var livery_force := Vector2i(-1, -1)


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
	water = load("res://assets/water.png")
	# The ravine lip repeats along each gorge; every other picture is drawn inside its own rectangle, so repeating changes nothing for it.
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	for layer in [_floor, _wheat, _water]:
		layer.show_behind_parent = true
		add_child(layer)
	_floor.draw.connect(_draw_floor)
	_water.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var flow := ShaderMaterial.new()
	flow.shader = load("res://scripts/water.gdshader")
	_water.material = flow
	_water.draw.connect(_draw_water)
	var fray := ShaderMaterial.new()
	fray.shader = load("res://scripts/wheat_field.gdshader")
	_wheat.material = fray
	_wheat.draw.connect(_draw_fields)
	var dress := ShaderMaterial.new()
	dress.shader = load("res://scripts/livery.gdshader")
	material = dress


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
		_cheer_t = _cheer_t + dt if _cheering() else 0.0
		var jolt := Vector2.ZERO
		if shake_on and sim.shake > 0.0:
			# Neptune's earthquake shakes the screen harder than any blow.
			var reach := int(sim.b.gods.neptune.shake_pixels) if sim.gods.quake > 0.0 else (sim.shake_pixels if sim.shake_pixels > 0 else int(sim.b.shake.pixels))
			jolt = Vector2(_shake_rng.randi_range(-reach, reach), _shake_rng.randi_range(-reach, reach))
		# The shake dies away here, not in the sim, so it still ends while the run is paused or over.
		sim.shake = maxf(0.0, sim.shake - dt)
		if sim.shake <= 0.0:
			sim.shake_pixels = 0
		sim.gods.quake = maxf(0.0, sim.gods.quake - dt)
		position = (get_viewport_rect().size / 2.0 - sim.commander.pos).round() + jolt
		queue_redraw()
		_floor.queue_redraw()
		_wheat.queue_redraw()
		_water.queue_redraw()


## A sprite's place in the drawing order, from its depth measured from the camera so the key stays positive however far the legion marches.
static func depth_key(y: float, cam_y: float, index: int) -> int:
	# Each side is rounded down on its own, so two sprites keep their order while the camera moves between pixels.
	return (floori(y) - floori(cam_y) + 100000) * 65536 + index


func _add(y: float, rect: Rect2, dest: Vector2, mod: Color, moving := false, size := Vector2.ZERO) -> void:
	_keys.append(depth_key(y, _cam.y, _rects.size()))
	_rects.append(rect)
	_dests.append(_snap(dest) if moving else dest.round())
	_mods.append(mod)
	_sizes.append(rect.size if size == Vector2.ZERO else size)


## Draws the sorted sprites from `from` up to `to` in depth order.
func _draw_sorted(tex: Texture2D, from: int, to: int) -> void:
	for n in range(from, to):
		var idx := int(_keys[n] % 65536)
		if idx >= _turn_lo and idx < _turn_hi and _turns.has(idx):
			draw_set_transform_matrix(_turns[idx])
			draw_texture_rect_region(tex, Rect2(_dests[idx], _sizes[idx]), _rects[idx], _mods[idx])
			draw_set_transform_matrix(Transform2D.IDENTITY)
		else:
			draw_texture_rect_region(tex, Rect2(_dests[idx], _sizes[idx]), _rects[idx], _mods[idx])


## A sprite drawn turned and squashed by `xf` about its origin, for a body toppling over.
func _add_turned(y: float, rect: Rect2, dest: Vector2, mod: Color, size: Vector2, xf: Transform2D) -> void:
	if _turns.is_empty():
		_turn_lo = _rects.size()
	_turns[_rects.size()] = xf
	_turn_hi = _rects.size() + 1
	_add(y, rect, dest - xf.origin, mod, false, size)


## Feather grass bends in the wind: its upper half is drawn a pixel or two aside, in a slow wave that runs across the field.
func _add_swaying(at: Vector2, f: Array, mod: Color) -> void:
	var rect: Rect2 = f[0]
	var top := floorf(rect.size.y / 2.0)
	var lean := roundf(sin(sim.time * 1.8 + at.x * 0.02 + at.y * 0.01) * 1.5)
	_add(at.y, Rect2(rect.position, Vector2(rect.size.x, top)), at - f[1] + Vector2(lean, 0), mod)
	_add(at.y, Rect2(rect.position + Vector2(0, top), Vector2(rect.size.x, rect.size.y - top)), at - f[1] + Vector2(0, top), mod)


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
	var livery := livery_force if livery_force.x >= 0 else Livery.tiers(sim)
	if livery != _livery:
		_livery = livery
		Livery.apply(material, livery)
	_keys.clear()
	_rects.clear()
	_dests.clear()
	_mods.clear()
	_sizes.clear()
	_turns.clear()
	_turn_lo = 0
	_turn_hi = 0
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
				if pr[0] == "dune" or pr[0] == "bog" or pr[0] == "heather" or pr[0] == "dry_grass":
					# Dunes, bog pools, heather and dry grass are walked over, so they are drawn on the ground under everything that stands on them.
					_add(at.y - 60000.0, f[0], at - f[1], white)
					continue
				if not chops.is_empty() and chops.has(at) and sim.time - float(chops[at][1]) < shaking:
					_felling.append([at, float(chops[at][0])])
					at += Vector2(roundf(sin(sim.time * 45.0 + at.x) * 1.2), 0)
				var mod := white
				# A tree standing in front of the commander is seen through, so he is not lost once the legion cuts into a ridge.
				# Only the middle of the picture counts, since the empty margins round a canopy hide nothing.
				# A log lies low on the ground and hides nobody, so it stays solid.
				if (pr[2] > 0.0 or Terrain.SOLID.has(pr[0]) or pr[0] == "papyrus" or pr[0] == "feather_grass") and pr[0] != "log" and at.y > cam.y and _solid_part(Rect2(at - f[1], f[0].size)).intersects(him):
					mod = see_through
				# The gate fades only half way, so the fort still reads while the commander walks under it.
				elif pr[0] == "fort_gate" and at.y > cam.y and Rect2(at - f[1], f[0].size).intersects(him):
					mod = Color(1, 1, 1, 0.55)
				if pr[0] == "feather_grass":
					_add_swaying(pr[1], f, mod)
					continue
				_add(pr[1].y, f[0], at - f[1], mod)
	if not sim.terrain.posts.is_empty():
		var sf := atlas.prop_frame("stake")
		var fade := float(sim.b.palisade.fade)
		var hold := float(sim.b.wall.hold)
		for post in sim.terrain.posts:
			if view.has_point(post[1]):
				# A wall stake darkens as the horde batters it, so the player sees where it is about to give.
				var worn := 1.0 - 0.5 * clampf(float(sim.terrain.battered.get(post[1], 0.0)) / hold, 0.0, 1.0)
				_add(post[1].y, sf[0], post[1] - sf[1], Color(worn, worn, worn, clampf((post[3] - sim.time) / fade, 0.0, 1.0)))


	var gold := Color(1.0, 0.92, 0.7)
	var cursed := Color(0.78, 0.55, 1.0)
	var stunned := Color(0.78, 0.74, 0.62)
	var cheering := _cheering()
	var cycle := float(sim.b.triumph.cheer_cycle)
	_dazed.clear()
	_train_marks.clear()
	var men: Array = [sim.commander] + sim.soldiers
	for k in men.size():
		var u: Dictionary = men[k]
		var phase := cheer_phase(_cheer_t, k, cycle)
		var f := _cheer_frame(u, phase) if cheering and not u.moving else _legion_frame(u)
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
			hop.y = -sin(PI * phase / cycle) * float(sim.b.triumph.hop)
		_add(u.pos.y, f[0], u.pos - f[1] + hop, Livery.mark(mod), true)

	if _kinds_of != sim:
		_index_kinds()
	var h: Horde = sim.horde
	var strike_secs := Atlas.ATTACK_FRAMES / Atlas.ATTACK_FPS
	var loop_t := sim.time * Atlas.ATTACK_FPS
	var wide := view.grow(maxf(0.0, _max_reach - 80.0))
	for i in h.e_pos.size():
		var p: Vector2 = h.e_pos[i]
		if not wide.has_point(p):
			continue
		var kind := h.e_kind[i]
		var reach := _k_reach[kind]
		if not (view.has_point(p) if reach <= 80.0 else view.grow(reach - 80.0).has_point(p)):
			continue
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
		elif h.e_ward[i] > sim.time:
			mod = Color(0.72, 0.95, 0.6)
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
			_add_body(e)
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
	# Stains go over the ground pictures, such as dunes and heather, and under everything that stands.
	var standing := _keys.bsearch(STANDING_KEY)
	_draw_sorted(tex, 0, standing)
	_draw_stains(view)
	_draw_sorted(tex, standing, _keys.size())
	_draw_death_bits()

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


## The wheat fields of Gaul and Aegyptus: the wheat tile repeated over each field, lined up with the world so neighbouring fields share their rows.
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
	_wheat.material.set_shader_parameter("turn", sim.terrain.field_turn)
	_wheat.material.set_shader_parameter("reach", FIELD_FRAY)
	var tint: Array = sim.terrain.valley.get("grain_tint", [1.0, 1.0, 1.0])
	_wheat.material.set_shader_parameter("tint", Vector3(float(tint[0]), float(tint[1]), float(tint[2])))
	if _wheat_tile == null:
		# The tile has a texture of its own so it repeats across a whole field in one piece, with no seams where atlas pieces would meet.
		var src: Rect2 = atlas.prop_frame("wheat_field")[0]
		_wheat_tile = ImageTexture.create_from_image(atlas.texture.get_image().get_region(Rect2i(src)))
	for f in fields:
		var area: Rect2 = sim.terrain.field_box(f.grow(FIELD_FRAY)).intersection(view)
		if area.size.x > 0.0 and area.size.y > 0.0:
			# The texture repeats from world (0, 0), so neighbouring fields share their rows.
			_wheat.draw_texture_rect_region(_wheat_tile, area, area)


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
## Whether the legion cheers: through the triumph and on behind the victory screens that follow it.
func _cheering() -> bool:
	return sim.triumph_left > 0.0 or (sim.over and sim.victory)


## How far man number `k` is through his cheer at `clock` seconds, from 0 to `cycle`, a little out of step with his neighbours.
static func cheer_phase(clock: float, k: int, cycle: float) -> float:
	return fmod(clock + k * 0.37, cycle)


func _cheer_frame(u: Dictionary, phase: float) -> Array:
	# The swing plays slower than a blow, so the raised weapons read as a cheer and not a twitch.
	var f := atlas.attack_frame(u.type, "south", phase * float(sim.b.triumph.cheer_swing))
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
	_k_reach.resize(h.kind_ids.size())
	_k_reach.fill(0.0)
	_max_reach = 0.0
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
					_k_reach[k] = maxf(_k_reach[k], maxf(float(f[2]), float(f[3])) * _k_scale[k])
					_max_reach = maxf(_max_reach, _k_reach[k])
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
				# The ditch is the dark band the stakes stand in, rounded like the legion so it keeps step with them.
				draw_arc(_snap(sim.commander.pos), r, 0.0, TAU, 72, Color(0.2, 0.13, 0.07, 0.5), 5.0)


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
			var p: Vector2 = sim.commander.pos + Vector2.from_angle(i * TAU / n) * st.radius
			if view.has_point(p):
				_add(p.y, f[0], p - f[1], Color.WHITE, true)
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
		if l.get("javelin", false):
			# A hidden man's javelin flies high from the flank, its point leading along its arc.
			var at: Vector2 = ground + Vector2(0, -sin(k * PI) * 70.0)
			var ahead: Vector2 = ((l.to - l.from).normalized() + Vector2(0, -cos(k * PI) * 2.0)).normalized()
			draw_line(at - ahead * 7.0, at + ahead * 5.0, Color(0.2, 0.13, 0.08), 2.0)
			draw_line(at - ahead * 6.0, at + ahead * 4.0, Color(0.55, 0.36, 0.2), 1.0)
			draw_line(at + ahead * 4.0, at + ahead * 8.0, Color(0.78, 0.78, 0.74), 1.0)
			continue
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
	if not h.flood.is_empty():
		_draw_flood(h.flood)
	if not h.wave.is_empty() and h.wave.t < h.wave.warn:
		_draw_lane(h.wave.from, h.wave.dir, h.wave.length, h.wave.width, clampf(h.wave.t / h.wave.warn, 0.0, 1.0))
	if not h.steppe_fire.is_empty():
		_draw_steppe_fire(h.steppe_fire)
	for l in h.lassos:
		var i := h.e_id.find(l.id)
		if i >= 0:
			_draw_lasso(h.e_pos[i], l.unit.pos, clampf(l.t / l.dur, 0.0, 1.0))
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


## The band the Egyptian general floods: a blue outline filling from the bank while it is marked, then muddy water with ripples until it drains.
func _draw_flood(fl: Dictionary) -> void:
	var c: Vector2 = fl.pos
	var d: Vector2 = fl.dir
	var side := d.orthogonal()
	var hl: float = fl.half_len
	var hw: float = fl.half_w
	var corners := PackedVector2Array([c - d * hl - side * hw, c + d * hl - side * hw, c + d * hl + side * hw, c - d * hl + side * hw])
	if fl.t < fl.warn:
		var k: float = clampf(fl.t / fl.warn, 0.0, 1.0)
		draw_colored_polygon(corners, Color(0.25, 0.5, 0.85, 0.1 + 0.15 * k))
		draw_colored_polygon(PackedVector2Array([c - d * hl - side * hw, c + d * hl - side * hw, c + d * hl + side * hw * (2.0 * k - 1.0), c - d * hl + side * hw * (2.0 * k - 1.0)]), Color(0.35, 0.6, 0.95, 0.22))
		corners.append(corners[0])
		draw_polyline(corners, Color(0.5, 0.75, 1.0, 0.9), 1.0)
		return
	var left: float = fl.warn + fl.seconds - fl.t
	var a := clampf(left / 0.8, 0.0, 1.0) * clampf((fl.t - fl.warn) / 0.3, 0.0, 1.0)
	draw_colored_polygon(corners, Color(0.32, 0.42, 0.36, 0.75 * a))
	for n in 6:
		var along: float = -hl + hl * 2.0 * fmod(n * 0.37 + sim.time * 0.15, 1.0)
		var across: float = hw * (n % 3 - 1) * 0.55
		var at := c + d * along + side * across
		draw_line(at - d * 6.0, at + d * 6.0, Color(0.7, 0.8, 0.78, 0.5 * a), 1.0)
	corners.append(corners[0])
	draw_polyline(corners, Color(0.24, 0.2, 0.14, 0.8 * a), 2.0)


## The Roxolani king's burning band: marked in orange and filling from its starting edge while it is marked, then flames over the strip
## alight with charred grass behind them.
func _draw_steppe_fire(fire: Dictionary) -> void:
	var c: Vector2 = fire.pos
	var d: Vector2 = fire.dir
	var side := d.orthogonal()
	var hl: float = fire.half_len
	var depth: float = fire.depth
	var band := func(a: float, b: float) -> PackedVector2Array:
		return PackedVector2Array([c + d * a - side * hl, c + d * b - side * hl, c + d * b + side * hl, c + d * a + side * hl])
	var outline: PackedVector2Array = band.call(0.0, depth)
	outline.append(outline[0])
	if fire.t < fire.warn:
		var k: float = clampf(fire.t / fire.warn, 0.0, 1.0)
		draw_colored_polygon(band.call(0.0, depth), Color(0.85, 0.35, 0.05, 0.08 + 0.12 * k))
		draw_colored_polygon(band.call(0.0, depth * 0.25 * k), Color(1.0, 0.5, 0.15, 0.3))
		draw_polyline(outline, Color(1.0, 0.55, 0.15, 0.9), 1.0)
		return
	var span: Vector2 = sim.horde.fire_span()
	var left: float = fire.warn + fire.seconds + fire.burn - fire.t
	var fade := clampf(left / 0.8, 0.0, 1.0)
	if span.y < depth:
		draw_colored_polygon(band.call(span.y, depth), Color(0.85, 0.35, 0.05, 0.1))
	draw_colored_polygon(band.call(0.0, span.x), Color(0.12, 0.1, 0.08, 0.35 * fade))
	if span.y > span.x:
		draw_colored_polygon(band.call(span.x, span.y), Color(0.2, 0.07, 0.03, 0.5 * fade))
		var beat := int(sim.time * 10.0)
		var n := int((span.y - span.x) * hl * 2.0 / 90.0) + 4
		for i in n:
			var a := float(i) * 0.618034
			var along: float = lerpf(span.x, span.y, fmod(a, 1.0))
			var across: float = (fmod(float(i) * 0.7548777, 1.0) * 2.0 - 1.0) * hl
			var base: Vector2 = c + d * along + side * across
			var h := 2 + (beat + i * 3) % 4
			draw_rect(Rect2(base.round() + Vector2(0, -h), Vector2(2, h)), Color(1.0, 0.5, 0.12, 0.9 * fade))
			draw_rect(Rect2(base.round() + Vector2(0, -h + 1), Vector2(1, maxi(1, h - 2))), Color(1.0, 0.86, 0.35, 0.9 * fade))
	draw_polyline(outline, Color(1.0, 0.55, 0.15, 0.6 * fade), 1.0)


## A lasso swung at a soldier: a loop circling over the rider's head that shrinks round the soldier as the throw comes.
func _draw_lasso(rider: Vector2, man: Vector2, k: float) -> void:
	var rope := Color(0.62, 0.45, 0.25, 0.95)
	var hand := rider + Vector2(0, -16)
	var spin := sim.time * 14.0
	draw_arc(hand + Vector2(cos(spin), sin(spin) * 0.4) * 3.0, 7.0, 0.0, TAU, 14, rope, 1.0)
	draw_arc(man + Vector2(0, -6), 14.0 - 8.0 * k, 0.0, TAU, 20, Color(0.95, 0.25, 0.15, 0.4 + 0.5 * k), 1.0)
	if k > 0.6:
		draw_line(hand, man + Vector2(0, -6), rope, 1.0)


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
				_add_prop(str(o.get("centre", "altar")), o.pos, Color.WHITE)


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
		elif o.kind == "grove" and o.get("centre", "altar") == "altar":
			# The altar's fire always flickers, so its painted flames never sit still.
			_add_flame(o.pos, Vector2(0, -8), o.oaks.size(), 0, 1.0)
			if o.done and sim.time - o.burnt_at < float(cfg.burn_seconds):
				var fade := clampf((float(cfg.burn_seconds) - (sim.time - o.burnt_at)) / 2.0, 0.0, 1.0)
				for i in o.oaks.size():
					_add_flame(o.oaks[i], Vector2(0, -30), i, 0, fade)


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
		elif e.kind == "ward":
			# A priest of Sobek's blessing spreads as a green ring of scales.
			var k: float = e.t / 0.45
			draw_circle(e.pos, e.radius * (0.3 + 0.7 * k), Color(0.35, 0.6, 0.25, 0.25 * (1.0 - k)))
			draw_arc(e.pos, e.radius * (0.3 + 0.7 * k), 0.0, TAU, 64, Color(0.6, 0.85, 0.35, 1.0 - k), 2.0)
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
	var screen := get_viewport_rect().size
	var seen := Rect2(sim.commander.pos - screen / 2.0, screen).grow(40.0)
	for i in sim.horde.e_pos.size():
		if not seen.has_point(sim.horde.e_pos[i]):
			continue
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
		var rng := _bolt_rng
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
			if rv.get("canal", false):
				if not piece.has("mud"):
					piece.mud = _mud_mesh(piece)
				var m: Array = piece.mud
				RenderingServer.canvas_item_add_triangle_array(item, m[0], m[1], m[2])
				continue
			# Each piece keeps its triangles once worked out, since a ravine never changes.
			if not piece.has("mesh"):
				piece.mesh = _gorge_mesh(piece)
			var g: Array = piece.mesh
			RenderingServer.canvas_item_add_triangle_array(item, g[0], g[1], g[2], empty_uv)
			RenderingServer.canvas_item_add_triangle_array(item, g[3], g[4], g[5], g[6], PackedInt32Array(), PackedFloat32Array(), ravine_edge.get_rid())
	for br in sim.terrain.bridges:
		if view.has_point(br.pos):
			_draw_bridge(br)


## The water of every canal in view, on its own layer so the shader can drift it along the canals.
func _draw_water() -> void:
	if not sim or sim.terrain.canal.is_empty():
		return
	var view := view_for(sim.commander.pos - get_viewport_rect().size / 2.0)
	var item := _water.get_canvas_item()
	var flow := Vector2.ZERO
	for rv in sim.terrain.ravines_in(view):
		if not rv.get("canal", false):
			continue
		for piece in rv.pieces:
			if not piece.has("mesh"):
				piece.mesh = _water_mesh(piece)
			var w: Array = piece.mesh
			flow = w[4]
			RenderingServer.canvas_item_add_triangle_array(item, w[0], w[1], w[2], w[3], PackedInt32Array(), PackedFloat32Array(), water.get_rid())
	if flow != Vector2.ZERO:
		var tex := Vector2(water.get_width(), water.get_height())
		_water.material.set_shader_parameter("drift", flow * float(sim.terrain.canal.drift) / tex)


## One straight canal piece as two water triangles, laid in world space so neighbouring pieces line up, with the way it flows.
func _water_mesh(piece: Dictionary) -> Array:
	var pts: PackedVector2Array = piece.pts
	var a := pts[0]
	var z := pts[pts.size() - 1]
	var along := (z - a).normalized()
	var out := along.orthogonal() * float(piece.half[0])
	var tex := Vector2(water.get_width(), water.get_height())
	var corners := PackedVector2Array([a - out, a + out, z + out, z - out])
	var uvs := PackedVector2Array()
	for q in corners:
		uvs.append(q / tex)
	return [PackedInt32Array([0, 1, 2, 0, 2, 3]), corners, PackedColorArray([Color.WHITE, Color.WHITE, Color.WHITE, Color.WHITE]), uvs, along]


## The wet mud along both banks of a straight canal piece: dark at the water's edge, fading into the silt.
func _mud_mesh(piece: Dictionary) -> Array:
	var pts: PackedVector2Array = piece.pts
	var a := pts[0]
	var z := pts[pts.size() - 1]
	var n := (z - a).normalized().orthogonal()
	var half := float(piece.half[0])
	var steps := [[-3.0, Color(0.12, 0.09, 0.06, 1.0)], [4.0, Color(0.18, 0.13, 0.08, 1.0)], [12.0, Color(0.23, 0.17, 0.1, 0.8)], [22.0, Color(0.26, 0.19, 0.12, 0.0)]]
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for side in [-1.0, 1.0]:
		var base := verts.size()
		for st in steps:
			var off: Vector2 = n * side * (half + float(st[0]))
			verts.append(a + off)
			verts.append(z + off)
			cols.append(st[1])
			cols.append(st[1])
		for k in steps.size() - 1:
			var i := base + k * 2
			idx.append_array([i, i + 1, i + 3, i, i + 3, i + 2])
	return [idx, verts, cols]


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


## A dead man flashes white, is knocked away from the blow, topples over away from it and fades.
func _add_body(e: Dictionary) -> void:
	var cfg: Dictionary = sim.b.deaths
	var soldier: bool = e.kind == "fallen"
	var big: bool = e.get("big", false)
	var secs := float(cfg.big_seconds if big else cfg.seconds)
	var t: float = e.t
	var dir := _death_dir(e)
	var f := atlas.unit_frame(e.type, "idle", Sim.dir_name(e.facing), 0.0)
	var sc := _scale_of(e.type)
	var knock := float(cfg.soldier_knock if soldier else (cfg.big_knock if big else cfg.knock))
	var kk := clampf(t / float(cfg.knock_seconds), 0.0, 1.0)
	var at: Vector2 = (e.pos + dir * knock * (1.0 - (1.0 - kk) * (1.0 - kk))).round()
	var tk := clampf(t / float(cfg.topple_seconds), 0.0, 1.0)
	tk *= tk
	var side := signf(dir.x) if absf(dir.x) > 0.05 else (1.0 if _death_seed(e) % 2 == 0 else -1.0)
	var lean := maxf(absf(dir.x), float(cfg.least_lean))
	var angle := deg_to_rad(float(cfg.soldier_degrees if soldier else cfg.topple_degrees)) * side * lean * tk
	var flat := 1.0 - (1.0 - float(cfg.flat)) * tk * absf(dir.y)
	var xf_fade := float(cfg.fade_from)
	if not soldier and _on_all_fours(e.type):
		# Turned on end, a beast or a horse would look like it was rearing, so it rolls onto its side instead.
		angle = deg_to_rad(float(cfg.beast_degrees)) * side * tk
		flat = 1.0 - (1.0 - float(cfg.beast_flat)) * tk
	if e.get("chief", false):
		# The chieftain reels back swaying, sinks to his knees and only then topples over.
		var cc: Dictionary = sim.b.chief_death
		secs = float(cc.fall_seconds)
		var stagger := float(cc.stagger_seconds)
		var sink := float(cc.drop_seconds)
		var reel := clampf(t / stagger, 0.0, 1.0)
		at = (e.pos + dir * float(cc.knock) * (1.0 - (1.0 - reel) * (1.0 - reel))).round()
		var sway := deg_to_rad(float(cc.stagger_degrees)) * sin(reel * 2.5 * TAU) * (1.0 - reel * 0.5)
		var kneel := clampf((t - stagger) / sink, 0.0, 1.0)
		tk = clampf((t - stagger - sink) / float(cc.topple_seconds), 0.0, 1.0)
		tk *= tk
		angle = sway * (1.0 - kneel) + deg_to_rad(float(cfg.topple_degrees)) * side * lean * tk
		flat = (1.0 - float(cc.drop) * kneel) * (1.0 - (1.0 - float(cfg.flat)) * tk * absf(dir.y))
		if _on_all_fours(e.type):
			angle = sway * (1.0 - kneel) + deg_to_rad(float(cfg.beast_degrees)) * side * tk
		xf_fade = float(cc.fade_from)
	var xf := Transform2D(angle, Vector2.ZERO).scaled(Vector2(1.0, flat))
	xf.origin = at
	var a := 1.0 - smoothstep(xf_fade * secs, secs, t)
	var tint: Array = cfg.tint
	var bright := float(cfg.flash_bright)
	var mod := Color(bright, bright, bright, 1.0) if t < float(cfg.flash) else Color(float(tint[0]), float(tint[1]), float(tint[2]), a)
	if soldier:
		mod = Livery.mark(mod)
	_add_turned(at.y, f[0], at - f[1] * sc, mod, f[0].size * sc, xf)


## The way a dead man falls: away from the blow that killed him, or backwards from where a soldier faced.
func _death_dir(e: Dictionary) -> Vector2:
	if e.has("dir"):
		return e.dir
	var back: Vector2 = -e.facing
	return back.normalized() if back != Vector2.ZERO else Vector2.DOWN


func _on_all_fours(type: String) -> bool:
	if not _all_fours.has(type):
		var info: Dictionary = sim.content.enemies.get(type, {})
		_all_fours[type] = info.get("behaviour", "") in ["beast", "driver", "charger"] or info.get("mounted", false) or type in sim.b.deaths.roll_kinds
	return _all_fours[type]


func _death_seed(e: Dictionary) -> int:
	return int(e.get("seed", int(e.pos.x) * 31 + int(e.pos.y) * 17))


## A steady number from 0 to 1 for the k-th draw of a seed, so each death's blood and stain keep their shape every frame.
static func _hash01(seed_n: int, k: int) -> float:
	var h := (seed_n * 73856093) ^ (k * 19349663) ^ 0x5bd1e995
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xffff) / 65535.0


## The blood thrown out along the killing blow, falling to the ground, or a puff of dust when blood is off.
func _draw_death_bits() -> void:
	var cfg: Dictionary = sim.b.deaths
	var g := float(cfg.gravity)
	for e in sim.effects:
		if e.kind != "death" and e.kind != "fallen":
			continue
		var soldier: bool = e.kind == "fallen"
		var big: bool = e.get("big", false)
		var seed_n := _death_seed(e)
		var t: float = e.t
		var bloody: bool = e.get("blood", sim.blood and soldier and sim.triumph_left <= 0.0)
		if bloody:
			var dir := _death_dir(e)
			var col: Array = cfg.blood
			var c := Color(float(col[0]), float(col[1]), float(col[2]))
			var n := int(e.get("spray", cfg.soldier_spray))
			var speed: Array = cfg.spray_speed
			var rise: Array = cfg.spray_rise
			var reach := float(sim.b.chief_death.spray_reach) if e.get("chief", false) else (1.4 if big else 1.0)
			var z0 := float(cfg.spray_height) * (1.6 if big else 1.0) * _scale_of(e.type)
			var r0 := float(rise[0])
			var r1 := float(rise[1])
			var s0 := float(speed[0]) * reach
			var s1 := float(speed[1]) * reach
			var aim := dir.angle()
			var spread := 2.0 * float(cfg.spray_spread)
			var fall := z0 - 0.5 * g * t * t
			for k in n:
				var z := fall + lerpf(r0, r1, _hash01(seed_n, k * 3 + 2)) * t
				if z < 0.0:
					continue
				var ang := aim + (_hash01(seed_n, k * 3) - 0.5) * spread
				var p: Vector2 = e.pos + Vector2.from_angle(ang) * lerpf(s0, s1, _hash01(seed_n, k * 3 + 1)) * t - Vector2(0, z)
				draw_rect(Rect2(p.round(), Vector2(2 if k % 3 == 0 else 1, 1)), c)
		else:
			var chief: bool = e.get("chief", false)
			var secs := float(sim.b.chief_death.fall_seconds) if chief else float(cfg.big_seconds if big else cfg.seconds)
			var k01 := clampf(t / secs, 0.0, 1.0)
			var col: Array = cfg.dust
			var c := Color(float(col[0]), float(col[1]), float(col[2]), 0.75 * (1.0 - k01))
			var n := int(e.get("dust", int(cfg.dust_puffs) * (2 if big else 1)))
			var far := float(sim.b.chief_death.dust_reach) if chief else float(cfg.dust_reach[1] if big else cfg.dust_reach[0])
			var spread := (1.0 - (1.0 - k01) * (1.0 - k01)) * far
			for k in n:
				var ang := _hash01(seed_n, k) * TAU
				var r := spread * (0.5 + 0.5 * _hash01(seed_n, k + 40))
				var p: Vector2 = e.pos + Vector2(cos(ang) * r, sin(ang) * r * 0.5 - 3.0 * k01 - 1.0)
				draw_rect(Rect2(p.round(), Vector2(2, 2)), c)


## Dark red splats where barbarians fell, one picture each from the stain sheet, faded in as the body lands and out at the end of its time.
func _draw_stains(view: Rect2) -> void:
	if sim.stain_pos.is_empty():
		return
	if _stain_sheet == null:
		_stain_sheet = _paint_stains()
	var cfg: Dictionary = sim.b.deaths
	var fade := float(cfg.stain_fade)
	var knock := float(cfg.knock)
	var topple := deg_to_rad(float(cfg.topple_degrees))
	var lean_least := float(cfg.least_lean)
	var torso := float(cfg.stain_torso)
	var fade_in := float(cfg.stain_in)
	var big := float(cfg.big_stain)
	var now := sim.time
	var area := view.grow(-40.0)
	for k in sim.stain_pos.size():
		var age := now - sim.stain_born[k]
		var life := sim.stain_life[k]
		if age < 0.0 or age >= life:
			continue
		var p := sim.stain_pos[k]
		if not area.has_point(p):
			continue
		var sz := sim.stain_size[k]
		var d := sim.stain_dir[k]
		var seed_n := sim.stain_seed[k]
		var row := 0 if sz <= 1.0 else (1 if sz <= big else 2)
		var cell := float(_stain_cells[row])
		var col := Sim.dir_index(d) * STAIN_SHAPES + posmod(seed_n, STAIN_SHAPES)
		var a := clampf((life - age) / fade, 0.0, 1.0) * clampf(age / fade_in, 0.0, 1.0)
		# The pool spreads under the body's middle, which lies to the side it toppled towards.
		var fell := signf(d.x) if absf(d.x) > 0.05 else (1.0 if seed_n % 2 == 0 else -1.0)
		var mid := (p + d * knock * sz + Vector2(fell * sin(topple * maxf(absf(d.x), lean_least)) * torso * sz, -2.0)).round()
		draw_texture_rect_region(_stain_sheet, Rect2(mid - Vector2(cell, cell) / 2.0, Vector2(cell, cell)), Rect2(col * cell, _stain_rows[row], cell, cell), Color(1, 1, 1, a))


## Paints every stain picture once: a row for ordinary, elite and chieftain sizes, each with STAIN_SHAPES shapes thrown along each of the eight directions.
func _paint_stains() -> Texture2D:
	var cfg: Dictionary = sim.b.deaths
	var sizes := [1.0, float(cfg.big_stain), float(sim.b.chief_death.stain)]
	var light: Array = cfg.stain
	var dark: Array = cfg.stain_dark
	var c := Color(float(light[0]), float(light[1]), float(light[2]), float(light[3]))
	var cd := Color(float(dark[0]), float(dark[1]), float(dark[2]), float(dark[3]))
	_stain_cells.clear()
	_stain_rows.clear()
	var tall := 0
	for sz in sizes:
		_stain_rows.append(tall)
		_stain_cells.append(int(ceil(32.0 * sz / 2.0)) * 2)
		tall += _stain_cells[-1]
	var img := Image.create(8 * STAIN_SHAPES * _stain_cells[2], tall, false, Image.FORMAT_RGBA8)
	for row in sizes.size():
		var sz: float = sizes[row]
		var cell: int = _stain_cells[row]
		for dir_i in 8:
			var d := Vector2.from_angle(dir_i * PI / 4.0)
			var side := d.orthogonal()
			for v in STAIN_SHAPES:
				var seed_n := 101 + v * 7919 + row * 31
				var mid := Vector2((dir_i * STAIN_SHAPES + v) * cell + cell / 2, _stain_rows[row] + cell / 2)
				var w := roundf((7.0 + 4.0 * _hash01(seed_n, 1)) * sz)
				var h := maxf(2.0, roundf((3.0 + 2.0 * _hash01(seed_n, 2)) * sz))
				_blob(img, mid, w, h, c)
				var lobe := (mid + d * w * 0.45 + side * roundf((_hash01(seed_n, 4) - 0.5) * 4.0)).round()
				_blob(img, lobe, roundf(w * 0.55), maxf(2.0, roundf(h * 0.7)), c)
				_blob(img, mid + Vector2(roundf((_hash01(seed_n, 5) - 0.5) * 2.0), 0), roundf(w * 0.45), maxf(1.0, roundf(h * 0.5)), cd)
				var drops := 2 + int(_hash01(seed_n, 3) * 3.0) + (3 if sz > 1.0 else 0)
				for j in drops:
					var out := w / 2.0 + 1.0 + (2.0 + 6.0 * _hash01(seed_n, 10 + j)) * sz
					var off := (_hash01(seed_n, 20 + j) - 0.5) * 6.0 * sz
					var dp := (mid + d * out + side * off).round()
					img.fill_rect(Rect2i(Vector2i(dp), Vector2i(2 if _hash01(seed_n, 30 + j) > 0.6 else 1, 1)), c)
	return ImageTexture.create_from_image(img)


## A rounded pixel splat w by h centred on p: a rectangle with its corners cut.
func _blob(img: Image, p: Vector2, w: float, h: float, c: Color) -> void:
	var corner := Vector2i(p - Vector2(floorf(w / 2.0), floorf(h / 2.0)))
	var wi := int(w)
	var hi := int(h)
	if hi <= 2 or wi <= 2:
		img.fill_rect(Rect2i(corner, Vector2i(wi, hi)), c)
		return
	img.fill_rect(Rect2i(corner + Vector2i(0, 1), Vector2i(wi, hi - 2)), c)
	img.fill_rect(Rect2i(corner + Vector2i(1, 0), Vector2i(wi - 2, hi)), c)
