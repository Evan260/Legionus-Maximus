extends Node
## The trailer's staging on top of the game's own look flags: main.gd adds this node with --trailer-shot=NAME, and
## tools/trailer/make_trailer.py passes each shot's look flags beside it. Nothing is saved, the game's music is left
## out for the edit's, the legion never falls, and level-ups are taken out of sight unless the shot shows the choice.
##   --men=N        start with N more soldiers in the trailer's mix of recruits, or --men=N:KIND all of one kind
##   --mortal       let the legion take harm as in a real run
##   --hud=L,S,K    show the top bar as a run at level L, S seconds in with K kills would, counting on from there
##   --zoom=Z       draw the field Z times larger round the commander, with the interface at its own size
##   --march=X,Y    keep the legion marching that way, at that share of its full pace

const MIX := ["legionary", "legionary", "archer"]
## How far down the end card's field is moved, in game pixels, so the legion stands below the logo.
const END_DROP := 75.0
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
## The gods' shot: when Jupiter is picked out and when he is called, in seconds from the start. The edit cuts to the
## lightning before the call, so the call only keeps the choice open to the end of the recording.
const GOD_PICK_AT := 2.0
const GOD_CALL_AT := 7.0
## When the chieftain falls in his shot, in seconds, so he is seen in the fight first.
const CHIEF_FALLS_AT := 2.2
## How fast the legion marches along the ravine's lip once the berserker has gone over, as a share of its full pace.
const LIP_MARCH := 0.6

var main: Node
var shot := ""
var _clock := 0.0
var _levelled := false
var _turned := false
var _zoom := 1.0
## The top bar's level, seconds and kills from --hud, and the run's own at the start, which they count on from.
var _hud := PackedStringArray()
var _from := Vector3.ZERO


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
	var sim: Sim = main.sim
	if sim == null:
		return
	var men := str(main.args.get("men", "0")).split(":")
	for i in int(men[0]):
		sim.add_soldier(men[1] if men.size() > 1 else MIX[i % MIX.size()])
	sim.legion.place_all(sim.facing_angle)
	# Damage numbers would cover the fighting at trailer size.
	sim.show_numbers = false
	sim.blood = true
	_zoom = float(main.args.get("zoom", "1"))
	if main.args.has("hud"):
		_hud = str(main.args.hud).split(",")
	if has_method("_shot_" + shot):
		call("_shot_" + shot, sim)
	if main.args.has("march"):
		var way := str(main.args.march).split(",")
		main.look_march = Vector2(float(way[0]), float(way[1]))
	_from = Vector3(sim.level, sim.time, sim.kills)


func _process(dt: float) -> void:
	_clock += dt
	Steamworks.queue.clear()
	var sim: Sim = main.sim
	if sim == null:
		return
	if _zoom != 1.0:
		# The field is drawn larger round the middle of the view, which the commander stands at.
		var world: Node2D = main.world
		var middle := get_viewport().get_visible_rect().size / 2.0
		world.scale = Vector2(_zoom, _zoom)
		world.position = ((world.position - middle) * _zoom + middle).round()
	if shot == "levelup":
		_level_up(sim)
	if main.state == "pray":
		_pray()
	if not main.state in ["play", "choose"] or (shot == "levelup" and main.state == "choose"):
		return
	while sim.pending_levels > 0:
		Upgrades.apply(sim, Upgrades.offers(sim)[0])
	sim.free_choices = 0
	main.state = "play"
	if not main.args.has("mortal"):
		sim.commander.hp = sim.commander.max_hp
		for s in sim.soldiers:
			s.hp = s.max_hp
	if shot == "endcard":
		main.world.position.y += END_DROP
	if shot == "whirl" and _whirling(sim):
		main.look_march = Vector2(-1.0, 0.15)
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
	_wave(sim, sim.commander.pos, 0.0, 1.6, 70.0, 150.0, 16)


## The skirmish again, with a level-up in the middle of it; --hold-choice keeps main.gd from taking the first card.
func _shot_levelup(sim: Sim) -> void:
	main.args["hold-choice"] = ""
	_shot_skirmish(sim)


## A block of archers looses at a band charging from the right, so the arrows fly the whole gap.
func _shot_archers(sim: Sim) -> void:
	_quiet(sim)
	_wave(sim, sim.commander.pos, 0.0, 0.9, 170.0, 300.0, 18)


## A legion of forty ringed by a medium crowd, from every side.
func _shot_hold(sim: Sim) -> void:
	_quiet(sim)
	_wave(sim, sim.commander.pos, 0.0, TAU, 150.0, 330.0, 140)


## The legion on a cleared meadow meets a band coming on from the right, for a close look at its armour and cloth.
func _shot_livery(sim: Sim) -> void:
	sim.terrain.clear()
	_quiet(sim)
	_wave(sim, sim.commander.pos, 0.0, 1.4, 90.0, 170.0, 14)


## The chieftain fights in the thick of a crowd for a moment, then falls.
func _shot_chief(sim: Sim) -> void:
	_quiet(sim)
	_wave(sim, sim.commander.pos, 0.0, TAU, 140.0, 300.0, 90)
	main.slay_at = main.clock + CHIEF_FALLS_AT


## The berserker waits at the ravine's lip while the legion, set back from it, marches up and shoves him over.
func _shot_ravine(sim: Sim) -> void:
	var ahead := Vector2.from_angle(sim.facing_angle)
	sim.commander.pos -= ahead * 120.0
	sim.legion.place_all(sim.facing_angle)
	sim.terrain.refresh(sim.commander.pos)


## The berserker stands at the edge of a small legion; when his whirlwind's ring shows, the legion marches out of it.
func _shot_whirl(sim: Sim) -> void:
	_quiet(sim)
	var h := sim.horde
	var i := h.e_pos.size() - 1
	if i >= 0:
		h.e_pos[i] = sim.commander.pos + Vector2(62, 10)
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
		var view := Rect2(at - Vector2(320.0, 180.0 + END_DROP), Vector2(640.0, 360.0))
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
