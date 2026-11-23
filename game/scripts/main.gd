extends Node
## Runs the game: title, the run, level-up choices, pause and the summary, plus the command-line modes used to test.
##   --run-tests        run the checks in tests/ and quit
##   --bench            time the simulation with a full horde and quit
##   --autoplay         march in circles and take the first choice, for looking at the game without playing
##   --skip=SECONDS     start the run this far in, simulated in fast steps
##   --shot=PATH        save a screenshot after --at seconds (default 3) and quit
##   --chieftain-at=S   bring the chieftain at this many seconds instead
##   --objectives-near  place the objectives close to the start, for looking at them
##   --go-to=KIND       with --autoplay, start beside the camp, column or grove, inside a fort raised at once, or burning-camp;
##                      ravine stands the legion at the lip of the nearest ravine, bridge lays a bridge there and marches onto it,
##                      ravine-end stands it just past one end of the nearest ravine
##                      fort-gate stands it south of a freshly raised fort and marches it in through the gate
##                      crowd gives it 80 men on cleared ground ringed by a full late horde
##                      village or hedge stands it beside the nearest village or hedge, in a province that has them
##                      canal stands it before the nearest canal crossing, reeds, ruin or palms beside the nearest reed bed, obelisk or date palm
##                      grass, kurgan, wagons or birches beside the nearest feather grass, kurgan, wagon circle or birch
##   --hold-choice      with --autoplay, give a level at once and leave its choices open; --select=N picks out choice N (from 0)
##   --easy, --hard     start the run at that difficulty
##   --endless, --decimatio   start the run in that mode
##   --screen=NAME      open a screen (camp, quartermaster, tablinum, map, commanders, settings, title, saves) with a sample profile, for screenshots;
##                      summary runs a skipped autoplay to its end and shows the run summary
##   --page=controls    with --screen=settings, open the key and button page; --page=delete with --screen=saves asks about deleting a game
##   --save-dir=NAME    keep the save slots and settings in user://NAME, for looking at or playing with saves that are not the player's
##   --lang=CODE        show the game in that language (fr, de, es, it, pt_BR, pl, tr, ru, uk, ja, ko, zh_CN, zh_TW) without saving it
##   --text-size=N      use text size 1 or 2 without saving it
##   --commander=ID     start with that commander (the tribune when his art is not drawn)
##   --as-demo          play as the demo: Germania, three commanders and the demo's time limit
##   --card=ID          show that achievement's card, for looking at it
##   --give=ID,ID:RANK  start the run with these arms or drills at the rank (default 1), or that many of a recruit, for looking at them
##   --timber=N         with --autoplay, start the run carrying that much timber
##   --men=N            with --autoplay, start the run with N soldiers, legionaries and archers
##   --boss=ID          with --autoplay, bring that elite or the chieftain beside the legion; --boss-act=far (stunned, off screen, for the edge badge)|edge (stunned, his feet below the screen, for a look at a big boss half in view)|die (cut down a second in, for a look at his fall)|whirl|shield|band|mend|curse|blink|rage|roar,
##                      fall (with --go-to=ravine) stands him at the lip for the legion to shove in,
##                      duel|rally|blast|flee for the Gaulish elites and siege|summon for the Gaulish king, onrush|blizzard for the Dacian elites and
##                      sweep|rockfall|leap for the Dacian king, wedge|trample for the Parthian elites and storm|elephants for the shah,
##                      scythe|skyfire|rouse for the British elites and drive|tribes|burn for the warrior queen, rouse|onrush for the Hispanic elites
##                      and ambush|feint|javelins for the shepherd general, harden|wedge for the Egyptian elites and volleys|sluice for the Egyptian general,
##                      howl for the draco bearer and lancers|fire for the Roxolani king,
##                      makes him use that ability at once
##                      and holds his others back; an ordinary enemy comes as a small group, and slash|rear|volley|rush (Gaul),
##                      chop|salvo|howl|maul (Dacia), kite|lance|thrust|sling (Parthia), cry|stones|tend|pass (Britannia), slash|sling|kite (Hispania), thrust|volley|sprint|rush (Aegyptus) or lance|volley|lasso (Sarmatia) has them use theirs
##   --province=ID      start the run in that province, for looking at it
##   --god=ID           with --autoplay, call that god at --god-at seconds (default 2) of the look; --god=choose fills the favour and holds the choice open
##   --seed=N           lay out the field and run from a fixed seed, so a look comes out the same every time
##   --max-state        open every province, mode and commander with a million denarii, without reading or touching the real save
##   --trailer-shot=NAME  stage a trailer shot with tools/trailer/shots.gd
##   --no-save          leave the real save unread and untouched, as every flag above also does
##   --phone            show the phone's layout and touch controls, with the mouse as a finger (--phone-insets=L,T,R,B for a camera)

var balance: Dictionary
var content: Content
var sim: Sim
var state := "title"
var choices: Array = []
var selected := 0
## The march an autoplay look holds to instead of circling, or INF.
var look_march := Vector2.INF
# With --go-to=fort-gate the look marches north until the commander stands in the middle of the fort.
var march_to_fort := false
var args := {}
var shot_at := -1.0
var clock := 0.0
var ui := Ui.new()
var screens := {}
var camp_sim: Sim
var settings_from := "title"
var swallow_input := false
var check_clock := 0.0
var opened_at := 0.0
## The profile as it stood when the run began, so the summary can list what the run unlocked.
var profile_at_start := {}
## With --win-at, the second at which an autoplay wins, for a look at the triumph.
var win_at := -1.0
var god_at := -1.0
# When the look started by --boss-act=die cuts the chieftain down, on the real clock.
var slay_at := -1.0
## The run's touch controls on a phone, or null.
var touch_pad: TouchPad = null
## When the last back gesture came, on the real clock in milliseconds.
var _back_at := -100000
## Each finger on a screen by its touch index, as {from, moved, pulled, state}, so a finger lifted where it landed is a tap.
var _fingers := {}
## Whether the phone's text size has been settled, which waits for the screen's size to be known.
var _text_sized := false
const RUN_SETUP := {"province": "germania", "commander": "tribune", "difficulty": "medium", "endless": false, "decimatio": false}
var run_setup: Dictionary = RUN_SETUP.duplicate()

@onready var world: Node2D = $World
@onready var hud: Node2D = $UI/Hud


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var parts := a.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	content = Content.load_all(Content.available_art())
	Steamworks.content = content
	Profile.open_won_provinces(content)
	if args.has("max-state"):
		Profile.max_out(content)
	Lang.changed.connect(_language_changed)
	if args.has("chieftain-at"):
		balance.chieftain_at = float(args["chieftain-at"])
	if args.has("run-tests") or args.has("bench"):
		world.process_mode = Node.PROCESS_MODE_DISABLED
		hud.process_mode = Node.PROCESS_MODE_DISABLED
	if args.has("run-tests"):
		var tests: Object = load("res://tests/run_tests.gd").new()
		set_process(false)
		get_tree().quit(tests.run(balance))
		return
	if args.has("bench"):
		set_process(false)
		_bench()
		return
	_setup_input()
	world.atlas = Atlas.new()
	if args.has("livery"):
		var tiers: PackedStringArray = str(args.livery).split(",")
		world.livery_force = Vector2i(int(tiers[0]), int(tiers[1] if tiers.size() > 1 else tiers[0]))
	hud.main = self
	hud.ui = ui
	if Touch.phone:
		touch_pad = TouchPad.new()
		touch_pad.main = self
		$UI.add_child(touch_pad)
		Input.emulate_touch_from_mouse = Touch.preview
	screens = {"camp": CampScreen.new(self), "quartermaster": QuartermasterScreen.new(self), "tablinum": TablinumScreen.new(self),
		"map": MapScreen.new(self), "commanders": CommandersScreen.new(self), "title": TitleScreen.new(self), "pause": PauseScreen.new(self),
		"settings": SettingsScreen.new(self), "over": SummaryScreen.new(self), "saves": SavesScreen.new(self)}
	if args.has("text-size"):
		Profile.settings.text_size = int(args["text-size"])
	apply_settings()
	_load_run_setup()
	_new_sim()
	ui.focus = "continue"
	if args.get("screen", "") in ["summary", "victory"]:
		_sample_profile()
		_summary_shot(args.screen == "victory")
	elif args.has("screen") and screens.has(args.screen):
		_sample_profile()
		_enter_camp()
		state = args.screen
		ui.focus = ""
		if state == "settings":
			screens.settings.enter()
			screens.settings.page = args.get("page", "main")
		if state == "saves" and args.get("page", "") == "delete":
			screens.saves.confirming = maxi(1, Profile.slot)
			ui.focus = "no"
	if args.has("autoplay") or args.has("skip"):
		_start()
		if args.has("skip"):
			var target := float(args.skip)
			while sim.time < target and not sim.over:
				sim.update(1.0 / 30.0, Vector2(cos(sim.time * 0.3), sin(sim.time * 0.3)), false)
				while sim.pending_levels > 0:
					Upgrades.apply(sim, Upgrades.offers(sim)[0])
	if args.has("men") and state == "play":
		for i in int(args.men):
			sim.add_soldier("archer" if i % 3 == 1 else "legionary")
		sim.legion.place_all(sim.facing_angle)
	if args.has("go-to") and state == "play":
		_go_to(str(args["go-to"]))
	if args.has("card") and content.achievements.has(args.card):
		Steamworks.show_card(args.card)
	if args.has("hold-choice"):
		sim.gain(sim.xp_next - sim.xp)
	if args.get("screen", "") == "pause" and state == "play":
		_pause()
	if args.has("boss") and sim != null:
		_bring_boss(str(args.boss), str(args.get("boss-act", "")))
	if args.has("god"):
		god_at = float(args.get("god-at", "2"))
	if args.has("shot"):
		shot_at = float(args.get("at", "3"))
	if args.has("win-at"):
		win_at = float(args["win-at"])
	if args.has("trailer-shot"):
		add_child(load("res://tools/trailer/shots.gd").new())


## Brings a boss close beside the legion and has him use one ability at once, for a screenshot.
func _bring_boss(kind: String, act: String) -> void:
	if not content.enemies.has(kind):
		return
	var h := sim.horde
	var at: Vector2 = sim.commander.pos + (Vector2(130, 50) if act in ["curse", "blizzard", "skyfire"] else (Vector2(30, 25) if act in ["whirl", "sweep"] else (Vector2(160, 60) if act == "leap" else (Vector2(200, 40) if act in ["wedge", "trample", "scythe", "drive"] else Vector2(60, 50)))))
	if act == "far":
		at = sim.commander.pos + Vector2(700, -160)
	if kind == h.chief_kind:
		var ci := h.spawn_chieftain(at)
		if act == "die":
			slay_at = clock + 1.0
		if act == "far":
			h.e_stun[ci] = 1e9
		if act == "roar":
			h.e_hp[ci] = h.e_max[ci] * 0.5 + 1.0
		elif act == "siege" or act == "summon":
			h.siege_cd = 0.0 if act == "siege" else 1e9
			h.summon_cd = 0.0 if act == "summon" else 1e9
			h.charge_cd = 1e9
		elif act == "sweep" or act == "rockfall" or act == "leap":
			h.sweep_cd = 0.0 if act == "sweep" else 1e9
			h.rockfall_cd = 0.0 if act == "rockfall" else 1e9
			h.leap_cd = 0.0 if act == "leap" else 1e9
			# The leap belongs to his second phase, so he is brought in just below half health.
			if act == "leap":
				h.e_hp[ci] = h.e_max[ci] * 0.5 - 1.0
		elif act == "storm" or act == "elephants":
			h.storm_cd = 0.0 if act == "storm" else 1e9
			# The elephants come with his second phase, so he is brought in just below half health.
			if act == "elephants":
				h.e_hp[ci] = h.e_max[ci] * 0.5 - 1.0
		elif act == "drive" or act == "tribes" or act == "burn":
			h.drive_cd = 0.0 if act == "drive" else 1e9
			h.tribes_cd = 0.0 if act == "tribes" else 1e9
			h.burn_cd = 0.0 if act == "burn" else 1e9
			# She burns the land only in her second phase, so she is brought in just below half health.
			if act == "burn":
				h.e_hp[ci] = h.e_max[ci] * 0.5 - 1.0
		elif act == "ambush" or act == "feint" or act == "javelins":
			h.ambush_cd = 0.0 if act == "ambush" else 1e9
			h.feint_cd = 0.0 if act == "feint" else 1e9
			h.javelins_cd = 0.0 if act == "javelins" else 1e9
		elif act == "volleys" or act == "sluice":
			h.volleys_cd = 0.0 if act == "volleys" else 1e9
			h.sluice_cd = 0.0 if act == "sluice" else 1e9
		elif act == "lancers" or act == "fire":
			h.lancers_cd = 0.0 if act == "lancers" else 1e9
			h.fire_cd = 0.0 if act == "fire" else 1e9
		return
	if not content.enemies[kind].get("elite", false):
		_bring_group(kind, act)
		return
	if act == "edge":
		at = sim.commander.pos + Vector2(0, get_viewport().get_visible_rect().size.y / 2.0 + 95.0)
	var i := h.spawn(kind, at + (Vector2(-30, -20) if act == "flee" else Vector2.ZERO), true)
	if act == "edge":
		h.e_stun[i] = 1e9
	if act == "fall":
		_stand_at_lip(i)
	var st := h.boss_state(i)
	var timers := {"whirl": "whirl_cd", "shield": "shield_cd", "band": "band_cd", "mend": "mend_cd", "curse": "curse_cd", "blink": "blink_cd",
		"duel": "duel_cd", "blast": "blast_cd", "onrush": "onrush_cd", "blizzard": "blizzard_cd", "wedge": "wedge_cd", "trample": "trample_cd",
		"scythe": "scythe_cd", "skyfire": "fire_cd", "rouse": "rouse_cd", "harden": "harden_cd"}
	for key in timers.values():
		if st.has(key):
			st[key] = 1e9
	if timers.has(act) and st.has(timers[act]):
		st[timers[act]] = 0.0
	if act == "rage":
		h.e_hp[i] = h.e_max[i] * 0.45
	if act == "howl":
		h.e_cd[i] = 0.5
		for k in 6:
			h.spawn("lasso_rider" if k % 2 == 0 else "sarmatian_lancer", at + Vector2.from_angle(k * TAU / 6.0) * 70.0)
	h.rally_cd[h.e_id[i]] = 0.0 if act == "rally" else 1e9
	if act == "mend" or act == "rally" or act == "onrush" or act == "rouse" or act == "harden":
		for k in 6:
			var j := h.spawn(h.ordinary[0], at + Vector2.from_angle(k * TAU / 6.0) * 60.0)
			h.e_hp[j] = h.e_max[j] * 0.4


## Stands a boss at the ravine's lip just ahead of the legion, held still, and marches the legion into him so it shoves him in.
func _stand_at_lip(i: int) -> void:
	var h := sim.horde
	var ahead := Vector2.from_angle(sim.facing_angle)
	var r: float = h.k_radius[h.e_kind[i]]
	h.e_pos[i] = sim.terrain.ravine_push(sim.commander.pos + ahead * 40.0, r, true)
	h.e_stun[i] = 1e9
	look_march = ahead * 0.5


## Brings a small group of an ordinary enemy at the distance their ability needs, ready to use it at once.
func _bring_group(kind: String, act: String) -> void:
	var h := sim.horde
	var away := {"slash": 26.0, "rear": 170.0, "volley": 150.0, "rush": 170.0, "chop": 26.0, "salvo": 150.0, "howl": 90.0, "maul": 30.0,
		"kite": 120.0, "lance": 170.0, "thrust": 30.0, "sling": 130.0, "cry": 150.0, "stones": 190.0, "tend": 120.0, "pass": 220.0, "sprint": 140.0, "lasso": 70.0}
	var r: float = away.get(act, 90.0)
	var ahead := Vector2.from_angle(sim.facing_angle)
	for k in 4:
		var j := h.spawn(kind, sim.commander.pos + ahead.rotated((k - 1.5) * 0.35) * r)
		h.e_cd[j] = 0.0
	if act == "salvo" or act == "stones":
		h.salvo_cd = 0.4
	if act == "tend":
		for k in 6:
			var j := h.spawn(h.ordinary[0], sim.commander.pos + ahead.rotated((k - 2.5) * 0.25) * 95.0)
			h.e_hp[j] = h.e_max[j] * 0.4


## Puts the legion just below an objective or inside a freshly raised fort, for a screenshot.
func _go_to(kind: String) -> void:
	var at := Vector2.INF
	if kind == "ravine" or kind == "bridge" or kind == "ravine-end":
		_go_to_ravine(kind == "bridge", kind == "ravine-end")
		return
	if kind == "crowd":
		_go_to_crowd()
		return
	if kind == "stream":
		var best := Vector2.INF
		for st in sim.terrain.streams_in(Rect2(-4000, -4000, 8000, 8000)):
			var mid: Vector2 = st.pieces[0].pts[st.pieces[0].pts.size() / 2]
			if mid.length() < best.length():
				best = mid
		if best == Vector2.INF:
			return
		sim.commander.pos = best + Vector2(0, -90)
		sim.legion.place_all(sim.facing_angle)
		look_march = Vector2(0, 0.6)
		return
	if kind == "village" or kind == "hedge":
		var best := Vector2.INF
		var names := ["hedge"] if kind == "hedge" else ["village", "roundhouse"]
		for pr in sim.terrain.props_in(Rect2(-3000, -3000, 6000, 6000)):
			if pr[0] in names and pr[1].length() < best.length():
				best = pr[1]
		if best == Vector2.INF:
			return
		sim.commander.pos = best + Vector2(-70, 50)
		sim.legion.place_all(sim.facing_angle)
		look_march = Vector2.ZERO
		return
	if kind == "field":
		var fields: Array = sim.terrain.fields_in(Rect2(-3000, -3000, 6000, 6000))
		if fields.is_empty():
			return
		fields.sort_custom(func(f: Rect2, g: Rect2) -> bool: return f.get_center().length() < g.get_center().length())
		sim.commander.pos = sim.terrain.out_of_fields(Vector2(fields[0].get_center().x, fields[0].end.y + 40.0).rotated(sim.terrain.field_turn), 60.0)
		sim.legion.place_all(sim.facing_angle)
		look_march = Vector2.ZERO
		return
	if kind == "canal":
		var near := {}
		for br in sim.terrain.bridges:
			if near.is_empty() or br.pos.length() < near.pos.length():
				near = br
		if near.is_empty():
			return
		sim.commander.pos = near.pos - near.dir * (near.half_len + 60.0)
		sim.facing_angle = near.dir.angle()
		sim.commander.facing = near.dir
		sim.legion.place_all(sim.facing_angle)
		look_march = Vector2.ZERO
		return
	if kind in ["circle", "bog", "terrace", "olives", "reeds", "ruin", "palms", "grass", "kurgan", "wagons", "birches"]:
		var want: String = {"circle": "stone_circle", "bog": "bog", "terrace": "stone_wall", "olives": "olive", "reeds": "papyrus", "ruin": "obelisk", "palms": "date_palm",
			"grass": "feather_grass", "kurgan": "kurgan", "wagons": "wagon", "birches": "birch"}[kind]
		var best := Vector2.INF
		for pr in sim.terrain.props_in(Rect2(-3000, -3000, 6000, 6000)):
			if pr[0] == want and pr[1].length() < best.length():
				best = pr[1]
		if best == Vector2.INF:
			return
		sim.commander.pos = best + Vector2(0, {"circle": 150, "bog": 70, "terrace": 80, "olives": 90, "reeds": 50, "ruin": 110, "palms": 90, "grass": 50, "kurgan": 90, "wagons": 70, "birches": 90}[kind])
		sim.legion.place_all(sim.facing_angle)
		look_march = Vector2.ZERO
		return
	var burn := kind == "burning-camp"
	if burn:
		kind = "camp"
	if kind == "fort-gate":
		sim.objectives.raise_fort(sim)
		sim.commander.pos = sim.objectives.fort.pos + Vector2(0, 260)
		sim.facing_angle = -PI / 2.0
		sim.commander.facing = Vector2.UP
		sim.legion.place_all(sim.facing_angle)
		sim.terrain.refresh(sim.commander.pos)
		sim.horde.next_band = 1e9
		look_march = Vector2.UP
		march_to_fort = true
		return
	if kind == "fort":
		sim.objectives.raise_fort(sim)
		# The commander stands just inside the gate, where the whole fort is on screen.
		sim.commander.pos = sim.objectives.fort.centre + Vector2(0, float(sim.objectives.fort.half) * 0.5)
		sim.legion.place_all(sim.facing_angle)
		return
	for o in sim.objectives.list:
		if o.kind == kind:
			at = o.pos
	if at == Vector2.INF and kind in Objectives.KINDS:
		at = sim.objectives.add(sim, kind, Vector2(0, -700)).pos
	if at == Vector2.INF:
		return
	sim.commander.pos = at + Vector2(0, 110)
	if burn:
		sim.commander.pos = at + Vector2(0, 30)
	sim.legion.place_all(sim.facing_angle)


## Gives the legion 80 men on cleared ground and rings it with a full late horde, which presses it from every side.
func _go_to_crowd() -> void:
	sim.terrain.clear()
	for i in 80:
		sim.add_soldier("archer" if i % 3 == 1 else "legionary")
	sim.legion.place_all(sim.facing_angle)
	sim.commander.max_hp *= 20.0
	sim.commander.hp = sim.commander.max_hp
	var kinds := ["barbarian_club", "barbarian_spear", "barbarian_club", "wolf", "barbarian_club"]
	for i in int(balance.max_enemies):
		sim.horde.spawn(kinds[i % kinds.size()], sim.commander.pos + Vector2.from_angle(i * 2.39996) * (200.0 + 500.0 * fmod(i * 0.618034, 1.0)))
	sim.horde.next_band = 1e9
	look_march = Vector2.ZERO


## Stands the legion at the lip of the ravine nearest the start, facing across; with `bridge` it lays a bridge and marches onto it.
func _go_to_ravine(bridge: bool, at_end := false) -> void:
	var list: Array = sim.terrain.ravines_in(Rect2(-4000, -4000, 8000, 8000))
	if list.is_empty():
		return
	list.sort_custom(func(a: Dictionary, z: Dictionary) -> bool: return a.box.get_center().length() < z.box.get_center().length())
	var piece: Dictionary = list[0].pieces[0]
	if at_end:
		var tip: Vector2 = piece.pts[0]
		var back: Vector2 = (piece.pts[0] - piece.pts[6]).normalized()
		sim.commander.pos = tip + back * 70.0 + back.orthogonal() * 40.0
		sim.legion.place_all(sim.facing_angle)
		sim.terrain.refresh(sim.commander.pos)
		sim.horde.next_band = 1e9
		look_march = Vector2.ZERO
		return
	var i: int = piece.pts.size() / 2
	var along: Vector2 = (piece.pts[i + 1] - piece.pts[i - 1]).normalized()
	var out := along.orthogonal()
	sim.commander.pos = piece.pts[i] + out * (piece.half[i] + 40.0)
	sim.facing_angle = (-out).angle()
	sim.commander.facing = -out
	sim.legion.place_all(sim.facing_angle)
	sim.terrain.refresh(sim.commander.pos)
	sim.horde.next_band = 1e9
	if bridge:
		sim.timber = int(balance.bridge.cost)
		sim.build_bridge()
		look_march = -out * 0.6
	else:
		look_march = Vector2.ZERO


## Runs an autoplay to its end and shows the summary, for a screenshot.
## Plays a run to its end for a look at the summary; with `won`, the run is won at once and the summary opens on the victory reveal.
func _summary_shot(won := false) -> void:
	_start()
	if won:
		for i in 60 * 30:
			sim.update(1.0 / 30.0, Vector2(cos(sim.time * 0.3), sin(sim.time * 0.3)), false)
			while sim.pending_levels > 0:
				Upgrades.apply(sim, Upgrades.offers(sim)[0])
		sim.win(sim.commander.pos)
	while not sim.over:
		sim.update(1.0 / 30.0, Vector2(cos(sim.time * 0.3), sin(sim.time * 0.3)), false)
		while sim.pending_levels > 0:
			Upgrades.apply(sim, Upgrades.offers(sim)[0])
	_finish_run()


## Puts every saved setting to work: volumes, full screen, text size, damage numbers, blood and screen shake.
func apply_settings() -> void:
	var cfg := Profile.settings_of(Profile.settings)
	SettingsScreen.apply_audio(cfg)
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if cfg.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want and not Touch.phone:
		DisplayServer.window_set_mode(want)
	Ui.set_text_size(int(cfg.text_size), balance)
	world.shake_on = cfg.shake
	for s in [sim, camp_sim]:
		if s != null:
			s.show_numbers = cfg.numbers
			s.blood = cfg.blood


## The words and fonts change with the language, and the text size is drawn again in the new font.
func _language_changed() -> void:
	content.localize()
	apply_settings()


func open_settings(from: String) -> void:
	settings_from = from
	state = "settings"
	ui.focus = ""
	screens.settings.enter()


func close_settings() -> void:
	Profile.save_settings()
	state = settings_from
	ui.focus = "settings"


func go_to_camp() -> void:
	_enter_camp()


func go_to_title(focus_id := "continue") -> void:
	_new_sim()
	state = "title"
	ui.focus = focus_id


func open_saves() -> void:
	screens.saves.confirming = 0
	state = "saves"
	ui.focus = ""


## Puts the game just opened from its slot to work: its open provinces and the camp's choices as that game left them.
func use_profile() -> void:
	Profile.open_won_provinces(content)
	run_setup = RUN_SETUP.duplicate()
	_load_run_setup()
	Steamworks.sync()


func _new_sim() -> void:
	sim = Sim.new(balance, content, _run_options())
	sim.show_numbers = bool(Profile.setting("numbers"))
	sim.blood = bool(Profile.setting("blood"))
	world.sim = sim
	if args.has("autoplay") or args.has("skip"):
		sim.timber = int(args.get("timber", "0"))
		for entry in str(args.get("give", "")).split(",", false):
			var parts := entry.split(":")
			var info := content.upgrade(parts[0])
			if content.recruits.has(parts[0]):
				for n in (int(parts[1]) if parts.size() > 1 else 1):
					sim.add_soldier(parts[0])
				sim.legion.place_all(sim.facing_angle)
			elif not info.is_empty():
				sim.ranks[parts[0]] = clampi(int(parts[1]) if parts.size() > 1 else 1, 0, int(info.get("max", 0)))


## The camp's choices, the saved ones first, then anything the command line asks for.
func _load_run_setup() -> void:
	var settings: Dictionary = Profile.data.choices
	var offered := Game.commanders(content, balance)
	if content.ready("provinces", str(settings.get("province", ""))) and Profile.province_unlocked(settings.province) and Game.province_allowed(settings.province, balance):
		run_setup.province = settings.province
	if settings.get("difficulty", "") in Sim.DIFFICULTIES:
		run_setup.difficulty = settings.difficulty
	if settings.get("commander", "") in offered and Profile.commander_unlocked(settings.commander):
		run_setup.commander = settings.commander
	if args.has("commander") and args.commander in offered:
		run_setup.commander = args.commander
	for level in ["easy", "hard"]:
		if args.has(level):
			run_setup.difficulty = level
	for mode in ["endless", "decimatio"]:
		run_setup[mode] = args.has(mode)
	if args.has("province") and content.provinces.has(args.province) and Game.province_allowed(args.province, balance):
		run_setup.province = args.province


## The run's options: what was chosen in the camp and the quartermaster's ranks.
func _run_options() -> Dictionary:
	var options: Dictionary = run_setup.duplicate()
	options.profile_bonuses = Profile.bonuses()
	options.demo_seconds = Game.run_cap(balance)
	options.objectives_near = args.has("objectives-near")
	if args.has("seed"):
		options.seed = int(args.seed)
	options.ravine_tip = int(Profile.data.totals.get("ravine_tips", 0)) < int(balance.bridge.tip_runs)
	return options


## A profile with something in every screen, held in memory only, so a screenshot shows the screens filled in.
func _sample_profile() -> void:
	Profile.data = Profile.merge_saved({"denarii": 640, "ranks": {"start_health": 2, "damage": 1, "rerolls": 3, "denarii": 5},
		"records": {"germania": {"best_time": 1110.0, "longest": 1200.0, "won": true, "hard_won": false}},
		"seen": {"legionary": true, "archer": true, "pilum": true, "barbarian_club": true, "wolf": true, "berserker": true},
		"totals": {"kills": 2400, "runs": 9, "wins": 1}, "unlocked": {"commanders": ["tribune", "archer_captain"]}})
	Profile.open_won_provinces(content)


## Back to the camp, with the legion standing on the field as the chosen commander and the quartermaster's ranks would start it.
func _enter_camp(focus_id := "march") -> void:
	camp_sim = Sim.new(balance, content, _run_options())
	camp_sim.show_numbers = bool(Profile.setting("numbers"))
	camp_sim.blood = bool(Profile.setting("blood"))
	if Profile.rank("triumphal_arch") > 0:
		var spot: Array = CampScreen.arch_clearing()
		camp_sim.terrain.add_clearing(camp_sim.commander.pos + spot[0], spot[1], [])
	world.sim = camp_sim
	state = "camp"
	ui.focus = focus_id


func _finish_run() -> void:
	state = "over"
	opened_at = clock
	ui.focus = "camp"
	Profile.record_run(sim)
	Steamworks.check(sim, true)
	if sim.victory and not sim.demo_over:
		Audio.play("laurels")
		var next := Game.next_province(content, balance, sim.province)
		if next != "":
			screens.map.activate("prov:" + next)


func _start() -> void:
	profile_at_start = Profile.data.duplicate(true)
	_new_sim()
	state = "play"


func _setup_input() -> void:
	Controls.install(Profile.settings.get("bindings", {}))


func _process(dt: float) -> void:
	clock += dt
	if touch_pad != null and not _text_sized and Touch.fingertip > 0.0:
		_text_sized = true
		# A phone starts on large text when the normal size would be too small to read, until the player picks a size.
		if Touch.wants_large and not Profile.settings.has("text_size"):
			Profile.settings.text_size = 2
			apply_settings()
	Steamworks.blocked = state in Steamworks.HIDING_STATES
	_steam_update(dt)
	if shot_at >= 0.0 and clock >= shot_at:
		shot_at = -1.0
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args.shot)
		print("FPS %d with %d barbarians" % [Engine.get_frames_per_second(), sim.horde.e_pos.size()])
		get_tree().quit()
		return
	if Input.is_action_just_pressed("fullscreen") and not Touch.phone:
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		Profile.settings.fullscreen = not full
		apply_settings()
		Profile.save_settings()
	match state:
		"title", "camp", "quartermaster", "tablinum", "map", "commanders", "pause", "settings", "over", "saves":
			_screen_input(dt)
		"play":
			if Input.is_action_just_pressed("pause") or _pad("pause"):
				_pause()
				return
			if god_at >= 0.0 and clock >= god_at:
				god_at = -1.0
				_look_at_god(str(args.god))
				if state != "play":
					return
			if slay_at >= 0.0 and clock >= slay_at:
				slay_at = -1.0
				var ci := sim.chieftain_index()
				if ci >= 0:
					sim.hit(ci, 1e12, 0.0, "", sim.commander.pos)
			if win_at >= 0.0 and sim.time >= win_at:
				win_at = -1.0
				sim.win(sim.commander.pos)
			if (Input.is_action_just_pressed("pray") or _pad("pray")) and sim.triumph_left <= 0.0:
				_open_gods()
				if state != "play":
					return
			var move := Input.get_vector("left", "right", "up", "down")
			if touch_pad != null and touch_pad.move() != Vector2.ZERO:
				move = touch_pad.move()
			var testudo := Input.is_action_just_pressed("testudo") or _pad("testudo")
			var build := Input.is_action_just_pressed("build") or _pad("build")
			if args.has("autoplay"):
				if march_to_fort and sim.commander.pos.y <= sim.objectives.fort.centre.y + 20.0:
					look_march = Vector2.ZERO
				move = Vector2(cos(sim.time * 0.4), sin(sim.time * 0.4)) if look_march == Vector2.INF else look_march
				testudo = int(sim.time) % 20 == 5 and not march_to_fort
				build = sim.timber >= int(balance.palisade.cost) and look_march == Vector2.INF
			if build:
				sim.build_palisade()
			if Input.is_action_just_pressed("wall") or _pad("wall"):
				sim.build_wall()
			if Input.is_action_just_pressed("bridge") or _pad("bridge"):
				sim.build_bridge()
			sim.update(sim.slowed(minf(dt, 1.0 / 30.0)), move, testudo)
			Audio.drain(sim)
			if sim.over:
				_finish_run()
			elif (sim.pending_levels > 0 or sim.free_choices > 0) and sim.triumph_left <= 0.0:
				_open_choices()
		"pray":
			if args.has("autoplay") and clock - opened_at > 0.5 and args.get("god", "") != "choose":
				_call_god(0)
			elif Input.is_action_just_pressed("back") or Input.is_action_just_pressed("pray"):
				_not_now()
			elif Input.is_action_just_pressed("up") or Input.is_action_just_pressed("left"):
				selected = posmod(selected - 1, choices.size())
			elif Input.is_action_just_pressed("down") or Input.is_action_just_pressed("right"):
				selected = posmod(selected + 1, choices.size())
			elif Input.is_action_just_pressed("confirm"):
				if Game.confirm_allowed(state, opened_at, clock, balance):
					_call_god(selected)
		"choose":
			if args.has("autoplay") and clock > 0.5 and not args.has("hold-choice"):
				_take(0)
			elif Input.is_action_just_pressed("up") or Input.is_action_just_pressed("left"):
				selected = posmod(selected - 1, choices.size())
			elif Input.is_action_just_pressed("down") or Input.is_action_just_pressed("right"):
				selected = posmod(selected + 1, choices.size())
			elif Input.is_action_just_pressed("confirm"):
				if Game.confirm_allowed(state, opened_at, clock, balance):
					_take(selected)
			elif Input.is_action_just_pressed("reroll"):
				_reroll()
			elif Input.is_action_just_pressed("banish"):
				_banish()


## Whether a touch button was pressed this frame.
func _pad(id: String) -> bool:
	return touch_pad != null and touch_pad.take(id)


func _reroll() -> void:
	_press("reroll")


func _banish() -> void:
	if sim.banishes <= 0:
		return
	_press("banish")
	if choices.is_empty():
		sim.pending_levels = 0
		sim.free_choices = 0
		state = "play"


func _press(id: String) -> void:
	var after := Upgrades.press(sim, id, choices, selected)
	choices = after.choices
	selected = after.selected


## Leaves the gods' choice for later, with the favour kept.
func _not_now() -> void:
	Audio.play("back")
	state = "play"


## Earns achievements the run meets while it is on, and tells Steam where the player is.
func _steam_update(dt: float) -> void:
	if sim != null and Game.in_run(state, settings_from):
		check_clock += dt
		if check_clock >= float(balance.steam.check_every):
			check_clock = 0.0
			Steamworks.check(sim)
		Steamworks.presence(content.provinces[sim.province].name, int(sim.time / 60.0), sim.soldiers.size() + 1)
	else:
		Steamworks.presence("", 0, 0)


func _screen_input(dt: float) -> void:
	# The key that cancelled or finished a rebinding is already used up this frame.
	if swallow_input:
		swallow_input = false
		return
	if state == "settings" and not screens.settings.waiting.is_empty():
		return
	if state == "camp":
		for u in [camp_sim.commander] + camp_sim.soldiers:
			u.anim += dt * 6.0
	if state == "over" and screens.over.revealing():
		screens.over.tick(dt)
		if (Input.is_action_just_pressed("confirm") or Input.is_action_just_pressed("back")) and Game.confirm_allowed(state, opened_at, clock, balance):
			screens.over.skip()
		return
	if Input.is_action_just_pressed("back") or (state == "pause" and Input.is_action_just_pressed("pause")):
		_back()
		return
	if state == "pause" and Input.is_action_just_pressed("quit"):
		screens.pause.activate("giveup")
		return
	for dir in [["left", Vector2.LEFT], ["right", Vector2.RIGHT], ["up", Vector2.UP], ["down", Vector2.DOWN]]:
		if Input.is_action_just_pressed(dir[0]):
			if state == "settings" and dir[1].y == 0.0 and screens.settings.adjust(ui.focus, int(dir[1].x)):
				continue
			ui.move(dir[1])
	if Input.is_action_just_pressed("confirm") and Game.confirm_allowed(state, opened_at, clock, balance):
		_activate(ui.focus)


func _pause() -> void:
	state = "pause"
	screens.pause.confirming = false
	ui.focus = "resume"


func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED] and Game.pauses_on_focus_loss(state, args.has("autoplay") or args.has("skip")):
		_pause()
	if not Touch.phone:
		return
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if Touch.back_counts(Time.get_ticks_msec(), _back_at):
				_back_at = Time.get_ticks_msec()
				_go_back()
		# A phone may close a game it has put away without warning, so the game is saved and silenced at once.
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			Profile.save()
			Profile.save_settings()
			AudioServer.set_bus_mute(0, true)
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			SettingsScreen.apply_audio(Profile.settings_of(Profile.settings))


## The phone's back gesture: one step back from where the player is, and from the title the game is put away.
func _go_back() -> void:
	match Touch.back_step(state, state == "over" and screens.over.revealing()):
		"pause":
			_pause()
		"not_now":
			_not_now()
		"skip":
			screens.over.skip()
		"back":
			_back()
		"background":
			Profile.save()
			if Engine.has_singleton("AndroidRuntime"):
				Engine.get_singleton("AndroidRuntime").getActivity().moveTaskToBack(true)


func _back() -> void:
	Audio.play("back")
	match state:
		"title":
			pass
		"camp":
			go_to_title()
		"over":
			go_to_camp()
		"pause":
			screens.pause.confirming = false
			state = "play"
			ui.focus = ""
		"settings":
			if not screens.settings.back():
				close_settings()
		"saves":
			if not screens.saves.back():
				go_to_title("load")
		_:
			_enter_camp(state)


func _activate(id: String) -> void:
	if id == "touch_back":
		_back()
		return
	if not ui.is_enabled(id):
		# A locked province on the map answers with the back sound, so the press is heard while the panel says what opens it.
		if state == "map" and id.begins_with("prov:"):
			Audio.play("back")
		return
	Audio.play("click")
	if state == "camp":
		if id == "march":
			_start()
			Input.action_release("testudo")
		elif screens.has(id):
			state = id
			ui.focus = ""
	else:
		screens[state].activate(id)


func _open_choices() -> void:
	choices = Upgrades.next_choices(sim)
	if choices.is_empty():
		return
	selected = Upgrades.keep_in(int(args.get("select", "0")), choices)
	opened_at = clock
	state = "choose"


## Opens the choice of gods when the favour is full; the run waits while it is open.
func _open_gods() -> void:
	var offered := Gods.offers(sim)
	if offered.is_empty():
		return
	choices = offered
	selected = 0
	opened_at = clock
	state = "pray"


func _call_god(i: int) -> void:
	Audio.play("confirm")
	sim.gods.invoke(sim, choices[i])
	state = "play"
	# The confirm key is also the testudo key, so the press that called the god must not raise the shields.
	Input.action_release("testudo")


## Calls a god for a look, or with "choose" fills the favour and opens the choice.
func _look_at_god(id: String) -> void:
	sim.gods.favour = sim.gods.need(balance)
	if id == "choose":
		_open_gods()
	elif id in Gods.IDS:
		sim.gods.invoke(sim, id)


func _take(i: int) -> void:
	Audio.play("confirm")
	Upgrades.apply(sim, choices[i])
	state = "play"
	# The confirm key is also the testudo key, so the press that took the choice must not raise the shields.
	Input.action_release("testudo")
	if sim.pending_levels > 0 or sim.free_choices > 0:
		_open_choices()


func _input(event: InputEvent) -> void:
	Controls.note_input(event)


func _unhandled_input(event: InputEvent) -> void:
	if (state == "settings" and screens.settings.capture(event)) or (state == "saves" and screens.saves.capture(event)):
		swallow_input = true
		get_viewport().set_input_as_handled()
		return
	# A phone works its screens by taps, and the mouse events a touch also makes would act twice.
	if Touch.phone:
		if event is InputEventScreenTouch or event is InputEventScreenDrag:
			_touch_input(event)
		if event is InputEventMouse:
			return
	# The press itself says where it landed; the last known mouse position can lag behind a click that came without a move first.
	var at := Vector2.INF
	if event is InputEventMouse:
		at = hud.make_input_local(event).position - Ui.offset
	if screens.has(state):
		if event is InputEventMouseMotion:
			ui.hover(at)
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			if state == "over" and screens.over.revealing():
				if Game.confirm_allowed(state, opened_at, clock, balance):
					screens.over.skip()
				return
			var id := ui.at(at)
			if id != "":
				ui.focus = id
				_activate(id)
		return
	if state != "choose" and state != "pray":
		return
	if event is InputEventMouseMotion:
		var i: int = hud.choice_at(at)
		if i >= 0:
			selected = i
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if state == "choose" and Hud.shows_choice_panel(false, Ui.scale > 1):
			match Hud.choice_button_at(sim, at):
				"reroll":
					_reroll()
					return
				"banish":
					_banish()
					return
		var i: int = hud.choice_at(at)
		if i >= 0:
			if state == "pray":
				_call_god(i)
			else:
				_take(i)


## Follows each finger on a screen: a finger lifted where it landed taps, and one dragged up or down scrolls a list.
func _touch_input(event: InputEvent) -> void:
	var at: Vector2 = hud.make_input_local(event).position - Ui.offset
	if event is InputEventScreenTouch:
		if event.pressed:
			_fingers[event.index] = {"from": at, "moved": 0.0, "pulled": 0.0, "state": state}
		elif _fingers.has(event.index):
			var f: Dictionary = _fingers[event.index]
			_fingers.erase(event.index)
			# A finger that opened a screen or a choice as it pressed does not also tap what opened under it.
			if f.state == state and Touch.is_tap(f.moved, Touch.slop):
				_tap(f.from)
		return
	if not _fingers.has(event.index):
		return
	var f: Dictionary = _fingers[event.index]
	f.moved = maxf(f.moved, at.distance_to(f.from))
	if f.state != state or not screens.has(state) or not screens[state].has_method("scroll_by") or Touch.is_tap(f.moved, Touch.slop):
		return
	f.pulled += event.relative.y
	var step: float = screens[state].row_step()
	while absf(f.pulled) >= step:
		var rows := -1 if f.pulled > 0.0 else 1
		screens[state].scroll_by(rows)
		f.pulled += step * rows


## A tap on a screen: a button acts, or a purchase or choice is first picked out to be read.
func _tap(at: Vector2) -> void:
	if state == "choose" or state == "pray":
		_tap_choice(at)
		return
	if not screens.has(state):
		return
	if state == "over" and screens.over.revealing():
		if Game.confirm_allowed(state, opened_at, clock, balance):
			screens.over.skip()
		return
	var id := ui.at(at)
	if id == "":
		return
	if screens[state].has_method("tap_at") and screens[state].tap_at(id, at):
		ui.focus = id
		Audio.play("click")
		return
	var acts := Touch.tap_acts(state, id, ui.focus)
	ui.focus = id
	if acts:
		_activate(id)
	else:
		Audio.play("click")


## A tap on the level-up or the gods' choice: a row is picked out, then taken by a second tap or the button under the rows.
func _tap_choice(at: Vector2) -> void:
	var button: String = hud.touch_button_at(at)
	var ready := Game.confirm_allowed(state, opened_at, clock, balance)
	match button:
		"take", "call":
			if ready:
				_call_god(selected) if state == "pray" else _take(selected)
			return
		"reroll":
			_reroll()
			return
		"banish":
			_banish()
			return
		"not_now":
			_not_now()
			return
	var i: int = hud.choice_at(at)
	if i < 0:
		return
	if Touch.tap_acts(state, "choice:%d" % i, "choice:%d" % selected):
		if ready:
			_call_god(i) if state == "pray" else _take(i)
	else:
		selected = i
		Audio.play("click")


func _bench() -> void:
	var mixed := Content.with_all_art()
	var s := Sim.new(balance, mixed, {"seed": 7})
	for id in content.arms:
		if content.arms[id].implemented:
			s.ranks[id] = 3
	var mix := ["legionary", "archer", "cavalry", "standard_bearer", "medicus", "ballista", "centurion", "legionary", "archer"]
	for i in 100:
		s.add_soldier(mix[i % mix.size()])
	var kinds := ["barbarian_club", "barbarian_spear", "axe_thrower", "wolf", "chariot", "barbarian_club"]
	# A late run has at most bosses.max_alive elites on the field, so the bench brings that many beside the ordinary horde.
	for e in ["berserker", "war_band_leader", "war_priest", "berserker"]:
		s.horde.spawn(e, s.horde.ring_point() * 0.5)
	for i in int(balance.max_enemies):
		s.horde.spawn(kinds[i % kinds.size()], s.horde.ring_point() * randf_range(0.3, 1.0))
	var frames := 300
	var spent := 0
	var worst := 0
	for f in frames:
		# The horde is topped back up so every measured update meets the full cap.
		while s.horde.e_pos.size() < int(balance.max_enemies):
			s.horde.spawn(kinds[randi() % kinds.size()], s.horde.ring_point() * randf_range(0.3, 1.0))
		var start := Time.get_ticks_usec()
		s.update(1.0 / 60.0, Vector2(1, 0.3), false)
		var took := Time.get_ticks_usec() - start
		spent += took
		worst = maxi(worst, took)
	var ms := spent / 1000.0 / frames
	print("BENCH %d enemies, %d soldiers: %.2f ms per update, worst %.2f ms" % [s.horde.e_pos.size(), s.soldiers.size(), ms, worst / 1000.0])
	get_tree().quit()
