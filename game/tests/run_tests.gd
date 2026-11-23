extends RefCounted
## Checks of the run's rules, run with: godot --headless --path game -- --run-tests

var failures := 0
var passes := 0
const WAITING_FOR_ART := []

# Built before their icons and small props are drawn; every other implemented entry must have all its art.
const NO_ICON_YET := []

var content: Content


func check(ok: bool, what: String) -> void:
	if ok:
		passes += 1
	else:
		failures += 1
		print("FAIL: ", what)


func run(balance: Dictionary) -> int:
	content = Content.load_all(Content.available_art())
	var only := OS.get_environment("ONLY_TESTS")
	for m in get_method_list():
		if m.name.begins_with("test_") and (only == "" or m.name.contains(only)):
			call(m.name, balance)
	print("%d passed, %d failed" % [passes, failures])
	if failures == 0 and passes > 0:
		print("ALL TESTS PASSED")
	return 1 if failures > 0 or passes == 0 else 0


func test_the_run_starts_with_the_commander_and_two_legionaries(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 1})
	check(s.soldiers.size() == 2, "two soldiers at the start")
	check(s.count("legionary") == 2, "both are legionaries")


func test_soldiers_reach_their_places_after_marching(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 2})
	Upgrades.apply(s, "archer")
	for i in 180:
		s.update(1.0 / 60.0, Vector2.RIGHT, false)
	for so in s.soldiers:
		var want: Vector2 = s.commander.pos + s.slot_of(so)
		check(so.pos.distance_to(want) < 6.0, "%s near its place" % so.type)


func test_coins_level_the_legion_up(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 3})
	s.gain(int(b.xp_first))
	check(s.level == 2, "first level reached")
	check(s.pending_levels == 1, "one choice waiting")
	check(s.xp_next == int(b.xp_first + b.xp_step), "next level needs more")


func test_a_killed_barbarian_drops_coins_and_is_removed(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 4})
	s.horde.spawn("barbarian_club", Vector2(300, 0))
	s.horde.spawn("barbarian_spear", Vector2(-300, 0))
	var id_left := s.horde.e_id[1]
	s.hit(0, 999.0)
	s._remove_dead()
	check(s.horde.e_pos.size() == 1, "one barbarian left")
	check(s.horde.e_id[0] == id_left, "the other barbarian kept its data")
	check(s.horde.e_pos[0] == Vector2(-300, 0), "and its place")
	check(s.c_pos.size() == 1 and s.c_val[0] == 1, "a coin dropped")
	check(s.kills == 1, "kill counted")


func test_barbarians_hurt_soldiers_they_reach(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 5})
	var club := s.horde.spawn("barbarian_club", s.commander.pos + Vector2(10, 0))
	s.horde.e_hp[club] = 1e6
	s.horde.e_max[club] = 1e6
	var before: float = s.commander.hp
	for i in 30:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.commander.hp < before, "the commander was hurt")


func test_testudo_cuts_the_harm_taken(b: Dictionary) -> void:
	var plain := Sim.new(b, content, {"seed": 6})
	var shielded := Sim.new(b, content, {"seed": 6})
	for s in [plain, shielded]:
		s.soldiers.clear()
		s.horde.spawn("barbarian_club", Vector2(10, 0))
	shielded.update(1.0 / 60.0, Vector2.ZERO, true)
	plain.update(1.0 / 60.0, Vector2.ZERO, false)
	for i in 30:
		plain.update(1.0 / 60.0, Vector2.ZERO, false)
		shielded.update(1.0 / 60.0, Vector2.ZERO, false)
	var lost_plain: float = plain.commander.max_hp - plain.commander.hp
	var lost_shielded: float = shielded.commander.max_hp - shielded.commander.hp
	check(lost_shielded < lost_plain * 0.4, "testudo takes much less harm (%.1f vs %.1f)" % [lost_shielded, lost_plain])
	check(shielded.testudo_charge == 0.0, "the charge is spent")


## A quiet field with the commander and one soldier of `type` 20 px to his right, both too tough to fall, and the testudo up or down.
func _one_soldier(b: Dictionary, seed_value: int, type: String, testudo: bool) -> Sim:
	var s := _quiet_sim(b, seed_value, Content.with_all_art())
	s.soldiers.clear()
	s.add_soldier(type)
	var u: Dictionary = s.soldiers[0]
	u.pos = s.commander.pos + Vector2(20, 0)
	for m in [u, s.commander]:
		m.hp = 1e6
		m.max_hp = 1e6
	s.testudo_left = 5.0 if testudo else 0.0
	s._rebuild_grids()
	return s


func test_the_shield_bearers_carry_shields(b: Dictionary) -> void:
	for type in ["legionary", "standard_bearer"]:
		check(content.recruits[type].get("shield", false), "the %s carries a shield into the testudo" % type)
	for type in ["archer", "cavalry", "medicus", "ballista", "centurion"]:
		check(not content.recruits[type].get("shield", false), "the %s has no place in the testudo" % type)
	check(content.base_commander.get("shield", false), "and so does the commander")
	var s := _one_soldier(b, 6100, "legionary", true)
	s.add_soldier("archer")
	check(Sim.shielded(s.soldiers[0]) and Sim.shielded(s.commander) and not Sim.shielded(s.soldiers[1]), "a soldier knows whether he carries one")
	check(is_equal_approx(s.testudo_guard(s.soldiers[0]), float(b.testudo_damage_taken)) and s.testudo_guard(s.soldiers[1]) == 1.0, "and only a shield-bearer is guarded by the testudo")
	s.testudo_left = 0.0
	check(s.testudo_guard(s.soldiers[0]) == 1.0, "nobody is once it is down")


func test_the_testudo_cuts_a_blow_only_for_the_shield_bearers(b: Dictionary) -> void:
	var lost := {}
	for c in [["legionary", true], ["archer", true], ["archer", false]]:
		var s := _one_soldier(b, 6101, c[0], c[1])
		var u: Dictionary = s.soldiers[0]
		var i := s.horde.spawn("barbarian_club", u.pos + Vector2(10, 0))
		s.horde.e_cd[i] = 1e9
		for k in 30:
			s._rebuild_grids()
			s.horde._move(1.0 / 60.0, s)
		lost["%s %s" % c] = 1e6 - u.hp
	var bare: float = lost["archer false"]
	check(bare > 0.0, "a club hurts a soldier beside him (%.1f)" % bare)
	check(is_equal_approx(lost["archer true"], bare), "under the testudo an archer still takes the whole blow (%.1f of %.1f)" % [lost["archer true"], bare])
	check(is_equal_approx(lost["legionary true"], bare * float(b.testudo_damage_taken)), "while a legionary takes the cut blow (%.1f)" % lost["legionary true"])


func test_the_testudo_stops_missiles_only_at_the_shield_bearers(b: Dictionary) -> void:
	for type in ["legionary", "archer"]:
		for kind in [0, 2]:
			var s := _one_soldier(b, 6102, type, true)
			var u: Dictionary = s.soldiers[0]
			s.horde.sling_stun = 1.0
			s.horde._throw(u.pos + Vector2(80, 0), Vector2.LEFT, 10.0, kind)
			for k in 120:
				s.horde._spears(1.0 / 60.0, s)
			var what := "sling stone" if kind == 2 else "spear"
			check(s.horde.sp_pos.is_empty() and s.commander.hp == 1e6, "the %s is spent before the commander (%s)" % [what, type])
			if type == "legionary":
				check(u.hp == 1e6 and u.get("dazed", 0.0) <= 0.0, "a legionary's shield stops a %s" % what)
			else:
				check(is_equal_approx(1e6 - u.hp, 10.0), "an archer takes a whole %s (%.1f)" % [what, 1e6 - u.hp])
				if kind == 2:
					check(u.get("dazed", 0.0) > 0.0, "and is left reeling by the stone")


func test_the_testudo_turns_marked_blows_only_for_the_shield_bearers(b: Dictionary) -> void:
	for ward in [false, true]:
		var s := _one_soldier(b, 6103, "legionary", true)
		s.add_soldier("archer")
		var legionary: Dictionary = s.soldiers[0]
		var archer: Dictionary = s.soldiers[1]
		archer.hp = 1e6
		archer.max_hp = 1e6
		archer.pos = s.commander.pos + Vector2(-200, 0)
		legionary.pos = s.commander.pos + Vector2(200, 0)
		s._rebuild_grids()
		for at in [legionary.pos, archer.pos]:
			s.horde.foe_lobs.append({"from": at, "to": at, "t": 0.0, "dur": 0.1, "radius": 12.0, "dmg": 10.0, "slam": true, "ward": ward})
		s.horde._foe_lobs(0.2, s)
		var what := "a whirl" if ward else "a falling ring"
		check(is_equal_approx(1e6 - archer.hp, 10.0), "%s takes its whole harm from an archer under the testudo (%.1f)" % [what, 1e6 - archer.hp])
		var want := 0.0 if ward else 10.0 * float(b.testudo_damage_taken)
		check(is_equal_approx(1e6 - legionary.hp, want), "and %.0f from a legionary (%.1f)" % [want, 1e6 - legionary.hp])


func test_a_big_shadow_is_drawn_at_its_own_size(_b: Dictionary) -> void:
	var view: GDScript = load("res://scripts/world_view.gd")
	var img: Image = view.shadow_image(48)
	check(img.get_size() == Vector2i(48, 18), "a 48 wide shadow is a 48 by 18 picture (%s)" % str(img.get_size()))
	check(absf(img.get_pixel(24, 9).a - 0.38) < 0.01 and img.get_pixel(0, 0).a == 0.0, "it is dark in the middle and clear in the corners")
	var row := 0
	for x in 48:
		if img.get_pixel(x, 9).a > 0.0:
			row += 1
	check(row >= 46, "its middle row spans the width (%d)" % row)
	check(view.shadow_image(16).get_size() == Vector2i(16, 6), "a small one keeps 16 by 6")


func test_the_testudo_tint_shows_on_the_shield_bearers(b: Dictionary) -> void:
	var view: GDScript = load("res://scripts/world_view.gd")
	var s := _one_soldier(b, 6104, "legionary", true)
	s.add_soldier("archer")
	var legionary: Dictionary = s.soldiers[0]
	var archer: Dictionary = s.soldiers[1]
	check(view.legion_tint(s, legionary) == view.TESTUDO_TINT and view.legion_tint(s, s.commander) == view.TESTUDO_TINT, "the commander and the legionary turn gold under the testudo")
	check(view.legion_tint(s, archer) == Color.WHITE, "the archer does not")
	s.testudo_left = 0.0
	check(view.legion_tint(s, legionary) == Color.WHITE, "nor does anyone once it is down")


func test_a_charge_rides_through_a_testudo_of_archers(b: Dictionary) -> void:
	var s := _gaul_sim(b, 6105, "hispania")
	s.soldiers.clear()
	for k in 10:
		s.add_soldier("archer")
	s.commander.pos = Vector2.ZERO
	s.legion.place_all(s.facing_angle)
	s._rebuild_grids()
	var r := float(content.enemies.lusitanian_raider.radius)
	var i := s.horde.spawn("lusitanian_raider", Vector2(-s.legion_reach - r - 120.0, 0), true)
	var st: Dictionary = s.horde.boss_state(i)
	for key in st:
		if str(key).ends_with("_cd"):
			st[key] = 1e9
	st.onrush_cd = 0.0
	var men: Array = s.soldiers.duplicate()
	var places: Array = men.map(func(so: Dictionary) -> Vector2: return so.pos)
	var thrown := 0.0
	for k in 3 * 60:
		s.testudo_left = 5.0
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		for n in men.size():
			thrown = maxf(thrown, men[n].pos.distance_to(places[n]))
	check(thrown >= 12.0, "archers in the testudo have no shields to stop a charge, which throws them aside (%.0f px)" % thrown)


func test_arms_stop_at_their_last_level(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 8})
	for i in 9:
		Upgrades.apply(s, "pilum")
	check(s.rank("pilum") == 9, "ranks counted")
	check(not Upgrades.available(s).has("pilum"), "a maxed weapon is not offered")


func test_burning_arrows_need_archers(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 9})
	check(not Upgrades.available(s).has("fire_arrows"), "no burning arrows without archers")
	Upgrades.apply(s, "archer")
	check(Upgrades.available(s).has("fire_arrows"), "offered once archers join")


func test_offers_are_three_different_choices(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 10})
	for i in 20:
		var o := Upgrades.offers(s)
		check(o.size() == 3, "three choices")
		check(o[0] != o[1] and o[1] != o[2] and o[0] != o[2], "all different")


func test_pilum_volley_kills_a_lone_barbarian(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 11})
	Upgrades.apply(s, "pilum")
	s.horde.spawn("barbarian_club", Vector2(120, 0))
	for i in 120:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.kills >= 1, "the pilum found its mark")


func test_pila_are_thrown_only_ahead(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 11})
	s.b = b.duplicate()
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	Upgrades.apply(s, "pilum")
	s.horde.spawn("barbarian_club", s.commander.pos - Vector2.from_angle(s.facing_angle) * 120.0)
	for i in 240:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.damage_by_source.get("pilum", 0.0) == 0.0, "no pilum flies at a barbarian behind the legion")


func test_soldiers_gather_coins_for_the_commander(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 13})
	s.b = b.duplicate()
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	for i in 30:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	var far: Dictionary = s.soldiers[0]
	far.pos = s.commander.pos + Vector2(80, 0)
	s.drop_coin(far.pos + Vector2(4, 0), 1)
	var before := s.xp + (s.level - 1) * 1000
	for i in 120:
		far.pos = s.commander.pos + Vector2(80, 0)
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.c_pos.is_empty(), "the coin by the soldier was gathered")
	check(s.xp + (s.level - 1) * 1000 > before, "and counted for the legion")


func test_solid_props_block_the_march(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 120})
	s.terrain.clear()
	s.terrain.empty = false
	s.terrain._chunks[Vector2i(0, 0)] = [["rock", Vector2(60, 0), 10.0]]
	s.terrain._anchor = Vector2i(1 << 30, 0)
	s.terrain.refresh(s.commander.pos)
	for f in 120:
		s.update(1.0 / 60.0, Vector2.RIGHT, false)
	var rock_side: bool = absf(s.commander.pos.y) < 1.0 and s.commander.pos.x < 60.0
	check(s.commander.pos.distance_to(Vector2(60, 0)) >= 10.0 + Sim.UNIT_RADIUS - 0.5, "the commander never stands inside the rock")
	check(rock_side or s.commander.pos.x > 60.0, "he stops at it or slides round it")


func test_a_ridge_is_long_and_too_tight_to_walk_through(b: Dictionary) -> void:
	var t := Terrain.new(7, b.forest)
	var found := false
	var longest := 0.0
	var crosses := false
	for rx in 6:
		for ry in 6:
			var trees: Array = []
			for p in t._region(rx, ry):
				if p[0] == "oak" or p[0] == "fir":
					trees.append(p[1])
			if trees.size() < 20:
				continue
			found = true
			var box := Rect2(trees[0], Vector2.ZERO)
			var widest := 0.0
			for a in trees:
				box = box.expand(a)
				var nearest := INF
				for c in trees:
					if a != c:
						nearest = minf(nearest, a.distance_to(c))
				widest = maxf(widest, nearest)
			check(widest - 2.0 * 8.0 < 2.0 * Sim.UNIT_RADIUS, "no gap in a ridge lets a soldier through (%.1f)" % widest)
			longest = maxf(longest, box.size.length())
			crosses = crosses or not Rect2(Vector2(rx, ry) * Terrain.REGION, Vector2.ONE * Terrain.REGION).encloses(box)
	check(found, "a ridge appears within a few regions")
	check(longest >= float(b.forest.length[0]), "a ridge runs a long way (%.0f px)" % longest)
	check(crosses, "ridges reach over the edges of their regions")


## The squares of `cell` px round the start that a soldier can stand in, out to `reach`, and how far out the legion can walk from the start.
func _escape(t: Terrain, reach: float) -> Dictionary:
	var cell := 16.0
	var n := int(reach * 2.0 / cell)
	var corner := Vector2(-reach, -reach)
	var blocked := PackedByteArray()
	blocked.resize(n * n)
	for pr in t.props_in(Rect2(corner, Vector2.ONE * reach * 2.0)):
		if pr[2] <= 0.0:
			continue
		var r: float = pr[2] + Sim.UNIT_RADIUS
		for gx in range(maxi(0, floori((pr[1].x - r - corner.x) / cell)), mini(n, ceili((pr[1].x + r - corner.x) / cell))):
			for gy in range(maxi(0, floori((pr[1].y - r - corner.y) / cell)), mini(n, ceili((pr[1].y + r - corner.y) / cell))):
				if (corner + (Vector2(gx, gy) + Vector2(0.5, 0.5)) * cell).distance_to(pr[1]) < r:
					blocked[gx + gy * n] = 1
	if not t.ravines_in(Rect2(corner, Vector2.ONE * reach * 2.0)).is_empty():
		for c in n * n:
			if t.ravine_edge(corner + (Vector2(c % n, c / n) + Vector2(0.5, 0.5)) * cell) < Sim.UNIT_RADIUS:
				blocked[c] = 1
	var seen := PackedByteArray()
	seen.resize(n * n)
	var queue := PackedInt32Array([n / 2 + (n / 2) * n])
	seen[queue[0]] = 1
	var head := 0
	var octants := {}
	while head < queue.size():
		var c := queue[head]
		head += 1
		var p := corner + (Vector2(c % n, c / n) + Vector2(0.5, 0.5)) * cell
		if p.length() > reach - 2.0 * cell:
			octants[posmod(int(floor(p.angle() / (TAU / 8.0))), 8)] = true
		for st in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var x: int = c % n + st.x
			var y: int = c / n + st.y
			if x < 0 or y < 0 or x >= n or y >= n or seen[x + y * n] == 1 or blocked[x + y * n] == 1:
				continue
			seen[x + y * n] = 1
			queue.append(x + y * n)
	return {"octants": octants.size()}


func test_the_legion_can_always_march_out_of_the_start(b: Dictionary) -> void:
	var fewest := 8
	for k in 24:
		var t := Terrain.new(1000 + k * 37, b.forest, b.ravines)
		fewest = mini(fewest, _escape(t, 900.0).octants)
	check(fewest >= 3, "from every start the open ground reaches the far ring in several directions (fewest %d of 8)" % fewest)


func test_the_forest_is_neither_maze_nor_open_field(b: Dictionary) -> void:
	var t := Terrain.new(55, b.forest)
	var trees := 0
	for pr in t.props_in(Rect2(-2400, -2400, 4800, 4800)):
		if pr[0] == "oak" or pr[0] == "fir":
			trees += 1
	# Ridges cover roughly a tenth to a third of the ground, one tree to every 420 square px inside them.
	var share := trees * 420.0 / (4800.0 * 4800.0)
	check(share > 0.08 and share < 0.35, "ridges cover %.0f%% of the ground" % (share * 100.0))


func test_a_war_band_arrives_together(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 121})
	s.b = b.duplicate()
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	s.horde.next_surge = 1e9
	s.time = float(b.war_band.first) - 0.01
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.horde.e_pos.size() == int(b.war_band.size_start), "the band has its size (%d)" % s.horde.e_pos.size())
	var centre := Vector2.ZERO
	for p in s.horde.e_pos:
		centre += p
	centre /= maxf(1.0, s.horde.e_pos.size())
	var tight := true
	for p in s.horde.e_pos:
		tight = tight and p.distance_to(centre) <= float(b.war_band.spread) * 2.0
	check(tight, "its men stand close together")
	var apart := INF
	for i in s.horde.e_pos.size():
		for j in range(i + 1, s.horde.e_pos.size()):
			apart = minf(apart, s.horde.e_pos[i].distance_to(s.horde.e_pos[j]))
	check(apart >= float(b.war_band.spread) * 0.5, "and none stands on another (%.0f px apart)" % apart)


func test_warriors_on_foot_never_outpace_the_legion(b: Dictionary) -> void:
	var cap := float(b.foot_pace) * float(content.base_commander.speed)
	check(cap < float(content.base_commander.speed), "the cap is below the legion's march")
	for province in content.provinces:
		var s := Sim.new(b, Content.with_all_art(), {"seed": 130, "province": province})
		s.commander.max_hp = 1e9
		s.commander.hp = 1e9
		var h := s.horde
		for id in h.ordinary:
			var i := h.spawn(id, s.commander.pos + Vector2(300, 0))
			# Hastened by a rally and rushing with a war band at once, he still walks no faster than the cap.
			h.hasten(i, 10.0, 2.0)
			h.e_slow[i] = float(b.war_band.rush)
			h.e_cd[i] = 1e9
			var from := h.e_pos[i]
			h.rebuild_grid()
			h._move(0.1, s)
			var pace := h.e_pos[i].distance_to(from) / 0.1
			if h.k_foot[h.e_kind[i]] == 1:
				check(pace <= cap + 0.5, "a %s in %s walks at %.0f, within %.0f" % [id, province, pace, cap])
			h.remove_at(i)
	var s := Sim.new(b, Content.with_all_art(), {"seed": 131})
	var w := s.horde.spawn("wolf", s.commander.pos + Vector2(300, 0))
	var from := s.horde.e_pos[w]
	s.horde.rebuild_grid()
	s.horde._move(0.1, s)
	check(s.horde.e_pos[w].distance_to(from) / 0.1 > cap, "a wolf still runs faster")


func test_every_full_choice_holds_a_recruit(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 122})
	var always := true
	var pair := true
	for k in 50:
		var picks := Upgrades.offers(s)
		var has := false
		var two := false
		for id in picks:
			has = has or s.content.recruits.has(id)
			two = two or (s.content.recruits.has(id) and int(s.content.recruits[id].per_pick) > 1)
		always = always and has
		pair = pair and two
	check(always, "fifty sets of choices each held a recruit")
	check(pair, "and each a recruit who brings two men")


func _quiet_sim(b: Dictionary, seed_value: int, art: Content = null) -> Sim:
	var s := Sim.new(b, art if art != null else content, {"seed": seed_value})
	s.terrain.clear()
	s.b = b.duplicate()
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	s.horde.next_surge = 1e9
	s.horde.next_band = 1e9
	s.horde.next_cart = 1e9
	s.horde.next_boss = 1e9
	return s


func test_a_crowd_in_melee_holds_the_legion_back(b: Dictionary) -> void:
	var s := _quiet_sim(b, 130)
	var free := s.speed()
	s.pressing = 10
	check(s.speed() < free * 0.5, "ten barbarians in melee more than halve the march (%.0f of %.0f)" % [s.speed(), free])
	s.pressing = 1000
	check(is_equal_approx(s.speed(), free * float(b.press.slowest)), "but never stop it dead")


func test_only_barbarians_in_the_way_hold_the_legion_back(b: Dictionary) -> void:
	check(float(b.press.slowest) >= 0.45, "a crowd never takes the march below nearly half (%.2f)" % float(b.press.slowest))
	for ahead in [false, true]:
		var s := _quiet_sim(b, 133)
		s.commander.hp = 1e9
		s.commander.max_hp = 1e9
		s.facing_angle = 0.0
		var side := 1.0 if ahead else -1.0
		for k in 6:
			var i := s.horde.spawn("barbarian_club", s.commander.pos + Vector2(side * 14.0, -15.0 + k * 6.0))
			s.horde.e_stun[i] = 0.0
			s.horde.e_hp[i] = 1e9
			s.horde.e_max[i] = 1e9
		for k in 20:
			s.update(1.0 / 60.0, Vector2.RIGHT, false)
		if ahead:
			check(s.pressing >= 1, "barbarians locked in melee across the legion's way hold it back (%d)" % s.pressing)
		else:
			check(s.pressing == 0, "barbarians fighting its rear do not hold back a legion marching away (%d)" % s.pressing)


func test_barbarians_find_a_way_round_a_wall(b: Dictionary) -> void:
	var s := _quiet_sim(b, 131)
	s.terrain.empty = false
	var top: Array = []
	var bottom: Array = []
	for k in 13:
		var tree := ["fir", Vector2(100, -130 + k * 22), 8.0]
		(top if tree[1].y < 0 else bottom).append(tree)
	s.terrain._chunks[Vector2i(0, -1)] = top
	s.terrain._chunks[Vector2i(0, 0)] = bottom
	s.terrain._anchor = Vector2i(1 << 30, 0)
	s.terrain.refresh(s.commander.pos)
	s.terrain.update_flow(s.commander.pos)
	s.commander.hp = 1e9
	for i in 10:
		s.horde.spawn("barbarian_spear", Vector2(200, -30 + i * 6))
	_step_dt(s, 15.0)
	var behind := 0
	for p in s.horde.e_pos:
		if p.x > 100.0:
			behind += 1
	check(behind <= 2, "after fifteen seconds most have gone round the wall (%d still behind)" % behind)


func test_a_supply_cart_stands_still(b: Dictionary) -> void:
	var s := _quiet_sim(b, 132, Content.with_all_art())
	s.horde.spawn_cart()
	var at: Vector2 = s.horde.carts[0].pos
	var gap := at.distance_to(s.commander.pos)
	check(gap > float(b.cart.near) * 0.9 and gap < float(b.cart.far) * 1.7, "it stands near the legion (%.0f)" % gap)
	s.commander.pos = Vector2(-500, 0)
	_step_dt(s, 5.0)
	check(not s.horde.carts.is_empty() and s.horde.carts[0].pos == at, "and does not move")


func test_a_soldier_picks_up_a_chest(b: Dictionary) -> void:
	var s := _quiet_sim(b, 134, Content.with_all_art())
	s.commander.hp = 1e9
	s.legion.soldiers.clear()
	Upgrades.apply(s, "legionary")
	s.legion.place_all(0.0)
	var man: Vector2 = s.soldiers[0].pos
	s.horde.chests.append({"pos": man})
	check(man.distance_to(s.commander.pos) > float(b.chest.radius), "the soldier stands away from the commander")
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.horde.chests.is_empty() and s.free_choices == 1, "a soldier touching the chest takes it for a free choice")


func test_the_first_supply_cart_says_what_carts_are_for(b: Dictionary) -> void:
	var s := _quiet_sim(b, 135, Content.with_all_art())
	s.objectives.notice = {}
	s.horde.spawn_cart()
	check(s.objectives.notice.get("kind", "") == "cart_tip", "a hint comes with the first cart (%s)" % [s.objectives.notice])
	s.objectives.notice = {}
	s.horde.spawn_cart()
	check(s.objectives.notice.is_empty(), "and only with the first")


func test_bosses_never_crowd_in_more_than_the_limit(b: Dictionary) -> void:
	var s := _quiet_sim(b, 136, Content.with_all_art())
	s.horde.pursuit = float(b.pursuit.cap)
	check(s.horde.hunted_bosses() == 0, "a legion on the run is not sent extra bosses")
	check(int(b.bosses.max_alive) <= 3, "no more than three bosses at once (%d)" % int(b.bosses.max_alive))
	var before := s.horde.next_boss
	s.horde.next_boss = 500.0
	s.time = 100.0
	s.horde.time = 100.0
	s.update(1.0 / 60.0, Vector2(1, 0), false)
	check(s.horde.next_boss == 500.0, "running does not bring the next boss sooner")
	s.horde.next_boss = before


func test_a_war_priest_burns_only_the_ring(b: Dictionary) -> void:
	for testudo in [false, true]:
		var s := _quiet_sim(b, 133, Content.with_all_art())
		s.commander.hp = 1e9
		s.commander.max_hp = 1e9
		var victim: Dictionary = s.soldiers[0]
		var other: Dictionary = s.soldiers[1]
		victim.pos = Vector2(300, 300)
		other.pos = Vector2(400, 300)
		s._rebuild_grids()
		var hp0: float = victim.hp
		s.horde.foe_lobs.append({"from": Vector2(500, 300), "to": victim.pos, "t": 0.0, "dur": 0.1, "radius": 20.0, "dmg": 10.0})
		if testudo:
			s.testudo_left = 3.0
		s.horde._foe_lobs(0.2, s)
		var want := 10.0 * (float(b.testudo_damage_taken) if testudo else 1.0)
		check(is_equal_approx(hp0 - victim.hp, want), "the soldier in the ring loses %.0f (testudo %s)" % [want, testudo])
		check(other.hp == other.max_hp, "the soldier outside it is untouched")


func test_a_war_band_leader_rallies_those_near_him(b: Dictionary) -> void:
	var s := _quiet_sim(b, 134, Content.with_all_art())
	var leader := s.horde.spawn("war_band_leader", Vector2(300, 0), true)
	var near := s.horde.spawn("barbarian_club", Vector2(320, 0))
	var far := s.horde.spawn("barbarian_club", Vector2(300, 600))
	s.horde.rally_cd[s.horde.e_id[leader]] = 0.01
	s.horde._rally(0.05, s)
	check(s.horde.e_haste[near] > 0.0, "a man beside him is rallied")
	check(s.horde.e_haste[far] == 0.0, "a man far off is not")


func test_marching_soldiers_walk(b: Dictionary) -> void:
	var s := _quiet_sim(b, 140)
	for f in 90:
		s.update(1.0 / 60.0, Vector2.RIGHT, false)
	var all := true
	for so in s.soldiers:
		all = all and so.moving
	check(all, "every soldier shows his walk while the legion marches")


func test_a_wedged_barbarian_slips_free(b: Dictionary) -> void:
	var s := _quiet_sim(b, 141)
	s.terrain.empty = false
	var ring: Array = []
	for k in 10:
		ring.append(["fir", Vector2(300, 0) + Vector2.from_angle(k * TAU / 10.0) * 18.0, 8.0])
	s.terrain._chunks[Vector2i(1, 0)] = ring
	s.terrain._anchor = Vector2i(1 << 30, 0)
	s.terrain.refresh(s.commander.pos)
	s.commander.hp = 1e9
	s.horde.spawn("barbarian_spear", Vector2(300, 0))
	_step_dt(s, 6.0)
	check(s.horde.e_pos.size() == 1 and s.horde.e_pos[0].distance_to(Vector2(300, 0)) > 30.0, "a barbarian boxed in by trees gets out (%.0f px)" % s.horde.e_pos[0].distance_to(Vector2(300, 0)))


func test_newcomers_arrive_on_open_ground(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 142})
	var open := 0
	for k in 200:
		if s.terrain.is_open(s.horde.ring_point()):
			open += 1
	check(open >= 195, "stream arrivals stand clear of the forest (%d of 200)" % open)


func test_lorica_raises_health(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 12})
	var before: float = s.commander.max_hp
	Upgrades.apply(s, "lorica")
	check(s.commander.max_hp > before, "the commander's health rose")
	check(s.soldiers[0].max_hp > float(content.recruits.legionary.hp), "the soldiers' health rose")
	Upgrades.apply(s, "legionary")
	check(s.soldiers[-1].max_hp > float(content.recruits.legionary.hp), "new recruits arrive with it")


## Kills the chieftain, then stands the commander in the fort until it is held.
func _kill_chief_and_hold(s: Sim, b: Dictionary) -> void:
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	s.hit(s.chieftain_index(), 1e9)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	s.commander.pos = s.objectives.fort.centre
	_step_dt(s, float(b.fort.hold) + 0.2)


func test_the_chieftain_comes_and_holding_the_fort_after_his_death_wins(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 13})
	s.time = float(b.chieftain_at) - 0.01
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var ci := s.chieftain_index()
	check(ci >= 0, "the chieftain arrived")
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	s.hit(ci, 1e9)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	_step_dt(s, 1.0)
	check(not s.victory and s.objectives.notice.get("kind", "") == "chieftain", "his death alone does not win, and a notice sends the legion to the fort")
	s.commander.pos = s.objectives.fort.centre
	_step_dt(s, float(b.fort.hold) + 0.2 + float(b.triumph.most_seconds))
	check(s.over and s.victory, "holding the fort then ends the run in victory, after its triumph")


func test_the_chieftain_killed_by_the_triumph_does_not_win_again(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 13})
	s.time = float(b.chieftain_at) - 0.01
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	s.win(s.commander.pos)
	s.events.clear()
	s.triumph_left = 1.0
	s._kill(s.chieftain_index())
	var again := s.events.filter(func(e): return e.kind == "victory").size()
	check(again == 0 and is_equal_approx(s.triumph_left, 1.0), "the chieftain dying in the triumph after a held fort does not play the win again")


func test_the_commanders_death_loses(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 14})
	s.commander.hp = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.over and not s.victory, "the run is lost")


func test_fallen_soldiers_leave_the_formation(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 15})
	s.soldiers[0].hp = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.soldiers.size() == 1, "one soldier left")


func test_the_horde_grows_over_time(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 16})
	s.terrain.clear()
	s.soldiers.clear()
	s.commander.hp = 1e9
	for i in 30 * 30:
		s.update(1.0 / 30.0, Vector2.ZERO, false)
	var half := s.horde.e_pos.size()
	for i in 30 * 30:
		s.update(1.0 / 30.0, Vector2.ZERO, false)
	check(s.horde.e_pos.size() > 20 and s.horde.e_pos.size() > half, "a growing crowd after a minute (%d, %d at half a minute)" % [s.horde.e_pos.size(), half])


func test_far_barbarians_give_up_the_chase(b: Dictionary) -> void:
	var s := _quiet_sim(b, 17)
	s.commander.hp = 1e9
	s.horde.spawn("barbarian_club", Vector2(float(b.give_up_radius) + 40.0, 0))
	s.horde.spawn("barbarian_club", Vector2(float(b.give_up_radius) - 60.0, 0))
	var kills := s.kills
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.horde.e_pos.size() == 1, "the one left far behind is gone (%d left)" % s.horde.e_pos.size())
	check(s.kills == kills and s.c_pos.is_empty(), "he leaves without counting as a kill or dropping a coin")
	check(float(b.give_up_radius) > Horde.view.x / 2.0 + 64.0, "nobody vanishes in view")
	var riders := _britannia_sim(b, 18)
	riders.commander.hp = 1e9
	var c := riders.horde.spawn("chariot", Vector2(float(b.give_up_radius) + 40.0, 0))
	var id: int = riders.horde.e_id[c]
	riders.update(1.0 / 60.0, Vector2.ZERO, false)
	check(riders.horde.e_id.has(id), "a chariot swinging wide on its pass keeps coming")


func test_a_barbarian_giving_up_stays_until_the_legion_has_fought(b: Dictionary) -> void:
	var s := _quiet_sim(b, 19)
	s.commander.hp = 1e9
	for k in 6:
		s.add_soldier("archer")
	s.legion.place_all(s.facing_angle)
	s.horde.spawn("barbarian_club", Vector2(float(b.give_up_radius) + 40.0, 0))
	var near := s.horde.spawn("barbarian_club", Vector2(90, 0))
	s.horde.e_stun[near] = 1e9
	s._rebuild_grids()
	s.horde.update(1.0 / 60.0, s)
	var stale := 0
	for t in s.horde.g_items:
		if t >= s.horde.e_pos.size():
			stale += 1
	check(stale == 0 and s.horde.e_pos.size() == 2, "the horde's move leaves every enemy the grid lists in place (%d stale)" % stale)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.horde.e_pos.size() == 1, "and the one left behind is gone once the update is over")


func test_a_crowd_never_throws_a_boss_faster_than_his_charge(b: Dictionary) -> void:
	for kind in ["berserker", "war_band_leader", "barbarian_club"]:
		var s := Sim.new(b, content, {"seed": 17})
		s.terrain.clear()
		var at: Vector2 = s.commander.pos + Vector2(220, 0)
		var i := s.horde.spawn(kind, at, kind != "barbarian_club")
		var id := s.horde.e_id[i]
		for k in 60:
			s.horde.spawn("barbarian_club", at + Vector2.from_angle(k * 0.7) * (k % 5))
		var dt := 1.0 / 30.0
		var cap: float = s.horde.k_top[s.horde.e_kind[i]] * (float(b.crowd_pace) if kind == "barbarian_club" else 1.0) * dt
		var worst := 0.0
		for t in 30:
			var j := s.horde.e_id.find(id)
			var before := s.horde.e_pos[j]
			s.update(dt, Vector2.ZERO, false)
			j = s.horde.e_id.find(id)
			if j >= 0:
				worst = maxf(worst, before.distance_to(s.horde.e_pos[j]))
		check(worst <= cap + 0.01, "%s in a packed crowd moves at most %.1f px a step (%.1f)" % [kind, cap, worst])


func test_hard_kills_pay_more_denarii_but_no_more_experience(b: Dictionary) -> void:
	var medium := Sim.new(b, content, {"seed": 18})
	var hard := Sim.new(b, content, {"seed": 18, "difficulty": "hard"})
	medium.gain(int(200 * float(b.medium.denarii_mult)))
	hard.gain(int(200 * float(b.hard.denarii_mult)))
	check(hard.denarii > medium.denarii, "Hard pays more denarii")
	check(absi(hard.level - medium.level) == 0 and absi(hard.xp - medium.xp) <= 1, "but the same experience (%d/%d against %d/%d)" % [hard.level, hard.xp, medium.level, medium.xp])


func test_every_direction_has_a_name(b: Dictionary) -> void:
	check(Sim.dir_name(Vector2.RIGHT) == "east", "right is east")
	check(Sim.dir_name(Vector2.DOWN) == "south", "down is south")
	check(Sim.dir_name(Vector2(-1, -1)) == "north-west", "up-left is north-west")


func test_content_without_art_is_hidden(b: Dictionary) -> void:
	var bare := Content.load_all({})
	check(not bare.ready("recruits", "legionary"), "no art, no recruit")
	check(not bare.ready("arms", "pilum"), "no art, no weapon")
	var drawn := Content.load_all({"unit:legionary": true, "icon:legionary": true})
	check(drawn.ready("recruits", "legionary"), "with its art the recruit shows")
	check(not drawn.ready("recruits", "archer"), "a recruit missing only some art stays hidden")


func test_germania_has_the_existing_enemies(b: Dictionary) -> void:
	check(content.province_enemies("germania") == content.provinces.germania.ordinary, "every Germanic enemy is drawn")
	check(_with_undrawn(content).province_enemies("hibernia").is_empty(), "a province with no art has no enemies")


func test_every_content_entry_has_a_name_and_text(b: Dictionary) -> void:
	for kind in ["recruits", "enemies", "arms", "forged", "drills", "provinces", "commanders", "quartermaster", "achievements"]:
		var entries: Dictionary = content.get(kind)
		check(not entries.is_empty(), "%s is not empty" % kind)
		for id in entries:
			check(str(entries[id].get("name", "")) != "", "%s %s has a name" % [kind, id])
			check(str(entries[id].get("text", "")) != "", "%s %s has a text" % [kind, id])
	check(content.recruits.size() == 7 and content.arms.size() == 12 and content.forged.size() == 6 and content.drills.size() == 15, "the full set of recruits, arms, forged forms and drills")
	check(content.provinces.size() == 8 and content.commanders.size() == 6, "eight provinces and six commanders")
	for p in content.provinces:
		var pr: Dictionary = content.provinces[p]
		check(pr.ordinary.size() == 4 and pr.elites.size() >= 2 and content.enemies.has(pr.chieftain), "%s has its enemies" % p)


func test_every_implemented_entry_is_ready_and_complete(b: Dictionary) -> void:
	for kind in ["recruits", "arms", "forged", "drills"]:
		var entries: Dictionary = content.get(kind)
		for id in entries:
			var e: Dictionary = entries[id]
			if not e.get("implemented", false):
				continue
			# These recruits are implemented before their sprites are drawn; the art gate keeps them hidden.
			if not (kind == "recruits" and WAITING_FOR_ART.has(id)) and not _art_waiting(kind, id):
				check(content.ready(kind, id), "%s %s has all its art" % [kind, id])
			check(str(e.get("name", "")) != "" and str(e.get("text", "")) != "", "%s %s has a name and text" % [kind, id])
			if kind != "recruits":
				check(int(e.get("max", 0)) > 0, "%s %s has a last level" % [kind, id])


## Arms, forged forms and drills are built before their icons and small props are drawn; the art gate keeps them hidden.
func _art_waiting(kind: String, id: String) -> bool:
	return kind != "recruits" and NO_ICON_YET.has(id)


## A copy of the content in which every art key exists, so offers can be tested before the art is drawn.
func _full_content() -> Content:
	var keys := {}
	for kind in ["recruits", "arms", "forged", "drills"]:
		for id in content.get(kind):
			for k in content.get(kind)[id].get("art", []):
				keys[k] = true
	return Content.load_all(keys)


## A run with no soldiers, then one of each listed type added and set on its place.
func _legion_sim(b: Dictionary, seed_value: int, types: Array) -> Sim:
	var s := Sim.new(b, content, {"seed": seed_value})
	s.soldiers.clear()
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	# No barbarians arrive on their own, so a test sees only the ones it places.
	s.b = b.duplicate()
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	s.horde.next_surge = 1e9
	for t in types:
		s.legion.add(t)
	var places: Array = s.legion.formation()
	for i in s.soldiers.size():
		s.soldiers[i].pos = s.commander.pos + places[i]
	return s


func test_legion_stops_at_one_hundred(b: Dictionary) -> void:
	var s := _legion_sim(b, 7, [])
	var last := true
	for i in 150:
		last = s.legion.add("legionary" if i % 2 == 0 else "archer")
	check(s.soldiers.size() == 100, "the legion holds 100 soldiers (%d)" % s.soldiers.size())
	check(not last, "adding at the cap says no")
	check(not Upgrades.available(s).has("legionary") and not Upgrades.available(s).has("archer"), "recruits are no longer offered")
	check(Upgrades.available(s).has("pilum"), "weapons still are")


func test_places_by_kind(b: Dictionary) -> void:
	var types: Array = []
	for i in 12:
		types.append("legionary")
	types.append_array(["centurion", "archer", "archer", "ballista", "cavalry", "cavalry", "medicus", "standard_bearer"])
	var s := _legion_sim(b, 1, types)
	var places: Array = s.legion.formation()
	check(places.size() == s.soldiers.size(), "one place per soldier")
	var front_width := 0.0
	for i in s.soldiers.size():
		if content.unit(s.soldiers[i].type).place == "front":
			front_width = maxf(front_width, absf(places[i].y))
	for i in s.soldiers.size():
		var kind: String = content.unit(s.soldiers[i].type).place
		var p: Vector2 = places[i]
		match kind:
			"front":
				check(p.x > 0.0, "front %s is ahead" % s.soldiers[i].type)
			"rear":
				check(p.x < 0.0, "rear %s is behind" % s.soldiers[i].type)
			"flank":
				check(absf(p.y) > front_width, "flank %s is wider than every front place" % s.soldiers[i].type)
			"middle":
				check(p.length() < 20.0, "middle %s is near the commander" % s.soldiers[i].type)
	for i in places.size():
		for j in range(i + 1, places.size()):
			check(places[i].distance_to(places[j]) >= 8.0, "places %d and %d apart" % [i, j])


func test_front_rank_takes_the_blow(b: Dictionary) -> void:
	var s := _legion_sim(b, 2, ["legionary", "archer"])
	var front: Dictionary = s.soldiers[0]
	var rear: Dictionary = s.soldiers[1]
	front.pos = Vector2(300, 0)
	rear.pos = Vector2(312, 0)
	s.horde.spawn("barbarian_club", Vector2(322, 0))
	s._rebuild_grids()
	s.legion.assign_guards()
	for i in 20:
		s.horde._move(1.0 / 60.0, s)
	check(front.hp < front.max_hp, "the front-rank man took the hit")
	check(rear.hp == rear.max_hp, "the archer behind him was spared")
	rear.pos = Vector2(300, 60)
	s._rebuild_grids()
	s.legion.assign_guards()
	s.horde.e_pos[0] = Vector2(310, 60)
	for i in 20:
		s.horde._move(1.0 / 60.0, s)
	check(rear.hp < rear.max_hp, "with no shield near, the archer is hit")


func test_fifth_pick_promotes(b: Dictionary) -> void:
	var s := _legion_sim(b, 3, [])
	for i in 4:
		Upgrades.apply(s, "legionary")
	check(s.count("legionary") == 8, "two legionaries join per pick")
	check(not s.legion.promoted("legionary"), "four picks do not promote")
	var hp_before: float = s.soldiers[0].max_hp
	Upgrades.apply(s, "legionary")
	check(s.legion.promoted("legionary"), "the fifth does")
	check(is_equal_approx(s.soldiers[0].max_hp, hp_before * 2.0), "veterans have double health")
	check(not s.legion.promoted("archer"), "other types are unchanged")
	Upgrades.apply(s, "centurion")
	check(s.count("centurion") == 1, "one centurion joins per pick")


func test_medicus_heals_the_wounded(b: Dictionary) -> void:
	var s := _legion_sim(b, 4, ["legionary", "legionary", "medicus"])
	var hurt: Dictionary = s.soldiers[1]
	hurt.hp = 10.0
	var well: Dictionary = s.soldiers[0]
	well.hp = 40.0
	for i in 60:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(hurt.hp > 10.0 + float(content.recruits.medicus.heal) * 0.8, "the most wounded was healed (%.1f)" % hurt.hp)
	check(well.hp <= 40.0 + 0.01, "the less wounded waited")
	hurt.pos = Vector2(500, 500)
	var before: float = hurt.hp
	s.legion.update(0.5, s)
	check(hurt.hp == before, "out of reach gets nothing")


func test_medicus_promoted_revives_a_fallen_soldier(b: Dictionary) -> void:
	var s := _legion_sim(b, 5, ["legionary", "medicus"])
	s.legion.picks["medicus"] = 5
	s.soldiers[0].hp = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.count("legionary") == 0, "he fell")
	for i in 62:
		s.update(1.0, Vector2.ZERO, false)
		s.commander.hp = 1e9
	check(s.count("legionary") == 1, "the medicus brought him back")


func test_standard_bearer_speeds_attacks(b: Dictionary) -> void:
	var s := _legion_sim(b, 6, ["legionary", "standard_bearer"])
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var haste: float = s.soldiers[0].haste
	check(is_equal_approx(haste, 1.25), "attack speed up by a quarter (%.2f)" % haste)
	s.soldiers[0].pos = Vector2(400, 0)
	s.legion.update(1.0 / 60.0, s)
	check(is_equal_approx(s.soldiers[0].haste, 1.0), "out of his reach there is no bonus")
	s.legion.picks["standard_bearer"] = 5
	s.legion.update(1.0 / 60.0, s)
	check(is_equal_approx(s.soldiers[0].haste, 1.25), "promoted, the whole legion gets it")


func test_cavalry_rides_out_and_back(b: Dictionary) -> void:
	var s := _legion_sim(b, 8, ["cavalry"])
	var cav: Dictionary = s.soldiers[0]
	var home: Vector2 = cav.pos
	s.horde.spawn("barbarian_club", home + Vector2(0, 70) * signf(home.y))
	var went := 0.0
	for i in 240:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		went = maxf(went, cav.pos.distance_to(home))
		s.commander.hp = 1e9
	check(went > 20.0, "he rode out (%.0f)" % went)
	check(s.kills >= 1 or s.horde.e_hp[0] < s.horde.e_max[0], "and struck")
	check(cav.pos.distance_to(s.commander.pos + s.slot_of(cav)) < 8.0, "and is back in his place")


func test_cavalry_strikes_a_big_enemy_instead_of_pushing_him(b: Dictionary) -> void:
	var s := _legion_sim(b, 8, ["cavalry"])
	var cav: Dictionary = s.soldiers[0]
	var home: Vector2 = cav.pos
	var at := home + Vector2(0, 70) * signf(home.y)
	s.horde.spawn("berserker", at)
	var struck := false
	for i in 90:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		s.commander.hp = 1e9
		if s.horde.e_hp[0] < s.horde.e_max[0]:
			struck = true
			break
	check(struck, "the rider struck the berserker")
	check(s.horde.e_pos[0].distance_to(at) < 40.0, "without carrying him along (%.0f)" % s.horde.e_pos[0].distance_to(at))


func test_ballista_bolt_pierces_all(b: Dictionary) -> void:
	var s := _legion_sim(b, 9, ["ballista"])
	for k in 3:
		s.horde.spawn("barbarian_club", Vector2(-80 - 25 * k, 0))
	for i in 20:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		s.commander.hp = 1e9
	check(s.shots.size() == 1 and s.shots[0].pierce >= 100, "a bolt that pierces everything flew")
	for i in 90:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		s.commander.hp = 1e9
	var hurt := 0
	for k in s.horde.e_pos.size():
		if s.horde.e_hp[k] < s.horde.e_max[k]:
			hurt += 1
	check(hurt + s.kills >= 2, "it hit the enemies down its line (%d)" % (hurt + s.kills))


func test_centurion_shout_stuns(b: Dictionary) -> void:
	var s := _legion_sim(b, 10, ["centurion"])
	var c: Dictionary = s.soldiers[0]
	c.shout = 0.0
	s.horde.spawn("barbarian_club", c.pos + Vector2(20, 0))
	s.horde.spawn("barbarian_club", c.pos + Vector2(200, 0))
	s._rebuild_grids()
	s.legion.update(1.0 / 60.0, s)
	check(s.horde.e_stun[0] > 0.0 and s.horde.e_stun[1] == 0.0, "only the enemy in the shout is stunned")


func test_recruit_without_art_is_not_offered(b: Dictionary) -> void:
	var art: Dictionary = content.available.duplicate()
	art.erase("unit:medicus")
	var c := Content.load_all(art)
	var s := Sim.new(b, c, {"seed": 11})
	check(c.recruits.medicus.implemented and not c.ready("recruits", "medicus"), "the medicus is implemented but has no art")
	for i in 30:
		check(not Upgrades.offers(s, 10).has("medicus"), "the medicus is never offered")
	check(not Upgrades.available(s).has("medicus"), "and is not available")


func test_a_full_legion_of_every_kind_has_no_overlapping_places(b: Dictionary) -> void:
	var kinds: Array = content.recruits.keys()
	var types: Array = []
	for i in 100:
		types.append(kinds[i % kinds.size()])
	var s := _legion_sim(b, 12, types)
	check(s.soldiers.size() == 100, "a full legion")
	var places: Array = s.legion.formation()
	var worst := INF
	for i in places.size():
		for j in range(i + 1, places.size()):
			worst = minf(worst, places[i].distance_to(places[j]))
	check(worst >= 8.0, "no two places closer than 8 px (%.1f)" % worst)


func test_a_rear_heavy_legion_has_no_overlapping_places(b: Dictionary) -> void:
	var types: Array = []
	for i in 100:
		types.append("archer" if i < 88 else "cavalry")
	var s := _legion_sim(b, 13, types)
	var places: Array = s.legion.formation()
	var worst := INF
	for i in places.size():
		for j in range(i + 1, places.size()):
			worst = minf(worst, places[i].distance_to(places[j]))
	check(worst >= 8.0, "a rear-heavy legion has no two places closer than 8 px (%.1f)" % worst)


## A quiet run: no arrivals, an unkillable commander and no soldiers, with the given ranks.
func _arms_sim(b: Dictionary, seed_value: int, ranks: Dictionary, game_content: Content = null) -> Sim:
	var s := Sim.new(b, game_content if game_content != null else content, {"seed": seed_value})
	s.soldiers.clear()
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	s.b = b.duplicate()
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	s.horde.next_surge = 1e9
	for id in ranks:
		s.ranks[id] = ranks[id]
	return s


func _run(s: Sim, seconds: float) -> void:
	for i in int(seconds * 60.0):
		s.update(1.0 / 60.0, Vector2.ZERO, false)


func _step(s: Sim, seconds: float, move: Vector2) -> void:
	for i in int(seconds * 60.0):
		s.update(1.0 / 60.0, move, false)


func _max_everything(s: Sim) -> void:
	for kind in ["arms", "forged", "drills"]:
		for id in s.content.get(kind):
			s.ranks[id] = int(s.content.get(kind)[id].max)


func _sum(a: PackedInt32Array) -> int:
	var t := 0
	for v in a:
		t += v
	return t


func test_forged_form_replaces_its_pair(b: Dictionary) -> void:
	var full := _full_content()
	var s := _arms_sim(b, 30, {"pilum": 5, "caltrops": 4}, full)
	check(not Upgrades.available(s).has("hooked_pila"), "no forged form while one of the pair is short")
	check(Upgrades.available(s).has("caltrops"), "the short weapon is still offered")
	s.ranks.caltrops = 5
	var avail := Upgrades.available(s)
	check(avail.has("hooked_pila"), "the forged form is offered when both are at their last level")
	check(not avail.has("pilum") and not avail.has("caltrops"), "and neither of the pair is")
	var seen := false
	for i in 60:
		seen = seen or Upgrades.offers(s).has("hooked_pila")
	check(seen, "it turns up in the choices")
	Upgrades.apply(s, "hooked_pila")
	check(s.rank("hooked_pila") == 1 and not Upgrades.available(s).has("hooked_pila"), "taken once, never again")


func test_every_forged_form_needs_its_own_pair(b: Dictionary) -> void:
	var full := _full_content()
	for id in full.forged:
		var s := _arms_sim(b, 31, {}, full)
		for w in full.forged[id].from:
			s.ranks[w] = 5
		check(Upgrades.available(s).has(id), "%s is offered when its pair is done" % id)


func test_no_choices_left_skips_the_screen(b: Dictionary) -> void:
	var full := _full_content()
	var s := _arms_sim(b, 32, {}, full)
	_max_everything(s)
	for i in 100:
		s.legion.add("legionary")
	s.pending_levels = 2
	check(Upgrades.offers(s).is_empty(), "nothing to offer")
	check(Upgrades.next_choices(s).is_empty(), "no choices for the screen")
	check(s.pending_levels == 0, "the waiting levels are dropped so the screen never opens")


func test_fortune_offers_four(b: Dictionary) -> void:
	var full := _full_content()
	var s := _arms_sim(b, 33, {}, full)
	check(Upgrades.offers(s).size() == 3, "three choices by default")
	Upgrades.apply(s, "fortune")
	var o := Upgrades.offers(s)
	check(o.size() == 4, "Fortune makes it four (%d)" % o.size())
	var seen := {}
	for id in o:
		seen[id] = true
	check(seen.size() == 4, "all different")


func test_rerolls_and_banishes_change_the_choices(b: Dictionary) -> void:
	var full := _full_content()
	var s := _arms_sim(b, 34, {}, full)
	check(s.rerolls == 1, "one reroll per run")
	check(s.banishes == 0 and s.banished.is_empty(), "no banishes to start with")
	var first := Upgrades.offers(s)
	var second := Upgrades.reroll(s, first)
	check(s.rerolls == 0, "a reroll is spent")
	check(second.size() == 3, "still three choices")
	for id in second:
		check(not first.has(id), "a rerolled choice is new (%s)" % id)
	check(Upgrades.reroll(s, second) == second, "no reroll left means the choices stay")
	check(s.rerolls == 0, "the count never goes below zero")


func test_banished_choice_never_returns(b: Dictionary) -> void:
	var full := _full_content()
	var s := _arms_sim(b, 35, {}, full)
	s.banishes = 1
	var o := Upgrades.offers(s)
	var gone: String = o[0]
	var after := Upgrades.banish(s, gone, o)
	check(s.banishes == 0 and s.banished.has(gone), "the banish is spent and recorded")
	check(not after.has(gone) and after.size() == 3, "its place is taken by another")
	var back := false
	for i in 80:
		back = back or Upgrades.offers(s).has(gone)
	check(not back, "banished %s stays out" % gone)
	check(not Upgrades.available(s).has(gone), "and it is not available")
	var again := Upgrades.banish(s, after[0], after)
	check(again == after and s.banished.size() == 1, "with none left, nothing is banished")


func test_burning_ground_hurts_over_time(b: Dictionary) -> void:
	var s := _arms_sim(b, 36, {})
	s.horde.spawn("barbarian_club", Vector2(60, 0))
	s.horde.e_hp[0] = 400.0
	s.horde.e_max[0] = 400.0
	s.horde.e_stun[0] = 100.0
	s.arms.add_zone("fire", Vector2(60, 0), 20.0, 5.0, 20.0)
	_run(s, 0.5)
	var early: float = s.horde.e_hp[0]
	_run(s, 1.0)
	var later: float = s.horde.e_hp[0]
	check(early < 400.0, "the fire hurt at once (%.1f)" % early)
	check(later < early - 10.0, "and kept hurting (%.1f then %.1f)" % [early, later])
	check(s.arms.ground_zones().size() == 1 and s.arms.ground_zones()[0].kind == "fire", "it is drawn as ground")
	_run(s, 6.0)
	check(s.arms.ground_zones().is_empty(), "the fire dies out")


func test_fire_pots_light_the_ground_ahead(b: Dictionary) -> void:
	var s := _arms_sim(b, 37, {"fire_pots": 3})
	s.horde.spawn("barbarian_club", Vector2(80, 0))
	s.horde.e_stun[0] = 100.0
	s.horde.e_hp[0] = 500.0
	_run(s, 6.0)
	check(s.horde.e_hp[0] < 500.0, "an enemy ahead was burned (%.1f)" % s.horde.e_hp[0])


func test_trumpets_push_enemies_back(b: Dictionary) -> void:
	var s := _arms_sim(b, 38, {"trumpets": 1})
	s.horde.spawn("barbarian_club", Vector2(60, 0))
	s.horde.spawn("barbarian_club", Vector2(400, 0))
	s.horde.e_stun[0] = 100.0
	s.horde.e_stun[1] = 100.0
	var far_before: Vector2 = s.horde.e_pos[1]
	_run(s, 1.5)
	check(s.horde.e_pos[0].x > 60.0 + 20.0, "the near enemy was pushed away (%.1f)" % s.horde.e_pos[0].x)
	check(s.horde.e_pos[1].distance_to(far_before) < 40.0, "the far one was not blasted")


func test_scorpio_bolt_damages_the_strongest(b: Dictionary) -> void:
	var s := _arms_sim(b, 39, {"scorpio": 1})
	s.horde.spawn("barbarian_club", Vector2(100, 0))
	var before: float = s.horde.e_hp[0]
	s.horde.e_stun[0] = 100.0
	_run(s, 1.5)
	check(s.horde.e_hp.size() == 0 or s.horde.e_hp[0] < before, "a projectile weapon hurts")


func test_onager_stone_scatters_the_crowd(b: Dictionary) -> void:
	var s := _arms_sim(b, 40, {"onager": 2})
	for i in 12:
		s.horde.spawn("barbarian_club", Vector2(120 + (i % 4) * 5, (i / 4) * 5))
		s.horde.e_stun[i] = 100.0
		s.horde.e_hp[i] = 500.0
	var before: PackedVector2Array = s.horde.e_pos.duplicate()
	_run(s, 3.0)
	var hurt := 0
	var moved := 0
	for i in s.horde.e_pos.size():
		if s.horde.e_hp[i] < 500.0:
			hurt += 1
		if s.horde.e_pos[i].distance_to(before[i]) > 2.0:
			moved += 1
	check(hurt >= 8, "the stone struck the crowd (%d hurt)" % hurt)
	check(moved >= 6, "and scattered it (%d moved)" % moved)


func test_stakes_hurt_enemies_in_the_ring(b: Dictionary) -> void:
	var s := _arms_sim(b, 41, {"stakes": 1})
	var r: float = float(b.stakes.radius)
	s.horde.spawn("barbarian_club", Vector2(r, 0))
	s.horde.spawn("barbarian_club", Vector2(r * 2.5, 0))
	s.horde.e_stun[0] = 100.0
	s.horde.e_stun[1] = 100.0
	s.horde.e_hp[0] = 300.0
	s.horde.e_hp[1] = 300.0
	_run(s, 1.0)
	check(s.horde.e_hp[0] < 290.0, "the one at the ring is hurt (%.1f)" % s.horde.e_hp[0])
	check(s.horde.e_hp[1] == 300.0, "the one far outside is not")
	check(s.arms.ground_zones().any(func(z): return z.kind == "stakes"), "the ring is drawn")


func test_torches_burn_what_they_pass(b: Dictionary) -> void:
	var s := _arms_sim(b, 42, {"torches": 3})
	for i in 8:
		s.horde.spawn("barbarian_club", Vector2.from_angle(i * TAU / 8.0) * float(b.torches.radius))
		s.horde.e_stun[i] = 100.0
		s.horde.e_hp[i] = 300.0
	_run(s, 4.0)
	var hurt := 0
	for i in s.horde.e_hp.size():
		if s.horde.e_hp[i] < 300.0:
			hurt += 1
	check(hurt >= 3, "torches circling the formation hurt those on their path (%d)" % hurt)
	check(s.arms.torch_points(s).size() == 4, "rank 3 carries four torches")


func test_eagle_flash_strikes_everyone_around(b: Dictionary) -> void:
	var s := _arms_sim(b, 43, {"eagle": 1})
	for i in 5:
		s.horde.spawn("barbarian_club", Vector2.from_angle(i * 1.2) * 50.0)
		s.horde.e_stun[i] = 100.0
		s.horde.e_hp[i] = 300.0
	s.horde.spawn("barbarian_club", Vector2(400, 0))
	s.horde.e_hp[5] = 300.0
	_run(s, 1.0)
	var hurt := 0
	for i in 5:
		if s.horde.e_hp[i] < 300.0:
			hurt += 1
	check(hurt == 5, "all around were struck (%d)" % hurt)
	check(s.horde.e_hp[5] == 300.0, "the far one was not")


func test_caltrops_are_left_behind_and_cut(b: Dictionary) -> void:
	var s := _arms_sim(b, 44, {"caltrops": 2})
	_step(s, 3.0, Vector2.RIGHT)
	var laid: Array = s.arms.ground_zones().filter(func(z): return z.kind == "caltrops")
	check(laid.size() >= 4, "spikes lie along the march (%d)" % laid.size())
	s.horde.spawn("barbarian_club", laid[0].pos)
	s.horde.e_stun[0] = 100.0
	s.horde.e_hp[0] = 300.0
	_run(s, 0.6)
	check(s.horde.e_hp[0] < 300.0, "an enemy on them is cut (%.1f)" % s.horde.e_hp[0])


func test_war_dogs_run_down_a_straggler(b: Dictionary) -> void:
	var s := _arms_sim(b, 45, {"war_dogs": 2})
	s.horde.spawn("barbarian_club", Vector2(120, 0))
	s.horde.e_stun[0] = 100.0
	var before: float = s.horde.e_hp[0]
	_run(s, 4.0)
	check(s.horde.e_hp.size() == 0 or s.horde.e_hp[0] < before, "the dogs bit him")
	check(s.arms.dogs.size() == 2, "rank 2 keeps two dogs")


func test_oil_slows_enemies_on_it(b: Dictionary) -> void:
	var s := _arms_sim(b, 46, {})
	s.arms.add_zone("oil", Vector2(60, 0), 30.0, 5.0, 0.0, {"slow": 0.5})
	s.horde.spawn("barbarian_club", Vector2(80, 0))
	s.horde.spawn("barbarian_club", Vector2(80, 100))
	var a0: Vector2 = s.horde.e_pos[0]
	var b0: Vector2 = s.horde.e_pos[1]
	_run(s, 0.5)
	var slow: float = a0.distance_to(s.horde.e_pos[0])
	var free: float = b0.distance_to(s.horde.e_pos[1])
	check(slow < free * 0.8, "the slick slows (%.1f vs %.1f)" % [slow, free])


func test_oil_jars_make_slick_ground(b: Dictionary) -> void:
	var s := _arms_sim(b, 47, {"oil_jars": 2})
	s.horde.spawn("barbarian_club", Vector2(80, 0))
	s.horde.e_stun[0] = 100.0
	_run(s, 3.0)
	check(s.arms.ground_zones().any(func(z): return z.kind == "oil"), "a jar broke into a slick")


func test_each_forged_form_changes_its_pair(b: Dictionary) -> void:
	var s := _arms_sim(b, 48, {"pilum": 5, "hooked_pila": 1})
	s.horde.spawn("barbarian_club", Vector2(100, 0))
	s.horde.e_hp[0] = 1000.0
	_run(s, 1.5)
	check(s.horde.e_stun[0] > 0.0, "hooked pila pin the enemy")
	var g := _arms_sim(b, 49, {"fire_arrows": 5, "greek_fire": 1})
	check(g.burn_seconds() > float(b.fire_arrows.seconds), "Greek fire burns longer")
	var t := _arms_sim(b, 50, {"scorpio": 5, "onager": 5, "siege_train": 1})
	check(t.arms.stones_per_throw(t) == int(b.onager.stones) + int(b.siege_train.extra_stones), "the siege train throws more stones")
	var h := _arms_sim(b, 51, {"war_dogs": 5, "trumpets": 5, "hunting_horn": 1})
	check(h.arms.dog_count(h) == 5 + int(b.hunting_horn.extra_dogs), "the horn calls more dogs")
	var e := _arms_sim(b, 52, {"eagle": 5, "torches": 5, "burning_eagle": 1})
	e.horde.spawn("barbarian_club", Vector2(40, 0))
	e.horde.e_stun[0] = 100.0
	e.horde.e_hp[0] = 1000.0
	_run(e, 7.0)
	check(e.horde.e_burn[0] > 0.0 or e.horde.e_hp[0] < 900.0, "the burning eagle sets enemies alight")
	var f := _arms_sim(b, 53, {"stakes": 5, "oil_jars": 5, "fortified_camp": 1})
	check(f.arms.stake_dps(f) > float(b.stakes.dps) + 4.0 * float(b.stakes.dps_per_level), "the camp's stakes hurt more")


func test_shield_wall_cuts_front_rank_harm(b: Dictionary) -> void:
	var lost := []
	for r in [0, 3]:
		var s := _legion_sim(b, 60, ["legionary"])
		s.ranks["shield_wall"] = r
		s.soldiers[0].hp = 1000.0
		s.soldiers[0].max_hp = 1000.0
		s.horde.spawn("barbarian_club", s.soldiers[0].pos + Vector2(8, 0))
		for i in 60:
			s.update(1.0 / 60.0, Vector2.ZERO, false)
		lost.append(1000.0 - s.soldiers[0].hp)
	check(lost[1] < lost[0] * 0.85 and lost[0] > 0.0, "shield wall takes less harm (%.2f vs %.2f)" % [lost[1], lost[0]])


func test_better_bows_reach_further(b: Dictionary) -> void:
	var near := _legion_sim(b, 61, ["archer"])
	var far := _legion_sim(b, 61, ["archer"])
	far.ranks["better_bows"] = 3
	for s in [near, far]:
		s.horde.spawn("barbarian_club", s.soldiers[0].pos + Vector2(-float(content.recruits.archer.range) * 1.2, 0))
		s.horde.e_stun[0] = 100.0
	for i in 90:
		near.update(1.0 / 60.0, Vector2.ZERO, false)
		far.update(1.0 / 60.0, Vector2.ZERO, false)
	check(near.shots.is_empty() and near.horde.e_hp[0] == near.horde.e_max[0], "an archer cannot reach")
	check(not far.shots.is_empty() or far.horde.e_hp[0] < far.horde.e_max[0], "with better bows he can")


func test_close_order_keeps_places_faster(b: Dictionary) -> void:
	var gaps := []
	for r in [0, 3]:
		var s := _legion_sim(b, 62, ["legionary", "legionary", "legionary", "archer"])
		s.ranks["close_order"] = r
		s.facing_angle = 0.0
		for so in s.soldiers:
			so.pos += Vector2(0, 60)
		s.legion.follow(0.1, s)
		var total := 0.0
		for so in s.soldiers:
			total += so.pos.distance_to(so.target)
		gaps.append(total)
	check(gaps[1] < gaps[0] - 1.0, "close order closes the gap faster (%.1f vs %.1f)" % [gaps[1], gaps[0]])


func test_plunder_and_glory_pay_more(b: Dictionary) -> void:
	var uncapped := b.duplicate(true)
	uncapped.max_coins = 100000
	var s := _arms_sim(uncapped, 63, {"plunder": 5})
	for i in 400:
		s.horde.spawn("barbarian_club", Vector2(300, 300))
		s.hit(s.horde.e_hp.size() - 1, 9999.0)
		s._remove_dead()
	var total := _sum(s.c_val) / float(b.medium.get("denarii_mult", 1.0))
	check(s.c_val.size() == 400 and total > 400 * 1.5 and total < 400 * 2.0, "plunder gives about 75 percent more (%d)" % total)
	var g := _arms_sim(b, 64, {"glory": 5})
	g.xp_next = 100000
	for i in 100:
		g.gain(1)
	check(g.xp >= 145 and g.xp <= 155, "glory gives 50 percent more experience (%d)" % g.xp)


func test_veterans_grow_with_kills(b: Dictionary) -> void:
	var s := _legion_sim(b, 65, ["legionary", "archer"])
	s.ranks["veterans"] = 2
	var before: float = s.soldiers[0].max_hp
	for i in 50:
		s.horde.spawn("barbarian_club", Vector2(300, 300))
		s.hit(s.horde.e_hp.size() - 1, 9999.0)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.soldiers[0].max_hp > before and s.soldiers[1].max_hp > float(content.recruits.archer.hp), "every soldier is tougher after kills")
	var grown: float = s.soldiers[0].max_hp
	for i in 20000:
		s.legion.veterans(1, s)
	check(s.soldiers[0].max_hp < before * 2.0, "growth has a cap (%.1f)" % s.soldiers[0].max_hp)
	Upgrades.apply(s, "lorica")
	check(s.soldiers[0].max_hp > grown, "lorica keeps what veterans gave")


func test_reserves_replace_the_fallen(b: Dictionary) -> void:
	var s := _legion_sim(b, 66, ["legionary", "archer"])
	s.ranks["reserves"] = 1
	s.soldiers[0].hp = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.soldiers.size() == 1, "he fell")
	for i in 60 * 10:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.soldiers.size() == 1, "not replaced early")
	for i in 60 * 11:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.soldiers.size() == 2 and s.count("legionary") == 1, "replaced after 20 seconds, of the same type")


func test_every_drill_applies(b: Dictionary) -> void:
	var s := _arms_sim(b, 67, {})
	for id in content.drills:
		Upgrades.apply(s, id)
		check(s.rank(id) == 1, "%s applied" % id)
		check(content.drills[id].implemented, "%s is implemented" % id)


func test_arms_run_together(b: Dictionary) -> void:
	var s := _arms_sim(b, 68, {})
	for id in content.arms:
		s.ranks[id] = 5
	for id in content.forged:
		s.ranks[id] = 1
	s.legion.add("archer")
	for i in 80:
		s.horde.spawn(["barbarian_club", "barbarian_spear"][i % 2], s.horde.ring_point() * 0.4)
	_step(s, 20.0, Vector2(1, 0.3))
	check(not s.over, "a legion with every arm and form runs on")


func _step_dt(s: Sim, seconds: float, move := Vector2.ZERO, testudo := false) -> void:
	for i in int(seconds * 60.0):
		s.update(1.0 / 60.0, move, testudo)


func test_ranged_enemy_keeps_its_distance(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 91})
	s.terrain.clear()
	s.b = b.duplicate()
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	s.horde.next_surge = 1e9
	s.horde.next_band = 1e9
	var reach := float(Content.with_all_art().enemies.axe_thrower.range)
	s.horde.spawn("axe_thrower", Vector2(200, 0))
	var id := s.horde.e_id[0]
	_step_dt(s, 4.0)
	var d: float = s.horde.e_pos[0].distance_to(s.commander.pos)
	check(d > reach and d <= reach + s.legion_reach + 4.0, "the thrower stops at its range from the legion (%.1f)" % d)
	var closed := false
	for f in 8 * 60:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		var i := s.horde.e_id.find(id)
		if i < 0 or s.horde.e_fighting[i] == 1:
			closed = true
			break
	check(closed, "after its throws it closes in to fight")


func test_testudo_blocks_thrown_spears(b: Dictionary) -> void:
	var open := Sim.new(b, Content.with_all_art(), {"seed": 92})
	var shut := Sim.new(b, Content.with_all_art(), {"seed": 92})
	for s in [open, shut]:
		s.horde.spawn("axe_thrower", Vector2(105, 0))
	var hp0: float = open.commander.hp + open.soldiers[0].hp + open.soldiers[1].hp
	for i in 360:
		open.update(1.0 / 60.0, Vector2.ZERO, false)
		shut.testudo_left = 5.0
		shut.update(1.0 / 60.0, Vector2.ZERO, false)
	var open_hp: float = open.commander.hp + open.soldiers[0].hp + open.soldiers[1].hp
	var shut_hp: float = shut.commander.hp + shut.soldiers[0].hp + shut.soldiers[1].hp
	check(open_hp < hp0, "spears hurt an open legion")
	check(shut_hp == hp0, "the testudo takes none of them (%.1f of %.1f)" % [shut_hp, hp0])


func test_elite_drops_a_chest(b: Dictionary) -> void:
	var art := Content.with_all_art()
	var s := Sim.new(b, art, {"seed": 93})
	var i: int = s.horde.spawn("berserker", Vector2(300, 0))
	check(s.horde.e_tag[i] == Horde.ELITE and s.horde.e_hp[i] > 300.0, "an elite with far more health")
	s.hit(i, 1e9)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.horde.chests.size() == 1, "it drops a chest")
	s.commander.pos = s.horde.chests[0].pos
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.free_choices == 1 and s.horde.chests.is_empty(), "walking onto it gives one free choice")
	var before := s.level
	var picks := Upgrades.next_choices(s)
	Upgrades.apply(s, picks[0])
	check(s.free_choices == 0 and s.level == before, "the choice does not change the level")
	var no_chest := Content.available_art()
	no_chest.erase("prop:chest")
	var bare := Sim.new(b, Content.load_all(no_chest), {"seed": 94})
	var j: int = bare.horde.spawn("berserker", Vector2(300, 0))
	bare.hit(j, 1e9)
	bare.update(1.0 / 60.0, Vector2.ZERO, false)
	check(bare.horde.chests.is_empty(), "with no chest art it drops nothing")


func test_touching_a_supply_cart_opens_its_choice(b: Dictionary) -> void:
	var s := _quiet_sim(b, 97, Content.with_all_art())
	s.soldiers[0].hp = 1.0
	s.c_pos.append(Vector2(500, 300))
	s.c_val.append(1)
	s.c_pull.append(0)
	s.horde.carts.append({"pos": s.commander.pos, "t": 0.0})
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.horde.carts.is_empty(), "the cart is taken")
	check(s.supply_offers() == ["free_choice", "heal", "magnet"], "touching it offers the three rewards (%s)" % [s.supply_offers()])
	check(s.free_choices == 0 and s.soldiers[0].hp < s.soldiers[0].max_hp and s.c_pull[0] == 0, "and gives none of them until one is chosen")


func test_each_supply_cart_choice_gives_its_reward(b: Dictionary) -> void:
	var s := _quiet_sim(b, 98, Content.with_all_art())
	for k in 6:
		s.c_pos.append(Vector2(400 + k * 30, 200))
		s.c_val.append(1)
		s.c_pull.append(0)
	s.add_supply(1)
	s.take_supply("magnet")
	var all := true
	for p in s.c_pull:
		all = all and p == 1
	check(all and s.supply_offers().is_empty(), "the coins choice pulls every coin and closes the choice")
	s.add_supply(1)
	s.take_supply("free_choice")
	check(s.free_choices == 1 and s.supply_offers().is_empty(), "the level-up choice gives a free choice")
	s.soldiers[0].hp = 1.0
	s.commander.hp = 1.0
	s.add_supply(1)
	s.take_supply("heal")
	check(s.soldiers[0].hp == s.soldiers[0].max_hp and s.commander.hp == s.commander.max_hp, "the heal choice heals the legion and the commander")
	s.add_supply(1)
	check(s.bot_supply() == "free_choice", "a bot takes the level-up while the legion is well")


func test_a_supply_cart_with_the_bonus_is_chosen_from_twice(b: Dictionary) -> void:
	var s := _quiet_sim(b, 99, Content.with_all_art())
	s.add_supply(2)
	s.take_supply("heal")
	check(s.supply_offers() == ["free_choice", "magnet"], "after the first pick the choice stays open without it (%s)" % [s.supply_offers()])
	s.take_supply("free_choice")
	check(s.supply_offers().is_empty() and s.free_choices == 1, "the second pick closes it")
	s.add_supply(1)
	s.add_supply(1)
	s.take_supply("magnet")
	check(s.supply_offers().size() == 3, "a second cart opened meanwhile offers all three again")


func test_the_supply_cart_heal_line_matches_the_legion(b: Dictionary) -> void:
	var s := _quiet_sim(b, 100, Content.with_all_art())
	while s.soldiers.size() < 4:
		s.add_soldier("legionary")
	var most := 0.0
	var has := 0.0
	for u in s.soldiers:
		most += u.max_hp
	s.soldiers[0].hp = s.soldiers[0].max_hp * 0.5
	s.soldiers[1].hp = s.soldiers[1].max_hp * 0.25
	for u in s.soldiers:
		has += u.hp
	s.commander.hp = s.commander.max_hp * 0.4
	var h := s.legion_health()
	check(h.wounded == 2, "two soldiers are wounded (%d)" % h.wounded)
	check(h.share == floori(100.0 * has / most), "the legion's share is its health over its most (%d)" % h.share)
	check(h.commander == 40, "the commander's share is his own (%d)" % h.commander)
	var line: String = Hud.supply_row(s, "heal").line
	check(line == "2 wounded, legion at %d%% health, commander at 40%%" % h.share, "the heal row says so (%s)" % line)
	for k in 7:
		s.c_pos.append(Vector2(400 + k * 30, 200))
		s.c_val.append(1)
		s.c_pull.append(0)
	check(Hud.supply_row(s, "magnet").line == "%d coins lie on the field" % s.c_pos.size(), "the coins row counts the coins (%s)" % Hud.supply_row(s, "magnet").line)
	for u in s.soldiers:
		u.hp = u.max_hp * 0.3
	s.add_supply(1)
	check(s.bot_supply() == "heal", "a bot heals a legion below half health")


func test_the_supply_cart_choice_pauses_the_run(b: Dictionary) -> void:
	Controls.install({})
	var m: Node = load("res://scripts/main.gd").new()
	m.balance = b
	m.sim = _quiet_sim(b, 101, Content.with_all_art())
	m.content = m.sim.content
	m.state = "play"
	m.sim.horde.carts.append({"pos": m.sim.commander.pos, "t": 0.0})
	m._process(1.0 / 60.0)
	check(m.state == "supply" and m.choices == ["free_choice", "heal", "magnet"], "touching a cart opens its choice (%s %s)" % [m.state, m.choices])
	var t: float = m.sim.time
	for k in 30:
		m._process(1.0 / 30.0)
	check(m.sim.time == t, "the run waits while the choice is open")
	check(Game.in_run("supply", "title") and not Game.confirm_allowed("supply", 1.0, 1.0, b) and Touch.back_step("supply", false) == "none", "the choice is part of the run, waits for a deliberate press and is not backed out of")
	m._take_supply(0)
	check(m.state == "choose" and m.sim.free_choices == 1, "taking the level-up opens the level-up after the cart's choice closes (%s)" % m.state)
	m.free()


func test_cart_magnet_pulls_every_coin(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 95})
	for k in 6:
		s.c_pos.append(Vector2(400 + k * 30, 200))
		s.c_val.append(1)
		s.c_pull.append(0)
	s.horde.cart_reward(s, "magnet")
	var all := true
	for p in s.c_pull:
		all = all and p == 1
	check(all, "every coin is on its way")
	s.horde.cart_reward(s, "free_choice")
	check(s.free_choices == 1, "a cart can give a free choice")
	s.soldiers[0].hp = 1.0
	s.horde.cart_reward(s, "heal")
	check(s.soldiers[0].hp == s.soldiers[0].max_hp, "or heal the legion")
	var no_cart := Content.available_art()
	no_cart.erase("prop:supply_cart")
	var none := Sim.new(b, Content.load_all(no_cart), {"seed": 96})
	none.time = float(b.cart.every) + 1.0
	none.update(1.0 / 60.0, Vector2.ZERO, false)
	check(none.horde.carts.is_empty(), "no cart without its art")
	var drawn := Sim.new(b, Content.with_all_art(), {"seed": 96})
	drawn.time = float(b.cart.every) + 1.0
	drawn.update(1.0 / 60.0, Vector2.ZERO, false)
	check(drawn.horde.carts.size() == 1, "a cart crosses the field with its art")


func test_chieftain_war_cry_speeds_the_horde(b: Dictionary) -> void:
	var calm := Sim.new(b, Content.with_all_art(), {"seed": 97})
	var cried := Sim.new(b, Content.with_all_art(), {"seed": 97})
	for s in [calm, cried]:
		s.horde.spawn("chieftain", Vector2(400, 0))
		s.horde.spawn("wolf", Vector2(350, 150))
		s.horde.cry_cd = 1e9
		s.horde.cleave_cd = 1e9
	cried.horde.war_cry(cried.horde.chieftain_index(), cried)
	check(cried.horde.e_haste[1] > 0.0, "a nearby enemy is roused")
	var from: Vector2 = cried.horde.e_pos[1]
	_step_dt(calm, 1.0)
	_step_dt(cried, 1.0)
	var slow: float = calm.horde.e_pos[1].distance_to(from)
	var fast: float = cried.horde.e_pos[1].distance_to(from)
	check(fast > slow * 1.3, "it walks faster (%.1f against %.1f)" % [fast, slow])


func test_chieftain_cleave_hurts_an_arc_in_front(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 98})
	var i: int = s.horde.spawn("chieftain", Vector2(24, 0))
	s.horde.e_face[i] = Vector2.LEFT
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var before: float = s.commander.hp
	check(s.horde.cleave(i, s), "he cleaves when the legion is in front")
	check(s.commander.hp < before, "and it hurts")
	s.horde.e_face[i] = Vector2.RIGHT
	check(not s.horde.cleave(i, s), "nothing behind him is struck")


func _chief_sim(b: Dictionary, seed_value: int) -> Sim:
	var s := _quiet_sim(b, seed_value, Content.with_all_art())
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	for k in 8:
		s.add_soldier("legionary")
	s.legion.place_all(s.facing_angle)
	s.horde.cleave_cd = 1e9
	s.horde.cry_cd = 1e9
	s.horde.charge_cd = 1e9
	s.horde.slam_cd = 1e9
	s.horde.horn_cd = 1e9
	return s


func _guard_ids(s: Sim) -> Array:
	var ids: Array = []
	for i in s.horde.e_pos.size():
		if s.horde.e_guard[i] != Vector2.ZERO:
			ids.append(s.horde.e_id[i])
	return ids


func test_the_chieftain_comes_with_a_bodyguard_who_stay_round_him(b: Dictionary) -> void:
	var s := _chief_sim(b, 140)
	s.time = float(b.chieftain_at) - 0.01
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var ci := s.chieftain_index()
	var ids := _guard_ids(s)
	check(ci >= 0 and ids.size() == int(b.chieftain_guard.count), "the chieftain arrives with a bodyguard of %d (%d)" % [int(b.chieftain_guard.count), ids.size()])
	var spears := true
	for id in ids:
		spears = spears and s.horde.kind_ids[s.horde.e_kind[s.horde.e_id.find(id)]] == "barbarian_spear"
	check(spears, "his bodyguard are spearmen")
	var start: Vector2 = s.horde.e_pos[ci]
	_step_dt(s, 4.0)
	ci = s.chieftain_index()
	var close := true
	for id in ids:
		var j := s.horde.e_id.find(id)
		# Barbarians keep a body's width apart, so ten guards stand in a wider ring than the guard radius alone.
		close = close and j >= 0 and s.horde.e_pos[j].distance_to(s.horde.e_pos[ci]) < float(b.chieftain_guard.radius) * 2.0
	check(s.horde.e_pos[ci].distance_to(start) > 50.0 and close, "after marching four seconds his guards still stand round him")
	s.hit(ci, 1e9)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(_guard_ids(s).is_empty(), "when he falls his guards join the horde")


func test_the_chieftains_guards_fight_romans_they_touch(b: Dictionary) -> void:
	var s := _chief_sim(b, 145)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	s.horde.spawn_chieftain(Vector2(70, 0))
	var fighting := false
	for f in 60:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		for i in s.horde.e_pos.size():
			fighting = fighting or (s.horde.e_guard[i] != Vector2.ZERO and s.horde.e_fighting[i] == 1)
	check(fighting, "a guard beside the legion fights the Romans he touches")


func test_the_chieftain_shows_his_charge_then_throws_aside_those_in_its_path(b: Dictionary) -> void:
	var s := _chief_sim(b, 141)
	var atk: Dictionary = s.content.enemies.chieftain.attacks.charge
	s.horde.spawn("chieftain", Vector2(90, 0))
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	s.horde.charge_cd = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var ci := s.chieftain_index()
	var start: Vector2 = s.horde.e_pos[ci]
	check(s.horde.charge_warn > 0.0 and s.horde.e_dash[ci] == 0.0, "a red line shows his charge before he starts it")
	check(s.horde.charge_dir.dot(Vector2.LEFT) > 0.95, "the line points at the legion")
	_step_dt(s, float(atk.warn) * 0.8)
	check(s.horde.e_pos[ci].distance_to(start) < 1.0, "he stands still while the line shows")
	for f in 60:
		if s.horde.e_dash[ci] > 0.0:
			break
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.horde.e_dash[ci] > 0.0, "then he charges")
	var dir: Vector2 = s.horde.charge_dir
	var side := dir.orthogonal()
	var from: Vector2 = s.horde.e_pos[ci]
	var victim: Dictionary = s.soldiers[0]
	victim.pos = from + dir * 20.0 + side * 2.0
	var hp0: float = victim.hp
	var thrown := 0.0
	var hurt := false
	for f in 120:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		thrown = maxf(thrown, absf((victim.pos - from).dot(side)))
		hurt = hurt or victim.hp < hp0
		if s.horde.e_dash[ci] <= 0.0:
			break
	check(thrown >= float(atk.throw) * 0.7, "a soldier in his path is thrown aside (%.0f px)" % thrown)
	check(hurt, "and hurt")
	var length: float = float(s.content.enemies.chieftain.speed) * float(atk.speed_mult) * float(atk.seconds)
	check(s.horde.e_pos[ci].distance_to(from) > length * 0.8, "he charges on through the soldier (%.0f of %.0f px)" % [s.horde.e_pos[ci].distance_to(from), length])


func test_the_chieftains_slam_warns_then_hurts_everyone_in_the_ring(b: Dictionary) -> void:
	var s := _chief_sim(b, 142)
	var atk: Dictionary = s.content.enemies.chieftain.attacks.slam
	s.horde.spawn("chieftain", Vector2(40, 0))
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	s.horde.slam_cd = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var ci := s.chieftain_index()
	var rings := 0
	for l in s.horde.foe_lobs:
		if l.get("slam", false) and l.to.distance_to(s.horde.e_pos[ci]) < 2.0 and is_equal_approx(float(l.dur), float(atk.windup)):
			rings += 1
	check(rings == 1, "a red ring round the chieftain fills in before his slam")
	var start: Vector2 = s.horde.e_pos[ci]
	_step_dt(s, float(atk.windup) * 0.8)
	check(s.horde.e_pos[ci].distance_to(start) < 1.0, "he stands still while it fills")
	for testudo in [false, true]:
		var t := _chief_sim(b, 146)
		var i := t.horde.spawn("chieftain", Vector2(300, 300))
		var victim: Dictionary = t.soldiers[0]
		var other: Dictionary = t.soldiers[1]
		victim.pos = Vector2(300 + float(atk.radius) * 0.5, 300)
		other.pos = Vector2(300 + float(atk.radius) + 40.0, 300)
		t._rebuild_grids()
		if testudo:
			t.testudo_left = 3.0
		var hp0: float = victim.hp
		check(t.horde.slam(i, t), "he slams when a soldier is inside the ring")
		t.horde._foe_lobs(float(atk.windup) + 0.01, t)
		var want: float = float(t.content.enemies.chieftain.dps) * float(atk.damage_mult) * (float(b.testudo_damage_taken) if testudo else 1.0)
		check(is_equal_approx(hp0 - victim.hp, want), "the slam takes %.0f from a soldier in the ring (testudo %s)" % [want, testudo])
		check(other.hp == other.max_hp, "a soldier outside the ring is untouched by the slam")


func test_the_chieftains_horn_brings_a_war_band_behind_the_legion(b: Dictionary) -> void:
	var s := _chief_sim(b, 143)
	s.facing_angle = 0.0
	s.horde.spawn("chieftain", Vector2(300, 0))
	var before := s.horde.e_pos.size()
	s.horde.horn_cd = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var n := s.horde.e_pos.size() - before
	check(n == int(b.war_band.size_start), "his horn brings a war band (%d)" % n)
	var centre := Vector2.ZERO
	for k in range(before, s.horde.e_pos.size()):
		centre += s.horde.e_pos[k]
	centre /= maxf(1.0, n)
	check((centre - s.commander.pos).dot(Vector2.RIGHT) < -float(b.spawn_radius) * 0.5, "the horn's war band arrives behind the legion")


func test_the_berserker_goes_round_to_the_rear(b: Dictionary) -> void:
	var s := _chief_sim(b, 144)
	s.facing_angle = 0.0
	var id: int = s.horde.e_id[s.horde.spawn("berserker", Vector2(300, 0), true)]
	var cut_through := false
	var reached := false
	for f in 60 * 15:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		var j := s.horde.e_id.find(id)
		if j < 0:
			break
		var rel: Vector2 = s.horde.e_pos[j] - s.commander.pos
		if rel.x > 0.0 and rel.length() < s.legion_reach - 4.0:
			cut_through = true
		if rel.x < -10.0 and s.horde.e_fighting[j] == 1:
			reached = true
			break
	check(not cut_through, "the berserker never walks into the front of the legion")
	check(s.horde.e_id.has(id), "the berserker is still alive to fight")
	check(reached, "he comes round and fights the rear")


func test_chargers_dash_in_a_line(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 99})
	var i: int = s.horde.spawn("cataphract", Vector2(200, 0))
	s.horde.e_cd[i] = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.horde.e_dash[i] > 0.0, "the cataphract starts a dash")
	var speed: float = float(content.enemies.cataphract.speed)
	var from: Vector2 = s.horde.e_pos[i]
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(from.distance_to(s.horde.e_pos[i]) / (1.0 / 60.0) > speed * 2.0, "the dash is much faster than a walk")


func test_beasts_are_fast_and_frail(b: Dictionary) -> void:
	check(content.enemies.wolf.behaviour == "beast", "the wolf is a beast")
	check(float(content.enemies.wolf.speed) > float(content.enemies.barbarian_club.speed) and float(content.enemies.wolf.hp) < float(content.enemies.barbarian_club.hp), "fast with low health")


func test_a_province_turns_on_with_its_ground_and_draws_it(b: Dictionary) -> void:
	var keys := Content.available_art()
	check(keys.has("ground:germania"), "Germania's ground is found in the grounds folder")
	var art := {}
	for k in content.provinces.gaul.art:
		art[k] = true
	for id in content.provinces.gaul.ordinary + content.provinces.gaul.elites + [content.provinces.gaul.chieftain]:
		for k in content.enemies[id].art:
			art[k] = true
	var c := Content.load_all(art)
	check(c.ready("provinces", "gaul"), "a province with its ground, props and enemies is ready")
	art.erase("ground:gaul")
	check(not Content.load_all(art).ready("provinces", "gaul"), "without its ground it stays hidden")
	var s := Sim.new(b, c, {"seed": 5, "province": "gaul"})
	check(s.province == "gaul" and Content.ground_path("gaul") == "res://assets/grounds/gaul.png", "Gaul draws its own ground")
	check(Content.ground_path("hibernia") == "res://assets/grounds/germania.png", "a province without a file falls back to Germania's ground")


func test_the_crowd_round_the_legion_stops_growing_at_its_limit(b: Dictionary) -> void:
	for level in ["easy", "medium", "hard"]:
		var s := Sim.new(b, content, {"seed": 140, "difficulty": level})
		s.commander.max_hp = 1e9
		s.commander.hp = 1e9
		var most := int(b.crowd[level])
		var crowd := 0
		for i in most:
			s.horde.spawn("barbarian_club", s.commander.pos + Vector2.from_angle(i * 2.39996) * 150.0)
		s.time = 400.0
		s.horde.time = 400.0
		s.horde.next_surge = 400.5
		s.horde.next_band = 400.5
		var before := s.horde.e_pos.size()
		for f in 120:
			s.update(1.0 / 60.0, Vector2.ZERO, false)
			crowd = maxi(crowd, s.horde.crowd)
		check(crowd <= most + 2, "on %s the crowd stays near %d (%d)" % [level, most, crowd])
		check(s.horde.e_pos.size() <= before + 2, "on %s no surge or band is added to a full crowd (%d from %d)" % [level, s.horde.e_pos.size(), before])
	var thin := Sim.new(b, content, {"seed": 141})
	thin.commander.max_hp = 1e9
	thin.commander.hp = 1e9
	thin.time = 400.0
	thin.horde.time = 400.0
	var start := thin.horde.e_pos.size()
	_step_dt(thin, 2.0)
	check(thin.horde.e_pos.size() > start + 5, "a thin crowd still gets its stream (%d from %d)" % [thin.horde.e_pos.size(), start])
	check(b.crowd.easy < b.crowd.medium and b.crowd.medium < b.crowd.hard, "the limit rises with the difficulty")


func test_enemies_walk_at_the_balance_share_of_their_listed_speed(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 142})
	var mult := float(b.enemy_speed_mult)
	check(mult < 1.0, "enemies are slowed from their listed speed (%.2f)" % mult)
	for id in ["barbarian_club", "wolf", "berserker"]:
		var want := float(content.enemies[id].speed) * mult
		check(absf(s.horde.k_speed[s.horde.kind_of[id]] - want) < 0.001, "%s walks at %.1f" % [id, want])


func test_province_only_spawns_its_ready_enemies(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 100})
	var ready_ids: Array = content.province_enemies("germania")
	check(ready_ids.has("axe_thrower") and ready_ids.has("wolf"), "the drawn Germanic enemies are ready")
	ready_ids = ready_ids + s.horde.elites
	s.time = 300.0
	_step_dt(s, 30.0)
	var seen := {}
	for k in s.horde.e_kind:
		seen[s.horde.kind_ids[k]] = true
	for id in seen:
		check(ready_ids.has(id), "%s may spawn" % id)
	check(not seen.has("painted_warrior") and not seen.has("gaul_swordsman"), "no enemy from another province appears")
	var wide := Sim.new(b, Content.with_all_art(), {"seed": 101})
	wide.time = float(b.bosses.first) - 0.1
	_step_dt(wide, 1.0)
	var elite := false
	for t in wide.horde.e_tag:
		elite = elite or t == Horde.ELITE
	check(elite, "a ready elite arrives on the boss timer")
	var wrong := Sim.new(b, Content.with_all_art(), {"seed": 102, "province": "britannia"})
	check(wrong.horde.ordinary == content.provinces.britannia.ordinary, "another province brings its own")


func test_thrower_stays_outside_a_big_legion(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 103})
	s.b = b.duplicate()
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	for i in 38:
		s.add_soldier("legionary")
	s.legion.place_all(0.0)
	s.terrain.clear()
	s.horde.spawn("axe_thrower", Vector2(400, 0))
	# Enough throws for the whole test, so only the standing off is checked here.
	s.horde.e_ammo[0] = 1000
	var reach := float(Content.with_all_art().enemies.axe_thrower.range)
	var hp0 := 0.0
	for u in [s.commander] + s.soldiers:
		hp0 += u.hp
	var nearest := INF
	for i in 900:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		for u in s.soldiers:
			nearest = minf(nearest, u.pos.distance_to(s.horde.e_pos[0]))
	check(nearest > reach, "while it has axes the thrower stays outside every soldier (%.1f)" % nearest)
	check(s.horde.e_fighting[0] == 0, "and never fights in melee")


## A run with no arrivals of its own and an unkillable commander.
func _mode_sim(b: Dictionary, options: Dictionary) -> Sim:
	var s := Sim.new(b, Content.with_all_art(), options)
	s.b = b.duplicate(true)
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	return s


func test_endless_keeps_going_after_the_chieftain(b: Dictionary) -> void:
	var s := _mode_sim(b, {"seed": 110, "endless": true})
	s.time = float(b.chieftain_at) - 0.01
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var ci := s.chieftain_index()
	check(ci >= 0, "the chieftain arrived")
	_kill_chief_and_hold(s, b)
	check(not s.over and s.victory, "his death and the fort held do not end an endless run but win it")
	_step_dt(s, float(b.triumph.most_seconds) + 0.1)
	s.commander.hp = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.over and s.victory, "the win stands when the legion falls later")
	var saved: Dictionary = Profile.data
	Profile.data = Profile.defaults()
	Profile.record_run(s)
	check(bool(Profile.record_of(s.province).won), "the win is recorded")
	check(Profile.province_unlocked("gaul"), "and opens the next province")
	Profile.data = saved
	var plain := _mode_sim(b, {"seed": 110})
	var since := s.time
	s.time = since + 120.0
	plain.time = s.time
	s.horde.time = s.time
	plain.horde.time = s.time
	var a := s.horde.spawn("barbarian_club", Vector2(300, 0))
	var c := plain.horde.spawn("barbarian_club", Vector2(300, 0))
	var want := 1.0 + 2.0 * float(b.endless.health_per_minute)
	check(absf(s.horde.e_hp[a] / plain.horde.e_hp[c] - want) < 0.001, "two minutes on, enemies have %.2f times the health (%.3f)" % [want, s.horde.e_hp[a] / plain.horde.e_hp[c]])
	var normal := _mode_sim(b, {"seed": 111})
	normal.time = float(b.chieftain_at) - 0.01
	normal.update(1.0 / 60.0, Vector2.ZERO, false)
	_kill_chief_and_hold(normal, b)
	_step_dt(normal, float(b.triumph.most_seconds) + 0.1)
	check(normal.over and normal.victory, "a normal run still ends with the chieftain and the fort")


func test_decimatio_takes_one_in_ten(b: Dictionary) -> void:
	var s := _mode_sim(b, {"seed": 112, "decimatio": true})
	check(s.soldiers.size() == int(b.decimatio.start_soldiers), "the legion starts at %d" % int(b.decimatio.start_soldiers))
	s.time = float(b.decimatio.every) - 0.01
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.soldiers.size() == 27, "one in ten is gone after two minutes (%d)" % s.soldiers.size())
	s.time = 2.0 * float(b.decimatio.every) - 0.01
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.soldiers.size() == 25, "and again after four (%d)" % s.soldiers.size())
	var small := _mode_sim(b, {"seed": 113, "decimatio": true})
	small.soldiers.resize(10)
	small.time = float(b.decimatio.every) - 0.01
	small.update(1.0 / 60.0, Vector2.ZERO, false)
	check(small.soldiers.size() == 9, "ten soldiers lose one")
	var falls := 0
	for e in small.effects:
		falls += 1 if e.kind == "fallen" else 0
	check(falls == 1, "the lost soldier is shown falling")
	var tiny := _mode_sim(b, {"seed": 114, "decimatio": true})
	tiny.soldiers.resize(9)
	tiny.time = float(b.decimatio.every) - 0.01
	tiny.update(1.0 / 60.0, Vector2.ZERO, false)
	check(tiny.soldiers.size() == 9, "nine soldiers lose none")
	var archers := _mode_sim(b, {"seed": 115, "decimatio": true, "commander": "archer_captain"})
	check(archers.soldiers.size() == 30 and archers.count("archer") > 3 and archers.count("legionary") == 0, "the archer captain's legion is archers")


func test_hard_mode_pays_more(b: Dictionary) -> void:
	var medium := _mode_sim(b, {"seed": 116})
	var hard := _mode_sim(b, {"seed": 116, "difficulty": "hard"})
	check(medium.difficulty == "medium" and hard.difficulty == "hard", "a run is Medium unless it asks for another difficulty")
	var e := medium.horde.spawn("barbarian_club", Vector2(300, 0))
	var h := hard.horde.spawn("barbarian_club", Vector2(300, 0))
	check(absf(hard.horde.e_hp[h] / medium.horde.e_hp[e] - float(b.hard.health_mult) / float(b.medium.get("health_mult", 1.0))) < 0.001, "enemies have more health")
	check(absf(hard.horde.e_power[h] / medium.horde.e_power[e] - float(b.hard.get("damage_mult", 1.0)) / float(b.medium.get("damage_mult", 1.0))) < 0.001, "and hit as hard as its block says")
	var ratio := _pay_ratio(medium, hard)
	var paid := float(b.hard.denarii_mult) / float(b.medium.get("denarii_mult", 1.0))
	check(ratio > 1.1 and absf(ratio - paid) < 0.15, "denarii pay about %.2f times as much (%.2f)" % [paid, ratio])
	check(_crowd_after(medium, hard, 10.0) > 1.2, "and they arrive faster")


func test_easy_mode_is_gentler_and_pays_less(b: Dictionary) -> void:
	var cfg: Dictionary = b.easy
	check(float(cfg.health_mult) < 1.0 and float(cfg.spawn_mult) < 1.0 and float(cfg.denarii_mult) < 1.0, "Easy lowers health, numbers and pay")
	var medium := _mode_sim(b, {"seed": 122})
	var easy := _mode_sim(b, {"seed": 122, "difficulty": "easy"})
	var m := medium.horde.spawn("barbarian_club", Vector2(300, 0))
	var e := easy.horde.spawn("barbarian_club", Vector2(300, 0))
	check(absf(easy.horde.e_hp[e] / medium.horde.e_hp[m] - float(cfg.health_mult) / float(b.medium.get("health_mult", 1.0))) < 0.001, "enemies have less health")
	check(absf(easy.horde.e_power[e] / medium.horde.e_power[m] - float(cfg.get("damage_mult", 1.0)) / float(b.medium.get("damage_mult", 1.0))) < 0.001, "and hit as hard as its block says")
	var ratio := _pay_ratio(medium, easy)
	var paid := float(cfg.denarii_mult) / float(b.medium.get("denarii_mult", 1.0))
	check(absf(ratio - paid) < 0.15, "denarii pay about %.2f times as much (%.2f)" % [paid, ratio])
	check(_crowd_after(medium, easy, 10.0) < 0.9, "and fewer of them come")
	var gaul_m := _mode_sim(b, {"seed": 123, "province": "gaul"})
	var gaul_e := _mode_sim(b, {"seed": 123, "province": "gaul", "difficulty": "easy"})
	var gm := gaul_m.horde.spawn("barbarian_club", Vector2(300, 0))
	var ge := gaul_e.horde.spawn("barbarian_club", Vector2(300, 0))
	check(absf(gaul_e.horde.e_hp[ge] / gaul_m.horde.e_hp[gm] - float(cfg.health_mult) / float(b.medium.get("health_mult", 1.0))) < 0.001, "on top of the province's own difficulty")
	check(_mode_sim(b, {"seed": 124, "difficulty": "nonsense"}).difficulty == "medium", "an unknown difficulty plays as Medium")


## The denarii a run at another difficulty pays for 400 kills, against the first run's.
func _pay_ratio(base: Sim, other: Sim) -> float:
	var paid := [0, 0]
	var runs := [base, other]
	for k in 2:
		var s: Sim = runs[k]
		for i in 400:
			s.horde.spawn("barbarian_club", Vector2(300, 0))
			s.horde.e_hp[s.horde.e_hp.size() - 1] = 0.0
		s._remove_dead()
		for v in s.c_val:
			paid[k] += v
	return float(paid[1]) / maxf(1.0, float(paid[0]))


## How many enemies the second run has after `seconds` of a steady stream, against the first run's.
func _crowd_after(base: Sim, other: Sim, seconds: float) -> float:
	base.b.spawn_per_second_start = 2.0
	other.b.spawn_per_second_start = 2.0
	for i in int(seconds * 60.0):
		base.update(1.0 / 60.0, Vector2.ZERO, false)
		other.update(1.0 / 60.0, Vector2.ZERO, false)
	return float(other.horde.e_pos.size()) / maxf(1.0, float(base.horde.e_pos.size()))


func test_each_commander_starts_with_his_kit(b: Dictionary) -> void:
	var all := Content.with_all_art()
	for id in all.commanders:
		var kit: Dictionary = all.commanders[id].starts
		var s := _mode_sim(b, {"seed": 117, "commander": id})
		for key in kit:
			if key.begins_with("arm:"):
				check(s.rank(key.trim_prefix("arm:")) == int(kit[key]), "%s starts with the %s" % [id, key])
			else:
				check(s.count(key) == int(kit[key]), "%s starts with %d %s" % [id, int(kit[key]), key])
		check(s.commander_id == id, "%s is the commander" % id)
	var old := _mode_sim(b, {"seed": 118, "commander": "old_centurion"})
	check(Sim.new(b, all, {"seed": 118, "commander": "old_centurion"}).commander.max_hp == float(all.base_commander.hp) * 1.5, "the old centurion has more health")
	check(old.speed() < _mode_sim(b, {"seed": 118}).speed(), "and marches slower")
	check(_mode_sim(b, {"seed": 118, "commander": "legate"}).rerolls == int(b.rerolls) + 1, "the legate has a free reroll")
	check(_mode_sim(b, {"seed": 119}).count("legionary") == 2, "the default is the tribune with two legionaries")
	check(content.ready("commanders", "tribune"), "the tribune can be chosen")
	check(not content.ready("commanders", "cavalry_prefect") or content.available.has("unit:cavalry"), "a commander whose cavalry is not drawn is not offered")


func test_quartermaster_ranks_change_the_start(b: Dictionary) -> void:
	var fresh := Sim.new(b, Content.with_all_art(), {"seed": 120, "profile_bonuses": {"start_health": 2, "start_soldiers": 3, "rerolls": 2, "banishes": 1, "move_speed": 2}})
	var qm: Dictionary = fresh.content.quartermaster
	check(fresh.commander.max_hp == float(fresh.content.base_commander.hp) + 2.0 * float(qm.start_health.per_rank), "two ranks of health")
	check(fresh.count("legionary") == 2 + 3, "three more soldiers")
	check(fresh.rerolls == int(b.rerolls) + 2 and fresh.banishes == int(b.banishes) + 1, "more rerolls and banishes")
	check(Sim.new(b, Content.with_all_art(), {"commander": "nobody"}).commander_id == "tribune", "an unknown commander becomes the tribune")
	var base := _mode_sim(b, {"seed": 121})
	var boosted := _mode_sim(b, {"seed": 121, "profile_bonuses": {"damage": 4, "pickup_radius": 3, "testudo_charge": 4, "experience": 2, "denarii": 5, "no_such_upgrade": 9}})
	var qd: Dictionary = base.content.quartermaster
	for s in [base, boosted]:
		s.horde.spawn("barbarian_club", Vector2(300, 0))
	var hp0: float = base.horde.e_hp[0]
	base.scorch(0, 5.0)
	boosted.scorch(0, 5.0)
	check(absf((hp0 - boosted.horde.e_hp[0]) / (hp0 - base.horde.e_hp[0]) - (1.0 + 4.0 * float(qd.damage.per_rank))) < 0.001, "the damage bonus counts for scorching")
	base.horde.e_burn[0] = 1.0
	base.horde.e_burn_dps[0] = 10.0
	boosted.horde.e_burn[0] = 1.0
	boosted.horde.e_burn_dps[0] = 10.0
	var h1: float = base.horde.e_hp[0]
	var h2: float = boosted.horde.e_hp[0]
	base._burns(0.1)
	boosted._burns(0.1)
	check(absf((h2 - boosted.horde.e_hp[0]) / (h1 - base.horde.e_hp[0]) - (1.0 + 4.0 * float(qd.damage.per_rank))) < 0.001, "and for burning")
	check(is_equal_approx(boosted.pickup_radius() / base.pickup_radius(), 1.0 + 3.0 * float(qd.pickup_radius.per_rank)), "pickup radius grows")
	for s in [base, boosted]:
		s.testudo_charge = 0.0
		s.update(1.0, Vector2.ZERO, false)
	check(boosted.testudo_charge > base.testudo_charge, "the testudo charges sooner")
	base.gain(100)
	boosted.gain(100)
	check(boosted.xp + boosted.level * 1000 > base.xp + base.level * 1000, "coins give more experience")
	for s in [base, boosted]:
		s.c_pos.clear()
		s.c_val.clear()
		for i in 400:
			s.horde.spawn("barbarian_club", Vector2(300, 0))
			s.horde.e_hp[s.horde.e_hp.size() - 1] = 0.0
		s._remove_dead()
	var paid_base := 0
	var paid_boosted := 0
	for v in base.c_val:
		paid_base += v
	for v in boosted.c_val:
		paid_boosted += v
	check(paid_boosted > paid_base * 1.15, "kills pay more denarii")
	check(boosted.bonus_amount("no_such_upgrade") == 0.0, "an unknown upgrade adds nothing")
	check(fresh.speed() > Sim.new(b, Content.with_all_art(), {"seed": 120}).speed(), "a faster march")


const ProfileScript := preload("res://scripts/profile.gd")
const TEST_SAVES := "user://test_saves"


## A profile playing slot 1 of the test folder, which never holds the player's own saves.
func _fresh_profile() -> Node:
	var p: Node = ProfileScript.new()
	p.disabled = false
	p.dir = TEST_SAVES
	p.slot = 1
	p.data = ProfileScript.defaults()
	p.settings = {}
	return p


func _cleanup_profile_files() -> void:
	var d := DirAccess.open(TEST_SAVES)
	if d == null:
		return
	for f in d.get_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_SAVES.path_join(f)))


func _write_raw(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func _test_files() -> Array:
	var d := DirAccess.open(TEST_SAVES)
	return Array(d.get_files()) if d != null else []


func test_denarii_are_banked_after_a_run(b: Dictionary) -> void:
	var p := _fresh_profile()
	var all := Content.with_all_art()
	var s := Sim.new(b, all, {"seed": 130})
	s.denarii = 120
	s.kills = 40
	s.over = true
	s.victory = false
	p.record_run(s)
	check(p.data.denarii == 120, "a lost run still banks its denarii")
	check(p.data.totals.kills == 40 and p.data.totals.runs == 1, "kills and runs are counted")
	check(not p.record_of("germania").won, "a lost run is not a win")
	check(p.data.seen.has("legionary"), "the legion's recruits are seen")
	var again := Sim.new(b, all, {"seed": 131})
	again.denarii = 30
	again.over = true
	p.record_run(again)
	check(p.data.denarii == 150, "denarii add up across runs")
	p.free()
	_cleanup_profile_files()


## A finished run in Germania of `seconds`, won or not, with its difficulty and modes.
func _finished(b: Dictionary, c: Content, seconds: float, won: bool, options: Dictionary) -> Sim:
	options.seed = 140
	var s := Sim.new(b, c, options)
	s.time = seconds
	s.over = true
	s.victory = won
	return s


func test_a_win_is_recorded_under_its_difficulty_and_mode_only(b: Dictionary) -> void:
	var p := _fresh_profile()
	var all := Content.with_all_art()
	p.record_run(_finished(b, all, 900.0, true, {"difficulty": "easy"}))
	var others := []
	for d in Sim.DIFFICULTIES:
		for m in ProfileScript.TIME_MODES:
			if p.mode_time("germania", d, m) > 0.0 and not (d == "easy" and m == "win"):
				others.append("%s %s" % [d, m])
	check(is_equal_approx(p.mode_time("germania", "easy", "win"), 900.0) and others.is_empty(), "an Easy win is Easy's best time and nothing else's (%s)" % str(others))
	p.record_run(_finished(b, all, 1000.0, true, {"difficulty": "hard", "decimatio": true}))
	check(is_equal_approx(p.mode_time("germania", "hard", "decimatio"), 1000.0) and p.mode_time("germania", "hard", "win") <= 0.0, "a Hard win with Decimatio is Hard's Decimatio time, not its plain one")
	check(p.record_of("germania").won and p.record_of("germania").hard_won, "and still counts as won and hard won")
	p.free()
	_cleanup_profile_files()


func test_a_slower_win_keeps_the_faster_time(b: Dictionary) -> void:
	var p := _fresh_profile()
	var all := Content.with_all_art()
	p.record_run(_finished(b, all, 900.0, true, {"difficulty": "medium"}))
	p.record_run(_finished(b, all, 1000.0, true, {"difficulty": "medium"}))
	check(is_equal_approx(p.mode_time("germania", "medium", "win"), 900.0), "a slower win leaves the best time")
	p.record_run(_finished(b, all, 800.0, true, {"difficulty": "medium"}))
	check(is_equal_approx(p.mode_time("germania", "medium", "win"), 800.0), "a faster one replaces it")
	p.record_run(_finished(b, all, 700.0, false, {"difficulty": "medium"}))
	check(is_equal_approx(p.mode_time("germania", "medium", "win"), 800.0), "a lost run is no best time")
	p.free()
	_cleanup_profile_files()


func test_endless_keeps_the_longest_run_of_each_difficulty(b: Dictionary) -> void:
	var p := _fresh_profile()
	var all := Content.with_all_art()
	p.record_run(_finished(b, all, 1200.0, false, {"difficulty": "hard", "endless": true}))
	p.record_run(_finished(b, all, 1100.0, false, {"difficulty": "hard", "endless": true}))
	check(is_equal_approx(p.mode_time("germania", "hard", "endless"), 1200.0), "a shorter endless run leaves the longest")
	var won := _finished(b, all, 1500.0, true, {"difficulty": "hard", "endless": true})
	won.endless_since = 950.0
	p.record_run(won)
	check(is_equal_approx(p.mode_time("germania", "hard", "endless"), 1500.0), "a longer one replaces it")
	check(is_equal_approx(p.mode_time("germania", "hard", "win"), 950.0), "and its win counts as the time the chieftain's fort was held")
	check(p.mode_time("germania", "medium", "endless") <= 0.0 and p.mode_time("germania", "easy", "endless") <= 0.0, "the other difficulties keep none")
	p.free()
	_cleanup_profile_files()


func test_an_old_save_keeps_its_record_as_a_medium_one(b: Dictionary) -> void:
	var p := _fresh_profile()
	p.data = ProfileScript.merge_saved({"unlocked": {"commanders": ["tribune"], "provinces": ["germania"]},
		"records": {"germania": {"best_time": 800.0, "longest": 1300.0, "won": true, "hard_won": true, "endless_best": 1300.0}}})
	p.open_won_provinces(content)
	check(p.record_of("germania").won and p.record_of("germania").hard_won and p.province_unlocked("gaul"), "an old win still counts as won and hard won")
	check(is_equal_approx(p.mode_time("germania", "medium", "win"), 800.0) and is_equal_approx(p.mode_time("germania", "medium", "endless"), 1300.0), "its times count under Medium")
	check(p.mode_time("germania", "easy", "win") <= 0.0 and p.mode_time("germania", "hard", "win") <= 0.0 and p.mode_time("germania", "medium", "decimatio") <= 0.0, "and nowhere else")
	p.record_run(_finished(b, Content.with_all_art(), 700.0, true, {"difficulty": "easy"}))
	check(is_equal_approx(p.mode_time("germania", "medium", "win"), 800.0) and is_equal_approx(p.mode_time("germania", "easy", "win"), 700.0), "a new Easy win leaves the old time under Medium")
	var raw := _fresh_profile()
	raw.data.records["germania"] = {"best_time": 900.0, "longest": 900.0, "won": true, "hard_won": false}
	check(is_equal_approx(raw.mode_time("germania", "medium", "win"), 900.0), "a record written without times reads the same way")
	raw.free()
	p.free()
	_cleanup_profile_files()


func test_the_map_panel_lists_each_modes_time(b: Dictionary) -> void:
	var host := _map_host(content, b, "germania")
	var map := MapScreen.new(host)
	var saved: Dictionary = Profile.data
	Profile.data = Profile.defaults()
	Profile.data.records["germania"] = ProfileScript.merge_saved({"records": {"germania": {"won": true,
		"times": {"easy": {"win": 900.0}, "medium": {"endless": 1500.0}, "hard": {"decimatio": 1000.0}}}}}).records.germania
	var rows := map.record_rows("germania")
	check(rows.map(func(r: Array) -> Array: return r.slice(1)) == [["15:00", "-", "-"], ["-", "-", "25:00"], ["-", "16:40", "-"]], "a row per difficulty with its win, Decimatio and Endless times (%s)" % str(rows))
	check(rows.map(func(r: Array) -> String: return r[0]) == MapScreen.LEVELS.map(func(l: Array) -> String: return TranslationServer.translate(l[1])), "named Easy, Medium and Hard")
	Profile.data = saved
	host.free()


func test_winning_germania_unlocks_the_archer_captain(b: Dictionary) -> void:
	var p := _fresh_profile()
	var all := Content.with_all_art()
	check(not p.commander_unlocked("archer_captain"), "he starts locked")
	var s := Sim.new(b, all, {"seed": 132})
	s.time = 900.0
	s.over = true
	s.victory = true
	p.record_run(s)
	check(p.commander_unlocked("archer_captain"), "winning in Germania unlocks the archer captain")
	check(p.record_of("germania").won and is_equal_approx(p.record_of("germania").best_time, 900.0), "the win and its time are recorded")
	check(p.province_unlocked("gaul"), "the next province opens")
	check(not p.commander_unlocked("legate") and not p.commander_unlocked("engineer"), "the others stay locked")
	check(not p.record_of("germania").hard_won, "a Medium win is not a hard win")
	var faster := Sim.new(b, all, {"seed": 133, "difficulty": "hard"})
	faster.time = 700.0
	faster.over = true
	faster.victory = true
	p.record_run(faster)
	check(p.record_of("germania").hard_won, "a hard win is its own record")
	var gentle := _fresh_profile()
	var easy := Sim.new(b, all, {"seed": 135, "difficulty": "easy", "province": "gaul"})
	easy.time = 900.0
	easy.over = true
	easy.victory = true
	gentle.record_run(easy)
	check(gentle.record_of("gaul").won and not gentle.record_of("gaul").hard_won, "an Easy win counts as won")
	var bold := _fresh_profile()
	var hard := Sim.new(b, all, {"seed": 136, "difficulty": "hard"})
	hard.time = 900.0
	hard.over = true
	hard.victory = true
	bold.record_run(hard)
	check(bold.record_of("germania").won and bold.record_of("germania").hard_won and bold.province_unlocked("gaul"), "a Hard win counts as won and opens the next province")
	bold.free()
	gentle.free()
	check(is_equal_approx(p.record_of("germania").best_time, 700.0), "the best time keeps the fastest win")
	var kills := Sim.new(b, all, {"seed": 134})
	kills.kills = 5000
	kills.over = true
	p.record_run(kills)
	check(p.commander_unlocked("cavalry_prefect"), "5,000 kills in total unlock the cavalry prefect")
	p.free()
	_cleanup_profile_files()


func test_quartermaster_rank_costs_and_caps(b: Dictionary) -> void:
	var p := _fresh_profile()
	var qm: Dictionary = content.quartermaster
	p.data.denarii = 1000000
	var capped := 0
	for id in qm:
		var info: Dictionary = qm[id]
		if info.get("repeat", false):
			continue
		capped += 1
		check(info.costs.size() == int(info.ranks), "%s has a cost for every rank" % id)
		for r in int(info.ranks):
			check(p.next_cost(id, content) == int(info.costs[r]), "%s rank %d costs what the data says" % [id, r + 1])
			var before: int = p.data.denarii
			check(p.buy(id, content), "%s rank %d can be bought" % [id, r + 1])
			check(before - p.data.denarii == int(info.costs[r]), "and costs exactly that")
		check(p.rank(id) == int(info.ranks), "%s reaches its cap" % id)
		check(p.next_cost(id, content) == -1 and not p.buy(id, content), "%s cannot go past its cap" % id)
	check(p.bonuses().size() == capped, "every rank reaches the run's bonuses")
	var poor := _fresh_profile()
	poor.data.denarii = int(qm.start_health.costs[0]) - 1
	check(not poor.buy("start_health", content) and poor.rank("start_health") == 0, "too few denarii buy nothing")
	check(poor.data.denarii == int(qm.start_health.costs[0]) - 1, "and spend nothing")
	check(not poor.buy("no_such_upgrade", content), "an unknown upgrade is refused")
	p.free()
	poor.free()
	_cleanup_profile_files()


func test_damaged_profile_loads_defaults(b: Dictionary) -> void:
	_cleanup_profile_files()
	var p := _fresh_profile()
	check(not p.load_slot(1) and p.data == ProfileScript.defaults(), "a missing file gives the defaults")
	for junk in ["", "not json at all {{{", "[1, 2, 3]", "\"text\"", "null", "{\"denarii\": 5}"]:
		_write_raw(p.path_for(1), junk)
		check(not p.load_slot(1) and p.data == ProfileScript.defaults(), "damaged file %s gives the defaults" % junk.left(8))
	_write_raw(p.path_for(1), JSON.stringify({"version": 1, "denarii": 75, "ranks": {"damage": 2, "armour": "lots"}, "totals": {"kills": "many", "runs": 3},
		"unlocked": {"commanders": ["tribune", "legate", 7]}, "seen": {"wolf": true, "pilum": "yes"}, "old_key": 1}))
	check(p.load_slot(1), "a save with readable parts loads")
	check(p.data.denarii == 75, "a readable number is kept")
	check(p.data.ranks == {"damage": 2}, "a rank with the wrong type is dropped and the rest kept")
	check(p.data.totals.kills == 0 and p.data.totals.runs == 3, "totals merge by key")
	check(p.data.unlocked.commanders == ["tribune", "legate"] and p.data.unlocked.provinces == ["germania"], "unlocks keep the readable ids")
	check(p.data.seen == {"wolf": true}, "seen keeps the true entries")
	check(not p.data.has("old_key"), "unknown keys are not carried")
	p.free()
	_cleanup_profile_files()


func test_disabled_profile_never_writes(b: Dictionary) -> void:
	_cleanup_profile_files()
	var p := _fresh_profile()
	p.disabled = true
	p.data.denarii = 99
	p.save()
	p.save_settings()
	check(_test_files().is_empty(), "a disabled profile writes nothing")
	p.disabled = false
	p.save()
	check(FileAccess.file_exists(p.path_for(1)), "an enabled one does write")
	var back := _fresh_profile()
	back.load_slot(1)
	check(back.data.denarii == 99, "and reads back what it wrote")
	back.free()
	p.free()
	_cleanup_profile_files()
	check(Profile.disabled, "the real profile is disabled while the tests run")
	check(Profile.dir == "user://" and Profile.slot == 0 and Profile.data == ProfileScript.defaults(), "and holds only defaults")


func test_save_slots_keep_their_own_progress(_b: Dictionary) -> void:
	_cleanup_profile_files()
	var p := _fresh_profile()
	p.slot = 0
	check(p.new_game() == 1, "the first game goes in slot 1")
	p.data.denarii = 50
	p.save()
	check(p.new_game() == 2 and p.data == ProfileScript.defaults(), "a new game starts from nothing in slot 2")
	p.data.denarii = 7
	p.data.records["germania"] = {"best_time": 900.0, "longest": 900.0, "won": true, "hard_won": false}
	p.save()
	check(p.load_slot(1) and p.slot == 1 and int(p.data.denarii) == 50 and not p.record_of("germania").won, "slot 1 keeps its own game")
	check(p.load_slot(2) and p.slot == 2 and int(p.data.denarii) == 7 and p.record_of("germania").won, "and slot 2 its own")
	check(not p.load_slot(3), "an empty slot loads nothing")
	var info: Dictionary = p.slot_info(2)
	check(info.get("won", []) == ["germania"] and int(info.get("denarii", -1)) == 7 and float(info.get("saved_at", 0.0)) > 0.0, "a slot tells what is in it (%s)" % str(info))
	check(p.slot_info(3).is_empty(), "and an empty slot tells nothing")
	var again := _fresh_profile()
	again.slot = 0
	again.start_up()
	check(again.slot == 2 and int(again.data.denarii) == 7, "starting the game opens the slot saved last")
	again.free()
	p.free()
	_cleanup_profile_files()


func test_a_new_game_takes_the_first_free_slot_and_never_overwrites(_b: Dictionary) -> void:
	_cleanup_profile_files()
	var p := _fresh_profile()
	p.slot = 0
	check(p.free_slot() == 1, "with no saves slot 1 is free")
	for n in [1, 2, 3]:
		check(p.new_game() == n, "game %d goes in slot %d" % [n, n])
		p.data.denarii = n * 100
		p.save()
	check(p.free_slot() == 0, "with three games no slot is free")
	check(p.new_game() == 0 and p.slot == 3 and int(p.data.denarii) == 300, "and a new game is refused, leaving the one being played")
	for n in [1, 2, 3]:
		check(int(p.slot_info(n).get("denarii", -1)) == n * 100, "slot %d is untouched" % n)
	p.delete_slot(2)
	check(p.free_slot() == 2 and p.new_game() == 2, "a deleted slot is the next free one")
	p.free()
	_cleanup_profile_files()


func test_deleting_a_slot_removes_it_and_its_backups(_b: Dictionary) -> void:
	_cleanup_profile_files()
	var p := _fresh_profile()
	p.save()
	_write_raw(p.path_for(1) + ".bak1", "{}")
	_write_raw(p.path_for(1) + ".bak3", "{}")
	_write_raw(p.path_for(1) + ".tmp", "{}")
	p.slot = 2
	p.save()
	p.load_slot(1)
	p.data.denarii = 40
	p.delete_slot(1)
	check(_test_files() == ["save_2.json"], "only the other slot's save is left (%s)" % str(_test_files()))
	check(p.slot == 0 and p.data == ProfileScript.defaults(), "deleting the slot being played leaves no game open")
	p.free()
	_cleanup_profile_files()


func test_a_broken_save_falls_back_to_its_newest_readable_backup(_b: Dictionary) -> void:
	_cleanup_profile_files()
	var p := _fresh_profile()
	p.data.denarii = 10
	p.save()
	p.data.denarii = 20
	p.save()
	check(FileAccess.file_exists(p.path_for(1) + ".bak1"), "a second save keeps the first as a backup")
	p.data.denarii = 30
	p.save()
	check(not FileAccess.file_exists(p.path_for(1) + ".bak2"), "backups move along at most every few minutes")
	_write_raw(p.path_for(1) + ".bak2", JSON.stringify({"version": 1, "saved_at": 1.0, "denarii": 5}))
	_write_raw(p.path_for(1), "{\"version\": 1, \"denar")
	check(p.load_slot(1) and int(p.data.denarii) == 10, "a broken save loads its newest readable backup")
	_write_raw(p.path_for(1) + ".bak1", "")
	check(p.load_slot(1) and int(p.data.denarii) == 5, "and the next one when that is broken too")
	_write_raw(p.path_for(1) + ".tmp", JSON.stringify({"version": 1, "saved_at": Time.get_unix_time_from_system() + 60.0, "denarii": 77}))
	check(p.load_slot(1) and int(p.data.denarii) == 77, "a newer whole .tmp left by a cut-off save is read first")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(p.path_for(1) + ".tmp"))
	_write_raw(p.path_for(1) + ".bak2", "garbage")
	check(not p.load_slot(1), "with nothing readable the slot does not load")
	check(p.slot_taken(1), "but the slot still counts as taken")
	check(p.free_slot() == 2, "so a new game never goes over it")
	p.slot = 1
	p.data = ProfileScript.defaults()
	p.data.denarii = 1
	p.save()
	var aside := _test_files().filter(func(f: String) -> bool: return f.contains(".unreadable-"))
	check(aside.size() == 3, "an unreadable game is set aside before anything is saved in its slot (%s)" % str(_test_files()))
	p.free()
	_cleanup_profile_files()


func test_settings_are_shared_by_every_slot(_b: Dictionary) -> void:
	_cleanup_profile_files()
	var p := _fresh_profile()
	p.slot = 0
	p.settings.text_size = 2
	p.settings.language = "de"
	check(p.save_settings(), "the settings save with no game open")
	p.new_game()
	p.save()
	p.new_game()
	p.settings.master = 0.3
	p.save_settings()
	p.load_slot(1)
	check(int(p.setting("text_size")) == 2 and is_equal_approx(float(p.setting("master")), 0.3), "loading another slot keeps the settings")
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(p.path_for(1)))
	check(not saved.has("settings") and not saved.has("text_size") and not str(saved).contains("language"), "a slot's file holds no settings")
	var other := _fresh_profile()
	other.load_settings()
	check(other.setting("language") == "de" and int(other.setting("text_size")) == 2, "the settings file is read back")
	other.free()
	p.free()
	_cleanup_profile_files()


func test_the_old_profile_moves_into_slot_one_and_the_settings_file(_b: Dictionary) -> void:
	_cleanup_profile_files()
	var old := JSON.stringify({"denarii": 4321, "ranks": {"damage": 3}, "unlocked": {"commanders": ["tribune", "engineer"], "provinces": ["germania", "gaul", "britannia"]},
		"records": {"germania": {"best_time": 800.0, "longest": 900.0, "won": true, "hard_won": true}, "gaul": {"won": true, "best_time": 850.0, "longest": 850.0}},
		"seen": {"wolf": true}, "totals": {"kills": 9000, "runs": 30, "wins": 2, "ravine_tips": 3}, "achievements": ["kills_1000"],
		"settings": {"language": "fr", "text_size": 2, "music": 0.4, "fullscreen": true, "bindings": {"left": {"keys": [KEY_J]}}, "province": "gaul", "commander": "engineer", "difficulty": "hard"}}, "\t")
	var old_path := TEST_SAVES.path_join("profile.json")
	_write_raw(old_path, old)
	var p := _fresh_profile()
	p.slot = 0
	p.start_up()
	check(p.slot == 1 and int(p.data.denarii) == 4321 and p.record_of("gaul").won and p.rank("damage") == 3, "the old progress opens in slot 1")
	check(p.data.get("choices", {}) == {"province": "gaul", "commander": "engineer", "difficulty": "hard"} and int(p.data.totals.kills) == 9000, "with its choices and totals")
	check(p.data.achievements == ["kills_1000"] and p.commander_unlocked("engineer"), "its achievements and unlocks")
	check(p.setting("language") == "fr" and int(p.setting("text_size")) == 2 and p.setting("fullscreen") == true, "the old settings are the shared settings")
	check(p.setting("bindings").get("left", {}).get("keys", []) == [KEY_J], "the player's own keys too")
	check(FileAccess.file_exists(p.settings_path()) and FileAccess.file_exists(p.path_for(1)), "both files are written")
	check(not FileAccess.file_exists(old_path), "the old file is no longer read")
	check(FileAccess.get_file_as_string(old_path + ".migrated") == old, "but kept whole beside them")
	var next := _fresh_profile()
	next.slot = 0
	next.start_up()
	check(next.slot == 1 and next.free_slot() == 2 and int(next.data.denarii) == 4321, "the next start opens the same game and makes no copy")
	next.free()
	_write_raw(old_path, old)
	var twice := _fresh_profile()
	twice.slot = 0
	twice.start_up()
	check(twice.free_slot() == 2 and FileAccess.file_exists(old_path), "an old file beside saves already made is left alone")
	twice.free()
	p.free()
	_cleanup_profile_files()
	_write_raw(old_path, "{ not json")
	var broken := _fresh_profile()
	broken.slot = 0
	broken.start_up()
	check(broken.slot == 0 and broken.free_slot() == 1 and FileAccess.get_file_as_string(old_path) == "{ not json", "an unreadable old file is left as it is")
	broken.free()
	_cleanup_profile_files()


func test_a_fresh_slot_plays_like_a_new_player(b: Dictionary) -> void:
	_cleanup_profile_files()
	var p := _fresh_profile()
	_won(b, p, "germania")
	p.data.denarii = 999
	p.slot = 0
	p.new_game()
	check(p.data == ProfileScript.defaults(), "a new game holds nothing earned")
	p.open_won_provinces(content)
	check(p.province_unlocked("germania") and not p.province_unlocked("gaul"), "only Germania is open")
	check(not p.commander_unlocked("archer_captain") and int(p.data.denarii) == 0, "with the tribune alone and no denarii")
	p.free()
	_cleanup_profile_files()


func test_saves_can_be_kept_in_another_folder(_b: Dictionary) -> void:
	check(ProfileScript.save_dir_of(PackedStringArray([])) == "user://", "saves are in the user folder")
	check(ProfileScript.save_dir_of(PackedStringArray(["--save-dir=look"])) == "user://look", "--save-dir keeps them in a folder of their own")
	check(not Profile.blocks_saving(PackedStringArray(["--save-dir=look"])), "where they are saved")
	check(Profile.blocks_saving(PackedStringArray(["--no-save"])) and Profile.blocks_saving(PackedStringArray(["--max-state"])), "--no-save and --max-state never save")
	check(not Profile.reads() and Profile.free_slot() == 1 and not Profile.load_slot(1), "and a look never reads the player's games")


class FakeMenuMain:
	extends Node
	var state := "saves"
	var ui := Ui.new()
	var content: Content
	var balance: Dictionary
	var camp := 0
	var used := 0

	func use_profile() -> void:
		used += 1

	func go_to_camp() -> void:
		camp += 1
		state = "camp"

	func go_to_title(focus_id := "continue") -> void:
		state = "title"
		ui.focus = focus_id

	func open_saves() -> void:
		state = "saves"


## Points the real Profile at the test folder for a test of the title or the load list, returning what to put back.
func _borrow_profile() -> Dictionary:
	_cleanup_profile_files()
	var kept := {"disabled": Profile.disabled, "dir": Profile.dir, "slot": Profile.slot, "data": Profile.data, "settings": Profile.settings}
	Profile.disabled = false
	Profile.dir = TEST_SAVES
	Profile.slot = 0
	Profile.data = ProfileScript.defaults()
	return kept


func _return_profile(kept: Dictionary) -> void:
	for key in kept:
		Profile.set(key, kept[key])
	_cleanup_profile_files()


func test_the_title_offers_continue_new_game_and_load(b: Dictionary) -> void:
	var kept := _borrow_profile()
	var ids := func() -> Array: return TitleScreen.buttons(b).map(func(x: Array) -> String: return x[0])
	check(ids.call() == ["new", "settings"], "a first start offers a new game (%s)" % str(ids.call()))
	var m := FakeMenuMain.new()
	m.state = "title"
	var title := TitleScreen.new(m)
	title.activate("new")
	check(Profile.slot == 1 and m.used == 1 and m.camp == 1, "New game opens slot 1 and goes to the camp")
	check(ids.call() == ["continue", "new", "load", "settings"], "with a game there is Continue and Load (%s)" % str(ids.call()))
	title.activate("continue")
	check(m.camp == 2 and Profile.slot == 1, "Continue goes on with the open game")
	Profile.new_game()
	Profile.new_game()
	var new_button: Array = TitleScreen.buttons(b)[1]
	check(new_button[0] == "new" and not new_button[2], "with three games New game is refused")
	title.activate("new")
	check(Profile.slot == 3 and m.camp == 2 and m.used == 1, "and pressing it changes nothing")
	title.activate("load")
	check(m.state == "saves", "Load opens the load list")
	m.free()
	_return_profile(kept)


func _key_press(code: Key, ch: String) -> InputEventKey:
	var e := InputEventKey.new()
	e.pressed = true
	e.keycode = code
	e.physical_keycode = code
	e.unicode = ch.unicode_at(0) if ch != "" else 0
	return e


func _type_word(saves: SavesScreen, word: String) -> void:
	for ch in word:
		saves.capture(_key_press(KEY_A, ch))


func test_the_load_list_plays_and_deletes_slots(b: Dictionary) -> void:
	var kept := _borrow_profile()
	var m := FakeMenuMain.new()
	m.content = content
	m.balance = b
	var saves := SavesScreen.new(m)
	Profile.new_game()
	Profile.data.denarii = 11
	Profile.save()
	Profile.new_game()
	Profile.data.denarii = 22
	Profile.save()
	saves.activate("play:1")
	check(Profile.slot == 1 and int(Profile.data.denarii) == 11 and m.used == 1 and m.camp == 1, "Play opens that slot's game in the camp")
	saves.activate("delete:2")
	check(saves.confirming == 2 and m.ui.focus == "no", "Delete asks first, starting on Cancel")
	saves.activate("no")
	check(saves.confirming == 0 and Profile.slot_taken(2) and m.ui.focus == "delete:2", "Cancel keeps the game")
	saves.activate("delete:2")
	check(saves.back() and saves.confirming == 0 and Profile.slot_taken(2), "and so does the back key")
	check(not saves.back(), "which then leaves the list")
	check(not saves.capture(_key_press(KEY_D, "d")), "keys are not taken for typing while no question is open")
	saves.activate("delete:2")
	saves.activate("yes")
	check(Profile.slot_taken(2) and saves.confirming == 2 and not saves.word_typed(), "Delete does nothing until the word is typed")
	check(saves.capture(_key_press(KEY_D, "d")), "a letter goes into the typed word, not to the menu")
	for ch in "eletex":
		saves.capture(_key_press(KEY_A, ch))
	check(not saves.word_typed(), "a wrong word does not delete")
	saves.capture(_key_press(KEY_BACKSPACE, ""))
	check(saves.word_typed(), "Backspace takes off the last letter (%s)" % saves.typed)
	saves.capture(_key_press(KEY_ENTER, ""))
	check(not Profile.slot_taken(2) and Profile.slot == 1, "Enter with the word typed deletes the game")
	saves.activate("delete:1")
	_type_word(saves, "delete")
	saves.capture(_key_press(KEY_ESCAPE, ""))
	check(saves.confirming == 0 and Profile.slot_taken(1), "Escape leaves the question and keeps the game")
	saves.activate("delete:1")
	check(saves.typed == "", "and the word starts empty each time")
	saves.back()
	Profile.new_game()
	Profile.save()
	Profile.load_slot(1)
	saves.activate("delete:1")
	_type_word(saves, "DELETE")
	saves.activate("yes")
	check(Profile.slot == 2 and m.used == 2, "deleting the open game opens the one saved last, the word typed in any case")
	saves.activate("delete:2")
	_type_word(saves, "delete")
	saves.activate("yes")
	check(Profile.slot == 0 and m.state == "title" and m.ui.focus == "new", "deleting the last game goes back to the title on New game")
	var info := {"won": ["germania", "gaul", "nowhere"], "denarii": 1240, "runs": 3, "saved_at": 0.0}
	var playable := content.provinces.keys().filter(func(p: String) -> bool: return content.ready("provinces", p)).size()
	check(SavesScreen.summary(info, content, b) == ["2 of %d provinces won" % playable, "1240 denarii"], "a row says the provinces won and the denarii (%s)" % str(SavesScreen.summary(info, content, b)))
	check(SavesScreen.played_on(Time.get_unix_time_from_system()).begins_with("Last played 20"), "and the day it was last played")
	m.free()
	_return_profile(kept)


func _won(b: Dictionary, p: Node, province: String, time := 900.0, peak := 99) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 140, "province": province})
	s.time = time
	s.peak_soldiers = peak
	s.over = true
	s.victory = true
	p.record_run(s)


func test_survive_unlock_needs_a_small_legion(b: Dictionary) -> void:
	var rule: Dictionary = content.commanders.old_centurion.unlock
	var few := _fresh_profile()
	_won(b, few, "germania", float(rule.seconds), int(rule.max_soldiers))
	check(few.commander_unlocked("old_centurion"), "a full-length win with 10 soldiers unlocks the old centurion")
	var many := _fresh_profile()
	_won(b, many, "germania", float(rule.seconds), int(rule.max_soldiers) + 1)
	check(not many.commander_unlocked("old_centurion"), "11 soldiers do not")
	var quick := _fresh_profile()
	_won(b, quick, "germania", float(rule.seconds) - 1.0, 3)
	check(not quick.commander_unlocked("old_centurion"), "a shorter run does not")
	for p in [few, many, quick]:
		p.free()


func test_the_engineer_and_legate_unlocks(b: Dictionary) -> void:
	var p := _fresh_profile()
	_won(b, p, "germania")
	check(not p.commander_unlocked("engineer"), "Germania does not unlock the engineer")
	_won(b, p, "gaul")
	check(p.commander_unlocked("engineer"), "winning in Gaul unlocks the engineer")
	check(not p.commander_unlocked("legate"), "two provinces are not enough for the legate")
	for id in ["britannia", "dacia", "parthia", "hispania", "aegyptus", "sarmatia"]:
		_won(b, p, id)
	check(p.commander_unlocked("legate"), "a win in every province unlocks the legate")
	p.free()


func test_every_entry_has_a_history_line(b: Dictionary) -> void:
	for kind in ["recruits", "arms", "forged", "enemies", "commanders", "gods"]:
		for id in content.get(kind):
			var line: String = str(content.get(kind)[id].get("history", ""))
			check(line.length() > 0 and line.length() <= 110, "%s has a history line that fits" % id)


func test_saved_choices_keep_only_text_for_province_and_commander(b: Dictionary) -> void:
	var merged: Dictionary = ProfileScript.merge_saved({"choices": {"province": 5, "commander": "legate", "other": 1}})
	check(not merged.choices.has("province") and merged.choices.commander == "legate", "only string choices are kept")
	check(not merged.choices.has("other"), "and nothing but the three choices")
	check(ProfileScript.merge_saved({"choices": {"difficulty": "easy"}}).choices.difficulty == "easy", "a saved difficulty is kept")
	check(not ProfileScript.merge_saved({"choices": {"difficulty": "brutal"}}).choices.has("difficulty"), "an unknown one is dropped")
	check(not ProfileScript.merge_saved({"choices": {"difficulty": 2}}).choices.has("difficulty"), "and so is one that is not text")
	var old: Dictionary = ProfileScript.merge_saved({"settings": {"province": "gaul", "difficulty": "hard", "language": "de"}})
	check(old.choices == {"province": "gaul", "difficulty": "hard"}, "an old profile's choices come from its settings")
	check(not old.has("settings"), "and a save keeps no settings of its own")


func test_damage_is_counted_by_source(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 201})
	var i := s.horde.spawn("barbarian_club", Vector2(300, 0))
	var whole: float = s.horde.e_max[i]
	s.hit(i, 6.0, 0.0, "pilum")
	s.scorch(i, 4.0, "fire_pots")
	check(is_equal_approx(float(s.damage_by_source.get("pilum", 0.0)), 6.0), "a hit is counted under its weapon")
	check(is_equal_approx(float(s.damage_by_source.get("fire_pots", 0.0)), 4.0), "burning ground is counted under its pot")
	s.hit(i, 1000.0, 0.0, "pilum")
	check(is_equal_approx(float(s.damage_by_source.pilum), whole - 4.0), "only the health that was left is counted, not the overkill")
	var boosted := Sim.new(b, content, {"seed": 202, "profile_bonuses": {"damage": 2}})
	var j := boosted.horde.spawn("barbarian_club", Vector2(300, 0))
	boosted.hit(j, 5.0, 0.0, "stakes")
	var want := 5.0 * (1.0 + 2.0 * float(content.quartermaster.damage.per_rank))
	check(is_equal_approx(float(boosted.damage_by_source.stakes), want), "the quartermaster's bonus is in the count")
	check(content.source_name("commander") != "" and content.source_name("pilum") == "Pilum volley", "sources have names from content")


func test_every_damage_path_names_its_source(b: Dictionary) -> void:
	var mixed := Content.with_all_art()
	var s := Sim.new(b, mixed, {"seed": 203})
	for kind in ["arms", "forged"]:
		for id in mixed.get(kind):
			if mixed.get(kind)[id].implemented:
				s.ranks[id] = 3
	for t in ["archer", "cavalry", "standard_bearer", "centurion", "ballista", "medicus"]:
		s.add_soldier(t)
	var kinds := ["barbarian_club", "barbarian_spear", "wolf"]
	for i in 90:
		s.horde.spawn(kinds[i % kinds.size()], s.commander.pos + Vector2.from_angle(i * 0.7) * (30.0 + i * 1.5))
	for f in 1200:
		s.update(1.0 / 60.0, Vector2(cos(f * 0.01), sin(f * 0.01)), false)
	check(s.damage_by_source.size() >= 4, "a busy twenty seconds is spread over several sources (%d)" % s.damage_by_source.size())
	for id in s.damage_by_source:
		check(mixed.source_name(id) != "", "the source '%s' has a name" % id)


func test_history_samples_every_ten_seconds(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 204})
	s.b = b.duplicate()
	# No barbarians come, so the legion stays the same size through all three samples.
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	Upgrades.apply(s, "archer")
	for f in 35 * 30:
		s.update(1.0 / 30.0, Vector2.ZERO, false)
		if s.over:
			break
	check(s.history.size() == 3, "three samples in 35 seconds (%d)" % s.history.size())
	if s.history.size() == 3:
		check(absf(float(s.history[0].t) - 10.0) < 0.1 and absf(float(s.history[2].t) - 30.0) < 0.1, "at 10, 20 and 30 seconds")
		check(int(s.history[0].legion) == s.soldiers.size() + 1 and s.history[0].has("kills"), "each holds the legion size and the kills")


func _has_key(action: String, code: int) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventKey and e.physical_keycode == code:
			return true
	return false


func _has_button(action: String, button: int) -> bool:
	for e in InputMap.action_get_events(action):
		if e is InputEventJoypadButton and e.button_index == button:
			return true
	return false


func test_rebinding_replaces_the_key(b: Dictionary) -> void:
	var saved := {}
	Controls.install(saved)
	check(_has_key("testudo", KEY_SPACE) and _has_button("testudo", JOY_BUTTON_A), "the defaults are in place")
	Controls.rebind(saved, "testudo", "keys", 0, KEY_T)
	check(_has_key("testudo", KEY_T) and not _has_key("testudo", KEY_SPACE), "the new key replaces the old one")
	check(_has_key("confirm", KEY_SPACE), "other actions keep their keys")
	Controls.rebind(saved, "testudo", "pads", 0, JOY_BUTTON_B)
	check(_has_button("testudo", JOY_BUTTON_B) and not _has_button("testudo", JOY_BUTTON_A), "a pad button is replaced the same way")
	Controls.rebind(saved, "up", "keys", 1, KEY_I)
	check(_has_key("up", KEY_W) and _has_key("up", KEY_I) and not _has_key("up", KEY_UP), "the second key slot leaves the first alone")
	Controls.install(saved)
	check(_has_key("testudo", KEY_T) and not _has_key("testudo", KEY_SPACE), "saved bindings are applied over the defaults")
	check(not InputMap.action_get_events("left").filter(func(e): return e is InputEventJoypadMotion).is_empty(), "the stick still steers")
	Controls.install({})
	check(_has_key("testudo", KEY_SPACE) and not _has_key("testudo", KEY_T), "no saved bindings gives the defaults back")


func test_rebinding_to_a_key_held_in_another_slot_keeps_it(b: Dictionary) -> void:
	var saved := {}
	Controls.install(saved)
	Controls.rebind(saved, "up", "keys", 0, KEY_UP)
	check(_has_key("up", KEY_UP) and not _has_key("up", KEY_W), "up keeps the arrow key it was moved to")
	check(saved.up.keys == [KEY_UP], "and lists it once")
	Controls.rebind(saved, "up", "keys", 0, KEY_UP)
	check(saved.up.keys == [KEY_UP], "rebinding the only key to itself leaves it")
	Controls.install({})


func test_empty_saved_bindings_fall_back_to_the_defaults(b: Dictionary) -> void:
	var cfg: Dictionary = ProfileScript.settings_of(ProfileScript.merge_settings({"bindings": {"up": {"keys": [], "pads": []}, "down": {"keys": [0, -3, "x"]}, "left": {"keys": [KEY_J]}}}))
	check(not cfg.bindings.has("up") and not cfg.bindings.has("down"), "empty or unusable lists are dropped when loaded")
	check(cfg.bindings.left.keys == [KEY_J], "a good list is kept")
	check(Controls.effective({"up": {"keys": [], "pads": []}}, "up").keys == [KEY_W, KEY_UP], "an empty saved list gives the defaults")
	var pad: Dictionary = ProfileScript.settings_of(ProfileScript.merge_settings({"bindings": {"testudo": {"pads": [0]}}}))
	check(pad.bindings.testudo.pads == [0], "pad button 0 is a real button")


func test_saved_settings_are_checked(b: Dictionary) -> void:
	var cfg: Dictionary = ProfileScript.settings_of(ProfileScript.merge_settings({"master": 4, "music": "loud", "text_size": 7, "shake": "yes", "numbers": false,
		"bindings": {"testudo": {"keys": [KEY_T, "x"], "pads": [2.0]}, "bad": 3}, "province": "gaul"}))
	check(not cfg.has("province"), "the shared settings keep only the player's settings")
	check(is_equal_approx(float(cfg.master), 1.0), "a volume is held between 0 and 1")
	check(is_equal_approx(float(cfg.music), float(ProfileScript.SETTING_DEFAULTS.music)), "a volume that is not a number gives the default")
	check(int(cfg.text_size) == 1 and cfg.shake == true and cfg.numbers == false, "text size, and the on or off choices, are checked")
	check(cfg.bindings.testudo.keys == [KEY_T] and cfg.bindings.testudo.pads == [2] and not cfg.bindings.has("bad"), "bindings keep only whole key and button numbers")


func test_damage_numbers_are_capped(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 205})
	for i in 100:
		s.horde.spawn("barbarian_club", Vector2(200 + i, 0))
	for i in 100:
		s.hit(i, 3.0, 0.0, "pilum")
	check(s.numbers.is_empty(), "no numbers are made while they are switched off")
	s.show_numbers = true
	for i in 100:
		s.hit(i, 1.0, 0.0, "pilum")
	check(s.numbers.size() == int(b.damage_numbers.cap), "at most %d are alive at once (%d)" % [int(b.damage_numbers.cap), s.numbers.size()])
	for f in 60:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.numbers.is_empty() or s.numbers.size() < int(b.damage_numbers.cap), "they fade away")


func test_shake_comes_from_hurt_chieftain_and_testudo(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 206})
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.shake <= 0.0, "a quiet legion does not shake")
	s.update(1.0 / 60.0, Vector2.ZERO, true)
	check(s.shake > 0.0, "raising the shields shakes the view")
	var h := Sim.new(b, content, {"seed": 207})
	h.update(1.0 / 60.0, Vector2.ZERO, false)
	h.commander.hp -= 5.0
	h.update(1.0 / 60.0, Vector2.ZERO, false)
	check(h.shake > 0.0, "the commander being hurt shakes the view")
	var before := h.shake
	for f in 60:
		h.update(1.0 / 60.0, Vector2.ZERO, false)
	check(h.shake == before, "the sim leaves decaying the shake to the view")


func _event_kinds(s: Sim) -> Array:
	var out := []
	for e in s.events:
		out.append(e.kind)
	return out


func test_events_are_reported_once(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 301})
	s.horde.spawn("barbarian_club", s.commander.pos + Vector2(12, 0))
	var seen := false
	for i in 120:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		var kinds := _event_kinds(s)
		check(kinds.count("hit") <= 1, "many hits in one update make one event")
		if "hit" in kinds:
			seen = true
			check(s.events[kinds.find("hit")].n >= 1 and s.events[kinds.find("hit")].has("pos"), "a hit event has a count and a place")
			break
	check(seen, "fighting reports a hit")
	s.events.clear()
	s.horde.e_pos.clear()
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(not ("hit" in _event_kinds(s)), "a hit is not reported again once the reader has cleared it")
	s.events.clear()
	s.gain(int(b.xp_first))
	check(_event_kinds(s) == ["level"], "a new level is one event")
	s.events.clear()
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(not ("level" in _event_kinds(s)), "the level is not reported twice")
	s.update(1.0 / 60.0, Vector2.ZERO, true)
	check("testudo" in _event_kinds(s), "raising the shields is an event")
	s.events.clear()
	s.time += float(b.hurt_every)
	s.commander.hp -= 5.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check("hurt" in _event_kinds(s), "the commander being hurt is an event")


func test_events_never_pile_up_unread(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 302})
	for i in 500:
		s.event("level", Vector2.ZERO)
	check(s.events.size() <= Sim.EVENT_CAP, "an unread list stops growing")


func test_settings_make_the_audio_buses(b: Dictionary) -> void:
	SettingsScreen.apply_audio({"master": 1.0, "music": 0.5, "effects": 0.0})
	for name in ["Master", "Music", "Effects"]:
		check(AudioServer.get_bus_index(name) >= 0, "the %s bus exists" % name)
	check(absf(AudioServer.get_bus_volume_db(AudioServer.get_bus_index("Music")) - linear_to_db(0.5)) < 0.01, "a volume sets its bus")
	check(AudioServer.is_bus_mute(AudioServer.get_bus_index("Effects")), "zero mutes the bus")
	SettingsScreen.apply_audio(Profile.SETTING_DEFAULTS)


func test_a_setting_leaves_a_maximized_window_maximized(_b: Dictionary) -> void:
	check(SettingsScreen.window_change(false, DisplayServer.WINDOW_MODE_MAXIMIZED) == -1, "a maximized window stays maximized")
	check(SettingsScreen.window_change(false, DisplayServer.WINDOW_MODE_WINDOWED) == -1, "a window stays a window")
	check(SettingsScreen.window_change(false, DisplayServer.WINDOW_MODE_FULLSCREEN) == DisplayServer.WINDOW_MODE_WINDOWED, "full screen turned off makes a window")
	check(SettingsScreen.window_change(false, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN) == DisplayServer.WINDOW_MODE_WINDOWED, "exclusive full screen turned off makes a window")
	check(SettingsScreen.window_change(true, DisplayServer.WINDOW_MODE_MAXIMIZED) == DisplayServer.WINDOW_MODE_FULLSCREEN, "full screen turned on fills the screen")
	check(SettingsScreen.window_change(true, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN) == -1, "a full screen stays full")


func test_a_volume_bar_follows_the_pointer(_b: Dictionary) -> void:
	var bar := Rect2(100, 50, 80, 20)
	check(is_equal_approx(SettingsScreen.value_at(bar, 140.0), 0.5), "the middle of the bar is half")
	check(is_equal_approx(SettingsScreen.value_at(bar, 172.0), 0.9), "a point near the end snaps to a tenth")
	check(SettingsScreen.value_at(bar, 20.0) == 0.0 and SettingsScreen.value_at(bar, 400.0) == 1.0, "a drag past either end stops at the end")


func test_summary_lists_the_top_eight_sources(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 208})
	for id in ["pilum", "fire_arrows", "scorpio", "onager", "caltrops", "stakes", "fire_pots", "war_dogs", "trumpets", "eagle"]:
		s.damage_by_source[id] = 10.0 + s.damage_by_source.size()
	s.damage_by_source["commander"] = 0.0
	var rows := SummaryScreen.top_sources(s)
	check(rows.size() == 8, "only eight bars")
	check(rows[0][0] == "Eagle" or content.source_name("eagle") == rows[0][0], "the biggest is first")
	check(rows[0][1] >= rows[7][1], "sorted from the most damage down")
	s.history = [{"t": 10.0, "legion": 3, "kills": 1}]
	s.time = 25.0
	check(SummaryScreen.chart_points(s).size() == 2, "the line is carried to the end of the run")


func test_achievements_unlock_from_the_run(b: Dictionary) -> void:
	var saved: Dictionary = Profile.data
	Profile.data = Profile.defaults()
	var s := Sim.new(b, content, {"seed": 30})
	var fresh: Array = Steamworks.check(s)
	check(fresh.is_empty(), "nothing is earned at the start")
	s.ranks["hooked_pila"] = 1
	for i in 30:
		s.add_soldier("legionary")
	s.update(1.0 / 60.0, Vector2.RIGHT, false)
	s.kills = 1000
	fresh = Steamworks.check(s)
	check("forge_hooked_pila" in fresh and "legion_25" in fresh and "kills_1000" in fresh, "forged form, legion size and kills are earned live")
	check(not "legion_50" in fresh and not "kills_10000" in fresh, "larger targets stay unearned")
	check(Steamworks.check(s).is_empty(), "an earned achievement is not earned again")
	check(Profile.data.achievements.size() == 3, "every earned one is kept in the profile")
	s.victory = true
	s.over = true
	Profile.record_run(s)
	fresh = Steamworks.check(s, true)
	check("win_germania" in fresh and not "kills_10000" in fresh, "a won province is earned when the run ends, and kills are not counted twice")
	check(Profile.merge_saved(JSON.parse_string(JSON.stringify(Profile.data))).achievements == Profile.data.achievements, "the earned list survives saving")
	Steamworks.queue.clear()
	Profile.data = saved


func test_presence_names_the_province_minute_and_legion(b: Dictionary) -> void:
	var march: Dictionary = Steamworks.presence_of("Germania", 4, 12)
	check(march == {"steam_display": "#Status_Marching", "province": "Germania", "minute": "4", "legion": "12"}, "marching presence")
	check(Steamworks.presence_of("", 0, 0) == {"steam_display": "#Status_Camp"}, "camp presence")
	var vdf := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join("../tools/steam/rich_presence.vdf"))
	for token in ["#Status_Marching", "#Status_Camp", "%province%", "%minute%", "%legion%"]:
		check(vdf.contains(token), "the vdf has " + token)
	Steamworks.presence("Germania", 1, 3)
	check(not Steamworks.running(), "no Steam is called in a test")


func test_demo_caps_the_run_at_fifteen_minutes(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 31, "demo_seconds": 900.0})
	s.commander.hp = 1.0e9
	s.commander.max_hp = 1.0e9
	while s.time < 899.0:
		s.update(0.5, Vector2.ZERO, false)
		s.pending_levels = 0
	check(not s.over, "a minute before the cap the run goes on")
	for i in 4:
		s.update(0.5, Vector2.ZERO, false)
	check(s.over and s.victory and s.demo_over, "the run ends as a demo victory at the cap")
	var full := Sim.new(b, content, {"seed": 31})
	full.time = 905.0
	full.update(0.5, Vector2.ZERO, false)
	check(not full.over, "the full game has no cap")
	var saved: Dictionary = Profile.data
	Profile.data = Profile.defaults()
	Profile.record_run(s)
	check(not Profile.record_of("germania").won and int(Profile.data.totals.wins) == 0, "a demo ending does not count as a win")
	Profile.data = saved


func test_demo_offers_three_commanders(b: Dictionary) -> void:
	var ready: Array = []
	for id in content.commanders:
		var rule: Dictionary = content.commanders[id].get("unlock", {})
		var province := str(rule.get("province", ""))
		if content.ready("commanders", id) and (province == "" or content.ready("provinces", province)):
			ready.append(id)
	check(Game.commanders(content, b) == ready, "the full game lists every drawn commander whose unlock province is playable")
	check("engineer" in Game.commanders(content, b), "the engineer is offered now that Gaul is drawn")
	var later := Content.load_all(Content.available_art())
	later = _with_undrawn(later)
	later.commanders.engineer.unlock = {"type": "win", "province": "hibernia"}
	check(not "engineer" in Game.commanders(later, b), "a commander won in a province not drawn yet waits for it")
	check(Game.province_allowed("gaul", b), "the full game opens every province")
	check(Game.run_cap(b) == 0.0, "the full game has no cap")
	Game.demo_forced = true
	check(Game.commanders(content, b) == ready.slice(0, 3), "the demo lists the first three drawn commanders")
	check(Game.province_allowed("germania", b) and not Game.province_allowed("gaul", b), "the demo opens Germania only")
	check(Game.run_cap(b) == float(b.demo.seconds) and float(b.demo.seconds) < float(b.chieftain_at), "the demo caps the run at its time limit, before the chieftain")
	var saved: Dictionary = Profile.data
	Profile.data = Profile.defaults()
	for id in Game.commanders(content, b):
		check(Profile.commander_unlocked(id), "the demo's %s is unlocked" % id)
	Profile.data = saved
	Game.demo_forced = false
	Profile.data = Profile.defaults()
	check(not Profile.commander_unlocked("archer_captain"), "the full game still makes the player earn the archer captain")
	Profile.data = saved


func test_winning_as_a_commander_is_earned(b: Dictionary) -> void:
	var saved: Dictionary = Profile.data
	Profile.data = Profile.defaults()
	var s := Sim.new(b, content, {"seed": 32, "commander": "archer_captain"})
	check(not "win_as_archer_captain" in Steamworks.check(s), "not earned before the win")
	s.victory = true
	s.over = true
	check("win_as_archer_captain" in Steamworks.check(s), "earned by winning as that commander")
	Steamworks.queue.clear()
	Profile.data = saved


func test_last_rank_achievements_are_earned_when_the_last_one_is_reached(b: Dictionary) -> void:
	var saved: Dictionary = Profile.data
	for case in [["arms_8", "arms"], ["forge_all", "forged"], ["drills_all", "drills"]]:
		Profile.data = Profile.defaults()
		Steamworks.queue.clear()
		var info: Dictionary = content.achievements.get(case[0], {})
		check(info.get("kind", "") == "maxed" and info.get("group", "") == case[1], "%s counts %s at their last rank" % case)
		var need: int = int(info.get("target", content.get(case[1]).size()))
		check(case[0] == "arms_8" or need == content.get(case[1]).size(), "%s asks for every one of the %s" % case)
		var s := Sim.new(b, content, {"seed": 33})
		var ids: Array = content.get(case[1]).keys()
		for i in need - 1:
			s.ranks[ids[i]] = int(content.get(case[1])[ids[i]].max)
		var last: String = ids[need - 1]
		s.ranks[last] = int(content.get(case[1])[last].max) - 1
		for other in ids.slice(need):
			s.ranks[other] = int(content.get(case[1])[other].max) - 1
		check(not case[0] in Steamworks.check(s), "%s is not earned one rank short" % case[0])
		s.ranks[last] = int(content.get(case[1])[last].max)
		check(case[0] in Steamworks.check(s), "%s is earned when the last one reaches its last rank" % case[0])
		check(Steamworks.queue.any(func(c: Dictionary) -> bool: return c.id == case[0]), "%s slides in as a card" % case[0])
	Steamworks.queue.clear()
	Profile.data = saved


func test_every_achievement_has_its_steam_icons_and_row(_b: Dictionary) -> void:
	var dir := ProjectSettings.globalize_path("res://").path_join("../store/achievements")
	var table := FileAccess.get_file_as_string(dir.path_join("achievements.md"))
	for id in content.achievements:
		check(FileAccess.file_exists(dir.path_join(id + ".jpg")) and FileAccess.file_exists(dir.path_join(id + "_locked.jpg")), "%s has its earned and locked icons" % id)
		check(table.contains("| `%s` | %s | %s |" % [id, content.achievements[id].name, content.achievements[id].text]), "%s has its row in achievements.md" % id)


class FakeSteam:
	extends RefCounted
	var sent: Array = []

	func setAchievement(id: String) -> void:
		sent.append(id)

	func storeStats() -> void:
		pass


func test_achievements_wait_in_the_profile_until_steam_is_there(b: Dictionary) -> void:
	var saved: Dictionary = Profile.data
	Profile.data = Profile.defaults()
	check(Steamworks.unlock("kills_1000"), "earned without Steam")
	check(Profile.data.achievements == ["kills_1000"], "kept in the profile")
	var fake := FakeSteam.new()
	Steamworks.steam = fake
	Steamworks.unlock("legion_25")
	check(fake.sent == ["legion_25"], "sent at once when Steam is there")
	fake.sent.clear()
	Steamworks.sync()
	check(fake.sent.size() == 2 and "kills_1000" in fake.sent and "legion_25" in fake.sent, "sync sends every earned one")
	Steamworks.steam = null
	Steamworks.queue.clear()
	Profile.data = saved


func test_no_card_draws_over_the_choice_or_the_summary(b: Dictionary) -> void:
	Steamworks.card = {"id": "kills_1000", "name": "x", "text": "y"}
	check(Steamworks.card_visible("play") and Steamworks.card_visible("camp"), "a card shows while playing and in the camp")
	check(not Steamworks.card_visible("choose") and not Steamworks.card_visible("over"), "no card over the level-up choice or the summary")
	check(not Steamworks.card_visible("pause") and not Steamworks.card_visible("settings"), "no card over the pause menu or the settings")
	Steamworks.card = {}


func test_only_a_prop_tall_enough_to_hide_the_commander_turns_see_through(_b: Dictionary) -> void:
	var view: GDScript = load("res://scripts/world_view.gd")
	var cam := Vector2(100, 100)
	# Each prop stands just in front of the commander, its picture over his feet.
	var cases := {"rock": Vector2(25, 23), "stone_wall": Vector2(60, 19), "oak": Vector2(70, 87), "obelisk": Vector2(24, 71), "log": Vector2(55, 29)}
	var seen := {}
	for kind in cases:
		var size: Vector2 = cases[kind]
		var foot := cam + Vector2(0, 6)
		seen[kind] = view.hides_commander(kind, kind == "oak", Rect2(foot - Vector2(size.x / 2.0, size.y), size), foot.y, cam)
	check(not seen.rock and not seen.stone_wall, "a rock and a low wall, no taller than the commander, stay solid (%s)" % [seen])
	check(seen.oak and seen.obelisk, "a tree and an obelisk in front of him turn see-through")
	check(not seen.log, "a log lying on the ground stays solid")
	var behind := cam - Vector2(0, 6)
	check(not view.hides_commander("oak", true, Rect2(behind - Vector2(35, 87), Vector2(70, 87)), behind.y, cam), "a tree behind him stays solid")


func test_the_build_panel_lists_every_soldier_arm_and_drill_even_at_none(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 3})
	s.legion.add("ballista")
	s.legion.add("archer")
	s.ranks["pilum"] = 2
	s.ranks["hooked_pila"] = 1
	s.ranks["march"] = 1
	var sections: Array = Hud.build_sections(s)
	var by := {}
	for sec in sections:
		by[sec[0]] = sec[1]
	check(sections.map(func(sec): return sec[0]) == ["soldiers", "arms", "drills"], "soldiers come first, then arms, then drills")
	var soldiers: Array = by.get("soldiers", [])
	check(soldiers.map(func(e): return e[0]) == s.content.recruits.keys(), "every kind of soldier is listed, in order (%s)" % [soldiers.map(func(e): return e[0])])
	for e in soldiers:
		check(e[1] == s.count(e[0]), "the panel counts the %s as the legion does (%d, %d)" % [e[0], e[1], s.count(e[0])])
	var arms: Array = by.get("arms", [])
	check(arms.map(func(e): return e[0]) == s.content.arms.keys() + s.content.forged.keys(), "every arm is listed, the forged ones after")
	check(arms.has(["pilum", 2, 5]) and arms.has(["scorpio", 0, 5]) and arms.has(["hooked_pila", 1, 1]) and arms.has(["greek_fire", 0, 1]), "with its rank, none for one not taken, and its most ranks")
	var drills: Array = by.get("drills", [])
	check(drills.map(func(e): return e[0]) == s.content.drills.keys(), "every drill is listed")
	check(drills.has(["march", 1, 5]) and drills.has(["lorica", 0, 5]), "with its rank and most ranks")


func test_the_level_up_choices_stack_down_the_middle_of_the_screen(b: Dictionary) -> void:
	var before_scale := Ui.scale
	var problems := []
	for scale in [1, 2]:
		Ui.set_text_size(scale, b)
		if scale == 1:
			for n in [3, 4]:
				var rows: Array = Hud.choice_rows(n, false)
				if rows.size() != n:
					problems.append("x1 %d choices give %d rows" % [n, rows.size()])
					continue
				for i in n:
					var r: Rect2 = rows[i]
					if absf(r.get_center().x - Ui.W / 2.0) > 0.5:
						problems.append("x1 %d choices: row %d is not centred on the screen (%s)" % [n, i, r])
					if not Rect2(4, 4, Ui.W - 8, Ui.H - 8).encloses(r):
						problems.append("x1 %d choices: row %d %s is off the screen" % [n, i, r])
					if i > 0 and r.position.y < rows[i - 1].end.y + 3.0:
						problems.append("x1 %d choices: row %d touches the one above" % [n, i])
				var panel := Hud.build_rect()
				if panel.position.y >= rows[0].position.y or panel.end.y <= rows[-1].end.y:
					problems.append("x1 %d choices: the panel %s does not stand taller than the rows, %s to %s" % [n, panel, rows[0].position.y, rows[-1].end.y])
				if panel.end.x + 8.0 > rows[0].position.x:
					problems.append("x1 %d choices: the panel reaches the rows" % n)
				# The key hints go under the rows, above the corners of the screen where the testudo and favour sit.
				if rows[-1].end.y + 29.0 > Ui.H - 4.0:
					problems.append("x1 %d choices: no room left for the key hints under the rows" % n)
		elif Hud.shows_build(false, true):
			problems.append("x2 the panel shows beside the large rows")
		# The panel keeps clear of the level in the top bar and of the testudo and timber in the bottom corner.
		var room := Hud.build_rect()
		var top_bar: float = 16.0 + 8.0 * scale + Ui.leading() - Ui.px
		if room.position.y < top_bar + 4.0 or room.end.y > Ui.H - 44.0:
			problems.append("x%d the panel %s runs into the top bar or the testudo" % [scale, room])
	Ui.set_text_size(before_scale, b)
	for p in problems:
		print("  ", p)
	check(problems.is_empty(), "the choices stack down the middle at both text sizes, three or four of them (%d problems)" % problems.size())
	check(Hud.shows_build(false, false) and not Hud.shows_build(true, false), "the panel shows beside a level-up's rows but not the gods'")


## The screens large text is laid out for: a computer at 16:9, a 2424 by 1080 phone and a 16:9 phone at half size, and a tablet, each with the insets and fingertip the touch screen works out for it.
static func _big_screens() -> Array:
	var out: Array = [{"name": "computer", "view": Vector2(640, 360), "tl": Vector2.ZERO, "br": Vector2.ZERO, "phone": false, "tip": 0.0}]
	for e in [["20:9 phone", Vector2i(1212, 540), Vector2(808, 360), Touch.PHONE_INCHES], ["16:9 phone", Vector2i(1280, 720), Vector2(640, 360), Touch.PHONE_INCHES], ["tablet", Vector2i(1024, 768), Vector2(640, 480), Touch.TABLET_INCHES]]:
		var window: Vector2i = e[1]
		var scale := Vector2(window) / Vector2(e[2])
		var insets := Touch.insets_for(window, Rect2i(Vector2i.ZERO, window), scale)
		out.append({"name": e[0], "view": e[2], "tl": insets[0], "br": insets[1], "phone": true, "tip": Touch.fingertip_for(window.y / float(e[3]), scale.y)})
	return out


static func _big_layout_on(screen: Dictionary, n: int) -> Dictionary:
	return Hud.big_layout(n, screen.view, screen.tl, screen.br, screen.phone, screen.tip)


func test_large_text_choices_are_tall_rows_clear_of_the_bars_and_corners(b: Dictionary) -> void:
	var before_scale := Ui.scale
	var before_view := Ui.view
	Ui.set_text_size(2, b)
	var problems := []
	for screen in _big_screens():
		Ui.fit_view(screen.view)
		var safe := Rect2(screen.tl - Ui.offset, screen.view - screen.tl - screen.br)
		var plates: float = safe.position.y + 16.0 + 8.0 * Ui.scale - Ui.px + Ui.leading()
		for n in [3, 4]:
			var lay := _big_layout_on(screen, n)
			var rows: Array = lay.rows
			var tag := "%s, %d choices" % [screen.name, n]
			if rows.size() != n:
				problems.append("%s: %d rows" % [tag, rows.size()])
				continue
			for i in n:
				var r: Rect2 = rows[i]
				if not safe.encloses(r):
					problems.append("%s: row %d %s leaves the safe area %s" % [tag, i, r, safe])
				if absf(r.get_center().x - safe.get_center().x) > 0.5:
					problems.append("%s: row %d is not centred" % [tag, i])
				if r.position.y < plates + 2.0:
					problems.append("%s: row %d at %s covers the level and legion in the top bar, which end at %s" % [tag, i, r.position.y, plates])
				for c in lay.corners:
					if r.intersects(c):
						problems.append("%s: row %d %s covers a corner %s" % [tag, i, r, c])
				if i > 0 and r.position.y < rows[i - 1].end.y + 3.0:
					problems.append("%s: row %d touches the one above" % [tag, i])
				if screen.phone and r.size.y < screen.tip:
					problems.append("%s: rows are %d tall, under a fingertip of %d" % [tag, r.size.y, screen.tip])
			if float(lay.icon) < 32.0:
				problems.append("%s: icons are only %d px" % [tag, lay.icon])
			if int(lay.lines) < 1:
				problems.append("%s: no room for a description in the rows" % tag)
			if screen.name == "20:9 phone" and (int(lay.lines) < 2 or (n == 3 and float(lay.icon) < 48.0)):
				problems.append("%s: rows hold %d lines and %d px icons" % [tag, lay.lines, lay.icon])
			if screen.phone:
				var bar: Rect2 = lay.buttons
				if bar.size.y < minf(screen.tip, 30.0) or bar.size.x < 80.0:
					problems.append("%s: the buttons %s are too small" % [tag, bar])
				var whole := Rect2(safe.get_center().x - (3.0 * bar.size.x + 16.0) / 2.0, bar.position.y, 3.0 * bar.size.x + 16.0, bar.size.y)
				if not safe.encloses(whole) or whole.position.y < rows[-1].end.y + 4.0:
					problems.append("%s: the buttons %s are off the screen or on the rows" % [tag, whole])
				for c in lay.corners:
					if whole.intersects(c):
						problems.append("%s: the buttons %s cover a corner %s" % [tag, whole, c])
			else:
				# The key hints fit under the rows, above the corners.
				if lay.hint_y - Ui.px < rows[-1].end.y + 4.0:
					problems.append("%s: the key hints at %s run into the rows" % [tag, lay.hint_y])
				for c in lay.corners:
					if c.position.y < lay.hint_y + 2.0:
						problems.append("%s: the key hints at %s run into a corner %s" % [tag, lay.hint_y, c])
	Ui.fit_view(before_view)
	Ui.set_text_size(before_scale, b)
	for p in problems:
		print("  ", p)
	check(problems.is_empty(), "large text shows the choices as tall rows between the top bar and the corners on a computer, phones and a tablet (%d problems)" % problems.size())
	check(Hud.choice_rows(3, true) == Hud.big_layout(3, Ui.view, Touch.inset_tl, Touch.inset_br, Touch.phone, Touch.fingertip).rows, "the large rows are the layout's rows for the screen showing")


func test_every_choice_fits_its_row_in_every_language(b: Dictionary) -> void:
	var before: String = Lang.code
	var before_scale := Ui.scale
	var words := Content.load_all(Content.available_art())
	var s := Sim.new(b, words, {"seed": 3})
	# The most a legion can show: every kind of soldier, every arm and forged arm and every drill; counts are given room for three figures.
	for id in words.recruits:
		s.legion.add(id)
	for kind in ["arms", "forged", "drills"]:
		for id in words.get(kind):
			s.ranks[id] = int(words.get(kind)[id].max)
	var ids: Array = words.recruits.keys() + words.arms.keys() + words.forged.keys() + words.drills.keys()
	var problems := []
	for loc in LANGUAGES:
		Lang.apply(loc, false)
		words.localize()
		for scale in [1, 2]:
			Ui.set_text_size(scale, b)
			var big: bool = scale > 1
			# The pause screen shows the panel at both text sizes, clear of its buttons, and the level-up beside its rows.
			var room := Hud.build_rect()
			if room.end.x >= (Ui.W - PauseScreen.button_width()) / 2.0:
				problems.append("%s x%d the panel reaches the pause buttons" % [loc, scale])
			var placed: Array = []
			for it in Hud.build_items(s, room):
				if not room.grow(-1.0).encloses(it[1]):
					problems.append("%s x%d %s at %s spills out of the panel %s" % [loc, scale, it[2], it[1], room])
				if it[0] != "line":
					if int(it[5]) < (20 if big else 24):
						problems.append("%s x%d %s's icon is only %d px" % [loc, scale, it[2], it[5]])
					for other in placed:
						if other.intersects(it[1]):
							problems.append("%s x%d %s at %s overlaps another piece" % [loc, scale, it[2], it[1]])
					placed.append(it[1])
			var entries: Array = []
			for id in ids:
				var info: Dictionary = words.upgrade(id)
				for tx in [str(info.get("text", "")), str(info.get("more", ""))]:
					if tx != "":
						entries.append([id, str(info.name).to_upper(), Upgrades.level_text(s, id), tx])
			for id in words.gods:
				entries.append([id, str(words.gods[id].name).to_upper(), TranslationServer.translate("God").to_upper(), str(words.gods[id].text)])
			# The supply cart's lines are in the large rows too; the normal rows' are checked with the other labels.
			for id in Horde.CART_REWARDS if big else []:
				var row := Hud.supply_text(id, {"wounded": 199, "share": 100, "commander": 100}, 9999)
				entries.append([id, str(row.name).to_upper(), "", str(row.line)])
			# Large text is checked on every screen it is laid out for; the normal size has one layout.
			var screens: Array = _big_screens() if big else [{"name": "computer"}]
			var before_view := Ui.view
			for screen in screens:
				if big:
					Ui.fit_view(screen.view)
				for n in [3, 4]:
					var r: Rect2 = _big_layout_on(screen, n).rows[0] if big else Hud.choice_rows(n, false)[0]
					var head := Hud.row_text(r, big)
					var lines := Hud.row_lines(r, big)
					# Three rows anywhere and four on the 20:9 phone hold every description at the text size; four on a smaller screen may step down to the small size.
					var strict: bool = not big or n == 3 or screen.name == "20:9 phone"
					for e in entries:
						if Ui.width_at(e[1], Ui.px) + 8.0 + Ui.width_at(e[2], Ui.px) > head.size.x:
							problems.append("%s x%d %s %d rows: %s's name and '%s' do not fit one line" % [loc, scale, screen.name, n, e[0], e[2]])
						var need: int = Ui.lines_of(e[3], head.size.x).size() if strict else Ui.block(e[3], head.size.x, lines).lines
						if need > lines:
							problems.append("%s x%d %s %d rows: %s's text takes %d lines, room for %d" % [loc, scale, screen.name, n, e[0], need, lines])
			Ui.fit_view(before_view)
	Lang.apply(before, false)
	words.localize()
	Ui.set_text_size(before_scale, b)
	for p in problems.slice(0, 12):
		print("  ", p)
	check(problems.is_empty(), "every choice's name, level and text fit its row in every language, at both text sizes, three or four rows (%d problems)" % problems.size())


func test_the_choice_panel_mirrors_the_build_panel(b: Dictionary) -> void:
	var before_scale := Ui.scale
	Ui.set_text_size(1, b)
	var left := Hud.build_rect()
	var right := Hud.choice_panel_rect()
	check(is_equal_approx(right.position.x, Ui.W - left.end.x) and right.position.y == left.position.y and right.size == left.size,
		"the choice panel %s is the build panel %s mirrored across the middle of the screen" % [right, left])
	for n in [3, 4]:
		var rows: Array = Hud.choice_rows(n, false)
		for r in rows:
			check(left.end.x + 8.0 <= r.position.x and r.end.x + 8.0 <= right.position.x, "%d choices: neither panel reaches the row %s" % [n, r])
	var buttons: Dictionary = Hud.choice_panel_buttons()
	check(buttons.keys() == ["reroll", "banish"], "the panel has a reroll and a banish button")
	for id in buttons:
		check(right.grow(-1.0).encloses(buttons[id]), "the %s button sits inside the panel" % id)
	check(is_equal_approx(buttons.banish.end.y, left.end.y - Hud.BUILD_PAD), "the lower button is level with the foot of the build panel, inside its margin")
	check(Hud.shows_choice_panel(false, false) and not Hud.shows_choice_panel(true, false) and not Hud.shows_choice_panel(false, true),
		"the panel shows beside a level-up's rows at the normal text size, but not for the gods or with large text")
	Touch.phone = true
	check(not Hud.shows_choice_panel(false, false), "and not on a phone")
	Touch.phone = false
	Ui.set_text_size(before_scale, b)


func test_every_piece_of_the_choice_panel_fits_it_in_every_language(b: Dictionary) -> void:
	var before: String = Lang.code
	var before_scale := Ui.scale
	Ui.set_text_size(1, b)
	var words := Content.load_all(Content.available_art())
	var ids: Array = words.recruits.keys() + words.arms.keys() + words.forged.keys() + words.drills.keys()
	# A fresh legion shows each choice as new, and one built halfway shows a rank and the next side by side with two-figure counts.
	var fresh := Sim.new(b, words, {"seed": 3})
	var built := Sim.new(b, words, {"seed": 3})
	for id in words.recruits:
		for k in 6:
			built.legion.pick(id)
	for kind in ["arms", "drills"]:
		for id in words.get(kind):
			built.ranks[id] = maxi(1, int(words.get(kind)[id].max) - 1)
	for s in [fresh, built]:
		s.rerolls = 10
		s.banishes = 10
	var room := Hud.choice_panel_rect()
	var buttons: Dictionary = Hud.choice_panel_buttons()
	var problems := []
	for loc in LANGUAGES:
		Lang.apply(loc, false)
		words.localize()
		for id in buttons:
			var label := Hud.choice_button_label(fresh, id)
			if Ui.width_at(label, Ui.px) > buttons[id].size.x - 8.0:
				problems.append("%s the %s button's '%s' does not fit" % [loc, id, label])
		for s in [fresh, built]:
			for id in ids:
				var placed: Array = buttons.values()
				var shown := {}
				for it in Hud.choice_panel_items(s, id, room):
					var r: Rect2 = it[1]
					shown[it[0]] = true
					if not room.grow(-1.0).encloses(r):
						problems.append("%s %s: %s at %s spills out of the panel" % [loc, id, it.slice(2), r])
					if it[0] == "text" and Ui.width_at(it[2], Ui.px) > r.size.x:
						problems.append("%s %s: '%s' is wider than its place" % [loc, id, it[2]])
					if it[0] == "icon" and r.size.x < 32.0:
						problems.append("%s %s: the icon is only %d px" % [loc, id, r.size.x])
					if it[0] != "line":
						for other in placed:
							if other.intersects(r):
								problems.append("%s %s: %s at %s overlaps another piece" % [loc, id, it.slice(2), r])
						placed.append(r)
				for kind in ["icon", "text", "value"]:
					if not shown.has(kind):
						problems.append("%s %s shows no %s" % [loc, id, kind])
	Lang.apply(before, false)
	words.localize()
	Ui.set_text_size(before_scale, b)
	for p in problems.slice(0, 12):
		print("  ", p)
	check(problems.is_empty(), "every piece of the choice panel fits inside it for every choice in every language (%d problems)" % problems.size())


func test_the_choice_panel_reads_the_games_own_numbers(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 3})
	s.ranks["pilum"] = 2
	var lines: Array = Upgrades.stat_lines(s, "pilum")
	var p: Dictionary = b.pilum
	check(lines[0] == ["Damage", str(int(p.damage) + int(p.damage_per_level)), str(int(p.damage) + 2 * int(p.damage_per_level))],
		"the pilum's damage goes from its rank to the next (%s)" % [lines[0]])
	check(lines.has(["Pierce", "2", "2"]) and lines.has(["Thrown", "5", "7"]), "with its pierce and throwers (%s)" % [lines])
	var fresh: Array = Upgrades.stat_lines(s, "scorpio")
	check(fresh[0] == ["Damage", "", str(int(b.scorpio.damage))], "an arm not yet taken shows its first rank alone (%s)" % [fresh[0]])
	s.ranks["march"] = 1
	check(Upgrades.stat_lines(s, "march") == [["Speed", "+8%", "+16%"]], "a drill shows its whole bonus now and next (%s)" % [Upgrades.stat_lines(s, "march")])
	var legion: Array = Upgrades.stat_lines(s, "legionary")
	var n := s.count("legionary")
	check(legion[0] == ["In the legion", str(n), str(n + 2)], "a recruit counts the legion's men of his kind now and after (%s)" % [legion[0]])
	check(legion.has(["Damage", "12", ""]) and legion.has(["Health", str(roundi(s.max_hp_of("legionary"))), ""]), "with a soldier's damage and health (%s)" % [legion])
	check(Upgrades.stat_lines(s, "hooked_pila") == [["Pin", "", "1.6 s"], ["Pierce", "", "+1"]], "a forged arm shows what it adds (%s)" % [Upgrades.stat_lines(s, "hooked_pila")])
	for kind in ["recruits", "arms", "forged", "drills"]:
		for id in content.get(kind):
			check(not Upgrades.stat_lines(s, id).is_empty(), "%s has numbers to show" % id)


func test_the_forge_line_names_the_partner_and_its_rank(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 3})
	s.ranks["scorpio"] = 3
	s.ranks["onager"] = 1
	check(Upgrades.forge_lines(s, "onager") == ["With Scorpio (3/5) forges Siege train"], "the onager names the scorpio's rank (%s)" % [Upgrades.forge_lines(s, "onager")])
	check(Upgrades.forge_lines(s, "scorpio") == ["With Onager (1/5) forges Siege train"], "and the scorpio the onager's (%s)" % [Upgrades.forge_lines(s, "scorpio")])
	check(Upgrades.forge_lines(s, "caltrops") == ["With Pilum volley (0/5) forges Hooked pila"], "a partner not yet taken is at 0 (%s)" % [Upgrades.forge_lines(s, "caltrops")])
	check(Upgrades.forge_lines(s, "siege_train") == ["Made from Scorpio and Onager"], "a forged arm says what it is made from (%s)" % [Upgrades.forge_lines(s, "siege_train")])
	check(Upgrades.forge_lines(s, "march").is_empty() and Upgrades.forge_lines(s, "legionary").is_empty(), "drills and recruits forge nothing")


func test_the_choice_panels_buttons_reroll_and_banish(b: Dictionary) -> void:
	var full := _full_content()
	var s := _arms_sim(b, 34, {}, full)
	s.rerolls = 1
	s.banishes = 1
	var buttons: Dictionary = Hud.choice_panel_buttons()
	var first := Upgrades.offers(s)
	var press := Hud.choice_button_at(s, buttons.reroll.get_center())
	check(press == "reroll", "a click on the reroll button presses it (%s)" % press)
	var after: Dictionary = Upgrades.press(s, press, first, 0)
	check(s.rerolls == 0 and after.choices.size() == 3 and not after.choices.has(first[0]), "and rerolls the choices (%s to %s)" % [first, after.choices])
	check(Hud.choice_button_at(s, buttons.reroll.get_center()) == "", "with none left the button does nothing")
	var gone: String = after.choices[1]
	press = Hud.choice_button_at(s, buttons.banish.get_center())
	var banished: Dictionary = Upgrades.press(s, press, after.choices, 1)
	check(press == "banish" and s.banishes == 0 and s.banished == [gone] and not banished.choices.has(gone), "a click on the banish button banishes the choice picked out")
	check(Hud.choice_button_at(s, buttons.banish.get_center()) == "", "and with none left it does nothing")
	check(Hud.choice_button_at(s, Hud.choice_panel_rect().position + Vector2(10, 10)) == "", "a click elsewhere on the panel presses nothing")


const LANGUAGES := ["en", "fr", "de", "es", "it", "pt_BR", "pl", "tr", "ru", "uk", "ja", "ko", "zh_CN", "zh_TW"]


func _sheet() -> Dictionary:
	var f := FileAccess.open("res://translations/strings.csv", FileAccess.READ)
	var header := f.get_csv_line()
	var rows := {}
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() > 1:
			rows[line[0]] = line
	return {"header": header, "rows": rows}


func _percent_codes(s: String) -> Array:
	var out := []
	for m in RegEx.create_from_string("%[-0-9.]*[sdifxXcv%]").search_all(s):
		# A literal percent sign takes no value, so a language may put it before the number, as Turkish does.
		if m.get_string() != "%%":
			out.append(m.get_string())
	return out


func test_every_string_has_all_languages(_b: Dictionary) -> void:
	var sheet := _sheet()
	check(Array(sheet.header).slice(1) == LANGUAGES, "the sheet has the 14 languages")
	var placeholder := RegEx.create_from_string("%[-0-9.]*[sdifxXcv%]|\\{[A-Za-z0-9_]*\\}| {2,}")
	var empty := 0
	var changed := 0
	var reordered := 0
	for key in sheet.rows:
		var row: PackedStringArray = sheet.rows[key]
		for i in range(1, row.size()):
			if row[i].strip_edges() == "":
				empty += 1
				print("  empty ", LANGUAGES[i - 1], ": ", key)
			elif placeholder.search_all(row[i]).size() != placeholder.search_all(row[1]).size():
				changed += 1
				print("  placeholders differ ", LANGUAGES[i - 1], ": ", key)
			elif _percent_codes(row[i]) != _percent_codes(row[1]):
				reordered += 1
				print("  placeholders reordered ", LANGUAGES[i - 1], ": ", key)
	check(empty == 0, "no cell of the sheet is empty")
	check(changed == 0, "every translation keeps its placeholders")
	# The % operator fills its codes in order, so a language that needs another order uses named {fields} instead.
	check(reordered == 0, "every translation keeps its % codes in the English order")
	for kind in Content.KINDS:
		for id in content.get(kind):
			for field in Content.WORDS:
				if content.get(kind)[id].has(field):
					check(sheet.rows.has(Content.key_of(kind, id, field)), "%s.%s.%s is in the sheet" % [kind, id, field])


func test_every_tr_call_is_in_the_sheet(_b: Dictionary) -> void:
	var rows: Dictionary = _sheet().rows
	var call := RegEx.create_from_string("\\b(?:tr|TranslationServer\\.translate)\\(\\s*\"((?:[^\"\\\\]|\\\\.)*)\"")
	var dirs := ["res://scripts/", "res://scripts/screens/"]
	var missing := 0
	for dir in dirs:
		for file in DirAccess.get_files_at(dir):
			if file.get_extension() != "gd":
				continue
			for m in call.search_all(FileAccess.get_file_as_string(dir + file)):
				var key: String = m.get_string(1).c_unescape()
				if not rows.has(key):
					missing += 1
					print("  not in the sheet: ", key)
	check(missing == 0, "every tr() string is in the sheet")


func test_every_language_shows_its_own_words(_b: Dictionary) -> void:
	var before := TranslationServer.get_locale()
	for loc in LANGUAGES:
		TranslationServer.set_locale(loc)
		check(TranslationServer.get_locale() == loc, "%s is loaded" % loc)
		if loc != "en":
			check(TranslationServer.translate("Settings") != "Settings", "%s translates Settings" % loc)
			check(TranslationServer.translate(Content.key_of("recruits", "legionary", "name")) != "Legionaries", "%s has the legionaries' name" % loc)
	TranslationServer.set_locale(before)


func test_each_language_has_a_font_that_draws_it(_b: Dictionary) -> void:
	var samples := {"pl": "ąćęłńśźż", "tr": "ğışİ", "ru": "Русский", "uk": "їієґ", "ja": "日本語", "ko": "한국어", "zh_CN": "简体中文", "zh_TW": "繁體中文", "de": "ÄÖÜß", "fr": "éèêç"}
	for loc in samples:
		var f: Font = Lang.font(loc)
		check(f.has_char(samples[loc].unicode_at(0)) or f.get_string_size(samples[loc]).x > 0.0, "%s has a font" % loc)
		for ch in samples[loc]:
			check(f.has_char(ch.unicode_at(0)), "the %s font draws %s" % [loc, ch])


# Every label the screens draw, at the width its caller gives it, in every language and at both text sizes. A label that
# does not fit at the text size steps down to the smallest size of the language; one that does not fit even then would
# be cut with "..", and this test fails for it, so a long translation is fixed by layout and never by cutting.
func test_no_label_is_cut_in_any_language(b: Dictionary) -> void:
	var before: String = Lang.code
	var before_scale := Ui.scale
	var cuts := []
	var words := Content.load_all(Content.available_art())
	var sim := Sim.new(b, words, {"seed": 1})
	for loc in LANGUAGES:
		Lang.apply(loc, false)
		words.localize()
		for scale in [1, 2]:
			Ui.set_text_size(scale, b)
			_cuts_in(loc, scale, words, sim, cuts)
	Lang.apply(before, false)
	Ui.set_text_size(before_scale, b)
	for c in cuts:
		print("  cut: ", c)
	check(cuts.is_empty(), "no label is cut in any language at either text size (%d cut)" % cuts.size())


func _fit(cuts: Array, loc: String, scale: int, what: String, s: String, width: float) -> void:
	if not Ui.fits(s, width):
		cuts.append("%s x%d %s: '%s' needs %d of %d" % [loc, scale, what, s, Ui.width_at(s, Ui.small_px()), width])


func _lines(cuts: Array, loc: String, scale: int, what: String, s: String, width: float, most: int) -> void:
	var n: int = Ui.block(s, width, most).lines
	if n > most:
		cuts.append("%s x%d %s: '%s' takes %d lines, room for %d" % [loc, scale, what, s, n, most])


func _longest(list: Array) -> String:
	var best := ""
	for s in list:
		if Ui.width_at(s, Ui.px) > Ui.width_at(best, Ui.px):
			best = s
	return best


func _cuts_in(loc: String, scale: int, c: Content, sim: Sim, cuts: Array) -> void:
	var big := scale > 1
	var all_names: Array = []
	for kind in ["recruits", "arms", "forged", "drills"]:
		all_names.append_array(c.get(kind).values().map(func(e): return str(e.name)))
	var provinces: Array = c.provinces.values().map(func(e): return str(e.name))
	var commanders: Array = c.commanders.values().map(func(e): return str(e.name))
	var tr_ := func(s: String) -> String: return TranslationServer.translate(s)
	# The key hints at the foot of a screen, which lose their first parts when they do not fit.
	for kind in ["volume", "keys", "press", "title"]:
		_fit(cuts, loc, scale, "key hint " + kind, Controls.hint(kind), 624.0)
	# The run's line at the top left stays clear of the chieftain's name and health bar in the middle.
	for pid in c.provinces:
		for d in ["Easy", "Medium", "Hard"]:
			_fit(cuts, loc, scale, "run line", ("%s, %s" % [c.provinces[pid].name, tr_.call(d)]).to_upper(), Hud.RUN_LINE_ROOM)
	_title_cuts(cuts, loc, scale, "how to play", sim.b)
	Controls.pad_in_use = true
	_title_cuts(cuts, loc, scale, "how to play on a gamepad", sim.b)
	Controls.pad_in_use = false
	_fit(cuts, loc, scale, "give-up prompt", tr_.call("Give up the run? %s again to confirm") % "Q", 624.0)
	for kind in ["pick", "buy", "look", "summary", "level", "gods"]:
		_fit(cuts, loc, scale, "key hint " + kind, Controls.hint(kind), 624.0)
	_fit(cuts, loc, scale, "level-up extras", Controls.hint("reroll", 9) + "     " + Controls.hint("banish", 9), 624.0)
	_fit(cuts, loc, scale, "demo hint", tr_.call("The full game continues past %d minutes") % 15, 624.0)
	_fit(cuts, loc, scale, "endless hint", tr_.call("Held out %s after the chieftain") % "99:59", 624.0)
	# Pause and title buttons.
	var pause_w := (260.0 if big else 180.0) - 12.0
	for s in ["Resume", "Settings", "Give up the run"]:
		_fit(cuts, loc, scale, "pause button", tr_.call(s).to_upper(), pause_w)
	for s in ["March", "Settings", "Wishlist on Steam"]:
		_fit(cuts, loc, scale, "title button", tr_.call(s).to_upper(), 188.0)
	_fit(cuts, loc, scale, "march button", tr_.call("March").to_upper(), 148.0)
	# Camp boards and the line over the march button.
	var board_w := (296.0 if big else 140.0) - 12.0
	for s in CampScreen.BOARDS:
		_fit(cuts, loc, scale, "board name", tr_.call(s[1]).to_upper(), board_w)
	for s in [tr_.call("%d denarii") % 99999, tr_.call("%d found") % 999] + provinces + commanders:
		_fit(cuts, loc, scale, "board line", s, board_w)
	var levels: Array = [tr_.call("Easy"), tr_.call("Medium"), tr_.call("Hard")]
	var modes: Array = [_longest([tr_.call("Easy"), tr_.call("Hard")]), tr_.call("Endless"), tr_.call("Decimatio")]
	_fit(cuts, loc, scale, "camp line", "%s, %s, %s" % [_longest(provinces), _longest(commanders), " + ".join(modes)], 624.0)
	# Summary buttons, stat labels, mode list, bars and chart captions.
	for s in ["Camp", "Title"]:
		_fit(cuts, loc, scale, "summary button", tr_.call(s).to_upper(), SummaryScreen.button_width() - 12.0)
	_fit(cuts, loc, scale, "wishlist button", tr_.call("Wishlist").to_upper(), SummaryScreen.wide_button_width() - 12.0)
	var labels: Array = ["Time", "Kills", "Level", "Legion", "Denarii", "Banked"].map(func(s): return tr_.call(s))
	var left_w := SummaryScreen.stats_width(labels)
	for s in labels:
		_fit(cuts, loc, scale, "stat label", s, left_w - Ui.width_at("99999", Ui.px) - 8.0)
	var sources: Array = all_names + [str(c.base_commander.name)]
	var bar_w := SummaryScreen.names_width(sources)
	for s in sources:
		_fit(cuts, loc, scale, "damage source", s, bar_w)
	for s in ["Victory", "The commander has fallen", "The demo ends here"]:
		_fit(cuts, loc, scale, "summary mode list", " + ".join(modes), 608.0 - 36.0 - Ui.width_at(tr_.call(s).to_upper(), Ui.px))
	_fit(cuts, loc, scale, "damage heading", tr_.call("Damage by source").to_upper(), 356.0)
	_fit(cuts, loc, scale, "none recorded", tr_.call("None recorded"), 356.0)
	_fit(cuts, loc, scale, "chart heading", tr_.call("Legion size over time").to_upper(), 584.0 - Ui.width_at(tr_.call("Largest %d") % 999, Ui.px) - 12.0)
	_fit(cuts, loc, scale, "chart empty", tr_.call("The run was too short to chart"), 584.0)
	# Settings.
	var pct := Ui.width_at("100%", Ui.px)
	for s in ["Master volume", "Music volume", "Effects volume"]:
		_fit(cuts, loc, scale, "volume name", tr_.call(s), 440.0 - 6.0 - 12.0 - pct - 80.0 - 6.0)
	for s in ["Full screen", "Screen shake", "Damage numbers", "Blood"]:
		_fit(cuts, loc, scale, "toggle name", tr_.call(s), 440.0 - 12.0 - maxf(Ui.width_at(tr_.call("On"), Ui.px), Ui.width_at(tr_.call("Off"), Ui.px)) - 6.0)
	_fit(cuts, loc, scale, "text size", tr_.call("Text size"), 440.0 - 12.0 - maxf(Ui.width_at(tr_.call("Large"), Ui.px), Ui.width_at(tr_.call("Normal"), Ui.px)) - 6.0)
	_fit(cuts, loc, scale, "language label", tr_.call("Language"), 440.0 - 12.0 - 120.0)
	_fit(cuts, loc, scale, "controls button", tr_.call("Keys and buttons"), 428.0)
	# A phone's own labels: how to play by touch, the give-up prompt, the volumes beside wider bars, the choice and buy buttons.
	var was_phone := Touch.phone
	Touch.phone = true
	_title_cuts(cuts, loc, scale, "how to play on a phone", sim.b)
	Touch.phone = was_phone
	_fit(cuts, loc, scale, "give-up prompt on a phone", tr_.call("Give up the run? Tap again to confirm"), 624.0)
	for s in ["Master volume", "Music volume", "Effects volume"]:
		_fit(cuts, loc, scale, "volume name on a phone", tr_.call(s), 440.0 - 6.0 - 12.0 - pct - SettingsScreen.PHONE_BAR_W - 6.0)
	for s in [tr_.call("take it"), tr_.call("call"), tr_.call("not now"), tr_.call("reroll") + " (9)", tr_.call("banish") + " (9)"]:
		_fit(cuts, loc, scale, "choice button on a phone", s.to_upper(), Hud.touch_button_width(3) - 12.0)
	_fit(cuts, loc, scale, "buy button on a phone", tr_.call("buy a rank").to_upper(), Ui.label_room(Rect2(0, 0, 224, 30), "10000", false))
	_fit(cuts, loc, scale, "back button", tr_.call("Back").to_upper(), 428.0)
	var m := SettingsScreen.controls_metrics(608.0)
	for a in Controls.ACTIONS:
		_fit(cuts, loc, scale, "action name", tr_.call(a[1]), m.name_w - 6.0)
	var key_names: Array = [tr_.call("Press...")]
	for k in Controls.KEYS.values():
		for code in k:
			key_names.append(Controls.key_name(code))
	for button in Controls.PAD_NAMES:
		key_names.append(Controls.pad_name(button))
	for s in key_names:
		_fit(cuts, loc, scale, "key button", s, m.bw - 12.0)
	for s in ["Use defaults", "Back"]:
		_fit(cuts, loc, scale, "controls footer button", tr_.call(s).to_upper(), 288.0 - 12.0)
	# Quartermaster rows and the description box.
	var right_w := maxf(Ui.width_at(tr_.call("Max").to_upper(), Ui.px), Ui.width_at("1600", Ui.px)) + 6.0
	for id in c.quartermaster:
		var info: Dictionary = c.quartermaster[id]
		var label := "%d/%d %s" % [3, int(info.ranks), info.name] if big else "%s  %d/%d" % [info.name, 3, int(info.ranks)]
		_fit(cuts, loc, scale, "quartermaster row", label, 280.0 - 23.0 - right_w - 6.0)
		_lines(cuts, loc, scale, "quartermaster text", info.text, 568.0, 2)
	# Map and commanders.
	var map_text := 568.0
	for id in c.provinces:
		_lines(cuts, loc, scale, "province text", c.provinces[id].text, map_text, 2)
	for id in c.commanders:
		_lines(cuts, loc, scale, "commander text", c.commanders[id].text, map_text, 2)
		var tag: String = (tr_.call("Locked: %s") % Profile.unlock_text(c.commanders[id], c)).to_upper()
		_fit(cuts, loc, scale, "commander tag", tag, 434.0)
	_fit(cuts, loc, scale, "chosen tag", tr_.call("Chosen").to_upper(), 434.0)
	var panel_w := MapScreen.panel_rect().size.x - 16.0
	var mode_w := panel_w if big else (panel_w - 4.0) / 2.0
	for s in [tr_.call("Endless"), tr_.call("Decimatio")]:
		_fit(cuts, loc, scale, "mode button", s, mode_w - Ui.px - 14.0)
	var level_w := MapScreen.level_widths(panel_w)
	for k in levels.size():
		_fit(cuts, loc, scale, "difficulty button", levels[k], level_w[k] - 4.0)
		if Ui.width_at(levels[k], Ui.px) > level_w[k] - 4.0:
			cuts.append("%s x%d difficulty button '%s' is drawn smaller than the text size" % [loc, scale, levels[k]])
	var columns := MapScreen.table_columns(panel_w)
	for k in MapScreen.TIMES.size():
		if MapScreen.full_table():
			_fit(cuts, loc, scale, "record column", tr_.call(MapScreen.TIMES[k][1]), columns[k + 1])
			_fit(cuts, loc, scale, "record time", "99:59", columns[k + 1])
		else:
			_fit(cuts, loc, scale, "record line", tr_.call(MapScreen.TIMES[k][1]), MapScreen.time_label_room(panel_w))
	if MapScreen.full_table():
		if columns.reduce(func(sum: float, n: float) -> float: return sum + n, 0.0) > panel_w + 0.5:
			cuts.append("%s x%d record table needs %d of %d" % [loc, scale, columns.reduce(func(sum: float, n: float) -> float: return sum + n, 0.0), panel_w])
		for s in levels:
			_fit(cuts, loc, scale, "record row", s, columns[0] - 4.0)
	_lines(cuts, loc, scale, "map note", tr_.call("Win here to open Endless and Decimatio"), panel_w, 2)
	_fit(cuts, loc, scale, "marching here", tr_.call("Marching here").to_upper(), 300.0)
	# The line under each province's name on the map, in its plate.
	var plate_w := 200.0 if not big else 260.0
	for s in [tr_.call("Win in %s to open") % _longest(provinces), tr_.call("March here"), tr_.call("Marching here"), tr_.call("Won"), tr_.call("Hard won"), tr_.call("Not ready yet")]:
		_fit(cuts, loc, scale, "map plate", s, plate_w)
	# The level-up and gods' rows, whose names and levels share one line, and the god's name written across the screen at three times the size.
	_fit(cuts, loc, scale, "god heading", tr_.call("The gods hear you").to_upper(), 624.0)
	_fit(cuts, loc, scale, "favour hint", Controls.hint("pray").to_upper(), 624.0 * 0.45)
	var screens: Array = _big_screens() if big else [{"name": "computer"}]
	var before_view := Ui.view
	_fit(cuts, loc, scale, "supplies heading", tr_.call("Supplies").to_upper(), 300.0 if big else 624.0)
	for screen in screens:
		if big:
			Ui.fit_view(screen.view)
		for n in [3, 4]:
			var r: Rect2 = _big_layout_on(screen, n).rows[0] if big else Hud.choice_rows(n, false)[0]
			var head := Hud.row_text(r, big)
			var what := "%s, %d rows" % [screen.name, n]
			for id in c.recruits.keys() + c.arms.keys() + c.forged.keys() + c.drills.keys():
				_fit(cuts, loc, scale, "row name and level (%s)" % what, str(c.upgrade(id).name).to_upper() + "  " + Upgrades.level_text(sim, id), head.size.x)
			for id in c.gods:
				_fit(cuts, loc, scale, "god row (%s)" % what, str(c.gods[id].name).to_upper() + "  " + tr_.call("God").to_upper(), head.size.x)
			# The supply cart's rows with the longest numbers they can show.
			for id in Horde.CART_REWARDS:
				var row := Hud.supply_text(id, {"wounded": 199, "share": 100, "commander": 100}, 9999)
				_fit(cuts, loc, scale, "supply row name (%s)" % what, str(row.name).to_upper(), head.size.x)
				_lines(cuts, loc, scale, "supply row line (%s)" % what, row.line, head.size.x, Hud.row_lines(r, big))
		if big and screen.phone:
			for t in [tr_.call("take it"), tr_.call("call"), tr_.call("not now"), tr_.call("reroll") + " (9)", tr_.call("banish") + " (9)"]:
				_fit(cuts, loc, scale, "choice button on a %s" % screen.name, t.to_upper(), _big_layout_on(screen, 3).buttons.size.x - 12.0)
	Ui.fit_view(before_view)
	for id in c.gods:
		if Ui.width_at(str(c.gods[id].name).to_upper(), Ui.px * 3) > 624.0:
			cuts.append("%s x%d god banner %s does not fit" % [loc, scale, id])
	# Achievement cards.
	var room := 240.0 if big else 150.0
	_fit(cuts, loc, scale, "card heading", tr_.call("Achievement").to_upper(), room)
	for id in c.achievements:
		_lines(cuts, loc, scale, "achievement name", str(c.achievements[id].name).to_upper(), room, 2)


func test_selection_stays_on_a_choice_after_a_shorter_list(b: Dictionary) -> void:
	check(Upgrades.keep_in(2, ["a", "b"]) == 1, "a selection past the end moves to the last choice")
	check(Upgrades.keep_in(0, ["a", "b"]) == 0, "a selection inside the list stays")
	check(Upgrades.keep_in(3, []) == 0, "an empty list gives 0")


func test_confirm_waits_after_a_choice_or_the_summary_opens(b: Dictionary) -> void:
	var delay := float(b.confirm_delay)
	check(delay > 0.0, "the delay is set in balance.json")
	for st in ["choose", "over"]:
		check(not Game.confirm_allowed(st, 10.0, 10.0 + delay * 0.5, b), "%s ignores a press right after it opens" % st)
		check(Game.confirm_allowed(st, 10.0, 10.0 + delay + 0.01, b), "%s takes a press after the delay" % st)
	check(Game.confirm_allowed("camp", 10.0, 10.0, b), "other screens take confirm at once")


func test_hints_name_the_players_own_keys(_b: Dictionary) -> void:
	var saved: Dictionary = Profile.settings
	Profile.settings = {"bindings": {}}
	check(Controls.hint("level") == "W / S  choose     Space  take it", "the level-up hint names the keys that move up and down its rows (%s)" % Controls.hint("level"))
	Controls.rebind(Profile.settings.bindings, "up", "keys", 0, KEY_J)
	Controls.rebind(Profile.settings.bindings, "confirm", "keys", 0, KEY_E)
	check(Controls.hint("level") == "J / S  choose     E  take it", "the level-up hint shows the rebound keys")
	check(Controls.hint("summary").begins_with("E  choose"), "the summary hint shows the rebound confirm key (%s)" % Controls.hint("summary"))
	check(Controls.hint("pick").begins_with("J A S D  move"), "the move hint shows the rebound march keys")
	Controls.install({})
	Profile.settings = saved


func test_hints_are_built_from_single_translated_words(_b: Dictionary) -> void:
	var saved: Dictionary = Profile.settings
	Profile.settings = {"bindings": {}}
	Controls.install({})
	var before := TranslationServer.get_locale()
	for loc in LANGUAGES:
		TranslationServer.set_locale(loc)
		for w in Controls.HINT_WORDS:
			var said := TranslationServer.translate(w)
			check(not said.contains("%"), "%s: the hint word '%s' carries no placeholder (%s)" % [loc, w, said])
		# Every part starts with its keys, so the translation of a word can never move a key into another part.
		var parts := Controls.hint("pick").split("     ")
		check(parts.size() == 3, "%s: the pick hint has its three parts" % loc)
		if parts.size() == 3:
			check(parts[0].begins_with(Controls.march_keys() + "  "), "%s: the march keys lead the first part" % loc)
			check(parts[1] == Controls.key_of("confirm") + "  " + TranslationServer.translate("choose"), "%s: confirm names choose" % loc)
			check(parts[2] == Controls.key_of("back") + "  " + TranslationServer.translate("back"), "%s: back names back" % loc)
		var gods := Controls.hint("gods").split("     ")
		check(gods.size() == 3 and gods[2].begins_with(Controls.key_of("back")), "%s: the gods hint ends with the back key" % loc)
	TranslationServer.set_locale("de")
	check(Controls.key_name(KEY_SPACE) == "Leertaste", "key names are translated (%s)" % Controls.key_name(KEY_SPACE))
	check(Controls.key_name(KEY_W) == "W", "a letter key keeps its letter")
	TranslationServer.set_locale(before)
	Profile.settings = saved


func test_reroll_and_banish_can_be_rebound(_b: Dictionary) -> void:
	var saved: Dictionary = Profile.settings
	Profile.settings = {"bindings": {}}
	var names: Array = Controls.ACTIONS.map(func(a: Array) -> String: return a[0])
	check(names.has("reroll") and names.has("banish"), "the key page lists reroll and banish")
	Controls.rebind(Profile.settings.bindings, "reroll", "keys", 0, KEY_T)
	Controls.rebind(Profile.settings.bindings, "banish", "pads", 0, JOY_BUTTON_LEFT_SHOULDER)
	var has_t := false
	for e in InputMap.action_get_events("reroll"):
		has_t = has_t or (e is InputEventKey and e.physical_keycode == KEY_T)
	check(has_t, "the rebound reroll key is in the input map")
	check(Controls.hint("reroll", 2) == "T  reroll (2)", "the reroll hint names the new key (%s)" % Controls.hint("reroll", 2))
	Controls.pad_in_use = true
	check(Controls.hint("banish", 1) == "LB  banish (1)", "with a gamepad in hand the banish hint names the new button (%s)" % Controls.hint("banish", 1))
	Controls.pad_in_use = false
	Controls.install({})
	Profile.settings = saved


func test_japanese_lines_never_start_with_a_full_stop(_b: Dictionary) -> void:
	var before: String = Lang.code
	Lang.apply("ja", false)
	var s := "前列の方が受けるダメージは少なくなります。"
	var cut := false
	for w in range(20, 200):
		for line in Ui.lines_of(s, float(w)):
			cut = cut or Ui.NO_LINE_START.contains(str(line).left(1))
	check(not cut, "no line at any width starts with closing punctuation")
	Lang.apply(before, false)


func test_a_word_too_long_for_a_line_is_broken(b: Dictionary) -> void:
	var before: String = Lang.code
	Lang.apply("de", false)
	var lines := Ui.lines_of("Die Legion der BÜRGERSOLDATENVERSAMMLUNG kam", 60.0, 8)
	var fits := true
	for line in lines:
		fits = fits and Ui.width_at(line, 8) <= 60.0
	check(fits, "every line fits the width (%s)" % [lines])
	check("".join(lines).replace("-", "").replace(" ", "") == "DieLegionderBÜRGERSOLDATENVERSAMMLUNGkam", "no letter is lost")
	check(lines.any(func(l: String) -> bool: return l.ends_with("-")), "the broken word carries a hyphen")
	Lang.apply(before, false)


## The title's controls: every label in its cell, the goal in its two lines, and the box above the buttons.
func _title_cuts(cuts: Array, loc: String, scale: int, what: String, b: Dictionary) -> void:
	var g := TitleScreen.grid(b)
	for cell in g.cells:
		_lines(cuts, loc, scale, what, cell.label, cell.room, cell.lines)
	_lines(cuts, loc, scale, what + " goal", Game.goal_text(b), g.goal_width, 2)
	if g.box.end.y > TitleScreen.box_limit():
		cuts.append("%s x%d %s: the box ends at %d, under the buttons' room" % [loc, scale, what, g.box.end.y])


func test_title_controls_follow_the_bindings_and_the_gamepad(b: Dictionary) -> void:
	var saved: Dictionary = Profile.settings
	var pad := Controls.pad_in_use
	Profile.settings = {"bindings": {}}
	Controls.install({})
	Controls.pad_in_use = false
	var caps := func(id: String) -> Array: return TitleScreen.controls().filter(func(e: Dictionary) -> bool: return e.id == id)[0].caps
	check(caps.call("march") == ["W", "A", "S", "D"], "the march shows the four keys as a cluster (%s)" % [caps.call("march")])
	check(caps.call("testudo") == [Controls.key_name(KEY_SPACE)] and caps.call("pause") == [Controls.key_name(KEY_ESCAPE)], "the testudo and pause show Space and Escape")
	check(caps.call("build") == ["E"] and caps.call("wall") == ["F"] and caps.call("bridge") == ["C"] and caps.call("pray") == ["G"], "the timber works and the gods show their keys")
	check(caps.call("fight").is_empty(), "the soldiers' fighting needs no key")
	Controls.rebind(Profile.settings.bindings, "testudo", "keys", 0, KEY_T)
	Controls.rebind(Profile.settings.bindings, "up", "keys", 0, KEY_I)
	check(caps.call("testudo") == ["T"] and caps.call("march")[0] == "I", "a rebound key shows on the title (%s, %s)" % [caps.call("testudo"), caps.call("march")])
	Controls.pad_in_use = true
	check(caps.call("testudo") == ["A"] and caps.call("pray") == ["Y"] and caps.call("pause") == ["Start"], "a gamepad shows its buttons")
	check(caps.call("march") == [Controls.pad_name(JOY_BUTTON_LEFT_STICK)], "and the stick for the march")
	Touch.phone = true
	check(TitleScreen.controls().all(func(e: Dictionary) -> bool: return e.caps.is_empty()), "a phone shows its buttons' pictures, no keys")
	check(TitleScreen.controls().size() == 8 and TitleScreen.controls().all(func(e: Dictionary) -> bool: return str(e.label) != ""), "every control has a label")
	Touch.phone = false
	Controls.pad_in_use = pad
	Profile.settings = saved
	Controls.install(saved.get("bindings", {}))


func test_title_how_to_play_is_a_short_grid(b: Dictionary) -> void:
	var before := Ui.scale
	Ui.set_text_size(1, b)
	var g := TitleScreen.grid(b)
	check(g.box.size.y < 90.0, "the how-to-play box is shorter than the nine lines it was (%d)" % g.box.size.y)
	for scale in [1, 2]:
		Ui.set_text_size(scale, b)
		for phone in [false, true]:
			Touch.phone = phone
			g = TitleScreen.grid(b)
			check(g.box.end.y <= TitleScreen.box_limit(), "the box leaves room for the buttons (x%d, phone %s, ends %d)" % [scale, phone, g.box.end.y])
			for i in g.cells.size():
				var r: Rect2 = g.cells[i].rect
				check(g.box.encloses(r), "cell %d is inside the box (x%d, phone %s)" % [i, scale, phone])
				for j in i:
					check(not r.intersects(g.cells[j].rect), "cells %d and %d do not overlap (x%d, phone %s)" % [j, i, scale, phone])
	Touch.phone = false
	Ui.set_text_size(before, b)


func test_title_goal_comes_from_the_balance(b: Dictionary) -> void:
	check(str(int(float(b.chieftain_at) / 60.0)) in Game.goal_text(b) and "chieftain" in Game.goal_text(b), "the full game names the minutes to the chieftain")
	Game.demo_forced = true
	check(str(int(float(b.demo.seconds) / 60.0)) in Game.goal_text(b) and not "chieftain" in Game.goal_text(b), "the demo names its minutes and no chieftain")
	Game.demo_forced = false


class FakeMain:
	extends Node
	var state := "pause"
	var finished := false
	var sim: Sim
	var ui := Ui.new()

	func _finish_run() -> void:
		finished = true


func test_giving_up_asks_twice(b: Dictionary) -> void:
	var m := FakeMain.new()
	m.sim = Sim.new(b, content, {"seed": 5})
	var pause := PauseScreen.new(m)
	pause.activate("giveup")
	check(not m.finished and not m.sim.over, "the first press only asks")
	check(m.ui.focus == "giveup", "and leaves the focus on giving up, so the confirm key finishes it")
	pause.activate("giveup")
	check(m.finished and m.sim.over, "the second press gives up")
	m.free()


func test_look_flags_never_touch_the_saved_profile(_b: Dictionary) -> void:
	check(Profile.blocks_saving(PackedStringArray(["--text-size=2"])), "--text-size is not saved")
	check(Profile.blocks_saving(PackedStringArray(["--autoplay"])), "--autoplay is not saved")
	check(not Profile.blocks_saving(PackedStringArray([])), "an ordinary start saves")


func test_settings_opened_from_pause_stay_in_the_run(_b: Dictionary) -> void:
	check(Game.in_run("settings", "pause"), "settings from the pause is in the run")
	check(not Game.in_run("settings", "title"), "settings from the title is not")
	check(Game.in_run("choose", "title") and not Game.in_run("camp", "pause"), "choose is in the run, the camp is not")


func test_losing_focus_pauses_only_while_playing(_b: Dictionary) -> void:
	check(Game.pauses_on_focus_loss("play", false), "focus lost in play pauses")
	check(not Game.pauses_on_focus_loss("play", true), "not in an autoplay")
	check(not Game.pauses_on_focus_loss("camp", false) and not Game.pauses_on_focus_loss("choose", false), "other states are left alone")


func test_coins_on_the_field_are_capped_without_losing_value(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 61})
	var total := 0
	for i in 1000:
		s.time = i * 0.1
		s.drop_coin(Vector2(i, 0), 1 + i % 3)
		total += 1 + i % 3
		check(s.c_pos.size() <= int(b.max_coins), "coin count stays at the cap")
		if s.c_pos.size() > int(b.max_coins):
			return
	var held := 0
	for v in s.c_val:
		held += v
	check(held == total, "the merged coins hold the same value (%d of %d)" % [held, total])
	check(s.c_pos.size() == s.c_born.size() and s.c_pos.size() == s.c_pull.size(), "the coin arrays stay in step")


func test_credits_carry_the_licence_texts_in_full(_b: Dictionary) -> void:
	var credits: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/credits.json"))
	var text := "
".join(load("res://tools/write_credits.gd").licence_sections(credits))
	for path in ["res://addons/godotsteam/license.md", "res://assets/fonts/OFL.txt", "res://assets/fonts/fusion-pixel-OFL.txt",
			"res://assets/fonts/fusion-pixel-LICENSES/misaki/misaki.txt", "res://assets/fonts/fusion-pixel-LICENSES/galmuri/LICENSE.txt",
			"res://assets/fonts/fusion-pixel-LICENSES/ark-pixel/OFL.txt"]:
		check(text.contains(FileAccess.get_file_as_string(path).strip_edges()), "the credits hold %s in full" % path)


func test_a_clearing_keeps_its_ground_free_of_props(b: Dictionary) -> void:
	var t := Terrain.new(77, b.forest)
	t.clearings.append([Vector2(900, 300), 200.0])
	var inside := 0
	for pr in t.props_in(Rect2(Vector2(600, 0), Vector2(600, 600))):
		if pr[1].distance_to(Vector2(900, 300)) < 200.0:
			inside += 1
	check(inside == 0, "nothing grows in a clearing set before the field is built (%d)" % inside)
	var built := Terrain.new(78, b.forest)
	built.refresh(Vector2(1000, 0))
	var near := 0
	for pr in built.props_in(Rect2(Vector2(700, -300), Vector2(600, 600))):
		if pr[1].distance_to(Vector2(1000, 0)) < 180.0:
			near += 1
	built.add_clearing(Vector2(1000, 0), 180.0, [["stake", Vector2(1000, 0), 5.0]])
	var left: Array = []
	for pr in built.props_in(Rect2(Vector2(700, -300), Vector2(600, 600))):
		if pr[1].distance_to(Vector2(1000, 0)) < 180.0:
			left.append(pr[0])
	check(near > 0 and left == ["stake"], "a clearing made later takes out what grew there and keeps its own pieces (%d before, %s after)" % [near, left])
	built.refresh(Vector2(1000, 0))
	var blocked := false
	for sv in built.solid:
		blocked = blocked or (Vector2(sv.x, sv.y) == Vector2(1000, 0))
	check(blocked, "and the solid pieces block at once")


func test_a_run_places_two_or_three_objectives_in_clearings(b: Dictionary) -> void:
	var cfg: Dictionary = b.objectives
	var sizes := {}
	for seed_value in range(1, 21):
		var s := Sim.new(b, Content.with_all_art(), {"seed": seed_value})
		var list: Array = s.objectives.list
		sizes[list.size()] = true
		var kinds := {}
		for o in list:
			kinds[o.kind] = true
			var d: float = o.pos.length()
			check(d >= float(cfg.near) - 1.0 and d <= float(cfg.far) + 1.0, "seed %d: the %s lies %.0f from the start" % [seed_value, o.kind, d])
			var stray := 0
			for pr in s.terrain.props_in(Rect2(o.pos - Vector2.ONE * 200.0, Vector2.ONE * 400.0)):
				if pr[1].distance_to(o.pos) < float(cfg.clearing) and not s.terrain.extras.has(pr):
					stray += 1
			check(stray == 0, "seed %d: the %s stands in a clearing (%d strays)" % [seed_value, o.kind, stray])
		check(kinds.size() == list.size(), "seed %d: no kind twice" % seed_value)
		for i in list.size():
			for j in range(i + 1, list.size()):
				var gap := absf(list[i].pos.angle_to(list[j].pos))
				check(gap > deg_to_rad(60.0), "seed %d: objectives lie in different directions (%.0f degrees)" % [seed_value, rad_to_deg(gap)])
	check(sizes.has(2) and sizes.has(3) and sizes.size() == 2, "runs have two or three objectives (%s)" % [sizes.keys()])


func _objective_sim(b: Dictionary, seed_value: int) -> Sim:
	var s := _quiet_sim(b, seed_value, Content.with_all_art())
	s.objectives.list.clear()
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	return s


func _kinds_alive(s: Sim) -> Array:
	var out: Array = []
	for k in s.horde.e_kind:
		out.append(s.horde.kind_ids[k])
	return out


func _empty_horde(s: Sim) -> void:
	while not s.horde.e_pos.is_empty():
		s.horde.remove_at(0)


func test_the_camp_pours_out_defenders_and_gives_back_the_eagle(b: Dictionary) -> void:
	var cfg: Dictionary = b.objectives.camp
	var s := _objective_sim(b, 150)
	var camp: Dictionary = s.objectives.add(s, "camp", Vector2(600, 0))
	_step_dt(s, 0.2)
	check(s.horde.e_pos.is_empty(), "nobody comes out while the legion is far off")
	s.commander.pos = Vector2(600.0 - float(cfg.wake) + 10.0, 0)
	_step_dt(s, 0.1)
	var kinds := _kinds_alive(s)
	check(kinds.size() > 5 and kinds.has("war_band_leader"), "a war band and its leader pour out when the legion comes near (%d)" % kinds.size())
	var n := kinds.size()
	_step_dt(s, 1.0)
	check(s.horde.e_pos.size() <= n, "and only once")
	var choices := s.free_choices
	s.soldiers[0].pos = camp.pos
	s._rebuild_grids()
	s.objectives.update(0.01, s)
	check(camp.done and s.free_choices == choices + 1, "a soldier touching the eagle takes it back for a free choice")
	check(camp.burnt_at >= 0.0, "and the camp is set alight")
	check(s.objectives.purse == int(b.objectives.purse.camp), "and a purse of %d denarii (%d)" % [int(b.objectives.purse.camp), s.objectives.purse])
	s.objectives.update(0.01, s)
	check(s.free_choices == choices + 1, "the eagle is taken only once")


func test_the_camp_brings_its_own_provinces_leader(b: Dictionary) -> void:
	var cfg: Dictionary = b.objectives.camp
	for province in ["gaul", "dacia", "parthia", "britannia", "hispania", "aegyptus", "sarmatia"]:
		var s := Sim.new(b, Content.with_all_art(), {"seed": 151, "province": province})
		s.terrain.clear()
		s.objectives.list.clear()
		s.horde.next_surge = 1e9
		s.horde.next_band = 1e9
		s.horde.next_boss = 1e9
		s.commander.hp = 1e9
		s.objectives.add(s, "camp", Vector2(600, 0))
		s.commander.pos = Vector2(600.0 - float(cfg.wake) + 10.0, 0)
		_step_dt(s, 0.1)
		var leader := str(cfg.leader[province])
		var kinds := _kinds_alive(s)
		check(leader in content.provinces[province].elites and kinds.has(leader) and not kinds.has("war_band_leader"), "a camp in %s brings out its own %s" % [province, leader])


func test_the_stranded_column_holds_and_joins_the_legion(b: Dictionary) -> void:
	var cfg: Dictionary = b.objectives.column
	var s := _objective_sim(b, 151)
	var col: Dictionary = s.objectives.add(s, "column", Vector2(500, 0))
	check(col.guards.size() == int(cfg.guards), "%d legionaries guard the cart" % int(cfg.guards))
	var g: Dictionary = col.guards[0]
	var foe := s.horde.spawn("barbarian_club", g.pos + Vector2(12, 0))
	var id := s.horde.e_id[foe]
	var hp0: float = s.horde.e_hp[foe]
	s.commander.pos = col.pos - Vector2(float(cfg.wake) + 60.0, 0)
	_step_dt(s, 1.0)
	var j := s.horde.e_id.find(id)
	check(j < 0 or s.horde.e_hp[j] < hp0, "the guards strike a barbarian beside them")
	check(g.hp < g.max_hp, "and he strikes back")
	check(j < 0 or s.horde.e_pos[j].distance_to(g.pos) < 30.0, "he is held at the guard and does not walk on to the legion")
	_empty_horde(s)
	s.commander.pos = col.pos - Vector2(float(cfg.wake) - 10.0, 0)
	_step_dt(s, 0.1)
	check(s.horde.e_pos.size() > 5, "a war band falls on the column when the legion comes near")
	_empty_horde(s)
	s.commander.hp = 10.0
	g.hp = 0.0
	var size := s.soldiers.size()
	s.commander.pos = col.pos + Vector2(float(cfg.reach) - 5.0, 0)
	_step_dt(s, 0.1)
	check(col.done and s.soldiers.size() == size + int(cfg.guards) - 1, "reaching the cart adds the survivors to the legion (%d)" % (s.soldiers.size() - size))
	check(s.commander.hp == s.commander.max_hp, "and heals the legion")
	var full := _objective_sim(b, 152)
	while full.soldiers.size() < int(b.legion_cap) - 1:
		full.add_soldier("legionary")
	var c2: Dictionary = full.objectives.add(full, "column", Vector2(300, 0))
	full.commander.pos = c2.pos
	_step_dt(full, 0.1)
	check(full.soldiers.size() == int(b.legion_cap), "a full legion takes only the men it has room for (%d)" % full.soldiers.size())


func test_the_grove_is_ringed_with_its_provinces_own_props(b: Dictionary) -> void:
	for province in ["germania", "dacia", "parthia", "britannia", "hispania", "aegyptus", "sarmatia"]:
		var s := Sim.new(b, Content.with_all_art(), {"seed": 152, "province": province})
		s.objectives.list.clear()
		var at := Vector2(900, 0)
		s.objectives.add(s, "grove", at)
		var kinds := {}
		for pr in s.terrain.extras:
			if pr[1].distance_to(at) < float(b.objectives.clearing):
				kinds[pr[0]] = true
		var want: String = {"germania": "oak", "dacia": "pine", "parthia": "palm", "britannia": "stone_circle", "hispania": "olive", "aegyptus": "date_palm", "sarmatia": "birch"}[province]
		check(kinds.has(want) and (want == "oak" or not kinds.has("oak")), "the grove in %s is ringed with %s (%s)" % [province, want, kinds.keys()])


func test_the_legion_walks_through_the_groves_standing_stones(b: Dictionary) -> void:
	var s := _britannia_sim(b, 157)
	s.objectives.list.clear()
	var circle: Dictionary = s.objectives.add(s, "grove", Vector2(0, 400))
	var pictures: Array = s.terrain.extras.filter(func(pr: Array) -> bool: return pr[0] == "stone_circle" and pr[1].distance_to(circle.pos) < 200.0)
	var stones: Array = s.terrain.extras.filter(func(pr: Array) -> bool: return pr[0] == "" and pr[2] > 0.0 and pr[1].distance_to(circle.pos) < 200.0)
	check(not pictures.is_empty() and stones.is_empty(), "the grove's standing stones are scenery with nothing solid under them (%d blockers)" % stones.size())
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	var inside := false
	for k in 12 * 60:
		s.update(1.0 / 60.0, (circle.pos - s.commander.pos).normalized() if s.commander.pos.distance_to(circle.pos) > 8.0 else Vector2.ZERO, false)
		inside = inside or s.commander.pos.distance_to(circle.pos) < float(b.objectives.grove.inside)
	check(inside, "the commander marches into the middle of the circle")


func test_nobody_stands_inside_a_cluster_of_standing_stones_on_the_moor(b: Dictionary) -> void:
	var cfg: Dictionary = b.moors.britannia
	var stones: Array = cfg.circle_stones
	var mid := Vector2.ZERO
	for off in stones:
		mid += Vector2(float(off[0]), float(off[1]))
	mid /= stones.size()
	var s := _britannia_sim(b, 158)
	s.objectives.list.clear()
	var anchor := Vector2(0, -200)
	var group: Array = [["stone_circle", anchor, 0.0]]
	for off in stones:
		group.append(["", anchor + Vector2(float(off[0]), float(off[1])), float(cfg.stone_radius)])
	s.terrain.add_clearing(anchor, 1.0, group)
	s.terrain.refresh(s.commander.pos)
	while s.soldiers.size() < 20:
		s.legion.add(["cavalry", "legionary"][s.soldiers.size() % 2])
	s.legion.place_all(s.facing_angle)
	var centre: Vector2 = anchor + mid
	var inside := 0
	for k in 10 * 60:
		var to: Vector2 = centre - s.commander.pos
		s.update(1.0 / 60.0, to.normalized() if to.length() > 4.0 else Vector2.ZERO, false)
		for u in s.units:
			if u.pos.distance_to(centre) < 20.0:
				inside += 1
	check(inside == 0, "marching at a cluster of standing stones on the moor, no man ever stands inside it (%d times)" % inside)


func test_the_desert_grove_is_a_well_that_does_not_burn(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 156, "province": "parthia"})
	s.objectives.list.clear()
	var well: Dictionary = s.objectives.add(s, "grove", Vector2(500, 0))
	check(well.centre == "well", "in Parthia the grove's heart is a well (%s)" % well.centre)
	var home := Sim.new(b, Content.with_all_art(), {"seed": 156})
	check(home.objectives.add(home, "grove", Vector2(500, 0)).centre == "altar", "elsewhere it is the altar")
	var hud_name := Hud.objective_name("grove", s)
	check(hud_name == "Sacred well", "its badge calls it the sacred well (%s)" % hud_name)
	s.commander.pos = well.pos
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	_step_dt(s, float(b.objectives.grove.hold) + 0.2)
	check(well.done, "holding it takes it")
	check(not s.effects.any(func(e: Dictionary) -> bool: return e.kind == "boom" and e.pos == well.pos), "with no burst of fire")
	check(not Hud.notice_line("grove", s).contains("burn") and not Hud.notice_line("grove_tip", s).contains("burn"), "and nothing it says speaks of burning")


func test_burning_the_grove_thins_the_stream(b: Dictionary) -> void:
	var cfg: Dictionary = b.objectives.grove
	var s := _objective_sim(b, 153)
	var grove: Dictionary = s.objectives.add(s, "grove", Vector2(500, 0))
	var oaks := 0
	var solid := 0
	for pr in s.terrain.extras:
		if pr[1].distance_to(grove.pos) < float(cfg.ring) + 30.0 and pr[2] > 0.0:
			solid += 1
		if pr[0] == "oak" and absf(pr[1].distance_to(grove.pos) - float(cfg.ring)) < 1.0:
			oaks += 1
	var slots := int(TAU * float(cfg.ring) / float(cfg.oak_step))
	check(oaks > slots / 2 and oaks < slots, "oaks ring the altar with gaps (%d of %d)" % [oaks, slots])
	check(solid == 0, "nothing in the grove's ring blocks the legion (%d solid)" % solid)
	var ring_oak: Vector2 = grove.oaks[0]
	s.terrain.refresh(ring_oak)
	check(s.terrain.push_out(ring_oak, Sim.UNIT_RADIUS) == ring_oak, "a soldier standing on a ring oak is not pushed away")
	s.commander.pos = grove.pos + Vector2(10, 0)
	_step_dt(s, float(cfg.hold) * 0.5)
	check(not grove.done and grove.hold > 0.0, "half the time in the grove is not enough")
	check(s.horde.e_pos.size() >= 5, "war bands come to defend it (%d)" % s.horde.e_pos.size())
	_empty_horde(s)
	var choices := s.free_choices
	_step_dt(s, float(cfg.hold) * 0.5 + 0.2)
	check(grove.done and s.free_choices == choices + 1, "holding the grove burns it for a free choice")
	check(s.objectives.purse == int(b.objectives.purse.grove), "and adds its denarii")
	check(is_equal_approx(s.objectives.spawn_mult(s.time), float(cfg.calm_mult)), "the stream is thinned")
	check(is_equal_approx(s.objectives.spawn_mult(s.time + float(cfg.calm_seconds) + 1.0), 1.0), "for %d seconds" % int(cfg.calm_seconds))
	s.b.spawn_per_second_start = 2.0
	s.horde.spawn_acc = 0.0
	s.horde._spawn(0.25, s)
	var want := (2.0 + float(s.b.spawn_per_second_growth) * s.time) * 0.25 * float(cfg.calm_mult) * s.horde.level_mult("spawn_mult")
	check(is_equal_approx(s.horde.spawn_acc, want), "the horde's stream reads the thinning (%.3f of %.3f)" % [s.horde.spawn_acc, want])


func test_the_grove_says_what_it_gives_when_it_comes_into_view(b: Dictionary) -> void:
	var cfg: Dictionary = b.objectives.grove
	check(float(cfg.tip_seconds) >= 10.0, "the hint stays long enough to read (%.0f s)" % float(cfg.tip_seconds))
	var s := _objective_sim(b, 155)
	var grove: Dictionary = s.objectives.add(s, "grove", Vector2(900, 0))
	s.objectives.notice = {}
	s.commander.pos = grove.pos + Vector2(float(cfg.tip_within) + 200.0, 0)
	s.objectives.update(0.1, s)
	check(s.objectives.notice.is_empty(), "no hint while the grove is far off")
	s.commander.pos = grove.pos + Vector2(float(cfg.tip_within) - 10.0, 0)
	s.objectives.update(0.1, s)
	check(s.objectives.notice.get("kind", "") == "grove_tip", "a hint once the grove is in view (%s)" % [s.objectives.notice])
	s.objectives.notice = {}
	s.objectives.update(0.1, s)
	check(s.objectives.notice.is_empty(), "the hint is shown only once")


func test_leaving_the_grove_loses_the_hold(b: Dictionary) -> void:
	var cfg: Dictionary = b.objectives.grove
	var s := _objective_sim(b, 154)
	var grove: Dictionary = s.objectives.add(s, "grove", Vector2(500, 0))
	s.commander.pos = grove.pos
	_step_dt(s, float(cfg.hold) * 0.8)
	s.commander.pos = grove.pos + Vector2(400, 0)
	_step_dt(s, float(cfg.hold))
	s.commander.pos = grove.pos
	_step_dt(s, float(cfg.hold) * 0.5)
	check(not grove.done, "time spent in the grove drains away when the legion leaves")


func test_objectives_raise_the_denarii_banked(b: Dictionary) -> void:
	var p := _fresh_profile()
	var s := Sim.new(b, Content.with_all_art(), {"seed": 155})
	s.denarii = 40
	s.objectives.purse = 150
	s.over = true
	p.record_run(s)
	check(p.data.denarii == 190, "the purse is banked with the denarii carried (%d)" % p.data.denarii)
	p.free()
	_cleanup_profile_files()


func test_the_fort_appears_with_the_chieftain_and_holding_it_wins(b: Dictionary) -> void:
	var cfg: Dictionary = b.fort
	var s := _mode_sim(b, {"seed": 156})
	s.objectives.list.clear()
	s.commander.pos = Vector2(300, -200)
	s.time = float(b.chieftain_at) - 0.5
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.objectives.fort.is_empty(), "no fort before %d seconds" % int(b.chieftain_at))
	s.time = float(b.chieftain_at) - 0.01
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var fort: Dictionary = s.objectives.fort
	check(not fort.is_empty(), "the fort appears")
	var d: float = fort.pos.distance_to(s.commander.pos)
	check(d >= float(cfg.near) - 1.0 and d <= float(cfg.far) + 1.0, "%.0f from the commander" % d)
	var stray := 0
	for pr in s.terrain.props_in(Rect2(fort.pos - Vector2.ONE * 250.0, Vector2.ONE * 500.0)):
		if pr[1].distance_to(fort.centre) < float(cfg.clearing) and not s.terrain.extras.has(pr):
			stray += 1
	check(stray == 0, "in open ground (%d strays)" % stray)
	var ci := s.chieftain_index()
	check(ci >= 0, "the chieftain comes out at the same moment")
	var cp: Vector2 = s.horde.e_pos[ci]
	check(cp.distance_to(fort.pos) < d and (cp - s.commander.pos).dot(fort.pos - s.commander.pos) > 0.0, "between the legion and the fort")
	s.horde.e_pos[ci] = s.commander.pos + Vector2(0, 2000)
	s.horde.e_stun[ci] = 1e9
	s.commander.max_hp = 1e9
	s.commander.hp = 1e9
	s.commander.pos = fort.centre
	_step_dt(s, float(cfg.hold) + 0.2)
	check(not s.victory, "holding the fort while the chieftain lives does not win")
	s.hit(s.chieftain_index(), 1e9)
	_step_dt(s, float(cfg.hold) + float(b.triumph.most_seconds) + 0.5)
	check(s.over and s.victory, "once he is dead, holding the fort wins the run")
	var e := _mode_sim(b, {"seed": 157, "endless": true})
	e.objectives.list.clear()
	e.time = float(b.chieftain_at) - 0.01
	e.update(1.0 / 60.0, Vector2.ZERO, false)
	e.commander.max_hp = 1e9
	e.commander.hp = 1e9
	e.commander.pos = e.objectives.fort.centre
	_kill_chief_and_hold(e, b)
	check(not e.over and e.victory and e.endless_since >= 0.0, "in an endless run holding the fort after his death wins and the march goes on")
	var since := e.endless_since
	_step_dt(e, float(cfg.hold) + 0.2)
	check(e.endless_since == since and not e.over, "and staying in the fort keeps the endless clock")


## Lays the given props on otherwise bare ground round the start and rebuilds the solid grid.
func _field(s: Sim, props: Array) -> void:
	s.terrain.empty = false
	for cx in range(-8, 9):
		for cy in range(-8, 9):
			s.terrain._chunks[Vector2i(cx, cy)] = []
	for pr in props:
		s.terrain._chunks[Vector2i(floori(pr[1].x / Terrain.CHUNK), floori(pr[1].y / Terrain.CHUNK))].append(pr)
	s.terrain._anchor = Vector2i(1 << 30, 0)
	s.terrain.refresh(s.commander.pos)


func _solid_at(s: Sim, p: Vector2) -> bool:
	for sv in s.terrain.solid:
		if Vector2(sv.x, sv.y) == p:
			return true
	return false


func _kinds_at(s: Sim, p: Vector2) -> Array:
	var out: Array = []
	for pr in s.terrain.props_in(Rect2(p - Vector2.ONE, Vector2.ONE * 2.0)):
		if pr[1] == p:
			out.append(pr[0])
	return out


func test_pressing_a_tree_fells_it_for_timber(b: Dictionary) -> void:
	var s := _quiet_sim(b, 300)
	s.legion.soldiers.clear()
	var at := Vector2(40, 0)
	_field(s, [["oak", at, Terrain.SOLID.oak]])
	var secs := float(b.felling.seconds)
	_step_dt(s, secs * 0.7, Vector2.RIGHT)
	check(_solid_at(s, at) and s.timber == 0, "the oak still stands before its time")
	check(s.terrain.chop_of(at) > 0.0, "but the chopping has begun")
	_step_dt(s, secs * 0.5, Vector2.RIGHT)
	check(not _solid_at(s, at), "pressed long enough, the oak falls")
	check(_kinds_at(s, at) == ["stump"], "and leaves a stump (%s)" % [_kinds_at(s, at)])
	check(s.timber == 1, "the run gains a log of timber (%d)" % s.timber)
	_step_dt(s, 1.0, Vector2.RIGHT)
	check(s.commander.pos.x > at.x, "the commander walks on over the stump")


func test_rocks_and_logs_do_not_fall(b: Dictionary) -> void:
	for kind in ["rock", "log"]:
		var s := _quiet_sim(b, 301)
		s.legion.soldiers.clear()
		var at := Vector2(40, 0)
		_field(s, [[kind, at, Terrain.SOLID[kind]]])
		_step_dt(s, float(b.felling.seconds) * 2.0, Vector2.RIGHT)
		check(_solid_at(s, at) and s.timber == 0, "a %s stays however long it is pushed" % kind)


func test_several_soldiers_fell_a_tree_faster(b: Dictionary) -> void:
	var secs := float(b.felling.seconds)
	var felled := []
	for pushers in [1, 3]:
		var s := _quiet_sim(b, 302)
		var at := Vector2(40, 0)
		_field(s, [["fir", at, Terrain.SOLID.fir]])
		for f in int(secs * 0.45 * 60.0):
			for k in pushers:
				s.terrain.push_out(at + Vector2.from_angle(PI + (k - 1) * 0.6) * 12.0, Sim.UNIT_RADIUS, 1.0 / 60.0)
		felled.append(s.terrain.fell_ready())
	check(felled == [0, 1], "three men fell in under half the time what one man cannot (%s)" % [felled])


func test_a_felled_tree_stays_felled_when_its_ground_is_built_again(b: Dictionary) -> void:
	var t := Terrain.new(9, b.forest)
	var tree := Vector2.INF
	for pr in t.props_in(Rect2(-1200, -1200, 2400, 2400)):
		if pr[0] == "oak" or pr[0] == "fir":
			tree = pr[1]
			break
	check(tree != Vector2.INF, "a tree grows near the start")
	t.fell(tree)
	t._chunks.clear()
	t._buckets.clear()
	var kinds: Array = []
	for pr in t.props_in(Rect2(tree - Vector2.ONE, Vector2.ONE * 2.0)):
		if pr[1] == tree:
			kinds.append(pr[0])
	check(not kinds.is_empty() and kinds.all(func(k: String) -> bool: return k == "stump"), "only its stump is there (%s)" % [kinds])


func test_the_runs_own_pieces_are_not_felled(b: Dictionary) -> void:
	var s := _quiet_sim(b, 303)
	s.legion.soldiers.clear()
	_field(s, [])
	var at := Vector2(40, 0)
	s.terrain.add_clearing(Vector2(40, 0), 30.0, [["oak", at, Terrain.SOLID.oak]])
	s.terrain.refresh(s.commander.pos)
	_step_dt(s, float(b.felling.seconds) * 2.0, Vector2.RIGHT)
	check(_solid_at(s, at) and s.timber == 0, "a grove's oak is not cut down")


func test_a_palisade_costs_timber_and_stands_ahead_of_the_front(b: Dictionary) -> void:
	var s := _quiet_sim(b, 304)
	_field(s, [])
	for i in 10:
		s.add_soldier("legionary")
	s.legion.place_all(s.facing_angle)
	var cfg: Dictionary = b.palisade
	s.timber = int(cfg.cost) - 1
	s.events.clear()
	check(not s.build_palisade(), "too little timber builds nothing")
	check(s.terrain.posts.is_empty() and s.timber == int(cfg.cost) - 1, "and spends nothing")
	check(s.events.any(func(e: Dictionary) -> bool: return e.kind == "back"), "the refusal is heard")
	check(s.palisade_refused_at == s.time, "and a notice shows")
	s.timber = int(cfg.cost) + 1
	check(s.build_palisade(), "with enough timber the palisade goes up")
	check(s.timber == 1, "it spends its cost")
	check(s.terrain.posts.size() == int(cfg.stakes), "%d stakes are driven (%d)" % [int(cfg.stakes), s.terrain.posts.size()])
	var dir := Vector2.from_angle(s.facing_angle)
	var front := 0.0
	for u in s.units_in_formation():
		front = maxf(front, (u.pos - s.commander.pos).dot(dir))
	var ahead := true
	var clear := true
	var across := PackedFloat32Array()
	for post in s.terrain.posts:
		var off: Vector2 = post[1] - s.commander.pos
		ahead = ahead and off.dot(dir) >= front + float(cfg.ahead) - float(cfg.bow) - 0.5
		across.append(off.dot(dir.orthogonal()))
		for u in [s.commander] + s.soldiers:
			clear = clear and u.pos.distance_to(post[1]) >= float(cfg.radius) + Sim.UNIT_RADIUS
	check(ahead, "every stake stands beyond the front rank")
	check(clear, "no stake stands on a man")
	across.sort()
	check(across[across.size() - 1] - across[0] >= float(cfg.gap) * (int(cfg.stakes) - 1) * 0.9, "the line runs across the legion's facing")
	var post_at: Vector2 = s.terrain.posts[3][1]
	check(s.terrain.push_out(post_at + Vector2(1, 0), 6.0) != post_at + Vector2(1, 0), "the stakes are solid")
	check(_solid_at(s, post_at), "and in the grid the horde reads")


func test_a_palisade_skips_a_place_where_a_man_stands(b: Dictionary) -> void:
	var s := _quiet_sim(b, 305)
	_field(s, [])
	s.timber = int(b.palisade.cost)
	var planned: Array = s.palisade_points()
	var rider: Dictionary = s.soldiers[0]
	rider.sortie = 1
	rider.pos = planned[3]
	s.build_palisade()
	check(s.terrain.posts.size() == int(b.palisade.stakes) - 1, "the stake on the man is left out (%d)" % s.terrain.posts.size())


func test_a_palisade_rots_away(b: Dictionary) -> void:
	var s := _quiet_sim(b, 306)
	_field(s, [])
	s.timber = int(b.palisade.cost)
	s.build_palisade()
	var post_at: Vector2 = s.terrain.posts[0][1]
	_step_dt(s, float(b.palisade.seconds) - 1.0)
	check(not s.terrain.posts.is_empty() and _solid_at(s, post_at), "the stakes still stand before they rot")
	_step_dt(s, 1.5)
	check(s.terrain.posts.is_empty() and not _solid_at(s, post_at), "after %d seconds they are gone" % int(b.palisade.seconds))


func test_a_wall_costs_timber_and_closes_the_way_behind_the_rear(b: Dictionary) -> void:
	var s := _quiet_sim(b, 307)
	_field(s, [])
	for i in 10:
		s.add_soldier("legionary")
	s.legion.place_all(s.facing_angle)
	var cfg: Dictionary = b.wall
	s.timber = int(cfg.cost) - 1
	check(not s.build_wall(), "too little timber builds no wall")
	check(s.terrain.posts.is_empty() and s.wall_refused_at == s.time, "and a notice shows")
	s.timber = int(cfg.cost)
	check(s.build_wall(), "with enough timber the wall goes up")
	check(s.timber == 0 and s.terrain.posts.size() == int(cfg.stakes), "it spends its cost on %d stakes (%d)" % [int(cfg.stakes), s.terrain.posts.size()])
	var dir := Vector2.from_angle(s.facing_angle)
	var rear := 0.0
	for u in s.units_in_formation():
		rear = minf(rear, (u.pos - s.commander.pos).dot(dir))
	var behind := true
	var across: Array = []
	for post in s.terrain.posts:
		var off: Vector2 = post[1] - s.commander.pos
		behind = behind and off.dot(dir) <= rear - float(cfg.behind) + float(cfg.bow) + 0.5
		across.append(post[1])
	check(behind, "every stake stands behind the rear rank")
	across.sort_custom(func(p: Vector2, q: Vector2) -> bool: return (p - s.commander.pos).dot(dir.orthogonal()) < (q - s.commander.pos).dot(dir.orthogonal()))
	var tight := true
	for k in across.size() - 1:
		tight = tight and across[k].distance_to(across[k + 1]) < (float(cfg.radius) + 6.0) * 2.0
	check(tight, "no barbarian fits between two stakes")
	check(_solid_at(s, across[0]), "the wall is solid")


func test_a_wall_goes_behind_the_army_not_behind_a_straggler(b: Dictionary) -> void:
	var s := _quiet_sim(b, 309)
	_field(s, [])
	for i in 10:
		s.add_soldier("legionary")
	s.legion.place_all(s.facing_angle)
	var dir := Vector2.from_angle(s.facing_angle)
	var rear := 0.0
	for u in s.units_in_formation():
		rear = minf(rear, (u.pos - s.commander.pos).dot(dir))
	s.soldiers[0].pos = s.commander.pos - dir * 400.0
	var cfg: Dictionary = b.wall
	var deepest := INF
	for p in s.wall_points():
		deepest = minf(deepest, (p - s.commander.pos).dot(dir))
	check(deepest >= rear - float(cfg.behind) - 0.5, "the wall stands behind the main army's rear (%.0f px back, rear %.0f)" % [deepest, rear])


func test_the_dacian_king_never_wipes_out_a_packed_legion_at_once(b: Dictionary) -> void:
	for attack in ["rockfall", "leap"]:
		var s := _fort_sim(b, 1670)
		s.province = "dacia"
		s.commander.hp = 1e9
		s.commander.max_hp = 1e9
		while s.soldiers.size() < 40:
			s.legion.add(["legionary", "archer", "cavalry"][s.soldiers.size() % 3])
		s.commander.pos = s.objectives.fort.centre
		s.legion.place_all(s.facing_angle)
		for k in 6 * 60:
			s.objectives.fort.hold = 0.0
			s.update(1.0 / 60.0, Vector2.ZERO, false)
		var before := s.soldiers.size()
		var h := s.horde
		var i := h.spawn("dacian_king", s.commander.pos + Vector2(0, 60))
		h.chieftain_id = h.e_id[i]
		h.chief_fury = true
		h.e_stun[i] = 1e9
		match attack:
			"rockfall":
				h.rockfall(i, s)
			"leap":
				h.start_leap(i, s)
		for k in 3 * 60:
			s.objectives.fort.hold = 0.0
			s.update(1.0 / 60.0, Vector2.ZERO, false)
		var killed := before - s.soldiers.size()
		check(killed <= before / 4, "his %s on a legion packed in the fort kills at most a quarter of it (%d of %d)" % [attack, killed, before])


func test_a_charging_boss_is_stopped_by_a_wall(b: Dictionary) -> void:
	for kind in ["gaul_king", "falx_band", "lusitanian_raider", "camel_captain"]:
		var s := _gaul_sim(b, 1660, {"gaul_king": "gaul", "falx_band": "dacia", "lusitanian_raider": "hispania", "camel_captain": "aegyptus"}[kind])
		s.horde.cleave_cd = 1e9
		s.horde.summon_cd = 1e9
		s.horde.siege_cd = 1e9
		for t in ["sweep_cd", "rockfall_cd", "leap_cd", "salvo_cd"]:
			s.horde.set(t, 1e9)
		s.commander.pos = Vector2.ZERO
		s.legion.place_all(s.facing_angle)
		s._rebuild_grids()
		var wall_x := -s.legion_reach - (6.0 if kind == "gaul_king" else 40.0)
		var cfg: Dictionary = b.wall
		for k in 21:
			s.terrain.add_post(Vector2(wall_x, -110.0 + k * float(cfg.gap)), float(cfg.radius), 1e9, "wall")
		s.terrain.refresh(s.commander.pos)
		var r := float(content.enemies[kind].radius)
		var i := s.horde.spawn_chieftain(Vector2(wall_x - r - 7.0, 0)) if kind == "gaul_king" else s.horde.spawn(kind, Vector2(wall_x - r - 120.0, 0), true)
		var id: int = s.horde.e_id[i]
		if kind == "gaul_king":
			s.horde.charge_cd = 0.0
		else:
			var st: Dictionary = s.horde.boss_state(i)
			for key in st:
				if str(key).ends_with("_cd"):
					st[key] = 1e9
			st["wedge_cd" if st.has("wedge_cd") else "onrush_cd"] = 0.0
		var through := false
		var charged := false
		for k in 4 * 60:
			s.update(1.0 / 60.0, Vector2.ZERO, false)
			charged = charged or s.horde.charging or (kind != "gaul_king" and s.horde.e_id.has(id) and float(s.horde.boss_state(s.horde.e_id.find(id)).get("rush_left", 0.0)) > 0.0)
			var j := s.horde.e_id.find(id)
			if j >= 0:
				through = through or s.horde.e_pos[j].x > wall_x
		check(charged, "the %s charges at the legion beyond the wall" % kind)
		check(not through, "the %s's charge stops at a wall and never comes out the other side" % kind)


func test_the_cheer_keeps_real_time_whatever_the_walk_counter_does(b: Dictionary) -> void:
	var cycle := float(b.triumph.cheer_cycle)
	var view: GDScript = load("res://scripts/world_view.gd")
	var step := 0.1
	var a: float = view.cheer_phase(1.0, 3, cycle)
	var later: float = view.cheer_phase(1.0 + step, 3, cycle)
	check(is_equal_approx(fposmod(later - a, cycle), step), "a man's cheer moves on at the pace of the clock (%.2f s for %.2f s)" % [fposmod(later - a, cycle), step])
	check(not is_equal_approx(view.cheer_phase(1.0, 3, cycle), view.cheer_phase(1.0, 4, cycle)), "and neighbours cheer a little out of step")


func test_horse_archers_on_the_edge_of_their_ring_do_not_flicker(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 1672, "province": "parthia"})
	s.commander.max_hp = 1e9
	s.commander.hp = 1e9
	while s.soldiers.size() < 30:
		s.legion.add(["legionary", "archer", "cavalry"][s.soldiers.size() % 3])
	s.legion.place_all(s.facing_angle)
	for k in 150 * 30:
		var a0 := k / 30.0 * 0.6
		s.update(1.0 / 30.0, Vector2(cos(a0), sin(a0)) * 0.8, false)
	var hist := {}
	var flips := 0
	var riders := {}
	for k in 26 * 60:
		var a := k / 60.0 * 0.6
		s.update(1.0 / 60.0, Vector2(cos(a), sin(a)) * 0.8, false)
		for j in s.horde.e_pos.size():
			if s.horde.kind_ids[s.horde.e_kind[j]] != "horse_archer":
				continue
			var id: int = s.horde.e_id[j]
			riders[id] = true
			var h: Array = hist.get(id, [])
			h.append(Sim.dir_index(s.horde.e_face[j]))
			if h.size() > 3:
				h.pop_front()
			hist[id] = h
			if h.size() == 3 and h[0] == h[2] and h[1] != h[0]:
				flips += 1
	check(riders.size() > 3, "horse archers ride round the legion (%d)" % riders.size())
	check(flips <= riders.size() * 2, "and their pictures do not flick back and forth between two ways (%d flicks among %d riders in 26 s)" % [flips, riders.size()])


func test_a_chieftain_hemmed_in_by_the_legion_does_not_spin(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 7, "province": "germania"})
	s.commander.max_hp = 1e9
	s.commander.hp = 1e9
	while s.soldiers.size() < 60:
		s.legion.add(["legionary", "legionary", "archer"][s.soldiers.size() % 3])
	s.legion.place_all(s.facing_angle)
	s.horde.next_band = 1e9
	s.horde.spawn_acc = -1e9
	for t in ["cleave_cd", "summon_cd", "siege_cd", "charge_cd"]:
		s.horde.set(t, 1e9)
	var ci := s.horde.spawn_chieftain(s.commander.pos + Vector2(60, 50))
	var id: int = s.horde.e_id[ci]
	var turns := 0
	var fought := 0
	var last := -1
	for k in 4 * 30:
		for u in s.units:
			u.hp = u.max_hp
		s.update(1.0 / 30.0, Vector2.ZERO, false)
		var j := s.horde.e_id.find(id)
		if j < 0:
			break
		s.horde.e_hp[j] = s.horde.e_max[j]
		fought += s.horde.e_fighting[j]
		var dir := Sim.dir_index(s.horde.e_face[j])
		if last >= 0 and dir != last:
			turns += 1
		last = dir
	check(fought > 60, "the chieftain is locked in melee among the soldiers (%d of 120 frames)" % fought)
	check(turns <= 8, "and turns now and then rather than from soldier to soldier every few frames (%d turns in 4 s)" % turns)


func test_the_testudo_stops_a_boss_charge(b: Dictionary) -> void:
	for kind in ["gaul_king", "falx_band", "lusitanian_raider", "camel_captain"]:
		var s := _gaul_sim(b, 1661, {"gaul_king": "gaul", "falx_band": "dacia", "lusitanian_raider": "hispania", "camel_captain": "aegyptus"}[kind])
		s.horde.cleave_cd = 1e9
		s.horde.summon_cd = 1e9
		s.horde.siege_cd = 1e9
		for t in ["sweep_cd", "rockfall_cd", "leap_cd", "salvo_cd"]:
			s.horde.set(t, 1e9)
		s.commander.pos = Vector2.ZERO
		s.legion.place_all(s.facing_angle)
		s._rebuild_grids()
		var r := float(content.enemies[kind].radius)
		var i := s.horde.spawn_chieftain(Vector2(-s.legion_reach - 10.0, 0)) if kind == "gaul_king" else s.horde.spawn(kind, Vector2(-s.legion_reach - r - 120.0, 0), true)
		var id: int = s.horde.e_id[i]
		if kind == "gaul_king":
			s.horde.charge_cd = 0.0
		else:
			var st: Dictionary = s.horde.boss_state(i)
			for key in st:
				if str(key).ends_with("_cd"):
					st[key] = 1e9
			st["wedge_cd" if st.has("wedge_cd") else "onrush_cd"] = 0.0
		var hp := 0.0
		for so in s.soldiers:
			hp += so.hp
		var places: Array = s.soldiers.map(func(so: Dictionary) -> Vector2: return so.pos)
		var dazed := false
		for k in 4 * 60:
			s.testudo_left = 5.0
			s.update(1.0 / 60.0, Vector2.ZERO, false)
			var j := s.horde.e_id.find(id)
			dazed = dazed or (j >= 0 and s.horde.e_stun[j] > 0.0)
		var after := 0.0
		var thrown := 0.0
		for n in s.soldiers.size():
			after += s.soldiers[n].hp
			thrown = maxf(thrown, s.soldiers[n].pos.distance_to(places[n]))
		check(after >= hp - 1.0, "the %s's charge into the testudo hurts nobody (%.0f of %.0f health left)" % [kind, after, hp])
		check(thrown < 12.0, "and throws nobody aside (%.0f px)" % thrown)
		check(dazed, "and leaves him dazed against the shields")


func test_barbarians_slowly_break_through_a_wall(b: Dictionary) -> void:
	var s := _quiet_sim(b, 308)
	_field(s, [])
	var cfg: Dictionary = b.wall
	var n := 44
	for k in n:
		s.terrain.add_post(s.commander.pos + Vector2.from_angle(TAU * k / n) * 75.0, float(cfg.radius), 1e9, "wall")
	s.terrain.refresh(s.commander.pos)
	for k in 30:
		s.horde.spawn("barbarian_club", s.commander.pos + Vector2.from_angle(TAU * k / 30.0) * 130.0)
	var inside := func() -> int:
		var c := 0
		for p in s.horde.e_pos:
			if p.distance_to(s.commander.pos) < 60.0:
				c += 1
		return c
	_step_dt(s, 6.0)
	check(inside.call() == 0 and s.terrain.posts.size() == n, "for a while the wall holds them all out")
	_step_dt(s, 40.0)
	check(s.terrain.posts.size() < n, "pressing on it, they break stakes (%d left)" % s.terrain.posts.size())
	check(inside.call() > 0 or s.kills > 0, "and get through")


func test_the_wall_has_its_own_key(b: Dictionary) -> void:
	Controls.install({})
	check(_has_key("wall", KEY_F) and _has_button("wall", JOY_BUTTON_LEFT_SHOULDER), "F and the left shoulder build a wall")
	check(Controls.ACTIONS.any(func(a: Array) -> bool: return a[0] == "wall"), "the settings let it be rebound")


func test_the_timber_keys_are_listed_with_their_costs(b: Dictionary) -> void:
	Controls.install({})
	var lines: Array = Hud.timber_keys(b, 5)
	check(lines.size() == 3, "palisade, wall and bridge are listed (%d)" % lines.size())
	var all := " ".join(lines.map(func(l: Dictionary) -> String: return l.text))
	for action in ["build", "wall", "bridge"]:
		check(all.contains(Controls.key_of(action)), "the %s key is shown" % action)
	check(not all.contains("/") and not all.contains(Controls.pad_of("wall")), "and no gamepad button beside it")
	check(str(lines[0].text).contains(str(int(b.palisade.cost))), "with its cost")
	check(lines[0].enough == (5 >= int(b.palisade.cost)) and lines[2].enough == (5 >= int(b.bridge.cost)), "lit only when the timber is there")


func test_the_palisade_has_its_own_key(b: Dictionary) -> void:
	Controls.install({})
	check(_has_key("build", KEY_E) and _has_button("build", JOY_BUTTON_X), "E and the west face button build")
	check(Controls.ACTIONS.any(func(a: Array) -> bool: return a[0] == "build"), "the settings let it be rebound")



func _fort_sim(b: Dictionary, seed_value: int) -> Sim:
	var s := _mode_sim(b, {"seed": seed_value})
	s.objectives.list.clear()
	s.terrain.clear()
	s.horde.next_surge = 1e9
	s.horde.next_band = 1e9
	s.horde.next_cart = 1e9
	s.objectives.raise_fort(s)
	s.terrain.refresh(s.commander.pos)
	return s


func test_a_short_row_stands_centred_behind_the_rows_before_it(b: Dictionary) -> void:
	var off_centre := []
	for n in range(1, 30):
		var s := _quiet_sim(b, 3)
		for k in n:
			s.legion.add("archer")
		var rows: Dictionary = {}
		for p in s.legion.formation():
			var key := snappedf(p.x, 0.5)
			rows[key] = rows.get(key, []) + [p.y]
		for key in rows:
			var sum := 0.0
			for y in rows[key]:
				sum += y
			if absf(sum / rows[key].size()) > 0.01:
				off_centre.append("%d archers, a row of %d" % [n, rows[key].size()])
	check(off_centre.is_empty(), "every row of the rear block stands centred, the short last row too (%s)" % [off_centre.slice(0, 4)])


func test_the_legion_marching_past_the_north_of_the_fort_stays_with_its_commander(b: Dictionary) -> void:
	var s := _fort_sim(b, 400)
	var fort: Dictionary = s.objectives.fort
	var half := float(fort.half)
	while s.soldiers.size() < 40:
		s.legion.add(["legionary", "legionary", "archer"][s.soldiers.size() % 3])
	# The legion marches west to east just beyond the fort's north wall, inside the band of its east and west walls.
	s.commander.pos = fort.centre + Vector2(-half * 2.0, -half - 90.0)
	s.facing_angle = 0.0
	s.legion.place_all(s.facing_angle)
	s.terrain.refresh(s.commander.pos)
	for k in 8 * 30:
		s.commander.hp = s.commander.max_hp
		s.update(1.0 / 30.0, Vector2(0.6, 0), false)
	var strays := 0
	var in_yard := 0
	for so in s.soldiers:
		if so.pos.distance_to(s.commander.pos) > s.legion_reach + 40.0:
			strays += 1
		if s.objectives.in_fort(so.pos, s):
			in_yard += 1
	check(not s.objectives.in_fort(s.commander.pos, s), "the commander never went into the fort")
	check(strays == 0 and in_yard == 0, "no soldier is led off into the fort while the legion passes its north wall (%d strayed, %d inside)" % [strays, in_yard])


func test_the_top_bar_names_the_province_and_difficulty(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 3, "province": "gaul", "difficulty": "hard"})
	var line: String = Hud.run_line(s)
	check(line == ("%s, %s" % [s.content.provinces.gaul.name, TranslationServer.translate("Hard")]).to_upper(), "the run's line reads the province, then the difficulty (%s)" % line)


func test_the_chieftain_is_never_inside_the_fort(b: Dictionary) -> void:
	var s := _fort_sim(b, 400)
	var fort: Dictionary = s.objectives.fort
	var ci := s.horde.spawn_chieftain(fort.centre + Vector2(10, 20))
	var id: int = s.horde.e_id[ci]
	s.update(1.0 / 30.0, Vector2.ZERO, false)
	var j := s.horde.e_id.find(id)
	check(j >= 0 and not Legion._in_yard(s.horde.e_pos[j], fort), "a chieftain shoved through the gate is put back outside the walls (%s)" % [s.horde.e_pos[j] - fort.centre if j >= 0 else "gone"])
	# Through the gate itself he may stand, since that is outside the yard.
	s.horde.e_pos[j] = fort.pos + Vector2(0, 40)
	s.update(1.0 / 30.0, Vector2.ZERO, false)
	check(s.horde.e_pos[s.horde.e_id.find(id)].distance_to(fort.pos + Vector2(0, 40)) < 30.0, "a chieftain outside the gate is left where he is")


func test_the_fort_is_a_walled_square_with_its_gate_towards_the_legion(b: Dictionary) -> void:
	var cfg: Dictionary = b.fort
	var s := _fort_sim(b, 400)
	var fort: Dictionary = s.objectives.fort
	var c: Vector2 = fort.centre
	var half := float(fort.half)
	check(fort.pos.is_equal_approx(c + Vector2(0, half)), "the gate stands in the middle of the south wall")
	check(c.y < s.commander.pos.y and absf(c.x - s.commander.pos.x) < c.distance_to(s.commander.pos), "the fort stands to the north, so the legion comes on its gate")
	var gate := false
	var stakes := 0
	var on_wall := true
	for pr in s.terrain.extras:
		gate = gate or (pr[0] == "fort_gate" and pr[1] == fort.pos)
		var walled: bool = absf(maxf(absf(pr[1].x - c.x), absf(pr[1].y - c.y)) - half) < 1.0
		# The side walls draw only some of their stakes and block with unseen posts between them.
		if pr[0] == "stake" or (pr[0] == "" and walled):
			stakes += 1
			on_wall = on_wall and pr[2] > 0.0 and walled
	check(gate, "the gate is the fort's entrance")
	s.terrain.refresh(c)
	check(stakes > int(8.0 * half / float(cfg.stake_gap)) - 12 and on_wall, "solid stakes run along all four walls (%d)" % stakes)
	var closed := true
	for k in 41:
		var t := -half + 2.0 * half * k / 40.0
		for p in [c + Vector2(t, -half), c + Vector2(-half, t), c + Vector2(half, t)]:
			closed = closed and s.terrain.push_out(p, 6.0) != p
		if absf(t) > float(cfg.tower_x) + 6.0:
			var q := c + Vector2(t, half)
			closed = closed and s.terrain.push_out(q, 6.0) != q
	check(closed, "a barbarian cannot slip between the stakes")
	var way: Vector2 = fort.pos + Vector2(0, -4)
	check(s.terrain.push_out(way, Sim.UNIT_RADIUS) == way, "but the gate is open")
	var block: Vector2 = Legion.block_size(int(b.legion_cap), b.legion)
	check(half - float(cfg.stake_radius) - Sim.UNIT_RADIUS > maxf(block.x, block.y) / 2.0, "inside there is room for the largest legion, %d men, in a block" % int(b.legion_cap))
	check(2.0 * half + 40.0 <= 360.0, "and the whole fort fits on the screen")


func test_a_full_legion_files_through_the_gate_and_stands_inside(b: Dictionary) -> void:
	var s := _fort_sim(b, 402)
	s.commander.max_hp = 1e9
	s.commander.hp = 1e9
	while s.soldiers.size() < int(b.legion_cap):
		s.legion.add(["legionary", "archer", "cavalry"][s.soldiers.size() % 3])
	var fort: Dictionary = s.objectives.fort
	s.commander.pos = fort.pos + Vector2(0, 320)
	s.facing_angle = -PI / 2.0
	s.legion.place_all(s.facing_angle)
	s.terrain.refresh(s.commander.pos)
	var dt := 1.0 / 30.0
	var k := 0
	while not s.objectives.in_fort(s.commander.pos, s) and k < 20 * 30:
		s.update(dt, Vector2.UP, false)
		k += 1
	check(s.objectives.in_fort(s.commander.pos, s), "the commander marches in through the gate (%.1f s)" % (k * dt))
	s.update(dt, Vector2.UP * 0.5, false)
	var settle := 0
	var all_in := false
	# The hold is kept from winning, so the run goes on while the legion settles.
	while settle < 8 * 30 and not all_in:
		fort.hold = 0.0
		s.update(dt, Vector2.ZERO, false)
		settle += 1
		all_in = true
		for so in s.soldiers:
			all_in = all_in and s.objectives.in_fort(so.pos, s)
	check(all_in, "every one of the %d soldiers is inside the walls %.1f s later" % [s.soldiers.size(), settle * dt])
	for j in 3 * 30:
		fort.hold = 0.0
		s.update(dt, Vector2.ZERO, false)
	var shoves := 0
	var drift := 0.0
	for j in 30:
		fort.hold = 0.0
		var before: Array = []
		for so in s.soldiers:
			before.append(so.pos)
		s.terrain.legion_shoves = 0
		s.update(dt, Vector2.ZERO, false)
		shoves += s.terrain.legion_shoves
		for i in s.soldiers.size():
			drift = maxf(drift, s.soldiers[i].pos.distance_to(before[i]))
	check(shoves == 0 and drift < 0.5, "and once settled no man is pushed by a wall or keeps moving (%d pushes, %.2f px)" % [shoves, drift])


func test_holding_the_fort_wins_the_run(b: Dictionary) -> void:
	var hold := float(b.fort.hold)
	var s := _fort_sim(b, 401)
	var fort: Dictionary = s.objectives.fort
	s.commander.pos = fort.pos + Vector2(0, 30)
	_step_dt(s, hold + 0.5)
	check(not s.over, "standing outside the gate does not win")
	s.commander.pos = fort.centre
	_step_dt(s, hold * 0.5)
	check(not s.over and fort.hold > 0.0, "half the time inside the walls is not enough")
	_step_dt(s, hold * 0.5 + 0.2 + float(b.triumph.most_seconds))
	check(s.over and s.victory, "holding the fort for %d seconds wins the run" % int(hold))
	var l := _fort_sim(b, 402)
	l.commander.pos = l.objectives.fort.centre
	_step_dt(l, hold * 0.8)
	l.commander.pos = l.objectives.fort.pos + Vector2(0, 200)
	_step_dt(l, hold)
	l.commander.pos = l.objectives.fort.centre
	_step_dt(l, hold * 0.5)
	check(not l.over, "time inside drains away when the commander leaves")


func test_the_fort_cannot_be_held_while_the_chieftain_lives(b: Dictionary) -> void:
	var hold := float(b.fort.hold)
	var s := _fort_sim(b, 404)
	var fort: Dictionary = s.objectives.fort
	var ci := s.horde.spawn_chieftain(fort.pos + Vector2(0, 900))
	s.horde.e_stun[ci] = 1e9
	s.commander.max_hp = 1e9
	s.commander.hp = 1e9
	s.commander.pos = fort.centre
	_step_dt(s, hold * 2.0)
	check(not s.victory, "standing in the fort while the chieftain lives does not win")
	check(s.objectives.notice.get("kind", "") == "fort_barred", "and a notice says he must fall first")
	s.hit(s.chieftain_index(), 1e9)
	_step_dt(s, hold + 0.2)
	check(s.victory, "once he falls, holding the fort wins the run")


func test_horses_follow_the_legion_into_the_fort(b: Dictionary) -> void:
	var s := _fort_sim(b, 405)
	var fort: Dictionary = s.objectives.fort
	s.commander.max_hp = 1e9
	s.commander.hp = 1e9
	for k in 6:
		s.add_soldier("cavalry")
	s.commander.pos = fort.centre
	s.facing_angle = -PI / 2.0
	s.legion.place_all(s.facing_angle)
	# Barbarians stand just outside the east wall, stunned and too tough to die, within a rider's reach.
	for k in 6:
		var e := s.horde.spawn("barbarian_club", fort.centre + Vector2(float(fort.half) + 14.0, -40.0 + k * 16.0))
		s.horde.e_stun[e] = 1e9
		s.horde.e_hp[e] = 1e9
		s.horde.e_max[e] = 1e9
	var rider: Dictionary = s.soldiers.filter(func(so: Dictionary) -> bool: return so.type == "cavalry")[0]
	rider.pos = fort.centre + Vector2(float(fort.half) + 60.0, 0)
	rider.sortie = 1
	var rode_out := false
	# The hold is kept from winning, so the riders are watched while the legion holds the fort.
	for k in 12 * 30:
		fort.hold = 0.0
		s.update(1.0 / 30.0, Vector2.ZERO, false)
		for so in s.soldiers:
			rode_out = rode_out or (so != rider and so.sortie != 0)
	check(not rode_out, "while the commander holds the fort no rider charges out")
	var out := 0
	for so in s.soldiers:
		if not s.objectives.in_fort(so.pos, s):
			out += 1
	check(out == 0, "and a rider already out comes back in through the gate (%d outside)" % out)
	var t := _fort_sim(b, 406)
	t.commander.pos = t.objectives.fort.centre
	t.add_soldier("cavalry")
	t.legion.place_all(t.facing_angle)
	var late: Dictionary = t.soldiers.filter(func(so: Dictionary) -> bool: return so.type == "cavalry")[0]
	late.pos = t.objectives.fort.centre + Vector2(0, -float(t.objectives.fort.half) - 80.0)
	late.sortie = 1
	t.win(t.commander.pos)
	_step_dt(t, float(b.triumph.most_seconds))
	check(t.objectives.in_fort(late.pos, t), "a rider out on a charge when the run is won rides back in for the triumph")


func test_a_victory_opens_with_a_reveal_that_counts_the_denarii(b: Dictionary) -> void:
	var s := _won_sim(b, 1653)
	s.win(s.commander.pos)
	check(SummaryScreen.reveals(s), "a won run opens with the victory reveal")
	s.demo_over = true
	check(not SummaryScreen.reveals(s), "the demo reaching its limit does not")
	var lost := _won_sim(b, 1654)
	check(not SummaryScreen.reveals(lost), "nor does a lost run")
	check(SummaryScreen.counted(250, 0.0) == 0 and SummaryScreen.counted(250, SummaryScreen.COUNT_FROM) == 0, "the count starts at nothing")
	var mid := SummaryScreen.counted(250, (SummaryScreen.COUNT_FROM + SummaryScreen.COUNT_TO) / 2.0)
	check(mid > 100 and mid < 150, "rises through the middle (%d)" % mid)
	check(SummaryScreen.counted(250, SummaryScreen.COUNT_TO) == 250 and SummaryScreen.counted(250, SummaryScreen.REVEAL) == 250, "and lands on the run's denarii")
	check(SummaryScreen.COUNT_TO < SummaryScreen.REVEAL, "before the reveal gives way to the summary")


func test_your_own_music_joins_the_battle_music(_b: Dictionary) -> void:
	check(Audio.PLAYER_MUSIC.begins_with("user://"), "your own music is kept beside the saves")
	var folder := ProjectSettings.globalize_path("user://test_music")
	DirAccess.make_dir_recursive_absolute(folder)
	var tone := AudioStreamWAV.new()
	tone.format = AudioStreamWAV.FORMAT_16_BITS
	tone.mix_rate = 22050
	tone.data = PackedByteArray()
	tone.data.resize(4410)
	tone.save_to_wav(folder.path_join("march.wav"))
	var notes := FileAccess.open(folder.path_join("notes.txt"), FileAccess.WRITE)
	notes.store_string("not music")
	notes.close()
	var found := Audio.player_tracks(folder)
	check(found.size() == 1 and str(found[0]).ends_with("march.wav"), "a music file in the folder is found (%s)" % str(found))
	check(Audio.load_external(str(found[0])) is AudioStreamWAV, "and it can be played")
	check(Audio.load_external(folder.path_join("notes.txt")) == null, "a file that is not music is skipped")
	check(Audio.player_tracks(folder.path_join("missing")).is_empty(), "and a folder not yet made has none")
	for f in DirAccess.get_files_at(folder):
		DirAccess.remove_absolute(folder.path_join(f))
	DirAccess.remove_absolute(folder)
	var game := Audio.battle_tracks()
	check(game.size() == 3, "the game brings three battle tracks (%d)" % game.size())
	var picked := {}
	var last := ""
	var repeats := 0
	for k in 60:
		var next := Audio.next_track(["a", "b", "c"], last)
		repeats += 1 if next == last else 0
		picked[next] = true
		last = next
	check(repeats == 0 and picked.size() == 3, "the battle music never plays the same track twice running, and plays them all")
	check(Audio.next_track(["a"], "a") == "a" and Audio.next_track([], "a") == "", "a single track repeats, and none means silence")


func test_the_triumph_waits_for_the_last_coin_and_barbarian(b: Dictionary) -> void:
	var cfg: Dictionary = b.triumph
	var s := _won_sim(b, 1652)
	s.drop_coin(s.commander.pos + Vector2(float(cfg.coin_speed) * float(cfg.seconds) * 1.5, 0), 5)
	s.win(s.commander.pos)
	var steps := 0
	var early := false
	while not s.over and steps < 60 * 60:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		steps += 1
		early = early or (s.over and (s.c_pos.size() > 0 or not s.horde.e_pos.is_empty()))
	check(not early, "the run does not end while a coin or barbarian is left")
	check(s.over and s.c_pos.is_empty() and s.horde.e_pos.is_empty(), "it ends once the field is clear")
	check(steps / 60.0 <= float(cfg.most_seconds) + 0.1, "and never waits past %.0f s (%.1f)" % [float(cfg.most_seconds), steps / 60.0])


func test_a_win_marches_on_to_the_next_province(b: Dictionary) -> void:
	var saved: Dictionary = Profile.data
	Profile.data = Profile.defaults()
	Profile.data.records["germania"] = Profile.record_of("germania")
	Profile.data.records.germania.won = true
	Profile.open_won_provinces(content)
	var next := Game.next_province(content, b, "germania")
	if content.ready("provinces", "gaul"):
		check(next == "gaul", "after Germania is won the map moves on to Gaul (%s)" % next)
	check(Game.next_province(content, b, content.provinces.keys()[-1]) == "", "after the last province there is nowhere further")
	Profile.data = Profile.defaults()
	check(Game.next_province(content, b, "germania") == "", "a province that is still locked is not chosen")
	Profile.data = saved


func test_killing_the_chieftain_does_not_end_the_run(b: Dictionary) -> void:
	var s := _fort_sim(b, 403)
	s.time = float(b.chieftain_at)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var ci := s.chieftain_index()
	check(ci >= 0, "the chieftain is out")
	s.hit(ci, 1e9)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(not s.over, "killing the chieftain does not end the run")


func test_the_camp_burns_and_its_huts_go(b: Dictionary) -> void:
	var cfg: Dictionary = b.objectives.camp
	var s := _objective_sim(b, 410)
	var camp: Dictionary = s.objectives.add(s, "camp", Vector2(600, 0))
	var huts: Array = camp.huts
	check(huts.size() == int(cfg.huts), "the camp has %d huts" % int(cfg.huts))
	s.commander.pos = camp.pos + Vector2(float(cfg.hut_ring) - 20.0, 0)
	s.terrain.refresh(s.commander.pos)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(camp.done and camp.burnt_at >= 0.0, "the commander walking into the camp takes the eagle and sets the huts alight")
	check(_solid_at(s, huts[0]), "the burning huts still stand at first")
	_step_dt(s, Objectives.fall_at(cfg, 0) - 0.1)
	check(_solid_at(s, huts[0]) and _kinds_at(s, huts[0]) == ["hut"], "until the first one collapses")
	_step_dt(s, float(cfg.burn_seconds) - Objectives.fall_at(cfg, 0) + 0.5)
	var gone := true
	for h in huts:
		gone = gone and not _solid_at(s, h) and _kinds_at(s, h) == ["hut_ruin"] and s.terrain.is_open(h)
	check(camp.razed and gone, "then only walk-through ruins are left and the ground is open")
	var e := _objective_sim(b, 411)
	var c2: Dictionary = e.objectives.add(e, "camp", Vector2(600, 0))
	e.soldiers[0].pos = c2.pos
	e._rebuild_grids()
	e.objectives.update(0.01, e)
	check(c2.burnt_at >= 0.0, "taking the eagle sets the camp alight too")


func test_the_camp_burn_runs_through_its_stages(b: Dictionary) -> void:
	var cfg: Dictionary = b.objectives.camp
	var last := int(cfg.huts) - 1
	check(Objectives.hut_stage(cfg, 0, 0.05) == "catching" and Objectives.hut_stage(cfg, last, 0.05) == "catching", "every hut is catching fire at first")
	check(Objectives.hut_stage(cfg, 0, 0.0) == "catching" and Objectives.hut_flames(cfg, 0, 0.05) == 1, "a hut catches at one spot")
	check(Objectives.hut_flames(cfg, last, 0.05) == 0, "and the huts catch one after another")
	var blazing := true
	for i in int(cfg.huts):
		blazing = blazing and Objectives.hut_stage(cfg, i, 2.05) == "blazing" and Objectives.hut_flames(cfg, i, 2.05) == 3
	check(blazing, "by two seconds every hut blazes at three spots")
	var falls: Array = []
	for i in int(cfg.huts):
		falls.append(Objectives.fall_at(cfg, i))
	check(falls[0] >= 5.5 and falls[0] <= 6.5 and falls[last] > falls[0] and falls[last] < 9.0, "the huts collapse about six seconds in, one after another (%s)" % [falls])
	check(Objectives.hut_stage(cfg, 0, falls[0] - 0.05) == "blazing" and Objectives.hut_stage(cfg, 0, falls[0] + 0.05) == "collapsing", "a hut blazes until it collapses")
	check(Objectives.hut_stage(cfg, 0, 10.0) == "smouldering" and Objectives.hut_stage(cfg, last, 10.0) == "smouldering", "then smoulders")
	check(absf(float(cfg.burn_seconds) - 15.0) < 0.01, "the burn lasts fifteen seconds (%.1f)" % float(cfg.burn_seconds))
	check(Objectives.hut_stage(cfg, 0, 14.9) == "smouldering" and Objectives.hut_stage(cfg, last, 15.0) == "ruins", "and leaves ruins once it is over")


func test_the_camp_huts_stop_blocking_as_each_collapses(b: Dictionary) -> void:
	var cfg: Dictionary = b.objectives.camp
	var s := _objective_sim(b, 412)
	var camp: Dictionary = s.objectives.add(s, "camp", Vector2(600, 0))
	var huts: Array = camp.huts
	s.commander.pos = camp.pos
	s.terrain.refresh(s.commander.pos)
	s.events.clear()
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var start: float = camp.burnt_at
	var first := Objectives.fall_at(cfg, 0)
	var second := Objectives.fall_at(cfg, 1)
	_step_dt(s, first + 0.05 - (s.time - start))
	check(not _solid_at(s, huts[0]) and _kinds_at(s, huts[0]) == ["hut_charred"], "the first hut stops blocking as it collapses")
	check(_solid_at(s, huts[1]) and _kinds_at(s, huts[1]) == ["hut"], "while the next still stands")
	check(_count_events(s, "hut_fall") == 1 and s.shake > 0.0, "the collapse sounds and shakes the screen")
	check(not camp.razed, "and the camp is not razed yet")
	_step_dt(s, second + 0.05 - (s.time - start))
	check(not _solid_at(s, huts[1]), "the next stops blocking when it collapses")
	_step_dt(s, float(cfg.burn_seconds) + 0.1 - (s.time - start))
	check(_count_events(s, "hut_fall") == huts.size(), "every hut collapses once (%d)" % _count_events(s, "hut_fall"))
	_step_dt(s, 30.0)
	var open := true
	for h in huts:
		open = open and not _solid_at(s, h) and s.terrain.is_open(h) and _kinds_at(s, h) == ["hut_ruin"]
	check(camp.razed and open, "the ruins stay walk-through after the burn")


func test_burning_the_camp_changes_nothing_else_about_finishing_it(b: Dictionary) -> void:
	var cfg: Dictionary = b.objectives.camp
	var s := _objective_sim(b, 413)
	var camp: Dictionary = s.objectives.add(s, "camp", Vector2(600, 0))
	var choices := s.free_choices
	s.commander.pos = camp.pos
	s.terrain.refresh(s.commander.pos)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var after := [camp.done, s.free_choices, s.objectives.purse, camp.done_at]
	check(camp.done and s.free_choices == choices + 1, "taking the eagle finishes the camp at once with a free choice")
	_step_dt(s, float(cfg.burn_seconds) + 1.0)
	check([camp.done, s.free_choices, s.objectives.purse, camp.done_at] == after, "and the burn adds nothing to it (%s against %s)" % [[camp.done, s.free_choices, s.objectives.purse, camp.done_at], after])


func _press_tree(s: Sim, i: int, tree: Vector2, seconds: float) -> void:
	for f in int(seconds * 60.0):
		s.horde.e_pos[i] = tree + Vector2(Terrain.SOLID.oak + 5.0, 0)
		s.horde.e_stuck[i] = 0.0
		s.update(1.0 / 60.0, Vector2.ZERO, false)


func test_barbarians_chop_trees_slowly_and_leave_no_timber(b: Dictionary) -> void:
	var s := _quiet_sim(b, 412)
	s.legion.soldiers.clear()
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	var at := Vector2(-60, 0)
	_field(s, [["oak", at, Terrain.SOLID.oak]])
	s.commander.pos = Vector2(-200, 0)
	var i := s.horde.spawn("barbarian_club", at + Vector2(14, 0))
	var rate := float(b.felling.barbarian_rate)
	check(rate > 0.0 and rate <= 0.25, "a barbarian chops at a fraction of a soldier's pace (%.2f)" % rate)
	_press_tree(s, i, at, 2.0)
	var chop := s.terrain.chop_of(at)
	check(chop > 2.0 * rate * 0.6 and chop < 2.0 * rate * 1.2, "two seconds against the tree give %.2f seconds of chopping (%.2f)" % [2.0 * rate, chop])
	_press_tree(s, i, at, float(b.felling.seconds) / rate - 1.5)
	check(not _solid_at(s, at) and _kinds_at(s, at) == ["stump"], "in the end the tree falls and leaves a stump")
	check(s.timber == 0, "and the legion gains no timber (%d)" % s.timber)


func test_barbarians_cannot_fell_the_runs_own_pieces(b: Dictionary) -> void:
	var s := _quiet_sim(b, 413)
	s.legion.soldiers.clear()
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	_field(s, [])
	var at := Vector2(-60, 0)
	s.terrain.add_clearing(at, 30.0, [["oak", at, Terrain.SOLID.oak]])
	s.commander.pos = Vector2(-200, 0)
	s.terrain.refresh(s.commander.pos)
	var i := s.horde.spawn("barbarian_club", at + Vector2(14, 0))
	_press_tree(s, i, at, float(b.felling.seconds) / float(b.felling.barbarian_rate) + 1.0)
	check(_solid_at(s, at) and s.terrain.chop_of(at) == 0.0, "a grove's oak stands however long barbarians press it")


func test_bosses_are_big_and_sturdy(b: Dictionary) -> void:
	var all := Content.with_all_art()
	var elites := true
	var chiefs := true
	for id in all.enemies:
		var e: Dictionary = all.enemies[id]
		if e.get("elite", false):
			elites = elites and float(e.hp) >= 1100.0 and float(e.radius) >= 14.0
		if e.get("chieftain", false):
			chiefs = chiefs and float(e.hp) >= 7800.0 and float(e.radius) >= 26.0
	check(elites, "every elite has at least 1100 health and a radius of 14")
	check(chiefs, "every chieftain has at least 7800 health and a radius of 26")


func _calm_chief(s: Sim) -> void:
	s.horde.cleave_cd = 1e9
	s.horde.cry_cd = 1e9
	s.horde.charge_cd = 1e9
	s.horde.slam_cd = 1e9
	s.horde.horn_cd = 1e9


func test_big_bosses_still_fight_and_collide(b: Dictionary) -> void:
	var s := _chief_sim(b, 414)
	s.legion.soldiers.clear()
	s.commander.pos = Vector2(31, 0)
	var ci := s.horde.spawn("chieftain", Vector2(31 + Sim.UNIT_RADIUS + 41, 0))
	s.horde.k_radius[s.horde.e_kind[ci]] = 40.0
	s.horde.set("max_radius", 40.0)
	s._rebuild_grids()
	var hp0: float = s.horde.e_hp[ci]
	s.commander.cd = 0.0
	var cu: Dictionary = s.content.base_commander
	s.melee(s.commander, float(cu.damage), float(cu.reach), float(cu.cooldown), 1.0 / 60.0)
	check(s.horde.e_hp[ci] < hp0, "the commander strikes a big chieftain he stands against")
	var before: float = s.commander.hp
	s.horde.e_pos[ci] = s.commander.pos + Vector2(Sim.UNIT_RADIUS + 41, 0)
	s._rebuild_grids()
	s.horde._move(1.0 / 60.0, s)
	check(s.commander.hp < before, "and the chieftain hurts the commander at the edge of his reach")
	var g := _chief_sim(b, 415)
	g.horde.spawn_chieftain(Vector2(300, 0))
	var gc := g.horde.chieftain_index()
	var clear := true
	for j in g.horde.e_pos.size():
		if g.horde.e_guard[j] != Vector2.ZERO:
			clear = clear and g.horde.e_pos[j].distance_to(g.horde.e_pos[gc]) > g.horde.k_radius[g.horde.e_kind[j]] + g.horde.k_radius[g.horde.e_kind[gc]] + 2.0
	check(clear, "his bodyguard stand clear of his bigger frame")
	var r := _quiet_sim(b, 416, Content.with_all_art())
	r.commander.hp = 1e9
	r.commander.max_hp = 1e9
	r.commander.pos = Vector2(-300, 0)
	var rock := Vector2(-15, 0)
	_field(r, [["rock", rock, Terrain.SOLID.rock]])
	var k := r.horde.spawn("chieftain", Vector2(18, 0))
	var big := r.horde.k_radius[r.horde.e_kind[k]]
	r.horde.e_pos[k] = rock + Vector2(Terrain.SOLID.rock + big - 3.0, 0)
	_calm_chief(r)
	_step_dt(r, 0.3)
	check(r.horde.e_pos[k].distance_to(rock) >= Terrain.SOLID.rock + big - 0.5, "a big chieftain cannot walk through a rock")



## A quiet sim with a sturdy commander and `n` club warriors spread over the screen, out of the legion's reach.
func _god_sim(b: Dictionary, seed_value: int, n := 30) -> Sim:
	var s := _quiet_sim(b, seed_value, Content.with_all_art())
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	for k in n:
		var a := k * TAU / n
		s.horde.spawn("barbarian_club", Vector2(cos(a) * 250.0, sin(a) * 140.0))
	return s


func _fill_favour(s: Sim) -> void:
	s.gods.favour = s.gods.need(s.b)


func test_a_god_called_gathers_every_coin(b: Dictionary) -> void:
	var s := _god_sim(b, 506, 0)
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	for k in 6:
		s.drop_coin(s.commander.pos + Vector2.from_angle(k) * 900.0, 3)
	var money := s.denarii
	_fill_favour(s)
	s.gods.invoke(s, "mars")
	_step_dt(s, 0.5)
	s.drop_coin(s.commander.pos + Vector2(700, 0), 3)
	_step_dt(s, float(b.gods.gather_seconds))
	check(s.c_pos.is_empty(), "every coin on the field comes in, including those dropped just after the call (%d left)" % s.c_pos.size())
	check(s.denarii >= money + 21, "and is counted (%d)" % (s.denarii - money))
	check(int(b.gods.favour_first) <= 1000 and int(b.gods.favour_step) <= 900, "the gods can be called a little more often than before (%d, then %d more each time)" % [int(b.gods.favour_first), int(b.gods.favour_step)])


func test_favour_fills_as_barbarians_die(b: Dictionary) -> void:
	var s := _god_sim(b, 500, 0)
	var need := int(b.gods.favour_first)
	check(s.gods.need(s.b) == need, "the first call needs %d kills" % need)
	for k in need + 5:
		var i := s.horde.spawn("barbarian_club", Vector2(250, 0))
		s.hit(i, 1e6)
		s._remove_dead()
	check(s.gods.favour == need, "every kill adds favour, up to the full meter (%d)" % s.gods.favour)
	check(s.gods.full(s.b), "the meter is full")
	s.gods.invoke(s, "apollo")
	check(s.gods.favour == 0, "a call spends the favour")
	check(s.gods.need(s.b) == need + int(b.gods.favour_step), "and the next call needs more kills")


func test_favour_does_not_fill_while_a_god_is_at_work(b: Dictionary) -> void:
	var s := _god_sim(b, 501, 0)
	s.gods.invoke(s, "mars")
	var i := s.horde.spawn("barbarian_club", Vector2(250, 0))
	s.hit(i, 1e6)
	s._remove_dead()
	check(s.gods.favour == 0, "a kill during the frenzy of Mars adds no favour")
	_step_dt(s, float(b.gods.mars.seconds) + 0.5)
	i = s.horde.spawn("barbarian_club", Vector2(250, 0))
	s.hit(i, 1e6)
	s._remove_dead()
	check(s.gods.favour == 1, "once it ends kills count again")


func test_the_gods_are_offered_only_with_full_favour(b: Dictionary) -> void:
	var s := _god_sim(b, 502, 0)
	check(Gods.offers(s).is_empty(), "no choice without full favour")
	s.gods.favour = s.gods.need(s.b) - 1
	check(Gods.offers(s).is_empty(), "nor one kill short")
	_fill_favour(s)
	var seen := {}
	for k in 30:
		s.gods.offer = []
		var o := Gods.offers(s)
		check(o.size() == 3 and o[0] != o[1] and o[1] != o[2] and o[0] != o[2], "three different gods")
		for id in o:
			seen[id] = true
	check(seen.size() == 5, "all five gods turn up (%d)" % seen.size())
	for id in Gods.IDS:
		check(content.ready("gods", id), "%s has its art" % id)


func test_jupiter_strikes_down_the_barbarians_on_screen(b: Dictionary) -> void:
	var s := _god_sim(b, 503, 40)
	var far_i := s.horde.spawn("barbarian_club", Vector2(420, 0))
	var far := s.horde.e_id[far_i]
	s.horde.e_stun[far_i] = 100.0
	s.gods.invoke(s, "jupiter")
	_step_dt(s, 0.5)
	check(not s.gods.bolts.is_empty(), "bolts are falling")
	_step_dt(s, float(b.gods.jupiter.seconds))
	var left_on_screen := 0
	var far_alive := false
	for i in s.horde.e_pos.size():
		if s.horde.e_id[i] == far:
			far_alive = true
		elif Gods.on_screen(s, s.horde.e_pos[i]):
			left_on_screen += 1
	check(left_on_screen == 0, "every barbarian on screen is struck down (%d left)" % left_on_screen)
	check(far_alive, "the one off screen is spared")
	check(s.damage_by_source.get("jupiter", 0.0) > 0.0, "the damage is counted for Jupiter")


func test_neptune_throws_back_and_stuns_the_barbarians(b: Dictionary) -> void:
	var s := _god_sim(b, 504, 0)
	for k in 12:
		s.horde.spawn("barbarian_club", Vector2.from_angle(k * TAU / 12.0) * 70.0)
	s.gods.invoke(s, "neptune")
	check(s.shake > 0.0, "the ground shakes")
	_step_dt(s, 1.2)
	var nearest := INF
	var stunned := true
	for i in s.horde.e_pos.size():
		nearest = minf(nearest, s.horde.e_pos[i].distance_to(s.commander.pos))
		stunned = stunned and s.horde.e_stun[i] > 0.0
	check(nearest > 70.0 + float(b.gods.neptune.throw) * 0.8, "they are thrown far back (nearest %.0f)" % nearest)
	check(stunned and s.horde.e_pos.size() == 12, "and lie stunned")
	var at: Vector2 = s.horde.e_pos[0]
	_step_dt(s, 0.5)
	check(s.horde.e_pos[0] == at, "a stunned barbarian does not move")
	_step_dt(s, float(b.gods.neptune.stun))
	check(s.horde.e_pos[0] != at, "and comes on again once the stun wears off")


func test_mars_fills_the_legion_with_war_frenzy(b: Dictionary) -> void:
	var s := _god_sim(b, 505, 0)
	var rate := s.attack_rate()
	var i := s.horde.spawn("barbarian_club", Vector2(250, 0))
	s.horde.e_hp[i] = 1000.0
	s.hit(i, 10.0)
	var plain := 1000.0 - s.horde.e_hp[i]
	s.gods.invoke(s, "mars")
	s.horde.e_hp[i] = 1000.0
	s.hit(i, 10.0)
	check(is_equal_approx(1000.0 - s.horde.e_hp[i], plain * float(b.gods.mars.damage_mult)), "the legion strikes three times as hard")
	check(is_equal_approx(s.attack_rate(), rate * float(b.gods.mars.rate_mult)), "and half again as fast")
	var calm := _god_sim(b, 505, 0)
	for t in [s, calm]:
		for j in t.horde.e_pos.size():
			t.horde.e_hp[j] = 0.0
		t._remove_dead()
		t.b.commander_regen = 0.0
		t.commander.hp = 100.0
		t.commander.max_hp = 100.0
		t._last_hp = 100.0
		t.soldiers.clear()
		t.horde.spawn("barbarian_club", t.commander.pos + Vector2(10, 0))
		t.horde.e_hp[0] = 1e9
		t.horde.e_max[0] = 1e9
		_step_dt(t, 1.0)
	var lost_frenzy: float = 100.0 - s.commander.hp
	var lost_calm: float = 100.0 - calm.commander.hp
	check(lost_frenzy > 0.0 and absf(lost_frenzy - lost_calm * float(b.gods.mars.taken_mult)) < lost_calm * 0.1, "and takes half the harm (%.1f vs %.1f)" % [lost_frenzy, lost_calm])
	_step_dt(s, float(b.gods.mars.seconds))
	check(is_equal_approx(s.attack_rate(), rate), "the frenzy ends after %d seconds" % int(b.gods.mars.seconds))


func test_vulcan_sets_the_screen_on_fire(b: Dictionary) -> void:
	var s := _god_sim(b, 506, 30)
	var far := s.horde.spawn("barbarian_club", Vector2(700, 0))
	s.horde.e_stun[far] = 100.0
	s.gods.invoke(s, "vulcan")
	var all_burning := true
	for i in s.horde.e_pos.size():
		if i != far:
			all_burning = all_burning and s.horde.e_burn[i] > 0.0
	check(all_burning, "every barbarian on screen catches fire")
	check(s.horde.e_burn[far] <= 0.0, "the one off screen does not")
	_step_dt(s, 2.0)
	var patches := 0
	for z in s.arms.zones:
		if z.kind == "fire" and z.src == "vulcan":
			patches += 1
	check(patches == int(b.gods.vulcan.patches), "burning ground lands on the screen (%d)" % patches)
	_step_dt(s, float(b.gods.vulcan.burn_seconds))
	var left := 0
	for i in s.horde.e_pos.size():
		if Gods.on_screen(s, s.horde.e_pos[i]):
			left += 1
	check(left == 0, "the burning barbarians fall (%d left)" % left)


func test_apollo_heals_the_legion_and_brings_back_the_fallen(b: Dictionary) -> void:
	var s := _god_sim(b, 507, 0)
	for so in s.soldiers:
		so.hp = 1.0
	s.commander.hp = 5.0
	for k in 15:
		s.legion.fallen.append("legionary")
	s.legion.reserves.append({"type": "legionary", "t": 50.0})
	var before := s.soldiers.size()
	s.gods.invoke(s, "apollo")
	var full: bool = s.commander.hp == s.commander.max_hp
	for so in s.soldiers:
		full = full and so.hp == so.max_hp
	check(full, "every man is healed to full")
	var back := int(b.gods.apollo.revive)
	check(s.soldiers.size() == before + back, "%d fallen soldiers come back (%d)" % [back, s.soldiers.size() - before])
	check(s.legion.fallen.size() == 15 - back, "and leave the fallen list")
	check(s.legion.reserves.is_empty(), "a man brought back is not sent again by the reserves")


func test_the_gods_do_not_one_shot_a_boss(b: Dictionary) -> void:
	var share := float(b.gods.boss_share)
	for id in ["jupiter", "vulcan"]:
		var s := _god_sim(b, 508, 0)
		var e := s.horde.spawn("berserker", Vector2(200, 0), true)
		s.horde.e_stun[e] = 100.0
		var eid := s.horde.e_id[e]
		s.gods.invoke(s, id)
		_step_dt(s, 10.0)
		var hp := -1.0
		var max_hp := 0.0
		for i in s.horde.e_pos.size():
			if s.horde.e_id[i] == eid:
				hp = s.horde.e_hp[i]
				max_hp = s.horde.e_max[i]
		check(hp > 0.0 and hp < max_hp, "%s hurts the elite but does not kill it" % id)
		check(hp >= max_hp * (1.0 - share) - 1.0, "%s takes at most %d%% of its health (%.0f of %.0f)" % [id, int(share * 100.0), hp, max_hp])
	var c := _god_sim(b, 509, 0)
	var ci := c.horde.spawn_chieftain(Vector2(200, 0))
	var cid := c.horde.e_id[ci]
	c.gods.invoke(c, "jupiter")
	_step_dt(c, 4.0)
	ci = c.horde.chieftain_index()
	check(ci >= 0 and c.horde.e_id[ci] == cid and c.horde.e_hp[ci] >= c.horde.e_max[ci] * (1.0 - share) - 1.0, "the chieftain survives the storm of Jupiter")


func test_hints_follow_the_last_device_used(b: Dictionary) -> void:
	Controls.pad_in_use = false
	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	Controls.note_input(button)
	check(Controls.pad_in_use, "a gamepad button switches the hints to the gamepad")
	var drift := InputEventJoypadMotion.new()
	drift.axis = JOY_AXIS_LEFT_X
	drift.axis_value = 0.1
	var key := InputEventKey.new()
	key.physical_keycode = KEY_W
	key.pressed = true
	Controls.note_input(key)
	check(not Controls.pad_in_use, "a key switches them back")
	Controls.note_input(drift)
	check(not Controls.pad_in_use, "a resting stick's drift does not")


func test_the_gods_have_their_own_key(b: Dictionary) -> void:
	Controls.install({})
	check(_has_key("pray", KEY_G) and _has_button("pray", JOY_BUTTON_Y), "G and the north face button call the gods")
	check(Controls.ACTIONS.any(func(a: Array) -> bool: return a[0] == "pray"), "the settings let it be rebound")
	check(Controls.hint("pray") == "G  call the gods", "on the keyboard the hint names only the key (%s)" % Controls.hint("pray"))
	Controls.pad_in_use = true
	check(Controls.hint("pray") == "Y  call the gods", "with a gamepad in hand only the button (%s)" % Controls.hint("pray"))
	Controls.pad_in_use = false
	for other in ["testudo", "build", "pause", "up", "down", "left", "right", "quit", "reroll", "banish", "fullscreen"]:
		check(not _has_key(other, KEY_G), "G is not also %s" % other)
	for other in ["testudo", "build", "pause", "back"]:
		check(not _has_button(other, JOY_BUTTON_Y), "Y is not also %s" % other)


const ATTACKERS := ["legionary", "commander", "archer", "barbarian_club", "barbarian_spear", "axe_thrower", "wolf", "war_dog",
	"berserker", "war_band_leader", "war_priest", "chieftain"]
const DIRECTIONS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]


func test_every_fighter_has_an_attack_in_all_eight_directions(_b: Dictionary) -> void:
	var atlas := Atlas.new()
	for type in ATTACKERS:
		var unit: Dictionary = atlas.units.get(type, {})
		check(unit.has("attack"), "%s has an attack in the atlas" % type)
		for d in DIRECTIONS:
			check(unit.get("attack", {}).has(d) and unit.attack[d].frames.size() == 8, "%s attacks facing %s in 8 frames" % [type, d])


func test_a_soldiers_strike_plays_his_attack_once(b: Dictionary) -> void:
	var atlas := Atlas.new()
	var s := _quiet_sim(b, 600)
	var so: Dictionary = s.soldiers[0]
	s.horde.spawn("barbarian_club", so.pos + Vector2(0, 12))
	s.horde.e_stun[0] = 100.0
	s.horde.e_hp[0] = 1e6
	s.horde.e_max[0] = 1e6
	so.cd = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(is_equal_approx(float(so.get("struck_at", -1.0)), s.time), "the strike is timed on the soldier")
	check(Sim.dir_name(so.strike_dir) == "south", "he turns to the barbarian he strikes (%s)" % Sim.dir_name(so.strike_dir))
	var start := atlas.attack_frame(so.type, Sim.dir_name(so.strike_dir), s.time - so.struck_at)
	check(not start.is_empty() and start[0] == atlas.unit_frame(so.type, "attack", "south", 0.0)[0], "his attack starts on its first frame")
	s.horde.remove_at(0)
	for i in 60:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(atlas.attack_frame(so.type, Sim.dir_name(so.strike_dir), s.time - so.struck_at).is_empty(), "and is over a second later")


func test_barbarians_turn_to_the_roman_they_fight(b: Dictionary) -> void:
	var s := _quiet_sim(b, 601)
	s.horde.spawn("barbarian_club", s.commander.pos + Vector2(-9, -9))
	s.horde.e_face[0] = Vector2.RIGHT
	for i in 10:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.horde.e_fighting[0] == 1, "the barbarian is in melee")
	check(s.horde.e_face[0].dot((s.commander.pos - s.horde.e_pos[0]).normalized()) > 0.9, "and faces the man he fights")


func test_a_thrower_marks_his_throw_and_faces_it(b: Dictionary) -> void:
	var s := _quiet_sim(b, 602)
	s.horde.spawn("axe_thrower", s.commander.pos + Vector2(0, -80))
	s.horde.e_cd[0] = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.horde.sp_pos.size() == 1, "the axe is thrown")
	check(is_equal_approx(s.horde.e_strike[0], s.time), "the throw is timed on the thrower")
	check(Sim.dir_name(s.horde.e_face[0]) == "south", "he faces where he threw")
	var power0: float = s.horde.e_power[0]
	s.horde.e_power[0] = 2.0
	s.horde.e_cd[0] = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.horde.sp_dmg.size() == 2 and is_equal_approx(s.horde.sp_dmg[1], s.horde.sp_dmg[0] * 2.0 / power0), "a fiercer thrower's axe hurts in step with his power")


func test_the_horde_is_drawn_from_the_atlas_frames(b: Dictionary) -> void:
	var s := _quiet_sim(b, 603)
	var view: Node2D = load("res://scripts/world_view.gd").new()
	view.atlas = Atlas.new()
	view.sim = s
	view._index_kinds()
	var wrong: Array = []
	for k in s.horde.kind_ids.size():
		var type: String = s.horde.kind_ids[k]
		if not view.atlas.units.has(type):
			continue
		for d in 8:
			var slot: int = k * 24 + d
			for t in [0.0, 0.7, 3.2, 7.9, 8.0, 13.5, 101.25]:
				var f: Array = view.atlas.unit_frame(type, "move", Sim.DIRS[d], t)
				if f[0] != view._f_rect[view._f_start[slot] + posmod(int(t), view._f_count[slot])] or f[1] != view._f_anchor[slot]:
					wrong.append("%s move %s %.2f" % [type, Sim.DIRS[d], t])
				var idle: Array = view.atlas.unit_frame(type, "idle", Sim.DIRS[d], 0.0)
				if idle[0] != view._f_rect[view._f_start[slot + 16]] or idle[1] != view._f_anchor[slot + 16]:
					wrong.append("%s idle %s" % [type, Sim.DIRS[d]])
				if view._k_attack[k] == 1:
					var since: float = fmod(t, 0.5)
					var a: Array = view.atlas.attack_frame(type, Sim.DIRS[d], since)
					if a[0] != view._f_rect[view._f_start[slot + 8] + int(since * Atlas.ATTACK_FPS)] or a[1] != view._f_anchor[slot + 8]:
						wrong.append("%s attack %s %.2f" % [type, Sim.DIRS[d], since])
		for d in 8:
			var face := Vector2.from_angle(d * PI / 4.0 + 0.3)
			if Sim.DIRS[Sim.dir_index(face)] != Sim.dir_name(face):
				wrong.append("direction %d" % d)
	view.free()
	check(wrong.is_empty(), "every barbarian's frame comes from the atlas (%s)" % [wrong.slice(0, 4)])


func test_trees_on_sand_stand_in_a_drift_and_trees_on_grass_do_not(b: Dictionary) -> void:
	var view: Node2D = load("res://scripts/world_view.gd").new()
	view.atlas = Atlas.new()
	view.sim = Sim.new(b, Content.with_all_art(), {"seed": 7, "province": "parthia"})
	view._paint_drifts()
	var palm: Array = view.atlas.prop_frame("palm")
	var foot: Vector2i = view._trunk_feet.palm
	var drift: Array = view._drifts.get("palm", [[null, Vector2.ZERO]])[0]
	var round_foot: bool = drift[0] != null and drift[1].x < foot.x and drift[1].x + drift[0].get_width() > foot.y + 1 \
		and drift[1].y <= palm[1].y and drift[1].y + drift[0].get_height() > palm[1].y + 1
	check(round_foot, "a palm on Parthia's sand stands in a drift wider than its trunk, round its foot")
	view.sim = Sim.new(b, Content.with_all_art(), {"seed": 7, "province": "germania"})
	view._paint_drifts()
	check(view._drifts.is_empty(), "trees on Germania's grass stand in no drift")
	view.free()


func test_the_bosses_are_drawn_big(_b: Dictionary) -> void:
	var atlas := Atlas.new()
	for type in ["berserker", "war_band_leader", "war_priest"]:
		var h: int = atlas.units[type].idle.south.frames[0][3]
		check(h >= 64, "%s stands at least 64 px tall (%d)" % [type, h])
	var ch: int = atlas.units.chieftain.idle.south.frames[0][3]
	check(ch >= 96, "the chieftain stands at least 96 px tall (%d)" % ch)


func test_bosses_are_much_tougher(_b: Dictionary) -> void:
	var e: Dictionary = content.enemies
	check(float(e.chieftain.hp) >= 23000.0 and float(e.chieftain.hp) <= 25000.0, "the chieftain has 23000 to 25000 health (%d)" % int(e.chieftain.hp))
	for id in e:
		if e[id].get("elite", false):
			check(float(e[id].hp) >= 1800.0 and float(e[id].hp) <= 3500.0, "every elite has 1800 to 3500 health, many times an ordinary's (%s %d)" % [id, int(e[id].hp)])
			check(float(e[id].hp) >= float(e.barbarian_club.hp) * 40.0, "and over forty times a clubman's (%s)" % id)
		if e[id].get("chieftain", false):
			check(float(e[id].hp) >= 23000.0, "every chieftain has at least 23000 health (%s %d)" % [id, int(e[id].hp)])


func test_elites_grow_tougher_through_the_run(b: Dictionary) -> void:
	var s := _quiet_sim(b, 700, Content.with_all_art())
	s.horde.time = 1200.0
	var late := s.horde.spawn("berserker", Vector2(-300, 0), true)
	var ratio := s.horde.e_max[late] / float(content.enemies.berserker.hp) / s.horde.level_mult("health_mult")
	check(absf(ratio - (1.0 + float(b.bosses.health_growth) * 1200.0)) < 0.01 and ratio > 1.9, "an elite at 20 minutes has about twice his listed health (%.2f)" % ratio)


func _boss_count(s: Sim) -> int:
	var n := 0
	for t in s.horde.e_tag:
		if t == Horde.ELITE:
			n += 1
	return n


func test_bosses_arrive_on_their_own_timer(b: Dictionary) -> void:
	var cfg: Dictionary = b.bosses
	var s := _quiet_sim(b, 701, Content.with_all_art())
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	s.horde.next_boss = float(cfg.first)
	s.time = float(cfg.first) - 0.5
	_step_dt(s, 1.0)
	check(_boss_count(s) == int(cfg.count_start), "the first boss arrives at %d s (%d)" % [int(cfg.first), _boss_count(s)])
	check(is_equal_approx(s.horde.next_boss, float(cfg.first) + float(cfg.every)), "the next comes %d s later" % int(cfg.every))
	var late_t := maxf((float(cfg.count_max) - float(cfg.count_start)) / float(cfg.count_growth), (float(cfg.max_alive) - float(cfg.max_alive_start)) / float(cfg.max_alive_growth)) + 1.0
	var late := _quiet_sim(b, 702, Content.with_all_art())
	late.time = late_t
	late.horde.time = late_t
	late.horde._boss_arrival(late)
	check(_boss_count(late) == int(cfg.count_max), "late in the run %d come at once (%d)" % [int(cfg.count_max), _boss_count(late)])
	var kinds := {}
	for k in late.horde.e_kind:
		kinds[late.horde.kind_ids[k]] = true
	for id in kinds:
		check(late.horde.elites.has(id), "%s is one of the province's elites" % id)
	var full := _quiet_sim(b, 703, Content.with_all_art())
	full.horde.time = late_t
	for k in 3:
		full.horde._boss_arrival(full)
	check(_boss_count(full) == int(cfg.max_alive), "no more than %d bosses at once (%d)" % [int(cfg.max_alive), _boss_count(full)])
	var surge := _quiet_sim(b, 704, Content.with_all_art())
	surge.horde.next_surge = 120.0
	surge.time = 119.9
	_step_dt(surge, 0.5)
	check(_boss_count(surge) == 0 and surge.horde.e_pos.size() > 0, "a surge brings barbarians but no boss")


func test_the_horde_is_a_quarter_thinner(b: Dictionary) -> void:
	check(is_equal_approx(float(b.spawn_per_second_start), 0.88) and is_equal_approx(float(b.spawn_per_second_growth), 0.0176), "the stream is trimmed by an eighth, leaving the bosses the main threat")
	check(int(b.surge_size_start) == 8 and is_equal_approx(float(b.surge_size_growth), 0.035), "so are the surges, softer still")
	check(int(b.war_band.size_start) == 6 and is_equal_approx(float(b.war_band.size_growth), 0.0176), "and the war bands' growth")


func _boss_sim(b: Dictionary, seed_value: int, kind: String, at: Vector2) -> Array:
	var s := _chief_sim(b, seed_value)
	var i := s.horde.spawn(kind, at, true)
	s._rebuild_grids()
	var st: Dictionary = s.horde.boss_state(i)
	for key in st:
		if str(key).ends_with("_cd"):
			st[key] = 1e9
	return [s, i, st]


func test_the_berserker_whirls_after_a_red_ring(b: Dictionary) -> void:
	var cfg: Dictionary = content.enemies.berserker.whirlwind
	var r := float(cfg.radius)
	var at := Vector2(200, 0)
	var made := _boss_sim(b, 710, "berserker", at)
	var s: Sim = made[0]
	var st: Dictionary = made[2]
	var near: Dictionary = s.soldiers[0]
	var far: Dictionary = s.soldiers[1]
	s.commander.pos = Vector2(-300, 0)
	for so in s.soldiers:
		so.pos = Vector2(-300, 40)
	near.pos = at + Vector2(r - 8.0, 0)
	far.pos = at + Vector2(r + 30.0, 0)
	near.max_hp = 1e6
	near.hp = 1e6
	far.max_hp = 1e6
	far.hp = 1e6
	st.whirl_cd = 0.0
	s._rebuild_grids()
	s.horde._bosses(1.0 / 60.0, s)
	var ring := false
	for l in s.horde.foe_lobs:
		ring = ring or (l.get("slam", false) and l.to == s.horde.e_pos[made[1]] and is_equal_approx(l.radius, r))
	check(ring, "a red ring of %d px fills round the berserker" % int(r))
	check(near.hp == 1e6, "nobody is hurt while it fills")
	for l in s.horde.foe_lobs:
		l.t = l.dur
	s.horde._foe_lobs(0.01, s)
	var want := float(content.enemies.berserker.dps) * float(cfg.damage_mult) * s.horde.e_power[made[1]]
	check(is_equal_approx(1e6 - near.hp, want), "then his whirl hits a Roman inside it hard (%.0f)" % (1e6 - near.hp))
	check(far.hp == 1e6, "and misses a Roman outside it")


func test_the_testudo_turns_the_elites_marked_blows(b: Dictionary) -> void:
	var made := _boss_sim(b, 712, "berserker", Vector2(200, 0))
	var s: Sim = made[0]
	var st: Dictionary = made[2]
	var near: Dictionary = s.soldiers[0]
	near.pos = s.horde.e_pos[made[1]] + Vector2(10, 0)
	near.hp = 1e6
	near.max_hp = 1e6
	s.objectives.notice = {}
	st.whirl_cd = 0.0
	s._rebuild_grids()
	s.horde._bosses(1.0 / 60.0, s)
	check(s.objectives.notice.get("kind", "") == "testudo", "the berserker's red ring brings a notice to raise the testudo")
	check(Hud.notice_line("testudo", s) == TranslationServer.translate("Raise the testudo!"), "which says so")
	s.testudo_left = 1.0
	for l in s.horde.foe_lobs:
		l.t = l.dur
	s.horde._foe_lobs(0.01, s)
	check(near.hp == 1e6, "under the testudo his whirl does no harm")
	var druid := _boss_sim(b, 713, "druid", Vector2(100, 0))
	var ds: Sim = druid[0]
	ds.horde.sky_fire(druid[1], content.enemies.druid.sky_fire, ds)
	ds.testudo_left = 1.0
	var before: float = ds.commander.hp
	for l in ds.horde.foe_lobs:
		l.t = l.dur
	ds.horde._foe_lobs(0.01, ds)
	check(ds.commander.hp == before, "nor does a druid's fire from the sky")


func test_the_berserker_rages_when_wounded(b: Dictionary) -> void:
	var made := _boss_sim(b, 711, "berserker", Vector2(300, 0))
	var s: Sim = made[0]
	var i: int = made[1]
	s.horde._bosses(1.0 / 60.0, s)
	check(s.horde.e_fury[i] == 1.0, "at full health he is calm")
	s.horde.e_hp[i] = s.horde.e_max[i] * 0.49
	s.horde._bosses(1.0 / 60.0, s)
	check(is_equal_approx(s.horde.e_fury[i], float(content.enemies.berserker.rage.mult)), "below half health he rages")
	s.commander.pos = Vector2.ZERO
	var p0: Vector2 = s.horde.e_pos[i]
	s.horde.e_cd[i] = 1e9
	s._rebuild_grids()
	s.horde._move(0.1, s)
	var moved := (s.horde.e_pos[i] - p0).length()
	check(moved > float(content.enemies.berserker.speed) * float(b.enemy_speed_mult) * 0.1 * 1.15, "and runs faster (%.1f px)" % moved)


func test_the_war_band_leader_raises_his_shield(b: Dictionary) -> void:
	var cfg: Dictionary = content.enemies.war_band_leader.shield_wall
	var made := _boss_sim(b, 712, "war_band_leader", Vector2(120, 0))
	var s: Sim = made[0]
	var i: int = made[1]
	var st: Dictionary = made[2]
	s.commander.pos = Vector2.ZERO
	st.shield_cd = 0.0
	s._rebuild_grids()
	s.horde._bosses(1.0 / 60.0, s)
	check(st.shield > 0.0, "he raises his shield")
	check(st.shield_dir.dot(Vector2.LEFT) > 0.99, "towards the legion")
	var hp0: float = s.horde.e_hp[i]
	s.hit(i, 100.0, 0.0, "", Vector2(60, 0))
	var front: float = hp0 - s.horde.e_hp[i]
	check(is_equal_approx(front, 100.0 * (1.0 - float(cfg.cut))), "a blow from in front does a fifth (%.0f)" % front)
	hp0 = s.horde.e_hp[i]
	s.hit(i, 100.0, 0.0, "", Vector2(180, 0))
	check(is_equal_approx(hp0 - s.horde.e_hp[i], 100.0), "a blow from behind does full harm")
	hp0 = s.horde.e_hp[i]
	s.hit(i, 100.0, 0.0, "", Vector2(120, 60))
	check(is_equal_approx(hp0 - s.horde.e_hp[i], 100.0), "a blow from the side does full harm")
	hp0 = s.horde.e_hp[i]
	s.hit(i, 100.0, 0.0, "onager")
	check(is_equal_approx(hp0 - s.horde.e_hp[i], 100.0), "a stone falling from above does full harm")
	st.shield = 0.0
	hp0 = s.horde.e_hp[i]
	s.hit(i, 100.0, 0.0, "", Vector2(60, 0))
	check(is_equal_approx(hp0 - s.horde.e_hp[i], 100.0), "with the shield down a blow from in front does full harm")


func test_a_shot_from_the_front_hits_his_shield(b: Dictionary) -> void:
	var made := _boss_sim(b, 713, "war_band_leader", Vector2(120, 0))
	var s: Sim = made[0]
	var i: int = made[1]
	made[2].shield = 3.0
	made[2].shield_dir = Vector2.LEFT
	s._rebuild_grids()
	var hp0: float = s.horde.e_hp[i]
	s.shoot("arrow", Vector2(80, 0), Vector2(120, 0), 300.0, 50.0, 0)
	s._move_shots(0.1)
	check(is_equal_approx(hp0 - s.horde.e_hp[i], 50.0 * (1.0 - float(content.enemies.war_band_leader.shield_wall.cut))), "an arrow from in front is mostly stopped (%.0f)" % (hp0 - s.horde.e_hp[i]))


func test_the_war_band_leader_calls_his_band(b: Dictionary) -> void:
	var made := _boss_sim(b, 714, "war_band_leader", Vector2(250, 0))
	var s: Sim = made[0]
	var before := s.horde.e_pos.size()
	made[2].band_cd = 0.0
	s.horde._bosses(1.0 / 60.0, s)
	var n := s.horde.e_pos.size() - before
	var want := int(float(b.war_band.size_start) * float(content.enemies.war_band_leader.call_band.size_mult))
	check(n == want, "a band of %d arrives (%d)" % [want, n])
	# His band gathers round him, but steps in from beyond the edge of the screen rather than appearing in view.
	var round_him := true
	var view := Rect2(s.commander.pos - Ui.view / 2.0, Ui.view)
	for k in range(before, s.horde.e_pos.size()):
		var q: Vector2 = s.horde.e_pos[k]
		round_him = round_him and not view.has_point(q) and (q - s.commander.pos).dot(Vector2(250, 0) - s.commander.pos) > 0.0
	check(round_him, "round him, from off the screen on his side")
	check(made[2].band_cd > 0.0, "and he waits before calling again")


func test_the_war_priest_mends_those_round_him(b: Dictionary) -> void:
	var cfg: Dictionary = content.enemies.war_priest.mend
	var made := _boss_sim(b, 715, "war_priest", Vector2(300, 0))
	var s: Sim = made[0]
	var i: int = made[1]
	var near := s.horde.spawn("berserker", Vector2(300 + float(cfg.radius) - 20.0, 0), true)
	var club := s.horde.spawn("barbarian_club", Vector2(300, 30))
	var far := s.horde.spawn("barbarian_club", Vector2(300 + float(cfg.radius) + 60.0, 0))
	for j in [i, near, club, far]:
		s.horde.e_hp[j] = s.horde.e_max[j] * 0.5
	made[2].mend_cd = 0.0
	s.horde._bosses(1.0 / 60.0, s)
	var green := false
	for m in s.horde.marks:
		green = green or (m.kind == "mend" and is_equal_approx(m.radius, float(cfg.radius)))
	check(green, "a green ring of %d px shows round him" % int(cfg.radius))
	check(s.horde.e_hp[near] == s.horde.e_max[near] * 0.5, "nobody is healed while it fills")
	s.horde._marks(float(cfg.windup) + 0.01, s)
	var share := float(cfg.share)
	check(is_equal_approx(s.horde.e_hp[near], s.horde.e_max[near] * (0.5 + share)), "a boss near him gets back a fifth of his health")
	check(is_equal_approx(s.horde.e_hp[club], s.horde.e_max[club] * (0.5 + share)), "so does a barbarian near him")
	check(is_equal_approx(s.horde.e_hp[far], s.horde.e_max[far] * 0.5), "a barbarian far off is not healed")
	check(is_equal_approx(s.horde.e_hp[i], s.horde.e_max[i] * 0.5), "he does not heal himself")


func test_the_war_priest_curses_the_legion(b: Dictionary) -> void:
	var cfg: Dictionary = content.enemies.war_priest.curse
	for stay in [true, false]:
		var made := _boss_sim(b, 716, "war_priest", Vector2(150, 0))
		var s: Sim = made[0]
		s.commander.pos = Vector2.ZERO
		var plain := s.speed()
		made[2].curse_cd = 0.0
		s.horde._bosses(1.0 / 60.0, s)
		var mark := {}
		for m in s.horde.marks:
			if m.kind == "curse":
				mark = m
		check(not mark.is_empty() and mark.get("pos", Vector2.INF) == Vector2.ZERO, "a purple mark appears under the commander")
		if not stay:
			s.commander.pos = Vector2(0, float(cfg.radius) + 20.0)
		s.horde._marks(float(cfg.windup) + 0.01, s)
		if stay:
			check(is_equal_approx(s.speed(), plain * (1.0 - float(cfg.slow))), "a commander still in it marches %d%% slower" % int(float(cfg.slow) * 100.0))
			s.horde._bosses(float(cfg.seconds) + 0.1, s)
			check(is_equal_approx(s.speed(), plain), "until the curse wears off")
		else:
			check(is_equal_approx(s.speed(), plain), "a commander who stepped out is not slowed")


func test_the_war_priest_blinks_away(b: Dictionary) -> void:
	var cfg: Dictionary = content.enemies.war_priest.blink
	var made := _boss_sim(b, 717, "war_priest", Vector2(200, 0))
	var s: Sim = made[0]
	var i: int = made[1]
	s.commander.pos = Vector2(-200, 0)
	for so in s.soldiers:
		so.pos = Vector2(-200, 20)
	made[2].blink_cd = 0.0
	s._rebuild_grids()
	s.horde._bosses(1.0 / 60.0, s)
	check(s.horde.e_pos[i] == Vector2(200, 0), "he stays while nobody is close")
	s.soldiers[0].pos = Vector2(200 - float(content.enemies.war_priest.radius) - float(cfg.near) + 10.0, 0)
	s.horde._bosses(1.0 / 60.0, s)
	var gone := s.horde.e_pos[i].distance_to(Vector2(200, 0))
	check(gone > float(cfg.distance) * 0.8, "a soldier close by makes him vanish %.0f px away" % gone)
	check(s.horde.e_pos[i].distance_to(s.commander.pos) > Vector2(200, 0).distance_to(s.commander.pos), "away from the legion")
	var smoke := 0
	for e in s.effects:
		if e.kind == "smoke":
			smoke += 1
	check(smoke == 2, "in a puff of smoke where he was and where he comes out")
	var then := s.horde.e_pos[i]
	s.soldiers[0].pos = then + Vector2(-20, 0)
	s.horde._bosses(1.0 / 60.0, s)
	check(s.horde.e_pos[i] == then, "he cannot blink again at once")


func test_the_chieftain_rages_in_his_second_phase(b: Dictionary) -> void:
	var cfg: Dictionary = content.enemies.chieftain.fury
	var s := _chief_sim(b, 718)
	s.facing_angle = 0.0
	var ci := s.horde.spawn("chieftain", Vector2(300, 0))
	s.horde.horn_cd = 10.0
	s.horde._chieftain(1.0, s)
	check(is_equal_approx(s.horde.horn_cd, 9.0) and not s.horde.chief_fury, "above half health his attacks come at their pace")
	s.horde.e_hp[ci] = s.horde.e_max[ci] * 0.49
	s.horde._chieftain(1.0 / 60.0, s)
	check(s.horde.chief_fury, "below half health he roars")
	check(s.shake >= float(b.shake.roar), "the screen shakes")
	check(s.objectives.notice.get("kind", "") == "roar", "and a notice says so")
	s.horde.horn_cd = 10.0
	s.horde._chieftain(1.0, s)
	check(is_equal_approx(s.horde.horn_cd, 10.0 - float(cfg.rate_mult)), "then his attacks come %d%% faster" % roundi((float(cfg.rate_mult) - 1.0) * 100.0))
	var before := s.horde.e_pos.size()
	s.horde.horn_cd = 0.0
	s.horde._chieftain(1.0 / 60.0, s)
	var n := s.horde.e_pos.size() - before
	check(n == int(b.war_band.size_start) * int(cfg.bands), "and his horn calls %d bands (%d)" % [int(cfg.bands), n])


func test_early_bosses_come_weaker(b: Dictionary) -> void:
	var cfg: Dictionary = b.bosses
	var s := _quiet_sim(b, 720, Content.with_all_art())
	s.horde.time = 0.0
	var first := s.horde.spawn("berserker", Vector2(300, 0), true)
	s.horde.time = float(cfg.early_until)
	var full := s.horde.spawn("berserker", Vector2(-300, 0), true)
	s.horde.time = float(cfg.early_health_until)
	var hale := s.horde.spawn("berserker", Vector2(0, -300), true)
	var grown := 1.0 + float(cfg.health_growth) * float(cfg.early_health_until)
	check(is_equal_approx(s.horde.e_max[first] / s.horde.e_max[hale], float(cfg.early_health) / grown), "a boss at the start has %d%% of the health of one at %d s" % [int(float(cfg.early_health) * 100.0), int(cfg.early_health_until)])
	var lvl := s.horde.level_mult("damage_mult")
	check(is_equal_approx(s.horde.e_power[first], float(cfg.early_mult) * lvl) and is_equal_approx(s.horde.e_power[full], lvl), "and hits that much softer")
	var club := s.horde.spawn("barbarian_club", Vector2(0, 300))
	check(is_equal_approx(s.horde.e_power[club], lvl), "an ordinary barbarian is not changed")
	s.horde.e_hp[first] = 1.0
	s.horde._bosses(1.0 / 60.0, s)
	check(is_equal_approx(s.horde.e_power[first], float(cfg.early_mult) * lvl * float(content.enemies.berserker.rage.mult)), "his rage builds on it")


func test_bosses_at_full_strength_wound_a_legionary_and_chieftains_cut_one_down(b: Dictionary) -> void:
	var qm: Dictionary = content.quartermaster
	var two_thirds := func(id: String) -> float: return roundi(int(qm[id].ranks) * 2.0 / 3.0) * float(qm[id].per_rank)
	var s := _quiet_sim(b, 723, Content.with_all_art())
	var hp: float = s.legion.max_hp_of("legionary") * (1.0 + two_thirds.call("soldier_health")) / (1.0 - two_thirds.call("armour"))
	s.horde.time = float(b.bosses.early_until)
	check(s.horde.early_boss_mult() == 1.0, "by %d s bosses hit at full strength" % int(b.bosses.early_until))
	check(float(b.bosses.early_until) <= 180.0, "which is no later than three minutes in")
	var bare := s.legion.max_hp_of("legionary")
	for province in content.provinces:
		var power := float(b.difficulty.get(province, {}).get("elites", 1.0))
		for id in content.provinces[province].elites:
			var info: Dictionary = content.enemies[id]
			for key in ["whirlwind", "onrush", "wedge", "trample", "scythe"]:
				if info.has(key):
					check(float(info.dps) * float(info[key].damage_mult) * power < bare, "one %s's %s wounds a fresh legionary but leaves him standing (%.0f against %.0f)" % [id, key, float(info.dps) * float(info[key].damage_mult) * power, bare])
			for key in ["lob", "sky_fire", "blast"]:
				if info.has(key):
					check(float(info[key].damage) * power < bare, "and so does a %s's %s" % [id, key])
	var whirl := float(content.enemies.berserker.dps) * float(content.enemies.berserker.whirlwind.damage_mult)
	check(whirl >= bare * 0.4, "a berserker's whirl still takes a good part of a legionary's health (%.0f of %.0f)" % [whirl, bare])
	for id in ["chieftain", "gaul_king"]:
		var info: Dictionary = content.enemies[id]
		var atk: Dictionary = info.attacks
		check(float(info.dps) * float(atk.cleave.damage_mult) >= hp, "%s's cleave fells one" % id)
		check(float(info.dps) * float(atk.charge.burst_mult) >= hp, "and so does his charge")
		if atk.has("slam"):
			check(float(info.dps) * float(atk.slam.damage_mult) >= hp, "and his slam")


## 30 legionaries and 8 archers with no upgrades march at one elite spawned 90 px ahead `at` seconds into the run, the testudo raised
## whenever a blow is marked and `testudo` is set; returns whether he fell, how long it took and how many soldiers he cost.
func _elite_fight(b: Dictionary, province: String, kind: String, at: float, testudo: bool, most := 45.0) -> Dictionary:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 1, "province": province})
	s.terrain.clear()
	s.b = b.duplicate()
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	s.b.pursuit = {}
	s.horde.next_surge = 1e9
	s.horde.next_band = 1e9
	s.horde.next_cart = 1e9
	s.horde.next_boss = 1e9
	s.time = at
	s.horde.time = at
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	s.soldiers.clear()
	for k in 30:
		s.add_soldier("legionary")
	for k in 8:
		s.add_soldier("archer")
	s.legion.place_all(s.facing_angle)
	var id := s.horde.e_id[s.horde.spawn(kind, s.commander.pos + Vector2.from_angle(s.facing_angle) * 90.0, true)]
	var dt := 1.0 / 30.0
	var t := 0.0
	while t < most and s.horde.e_id.has(id):
		var to: Vector2 = s.horde.e_pos[s.horde.e_id.find(id)] - s.commander.pos
		s.update(dt, to.normalized() if to.length() > 20.0 else Vector2.ZERO, testudo and s.testudo_charge >= 1.0 and _blow_marked(s))
		t += dt
	return {"fell": not s.horde.e_id.has(id), "seconds": t, "lost": 38 - s.soldiers.size()}


func _blow_marked(s: Sim) -> bool:
	if not s.horde.foe_lobs.is_empty() or not s.horde.marks.is_empty():
		return true
	for id in s.horde.boss:
		if float(s.horde.boss[id].rush_warn) > 0.0:
			return true
	return false


func test_a_legion_that_engages_an_elite_beats_him_soon(b: Dictionary) -> void:
	var total_shielded := 0
	var total_bare := 0
	for province in content.provinces:
		for kind in content.provinces[province].elites:
			var shielded := _elite_fight(b, province, kind, 600.0, true)
			check(shielded.fell and shielded.seconds <= 32.0, "30 legionaries and 8 archers cut down a %s at 10 minutes within about 30 s (%s, %.0f s)" % [kind, "fell" if shielded.fell else "alive", shielded.seconds])
			check(int(shielded.lost) <= 5, "and under the testudo he costs them at most 5 men (%s %d)" % [kind, int(shielded.lost)])
			var info: Dictionary = content.enemies[kind]
			if ["whirlwind", "lob", "sky_fire", "onrush", "wedge", "trample", "scythe"].any(func(key: String) -> bool: return info.has(key)):
				var bare := _elite_fight(b, province, kind, 600.0, false)
				total_shielded += int(shielded.lost)
				total_bare += int(bare.lost)
				check(bare.fell and int(bare.lost) <= 15, "without it he still falls and takes no more than 15 (%s %s, %d)" % [kind, "fell" if bare.fell else "alive", int(bare.lost)])
	check(total_bare > total_shielded + 5, "the testudo saves men against the elites' big blows (%d lost without, %d with)" % [total_bare, total_shielded])


func test_elites_at_ten_minutes_are_not_much_tougher_than_at_five(b: Dictionary) -> void:
	var s := _quiet_sim(b, 724, Content.with_all_art())
	s.horde.time = 300.0
	var five := s.horde.spawn("berserker", Vector2(300, 0), true)
	s.horde.time = 600.0
	var ten := s.horde.spawn("berserker", Vector2(-300, 0), true)
	var ratio := s.horde.e_max[ten] / s.horde.e_max[five]
	check(ratio <= 1.6, "an elite at 10 minutes has at most 1.6 times the health of one at 5 (%.2f)" % ratio)


func test_few_bosses_at_once_early_on(b: Dictionary) -> void:
	var cfg: Dictionary = b.bosses
	var s := _quiet_sim(b, 721, Content.with_all_art())
	s.horde.time = 60.0
	for k in 3:
		s.horde._boss_arrival(s)
	check(_boss_count(s) == int(cfg.max_alive_start), "early on only %d boss is on the field at once (%d)" % [int(cfg.max_alive_start), _boss_count(s)])


func test_early_bosses_act_less_often(b: Dictionary) -> void:
	var cfg: Dictionary = b.bosses
	var made := _boss_sim(b, 722, "war_priest", Vector2(400, 0))
	var s: Sim = made[0]
	var st: Dictionary = made[2]
	s.horde.time = 0.0
	st.mend_cd = 10.0
	s.horde._bosses(1.0, s)
	check(is_equal_approx(st.mend_cd, 10.0 - float(cfg.early_pace)), "at the start his timers run at %d%% pace (%.2f)" % [int(float(cfg.early_pace) * 100.0), st.mend_cd])
	s.horde.time = float(cfg.early_until)
	st.mend_cd = 10.0
	s.horde._bosses(1.0, s)
	check(is_equal_approx(st.mend_cd, 9.0), "and at full pace later")
	s.horde.time = 0.0
	var wait := s.horde._lob_at_ranks(made[1], s)
	check(is_equal_approx(wait, float(content.enemies.war_priest.lob.every) / float(cfg.early_pace)), "his pots come less often early on (%.1f s)" % wait)


## A straight gorge from x0 to x1 along the line y, `half` px either side of its middle, laid on the run's field.
func _gorge(s: Sim, x0: float, x1: float, y: float, half: float) -> void:
	var pts := PackedVector2Array()
	var halves := PackedFloat32Array()
	var x := x0
	while x <= x1 + 0.01:
		pts.append(Vector2(x, y))
		halves.append(half)
		x += 20.0
	s.terrain.add_ravine([{"pts": pts, "half": halves}])
	s.terrain.refresh(s.commander.pos)
	s.terrain.update_flow(s.commander.pos)


func test_ravines_wind_across_the_field_in_long_wide_gorges(b: Dictionary) -> void:
	var cfg: Dictionary = b.ravines
	var found := 0
	var land_bridges := 0
	var sizes_ok := true
	var lengths_ok := true
	var bridge_ok := true
	for k in 6:
		var t := Terrain.new(300 + k, b.forest, cfg)
		for rx in range(-2, 3):
			for ry in range(-2, 3):
				var rv: Dictionary = t.ravine(rx, ry)
				if rv.is_empty():
					continue
				found += 1
				var length := 0.0
				var widest := 0.0
				for piece in rv.pieces:
					var pts: PackedVector2Array = piece.pts
					# The three points at each end are the closing crack, not the gorge's own length.
					for i in range(3, pts.size() - 4):
						length += pts[i].distance_to(pts[i + 1])
					for h in piece.half:
						widest = maxf(widest, h * 2.0)
				sizes_ok = sizes_ok and widest >= float(cfg.width[0]) and widest <= float(cfg.width[1]) + 0.01
				lengths_ok = lengths_ok and length >= float(cfg.length[0]) * 0.7 and length <= float(cfg.length[1]) + 1.0
				if rv.pieces.size() == 2:
					land_bridges += 1
					var a: Dictionary = rv.pieces[0]
					var c: Dictionary = rv.pieces[1]
					var gap := INF
					for i in a.pts.size():
						for j in c.pts.size():
							gap = minf(gap, a.pts[i].distance_to(c.pts[j]) - a.half[i] - c.half[j])
					bridge_ok = bridge_ok and gap >= float(cfg.land_bridge[0]) - 1.0
	check(found >= 20, "ravines appear across the field (%d in six fields)" % found)
	check(sizes_ok, "each gorge is %d to %d px across at its widest" % [int(cfg.width[0]), int(cfg.width[1])])
	check(lengths_ok, "each runs one to two screens long")
	check(land_bridges >= 3, "some keep a natural land bridge partway (%d)" % land_bridges)
	check(bridge_ok, "and that land bridge is wide enough to march over")


func test_ravines_keep_apart_from_each_other_and_the_trees(b: Dictionary) -> void:
	var cfg: Dictionary = b.ravines
	var t := Terrain.new(41, b.forest, cfg)
	var area := Rect2(-3600, -3600, 7200, 7200)
	var list: Array = t.ravines_in(area)
	check(list.size() >= 4, "a large stretch holds several ravines (%d)" % list.size())
	var apart := true
	for i in list.size():
		for j in range(i + 1, list.size()):
			for pa in list[i].pieces:
				for p in pa.pts:
					apart = apart and t.edge_of(list[j], p) >= 2.0 * float(cfg.band)
	check(apart, "no two ravines come within two bands of each other, so a walkable strip runs right round each")
	var near := 0
	for pr in t.props_in(area):
		if pr[2] > 0.0 and t.ravine_edge(pr[1]) < float(cfg.band):
			near += 1
	check(near == 0, "no tree, rock or log stands in the band round a ravine (%d do)" % near)


func test_the_start_objectives_and_fort_stay_clear_of_ravines(b: Dictionary) -> void:
	var clear_start := true
	var clear_objectives := true
	var clear_fort := true
	for k in 20:
		var s := Sim.new(b, content, {"seed": 500 + k})
		clear_start = clear_start and s.terrain.ravine_edge(Vector2.ZERO) >= float(b.ravines.start_clear)
		for o in s.objectives.list:
			clear_objectives = clear_objectives and s.terrain.ravine_edge(o.pos) >= float(b.objectives.clearing)
		s.commander.pos = Vector2.from_angle(k * 0.7) * 1500.0
		s.objectives.raise_fort(s)
		clear_fort = clear_fort and s.terrain.ravine_edge(s.objectives.fort.centre) >= float(b.fort.clearing)
	check(clear_start, "no ravine comes near the start")
	check(clear_objectives, "no ravine cuts into an objective's clearing")
	check(clear_fort, "no ravine cuts into the fort's clearing")


## Whether a soldier can walk from the start to every objective and the fort without crossing a ravine, a rock or a wheat field, cutting through trees as the legion can.
func _reaches_everything(s: Sim) -> bool:
	var goals: Array = []
	for o in s.objectives.list:
		goals.append([o.pos, float(s.b.objectives.clearing) * 0.5])
	goals.append([s.objectives.fort.centre, float(s.objectives.fort.half) * 0.5])
	var box := Rect2(Vector2.ZERO, Vector2.ZERO)
	for g in goals:
		box = box.expand(g[0])
	box = box.grow(400.0)
	var cell := 24.0
	var nx := int(box.size.x / cell) + 1
	var ny := int(box.size.y / cell) + 1
	var blocked := PackedByteArray()
	blocked.resize(nx * ny)
	for rv in s.terrain.ravines_in(box):
		for piece in rv.pieces:
			var pts: PackedVector2Array = piece.pts
			for i in pts.size():
				var r: float = piece.half[i] + Sim.UNIT_RADIUS + 10.0
				for gx in range(maxi(0, floori((pts[i].x - r - box.position.x) / cell)), mini(nx, ceili((pts[i].x + r - box.position.x) / cell))):
					for gy in range(maxi(0, floori((pts[i].y - r - box.position.y) / cell)), mini(ny, ceili((pts[i].y + r - box.position.y) / cell))):
						var c := box.position + (Vector2(gx, gy) + Vector2(0.5, 0.5)) * cell
						if s.terrain.ravine_edge(c) < Sim.UNIT_RADIUS:
							blocked[gx + gy * nx] = 1
	for pr in s.terrain.props_in(box):
		if pr[2] <= 0.0 or Terrain.TREES.has(pr[0]):
			continue
		var r: float = pr[2] + Sim.UNIT_RADIUS
		for gx in range(maxi(0, floori((pr[1].x - r - box.position.x) / cell)), mini(nx, ceili((pr[1].x + r - box.position.x) / cell))):
			for gy in range(maxi(0, floori((pr[1].y - r - box.position.y) / cell)), mini(ny, ceili((pr[1].y + r - box.position.y) / cell))):
				if (box.position + (Vector2(gx, gy) + Vector2(0.5, 0.5)) * cell).distance_to(pr[1]) < r:
					blocked[gx + gy * nx] = 1
	if not s.terrain.field.is_empty():
		for rc in s.terrain.field_solids(s.terrain.fields_in(box)):
			var body := Rect2(rc.x, rc.y, rc.z - rc.x, rc.w - rc.y).grow(Sim.UNIT_RADIUS)
			for gx in range(maxi(0, floori((body.position.x - box.position.x) / cell)), mini(nx, ceili((body.end.x - box.position.x) / cell))):
				for gy in range(maxi(0, floori((body.position.y - box.position.y) / cell)), mini(ny, ceili((body.end.y - box.position.y) / cell))):
					if body.has_point(box.position + (Vector2(gx, gy) + Vector2(0.5, 0.5)) * cell):
						blocked[gx + gy * nx] = 1
	var seen := PackedByteArray()
	seen.resize(nx * ny)
	var start := floori(-box.position.x / cell) + floori(-box.position.y / cell) * nx
	var queue := PackedInt32Array([start])
	seen[start] = 1
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		for st in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var x: int = c % nx + st.x
			var y: int = c / nx + st.y
			if x < 0 or y < 0 or x >= nx or y >= ny or seen[x + y * nx] == 1 or blocked[x + y * nx] == 1:
				continue
			seen[x + y * nx] = 1
			queue.append(x + y * nx)
	for g in goals:
		var reached := false
		for i in queue:
			var p := box.position + (Vector2(i % nx, i / nx) + Vector2(0.5, 0.5)) * cell
			if p.distance_to(g[0]) < g[1]:
				reached = true
				break
		if not reached:
			return false
	return true


func test_the_legion_can_reach_every_objective_and_the_fort_past_the_ravines(b: Dictionary) -> void:
	var stuck: Array = []
	var ravines := 0
	for k in 30:
		var s := Sim.new(b, content, {"seed": 900 + k})
		s.objectives.raise_fort(s)
		ravines += s.terrain.ravines_in(Rect2(-2400, -2400, 4800, 4800)).size()
		if not _reaches_everything(s):
			stuck.append(900 + k)
	check(ravines >= 30, "the runs tried have ravines round their objectives (%d)" % ravines)
	check(stuck.is_empty(), "from the start the legion reaches every objective and the fort in every run (cut off in %s)" % str(stuck))


func test_the_legion_can_reach_every_objective_and_the_fort_past_the_wheat(b: Dictionary) -> void:
	var stuck: Array = []
	var fields := 0
	for k in 30:
		var s := Sim.new(b, content, {"seed": 930 + k, "province": "gaul"})
		s.objectives.raise_fort(s)
		fields += s.terrain.fields_in(Rect2(-2400, -2400, 4800, 4800)).size()
		if not _reaches_everything(s):
			stuck.append(930 + k)
	check(fields >= 60, "the Gaulish runs tried have wheat fields round their objectives (%d)" % fields)
	check(stuck.is_empty(), "from the start the legion reaches every objective and the fort past the fields in every Gaulish run (cut off in %s)" % str(stuck))


func test_the_legion_cannot_walk_into_a_ravine(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1500)
	Upgrades.apply(s, "legionary")
	_gorge(s, -400, 400, 100, 50)
	_step_dt(s, 4.0, Vector2.DOWN)
	check(s.commander.pos.y <= 50.0 - Sim.UNIT_RADIUS + 0.5, "the commander stops at the lip (%.1f)" % s.commander.pos.y)
	var dry := true
	for so in s.soldiers:
		dry = dry and s.terrain.ravine_edge(so.pos) >= Sim.UNIT_RADIUS - 0.5
	check(dry, "and no soldier stands over the drop")
	check(s.timber == 0 and s.terrain.chops.is_empty(), "nobody can fell a ravine")
	check(not s.terrain.is_open(Vector2(0, 100)), "the route map counts the gorge as closed")


func test_barbarians_go_round_a_ravine(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1501)
	_gorge(s, -160, 160, 100, 45)
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	for i in 8:
		s.horde.spawn("barbarian_spear", Vector2(-40 + i * 10, 220))
	var fell_in := false
	var reached := {}
	for f in 25 * 60:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		for i in s.horde.e_pos.size():
			fell_in = fell_in or s.terrain.ravine_edge(s.horde.e_pos[i]) < 0.0
			if s.horde.e_pos[i].y < 40.0:
				reached[s.horde.e_id[i]] = true
	var across := reached.size()
	check(not fell_in, "no barbarian walks into the gorge")
	check(across >= 6, "they find the way round its end to the legion (%d of 8)" % across)


func test_a_bridge_needs_timber_and_a_ravine_ahead(b: Dictionary) -> void:
	var cfg: Dictionary = b.bridge
	var s := _quiet_sim(b, 1502)
	_gorge(s, -400, 400, 100, 50)
	s.commander.pos = Vector2(0, -10)
	s.facing_angle = PI / 2.0
	s.legion.place_all(s.facing_angle)
	s.timber = int(cfg.cost) - 1
	s.events.clear()
	check(not s.build_bridge(), "with too little timber no bridge is laid")
	check(s.timber == int(cfg.cost) - 1 and s.terrain.bridges.is_empty(), "and nothing is spent")
	check(s.events.any(func(e: Dictionary) -> bool: return e.kind == "back"), "the refusal sounds")
	check(s.bridge_refused.get("why", "") == "timber", "and the notice says timber is short")
	s.timber = int(cfg.cost)
	check(s.build_bridge(), "with %d timber a bridge is laid" % int(cfg.cost))
	check(s.timber == 0 and s.terrain.bridges.size() == 1, "the timber is spent on one bridge")
	if s.terrain.bridges.size() == 1:
		var deck: Dictionary = s.terrain.bridges[0]
		var a: Vector2 = deck.pos - deck.dir * deck.half_len
		var z: Vector2 = deck.pos + deck.dir * deck.half_len
		check(minf(a.y, z.y) < 50.0 and maxf(a.y, z.y) > 150.0, "it spans the gorge in the legion's facing")
		check(deck.half_w * 2.0 >= float(cfg.width) - 0.01, "and is wide enough for the formation")
	s.facing_angle = -PI / 2.0
	s.timber = int(cfg.cost)
	s.events.clear()
	check(not s.build_bridge(), "facing away from the gorge, no bridge")
	check(s.timber == int(cfg.cost) and s.bridge_refused.get("why", "") == "ravine", "nothing is spent and the notice says there is no ravine ahead")


func test_the_bridge_hint_shows_at_a_lip_with_or_without_timber(b: Dictionary) -> void:
	var cost := int(b.bridge.cost)
	var s := _quiet_sim(b, 1510)
	_gorge(s, -400, 400, 100, 50)
	s.commander.pos = Vector2(0, -10)
	s.facing_angle = PI / 2.0
	s.legion.place_all(s.facing_angle)
	s.timber = 0
	_step_dt(s, 0.5)
	check(s.bridge_here, "the hint is up at the lip with no timber")
	var short := Hud.bridge_hint(3, cost)
	check(not short.enough and short.text.contains(str(cost)) and short.text.contains("3"), "without timber it gives the cost and the count (%s)" % short.text)
	var ready := Hud.bridge_hint(cost, cost)
	check(ready.enough and ready.text.contains(str(cost)) and ready.text != short.text, "with timber it gives the cost (%s)" % ready.text)
	check(short.text.begins_with(Controls.key_of("bridge")) and ready.text.begins_with(Controls.key_of("bridge")), "both lead with the key")


func test_the_ravine_tip_shows_once_a_run_when_a_ravine_comes_near(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1511)
	_gorge(s, -400, 400, 900, 50)
	_step_dt(s, 0.5)
	check(not s.ravine_near and not s.ravine_tip_shown, "a ravine far off gives no tip")
	s.commander.pos = Vector2(0, 760)
	s.legion.place_all(s.facing_angle)
	s.terrain.refresh(s.commander.pos)
	_step_dt(s, 0.5)
	check(s.ravine_near, "a ravine on screen is noticed")
	check(s.ravine_tip_shown and s.objectives.notice.get("kind", "") == "ravine", "and the tip is shown")
	s.objectives.notice = {}
	s.commander.pos = Vector2(0, 0)
	_step_dt(s, 0.5)
	s.commander.pos = Vector2(0, 760)
	_step_dt(s, 0.5)
	check(s.objectives.notice.is_empty(), "the tip is shown only once a run")
	var done := Sim.new(b, content, {"seed": 1512, "ravine_tip": false})
	done.terrain.clear()
	done.commander.pos = Vector2(0, 760)
	_gorge(done, -400, 400, 900, 50)
	_step_dt(done, 0.5)
	check(not done.ravine_tip_shown, "a player past the first runs gets no tip")


func test_the_profile_counts_the_runs_that_showed_the_ravine_tip(b: Dictionary) -> void:
	var p := _fresh_profile()
	var s := Sim.new(b, Content.with_all_art(), {"seed": 1513})
	s.over = true
	s.ravine_tip_shown = true
	p.record_run(s)
	check(int(p.data.totals.ravine_tips) == 1, "a run that showed the tip is counted")
	check(Profile.merge_saved({"totals": {"ravine_tips": 2}}).totals.ravine_tips == 2, "the count is read back")
	_cleanup_profile_files()


func test_a_legion_that_marches_without_fighting_is_hunted(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1520)
	s.commander.max_hp = 1e9
	s.commander.hp = 1e9
	_step_dt(s, 90.0, Vector2.RIGHT)
	check(s.horde.pursuit > 0.5, "marching on without a kill raises the pursuit (%.2f)" % s.horde.pursuit)
	var since := s.horde.next_id
	for k in 30 * 10:
		s.update(1.0 / 30.0, Vector2.RIGHT, false)
		if s.horde.next_id > since:
			break
	var ahead := 0
	var behind := 0
	for i in s.horde.e_pos.size():
		if s.horde.e_id[i] >= since:
			if s.horde.e_pos[i].x > s.commander.pos.x:
				ahead += 1
			else:
				behind += 1
	check(s.horde.e_pos.size() > 0 and ahead > behind, "and hunters come in ahead of its march (%d ahead, %d behind)" % [ahead, behind])
	var hunter := s.horde.e_bare.find(1)
	var coins := s.c_pos.size()
	var bare := s.horde.bare_kills
	if hunter >= 0:
		s._kill(hunter)
	check(hunter >= 0 and s.c_pos.size() == coins and s.horde.bare_kills == bare + 1, "a hunter carries no coins")


func test_a_legion_that_holds_and_fights_is_not_hunted_but_one_standing_idle_is(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1521)
	s.commander.max_hp = 1e9
	s.commander.hp = 1e9
	for k in 120 * 30:
		var back := 1.0 if (k / 60) % 2 == 0 else -1.0
		s.update(1.0 / 30.0, Vector2.RIGHT * 0.2 * back, false)
		if k % 15 == 0:
			s.kills += 1
	check(s.horde.pursuit < 0.05, "a legion stepping about as it kills is not hunted (%.2f)" % s.horde.pursuit)
	var still := _quiet_sim(b, 1522)
	still.commander.max_hp = 1e9
	still.commander.hp = 1e9
	_step_dt(still, 120.0)
	check(still.horde.pursuit > 0.5, "one that never moves is (%.2f)" % still.horde.pursuit)


func test_the_legion_marches_over_its_bridge(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1503)
	for k in 6:
		Upgrades.apply(s, "legionary" if k % 2 == 0 else "archer")
	_gorge(s, -600, 600, 100, 60)
	s.commander.pos = Vector2(0, -10)
	s.facing_angle = PI / 2.0
	s.legion.place_all(s.facing_angle)
	s.timber = int(b.bridge.cost)
	check(s.build_bridge(), "the bridge is laid")
	_step_dt(s, 6.0, Vector2.DOWN)
	check(s.commander.pos.y > 200.0, "the commander walks over it (%.0f)" % s.commander.pos.y)
	_step_dt(s, 4.0, Vector2.ZERO)
	var over := 0
	for so in s.soldiers:
		if so.pos.y > 160.0:
			over += 1
	check(over == s.soldiers.size(), "every soldier follows him across (%d of %d)" % [over, s.soldiers.size()])


func test_a_big_legion_files_over_a_bridge_without_being_shoved(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1505)
	while s.soldiers.size() < 40:
		s.legion.add(["legionary", "archer", "cavalry"][s.soldiers.size() % 3])
	_gorge(s, -600, 600, 100, 60)
	s.commander.pos = Vector2(0, 0)
	s.facing_angle = PI / 2.0
	s.legion.place_all(s.facing_angle)
	s.timber = int(b.bridge.cost)
	check(s.build_bridge(), "the bridge is laid")
	s.commander.pos = Vector2(0, -400)
	s.legion.place_all(s.facing_angle)
	s.terrain.refresh(s.commander.pos)
	var dt := 1.0 / 30.0
	var step := s.speed() * float(b.legion.follow_speed) * dt + 0.01
	var worst := 0.0
	var shoves := 0
	for k in 18 * 30:
		var before: Array = []
		for so in s.soldiers:
			before.append(so.pos)
		s.terrain.legion_shoves = 0
		s.update(dt, Vector2.DOWN, false)
		shoves += s.terrain.legion_shoves
		for i in s.soldiers.size():
			worst = maxf(worst, s.soldiers[i].pos.distance_to(before[i]))
	check(s.commander.pos.y > 500.0, "the legion of %d marches over (%.0f)" % [s.soldiers.size() + 1, s.commander.pos.y])
	check(shoves == 0, "and no man is pushed by the ravine or the bridge's sides (%d pushes)" % shoves)
	check(worst <= step, "and no man moves faster than he can march (%.2f px in one update, %.2f allowed)" % [worst, step])
	var past := 0
	for so in s.soldiers:
		if so.pos.y > 200.0:
			past += 1
	check(past == s.soldiers.size(), "every man is across (%d of %d)" % [past, s.soldiers.size()])


func test_the_column_ends_once_the_last_man_is_off_the_bridge(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1508)
	while s.soldiers.size() < 40:
		s.legion.add(["legionary", "archer", "cavalry"][s.soldiers.size() % 3])
	_gorge(s, -600, 600, 100, 60)
	s.commander.pos = Vector2(0, 0)
	s.facing_angle = PI / 2.0
	s.legion.place_all(s.facing_angle)
	s.timber = int(b.bridge.cost)
	check(s.build_bridge(), "the bridge is laid")
	var br: Dictionary = s.terrain.bridges[0]
	var far_end: float = br.pos.y + absf(br.dir.y) * float(br.half_len)
	s.commander.pos = Vector2(0, -400)
	s.legion.place_all(s.facing_angle)
	s.terrain.refresh(s.commander.pos)
	var dt := 1.0 / 30.0
	var cleared := -1.0
	var filing_after := 0.0
	for k in 30 * 30:
		s.update(dt, Vector2.DOWN, false)
		var all_off := true
		for so in s.soldiers:
			all_off = all_off and so.pos.y > far_end + Sim.UNIT_RADIUS
		if all_off and cleared < 0.0:
			cleared = k * dt
		if cleared >= 0.0 and not s.legion._column(s.legion.formation(), s).is_empty():
			filing_after = k * dt - cleared
	check(cleared >= 0.0, "every man gets off the deck")
	check(filing_after <= 0.5, "and the column breaks up as soon as the last man is off it (still filing %.1f s later)" % filing_after)


func test_the_legion_files_for_a_bridge_only_when_heading_onto_it(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1506)
	while s.soldiers.size() < 30:
		s.legion.add(["legionary", "archer"][s.soldiers.size() % 2])
	_gorge(s, -600, 600, 100, 60)
	s.commander.pos = Vector2(0, 0)
	s.facing_angle = PI / 2.0
	s.legion.place_all(s.facing_angle)
	s.timber = int(b.bridge.cost)
	check(s.build_bridge(), "the bridge is laid")
	var br: Dictionary = s.terrain.bridges[0]
	var near_end: Vector2 = br.pos - br.dir * float(br.half_len)
	var places: Array = s.legion.formation()
	var front := 0.0
	for p in places:
		front = maxf(front, p.x)
	var cases := [
		["walking past the end of the deck", near_end - br.dir * 60.0, 0.0, false],
		["walking along the ravine just short of the deck", near_end - br.dir * 20.0, PI, false],
		["heading for the deck from far off", near_end - br.dir * (front + 300.0), PI / 2.0, false],
		["heading away from the deck on the near side", near_end - br.dir * 60.0, -PI / 2.0, false],
		["heading for the deck close by", near_end - br.dir * (front + 20.0), PI / 2.0, true],
		["on the deck", br.pos, PI / 2.0, true]]
	for c in cases:
		s.commander.pos = c[1]
		s.facing_angle = c[2]
		var filed := not s.legion._column(places, s).is_empty()
		check(filed == c[3], "%s: %s" % [c[0], "files into a column" if filed else "keeps its formation"])
	s.commander.pos = br.pos + br.dir * (float(br.half_len) + 100.0)
	s.facing_angle = PI / 2.0
	check(not s.legion._column(places, s).is_empty(), "just across, the men still on the deck keep filing over")


func test_the_legion_files_for_the_fort_gate_only_when_heading_in(b: Dictionary) -> void:
	var s := _fort_sim(b, 1507)
	while s.soldiers.size() < 30:
		s.legion.add(["legionary", "archer"][s.soldiers.size() % 2])
	var fort: Dictionary = s.objectives.fort
	var gate: Vector2 = fort.pos
	var places: Array = s.legion.formation()
	var front := 0.0
	for p in places:
		front = maxf(front, p.x)
	var cases := [
		["fighting along the wall below the gate", gate + Vector2(0, 60), 0.0, false],
		["fighting with his back to the gate", gate + Vector2(0, 60), PI / 2.0, false],
		["heading for the gate from far off", gate + Vector2(0, front + 300.0), -PI / 2.0, false],
		["heading for the gate close by", gate + Vector2(0, front + 20.0), -PI / 2.0, true]]
	for c in cases:
		s.commander.pos = c[1]
		s.facing_angle = c[2]
		var filed := not s.legion._column(places, s).is_empty()
		check(filed == c[3], "%s: %s" % [c[0], "files into a column" if filed else "keeps its formation"])


func test_the_hud_points_to_the_chieftain_off_screen(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 1508})
	s.time = float(b.chieftain_at) - 0.01
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var ci := s.chieftain_index()
	check(ci >= 0, "the chieftain has come")
	s.horde.e_pos[ci] = s.commander.pos + Vector2(1500, 300)
	var targets := Hud.targets_of(s)
	var chief: Array = targets.filter(func(t: Array) -> bool: return t[0] == "chieftain")
	check(chief.size() == 1 and chief[0][1] == s.horde.e_pos[ci], "the HUD points to him")
	var view := Vector2(640, 360)
	var laid := Hud.arrow_layout(chief, s.commander.pos, view, 40.0)
	check(laid.size() == 1 and not laid[0].on_screen and laid[0].name == Hud.chief_name(s).to_upper(), "with a badge at the edge under his own name (%s)" % (laid[0].name if not laid.is_empty() else "none"))
	s.horde.e_pos[ci] = s.commander.pos + Vector2(60, 0)
	check(Hud.arrow_layout(Hud.targets_of(s).filter(func(t: Array) -> bool: return t[0] == "chieftain"), s.commander.pos, view, 40.0).is_empty(), "and no label when he is on screen, where his bar names him")
	s.hit(s.chieftain_index(), 1e9)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(not Hud.targets_of(s).any(func(t: Array) -> bool: return t[0] == "chieftain"), "once he falls the badge goes")


func test_barbarians_cross_a_bridge(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1504)
	_gorge(s, -1400, 1400, 100, 50)
	s.commander.pos = Vector2(0, -10)
	s.facing_angle = PI / 2.0
	s.legion.place_all(s.facing_angle)
	s.timber = int(b.bridge.cost)
	s.build_bridge()
	s.terrain.refresh(s.commander.pos)
	s.terrain.update_flow(s.commander.pos)
	check(s.terrain.is_open(Vector2(0, 100)), "the route map opens the bridge's deck")
	check(not s.terrain.is_open(Vector2(200, 100)), "but not the gorge beside it")
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	for i in 6:
		s.horde.spawn("barbarian_spear", Vector2(250 + i * 12, 230))
	var reached := {}
	for f in 20 * 60:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		for i in s.horde.e_pos.size():
			if s.horde.e_pos[i].y < 40.0:
				reached[s.horde.e_id[i]] = true
	var across := reached.size()
	check(across >= 4, "barbarians find the bridge and cross to the legion (%d of 6)" % across)


func test_neptune_throws_barbarians_into_a_ravine(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1505, Content.with_all_art())
	_gorge(s, -400, 400, 100, 50)
	s.commander.pos = Vector2(0, -10)
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	for i in 3:
		s.horde.spawn("barbarian_spear", Vector2(-20 + i * 20, 35))
	var beside := s.horde.e_id[s.horde.spawn("barbarian_spear", Vector2(-70, -10))]
	var kills := s.kills
	s.gods.invoke(s, "neptune")
	_step_dt(s, 1.5)
	check(s.kills - kills == 3, "the three thrown towards the gorge fall in (%d)" % (s.kills - kills))
	check(s.horde.e_pos.size() == 1 and s.horde.e_id[0] == beside, "the one thrown over open ground lives")
	check(s.c_pos.is_empty(), "nothing is dropped into the gorge")


func test_the_bridge_has_its_own_key_and_button(b: Dictionary) -> void:
	var names: Array = Controls.ACTIONS.map(func(a: Array) -> String: return a[0])
	check(names.has("bridge"), "the bridge is on the key page")
	check(Controls.KEYS.get("bridge", []) == [KEY_C], "it is on C by default")
	check(Controls.PADS.get("bridge", -1) == JOY_BUTTON_RIGHT_SHOULDER, "and the right shoulder button")
	var keys := {}
	var pads := {}
	var shared := false
	for a in ["up", "down", "left", "right", "testudo", "build", "pray", "pause", "bridge"]:
		for k in Controls.KEYS.get(a, []):
			shared = shared or keys.has(k)
			keys[k] = true
		if Controls.PADS.has(a):
			shared = shared or pads.has(Controls.PADS[a])
			pads[Controls.PADS[a]] = true
	check(not shared, "no key or button used while marching does two things")
	check(Controls.hint("bridge").contains(Controls.key_of("bridge")), "the bridge hint names its key")


func test_the_health_bar_keeps_clear_of_the_corners(b: Dictionary) -> void:
	var before := Ui.scale
	for scale in [1, 2]:
		Ui.set_text_size(scale, b)
		var view := Vector2(640, 360)
		var parts := Hud.bottom_layout(view)
		var bar: Rect2 = parts.health
		check(bar.size.x >= 160.0 and absf(bar.get_center().x - view.x / 2.0) < 1.0, "the health bar is big and centred at text size %d (%.0f px)" % [scale, bar.size.x])
		check(bar.end.y <= view.y and bar.position.y > view.y * 0.8, "and sits along the bottom")
		for key in parts:
			if key != "health":
				check(not bar.intersects(parts[key]), "it keeps clear of the %s at text size %d" % [key, scale])
	Ui.set_text_size(before, b)


func test_the_health_bar_flashes_and_reddens(b: Dictionary) -> void:
	check(Hud.health_colour(0.9, 10.0) != Hud.health_colour(0.9, 0.05), "it flashes just after a blow")
	check(Hud.health_colour(0.2, 10.0) == Hud.RED, "below a quarter it is red")
	check(Hud.health_colour(0.5, 10.0) != Hud.RED, "above it, not")


func test_the_arrows_are_badges_whose_labels_never_overlap(b: Dictionary) -> void:
	var before := Ui.scale
	var view := Vector2(640, 360)
	for scale in [1, 2]:
		Ui.set_text_size(scale, b)
		check(Hud.badge_radius() >= 12.0, "an arrow's badge is readable at text size %d" % scale)
		for k in 12:
			var a := k * TAU / 12.0
			var targets := [["camp", Vector2.from_angle(a) * 900.0], ["grove", Vector2.from_angle(a + 0.3) * 1200.0], ["column", Vector2.from_angle(a + 2.5) * 800.0], ["fort", Vector2.from_angle(a - 0.25) * 1000.0]]
			var laid: Array = Hud.arrow_layout(targets, Vector2.ZERO, view, 40.0)
			var boxes: Array = []
			for l in laid:
				boxes.append(l.badge)
				boxes.append(l.label)
			var clash := false
			for i in boxes.size():
				for j in range(i + 1, boxes.size()):
					clash = clash or boxes[i].intersects(boxes[j])
			var inside := true
			for r in boxes:
				inside = inside and Rect2(Vector2.ZERO, view).encloses(r)
			var bottom: Dictionary = Hud.bottom_layout(view)
			for r in boxes:
				for key in ["health", "testudo", "favour", "timber", "bridge"]:
					clash = clash or r.intersects(bottom[key])
			check(not clash, "badges and labels overlap neither each other nor the bottom of the screen (text size %d, turn %d)" % [scale, k])
			check(inside, "and stay on screen (text size %d, turn %d)" % [scale, k])
	Ui.set_text_size(before, b)


func _find(s: Sim, id: int) -> int:
	return s.horde.e_id.find(id)


func test_a_gods_burn_is_not_carried_on_by_a_later_fire(b: Dictionary) -> void:
	var share := float(b.gods.boss_share)
	for kind in ["berserker", "chieftain"]:
		for follow in ["fire_arrows", "torches", "scorch"]:
			var s := _god_sim(b, 1601, 0)
			s.soldiers.clear()
			# An elite who comes at ten minutes has his full health, so a small fire is a small share of it.
			s.horde.time = 600.0
			var i := s.horde.spawn(kind, Vector2(150, 0), kind != "chieftain")
			var id := s.horde.e_id[i]
			var max_hp: float = s.horde.e_max[i]
			s.horde.e_stun[i] = 1e9
			_fill_favour(s)
			s.gods.invoke(s, "vulcan")
			s.ignite(i, 5.0, 2.0, "torches")
			check(s.horde.e_burn_src[i] == s.src_id("vulcan"), "a smaller fire does not take over a god's burn (%s)" % kind)
			_step_dt(s, 10.0)
			i = _find(s, id)
			check(i >= 0 and s.horde.e_burn_dps[i] == 0.0 and s.horde.e_burn_src[i] == -1, "a burn that has gone out leaves nothing behind (%s)" % kind)
			if i < 0:
				continue
			var hp_after_god: float = s.horde.e_hp[i]
			match follow:
				"fire_arrows":
					s.hit(i, 1.0, 4.0, "archer")
				"torches":
					s.ignite(i, 5.0, 2.0, "torches")
				"scorch":
					s.scorch(i, 1.0, "fire_pots")
			_step_dt(s, 10.0)
			i = _find(s, id)
			check(i >= 0 and hp_after_god - s.horde.e_hp[i] < max_hp * 0.02, "a %s after Vulcan only does its own small harm to the %s" % [follow, kind])
			check(i >= 0 and s.horde.e_hp[i] >= max_hp * (1.0 - share) - 60.0, "and he keeps the health the god's cap left him")


func test_a_stunned_boss_uses_no_ability(b: Dictionary) -> void:
	var s := _chief_sim(b, 1602)
	var ci := s.horde.spawn("chieftain", s.commander.pos + Vector2(40, 0))
	var cid := s.horde.e_id[ci]
	s.horde.cleave_cd = 0.0
	s.horde.cry_cd = 0.0
	s.horde.charge_cd = 0.0
	s.horde.slam_cd = 0.0
	s.horde.horn_cd = 1e9
	var lobs := 0
	var warned := false
	var men := s.soldiers.size()
	for f in 120:
		ci = _find(s, cid)
		s.horde.e_stun[ci] = 5.0
		var n := s.horde.foe_lobs.size()
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		lobs += maxi(0, s.horde.foe_lobs.size() - n)
		warned = warned or s.horde.charge_warn > 0.0 or s.horde.charging
	check(lobs == 0 and not warned, "a stunned chieftain neither slams nor charges")
	check(s.soldiers.size() == men, "nor cleaves a soldier (%d of %d left)" % [s.soldiers.size(), men])
	var c := _chief_sim(b, 1603)
	var k := c.horde.spawn("chieftain", c.commander.pos + Vector2(200, 0))
	c.horde.e_dash[k] = 0.5
	c.horde.charging = true
	c.horde.e_stun[k] = 1.0
	_step_dt(c, 1.5)
	check(not c.horde.charging, "a charge cut short by a stun ends")
	var made := _boss_sim(b, 1604, "berserker", Vector2(30, 0))
	var bs: Sim = made[0]
	var st: Dictionary = made[2]
	st.whirl_cd = 0.0
	bs.horde.e_stun[made[1]] = 2.0
	bs.horde._bosses(1.0 / 60.0, bs)
	check(bs.horde.foe_lobs.is_empty(), "a stunned berserker does not whirl")
	var pm := _boss_sim(b, 1605, "war_priest", Vector2(120, 0))
	var ps: Sim = pm[0]
	var pst: Dictionary = pm[2]
	pst.mend_cd = 0.0
	pst.curse_cd = 0.0
	ps.horde.e_stun[pm[1]] = 2.0
	ps.horde._bosses(1.0 / 60.0, ps)
	check(ps.horde.marks.is_empty(), "a stunned war priest neither mends nor curses")


func test_the_pilum_keeps_a_seed_repeatable(b: Dictionary) -> void:
	var out: Array = []
	for global_seed in [1, 2]:
		seed(global_seed)
		var s := Sim.new(b, content, {"seed": 1606})
		s.commander.hp = 1e9
		s.commander.max_hp = 1e9
		for k in 12:
			s.add_soldier("legionary")
		s.ranks["pilum"] = 1
		while s.time < 60.0:
			s.update(1.0 / 30.0, Vector2(cos(s.time * 0.4), sin(s.time * 0.4)), false)
			s.pending_levels = 0
		out.append([s.kills, s.horde.e_pos.size(), Array(s.horde.e_hp)])
	check(out[0] == out[1], "the same seed plays the same run whatever the engine's own dice say")


func test_closing_the_gods_keeps_the_same_offer(b: Dictionary) -> void:
	var s := _god_sim(b, 1607, 0)
	_fill_favour(s)
	var first := Gods.offers(s)
	var state := s.rng.state
	check(Gods.offers(s) == first, "opening the gods again shows the same three")
	check(s.rng.state == state, "and draws nothing from the run's dice")
	var seen := {}
	for k in 20:
		s.gods.invoke(s, "apollo")
		_fill_favour(s)
		for id in Gods.offers(s):
			seen[id] = true
	check(seen.size() == 5, "each new fill draws afresh (%d gods seen)" % seen.size())


func test_a_man_brought_back_by_the_medicus_is_not_also_a_reserve(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1608, Content.with_all_art())
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	for k in 5:
		s.legion.pick("medicus")
	s.ranks["reserves"] = 1
	var before := s.soldiers.size()
	s.legion.revive_timer = float(b.legion.revive_interval) - 1.0
	s.soldiers[0].hp = 0.0
	s.legion.remove_fallen(s)
	_step_dt(s, 25.0)
	check(s.soldiers.size() == before, "one man falls and one comes back (%d of %d)" % [s.soldiers.size(), before])


func test_no_favour_while_vulcans_fire_or_neptunes_throw_is_at_work(b: Dictionary) -> void:
	var cfg: Dictionary = b.gods.vulcan
	var s := _god_sim(b, 1609, 0)
	s.gods.invoke(s, "vulcan")
	_step_dt(s, float(cfg.burn_seconds) + 0.5)
	check(s.gods.busy(), "Vulcan is still at work while his burning ground lasts")
	_step_dt(s, float(cfg.patch_life) + float(cfg.rain_seconds) + float(cfg.fall_seconds))
	check(not s.gods.busy(), "and done once it has burnt out")
	var n := _god_sim(b, 1610, 20)
	n.gods.invoke(n, "neptune")
	_step_dt(n, float(b.gods.neptune.wave_seconds) + 0.05)
	check(n.gods.busy(), "Neptune is still at work while the thrown are flying")


func test_nothing_slows_the_march_below_the_floor(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1611)
	var free := s.speed()
	s.pressing = 1000
	s.horde.curse_left = 5.0
	s.horde.curse_slow = 0.4
	s.testudo_left = 2.0
	check(s.speed() >= free * float(b.press.slowest) - 0.01, "a crowd, a curse and the testudo together keep the slowest share of the march (%.1f of %.1f)" % [s.speed(), free])


func test_an_endless_run_keeps_the_moment_it_was_won(b: Dictionary) -> void:
	var saved: Dictionary = Profile.data
	Profile.data = Profile.defaults()
	var s := Sim.new(b, Content.with_all_art(), {"seed": 1612, "endless": true})
	s.time = 1000.0
	s.horde.time = 1000.0
	s.objectives.raise_fort(s)
	s.win(s.commander.pos)
	check(s.objectives.targets().all(func(t: Array) -> bool: return t[0] != "fort"), "once won, the fort's arrow goes")
	s.events.clear()
	s.commander.pos = s.objectives.fort.centre
	for k in 300:
		s.objectives.update(1.0 / 60.0, s)
	check(not s.events.any(func(e: Dictionary) -> bool: return e.kind == "victory"), "and holding it does not win a second time")
	check(SummaryScreen.held_line(s) != TranslationServer.translate("Held out %s after the chieftain") % SummaryScreen.clock(s.endless_seconds()), "the summary does not say the chieftain fell while he lives")
	s.time = 1500.0
	s.over = true
	Profile.record_run(s)
	check(is_equal_approx(float(Profile.record_of(s.province).best_time), 1000.0), "the best time is when the run was won (%.0f)" % float(Profile.record_of(s.province).best_time))
	Profile.data = saved


func test_the_old_centurion_can_be_earned_in_a_run_that_ends_at_the_fort(b: Dictionary) -> void:
	var rule: Dictionary = content.commanders.old_centurion.unlock
	check(float(rule.seconds) <= float(b.chieftain_at), "the time to survive is reached before the fort ends the run")
	check(not b.has("run_seconds"), "no unused run length is left in the data")
	var died := _fresh_profile()
	var s := Sim.new(b, Content.with_all_art(), {"seed": 1613})
	s.time = float(rule.seconds) + 1.0
	s.peak_soldiers = int(rule.max_soldiers)
	s.over = true
	died.record_run(s)
	check(died.commander_unlocked("old_centurion"), "falling after the time with a small legion still earns him")
	died.free()


func test_every_look_flag_keeps_the_profile_unsaved(_b: Dictionary) -> void:
	for flag in ["easy", "hard", "endless", "decimatio", "commander=legate", "chieftain-at=60", "as-demo", "objectives-near", "boss=berserker", "boss-act=whirl", "god=vulcan", "god-at=3", "give=pilum:3", "go-to=fort", "hold-choice", "lang=fr", "card=kills_1000", "page=controls", "province=britannia", "seed=7", "men=20", "mortal", "trailer-shot=fort", "no-save"]:
		check(Profile.blocks_saving(PackedStringArray(["--" + flag])), "--%s is not saved" % flag)


func test_no_timber_is_spent_on_stakes_over_a_ravine_or_a_second_deck(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1614)
	_gorge(s, -400, 400, 100, 50)
	s.commander.pos = Vector2(0, 30)
	s.facing_angle = PI / 2.0
	s.legion.place_all(s.facing_angle)
	s.terrain.refresh(s.commander.pos)
	s.timber = int(b.palisade.cost)
	s.build_palisade()
	var over := 0
	for p in s.terrain.posts:
		if s.terrain.ravine_edge(p[1]) < float(b.palisade.radius):
			over += 1
	check(over == 0, "no stake stands over the drop (%d)" % over)
	check(not s.terrain.posts.is_empty() or s.timber == int(b.palisade.cost), "and with no room for any the timber is kept")
	var r := _quiet_sim(b, 1615)
	_gorge(r, -400, 400, 100, 50)
	r.commander.pos = Vector2(0, -10)
	r.facing_angle = PI / 2.0
	r.legion.place_all(r.facing_angle)
	r.timber = int(b.bridge.cost) * 2
	check(r.build_bridge(), "a first bridge is laid")
	r.commander.pos = Vector2(0, 100)
	r.terrain.refresh(r.commander.pos)
	check(r.bridge_span().is_empty(), "standing on it, no second bridge is offered")
	check(not r.build_bridge() and r.timber == int(b.bridge.cost) and r.terrain.bridges.size() == 1, "and none is laid")
	r.commander.pos = Vector2(0, -10)
	r.terrain.refresh(r.commander.pos)
	check(r.bridge_span().is_empty(), "nor facing the one already laid")


func test_an_objectives_leader_takes_no_boss_slot(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1616, Content.with_all_art())
	s.horde.time = 100.0
	s.time = 100.0
	s.horde.spawn("war_band_leader", Vector2(300, 0), true)
	s.horde._boss_arrival(s)
	check(_boss_count(s) == 2, "the timed boss still comes while the camp's leader lives (%d)" % _boss_count(s))
	s.horde._boss_arrival(s)
	check(_boss_count(s) == 2, "but only one timed boss at a time this early (%d)" % _boss_count(s))


func test_the_demo_hands_out_no_commander_achievement(_b: Dictionary) -> void:
	var saved: Dictionary = Profile.data
	var open := Game.demo_open
	Profile.data = Profile.defaults()
	Game.demo_forced = true
	Game.demo_open = ["tribune", "archer_captain", "cavalry_prefect"]
	check(not Steamworks.met({"kind": "commander", "target": "cavalry_prefect"}, null, false), "a commander the demo lends is not earned")
	Game.demo_forced = false
	Game.demo_open = open
	Profile.data = saved


func _count_events(s: Sim, kind: String) -> int:
	return s.events.filter(func(e: Dictionary) -> bool: return e.kind == kind).size()


func test_building_and_objectives_sound_once_each(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1510)
	_gorge(s, -400, 400, 100, 50)
	s.commander.pos = Vector2(0, -10)
	s.facing_angle = PI / 2.0
	s.legion.place_all(s.facing_angle)
	s.timber = int(b.bridge.cost) + int(b.palisade.cost)
	s.events.clear()
	check(s.build_bridge(), "the bridge is laid")
	check(_count_events(s, "bridge") == 1 and _count_events(s, "palisade") == 0, "a bridge sounds as a bridge and not as stakes")
	s.events.clear()
	s.facing_angle = -PI / 2.0
	s.legion.place_all(s.facing_angle)
	check(s.build_palisade(), "the palisade goes up")
	check(_count_events(s, "palisade") == 1 and _count_events(s, "bridge") == 0, "the stakes sound once")
	var f := _mode_sim(b, {"seed": 156})
	f.objectives.list.clear()
	f.commander.pos = Vector2(300, -200)
	f.time = float(b.chieftain_at) - 0.01
	f.update(1.0 / 60.0, Vector2.ZERO, false)
	f.horde.e_pos[f.chieftain_index()] = f.commander.pos + Vector2(0, 2000)
	f.commander.pos = f.objectives.fort.centre
	f.events.clear()
	_step_dt(f, 1.0)
	check(_count_events(f, "fort") == 1, "entering the fort sounds once however long the legion stays (%d)" % _count_events(f, "fort"))
	var o := _objective_sim(b, 151)
	var camp: Dictionary = o.objectives.add(o, "camp", Vector2(600, 0))
	o.soldiers[0].pos = camp.pos
	o._rebuild_grids()
	o.events.clear()
	o.objectives.update(0.01, o)
	o.objectives.update(0.01, o)
	check(_count_events(o, "fire") == 1, "the camp catches fire with one sound")


func test_the_horn_sounds_rarely(b: Dictionary) -> void:
	var horn: Dictionary = b.audio.kinds.surge
	check(float(horn.get("cooldown", 0.0)) >= 45.0, "the horn waits at least 45 seconds before it sounds again (%.0f)" % float(horn.get("cooldown", 0.0)))


func test_the_gods_sound_ready_once_when_the_favour_fills(b: Dictionary) -> void:
	var s := _god_sim(b, 502, 0)
	s.gods.favour = s.gods.need(s.b) - 1
	s.events.clear()
	for k in 3:
		var i := s.horde.spawn("barbarian_club", Vector2(250, 0))
		s.hit(i, 1e6)
		s._remove_dead()
	check(_count_events(s, "godready") == 1, "the gods are ready once, when the meter fills (%d)" % _count_events(s, "godready"))


## A quiet run in Gaul on open ground: no stream, surges or bosses on their own, a commander who cannot fall and eight legionaries round him.
func _gaul_sim(b: Dictionary, seed_value: int, province := "gaul") -> Sim:
	var s := Sim.new(b, Content.with_all_art(), {"seed": seed_value, "province": province})
	s.terrain.clear()
	s.b = b.duplicate()
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	s.horde.next_surge = 1e9
	s.horde.next_band = 1e9
	s.horde.next_cart = 1e9
	s.horde.next_boss = 1e9
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	for k in 8:
		s.add_soldier("legionary")
	s.legion.place_all(s.facing_angle)
	for t in ["cleave_cd", "cry_cd", "charge_cd", "slam_cd", "horn_cd", "summon_cd", "siege_cd"]:
		s.horde.set(t, 1e9)
	s._rebuild_grids()
	return s


## A copy of the content with a made-up province, Hibernia, between Germania and Gaul, whose ground, props and enemy are not drawn.
func _with_undrawn(base: Content) -> Content:
	var c := Content.load_all(base.available.duplicate())
	c.enemies["hibernian_raider"] = {"name": "Raider", "text": "A raider.", "history": "Made up for the tests.", "behaviour": "melee", "hp": 10, "speed": 40,
		"dps": 1, "radius": 6, "coins": 1, "art": ["unit:hibernian_raider"]}
	var order := {}
	for id in c.provinces:
		order[id] = c.provinces[id]
		if id == "germania":
			order["hibernia"] = {"name": "Hibernia", "text": "Made up for the tests.", "ground": "bog", "props": [], "ordinary": ["hibernian_raider"],
				"elites": [], "chieftain": "chieftain", "art": ["prop:hibernian_bog", "ground:hibernia"]}
	c.provinces = order
	return c


func test_winning_germania_opens_gaul_while_an_undrawn_province_waits_for_art(b: Dictionary) -> void:
	var c := _with_undrawn(content)
	check(c.ready("provinces", "gaul") and not c.ready("provinces", "hibernia"), "Gaul is drawn and the made-up Hibernia is not")
	check(c.province_before("gaul") == "germania", "the drawn province before Gaul is Germania")
	check(c.province_before("germania") == "", "nothing comes before Germania")
	var drawn := _with_undrawn(content)
	drawn.available["prop:hibernian_bog"] = true
	drawn.available["ground:hibernia"] = true
	check(drawn.province_before("gaul") == "hibernia", "once it is drawn it comes between them")
	var p := _fresh_profile()
	var s := Sim.new(b, c, {"seed": 901})
	s.time = 900.0
	s.over = true
	s.victory = true
	p.record_run(s)
	check(p.province_unlocked("gaul"), "winning in Germania opens Gaul")
	var old := _fresh_profile()
	old.data.records["germania"] = {"best_time": 900.0, "longest": 900.0, "won": true, "hard_won": false}
	check(not old.province_unlocked("gaul"), "a profile that won Germania before Gaul was drawn starts without it")
	old.open_won_provinces(content)
	check(old.province_unlocked("gaul"), "and finds it open once the game starts")
	old.free()
	_cleanup_profile_files()
	p.free()


## A stand-in for main with what the map reads: the content, the balance and the run's choices.
func _map_host(c: Content, b: Dictionary, province: String) -> Node:
	var host_script := GDScript.new()
	host_script.source_code = "extends Node\nvar content\nvar balance\nvar run_setup := {}\n"
	host_script.reload()
	var host: Node = Node.new()
	host.set_script(host_script)
	host.content = c
	host.balance = b
	host.run_setup = {"province": province, "commander": "tribune", "difficulty": "medium", "endless": false, "decimatio": false}
	return host


func test_gaul_is_farmland_with_villages_hedges_and_wheat(b: Dictionary) -> void:
	var kinds := {}
	var t := Terrain.new(902, b.forest, {})
	t.field = b.fields.gaul
	for pr in t.props_in(Rect2(-3000, -3000, 6000, 6000)):
		kinds[pr[0]] = kinds.get(pr[0], 0) + 1
	check(kinds.has("hedge") and kinds.has("roundhouse"), "the farmland holds hedges and villages of roundhouses (%s)" % str(kinds.keys()))
	check(not kinds.has("wheat"), "and no scattered sheaves of wheat")
	var fields := t.fields_in(Rect2(-3000, -3000, 6000, 6000))
	var big := fields.filter(func(f: Rect2) -> bool: return f.size.x >= 100.0 and f.size.y >= 70.0)
	check(big.size() >= 6, "but whole fields of standing wheat (%d large of %d)" % [big.size(), fields.size()])
	check(not kinds.has("oak") and not kinds.has("fir") and not kinds.has("log"), "and none of Germania's forest")
	var g := Terrain.new(902, b.forest, {})
	var forest := {}
	for pr in g.props_in(Rect2(-3000, -3000, 6000, 6000)):
		forest[pr[0]] = true
	check(forest.has("oak") and not forest.has("wheat") and not forest.has("roundhouse") and g.fields_in(Rect2(-3000, -3000, 6000, 6000)).is_empty(), "Germania keeps its forest and has no fields")


func test_hedges_and_villages_block(b: Dictionary) -> void:
	var t := Terrain.new(903, b.forest, {})
	t.field = b.fields.gaul
	var hedge := Vector2.INF
	var village := Vector2.INF
	for pr in t.props_in(Rect2(-3000, -3000, 6000, 6000)):
		if pr[0] == "hedge" and hedge == Vector2.INF:
			hedge = pr[1]
		elif pr[0] == "roundhouse" and village == Vector2.INF:
			village = pr[1]
	check(hedge != Vector2.INF and village != Vector2.INF, "a hedge and a village were found")
	t.refresh(hedge)
	var at := hedge + Vector2(3, -6)
	check(t.push_out(at, Sim.UNIT_RADIUS).distance_to(at) > 4.0, "a soldier cannot stand in a hedge")
	t.refresh(village)
	for off in [Vector2(0, -24), Vector2(-30, -20), Vector2(30, -20), Vector2(0, -50)]:
		at = village + off
		check(t.push_out(at, Sim.UNIT_RADIUS).distance_to(at) > 4.0, "nor inside a roundhouse's wall (%s)" % off)
	at = village + Vector2(0, 30)
	check(t.push_out(at, Sim.UNIT_RADIUS) == at, "but he can walk past in front of its door")


func test_a_swordsman_slash_cuts_two_soldiers(b: Dictionary) -> void:
	var s := _gaul_sim(b, 904)
	var h := s.horde
	var i := h.spawn("gaul_swordsman", Vector2(100, 0))
	var cfg: Dictionary = content.enemies.gaul_swordsman.slash
	var a: Dictionary = s.soldiers[0]
	var c: Dictionary = s.soldiers[1]
	var far: Dictionary = s.soldiers[2]
	a.pos = Vector2(86, -6)
	c.pos = Vector2(86, 8)
	far.pos = Vector2(40, 0)
	for u in [a, c, far]:
		u.max_hp = 1e6
		u.hp = 1e6
	s._rebuild_grids()
	h._slash(i, Vector2.LEFT, 1.0, s)
	var want := float(content.enemies.gaul_swordsman.dps) * float(cfg.damage_mult)
	check(is_equal_approx(1e6 - a.hp, want) and is_equal_approx(1e6 - c.hp, want), "one slash cuts both soldiers in front of him (%.0f each)" % want)
	check(far.hp == 1e6, "and misses a soldier out of reach")
	check(h.e_strike[i] == s.time, "and plays his swing")


func test_a_horseman_charges_along_the_flank_then_rears(b: Dictionary) -> void:
	var s := _gaul_sim(b, 905)
	var h := s.horde
	var i := h.spawn("gaul_horseman", s.commander.pos + Vector2(200, 0))
	h.e_cd[i] = 0.0
	s._rebuild_grids()
	h._move(1.0 / 60.0, s)
	var dir: Vector2 = h.e_dir[i]
	check(h.e_dash[i] > 0.0, "he starts a charge")
	# How close his line of charge passes the commander.
	var to: Vector2 = s.commander.pos - h.e_pos[i]
	var miss := absf(to.cross(dir))
	check(miss > s.legion_reach * 0.4, "aimed beside the legion rather than at its middle (%.0f px off)" % miss)
	h.e_pos[i] = s.soldiers[0].pos + Vector2(10, 0)
	s._rebuild_grids()
	h._move(1.0 / 60.0, s)
	check(h.e_dash[i] == 0.0 and h.e_strike[i] == s.time, "riding into a soldier ends the charge as his horse rears")


func test_an_archer_volley_falls_on_a_marked_ring(b: Dictionary) -> void:
	var s := _gaul_sim(b, 906)
	var h := s.horde
	var i := h.spawn("gaul_archer", s.commander.pos + Vector2(140, 0))
	var target: Dictionary = s.commander
	for u in s.units:
		if u.pos.distance_to(h.e_pos[i]) < target.pos.distance_to(h.e_pos[i]):
			target = u
	h.e_cd[i] = 0.0
	s._rebuild_grids()
	h._move(1.0 / 60.0, s)
	var volley: Dictionary = {}
	for l in h.foe_lobs:
		if l.get("volley", false):
			volley = l
	check(not volley.is_empty(), "he looses a volley instead of a straight shot")
	check(h.sp_pos.is_empty(), "nothing flies straight at the legion")
	check(volley.get("to", Vector2.INF).distance_to(target.pos) < float(content.enemies.gaul_archer.volley.radius), "it falls by the nearest soldier")
	for u in [s.commander] + s.soldiers:
		u.max_hp = 1e6
		u.hp = 1e6
	h._foe_lobs(0.01, s)
	check(target.hp == 1e6, "nobody is hurt while the ring fills")
	volley.t = volley.dur
	h._foe_lobs(0.01, s)
	var hurt := 0
	for u in [s.commander] + s.soldiers:
		if u.hp < 1e6 and u.pos.distance_to(volley.to) < volley.radius + Sim.UNIT_RADIUS:
			hurt += 1
	check(hurt >= 1, "then it hurts the soldiers in the ring")


func test_a_boar_rushes_straight_and_a_stake_stuns_it(b: Dictionary) -> void:
	var s := _gaul_sim(b, 907)
	var h := s.horde
	var i := h.spawn("boar", s.commander.pos + Vector2(180, 0))
	h.e_cd[i] = 0.0
	s._rebuild_grids()
	h._move(1.0 / 60.0, s)
	check(h.e_dash[i] > 0.0, "the boar starts its rush")
	var dir: Vector2 = h.e_dir[i]
	s.commander.pos += Vector2(0, 120)
	s._rebuild_grids()
	h._move(1.0 / 60.0, s)
	check(h.e_dir[i] == dir, "and cannot turn while it runs")
	s.terrain.add_post(h.e_pos[i] + dir * 12.0, 6.0, 1e9)
	s.terrain.refresh(s.commander.pos)
	var stunned := false
	for k in 30:
		s._rebuild_grids()
		h._move(1.0 / 60.0, s)
		stunned = stunned or h.e_stun[i] > 0.0
	check(stunned, "running into a stake stuns it")


func test_the_champion_calls_a_duel(b: Dictionary) -> void:
	var cfg: Dictionary = content.enemies.champion.duel
	var s := _gaul_sim(b, 908)
	var h := s.horde
	s.commander.pos = Vector2.ZERO
	var i := h.spawn("champion", Vector2(90, 0), true)
	var st: Dictionary = h.boss_state(i)
	for key in st:
		if str(key).ends_with("_cd"):
			st[key] = 1e9
	st.duel_cd = 0.0
	s._rebuild_grids()
	h._bosses(1.0 / 60.0, s)
	check(st.duel > 0.0, "he calls the commander out")
	check(st.duel_at.distance_to(Vector2.ZERO) <= st.duel_r and st.duel_at.distance_to(h.e_pos[i]) <= st.duel_r, "the ring holds them both")
	var hp0: float = h.e_hp[i]
	s.hit(i, 100.0, 0.0, "", Vector2(40, 0))
	check(is_equal_approx(hp0 - h.e_hp[i], 100.0 * float(cfg.inside_mult)), "a blow from inside the ring lands harder")
	hp0 = h.e_hp[i]
	s.hit(i, 100.0, 0.0, "", Vector2(400, 0))
	check(is_equal_approx(hp0 - h.e_hp[i], 100.0 * (1.0 - float(cfg.cut))), "a blow from outside it is mostly turned")
	var power: float = h.e_power[i]
	s.commander.pos = Vector2(-400, 0)
	h._bosses(1.0 / 60.0, s)
	check(st.duel == 0.0, "walking out of the ring ends the duel")
	check(is_equal_approx(h.e_power[i], power * float(cfg.scorn.power_mult)), "and shames him into hitting harder")
	h._bosses(1.0 / 60.0, s)
	check(is_equal_approx(h.e_power[i], power * float(cfg.scorn.power_mult)), "only once")


func test_the_horn_blower_rallies_blasts_and_runs(b: Dictionary) -> void:
	var cfg: Dictionary = content.enemies.horn_blower
	var s := _gaul_sim(b, 909)
	var h := s.horde
	s.commander.pos = Vector2.ZERO
	s.legion.place_all(s.facing_angle)
	var i := h.spawn("horn_blower", Vector2(150, 0), true)
	var st: Dictionary = h.boss_state(i)
	for key in st:
		if str(key).ends_with("_cd"):
			st[key] = 1e9
	var j := h.spawn("gaul_swordsman", Vector2(170, 20))
	h.e_hp[j] = h.e_max[j] * 0.5
	h.rally_cd[h.e_id[i]] = 0.0
	s._rebuild_grids()
	h._rally(1.0 / 60.0, s)
	check(h.e_hp[j] > h.e_max[j] * 0.5 and h.e_haste[j] > 0.0, "his rally heals and speeds the warriors round him")
	var rate := s.attack_rate()
	var soldier: Dictionary = s.soldiers[0]
	var before: float = soldier.pos.distance_to(h.e_pos[i])
	var hp0: float = soldier.hp
	st.blast_cd = 0.0
	h._bosses(1.0 / 60.0, s)
	check(h.blast_left > 0.0 and s.attack_rate() < rate, "his blast slows the legion's blows")
	check(soldier.pos.distance_to(h.e_pos[i]) > before, "and pushes the soldiers back")
	check(soldier.hp < hp0, "and hurts them")
	check(h.k_beh[h.e_kind[i]] == Horde.LOBBER and h.k_lob[h.e_kind[i]] == 0, "he stands off and throws nothing")
	soldier.pos = h.e_pos[i] + Vector2(-20, 0)
	s._rebuild_grids()
	h._bosses(1.0 / 60.0, s)
	check(h.e_flee[i] > 0.0, "a soldier at his elbow sends him running")
	var gap := h.e_pos[i].length()
	h._move(0.1, s)
	check(h.e_pos[i].length() > gap, "away from the legion")
	check(float(cfg.flee.speed_mult) > 1.0, "faster than he walks")


func test_a_war_band_grows_with_its_provinces_numbers(b: Dictionary) -> void:
	var s := _gaul_sim(b, 912)
	var h := s.horde
	var wb: Dictionary = b.war_band
	h.time = 600.0
	var n0 := h.e_pos.size()
	h.war_band_at(s, Vector2(600, 0))
	var want := int((float(wb.size_start) + float(wb.size_growth) * h.time) * float(b.difficulty.gaul.spawn))
	check(h.e_pos.size() - n0 == want, "a war band in Gaul is %d strong, scaled by its spawn (%d)" % [want, h.e_pos.size() - n0])


func test_the_gaulish_king_and_his_sworn_guard(b: Dictionary) -> void:
	var s := _gaul_sim(b, 910)
	var h := s.horde
	var cfg: Dictionary = content.enemies.gaul_king
	var ci := h.spawn_chieftain(Vector2(300, 0))
	var guards := 0
	for k in h.e_pos.size():
		if h.e_guard[k] != Vector2.ZERO:
			guards += 1
			check(h.kind_ids[h.e_kind[k]] == "gaul_swordsman", "his guards are swordsmen")
	check(guards == h.guards_alive and guards == int(b.chieftain_guard.count), "he comes with his ring of guards")
	var hp0: float = h.e_hp[ci]
	s.hit(ci, 100.0)
	check(is_equal_approx(hp0 - h.e_hp[ci], 100.0 * (1.0 - float(cfg.sworn.cut))), "while they stand he takes little harm")
	hp0 = h.e_hp[ci]
	s.scorch(ci, 100.0)
	check(is_equal_approx(hp0 - h.e_hp[ci], 100.0 * (1.0 - float(cfg.sworn.cut))), "and burning ground hurts him as little")
	hp0 = h.e_hp[ci]
	s.ignite(ci, 60.0, 1.0)
	s._burns(0.5)
	check(is_equal_approx(hp0 - h.e_hp[ci], 30.0 * (1.0 - float(cfg.sworn.cut))), "and so does a burn")
	while h.guards_alive >= int(cfg.sworn.min):
		for k in h.e_pos.size():
			if h.e_guard[k] != Vector2.ZERO:
				h.remove_at(k)
				break
	ci = h.chieftain_index()
	hp0 = h.e_hp[ci]
	s.hit(ci, 100.0)
	check(is_equal_approx(hp0 - h.e_hp[ci], 100.0), "with fewer than %d left he takes full harm" % int(cfg.sworn.min))


func test_the_gaulish_king_rings_the_legion_with_stakes(b: Dictionary) -> void:
	var s := _gaul_sim(b, 911)
	var h := s.horde
	var siege: Dictionary = content.enemies.gaul_king.attacks.siege
	var ci := h.spawn_chieftain(Vector2(300, 0))
	var before := s.terrain.posts.size()
	h.siege(ci, s)
	var added := s.terrain.posts.size() - before
	check(added > 10, "he drives a ring of stakes (%d)" % added)
	var ahead := Vector2.from_angle(s.facing_angle)
	var front := 0
	var outside := true
	for post in s.terrain.posts:
		var off: Vector2 = post[1] - s.commander.pos
		outside = outside and off.length() > s.legion_reach
		if off.normalized().dot(ahead) > 0.9:
			front += 1
	check(outside, "every stake stands outside the legion")
	check(front > 0, "and some across its front")
	s.terrain.refresh(s.commander.pos)
	var at: Vector2 = s.commander.pos + ahead * (s.legion_reach + float(siege.gap))
	check(s.terrain.push_out(at, Sim.UNIT_RADIUS).distance_to(at) > 2.0, "nobody walks through them")
	s.terrain.rot_posts(s.time + float(siege.seconds) + 0.1)
	check(s.terrain.posts.size() == before, "they rot after %d seconds" % int(siege.seconds))


func test_the_gaulish_king_summons_horsemen_and_frees_his_guard(b: Dictionary) -> void:
	var s := _gaul_sim(b, 912)
	var h := s.horde
	var cfg: Dictionary = content.enemies.gaul_king.attacks.summon
	var ci := h.spawn_chieftain(Vector2(300, 0))
	var n0 := h.e_pos.size()
	h.summon(ci, s)
	var riders := 0
	for k in range(n0, h.e_pos.size()):
		if h.kind_ids[h.e_kind[k]] == "gaul_horseman":
			riders += 1
	check(riders == int(cfg.count), "he calls %d horsemen from the edge of the field" % int(cfg.count))
	h.e_hp[ci] = h.e_max[ci] * 0.49
	h.siege_cd = 0.0
	var posts := s.terrain.posts.size()
	h._chieftain(1.0 / 60.0, s)
	check(h.chief_fury, "below half health he enters his second phase")
	check(h.guards_alive == 0, "his guards leave their places")
	var placed := 0
	for k in h.e_pos.size():
		if h.e_guard[k] != Vector2.ZERO:
			placed += 1
	check(placed == 0, "and run at the legion")
	check(s.terrain.posts.size() == posts, "and he stops driving stakes")
	n0 = h.e_pos.size()
	h.summon(ci, s)
	check(h.e_pos.size() - n0 == int(cfg.fury_count), "his summons bring %d riders now" % int(cfg.fury_count))


func _dacia_sim(b: Dictionary, seed_value: int) -> Sim:
	var s := _gaul_sim(b, seed_value, "dacia")
	for t in ["sweep_cd", "rockfall_cd", "leap_cd", "salvo_cd"]:
		s.horde.set(t, 1e9)
	return s


func test_winning_parthia_opens_dacia(b: Dictionary) -> void:
	check(content.ready("provinces", "dacia"), "Dacia is drawn")
	check(content.province_before("dacia") == "parthia" and content.provinces.keys().find("dacia") == content.provinces.keys().find("parthia") + 1, "Dacia comes after Parthia on the road")
	var p := _fresh_profile()
	var s := Sim.new(b, content, {"seed": 940, "province": "parthia"})
	s.time = 900.0
	s.over = true
	s.victory = true
	p.record_run(s)
	check(p.province_unlocked("dacia"), "winning in Parthia opens Dacia")
	_cleanup_profile_files()
	p.free()


func test_dacia_is_snowy_mountains_with_pines_rocks_and_ice(b: Dictionary) -> void:
	var area := Rect2(-4000, -4000, 8000, 8000)
	var t := Terrain.new(941, b.forest, b.ravines)
	t.mountain = b.mountains.dacia
	t.stream_cfg = b.streams.dacia
	var g := Terrain.new(941, b.forest, b.ravines)
	var kinds := {}
	var forest := {}
	for pr in t.props_in(area):
		kinds[pr[0]] = kinds.get(pr[0], 0) + 1
	for pr in g.props_in(area):
		forest[pr[0]] = forest.get(pr[0], 0) + 1
	check(kinds.has("pine") and kinds.has("rock"), "the mountains hold pines and rocks (%s)" % str(kinds.keys()))
	check(not kinds.has("oak") and not kinds.has("fir") and not kinds.has("log"), "and none of Germania's oaks, firs or logs")
	check(int(kinds.get("rock", 0)) > int(forest.get("rock", 0)), "more rock than Germania (%d against %d)" % [kinds.get("rock", 0), forest.get("rock", 0)])
	check(int(kinds.get("pine", 0)) > int(forest.get("fir", 0)) + int(forest.get("oak", 0)), "and more trees in its ridges (%d against %d)" % [kinds.get("pine", 0), int(forest.get("fir", 0)) + int(forest.get("oak", 0))])
	var streams := t.streams_in(area)
	check(streams.size() >= 4, "frozen streams wind across the field (%d)" % streams.size())
	check(g.streams_in(area).is_empty(), "and Germania has none")
	var on_ice := 0
	for pr in t.props_in(area):
		if pr[2] > 0.0 and t.on_ice(pr[1]):
			on_ice += 1
	check(on_ice == 0, "nothing solid stands on the ice")
	var clear := true
	for st in streams:
		for piece in st.pieces:
			for i in range(0, piece.pts.size(), 4):
				clear = clear and t.ravine_edge(piece.pts[i], 400.0) > piece.half[i]
	check(clear, "and no stream runs into a ravine")


func test_the_legion_slides_on_ice(b: Dictionary) -> void:
	var s := _dacia_sim(b, 942)
	s.terrain.add_stream([{"pts": PackedVector2Array([Vector2(-600, 0), Vector2(600, 0)]), "half": PackedFloat32Array([400.0, 400.0])}])
	s.commander.pos = Vector2.ZERO
	s.legion.place_all(s.facing_angle)
	check(s.terrain.on_ice(Vector2.ZERO) and not s.terrain.on_ice(Vector2(0, 600)), "the ice is where the stream lies")
	s.update(1.0 / 60.0, Vector2.RIGHT, false)
	var first: float = s.commander.pos.x
	check(first > 0.0 and first < s.speed() / 60.0 * 0.5, "on the ice the legion gathers speed slowly (%.2f px)" % first)
	for k in 120:
		s.update(1.0 / 60.0, Vector2.RIGHT, false)
	var at: Vector2 = s.commander.pos
	for k in 30:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.commander.pos.x - at.x > 20.0, "and slides on after the march stops (%.0f px)" % (s.commander.pos.x - at.x))
	var dry := _dacia_sim(b, 942)
	dry.commander.pos = Vector2.ZERO
	dry.update(1.0 / 60.0, Vector2.RIGHT, false)
	var start: float = dry.commander.pos.x
	dry.update(1.0 / 60.0, Vector2.ZERO, false)
	check(is_equal_approx(dry.commander.pos.x, start), "off the ice it stops where it stands")


func test_a_falx_cuts_through_the_testudo(b: Dictionary) -> void:
	var hurt := {}
	for kind in ["falx_warrior", "barbarian_club"]:
		var s := _dacia_sim(b, 943)
		s.soldiers.clear()
		s.legion.place_all(s.facing_angle)
		var i := s.horde.spawn(kind, s.commander.pos + Vector2(10, 0))
		s.horde.e_cd[i] = 1e9
		s.testudo_left = 5.0
		var before: float = s.commander.hp
		for k in 30:
			s._rebuild_grids()
			s.horde._move(1.0 / 60.0, s)
		hurt[kind] = (before - s.commander.hp) / float(content.enemies[kind].dps)
	check(hurt.falx_warrior > hurt.barbarian_club * 2.0, "the testudo turns a club but not a falx (%.2f against %.2f)" % [hurt.falx_warrior, hurt.barbarian_club])
	var s := _dacia_sim(b, 944)
	s.soldiers.clear()
	var i := s.horde.spawn("falx_warrior", s.commander.pos + Vector2(10, 0))
	s.horde.e_cd[i] = 0.0
	var hp0: float = s.commander.hp
	s._rebuild_grids()
	s.horde._move(1.0 / 60.0, s)
	var cfg: Dictionary = content.enemies.falx_warrior
	check(hp0 - s.commander.hp >= float(cfg.dps) * float(cfg.falx.damage_mult) * s.horde.difficulty("damage") * s.horde.level_mult("damage_mult"), "and every few seconds he lands a heavy chop")
	check(s.horde.e_strike[i] == s.time, "which plays his swing")


func test_dacian_archers_loose_together_on_the_drum(b: Dictionary) -> void:
	var s := _dacia_sim(b, 945)
	var h := s.horde
	var cfg: Dictionary = content.enemies.dacian_archer.salvo
	check(h.salvo_every == float(cfg.every), "the drum beats every %d seconds" % int(cfg.every))
	var archers: Array = []
	for k in 3:
		var i := h.spawn("dacian_archer", s.commander.pos + Vector2.from_angle(k * 2.0) * 150.0)
		h.e_cd[i] = 0.0
		archers.append(i)
	h.salvo_cd = 1.0
	s._rebuild_grids()
	h.update(1.0 / 60.0, s)
	check(h.sp_pos.is_empty(), "no archer shoots before the beat")
	h.salvo_cd = 0.001
	h.update(1.0 / 60.0, s)
	check(h.sp_pos.size() == 3 * int(cfg.arrows), "on the beat every archer looses %d arrows at once (%d)" % [int(cfg.arrows), h.sp_pos.size()])
	var arrows := true
	for k in h.sp_kind:
		arrows = arrows and k == 1
	check(arrows, "drawn as arrows")
	s.testudo_left = 5.0
	var hp0: float = s.commander.hp
	for k in 120:
		h._spears(1.0 / 60.0, s)
	check(h.sp_pos.is_empty() and s.commander.hp == hp0, "and the testudo stops them")


func test_the_draco_howls_and_speeds_the_warriors(b: Dictionary) -> void:
	var s := _dacia_sim(b, 946)
	var h := s.horde
	var cfg: Dictionary = content.enemies.wolf_standard_bearer.howl
	var i := h.spawn("wolf_standard_bearer", s.commander.pos + Vector2(120, 0))
	var near := h.spawn("falx_warrior", s.commander.pos + Vector2(140, 30))
	var far := h.spawn("falx_warrior", s.commander.pos + Vector2(-200, 200))
	h.e_cd[i] = 0.0
	s._rebuild_grids()
	h._move(1.0 / 60.0, s)
	check(h.e_haste[near] > 0.0 and is_equal_approx(h.e_haste_mult[near], float(cfg.speed_mult)), "his howl speeds the warriors round him")
	check(h.e_haste[far] == 0.0, "but not those far off")
	check(h.e_strike[i] == s.time, "and he raises the draco")


func test_a_bear_mauls_and_throws_soldiers_back(b: Dictionary) -> void:
	var s := _dacia_sim(b, 947)
	var h := s.horde
	var cfg: Dictionary = content.enemies.mountain_bear
	var i := h.spawn("mountain_bear", Vector2(100, 0))
	var a: Dictionary = s.soldiers[0]
	var c: Dictionary = s.soldiers[1]
	var far: Dictionary = s.soldiers[2]
	a.pos = Vector2(84, 0)
	c.pos = Vector2(80, 10)
	far.pos = Vector2(-60, 0)
	for u in [a, c, far]:
		u.max_hp = 1e6
		u.hp = 1e6
	var gap: float = a.pos.distance_to(h.e_pos[i])
	h._maul(i, a, 1.0, s)
	var want := float(cfg.dps) * float(cfg.maul.damage_mult)
	check(is_equal_approx(1e6 - a.hp, want), "the maul strikes hard (%.0f)" % want)
	check(c.hp < 1e6 and c.hp > a.hp, "catches the soldier beside him more lightly")
	check(far.hp == 1e6, "and misses one out of reach")
	check(a.pos.distance_to(h.e_pos[i]) > gap, "throwing the soldier back")
	check(float(cfg.hp) > float(content.enemies.falx_warrior.hp) * 2.0, "a bear takes much more to bring down than a warrior")


func test_the_falx_band_leader_charges_with_his_band(b: Dictionary) -> void:
	var s := _dacia_sim(b, 948)
	var h := s.horde
	var cfg: Dictionary = content.enemies.falx_band.onrush
	s.commander.pos = Vector2.ZERO
	s.legion.place_all(s.facing_angle)
	var i := h.spawn("falx_band", Vector2(200, 0), true)
	var st: Dictionary = h.boss_state(i)
	st.onrush_cd = 0.0
	var mate := h.spawn("falx_warrior", Vector2(230, 40))
	s._rebuild_grids()
	h._bosses(1.0 / 60.0, s)
	check(st.rush_warn > 0.0, "he marks his lane first")
	check(st.rush_dir.dot(Vector2.LEFT) > 0.99, "towards the legion")
	var hp0: float = s.commander.hp
	var start := h.e_pos[i]
	while st.rush_warn > 0.0:
		h._bosses(1.0 / 60.0, s)
		h._bosses_after()
	check(h.e_pos[i] == start and s.commander.hp == hp0, "nobody is hurt while the lane fills")
	check(st.rush_left > 0.0, "then he charges")
	check(h.e_slow[mate] > 1.0, "and the warriors round him rush in with him")
	for k in int(float(cfg.seconds) * 60.0) + 2:
		h._bosses(1.0 / 60.0, s)
		h._bosses_after()
	check(h.e_pos[i].distance_to(start) > float(cfg.length) * 0.8, "running the length of his lane")
	check(s.commander.hp < hp0, "cutting down the soldiers in his path")


func test_the_priest_calls_a_blizzard(b: Dictionary) -> void:
	var s := _dacia_sim(b, 949)
	var h := s.horde
	var cfg: Dictionary = content.enemies.priest.blizzard
	s.commander.pos = Vector2.ZERO
	s.legion.place_all(s.facing_angle)
	var i := h.spawn("priest", Vector2(160, 0), true)
	h.boss_state(i).blizzard_cd = 0.0
	var pace := s.speed()
	h._bosses(1.0 / 60.0, s)
	check(h.marks.size() == 1 and h.marks[0].kind == "blizzard", "a ring marks where his blizzard will fall")
	h._storms(1.0 / 60.0, s)
	check(is_equal_approx(s.speed(), pace), "it does nothing while the ring fills")
	h.marks[0].t = h.marks[0].dur
	h._marks(1.0 / 60.0, s)
	var hp0: float = s.commander.hp
	h._storms(1.0 / 60.0, s)
	check(h.storms.size() == 1 and s.speed() < pace * (1.0 - float(cfg.slow) * 0.9), "then the storm slows the legion's march")
	check(s.commander.hp < hp0, "and freezes those inside it")
	s.commander.pos = Vector2(600, 0)
	h._storms(1.0 / 60.0, s)
	check(is_equal_approx(s.speed(), pace), "marching out of it frees the legion")
	h.storms[0].t = float(cfg.seconds)
	h._storms(1.0 / 60.0, s)
	check(h.storms.is_empty(), "and it blows over after %d seconds" % int(cfg.seconds))


func test_the_dacian_king_behind_his_wall(b: Dictionary) -> void:
	var s := _dacia_sim(b, 950)
	var h := s.horde
	var cfg: Dictionary = content.enemies.dacian_king.wall
	s.commander.pos = Vector2.ZERO
	var ci := h.spawn_chieftain(Vector2(300, 0))
	var front := true
	var guards := 0
	for k in h.e_pos.size():
		if h.e_guard[k] != Vector2.ZERO:
			guards += 1
			front = front and h.e_guard[k].dot(Vector2.LEFT) > 0.0 and h.kind_ids[h.e_kind[k]] == "falx_warrior"
	check(guards == h.guards_alive and guards > 0, "he comes with his guard")
	check(front, "falx warriors standing in an arc between him and the legion")
	var hp0: float = h.e_hp[ci]
	s.hit(ci, 100.0, 0.0, "", Vector2(200, 0))
	check(is_equal_approx(hp0 - h.e_hp[ci], 100.0 * (1.0 - float(cfg.cut))), "a blow from in front glances off the wall")
	hp0 = h.e_hp[ci]
	s.hit(ci, 100.0, 0.0, "", Vector2(400, 0))
	check(is_equal_approx(hp0 - h.e_hp[ci], 100.0), "a blow from behind him lands in full")
	s.commander.pos = Vector2(300, 400)
	h._chieftain(1.0 / 60.0, s)
	var turned := true
	for k in h.e_pos.size():
		if h.e_guard[k] != Vector2.ZERO:
			turned = turned and h.e_guard[k].dot(Vector2.DOWN) > 0.0
	check(turned, "the wall turns to face the legion")
	while h.guards_alive >= int(cfg.min):
		for k in h.e_pos.size():
			if h.e_guard[k] != Vector2.ZERO:
				h.remove_at(k)
				break
	ci = h.chieftain_index()
	hp0 = h.e_hp[ci]
	s.hit(ci, 100.0, 0.0, "", Vector2(300, 200))
	check(is_equal_approx(hp0 - h.e_hp[ci], 100.0), "with fewer than %d left even blows from in front land" % int(cfg.min))


func test_the_dacian_king_sweeps_and_brings_down_rocks(b: Dictionary) -> void:
	var s := _dacia_sim(b, 951)
	var h := s.horde
	var atk: Dictionary = content.enemies.dacian_king.attacks
	s.commander.pos = Vector2.ZERO
	s.legion.place_all(s.facing_angle)
	var ci := h.spawn_chieftain(Vector2(50, 0))
	for u in s.units:
		u.max_hp = 1e6
		u.hp = 1e6
	check(h.start_sweep(ci, s), "with soldiers in reach he raises his blade")
	check(not h.sweep.is_empty() and h.chief_hold > 0.0, "and stands while a cone fills before him")
	h._sweep_and_leap(ci, 0.1, s)
	var whole := true
	for u in s.units:
		whole = whole and u.hp == 1e6
	check(whole, "nobody is hurt while it fills")
	h._sweep_and_leap(ci, float(atk.sweep.windup), s)
	var cut := 0
	var behind := true
	for u in s.units:
		var to: Vector2 = u.pos - Vector2(50, 0)
		if u.hp < 1e6:
			cut += 1
			behind = behind and to.dot(Vector2.LEFT) > 0.0
	check(cut >= 2 and behind, "then it cuts the soldiers in the cone and only them (%d)" % cut)
	check(h.sweep.is_empty(), "and is spent")
	var n0 := h.foe_lobs.size()
	h.rockfall(ci, s)
	var rocks := h.foe_lobs.slice(n0)
	check(rocks.size() == int(atk.rockfall.count), "rocks come down on %d rings" % int(atk.rockfall.count))
	var on_him := false
	for l in rocks:
		on_him = on_him or (l.to == s.commander.pos and l.get("rock", false))
	check(on_him, "one of them on the commander")
	h.chief_fury = true
	n0 = h.foe_lobs.size()
	h.rockfall(ci, s)
	check(h.foe_lobs.size() - n0 == int(atk.rockfall.fury_count), "more in his second phase")


func test_the_dacian_king_leaps_in_his_second_phase(b: Dictionary) -> void:
	var s := _dacia_sim(b, 952)
	var h := s.horde
	var atk: Dictionary = content.enemies.dacian_king.attacks
	s.commander.pos = Vector2.ZERO
	s.legion.place_all(s.facing_angle)
	var ci := h.spawn_chieftain(Vector2(200, 0))
	h.leap_cd = 0.0
	h._chieftain(1.0 / 60.0, s)
	check(h.leap.is_empty(), "he does not leap while his wall stands")
	h.e_hp[ci] = h.e_max[ci] * 0.49
	h._chieftain(1.0 / 60.0, s)
	check(h.chief_fury and h.guards_alive == 0, "below half health he sends his wall in")
	h.leap_cd = 0.0
	h._chieftain(1.0 / 60.0, s)
	check(not h.leap.is_empty(), "and leaps")
	var ring := false
	for l in h.foe_lobs:
		ring = ring or (l.to == Vector2.ZERO and l.get("slam", false))
	check(ring, "onto a ring marked where the commander stood")
	var hp0: float = s.commander.hp
	var t := 0.0
	while t < float(atk.leap.windup) + 0.05:
		h._chieftain(1.0 / 60.0, s)
		h._chieftain_after(s)
		h._foe_lobs(1.0 / 60.0, s)
		t += 1.0 / 60.0
	check(h.e_pos[h.chieftain_index()].distance_to(Vector2.ZERO) < 40.0, "landing on it")
	check(s.commander.hp < hp0, "and crushing those under him")


func _parthia_sim(b: Dictionary, seed_value: int) -> Sim:
	var s := _gaul_sim(b, seed_value, "parthia")
	s.horde.storm_cd = 1e9
	return s


func test_winning_aegyptus_opens_parthia(b: Dictionary) -> void:
	check(content.ready("provinces", "parthia"), "Parthia is drawn")
	check(content.province_before("parthia") == "aegyptus", "the drawn province before Parthia is Aegyptus")
	var p := _fresh_profile()
	var s := Sim.new(b, content, {"seed": 960, "province": "aegyptus"})
	s.time = 900.0
	s.over = true
	s.victory = true
	p.record_run(s)
	check(p.province_unlocked("parthia"), "winning in Aegyptus opens Parthia")
	_cleanup_profile_files()
	p.free()


func test_parthia_is_open_desert_with_oases_walls_and_dunes(b: Dictionary) -> void:
	var area := Rect2(-4000, -4000, 8000, 8000)
	var t := Terrain.new(961, b.forest, b.ravines)
	t.desert = b.deserts.parthia
	var g := Terrain.new(961, b.forest, b.ravines)
	var kinds := {}
	var solid := 0
	for pr in t.props_in(area):
		kinds[pr[0]] = kinds.get(pr[0], 0) + 1
		if pr[2] > 0.0:
			solid += 1
	var forest_solid := 0
	for pr in g.props_in(area):
		if pr[2] > 0.0:
			forest_solid += 1
	check(kinds.has("palm") and kinds.has("ruined_wall") and kinds.has("dune"), "the desert holds palms, ruined walls and dunes (%s)" % str(kinds.keys()))
	check(not kinds.has("oak") and not kinds.has("fir") and not kinds.has("pine") and not kinds.has("log"), "and no forest")
	check(solid * 3 < forest_solid, "far fewer obstacles than Germania (%d against %d)" % [solid, forest_solid])
	check(Terrain.SOLID.has("palm") and Terrain.SOLID.has("ruined_wall") and not Terrain.SOLID.has("dune"), "palms and walls are solid and dunes are not")
	# Palms grow in small clusters: every palm has another close by.
	var palms: Array = []
	for pr in t.props_in(area):
		if pr[0] == "palm":
			palms.append(pr[1])
	var lone := 0
	for p in palms:
		var mate := false
		for q in palms:
			mate = mate or (q != p and q.distance_to(p) < float(b.deserts.parthia.oasis_radius) * 2.0)
		if not mate:
			lone += 1
	check(lone * 4 < palms.size(), "palms stand in oases (%d of %d alone)" % [lone, palms.size()])
	check(not t.ravines_in(area).is_empty(), "dry wadis still cut the desert")


func test_dunes_slow_the_march(b: Dictionary) -> void:
	var s := _parthia_sim(b, 962)
	s.terrain.add_clearing(Vector2(0, 400), 1.0, [["dune", Vector2(0, 400), 0.0]])
	check(s.terrain.on_dune(Vector2(0, 390)) and not s.terrain.on_dune(Vector2(0, 300)), "the soft sand lies over the dune")
	s.commander.pos = Vector2(0, 200)
	s.update(1.0 / 60.0, Vector2.RIGHT, false)
	var pace := s.speed()
	s.commander.pos = Vector2(0, 392)
	s.update(1.0 / 60.0, Vector2.RIGHT, false)
	check(s.on_sand and is_equal_approx(s.speed(), pace * (1.0 - float(b.deserts.parthia.dune_slow))), "on a dune the legion marches slower (%.0f against %.0f)" % [s.speed(), pace])
	var g := _gaul_sim(b, 962)
	check(not g.terrain.on_dune(Vector2.ZERO), "and other provinces have no dunes")


func test_horse_archers_ride_off_and_shoot_back(b: Dictionary) -> void:
	var s := _parthia_sim(b, 963)
	var h := s.horde
	var cfg: Dictionary = content.enemies.horse_archer
	s.commander.pos = Vector2.ZERO
	s.legion.place_all(s.facing_angle)
	s._rebuild_grids()
	var close := h.spawn("horse_archer", Vector2(s.legion_reach + float(cfg.kite.near) * 0.5, 0))
	var far := h.spawn("horse_archer", Vector2(0, s.legion_reach + float(cfg.kite.near) + 40.0))
	h.e_cd[close] = 0.0
	var gap0 := h.e_pos[close].length()
	var far0 := h.e_pos[far].length()
	h._move(1.0 / 60.0, s)
	check(h.e_pos[close].length() > gap0, "with soldiers close he rides away")
	check(h.sp_pos.size() >= 1 and h.sp_vel[0].dot(Vector2.LEFT) > 0.0, "shooting back at the legion as he goes")
	check(absf(h.e_pos[far].length() - far0) < 1.0, "further off he rides round the legion at range")
	for k in 10:
		h.e_cd[close] = 0.0
		h._move(1.0 / 60.0, s)
	check(h.e_ammo[close] == 0, "until his arrows are spent")
	var gap1 := h.e_pos[close].length()
	h._move(1.0 / 60.0, s)
	check(h.e_pos[close].length() < gap1, "then he rides in to fight")
	check(float(cfg.speed) * float(cfg.kite.speed_mult) > float(content.base_commander.speed), "he outrides the legion")
	check(float(cfg.hp) < float(content.enemies.cataphract.hp), "but falls easily")


func test_cataphracts_charge_with_the_lance_and_turn_arrows(b: Dictionary) -> void:
	var s := _parthia_sim(b, 964)
	var h := s.horde
	var cfg: Dictionary = content.enemies.cataphract
	s.commander.pos = Vector2.ZERO
	s.soldiers.clear()
	s._rebuild_grids()
	var i := h.spawn("cataphract", Vector2(140, 0))
	h.e_cd[i] = 0.0
	h._move(1.0 / 60.0, s)
	check(h.e_dash[i] > 0.0 and h.e_dir[i].dot(Vector2.LEFT) > 0.99, "he lowers his lance and charges straight at the legion")
	var hp0: float = s.commander.hp
	for k in 60:
		s._rebuild_grids()
		h._move(1.0 / 60.0, s)
		if s.commander.hp < hp0:
			break
	check(hp0 - s.commander.hp >= float(cfg.dps) * float(cfg.lance.burst_mult) * h.difficulty("damage") * h.level_mult("damage_mult") * 0.99, "the lance strikes hard (%.1f)" % (hp0 - s.commander.hp))
	check(h.e_strike[i] == h.time, "with a thrust of the lance")
	var c := h.spawn("cataphract", Vector2(600, 0))
	var a := h.spawn("horse_archer", Vector2(600, 200))
	s._rebuild_grids()
	s.shoot("arrow", Vector2(560, 0), h.e_pos[c], 300.0, 10.0, 0)
	s.shoot("arrow", Vector2(560, 200), h.e_pos[a], 300.0, 10.0, 0)
	var c0 := h.e_hp[c]
	var a0 := h.e_hp[a]
	for k in 20:
		s._move_shots(1.0 / 60.0)
	check(is_equal_approx(c0 - h.e_hp[c], 10.0 * (1.0 - float(cfg.armour.arrows))), "his armour turns part of an arrow (%.1f)" % (c0 - h.e_hp[c]))
	check(is_equal_approx(a0 - h.e_hp[a], 10.0), "an unarmoured rider takes it in full")


## Rings a still legion of `men` with twelve of `kind` and returns [slashes, the slashes their pace would give in the time they fought].
func _slashes_in_melee(b: Dictionary, kind: String, province: String, men: int) -> Array:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 5, "province": province})
	s.terrain.clear()
	s.b = b.duplicate()
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	var h := s.horde
	h.next_surge = 1e9
	h.next_band = 1e9
	h.next_cart = 1e9
	h.next_boss = 1e9
	for k in men:
		s.add_soldier("legionary")
	s.legion.place_all(s.facing_angle)
	for u in s.units:
		u.hp = 1e9
		u.max_hp = 1e9
	s._rebuild_grids()
	for k in 12:
		h.spawn(kind, s.commander.pos + Vector2.from_angle(TAU * k / 12) * (s.legion_reach + 20.0))
	var strikes := 0
	var fighting := 0.0
	var dt := 1.0 / 60.0
	for f in 60 * 20:
		h.time += dt
		s._rebuild_grids()
		h.frame += 1
		h._move(dt, s)
		for i in h.e_pos.size():
			if h.e_fighting[i] == 1:
				fighting += dt
			if absf(h.e_strike[i] - h.time) < 0.0001:
				strikes += 1
	var cfg: Dictionary = s.content.enemies[kind]
	return [strikes, fighting / float(cfg.get("slash", cfg.get("thrust", {})).every)]


func test_raiders_in_melee_slash_at_their_own_pace(b: Dictionary) -> void:
	for t in [["khopesh_raider", "aegyptus", 30], ["camel_rider", "parthia", 30], ["khopesh_raider", "aegyptus", 0]]:
		var got := _slashes_in_melee(b, t[0], t[1], t[2])
		check(got[1] > 5.0 and got[0] > got[1] * 0.6 and got[0] < got[1] * 1.5, "%s against %d men slash about as often as their pace (%d against %.0f)" % [t[0], t[2], got[0], got[1]])


func test_a_long_frame_is_played_in_sixtieths(_b: Dictionary) -> void:
	check(Game.steps_for(1.0 / 30.0) == 2 and Game.steps_for(0.02) == 2, "a frame of a thirtieth or a fiftieth is played as two steps")
	check(Game.steps_for(1.0 / 60.0) == 1 and Game.steps_for(1.0 / 144.0) == 1 and Game.steps_for(0.0) == 1, "a sixtieth or less is one step")


func test_a_stunned_king_never_lands_his_leap(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 9, "province": "dacia"})
	s.terrain.clear()
	s.b = b.duplicate()
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	var h := s.horde
	h.next_surge = 1e9
	h.next_band = 1e9
	h.next_cart = 1e9
	h.next_boss = 1e9
	h._p_next = 1e9
	s.commander.hp = 1000.0
	s.commander.max_hp = 1000.0
	var ci := h.spawn_chieftain(s.commander.pos + Vector2(200, 0))
	for t in ["cleave_cd", "sweep_cd", "rockfall_cd", "leap_cd"]:
		h.set(t, 1e9)
	h.chief_fury = true
	h.release_guards()
	s._rebuild_grids()
	check(h.start_leap(ci, s), "the king leaps")
	h.e_stun[ci] = 3.0
	for f in 120:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.commander.hp == 1000.0, "his ring does not land while he is stunned (%.1f lost)" % (1000.0 - s.commander.hp))
	check(h.foe_lobs.is_empty(), "and its mark is gone")


func test_a_wedge_broken_on_the_testudo_frees_its_riders(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 9, "province": "parthia"})
	s.terrain.clear()
	s.b = b.duplicate()
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	var h := s.horde
	h.next_surge = 1e9
	h.next_band = 1e9
	h.next_cart = 1e9
	h.next_boss = 1e9
	h.storm_cd = 1e9
	h._p_next = 1e9
	h.time = 400.0
	s.time = 400.0
	for k in 30:
		s.add_soldier("legionary")
	s.legion.place_all(s.facing_angle)
	for u in s.units:
		u.hp = 1e9
		u.max_hp = 1e9
	s._rebuild_grids()
	var i := h.spawn("cataphract_charge", s.commander.pos + Vector2(200, 0), true)
	h.e_hp[i] = 1e9
	var st: Dictionary = h.boss_state(i)
	st.wedge_cd = 0.0
	var riders: Array = []
	var broke := false
	for f in 60 * 4:
		s.testudo_left = 10.0
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		if riders.is_empty() and not st.wedge.is_empty():
			riders = st.wedge.map(func(w: Array) -> int: return w[0])
		var li := h.e_id.find(h.elite_ids[0]) if not h.elite_ids.is_empty() else -1
		broke = broke or (li >= 0 and h.e_stun[li] > 0.0)
	check(broke and not riders.is_empty(), "the wedge forms and breaks on the shields")
	check(st.wedge.is_empty(), "the broken wedge is let go (%d still held)" % st.wedge.size())
	var free := riders.all(func(id: int) -> bool: return h.e_id.find(id) < 0 or is_finite(h.e_cd[h.e_id.find(id)]))
	check(free, "each rider is soon ready to charge again on his own")


func test_camel_riders_thrust_through_two_ranks(b: Dictionary) -> void:
	var s := _parthia_sim(b, 965)
	var h := s.horde
	var cfg: Dictionary = content.enemies.camel_rider
	var i := h.spawn("camel_rider", Vector2(100, 0))
	var front: Dictionary = s.soldiers[0]
	var back: Dictionary = s.soldiers[1]
	var side: Dictionary = s.soldiers[2]
	front.pos = Vector2(86, 0)
	back.pos = Vector2(70, 0)
	side.pos = Vector2(86, 30)
	for u in [front, back, side]:
		u.max_hp = 1e6
		u.hp = 1e6
	h._slash(i, front.pos - h.e_pos[i], 1.0, s)
	check(front.hp < 1e6 and back.hp < 1e6, "his spear goes through the front man into the one behind")
	check(side.hp == 1e6, "but not the man beside them")
	check(is_equal_approx(1e6 - front.hp, float(cfg.dps) * float(cfg.thrust.damage_mult)), "and strikes hard")
	check(float(cfg.speed) > float(content.enemies.cataphract.speed) and float(cfg.hp) > float(content.enemies.horse_archer.hp) * 2.0, "he is fast and tough")
	check(cfg.has("sprint"), "and runs in, so the hunt sends camels after a legion that runs")


func test_slingers_stones_leave_soldiers_reeling(b: Dictionary) -> void:
	var s := _parthia_sim(b, 966)
	var h := s.horde
	var cfg: Dictionary = content.enemies.parthian_slinger
	s.commander.pos = Vector2.ZERO
	s.legion.place_all(s.facing_angle)
	s._rebuild_grids()
	var i := h.spawn("parthian_slinger", Vector2(s.legion_reach + 60.0, 0))
	h.e_cd[i] = 0.0
	h._move(1.0 / 60.0, s)
	check(h.sp_pos.size() == int(cfg.sling.stones), "he looses a volley of %d stones" % int(cfg.sling.stones))
	var stones := true
	for k in h.sp_kind:
		stones = stones and k == 2
	check(stones, "drawn as stones")
	h.sp_pos.clear(); h.sp_vel.clear(); h.sp_dmg.clear(); h.sp_life.clear(); h.sp_kind.clear()
	var u: Dictionary = s.soldiers[0]
	u.max_hp = 1e6
	u.hp = 1e6
	h._throw(u.pos + Vector2(20, 0), Vector2.LEFT, 1.0, 2)
	s._rebuild_grids()
	for k in 30:
		h._spears(1.0 / 60.0, s)
	var struck: Dictionary = {}
	for so in s.soldiers:
		if so.get("dazed", 0.0) > 0.0:
			struck = so
	check(not struck.is_empty() and is_equal_approx(float(struck.dazed), float(cfg.sling.stun)), "a stone leaves the soldier it strikes reeling")
	struck.cd = 0.0
	h.spawn("horse_archer", struck.pos + Vector2(10, 0))
	s._rebuild_grids()
	s.legion.update(1.0 / 60.0, s)
	check(float(struck.get("struck_at", -1.0)) != s.time and float(struck.dazed) < float(cfg.sling.stun), "and he cannot fight while he reels")
	s.commander.dazed = 0.0
	h._throw(s.commander.pos + Vector2(0, -12), Vector2.DOWN, 0.0, 2)
	s.soldiers.clear()
	s._rebuild_grids()
	for k in 10:
		h._spears(1.0 / 60.0, s)
	check(float(s.commander.get("dazed", 0.0)) == 0.0, "the commander keeps his head")


func test_a_wedge_whose_leader_falls_can_charge_again(b: Dictionary) -> void:
	var s := _parthia_sim(b, 968)
	var h := s.horde
	var i := h.spawn("cataphract_charge", Vector2(220, 0), true)
	var st: Dictionary = h.boss_state(i)
	st.wedge_cd = 0.0
	s._rebuild_grids()
	h._bosses(1.0 / 60.0, s)
	var riders: Array = st.wedge.map(func(w): return w[0])
	h.remove_at(i)
	var ready := 0
	for id in riders:
		var j := h.e_id.find(id)
		if j >= 0 and h.e_cd[j] < INF:
			ready += 1
	check(not riders.is_empty() and ready == riders.size(), "riders whose leader falls before his charge lower their lances again (%d of %d)" % [ready, riders.size()])


func test_each_hastened_barbarian_keeps_his_own_haste(b: Dictionary) -> void:
	var s := _quiet_sim(b, 969)
	var h := s.horde
	var a := h.spawn("barbarian_club", Vector2(300, 0))
	var c := h.spawn("barbarian_club", Vector2(-300, 0))
	h.hasten(a, 4.0, 1.5)
	h.hasten(a, 2.0, 1.35)
	h.hasten(c, 2.0, 1.35)
	check(is_equal_approx(h.e_haste_mult[a], 1.5) and is_equal_approx(h.e_haste[a], 4.0), "a weaker haste does not slow a man already hastened more")
	check(is_equal_approx(h.e_haste_mult[c], 1.35), "and another man's haste is his own")


func test_the_cataphract_leader_leads_a_wedge_down_his_lane(b: Dictionary) -> void:
	var s := _parthia_sim(b, 967)
	var h := s.horde
	var cfg: Dictionary = content.enemies.cataphract_charge.wedge
	s.commander.pos = Vector2.ZERO
	s.legion.place_all(s.facing_angle)
	for u in s.units:
		u.max_hp = 1e6
		u.hp = 1e6
	var i := h.spawn("cataphract_charge", Vector2(220, 0), true)
	var st: Dictionary = h.boss_state(i)
	st.wedge_cd = 0.0
	var n0 := h.e_pos.size()
	s._rebuild_grids()
	h._bosses(1.0 / 60.0, s)
	check(st.rush_warn > 0.0 and is_equal_approx(st.rush_len, float(cfg.length)) and is_equal_approx(st.rush_width, float(cfg.width)), "he marks his lane first")
	check(h.e_pos.size() - n0 == int(cfg.riders) and st.wedge.size() == int(cfg.riders), "and %d cataphracts fall in behind him" % int(cfg.riders))
	var behind := true
	for w in st.wedge:
		var j := h.e_id.find(w[0])
		behind = behind and h.kind_ids[h.e_kind[j]] == "cataphract" and h.e_pos[j].x > h.e_pos[i].x
	check(behind, "in a wedge behind him")
	var start := h.e_pos[i]
	while st.rush_warn > 0.0:
		h._bosses(1.0 / 60.0, s)
		s._rebuild_grids()
		h._move(1.0 / 60.0, s)
		h._bosses_after()
	check(h.e_pos[i] == start, "they wait while the lane fills")
	var hurt := 0
	while st.rush_left > 0.0:
		h._bosses(1.0 / 60.0, s)
		h._bosses_after()
	for u in s.units:
		if u.hp < 1e6:
			hurt += 1
	check(h.e_pos[i].distance_to(start) > float(cfg.length) * 0.8, "then they gallop the length of the lane")
	check(hurt >= 3, "riding down the soldiers in their path (%d)" % hurt)
	check(st.wedge.is_empty() and h.e_pos.size() - n0 == int(cfg.riders), "and the riders stay on the field once it is spent")


func test_the_war_elephant_tramples_and_its_tower_shoots(b: Dictionary) -> void:
	var s := _parthia_sim(b, 968)
	var h := s.horde
	var info: Dictionary = content.enemies.war_elephant
	var cfg: Dictionary = info.trample
	var art := Atlas.new()
	check(float(art.units.war_elephant.idle.south.frames[0][3]) >= float(art.units.cataphract_charge.idle.south.frames[0][3]) * 1.5, "it stands far taller than a cataphract champion")
	check(float(info.radius) >= float(content.enemies.cataphract_charge.radius) * 1.6, "and stands as wide as it is drawn")
	check(float(info.hp) > float(content.enemies.cataphract_charge.hp) * 1.5, "with great health")
	s.commander.pos = Vector2.ZERO
	s.legion.place_all(s.facing_angle)
	for u in s.units:
		u.max_hp = 1e6
		u.hp = 1e6
	# Late in the run the elephant uses its abilities at full pace.
	h.time = 600.0
	var i := h.spawn("war_elephant", Vector2(240, 0), true)
	var st: Dictionary = h.boss_state(i)
	st.trample_cd = 0.0
	st.tower_cd = 0.0
	s._rebuild_grids()
	h._bosses(1.0 / 60.0, s)
	check(st.rush_warn > 0.0 and is_equal_approx(st.rush_len, float(cfg.length)), "it marks the line it will trample")
	var arrows := h.sp_pos.size()
	check(arrows == int(info.tower.arrows), "while the archers in its tower shoot")
	check(s._tally_n[Sim.COUNTED.find("arrow")] == 1 and s._tally_n[Sim.COUNTED.find("kill")] == 0, "and the volley sounds as arrows, not as a death")
	var before: Array = []
	for u in s.soldiers:
		before.append(u.pos)
	s.shake = 0.0
	while st.rush_warn > 0.0:
		h._bosses(1.0 / 60.0, s)
	check(s.shake >= float(cfg.shake) * 0.99, "its stomp shakes the screen")
	while st.rush_left > 0.0:
		h._bosses(1.0 / 60.0, s)
		h._bosses_after()
	var thrown := 0
	for k in s.soldiers.size():
		if s.soldiers[k].hp < 1e6 and s.soldiers[k].pos.distance_to(before[k]) > float(cfg.throw) * 0.9:
			thrown += 1
	check(thrown >= 2, "and the soldiers in its path are trampled and thrown aside (%d)" % thrown)
	check(h.sp_pos.size() > arrows, "the tower kept shooting through the trample")


func test_the_shahs_arrow_storm_and_camel_train(b: Dictionary) -> void:
	var s := _parthia_sim(b, 969)
	var h := s.horde
	var cfg: Dictionary = content.enemies.shah.attacks.storm
	s.commander.pos = Vector2.ZERO
	s.legion.place_all(s.facing_angle)
	var ci := h.spawn_chieftain(Vector2(400, 0))
	var guards := 0
	for k in h.e_pos.size():
		if h.e_guard[k] != Vector2.ZERO and h.kind_ids[h.e_kind[k]] == "cataphract":
			guards += 1
	check(guards > 0 and guards == h.guards_alive, "the shah comes with a guard of cataphracts")
	var n0 := h.e_pos.size()
	h.start_storm(ci, s)
	check(h.e_pos.size() - n0 == int(cfg.riders), "his storm brings %d horse archers to ring the legion" % int(cfg.riders))
	var lobs := 0
	var t := 0.0
	while t < float(cfg.delay) + 0.05:
		h._arrow_storm(1.0 / 60.0, s)
		t += 1.0 / 60.0
	for l in h.foe_lobs:
		if l.get("volley", false):
			lobs += 1
	check(lobs == int(cfg.zones), "their volleys fall on %d marked rings" % int(cfg.zones))
	h.arrow_storm.quiver = int(cfg.train_at)
	h._arrow_storm(1.0 / 60.0, s)
	check(h.arrow_storm.waiting and h.arrow_storm.train.size() == int(cfg.train), "when the quivers run low a camel train comes with fresh arrows")
	var camel := h.e_id.find(h.arrow_storm.train[0])
	h.e_pos[camel] = Vector2(float(cfg.resupply) - 10.0, 0)
	h._arrow_storm(1.0 / 60.0, s)
	check(h.arrow_storm.quiver == int(cfg.quiver) and not h.arrow_storm.waiting, "and the storm goes on once it reaches the riders")
	h.arrow_storm.quiver = int(cfg.train_at)
	h._arrow_storm(1.0 / 60.0, s)
	for id in h.arrow_storm.train.duplicate():
		h.remove_at(h.e_id.find(id))
	h.arrow_storm.quiver = 0
	h._arrow_storm(1.0 / 60.0, s)
	check(h.arrow_storm.is_empty(), "but cutting down the camels ends the storm when the arrows run out")
	h.start_storm(ci, s)
	for id in h.arrow_storm.riders.duplicate():
		h.remove_at(h.e_id.find(id))
	h._arrow_storm(1.0 / 60.0, s)
	check(h.arrow_storm.is_empty(), "as does cutting down every rider")


func test_the_shah_calls_in_his_elephants_when_hurt(b: Dictionary) -> void:
	var s := _parthia_sim(b, 970)
	var h := s.horde
	var call: Dictionary = content.enemies.shah.fury.call
	s.commander.pos = Vector2.ZERO
	var ci := h.spawn_chieftain(Vector2(300, 0))
	var elephants := func() -> int:
		var n := 0
		for k in h.e_pos.size():
			if h.kind_ids[h.e_kind[k]] == "war_elephant":
				n += 1
		return n
	h._chieftain(1.0 / 60.0, s)
	check(elephants.call() == 0, "no elephants while he is whole")
	h.e_hp[ci] = h.e_max[ci] * 0.49
	h._chieftain(1.0 / 60.0, s)
	check(h.chief_fury and elephants.call() == int(call.count), "below half health he calls in %d war elephants" % int(call.count))
	check(h.guards_alive == 0, "and sends his guard in")
	check(not str(content.enemies.shah.text).contains("riding"), "he fights on foot among them")


func _britannia_sim(b: Dictionary, seed_value: int) -> Sim:
	var s := _gaul_sim(b, seed_value, "britannia")
	for t in ["drive_cd", "tribes_cd", "burn_cd"]:
		s.horde.set(t, 1e9)
	s.horde.salvo_cd = 1e9
	s.commander.pos = Vector2.ZERO
	s.legion.place_all(s.facing_angle)
	s._rebuild_grids()
	return s


func test_winning_gaul_opens_britannia(b: Dictionary) -> void:
	check(content.ready("provinces", "britannia"), "Britannia is drawn")
	check(content.provinces.keys().find("britannia") == content.provinces.keys().find("gaul") + 1, "Britannia comes after Gaul on the road")
	check(content.province_before("britannia") == "gaul" and content.province_before("gaul") == "germania", "it follows Gaul, and Gaul follows Germania")
	var p := _fresh_profile()
	var before: Dictionary = p.data.duplicate(true)
	var s := Sim.new(b, content, {"seed": 980, "province": "gaul"})
	s.time = 900.0
	s.over = true
	s.victory = true
	p.record_run(s)
	check(p.province_unlocked("britannia"), "winning in Gaul opens Britannia")
	var lines: Array = SummaryScreen.unlocks(before, p.data, content, "gaul")
	var said := false
	for u in lines:
		said = said or (u.kind == "province" and u.id == "britannia" and str(u.text) == "Britannia is open")
	check(said, "and the summary says Britannia is open")
	var old := _fresh_profile()
	old.data.records["germania"] = {"best_time": 900.0, "longest": 900.0, "won": true, "hard_won": false}
	old.data.unlocked.provinces = ["germania", "britannia"]
	old.open_won_provinces(content)
	check(old.province_unlocked("gaul") and not old.province_unlocked("britannia"), "a profile that opened Britannia straight after Germania waits for Gaul")
	old.free()
	_cleanup_profile_files()
	p.free()


func test_the_map_shows_all_eight_provinces_in_order(b: Dictionary) -> void:
	var host_script := GDScript.new()
	host_script.source_code = "extends Node\nvar content\nvar balance\nvar run_setup := {}\n"
	host_script.reload()
	var host: Node = Node.new()
	host.set_script(host_script)
	host.content = content
	host.balance = b
	host.run_setup = {"province": "germania", "difficulty": "medium", "endless": false, "decimatio": false}
	var map := MapScreen.new(host)
	check(map.road() == ["germania", "gaul", "britannia", "hispania", "aegyptus", "parthia", "dacia", "sarmatia"], "the road runs Germania, Gaul, Britannia, Hispania, Aegyptus, Parthia, Dacia, Sarmatia (%s)" % str(map.road()))
	var saved: Dictionary = Profile.data
	Profile.data = Profile.defaults()
	check(map.state_of("germania") == "open" and map.state_of("gaul") == "locked" and map.state_of("britannia") == "locked", "a new profile has only Germania open and no province in fog")
	check(map.locked_text("britannia") == "Win in Gaul to open", "Britannia waits for a win in Gaul")
	check(map.locked_text("hispania") == "Win in Britannia to open", "Hispania waits for a win in Britannia")
	for id in ["germania", "gaul"]:
		Profile.data.records[id] = {"best_time": 900.0, "longest": 900.0, "won": true, "hard_won": false}
	Profile.open_won_provinces(content)
	check(map.state_of("gaul") == "won" and map.state_of("britannia") == "open", "with Gaul won Britannia is open")
	check(MapScreen.route("gaul", "britannia", 0.0)[0] == MapScreen.spot("gaul"), "and the road runs on from Gaul to it")
	check(map.state_of("hispania") == "locked", "Hispania stays locked until Britannia is won")
	Profile.data.records["britannia"] = {"best_time": 900.0, "longest": 900.0, "won": true, "hard_won": false}
	Profile.open_won_provinces(content)
	check(map.state_of("hispania") == "open", "with Britannia won Hispania is open")
	var to_hispania := MapScreen.route("britannia", "hispania", 0.0)
	check(to_hispania[0] == MapScreen.spot("britannia") and to_hispania[to_hispania.size() - 1] == MapScreen.spot("hispania"), "and the road runs on from Britannia to it")
	check(map.locked_text("aegyptus") == "Win in Hispania to open" and map.state_of("aegyptus") == "locked", "Aegyptus waits for a win in Hispania")
	Profile.data.records["hispania"] = {"best_time": 900.0, "longest": 900.0, "won": true, "hard_won": false}
	Profile.open_won_provinces(content)
	check(map.state_of("aegyptus") == "open", "with Hispania won Aegyptus is open")
	var to_egypt := MapScreen.route("hispania", "aegyptus", 0.0)
	check(to_egypt[0] == MapScreen.spot("hispania") and to_egypt[to_egypt.size() - 1] == MapScreen.spot("aegyptus"), "and the road sails on from Hispania to it")
	check(map.locked_text("sarmatia") == "Win in Dacia to open" and map.state_of("sarmatia") == "locked", "Sarmatia waits for a win in Dacia")
	for id in ["aegyptus", "parthia", "dacia"]:
		Profile.data.records[id] = {"best_time": 900.0, "longest": 900.0, "won": true, "hard_won": false}
	Profile.open_won_provinces(content)
	check(map.state_of("sarmatia") == "open", "with Dacia won Sarmatia is open")
	var to_steppe := MapScreen.route("dacia", "sarmatia", 0.0)
	check(to_steppe[0] == MapScreen.spot("dacia") and to_steppe[to_steppe.size() - 1] == MapScreen.spot("sarmatia"), "and the road runs east from Dacia to it")
	Profile.data = saved
	host.free()


func test_the_map_road_never_crosses_itself(b: Dictionary) -> void:
	var host := _map_host(content, b, "germania")
	var map := MapScreen.new(host)
	var legs: Array = []
	var from := "roma"
	for id in map.road():
		legs.append(MapScreen.route(from, id, 0.0))
		from = id
	var crossings: Array = []
	for i in legs.size():
		for j in range(i + 1, legs.size()):
			# Neighbouring legs share the province between them, so the first and last steps of each are left out where they meet.
			var a: PackedVector2Array = legs[i].slice(0, legs[i].size() - 2) if j == i + 1 else legs[i]
			var c: PackedVector2Array = legs[j].slice(2) if j == i + 1 else legs[j]
			for m in a.size() - 1:
				for n in c.size() - 1:
					if Geometry2D.segment_intersects_segment(a[m], a[m + 1], c[n], c[n + 1]) != null:
						crossings.append("%d/%d" % [i, j])
	check(crossings.is_empty(), "no leg of the road crosses another (%s)" % str(crossings))
	host.free()


func test_hovering_a_province_leaves_the_panel_until_it_is_clicked(b: Dictionary) -> void:
	var host := _map_host(content, b, "germania")
	var map := MapScreen.new(host)
	var ui := Ui.new()
	map.selected = "germania"
	ui.focus = "prov:germania"
	ui.pointer_focus = true
	ui.focus = "prov:gaul"
	map.follow_focus(ui)
	check(map.selected == "germania", "the pointer passing over Gaul leaves Germania's panel and difficulty up")
	map.activate("prov:gaul")
	map.follow_focus(ui)
	check(map.selected == "gaul", "clicking Gaul shows its panel")
	ui.pointer_focus = false
	ui.focus = "prov:britannia"
	map.follow_focus(ui)
	check(map.selected == "britannia", "keys or a gamepad moving to a province still show its panel")
	host.free()


func test_the_map_chooses_the_difficulty_and_keeps_modes_for_a_win(b: Dictionary) -> void:
	var host := _map_host(content, b, "germania")
	var map := MapScreen.new(host)
	var saved: Dictionary = Profile.data
	Profile.data = Profile.defaults()
	Profile.data.records["germania"] = {"best_time": 900.0, "longest": 900.0, "won": true, "hard_won": false}
	Profile.open_won_provinces(content)
	map.activate("easy:gaul")
	check(host.run_setup.difficulty == "easy" and host.run_setup.province == "gaul", "Easy is chosen, and with it the province of the panel")
	check(Profile.data.choices.difficulty == "easy" and Profile.data.choices.province == "gaul", "both are kept in the save")
	map.activate("hard:gaul")
	check(host.run_setup.difficulty == "hard", "Hard needs no win")
	map.activate("endless:gaul")
	check(not host.run_setup.endless, "Endless waits for a win in the province")
	Profile.data.records["gaul"] = {"best_time": 900.0, "longest": 900.0, "won": true, "hard_won": false}
	map.activate("endless:gaul")
	check(host.run_setup.endless, "and opens once it is won")
	map.activate("prov:germania")
	check(not host.run_setup.endless and host.run_setup.difficulty == "hard", "another province clears the modes but keeps the difficulty")
	Profile.data = saved
	host.free()


func test_britannia_is_moorland_with_stone_circles_bogs_and_heather(b: Dictionary) -> void:
	var area := Rect2(-4000, -4000, 8000, 8000)
	var t := Terrain.new(981, b.forest, b.ravines)
	t.moor = b.moors.britannia
	var g := Terrain.new(981, b.forest, b.ravines)
	var kinds := {}
	var circles: Array = []
	var stones := {}
	var blockers := 0
	for pr in t.props_in(area):
		kinds[pr[0]] = kinds.get(pr[0], 0) + 1
		if pr[0] == "stone_circle":
			circles.append(pr[1])
		elif pr[0] == "" and is_equal_approx(pr[2], float(b.moors.britannia.stone_radius)):
			blockers += 1
			stones[pr[1]] = true
	var trees := 0
	var forest_trees := 0
	for pr in t.props_in(area):
		trees += 1 if Terrain.TREES.has(pr[0]) else 0
	for pr in g.props_in(area):
		forest_trees += 1 if Terrain.TREES.has(pr[0]) else 0
	check(kinds.has("stone_circle") and kinds.has("bog") and kinds.has("heather"), "the moor holds stone circles, bog pools and heather (%s)" % str(kinds.keys()))
	check(trees > 0 and trees * 2 < forest_trees, "with a few forest ridges, far fewer trees than Germania (%d against %d)" % [trees, forest_trees])
	var missing := 0
	for c in circles:
		if area.grow(-200.0).has_point(c):
			for off in b.moors.britannia.circle_stones:
				missing += 0 if stones.has(c + Vector2(float(off[0]), float(off[1]))) else 1
	check(blockers > 0 and missing == 0, "every standing stone is solid (%d missing)" % missing)
	check(not Terrain.SOLID.has("bog") and not Terrain.SOLID.has("heather"), "bogs and heather do not block")
	# A whole circle's stones stand round one middle, with a gap where stones are missing.
	var cfg: Dictionary = b.moors.britannia
	var biggest := 0.0
	var first: Vector2 = circles[0]
	var ring: Array = circles.filter(func(q: Vector2) -> bool: return q.distance_to(first) <= float(cfg.circle_radius) * 2.0 + 1.0)
	var angles: Array = []
	var mid := Vector2.ZERO
	for q in ring:
		mid += q
	mid /= ring.size()
	for q in ring:
		angles.append((q - mid).angle())
	angles.sort()
	for k in angles.size():
		var next: float = angles[(k + 1) % angles.size()] + (TAU if k == angles.size() - 1 else 0.0)
		biggest = maxf(biggest, next - angles[k])
	check(ring.size() <= int(cfg.circle_count) - int(cfg.circle_gap) and biggest > TAU / float(cfg.circle_count) * 2.5, "each circle has an opening to march in by")


func test_bogs_slow_the_march_more_than_dunes(b: Dictionary) -> void:
	var s := _britannia_sim(b, 982)
	s.terrain.add_clearing(Vector2(0, 400), 1.0, [["bog", Vector2(0, 400), 0.0]])
	var lift := float(b.moors.britannia.bog_lift)
	check(s.terrain.in_bog(Vector2(0, 400 - lift)) and not s.terrain.in_bog(Vector2(0, 300)), "the water lies over the pool")
	s.commander.pos = Vector2(0, 200)
	s.update(1.0 / 60.0, Vector2.RIGHT, false)
	var pace := s.speed()
	s.commander.pos = Vector2(0, 400 - lift)
	s.update(1.0 / 60.0, Vector2.RIGHT, false)
	check(s.in_bog and is_equal_approx(s.speed(), pace * (1.0 - float(b.moors.britannia.bog_slow))), "in a bog the legion marches slower (%.0f against %.0f)" % [s.speed(), pace])
	check(float(b.moors.britannia.bog_slow) > float(b.deserts.parthia.dune_slow), "slower than on a dune")
	check(not _gaul_sim(b, 982).terrain.in_bog(Vector2.ZERO), "and other provinces have no bogs")


func test_painted_warriors_charge_through_the_crowd_and_frighten(b: Dictionary) -> void:
	var s := _britannia_sim(b, 983)
	var h := s.horde
	var cfg: Dictionary = content.enemies.painted_warrior.fearless
	var i := h.spawn("painted_warrior", Vector2(s.legion_reach + 90.0, 0))
	for k in 6:
		h.spawn("painted_warrior", Vector2(s.legion_reach + 70.0 - k * 2.0, (k - 2.5) * 3.0))
	for k in h.e_pos.size():
		h.e_cd[k] = 1e9
	h.e_cd[i] = 0.0
	h.rebuild_grid()
	h._move(1.0 / 60.0, s)
	check(h.e_dash[i] > 0.0, "he starts a charge")
	var x0 := h.e_pos[i].x
	for k in 6:
		h.rebuild_grid()
		h._move(1.0 / 60.0, s)
	var want := float(content.enemies.painted_warrior.speed) * float(b.enemy_speed_mult) * float(cfg.speed_mult) * 6.0 / 60.0
	check(absf((x0 - h.e_pos[i].x) - want) < 1.0, "the crowd in front does not shove him aside (%.1f of %.1f)" % [x0 - h.e_pos[i].x, want])
	for u in s.soldiers:
		u.afraid = 0.0
	var front: Dictionary = s.soldiers[0]
	for u in s.soldiers:
		if u.pos.x > front.pos.x:
			front = u
	h.e_pos[i] = front.pos + Vector2(Sim.UNIT_RADIUS + 6.0, 0)
	h.e_dash[i] = 0.5
	h.e_dir[i] = Vector2.LEFT
	s._rebuild_grids()
	h._move(1.0 / 60.0, s)
	var scared := 0
	for u in s.soldiers:
		if float(u.get("afraid", 0.0)) > 0.0:
			scared += 1
	check(scared >= 1 and float(front.get("afraid", 0.0)) > 0.0, "his battle cry frightens the soldiers he strikes (%d)" % scared)
	s.legion.update(1.0 / 60.0, s)
	check(is_equal_approx(float(front.haste), 1.0 - float(cfg.cry_slow)), "who strike more slowly while it lasts")
	front.afraid = 0.0
	s.legion.update(1.0 / 60.0, s)
	check(is_equal_approx(float(front.haste), 1.0), "and at full pace once they steady")


func test_briton_slingers_loose_stone_volleys_from_far_off(b: Dictionary) -> void:
	var s := _britannia_sim(b, 984)
	var h := s.horde
	var cfg: Dictionary = content.enemies.briton_slinger
	check(float(cfg.range) > float(content.enemies.parthian_slinger.range) + 30.0, "they throw from further off than Parthia's slingers")
	var far := s.legion_reach + float(cfg.range) - 10.0
	h.spawn("briton_slinger", Vector2(far, 0))
	h.spawn("briton_slinger", Vector2(0, far))
	h.rebuild_grid()
	h.salvo_now = false
	h._move(1.0 / 60.0, s)
	check(h.sp_pos.size() == 0, "they hold their stones until the volley")
	h.salvo_now = true
	h._move(1.0 / 60.0, s)
	check(h.sp_pos.size() == 2 * int(cfg.salvo.arrows), "then loose together, %d stones each" % int(cfg.salvo.arrows))
	var stones := true
	for k in h.sp_kind:
		stones = stones and k == 2
	check(stones, "drawn as stones")
	h.sp_pos.clear(); h.sp_vel.clear(); h.sp_dmg.clear(); h.sp_life.clear(); h.sp_kind.clear()
	for so in s.soldiers:
		so.max_hp = 1e6
		so.hp = 1e6
	var u: Dictionary = s.soldiers[0]
	h._throw(u.pos + Vector2(20, 0), Vector2.LEFT, 1.0, 2)
	s._rebuild_grids()
	for k in 30:
		h._spears(1.0 / 60.0, s)
	var dazed := false
	var hurt := false
	for so in s.soldiers:
		dazed = dazed or float(so.get("dazed", 0.0)) > 0.0
		hurt = hurt or so.hp < 1e6
	check(hurt and not dazed, "their stones hurt but do not stun")


func test_druid_acolytes_tend_the_warriors_round_them(b: Dictionary) -> void:
	var s := _britannia_sim(b, 985)
	var h := s.horde
	var cfg: Dictionary = content.enemies.druid_acolyte
	var at := Vector2(s.legion_reach + float(cfg.range) - 10.0, 0)
	var a := h.spawn("druid_acolyte", at)
	var w := h.spawn("painted_warrior", at + Vector2(-30, 0))
	var far := h.spawn("painted_warrior", at + Vector2(0, float(cfg.tend.radius) + 40.0))
	for j in [w, far]:
		h.e_hp[j] = h.e_max[j] * 0.3
		h.e_cd[j] = 1e9
	h.e_cd[a] = 0.0
	h.rebuild_grid()
	h._move(1.0 / 60.0, s)
	check(is_equal_approx(h.e_hp[w], h.e_max[w] * (0.3 + float(cfg.tend.share))), "he heals the wounded warrior beside him")
	check(is_equal_approx(h.e_hp[far], h.e_max[far] * 0.3), "but not one beyond his reach")
	var other := h.spawn("druid_acolyte", at + Vector2(0, 10))
	h.e_cd[other] = 0.0
	h.e_cd[a] = 1e9
	h.rebuild_grid()
	h._move(1.0 / 60.0, s)
	check(is_equal_approx(h.e_hp[w], h.e_max[w] * (0.3 + float(cfg.tend.share))), "a second acolyte beside him heals the same warrior no faster")
	h.remove_at(other)
	check(h.sp_pos.is_empty() and h.e_ammo[a] == int(b.ranged.throws), "he throws nothing and keeps to his work")
	check(float(cfg.hp) < float(content.enemies.painted_warrior.hp) and float(cfg.tend.share) < float(content.enemies.war_priest.mend.share), "he is fragile, and weaker than a war priest")
	var d0 := h.e_pos[a].length()
	for k in 60:
		h.rebuild_grid()
		h._move(1.0 / 60.0, s)
	check(h.e_pos[a].length() > s.legion_reach + 20.0 and absf(h.e_pos[a].length() - d0) < 30.0, "and he stays back from the legion")


func test_only_a_few_druid_acolytes_are_alive_at_once(b: Dictionary) -> void:
	var s := _britannia_sim(b, 987)
	var h := s.horde
	var most := int(content.enemies.druid_acolyte.most)
	for k in most:
		h.spawn("druid_acolyte", Vector2(300, k * 20))
	h.time = 1200.0
	var more := 0
	for k in 400:
		more += 1 if h._pick_ordinary() == "druid_acolyte" else 0
	check(most > 0 and more == 0, "with %d acolytes alive the stream sends no more" % most)


func test_chariots_pass_along_the_flank_throwing_javelins(b: Dictionary) -> void:
	var s := _britannia_sim(b, 986)
	var h := s.horde
	var cfg: Dictionary = content.enemies.chariot
	var art := Atlas.new()
	check(float(art.units.chariot.idle.south.frames[0][3]) >= float(art.units.painted_warrior.idle.south.frames[0][3]) * 1.4 and float(cfg.radius) >= float(content.enemies.painted_warrior.radius) * 1.8, "a chariot is drawn larger than a foot soldier, and as wide")
	var i := h.spawn("chariot", Vector2(500, 60))
	h.e_ammo[i] = 0
	var nearest := INF
	var passes := 0
	var close := false
	var thrown := 0
	for k in 1200:
		h.rebuild_grid()
		var before := h.sp_pos.size()
		h._move(1.0 / 60.0, s)
		thrown += maxi(0, h.sp_pos.size() - before)
		h.sp_pos.clear(); h.sp_vel.clear(); h.sp_dmg.clear(); h.sp_life.clear(); h.sp_kind.clear()
		var d := h.e_pos[i].length()
		nearest = minf(nearest, d)
		if d < s.legion_reach + float(cfg.drive.gap) + 40.0 and not close:
			close = true
			passes += 1
		elif d > s.legion_reach + float(cfg.drive.gap) + 120.0:
			close = false
	check(nearest > s.legion_reach + 4.0, "it never drives into the ranks (%.0f against a reach of %.0f)" % [nearest, s.legion_reach])
	check(passes >= 2, "it passes the legion and swings round for another pass (%d)" % passes)
	check(thrown >= 3, "throwing javelins as it goes (%d)" % thrown)
	check(h.e_fighting[i] == 0, "and never stops to fight")
	var j := h.spawn("chariot", Vector2(s.legion_reach + float(cfg.drive.gap) + 20.0, -60))
	h.e_ammo[j] = 1
	h.e_dir[j] = Vector2.DOWN
	var n0 := h.e_pos.size()
	for k in 40:
		h.rebuild_grid()
		h._move(1.0 / 60.0, s)
	var dropped := 0
	for k in range(n0, h.e_pos.size()):
		dropped += 1 if h.kind_ids[h.e_kind[k]] == str(cfg.drop.kind) else 0
	check(dropped == int(cfg.drop.count) and h.e_ammo[j] == 0, "a chariot carrying warriors sets %d down beside the legion, once" % int(cfg.drop.count))


func test_the_scythed_chariot_cuts_down_its_lane_and_comes_again(b: Dictionary) -> void:
	var s := _britannia_sim(b, 987)
	var h := s.horde
	var cfg: Dictionary = content.enemies.chariot_charge.scythe
	for u in s.units:
		u.max_hp = 1e6
		u.hp = 1e6
	var i := h.spawn("chariot_charge", Vector2(220, 0), true)
	var st: Dictionary = h.boss_state(i)
	st.scythe_cd = 0.0
	s._rebuild_grids()
	h._bosses(1.0 / 60.0, s)
	check(st.rush_warn > 0.0 and is_equal_approx(st.rush_len, float(cfg.length)), "it marks its lane first")
	var start := h.e_pos[i]
	while st.rush_warn > 0.0:
		h._bosses(1.0 / 60.0, s)
		h._bosses_after()
	check(h.e_pos[i] == start, "and waits while the lane fills")
	while st.rush_left > 0.0:
		h._bosses(1.0 / 60.0, s)
		h._bosses_after()
	var cut := 0
	for u in s.units:
		if u.hp < 1e6:
			cut += 1
	check(h.e_pos[i].distance_to(start) > float(cfg.length) * 0.8, "then drives the length of the lane, through and past the legion")
	check(cut >= 4, "cutting every soldier it passes (%d)" % cut)
	check(st.rush_warn > 0.0 and is_equal_approx(st.rush_total, float(cfg.again_warn)) and st.rush_dir.dot(-h.e_pos[i].normalized()) > 0.9, "then turns and marks a new lane back at the legion")
	while st.rush_warn > 0.0 or st.rush_left > 0.0:
		h._bosses(1.0 / 60.0, s)
		h._bosses_after()
	check(st.rush_warn <= 0.0 and st.passes == 0 and st.scythe_cd > 0.0, "after %d passes it rests (%.2f %d %.1f)" % [int(cfg.passes), st.rush_warn, st.passes, st.scythe_cd])


func test_the_druid_calls_fire_from_the_sky_and_rouses_warriors(b: Dictionary) -> void:
	var s := _britannia_sim(b, 988)
	var h := s.horde
	var info: Dictionary = content.enemies.druid
	var i := h.spawn("druid", Vector2(200, 0), true)
	var st: Dictionary = h.boss_state(i)
	st.rouse_cd = 1e9
	st.fire_cd = 0.0
	h._bosses(1.0 / 60.0, s)
	var rings: Array = h.foe_lobs.filter(func(l: Dictionary) -> bool: return l.get("sky", false))
	check(rings.size() == int(info.sky_fire.count), "he marks %d rings for fire from the sky" % int(info.sky_fire.count))
	var spread := 0.0
	var later := true
	for k in rings.size():
		spread = maxf(spread, rings[k].to.distance_to(rings[0].to))
		if k > 0:
			later = later and rings[k].dur > rings[k - 1].dur
	check(spread > float(info.sky_fire.radius) * 2.0 and later, "in a line across the legion, falling one after another")
	var hp0: float = s.commander.hp
	for k in 180:
		h._foe_lobs(1.0 / 60.0, s)
	check(h.foe_lobs.is_empty() and s.commander.hp < hp0, "the fire burns those under it")
	var fx := s.effects.filter(func(e: Dictionary) -> bool: return e.kind == "skyfire")
	check(fx.size() == int(info.sky_fire.count), "each ring ends in a swirl of flame")
	var w := h.spawn("painted_warrior", h.e_pos[i] + Vector2(40, 0))
	h.e_hp[w] = h.e_max[w] * 0.4
	h.rebuild_grid()
	st.rouse_cd = 0.0
	st.fire_cd = 1e9
	h._bosses(1.0 / 60.0, s)
	check(is_equal_approx(h.e_hp[w], h.e_max[w] * (0.4 + float(info.rouse.share))) and h.e_slow[w] > 1.0, "his chant heals the warriors round him and sends them running in")
	check(not info.has("mend") and not info.has("curse") and not info.has("blink"), "unlike the war priest")


func test_the_warrior_queen_drives_round_the_legion(b: Dictionary) -> void:
	var s := _britannia_sim(b, 989)
	var h := s.horde
	var cfg: Dictionary = content.enemies.warrior_queen.attacks.drive
	for k in 16:
		s.add_soldier("legionary")
	s.legion.place_all(s.facing_angle)
	s._rebuild_grids()
	for u in s.units:
		u.max_hp = 1e6
		u.hp = 1e6
	var ci := h.spawn_chieftain(Vector2(250, 0))
	var guards := 0
	for k in h.e_pos.size():
		guards += 1 if h.e_guard[k] != Vector2.ZERO and h.kind_ids[h.e_kind[k]] == "painted_warrior" else 0
	check(guards > 0, "she comes with painted warriors round her")
	h.drive_cd = 0.0
	h._chieftain(1.0 / 60.0, s)
	check(not h.drive.is_empty() and h.drive.t < h.drive.warn, "she marks her path first")
	var pts: PackedVector2Array = h.drive.pts
	var turned := 0.0
	var mid := pts[pts.size() / 2]
	for k in range(2, pts.size() - 1):
		turned += absf((pts[k] - pts[k - 1]).angle_to(pts[k - 1] - pts[k - 2]))
	check(turned > 2.5 and mid.length() < s.legion_reach + float(cfg.outer) + 1.0, "a path that sweeps round the legion through its outer ranks")
	var start := h.e_pos[ci]
	var t := 0.0
	while t < float(cfg.warn) - 0.05:
		h._chieftain(1.0 / 60.0, s)
		h._chieftain_after(s)
		t += 1.0 / 60.0
	check(h.e_pos[ci] == start, "and waits while it fills")
	var far := 0.0
	while not h.drive.is_empty():
		h._chieftain(1.0 / 60.0, s)
		h._chieftain_after(s)
		far = maxf(far, h.e_pos[ci].distance_to(start))
	var hurt := 0
	for u in s.units:
		if u.hp < 1e6:
			hurt += 1
	check(far > 150.0 and hurt >= 3, "then drives her chariot along it, riding down the soldiers in her way (%d)" % hurt)


func test_the_warrior_queen_calls_the_tribes_and_burns_the_land(b: Dictionary) -> void:
	var s := _britannia_sim(b, 990)
	var h := s.horde
	var atk: Dictionary = content.enemies.warrior_queen.attacks
	var ci := h.spawn_chieftain(Vector2(300, 0))
	var n0 := h.e_pos.size()
	h.tribes_cd = 0.0
	h._chieftain(1.0 / 60.0, s)
	var sides := {}
	for k in range(n0, h.e_pos.size()):
		sides[int(round(h.e_pos[k].angle() / (TAU / 8.0)))] = true
	var per_side := int((float(b.war_band.size_start) + float(b.war_band.size_growth) * h.time) * float(atk.tribes.mult) * h.difficulty("spawn"))
	check(h.e_pos.size() - n0 >= int(atk.tribes.sides) * per_side and sides.size() >= int(atk.tribes.sides), "she calls the tribes from %d sides at once (%d warriors)" % [sides.size(), h.e_pos.size() - n0])
	h.burn_cd = 0.0
	h._chieftain(1.0 / 60.0, s)
	check(h.marks.filter(func(m: Dictionary) -> bool: return m.kind == "fire").is_empty(), "she does not burn the land while she is whole")
	h.e_hp[ci] = h.e_max[ci] * 0.49
	h.burn_cd = 0.0
	h._chieftain(1.0 / 60.0, s)
	var fires: Array = h.marks.filter(func(m: Dictionary) -> bool: return m.kind == "fire")
	check(h.chief_fury and fires.size() == int(atk.burn.rings), "below half health she marks %d rings to burn" % int(atk.burn.rings))
	check(fires.any(func(m: Dictionary) -> bool: return m.pos == s.commander.pos), "one on the commander")
	for k in int(float(atk.burn.warn) * 60.0) + 2:
		h._marks(1.0 / 60.0, s)
	var burning: Array = h.storms.filter(func(z: Dictionary) -> bool: return z.get("fire", false))
	check(burning.size() == int(atk.burn.rings) and h.marks.is_empty(), "each catches fire when its warning runs out")
	var hp0: float = s.commander.hp
	for k in 60:
		h._storms(1.0 / 60.0, s)
	check(s.commander.hp < hp0 and h.frost_slow == 0.0, "and burns those in it without slowing the march")
	for k in int(float(atk.burn.seconds) * 60.0):
		h._storms(1.0 / 60.0, s)
	check(h.storms.is_empty(), "until the fire dies down")


## How many steps of the route map round the commander pass through a solid prop, from each open square's centre to the next open square's.
func _route_steps_through_solids(s: Sim) -> int:
	var t := s.terrain
	var bad := 0
	for c in Terrain.FN * Terrain.FN:
		var dir: Vector2 = t.flow_dir[c]
		var from := t.flow_origin + (Vector2(c % Terrain.FN, c / Terrain.FN) + Vector2(0.5, 0.5)) * Terrain.FLOW_CELL
		if dir == Vector2.ZERO or not t.is_open(from):
			continue
		var to := from + Vector2(signf(dir.x), signf(dir.y)) * Terrain.FLOW_CELL
		# A pocket of open ground walled in by the forest leads out through the trees, which is meant.
		if not t.is_open(to):
			continue
		var hit := false
		for q in [from, (from + to) / 2.0, to]:
			var gx := floori((q.x - t.origin.x) / Terrain.CELL)
			var gy := floori((q.y - t.origin.y) / Terrain.CELL)
			if hit or gx < 0 or gy < 0 or gx >= Terrain.GN or gy >= Terrain.GN:
				continue
			var gc := gx + gy * Terrain.GN
			for n in range(t.start[gc], t.start[gc + 1]):
				var so: Vector3 = t.solid[t.items[n]]
				var at := Vector2(so.x, so.y)
				if Geometry2D.get_closest_point_to_segment(at, from, to).distance_to(at) < so.z:
					hit = true
					break
		if hit:
			bad += 1
	return bad


func test_the_route_map_never_leads_through_a_prop(b: Dictionary) -> void:
	for province in ["germania", "gaul"]:
		for seed_value in [1, 2, 3]:
			var s := Sim.new(b, content, {"seed": seed_value, "province": province})
			var worst := 0
			for at in [Vector2.ZERO, Vector2(900, 300), Vector2(-700, -800)]:
				s.commander.pos = at
				s.terrain.refresh(at)
				s.terrain.update_flow(at)
				worst = maxi(worst, _route_steps_through_solids(s))
			check(worst == 0, "in %s seed %d no step of the route map passes through a tree, rock or blocker (%d do)" % [province, seed_value, worst])


## A good run's banked denarii with no upgrades and with every one, from the smart balance bot reaching about 16 minutes.
const GOOD_RUN := [14000.0, 24000.0]


## How many good runs pay for every rank of every capped upgrade, a run earning more as more of them are bought.
func _runs_to_max(qm: Dictionary) -> int:
	var total := 0.0
	for id in qm:
		if not qm[id].get("camp", false):
			for cost in qm[id].costs:
				total += float(cost)
	var spent := 0.0
	var runs := 0
	while spent < total:
		runs += 1
		spent += GOOD_RUN[0] + (GOOD_RUN[1] - GOOD_RUN[0]) * spent / total
	return runs


func test_quartermaster_costs_rise_steeply_and_take_many_runs(_b: Dictionary) -> void:
	var qm: Dictionary = content.quartermaster
	for id in qm:
		var costs: Array = qm[id].costs
		check(qm[id].get("repeat", false) or int(costs[0]) <= int(GOOD_RUN[0]), "%s's first rank costs no more than a good run" % id)
		for r in range(1, costs.size()):
			var steep := 1.2 if qm[id].get("camp", false) else 1.6
			check(float(costs[r]) >= float(costs[r - 1]) * steep, "%s rank %d costs at least %.1f times rank %d" % [id, r + 1, steep, r])
	var runs := _runs_to_max(qm)
	check(runs >= 25 and runs <= 40, "maxing every upgrade takes 25 to 40 good runs (%d)" % runs)
	var arch := 0
	for cost in qm.triumphal_arch.costs:
		arch += int(cost)
	check(arch >= int(GOOD_RUN[1]) * 10, "the arch takes at least ten more good runs to finish")


func test_a_triumph_can_be_held_again_and_again_once_the_arch_stands(_b: Dictionary) -> void:
	var p := _fresh_profile()
	p.data.denarii = 100000000
	check(p.next_cost("triumph", content) == -1 and p.waiting_for("triumph", content) == "triumphal_arch", "no triumph before the arch is built")
	check(not p.buy("triumph", content), "and none can be bought")
	for r in int(content.quartermaster.triumphal_arch.ranks):
		p.buy("triumphal_arch", content)
	check(p.waiting_for("triumph", content) == "", "the finished arch opens the triumphs")
	var last := 0
	var rising := true
	for k in 40:
		var cost: int = p.next_cost("triumph", content)
		rising = rising and cost > last
		last = cost
		var before: int = p.data.denarii
		check(p.buy("triumph", content) and before - p.data.denarii == cost, "triumph %d costs what it says" % (k + 1))
	check(rising, "each triumph costs more than the last")
	check(p.rank("triumph") == 40 and p.next_cost("triumph", content) > 0, "and there is always another")
	check(ProfileScript.repeat_cost(40000.0, 1.1, 0) == 40000 and ProfileScript.repeat_cost(40000.0, 1.1, 1) == 44000, "the cost grows by its rate, rounded")
	p.free()
	_cleanup_profile_files()


func test_a_locked_commander_can_be_bought_with_denarii(_b: Dictionary) -> void:
	for id in content.commanders:
		var free: bool = content.commanders[id].get("unlock", {}).get("type", "free") == "free"
		check(free or ProfileScript.commander_price(content.commanders[id]) > 0, "%s has a price" % id)
	var p := _fresh_profile()
	var price := ProfileScript.commander_price(content.commanders.engineer)
	p.data.denarii = price - 1
	check(not p.buy_commander("engineer", content) and not p.commander_unlocked("engineer"), "too few denarii buy no commander")
	p.data.denarii = price + 5
	check(p.buy_commander("engineer", content) and p.commander_unlocked("engineer"), "his price unlocks him")
	check(p.data.denarii == 5, "and is paid")
	check(not p.buy_commander("engineer", content) and p.data.denarii == 5, "he is not bought twice")
	check(not p.buy_commander("tribune", content), "the free commander is not for sale")
	var tag := CommandersScreen.locked_tag(content.commanders.legate, content)
	check(tag.contains(str(ProfileScript.commander_price(content.commanders.legate))), "his locked tag names his price")
	p.free()
	_cleanup_profile_files()


func test_a_rich_old_save_still_has_much_to_buy(_b: Dictionary) -> void:
	var p := _fresh_profile()
	var old_caps := {"start_health": 5, "start_soldiers": 3, "move_speed": 4, "damage": 5, "pickup_radius": 3, "rerolls": 3, "banishes": 3,
		"testudo_charge": 4, "experience": 4, "denarii": 5, "attack_speed": 4, "soldier_health": 4, "regeneration": 3, "missile_range": 3,
		"testudo_hold": 3, "armour": 4, "cart_rewards": 3, "recruit_cap": 3, "level_ease": 3, "choice_luck": 3}
	for id in old_caps:
		p.data.ranks[id] = mini(old_caps[id], int(content.quartermaster[id].ranks))
	p.data.denarii = 56000
	var left := 0
	var buyable := 0
	for id in content.quartermaster:
		var cost: int = p.next_cost(id, content)
		if cost > 0 and cost <= 56000:
			buyable += 1
		if not content.quartermaster[id].get("repeat", false):
			for r in range(p.rank(id), int(content.quartermaster[id].ranks)):
				left += int(content.quartermaster[id].costs[r])
	check(buyable >= 3, "a save that maxed the old ranks can buy something at once (%d)" % buyable)
	check(left > 56000 * 4, "and has far more to buy than its balance (%d left)" % left)
	p.free()
	_cleanup_profile_files()


func test_a_screen_can_send_a_key_to_a_chosen_button(_b: Dictionary) -> void:
	var u := Ui.new()
	u.begin()
	u.register(Rect2(0, 0, 10, 10), "a")
	u.register(Rect2(20, 0, 10, 10), "b")
	u.register(Rect2(300, 200, 10, 10), "c")
	u.link("a", Vector2.RIGHT, "c")
	u.end()
	u.focus = "a"
	u.move(Vector2.RIGHT)
	check(u.focus == "c", "a link sends focus where the screen chose")
	u.move(Vector2.LEFT)
	check(u.focus == "b", "without one it goes to the nearest button that way")
	var pts := MapScreen.road_points(Vector2(0, 0), Vector2(100, 0), 0.2)
	check(pts[0] == Vector2(0, 0) and pts[pts.size() - 1] == Vector2(100, 0) and absf(pts[12].y) > 5.0, "the road runs from place to place and bends")


func test_the_map_puts_each_province_where_it_lies(_b: Dictionary) -> void:
	check(MapScreen.spot("dacia") == MapScreen.project(Vector2(24.5, 46.0)).round(), "a province sits at its longitude and latitude")
	check(Rect2(0, 0, Ui.W, Ui.H - 24).has_point(MapScreen.spot("parthia")), "Parthia lies on the map above the key hints")
	check(MapScreen.spot("britannia").x < MapScreen.spot("gaul").x and MapScreen.spot("britannia").y < MapScreen.spot("gaul").y, "Britannia lies north-west of Gaul")
	check(MapScreen.spot("hispania").x < MapScreen.spot("gaul").x and MapScreen.spot("hispania").y > MapScreen.spot("gaul").y, "Hispania lies south-west of Gaul")
	check(MapScreen.spot("aegyptus").x > MapScreen.spot("dacia").x and MapScreen.spot("aegyptus").y > MapScreen.spot("dacia").y and Rect2(0, 0, Ui.W, Ui.H - 24).has_point(MapScreen.spot("aegyptus")), "Aegyptus lies south-east across the sea, above the key hints")
	check(MapScreen.spot("sarmatia").x > MapScreen.spot("dacia").x and MapScreen.spot("sarmatia").y < MapScreen.spot("dacia").y and not MapScreen.panel_rect().has_point(MapScreen.spot("sarmatia")), "Sarmatia lies north-east of Dacia, clear of the panel")
	var road := MapScreen.route("roma", "germania", 0.0)
	var alps := MapScreen.project(Vector2(11.5, 47.0))
	var near := INF
	for p in road:
		near = minf(near, p.distance_to(alps))
	check(road[0] == MapScreen.spot("roma") and road[road.size() - 1] == MapScreen.spot("germania") and near < 2.0, "the road from Rome to Germania crosses the Alps")


func test_the_objective_badges_keep_their_size(b: Dictionary) -> void:
	var before := Ui.scale
	for scale in [1, 2]:
		Ui.set_text_size(scale, b)
		check(Hud.badge_radius() >= 14.0 and Hud.badge_radius() <= 17.0 and Hud.tip_length() >= 10.0, "an objective badge stays its compact size at text size %d" % scale)
	Ui.set_text_size(before, b)


func test_barbarians_go_round_a_wood_without_standing_still(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1601)
	s.terrain.empty = false
	var wood := {}
	for cx in range(-8, 9):
		for cy in range(-8, 9):
			wood[Vector2i(cx, cy)] = []
	for row in 4:
		for col in 14:
			var at := Vector2(-150 + col * 22 + (11 if row % 2 == 1 else 0), 100 + row * 19)
			var key := Vector2i(floori(at.x / Terrain.CHUNK), floori(at.y / Terrain.CHUNK))
			var list: Array = wood.get(key, [])
			list.append(["fir", at, 8.0])
			wood[key] = list
	for key in wood:
		s.terrain._chunks[key] = wood[key]
	s.terrain._anchor = Vector2i(1 << 30, 0)
	s.terrain.refresh(s.commander.pos)
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	for k in 10:
		s.horde.spawn("barbarian_club", Vector2(-60 + k * 14, 240))
	var still := 0.0
	var reached := {}
	for f in 20 * 60:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		for i in s.horde.e_pos.size():
			if s.horde.e_want[i] == 1 and s.horde.e_fighting[i] == 0 and s.horde.e_pace[i] < Horde.STILL_PACE:
				still += 1.0 / 60.0
			if s.horde.e_pos[i].y < 60.0:
				reached[s.horde.e_id[i]] = true
	check(reached.size() >= 8, "they find the way round the wood to the legion (%d of 10)" % reached.size())
	check(still < 3.0, "and between them stand pressing into the trees for under three seconds (%.1f)" % still)


func _band_of_wood(s: Sim, top: float, rows: int) -> void:
	s.terrain.empty = false
	var wood := {}
	for cx in range(-8, 9):
		for cy in range(-8, 9):
			wood[Vector2i(cx, cy)] = []
	for row in rows:
		for col in 60:
			var at := Vector2(-650 + col * 22 + (11 if row % 2 == 1 else 0), top + row * 19)
			var key := Vector2i(floori(at.x / Terrain.CHUNK), floori(at.y / Terrain.CHUNK))
			var list: Array = wood.get(key, [])
			list.append(["fir", at, 8.0])
			wood[key] = list
	for key in wood:
		s.terrain._chunks[key] = wood[key]
	s.terrain._anchor = Vector2i(1 << 30, 0)
	s.terrain.refresh(s.commander.pos)


func test_barbarians_behind_a_wood_do_not_come_through_it(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1604)
	_band_of_wood(s, 290.0, 7)
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	for k in 6:
		s.horde.spawn("barbarian_club", Vector2(-60 + k * 24, 445))
	_step_dt(s, 8.0)
	var through := 0
	for p in s.horde.e_pos:
		if p.y < 280.0:
			through += 1
	check(through == 0, "and nobody comes out on the legion's side of it unseen (%d)" % through)


func test_a_barbarian_held_in_place_counts_as_still(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1602)
	s.b.detour = {"seconds": 0.6, "slide": 0.2, "stuck_after": 1e9, "stuck_slip": 0.0}
	s.terrain.empty = false
	var ring: Array = []
	for k in 10:
		ring.append(["rock", Vector2(300, 0) + Vector2.from_angle(k * TAU / 10.0) * 18.0, 9.0])
	s.terrain._chunks[Vector2i(1, 0)] = ring
	s.terrain._anchor = Vector2i(1 << 30, 0)
	s.terrain.refresh(s.commander.pos)
	s.commander.hp = 1e9
	s.horde.spawn("barbarian_club", Vector2(300, 0))
	s.horde.spawn("barbarian_club", Vector2(-300, 0))
	_step_dt(s, 1.0)
	check(s.horde.e_pace[1] > Horde.STILL_PACE, "a barbarian walking in the open counts as moving (%.0f)" % s.horde.e_pace[1])
	check(s.horde.e_want[0] == 1 and s.horde.e_pace[0] < Horde.STILL_PACE, "one boxed in by rocks counts as still and shows his stance (%.1f)" % s.horde.e_pace[0])


func test_a_ravine_end_is_solid_only_where_it_is_drawn(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1603)
	_gorge(s, -200, 160, 300, 20)
	check(s.terrain.ravine_edge(Vector2(176, 300)) < 0.0, "the narrowing crack past the last point is part of the drop")
	check(s.terrain.ravine_edge(Vector2(184, 306)) > 0.0, "but the ground beside its tip is open")
	check(s.terrain.over_ravine(Vector2(176, 300)), "and the horde's grid holds the crack as well")


func _overlapping_boss(s: Sim, i: int) -> int:
	var n := 0
	var reach: float = s.horde.k_radius[s.horde.e_kind[i]] + Sim.UNIT_RADIUS - 0.5
	for u in s.units_in_formation():
		if u.pos.distance_to(s.horde.e_pos[i]) < reach:
			n += 1
	return n


func test_a_boss_never_slips_through_trees(b: Dictionary) -> void:
	var made := _boss_sim(b, 1610, "war_band_leader", Vector2(300, 0))
	var s: Sim = made[0]
	var i: int = made[1]
	s.terrain.empty = false
	var ring: Array = []
	for k in 16:
		ring.append(["oak", Vector2(300, 0) + Vector2.from_angle(k * TAU / 16.0) * 30.0, 9.0])
	s.terrain._chunks[Vector2i(1, 0)] = ring
	s.terrain._anchor = Vector2i(1 << 30, 0)
	s.terrain.refresh(s.commander.pos)
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	var far := 0.0
	for f in 6 * 60:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		far = maxf(far, s.horde.e_pos[i].distance_to(Vector2(300, 0)))
	check(far < 20.0, "a boss boxed in by trees stays in the box instead of slipping out (%.0f px)" % far)


func test_the_legion_shoves_a_boss_it_marches_into(b: Dictionary) -> void:
	var made := _boss_sim(b, 1611, "berserker", Vector2(40, 0))
	var s: Sim = made[0]
	var i: int = made[1]
	for k in 20:
		Upgrades.apply(s, "legionary")
	s.legion.place_all(0.0)
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	s.horde.e_stun[i] = 1e9
	s.horde.e_hp[i] = 1e9
	_step_dt(s, 3.0, Vector2.RIGHT)
	check(s.horde.e_pos[i].x > 120.0, "marching into a boss pushes him ahead of the legion (%.0f)" % s.horde.e_pos[i].x)
	check(_overlapping_boss(s, i) == 0, "and no Roman stands inside him")


func test_the_legion_halts_at_a_boss_pinned_against_rocks(b: Dictionary) -> void:
	var made := _boss_sim(b, 1612, "berserker", Vector2(60, 0))
	var s: Sim = made[0]
	var i: int = made[1]
	s.terrain.empty = false
	var wall: Array = []
	for k in 13:
		wall.append(["rock", Vector2(110, -120 + k * 20), 10.0])
	s.terrain._chunks[Vector2i(0, 0)] = wall.filter(func(w: Array) -> bool: return w[1].y >= 0)
	s.terrain._chunks[Vector2i(0, -1)] = wall.filter(func(w: Array) -> bool: return w[1].y < 0)
	s.terrain._anchor = Vector2i(1 << 30, 0)
	s.terrain.refresh(s.commander.pos)
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	s.horde.e_stun[i] = 1e9
	s.horde.e_hp[i] = 1e9
	var r: float = s.horde.k_radius[s.horde.e_kind[i]]
	_step_dt(s, 4.0, Vector2.RIGHT)
	check(s.horde.e_pos[i].x <= 110.0 - 10.0 - r + 1.0, "the boss stops at the rocks (%.1f)" % s.horde.e_pos[i].x)
	check(_overlapping_boss(s, i) == 0, "and the legion stops against him instead of walking through him")
	check(s.commander.pos.x < s.horde.e_pos[i].x, "the commander stays on his side")


## A boss held by a long stun beside a gorge whose lip runs along y = 60, with a legion of twenty north of him facing south.
func _boss_at_gorge(b: Dictionary, seed_value: int, kind: String, at: Vector2, commander_at: Vector2) -> Array:
	var made := _boss_sim(b, seed_value, kind, at)
	var s: Sim = made[0]
	var i: int = made[1]
	_gorge(s, -600, 600, 100, 40)
	s.commander.pos = commander_at
	s.facing_angle = PI / 2.0
	for k in 12:
		s.add_soldier("legionary")
	s.legion.place_all(s.facing_angle)
	s.horde.e_stun[i] = 1e9
	s.horde.e_hp[i] = 1e9
	s.horde.e_max[i] = 1e9
	s._rebuild_grids()
	return [s, s.horde.e_id[i]]


func test_the_legion_shoves_a_boss_into_a_ravine(b: Dictionary) -> void:
	var r := float(content.enemies.berserker.radius)
	var made := _boss_at_gorge(b, 1630, "berserker", Vector2(0, 60 - r - 1.0), Vector2(0, -60))
	var s: Sim = made[0]
	var id: int = made[1]
	var kills := s.kills
	var rewards := s.horde.chests.size() + s.free_choices
	var fell := false
	for f in 4 * 60:
		s.update(1.0 / 60.0, Vector2.DOWN, false)
		for e in s.effects:
			fell = fell or (e.kind == "plunge" and e.type == "berserker")
		if s.horde.e_id.find(id) < 0:
			break
	check(s.horde.e_id.find(id) < 0, "the boss shoved over the lip falls into the gorge")
	check(s.kills - kills == 1, "and counts as a kill (%d)" % (s.kills - kills))
	check(fell, "and is seen to fall")
	check(s.horde.chests.size() + s.free_choices > rewards, "he leaves his chest")
	var dry := true
	for ch in s.horde.chests:
		dry = dry and s.terrain.ravine_edge(ch.pos) >= 0.0
	check(dry, "on the lip, where the legion can take it")


func test_the_chieftain_cannot_be_shoved_over_a_ravine(b: Dictionary) -> void:
	var s := _chief_sim(b, 1634)
	s.ravine_tip = false
	_gorge(s, -600, 600, 100, 40)
	s.commander.pos = Vector2(0, -70)
	s.facing_angle = PI / 2.0
	for k in 12:
		s.add_soldier("legionary")
	s.legion.place_all(s.facing_angle)
	var ci := s.horde.spawn_chieftain(Vector2(0, 60 - float(content.enemies.chieftain.radius) - 1.0))
	s.objectives.raise_fort(s)
	s.horde.e_stun[ci] = 1e9
	s.horde.e_hp[ci] = 1e9
	s.horde.e_max[ci] = 1e9
	var id: int = s.horde.e_id[ci]
	_step_dt(s, 4.0, Vector2.DOWN)
	var j := s.horde.e_id.find(id)
	check(not s.horde.chief_dead and j >= 0, "the chieftain marched into at a ravine's lip does not fall, since he is too easy a kill that way")
	check(j >= 0 and s.terrain.ravine_edge(s.horde.e_pos[j]) >= 0.0, "he stands his ground at the lip")


func test_a_boss_beside_a_ravine_is_not_shoved_in(b: Dictionary) -> void:
	var made := _boss_at_gorge(b, 1631, "berserker", Vector2(60, 25), Vector2(-60, 25))
	var s: Sim = made[0]
	var id: int = made[1]
	_step_dt(s, 1.5, Vector2.RIGHT)
	var i := s.horde.e_id.find(id)
	check(i >= 0, "a boss pushed along beside the lip stays alive")
	check(i >= 0 and s.terrain.ravine_edge(s.horde.e_pos[i]) >= 0.0, "and on firm ground")


func test_a_boss_on_a_bridge_is_not_shoved_through_it(b: Dictionary) -> void:
	var made := _boss_at_gorge(b, 1632, "berserker", Vector2(0, 30), Vector2(0, -40))
	var s: Sim = made[0]
	var id: int = made[1]
	s.timber = int(b.bridge.cost)
	check(s.build_bridge(), "a bridge is laid across the gorge")
	s.horde.e_pos[s.horde.e_id.find(id)] = Vector2(0, 100)
	_step_dt(s, 2.0, Vector2.DOWN)
	check(s.horde.e_id.find(id) >= 0, "a boss shoved along the deck does not fall through it")


func test_the_legion_shoves_barbarians_into_a_ravine(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1633)
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	for k in 12:
		s.add_soldier("legionary")
	_gorge(s, -600, 600, 100, 40)
	s.commander.pos = Vector2(0, -40)
	s.facing_angle = PI / 2.0
	s.legion.place_all(s.facing_angle)
	for k in 6:
		var i := s.horde.spawn("barbarian_club", Vector2(-50 + k * 20, 60 - 6 - 1))
		s.horde.e_hp[i] = 1e9
		s.horde.e_max[i] = 1e9
	var kills := s.kills
	_step_dt(s, 3.0, Vector2.DOWN)
	check(s.kills - kills >= 3, "barbarians the legion shoves over the lip fall in (%d of 6)" % (s.kills - kills))
	check(s.c_pos.is_empty(), "and drop nothing")


func test_the_war_priest_blinks_clear_of_the_legion(b: Dictionary) -> void:
	var made := _boss_sim(b, 1613, "war_priest", Vector2(10, 0))
	var s: Sim = made[0]
	var i: int = made[1]
	for k in 60:
		Upgrades.apply(s, "legionary")
	s.legion.place_all(0.0)
	s._rebuild_grids()
	made[2].blink_cd = 0.0
	s.horde._bosses(1.0 / 60.0, s)
	var r: float = s.horde.k_radius[s.horde.e_kind[i]]
	var clear := true
	for u in s.units_in_formation():
		clear = clear and u.pos.distance_to(s.horde.e_pos[i]) > r + Sim.UNIT_RADIUS + 10.0
	check(s.horde.e_pos[i] != Vector2(10, 0), "surrounded, he blinks")
	check(clear, "and comes out beyond the legion's ranks (%.0f px from the commander, reach %.0f)" % [s.horde.e_pos[i].distance_to(s.commander.pos), s.legion_reach])


func test_the_rescued_column_cart_fades_away(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 1620, "objectives_near": true})
	var col: Dictionary = {}
	for o in s.objectives.list:
		if o.kind == "column":
			col = o
	if col.is_empty():
		check(false, "the run has a stranded column")
		return
	check(s.objectives.cart_alpha(col, s.time) == 1.0, "the column's cart stands while the column waits")
	s.commander.pos = col.pos
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(col.done, "reaching the column rescues it")
	check(s.objectives.cart_alpha(col, s.time + 0.5) < 1.0, "then its cart fades")
	check(s.objectives.cart_alpha(col, s.time + 5.0) == 0.0, "and is gone a few seconds later")


func test_a_supply_cart_fades_before_it_goes(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1621, Content.with_all_art())
	s.horde.spawn_cart()
	var cart: Dictionary = s.horde.carts[0]
	check(s.horde.cart_alpha(cart) == 1.0, "a new cart is drawn whole")
	cart.t = float(b.cart.life) - 0.5
	check(s.horde.cart_alpha(cart) < 1.0 and s.horde.cart_alpha(cart) > 0.0, "it fades near the end of its time")
	s.commander.pos = Vector2(5000, 0)
	_step_dt(s, 1.0)
	check(s.horde.carts.is_empty(), "and is gone when its time is up")


func test_supply_carts_stand_where_the_legion_can_reach_them(b: Dictionary) -> void:
	var bad := 0
	for province in ["germania", "gaul"]:
		for seed_value in [1, 2, 3, 4]:
			var s := Sim.new(b, Content.with_all_art(), {"seed": seed_value, "province": province})
			for at in [Vector2.ZERO, Vector2(600, 400), Vector2(-900, 700), Vector2(1200, -1000)]:
				s.commander.pos = at
				s.terrain.refresh(at)
				s.terrain.update_flow(at)
				for k in 30:
					s.horde.carts.clear()
					s.horde.spawn_cart()
					var p: Vector2 = s.horde.carts[0].pos
					if not s.terrain.is_open(p) or s.terrain.ravine_edge(p) < float(b.cart.radius):
						bad += 1
	check(bad == 0, "every supply cart stands on open ground, clear of woods and gorges (%d do not)" % bad)


func test_a_pack_of_beasts_bites_quietly_and_rarely(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1630, Content.with_all_art())
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	for k in 12:
		s.horde.spawn("boar" if k % 2 == 0 else "wolf", Vector2.from_angle(k * TAU / 12.0) * 120.0)
	var heard := {}
	for f in 10 * 60:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		for e in s.events:
			heard[e.kind] = int(heard.get(e.kind, 0)) + 1
		s.events.clear()
	check(not heard.has("charge") and not heard.has("roar"), "boars and wolves never roar or bellow a charge (%s)" % heard)
	check(int(heard.get("bite", 0)) >= 1 and int(heard.get("bite", 0)) <= 10 / float(b.bite_every) + 1, "they bite now and then, no more than once every %.1f s (%d)" % [float(b.bite_every), int(heard.get("bite", 0))])
	check(int(heard.get("hurt", 0)) <= 10 / float(b.hurt_every) + 1, "and the commander's hurt cry does not loop while they gnaw at him (%d)" % int(heard.get("hurt", 0)))
	check(b.audio.kinds.has("bite") and int(b.audio.kinds.bite.max) == 1 and float(b.audio.kinds.bite.db) <= -12.0, "the bite is a quiet sound, one at a time")


func _qm_sim(b: Dictionary, id: String, rank: int, seed_value := 1640) -> Sim:
	var s := Sim.new(b, Content.with_all_art(), {"seed": seed_value, "profile_bonuses": {id: rank} if rank > 0 else {}})
	s.terrain.clear()
	return s


func _qm_step(id: String) -> float:
	return float(content.quartermaster[id].per_rank)


func test_the_fort_has_room_for_a_legion_grown_by_the_barracks(b: Dictionary) -> void:
	var top := int(content.quartermaster.recruit_cap.ranks)
	var s := _qm_sim(b, "recruit_cap", top)
	s.objectives.list.clear()
	s.objectives.raise_fort(s)
	var block: Vector2 = Legion.block_size(s.legion.cap, b.legion)
	var room := float(s.objectives.fort.half) - float(b.fort.stake_radius) - Sim.UNIT_RADIUS - maxf(block.x, block.y) / 2.0
	check(s.legion.cap > int(b.legion_cap) and room >= float(b.fort.room_margin) - 0.01, "the yard keeps its margin for %d men (%.1f px)" % [s.legion.cap, room])


func test_the_fort_walls_run_straight_from_tower_to_gate(b: Dictionary) -> void:
	var s := _qm_sim(b, "recruit_cap", 0)
	var half := 200.0
	var w := float(b.fort.wall_step)
	var gate_picture_half := 48.0
	var back := {}
	var front := {}
	var left := -INF
	var right := INF
	var reach := Vector2(INF, -INF)
	var sides: Array = []
	for p in s.objectives._fort_pictures(Vector2.ZERO, half, b.fort):
		if p[0] == "fort_wall":
			if p[1].y < 0.0:
				back[p[1].y] = true
				reach = Vector2(minf(reach.x, p[1].x - w / 2.0), maxf(reach.y, p[1].x + w / 2.0))
			else:
				front[p[1].y] = true
				if p[1].x < 0.0:
					left = maxf(left, p[1].x + w / 2.0)
				else:
					right = minf(right, p[1].x - w / 2.0)
		elif p[0] == "fort_side" and p[1].x < 0.0:
			sides.append(p[1].y)
	check(back.size() == 1 and front.size() == 1, "the back wall and the front walls each stand on one line")
	check(reach.x <= -half and reach.y >= half, "the back wall runs from corner to corner")
	check(left >= -gate_picture_half and left < -float(b.fort.tower_x) + float(b.fort.tower_radius) and right <= gate_picture_half and right > float(b.fort.tower_x) - float(b.fort.tower_radius), "the front walls reach in behind the gate on both sides, short of its opening (%.0f, %.0f)" % [left, right])
	sides.sort()
	check(not sides.is_empty() and sides[0] <= -half and sides[-1] >= half - float(b.fort.side_step), "the side walls run from the back towers to the front towers")


func test_each_province_fort_stands_on_its_own_ground(b: Dictionary) -> void:
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/atlas.json"))
	var pieces := ["fort_wall", "fort_side", "fort_gate", "watchtower", "tent", "command_tent"]
	for id in content.provinces:
		var ground: String = content.provinces[id].get("fort_ground", "")
		check(ground != "", "%s names its fort's ground" % id)
		for name in pieces:
			check(meta.props.has(Objectives.fort_piece(name, ground)), "the atlas has %s for %s" % [Objectives.fort_piece(name, ground), id])
		var s := _mode_sim(b, {"seed": 400, "province": id})
		s.objectives.list.clear()
		s.terrain.clear()
		s.objectives.raise_fort(s)
		var drawn := {}
		var wrong := []
		for pr in s.terrain.extras:
			for name in pieces:
				if pr[0] == name or pr[0].begins_with(name + "_"):
					drawn[name] = true
					if pr[0] != Objectives.fort_piece(name, ground):
						wrong.append(pr[0])
		check(drawn.size() == pieces.size() and wrong.is_empty(), "%s's fort is drawn in its %s pieces (%s)" % [id, ground, wrong])
	check(Objectives.fort_piece("fort_gate", "grass") == "fort_gate" and Objectives.fort_piece("fort_gate", "sand") == "fort_gate_sand", "grass keeps the pieces as drawn")


func test_quartermaster_attack_speed_quickens_every_blow(b: Dictionary) -> void:
	var plain := _qm_sim(b, "attack_speed", 0).attack_rate()
	var drilled := _qm_sim(b, "attack_speed", 2).attack_rate()
	check(is_equal_approx(drilled, plain * (1.0 + 2.0 * _qm_step("attack_speed"))), "two ranks of attack speed make every soldier strike %.0f%% faster" % (200.0 * _qm_step("attack_speed")))


func test_quartermaster_soldier_health_raises_every_soldier(b: Dictionary) -> void:
	var plain := _qm_sim(b, "soldier_health", 0)
	var drilled := _qm_sim(b, "soldier_health", 2)
	check(is_equal_approx(drilled.soldiers[0].max_hp, plain.soldiers[0].max_hp * (1.0 + 2.0 * _qm_step("soldier_health"))), "two ranks give every soldier more health (%.0f vs %.0f)" % [drilled.soldiers[0].max_hp, plain.soldiers[0].max_hp])
	Upgrades.apply(drilled, "archer")
	check(drilled.soldiers[-1].max_hp > float(content.recruits.archer.hp), "and recruits joining later have it too")


func test_quartermaster_regeneration_heals_soldiers(b: Dictionary) -> void:
	var healed := {}
	for rank in [0, 1]:
		var s := _qm_sim(b, "regeneration", rank)
		s.soldiers[0].hp = 1.0
		s._regen(10.0)
		healed[rank] = s.soldiers[0].hp - 1.0
	check(healed[0] == 0.0, "without it a soldier does not heal on his own")
	check(is_equal_approx(healed[1], 10.0 * _qm_step("regeneration")), "one rank heals every soldier %.1f a second" % _qm_step("regeneration"))


func test_quartermaster_missile_range_reaches_further(b: Dictionary) -> void:
	var plain := _qm_sim(b, "missile_range", 0).range_mult()
	var drilled := _qm_sim(b, "missile_range", 3).range_mult()
	check(is_equal_approx(drilled, plain * (1.0 + 3.0 * _qm_step("missile_range"))), "three ranks make missiles reach %.0f%% further" % (300.0 * _qm_step("missile_range")))


func test_quartermaster_testudo_hold_holds_longer(b: Dictionary) -> void:
	var held := {}
	for rank in [0, 2]:
		var s := _qm_sim(b, "testudo_hold", rank)
		s.update(1.0 / 60.0, Vector2.ZERO, true)
		held[rank] = s.testudo_left
	check(is_equal_approx(held[2] - held[0], 2.0 * _qm_step("testudo_hold")), "two ranks hold the testudo %.1f s longer" % (2.0 * _qm_step("testudo_hold")))


func test_quartermaster_armour_cuts_the_harm_taken(b: Dictionary) -> void:
	var lost := {}
	for rank in [0, 4]:
		var s := _quiet_sim(b, 1641)
		s.bonuses = {"armour": rank}
		s.commander.hp = 1e9
		s.commander.max_hp = 1e9
		var so: Dictionary = s.soldiers[0]
		so.hp = 1e6
		so.max_hp = 1e6
		s.horde.spawn("barbarian_club", so.pos + Vector2(8, 0))
		_step_dt(s, 1.0)
		lost[rank] = 1e6 - so.hp
	check(lost[0] > 0.0 and is_equal_approx(lost[4], lost[0] * (1.0 - 4.0 * _qm_step("armour"))), "four ranks of armour cut the harm a soldier takes by %.0f%% (%.2f vs %.2f)" % [400.0 * _qm_step("armour"), lost[4], lost[0]])


func test_quartermaster_cart_rewards_give_more(b: Dictionary) -> void:
	var extra := {}
	for rank in [0, 3]:
		var s := _qm_sim(b, "cart_rewards", rank)
		var picks := 0
		for k in 400:
			s.horde.open_cart(s)
			picks += int(s.supplies[-1].picks)
		extra[rank] = picks - 400
	check(extra[0] == 0, "without it a cart gives its one reward")
	var want := 400.0 * 3.0 * _qm_step("cart_rewards")
	check(extra[3] > want * 0.6 and extra[3] < want * 1.4, "three ranks give a second reward from about %d%% of carts (%d of 400)" % [int(300.0 * _qm_step("cart_rewards")), extra[3]])


func test_quartermaster_recruit_cap_holds_more_soldiers(b: Dictionary) -> void:
	var s := _qm_sim(b, "recruit_cap", 2)
	var cap := int(b.legion_cap) + int(2.0 * _qm_step("recruit_cap"))
	while s.soldiers.size() < cap + 5:
		if not s.legion.add("legionary"):
			break
	check(s.soldiers.size() == cap, "two ranks let the legion hold %d soldiers (%d)" % [cap, s.soldiers.size()])
	check(not Upgrades.available(s).has("legionary"), "and recruits stop being offered once it is full")


func test_quartermaster_level_ease_needs_fewer_coins(b: Dictionary) -> void:
	var plain := _qm_sim(b, "level_ease", 0)
	var eased := _qm_sim(b, "level_ease", 3)
	for s in [plain, eased]:
		s.gain(400)
	check(eased.level > plain.level, "with three ranks the same coins reach a higher level (%d vs %d)" % [eased.level, plain.level])
	check(eased.xp_next < plain.xp_next, "since each level needs fewer coins")


func test_quartermaster_choice_luck_brings_more_arms_and_recruits(b: Dictionary) -> void:
	var share := {}
	for rank in [0, 3]:
		var s := _qm_sim(b, "choice_luck", rank)
		var hits := 0
		var total := 0
		for k in 600:
			for id in Upgrades.offers(s):
				total += 1
				var g := s.content.group_of(id)
				if g == "Arms" or g == "Recruit":
					hits += 1
		share[rank] = float(hits) / total
	check(share[3] > share[0], "three ranks bring arms and recruits up more often (%.2f vs %.2f)" % [share[3], share[0]])


func _won_sim(b: Dictionary, seed_value: int, options := {}) -> Sim:
	var opts := {"seed": seed_value}
	opts.merge(options)
	var s := Sim.new(b, content, opts)
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	for k in 40:
		s.horde.spawn("barbarian_club", s.commander.pos + Vector2.from_angle(k * 0.7) * (60.0 + k * 9.0))
	for k in 30:
		s.drop_coin(s.commander.pos + Vector2.from_angle(k * 1.3) * (80.0 + k * 10.0), 2)
	return s


func test_a_win_ends_in_a_triumph(b: Dictionary) -> void:
	var cfg: Dictionary = b.triumph
	var s := _won_sim(b, 1650)
	var t0 := s.time
	var money := s.denarii
	s.win(s.commander.pos)
	check(not s.over and s.triumph_left > 0.0, "a win first holds a triumph before the run ends")
	check(s.events.any(func(e: Dictionary) -> bool: return e.kind == "victory"), "with the victory sound")
	var near_gone_at := -1.0
	var far_gone_at := -1.0
	var near_id := -1
	var far_id := -1
	var best := INF
	var worst := 0.0
	for i in s.horde.e_pos.size():
		var d: float = s.horde.e_pos[i].distance_to(s.commander.pos)
		if d < best:
			best = d
			near_id = s.horde.e_id[i]
		if d > worst:
			worst = d
			far_id = s.horde.e_id[i]
	var start: Vector2 = s.commander.pos
	var steps := 0
	var clear_at := -1
	while not s.over and steps < 600:
		s.update(1.0 / 60.0, Vector2.RIGHT, false)
		steps += 1
		if near_gone_at < 0.0 and not s.horde.e_id.has(near_id):
			near_gone_at = steps
		if far_gone_at < 0.0 and not s.horde.e_id.has(far_id):
			far_gone_at = steps
		if clear_at < 0 and s.horde.e_pos.is_empty() and s.c_pos.is_empty():
			clear_at = steps
	check(s.over and s.victory, "then the run ends in victory")
	var ends_by := maxf(float(cfg.seconds), clear_at / 60.0 + float(cfg.linger))
	check(steps / 60.0 >= float(cfg.seconds) - 0.02 and steps / 60.0 <= ends_by + 0.1, "no sooner than %.1f s and no later than %.1f s after the field is clear (%.2f)" % [float(cfg.seconds), float(cfg.linger), steps / 60.0])
	check(s.horde.e_pos.is_empty(), "every barbarian on the field dies")
	check(near_gone_at > 0.0 and far_gone_at > near_gone_at, "in a wave from the commander outwards (%d then %d)" % [near_gone_at, far_gone_at])
	check(s.c_pos.is_empty() and s.denarii >= money + 60, "every coin flies to the commander and is counted (%d)" % (s.denarii - money))
	check(s.time == t0 and s.commander.pos == start, "the clock and the commander stand still while it plays")


func test_an_endless_win_triumphs_and_goes_on(b: Dictionary) -> void:
	var s := _won_sim(b, 1651, {"endless": true})
	s.win(s.commander.pos)
	_step_dt(s, float(b.triumph.most_seconds) + 0.5)
	check(not s.over and s.victory and s.triumph_left <= 0.0, "an endless run holds its triumph and then marches on")
	check(s.endless_since >= 0.0, "counting the endless time from the win")


func test_the_summary_lists_what_a_win_unlocked(b: Dictionary) -> void:
	var before := Profile.merge_saved({"unlocked": {"commanders": ["tribune"], "provinces": ["germania"]}, "achievements": []})
	var after := Profile.merge_saved({"unlocked": {"commanders": ["tribune", "archer_captain"], "provinces": ["germania", "gaul"]},
		"records": {"germania": {"won": true, "best_time": 700.0}}, "achievements": ["win_germania"]})
	var got := SummaryScreen.unlocks(before, after, content, "germania")
	var kinds: Array = got.map(func(u: Dictionary) -> String: return u.kind)
	check(kinds == ["province", "modes", "commander", "achievement"], "a first win lists the new province, the modes, the commander and the achievement in that order (%s)" % [kinds])
	if got.size() == 4:
		check(str(content.provinces.gaul.name) in got[0].text, "the province line names it (%s)" % got[0].text)
		check(str(content.commanders.archer_captain.name) in got[2].text, "the commander line names him (%s)" % got[2].text)
		check(got[1].text == "Endless and Decimatio in %s" % str(content.provinces.germania.name), "the modes line names the province (%s)" % got[1].text)
		check(got[3].text == str(content.achievements.win_germania.name), "the achievement line names it")
	check(SummaryScreen.unlocks(after, after, content, "germania").is_empty(), "a run that unlocks nothing lists nothing")


func test_a_war_band_runs_down_a_marching_legion(b: Dictionary) -> void:
	var cfg: Dictionary = b.war_band
	var s := _quiet_sim(b, 1660)
	s.commander.hp = 1e9
	s.time = float(cfg.rush_from)
	s.horde.time = s.time
	s.horde.next_band = s.time
	s.horde.next_surge = 1e9
	s.horde.next_boss = 1e9
	s.horde._spawn(1.0 / 60.0, s)
	var n := s.horde.e_pos.size()
	check(n > 0, "the band comes")
	var before: Array = []
	for i in n:
		before.append(s.horde.e_pos[i].distance_to(s.commander.pos))
	s.horde.spawn("barbarian_club", s.commander.pos + Vector2(0, 300))
	var plain_from: float = s.horde.e_pos[n].distance_to(s.commander.pos)
	_step_dt(s, 1.0)
	var band_ran: float = before[0] - s.horde.e_pos[0].distance_to(s.commander.pos)
	var plain_ran: float = plain_from - s.horde.e_pos[n].distance_to(s.commander.pos)
	# A warrior on foot rushes only up to the cap on his pace.
	var rush := minf(float(cfg.rush), float(b.foot_pace) * float(content.base_commander.speed) / float(content.enemies.barbarian_club.speed))
	check(band_ran > plain_ran * (rush - 0.15), "a war band rushes in about %.1f times as fast as the stream (%.0f vs %.0f px)" % [rush, band_ran, plain_ran])
	_step_dt(s, float(cfg.rush_seconds))
	check(s.horde.e_slow[0] == 1.0, "and slows to a walk after %.0f s" % float(cfg.rush_seconds))
	var camp := _quiet_sim(b, 1661)
	camp.horde.war_band_at(camp, Vector2(300, 0))
	check(camp.horde.e_slow[0] == 1.0, "an objective's defenders do not rush")


func test_wheat_fields_stand_away_from_the_start_with_lanes_between(b: Dictionary) -> void:
	var lane := float(b.fields.gaul.field_lane)
	var inset := float(b.fields.gaul.field_inset)
	for seed_value in [1, 2, 3]:
		var s := Sim.new(b, content, {"seed": seed_value, "province": "gaul"})
		var area := Rect2(-2500, -2500, 5000, 5000)
		var fields := s.terrain.fields_in(area)
		check(fields.size() >= 4, "seed %d has wheat fields (%d)" % [seed_value, fields.size()])
		var clear := true
		var away := true
		for f in fields:
			away = away and not f.grow(-1.0).has_point(Vector2.ZERO)
			for c in s.terrain.clearings:
				var near := Vector2(clampf(c[0].x, f.position.x, f.end.x), clampf(c[0].y, f.position.y, f.end.y))
				clear = clear and near.distance_to(c[0]) >= c[1]
		check(away and clear, "no field covers the start or an objective's clearing (seed %d)" % seed_value)
		# Parts of one field touch; two separate fields, and a field and a hedge or house, keep a lane the legion can march down.
		var narrowest := INF
		for f in fields:
			var body: Rect2 = f.grow(-inset)
			for g in fields:
				if g != f and Terrain._rect_gap(f, g) > 0.5:
					narrowest = minf(narrowest, Terrain._rect_gap(body, g.grow(-inset)))
			for pr in s.terrain.props_in(f.grow(lane + 60.0)):
				if pr[0] == "" and pr[2] > 0.0:
					narrowest = minf(narrowest, Terrain._rect_gap(body, Rect2(pr[1], Vector2.ZERO)) - pr[2])
		check(narrowest >= lane - 0.5, "every field keeps a lane of %.0f px from the next field, hedge or house (narrowest %.0f, seed %d)" % [lane, narrowest, seed_value])


## A quiet Gaulish run on its own farmland, and the wheat field nearest the start that has no strip off its corner.
func _wheat_sim(b: Dictionary, seed_value: int) -> Array:
	var s := Sim.new(b, Content.with_all_art(), {"seed": seed_value, "province": "gaul"})
	s.b = b.duplicate()
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	s.horde.next_surge = 1e9
	s.horde.next_band = 1e9
	s.horde.next_cart = 1e9
	s.horde.next_boss = 1e9
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	var fields := s.terrain.fields_in(Rect2(-2500, -2500, 5000, 5000))
	var best := Rect2()
	for f in fields:
		var lone := fields.all(func(g: Rect2) -> bool: return g == f or Terrain._rect_gap(f, g) > 0.5)
		if lone and (best.size == Vector2.ZERO or f.get_center().length() < best.get_center().length()):
			best = f
	return [s, best]


## Stands the commander at p facing east, with his legion round him.
func _stand_at(s: Sim, p: Vector2) -> void:
	s.commander.pos = p
	s.facing_angle = 0.0
	s.legion.place_all(0.0)
	s.terrain.refresh(p)
	s.terrain.update_flow(p)


func test_the_legion_marches_through_a_wheat_field(b: Dictionary) -> void:
	var got := _wheat_sim(b, 1801)
	var s: Sim = got[0]
	var f: Rect2 = got[1]
	check(f.size != Vector2.ZERO, "a wheat field lies near the start")
	var body := f.grow(-float(b.fields.gaul.field_inset))
	for k in 8:
		s.add_soldier("legionary")
	_stand_at(s, Vector2(f.position.x - 90.0, f.get_center().y))
	var commander_in := false
	var soldiers_in := false
	var y0: float = s.commander.pos.y
	while s.commander.pos.x < f.end.x + 60.0 and s.time < 30.0:
		s.update(1.0 / 60.0, Vector2.RIGHT, false)
		commander_in = commander_in or body.has_point(s.commander.pos)
		for so in s.soldiers:
			soldiers_in = soldiers_in or body.has_point(so.pos)
	check(commander_in and soldiers_in, "the commander and his soldiers march into the wheat")
	check(s.commander.pos.x >= f.end.x + 60.0 and absf(s.commander.pos.y - y0) < 4.0, "and straight out the far side (%.0f, %.0f)" % [s.commander.pos.x - f.end.x, s.commander.pos.y - y0])


func test_a_barbarian_walks_through_a_wheat_field(b: Dictionary) -> void:
	var got := _wheat_sim(b, 1802)
	var s: Sim = got[0]
	var f: Rect2 = got[1]
	var body := f.grow(-float(b.fields.gaul.field_inset))
	_stand_at(s, Vector2(f.get_center().x, f.end.y + 80.0))
	check(s.terrain.is_open(f.get_center()), "the route map leaves the wheat open")
	var i := s.horde.spawn(s.horde.ordinary[0], Vector2(f.get_center().x, f.position.y - 50.0))
	var entered := false
	var reached := false
	for k in 30 * 60:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		if i >= s.horde.e_pos.size():
			break
		entered = entered or body.has_point(s.horde.e_pos[i])
		reached = reached or s.horde.e_pos[i].distance_to(s.commander.pos) < s.legion_reach + 30.0
		if reached:
			break
	check(entered and reached, "a barbarian across a field comes straight through the wheat to the legion")

func test_nothing_comes_onto_the_field_inside_the_wheat(b: Dictionary) -> void:
	var got := _wheat_sim(b, 1803)
	var s: Sim = got[0]
	var f: Rect2 = got[1]
	var body := f.grow(-float(b.fields.gaul.field_inset))
	var mid := f.get_center()
	_stand_at(s, mid + Vector2(0.0, float(b.spawn_radius) * 0.75))
	var h := s.horde
	var i := h.spawn(h.ordinary[0], mid)
	check(not body.has_point(h.e_pos[i]), "a barbarian sent to the middle of a field arrives at its edge")



func test_a_legion_marching_in_a_loop_meets_a_band_across_it(b: Dictionary) -> void:
	var s := _quiet_sim(b, 1670)
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	s.soldiers.clear()
	for f in 20 * 30:
		s.update(1.0 / 30.0, Vector2(cos(s.time * 0.4), sin(s.time * 0.4)), false)
	var mid := s.horde.loop_centre()
	check(mid != Vector2.INF, "marching round in circles is seen as a loop")
	var before := s.horde.e_id.size()
	s.horde.time = float(b.war_band.loop_from)
	s.horde._war_band(s)
	var side := 0
	for i in range(before, s.horde.e_id.size()):
		if (s.horde.e_pos[i] - s.commander.pos).dot(mid - s.commander.pos) > 0.0:
			side += 1
	check(s.horde.e_id.size() > before and side == s.horde.e_id.size() - before, "and the next war band comes in from across the middle of the loop")
	var still := _quiet_sim(b, 1671)
	_step_dt(still, 20.0)
	check(still.horde.loop_centre() == Vector2.INF, "a legion standing still is not looping")
	var march := _quiet_sim(b, 1672)
	_step_dt(march, 20.0, Vector2.RIGHT)
	check(march.horde.loop_centre() == Vector2.INF, "nor is one marching straight on")


func test_a_roundhouse_towers_over_a_soldier_and_stands_in_a_cluster(b: Dictionary) -> void:
	var atlas := Atlas.new()
	var house: float = atlas.prop_frame("roundhouse")[0].size.y
	var man: float = atlas.unit_frame("legionary", "idle", "south", 0.0)[0].size.y
	check(house >= man * 2.0, "a roundhouse is at least twice a soldier's height (%.0f vs %.0f px)" % [house, man])
	var t := Terrain.new(905, b.forest, {})
	t.field = b.fields.gaul
	var houses: Array = t.props_in(Rect2(-3000, -3000, 6000, 6000)).filter(func(pr: Array) -> bool: return pr[0] == "roundhouse")
	var clustered := 0
	for h in houses:
		var near := 0
		for o in houses:
			if o != h and o[1].distance_to(h[1]) < 160.0:
				near += 1
		if near >= 2:
			clustered += 1
	check(houses.size() >= 6 and clustered >= houses.size() * 0.8, "houses stand in clusters of three or more (%d of %d)" % [clustered, houses.size()])
	var gap := float(b.fields.gaul.house_spacing)
	var stacked := 0
	for i in houses.size():
		for j in range(i + 1, houses.size()):
			if houses[i][1].distance_to(houses[j][1]) < gap:
				stacked += 1
	check(stacked == 0, "no roundhouse is drawn into another (%d pairs)" % stacked)


func _hispania_sim(b: Dictionary, seed_value: int) -> Sim:
	var s := _gaul_sim(b, seed_value, "hispania")
	for t in ["ambush_cd", "feint_cd", "javelins_cd"]:
		s.horde.set(t, 1e9)
	s.commander.pos = Vector2.ZERO
	s.legion.place_all(s.facing_angle)
	s._rebuild_grids()
	return s


func test_winning_britannia_opens_hispania(b: Dictionary) -> void:
	check(content.ready("provinces", "hispania"), "Hispania is drawn")
	check(content.provinces.keys().find("hispania") == content.provinces.keys().find("britannia") + 1, "Hispania comes after Britannia on the road")
	check(content.province_before("hispania") == "britannia", "it follows Britannia")
	var p := _fresh_profile()
	var before: Dictionary = p.data.duplicate(true)
	var s := Sim.new(b, content, {"seed": 1980, "province": "britannia"})
	s.time = 900.0
	s.over = true
	s.victory = true
	p.record_run(s)
	check(p.province_unlocked("hispania"), "winning in Britannia opens Hispania")
	var said := false
	for u in SummaryScreen.unlocks(before, p.data, content, "britannia"):
		said = said or (u.kind == "province" and u.id == "hispania" and str(u.text) == "Hispania is open")
	check(said, "and the summary says Hispania is open")
	check(content.achievements.has("win_hispania") and content.achievements.win_hispania.target == "hispania", "a win in Hispania has its own achievement")
	_cleanup_profile_files()
	p.free()


func test_hispania_is_hill_country_with_olive_groves_walls_and_dry_grass(b: Dictionary) -> void:
	var area := Rect2(-4000, -4000, 8000, 8000)
	var t := Terrain.new(1981, b.forest, b.ravines)
	t.hills = b.hills.hispania
	var g := Terrain.new(1981, b.forest, b.ravines)
	var kinds := {}
	var trees := 0
	var forest_trees := 0
	for pr in t.props_in(area):
		kinds[pr[0]] = kinds.get(pr[0], 0) + 1
		trees += 1 if Terrain.TREES.has(pr[0]) else 0
	for pr in g.props_in(area):
		forest_trees += 1 if Terrain.TREES.has(pr[0]) else 0
	check(kinds.has("olive") and kinds.has("stone_wall") and kinds.has("dry_grass") and kinds.has("rock"), "the hills hold olives, dry-stone walls, dry grass and rocks (%s)" % str(kinds.keys()))
	check(not kinds.has("oak") and not kinds.has("fir"), "every tree is an olive")
	check(trees > 0 and trees * 2 < forest_trees, "with far fewer trees than Germania (%d against %d)" % [trees, forest_trees])
	check(Terrain.TREES.has("olive") and Terrain.SOLID.has("olive") and Terrain.SOLID.has("stone_wall"), "olives and walls are solid, and olives can be felled")
	check(not Terrain.SOLID.has("dry_grass"), "dry grass blocks nothing")


func test_every_terrace_wall_has_a_gap_the_legion_can_pass(b: Dictionary) -> void:
	var cfg: Dictionary = b.hills.hispania.duplicate()
	cfg.walls = [1, 1]
	var t := Terrain.new(1982, b.forest, b.ravines)
	t.hills = cfg
	var widest := INF
	var tilt := 0.0
	var walls := true
	for k in 40:
		var r := RandomNumberGenerator.new()
		r.seed = 500 + k
		var wall: Array = t._hill_feature(r, float(cfg.grove_chance) + 0.01, Vector2.ZERO)
		walls = walls and wall.size() > 3 and wall.all(func(pr: Array) -> bool: return pr[0] == "stone_wall")
		var a: Vector2 = wall[0][1]
		var z: Vector2 = wall[wall.size() - 1][1]
		var dir: Vector2 = (z - a).normalized()
		tilt = maxf(tilt, absf(dir.angle()))
		var biggest := 0.0
		for n in range(1, wall.size()):
			biggest = maxf(biggest, (wall[n][1] - wall[n - 1][1]).dot(dir))
		widest = minf(widest, biggest - 2.0 * float(Terrain.SOLID.stone_wall))
	check(walls, "a wall region holds a dry-stone wall")
	check(widest > 4.0 * Sim.UNIT_RADIUS, "every wall has a gap several men wide (narrowest %.0f px)" % widest)
	check(tilt <= float(cfg.wall_tilt) + 0.15, "and the walls run along the hillside, roughly east and west")


func test_a_terrace_wall_holds_men_back_but_dry_grass_does_not(b: Dictionary) -> void:
	var s := _hispania_sim(b, 1983)
	s.terrain.add_clearing(Vector2(0, 300), 1.0, [["stone_wall", Vector2(0, 300), Terrain.SOLID.stone_wall], ["dry_grass", Vector2(200, 300), 0.0]])
	s.terrain.refresh(s.commander.pos)
	check(s.terrain.push_out(Vector2(0, 302), Sim.UNIT_RADIUS).distance_to(Vector2(0, 300)) >= Terrain.SOLID.stone_wall, "a man is pushed out of the wall")
	check(s.terrain.push_out(Vector2(200, 302), Sim.UNIT_RADIUS) == Vector2(200, 302), "but walks through dry grass")


func test_hispanias_warriors_slash_sling_throw_and_hunt(b: Dictionary) -> void:
	var e: Dictionary = content.enemies
	check(e.celtiberian_warrior.behaviour == "melee" and e.celtiberian_warrior.slash.damage_mult > e.gaul_swordsman.slash.damage_mult, "the falcata's slash hits harder than a Gaulish sword")
	check(e.balearic_slinger.has("sling") and e.balearic_slinger.sling.stun > 0.0, "the Balearic slinger's stones daze")
	check(e.war_hound.behaviour == "beast" and is_equal_approx(float(e.war_hound.share), 0.5) and float(e.war_hound.arrives) >= 90.0, "the war hound is a beast that comes later and only half as often")
	var s := _hispania_sim(b, 1984)
	var h := s.horde
	var cfg: Dictionary = e.caetratus
	var c := h.spawn("caetratus", Vector2(s.legion_reach + float(cfg.kite.near) * 0.5, 0))
	h.e_cd[c] = 0.0
	var gap0 := h.e_pos[c].length()
	h._move(1.0 / 60.0, s)
	check(h.e_pos[c].length() > gap0, "the caetratus backs away from soldiers who close in")
	check(h.sp_pos.size() >= 1 and h.sp_kind[0] == 0, "throwing a javelin, not an arrow")


func test_the_celtiberian_chief_rouses_the_warriors_round_him(b: Dictionary) -> void:
	var s := _hispania_sim(b, 1985)
	var h := s.horde
	var info: Dictionary = content.enemies.celtiberian_chief
	var i := h.spawn("celtiberian_chief", Vector2(200, 0), true)
	var st: Dictionary = h.boss_state(i)
	var w := h.spawn("celtiberian_warrior", h.e_pos[i] + Vector2(40, 0))
	h.e_hp[w] = h.e_max[w] * 0.4
	h.rebuild_grid()
	st.rouse_cd = 0.0
	h._bosses(1.0 / 60.0, s)
	check(h.e_hp[w] > h.e_max[w] * 0.4 and h.e_slow[w] > 1.0, "his shout gives the warriors round him their second wind and sends them running in")
	check(info.keys().filter(func(k: String) -> bool: return h.ABILITY_TIMERS.has(k)).size() == 1, "it is his one ability")


func test_the_shepherd_general_springs_an_ambush_on_both_flanks(b: Dictionary) -> void:
	var s := _hispania_sim(b, 1986)
	var h := s.horde
	var cfg: Dictionary = content.enemies.viriathus.attacks.ambush
	h.spawn_chieftain(Vector2(300, 0))
	var n0 := h.e_pos.size()
	h.ambush_cd = 0.0
	h._chieftain(1.0 / 60.0, s)
	check(s.objectives.notice.get("kind", "") == "ambush", "a notice warns of the ambush")
	check(h.e_pos.size() == n0, "and nobody comes yet")
	var t := 0.0
	while t < float(cfg.warn) - 0.1:
		h._chieftain(1.0 / 60.0, s)
		t += 1.0 / 60.0
	check(h.e_pos.size() == n0, "nobody comes while the warning lasts")
	for k in 12:
		h._chieftain(1.0 / 60.0, s)
	var side := Vector2.from_angle(s.facing_angle).orthogonal()
	var left := 0
	var right := 0
	var rushing := true
	for j in range(n0, h.e_pos.size()):
		var across: float = (h.e_pos[j] - s.commander.pos).dot(side)
		left += 1 if across < -100.0 else 0
		right += 1 if across > 100.0 else 0
		rushing = rushing and h.e_slow[j] > 1.0
	check(left > 0 and right > 0, "then war bands burst out on both flanks of the legion at once (%d and %d)" % [left, right])
	check(rushing, "running at it")


func test_the_shepherd_general_feigns_flight_and_turns_on_a_legion_that_follows(b: Dictionary) -> void:
	var cfg: Dictionary = content.enemies.viriathus.attacks.feint
	for follow in [true, false]:
		var s := _hispania_sim(b, 1987)
		var h := s.horde
		h.cleave_cd = 1e9
		var ci := h.spawn_chieftain(Vector2(200, 0))
		var id: int = h.e_id[ci]
		var w := h.spawn("celtiberian_warrior", Vector2(200, 120))
		var wid: int = h.e_id[w]
		h.feint_cd = 0.0
		h._chieftain(1.0 / 60.0, s)
		check(s.objectives.notice.get("kind", "") == "feint", "a notice says he turns and runs")
		var t := 0.0
		var far := 0.0
		while t < float(cfg.seconds) + 0.2:
			s.update(1.0 / 60.0, Vector2.RIGHT if follow else Vector2.ZERO, false)
			far = maxf(far, h.e_pos[h.e_id.find(id)].x)
			t += 1.0 / 60.0
		check(far > 230.0, "he runs a short way from the legion (to %.0f px)" % far)
		var c := h.e_id.find(id)
		var k := h.e_id.find(wid)
		if follow:
			check(s.objectives.notice.get("kind", "") == "feint_turn", "when the legion follows, a notice says it was a feint")
			check(h.e_haste[c] > 0.0 and k >= 0 and h.e_haste[k] > 0.0, "and he and the warriors round him rush back in")
		else:
			check(s.objectives.notice.get("kind", "") == "feint" and h.e_haste[c] <= 0.0 and (k < 0 or h.e_haste[k] <= 0.0), "a legion that holds its ground is not caught")


func _aegyptus_sim(b: Dictionary, seed_value: int) -> Sim:
	var s := _gaul_sim(b, seed_value, "aegyptus")
	for t in ["volleys_cd", "sluice_cd"]:
		s.horde.set(t, 1e9)
	s.commander.pos = Vector2.ZERO
	s.legion.place_all(s.facing_angle)
	s._rebuild_grids()
	return s


func _nile_terrain(b: Dictionary, seed_value: int) -> Terrain:
	var t := Terrain.new(seed_value, b.forest, b.ravines)
	t.valley = b.valleys.aegyptus
	t.set_canals(b.canals.aegyptus)
	return t


func test_winning_hispania_opens_aegyptus(b: Dictionary) -> void:
	check(content.ready("provinces", "aegyptus"), "Aegyptus is drawn")
	check(content.province_before("aegyptus") == "hispania", "it follows Hispania")
	var p := _fresh_profile()
	var before: Dictionary = p.data.duplicate(true)
	var s := Sim.new(b, content, {"seed": 1990, "province": "hispania"})
	s.time = 900.0
	s.over = true
	s.victory = true
	p.record_run(s)
	check(p.province_unlocked("aegyptus"), "winning in Hispania opens Aegyptus")
	var said := false
	for u in SummaryScreen.unlocks(before, p.data, content, "hispania"):
		said = said or (u.kind == "province" and u.id == "aegyptus" and str(u.text) == "Aegyptus is open")
	check(said, "and the summary says Aegyptus is open")
	check(content.achievements.has("win_aegyptus") and content.achievements.win_aegyptus.target == "aegyptus", "a win in Aegyptus has its own achievement")
	_cleanup_profile_files()
	p.free()


func test_aegyptus_is_the_nile_valley_with_palms_reeds_ruins_and_canals(b: Dictionary) -> void:
	var area := Rect2(-4000, -4000, 8000, 8000)
	var t := _nile_terrain(b, 1991)
	var kinds := {}
	for pr in t.props_in(area):
		kinds[pr[0]] = kinds.get(pr[0], 0) + 1
	for want in ["date_palm", "papyrus", "fallen_column", "obelisk"]:
		check(kinds.has(want), "the valley holds %s (%s)" % [want, str(kinds.keys())])
	check(not t.fields_in(area).is_empty(), "and fields of grain")
	for not_here in ["oak", "fir", "palm", "dune", "ruined_wall", "olive", "dry_grass", "crops"]:
		check(not kinds.has(not_here), "and no %s" % not_here)
	check(Terrain.TREES.has("date_palm") and Terrain.SOLID.has("date_palm") and Terrain.SOLID.has("obelisk"), "date palms are solid trees that can be felled, and obelisks are solid")
	check(not Terrain.SOLID.has("papyrus"), "reeds block nothing")
	var canals := t.ravines_in(area)
	check(canals.size() >= 3 and canals.all(func(rv: Dictionary) -> bool: return rv.get("canal", false)), "the field is cut by irrigation canals and no gorges (%d)" % canals.size())


func test_every_canal_is_straight_with_bridges_laid_across_it(b: Dictionary) -> void:
	var cfg: Dictionary = b.canals.aegyptus
	var t := _nile_terrain(b, 1992)
	var canals := t.ravines_in(Rect2(-6000, -6000, 12000, 12000))
	var straight := true
	var even := true
	var decks := true
	for rv in canals:
		for piece in rv.pieces:
			var pts: PackedVector2Array = piece.pts
			var a := pts[0]
			var dir := (pts[pts.size() - 1] - a).normalized()
			for q in pts:
				straight = straight and absf((q - a).dot(dir.orthogonal())) < 0.5
			for h in piece.half:
				even = even and h >= float(cfg.width[0]) / 2.0 - 0.01 and h <= float(cfg.width[1]) / 2.0 + 0.01 and is_equal_approx(h, piece.half[0])
		for br in rv.crossings:
			decks = decks and t.bridges.has(br) and t.ravine_edge(br.pos) < 0.0
			decks = decks and t.ravine_edge(br.pos + br.dir * br.half_len) >= 0.0 and t.ravine_edge(br.pos - br.dir * br.half_len) >= 0.0
	check(canals.size() > 5, "canals are laid across the field (%d)" % canals.size())
	check(straight and even, "each canal runs straight and keeps its width")
	check(decks, "and every crossing is a deck laid across the water from bank to bank")


## Every canal piece of the regions reaching into the area.
func _canal_pieces(t: Terrain, area: Rect2) -> Array:
	var out: Array = []
	for rv in t.ravines_in(area):
		for piece in rv.pieces:
			out.append(piece)
	return out


func test_canals_run_on_unbroken_from_region_to_region(b: Dictionary) -> void:
	var area := Rect2(-6000, -6000, 12000, 12000)
	var inner := area.grow(-2 * float(b.canals.aegyptus.region))
	for seed_value in [2101, 2102, 2103]:
		var t := _nile_terrain(b, seed_value)
		var pieces := _canal_pieces(t, area)
		var ends: Array = []
		for piece in pieces:
			ends.append(piece.pts[0])
			ends.append(piece.pts[piece.pts.size() - 1])
		var loose := 0
		for e in ends:
			if not inner.has_point(e):
				continue
			var met := 0
			for f in ends:
				if f.distance_to(e) < 0.5:
					met += 1
			if met < 2:
				loose += 1
		check(pieces.size() > 10, "seed %d lays canals across the field (%d pieces)" % [seed_value, pieces.size()])
		check(loose == 0, "and every piece runs on into the next region's, so no canal ends inside the world (%d loose ends)" % loose)


func test_canals_run_parallel_and_well_apart(b: Dictionary) -> void:
	var cfg: Dictionary = b.canals.aegyptus
	for seed_value in [2111, 2112, 2113, 2114]:
		var t := _nile_terrain(b, seed_value)
		var pieces := _canal_pieces(t, Rect2(-6000, -6000, 12000, 12000))
		var dir: Vector2 = (pieces[0].pts[1] - pieces[0].pts[0]).normalized()
		var parallel := true
		var across := {}
		for piece in pieces:
			var d: Vector2 = (piece.pts[1] - piece.pts[0]).normalized()
			parallel = parallel and absf(d.cross(dir)) < 0.001
			across[roundi(piece.pts[0].dot(dir.orthogonal()))] = true
		var lines: Array = across.keys()
		lines.sort()
		var spaced := true
		# Pieces of one canal can round to the next whole pixel across, so lines within a few pixels are one canal.
		lines = lines.filter(func(u: int) -> bool: return not across.has(u - 1) and not across.has(u - 2))
		for i in lines.size() - 1:
			var gap: float = lines[i + 1] - lines[i]
			spaced = spaced and gap >= float(cfg.apart[0]) - 3.0 and gap <= float(cfg.apart[1]) + 3.0
		check(parallel, "seed %d: every canal runs the same way" % seed_value)
		check(lines.size() >= 6 and spaced, "seed %d: and each lies %s px from the next (%s)" % [seed_value, str(cfg.apart), str(lines)])


func test_the_start_lies_clear_between_two_canals(b: Dictionary) -> void:
	var cfg: Dictionary = b.canals.aegyptus
	var clear := true
	var between := true
	for seed_value in range(2120, 2160):
		var t := _nile_terrain(b, seed_value)
		clear = clear and t.ravine_edge(Vector2.ZERO, 2000.0) >= float(cfg.start_clear)
		var pieces := _canal_pieces(t, Rect2(-1500, -1500, 3000, 3000))
		var side: Vector2 = (pieces[0].pts[1] - pieces[0].pts[0]).normalized().orthogonal()
		var sides := {}
		for piece in pieces:
			sides[signf(piece.pts[0].dot(side))] = true
		between = between and sides.size() == 2
	check(clear, "the start is always at least %s px from the nearest canal" % str(cfg.start_clear))
	check(between, "with a canal on either side of it")


func test_a_bridge_crosses_every_canal_often(b: Dictionary) -> void:
	var cfg: Dictionary = b.canals.aegyptus
	var t := _nile_terrain(b, 2131)
	var area := Rect2(-5000, -5000, 10000, 10000)
	var pieces := _canal_pieces(t, area)
	var bridges: Array = t.bridges.filter(func(br: Dictionary) -> bool: return area.has_point(br.pos))
	var farthest := 0.0
	var on_canal := true
	for br in bridges:
		on_canal = on_canal and t.ravine_edge(br.pos) < 0.0
	for piece in pieces:
		var pts: PackedVector2Array = piece.pts
		var along: Vector2 = (pts[1] - pts[0]).normalized()
		for q in pts:
			if not area.grow(-800).has_point(q):
				continue
			var near := INF
			for br in bridges:
				if absf((br.pos - q).dot(along.orthogonal())) < 1.0:
					near = minf(near, absf((br.pos - q).dot(along)))
			farthest = maxf(farthest, near)
	check(bridges.size() > 20 and on_canal, "bridges are laid over the canals (%d)" % bridges.size())
	check(farthest <= float(cfg.bridge_every[1]) / 2.0 + 1.0, "and no point along a canal is more than half of %s px from a bridge (%.0f)" % [str(cfg.bridge_every[1]), farthest])


func test_canal_bridges_agree_whichever_region_is_built_first(b: Dictionary) -> void:
	var one := _nile_terrain(b, 2141)
	var two := _nile_terrain(b, 2141)
	var size := float(b.canals.aegyptus.region)
	var cells: Array = []
	for rx in range(-3, 3):
		for ry in range(-3, 3):
			cells.append(Vector2i(rx, ry))
	for c in cells:
		one.ravines_in(Rect2(Vector2(c) * size + Vector2.ONE * size * 0.4, Vector2.ONE * size * 0.2))
	cells.reverse()
	for c in cells:
		two.ravines_in(Rect2(Vector2(c) * size + Vector2.ONE * size * 0.4, Vector2.ONE * size * 0.2))
	var area := Rect2(-2 * size, -2 * size, 3 * size, 3 * size)
	var a: Array = one.bridges.filter(func(br: Dictionary) -> bool: return area.has_point(br.pos)).map(func(br: Dictionary) -> Vector2: return br.pos.snapped(Vector2.ONE * 0.01))
	var z: Array = two.bridges.filter(func(br: Dictionary) -> bool: return area.has_point(br.pos)).map(func(br: Dictionary) -> Vector2: return br.pos.snapped(Vector2.ONE * 0.01))
	a.sort()
	z.sort()
	var once := true
	for i in a.size() - 1:
		once = once and a[i] != a[i + 1]
	check(a.size() > 5 and a == z, "the same bridges stand whichever region was built first (%d and %d)" % [a.size(), z.size()])
	check(once, "and a bridge near a region's edge is laid only once")


func test_nothing_solid_stands_in_a_canal_bridge_mouth(b: Dictionary) -> void:
	var cfg: Dictionary = b.canals.aegyptus
	var t := _nile_terrain(b, 2151)
	var area := Rect2(-4000, -4000, 8000, 8000)
	var props := t.props_in(area)
	var blocked := 0
	var n := 0
	for br in t.bridges:
		if not area.grow(-200).has_point(br.pos):
			continue
		n += 1
		for end in [-1.0, 1.0]:
			var mouth: Vector2 = br.pos + br.dir * end * (br.half_len + float(cfg.bridge_clear) / 2.0)
			for pr in props:
				if pr[2] > 0.0 and pr[1].distance_to(mouth) < float(cfg.bridge_clear) / 2.0 + pr[2]:
					blocked += 1
	check(n > 10 and blocked == 0, "no palm, stone or ruin stands at either end of a bridge (%d of %d)" % [blocked, n])


func test_grain_fields_line_the_canal_banks(b: Dictionary) -> void:
	var band := float(b.canals.aegyptus.band)
	var fray: float = load("res://scripts/world_view.gd").FIELD_FRAY
	var cfg: Dictionary = b.valleys.aegyptus
	var area := Rect2(-5000, -5000, 10000, 10000)
	var count := 0
	var by_water := true
	var dry := true
	var clear := true
	var big := true
	var breaks := true
	var open := true
	var tilted := false
	for seed_value in [2161, 2162, 2163]:
		var t := _nile_terrain(b, seed_value)
		var fields := t.fields_in(area)
		count += fields.size()
		tilted = tilted or absf(t.field_turn) > 0.01
		for f: Rect2 in fields:
			big = big and f.size.x >= 200.0 and f.size.y >= float(cfg.grain_depth[0])
			var near := INF
			# The drawn wheat reaches FIELD_FRAY past the field, so that whole area is checked.
			var drawn := f.grow(fray)
			var x := drawn.position.x
			while x <= drawn.end.x:
				var y := drawn.position.y
				while y <= drawn.end.y:
					var p := Vector2(x, y).rotated(t.field_turn)
					var e := t.ravine_edge(p, 900.0)
					near = minf(near, e)
					dry = dry and e >= band
					clear = clear and not t._by_bridge(p)
					open = open and p.length() > t.clear_radius
					y += 16.0
				x += 16.0
			by_water = by_water and near <= band + fray + 40.0
			for g: Rect2 in fields:
				# Fields on one bank share the edge nearest the water, and leave open ground between them.
				var same_bank := absf(g.position.y - f.position.y) < 1.0 or absf(g.end.y - f.end.y) < 1.0
				if g != f and same_bank and g.position.x > f.position.x:
					breaks = breaks and g.position.x - f.end.x >= 150.0
		for pr in t.props_in(area):
			for f: Rect2 in fields:
				if pr[2] > 0.0 and f.grow(pr[2] + 16.0).has_point(pr[1].rotated(-t.field_turn)):
					open = false
	check(count >= 30, "large grain fields are laid along the canals (%d)" % count)
	check(big, "and each is as big as a Gaulish wheat field")
	check(tilted, "and they lie along the canals however these are tilted")
	check(by_water, "every field lies just outside the bank's band")
	check(dry, "and no wheat is drawn over the water or the bank's band")
	check(clear, "and none reaches a bridge's approach")
	check(breaks, "and the fields along one bank have breaks between them")
	check(open, "and nothing solid stands in a field, nor any field by the start")


func test_grain_fields_are_walked_through_and_kept_out_of_clearings(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 2171, "province": "aegyptus"})
	var fields := s.terrain.fields_in(Rect2(-4000, -4000, 8000, 8000))
	check(not fields.is_empty(), "Aegyptus has grain fields (%d)" % fields.size())
	if fields.is_empty():
		return
	var f: Rect2 = fields[0]
	var mid := f.get_center().rotated(s.terrain.field_turn)
	s.terrain.refresh(mid)
	check(s.terrain.fd_rect.is_empty() and not s.terrain.in_field(mid, 10.0), "the grain blocks nobody, as Gaul's wheat does")
	check(s.terrain.push_out(mid, 10.0) == mid, "and a man standing in it is not pushed out")
	s.terrain.add_clearing(mid, 120.0, [])
	check(not s.terrain.fields_in(Rect2(-4000, -4000, 8000, 8000)).has(f), "a clearing laid over a field takes it away")


func test_a_canal_holds_men_back_but_its_bridge_carries_them(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 1993, "province": "aegyptus"})
	var rv: Dictionary = {}
	for c in s.terrain.ravines_in(Rect2(-3000, -3000, 6000, 6000)):
		if rv.is_empty() or c.box.get_center().length() < rv.box.get_center().length():
			rv = c
	check(not rv.is_empty(), "a canal lies near the start")
	if rv.is_empty():
		return
	var br: Dictionary = rv.crossings[0]
	var along: Vector2 = br.dir.orthogonal()
	var water: Vector2 = br.pos + along * (br.half_w + 30.0)
	if Terrain.edge_of(rv, water) >= 0.0:
		water = br.pos - along * (br.half_w + 30.0)
	s.commander.pos = br.pos
	s.terrain.refresh(s.commander.pos)
	check(Terrain.edge_of(rv, s.terrain.push_out(water, Sim.UNIT_RADIUS)) >= -0.5, "a man is kept out of the water")
	check(s.terrain.push_out(br.pos, Sim.UNIT_RADIUS) == br.pos and s.terrain.on_bridge(br.pos) >= 0, "but walks over the crossing, which the legion files across like any bridge")


func test_reeds_slow_the_march_but_block_nothing(b: Dictionary) -> void:
	var s := _aegyptus_sim(b, 1994)
	s.terrain.add_clearing(Vector2(0, 300), 1.0, [["papyrus", Vector2(0, 300), 0.0]])
	s.terrain.refresh(s.commander.pos)
	check(s.terrain.push_out(Vector2(0, 302), Sim.UNIT_RADIUS) == Vector2(0, 302), "a man walks into the reeds")
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var open := s.speed()
	s.commander.pos = Vector2(0, 300)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.in_reeds and is_equal_approx(s.speed(), open * (1.0 - float(b.valleys.aegyptus.reed_slow))), "and the legion marches a little slower while the commander is among them (%.1f against %.1f)" % [s.speed(), open])


func test_reed_beds_are_patches_on_the_canal_banks(b: Dictionary) -> void:
	var cfg: Dictionary = b.valleys.aegyptus
	var t := _nile_terrain(b, 1995)
	t.set_canals({})
	t.add_ravine([{"pts": PackedVector2Array([Vector2(-400, 0), Vector2(400, 0)]), "half": PackedFloat32Array([20.0, 20.0])}])
	var roll := float(cfg.grove_chance) + 0.01
	var small := true
	var banks := true
	var dry := true
	for k in 30:
		var r := RandomNumberGenerator.new()
		r.seed = 700 + k
		var bed: Array = t._valley_feature(r, roll, Vector2(r.randf_range(-200, 200), r.randf_range(-250, 250)))
		small = small and bed.size() >= int(cfg.reeds[0]) and bed.size() <= int(cfg.reeds[1]) and bed.all(func(pr: Array) -> bool: return pr[0] == "papyrus")
		if bed.is_empty():
			continue
		var box := Rect2(bed[0][1], Vector2.ZERO)
		for pr in bed:
			box = box.expand(pr[1])
			banks = banks and absf(pr[1].y) < 20.0 + 2.0 * float(cfg.reed_spread[1]) + 10.0
			dry = dry and t.ravine_edge(pr[1]) > 0.0
		small = small and box.size.x <= 2.0 * float(cfg.reed_spread[0]) + 1.0 and box.size.y <= 2.0 * float(cfg.reed_spread[1]) + 1.0
	check(small, "a reed bed is a small patch of papyrus, never a maze")
	check(banks, "it grows on the bank of the canal nearby")
	check(dry, "and never in the water")


func test_temple_ruins_are_solid_and_leave_room_to_pass(b: Dictionary) -> void:
	var cfg: Dictionary = b.valleys.aegyptus
	var t := _nile_terrain(b, 1996)
	t.set_canals({})
	var roll := float(cfg.grove_chance) + float(cfg.reed_chance) + 0.01
	var whole := true
	var apart := true
	for k in 30:
		var r := RandomNumberGenerator.new()
		r.seed = 800 + k
		var ruin: Array = t._valley_feature(r, roll, Vector2(900, 900))
		var pieces := ruin.filter(func(pr: Array) -> bool: return pr[0] != "")
		var obelisks := pieces.filter(func(pr: Array) -> bool: return pr[0] == "obelisk").size()
		var columns := pieces.filter(func(pr: Array) -> bool: return pr[0] == "fallen_column").size()
		whole = whole and obelisks == 1 and columns >= int(cfg.columns[0]) and columns <= int(cfg.columns[1])
		whole = whole and ruin.size() - pieces.size() == columns * cfg.column_blockers.size()
		for i in pieces.size():
			for j in range(i + 1, pieces.size()):
				apart = apart and pieces[i][1].distance_to(pieces[j][1]) >= float(cfg.ruin_gap)
	check(whole, "a ruin is an obelisk and a few fallen columns, each column held by its blockers")
	check(apart, "and its stones lie far enough apart to march between")
	var s := _aegyptus_sim(b, 1997)
	s.terrain.add_clearing(Vector2(0, 300), 1.0, [["fallen_column", Vector2(0, 300), 0.0], ["", Vector2(20, 300), 8.0], ["obelisk", Vector2(200, 300), Terrain.SOLID.obelisk]])
	s.terrain.refresh(s.commander.pos)
	check(s.terrain.push_out(Vector2(20, 302), Sim.UNIT_RADIUS) != Vector2(20, 302) and s.terrain.push_out(Vector2(200, 302), Sim.UNIT_RADIUS) != Vector2(200, 302), "a man is pushed out of a column or an obelisk")


func test_aegyptus_warriors_thrust_shoot_dart_and_lunge(b: Dictionary) -> void:
	var e: Dictionary = content.enemies
	check(e.egyptian_spearman.thrust.reach > e.celtiberian_warrior.slash.reach and e.egyptian_spearman.speed < e.celtiberian_warrior.speed, "the spearman is slow but his thrust reaches further than a sword")
	check(float(e.egyptian_spearman.armour.arrows) > 0.0, "and his tall shield turns part of each arrow")
	check(e.nubian_archer.has("volley") and float(e.nubian_archer.range) > float(e.gaul_archer.range), "the Nubian archer looses volleys from further off than a Gaulish archer")
	check(e.khopesh_raider.has("sprint") and e.khopesh_raider.speed > e.egyptian_spearman.speed, "the khopesh raider is quick and darts in")
	check(e.crocodile.behaviour == "beast" and is_equal_approx(float(e.crocodile.share), 0.5) and float(e.crocodile.arrives) >= 120.0, "the crocodile is a beast that comes after a couple of minutes, half as often")
	check(float(e.crocodile.speed) < float(e.war_hound.speed) and float(e.crocodile.speed) < float(content.base_commander.speed) * 0.6, "and is slow on land")
	var s := _aegyptus_sim(b, 1998)
	var h := s.horde
	var far := h.spawn("crocodile", Vector2(s.legion_reach + 160.0, 0))
	h.e_cd[far] = 0.0
	h._move(1.0 / 60.0, s)
	check(h.e_dash[far] <= 0.0, "a crocodile far from the legion does not lunge")
	var near := h.spawn("crocodile", Vector2(-s.legion_reach - 35.0, 0))
	h.e_cd[near] = 0.0
	h._move(1.0 / 60.0, s)
	var rush: Dictionary = e.crocodile.rush
	check(h.e_dash[near] > 0.0 and float(e.crocodile.speed) * float(rush.speed_mult) * float(rush.seconds) < 50.0, "one close to it lunges a short way")


func test_the_priest_of_sobek_hardens_the_warriors_round_him(b: Dictionary) -> void:
	var s := _aegyptus_sim(b, 1999)
	var h := s.horde
	var info: Dictionary = content.enemies.sobek_priest
	var cfg: Dictionary = info.harden
	var i := h.spawn("sobek_priest", Vector2(300, 0), true)
	var st: Dictionary = h.boss_state(i)
	var near_one := h.spawn("egyptian_spearman", h.e_pos[i] + Vector2(40, 0))
	var far_one := h.spawn("egyptian_spearman", h.e_pos[i] + Vector2(float(cfg.radius) + 60.0, 0))
	h.rebuild_grid()
	st.harden_cd = 0.0
	h._bosses(1.0 / 60.0, s)
	var taken := func(j: int) -> float:
		var before := h.e_hp[j]
		s.hit(j, 10.0)
		var lost := before - h.e_hp[j]
		h.e_hp[j] = before
		return lost
	var hard: float = taken.call(near_one)
	var soft: float = taken.call(far_one)
	check(is_equal_approx(hard, soft * (1.0 - float(cfg.cut))), "his blessing hardens the warriors round him against blows (%.1f against %.1f)" % [hard, soft])
	check(info.keys().filter(func(k: String) -> bool: return h.ABILITY_TIMERS.has(k)).size() == 1, "it is his one ability")
	s.time += float(cfg.seconds) + 0.1
	h.time = s.time
	check(is_equal_approx(taken.call(near_one), soft), "and it wears off after %.0f seconds" % float(cfg.seconds))


func test_the_camel_captain_leads_a_wedge_of_camel_riders(b: Dictionary) -> void:
	var s := _aegyptus_sim(b, 2000)
	var h := s.horde
	var cfg: Dictionary = content.enemies.camel_captain.wedge
	var i := h.spawn("camel_captain", Vector2(s.legion_reach + 100.0, 0), true)
	var st: Dictionary = h.boss_state(i)
	st.wedge_cd = 0.0
	h._bosses(1.0 / 60.0, s)
	var riders: Array = st.wedge.filter(func(w: Array) -> bool: return h.e_id.has(w[0]) and h.kind_ids[h.e_kind[h.e_id.find(w[0])]] == "camel_rider")
	check(st.rush_warn > 0.0 and riders.size() == int(cfg.riders), "he marks a lane and %d camel riders form a wedge behind him" % int(cfg.riders))


func test_achillas_raises_his_hand_and_volleys_fall_on_marked_rings(b: Dictionary) -> void:
	var cfg: Dictionary = content.enemies.achillas.attacks.volleys
	for stay in [true, false]:
		var s := _aegyptus_sim(b, 2001)
		var h := s.horde
		h.spawn_chieftain(Vector2(250, 0))
		h.cleave_cd = 1e9
		var hp0: float = s.commander.hp
		var men0 := 0.0
		for so in s.soldiers:
			men0 += so.hp
		h.volleys_cd = 0.0
		h._chieftain(1.0 / 60.0, s)
		var rings := h.foe_lobs.filter(func(l: Dictionary) -> bool: return l.get("volley", false))
		if stay:
			check(s.objectives.notice.get("kind", "") == "volleys", "a notice says he raises his hand")
			check(rings.size() == int(cfg.rings), "%d rings are marked over the legion" % int(cfg.rings))
			check(rings.any(func(l: Dictionary) -> bool: return l.to.distance_to(s.commander.pos) < 1.0), "one of them on the commander")
			check(rings.all(func(l: Dictionary) -> bool: return float(l.dur) >= 1.4), "each marked long enough to step out of it")
		else:
			s.commander.pos += Vector2(0, float(cfg.radius) * 2.0 + float(cfg.spread) * 2.0 + s.legion_reach)
		var t := 0.0
		while t < float(cfg.delay) - 0.1:
			h._foe_lobs(1.0 / 60.0, s)
			t += 1.0 / 60.0
		if stay:
			check(s.commander.hp == hp0, "nothing falls while the rings are marked")
		for k in 12:
			h._foe_lobs(1.0 / 60.0, s)
		var men := 0.0
		for so in s.soldiers:
			men += so.hp
		if stay:
			check(s.commander.hp <= hp0 - float(cfg.damage) * 0.5, "then the arrows strike a commander who stayed in his ring")
			check(men < men0, "and the soldiers under the rings")
		else:
			check(s.commander.hp == hp0, "but a commander who stepped out is not hurt")
	var s2 := _aegyptus_sim(b, 2002)
	s2.horde.spawn_chieftain(Vector2(250, 0))
	s2.horde.chief_fury = true
	s2.horde.volleys(s2.horde.chieftain_index(), s2)
	check(s2.horde.foe_lobs.size() == int(cfg.fury_rings), "in his fury more rings are marked")


func test_achillas_opens_the_sluices_across_the_legions_path(b: Dictionary) -> void:
	var cfg: Dictionary = content.enemies.achillas.attacks.sluice
	var s := _aegyptus_sim(b, 2003)
	var h := s.horde
	s.facing_angle = 0.0
	h.spawn_chieftain(Vector2(-250, 0))
	h.cleave_cd = 1e9
	var w := h.spawn("khopesh_raider", Vector2(120, 140))
	h.rebuild_grid()
	var dry := s.speed()
	h.sluice_cd = 0.0
	h._chieftain(1.0 / 60.0, s)
	check(s.objectives.notice.get("kind", "") == "sluice", "a notice says he opens the sluices")
	check(not h.flood.is_empty(), "a band of ground is marked")
	if h.flood.is_empty():
		return
	var ahead := Vector2.from_angle(s.facing_angle)
	check((h.flood.pos - s.commander.pos).dot(ahead) > 0.0 and absf(h.flood.dir.dot(ahead)) < 0.05, "across the legion's path, ahead of it")
	s.commander.pos = h.flood.pos
	h._sluice_on(1.0 / 60.0, s)
	check(is_equal_approx(s.speed(), dry), "the ground is only marked at first, and does not slow the march")
	var t := 0.0
	while t < float(cfg.warn) + 0.1:
		h._sluice_on(1.0 / 60.0, s)
		t += 1.0 / 60.0
	check(is_equal_approx(s.speed(), dry * (1.0 - float(cfg.slow))), "then the water comes and slows the legion inside it")
	check(h.e_haste[w] > 0.0, "while his warriors close in")
	s.commander.pos = h.flood.pos + h.flood.dir.orthogonal() * (float(cfg.width) / 2.0 + 20.0)
	h._sluice_on(1.0 / 60.0, s)
	check(is_equal_approx(s.speed(), dry), "a legion beside the band marches on dry")
	while t < float(cfg.warn) + float(cfg.seconds) + 0.2:
		h._sluice_on(1.0 / 60.0, s)
		t += 1.0 / 60.0
	check(h.flood.is_empty(), "and the water drains after %.0f seconds" % float(cfg.seconds))


func test_the_shepherd_general_marks_rings_where_hidden_men_hurl_javelins(b: Dictionary) -> void:
	var atk: Dictionary = content.enemies.viriathus.attacks
	check(atk.has("javelins"), "the shepherd general has a javelin attack")
	if not atk.has("javelins"):
		return
	var cfg: Dictionary = atk.javelins
	for stay in [true, false]:
		var s := _hispania_sim(b, 1990)
		var h := s.horde
		var ci := h.spawn_chieftain(Vector2(250, 0))
		h.cleave_cd = 1e9
		var hp0: float = s.commander.hp
		var men0 := 0.0
		for so in s.soldiers:
			men0 += so.hp
		h.set("javelins_cd", 0.0)
		h._chieftain(1.0 / 60.0, s)
		var rings := h.foe_lobs.filter(func(l: Dictionary) -> bool: return l.get("volley", false))
		if stay:
			check(s.objectives.notice.get("kind", "") == "javelins", "a notice warns of the javelins")
			check(rings.size() == int(cfg.rings), "%d rings are marked over the legion" % int(cfg.rings))
			check(rings.any(func(l: Dictionary) -> bool: return l.to.distance_to(s.commander.pos) < 1.0), "one of them on the commander")
			check(rings.all(func(l: Dictionary) -> bool: return float(l.dur) >= 1.4), "each marked long enough to step out of it")
			check(rings.all(func(l: Dictionary) -> bool: return l.from.distance_to(l.to) >= float(cfg.hidden) * 0.8 and l.from.distance_to(h.e_pos[ci]) > 60.0), "thrown by hidden men off the legion's flanks, not by him")
		else:
			s.commander.pos += Vector2(0, float(cfg.radius) * 2.0 + float(cfg.spread) * 2.0 + s.legion_reach)
		var t := 0.0
		while t < float(cfg.delay) - 0.1:
			h._foe_lobs(1.0 / 60.0, s)
			t += 1.0 / 60.0
		if stay:
			check(s.commander.hp == hp0, "nothing falls while the rings are marked")
		for k in 12:
			h._foe_lobs(1.0 / 60.0, s)
		var men := 0.0
		for so in s.soldiers:
			men += so.hp
		if stay:
			check(s.commander.hp <= hp0 - float(cfg.damage) * 0.5, "then the javelins strike a commander who stayed in his ring")
			check(men < men0, "and the soldiers under the rings")
		else:
			check(s.commander.hp == hp0, "but a commander who stepped out is not hurt")
	var s2 := _hispania_sim(b, 1991)
	s2.horde.spawn_chieftain(Vector2(250, 0))
	s2.horde.chief_fury = true
	s2.horde.call("volleys", s2.horde.chieftain_index(), s2, "javelins")
	check(s2.horde.foe_lobs.size() == int(cfg.fury_rings), "in his fury more rings are marked")


func test_overlapping_rings_of_one_volley_strike_each_man_once(b: Dictionary) -> void:
	var s := _aegyptus_sim(b, 2004)
	var h := s.horde
	h.spawn_chieftain(Vector2(250, 0))
	h.cleave_cd = 1e9
	h.volleys(h.chieftain_index(), s)
	var dmg: float = h.foe_lobs[0].dmg
	for l in h.foe_lobs:
		l.to = s.commander.pos
	var hp0: float = s.commander.hp
	for k in 150:
		h._foe_lobs(1.0 / 60.0, s)
	check(is_equal_approx(hp0 - s.commander.hp, dmg), "a commander under several rings of one volley is struck once (%.0f of %.0f)" % [hp0 - s.commander.hp, dmg])


func test_a_stunned_or_fallen_general_calls_off_what_he_was_warning_of(b: Dictionary) -> void:
	for fate in ["stun", "death"]:
		var s := _aegyptus_sim(b, 2005)
		var h := s.horde
		h.spawn_chieftain(Vector2(-250, 0))
		h.cleave_cd = 1e9
		h.sluice_cd = 0.0
		h._chieftain(1.0 / 60.0, s)
		var ci := h.chieftain_index()
		if fate == "stun":
			h.e_stun[ci] = 3.0
			h._chieftain(1.0 / 60.0, s)
		else:
			h.drive = {"t": 0.0, "warn": 1.0}
			h.sweep = {"t": 0.0}
			s.hit(ci, 1e9)
			s._remove_dead()
		check(h.flood.is_empty(), "a %s calls off the flood he marked" % fate)
		if fate == "death":
			check(h.drive.is_empty() and h.sweep.is_empty(), "and no marked path or sweep outlives him")
		var v := _hispania_sim(b, 1992)
		var vh := v.horde
		vh.spawn_chieftain(Vector2(250, 0))
		vh.cleave_cd = 1e9
		vh.ambush_cd = 0.0
		vh._chieftain(1.0 / 60.0, v)
		var vi := vh.chieftain_index()
		if fate == "stun":
			vh.e_stun[vi] = 3.0
			vh._chieftain(1.0 / 60.0, v)
		else:
			v.hit(vi, 1e9)
			v._remove_dead()
		check(vh.ambush_wait <= 0.0, "a %s calls off the ambush he warned of" % fate)


func test_a_win_stands_when_the_commander_falls_in_the_same_moment(b: Dictionary) -> void:
	var s := _fort_sim(b, 405)
	s.commander.pos = s.objectives.fort.centre
	s.objectives.fort.hold = float(b.fort.hold) - 0.001
	s.commander.hp = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.objectives.fort_reached and s.victory, "the fort held in the commander's last moment still wins the run")


func test_rations_do_not_raise_a_fallen_commander(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 406})
	s.ranks["rations"] = 3
	s.commander.hp = -0.01
	s._regen(1.0 / 60.0)
	check(s.commander.hp <= 0.0, "rations do not heal a commander who has fallen")


func test_sprites_far_north_keep_their_depth_order(b: Dictionary) -> void:
	var view: GDScript = load("res://scripts/world_view.gd")
	var cam := -150000.0
	var ground: int = view.depth_key(cam - 60000.0, cam, 3)
	var man: int = view.depth_key(cam + 10.0, cam, 1)
	var behind: int = view.depth_key(cam - 10.0, cam, 2)
	check(ground >= 0 and behind >= 0 and man >= 0, "depth keys far north stay positive")
	check(ground < behind and behind < man, "and keep the ground under the men, and the further man behind the nearer")
	check(ground % 65536 == 3 and man % 65536 == 1, "and each key still names its sprite")
	var steady := true
	for k in 8:
		var c := 0.125 * k
		steady = steady and view.depth_key(100.7, c, 1) < view.depth_key(101.2, c, 0)
	check(steady, "two trees a pixel apart keep their order however the camera moves between pixels")


func test_a_boss_shoved_into_a_canal_falls_into_the_water(b: Dictionary) -> void:
	var s := _aegyptus_sim(b, 2006)
	var i := s.horde.spawn("camel_captain", Vector2(100, 0), true)
	s._fall(i, Vector2(100, 0), Vector2(90, 0))
	var into: Vector2 = s.effects[-1].into
	check(into.length() <= float(b.canals.aegyptus.width[0]) * 0.5, "he sinks within the canal, not on its far bank (%.0f px)" % into.length())


func _sarmatia_sim(b: Dictionary, seed_value: int) -> Sim:
	var s := _gaul_sim(b, seed_value, "sarmatia")
	for t in ["lancers_cd", "fire_cd"]:
		s.horde.set(t, 1e9)
	s.commander.pos = Vector2.ZERO
	s.legion.place_all(s.facing_angle)
	s._rebuild_grids()
	return s


func test_the_steppe_hunts_with_riders_as_well_as_wolves(b: Dictionary) -> void:
	var s := _sarmatia_sim(b, 9601)
	s.horde.time = 600.0
	var kinds := s.horde.hunters()
	check(kinds.has("lasso_rider") and kinds.has("steppe_wolf"), "lasso riders hunt a running legion beside the wolves (%s)" % str(kinds))


func _steppe_terrain(b: Dictionary, seed_value: int) -> Terrain:
	var t := Terrain.new(seed_value, b.forest, b.ravines)
	t.steppe = b.steppes.sarmatia
	return t


func _men_hp(s: Sim) -> float:
	var hp := 0.0
	for so in s.soldiers:
		hp += so.hp
	return hp


func test_winning_dacia_opens_sarmatia(b: Dictionary) -> void:
	check(content.ready("provinces", "sarmatia"), "Sarmatia is drawn")
	check(content.provinces.keys().back() == "sarmatia", "Sarmatia is the last province on the road")
	check(content.province_before("sarmatia") == "dacia", "it follows Dacia")
	var p := _fresh_profile()
	var before: Dictionary = p.data.duplicate(true)
	var s := Sim.new(b, content, {"seed": 2100, "province": "dacia"})
	s.time = 900.0
	s.over = true
	s.victory = true
	p.record_run(s)
	check(p.province_unlocked("sarmatia"), "winning in Dacia opens Sarmatia")
	var said := false
	for u in SummaryScreen.unlocks(before, p.data, content, "dacia"):
		said = said or (u.kind == "province" and u.id == "sarmatia" and str(u.text) == "Sarmatia is open")
	check(said, "and the summary says Sarmatia is open")
	check(content.achievements.has("win_sarmatia") and content.achievements.win_sarmatia.target == "sarmatia", "a win in Sarmatia has its own achievement")
	_cleanup_profile_files()
	p.free()


func test_sarmatia_is_open_steppe_with_feather_grass_kurgans_wagons_and_birches(b: Dictionary) -> void:
	var area := Rect2(-4000, -4000, 8000, 8000)
	var t := _steppe_terrain(b, 2110)
	var kinds := {}
	for pr in t.props_in(area):
		kinds[pr[0]] = kinds.get(pr[0], 0) + 1
	for want in ["feather_grass", "kurgan", "wagon", "birch", "stones"]:
		check(kinds.has(want), "the steppe holds %s (%s)" % [want, str(kinds.keys())])
	for not_here in ["oak", "fir", "pine", "olive", "dry_grass", "heather", "rock", "log"]:
		check(not kinds.has(not_here), "and no %s" % not_here)
	check(Terrain.TREES.has("birch") and Terrain.SOLID.has("birch"), "birches are solid trees that can be felled")
	check(not Terrain.SOLID.has("feather_grass") and not Terrain.SOLID.has("kurgan") and not Terrain.SOLID.has("wagon"), "grass blocks nothing, and mounds and wagons are held by blockers of their own")
	check(int(kinds.get("birch", 0)) * 4 < int(kinds.get("feather_grass", 0)), "birches grow in a few copses, not forests (%d)" % int(kinds.get("birch", 0)))


func test_feather_grass_slows_the_march_but_blocks_nothing(b: Dictionary) -> void:
	var s := _sarmatia_sim(b, 2111)
	s.terrain.add_clearing(Vector2(0, 300), 1.0, [["feather_grass", Vector2(0, 300), 0.0]])
	s.terrain.refresh(s.commander.pos)
	check(s.terrain.push_out(Vector2(0, 302), Sim.UNIT_RADIUS) == Vector2(0, 302), "a man walks into the grass")
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var open := s.speed()
	s.commander.pos = Vector2(0, 300)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.in_grass and is_equal_approx(s.speed(), open * (1.0 - float(b.steppes.sarmatia.grass_slow))), "and the legion marches a little slower while the commander is in it (%.1f against %.1f)" % [s.speed(), open])


func test_feather_grass_grows_in_patches(b: Dictionary) -> void:
	var cfg: Dictionary = b.steppes.sarmatia
	var t := _steppe_terrain(b, 2112)
	var small := true
	for k in 30:
		var r := RandomNumberGenerator.new()
		r.seed = 900 + k
		var patch: Array = t._steppe_feature(r, 0.01, Vector2(900, 900))
		small = small and patch.size() >= int(cfg.grasses[0]) and patch.size() <= int(cfg.grasses[1]) and patch.all(func(pr: Array) -> bool: return pr[0] == "feather_grass")
		var box := Rect2(patch[0][1], Vector2.ZERO) if not patch.is_empty() else Rect2()
		for pr in patch:
			box = box.expand(pr[1])
		small = small and box.size.x <= 2.0 * float(cfg.grass_spread[0]) + 1.0 and box.size.y <= 2.0 * float(cfg.grass_spread[1]) + 1.0
	check(small, "feather grass grows in small patches, never a maze")


func test_kurgans_are_solid_mounds_with_room_between_them(b: Dictionary) -> void:
	var cfg: Dictionary = b.steppes.sarmatia
	var t := _steppe_terrain(b, 2113)
	var roll := float(cfg.grass_chance) + 0.01
	var whole := true
	var apart := true
	for k in 30:
		var r := RandomNumberGenerator.new()
		r.seed = 950 + k
		var found: Array = t._steppe_feature(r, roll, Vector2(900, 900))
		var mounds := found.filter(func(pr: Array) -> bool: return pr[0] == "kurgan")
		whole = whole and mounds.size() >= int(cfg.kurgans[0]) and mounds.size() <= int(cfg.kurgans[1])
		whole = whole and found.size() - mounds.size() == mounds.size() * cfg.kurgan_blockers.size()
		for i in mounds.size():
			for j in range(i + 1, mounds.size()):
				apart = apart and mounds[i][1].distance_to(mounds[j][1]) >= float(cfg.kurgan_gap)
	check(whole, "a kurgan feature is one or two mounds, each held by its blockers")
	check(apart, "and the mounds stand far enough apart to march between")
	var s := _sarmatia_sim(b, 2114)
	var pieces: Array = [["kurgan", Vector2(0, 300), 0.0]]
	for off in cfg.kurgan_blockers:
		pieces.append(["", Vector2(0, 300) + Vector2(float(off[0]), float(off[1])), float(cfg.kurgan_radius)])
	s.terrain.add_clearing(Vector2(0, 300), 1.0, pieces)
	s.terrain.refresh(s.commander.pos)
	check(s.terrain.push_out(Vector2(0, 282), Sim.UNIT_RADIUS) != Vector2(0, 282), "a man is pushed out of the mound")


func test_a_wagon_circle_is_a_ring_of_solid_wagons_with_two_openings(b: Dictionary) -> void:
	var cfg: Dictionary = b.steppes.sarmatia
	var t := _steppe_terrain(b, 2115)
	var roll := float(cfg.grass_chance) + float(cfg.kurgan_chance) + 0.01
	var good := true
	var openings := true
	for k in 20:
		var r := RandomNumberGenerator.new()
		r.seed = 980 + k
		var centre := Vector2(900, 900)
		var ring: Array = t._steppe_feature(r, roll, centre)
		var wagons := ring.filter(func(pr: Array) -> bool: return pr[0] == "wagon")
		good = good and wagons.size() == int(cfg.circle_count) - 2 and ring.size() - wagons.size() == wagons.size() * cfg.wagon_blockers.size()
		var angles: Array = wagons.map(func(pr: Array) -> float: return (pr[1] - centre).angle())
		angles.sort()
		var wide := 0
		for i in angles.size():
			var gap: float = fposmod(float(angles[(i + 1) % angles.size()]) - float(angles[i]), TAU)
			if gap > TAU / float(cfg.circle_count) * 1.5:
				wide += 1
		openings = openings and wide == 2
	check(good, "a wagon circle is a ring of wagons, each held by its blockers")
	check(openings, "with two openings to march through")


func test_sarmatian_warriors_charge_shoot_lasso_and_hunt(_b: Dictionary) -> void:
	var e: Dictionary = content.enemies
	check(e.sarmatian_lancer.behaviour == "charger" and e.sarmatian_lancer.has("lance") and float(e.sarmatian_lancer.armour.arrows) > 0.0, "the lancer charges with his lance, and arrows glance off his armour")
	check(e.steppe_archer.has("volley") and float(e.steppe_archer.range) > float(e.gaul_archer.range), "the steppe archer looses volleys from far off")
	check(e.lasso_rider.has("lasso") and e.lasso_rider.get("mounted", false), "the lasso rider rides with a lasso")
	check(e.steppe_wolf.behaviour == "beast" and is_equal_approx(float(e.steppe_wolf.share), 0.5) and float(e.steppe_wolf.arrives) >= 120.0, "the wolf is a beast that comes after a couple of minutes, half as often")
	check(int(e.steppe_wolf.most) <= 4, "and hunts in small packs")


func _lasso_setup(b: Dictionary, seed_value: int, type := "legionary") -> Array:
	var s := _sarmatia_sim(b, seed_value)
	if type != "legionary":
		s.soldiers.clear()
		for k in 8:
			s.add_soldier(type)
		s.legion.place_all(s.facing_angle)
		s._rebuild_grids()
	var h := s.horde
	var u: Dictionary = s.soldiers[0]
	var out: Vector2 = (u.pos - s.commander.pos).normalized()
	var i := h.spawn("lasso_rider", u.pos + out * 50.0)
	h.e_cd[i] = 0.0
	h.rebuild_grid()
	for so in s.soldiers:
		if so.pos.distance_to(h.e_pos[i]) < u.pos.distance_to(h.e_pos[i]):
			u = so
	return [s, h, u, i]


func test_a_lasso_drags_a_soldier_out_of_the_ranks_after_a_wind_up(b: Dictionary) -> void:
	var cfg: Dictionary = content.enemies.lasso_rider.lasso
	var set_up := _lasso_setup(b, 2120)
	var s: Sim = set_up[0]
	var h: Horde = set_up[1]
	var u: Dictionary = set_up[2]
	var i: int = set_up[3]
	h._move(1.0 / 60.0, s)
	check(h.lassos.size() == 1 and is_same(h.lassos[0].unit, u), "a rider near the legion swings his lasso at the nearest soldier")
	var from: Vector2 = u.pos
	var hp: float = u.hp
	var t := 0.0
	while t < float(cfg.windup) - 0.1:
		h._lassos(1.0 / 60.0, s)
		t += 1.0 / 60.0
	check(u.pos == from and u.hp == hp, "nothing happens while he winds up")
	for k in 12:
		h._lassos(1.0 / 60.0, s)
	var rider := h.e_pos[i]
	var want := minf(float(cfg.pull), from.distance_to(rider) - float(content.enemies.lasso_rider.radius) - Sim.UNIT_RADIUS)
	check(want > 15.0 and u.pos.distance_to(rider) <= from.distance_to(rider) - want + 0.5, "then the soldier is dragged out of the ranks towards him (%.0f px)" % (from.distance_to(rider) - u.pos.distance_to(rider)))
	check(u.hp < hp and h.lassos.is_empty(), "and hurt")
	var far := _sarmatia_sim(b, 2121)
	var j := far.horde.spawn("lasso_rider", Vector2(far.legion_reach + float(cfg.reach) + 80.0, 0))
	far.horde.e_cd[j] = 0.0
	far.horde.rebuild_grid()
	far.horde._move(1.0 / 60.0, far)
	check(far.horde.lassos.is_empty(), "a rider far from the legion does not throw")


func test_the_testudo_holds_a_lassoed_soldier_in_place(b: Dictionary) -> void:
	var set_up := _lasso_setup(b, 2122)
	var s: Sim = set_up[0]
	var h: Horde = set_up[1]
	var u: Dictionary = set_up[2]
	h._move(1.0 / 60.0, s)
	var from: Vector2 = u.pos
	s.testudo_left = 1e9
	for k in 90:
		h._lassos(1.0 / 60.0, s)
	check(h.lassos.is_empty() and u.pos == from, "the testudo holds the soldier, and the lasso falls away")
	set_up = _lasso_setup(b, 2122, "archer")
	s = set_up[0]
	h = set_up[1]
	u = set_up[2]
	h._move(1.0 / 60.0, s)
	from = u.pos
	var hp: float = u.hp
	s.testudo_left = 1e9
	for k in 90:
		h._lassos(1.0 / 60.0, s)
	check(u.pos.distance_to(from) > 10.0 and u.hp < hp, "but an archer has no shield to hold him, and is dragged out and hurt (%.0f px)" % u.pos.distance_to(from))


func test_the_draco_bearer_hastens_the_riders_round_him(b: Dictionary) -> void:
	var s := _sarmatia_sim(b, 2123)
	var h := s.horde
	var i := h.spawn("draco_rider", Vector2(300, 0), true)
	var rider := h.spawn("lasso_rider", Vector2(340, 0))
	var lancer := h.spawn("sarmatian_lancer", Vector2(300, 40))
	var archer := h.spawn("steppe_archer", Vector2(260, 0))
	h.rebuild_grid()
	h._howl(i, s)
	check(h.e_haste[rider] > 0.0 and h.e_haste[lancer] > 0.0, "his standard hastens the riders round him")
	check(h.e_haste[archer] <= 0.0, "but not the men on foot")
	check(content.enemies.draco_rider.keys().filter(func(k: String) -> bool: return k == "howl" or h.ABILITY_TIMERS.has(k)).size() == 1, "it is his one ability")


func test_the_war_wagon_rolls_through_the_crowd_and_its_archers_shoot(b: Dictionary) -> void:
	var s := _sarmatia_sim(b, 2124)
	var h := s.horde
	var i := h.spawn("war_wagon", Vector2(400, 0), true)
	var id := h.e_id[i]
	var st: Dictionary = h.boss_state(i)
	st.tower_cd = 1e9
	for k in 48:
		var j := h.spawn("steppe_archer", Vector2(360 - (k / 6) * 11, -28 + (k % 6) * 11))
		h.e_stun[j] = 1e9
	var start := h.e_pos[i]
	var t := 2.0
	for k in int(t * 60):
		h.rebuild_grid()
		h._move(1.0 / 60.0, s)
	var gone := start.x - h.e_pos[h.e_id.find(id)].x
	var free := float(content.enemies.war_wagon.speed) * float(b.get("enemy_speed_mult", 1.0)) * t
	check(gone >= free * 0.85, "the wagon rolls on through the warriors in its way (%.0f of %.0f px)" % [gone, free])
	check(float(content.enemies.war_wagon.armour.arrows) > 0.0 and content.enemies.war_wagon.speed < content.enemies.sarmatian_lancer.speed, "and it is slow and armoured")
	var shots := h.sp_pos.size()
	st.tower_cd = 0.0
	h.e_pos[h.e_id.find(id)] = Vector2(s.legion_reach + 100.0, 0)
	h._bosses(1.0 / 60.0, s)
	check(h.sp_pos.size() > shots, "its archers shoot")
	check(b.objectives.camp.leader.sarmatia == "war_wagon", "and it leads the barbarian camp")


func _king_wave(b: Dictionary, seed_value: int, shield: bool) -> Array:
	var s := _sarmatia_sim(b, seed_value)
	var h := s.horde
	h.spawn_chieftain(Vector2(300, 0))
	h.cleave_cd = 1e9
	h.lancers_cd = 0.0
	h._chieftain(1.0 / 60.0, s)
	if shield:
		s.testudo_left = 1e9
	return [s, h]


func test_the_roxolani_king_sends_lancers_down_a_marked_lane(b: Dictionary) -> void:
	var cfg: Dictionary = content.enemies.rasparaganus.attacks.lancers
	var lost := {}
	for shield in [false, true]:
		var set_up := _king_wave(b, 2130, shield)
		var s: Sim = set_up[0]
		var h: Horde = set_up[1]
		var hp0: float = s.commander.hp
		var men0 := _men_hp(s)
		if not shield:
			check(not h.wave.is_empty() and s.objectives.notice.get("kind", "") == "lancers", "he marks a lane and a notice warns of the lancers")
			var riders: Array = h.wave.riders.filter(func(w: Array) -> bool: return h.e_id.has(w[0]) and h.kind_ids[h.e_kind[h.e_id.find(w[0])]] == "sarmatian_lancer")
			check(riders.size() == int(cfg.riders), "%d lancers line up at its end" % int(cfg.riders))
			var off: Vector2 = s.commander.pos - h.wave.from
			var king: Vector2 = h.e_pos[h.chieftain_index()]
			check(absf(off.dot(h.wave.dir.orthogonal())) < 1.0 and absf(h.wave.dir.dot((s.commander.pos - king).normalized())) < 0.1, "the lane runs across the legion, not from the king")
		var t := 0.0
		while t < float(cfg.warn) - 0.1:
			h._chieftain(1.0 / 60.0, s)
			t += 1.0 / 60.0
		if not shield:
			check(s.commander.hp == hp0 and _men_hp(s) == men0, "nothing strikes while the lane is marked")
		for k in 6 * 60:
			if h.wave.is_empty():
				break
			h._chieftain(1.0 / 60.0, s)
		lost[shield] = [hp0 - s.commander.hp, men0 - _men_hp(s)]
		check(h.wave.is_empty(), "the sweep ends")
	check(is_equal_approx(lost[false][0], float(cfg.damage)) and lost[false][1] > 0.0, "the lancers strike the commander and the soldiers in the lane (%.1f, %.1f)" % lost[false])
	check(is_equal_approx(lost[true][0], float(cfg.damage) * 0.5), "the testudo halves their blow (%.1f)" % lost[true][0])
	var archers := {}
	for shield in [false, true]:
		var set_up := _king_wave(b, 2130, shield)
		var s: Sim = set_up[0]
		var h: Horde = set_up[1]
		for so in s.soldiers:
			so.shield = false
		var men0 := _men_hp(s)
		for k in 12 * 60:
			if h.wave.is_empty():
				break
			h._chieftain(1.0 / 60.0, s)
		archers[shield] = men0 - _men_hp(s)
	check(archers[false] > 0.0 and is_equal_approx(archers[true], archers[false]), "but men without shields take the whole blow (%.1f, %.1f)" % [archers[false], archers[true]])


func test_a_wall_stops_the_kings_lancers(b: Dictionary) -> void:
	var set_up := _king_wave(b, 2131, false)
	var s: Sim = set_up[0]
	var h: Horde = set_up[1]
	var dir: Vector2 = h.wave.dir
	var at: Vector2 = s.commander.pos - dir * (s.legion_reach + 40.0)
	var cfg: Dictionary = b.wall
	for k in 21:
		s.terrain.add_post(at + dir.orthogonal() * (-110.0 + k * float(cfg.gap)), float(cfg.radius), 1e9, "wall")
	s.terrain.refresh(s.commander.pos)
	var hp0: float = s.commander.hp
	var through := false
	for k in 6 * 60:
		if h.wave.is_empty():
			break
		h._chieftain(1.0 / 60.0, s)
		for w in h.wave.get("riders", []):
			var j := h.e_id.find(w[0])
			if j >= 0:
				through = through or (h.e_pos[j] - at).dot(dir) > 4.0
	check(not through and s.commander.hp == hp0, "a wall across the lane stops the lancers where they meet it")


func test_the_roxolani_king_sets_the_steppe_on_fire(b: Dictionary) -> void:
	var cfg: Dictionary = content.enemies.rasparaganus.attacks.steppe_fire
	for stay in [true, false]:
		var s := _sarmatia_sim(b, 2132)
		var h := s.horde
		h.spawn_chieftain(Vector2(300, 0))
		h.cleave_cd = 1e9
		h.fire_cd = 0.0
		h._chieftain(1.0 / 60.0, s)
		var hp0: float = s.commander.hp
		if stay:
			check(not h.steppe_fire.is_empty() and s.objectives.notice.get("kind", "") == "steppe_fire", "he sets the grass alight and a notice warns of it")
			check(h.in_fire_band(s.commander.pos), "the marked ground takes in the legion")
			var behind: Vector2 = s.commander.pos - h.steppe_fire.dir * (float(cfg.back) - 10.0)
			check(h.in_fire_band(behind) and not h.in_fire_band(s.commander.pos - h.steppe_fire.dir * (float(cfg.back) + 30.0)), "and starts on one side of it")
		else:
			s.commander.pos += h.steppe_fire.dir.orthogonal() * (float(cfg.length) / 2.0 + 60.0)
		var t := 0.0
		while t < float(cfg.warn) - 0.1:
			h._fire_on(1.0 / 60.0, s)
			t += 1.0 / 60.0
		if stay:
			check(s.commander.hp == hp0, "nothing burns while the ground is marked")
		var burnt_at := -1.0
		for k in int((float(cfg.seconds) + float(cfg.burn) + 1.0) * 60):
			h._fire_on(1.0 / 60.0, s)
			t += 1.0 / 60.0
			if burnt_at < 0.0 and s.commander.hp < hp0:
				burnt_at = t
		if stay:
			check(burnt_at > float(cfg.warn) + 0.5, "the fire takes a while to spread to a commander in the middle (%.1f s)" % burnt_at)
			check(s.commander.hp < hp0, "then burns him if he stays")
		else:
			check(s.commander.hp == hp0, "a commander who left the marked ground is not burnt")
		check(h.steppe_fire.is_empty(), "and the fire burns out")


func test_the_roxolani_kings_stun_or_death_calls_off_what_he_marked(b: Dictionary) -> void:
	for fate in ["stun", "death"]:
		var s := _sarmatia_sim(b, 2133)
		var h := s.horde
		h.spawn_chieftain(Vector2(300, 0))
		h.cleave_cd = 1e9
		h.fire_cd = 0.0
		h.lancers_cd = 0.0
		h._chieftain(1.0 / 60.0, s)
		var ci := h.chieftain_index()
		if fate == "stun":
			h.e_stun[ci] = 3.0
			h._chieftain(1.0 / 60.0, s)
		else:
			s.hit(ci, 1e9)
			s._remove_dead()
			h._fire_on(1.0 / 60.0, s)
		check(h.steppe_fire.is_empty() and h.wave.is_empty(), "a %s calls off the fire and the lancers he marked" % fate)


func test_the_game_view_widens_or_deepens_to_fill_the_window_as_godots_expand_does(_b: Dictionary) -> void:
	for c in [[Vector2i(1280, 720), Vector2i(640, 360)], [Vector2i(2400, 1350), Vector2i(640, 360)], [Vector2i(1920, 1200), Vector2i(640, 400)],
			[Vector2i(2560, 1080), Vector2i(853, 360)], [Vector2i(1500, 844), Vector2i(640, 360)], [Vector2i(800, 600), Vector2i(640, 480)]]:
		check(Display.base_size(c[0]) == c[1], "a %s window shows a %s view, not %s" % [c[0], c[1], Display.base_size(c[0])])


func test_a_fractional_window_scale_is_drawn_from_the_next_whole_scale(_b: Dictionary) -> void:
	check(Display.prescale(Vector2(3.75, 3.75)) == Vector2(4, 4), "3.75 times is smoothed down from 4 times")
	check(Display.prescale(Vector2(2.34, 2.3444)) == Vector2(3, 3), "2.34 times is smoothed down from 3 times")
	check(Display.prescale(Vector2(3.0016, 3.0)) == Vector2(3, 3), "a scale a hair off 3 counts as 3")
	check(Display.prescale(Vector2(0.5, 0.5)) == Vector2(1, 1), "a window smaller than the view still draws from whole pixels")
	check(Display.is_whole(Vector2(3, 3)) and Display.is_whole(Vector2(4.0, 4.0)), "3 and 4 times are whole")
	check(not Display.is_whole(Vector2(3.75, 3.75)) and not Display.is_whole(Vector2(4, 3.5)), "3.75 times is not whole")


func _death_of(s: Sim) -> Dictionary:
	for e in s.effects:
		if e.kind == "death":
			return e
	return {}


func test_a_kill_leaves_a_stain_where_he_fell_for_a_while(b: Dictionary) -> void:
	var cfg: Dictionary = b.deaths
	var s := Sim.new(b, content, {"seed": 1})
	s.terrain.clear()
	s.time = 30.0
	s.horde.spawn("barbarian_club", Vector2(120.4, -40.6))
	s.hit(0, 999.0)
	s._remove_dead()
	check(s.stains_alive() == 1, "one stain on the ground (%d)" % s.stains_alive())
	check(s.stain_pos[0] == Vector2(120, -41), "it lies where he fell, on a whole pixel (%s)" % s.stain_pos[0])
	check(is_equal_approx(s.stain_born[0], 30.0), "it is laid at the moment of the kill")
	var life := s.stain_life[0]
	check(life >= float(cfg.stain_seconds[0]) and life <= float(cfg.stain_seconds[1]), "it lasts between %s and %s seconds (%s)" % [cfg.stain_seconds[0], cfg.stain_seconds[1], life])
	s.time += life + 0.01
	check(s.stains_alive() == 0, "and is gone after its time")


func test_the_stains_are_capped_and_the_oldest_goes_first(b: Dictionary) -> void:
	var cap := int(b.deaths.stain_cap)
	var s := Sim.new(b, content, {"seed": 2})
	s.terrain.clear()
	for k in cap + 5:
		s.horde.spawn("barbarian_club", Vector2(200 + k * 3, 300))
		s.hit(0, 999.0)
		s._remove_dead()
	check(s.stains_alive() == cap, "at most %d stains (%d)" % [cap, s.stains_alive()])
	check(not s.stain_pos.has(Vector2(200, 300)) and not s.stain_pos.has(Vector2(212, 300)), "the five oldest are gone")
	check(s.stain_pos.has(Vector2(215, 300)) and s.stain_pos.has(Vector2(200 + (cap + 4) * 3, 300)), "the newer ones stay")


func test_with_blood_off_a_kill_leaves_no_stain_or_spray(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 3})
	s.terrain.clear()
	s.blood = false
	s.horde.spawn("barbarian_club", Vector2(150, 0))
	s.hit(0, 999.0)
	s._remove_dead()
	var e := _death_of(s)
	check(s.stains_alive() == 0, "no stain")
	check(not e.is_empty() and e.blood == false, "the death is drawn with no blood")
	check(ProfileScript.SETTING_DEFAULTS.blood == true, "blood is on by default")


func test_a_boss_falls_harder_than_an_ordinary_barbarian(b: Dictionary) -> void:
	var cfg: Dictionary = b.deaths
	var s := Sim.new(b, content, {"seed": 4})
	s.terrain.clear()
	s.horde.spawn("barbarian_club", Vector2(150, 0))
	s.hit(0, 999.0)
	s._remove_dead()
	var plain := _death_of(s)
	var plain_size := s.stain_size[0]
	check(s.shake == 0.0, "an ordinary kill does not shake the screen")
	s.effects.clear()
	s.horde.spawn("berserker", Vector2(150, 60), true)
	s.hit(0, 1e9)
	s._remove_dead()
	var big := _death_of(s)
	check(big.big and int(big.spray) > int(plain.spray), "an elite sprays more blood (%s against %s)" % [big.spray, plain.spray])
	check(s.stain_size[1] > plain_size, "and leaves a bigger stain")
	check(is_equal_approx(s.shake, float(b.shake.elite_death)), "and shakes the screen (%s)" % s.shake)
	s.effects.clear()
	s.shake = 0.0
	var ci := s.horde.spawn_chieftain(Vector2(150, -60))
	s.hit(ci, 1e12)
	s._remove_dead()
	var chief := _death_of(s)
	check(chief.chief and int(chief.spray) >= int(big.spray), "the chieftain sprays the most")
	check(is_equal_approx(s.shake, float(b.chief_death.shake)), "and shakes the screen hardest (%s)" % s.shake)
	check(float(cfg.big_seconds) > float(cfg.seconds), "a boss takes longer to fall")


func test_a_dead_barbarian_is_knocked_away_from_the_blow_that_killed_him(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 5})
	s.terrain.clear()
	s.horde.spawn("barbarian_club", Vector2(150, 150))
	s.hit(0, 999.0, 0.0, "", Vector2(150, 100))
	s._remove_dead()
	var e := _death_of(s)
	check(e.dir.distance_to(Vector2(0, 1)) < 0.01, "a blow from above knocks him down the screen (%s)" % e.dir)
	s.effects.clear()
	s.horde.spawn("barbarian_club", Vector2(-120, 0))
	s.hit(0, 999.0)
	s._remove_dead()
	e = _death_of(s)
	check(e.dir.distance_to(Vector2(-1, 0)) < 0.01, "with no blow to follow he falls away from the commander (%s)" % e.dir)
	s.effects.clear()
	s.horde.spawn("barbarian_club", Vector2(100, 0))
	s.horde.rebuild_grid()
	s._explode(Vector2(100, -30), 60.0, 999.0, "")
	s._remove_dead()
	e = _death_of(s)
	check(e.dir.distance_to(Vector2(0, 1)) < 0.01, "a blast throws him away from where it burst (%s)" % e.dir)


func test_a_death_is_drawn_for_its_set_time(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 6})
	s.terrain.clear()
	s.horde.spawn("barbarian_club", Vector2(150, 0))
	s.hit(0, 999.0)
	s._remove_dead()
	s._effects(float(b.deaths.seconds) - 0.02)
	check(not _death_of(s).is_empty(), "the body is still falling just before its time")
	s._effects(0.04)
	check(_death_of(s).is_empty(), "and gone after it")


func test_fallen_romans_and_the_triumph_leave_no_stains(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 7})
	s.terrain.clear()
	s.soldiers[0].hp = 0.0
	s.legion.remove_fallen(s)
	check(s.stains_alive() == 0, "a fallen soldier leaves no stain")
	s.horde.spawn("barbarian_club", Vector2(40, 0))
	s.win(s.commander.pos)
	for f in 30:
		s.update(1.0 / 30.0, Vector2.ZERO, false)
	check(s.horde.e_pos.is_empty(), "the triumph's wave killed him")
	check(s.stains_alive() == 0 and s.shake == 0.0, "the triumph kills with no stains or shake")


func test_no_stain_is_laid_over_a_gorge(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 8})
	s.terrain.clear()
	_gorge(s, -400.0, 400.0, 100.0, 20.0)
	s.horde.spawn("barbarian_club", Vector2(50, 100.0 - 20.0 - 2.0))
	s.hit(0, 999.0)
	s._remove_dead()
	check(s.stains_alive() == 0, "a barbarian killed on the lip leaves no stain hanging over the drop")
	s.horde.spawn("barbarian_club", Vector2(50, 100.0 - 20.0 - 40.0))
	s.hit(0, 999.0)
	s._remove_dead()
	check(s.stains_alive() == 1, "one killed well back from it does")


func test_the_blood_setting_is_shared_and_checked(_b: Dictionary) -> void:
	_cleanup_profile_files()
	var p := _fresh_profile()
	p.slot = 0
	p.settings.blood = false
	p.save_settings()
	p.new_game()
	p.save()
	p.new_game()
	p.load_slot(1)
	check(p.setting("blood") == false, "loading another slot keeps blood off")
	var other := _fresh_profile()
	other.load_settings()
	check(other.setting("blood") == false, "the settings file holds it")
	other.free()
	p.free()
	_cleanup_profile_files()
	var cfg: Dictionary = ProfileScript.settings_of(ProfileScript.merge_settings({"blood": "no"}))
	check(cfg.blood == true, "a blood setting that is not on or off gives the default")
	check(SettingsScreen.TOGGLES.any(func(t): return t[0] == "blood"), "the settings screen has a blood switch")


func _slay_chieftain(s: Sim, at := Vector2(80, 0)) -> void:
	var ci := s.horde.spawn_chieftain(at)
	s.hit(ci, 1e12, 0.0, "", s.commander.pos)
	s._remove_dead()


func test_the_chieftains_fall_slows_the_battle_for_a_moment(b: Dictionary) -> void:
	var cfg: Dictionary = b.chief_death
	var s := Sim.new(b, content, {"seed": 11})
	s.terrain.clear()
	check(is_equal_approx(s.slowed(0.1), 0.1), "the battle runs at full speed at first")
	s.horde.spawn("berserker", Vector2(60, 0), true)
	s.hit(0, 1e12)
	s._remove_dead()
	check(s.slow_left == 0.0, "an elite's death does not slow it")
	_slay_chieftain(s)
	check(is_equal_approx(s.slow_left, float(cfg.slow_seconds)), "the chieftain's does, for %s real seconds (%s)" % [cfg.slow_seconds, s.slow_left])
	check(is_equal_approx(s.slowed(0.1), 0.1 * float(cfg.slow_rate)), "the battle runs at %s of its speed" % cfg.slow_rate)
	check(s.flash() > 0.5, "the field flashes white (%s)" % s.flash())
	check(is_equal_approx(s.shake, float(cfg.shake)) and s.shake_pixels == int(cfg.shake_pixels), "and the screen shakes hard")
	var real := 0.1
	while real < float(cfg.slow_seconds) + 0.05:
		s.slowed(1.0 / 60.0)
		real += 1.0 / 60.0
	check(s.slow_left == 0.0 and is_equal_approx(s.slowed(0.1), 0.1), "then it runs at full speed again")
	check(s.flash() == 0.0, "and the flash is gone")


func test_the_chieftains_fall_breaks_the_warriors_round_him(b: Dictionary) -> void:
	var cfg: Dictionary = b.chief_death
	var s := Sim.new(b, content, {"seed": 12})
	s.terrain.clear()
	var r := float(cfg.rout_radius)
	var near_id := s.horde.e_id[s.horde.spawn("barbarian_club", Vector2(80 + r * 0.6, 0))]
	var far_id := s.horde.e_id[s.horde.spawn("barbarian_club", Vector2(80 + r * 1.4, 0))]
	var elite_id := s.horde.e_id[s.horde.spawn("berserker", Vector2(80, r * 0.5), true)]
	_slay_chieftain(s)
	var near := s.horde.e_id.find(near_id)
	var far := s.horde.e_id.find(far_id)
	var elite := s.horde.e_id.find(elite_id)
	check(is_equal_approx(s.horde.e_flee[near], float(cfg.rout_seconds)), "a warrior near him flees for %s seconds (%s)" % [cfg.rout_seconds, s.horde.e_flee[near]])
	check(s.horde.e_flee[far] == 0.0, "one far off fights on")
	check(s.horde.e_flee[elite] == 0.0, "an elite does not run")
	var from := s.horde.e_pos[near].distance_to(s.commander.pos)
	for f in 20:
		s.update(1.0 / 30.0, Vector2.ZERO, false)
	near = s.horde.e_id.find(near_id)
	check(near >= 0 and s.horde.e_pos[near].distance_to(s.commander.pos) > from, "the fleeing warrior runs from the legion")


func test_the_chieftains_fall_is_announced_by_name(b: Dictionary) -> void:
	var cfg: Dictionary = b.chief_death
	var s := Sim.new(b, content, {"seed": 13})
	s.terrain.clear()
	s.time = 700.0
	_slay_chieftain(s)
	var name := Hud.chief_name(s)
	check(Hud.chief_banner_line(s).contains(name), "the banner names him (%s)" % Hud.chief_banner_line(s))
	check(Hud.chief_banner_shown(s), "it shows at once")
	check(s.objectives.notice.kind == "chieftain" and is_equal_approx(float(s.objectives.notice.at), 700.0 + float(cfg.banner_seconds)), "the fort's notice waits for the banner to end")
	check(s.events.any(func(e: Dictionary) -> bool: return e.kind == "chief_fall") and s.events.any(func(e: Dictionary) -> bool: return e.kind == "chief_drum"), "a horn and a drum sound")
	check(b.audio.kinds.has("chief_fall") and b.audio.kinds.has("chief_drum"), "and both are audio kinds")
	s.time += float(cfg.banner_seconds) + 0.01
	check(not Hud.chief_banner_shown(s), "the banner is gone after %s seconds" % cfg.banner_seconds)


func test_the_chieftains_fall_spills_his_purse(b: Dictionary) -> void:
	var cfg: Dictionary = b.chief_death
	var s := Sim.new(b, content, {"seed": 14})
	s.terrain.clear()
	_slay_chieftain(s, Vector2(80, 0))
	var total := 0
	var spots := {}
	for k in s.c_pos.size():
		total += s.c_val[k]
		spots[s.c_pos[k].round()] = true
		check(s.c_pos[k].distance_to(Vector2(80, 0)) <= float(cfg.coin_reach[1]) + 0.01, "every coin lies round him (%s)" % s.c_pos[k])
	check(s.c_pos.size() == int(cfg.coin_pieces), "his purse spills as %d coins (%d)" % [cfg.coin_pieces, s.c_pos.size()])
	check(total == roundi(float(cfg.coins) * s.horde.level_mult("denarii_mult")), "worth %d denarii (%d)" % [cfg.coins, total])
	check(spots.size() > int(cfg.coin_pieces) / 2, "scattered, not in one heap")


func test_the_chieftains_fall_leaves_a_big_lasting_stain(b: Dictionary) -> void:
	var cfg: Dictionary = b.chief_death
	var s := Sim.new(b, content, {"seed": 15})
	s.terrain.clear()
	_slay_chieftain(s, Vector2(80, 0))
	var k := s.stain_size.find(float(cfg.stain))
	check(k >= 0 and float(cfg.stain) > float(b.deaths.big_stain), "his stain is the biggest")
	check(k >= 0 and is_equal_approx(s.stain_life[k], float(cfg.stain_seconds)), "and lasts %s seconds" % cfg.stain_seconds)
	var e := _death_of(s)
	check(not e.is_empty() and e.chief and int(e.spray) == int(cfg.spray), "he sprays a great burst of blood")
	for n in int(b.deaths.stain_cap) + 10:
		s.horde.spawn("barbarian_club", Vector2(-300 + n * 3, 300))
		s.hit(0, 999.0)
		s._remove_dead()
	check(s.stain_size.has(float(cfg.stain)), "the kills after his do not write over it")
	s._effects(float(cfg.fall_seconds) - 0.02)
	check(not _death_of(s).is_empty() and _death_of(s).get("chief", false), "he takes %s seconds to fall" % cfg.fall_seconds)
	s._effects(0.04)
	check(not s.effects.any(func(x: Dictionary) -> bool: return x.get("chief", false)), "and is gone after it")


func test_the_chieftains_fall_throws_up_dust_with_blood_off(b: Dictionary) -> void:
	var cfg: Dictionary = b.chief_death
	var s := Sim.new(b, content, {"seed": 16})
	s.terrain.clear()
	s.blood = false
	_slay_chieftain(s)
	var e := _death_of(s)
	check(s.stains_alive() == 0, "no stain")
	check(not e.is_empty() and e.blood == false and int(e.get("dust", 0)) == int(cfg.dust_puffs), "a great cloud of dust instead (%s)" % e.get("dust", 0))


func test_the_legions_livery_follows_its_upgrades(b: Dictionary) -> void:
	var plain := Sim.new(b, content, {"seed": 1})
	check(Livery.tiers(plain) == Vector2i(0, 0), "no upgrades, no new colours")
	var qm := Sim.new(b, content, {"seed": 1, "profile_bonuses": {"soldier_health": 2, "armour": 1, "damage": 4}})
	check(Livery.tiers(qm) == Vector2i(1, 1), "three armour ranks bring bronze and four damage ranks white cloth (%s)" % Livery.tiers(qm))
	qm.ranks["lorica"] = 3
	qm.ranks["shield_wall"] = 2
	qm.ranks["gladius"] = 5
	qm.ranks["discipline"] = 2
	check(Livery.tiers(qm) == Vector2i(2, 2), "drills in the run add to the quartermaster's ranks (%s)" % Livery.tiers(qm))
	var full := Sim.new(b, content, {"seed": 1, "profile_bonuses": {"soldier_health": 4, "armour": 4, "damage": 8, "attack_speed": 4}})
	check(Livery.tiers(full) == Vector2i(2, 2), "a fully upgraded quartermaster shows the last tier in camp")
	var other := Sim.new(b, content, {"seed": 1, "profile_bonuses": {"move_speed": 4, "start_health": 8, "rerolls": 3}})
	check(Livery.tiers(other) == Vector2i(0, 0), "upgrades of other kinds change nothing")


## The pixels of one frame of a unit's standing pose in the atlas.
func _livery_frame(unit: String, dir: String) -> Array:
	var img := Image.load_from_file("res://assets/atlas.png")
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/atlas.json"))
	var f: Array = meta.units[unit].idle[dir].frames[0]
	var px := []
	for y in int(f[3]):
		for x in int(f[2]):
			var c := img.get_pixel(int(f[0]) + x, int(f[1]) + y)
			if c.a8 > 0:
				px.append(c)
	return px


func test_the_livery_recolours_only_armour_and_cloth(b: Dictionary) -> void:
	for unit in ["legionary", "centurion", "cavalry"]:
		var px := _livery_frame(unit, "south")
		var armour := 0
		var cloth := 0
		var kept := true
		var outline_kept := true
		var armour_changed := true
		var cloth_alone := true
		for c: Color in px:
			var tag := c.a8
			var bronze := Livery.recolour(c, 1, 0)
			var purple := Livery.recolour(c, 0, 2)
			if tag == Livery.ARMOUR_ALPHA:
				armour += 1
				armour_changed = armour_changed and not bronze.is_equal_approx(Color(c, 1.0))
				cloth_alone = cloth_alone and purple.is_equal_approx(Color(c, 1.0))
			elif tag == Livery.CLOTH_ALPHA:
				cloth += 1
				cloth_alone = cloth_alone and bronze.is_equal_approx(Color(c, 1.0)) and not purple.is_equal_approx(Color(c, 1.0))
			else:
				kept = kept and bronze == c and purple == c and Livery.recolour(c, 2, 2) == c
			if c.r8 + c.g8 + c.b8 < 30:
				outline_kept = outline_kept and tag == 255
		check(armour > 20 and cloth > 20, "%s has armour and cloth marked (%d, %d)" % [unit, armour, cloth])
		check(armour_changed, "%s: every armour pixel turns bronze" % unit)
		check(cloth_alone, "%s: armour and cloth change only with their own tier" % unit)
		check(kept, "%s: skin, leather and everything else keep their colours" % unit)
		check(outline_kept, "%s: the dark outline is never marked" % unit)


func test_soldiers_with_no_upgrades_keep_their_colours(b: Dictionary) -> void:
	for unit in ["legionary", "archer", "medicus", "ballista"]:
		var same := true
		for c: Color in _livery_frame(unit, "south-east"):
			same = same and Livery.recolour(c, 0, 0).is_equal_approx(Color(c, 1.0))
		check(same, "%s looks as drawn at the first tier" % unit)


func test_only_the_legions_soldiers_carry_livery_marks(b: Dictionary) -> void:
	for unit in ["commander", "barbarian_club", "gaul_swordsman", "cataphract", "egyptian_spearman"]:
		var marked := 0
		for c: Color in _livery_frame(unit, "south"):
			if c.a8 == Livery.ARMOUR_ALPHA or c.a8 == Livery.CLOTH_ALPHA:
				marked += 1
		check(marked == 0, "%s keeps its own colours (%d marked)" % [unit, marked])
	var medicus := 0
	for c: Color in _livery_frame("medicus", "south"):
		if c.a8 == Livery.ARMOUR_ALPHA:
			medicus += 1
	check(medicus == 0, "the medicus's grey hair is not armour")


func test_a_soldiers_mark_comes_off_whole(b: Dictionary) -> void:
	for mod in [Color.WHITE, Color(1.0, 0.55, 0.55), Color(4.0, 4.0, 4.0, 1.0), Color(0.82, 0.74, 0.72, 0.3)]:
		var marked := Livery.mark(mod)
		check(marked.r > Livery.MARK / 2.0, "the mark stands out from any tint (%s)" % mod)
		check(Livery.unmark(marked).is_equal_approx(mod), "and comes off to the tint it was (%s)" % mod)


func test_touch_stick_has_a_dead_zone_and_full_speed_near_the_rim(_b: Dictionary) -> void:
	var r := 50.0
	check(Touch.stick_vector(Vector2.ZERO, r) == Vector2.ZERO, "a thumb resting on the stick's centre marches nowhere")
	check(Touch.stick_vector(Vector2(r * 0.12, 0), r) == Vector2.ZERO, "a small wobble inside the dead zone marches nowhere")
	var slow := Touch.stick_vector(Vector2(0, r * 0.4), r)
	check(slow.length() > 0.0 and slow.length() < 1.0, "past the dead zone the legion marches slowly (%.2f)" % slow.length())
	check(slow.normalized().is_equal_approx(Vector2.DOWN), "and the way the thumb pushes")
	var faster := Touch.stick_vector(Vector2(0, r * 0.6), r)
	check(faster.length() > slow.length(), "further out it marches faster")
	check(is_equal_approx(Touch.stick_vector(Vector2(r * 0.9, 0), r).length(), 1.0), "near the rim it marches at full speed")
	check(is_equal_approx(Touch.stick_vector(Vector2(-r * 3.0, r * 3.0), r).length(), 1.0), "past the rim it never marches faster than full speed")
	check(Touch.stick_vector(Vector2(-r, -r), r).normalized().is_equal_approx(Vector2(-1, -1).normalized()), "a slant marches on the slant")
	check(Touch.stick_vector(Vector2(0, r * 0.4), r).length() > 0.15, "a push past the dead zone is enough to set the legion moving")


func test_touch_stick_follows_a_finger_past_its_rim(_b: Dictionary) -> void:
	var base := Vector2(100, 200)
	check(Touch.stick_follow(base, base + Vector2(30, 0), 50.0) == base, "a finger inside the rim leaves the stick where it is")
	var moved := Touch.stick_follow(base, base + Vector2(0, -80), 50.0)
	check(moved.is_equal_approx(Vector2(100, 170)), "a finger past the rim drags the stick after it (%s)" % moved)
	check(is_equal_approx(moved.distance_to(base + Vector2(0, -80)), 50.0), "keeping the finger on the rim")


func test_touch_stick_takes_touches_on_the_left_of_the_screen(_b: Dictionary) -> void:
	var view := Vector2(808, 360)
	check(Touch.in_stick_zone(Vector2(60, 300), view), "a touch low on the left takes the stick")
	check(Touch.in_stick_zone(Vector2(380, 80), view), "and one anywhere on the left part")
	check(not Touch.in_stick_zone(Vector2(600, 300), view), "a touch on the right is left to the buttons")


## The touch buttons laid out for a screen, as the HUD lays them: below the top bar and above the favour, inside the safe area.
func _touch_layout(view: Vector2, tl: Vector2, br: Vector2, tip: float) -> Dictionary:
	var parts := Hud.bottom_layout(view - tl - br)
	return Touch.button_layout(view, tl, br, tip, tl.y + parts.favour.position.y, tl.y + 14.0)


func test_touch_buttons_are_found_where_they_are_drawn(b: Dictionary) -> void:
	var view := Vector2(808, 360)
	var layout := _touch_layout(view, Vector2(13, 13), Vector2(13, 13), 39.0)
	for id in Touch.ACTIONS:
		check(layout.has(id), "there is a button for %s" % id)
		if not layout.has(id):
			continue
		var c: Vector2 = layout[id].centre
		var r: float = layout[id].radius
		check(Touch.button_at(layout, c) == id, "a touch on the middle of %s lands on it" % id)
		check(Touch.button_at(layout, c + Vector2(r * 0.9, 0).rotated(0.7)) == id, "and one near its edge")
	check(Touch.button_at(layout, Vector2(120, 250)) == "", "a touch on the left lands on no button")
	check(Touch.button_at(layout, view / 2.0) == "", "nor one on the legion")


func test_touch_buttons_fit_the_right_thumb_and_clear_the_corners(b: Dictionary) -> void:
	var before := Ui.scale
	# Phones at 20:9 and 19.5:9 with a camera on either side, a 4:3 and a 16:10 tablet, at both text sizes.
	var cases := [[Vector2(808, 360), Vector2(13, 13), Vector2(13, 13), 39.0], [Vector2(780, 360), Vector2(40, 13), Vector2(13, 13), 39.0],
		[Vector2(808, 360), Vector2(13, 13), Vector2(40, 13), 39.0], [Vector2(640, 480), Vector2(6, 6), Vector2(6, 6), 22.0], [Vector2(640, 400), Vector2(7, 7), Vector2(7, 7), 19.0]]
	for size in [1, 2]:
		Ui.set_text_size(size, b)
		for k in cases:
			var view: Vector2 = k[0]
			var tl: Vector2 = k[1]
			var br: Vector2 = k[2]
			var tip: float = k[3]
			var layout := _touch_layout(view, tl, br, tip)
			var parts := Hud.bottom_layout(view - tl - br)
			var favour := Rect2(parts.favour.position + tl, parts.favour.size)
			var testudo := Rect2(parts.testudo.position + tl, parts.testudo.size)
			var safe := Rect2(tl, view - tl - br)
			var what := "%s at text size %d" % [view, size]
			for id in layout:
				var box := Rect2(layout[id].centre - Vector2.ONE * layout[id].radius, Vector2.ONE * layout[id].radius * 2.0)
				check(safe.encloses(box), "%s: %s stays in the safe area" % [what, id])
				check(not box.intersects(favour) and not box.intersects(testudo), "%s: %s keeps clear of the favour and the testudo corners" % [what, id])
				check(layout[id].radius * 2.0 >= tip - 0.01, "%s: %s is a fingertip across" % [what, id])
				check(layout[id].centre.x > view.x * 0.6, "%s: %s is on the right, for the right thumb" % [what, id])
				for other in layout:
					if other != id:
						var apart: float = layout[id].centre.distance_to(layout[other].centre)
						check(apart >= layout[id].radius + layout[other].radius + 2.0, "%s: %s and %s do not touch" % [what, id, other])
			check(layout.testudo.radius > layout.wall.radius, "%s: the testudo is the biggest button" % what)
			check(layout.testudo.centre.y > layout.wall.centre.y and layout.testudo.centre.y > layout.bridge.centre.y, "%s: the testudo sits lowest, under the thumb" % what)
			check(layout.pause.centre.y < view.y * 0.25, "%s: pause sits at the top" % what)
	Ui.set_text_size(before, b)


func test_touch_back_gesture_steps_back_one_place(_b: Dictionary) -> void:
	check(Touch.back_step("play", false) == "pause", "in a run it pauses")
	check(Touch.back_step("pause", false) == "back", "on the pause screen it goes back to the run")
	check(Touch.back_step("pray", false) == "not_now", "the gods' choice closes for now")
	check(Touch.back_step("choose", false) == "none", "a level-up waits for its choice")
	for st in ["camp", "quartermaster", "tablinum", "map", "commanders", "settings", "saves", "over"]:
		check(Touch.back_step(st, false) == "back", "%s steps back one place" % st)
	check(Touch.back_step("over", true) == "skip", "the victory reveal skips to the summary")
	check(Touch.back_step("title", false) == "background", "on the title it puts the game away")


func test_touch_back_gesture_acts_once_though_android_reports_it_twice(_b: Dictionary) -> void:
	check(Touch.back_counts(5000, -100000), "the first gesture counts")
	check(not Touch.back_counts(5100, 5000), "a second report straight after is the same gesture")
	check(Touch.back_counts(5000 + Touch.BACK_REPEAT_MS + 1, 5000), "a gesture a moment later counts again")


func test_touch_sizes_come_from_the_screens_dpi(_b: Dictionary) -> void:
	var tip := Touch.fingertip_for(420.0, 3.0)
	check(tip > 38.0 and tip < 40.0, "7 mm on a 420 dpi phone drawn 3 times is about 39 game pixels (%.1f)" % tip)
	check(is_equal_approx(Touch.fingertip_for(210.0, 1.5), tip), "the same at half the size and half the dpi")
	check(Touch.fingertip_for(274.0, 4.0) < 20.0, "a tablet needs fewer game pixels")
	check(is_equal_approx(Touch.preview_dpi(Vector2i(1212, 540)), 210.0), "the preview counts a 1212 by 540 window as half of a 2424 by 1080 phone")
	check(is_equal_approx(Touch.preview_dpi(Vector2i(2424, 1080)), 420.0), "and a full-size window as the phone itself")
	check(Touch.preview_dpi(Vector2i(1024, 768)) < 150.0, "a 4:3 window is a tablet held further off")
	check(Touch.large_text(420.0, 3.0), "a phone draws large text")
	check(not Touch.large_text(274.0, 4.0), "a tablet keeps the normal size")
	check(not Touch.large_text(Touch.preview_dpi(Vector2i(1024, 768)), 1.6), "and so does the tablet preview")


func test_touch_insets_clear_rounded_corners_and_the_camera(_b: Dictionary) -> void:
	var whole: Array = Touch.insets_for(Vector2i(2424, 1080), Rect2i(0, 0, 2424, 1080), Vector2(3, 3))
	check(whole[0] == whole[1] and whole[0].x >= 12.0 and whole[0].x <= 14.0, "rounded corners keep everything about 13 game pixels in (%s)" % [whole])
	var cut: Array = Touch.insets_for(Vector2i(2424, 1080), Rect2i(120, 0, 2304, 1080), Vector2(3, 3))
	check(is_equal_approx(cut[0].x, 40.0) and is_equal_approx(cut[1].x, whole[1].x), "a camera on the left moves the left side in past it (%s)" % [cut])


func test_touch_tap_on_a_purchase_or_choice_first_picks_it_out(_b: Dictionary) -> void:
	check(not Touch.tap_acts("quartermaster", "buy:damage", "buy:start_health"), "a tap on another upgrade shows it before buying")
	check(Touch.tap_acts("quartermaster", "buy:damage", "buy:damage"), "a tap on the upgrade shown buys it")
	check(not Touch.tap_acts("commanders", "see:centurion", "pick:tribune"), "a commander for sale is shown before he is bought")
	check(not Touch.tap_acts("choose", "choice:1", "choice:0"), "a level-up choice is shown before it is taken")
	check(Touch.tap_acts("choose", "choice:1", "choice:1"), "and taken by a tap on it once shown")
	check(Touch.tap_acts("title", "settings", "continue"), "an ordinary button acts at once")
	check(Touch.tap_acts("map", "prov:gaul", "prov:germania"), "and so does a province on the map")
	check(Touch.is_tap(3.0, 8.0) and not Touch.is_tap(20.0, 8.0), "a finger that slid away is a drag, not a tap")


func test_touch_phone_hints_and_options_name_no_keys(b: Dictionary) -> void:
	var saved: Dictionary = Profile.settings
	Profile.settings = {"bindings": {}}
	Controls.install({})
	Touch.phone = true
	for kind in ["pick", "buy", "look", "volume", "level", "summary", "title", "gods", "victory", "pray", "bridge", "type"]:
		var said := Controls.hint(kind)
		for key in ["Space", "Escape", "Enter", "W A S D", "W / S"]:
			check(not said.contains(key), "on a phone the %s hint names no key (%s)" % [kind, said])
	for e in TitleScreen.controls():
		check(e.caps.is_empty(), "on a phone how to play shows no key (%s)" % e.label)
	check(not Hud.bridge_hint(9, 8).text.contains(Controls.key_of("bridge") + " "), "the bridge hint names no key on a phone")
	var demo := Game.demo_forced
	Game.demo_forced = true
	var shop := b.duplicate(true)
	shop.demo.store_app_id = 123
	check(not TitleScreen.buttons(shop).any(func(x: Array) -> bool: return x[0] == "wishlist"), "no Steam wishlist on a phone")
	Game.demo_forced = demo
	check(not SettingsScreen.toggles().any(func(t: Array) -> bool: return t[0] == "fullscreen"), "no full screen switch on a phone")
	check(not SettingsScreen.rows().has("music_folder") and not SettingsScreen.rows().has("controls"), "nor the music folder or the key bindings")
	Touch.phone = false
	check(SettingsScreen.toggles().any(func(t: Array) -> bool: return t[0] == "fullscreen"), "a computer keeps its full screen switch")
	check(SettingsScreen.rows().has("music_folder") and SettingsScreen.rows().has("controls"), "and its music folder and key bindings")
	Controls.install({})
	Profile.settings = saved


func test_a_rock_in_a_field_sits_behind_the_row_of_wheat_in_front(b: Dictionary) -> void:
	var view: GDScript = load("res://scripts/world_view.gd")
	var field := Rect2(0, 0, 200, 150)
	check(view.stands_in_wheat("stones", Vector2(100, 60), [field], 0.0), "stones in a field stand among the wheat")
	check(view.stands_in_wheat("rock", Vector2(-10, 60), [field], 0.0), "and so does a rock in the wheat frayed past its edge")
	check(not view.stands_in_wheat("rock", Vector2(-60, 60), [field], 0.0), "but not a rock out on the grass")
	check(not view.stands_in_wheat("oak", Vector2(100, 60), [field], 0.0), "and a tree is never hidden by wheat")
	check(view.stands_in_wheat("rock", Vector2(100, 60).rotated(0.5), [field], 0.5), "a rock in a field turned along a canal stands among its wheat")
	var row := 19.0
	var low := true
	var whole_rows := true
	var top_shows := true
	var some_covered := false
	for foot in range(-40, 80):
		for height in [16.0, 23.0]:
			var c: Vector2 = view.wheat_cover(foot, height)
			var covered := float(foot) - c.x + 1.0
			some_covered = some_covered or covered > 0.0
			top_shows = top_shows and covered <= floorf(height / 2.0)
			# The wheat drawn starts at a row's ears and is that row's, whose stalks stand below the foot.
			var ears := c.x - c.y
			whole_rows = whole_rows and is_equal_approx(posmod(ears, row), 2.0) and ears + row - 3.0 > float(foot) and ears - row + 16.0 <= float(foot)
			low = low and c.y >= 0.0 and (c.y == 0.0 or covered == floorf(height / 2.0))
	check(some_covered, "the row in front covers the lower part of a rock")
	check(top_shows, "but never more than half of it, so its top shows")
	check(whole_rows, "the wheat over it is the row whose stalks stand just in front of its foot")
	check(low, "moved down only as far as keeps the top showing")
	check(view.wheat_cover(37.0, 16.0).x > 37.0, "a rock at the foot of a row stands in front of it, with nothing covering it")
	check(view.wheat_cover(44.0, 16.0) == Vector2(40, 0), "a rock just behind a row's ears has its foot hidden by them where they stand")
