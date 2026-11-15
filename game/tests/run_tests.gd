extends RefCounted
## Checks of the run's rules, run with: godot --headless --path game -- --run-tests

var failures := 0
var passes := 0
const WAITING_FOR_ART := ["slinger", "cavalry", "standard_bearer", "medicus", "ballista", "centurion"]

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
	for m in get_method_list():
		if m.name.begins_with("test_"):
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
	s.horde.spawn("barbarian_club", s.commander.pos + Vector2(10, 0))
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


func test_a_sprinting_clubman_outruns_the_commander(b: Dictionary) -> void:
	var info: Dictionary = content.enemies.barbarian_club
	check(float(info.speed) * float(info.sprint.speed_mult) > float(content.base_commander.speed), "his sprint is faster than the commander")
	check(float(info.speed) < float(content.base_commander.speed), "but his walk is slower")


func test_every_full_choice_holds_a_recruit(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 122})
	var always := true
	for k in 50:
		var picks := Upgrades.offers(s)
		var has := false
		for id in picks:
			has = has or s.content.recruits.has(id)
		always = always and has
	check(always, "fifty sets of choices each held a recruit")


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


func test_the_chieftain_comes_and_his_death_wins(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 13})
	s.time = float(b.chieftain_at) - 0.01
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var ci := s.chieftain_index()
	check(ci >= 0, "the chieftain arrived")
	s.objectives.fort.seen = true
	s.hit(ci, 1e9)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.over and s.victory, "once the fort has been seen, his death ends the run in victory")


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
	for i in 60 * 30:
		s.update(1.0 / 30.0, Vector2(1, 0), false)
	check(s.horde.e_pos.size() > 50, "a crowd after a minute (%d)" % s.horde.e_pos.size())


func test_far_barbarians_come_round_again(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 17})
	s.horde.spawn("barbarian_club", Vector2(2000, 0))
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.horde.e_pos[0].length() <= float(b.spawn_radius) + 5.0, "brought back to the edge")


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
	check(content.province_enemies("parthia").is_empty(), "a province with no art has no enemies")


func test_every_content_entry_has_a_name_and_text(b: Dictionary) -> void:
	for kind in ["recruits", "enemies", "arms", "forged", "drills", "provinces", "commanders", "quartermaster", "achievements"]:
		var entries: Dictionary = content.get(kind)
		check(not entries.is_empty(), "%s is not empty" % kind)
		for id in entries:
			check(str(entries[id].get("name", "")) != "", "%s %s has a name" % [kind, id])
			check(str(entries[id].get("text", "")) != "", "%s %s has a text" % [kind, id])
	check(content.recruits.size() == 8 and content.arms.size() == 12 and content.forged.size() == 6 and content.drills.size() == 15, "the full set from Features.md")
	check(content.provinces.size() == 5 and content.commanders.size() == 6, "five provinces and six commanders")
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
	types.append_array(["centurion", "archer", "archer", "slinger", "ballista", "cavalry", "cavalry", "medicus", "standard_bearer"])
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
	check(went > 30.0, "he rode out (%.0f)" % went)
	check(s.kills >= 1 or s.horde.e_hp[0] < s.horde.e_max[0], "and struck")
	check(cav.pos.distance_to(s.commander.pos + s.slot_of(cav)) < 8.0, "and is back in his place")


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
	var s := _legion_sim(b, 11, [])
	check(content.recruits.slinger.implemented and not content.ready("recruits", "slinger"), "the slinger is implemented but has no art")
	for i in 30:
		check(not Upgrades.offers(s, 10).has("slinger"), "the slinger is never offered")
	check(not Upgrades.available(s).has("slinger"), "and is not available")


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
	var total := _sum(s.c_val)
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


func test_cart_magnet_pulls_every_coin(b: Dictionary) -> void:
	var s := Sim.new(b, Content.with_all_art(), {"seed": 95})
	for k in 6:
		s.c_pos.append(Vector2(400 + k * 30, 200))
		s.c_val.append(1)
		s.c_pull.append(0)
	s.horde.open_cart(s, "magnet")
	var all := true
	for p in s.c_pull:
		all = all and p == 1
	check(all, "every coin is on its way")
	s.horde.open_cart(s, "free_choice")
	check(s.free_choices == 1, "a cart can give a free choice")
	s.soldiers[0].hp = 1.0
	s.horde.open_cart(s, "heal")
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
		s.horde.spawn("barbarian_club", Vector2(350, 150))
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
		close = close and j >= 0 and s.horde.e_pos[j].distance_to(s.horde.e_pos[ci]) < float(b.chieftain_guard.radius) * 1.6
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
	var i: int = s.horde.spawn("chariot", Vector2(200, 0))
	s.horde.e_cd[i] = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.horde.e_dash[i] > 0.0, "the chariot starts a dash")
	var speed: float = float(content.enemies.chariot.speed)
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
	check(Content.ground_path("dacia") == "res://assets/grounds/germania.png", "a province without a file falls back to Germania's ground")


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
	s.objectives.fort.seen = true
	s.hit(ci, 1e9)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(not s.over and s.victory, "his death does not end an endless run but wins it")
	s.commander.hp = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.over and s.victory, "the win stands when the legion falls later")
	var saved: Dictionary = Profile.data
	Profile.data = Profile.defaults()
	Profile.record_run(s)
	check(bool(Profile.record_of(s.province).won), "the win is recorded")
	check(Profile.province_unlocked("britannia"), "and opens the next province")
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
	normal.objectives.fort.seen = true
	normal.hit(normal.chieftain_index(), 1e9)
	normal.update(1.0 / 60.0, Vector2.ZERO, false)
	check(normal.over and normal.victory, "a normal run still ends with the chieftain")


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
	var easy := _mode_sim(b, {"seed": 116})
	var hard := _mode_sim(b, {"seed": 116, "hard": true})
	var e := easy.horde.spawn("barbarian_club", Vector2(300, 0))
	var h := hard.horde.spawn("barbarian_club", Vector2(300, 0))
	check(absf(hard.horde.e_hp[h] / easy.horde.e_hp[e] - float(b.hard.health_mult)) < 0.001, "enemies have more health")
	var paid := [0, 0]
	var runs := [easy, hard]
	for k in 2:
		var s: Sim = runs[k]
		for i in 400:
			s.horde.spawn("barbarian_club", Vector2(300, 0))
			s.horde.e_hp[s.horde.e_hp.size() - 1] = 0.0
		s._remove_dead()
		for v in s.c_val:
			paid[k] += v
	var ratio: float = float(paid[1]) / maxf(1.0, float(paid[0]))
	check(ratio > 1.3 and ratio < 1.7, "denarii pay about %.1f times as much (%.2f)" % [float(b.hard.denarii_mult), ratio])
	easy.b.spawn_per_second_start = 2.0
	hard.b.spawn_per_second_start = 2.0
	for i in 600:
		easy.update(1.0 / 60.0, Vector2.ZERO, false)
		hard.update(1.0 / 60.0, Vector2.ZERO, false)
	check(hard.horde.e_pos.size() > easy.horde.e_pos.size() * 1.2, "and they arrive faster")


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
	check(boosted._bonus_amount("no_such_upgrade") == 0.0, "an unknown upgrade adds nothing")
	check(fresh.speed() > Sim.new(b, Content.with_all_art(), {"seed": 120}).speed(), "a faster march")


const ProfileScript := preload("res://scripts/profile.gd")
const TEST_PROFILE := "user://test_profile.json"


func _fresh_profile() -> Node:
	var p: Node = ProfileScript.new()
	p.disabled = false
	p.path = TEST_PROFILE
	p.data = ProfileScript.defaults()
	return p


func _cleanup_profile_files() -> void:
	for f in [TEST_PROFILE, TEST_PROFILE + ".tmp"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))


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
	check(p.province_unlocked("britannia"), "the next province opens")
	check(not p.commander_unlocked("legate") and not p.commander_unlocked("engineer"), "the others stay locked")
	var faster := Sim.new(b, all, {"seed": 133, "hard": true})
	faster.time = 700.0
	faster.over = true
	faster.victory = true
	p.record_run(faster)
	check(p.record_of("germania").hard_won, "a hard win is its own record")
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
	for id in qm:
		var info: Dictionary = qm[id]
		check(info.costs.size() == int(info.ranks), "%s has a cost for every rank" % id)
		for r in int(info.ranks):
			check(p.next_cost(id, content) == int(info.costs[r]), "%s rank %d costs what the data says" % [id, r + 1])
			var before: int = p.data.denarii
			check(p.buy(id, content), "%s rank %d can be bought" % [id, r + 1])
			check(before - p.data.denarii == int(info.costs[r]), "and costs exactly that")
		check(p.rank(id) == int(info.ranks), "%s reaches its cap" % id)
		check(p.next_cost(id, content) == -1 and not p.buy(id, content), "%s cannot go past its cap" % id)
	check(p.bonuses().size() == qm.size(), "every rank reaches the run's bonuses")
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
	p.load_file()
	check(p.data == ProfileScript.defaults(), "a missing file gives the defaults")
	for junk in ["", "not json at all {{{", "[1, 2, 3]", "\"text\"", "null"]:
		var f := FileAccess.open(TEST_PROFILE, FileAccess.WRITE)
		f.store_string(junk)
		f.close()
		p.load_file()
		check(p.data == ProfileScript.defaults(), "damaged file %s gives the defaults" % junk.left(8))
	var partial := FileAccess.open(TEST_PROFILE, FileAccess.WRITE)
	partial.store_string(JSON.stringify({"denarii": 75, "ranks": {"damage": 2, "armour": "lots"}, "totals": {"kills": "many", "runs": 3},
		"unlocked": {"commanders": ["tribune", "legate", 7]}, "seen": {"wolf": true, "pilum": "yes"}, "old_key": 1}))
	partial.close()
	p.load_file()
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
	check(not FileAccess.file_exists(TEST_PROFILE) and not FileAccess.file_exists(TEST_PROFILE + ".tmp"), "a disabled profile writes nothing")
	p.disabled = false
	p.save()
	check(FileAccess.file_exists(TEST_PROFILE), "an enabled one does write")
	var back := _fresh_profile()
	back.load_file()
	check(back.data.denarii == 99, "and reads back what it wrote")
	back.free()
	p.free()
	_cleanup_profile_files()
	check(Profile.disabled, "the real profile is disabled while the tests run")
	check(Profile.path == "user://profile.json" and Profile.data == ProfileScript.defaults(), "and holds only defaults")


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
	for id in ["britannia", "dacia", "parthia"]:
		_won(b, p, id)
	check(p.commander_unlocked("legate"), "a win in every province unlocks the legate")
	p.free()


func test_every_entry_has_a_history_line(b: Dictionary) -> void:
	for kind in ["recruits", "arms", "forged", "enemies", "commanders", "gods"]:
		for id in content.get(kind):
			var line: String = str(content.get(kind)[id].get("history", ""))
			check(line.length() > 0 and line.length() <= 110, "%s has a history line that fits" % id)


func test_saved_settings_keep_only_text_for_province_and_commander(b: Dictionary) -> void:
	var merged: Dictionary = ProfileScript.merge_saved({"settings": {"province": 5, "commander": "legate", "other": 1}})
	check(not merged.settings.has("province") and merged.settings.commander == "legate", "only string choices are kept")


func test_damage_is_counted_by_source(b: Dictionary) -> void:
	var s := Sim.new(b, content, {"seed": 201})
	var i := s.horde.spawn("barbarian_club", Vector2(300, 0))
	s.hit(i, 6.0, 0.0, "pilum")
	s.scorch(i, 4.0, "fire_pots")
	check(is_equal_approx(float(s.damage_by_source.get("pilum", 0.0)), 6.0), "a hit is counted under its weapon")
	check(is_equal_approx(float(s.damage_by_source.get("fire_pots", 0.0)), 4.0), "burning ground is counted under its pot")
	s.hit(i, 1000.0, 0.0, "pilum")
	check(is_equal_approx(float(s.damage_by_source.pilum), 6.0 + 10.0), "only the health that was left is counted, not the overkill")
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
	for t in ["archer", "slinger", "cavalry", "standard_bearer", "centurion", "ballista", "medicus"]:
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
	var merged: Dictionary = ProfileScript.merge_saved({"settings": {"bindings": {"up": {"keys": [], "pads": []}, "down": {"keys": [0, -3, "x"]}, "left": {"keys": [KEY_J]}}}})
	var cfg: Dictionary = ProfileScript.settings_of(merged)
	check(not cfg.bindings.has("up") and not cfg.bindings.has("down"), "empty or unusable lists are dropped when loaded")
	check(cfg.bindings.left.keys == [KEY_J], "a good list is kept")
	check(Controls.effective({"up": {"keys": [], "pads": []}}, "up").keys == [KEY_W, KEY_UP], "an empty saved list gives the defaults")
	var pad: Dictionary = ProfileScript.settings_of(ProfileScript.merge_saved({"settings": {"bindings": {"testudo": {"pads": [0]}}}}))
	check(pad.bindings.testudo.pads == [0], "pad button 0 is a real button")


func test_saved_settings_are_checked(b: Dictionary) -> void:
	var merged: Dictionary = ProfileScript.merge_saved({"settings": {"master": 4, "music": "loud", "text_size": 7, "shake": "yes", "numbers": false,
		"bindings": {"testudo": {"keys": [KEY_T, "x"], "pads": [2.0]}, "bad": 3}}})
	var cfg: Dictionary = ProfileScript.settings_of(merged)
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
	later.commanders.engineer.unlock = {"type": "win", "province": "dacia"}
	check(not "engineer" in Game.commanders(later, b), "a commander won in a province not drawn yet, such as Dacia, waits for it")
	check(Game.province_allowed("gaul", b), "the full game opens every province")
	check(Game.run_cap(b) == 0.0, "the full game has no cap")
	Game.demo_forced = true
	check(Game.commanders(content, b) == ready.slice(0, 3), "the demo lists the first three drawn commanders")
	check(Game.province_allowed("germania", b) and not Game.province_allowed("gaul", b), "the demo opens Germania only")
	check(Game.run_cap(b) == 900.0, "the demo caps the run at 900 seconds")
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
	Steamworks.card = {}



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


func test_every_string_has_all_languages(_b: Dictionary) -> void:
	var sheet := _sheet()
	check(Array(sheet.header).slice(1) == LANGUAGES, "the sheet has the 14 languages")
	var placeholder := RegEx.create_from_string("%[-0-9.]*[sdifxXcv%]| {2,}")
	var empty := 0
	var changed := 0
	for key in sheet.rows:
		var row: PackedStringArray = sheet.rows[key]
		for i in range(1, row.size()):
			if row[i].strip_edges() == "":
				empty += 1
				print("  empty ", LANGUAGES[i - 1], ": ", key)
			elif placeholder.search_all(row[i]).size() != placeholder.search_all(row[1]).size():
				changed += 1
				print("  placeholders differ ", LANGUAGES[i - 1], ": ", key)
	check(empty == 0, "no cell of the sheet is empty")
	check(changed == 0, "every translation keeps its placeholders")
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
	for line in TitleScreen.how_to_play(sim.b):
		_fit(cuts, loc, scale, "how to play", line, TitleScreen.line_width())
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
	var modes: Array = [tr_.call("Hard"), tr_.call("Endless"), tr_.call("Decimatio")]
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
	for s in ["Full screen", "Screen shake", "Damage numbers"]:
		_fit(cuts, loc, scale, "toggle name", tr_.call(s), 440.0 - 12.0 - maxf(Ui.width_at(tr_.call("On"), Ui.px), Ui.width_at(tr_.call("Off"), Ui.px)) - 6.0)
	_fit(cuts, loc, scale, "text size", tr_.call("Text size"), 440.0 - 12.0 - maxf(Ui.width_at(tr_.call("Large"), Ui.px), Ui.width_at(tr_.call("Normal"), Ui.px)) - 6.0)
	_fit(cuts, loc, scale, "language label", tr_.call("Language"), 440.0 - 12.0 - 120.0)
	_fit(cuts, loc, scale, "controls button", tr_.call("Keys and buttons"), 428.0)
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
	var results: Array = [tr_.call("Best time %s") % "99:59", tr_.call("Not won yet"), tr_.call("Hard not won"), tr_.call("Endless %s") % "99:59"]
	if Ui.pack(results, "  " if big else "     ", map_text).size() > 2:
		cuts.append("%s x%d map results take more than two lines" % [loc, scale])
	for id in c.provinces:
		_lines(cuts, loc, scale, "province text", c.provinces[id].text, map_text, 2)
	for id in c.commanders:
		_lines(cuts, loc, scale, "commander text", c.commanders[id].text, map_text, 2)
		var tag: String = (tr_.call("Locked: %s") % Profile.unlock_text(c.commanders[id], c)).to_upper()
		_fit(cuts, loc, scale, "commander tag", tag, 434.0)
	_fit(cuts, loc, scale, "chosen tag", tr_.call("Chosen").to_upper(), 434.0)
	var mode_w := (map_text - 12.0) / 3.0
	for s in modes:
		_fit(cuts, loc, scale, "mode button", "[x] " + s, mode_w - 12.0)
	_fit(cuts, loc, scale, "map note", tr_.call("Win here to open these"), map_text)
	_fit(cuts, loc, scale, "marching here", tr_.call("Marching here").to_upper(), 300.0)
	# Level-up cards: three or four across.
	for n in [3, 4]:
		var gap := 8.0 if n > 3 else 12.0
		var bw := minf(200.0 if big else 176.0, (616.0 - (n - 1) * gap) / n)
		for id in c.recruits.keys() + c.arms.keys() + c.forged.keys() + c.drills.keys():
			_lines(cuts, loc, scale, "card name (%d across)" % n, str(c.upgrade(id).name).to_upper(), bw - 8.0, 2)
			_fit(cuts, loc, scale, "card level (%d across)" % n, Upgrades.level_text(sim, id), bw - 8.0)
		for g in ["Recruit", "Arms", "Forged", "Drill"]:
			_fit(cuts, loc, scale, "card group (%d across)" % n, tr_.call(g).to_upper(), bw - 8.0)
	# God cards, the favour hint beside its meter and the god's name written across the screen at three times the size.
	var god_w := minf(200.0 if big else 176.0, (616.0 - 2 * 12.0) / 3)
	_fit(cuts, loc, scale, "god heading", tr_.call("The gods hear you").to_upper(), 624.0)
	_fit(cuts, loc, scale, "god group", tr_.call("God").to_upper(), god_w - 8.0)
	_fit(cuts, loc, scale, "favour hint", Controls.hint("pray").to_upper(), 624.0 * 0.45)
	for id in c.gods:
		_lines(cuts, loc, scale, "god name", str(c.gods[id].name).to_upper(), god_w - 8.0, 1)
		_lines(cuts, loc, scale, "god text", str(c.gods[id].text), god_w - 18.0, 6 if big else 5)
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
	var saved: Dictionary = Profile.data
	Profile.data = Profile.defaults()
	Profile.data.settings.bindings = {}
	check(Controls.hint("level") == "A / D  choose     Space  take it", "the default level-up hint is unchanged (%s)" % Controls.hint("level"))
	Controls.rebind(Profile.data.settings.bindings, "left", "keys", 0, KEY_J)
	Controls.rebind(Profile.data.settings.bindings, "confirm", "keys", 0, KEY_E)
	check(Controls.hint("level") == "J / D  choose     E  take it", "the level-up hint shows the rebound keys")
	check(Controls.hint("summary").begins_with("E  Camp"), "the summary hint shows the rebound confirm key")
	check(Controls.hint("pick").begins_with("W J S D  move"), "the move hint shows the rebound march keys")
	Controls.install({})
	Profile.data = saved


func test_hints_are_built_from_single_translated_words(_b: Dictionary) -> void:
	var saved: Dictionary = Profile.data
	Profile.data = Profile.defaults()
	Profile.data.settings.bindings = {}
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
	Profile.data = saved


func test_reroll_and_banish_can_be_rebound(_b: Dictionary) -> void:
	var saved: Dictionary = Profile.data
	Profile.data = Profile.defaults()
	Profile.data.settings.bindings = {}
	var names: Array = Controls.ACTIONS.map(func(a: Array) -> String: return a[0])
	check(names.has("reroll") and names.has("banish"), "the key page lists reroll and banish")
	Controls.rebind(Profile.data.settings.bindings, "reroll", "keys", 0, KEY_T)
	Controls.rebind(Profile.data.settings.bindings, "banish", "pads", 0, JOY_BUTTON_LEFT_SHOULDER)
	var has_t := false
	for e in InputMap.action_get_events("reroll"):
		has_t = has_t or (e is InputEventKey and e.physical_keycode == KEY_T)
	check(has_t, "the rebound reroll key is in the input map")
	check(Controls.hint("reroll", 2) == "T / Y  reroll (2)", "the reroll hint names the new key (%s)" % Controls.hint("reroll", 2))
	check(Controls.hint("banish", 1) == "B / LB  banish (1)", "the banish hint names the new button (%s)" % Controls.hint("banish", 1))
	Controls.install({})
	Profile.data = saved


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


func test_title_goal_comes_from_the_balance(b: Dictionary) -> void:
	check("16" in Game.goal_text(b) and "fort" in Game.goal_text(b), "the full game names 16 minutes and the fort")
	Game.demo_forced = true
	check("15" in Game.goal_text(b) and not "chieftain" in Game.goal_text(b), "the demo names 15 minutes and no chieftain")
	Game.demo_forced = false


class FakeMain:
	extends Node
	var state := "pause"
	var finished := false
	var sim: Sim

	func _finish_run() -> void:
		finished = true


func test_giving_up_asks_twice(b: Dictionary) -> void:
	var m := FakeMain.new()
	m.sim = Sim.new(b, content, {"seed": 5})
	var pause := PauseScreen.new(m)
	pause.activate("giveup")
	check(not m.finished and not m.sim.over, "the first press only asks")
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


func test_burning_the_grove_thins_the_stream(b: Dictionary) -> void:
	var cfg: Dictionary = b.objectives.grove
	var s := _objective_sim(b, 153)
	var grove: Dictionary = s.objectives.add(s, "grove", Vector2(500, 0))
	var oaks := 0
	for pr in s.terrain.extras:
		if pr[0] == "oak" and pr[2] > 0.0 and absf(pr[1].distance_to(grove.pos) - float(cfg.ring)) < 1.0:
			oaks += 1
	var slots := int(TAU * float(cfg.ring) / float(cfg.oak_step))
	check(oaks > slots / 2 and oaks < slots, "solid oaks ring the altar with gaps to enter (%d of %d)" % [oaks, slots])
	s.commander.pos = grove.pos + Vector2(10, 0)
	_step_dt(s, float(cfg.hold) * 0.5)
	check(not grove.done and grove.hold > 0.0, "half the time in the grove is not enough")
	check(s.horde.e_pos.size() > 5, "war bands come to defend it")
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
	var want := (2.0 + float(s.b.spawn_per_second_growth) * s.time) * 0.25 * float(cfg.calm_mult)
	check(is_equal_approx(s.horde.spawn_acc, want), "the horde's stream reads the thinning (%.3f of %.3f)" % [s.horde.spawn_acc, want])


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
	s.commander.pos = fort.centre
	_step_dt(s, float(cfg.hold) + 0.2)
	check(s.over and s.victory, "holding the fort wins the run")
	var e := _mode_sim(b, {"seed": 157, "endless": true})
	e.objectives.list.clear()
	e.time = float(b.chieftain_at) - 0.01
	e.update(1.0 / 60.0, Vector2.ZERO, false)
	e.commander.pos = e.objectives.fort.centre
	_step_dt(e, float(cfg.hold) + 0.2)
	check(not e.over and e.victory and e.endless_since >= 0.0, "in an endless run the fort wins and the march goes on")
	var since := e.endless_since
	e.update(1.0 / 60.0, Vector2.ZERO, false)
	check(e.endless_since == since, "and the win is counted once")
	e.hit(e.chieftain_index(), 1e9)
	e.update(1.0 / 60.0, Vector2.ZERO, false)
	check(e.endless_since == since and not e.over, "the chieftain's death later keeps the endless clock")


func test_the_hud_points_to_objectives_off_screen(b: Dictionary) -> void:
	var view := Vector2(640, 360)
	var top := 40.0
	var at: Vector2 = Hud.edge_point(view, Vector2(2000, 0), top)
	check(at.x < view.x and at.x > view.x - 40.0 and absf(at.y - view.y / 2.0) < 1.0, "a target far east is marked at the right edge (%s)" % at)
	at = Hud.edge_point(view, Vector2(-300, -3000), top)
	check(at.y >= top and at.y < top + 30.0, "a target far north is marked below the top bar (%s)" % at)
	check(Hud.edge_point(view, Vector2(100, 50), top) == Vector2.INF, "a target on screen needs no arrow")


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


func test_the_fort_is_a_walled_square_with_its_gate_towards_the_legion(b: Dictionary) -> void:
	var cfg: Dictionary = b.fort
	var s := _fort_sim(b, 400)
	var fort: Dictionary = s.objectives.fort
	var c: Vector2 = fort.centre
	var half := float(cfg.half)
	check(fort.pos.is_equal_approx(c + Vector2(0, half)), "the gate stands in the middle of the south wall")
	check(c.y < s.commander.pos.y and absf(c.x - s.commander.pos.x) < c.distance_to(s.commander.pos), "the fort stands to the north, so the legion comes on its gate")
	var gate := false
	var stakes := 0
	var on_wall := true
	for pr in s.terrain.extras:
		gate = gate or (pr[0] == "fort_gate" and pr[1] == fort.pos)
		if pr[0] == "stake":
			stakes += 1
			on_wall = on_wall and pr[2] > 0.0 and absf(maxf(absf(pr[1].x - c.x), absf(pr[1].y - c.y)) - half) < 1.0
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
	check(2.0 * (half - float(cfg.stake_radius)) >= 150.0, "inside there is room for a legion of forty")
	check(2.0 * half + 40.0 <= 360.0, "and the whole fort fits on the screen")


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
	_step_dt(s, hold * 0.5 + 0.2)
	check(s.over and s.victory, "holding the fort for %d seconds wins the run" % int(hold))
	var l := _fort_sim(b, 402)
	l.commander.pos = l.objectives.fort.centre
	_step_dt(l, hold * 0.8)
	l.commander.pos = l.objectives.fort.pos + Vector2(0, 200)
	_step_dt(l, hold)
	l.commander.pos = l.objectives.fort.centre
	_step_dt(l, hold * 0.5)
	check(not l.over, "time inside drains away when the commander leaves")


func test_the_run_does_not_end_before_the_fort_is_seen(b: Dictionary) -> void:
	var s := _fort_sim(b, 403)
	var fort: Dictionary = s.objectives.fort
	check(not fort.seen, "the fort starts out of sight")
	s.time = float(b.chieftain_at)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var ci := s.chieftain_index()
	check(ci >= 0, "the chieftain is out")
	s.hit(ci, 1e9)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(not s.over, "killing the chieftain before the fort is in sight does not end the run")
	s.commander.pos = fort.pos + Vector2(0, 60)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(fort.seen, "the fort counts as seen once it is on screen")


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
	_step_dt(s, float(cfg.burn_seconds) - 0.5)
	check(_solid_at(s, huts[0]), "for %d seconds" % int(cfg.burn_seconds))
	_step_dt(s, 1.0)
	var gone := true
	for h in huts:
		gone = gone and not _solid_at(s, h) and _kinds_at(s, h).is_empty() and s.terrain.is_open(h)
	check(gone, "then the huts are gone and the ground is open")
	var e := _objective_sim(b, 411)
	var c2: Dictionary = e.objectives.add(e, "camp", Vector2(600, 0))
	e.soldiers[0].pos = c2.pos
	e._rebuild_grids()
	e.objectives.update(0.01, e)
	check(c2.burnt_at >= 0.0, "taking the eagle sets the camp alight too")


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


func test_the_gods_have_their_own_key(b: Dictionary) -> void:
	Controls.install({})
	check(_has_key("pray", KEY_F) and _has_button("pray", JOY_BUTTON_Y), "F and the north face button call the gods")
	check(Controls.ACTIONS.any(func(a: Array) -> bool: return a[0] == "pray"), "the settings let it be rebound")
	check(Controls.hint("pray") == "F / Y  call the gods", "the hint names the keys (%s)" % Controls.hint("pray"))
	for other in ["testudo", "build", "pause", "up", "down", "left", "right", "quit", "reroll", "banish", "fullscreen"]:
		check(not _has_key(other, KEY_F), "F is not also %s" % other)
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
			var slot: int = k * 16 + d
			for t in [0.0, 0.7, 3.2, 7.9, 8.0, 13.5, 101.25]:
				var f: Array = view.atlas.unit_frame(type, "move", Sim.DIRS[d], t)
				if f[0] != view._f_rect[view._f_start[slot] + posmod(int(t), view._f_count[slot])] or f[1] != view._f_anchor[slot]:
					wrong.append("%s move %s %.2f" % [type, Sim.DIRS[d], t])
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


func test_the_bosses_are_drawn_big(_b: Dictionary) -> void:
	var atlas := Atlas.new()
	for type in ["berserker", "war_band_leader", "war_priest"]:
		var h: int = atlas.units[type].idle.south.frames[0][3]
		check(h >= 64, "%s stands at least 64 px tall (%d)" % [type, h])
	var ch: int = atlas.units.chieftain.idle.south.frames[0][3]
	check(ch >= 96, "the chieftain stands at least 96 px tall (%d)" % ch)


func test_bosses_are_much_tougher(_b: Dictionary) -> void:
	var e: Dictionary = content.enemies
	for id in ["berserker", "war_band_leader", "war_priest"]:
		check(float(e[id].hp) >= 4500.0 and float(e[id].hp) <= 6000.0, "the %s has 4500 to 6000 health (%d)" % [id, int(e[id].hp)])
	check(float(e.chieftain.hp) >= 23000.0 and float(e.chieftain.hp) <= 25000.0, "the chieftain has 23000 to 25000 health (%d)" % int(e.chieftain.hp))
	for id in e:
		if e[id].get("elite", false):
			check(float(e[id].hp) >= 4500.0, "every elite has at least 4500 health (%s %d)" % [id, int(e[id].hp)])
		if e[id].get("chieftain", false):
			check(float(e[id].hp) >= 23000.0, "every chieftain has at least 23000 health (%s %d)" % [id, int(e[id].hp)])


func test_elites_grow_tougher_through_the_run(b: Dictionary) -> void:
	var s := _quiet_sim(b, 700, Content.with_all_art())
	s.horde.time = 1200.0
	var late := s.horde.spawn("berserker", Vector2(-300, 0), true)
	var ratio := s.horde.e_max[late] / float(content.enemies.berserker.hp)
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
	check(is_equal_approx(float(b.spawn_per_second_start), 0.75) and is_equal_approx(float(b.spawn_per_second_growth), 0.015), "the stream is a quarter thinner")
	check(int(b.surge_size_start) == 9 and is_equal_approx(float(b.surge_size_growth), 0.045), "so are the surges")
	check(int(b.war_band.size_start) == 6 and is_equal_approx(float(b.war_band.size_growth), 0.01125), "and the war bands")


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
	check(moved > float(content.enemies.berserker.speed) * 0.1 * 1.2, "and runs faster (%.1f px)" % moved)


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
	var round_him := true
	for k in range(before, s.horde.e_pos.size()):
		round_him = round_him and s.horde.e_pos[k].distance_to(Vector2(250, 0)) <= float(b.war_band.spread) + 1.0
	check(round_him, "round him")
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
	check(is_equal_approx(s.horde.e_power[first], float(cfg.early_mult)) and s.horde.e_power[full] == 1.0, "and hits that much softer")
	var club := s.horde.spawn("barbarian_club", Vector2(0, 300))
	check(s.horde.e_power[club] == 1.0, "an ordinary barbarian is not changed")
	s.horde.e_hp[first] = 1.0
	s.horde._bosses(1.0 / 60.0, s)
	check(is_equal_approx(s.horde.e_power[first], float(cfg.early_mult) * float(content.enemies.berserker.rage.mult)), "his rage builds on it")


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
					for i in pts.size() - 1:
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


## Whether a soldier can walk from the start to every objective and the fort without crossing a ravine or a rock, cutting through trees as the legion can.
func _reaches_everything(s: Sim) -> bool:
	var goals: Array = []
	for o in s.objectives.list:
		goals.append([o.pos, float(s.b.objectives.clearing) * 0.5])
	goals.append([s.objectives.fort.centre, float(s.b.fort.half) * 0.5])
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


func test_the_arrows_are_big_badges_whose_labels_never_overlap(b: Dictionary) -> void:
	var before := Ui.scale
	var view := Vector2(640, 360)
	for scale in [1, 2]:
		Ui.set_text_size(scale, b)
		check(Hud.badge_radius() >= 18.0, "an arrow's badge is big at text size %d" % scale)
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
	check(s.speed() >= free * float(b.press.slowest) - 0.01, "a crowd, a curse and the testudo together keep a fifth of the march (%.1f of %.1f)" % [s.speed(), free])


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
	for flag in ["hard", "endless", "decimatio", "commander=legate", "chieftain-at=60", "as-demo", "objectives-near", "boss=berserker", "boss-act=whirl", "god=vulcan", "god-at=3", "give=pilum:3", "go-to=fort", "hold-choice", "lang=fr", "card=kills_1000", "page=controls"]:
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
func _gaul_sim(b: Dictionary, seed_value: int) -> Sim:
	var s := Sim.new(b, Content.with_all_art(), {"seed": seed_value, "province": "gaul"})
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


func test_winning_germania_opens_gaul_while_britannia_waits_for_art(b: Dictionary) -> void:
	check(content.ready("provinces", "gaul") and not content.ready("provinces", "britannia"), "Gaul is drawn and Britannia is not")
	check(content.province_before("gaul") == "germania", "the drawn province before Gaul is Germania")
	check(content.province_before("germania") == "", "nothing comes before Germania")
	check(Content.with_all_art().province_before("gaul") == "britannia", "once Britannia is drawn it comes between them")
	var p := _fresh_profile()
	var s := Sim.new(b, content, {"seed": 901})
	s.time = 900.0
	s.over = true
	s.victory = true
	p.record_run(s)
	check(p.province_unlocked("gaul"), "winning in Germania opens Gaul")
	_cleanup_profile_files()
	p.free()


func test_gaul_is_farmland_with_villages_hedges_and_wheat(b: Dictionary) -> void:
	var kinds := {}
	var t := Terrain.new(902, b.forest, {})
	t.field = b.fields.gaul
	for pr in t.props_in(Rect2(-3000, -3000, 6000, 6000)):
		kinds[pr[0]] = kinds.get(pr[0], 0) + 1
	check(kinds.has("wheat") and kinds.has("hedge") and kinds.has("village"), "the fields hold wheat, hedges and villages (%s)" % str(kinds.keys()))
	check(not kinds.has("oak") and not kinds.has("fir") and not kinds.has("log"), "and none of Germania's forest")
	var g := Terrain.new(902, b.forest, {})
	var forest := {}
	for pr in g.props_in(Rect2(-3000, -3000, 6000, 6000)):
		forest[pr[0]] = true
	check(forest.has("oak") and not forest.has("wheat") and not forest.has("village"), "Germania keeps its forest")


func test_hedges_and_villages_block_and_wheat_does_not(b: Dictionary) -> void:
	var t := Terrain.new(903, b.forest, {})
	t.field = b.fields.gaul
	var hedge := Vector2.INF
	var village := Vector2.INF
	var wheat_solid := false
	for pr in t.props_in(Rect2(-3000, -3000, 6000, 6000)):
		if pr[0] == "hedge" and hedge == Vector2.INF:
			hedge = pr[1]
		elif pr[0] == "village" and village == Vector2.INF:
			village = pr[1]
		elif pr[0] == "wheat" and pr[2] > 0.0:
			wheat_solid = true
	check(not wheat_solid, "wheat never blocks")
	check(hedge != Vector2.INF and village != Vector2.INF, "a hedge and a village were found")
	t.refresh(hedge)
	var at := hedge + Vector2(3, -6)
	check(t.push_out(at, Sim.UNIT_RADIUS).distance_to(at) > 4.0, "a soldier cannot stand in a hedge")
	t.refresh(village)
	at = village + Vector2(0, -30)
	check(t.push_out(at, Sim.UNIT_RADIUS).distance_to(at) > 4.0, "nor in a village's houses")


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
	st.blast_cd = 0.0
	h._bosses(1.0 / 60.0, s)
	check(h.blast_left > 0.0 and s.attack_rate() < rate, "his blast slows the legion's blows")
	check(soldier.pos.distance_to(h.e_pos[i]) > before, "and pushes the soldiers back")
	check(h.k_beh[h.e_kind[i]] == Horde.LOBBER and h.k_lob[h.e_kind[i]] == 0, "he stands off and throws nothing")
	soldier.pos = h.e_pos[i] + Vector2(-20, 0)
	s._rebuild_grids()
	h._bosses(1.0 / 60.0, s)
	check(h.e_flee[i] > 0.0, "a soldier at his elbow sends him running")
	var gap := h.e_pos[i].length()
	h._move(0.1, s)
	check(h.e_pos[i].length() > gap, "away from the legion")
	check(float(cfg.flee.speed_mult) > 1.0, "faster than he walks")


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
