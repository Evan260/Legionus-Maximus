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
		var t := Terrain.new(1000 + k * 37, b.forest)
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
	s.hit(ci, 1e9)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.over and s.victory, "his death ends the run in victory")


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
	s.horde.spawn("barbarian_club", Vector2(500, 0))
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
		s.horde.spawn("chieftain", Vector2(500, 0))
		s.horde.spawn("barbarian_club", Vector2(450, 150))
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
	check(s.province == "gaul" and Content.ground_path("gaul") == "res://assets/grounds/germania.png", "a province without a file falls back to Germania's ground")


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
	wide.time = 119.9
	wide.horde.next_surge = 120.0
	_step_dt(wide, 1.0)
	var elite := false
	for t in wide.horde.e_tag:
		elite = elite or t == Horde.ELITE
	check(elite, "a ready elite arrives with the surge")
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
	for kind in ["recruits", "arms", "forged", "enemies", "commanders"]:
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
	check(not "engineer" in Game.commanders(content, b), "the engineer waits for Gaul")
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
	for s in ["Arrows or WASD move     Left and right change a volume     Esc back", "Press the new key or button     Esc cancel",
			"Space change a key or button     Esc back"]:
		_fit(cuts, loc, scale, "key hint", tr_.call(s), 624.0)
	_fit(cuts, loc, scale, "give-up prompt", tr_.call("Give up the run? %s again to confirm") % "Q", 624.0)
	for kind in ["pick", "buy", "look", "summary", "level"]:
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
		_fit(cuts, loc, scale, "volume name", tr_.call(s), 440.0 - 12.0 - pct - 80.0 - 6.0)
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
	check(Controls.hint("level") == "A / D to choose     Space to take it", "the default level-up hint is unchanged")
	Controls.rebind(Profile.data.settings.bindings, "left", "keys", 0, KEY_J)
	Controls.rebind(Profile.data.settings.bindings, "confirm", "keys", 0, KEY_E)
	check(Controls.hint("level") == "J / D to choose     E to take it", "the level-up hint shows the rebound keys")
	check(Controls.hint("summary").begins_with("E camp"), "the summary hint shows the rebound confirm key")
	check(Controls.hint("pick").begins_with("W J S D move"), "the move hint shows the rebound march keys")
	Controls.install({})
	Profile.data = saved


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


func test_the_fort_appears_with_the_chieftain_and_its_gate_wins(b: Dictionary) -> void:
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
		if pr[1].distance_to(fort.gate) < float(cfg.clearing) and not s.terrain.extras.has(pr):
			stray += 1
	check(stray == 0, "in open ground (%d strays)" % stray)
	var ci := s.chieftain_index()
	check(ci >= 0, "the chieftain comes out at the same moment")
	var cp: Vector2 = s.horde.e_pos[ci]
	check(cp.distance_to(fort.pos) < d and (cp - s.commander.pos).dot(fort.pos - s.commander.pos) > 0.0, "between the legion and the fort")
	s.horde.e_pos[ci] = s.commander.pos + Vector2(0, 2000)
	s.commander.pos = fort.gate
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.over and s.victory, "marching into the gate wins the run")
	var e := _mode_sim(b, {"seed": 157, "endless": true})
	e.objectives.list.clear()
	e.time = float(b.chieftain_at) - 0.01
	e.update(1.0 / 60.0, Vector2.ZERO, false)
	e.commander.pos = e.objectives.fort.gate
	e.update(1.0 / 60.0, Vector2.ZERO, false)
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
