extends Node
## The saved games and the settings. Each of the three save slots is a game of its own: denarii, quartermaster ranks, unlocks,
## records, the codex, totals, achievements and the camp's choices. The player's settings are shared by every slot in a file of their own.
## It is an autoload named Profile. Tests and screenshots never touch the real files, since `disabled` is set before anything loads.

const SLOTS := 3
const BACKUPS := 3
## Seconds the newest backup must have aged before the backups move along, so each really is an older copy.
const BACKUP_EVERY := 300.0
const VERSION := 1
const SETTINGS_FILE := "settings.json"
## The single profile kept before there were save slots; the first start moves it into slot 1 and the settings file.
const OLD_FILE := "profile.json"
## The camp's choices, kept with each game so it opens where it was left.
const CHOICES := ["province", "commander", "difficulty"]
## The kinds of best time kept for each difficulty: the fastest win, the fastest win with Decimatio and the longest Endless run.
const TIME_MODES := ["win", "decimatio", "endless"]
const NO_SAVE_FLAGS := ["run-tests", "bench", "autoplay", "skip", "shot", "at", "screen", "page", "text-size", "lang", "card", "easy", "hard", "endless", "decimatio",
	"commander", "chieftain-at", "as-demo", "objectives-near", "boss", "boss-act", "god", "god-at", "give", "go-to", "hold-choice", "win-at", "timber", "max-state",
	"province", "seed", "men", "mortal", "trailer-shot", "cart", "cart-at", "select", "livery", "no-save"]

const SETTING_DEFAULTS := {"master": 0.8, "music": 0.8, "effects": 0.8, "fullscreen": false, "shake": true, "numbers": true, "blood": true,
	"text_size": 1, "bindings": {}, "language": ""}

var disabled := false
## The folder the slots and the settings are kept in: the user folder, or user://NAME with --save-dir=NAME.
var dir := "user://"
## The slot being played, or 0 before a game is chosen.
var slot := 0
var data := {}
## The player's settings as saved; `setting()` gives the default of any not saved.
var settings := {}
## Whether the last save of the game being played failed, so the camp and the summary can say so until a save succeeds.
var last_save_failed := false
## Each loaded slot's save as read, by slot, laid under the game when it is saved so the fields this build does not know are kept.
var _kept := {}


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	disabled = blocks_saving(args)
	dir = save_dir_of(args)
	data = defaults()
	if reads():
		start_up()


## Whether the saves are read: always when saving, and for a look only from a folder of its own, so a look never reads the player's games.
func reads() -> bool:
	return not disabled or dir != "user://"


## Whether these command-line arguments are for looking or testing, so the saves must not be read or written.
static func blocks_saving(user_args: PackedStringArray) -> bool:
	for a in user_args:
		if a.trim_prefix("--").split("=", true, 1)[0] in NO_SAVE_FLAGS:
			return true
	return false


## The folder the saves are kept in for these command-line arguments.
static func save_dir_of(user_args: PackedStringArray) -> String:
	for a in user_args:
		if a.begins_with("--save-dir="):
			return "user://".path_join(a.trim_prefix("--save-dir="))
	return "user://"


static func defaults() -> Dictionary:
	return {
		"denarii": 0,
		"ranks": {},
		"unlocked": {"commanders": ["tribune"], "provinces": ["germania"]},
		"records": {},
		"seen": {},
		"totals": {"kills": 0, "runs": 0, "wins": 0, "ravine_tips": 0},
		"choices": {},
		"achievements": [],
	}


static func default_record() -> Dictionary:
	return {"best_time": 0.0, "longest": 0.0, "won": false, "hard_won": false, "endless_best": 0.0, "times": {}}


## Moves an old profile into the slots, reads the settings and opens the game saved last.
func start_up() -> void:
	migrate_old_profile()
	load_settings()
	var n := latest_slot()
	if n > 0:
		load_slot(n)


func path_for(n: int) -> String:
	return dir.path_join("save_%d.json" % n)


func settings_path() -> String:
	return dir.path_join(SETTINGS_FILE)


## Saves the game being played in its slot: written to a temporary file and read back before it replaces the save, with the
## older saves kept as rolling backups. Does nothing when disabled or before a game is chosen.
func save() -> bool:
	if disabled or slot < 1 or slot > SLOTS:
		return false
	last_save_failed = not _save_slot()
	return not last_save_failed


func _save_slot() -> bool:
	if made_by_newer(_newest(slot)):
		return false
	var path := path_for(slot)
	var out := laid_over(_kept.get(slot, {}), data.duplicate(true))
	out.version = VERSION
	out.saved_at = Time.get_unix_time_from_system()
	var tmp := path + ".tmp"
	if not _write(tmp, JSON.stringify(out, "\t")) or not _set_aside_unreadable(slot):
		return false
	_rotate_backups(path)
	return _move(tmp, path)


## Loads a slot from its save, or from the newest backup that can be read when it cannot. False when none can, or when a newer
## version of the game made it, since this build would lose what it does not understand.
func load_slot(n: int) -> bool:
	if n < 1 or n > SLOTS:
		return false
	var d := _newest(n)
	if d.is_empty() or made_by_newer(d):
		return false
	data = merge_saved(d)
	_kept[n] = d
	slot = n
	last_save_failed = false
	return true


## A slot's save as read from the best file it can be loaded from, or empty when none can be read.
func _newest(n: int) -> Dictionary:
	for path in _load_order(n):
		var d := _read(path)
		if not d.is_empty():
			return d
	return {}


## Whether a save was written by a newer version of the game than this one.
static func made_by_newer(saved: Dictionary) -> bool:
	return _is_number(saved.get("version")) and int(saved.version) > VERSION


## Starts a new game in the first free slot and saves it there. Returns the slot, or 0 when all three are taken and nothing changes.
func new_game() -> int:
	var n := free_slot()
	if n == 0:
		return 0
	data = defaults()
	_kept.erase(n)
	slot = n
	save()
	return n


## The first slot with no file of a game in it, or 0 when all three are taken.
func free_slot() -> int:
	for n in range(1, SLOTS + 1):
		if not slot_taken(n):
			return n
	return 0


## Whether any file of a game is in the slot, readable or not, so a new game never goes over one that could still be rescued.
func slot_taken(n: int) -> bool:
	return reads() and (_candidates(n) + [path_for(n) + ".tmp"]).any(func(path: String) -> bool: return FileAccess.file_exists(path))


## Deletes a slot's save and its backups; deleting the game being played leaves none open.
func delete_slot(n: int) -> void:
	if disabled:
		return
	for path in _candidates(n) + [path_for(n) + ".tmp"]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	_kept.erase(n)
	if slot == n:
		slot = 0
		data = defaults()


## What the load list shows of a slot: the provinces won, the denarii, the runs, when it was saved and whether a newer version of the
## game made it, or empty when nothing of it can be read.
func slot_info(n: int) -> Dictionary:
	var d := _newest(n)
	if d.is_empty():
		return {}
	var game := merge_saved(d)
	var won: Array = game.records.keys().filter(func(p: String) -> bool: return bool(game.records[p].won))
	var at: Variant = d.get("saved_at", 0.0)
	return {"won": won, "denarii": int(game.denarii), "runs": int(game.totals.runs), "saved_at": float(at) if _is_number(at) else 0.0, "newer": made_by_newer(d)}


## The slot saved most recently of those this build can play, or 0 when there are none.
func latest_slot() -> int:
	var best := 0
	var when := -1.0
	for n in range(1, SLOTS + 1):
		var info := slot_info(n)
		if not info.is_empty() and not info.newer and float(info.saved_at) >= when:
			when = float(info.saved_at)
			best = n
	return best


## Reads the settings from their file, or from the temporary file or the backup a save left when the file is missing or damaged.
func load_settings() -> void:
	settings = {}
	for path in [settings_path(), settings_path() + ".tmp", settings_path() + ".bak"]:
		var saved: Variant = _parse_json(path)
		if saved is Dictionary:
			settings = merge_settings(saved)
			return


## Writes the settings through a temporary file, keeping the last readable ones as a backup. Does nothing when disabled.
func save_settings() -> bool:
	if disabled:
		return false
	var path := settings_path()
	if not _write(path + ".tmp", JSON.stringify(settings, "\t")):
		return false
	# A failed move on Windows can delete the old file before the new one takes its place.
	if _parse_json(path) is Dictionary:
		DirAccess.copy_absolute(ProjectSettings.globalize_path(path), ProjectSettings.globalize_path(path + ".bak"))
	return _move(path + ".tmp", path)


## Moves the old single profile into slot 1 and the settings file, keeping it whole beside them as profile.json.migrated.
## It runs only while every slot is free, so a profile already moved is never copied twice.
func migrate_old_profile() -> bool:
	var old := dir.path_join(OLD_FILE)
	if disabled or not FileAccess.file_exists(old):
		return false
	for n in range(1, SLOTS + 1):
		if slot_taken(n):
			return false
	var saved := _read_json(old)
	if saved.is_empty():
		return false
	if saved.get("settings") is Dictionary and not FileAccess.file_exists(settings_path()):
		settings = merge_settings(saved.settings)
		if not save_settings():
			return false
	data = merge_saved(saved)
	slot = 1
	if not save():
		data = defaults()
		slot = 0
		return false
	return _move(old, old + ".migrated")


static func _is_number(v: Variant) -> bool:
	return v is int or v is float


## `over` laid over `under`: dictionaries in both are merged key by key, and any other value in `over` replaces the one in `under`.
static func laid_over(under: Dictionary, over: Dictionary) -> Dictionary:
	var out := under.duplicate(true)
	for key in over:
		out[key] = laid_over(out[key], over[key]) if out.get(key) is Dictionary and over[key] is Dictionary else over[key]
	return out


## The defaults with every readable, correctly typed value from `saved` laid over them.
static func merge_saved(saved: Dictionary) -> Dictionary:
	var out := defaults()
	if _is_number(saved.get("denarii")):
		out.denarii = maxi(0, int(saved.denarii))
	if saved.get("ranks") is Dictionary:
		for id in saved.ranks:
			if _is_number(saved.ranks[id]):
				out.ranks[str(id)] = maxi(0, int(saved.ranks[id]))
	if saved.get("unlocked") is Dictionary:
		for kind in ["commanders", "provinces"]:
			if saved.unlocked.get(kind) is Array:
				for id in saved.unlocked[kind]:
					if id is String and not out.unlocked[kind].has(id):
						out.unlocked[kind].append(id)
	if saved.get("records") is Dictionary:
		for id in saved.records:
			if saved.records[id] is Dictionary:
				out.records[str(id)] = _merge_record(saved.records[id])
	if saved.get("seen") is Dictionary:
		for id in saved.seen:
			if saved.seen[id] is bool and saved.seen[id]:
				out.seen[str(id)] = true
	if saved.get("totals") is Dictionary:
		for key in out.totals:
			if _is_number(saved.totals.get(key)):
				out.totals[key] = maxi(0, int(saved.totals[key]))
	if saved.get("achievements") is Array:
		for id in saved.achievements:
			if id is String and not out.achievements.has(id):
				out.achievements.append(id)
	# The old single profile keeps the camp's choices among its settings.
	var choices: Variant = saved.get("choices", saved.get("settings"))
	if choices is Dictionary:
		for key in CHOICES:
			var v: Variant = choices.get(key)
			if v is String and (key != "difficulty" or v in Sim.DIFFICULTIES):
				out.choices[key] = v
	return out


## The player's settings from `saved`, keeping only known ones of the right kind.
static func merge_settings(saved: Dictionary) -> Dictionary:
	var out := {}
	for key in saved:
		if SETTING_DEFAULTS.has(key):
			var v: Variant = _checked_setting(str(key), saved[key])
			if v != null:
				out[str(key)] = v
	return out


## A saved setting made safe, or null when it is the wrong kind of value.
static func _checked_setting(key: String, v: Variant) -> Variant:
	match key:
		"master", "music", "effects":
			return clampf(float(v), 0.0, 1.0) if _is_number(v) else null
		"fullscreen", "shake", "numbers", "blood":
			return v if v is bool else null
		"text_size":
			return clampi(int(v), 1, 2) if _is_number(v) and int(v) in [1, 2] else null
		"language":
			return v if v is String else null
		"bindings":
			if not v is Dictionary:
				return null
			var out := {}
			for action in v:
				if not v[action] is Dictionary:
					continue
				var entry := {}
				for kind in ["keys", "pads"]:
					if v[action].get(kind) is Array:
						var codes: Array = v[action][kind].filter(func(n): return _is_number(n) and n == floorf(n) and n >= (1 if kind == "keys" else 0)).map(func(n): return int(n))
						if not codes.is_empty():
							entry[kind] = codes
				if not entry.is_empty():
					out[str(action)] = entry
			return out
	return v


## Every setting, the saved value or its default.
static func settings_of(saved: Dictionary) -> Dictionary:
	var out: Dictionary = SETTING_DEFAULTS.duplicate(true)
	for key in saved:
		if SETTING_DEFAULTS.has(key):
			out[key] = saved[key]
	return out


func setting(key: String) -> Variant:
	return settings.get(key, SETTING_DEFAULTS[key])


static func _merge_record(saved: Dictionary) -> Dictionary:
	var rec := default_record()
	for key in rec:
		var v: Variant = saved.get(key)
		if rec[key] is bool and v is bool:
			rec[key] = v
		elif rec[key] is float and _is_number(v):
			rec[key] = float(v)
	rec.times = times_of(saved)
	return rec


## A record's best times as {difficulty: {mode: seconds}}; a record with no times has one of unknown difficulty, counted as Medium's.
static func times_of(rec: Dictionary) -> Dictionary:
	var out := {}
	var saved: Variant = rec.get("times")
	if not saved is Dictionary:
		saved = {"medium": {"win": rec.get("best_time", 0.0), "endless": rec.get("endless_best", 0.0)}}
	for d in Sim.DIFFICULTIES:
		var modes: Variant = saved.get(d)
		if not modes is Dictionary:
			continue
		for m in TIME_MODES:
			if _is_number(modes.get(m)) and float(modes[m]) > 0.0:
				if not out.has(d):
					out[d] = {}
				out[d][m] = float(modes[m])
	return out


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = _parse_json(path)
	return parsed if parsed is Dictionary else {}


## A file's JSON, or null when it is missing or damaged.
func _parse_json(path: String) -> Variant:
	if not reads() or not FileAccess.file_exists(path):
		return null
	var json := JSON.new()
	return json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null


## A save's contents, or empty when the file is missing, damaged or not a save.
func _read(path: String) -> Dictionary:
	var d := _read_json(path)
	return d if d.has("version") else {}


## Writes a file and reads it back, so a full disk or a failed write is caught before it can replace anything.
func _write(path: String, text: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Could not write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return false
	var stored := f.store_string(text)
	f.close()
	if not stored or FileAccess.get_file_as_string(path) != text:
		push_warning("Could not write %s" % path)
		return false
	return true


func _move(from: String, to: String) -> bool:
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(from), ProjectSettings.globalize_path(to))
	if err != OK:
		push_warning("Could not move %s to %s: %s" % [from, to, error_string(err)])
	return err == OK


## A slot's save and its backups, newest first.
func _candidates(n: int) -> Array:
	var list := [path_for(n)]
	for i in range(1, BACKUPS + 1):
		list.append("%s.bak%d" % [path_for(n), i])
	return list


## The files a slot is read from, best first: a save cut off before its .tmp replaced the save leaves the newest there.
func _load_order(n: int) -> Array:
	var list := _candidates(n)
	var tmp := path_for(n) + ".tmp"
	if _saved_at(tmp) > _saved_at(path_for(n)):
		list.push_front(tmp)
	return list


## When a save was made, or -1 for a file that is missing or not whole, so a half-written .tmp never wins.
func _saved_at(path: String) -> float:
	var d := _read(path)
	var at: Variant = d.get("saved_at", 0.0)
	return (float(at) if _is_number(at) else 0.0) if not d.is_empty() else -1.0


## A game none of whose files can be read is moved aside under a plain name rather than saved over, so it can be rescued.
func _set_aside_unreadable(n: int) -> bool:
	var found := _candidates(n).filter(func(path: String) -> bool: return FileAccess.file_exists(path))
	if found.is_empty() or found.any(func(path: String) -> bool: return not _read(path).is_empty()):
		return true
	var stamp := int(Time.get_unix_time_from_system())
	for path in found:
		if not _move(path, "%s.unreadable-%d" % [path, stamp]):
			return false
	push_warning("Save %d could not be read, so its files are kept beside it as .unreadable copies" % n)
	return true


## Moves each backup one along, the save itself becoming the newest, once the newest backup has aged.
func _rotate_backups(path: String) -> void:
	var newest := path + ".bak1"
	if FileAccess.file_exists(newest) and Time.get_unix_time_from_system() - FileAccess.get_modified_time(newest) < BACKUP_EVERY:
		return
	if _read(path).is_empty():
		return
	# Renaming rather than copying leaves each older copy's contents untouched on the disk.
	for i in range(BACKUPS - 1, 0, -1):
		var older := "%s.bak%d" % [path, i]
		if FileAccess.file_exists(older) and not _move(older, "%s.bak%d" % [path, i + 1]):
			return
	_move(path, newest)


## The quartermaster ranks as the run options expect them.
func bonuses() -> Dictionary:
	return data.ranks.duplicate()


func rank(id: String) -> int:
	return int(data.ranks.get(id, 0))


## What the next rank costs, or -1 when the upgrade is unknown, at its last rank, or waiting for the one it needs.
func next_cost(id: String, content: Content) -> int:
	if not content.quartermaster.has(id):
		return -1
	var info: Dictionary = content.quartermaster[id]
	var r := rank(id)
	if waiting_for(id, content) != "":
		return -1
	if info.get("repeat", false):
		return repeat_cost(float(info.costs[0]), float(info.get("growth", 1.0)), r)
	if r >= int(info.ranks):
		return -1
	return int(info.costs[r])


## The cost of a repeating purchase after `bought` of them, each `growth` times the last, rounded to a tidy sum.
static func repeat_cost(first: float, growth: float, bought: int) -> int:
	var raw := first * pow(growth, bought)
	var step := 10.0 if raw < 1000.0 else (50.0 if raw < 10000.0 else 500.0)
	return int(roundf(raw / step) * step)


## The upgrade that must be finished before this one can be bought, or "" when none is waited for.
func waiting_for(id: String, content: Content) -> String:
	var needs: String = content.quartermaster.get(id, {}).get("needs", "")
	if needs == "" or not content.quartermaster.has(needs):
		return ""
	return "" if rank(needs) >= int(content.quartermaster[needs].ranks) else needs


## Buys the next rank when it exists and the denarii cover it.
func buy(id: String, content: Content) -> bool:
	var cost := next_cost(id, content)
	if cost < 0 or cost > int(data.denarii):
		return false
	data.denarii = int(data.denarii) - cost
	data.ranks[id] = rank(id) + 1
	save()
	return true


func record_of(province: String) -> Dictionary:
	return data.records.get(province, default_record())


## The best time of one difficulty and mode in a province, 0 when there is none.
func mode_time(province: String, difficulty: String, mode: String) -> float:
	return float(times_of(record_of(province)).get(difficulty, {}).get(mode, 0.0))


func commander_unlocked(id: String) -> bool:
	return data.unlocked.commanders.has(id) or (Game.is_demo() and Game.demo_open.has(id))


## The denarii that unlock a commander without earning him, or 0 when he cannot be bought.
static func commander_price(info: Dictionary) -> int:
	return int(info.get("price", 0))


## Buys a locked commander for his price when the denarii cover it.
func buy_commander(id: String, content: Content) -> bool:
	if not content.commanders.has(id) or commander_unlocked(id):
		return false
	var price := commander_price(content.commanders[id])
	if price <= 0 or price > int(data.denarii):
		return false
	data.denarii = int(data.denarii) - price
	data.unlocked.commanders.append(id)
	save()
	return true


## Opens every drawn province with its modes and every commander, maxes every upgrade and fills the codex, for --max-state; it is never saved.
func max_out(content: Content) -> void:
	data.denarii = 1000000
	# Continue opens this game, which is never saved.
	slot = maxi(slot, 1)
	for p in content.provinces:
		if not content.ready("provinces", p):
			continue
		if not province_unlocked(p):
			data.unlocked.provinces.append(p)
		var rec := record_of(p)
		rec.won = true
		rec.hard_won = true
		data.records[p] = rec
	for id in content.commanders:
		if not data.unlocked.commanders.has(id):
			data.unlocked.commanders.append(id)
	# Every upgrade at its last rank; a triumph repeats for ever, so three are held to show their statues.
	for id in content.quartermaster:
		var info: Dictionary = content.quartermaster[id]
		data.ranks[id] = 3 if info.get("repeat", false) else int(info.ranks)
	for kind in Content.GROUPS.keys() + ["enemies", "commanders", "gods"]:
		for id in content.get(kind):
			data.seen[id] = true


func province_unlocked(id: String) -> bool:
	return data.unlocked.provinces.has(id)


## Plain words for how a commander is unlocked.
static func unlock_text(info: Dictionary, content: Content) -> String:
	var rule: Dictionary = info.get("unlock", {})
	match rule.get("type", "free"):
		"win":
			return TranslationServer.translate("Win in %s") % content.provinces.get(rule.get("province", ""), {}).get("name", TranslationServer.translate("a province"))
		"kills":
			return TranslationServer.translate("Defeat %d barbarians in total") % int(rule.get("count", 0))
		"survive":
			return TranslationServer.translate("Survive {minutes} minutes with {soldiers} soldiers or fewer").format({"minutes": int(rule.get("seconds", 0)) / 60, "soldiers": int(rule.get("max_soldiers", 0))})
		"win_all":
			return TranslationServer.translate("Win in every province")
	return TranslationServer.translate("Free")


## Banks a finished run: its denarii (win or lose), the records, the totals, the codex, and every unlock it earned.
func record_run(sim: Sim) -> void:
	data.denarii = int(data.denarii) + sim.banked_denarii()
	data.totals.runs = int(data.totals.runs) + 1
	data.totals.kills = int(data.totals.kills) + sim.kills
	if sim.ravine_tip_shown:
		data.totals.ravine_tips = int(data.totals.ravine_tips) + 1
	var rec: Dictionary = record_of(sim.province)
	rec.longest = maxf(float(rec.longest), sim.time)
	var times := times_of(rec)
	var mine: Dictionary = times.get(sim.difficulty, {})
	# A demo that reaches its time limit shows the victory screen but is not a win.
	var won := sim.victory and not sim.demo_over
	if won:
		data.totals.wins = int(data.totals.wins) + 1
		rec.won = true
		if sim.difficulty == "hard":
			rec.hard_won = true
		var won_at: float = sim.endless_since if sim.endless and sim.endless_since >= 0.0 else sim.time
		if float(rec.best_time) <= 0.0 or won_at < float(rec.best_time):
			rec.best_time = won_at
		var mode := "decimatio" if sim.decimatio else "win"
		if float(mine.get(mode, 0.0)) <= 0.0 or won_at < float(mine[mode]):
			mine[mode] = won_at
	if sim.endless:
		rec.endless_best = maxf(float(rec.endless_best), sim.time)
		mine.endless = maxf(float(mine.get("endless", 0.0)), sim.time)
	if not mine.is_empty():
		times[sim.difficulty] = mine
	rec.times = times
	data.records[sim.province] = rec
	for id in sim.ranks:
		if int(sim.ranks[id]) > 0:
			data.seen[id] = true
	for id in sim.legion.picks:
		data.seen[id] = true
	for u in [sim.commander] + sim.soldiers:
		data.seen[u.type] = true
	for id in sim.killed_kinds:
		data.seen[id] = true
	for id in sim.gods.called:
		data.seen[id] = true
	_unlock(sim)
	save()


## Opens every province whose drawn predecessor has been won. A province waiting for its art is passed over, so winning one opens
## the next that can be played; it also runs at start, so a profile that won a province before the next was drawn finds it open.
func open_won_provinces(content: Content) -> void:
	for p in content.provinces:
		var before: String = content.province_before(p)
		if not content.ready("provinces", p):
			continue
		var won := before == "" or bool(record_of(before).won)
		if won and before != "" and not province_unlocked(p):
			data.unlocked.provinces.append(p)
		# A province stays open only while the one before it on the road is won, unless it has been won itself.
		elif not won and province_unlocked(p) and not bool(record_of(p).won):
			data.unlocked.provinces.erase(p)


func _unlock(sim: Sim) -> void:
	var content: Content = sim.content
	var provinces: Array = content.provinces.keys()
	var all_won := true
	for p in provinces:
		if not bool(record_of(p).won):
			all_won = false
	open_won_provinces(content)
	for id in content.commanders:
		if commander_unlocked(id):
			continue
		var rule: Dictionary = content.commanders[id].get("unlock", {})
		var earned := false
		match rule.get("type", "free"):
			"free":
				earned = true
			"win":
				earned = bool(record_of(rule.get("province", "")).won)
			"kills":
				earned = int(data.totals.kills) >= int(rule.get("count", 0))
			"survive":
				earned = not sim.demo_over and sim.time >= float(rule.get("seconds", 0)) and sim.peak_soldiers <= int(rule.get("max_soldiers", 0))
			"win_all":
				earned = all_won
		if earned:
			data.unlocked.commanders.append(id)
