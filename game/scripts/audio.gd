extends Node
## Every sound in the game: the effects the run reports through Sim.events, the interface sounds, and the music, the game's
## own battle tracks and any the player puts in their own music folder, played one after another from the moment the game opens.
## Each kind of sound has a limit per tenth of a second, a slight random pitch and a few recorded cuts, so a thousand hits never stack.
## It does nothing in tests, benches and headless runs, so they stay silent and cheap.

const SFX_DIR := "res://assets/audio/sfx/"
const MUSIC_DIR := "res://assets/audio/music/"
## The player's own music, beside the saves; the settings open it.
const PLAYER_MUSIC := "user://music/"
const MUSIC_TYPES := ["ogg", "mp3", "wav"]
var enabled := false
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
var _battle: AudioStreamPlayer
var _battle_track := ""
var _retry_at := 0.0


func _ready() -> void:
	_rng.randomize()
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json")).audio
	_kinds = cfg.kinds
	# The everything-unlocked mode is for playing and a trailer shot's sound goes into the trailer, so both keep their sound
	# though they never save, at the default volumes since neither reads the player's settings.
	var args := OS.get_cmdline_user_args()
	var with_sound := "--with-sound" in args or "--max-state" in args or Array(args).any(func(a: String) -> bool: return a.begins_with("--trailer-shot="))
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
	_battle = AudioStreamPlayer.new()
	_battle.bus = "Music"
	_battle.volume_db = float(cfg.battle_db)
	add_child(_battle)


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
	var half_width := Horde.view.x / 2.0
	for e in sim.events:
		var n: int = e.get("n", 1)
		var pan := clampf((e.pos.x - centre) / half_width, -1.0, 1.0)
		# A crowd of hits is louder than one, up to a few decibels.
		play(e.kind, pan, minf(float(cfg.crowd_db_max), float(cfg.crowd_db_per_doubling) * log(float(n)) / log(2.0)) if n > 1 else 0.0)
	sim.events.clear()


## The music plays from the moment the game opens, one track after another through the menus and the runs alike, so
## marching out never cuts one track off for another.
func _process(dt: float) -> void:
	_clock += dt
	if not _battle.playing and _clock >= _retry_at:
		_start_battle_track()


## Plays the next battle track, from the game's own and the player's folder, which is looked at afresh each time.
func _start_battle_track() -> void:
	_battle_track = next_track(battle_tracks() + player_tracks(), _battle_track)
	var stream: AudioStream = null
	if _battle_track != "":
		stream = load(_battle_track) if _battle_track.begins_with("res://") else load_external(_battle_track)
	if stream == null:
		# With nothing playable the folder is looked at again a little later, not every frame.
		_retry_at = _clock + 5.0
		return
	_battle.stream = stream
	_battle.play()


## The game's own battle tracks, as paths.
static func battle_tracks() -> Array:
	var out: Array = []
	for f in ResourceLoader.list_directory(MUSIC_DIR):
		if f.begins_with("battle_") and f.ends_with(".ogg"):
			out.append(MUSIC_DIR + f)
	return out


## A track picked at random, never `last` again while there is another to play; "" when there are none.
static func next_track(choices: Array, last: String) -> String:
	var pool := choices.filter(func(t: String) -> bool: return t != last)
	if pool.is_empty():
		return "" if choices.is_empty() else str(choices[0])
	return str(pool[randi() % pool.size()])


## The music files in the player's own folder, or in `folder`, as full paths.
static func player_tracks(folder := ProjectSettings.globalize_path(PLAYER_MUSIC)) -> Array:
	if not DirAccess.dir_exists_absolute(folder):
		return []
	return Array(DirAccess.get_files_at(folder)).filter(func(f: String) -> bool: return f.get_extension().to_lower() in MUSIC_TYPES).map(func(f: String) -> String: return folder.path_join(f))


## Reads a music file from outside the game's own files; one it cannot read is skipped.
static func load_external(path: String) -> AudioStream:
	match path.get_extension().to_lower():
		"ogg":
			return AudioStreamOggVorbis.load_from_file(path)
		"mp3":
			return AudioStreamMP3.load_from_file(path)
		"wav":
			return AudioStreamWAV.load_from_file(path)
	return null


## Opens the player's music folder in the file explorer, making it first if need be.
func open_music_folder() -> void:
	var folder := ProjectSettings.globalize_path(PLAYER_MUSIC)
	DirAccess.make_dir_recursive_absolute(folder)
	OS.shell_open(folder)
