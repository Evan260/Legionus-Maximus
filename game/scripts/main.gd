extends Node
## Runs the game: title, the run, level-up choices, pause and the summary, plus the command-line modes used to test.
##   --run-tests        run the checks in tests/ and quit
##   --bench            time the simulation with a full horde and quit
##   --autoplay         march in circles and take the first choice, for looking at the game without playing
##   --skip=SECONDS     start the run this far in, simulated in fast steps
##   --shot=PATH        save a screenshot after --at seconds (default 3) and quit
##   --chieftain-at=S   bring the chieftain at this many seconds instead
##   --hold-choice      with --autoplay, give a level at once and leave its choices open
##   --hard, --endless, --decimatio   start the run in that mode
##   --screen=NAME      open a screen (camp, quartermaster, tablinum, map, commanders, settings) with a sample profile, for screenshots;
##                      summary runs a skipped autoplay to its end and shows the run summary
##   --page=controls    with --screen=settings, open the key and button page
##   --text-size=N      use text size 1 or 2 without saving it
##   --commander=ID     start with that commander (the tribune when his art is not drawn)
##   --as-demo          play as the demo: Germania, three commanders and 15 minutes
##   --card=ID          show that achievement's card, for looking at it
##   --give=ID,ID:RANK  start the run with these arms or drills at the rank (default 1), for looking at them

var balance: Dictionary
var content: Content
var sim: Sim
var state := "title"
var choices: Array = []
var selected := 0
var args := {}
var shot_at := -1.0
var clock := 0.0
var ui := Ui.new()
var screens := {}
var camp_sim: Sim
var settings_from := "title"
var swallow_input := false
var check_clock := 0.0
var run_setup := {"province": "germania", "commander": "tribune", "hard": false, "endless": false, "decimatio": false}

@onready var world: Node2D = $World
@onready var hud: Node2D = $UI/Hud


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var parts := a.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	content = Content.load_all(Content.available_art())
	Steamworks.content = content
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
	hud.main = self
	hud.ui = ui
	screens = {"camp": CampScreen.new(self), "quartermaster": QuartermasterScreen.new(self), "tablinum": TablinumScreen.new(self),
		"map": MapScreen.new(self), "commanders": CommandersScreen.new(self), "title": TitleScreen.new(self), "pause": PauseScreen.new(self),
		"settings": SettingsScreen.new(self), "over": SummaryScreen.new(self)}
	if args.has("text-size"):
		Profile.data.settings.text_size = int(args["text-size"])
	apply_settings()
	_load_run_setup()
	_new_sim()
	ui.focus = "march"
	if args.get("screen", "") == "summary":
		_sample_profile()
		_summary_shot()
	elif args.has("screen") and screens.has(args.screen):
		_sample_profile()
		_enter_camp()
		state = args.screen
		ui.focus = ""
		if state == "settings":
			screens.settings.enter()
			screens.settings.page = args.get("page", "main")
	if args.has("autoplay") or args.has("skip"):
		_start()
		if args.has("skip"):
			var target := float(args.skip)
			while sim.time < target and not sim.over:
				sim.update(1.0 / 30.0, Vector2(cos(sim.time * 0.3), sin(sim.time * 0.3)), false)
				while sim.pending_levels > 0:
					Upgrades.apply(sim, Upgrades.offers(sim)[0])
	if args.has("card") and content.achievements.has(args.card):
		Steamworks.show_card(args.card)
	if args.has("hold-choice"):
		sim.gain(sim.xp_next - sim.xp)
	if args.has("shot"):
		shot_at = float(args.get("at", "3"))


## Runs an autoplay to its end and shows the summary, for a screenshot.
func _summary_shot() -> void:
	_start()
	while not sim.over:
		sim.update(1.0 / 30.0, Vector2(cos(sim.time * 0.3), sin(sim.time * 0.3)), false)
		while sim.pending_levels > 0:
			Upgrades.apply(sim, Upgrades.offers(sim)[0])
	_finish_run()


## Puts every saved setting to work: volumes, full screen, text size, damage numbers and screen shake.
func apply_settings() -> void:
	var cfg := Profile.settings_of(Profile.data)
	SettingsScreen.apply_audio(cfg)
	var want := DisplayServer.WINDOW_MODE_FULLSCREEN if cfg.fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != want:
		DisplayServer.window_set_mode(want)
	Ui.set_text_size(int(cfg.text_size), balance)
	world.shake_on = cfg.shake
	for s in [sim, camp_sim]:
		if s != null:
			s.show_numbers = cfg.numbers


func open_settings(from: String) -> void:
	settings_from = from
	state = "settings"
	ui.focus = ""
	screens.settings.enter()


func close_settings() -> void:
	Profile.save()
	state = settings_from
	ui.focus = "settings"


func go_to_camp() -> void:
	_enter_camp()


func go_to_title() -> void:
	_new_sim()
	state = "title"
	ui.focus = "march"


func _new_sim() -> void:
	sim = Sim.new(balance, content, _run_options())
	sim.show_numbers = bool(Profile.setting("numbers"))
	world.sim = sim
	if args.has("autoplay") or args.has("skip"):
		for entry in str(args.get("give", "")).split(",", false):
			var parts := entry.split(":")
			var info := content.upgrade(parts[0])
			if not info.is_empty():
				sim.ranks[parts[0]] = clampi(int(parts[1]) if parts.size() > 1 else 1, 0, int(info.get("max", 0)))


## The camp's choices, the saved ones first, then anything the command line asks for.
func _load_run_setup() -> void:
	var settings: Dictionary = Profile.data.settings
	var offered := Game.commanders(content, balance)
	if content.ready("provinces", str(settings.get("province", ""))) and Profile.province_unlocked(settings.province) and Game.province_allowed(settings.province, balance):
		run_setup.province = settings.province
	if settings.get("commander", "") in offered and Profile.commander_unlocked(settings.commander):
		run_setup.commander = settings.commander
	if args.has("commander") and args.commander in offered:
		run_setup.commander = args.commander
	for mode in ["hard", "endless", "decimatio"]:
		run_setup[mode] = args.has(mode)


## The run's options: what was chosen in the camp and the quartermaster's ranks.
func _run_options() -> Dictionary:
	var options: Dictionary = run_setup.duplicate()
	options.profile_bonuses = Profile.bonuses()
	options.demo_seconds = Game.run_cap(balance)
	return options


## A profile with something in every screen, held in memory only, so a screenshot shows the screens filled in.
func _sample_profile() -> void:
	Profile.data = Profile.merge_saved({"denarii": 640, "ranks": {"start_health": 2, "damage": 1, "rerolls": 3, "denarii": 5},
		"records": {"germania": {"best_time": 1110.0, "longest": 1200.0, "won": true, "hard_won": false}},
		"seen": {"legionary": true, "archer": true, "pilum": true, "barbarian_club": true, "wolf": true, "berserker": true},
		"totals": {"kills": 2400, "runs": 9, "wins": 1}, "unlocked": {"commanders": ["tribune", "archer_captain"]}})


## Back to the camp, with the legion standing on the field as the chosen commander and the quartermaster's ranks would start it.
func _enter_camp(focus_id := "march") -> void:
	camp_sim = Sim.new(balance, content, _run_options())
	camp_sim.show_numbers = bool(Profile.setting("numbers"))
	world.sim = camp_sim
	state = "camp"
	ui.focus = focus_id


func _finish_run() -> void:
	state = "over"
	ui.focus = "camp"
	Profile.record_run(sim)
	Steamworks.check(sim, true)


func _start() -> void:
	_new_sim()
	state = "play"


func _setup_input() -> void:
	Controls.install(Profile.data.settings.get("bindings", {}))


func _process(dt: float) -> void:
	clock += dt
	Steamworks.blocked = state in Steamworks.HIDING_STATES
	_steam_update(dt)
	Audio.set_run(state in ["play", "choose", "pause"], sim.time if sim != null else 0.0)
	if shot_at >= 0.0 and clock >= shot_at:
		shot_at = -1.0
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args.shot)
		print("FPS %d with %d barbarians" % [Engine.get_frames_per_second(), sim.horde.e_pos.size()])
		get_tree().quit()
		return
	if Input.is_action_just_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		Profile.data.settings.fullscreen = not full
		apply_settings()
		Profile.save()
	match state:
		"title", "camp", "quartermaster", "tablinum", "map", "commanders", "pause", "settings", "over":
			_screen_input(dt)
		"play":
			if Input.is_action_just_pressed("pause"):
				state = "pause"
				ui.focus = "resume"
				return
			var move := Input.get_vector("left", "right", "up", "down")
			var testudo := Input.is_action_just_pressed("testudo")
			if args.has("autoplay"):
				move = Vector2(cos(sim.time * 0.4), sin(sim.time * 0.4))
				testudo = int(sim.time) % 20 == 5
			sim.update(minf(dt, 1.0 / 30.0), move, testudo)
			Audio.drain(sim)
			if sim.over:
				_finish_run()
			elif sim.pending_levels > 0 or sim.free_choices > 0:
				_open_choices()
		"choose":
			if args.has("autoplay") and clock > 0.5 and not args.has("hold-choice"):
				_take(0)
			elif Input.is_action_just_pressed("left"):
				selected = posmod(selected - 1, choices.size())
			elif Input.is_action_just_pressed("right"):
				selected = posmod(selected + 1, choices.size())
			elif Input.is_action_just_pressed("confirm"):
				_take(selected)
			elif Input.is_action_just_pressed("reroll") and sim.rerolls > 0:
				choices = Upgrades.reroll(sim, choices)
			elif Input.is_action_just_pressed("banish") and sim.banishes > 0:
				choices = Upgrades.banish(sim, choices[selected], choices)
				selected = mini(selected, choices.size() - 1)
				if choices.is_empty():
					sim.pending_levels = 0
					sim.free_choices = 0
					state = "play"


## Earns achievements the run meets while it is on, and tells Steam where the player is.
func _steam_update(dt: float) -> void:
	if sim != null and state in ["play", "choose", "pause"]:
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
	if Input.is_action_just_pressed("confirm"):
		_activate(ui.focus)


func _back() -> void:
	Audio.play("back")
	match state:
		"title":
			pass
		"camp", "over":
			go_to_title()
		"pause":
			state = "play"
			ui.focus = ""
		"settings":
			if not screens.settings.back():
				close_settings()
		_:
			_enter_camp(state)


func _activate(id: String) -> void:
	if not ui.is_enabled(id):
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
	selected = 0
	state = "choose"


func _take(i: int) -> void:
	Audio.play("confirm")
	Upgrades.apply(sim, choices[i])
	state = "play"
	# The confirm key is also the testudo key, so the press that took the choice must not raise the shields.
	Input.action_release("testudo")
	if sim.pending_levels > 0 or sim.free_choices > 0:
		_open_choices()


func _unhandled_input(event: InputEvent) -> void:
	if state == "settings" and screens.settings.capture(event):
		swallow_input = true
		get_viewport().set_input_as_handled()
		return
	if screens.has(state):
		if event is InputEventMouseMotion:
			ui.hover(hud.get_global_mouse_position())
		elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var id := ui.at(hud.get_global_mouse_position())
			if id != "":
				ui.focus = id
				_activate(id)
		return
	if state != "choose":
		return
	if event is InputEventMouseMotion:
		var i: int = hud.choice_at(hud.get_global_mouse_position())
		if i >= 0:
			selected = i
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var i: int = hud.choice_at(hud.get_global_mouse_position())
		if i >= 0:
			_take(i)


func _bench() -> void:
	var mixed := Content.with_all_art()
	var s := Sim.new(balance, mixed, {"seed": 7})
	for id in content.arms:
		if content.arms[id].implemented:
			s.ranks[id] = 3
	var mix := ["legionary", "archer", "slinger", "cavalry", "standard_bearer", "medicus", "ballista", "centurion", "legionary", "archer"]
	for i in 100:
		s.add_soldier(mix[i % mix.size()])
	var kinds := ["barbarian_club", "barbarian_spear", "axe_thrower", "wolf", "chariot", "berserker"]
	for i in 1000:
		s.horde.spawn(kinds[i % kinds.size()], s.horde.ring_point() * randf_range(0.3, 1.0))
	var frames := 300
	var spent := 0
	for f in frames:
		# The horde is topped back up so every measured update meets the full 1,000.
		while s.horde.e_pos.size() < 1000:
			s.horde.spawn(kinds[randi() % kinds.size()], s.horde.ring_point() * randf_range(0.3, 1.0))
		var start := Time.get_ticks_usec()
		s.update(1.0 / 60.0, Vector2(1, 0.3), false)
		spent += Time.get_ticks_usec() - start
	var ms := spent / 1000.0 / frames
	print("BENCH %d enemies, %d soldiers: %.2f ms per update" % [s.horde.e_pos.size(), s.soldiers.size(), ms])
	get_tree().quit()
