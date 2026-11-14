extends RefCounted
## Checks of the run's rules, run with: godot --headless --path game -- --run-tests

var failures := 0
var passes := 0
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
	var s := Sim.new(b, content, 1)
	check(s.soldiers.size() == 2, "two soldiers at the start")
	check(s.count("legionary") == 2, "both are legionaries")


func test_soldiers_reach_their_places_after_marching(b: Dictionary) -> void:
	var s := Sim.new(b, content, 2)
	Upgrades.apply(s, "archer")
	for i in 180:
		s.update(1.0 / 60.0, Vector2.RIGHT, false)
	for so in s.soldiers:
		var want: Vector2 = s.commander.pos + s.slot_of(so)
		check(so.pos.distance_to(want) < 6.0, "%s near its place" % so.type)


func test_coins_level_the_legion_up(b: Dictionary) -> void:
	var s := Sim.new(b, content, 3)
	s.gain(int(b.xp_first))
	check(s.level == 2, "first level reached")
	check(s.pending_levels == 1, "one choice waiting")
	check(s.xp_next == int(b.xp_first + b.xp_step), "next level needs more")


func test_a_killed_barbarian_drops_coins_and_is_removed(b: Dictionary) -> void:
	var s := Sim.new(b, content, 4)
	s.spawn_enemy(0, Vector2(300, 0))
	s.spawn_enemy(1, Vector2(-300, 0))
	var id_left := s.e_id[1]
	s.hit(0, 999.0)
	s._remove_dead()
	check(s.e_pos.size() == 1, "one barbarian left")
	check(s.e_id[0] == id_left, "the other barbarian kept its data")
	check(s.e_pos[0] == Vector2(-300, 0), "and its place")
	check(s.c_pos.size() == 1 and s.c_val[0] == 1, "a coin dropped")
	check(s.kills == 1, "kill counted")


func test_barbarians_hurt_soldiers_they_reach(b: Dictionary) -> void:
	var s := Sim.new(b, content, 5)
	s.spawn_enemy(0, s.commander.pos + Vector2(10, 0))
	var before: float = s.commander.hp
	for i in 30:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.commander.hp < before, "the commander was hurt")


func test_testudo_cuts_the_harm_taken(b: Dictionary) -> void:
	var plain := Sim.new(b, content, 6)
	var shielded := Sim.new(b, content, 6)
	for s in [plain, shielded]:
		s.soldiers.clear()
		s.spawn_enemy(0, Vector2(10, 0))
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
	var s := Sim.new(b, content, 8)
	for i in 9:
		Upgrades.apply(s, "pilum")
	check(s.rank("pilum") == 9, "ranks counted")
	check(not Upgrades.available(s).has("pilum"), "a maxed weapon is not offered")


func test_burning_arrows_need_archers(b: Dictionary) -> void:
	var s := Sim.new(b, content, 9)
	check(not Upgrades.available(s).has("fire_arrows"), "no burning arrows without archers")
	Upgrades.apply(s, "archer")
	check(Upgrades.available(s).has("fire_arrows"), "offered once archers join")


func test_offers_are_three_different_choices(b: Dictionary) -> void:
	var s := Sim.new(b, content, 10)
	for i in 20:
		var o := Upgrades.offers(s)
		check(o.size() == 3, "three choices")
		check(o[0] != o[1] and o[1] != o[2] and o[0] != o[2], "all different")


func test_pilum_volley_kills_a_lone_barbarian(b: Dictionary) -> void:
	var s := Sim.new(b, content, 11)
	Upgrades.apply(s, "pilum")
	s.spawn_enemy(0, Vector2(120, 0))
	for i in 120:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.kills >= 1, "the pilum found its mark")


func test_lorica_raises_health(b: Dictionary) -> void:
	var s := Sim.new(b, content, 12)
	var before: float = s.commander.max_hp
	Upgrades.apply(s, "lorica")
	check(s.commander.max_hp > before, "the commander's health rose")
	check(s.soldiers[0].max_hp > float(content.recruits.legionary.hp), "the soldiers' health rose")
	Upgrades.apply(s, "legionary")
	check(s.soldiers[-1].max_hp > float(content.recruits.legionary.hp), "new recruits arrive with it")


func test_the_chieftain_comes_and_his_death_wins(b: Dictionary) -> void:
	var s := Sim.new(b, content, 13)
	s.time = float(b.chieftain_at) - 0.01
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var ci := s.chieftain_index()
	check(ci >= 0, "the chieftain arrived")
	s.hit(ci, 1e9)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.over and s.victory, "his death ends the run in victory")


func test_the_commanders_death_loses(b: Dictionary) -> void:
	var s := Sim.new(b, content, 14)
	s.commander.hp = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.over and not s.victory, "the run is lost")


func test_fallen_soldiers_leave_the_formation(b: Dictionary) -> void:
	var s := Sim.new(b, content, 15)
	s.soldiers[0].hp = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.soldiers.size() == 1, "one soldier left")


func test_the_horde_grows_over_time(b: Dictionary) -> void:
	var s := Sim.new(b, content, 16)
	s.soldiers.clear()
	s.commander.hp = 1e9
	for i in 60 * 30:
		s.update(1.0 / 30.0, Vector2(1, 0), false)
	check(s.e_pos.size() > 50, "a crowd after a minute (%d)" % s.e_pos.size())


func test_far_barbarians_come_round_again(b: Dictionary) -> void:
	var s := Sim.new(b, content, 17)
	s.spawn_enemy(0, Vector2(2000, 0))
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.e_pos[0].length() <= float(b.spawn_radius) + 5.0, "brought back to the edge")


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
	check(content.province_enemies("germania") == ["barbarian_club", "barbarian_spear"], "only the drawn Germanic enemies")
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
		check(pr.ordinary.size() == 4 and pr.elites.size() == 2 and content.enemies.has(pr.chieftain), "%s has its enemies" % p)


func test_every_implemented_entry_is_ready_and_complete(b: Dictionary) -> void:
	for kind in ["recruits", "arms", "forged", "drills"]:
		var entries: Dictionary = content.get(kind)
		for id in entries:
			var e: Dictionary = entries[id]
			if not e.get("implemented", false):
				continue
			# Recruits are implemented before their sprites are drawn, and the art gate keeps them hidden.
			if kind != "recruits":
				check(content.ready(kind, id), "%s %s has all its art" % [kind, id])
			check(str(e.get("name", "")) != "" and str(e.get("text", "")) != "", "%s %s has a name and text" % [kind, id])
			if kind != "recruits":
				check(int(e.get("max", 0)) > 0, "%s %s has a last level" % [kind, id])


## A run with no soldiers, then one of each listed type added and set on its place.
func _legion_sim(b: Dictionary, seed_value: int, types: Array) -> Sim:
	var s := Sim.new(b, content, seed_value)
	s.soldiers.clear()
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	# No barbarians arrive on their own, so a test sees only the ones it places.
	s.b = b.duplicate()
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	s.next_surge = 1e9
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
	s.spawn_enemy(0, Vector2(322, 0))
	s._rebuild_grids()
	s.legion.assign_guards()
	for i in 20:
		s._move_enemies(1.0 / 60.0)
	check(front.hp < front.max_hp, "the front-rank man took the hit")
	check(rear.hp == rear.max_hp, "the archer behind him was spared")
	rear.pos = Vector2(300, 60)
	s._rebuild_grids()
	s.legion.assign_guards()
	s.e_pos[0] = Vector2(310, 60)
	for i in 20:
		s._move_enemies(1.0 / 60.0)
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
	s.spawn_enemy(0, home + Vector2(0, 70) * signf(home.y))
	var went := 0.0
	for i in 240:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		went = maxf(went, cav.pos.distance_to(home))
		s.commander.hp = 1e9
	check(went > 30.0, "he rode out (%.0f)" % went)
	check(s.kills >= 1 or s.e_hp[0] < s.e_max[0], "and struck")
	check(cav.pos.distance_to(s.commander.pos + s.slot_of(cav)) < 8.0, "and is back in his place")


func test_ballista_bolt_pierces_all(b: Dictionary) -> void:
	var s := _legion_sim(b, 9, ["ballista"])
	for k in 3:
		s.spawn_enemy(0, Vector2(-80 - 25 * k, 0))
	for i in 20:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		s.commander.hp = 1e9
	check(s.shots.size() == 1 and s.shots[0].pierce >= 100, "a bolt that pierces everything flew")
	for i in 90:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
		s.commander.hp = 1e9
	var hurt := 0
	for k in s.e_pos.size():
		if s.e_hp[k] < s.e_max[k]:
			hurt += 1
	check(hurt + s.kills >= 2, "it hit the enemies down its line (%d)" % (hurt + s.kills))


func test_centurion_shout_stuns(b: Dictionary) -> void:
	var s := _legion_sim(b, 10, ["centurion"])
	var c: Dictionary = s.soldiers[0]
	c.shout = 0.0
	s.spawn_enemy(0, c.pos + Vector2(20, 0))
	s.spawn_enemy(0, c.pos + Vector2(200, 0))
	s._rebuild_grids()
	s.legion.update(1.0 / 60.0, s)
	check(s.e_stun[0] > 0.0 and s.e_stun[1] == 0.0, "only the enemy in the shout is stunned")
