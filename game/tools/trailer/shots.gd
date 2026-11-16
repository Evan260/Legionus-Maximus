extends Node
## The trailer's staging on top of the game's own look flags: main.gd adds this node with --trailer-shot=NAME, and
## tools/trailer/make_trailer.py passes each shot's look flags beside it. Nothing is saved, the game's music is left
## out for the edit's, the legion never falls, and level-ups are taken out of sight unless the shot shows the choice.
##   --men=N        start with N more soldiers in the trailer's mix of recruits, or --men=N:KIND all of one kind
##   --mortal       let the legion take harm as in a real run

const MIX := ["legionary", "legionary", "archer"]
## How far down the end card's field is moved, in game pixels, so the legion stands below the logo.
const END_DROP := 75.0
## The level-up shot: when the level comes, when the archers are picked out and when they are taken, in seconds.
const LEVEL_AT := 1.0
const PICK_AT := 2.0
const TAKE_AT := 3.0
## The gods' shot: when Jupiter is picked out and when he is called, in seconds from the start.
const GOD_PICK_AT := 2.2
const GOD_CALL_AT := 3.4

var main: Node
var shot := ""
var _clock := 0.0
var _levelled := false


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
	if has_method("_shot_" + shot):
		call("_shot_" + shot, sim)


func _process(dt: float) -> void:
	_clock += dt
	Steamworks.queue.clear()
	var sim: Sim = main.sim
	if sim == null:
		return
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


## A level comes in the middle of the fight, the archers are picked out on the panel and then taken.
func _level_up(sim: Sim) -> void:
	if not _levelled and _clock >= LEVEL_AT:
		_levelled = true
		sim.gain(sim.xp_next - sim.xp)
	if main.state != "choose":
		return
	if not main.choices.has("archer"):
		main.choices[1] = "archer"
	if _clock >= TAKE_AT:
		main._take(main.choices.find("archer"))
	elif _clock >= PICK_AT:
		main.selected = main.choices.find("archer")


## The choice of gods stays open, Jupiter is picked out and then called.
func _pray() -> void:
	if not main.choices.has("jupiter"):
		main.choices[0] = "jupiter"
	var i: int = main.choices.find("jupiter")
	if _clock >= GOD_CALL_AT:
		main._call_god(i)
	elif _clock >= GOD_PICK_AT:
		main.selected = i


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


## The hold again, with the choice of gods opened over it by --god=choose.
func _shot_gods(sim: Sim) -> void:
	_shot_hold(sim)


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


## A legion in the wheat with no one about and no interface over it, behind the end card.
func _shot_endcard(sim: Sim) -> void:
	main.hud.visible = false
	main.look_march = Vector2(0.3, 0.0)
	_quiet(sim)


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
