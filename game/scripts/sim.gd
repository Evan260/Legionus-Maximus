class_name Sim
extends RefCounted
## One run: the legion, the horde, missiles, coins and levels, as plain data so it runs and tests without a scene.

const CELL := 32.0
const GW := 48
const UNIT_RADIUS := 7.0
## The widest enemy that skips the search for a unit to strike when his cell is not marked in ug_near.
const NEAR_RADIUS := 8.0
## How long a body falling into a ravine takes to vanish.
const PLUNGE_SECONDS := 0.55
## Kinds that happen many times an update are counted and reported once per update; the rest are reported as they happen.
const COUNTED := ["hit", "kill", "coin", "arrow", "pilum", "bolt"]
const EVENT_CAP := 64
const DIRS := ["east", "south-east", "south", "south-west", "west", "north-west", "north", "north-east"]
## The difficulties a run can be played at, easiest first.
const DIFFICULTIES := ["easy", "medium", "hard"]

var b: Dictionary
var rng := RandomNumberGenerator.new()

var time := 0.0
var level := 1
var xp := 0
var xp_next := 0
var kills := 0
var denarii := 0
var pending_levels := 0
var over := false
var victory := false
## The demo's time limit in seconds (0 for none), and whether the run ended by reaching it.
var demo_seconds := 0.0
var demo_over := false
var ranks := {}

var legion: Legion
var commander: Dictionary:
	get:
		return legion.commander
var soldiers: Array:
	get:
		return legion.soldiers
	set(value):
		legion.soldiers = value
var facing_angle := 0.0
var moving := false
## The legion's march on the ice, which follows the way it is steered only slowly, so it slides.
var glide := Vector2.ZERO
## Whether the commander stands on a dune's soft sand, which slows the march.
var on_sand := false
## Whether the commander stands in a bog pool, which slows the march more than sand.
var in_bog := false
## Whether the commander stands in a reed bed, which slows the march a little.
var in_reeds := false
## Whether the commander stands in feather grass, which slows the march a little.
var in_grass := false
# How many barbarians were locked in melee with the legion on the last update.
var pressing := 0

var horde: Horde
var terrain: Terrain
var objectives := Objectives.new()
var province := "germania"
var free_choices := 0
## The supply carts opened and not yet chosen from, oldest first, each as {left, picks}.
var supplies: Array = []
var g_origin: Vector2i:
	get:
		return horde.g_origin
var g_start: PackedInt32Array:
	get:
		return horde.g_start
var g_items: PackedInt32Array:
	get:
		return horde.g_items

## What the sound reads: {kind, pos} and, for counted kinds, how many (n). The reader clears the list.
var events: Array = []
var shots: Array = []
var c_pos := PackedVector2Array()
var c_val := PackedInt32Array()
var c_pull := PackedByteArray()
var c_born := PackedFloat32Array()
var effects: Array = []

var arms: Arms
var gods := Gods.new()
# The first source id that is a god, so a god's harm is told apart with one comparison.
var _god_src := 1 << 30
var rerolls := 0
var banishes := 0
var banished: Array = []
var xp_carry := 0.0
var testudo_left := 0.0
var testudo_charge := 1.0

var legion_reach := 0.0
var units: Array = []
# The units by cell on the horde's grid, built every update: the first unit in each cell or -1, the next unit in the same cell or -1,
# and 1 in every cell an enemy up to NEAR_RADIUS wide could strike a unit from.
var ug_head := PackedInt32Array()
var ug_next := PackedInt32Array()
var ug_near := PackedByteArray()
## Whether every unit stands inside the horde's grid; when one does not, lookups go through unit_cells() instead.
var ug_all_in := false
var _u_cells := {}
var _u_cells_ready := false
var _ug_pos := PackedVector2Array()
var content: Content
var commander_id := "tribune"
## The run's difficulty, one of DIFFICULTIES; Easy and Hard scale the horde by their blocks in balance.json.
var difficulty := "medium"
var endless := false
var decimatio := false
var bonuses := {}:
	set(value):
		bonuses = value
		_bonus_amounts.clear()
# What each quartermaster upgrade adds, worked out once, since every hit, burn, kill and coin asks for one.
var _bonus_amounts := {}
var decimate_next := 0.0
var endless_since := -1.0
var peak_soldiers := 0
var killed_kinds := {}
var damage_by_source: Dictionary:
	get:
		return _fold_damage()
var history: Array = []
var numbers: Array = []
var show_numbers := false
## The player's blood setting: with it off a kill sprays no blood and leaves no stain.
var blood := true
var shake := 0.0
## How far the screen shakes, in pixels, while it shakes harder than `shake.pixels`; 0 for the usual.
var shake_pixels := 0
## Real seconds left of the slow motion that follows the chieftain's fall.
var slow_left := 0.0
## When the chieftain fell, on the run's clock, for his banner; -1 while he stands.
var chief_fallen_at := -1.0
## The stains kills leave on the ground, kept as a ring of at most `deaths.stain_cap`, written over oldest first.
var stain_pos := PackedVector2Array()
var stain_dir := PackedVector2Array()
var stain_born := PackedFloat32Array()
var stain_life := PackedFloat32Array()
var stain_size := PackedFloat32Array()
var stain_seed := PackedInt32Array()
var _stain_next := 0
var _next_sample := 0.0
var _damage_named := {}
var _damage := PackedFloat64Array()
var _src_ids := {}
var _src_names: Array = []
var _last_hp := 0.0
var _tally_n := PackedInt32Array([0, 0, 0, 0, 0, 0])
var _tally_pos := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _chieftain_heard := false
## Seconds left of the triumph after a win, and how long it has played.
var triumph_left := 0.0
var triumph_t := 0.0
# When in the triumph the last barbarian and coin went and every man reached his place, or -1 while any is left.
var _clear_at := -1.0
var _hurt_heard := -1e9
## Logs from felled trees, spent on palisades.
var timber := 0
## When a palisade was last asked for without the timber for it, for the notice.
var palisade_refused_at := -1.0
## When a wall was last asked for without the timber for it, for the notice.
var wall_refused_at := -1.0
## The last bridge asked for that could not be laid, {at, why} with why "timber" or "ravine".
var bridge_refused := {}
## Whether the legion faces a ravine it could bridge, looked at a few times a second for the hint.
var bridge_here := false
var _bridge_look := 0.0
## Whether a ravine's lip is close enough to be on screen, for the bridge cost beside the timber.
var ravine_near := false
## Whether this run may still show the tip about bridging, and whether it has.
var ravine_tip := true
var ravine_tip_shown := false
# Barbarians thrown into a ravine, by id, with the lip a boss was shoved off (INF for the rest, who drop nothing).
var _plunged := {}


func _init(balance: Dictionary, game_content: Content, options := {}) -> void:
	province = options.get("province", "germania")
	commander_id = options.get("commander", "tribune")
	if not game_content.commanders.has(commander_id):
		commander_id = "tribune"
	difficulty = options.get("difficulty", "medium")
	if not difficulty in DIFFICULTIES:
		difficulty = "medium"
	endless = options.get("endless", false)
	decimatio = options.get("decimatio", false)
	ravine_tip = options.get("ravine_tip", true)
	demo_seconds = float(options.get("demo_seconds", 0.0))
	bonuses = options.get("profile_bonuses", {})
	b = balance
	content = game_content
	var seed_value := int(options.get("seed", 0))
	rng.seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system())
	var kit: Dictionary = content.commanders[commander_id]
	legion = Legion.new(b, content, rng, ranks)
	arms = Arms.new(rng)
	legion.commander_hp_add = bonus_amount("start_health")
	legion.commander_hp_mult = float(kit.get("hp_mult", 1.0))
	legion.soldier_hp_mult = 1.0 + bonus_amount("soldier_health")
	legion.cap = int(b.legion_cap) + int(bonus_amount("recruit_cap"))
	legion.commander.max_hp = legion.max_hp_of("commander")
	legion.commander.hp = legion.commander.max_hp
	horde = Horde.new(b, content, rng, legion.commander, province)
	horde.run_difficulty = difficulty
	terrain = Terrain.new(rng.seed, b.forest, b.get("ravines", {}))
	terrain.field = b.get("fields", {}).get(province, {})
	terrain.mountain = b.get("mountains", {}).get(province, {})
	terrain.stream_cfg = b.get("streams", {}).get(province, {})
	terrain.desert = b.get("deserts", {}).get(province, {})
	terrain.moor = b.get("moors", {}).get(province, {})
	terrain.hills = b.get("hills", {}).get(province, {})
	terrain.valley = b.get("valleys", {}).get(province, {})
	terrain.steppe = b.get("steppes", {}).get(province, {})
	if b.get("canals", {}).has(province):
		terrain.set_canals(b.canals[province])
	terrain.clear_radius = float(b.terrain_clear_radius)
	terrain.fell_seconds = float(b.felling.seconds)
	objectives.place_start(self, options.get("objectives_near", false))
	terrain.refresh(legion.commander.pos)
	horde.sim_ref = weakref(self)
	rerolls = int(b.rerolls) + int(kit.get("rerolls", 0)) + int(bonus_amount("rerolls"))
	banishes = int(b.banishes) + int(bonus_amount("banishes"))
	xp_next = xp_for(1)
	decimate_next = float(b.decimatio.every)
	_next_sample = float(b.history_every)
	_build_sources()
	# Decimatio fills the legion with the kit's line troops, so a commander's single specialist stays one man.
	var line_types: Array = []
	for key in kit.starts:
		if key.begins_with("arm:"):
			ranks[key.trim_prefix("arm:")] = int(kit.starts[key])
		else:
			if int(content.recruits[key].per_pick) > 1:
				line_types.append(key)
			for i in int(kit.starts[key]):
				add_soldier(key)
	if decimatio:
		var i := 0
		while soldiers.size() < int(b.decimatio.start_soldiers):
			add_soldier(line_types[i % line_types.size()] if not line_types.is_empty() else "legionary")
			i += 1
	for i in int(bonus_amount("start_soldiers")):
		add_soldier("legionary")
	legion.place_all(facing_angle)
	_last_hp = commander.hp


## The rank the profile holds in a quartermaster upgrade.
func _bonus(id: String) -> int:
	return int(bonuses.get(id, 0))


## What a quartermaster upgrade adds, its rank times its step.
func bonus_amount(id: String) -> float:
	var v: Variant = _bonus_amounts.get(id)
	if v == null:
		v = float(_bonus(id)) * float(content.quartermaster[id].per_rank) if content.quartermaster.has(id) else 0.0
		_bonus_amounts[id] = v
	return v


## Opens a supply cart's choice of rewards, to be chosen from `picks` times.
func add_supply(picks: int) -> void:
	supplies.append({"left": Horde.CART_REWARDS.duplicate(), "picks": picks})


## The rewards the oldest open supply cart still offers, or none.
func supply_offers() -> Array:
	return supplies[0].left.duplicate() if not supplies.is_empty() else []


## Gives a reward of the oldest open supply cart, which closes once its picks are spent.
func take_supply(id: String) -> void:
	if supplies.is_empty():
		return
	var cart: Dictionary = supplies[0]
	cart.left.erase(id)
	cart.picks -= 1
	if cart.picks <= 0 or cart.left.is_empty():
		supplies.pop_front()
	horde.cart_reward(self, id)


## How hurt the legion is: its wounded soldiers, their health as a percentage of their most, and the commander's percentage.
func legion_health() -> Dictionary:
	var has := 0.0
	var most := 0.0
	var wounded := 0
	for u in soldiers:
		has += u.hp
		most += u.max_hp
		if u.hp < u.max_hp:
			wounded += 1
	var share := 100 if wounded == 0 else floori(100.0 * has / most)
	var own := 100 if commander.hp >= commander.max_hp else floori(100.0 * commander.hp / commander.max_hp)
	return {"wounded": wounded, "share": share, "commander": own}


## The supply a bot or an autoplay takes: healing for a legion or a commander below half health, otherwise the free level-up.
func bot_supply() -> String:
	var offers := supply_offers()
	if offers.is_empty():
		return ""
	var h := legion_health()
	if offers.has("heal") and (h.share < 50 or h.commander < 50):
		return "heal"
	return "free_choice" if offers.has("free_choice") else str(offers[0])


func rank(id: String) -> int:
	return int(ranks.get(id, 0))


func count(type: String) -> int:
	return legion.count(type)


func max_hp_of(type: String) -> float:
	return legion.max_hp_of(type)


func add_soldier(type: String) -> void:
	legion.add(type)


## The commander's own march before any upgrade, which the pace of the barbarians on foot is measured against.
func base_pace() -> float:
	return float(content.base_commander.speed) * float(content.commanders[commander_id].get("speed_mult", 1.0))


func speed() -> float:
	var v: float = content.base_commander.speed * (1.0 + float(b.drills.march) * rank("march") + bonus_amount("move_speed")) * float(content.commanders[commander_id].get("speed_mult", 1.0))
	# Barbarians locked in melee hold the legion back, so marching into a crowd bogs it down instead of passing through.
	var held := 1.0 - float(b.press.per_enemy) * pressing
	var cursed := 1.0 - horde.curse_slow if horde.curse_left > 0.0 else 1.0
	var frozen := 1.0 - horde.frost_slow
	var sand := 1.0 - float(terrain.desert.get("dune_slow", 0.0)) if on_sand else 1.0
	var bog := 1.0 - float(terrain.moor.get("bog_slow", 0.0)) if in_bog else 1.0
	var reeds := 1.0 - float(terrain.valley.get("reed_slow", 0.0)) if in_reeds else 1.0
	var grass := 1.0 - float(terrain.steppe.get("grass_slow", 0.0)) if in_grass else 1.0
	var flooded := 1.0 - horde.flood_slow
	return v * maxf(float(b.press.slowest), held * cursed * frozen * sand * bog * reeds * grass * flooded * (b.testudo_speed if testudo_left > 0.0 else 1.0))


func range_mult() -> float:
	return (1.0 + float(b.drills.better_bows) * rank("better_bows")) * (1.0 + bonus_amount("missile_range"))


## The coins the next level after `at` needs, fewer with the quartermaster's level ease.
func xp_for(at: int) -> int:
	return maxi(1, int(float(b.xp_first + b.xp_step * (at - 1)) * (1.0 - bonus_amount("level_ease"))))


## How long a fire set by an arrow burns.
func burn_seconds() -> float:
	return float(b.greek_fire.seconds) if rank("greek_fire") > 0 else float(b.fire_arrows.seconds)


## How long the testudo holds and how long it takes to charge again with that many ranks of the drill.
func testudo_hold_at(drill: int) -> float:
	return b.testudo_hold + float(b.drills.testudo_hold) * drill + bonus_amount("testudo_hold")


func testudo_recharge_at(drill: int) -> float:
	return maxf(5.0, b.testudo_recharge - float(b.drills.testudo_recharge) * drill - bonus_amount("testudo_charge"))


## What the gladius drill does to a blow; missiles get half, since the drill trains sword work.
func gladius_mult(missile: bool) -> float:
	return 1.0 + float(b.drills.gladius) * rank("gladius") * (0.5 if missile else 1.0)


func attack_rate() -> float:
	return (1.0 + float(b.drills.discipline) * rank("discipline")) * (1.0 + bonus_amount("attack_speed")) * (float(b.gods.mars.rate_mult) if gods.frenzy_left > 0.0 else 1.0) * (1.0 - horde.blast_slow if horde.blast_left > 0.0 else 1.0)


## Whether a unit carries a shield, and so stands in the testudo (`shield` in content.json).
static func shielded(u: Dictionary) -> bool:
	return u.get("shield", false)


## The share of a blow that reaches unit u past the shield wall drill, which guards the front rank only.
func front_guard(u: Dictionary) -> float:
	return 1.0 - float(b.drills.shield_wall) * rank("shield_wall") if u.get("place", "") == "front" else 1.0


## The share of a blow that reaches unit u through the testudo: the cut share for a shield-bearer while it is raised, all of it for anyone else.
func testudo_guard(u: Dictionary) -> float:
	return float(b.testudo_damage_taken) if testudo_left > 0.0 and u.get("shield", false) else 1.0


## The share of harm the legion takes: less with the quartermaster's armour and while Mars's frenzy is on it.
func frenzy_guard() -> float:
	return (float(b.gods.mars.taken_mult) if gods.frenzy_left > 0.0 else 1.0) * (1.0 - bonus_amount("armour"))


func pickup_radius() -> float:
	return b.pickup_radius * (1.0 + float(b.drills.reach) * rank("reach") + bonus_amount("pickup_radius"))


func update(dt: float, move: Vector2, testudo_pressed: bool) -> void:
	if over:
		return
	if triumph_left > 0.0:
		_triumph(dt)
		return
	time += dt
	terrain.clock = time
	if testudo_pressed and testudo_charge >= 1.0 and testudo_left <= 0.0:
		event("testudo", commander.pos)
		testudo_left = testudo_hold_at(rank("testudo"))
		testudo_charge = 0.0
		shake = maxf(shake, float(b.shake.testudo))
	if testudo_left > 0.0:
		testudo_left -= dt
	else:
		testudo_charge = minf(1.0, testudo_charge + dt / testudo_recharge_at(rank("testudo")))
	_move_legion(dt, move)
	_bridge_look -= dt
	if _bridge_look <= 0.0:
		_bridge_look = float(b.bridge.look_every)
		bridge_here = not terrain.rv_items.is_empty() and not bridge_span().is_empty()
		_look_for_ravines()
	_rebuild_grids()
	objectives.before_horde(self)
	horde.update(dt, self)
	objectives.update(dt, self)
	_legion_attacks(dt)
	arms.update(dt, self)
	gods.update(dt, self)
	_move_shots(dt)
	_burns(dt)
	_remove_dead()
	horde.drop_gave_up()
	_coins(dt)
	_effects(dt)
	_regen(dt)
	_decimate()
	peak_soldiers = maxi(peak_soldiers, soldiers.size())
	_track(dt)
	if not _chieftain_heard and horde.chieftain_id != -1:
		_chieftain_heard = true
		event("chieftain", commander.pos)
	_flush_events()
	if commander.hp <= 0.0:
		over = true
		# A run already won, or a chieftain already slain in an endless run, keeps the win.
		victory = victory or endless_since >= 0.0
	elif not over and demo_seconds > 0.0 and time >= demo_seconds:
		over = true
		victory = true
		demo_over = true


## Reports something rare at once. The list is capped so a reader that never clears it cannot grow it.
func event(kind: String, pos: Vector2) -> void:
	if events.size() < EVENT_CAP:
		events.append({"kind": kind, "pos": pos})


## Counts something frequent; `flush` turns each count into one event at the end of the update.
func tally(kind_index: int, pos: Vector2) -> void:
	_tally_n[kind_index] += 1
	_tally_pos[kind_index] = pos


func _flush_events() -> void:
	for i in COUNTED.size():
		if _tally_n[i] > 0:
			if events.size() < EVENT_CAP:
				events.append({"kind": COUNTED[i], "pos": _tally_pos[i], "n": _tally_n[i]})
			_tally_n[i] = 0


## Gives every weapon and soldier type an int id once, so a harm is a plain array add.
func _build_sources() -> void:
	var names: Array = ["commander"]
	for kind in ["recruits", "arms", "forged"]:
		names.append_array(content.get(kind).keys())
	if not content.gods.is_empty():
		_god_src = names.size()
		names.append_array(content.gods.keys())
	for n in names:
		_src_ids[n] = _src_names.size()
		_src_names.append(n)
	_damage.resize(_src_names.size())


## The damage per source id, named; read when the summary or a test asks for it.
func _fold_damage() -> Dictionary:
	for i in _src_names.size():
		if _damage[i] > 0.0:
			_damage_named[_src_names[i]] = _damage[i]
	return _damage_named


## The run's history sample, and the screen shake that follows the commander being hurt.
func _track(dt: float) -> void:
	if time >= _next_sample:
		_next_sample += float(b.history_every)
		history.append({"t": time, "legion": soldiers.size() + 1, "kills": kills})
	if commander.hp < _last_hp:
		shake = maxf(shake, float(b.shake.hurt))
		# The cry sounds once for a run of blows, so a crowd gnawing at the commander does not loop it.
		if time - _hurt_heard >= float(b.get("hurt_every", 0.0)):
			_hurt_heard = time
			event("hurt", commander.pos)
	_last_hp = commander.hp


func _move_legion(dt: float, move: Vector2) -> void:
	moving = move.length() > 0.15
	on_sand = terrain.on_dune(commander.pos)
	in_bog = terrain.in_bog(commander.pos)
	in_reeds = terrain.in_reeds(commander.pos)
	in_grass = terrain.in_grass(commander.pos)
	var want := Vector2.ZERO
	if moving:
		var dir := move.normalized() if move.length() > 1.0 else move
		# Marching head-on into a wheat field, the legion turns along its edge rather than standing pressed against it.
		var along := terrain.round_field(commander.pos + dir * speed() * dt, UNIT_RADIUS, dir.normalized())
		want = (along * dir.length() if along != Vector2.ZERO else dir) * speed()
		facing_angle = lerp_angle(facing_angle, move.angle(), minf(1.0, dt * 5.0))
		commander.facing = move.normalized()
	if terrain.on_ice(commander.pos):
		var ice: Dictionary = b.ice
		glide = glide.lerp(want * float(ice.glide), minf(1.0, dt * float(ice.grip)))
	else:
		glide = want
	commander.pos += glide * dt
	var before: Vector2 = commander.pos
	commander.pos = terrain.push_out(commander.pos, UNIT_RADIUS, dt)
	if commander.pos != before:
		glide = Vector2.ZERO if moving else glide * 0.5
	terrain.rot_posts(time)
	terrain.refresh(commander.pos)
	terrain.update_flow(commander.pos)
	commander.moving = moving
	commander.anim += dt * 10.0
	legion.follow(dt, self)
	for so in soldiers:
		so.pos = terrain.push_out(so.pos, UNIT_RADIUS, dt)
	_shove_bosses()
	var fallen := terrain.fell_ready()
	if fallen > 0:
		timber += terrain.take_logs() * int(b.felling.timber)
		event("fell", commander.pos)
		terrain.refresh(commander.pos)


## Romans who march into a boss push him ahead of them; what the trees, rocks or a gorge will not let him give, the Romans give instead.
func _shove_bosses() -> void:
	var bosses: Array = horde.elite_ids.duplicate()
	if horde.chieftain_id != -1 and not horde.charging:
		bosses.append(horde.chieftain_id)
	if bosses.is_empty():
		return
	var line := units_in_formation()
	for id in bosses:
		var i := horde.e_id.find(id)
		if i < 0:
			continue
		var p := horde.e_pos[i]
		var r := horde.k_radius[horde.e_kind[i]]
		var reach := r + UNIT_RADIUS
		if p.distance_to(commander.pos) > legion_reach + reach:
			continue
		var shove := Vector2.ZERO
		for u in line:
			var off: Vector2 = p - u.pos
			var d := off.length()
			if d < reach:
				shove += (off / d if d > 0.001 else Vector2.RIGHT) * (reach - d)
		if shove == Vector2.ZERO:
			continue
		var wide := r > Terrain.MAX_UNIT
		var np := p + shove.limit_length(reach)
		var kept := terrain.ravine_push(np, r, wide)
		# The chieftain digs in at the lip, so a gorge is no shortcut past the last fight.
		if shoved_over(np, kept, shove) and horde.e_id[i] != horde.chieftain_id:
			_fall(i, np, kept)
			continue
		np = terrain.push_out_wide(np, r) if wide else terrain.push_out(np, r)
		np = terrain.ravine_push(np, r, wide)
		horde.e_pos[i] = np
		var st: Dictionary = horde.boss.get(id, {})
		if st.get("hold", 0.0) > 0.0:
			st.at = np
		for u in line:
			var off: Vector2 = u.pos - np
			var d := off.length()
			if d < reach:
				u.pos = np + (off / d if d > 0.001 else Vector2.LEFT) * reach


## The commander and the soldiers standing in the formation, not those out on a sortie.
func units_in_formation() -> Array:
	var out: Array = [commander]
	for so in soldiers:
		if so.sortie == 0:
			out.append(so)
	return out


## How far the legion reaches behind (x, negative) and ahead (y) of the commander along `dir`; a man far from his place counts at his place, so a straggler does not move the stakes to him.
func formation_reach(dir: Vector2) -> Vector2:
	var reach := Vector2.ZERO
	var places := legion.formation()
	var straggle := float(b.legion.straggle)
	for i in soldiers.size():
		var so: Dictionary = soldiers[i]
		if so.sortie != 0:
			continue
		var place: Vector2 = commander.pos + places[i].rotated(facing_angle)
		var at: Vector2 = so.pos if so.pos.distance_to(place) <= straggle else place
		var d: float = (at - commander.pos).dot(dir)
		reach = Vector2(minf(reach.x, d), maxf(reach.y, d))
	return reach


## Where the palisade's stakes go: a shallow arc across the legion's facing, `ahead` px beyond its front rank, its ends bowed back.
func palisade_points() -> Array:
	var cfg: Dictionary = b.palisade
	var dir := Vector2.from_angle(facing_angle)
	var front := formation_reach(dir).y
	var n := int(cfg.stakes)
	var out: Array = []
	for k in n:
		var t := (k - (n - 1) / 2.0) / maxf(1.0, (n - 1) / 2.0)
		out.append(commander.pos + dir * (front + float(cfg.ahead) - float(cfg.bow) * t * t) + dir.orthogonal() * t * (n - 1) / 2.0 * float(cfg.gap))
	return out


## Where the wall's stakes go: a line across the legion's facing, `behind` px beyond its rear rank, its ends bowed forward round the rear.
func wall_points() -> Array:
	var cfg: Dictionary = b.wall
	var dir := Vector2.from_angle(facing_angle)
	var rear := formation_reach(dir).x
	var n := int(cfg.stakes)
	var out: Array = []
	for k in n:
		var t := (k - (n - 1) / 2.0) / maxf(1.0, (n - 1) / 2.0)
		out.append(commander.pos + dir * (rear - float(cfg.behind) + float(cfg.bow) * t * t) + dir.orthogonal() * t * (n - 1) / 2.0 * float(cfg.gap))
	return out


## Spends timber on a line of stakes ahead of the legion, leaving out any place a man stands; without the timber it is refused.
func build_palisade() -> bool:
	if timber < int(b.palisade.cost):
		event("back", commander.pos)
		palisade_refused_at = time
		return false
	return _drive_stakes(palisade_points(), b.palisade, "stake")


## Spends timber on a wall of stakes behind the legion that the horde can batter down; without the timber it is refused.
func build_wall() -> bool:
	if timber < int(b.wall.cost):
		event("back", commander.pos)
		wall_refused_at = time
		return false
	return _drive_stakes(wall_points(), b.wall, "wall")


## Drives the stakes of `points` that stand clear of men and ravines and pays `cfg.cost`; with no room for any, the timber is kept.
func _drive_stakes(points: Array, cfg: Dictionary, kind: String) -> bool:
	var radius := float(cfg.radius)
	var spots: Array = []
	for p in points:
		var free := not terrain.over_ravine(p, -radius)
		for u in [commander] + soldiers:
			free = free and u.pos.distance_to(p) >= radius + UNIT_RADIUS
		if free:
			spots.append(p)
	if spots.is_empty():
		event("back", commander.pos)
		return false
	timber -= int(cfg.cost)
	for p in spots:
		terrain.add_post(p, radius, time + float(cfg.seconds), kind)
	terrain.refresh(commander.pos)
	event("palisade", commander.pos)
	return true


## How far ahead of the commander the legion's front rank stands, along its facing.
func _front() -> float:
	var dir := Vector2.from_angle(facing_angle)
	var front := 0.0
	for u in units_in_formation():
		front = maxf(front, (u.pos - commander.pos).dot(dir))
	return front


## The ravine straight ahead of the legion that a bridge would cross, as [near, far] distances from the commander, or [].
func bridge_span() -> Array:
	var cfg: Dictionary = b.bridge
	var dir := Vector2.from_angle(facing_angle)
	var span := terrain.span_ahead(commander.pos, dir, _front() + float(cfg.reach), float(cfg.longest))
	if span.is_empty() or terrain.on_bridge(commander.pos) >= 0 or terrain.on_bridge(commander.pos + dir * (float(span[0]) + float(span[1])) / 2.0) >= 0:
		return []
	return span


## Notes a ravine on screen, and the first time one comes into view tells the player how to cross it.
func _look_for_ravines() -> void:
	var within := float(b.bridge.tip_within)
	ravine_near = terrain.ravine_edge(commander.pos, within + float(b.ravines.width[1])) < within
	var note: Dictionary = objectives.notice
	var quiet := note.is_empty() or time - float(note.at) >= float(note.get("seconds", b.objectives.notice_seconds))
	if ravine_near and ravine_tip and not ravine_tip_shown and quiet:
		ravine_tip_shown = true
		objectives.notice = {"kind": "canal" if not terrain.canal.is_empty() else "ravine", "at": time, "seconds": float(b.bridge.tip_seconds)}


## Spends timber on a plank bridge across the ravine ahead; with no ravine ahead or too little timber it is refused.
func build_bridge() -> bool:
	var cfg: Dictionary = b.bridge
	var span := bridge_span()
	var why := "ravine" if span.is_empty() else ("timber" if timber < int(cfg.cost) else "")
	if why != "":
		event("back", commander.pos)
		bridge_refused = {"at": time, "why": why}
		return false
	timber -= int(cfg.cost)
	var dir := Vector2.from_angle(facing_angle)
	var over := float(cfg.overhang)
	terrain.add_bridge(commander.pos + dir * (span[0] - over), commander.pos + dir * (span[1] + over), float(cfg.width) / 2.0)
	terrain.refresh(commander.pos)
	bridge_refused = {}
	bridge_here = false
	event("bridge", commander.pos)
	return true


## A barbarian thrown over a ravine's drop falls to his death. A boss leaves his reward at `lip`, the ground he was shoved off.
func plunge(i: int, lip := Vector2.INF) -> void:
	_plunged[horde.e_id[i]] = lip
	horde.e_hp[i] = 0.0


## Whether a push that moved a man to `to` drove him over a ravine's lip: the gorge held him back at `kept`, against the push, and no bridge's deck bore him.
func shoved_over(to: Vector2, kept: Vector2, push: Vector2) -> bool:
	if kept == to or push == Vector2.ZERO:
		return false
	var back := kept - to
	return back.dot(push) < -0.5 * back.length() * push.length() and terrain.on_bridge(to) < 0 and terrain.on_bridge(kept) < 0


## A boss the legion shoves over a ravine's lip falls and dies at once, crying out as he goes.
func _fall(i: int, at: Vector2, lip: Vector2) -> void:
	event("bossfall", at)
	shake = maxf(shake, float(b.shake.get("bossfall", 0.0)))
	horde.e_pos[i] = at
	plunge(i, lip)
	var before := kills
	_kill(i)
	var widths: Array = terrain.canal.width if not terrain.canal.is_empty() else b.ravines.width
	effects[-1].into = (at - lip).normalized() * float(widths[0]) * 0.5
	legion.veterans(kills - before, self)


func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func _rebuild_grids() -> void:
	horde.rebuild_grid()
	legion_reach = 0.0
	for so in soldiers:
		legion_reach = maxf(legion_reach, (so.pos - commander.pos).length())
	legion_reach += 24.0
	units = [commander]
	units.append_array(soldiers)
	_u_cells_ready = false
	var gw := Horde.GW
	var go := horde.g_origin
	var n := units.size()
	ug_head.resize(gw * gw)
	ug_head.fill(-1)
	ug_next.resize(n)
	ug_near.resize(gw * gw)
	ug_near.fill(0)
	_ug_pos.resize(n)
	ug_all_in = true
	for i in n:
		var p: Vector2 = units[i].pos
		_ug_pos[i] = p
		var cx := floori(p.x / CELL) - go.x
		var cy := floori(p.y / CELL) - go.y
		if cx < 0 or cy < 0 or cx >= gw or cy >= gw:
			ug_all_in = false
			continue
		var reach := UNIT_RADIUS + 2.0 + NEAR_RADIUS
		for y in range(maxi(0, floori((p.y - reach) / CELL) - go.y), mini(gw, floori((p.y + reach) / CELL) - go.y + 1)):
			for x in range(maxi(0, floori((p.x - reach) / CELL) - go.x), mini(gw, floori((p.x + reach) / CELL) - go.x + 1)):
				ug_near[x + y * gw] = 1
	# Linked from the last unit back, each cell lists its units in the order of the units array.
	for i in range(n - 1, -1, -1):
		var p := _ug_pos[i]
		var cx := floori(p.x / CELL) - go.x
		var cy := floori(p.y / CELL) - go.y
		if cx >= 0 and cy >= 0 and cx < gw and cy < gw:
			ug_next[i] = ug_head[cx + cy * gw]
			ug_head[cx + cy * gw] = i


## The units by global cell where they stood when the grids were built, for a lookup the horde's grid cannot answer.
func unit_cells() -> Dictionary:
	if not _u_cells_ready:
		_u_cells_ready = true
		_u_cells.clear()
		for i in _ug_pos.size():
			var k := _cell(_ug_pos[i])
			if not _u_cells.has(k):
				_u_cells[k] = []
			_u_cells[k].append(i)
	return _u_cells


## Something moved a unit after the grids were built, so lookups use unit_cells() for the rest of the update.
func units_moved() -> void:
	ug_all_in = false


func _cidx(p: Vector2) -> int:
	return horde.cidx(p)


func nearest_enemy(p: Vector2, reach: float) -> int:
	return horde.nearest(p, reach)


## Indexes of the living enemies within r of p.
func enemies_near(p: Vector2, r: float) -> Array:
	return horde.near(p, r)


## Every harm to an enemy goes through here so the quartermaster's damage bonus counts for hits, burns and scorching alike.
## The health it took is added to `src`, the id of the weapon or soldier type that did it, and returned.
func _harm(i: int, dmg: float, src: int) -> float:
	var full := dmg * (1.0 + bonus_amount("damage"))
	if src >= _god_src:
		full = gods.boss_cap(self, i, full)
	elif gods.frenzy_left > 0.0:
		full *= float(b.gods.mars.damage_mult)
	var taken := minf(full, maxf(horde.e_hp[i], 0.0))
	horde.e_hp[i] -= full
	if src >= 0:
		_damage[src] += taken
	return taken


## The id of a source name, or -1 when it has none.
func src_id(src: String) -> int:
	return _src_ids.get(src, -1)


## A small number rises from the enemy; the count alive is capped so a big fight stays readable.
func _number(i: int, taken: float) -> void:
	if not show_numbers or numbers.size() >= int(b.damage_numbers.cap) or taken < 0.5:
		return
	numbers.append({"pos": horde.e_pos[i] + Vector2((horde.e_id[i] * 7) % 9 - 4, -12), "v": roundi(taken), "t": 0.0})


## `from` is where a direct blow or shot came from, for a boss's shield; it is left out for harm that falls from above or burns.
func hit(i: int, dmg: float, burn_dps: float = 0.0, src := "", from := Vector2.INF) -> void:
	_number(i, _harm(i, dmg * horde.guard_mult(i, from), src_id(src)))
	if from != Vector2.INF and from != horde.e_pos[i]:
		horde.e_hit[i] = (horde.e_pos[i] - from).normalized()
	tally(0, horde.e_pos[i])
	horde.e_flash[i] = 0.1
	if burn_dps > 0.0:
		var greek: float = float(b.greek_fire.burn_mult) if rank("greek_fire") > 0 else 1.0
		ignite(i, burn_dps * greek, burn_seconds(), "fire_arrows")


## Sets an enemy alight; the burn takes its health on the next update and is counted for `src`.
func ignite(i: int, dps: float, seconds: float, src := "") -> void:
	# The hotter fire keeps its own source, so a god's capped burn is never handed to an uncapped weapon.
	if dps < horde.e_burn_dps[i] and horde.e_burn[i] > 0.0:
		return
	horde.e_burn[i] = maxf(horde.e_burn[i], seconds)
	horde.e_burn_dps[i] = dps
	horde.e_burn_src[i] = src_id(src)


## Harm from standing in fire: it takes health and shows the flames without lighting a new burn.
func scorch(i: int, dmg: float, src := "") -> void:
	_number(i, _harm(i, dmg * horde.guard_mult(i, Vector2.INF), src_id(src)))
	horde.e_burn[i] = maxf(horde.e_burn[i], 0.4)


## Unit u strikes the nearest enemy in reach once his cooldown is out; `rate` is attack_rate(), which the caller reads once an update.
func melee(u: Dictionary, dmg: float, reach: float, cooldown: float, dt: float, rate: float) -> void:
	u.cd -= dt * rate * u.haste
	if u.cd > 0.0:
		return
	var t := horde.nearest_edge(u.pos, reach)
	if t < 0:
		u.cd = 0.0
		return
	strike(u, horde.e_pos[t])
	hit(t, dmg * gladius_mult(false), 0.0, u.type, u.pos)
	# The overshoot carries over, so the blows keep time at any frame rate; a man with nothing in reach waits at zero and banks none.
	u.cd += cooldown
	effects.append({"kind": "slash", "pos": u.pos, "to": horde.e_pos[t], "t": 0.0})


## Times a soldier's blow or shot and turns him to its target, for his attack animation.
func strike(u: Dictionary, at: Vector2) -> void:
	u.struck_at = time
	if at != u.pos:
		u.strike_dir = (at - u.pos).normalized()


func _legion_attacks(dt: float) -> void:
	var cu: Dictionary = content.base_commander
	melee(commander, cu.damage, cu.reach, cu.cooldown, dt, attack_rate())
	legion.update(dt, self)


## A missile in flight; extra can set explode, pin, life and src.
func shoot(kind: String, from: Vector2, to: Vector2, spd: float, dmg: float, pierce: int, burn: float = 0.0, extra: Dictionary = {}) -> void:
	var dir := (to - from).normalized()
	var counted := COUNTED.find(kind)
	if counted >= 0:
		tally(counted, from)
	var shot := {"kind": kind, "pos": from + dir * 6.0, "vel": dir * spd, "dmg": dmg, "pierce": pierce,
		"burn": burn, "life": 1.4, "hit": {}, "explode": 0.0, "pin": 0.0, "src": kind}
	shot.merge(extra, true)
	shots.append(shot)


func _move_shots(dt: float) -> void:
	if shots.is_empty():
		return
	var keep: Array = []
	# Every enemy near every shot is checked, so the horde's arrays are read into locals once; e_hp is read through the horde, since hit() writes it.
	var gs := horde.g_start
	var gi := horde.g_items
	var ids := horde.e_id
	var kinds := horde.e_kind
	var radius := horde.k_radius
	var at := horde.e_pos
	for s in shots:
		var pos: Vector2 = s.pos + s.vel * dt
		s.pos = pos
		s.life -= dt
		var c := _cidx(pos)
		var spent := c < 0
		var struck: Dictionary = s.hit
		var kx := c % GW
		var ky := c / GW
		var x0 := maxi(0, kx - 1)
		var x1 := mini(GW, kx + 2)
		for cy in range(maxi(0, ky - 1), mini(GW, ky + 2)):
			if spent:
				break
			# The cells of a row follow one another in the sorted grid, so the three are read as one run.
			for t in range(gs[x0 + cy * GW], gs[x1 + cy * GW]):
				var j := gi[t]
				var r := radius[kinds[j]] + 3.0
				if (at[j] - pos).length_squared() >= r * r or struck.has(ids[j]) or horde.e_hp[j] <= 0.0:
					continue
				# A cataphract's scale armour turns part of every arrow.
				var armour: float = horde.k_armour[kinds[j]] if s.kind == "arrow" else 0.0
				hit(j, s.dmg * (1.0 - armour), s.burn, s.src, pos - s.vel.normalized() * 30.0)
				if s.pin > 0.0:
					horde.e_stun[j] = maxf(horde.e_stun[j], s.pin)
				struck[ids[j]] = true
				s.pierce -= 1
				if s.pierce < 0:
					spent = true
					break
		if not spent and s.life > 0.0:
			keep.append(s)
		elif s.explode > 0.0:
			_explode(s.pos, s.explode, s.dmg, s.src)
	shots = keep


func _explode(p: Vector2, radius: float, dmg: float, src: String) -> void:
	for j in enemies_near(p, radius):
		hit(j, dmg, 0.0, src)
		if horde.e_pos[j] != p:
			horde.e_hit[j] = (horde.e_pos[j] - p).normalized()
	effects.append({"kind": "boom", "pos": p, "t": 0.0, "radius": radius})


func _burns(dt: float) -> void:
	for i in horde.e_pos.size():
		if horde.e_burn[i] > 0.0:
			horde.e_burn[i] -= dt
			_harm(i, horde.e_burn_dps[i] * dt * horde.guard_mult(i, Vector2.INF), horde.e_burn_src[i])
			if horde.e_burn[i] <= 0.0:
				horde.e_burn_dps[i] = 0.0
				horde.e_burn_src[i] = -1


func _remove_dead() -> void:
	var before := kills
	var i := horde.e_pos.size() - 1
	while i >= 0:
		if horde.e_hp[i] <= 0.0:
			_kill(i)
		i -= 1
	if kills > before:
		legion.veterans(kills - before, self)


func _kill(i: int) -> void:
	var id: String = horde.kind_ids[horde.e_kind[i]]
	kills += 1
	var was_full := gods.full(b)
	gods.on_kill(b)
	if not was_full and gods.full(b):
		event("godready", commander.pos)
	tally(1, horde.e_pos[i])
	killed_kinds[id] = true
	if horde.e_bare[i] == 1:
		horde.bare_kills += 1
	var pay := 0.0 if horde.e_bare[i] == 1 else float(content.enemies[id].coins) * (1.0 + float(b.drills.plunder) * rank("plunder") + bonus_amount("denarii")) * horde.level_mult("denarii_mult")
	# A fraction of a coin is paid as the same chance of one more.
	var value := int(pay) + (1 if pay > floorf(pay) and rng.randf() < pay - floorf(pay) else 0)
	var fell := _plunged.has(horde.e_id[i])
	var lip: Vector2 = _plunged.get(horde.e_id[i], Vector2.INF)
	_plunged.erase(horde.e_id[i])
	var boss := horde.e_tag[i] != Horde.ORDINARY
	# An ordinary barbarian takes his coins into the gorge; a boss shoved off the lip leaves his reward on it.
	var at := lip if lip != Vector2.INF else horde.e_pos[i]
	if value > 0 and (not fell or (boss and lip != Vector2.INF)):
		drop_coin(at, value)
	if fell:
		effects.append({"kind": "plunge", "pos": horde.e_pos[i], "t": 0.0, "type": id, "facing": horde.e_face[i], "big": boss})
	else:
		_death(i, id)
	if horde.e_tag[i] == Horde.ELITE:
		horde.drop_chest(at)
	if horde.e_id[i] == horde.chieftain_id:
		# His death opens the fort, and holding it wins the run.
		if not victory:
			_chief_falls(i)
	horde.remove_at(i)


## Holding the fort once the chieftain has fallen wins the run; an endless run keeps going and counts the win once.
func win(pos: Vector2) -> void:
	victory = true
	event("victory", pos)
	event("triumph", commander.pos)
	event("fanfare", commander.pos)
	objectives.fort_reached = true
	moving = false
	commander.moving = false
	triumph_left = float(b.triumph.seconds)
	triumph_t = 0.0
	_clear_at = -1.0
	horde.stand_down()
	if endless and endless_since < 0.0:
		endless_since = time


## The triumph after a win: a wave out from the commander kills every barbarian, every coin flies to him, and the clock stands still.
func _triumph(dt: float) -> void:
	var cfg: Dictionary = b.triumph
	triumph_t += dt
	var reach := triumph_t * float(cfg.wave_speed)
	var before := kills
	var i := horde.e_pos.size() - 1
	while i >= 0:
		if horde.e_pos[i].distance_to(commander.pos) <= reach:
			_plunged.erase(horde.e_id[i])
			_kill(i)
		i -= 1
	if kills > before:
		legion.veterans(kills - before, self)
	# Men still filing into the fort, and riders called back from a charge, walk on to their places while the rest cheer.
	for so in soldiers:
		so.sortie = 0
	legion.follow(dt, self)
	var settled := true
	for so in soldiers:
		so.pos = terrain.push_out(so.pos, UNIT_RADIUS)
		settled = settled and so.pos.distance_to(so.target) <= 4.0
	c_pull.fill(1)
	_coins(dt, float(cfg.coin_speed))
	_effects(dt)
	_float_numbers(dt)
	_flush_events()
	if horde.e_pos.is_empty() and c_pos.is_empty() and settled:
		if _clear_at < 0.0:
			_clear_at = triumph_t
	else:
		_clear_at = -1.0
	var end := maxf(float(cfg.seconds), _clear_at + float(cfg.linger)) if _clear_at >= 0.0 else float(cfg.most_seconds)
	triumph_left = minf(end, float(cfg.most_seconds)) - triumph_t
	if triumph_left <= 0.0 and not endless:
		over = true


## The denarii the run banks: those carried and the purses of the objectives done.
func banked_denarii() -> int:
	return denarii + objectives.purse


## Leaves a coin on the field. Past the cap, the oldest coins still lying there are merged into one of their total value.
func drop_coin(pos: Vector2, value: int) -> void:
	c_pos.append(pos)
	c_val.append(value)
	c_pull.append(0)
	c_born.append(time)
	if c_pos.size() <= int(b.max_coins):
		return
	var lying: Array = []
	for i in c_pos.size():
		if c_pull[i] == 0:
			lying.append(i)
	lying.sort_custom(func(x: int, y: int) -> bool: return c_born[x] < c_born[y])
	var merge := lying.slice(0, int(b.coin_merge))
	if merge.size() < 2:
		return
	var total := 0
	for i in merge:
		total += c_val[i]
	var keep: int = merge[0]
	c_val[keep] = total
	merge.remove_at(0)
	# Removing from the highest index down keeps the lower indices valid.
	merge.sort()
	for k in range(merge.size() - 1, -1, -1):
		var i: int = merge[k]
		var last := c_pos.size() - 1
		c_pos[i] = c_pos[last]
		c_val[i] = c_val[last]
		c_pull[i] = c_pull[last]
		c_born[i] = c_born[last]
		c_pos.resize(last)
		c_val.resize(last)
		c_pull.resize(last)
		c_born.resize(last)


func _coins(dt: float, pull_speed := 220.0) -> void:
	var r2 := pickup_radius() * pickup_radius()
	var far := legion_reach + pickup_radius()
	var far2 := far * far
	var i := c_pos.size() - 1
	while i >= 0:
		var to: Vector2 = commander.pos - c_pos[i]
		if c_pull[i] == 0 and (to.length_squared() < r2 or (to.length_squared() < far2 and _unit_near(c_pos[i], r2))):
			c_pull[i] = 1
		if c_pull[i] == 1:
			var d := to.length()
			if d < 6.0:
				tally(2, commander.pos)
				gain(c_val[i])
				var last := c_pos.size() - 1
				c_pos[i] = c_pos[last]
				c_val[i] = c_val[last]
				c_pull[i] = c_pull[last]
				c_born[i] = c_born[last]
				c_pos.resize(last)
				c_val.resize(last)
				c_pull.resize(last)
				c_born.resize(last)
			else:
				c_pos[i] += to / d * minf(d, pull_speed * dt)
		i -= 1


## Whether any soldier stands within the pickup radius of p, so the whole legion gathers coins for the commander.
func _unit_near(p: Vector2, r2: float) -> bool:
	var k := _cell(p)
	var span := ceili(sqrt(r2) / CELL)
	if ug_all_in:
		var gw := Horde.GW
		var kx := k.x - horde.g_origin.x
		var ky := k.y - horde.g_origin.y
		for cx in range(maxi(0, kx - span), mini(gw, kx + span + 1)):
			for cy in range(maxi(0, ky - span), mini(gw, ky + span + 1)):
				var cell := cx + cy * gw
				var ui := ug_head[cell]
				while ui >= 0:
					if (units[ui].pos - p).length_squared() < r2:
						return true
					ui = ug_next[ui]
		return false
	var cells := unit_cells()
	for cx in range(k.x - span, k.x + span + 1):
		for cy in range(k.y - span, k.y + span + 1):
			var cell: Variant = cells.get(Vector2i(cx, cy))
			if cell == null:
				continue
			for ui in cell:
				if (units[ui].pos - p).length_squared() < r2:
					return true
	return false


func gain(value: int) -> void:
	denarii += value
	# The difficulty's `xp_mult` takes back its `denarii_mult`, so Hard pays more denarii without levelling the legion faster.
	xp_carry += value * (1.0 + float(b.drills.glory) * rank("glory") + bonus_amount("experience")) * horde.level_mult("xp_mult")
	xp += int(xp_carry)
	xp_carry -= int(xp_carry)
	while xp >= xp_next:
		xp -= xp_next
		level += 1
		xp_next = xp_for(level)
		pending_levels += 1
		event("level", commander.pos)


## A barbarian topples away from the blow that killed him, spraying blood and leaving a stain, more of both for a boss.
func _death(i: int, id: String) -> void:
	var cfg: Dictionary = b.deaths
	var p := horde.e_pos[i]
	var dir := horde.e_hit[i]
	if dir == Vector2.ZERO or victory:
		dir = p - commander.pos
		dir = dir.normalized() if dir != Vector2.ZERO else Vector2.DOWN
	var tag := horde.e_tag[i]
	var bloody := blood and not victory
	var chief := tag == Horde.CHIEF
	var spray := int(b.chief_death.spray if chief else (cfg.big_spray if tag == Horde.ELITE else cfg.spray))
	var e := {"kind": "death", "pos": p, "t": 0.0, "type": id, "facing": horde.e_face[i], "big": tag != Horde.ORDINARY,
		"chief": chief, "dir": dir, "blood": bloody, "spray": spray, "seed": horde.e_id[i]}
	if chief and not bloody:
		e.dust = int(b.chief_death.dust_puffs)
	effects.append(e)
	if victory:
		return
	if tag == Horde.ELITE:
		shake = maxf(shake, float(b.shake.elite_death))
	if bloody:
		if chief:
			add_stain(p, dir, float(b.chief_death.stain), horde.e_id[i], float(b.chief_death.stain_seconds))
		else:
			add_stain(p, dir, float(cfg.big_stain) if tag == Horde.ELITE else 1.0, horde.e_id[i])


## The chieftain's fall: the battle slows and flashes white, his warriors nearby run, his purse spills and his name is written large.
func _chief_falls(i: int) -> void:
	var cfg: Dictionary = b.chief_death
	var p := horde.e_pos[i]
	chief_fallen_at = time
	slow_left = float(cfg.slow_seconds)
	shake = maxf(shake, float(cfg.shake))
	shake_pixels = int(cfg.shake_pixels)
	objectives.notice = {"kind": "chieftain", "at": time + float(cfg.banner_seconds), "seconds": 6.0}
	event("chief_drum", p)
	event("chief_fall", p)
	var r2 := float(cfg.rout_radius) * float(cfg.rout_radius)
	for j in horde.e_pos.size():
		if horde.e_tag[j] == Horde.ORDINARY and horde.e_pos[j].distance_squared_to(p) <= r2:
			horde.e_flee[j] = maxf(horde.e_flee[j], float(cfg.rout_seconds))
	var total := roundi(float(cfg.coins) * horde.level_mult("denarii_mult"))
	var n := mini(int(cfg.coin_pieces), total)
	var reach: Array = cfg.coin_reach
	for k in n:
		var at := p + Vector2.from_angle(TAU * (k + rng.randf() * 0.6) / n) * rng.randf_range(float(reach[0]), float(reach[1]))
		drop_coin(at, total / n + (1 if k < total % n else 0))


## The time step the run takes for `real_dt` seconds of play: slowed for a moment after the chieftain falls.
func slowed(real_dt: float) -> float:
	if slow_left <= 0.0:
		return real_dt
	slow_left = maxf(0.0, slow_left - real_dt)
	return real_dt * float(b.chief_death.slow_rate)


## How white the field is flashed just after the chieftain falls, from 0 to 1, on the real clock of the slow motion.
func flash() -> float:
	var cfg: Dictionary = b.chief_death
	if slow_left <= 0.0:
		return 0.0
	var since := float(cfg.slow_seconds) - slow_left
	return clampf(1.0 - since / float(cfg.flash_seconds), 0.0, 1.0)


## Lays a stain on the ground unless it would hang over a gorge or canal, writing over the oldest once the cap is reached.
func add_stain(p: Vector2, dir: Vector2, size: float, seed_n: int, lasts := 0.0) -> void:
	var cfg: Dictionary = b.deaths
	if terrain.over_ravine(p, -float(cfg.stain_clear) * size):
		return
	var spans: Array = cfg.stain_seconds
	var life := lasts if lasts > 0.0 else lerpf(float(spans[0]), float(spans[1]), float(posmod(seed_n * 7919, 1000)) / 999.0)
	var at := p.round()
	if stain_pos.size() < int(cfg.stain_cap):
		stain_pos.append(at)
		stain_dir.append(dir)
		stain_born.append(time)
		stain_life.append(life)
		stain_size.append(size)
		stain_seed.append(seed_n)
		return
	var k := _stain_next
	# A stain meant to outlast the ordinary ones, such as the chieftain's, is stepped over while it lasts.
	for tries in stain_pos.size():
		if stain_life[k] <= float(spans[1]) or time - stain_born[k] >= stain_life[k]:
			break
		k = (k + 1) % stain_pos.size()
	_stain_next = (k + 1) % stain_pos.size()
	stain_pos[k] = at
	stain_dir[k] = dir
	stain_born[k] = time
	stain_life[k] = life
	stain_size[k] = size
	stain_seed[k] = seed_n


## How many stains are still on the ground.
func stains_alive() -> int:
	var n := 0
	for k in stain_pos.size():
		if time - stain_born[k] < stain_life[k]:
			n += 1
	return n


func _effects(dt: float) -> void:
	var keep: Array = []
	var dying := float(b.deaths.seconds)
	var big_dying := float(b.deaths.big_seconds)
	for e in effects:
		e.t += dt
		var last := 0.12 if e.kind == "slash" else (PLUNGE_SECONDS if e.kind == "plunge" else 0.45)
		if e.kind == "death" or e.kind == "fallen":
			last = float(b.chief_death.fall_seconds) if e.get("chief", false) else (big_dying if e.get("big", false) else dying)
		if e.t < last:
			keep.append(e)
	effects = keep
	_float_numbers(dt)
	for u in [commander] + soldiers:
		if u.flash > 0.0:
			u.flash -= dt


func _float_numbers(dt: float) -> void:
	if numbers.is_empty():
		return
	var keep: Array = []
	for n in numbers:
		n.t += dt
		if n.t < float(b.damage_numbers.seconds):
			keep.append(n)
	numbers = keep


func _regen(dt: float) -> void:
	# The commander slowly recovers on his own, so stray axes wear him down only while the fighting is thick.
	if commander.hp > 0.0:
		commander.hp = minf(commander.max_hp, commander.hp + float(b.get("commander_regen", 0.0)) * dt)
	var r := float(b.drills.rations) * rank("rations")
	var own := bonus_amount("regeneration")
	if r <= 0.0 and own <= 0.0:
		return
	if r > 0.0 and commander.hp > 0.0:
		commander.hp = minf(commander.max_hp, commander.hp + r * dt)
	for u in soldiers:
		u.hp = minf(u.max_hp, u.hp + (r + own) * dt)


## Decimatio: every so often one soldier in ten, chosen by lot, is taken from the legion, at least one once it has ten.
func _decimate() -> void:
	if not decimatio or time < decimate_next:
		return
	decimate_next += float(b.decimatio.every)
	var n := soldiers.size()
	var lose := n / int(b.decimatio.one_in)
	for i in lose:
		var k := rng.randi_range(0, soldiers.size() - 1)
		var gone: Dictionary = soldiers[k]
		soldiers.remove_at(k)
		effects.append({"kind": "fallen", "pos": gone.pos, "t": 0.0, "type": gone.type, "facing": gone.facing})


## Seconds the legion has lasted since the chieftain fell in an endless run.
func endless_seconds() -> float:
	return maxf(0.0, time - endless_since) if endless_since >= 0.0 else 0.0


func chieftain_index() -> int:
	return horde.chieftain_index()


static func dir_name(v: Vector2) -> String:
	return DIRS[dir_index(v)]


## The index in DIRS of the direction v points.
static func dir_index(v: Vector2) -> int:
	return posmod(roundi(v.angle() / (PI / 4.0)), 8)
