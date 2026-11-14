extends RefCounted
## Checks of the run's rules, run with: godot --headless --path game -- --run-tests

var failures := 0
var passes := 0
const WAITING_FOR_ART := ["slinger", "cavalry", "standard_bearer", "medicus", "ballista", "centurion"]

# Built before their icons and small props are drawn; every other implemented entry must have all its art.
const NO_ICON_YET := ["onager", "caltrops", "stakes", "fire_pots", "war_dogs", "trumpets", "eagle", "oil_jars", "torches",
	"hooked_pila", "greek_fire", "siege_train", "hunting_horn", "burning_eagle", "fortified_camp",
	"shield_wall", "better_bows", "close_order", "plunder", "veterans", "reserves", "fortune", "glory"]

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


## A quiet run: no arrivals, an unkillable commander and no soldiers, with the given ranks.
func _arms_sim(b: Dictionary, seed_value: int, ranks: Dictionary, game_content: Content = null) -> Sim:
	var s := Sim.new(b, game_content if game_content != null else content, seed_value)
	s.soldiers.clear()
	s.commander.hp = 1e9
	s.commander.max_hp = 1e9
	s.b = b.duplicate()
	s.b.spawn_per_second_start = 0.0
	s.b.spawn_per_second_growth = 0.0
	s.next_surge = 1e9
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
	s.spawn_enemy(0, Vector2(60, 0))
	s.e_hp[0] = 400.0
	s.e_max[0] = 400.0
	s.e_stun[0] = 100.0
	s.arms.add_zone("fire", Vector2(60, 0), 20.0, 5.0, 20.0)
	_run(s, 0.5)
	var early: float = s.e_hp[0]
	_run(s, 1.0)
	var later: float = s.e_hp[0]
	check(early < 400.0, "the fire hurt at once (%.1f)" % early)
	check(later < early - 10.0, "and kept hurting (%.1f then %.1f)" % [early, later])
	check(s.arms.ground_zones().size() == 1 and s.arms.ground_zones()[0].kind == "fire", "it is drawn as ground")
	_run(s, 6.0)
	check(s.arms.ground_zones().is_empty(), "the fire dies out")


func test_fire_pots_light_the_ground_ahead(b: Dictionary) -> void:
	var s := _arms_sim(b, 37, {"fire_pots": 3})
	s.spawn_enemy(0, Vector2(80, 0))
	s.e_stun[0] = 100.0
	s.e_hp[0] = 500.0
	_run(s, 6.0)
	check(s.e_hp[0] < 500.0, "an enemy ahead was burned (%.1f)" % s.e_hp[0])


func test_trumpets_push_enemies_back(b: Dictionary) -> void:
	var s := _arms_sim(b, 38, {"trumpets": 1})
	s.spawn_enemy(0, Vector2(60, 0))
	s.spawn_enemy(0, Vector2(500, 0))
	s.e_stun[0] = 100.0
	s.e_stun[1] = 100.0
	var far_before: Vector2 = s.e_pos[1]
	_run(s, 1.5)
	check(s.e_pos[0].x > 60.0 + 20.0, "the near enemy was pushed away (%.1f)" % s.e_pos[0].x)
	check(s.e_pos[1].distance_to(far_before) < 40.0, "the far one was not blasted")


func test_scorpio_bolt_damages_the_strongest(b: Dictionary) -> void:
	var s := _arms_sim(b, 39, {"scorpio": 1})
	s.spawn_enemy(0, Vector2(100, 0))
	var before: float = s.e_hp[0]
	s.e_stun[0] = 100.0
	_run(s, 1.5)
	check(s.e_hp.size() == 0 or s.e_hp[0] < before, "a projectile weapon hurts")


func test_onager_stone_scatters_the_crowd(b: Dictionary) -> void:
	var s := _arms_sim(b, 40, {"onager": 2})
	for i in 12:
		s.spawn_enemy(0, Vector2(120 + (i % 4) * 5, (i / 4) * 5))
		s.e_stun[i] = 100.0
		s.e_hp[i] = 500.0
	var before: PackedVector2Array = s.e_pos.duplicate()
	_run(s, 3.0)
	var hurt := 0
	var moved := 0
	for i in s.e_pos.size():
		if s.e_hp[i] < 500.0:
			hurt += 1
		if s.e_pos[i].distance_to(before[i]) > 2.0:
			moved += 1
	check(hurt >= 8, "the stone struck the crowd (%d hurt)" % hurt)
	check(moved >= 6, "and scattered it (%d moved)" % moved)


func test_stakes_hurt_enemies_in_the_ring(b: Dictionary) -> void:
	var s := _arms_sim(b, 41, {"stakes": 1})
	var r: float = float(b.stakes.radius)
	s.spawn_enemy(0, Vector2(r, 0))
	s.spawn_enemy(0, Vector2(r * 2.5, 0))
	s.e_stun[0] = 100.0
	s.e_stun[1] = 100.0
	s.e_hp[0] = 300.0
	s.e_hp[1] = 300.0
	_run(s, 1.0)
	check(s.e_hp[0] < 290.0, "the one at the ring is hurt (%.1f)" % s.e_hp[0])
	check(s.e_hp[1] == 300.0, "the one far outside is not")
	check(s.arms.ground_zones().any(func(z): return z.kind == "stakes"), "the ring is drawn")


func test_torches_burn_what_they_pass(b: Dictionary) -> void:
	var s := _arms_sim(b, 42, {"torches": 3})
	for i in 8:
		s.spawn_enemy(0, Vector2.from_angle(i * TAU / 8.0) * float(b.torches.radius))
		s.e_stun[i] = 100.0
		s.e_hp[i] = 300.0
	_run(s, 4.0)
	var hurt := 0
	for i in s.e_hp.size():
		if s.e_hp[i] < 300.0:
			hurt += 1
	check(hurt >= 3, "torches circling the formation hurt those on their path (%d)" % hurt)
	check(s.arms.torch_points(s).size() == 4, "rank 3 carries four torches")


func test_eagle_flash_strikes_everyone_around(b: Dictionary) -> void:
	var s := _arms_sim(b, 43, {"eagle": 1})
	for i in 5:
		s.spawn_enemy(0, Vector2.from_angle(i * 1.2) * 50.0)
		s.e_stun[i] = 100.0
		s.e_hp[i] = 300.0
	s.spawn_enemy(0, Vector2(400, 0))
	s.e_hp[5] = 300.0
	_run(s, 1.0)
	var hurt := 0
	for i in 5:
		if s.e_hp[i] < 300.0:
			hurt += 1
	check(hurt == 5, "all around were struck (%d)" % hurt)
	check(s.e_hp[5] == 300.0, "the far one was not")


func test_caltrops_are_left_behind_and_cut(b: Dictionary) -> void:
	var s := _arms_sim(b, 44, {"caltrops": 2})
	_step(s, 3.0, Vector2.RIGHT)
	var laid: Array = s.arms.ground_zones().filter(func(z): return z.kind == "caltrops")
	check(laid.size() >= 4, "spikes lie along the march (%d)" % laid.size())
	s.spawn_enemy(0, laid[0].pos)
	s.e_stun[0] = 100.0
	s.e_hp[0] = 300.0
	_run(s, 0.6)
	check(s.e_hp[0] < 300.0, "an enemy on them is cut (%.1f)" % s.e_hp[0])


func test_war_dogs_run_down_a_straggler(b: Dictionary) -> void:
	var s := _arms_sim(b, 45, {"war_dogs": 2})
	s.spawn_enemy(0, Vector2(120, 0))
	s.e_stun[0] = 100.0
	var before: float = s.e_hp[0]
	_run(s, 4.0)
	check(s.e_hp.size() == 0 or s.e_hp[0] < before, "the dogs bit him")
	check(s.arms.dogs.size() == 2, "rank 2 keeps two dogs")


func test_oil_slows_enemies_on_it(b: Dictionary) -> void:
	var s := _arms_sim(b, 46, {})
	s.arms.add_zone("oil", Vector2(60, 0), 30.0, 5.0, 0.0, {"slow": 0.5})
	s.spawn_enemy(0, Vector2(80, 0))
	s.spawn_enemy(0, Vector2(80, 100))
	var a0: Vector2 = s.e_pos[0]
	var b0: Vector2 = s.e_pos[1]
	_run(s, 0.5)
	var slow: float = a0.distance_to(s.e_pos[0])
	var free: float = b0.distance_to(s.e_pos[1])
	check(slow < free * 0.8, "the slick slows (%.1f vs %.1f)" % [slow, free])


func test_oil_jars_make_slick_ground(b: Dictionary) -> void:
	var s := _arms_sim(b, 47, {"oil_jars": 2})
	s.spawn_enemy(0, Vector2(80, 0))
	s.e_stun[0] = 100.0
	_run(s, 3.0)
	check(s.arms.ground_zones().any(func(z): return z.kind == "oil"), "a jar broke into a slick")


func test_each_forged_form_changes_its_pair(b: Dictionary) -> void:
	var s := _arms_sim(b, 48, {"pilum": 5, "hooked_pila": 1})
	s.spawn_enemy(0, Vector2(100, 0))
	s.e_hp[0] = 1000.0
	_run(s, 1.5)
	check(s.e_stun[0] > 0.0, "hooked pila pin the enemy")
	var g := _arms_sim(b, 49, {"fire_arrows": 5, "greek_fire": 1})
	check(g.burn_seconds() > float(b.fire_arrows.seconds), "Greek fire burns longer")
	var t := _arms_sim(b, 50, {"scorpio": 5, "onager": 5, "siege_train": 1})
	check(t.arms.stones_per_throw(t) == int(b.onager.stones) + int(b.siege_train.extra_stones), "the siege train throws more stones")
	var h := _arms_sim(b, 51, {"war_dogs": 5, "trumpets": 5, "hunting_horn": 1})
	check(h.arms.dog_count(h) == 5 + int(b.hunting_horn.extra_dogs), "the horn calls more dogs")
	var e := _arms_sim(b, 52, {"eagle": 5, "torches": 5, "burning_eagle": 1})
	e.spawn_enemy(0, Vector2(40, 0))
	e.e_stun[0] = 100.0
	e.e_hp[0] = 1000.0
	_run(e, 7.0)
	check(e.e_burn[0] > 0.0 or e.e_hp[0] < 900.0, "the burning eagle sets enemies alight")
	var f := _arms_sim(b, 53, {"stakes": 5, "oil_jars": 5, "fortified_camp": 1})
	check(f.arms.stake_dps(f) > float(b.stakes.dps) + 4.0 * float(b.stakes.dps_per_level), "the camp's stakes hurt more")


func test_shield_wall_cuts_front_rank_harm(b: Dictionary) -> void:
	var lost := []
	for r in [0, 3]:
		var s := _legion_sim(b, 60, ["legionary"])
		s.ranks["shield_wall"] = r
		s.soldiers[0].hp = 1000.0
		s.soldiers[0].max_hp = 1000.0
		s.spawn_enemy(0, s.soldiers[0].pos + Vector2(8, 0))
		for i in 60:
			s.update(1.0 / 60.0, Vector2.ZERO, false)
		lost.append(1000.0 - s.soldiers[0].hp)
	check(lost[1] < lost[0] * 0.85 and lost[0] > 0.0, "shield wall takes less harm (%.2f vs %.2f)" % [lost[1], lost[0]])


func test_better_bows_reach_further(b: Dictionary) -> void:
	var near := _legion_sim(b, 61, ["archer"])
	var far := _legion_sim(b, 61, ["archer"])
	far.ranks["better_bows"] = 3
	for s in [near, far]:
		s.spawn_enemy(0, s.soldiers[0].pos + Vector2(-float(content.recruits.archer.range) * 1.2, 0))
		s.e_stun[0] = 100.0
	for i in 90:
		near.update(1.0 / 60.0, Vector2.ZERO, false)
		far.update(1.0 / 60.0, Vector2.ZERO, false)
	check(near.shots.is_empty() and near.e_hp[0] == near.e_max[0], "an archer cannot reach")
	check(not far.shots.is_empty() or far.e_hp[0] < far.e_max[0], "with better bows he can")


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
	var s := _arms_sim(b, 63, {"plunder": 5})
	for i in 400:
		s.spawn_enemy(0, Vector2(300, 300))
		s.hit(s.e_hp.size() - 1, 9999.0)
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
		s.spawn_enemy(0, Vector2(300, 300))
		s.hit(s.e_hp.size() - 1, 9999.0)
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
		s.spawn_enemy(i % 2, s._ring_point() * 0.4)
	_step(s, 20.0, Vector2(1, 0.3))
	check(not s.over, "a legion with every arm and form runs on")
