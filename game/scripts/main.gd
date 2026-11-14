extends Node
## Runs the game: title, the run, level-up choices, pause and the summary, plus the command-line modes used to test.
##   --run-tests        run the checks in tests/ and quit
##   --bench            time the simulation with a full horde and quit
##   --autoplay         march in circles and take the first choice, for looking at the game without playing
##   --skip=SECONDS     start the run this far in, simulated in fast steps
##   --shot=PATH        save a screenshot after --at seconds (default 3) and quit
##   --chieftain-at=S   bring the chieftain at this many seconds instead
##   --hold-choice      with --autoplay, give a level at once and leave its choices open

var balance: Dictionary
var sim: Sim
var state := "title"
var choices: Array = []
var selected := 0
var args := {}
var shot_at := -1.0
var clock := 0.0

@onready var world: Node2D = $World
@onready var hud: Node2D = $UI/Hud


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		var parts := a.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else ""
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
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
	_new_sim()
	if args.has("autoplay") or args.has("skip"):
		_start()
		if args.has("skip"):
			var target := float(args.skip)
			while sim.time < target and not sim.over:
				sim.update(1.0 / 30.0, Vector2(cos(sim.time * 0.3), sin(sim.time * 0.3)), false)
				while sim.pending_levels > 0:
					Upgrades.apply(sim, Upgrades.offers(sim)[0])
	if args.has("hold-choice"):
		sim.gain(sim.xp_next - sim.xp)
	if args.has("shot"):
		shot_at = float(args.get("at", "3"))


func _new_sim() -> void:
	sim = Sim.new(balance)
	world.sim = sim


func _start() -> void:
	_new_sim()
	state = "play"


func _setup_input() -> void:
	var keys := {
		"left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT], "up": [KEY_W, KEY_UP], "down": [KEY_S, KEY_DOWN],
		"testudo": [KEY_SPACE], "confirm": [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER], "pause": [KEY_ESCAPE], "quit": [KEY_Q],
		"fullscreen": [KEY_F11],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		for k in keys[action]:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
	var pad := {"testudo": JOY_BUTTON_A, "confirm": JOY_BUTTON_A, "pause": JOY_BUTTON_START,
		"left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT, "up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN}
	for action in pad:
		var e := InputEventJoypadButton.new()
		e.button_index = pad[action]
		InputMap.action_add_event(action, e)
	for pair in [["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0], ["up", JOY_AXIS_LEFT_Y, -1.0], ["down", JOY_AXIS_LEFT_Y, 1.0]]:
		var m := InputEventJoypadMotion.new()
		m.axis = pair[1]
		m.axis_value = pair[2]
		InputMap.action_add_event(pair[0], m)


func _process(dt: float) -> void:
	clock += dt
	if shot_at >= 0.0 and clock >= shot_at:
		shot_at = -1.0
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args.shot)
		print("FPS %d with %d barbarians" % [Engine.get_frames_per_second(), sim.e_pos.size()])
		get_tree().quit()
		return
	if Input.is_action_just_pressed("fullscreen"):
		var full := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if full else DisplayServer.WINDOW_MODE_FULLSCREEN)
	match state:
		"title":
			if Input.is_action_just_pressed("confirm"):
				_start()
		"play":
			if Input.is_action_just_pressed("pause"):
				state = "pause"
				return
			var move := Input.get_vector("left", "right", "up", "down")
			var testudo := Input.is_action_just_pressed("testudo")
			if args.has("autoplay"):
				move = Vector2(cos(sim.time * 0.4), sin(sim.time * 0.4))
				testudo = int(sim.time) % 20 == 5
			sim.update(minf(dt, 1.0 / 30.0), move, testudo)
			if sim.over:
				state = "over"
			elif sim.pending_levels > 0:
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
		"pause":
			if Input.is_action_just_pressed("pause"):
				state = "play"
			elif Input.is_action_just_pressed("quit"):
				sim.over = true
				state = "over"
		"over":
			if Input.is_action_just_pressed("confirm"):
				_start()
			elif Input.is_action_just_pressed("pause"):
				_new_sim()
				state = "title"


func _open_choices() -> void:
	choices = Upgrades.offers(sim)
	if choices.is_empty():
		sim.pending_levels = 0
		return
	selected = 0
	state = "choose"


func _take(i: int) -> void:
	Upgrades.apply(sim, choices[i])
	state = "play"
	# The confirm key is also the testudo key, so the press that took the choice must not raise the shields.
	Input.action_release("testudo")
	if sim.pending_levels > 0:
		_open_choices()


func _unhandled_input(event: InputEvent) -> void:
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
	var s := Sim.new(balance, 7)
	for id in ["pilum", "pilum", "scorpio", "fire_arrows"]:
		s.ranks[id] = s.rank(id) + 1
	for i in 40:
		s.add_soldier("legionary" if i % 3 else "archer")
	for i in 1000:
		s.spawn_enemy(i % 2, s._ring_point() * randf_range(0.3, 1.0))
	var start := Time.get_ticks_usec()
	var frames := 300
	for f in frames:
		s.update(1.0 / 60.0, Vector2(1, 0.3), false)
	var ms := (Time.get_ticks_usec() - start) / 1000.0 / frames
	print("BENCH %d enemies, %d soldiers: %.2f ms per update" % [s.e_pos.size(), s.soldiers.size(), ms])
	get_tree().quit()
