extends Node
## Every sound in the game: the effects the run reports through Sim.events, the interface sounds and the two music layers.
## Each kind of sound has a limit per tenth of a second, a slight random pitch and a few recorded cuts, so a thousand hits never stack.
## It does nothing in tests, benches and headless runs, so they stay silent and cheap.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
var enabled := false
var in_run := false
var _sets := {}
var _players: Array[AudioStreamPlayer] = []
var _pan_buses: Array[StringName] = []
var _next := 0
var _clock := 0.0
var _window_start := {}
var _window_count := {}
var _last_played := {}
var _rng := RandomNumberGenerator.new()
var cfg: Dictionary
var _kinds: Dictionary
var _calm: AudioStreamPlayer
var _drums: AudioStreamPlayer
var _drums_target := -80.0
var _run_time := 0.0
var _surge_left := 0.0


func _ready() -> void:
	_rng.randomize()
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json")).audio
	_kinds = cfg.kinds
	# The everything-unlocked mode is for playing, so it keeps its sound though it never saves.
	var with_sound := "--with-sound" in OS.get_cmdline_user_args() or "--max-state" in OS.get_cmdline_user_args()
	enabled = (not Profile.disabled or with_sound) and DisplayServer.get_name() != "headless"
	if not enabled:
		set_process(false)
		return
	for bus_name in ["Music", "Effects"]:
		if AudioServer.get_bus_index(bus_name) < 0:
			AudioServer.add_bus()
			var b := AudioServer.bus_count - 1
			AudioServer.set_bus_name(b, bus_name)
			AudioServer.set_bus_send(b, "Master")
	# A limiter on the master bus keeps a crowd of loud sounds from clipping.
	var master := AudioServer.get_bus_index("Master")
	var has_limiter := false
	for k in AudioServer.get_bus_effect_count(master):
		has_limiter = has_limiter or AudioServer.get_bus_effect(master, k) is AudioEffectHardLimiter
	if not has_limiter:
		var limiter := AudioEffectHardLimiter.new()
		limiter.ceiling_db = float(cfg.limiter_ceiling_db)
		AudioServer.add_bus_effect(master, limiter)
	for kind in _kinds:
		var set_name: String = _kinds[kind].set
		if not _sets.has(set_name):
			_sets[set_name] = _load_set(set_name)
	# Each pan position is a bus with a panner, since a single voice cannot be placed left or right on its own.
	for pan in cfg.pan_positions:
		AudioServer.add_bus()
		var b := AudioServer.bus_count - 1
		var bus_name := StringName("Pan%d" % roundi(pan * 10.0))
		AudioServer.set_bus_name(b, bus_name)
		AudioServer.set_bus_send(b, "Effects")
		var panner := AudioEffectPanner.new()
		panner.pan = pan
		AudioServer.add_bus_effect(b, panner)
		_pan_buses.append(bus_name)
	for i in int(cfg.voices):
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_calm = _music_player("calm", cfg.calm_db)
	_drums = _music_player("drums", cfg.silent_db)


func _music_player(track: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = db
	var stream := load(MUSIC_DIR + track + ".ogg") as AudioStreamOggVorbis
	if stream != null:
		stream.loop = true
		p.stream = stream
	add_child(p)
	return p


func _load_set(set_name: String) -> Array:
	var out := []
	var single := _load(SFX_DIR + set_name + ".ogg")
	if single:
		out.append(single)
	for k in range(1, 20):
		var s := _load("%s%s_%d.ogg" % [SFX_DIR, set_name, k])
		if s == null:
			break
		out.append(s)
	return out


func _load(path: String) -> AudioStream:
	return load(path) if ResourceLoader.exists(path) else null


## Plays one sound of a kind. `pan` runs from -1 (far left) to 1 (far right); `loudness_db` is added to the kind's own volume.
func play(kind: String, pan := 0.0, loudness_db := 0.0) -> void:
	if not enabled or not _kinds.has(kind):
		return
	var info: Dictionary = _kinds[kind]
	if _clock - float(_window_start.get(kind, -1.0)) >= float(cfg.window):
		_window_start[kind] = _clock
		_window_count[kind] = 0
	if int(_window_count[kind]) >= int(info.max):
		return
	# A kind with a cooldown waits that long after it last sounded, however often it is reported.
	if info.has("cooldown") and _clock - float(_last_played.get(kind, -1e9)) < float(info.cooldown):
		return
	var variants: Array = _sets.get(info.set, [])
	if variants.is_empty():
		return
	var p := _free_voice(int(info.priority))
	if p == null:
		return
	_window_count[kind] += 1
	_last_played[kind] = _clock
	p.stream = variants[_rng.randi() % variants.size()]
	p.volume_db = float(info.db) + loudness_db
	p.pitch_scale = float(info.pitch) * (1.0 + _rng.randf_range(-1.0, 1.0) * float(info.spread))
	p.bus = _pan_buses[clampi(roundi((clampf(pan, -1.0, 1.0) + 1.0) * 2.0), 0, 4)]
	p.play()


## A voice that is not playing, or, for a sound that matters, the next one in turn even if it is busy.
func _free_voice(priority: int) -> AudioStreamPlayer:
	for k in _players.size():
		var p := _players[(_next + k) % _players.size()]
		if not p.playing:
			_next = (_next + k + 1) % _players.size()
			return p
	if priority > 0:
		var p := _players[_next]
		_next = (_next + 1) % _players.size()
		return p
	return null


## Plays what the run reported this update and clears it, panned by where each thing happened relative to the commander.
func drain(sim: Sim) -> void:
	if sim.events.is_empty():
		return
	if not enabled:
		sim.events.clear()
		return
	var centre: float = sim.commander.pos.x
	var half_width := get_viewport().get_visible_rect().size.x / 2.0
	_run_time = sim.time
	for e in sim.events:
		var n: int = e.get("n", 1)
		var pan := clampf((e.pos.x - centre) / half_width, -1.0, 1.0)
		# A crowd of hits is louder than one, up to a few decibels.
		play(e.kind, pan, minf(float(cfg.crowd_db_max), float(cfg.crowd_db_per_doubling) * log(float(n)) / log(2.0)) if n > 1 else 0.0)
		if e.kind == "surge" or e.kind == "chieftain":
			_surge_left = float(cfg.surge_seconds)
	sim.events.clear()


## Chooses between the calm layer alone (title and camp) and the run, where the drums rise with the minutes.
func set_run(running: bool, run_time := 0.0) -> void:
	in_run = running
	_run_time = run_time


func _process(dt: float) -> void:
	_clock += dt
	if not _calm.playing and _calm.stream != null:
		_calm.play()
		_drums.play()
	_surge_left = maxf(0.0, _surge_left - dt)
	if in_run:
		var rise := pow(clampf(_run_time / float(cfg.drums_full_seconds), 0.0, 1.0), float(cfg.drums_curve))
		_drums_target = lerpf(float(cfg.drums_quiet_db), float(cfg.drums_loud_db), rise) + float(cfg.surge_boost_db) * clampf(_surge_left / float(cfg.surge_seconds) * float(cfg.surge_ramp), 0.0, 1.0)
	else:
		_drums_target = float(cfg.silent_db)
	_drums.volume_db = move_toward(_drums.volume_db, _drums_target, float(cfg.fade_db_per_second) * dt)
	# The layers share one length, and this keeps them from drifting apart.
	if _calm.playing and _drums.playing and absf(_calm.get_playback_position() - _drums.get_playback_position()) > float(cfg.resync_seconds):
		_drums.seek(_calm.get_playback_position())
