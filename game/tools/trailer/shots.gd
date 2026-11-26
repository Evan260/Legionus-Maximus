extends Node
## The trailer's staging on top of the game's own look flags: main.gd adds this node with --trailer-shot=NAME, and
## tools/trailer/make_trailer.py passes each shot's look flags beside it. Nothing is saved, the game's music is left
## out for the edit's, the legion never falls, and level-ups are taken out of sight unless the shot shows the choice.
##   --men=N        start with N more soldiers in the trailer's mix of recruits, or --men=N:KIND all of one kind
##   --mortal       let the legion take harm as in a real run
##   --hud=L,S,K    show the top bar as a run at level L, S seconds in with K kills would, counting on from there
##   --zoom=Z       draw the field Z times larger round the commander, with the interface at its own size
##   --march=X,Y    keep the legion marching that way, at that share of its full pace
##   --testudo      raise the testudo as a charging elite's warning runs out
##   --fixed        take no level-ups, so the legion keeps the men it started with
##   --back=PX, --pace=X  how far back from the ravine's lip the legion starts, and at what share of its pace it marches up
##   --aim=X,Y      move the view this far from the commander, in game pixels, to frame what he marches towards
## A recording also writes stats.jsonl beside its frames, a line per frame of the men, the commander's health, the kills,
## the barbarians in view, those that have reached the line, the gods called and the testudo, so the edit's captions can
## quote what really happened.

const MIX := ["legionary", "legionary", "archer"]
## How far down the end card's field is moved in the wide view and in the shorts' tall one, in game pixels, so the legion stands below the logo.
const END_DROP := 75.0
const END_DROP_TALL := 150.0
## How far below a wheat field the legion marches in the Gaul shot, and how far west of one it stands on the end card, in game pixels.
const FIELD_SIDE := 80.0
const END_SIDE := 170.0
## The level-up shot: the recruits offered, the one taken, and when the level comes, when it is picked out and when it is taken, in seconds.
const LEVEL_CHOICES := ["medicus", "cavalry", "ballista"]
const LEVEL_TAKE := "ballista"
const LEVEL_AT := 1.0
const PICK_AT := 1.7
const TAKE_AT := 2.4
## The provinces the map shot shows as won, so the whole road to Britannia is lit.
const MAP_WON := ["germania", "gaul", "dacia", "parthia"]
## Where the falx band leader and his band are moved to in the Dacia shot, from where --boss brings them, in game pixels.
const ONRUSH_SHIFT := Vector2(170.0, -20.0)
## When he marks his lane, in seconds from the start of the shot.
const ONRUSH_AT := 0.5
## When Jupiter is picked out and when he is called, in seconds; the edit cuts to the lightning before the call.
const GOD_PICK_AT := 2.0
const GOD_CALL_AT := 7.0
## When the chieftain falls in his shot, in seconds, so he is seen in the fight first.
const CHIEF_FALLS_AT := 2.2
## How fast the legion marches along the ravine's lip once the berserker has gone over, as a share of its full pace.
const LIP_MARCH := 0.6
## The great horde's shots, the gap between its barbarians, the open ground left round the commander and how far it reaches
## past the edges of the view, in game pixels.
const HORDE_SHOTS := ["hook", "gods", "reveal", "storm"]
const HORDE_STEP := 28.0
const HORDE_CLEAR := 110.0
const HORDE_BEYOND := Vector2(60.0, 50.0)
## Where the war elephant is moved to in the shorts' charge, from the commander, in game pixels.
const ELEPHANT_FROM := Vector2(10.0, -215.0)
## Seconds of the elephant's warning left when --testudo raises the shields, as a player who saw the lane would.
const TESTUDO_LEAD := 0.6
## The archers' short: the band charging them, how many and between which distances, in game pixels.
const VOLLEY_BAND := 60
const VOLLEY_NEAR := 230.0
const VOLLEY_FAR := 420.0
## The close call: the crowd ringing the small legion, and the men left when Apollo is called.
const CLOSE_CROWD := 70
const CLOSE_LEFT := 3
## Seconds between the legion falling to its last men and Apollo's call, as long as a player takes to see it and call him.
const CLOSE_WAIT := 1.0
## How near a barbarian comes to a soldier, in game pixels, to count as having reached the line.
const REACH := 14.0
## How many barbarians walk in from beyond the edges each frame at most, to make up for the fallen.
const HORDE_INFLOW := 8
## Where the chieftain comes from in his shot and how far in front of the legion's ranks he starts, in game pixels.
const CHIEF_FROM := Vector2(1.0, 0.3)
const CHIEF_AHEAD := 60.0
## On a phone the gods' shot taps the laurel, Jupiter's card and Call at these seconds; the edit cuts away after the last.
const GOD_TAPS := [0.85, GOD_PICK_AT, 2.7]
## The touch index the staged taps light a button with, apart from any finger the game itself follows.
const TAP_FINGER := 9

var main: Node
var shot := ""
var _clock := 0.0
var _levelled := false
var _turned := false
var _zoom := 1.0
var _march := Vector2.ZERO
var _horde_size := 0
var _rng := RandomNumberGenerator.new()
## The top bar's level, seconds and kills from --hud, and the run's own at the start, which they count on from.
var _hud := PackedStringArray()
var _from := Vector3.ZERO
## A recording with the phone's interface shows its controls as a player works them: a thumb on the stick and each tap.
var _touch := false
var _tip: Sprite2D
var _ring: Sprite2D
## The ring spreading from a tap, one picture for each whole pixel it grows.
var _ripples: Array[Texture2D] = []
var _fade: Tween
var _shielded := false
var _god_taps := 0
var _raised := false
var _prayed := false
var _low_at := -1.0
var _aim := Vector2.ZERO
## The barbarians, by id, that have come within REACH of a soldier.
var _reached := {}
var _stats: FileAccess


func _init() -> void:
	name = "TrailerShots"


func hud_shown() -> bool:
	return _hud.size() == 3


func zoomed() -> bool:
	return _zoom != 1.0


func level(sim: Sim) -> int:
	return int(_hud[0]) + sim.level - int(_from.x)


func seconds(sim: Sim) -> float:
	return float(_hud[1]) + sim.time - _from.y


func kills(sim: Sim) -> int:
	return int(_hud[2]) + sim.kills - int(_from.z)


func _ready() -> void:
	main = get_parent()
	shot = str(main.args.get("trailer-shot", ""))
	# A store picture shows the game alone, so only a recording shows the thumb and the taps.
	_touch = Touch.phone and Engine.get_write_movie_path() != ""
	if _touch:
		_build_touch()
	# This node runs after main.gd each frame, so a choice panel main has just opened is closed before it is drawn.
	process_priority = 10
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), true)
	# The trailer shows the field without the interface, and the map without its panel and key hints.
	var hud: Node2D = main.hud
	hud.set_script(load("res://tools/trailer/trailer_hud.gd"))
	hud.main = main
	hud.ui = main.ui
	main.screens["map"] = load("res://tools/trailer/trailer_map.gd").new(main)
	if shot == "map":
		for p in MAP_WON:
			Profile.data.records[p] = {"best_time": 1100.0, "longest": 1200.0, "won": true, "hard_won": false}
		Profile.open_won_provinces(main.content)
	# A legion that marches without fighting is hunted by extra beasts, which would swamp the marching shots.
	if main.balance.has("pursuit"):
		main.balance.pursuit.cap = 0.0
	# The gods strike what is on screen, so a tall view is struck from top to bottom.
	var half := _view() / 2.0
	main.balance.gods.view_half = [half.x + 10.0, half.y + 10.0]
	var sim: Sim = main.sim
	if sim == null:
		return
	if Engine.get_write_movie_path() != "":
		_stats = FileAccess.open(Engine.get_write_movie_path().get_base_dir().path_join("stats.jsonl"), FileAccess.WRITE)
	var men := str(main.args.get("men", "0")).split(":")
	for i in int(men[0]):
		sim.add_soldier(men[1] if men.size() > 1 else MIX[i % MIX.size()])
	sim.legion.place_all(sim.facing_angle)
	# Damage numbers would cover the fighting at trailer size.
	sim.show_numbers = false
	sim.blood = true
	_zoom = float(main.args.get("zoom", "1"))
	if main.args.has("aim"):
		var aim := str(main.args.aim).split(",")
		_aim = Vector2(float(aim[0]), float(aim[1]))
	if main.args.has("hud"):
		_hud = str(main.args.hud).split(",")
	if main.args.has("march"):
		var way := str(main.args.march).split(",")
		_march = Vector2(float(way[0]), float(way[1]))
	_rng.seed = 7
	if shot in HORDE_SHOTS:
		_horde(sim)
	if has_method("_shot_" + shot):
		call("_shot_" + shot, sim)
	if _march != Vector2.ZERO:
		main.look_march = _march
	_from = Vector3(sim.level, sim.time, sim.kills)


func _process(dt: float) -> void:
	_clock += dt
	Steamworks.queue.clear()
	var sim: Sim = main.sim
	if sim == null:
		return
	if _stats != null:
		_stats.store_line(JSON.stringify({"t": snappedf(_clock, 0.001), "men": sim.soldiers.size(), "hp": snappedf(sim.commander.hp / sim.commander.max_hp, 0.001),
			"kills": sim.kills, "seen": _seen(sim), "reached": _reach_count(sim), "calls": sim.gods.calls, "testudo": sim.testudo_left > 0.0}))
		_stats.flush()
	if shot == "elephant" and main.args.has("testudo") and not _raised:
		_testudo_for_charge(sim)
	if shot == "close" and _low_at < 0.0 and sim.soldiers.size() <= CLOSE_LEFT:
		_low_at = _clock
	if shot == "close" and not _prayed and _low_at >= 0.0 and _clock >= _low_at + CLOSE_WAIT:
		_prayed = true
		main._look_at_god("apollo")
	if _touch and main.touch_pad != null:
		_touch_controls(sim, main.touch_pad)
	if _zoom != 1.0 or _aim != Vector2.ZERO:
		# The field is drawn larger round the middle of the view, which the commander stands at unless --aim moves it.
		var world: Node2D = main.world
		var middle := get_viewport().get_visible_rect().size / 2.0
		world.scale = Vector2(_zoom, _zoom)
		world.position = ((world.position - middle - _aim) * _zoom + middle).round()
	if shot == "levelup":
		_level_up(sim)
	if main.state == "pray":
		_pray()
	if not main.state in ["play", "choose", "supply"] or (shot == "levelup" and main.state == "choose"):
		return
	# With --fixed the legion is only what it started with, so every man lost shows and none is added.
	while sim.pending_levels > 0:
		if main.args.has("fixed"):
			sim.pending_levels = 0
		else:
			Upgrades.apply(sim, Upgrades.offers(sim)[0])
	sim.free_choices = 0
	sim.supplies.clear()
	main.state = "play"
	if not main.args.has("mortal"):
		sim.commander.hp = sim.commander.max_hp
		for s in sim.soldiers:
			s.hp = s.max_hp
	if shot == "endcard":
		main.world.position.y += END_DROP_TALL if _tall() else END_DROP
	# Once Jupiter is called the storm's horde is left to fall, so the screen it clears stays clear.
	if shot in HORDE_SHOTS and not (shot == "storm" and sim.gods.calls > 0):
		_top_up(sim)
	if shot == "whirl" and _whirling(sim):
		main.look_march = Vector2(0.15, -1.0) if _tall() else Vector2(-1.0, 0.15)
	if shot == "ravine" and not _turned and _boss_went_over(sim):
		# Once he is over, the legion wheels and marches along the lip rather than on into the edge.
		_turned = true
		main.look_march = Vector2.from_angle(sim.facing_angle).orthogonal() * LIP_MARCH


## A level comes in the middle of the fight, offering three of the newer recruits, and the ballista crew is picked out and taken.
func _level_up(sim: Sim) -> void:
	if not _levelled and _clock >= LEVEL_AT:
		_levelled = true
		sim.gain(sim.xp_next - sim.xp)
	if main.state != "choose":
		return
	if main.choices != LEVEL_CHOICES:
		main.choices = LEVEL_CHOICES.duplicate()
	if _clock >= TAKE_AT:
		main._take(main.choices.find(LEVEL_TAKE))
	elif _clock >= PICK_AT:
		main.selected = main.choices.find(LEVEL_TAKE)


## The choice of gods stays open, Jupiter is picked out and then called.
func _pray() -> void:
	if not main.choices.has("jupiter"):
		main.choices[0] = "jupiter"
	var i: int = main.choices.find("jupiter")
	if _clock >= GOD_CALL_AT:
		main._call_god(i)
	elif _clock >= GOD_PICK_AT:
		main.selected = i


## Whether a boss has been shoved into the ravine, which leaves a big body falling in it.
func _boss_went_over(sim: Sim) -> bool:
	for e in sim.effects:
		if e.kind == "plunge" and e.get("big", false):
			return true
	return false


## Whether the berserker's whirlwind is winding up, its ring on the ground.
func _whirling(sim: Sim) -> bool:
	for l in sim.horde.foe_lobs:
		if l.get("whirl", false):
			return true
	return false


# Shots -------------------------------------------------------------------

## The legion stands outside the thickest stand of trees near the start and marches into it, felling the trees it presses.
func _shot_fell(sim: Sim) -> void:
	var trees: Array = sim.terrain.props_in(Rect2(-1500, -1500, 3000, 3000)).filter(func(p): return Terrain.TREES.has(p[0]))
	var best := Vector2.ZERO
	var most := -1
	for t in trees:
		if t[1].length() < 300.0:
			continue
		var near := 0
		for u in trees:
			if t[1].distance_to(u[1]) < 70.0:
				near += 1
		if near > most:
			most = near
			best = t[1]
	var way := (best - Vector2(0, 0)).normalized()
	sim.commander.pos = best - way * 110.0
	sim.facing_angle = way.angle()
	sim.commander.facing = way
	sim.legion.place_all(sim.facing_angle)
	sim.terrain.refresh(sim.commander.pos)
	sim.horde.next_band = 1e9
	main.look_march = way * 0.5


## The commander and a handful of men stand against a small band coming on from the right, for a close look at the fight.
func _shot_skirmish(sim: Sim) -> void:
	_quiet(sim)
	_wave(sim, sim.commander.pos, _across(), 1.6, 70.0, 150.0, 16)


## The skirmish again, with a level-up in the middle of it; --hold-choice keeps main.gd from taking the first card.
func _shot_levelup(sim: Sim) -> void:
	main.args["hold-choice"] = ""
	_shot_skirmish(sim)


## A block of archers looses at a band charging from the right, so the arrows fly the whole gap.
func _shot_archers(sim: Sim) -> void:
	_quiet(sim)
	_wave(sim, sim.commander.pos, _across(), 0.9, 170.0, 300.0, 18)


## A legion of forty ringed by a medium crowd, from every side.
func _shot_hold(sim: Sim) -> void:
	_quiet(sim)
	_wave(sim, sim.commander.pos, 0.0, TAU, 150.0, 330.0, 140)


## The legion on a cleared meadow meets a band coming on from the right, for a close look at its armour and cloth.
func _shot_livery(sim: Sim) -> void:
	sim.terrain.clear()
	_quiet(sim)
	_wave(sim, sim.commander.pos, 0.0, 1.4, 90.0, 170.0, 14)


## The legion holds its line facing the chieftain, who charges in with a crowd, meets its front rank and falls there.
func _shot_chief(sim: Sim) -> void:
	_quiet(sim)
	var way := CHIEF_FROM.normalized()
	_stand(sim, sim.commander.pos, way.angle())
	_wave(sim, sim.commander.pos, way.angle(), 2.4, 150.0, 300.0, 90)
	var front := 0.0
	for s in sim.soldiers:
		front = maxf(front, (s.pos - sim.commander.pos).dot(way))
	var ci := sim.horde.chieftain_index()
	if ci >= 0:
		sim.horde.e_pos[ci] = sim.commander.pos + way * (front + CHIEF_AHEAD)
	main.slay_at = main.clock + CHIEF_FALLS_AT


## Fills the field round the legion with the province's barbarians a pace apart, on cleared ground, with the run's own stream stopped.
func _horde(sim: Sim) -> void:
	sim.terrain.clear()
	_quiet(sim)
	var c: Vector2 = sim.commander.pos
	var reach := _reach()
	var x := -reach.x
	while x <= reach.x:
		var y := -reach.y
		while y <= reach.y:
			var at := Vector2(x, y) + Vector2(_rng.randf_range(-0.4, 0.4), _rng.randf_range(-0.4, 0.4)) * HORDE_STEP
			if at.length() > HORDE_CLEAR and _rng.randf() > 0.12:
				_spawn_ordinary(sim, c + at)
			y += HORDE_STEP
		x += HORDE_STEP
	_horde_size = sim.horde.e_pos.size()


## Brings fresh barbarians in from just beyond the edges of the view as others fall, so the horde never thins out.
func _top_up(sim: Sim) -> void:
	var c: Vector2 = sim.commander.pos
	for k in mini(HORDE_INFLOW, _horde_size - sim.horde.e_pos.size()):
		var edge := Vector2(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0))
		edge = edge / maxf(absf(edge.x), absf(edge.y))
		_spawn_ordinary(sim, c + edge * _reach())


## The size of the recorded view, wide for the trailer and tall for the shorts.
func _view() -> Vector2:
	return get_viewport().get_visible_rect().size


func _tall() -> bool:
	return _view().y > _view().x


## How far the great horde reaches from the commander: just past the edges of the view.
func _reach() -> Vector2:
	return _view() / 2.0 + HORDE_BEYOND


## The angle a staged band comes on from: the right of a wide view, the top of a tall one, so it crosses the view's long side.
func _across() -> float:
	return -PI / 2.0 if _tall() else 0.0


## How many barbarians have come within REACH of a soldier so far.
func _reach_count(sim: Sim) -> int:
	var h := sim.horde
	for i in h.e_pos.size():
		if h.e_hp[i] <= 0.0 or _reached.has(h.e_id[i]):
			continue
		for u in sim.units:
			if (u.pos - h.e_pos[i]).length_squared() <= pow(REACH + h.k_radius[h.e_kind[i]], 2.0):
				_reached[h.e_id[i]] = true
				break
	return _reached.size()


## The living barbarians within the view round the camera, as the field is drawn.
func _seen(sim: Sim) -> int:
	var half := _view() / 2.0 / _zoom
	var c: Vector2 = main.world.eye() + _aim
	var h := sim.horde
	var n := 0
	for i in h.e_pos.size():
		if h.e_hp[i] > 0.0 and absf(h.e_pos[i].x - c.x) <= half.x and absf(h.e_pos[i].y - c.y) <= half.y:
			n += 1
	return n


func _spawn_ordinary(sim: Sim, at: Vector2) -> void:
	var kinds: Array = sim.horde.ordinary
	sim.horde.spawn(kinds[_rng.randi() % kinds.size()], at)


## The berserker waits at the ravine's lip while the legion, set back from it, marches up and shoves him over.
func _shot_ravine(sim: Sim) -> void:
	var ahead := Vector2.from_angle(sim.facing_angle)
	sim.commander.pos -= ahead * float(main.args.get("back", "120"))
	sim.legion.place_all(sim.facing_angle)
	sim.terrain.refresh(sim.commander.pos)
	main.look_march = ahead * float(main.args.get("pace", "0.5"))


## The berserker stands at the edge of a small legion; when his whirlwind's ring shows, the legion marches out of it.
func _shot_whirl(sim: Sim) -> void:
	_quiet(sim)
	var h := sim.horde
	var i := h.e_pos.size() - 1
	if i >= 0:
		h.e_pos[i] = sim.commander.pos + (Vector2(10, 62) if _tall() else Vector2(62, 10))
	main.look_march = Vector2.ZERO


## In Dacia's snow the falx band leader stands off to the side with his band, marks a lane through the legion and charges down it.
func _shot_onrush(sim: Sim) -> void:
	_quiet(sim)
	var h := sim.horde
	for i in h.e_pos.size():
		h.e_pos[i] += ONRUSH_SHIFT
		if h.elite_ids.has(h.e_id[i]) and h.boss_state(i).has("onrush_cd"):
			h.boss_state(i).onrush_cd = ONRUSH_AT
	# More falx warriors come on behind the charge, so the legion has a fight once it is spent.
	_wave(sim, sim.commander.pos, 0.0, 1.4, 230.0, 330.0, 16)
	main.look_march = Vector2.ZERO


## Parthia's war elephant stands above the legion, which faces him, and marks his lane straight down through its ranks.
func _shot_elephant(sim: Sim) -> void:
	_quiet(sim)
	_stand(sim, sim.commander.pos, -PI / 2.0)
	var h := sim.horde
	var i := h.e_pos.size() - 1
	if i >= 0:
		h.e_pos[i] = sim.commander.pos + ELEPHANT_FROM
	main.look_march = Vector2.ZERO


## The shields go up as the elephant's warning runs out, as they would for a player who saw his lane marked.
func _testudo_for_charge(sim: Sim) -> void:
	var h := sim.horde
	for i in h.e_pos.size():
		if not h.elite_ids.has(h.e_id[i]):
			continue
		var st := h.boss_state(i)
		if float(st.get("rush_warn", 0.0)) > 0.0 and float(st.rush_warn) <= TESTUDO_LEAD:
			_raised = true
			# What Sim.update does when the testudo key is pressed.
			sim.event("testudo", sim.commander.pos)
			sim.testudo_left = sim.testudo_hold_at(sim.rank("testudo"))
			sim.testudo_charge = 0.0
			sim.shake = maxf(sim.shake, float(sim.b.shake.testudo))
			return


## A legion of archers stands facing a big band that charges it across the view, so the arrows fly the whole way.
func _shot_volley(sim: Sim) -> void:
	sim.terrain.clear()
	_quiet(sim)
	_stand(sim, sim.commander.pos, _across())
	_wave(sim, sim.commander.pos, _across(), 1.0, VOLLEY_NEAR, VOLLEY_FAR, VOLLEY_BAND)


## A small legion ringed by a crowd takes its losses as in a real run; with --mortal, Apollo is called when it is down to its last men.
func _shot_close(sim: Sim) -> void:
	sim.terrain.clear()
	_quiet(sim)
	_wave(sim, sim.commander.pos, 0.0, TAU, 100.0, 330.0, int(main.args.get("crowd", CLOSE_CROWD)))


## The chieftain stands off to the side and charges at once, through the ranks.
func _shot_charge(sim: Sim) -> void:
	var h := sim.horde
	var ci := h.e_id.find(h.chieftain_id)
	if ci >= 0:
		sim.update(1.0 / 30.0, Vector2.ZERO, false)
		h.e_pos[ci] = sim.commander.pos + Vector2(1.0, -0.35).normalized() * (sim.legion_reach + 30.0)
	h.charge_cd = 0.8
	main.look_march = Vector2.ZERO
	_quiet(sim)


## The fort ringed by a horde pressing at its walls.
func _shot_fort(sim: Sim) -> void:
	var centre: Vector2 = sim.objectives.fort.centre
	_wave(sim, centre, 0.0, TAU, float(main.balance.fort.half) + 60.0, float(main.balance.fort.half) + 260.0, 160)
	main.look_march = Vector2.ZERO


## The legion marches west along the foot of a wheat field, on the grass between the wheat and a village.
func _shot_field(sim: Sim) -> void:
	var spot := _wheat_by_village(sim)
	if spot.is_empty():
		return
	var f: Rect2 = spot[0]
	_stand(sim, Vector2(f.end.x - 20.0, f.end.y + FIELD_SIDE), PI)
	main.look_march = Vector2(-0.5, 0.0)


## The legion stands on the grass beside a wheat field with no one about and no interface over it, behind the end card.
func _shot_endcard(sim: Sim) -> void:
	main.hud.visible = false
	_quiet(sim)
	var area := Rect2(-2500, -2500, 5000, 5000)
	var fields := sim.terrain.fields_in(area)
	fields.sort_custom(func(f: Rect2, g: Rect2) -> bool: return f.get_center().length() < g.get_center().length())
	var props := sim.terrain.props_in(area).filter(func(p: Array) -> bool: return p[2] > 0.0 or p[0] in ["roundhouse", "hedge"])
	for f: Rect2 in fields:
		var at := Vector2(f.position.x - END_SIDE, f.get_center().y)
		# The card moves the field down by END_DROP, so more of the ground above the legion is in view.
		var drop := END_DROP_TALL if _tall() else END_DROP
		var view := Rect2(at - Vector2(_view().x / 2.0, _view().y / 2.0 + drop), _view())
		if f.size.y >= 140.0 and sim.terrain.ravines_in(view).is_empty() and not props.any(func(p: Array) -> bool: return view.has_point(p[1])):
			_stand(sim, at, 0.0)
			break
	main.look_march = Vector2.ZERO


## The wheat field nearest the start with a village below it, across a strip of grass the legion can march along, as [field, a house].
func _wheat_by_village(sim: Sim) -> Array:
	var area := Rect2(-2500, -2500, 5000, 5000)
	var houses: Array = sim.terrain.props_in(area).filter(func(p: Array) -> bool: return p[0] == "roundhouse")
	var best: Array = []
	for f: Rect2 in sim.terrain.fields_in(area):
		for h in houses:
			var at: Vector2 = h[1]
			var gap := at.y - f.end.y
			if at.x > f.position.x - 40.0 and at.x < f.end.x + 40.0 and gap > 180.0 and gap < 360.0:
				if best.is_empty() or f.get_center().length() < (best[0] as Rect2).get_center().length():
					best = [f, at]
	return best


## Stands the legion at p facing `angle`.
func _stand(sim: Sim, p: Vector2, angle: float) -> void:
	sim.commander.pos = p
	sim.facing_angle = angle
	sim.commander.facing = Vector2.from_angle(angle)
	sim.legion.place_all(angle)
	sim.terrain.refresh(p)


## Stops the run's own stream of barbarians and its bands, so only the staged ones are on the field, and holds the legion still.
func _quiet(sim: Sim) -> void:
	sim.horde.next_band = 1e9
	sim.horde.spawn_acc = -1e9
	if main.look_march == Vector2.INF:
		main.look_march = Vector2.ZERO


## Spawns a band of the province's ordinary barbarians over an arc round a point, between two distances.
func _wave(sim: Sim, at: Vector2, angle: float, spread: float, near: float, far: float, n: int) -> void:
	var kinds: Array = sim.horde.ordinary
	for i in n:
		var a := angle + spread * (fmod(i * 0.618034, 1.0) - 0.5)
		var r := lerpf(near, far, fmod(i * 0.381966 + 0.13, 1.0))
		sim.horde.spawn(kinds[i % kinds.size()], at + Vector2.from_angle(a) * r)


# The phone's controls ------------------------------------------------------

func _build_touch() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)
	_ring = Sprite2D.new()
	_ring.modulate.a = 0.0
	layer.add_child(_ring)
	_tip = Sprite2D.new()
	_tip.texture = _fingertip()
	_tip.modulate.a = 0.0
	layer.add_child(_tip)
	for radius in range(6, 12):
		_ripples.append(_ripple_texture(radius))


## A thumb holds the stick the way the legion marches, the testudo is tapped as its shields go up, and the gods are called.
func _touch_controls(sim: Sim, pad: TouchPad) -> void:
	# The end card's legion stands under the logo with no controls over it.
	if shot == "endcard":
		pad.visible = false
		return
	if main.state == "play":
		var march: Vector2 = main.look_march
		if march == Vector2.INF:
			march = Vector2(cos(sim.time * 0.4), sin(sim.time * 0.4))
		var r := pad.radius()
		var view := pad.get_viewport_rect().size
		pad._stick = 0
		pad._base = Vector2(Touch.inset_tl.x + r * 1.5, view.y - Touch.inset_br.y - r * 1.9)
		pad._finger = pad._base + march.limit_length(1.0) * r * 0.75
	# A phone writes a bridge's cost at a ravine's lip, where the cliff's caption goes, and this legion builds no bridge.
	if shot == "ravine":
		sim.bridge_here = false
	var raised := sim.testudo_left > 0.0
	if raised and not _shielded:
		_tap_button(pad, "testudo")
	_shielded = raised
	if shot == "gods" and _god_taps < GOD_TAPS.size() and _clock >= float(GOD_TAPS[_god_taps]):
		_tap_god(pad, _god_taps)
		_god_taps += 1


## The laurel button, then Jupiter's card, then Call.
func _tap_god(pad: TouchPad, step: int) -> void:
	if step == 0:
		_tap_button(pad, "pray")
		return
	var hud: Hud = main.hud
	var r := Rect2()
	if step == 1:
		var i: int = main.choices.find("jupiter")
		if i >= 0 and i < hud.choice_rects.size():
			r = hud.choice_rects[i]
	else:
		r = hud.touch_buttons.get("call", Rect2())
	if r.has_area():
		_touch_down(hud.get_global_transform_with_canvas() * (Ui.offset + r.get_center()))


## A round button lit as a finger presses it, with the fingertip on it.
func _tap_button(pad: TouchPad, id: String) -> void:
	var b: Dictionary = pad.layout.get(id, {})
	if b.is_empty():
		return
	pad._held[TAP_FINGER] = id
	get_tree().create_timer(0.25).timeout.connect(func() -> void: pad._held.erase(TAP_FINGER))
	_touch_down(pad.get_global_transform_with_canvas() * Vector2(b.centre))


## A fingertip where the screen is tapped, with a ring spreading from it a pixel at a time, then both fade.
func _touch_down(at: Vector2) -> void:
	if _fade:
		_fade.kill()
	_tip.position = at.round()
	_tip.modulate.a = 1.0
	_ring.position = _tip.position
	var spread := create_tween()
	for k in _ripples.size():
		spread.tween_callback(func() -> void:
			_ring.texture = _ripples[k]
			_ring.modulate.a = 1.0 - float(k) / _ripples.size())
		spread.tween_interval(0.05)
	spread.tween_callback(func() -> void: _ring.modulate.a = 0.0)
	_fade = create_tween()
	_fade.tween_property(_tip, "modulate:a", 0.0, 0.2).set_delay(0.15)


## A fingertip pressed on the glass: a pale disc ringed in cream and then ink, so it shows on light and dark alike.
static func _fingertip() -> Texture2D:
	var img := Image.create(11, 11, false, Image.FORMAT_RGBA8)
	for y in 11:
		for x in 11:
			var d := Vector2(x - 5, y - 5).length()
			if d < 3.5:
				img.set_pixel(x, y, Color(Ui.CREAM, 0.45))
			elif d < 4.5:
				img.set_pixel(x, y, Color(Ui.CREAM, 0.95))
			elif d < 5.5:
				img.set_pixel(x, y, Color(Ui.INK, 0.6))
	return ImageTexture.create_from_image(img)


static func _ripple_texture(radius: int) -> Texture2D:
	var side := radius * 2 + 3
	var img := Image.create(side, side, false, Image.FORMAT_RGBA8)
	var middle := float(radius + 1)
	for y in side:
		for x in side:
			var d := Vector2(x - middle, y - middle).length()
			if absf(d - radius) < 0.5:
				img.set_pixel(x, y, Color(Ui.CREAM, 0.9))
			elif absf(d - radius - 1.0) < 0.5:
				img.set_pixel(x, y, Color(Ui.INK, 0.45))
	return ImageTexture.create_from_image(img)
