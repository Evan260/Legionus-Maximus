extends RefCounted
## Checks of the run's rules, run with: godot --headless --path game -- --run-tests

var failures := 0
var passes := 0


func check(ok: bool, what: String) -> void:
	if ok:
		passes += 1
	else:
		failures += 1
		print("FAIL: ", what)


func run(balance: Dictionary) -> int:
	for m in get_method_list():
		if m.name.begins_with("test_"):
			call(m.name, balance)
	print("%d passed, %d failed" % [passes, failures])
	if failures == 0 and passes > 0:
		print("ALL TESTS PASSED")
	return 1 if failures > 0 or passes == 0 else 0


func test_the_run_starts_with_the_commander_and_two_legionaries(b: Dictionary) -> void:
	var s := Sim.new(b, 1)
	check(s.soldiers.size() == 2, "two soldiers at the start")
	check(s.count("legionary") == 2, "both are legionaries")


func test_formation_puts_legionaries_ahead_and_archers_behind(b: Dictionary) -> void:
	var places := Sim.formation(6, 4)
	check(places.size() == 10, "one place per soldier")
	for i in 6:
		check(places[i].x > 0.0, "legionary %d is ahead" % i)
	for i in range(6, 10):
		check(places[i].x < 0.0, "archer %d is behind" % i)


func test_formation_places_never_overlap(b: Dictionary) -> void:
	var places := Sim.formation(40, 30)
	for i in places.size():
		for j in range(i + 1, places.size()):
			check(places[i].distance_to(places[j]) >= 8.0, "places %d and %d apart" % [i, j])


func test_soldiers_reach_their_places_after_marching(b: Dictionary) -> void:
	var s := Sim.new(b, 2)
	Upgrades.apply(s, "archer")
	for i in 180:
		s.update(1.0 / 60.0, Vector2.RIGHT, false)
	for so in s.soldiers:
		var want: Vector2 = s.commander.pos + s.slot_of(so)
		check(so.pos.distance_to(want) < 6.0, "%s near its place" % so.type)


func test_coins_level_the_legion_up(b: Dictionary) -> void:
	var s := Sim.new(b, 3)
	s.gain(int(b.xp_first))
	check(s.level == 2, "first level reached")
	check(s.pending_levels == 1, "one choice waiting")
	check(s.xp_next == int(b.xp_first + b.xp_step), "next level needs more")


func test_a_killed_barbarian_drops_coins_and_is_removed(b: Dictionary) -> void:
	var s := Sim.new(b, 4)
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
	var s := Sim.new(b, 5)
	s.spawn_enemy(0, s.commander.pos + Vector2(10, 0))
	var before: float = s.commander.hp
	for i in 30:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.commander.hp < before, "the commander was hurt")


func test_testudo_cuts_the_harm_taken(b: Dictionary) -> void:
	var plain := Sim.new(b, 6)
	var shielded := Sim.new(b, 6)
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


func test_recruits_join_until_the_cap(b: Dictionary) -> void:
	var s := Sim.new(b, 7)
	for i in 50:
		Upgrades.apply(s, "legionary")
	check(s.count("legionary") == int(b.max_legionaries), "legionaries stop at the cap")
	check(not Upgrades.available(s).has("legionary"), "and are no longer offered")


func test_arms_stop_at_their_last_level(b: Dictionary) -> void:
	var s := Sim.new(b, 8)
	for i in 9:
		Upgrades.apply(s, "pilum")
	check(s.rank("pilum") == 9, "ranks counted")
	check(not Upgrades.available(s).has("pilum"), "a maxed weapon is not offered")


func test_burning_arrows_need_archers(b: Dictionary) -> void:
	var s := Sim.new(b, 9)
	check(not Upgrades.available(s).has("fire_arrows"), "no burning arrows without archers")
	Upgrades.apply(s, "archer")
	check(Upgrades.available(s).has("fire_arrows"), "offered once archers join")


func test_offers_are_three_different_choices(b: Dictionary) -> void:
	var s := Sim.new(b, 10)
	for i in 20:
		var o := Upgrades.offers(s)
		check(o.size() == 3, "three choices")
		check(o[0] != o[1] and o[1] != o[2] and o[0] != o[2], "all different")


func test_pilum_volley_kills_a_lone_barbarian(b: Dictionary) -> void:
	var s := Sim.new(b, 11)
	Upgrades.apply(s, "pilum")
	s.spawn_enemy(0, Vector2(120, 0))
	for i in 120:
		s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.kills >= 1, "the pilum found its mark")


func test_lorica_raises_health(b: Dictionary) -> void:
	var s := Sim.new(b, 12)
	var before: float = s.commander.max_hp
	Upgrades.apply(s, "lorica")
	check(s.commander.max_hp > before, "the commander's health rose")
	check(s.soldiers[0].max_hp > float(b.units.legionary.hp), "the soldiers' health rose")
	Upgrades.apply(s, "legionary")
	check(s.soldiers[-1].max_hp > float(b.units.legionary.hp), "new recruits arrive with it")


func test_the_chieftain_comes_and_his_death_wins(b: Dictionary) -> void:
	var s := Sim.new(b, 13)
	s.time = float(b.chieftain_at) - 0.01
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	var ci := s.chieftain_index()
	check(ci >= 0, "the chieftain arrived")
	s.hit(ci, 1e9)
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.over and s.victory, "his death ends the run in victory")


func test_the_commanders_death_loses(b: Dictionary) -> void:
	var s := Sim.new(b, 14)
	s.commander.hp = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.over and not s.victory, "the run is lost")


func test_fallen_soldiers_leave_the_formation(b: Dictionary) -> void:
	var s := Sim.new(b, 15)
	s.soldiers[0].hp = 0.0
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.soldiers.size() == 1, "one soldier left")


func test_the_horde_grows_over_time(b: Dictionary) -> void:
	var s := Sim.new(b, 16)
	s.soldiers.clear()
	s.commander.hp = 1e9
	for i in 60 * 30:
		s.update(1.0 / 30.0, Vector2(1, 0), false)
	check(s.e_pos.size() > 50, "a crowd after a minute (%d)" % s.e_pos.size())


func test_far_barbarians_come_round_again(b: Dictionary) -> void:
	var s := Sim.new(b, 17)
	s.spawn_enemy(0, Vector2(2000, 0))
	s.update(1.0 / 60.0, Vector2.ZERO, false)
	check(s.e_pos[0].length() <= float(b.spawn_radius) + 5.0, "brought back to the edge")


func test_every_direction_has_a_name(b: Dictionary) -> void:
	check(Sim.dir_name(Vector2.RIGHT) == "east", "right is east")
	check(Sim.dir_name(Vector2.DOWN) == "south", "down is south")
	check(Sim.dir_name(Vector2(-1, -1)) == "north-west", "up-left is north-west")
