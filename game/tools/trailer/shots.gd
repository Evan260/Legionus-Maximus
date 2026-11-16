extends Node
## The trailer's staging on top of the game's own look flags: main.gd adds this node with --trailer-shot=NAME, and
## tools/trailer/make_trailer.py passes each shot's look flags beside it. Nothing is saved, the game's music is left
## out for the edit's, the legion never falls, and level-ups are taken out of sight so no choice panel flashes up.
##   --men=N        start with N more soldiers in the trailer's mix of recruits, or --men=N:KIND all of one kind
##   --mortal       let the legion take harm as in a real run

const MIX := ["legionary", "legionary", "archer"]
## The hook: the commander stands alone for this long, then this many men join him each second until the legion is full.
const ALONE_SECONDS := 2.0
const JOIN_PER_SECOND := 16.0

var main: Node
var shot := ""
var _clock := 0.0
var _joined := 0.0


func _ready() -> void:
	main = get_parent()
	shot = str(main.args.get("trailer-shot", ""))
	# This node runs after main.gd each frame, so a choice panel main has just opened is closed before it is drawn.
	process_priority = 10
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), true)
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
	if sim == null or not main.state in ["play", "choose"]:
		return
	while sim.pending_levels > 0:
		Upgrades.apply(sim, Upgrades.offers(sim)[0])
	sim.free_choices = 0
	main.state = "play"
	if not main.args.has("mortal"):
		sim.commander.hp = sim.commander.max_hp
		for s in sim.soldiers:
			s.hp = s.max_hp
	if shot == "grow" and _clock > ALONE_SECONDS:
		_joined += JOIN_PER_SECOND * dt
		while _joined >= 1.0 and sim.soldiers.size() < sim.legion.cap:
			_joined -= 1.0
			sim.add_soldier(MIX[sim.soldiers.size() % MIX.size()])


# Shots -------------------------------------------------------------------

## The commander alone on the march, before a single man has joined him.
func _shot_grow(sim: Sim) -> void:
	sim.soldiers.clear()
	sim.horde.next_band = 1e9
	main.look_march = Vector2(0.6, 0.0)


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


## A wave of barbarians comes on from the right at a standing block of archers, so the arrows fly the whole gap.
func _shot_arrows(sim: Sim) -> void:
	sim.horde.next_band = 1e9
	main.look_march = Vector2.ZERO
	_wave(sim, sim.commander.pos, 0.0, 1.3, 230.0, 420.0, 220)


## The berserker waits at the ravine's lip while the legion, set back from it, marches up and shoves him over.
func _shot_ravine(sim: Sim) -> void:
	var ahead := Vector2.from_angle(sim.facing_angle)
	sim.commander.pos -= ahead * 120.0
	sim.legion.place_all(sim.facing_angle)
	sim.terrain.refresh(sim.commander.pos)


## The chieftain stands off to the side and charges at once, through the ranks.
func _shot_charge(sim: Sim) -> void:
	var h := sim.horde
	var ci := h.e_id.find(h.chieftain_id)
	if ci >= 0:
		sim.update(1.0 / 30.0, Vector2.ZERO, false)
		h.e_pos[ci] = sim.commander.pos + Vector2(1.0, -0.35).normalized() * (sim.legion_reach + 30.0)
	h.charge_cd = 0.8
	main.look_march = Vector2.ZERO


## The fort ringed by a horde pressing at its walls.
func _shot_fort(sim: Sim) -> void:
	var centre: Vector2 = sim.objectives.fort.centre
	_wave(sim, centre, 0.0, TAU, float(main.balance.fort.half) + 60.0, float(main.balance.fort.half) + 320.0, 400)
	main.look_march = Vector2.ZERO


## A legion in the wheat with no one about and no interface over it, behind the end card.
func _shot_endcard(sim: Sim) -> void:
	main.hud.visible = false
	main.look_march = Vector2(0.3, 0.0)
	sim.horde.next_band = 1e9
	sim.horde.spawn_acc = -1e9


## Spawns a band of the province's ordinary barbarians over an arc round a point, between two distances.
func _wave(sim: Sim, at: Vector2, angle: float, spread: float, near: float, far: float, n: int) -> void:
	var kinds: Array = sim.horde.ordinary
	for i in n:
		var a := angle + spread * (fmod(i * 0.618034, 1.0) - 0.5)
		var r := lerpf(near, far, fmod(i * 0.381966 + 0.13, 1.0))
		sim.horde.spawn(kinds[i % kinds.size()], at + Vector2.from_angle(a) * r)
