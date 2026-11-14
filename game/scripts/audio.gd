extends Node
## Every sound in the game: the effects the run reports through Sim.events, the interface sounds and the two music layers.
## Each kind of sound has a limit per tenth of a second, a slight random pitch and a few recorded cuts, so a thousand hits never stack.
## It does nothing in tests, benches and headless runs, so they stay silent and cheap.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
const VOICES := 24
const WINDOW := 0.1
const PAN_BUSES := [-0.8, -0.4, 0.0, 0.4, 0.8]
const VIEW_HALF_WIDTH := 320.0
const CALM_DB := -7.0
const DRUMS_QUIET_DB := -32.0
const DRUMS_LOUD_DB := -7.0
const DRUMS_FULL_SECONDS := 1080.0
const SURGE_BOOST_DB := 5.0
const SURGE_SECONDS := 14.0
const FADE_DB_PER_SECOND := 24.0

# kind: sound set, most plays per window, volume in dB, pitch spread, base pitch, priority (above 0 may take a busy voice)
const KINDS := {
	"hit": {"set": "hit", "max": 3, "db": -11.0, "spread": 0.12, "pitch": 1.0, "priority": 0},
	"kill": {"set": "die", "max": 1, "db": -14.0, "spread": 0.18, "pitch": 1.0, "priority": 0},
	"pilum": {"set": "pilum", "max": 2, "db": -9.0, "spread": 0.1, "pitch": 1.0, "priority": 0},
	"arrow": {"set": "arrow", "max": 2, "db": -10.0, "spread": 0.1, "pitch": 1.0, "priority": 0},
	"bolt": {"set": "bolt", "max": 1, "db": -6.0, "spread": 0.08, "pitch": 0.8, "priority": 0},
	"testudo": {"set": "thump", "max": 1, "db": -3.0, "spread": 0.03, "pitch": 0.8, "priority": 1},
	"level": {"set": "level", "max": 1, "db": -5.0, "spread": 0.0, "pitch": 1.0, "priority": 2},
	"coin": {"set": "coin", "max": 2, "db": -15.0, "spread": 0.3, "pitch": 1.1, "priority": 0},
	"hurt": {"set": "hurt", "max": 1, "db": -5.0, "spread": 0.1, "pitch": 1.0, "priority": 1},
	"surge": {"set": "horn_1", "max": 1, "db": -7.0, "spread": 0.0, "pitch": 1.0, "priority": 2},
	"chieftain": {"set": "horn_2", "max": 1, "db": -5.0, "spread": 0.0, "pitch": 0.95, "priority": 2},
	"victory": {"set": "roar", "max": 1, "db": -5.0, "spread": 0.0, "pitch": 1.0, "priority": 2},
	"roar": {"set": "roar", "max": 1, "db": -8.0, "spread": 0.05, "pitch": 1.0, "priority": 1},
	"drum": {"set": "drum", "max": 2, "db": -6.0, "spread": 0.05, "pitch": 1.0, "priority": 0},
	"click": {"set": "click", "max": 2, "db": -8.0, "spread": 0.04, "pitch": 1.0, "priority": 1},
	"confirm": {"set": "click", "max": 2, "db": -6.0, "spread": 0.0, "pitch": 1.25, "priority": 1},
	"back": {"set": "click", "max": 2, "db": -8.0, "spread": 0.0, "pitch": 0.75, "priority": 1},
}

var enabled := false
var in_run := false
var _sets := {}
var _players: Array[AudioStreamPlayer] = []
var _pan_buses: Array[StringName] = []
var _next := 0
var _clock := 0.0
var _window_start := {}
var _window_count := {}
var _rng := RandomNumberGenerator.new()
var _calm: AudioStreamPlayer
var _drums: AudioStreamPlayer
var _drums_target := -80.0
var _run_time := 0.0
var _surge_left := 0.0


func _ready() -> void:
	_rng.randomize()
	var with_sound := "--with-sound" in OS.get_cmdline_user_args()
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
	var limiter := AudioEffectHardLimiter.new()
	limiter.ceiling_db = -1.5
	AudioServer.add_bus_effect(AudioServer.get_bus_index("Master"), limiter)
	for kind in KINDS:
		var set_name: String = KINDS[kind].set
		if not _sets.has(set_name):
			_sets[set_name] = _load_set(set_name)
	# Each pan position is a bus with a panner, since a single voice cannot be placed left or right on its own.
	for pan in PAN_BUSES:
		AudioServer.add_bus()
		var b := AudioServer.bus_count - 1
		var bus_name := StringName("Pan%d" % roundi(pan * 10.0))
		AudioServer.set_bus_name(b, bus_name)
		AudioServer.set_bus_send(b, "Effects")
		var panner := AudioEffectPanner.new()
		panner.pan = pan
		AudioServer.add_bus_effect(b, panner)
		_pan_buses.append(bus_name)
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_calm = _music_player("calm", CALM_DB)
	_drums = _music_player("drums", -80.0)


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
	if not enabled or not KINDS.has(kind):
		return
	var info: Dictionary = KINDS[kind]
	if _clock - float(_window_start.get(kind, -1.0)) >= WINDOW:
		_window_start[kind] = _clock
		_window_count[kind] = 0
	if int(_window_count[kind]) >= int(info.max):
		return
	var variants: Array = _sets.get(info.set, [])
	if variants.is_empty():
		return
	var p := _free_voice(int(info.priority))
	if p == null:
		return
	_window_count[kind] += 1
	p.stream = variants[_rng.randi() % variants.size()]
	p.volume_db = float(info.db) + loudness_db
	p.pitch_scale = float(info.pitch) * (1.0 + _rng.randf_range(-1.0, 1.0) * float(info.spread))
	p.bus = _pan_buses[clampi(roundi((clampf(pan, -1.0, 1.0) + 1.0) * 2.0), 0, 4)]
	p.play()


## A voice that is not playing, or, for a sound that matters, the next one in turn even if it is busy.
func _free_voice(priority: int) -> AudioStreamPlayer:
	for k in VOICES:
		var p := _players[(_next + k) % VOICES]
		if not p.playing:
			_next = (_next + k + 1) % VOICES
			return p
	if priority > 0:
		var p := _players[_next]
		_next = (_next + 1) % VOICES
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
	_run_time = sim.time
	for e in sim.events:
		var n: int = e.get("n", 1)
		var pan := clampf((e.pos.x - centre) / VIEW_HALF_WIDTH, -1.0, 1.0)
		# A crowd of hits is louder than one, up to a few decibels.
		play(e.kind, pan, minf(5.0, 2.0 * log(float(n)) / log(2.0)) if n > 1 else 0.0)
		if e.kind == "surge" or e.kind == "chieftain":
			_surge_left = SURGE_SECONDS
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
		var rise := pow(clampf(_run_time / DRUMS_FULL_SECONDS, 0.0, 1.0), 0.8)
		_drums_target = lerpf(DRUMS_QUIET_DB, DRUMS_LOUD_DB, rise) + SURGE_BOOST_DB * clampf(_surge_left / SURGE_SECONDS * 2.0, 0.0, 1.0)
	else:
		_drums_target = -80.0
	_drums.volume_db = move_toward(_drums.volume_db, _drums_target, FADE_DB_PER_SECOND * dt)
	# The layers share one length, and this keeps them from drifting apart.
	if _calm.playing and _drums.playing and absf(_calm.get_playback_position() - _drums.get_playback_position()) > 0.05:
		_drums.seek(_calm.get_playback_position())
