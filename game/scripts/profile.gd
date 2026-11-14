extends Node
## The saved profile: denarii, quartermaster ranks, unlocks, records, the codex and totals, kept as JSON in the user folder.
## It is an autoload named Profile. Tests and screenshots never touch the real file, since `disabled` is set before anything loads.

const DEFAULT_PATH := "user://profile.json"
const NO_SAVE_FLAGS := ["run-tests", "bench", "autoplay", "skip", "shot", "screen"]

var disabled := false
var path := DEFAULT_PATH
var data := {}


func _init() -> void:
	for a in OS.get_cmdline_user_args():
		if a.trim_prefix("--").split("=", true, 1)[0] in NO_SAVE_FLAGS:
			disabled = true
	data = defaults()
	if not disabled:
		load_file()


static func defaults() -> Dictionary:
	return {
		"denarii": 0,
		"ranks": {},
		"unlocked": {"commanders": ["tribune"], "provinces": ["germania"]},
		"records": {},
		"seen": {},
		"totals": {"kills": 0, "runs": 0, "wins": 0},
		"settings": {},
	}


static func default_record() -> Dictionary:
	return {"best_time": 0.0, "longest": 0.0, "won": false, "hard_won": false, "endless_best": 0.0}


## Reads the file at `path`; a missing, old or damaged file leaves the defaults, and every readable key is kept.
func load_file() -> void:
	data = defaults()
	if not FileAccess.file_exists(path):
		return
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) == OK and json.data is Dictionary:
		data = merge_saved(json.data)


static func _is_number(v: Variant) -> bool:
	return v is int or v is float


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
	if saved.get("settings") is Dictionary:
		for key in saved.settings:
			var v: Variant = saved.settings[key]
			if key in ["province", "commander"] and not v is String:
				continue
			out.settings[str(key)] = v
	return out


static func _merge_record(saved: Dictionary) -> Dictionary:
	var rec := default_record()
	for key in rec:
		var v: Variant = saved.get(key)
		if rec[key] is bool and v is bool:
			rec[key] = v
		elif rec[key] is float and _is_number(v):
			rec[key] = float(v)
	return rec


## Writes the profile through a temporary file so a stopped game never leaves half a save. Does nothing when disabled.
func save() -> void:
	if disabled:
		return
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("Could not save the profile")
		return
	var wrote := f.store_string(JSON.stringify(data, "\t"))
	f.close()
	var moved := ERR_FILE_CANT_WRITE
	if wrote:
		moved = DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(path))
	if moved != OK:
		push_warning("Could not save the profile")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))


## The quartermaster ranks as the run options expect them.
func bonuses() -> Dictionary:
	return data.ranks.duplicate()


func rank(id: String) -> int:
	return int(data.ranks.get(id, 0))


## What the next rank costs, or -1 when the upgrade is unknown or at its last rank.
func next_cost(id: String, content: Content) -> int:
	if not content.quartermaster.has(id):
		return -1
	var info: Dictionary = content.quartermaster[id]
	var r := rank(id)
	if r >= int(info.ranks):
		return -1
	return int(info.costs[r])


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


func commander_unlocked(id: String) -> bool:
	return data.unlocked.commanders.has(id)


func province_unlocked(id: String) -> bool:
	return data.unlocked.provinces.has(id)


## Plain words for how a commander is unlocked.
static func unlock_text(info: Dictionary, content: Content) -> String:
	var rule: Dictionary = info.get("unlock", {})
	match rule.get("type", "free"):
		"win":
			return "Win in %s" % content.provinces.get(rule.get("province", ""), {}).get("name", "a province")
		"kills":
			return "Defeat %d barbarians in total" % int(rule.get("count", 0))
		"survive":
			return "Survive %d minutes with %d soldiers or fewer" % [int(rule.get("seconds", 0)) / 60, int(rule.get("max_soldiers", 0))]
		"win_all":
			return "Win in every province"
	return "Free"


## Banks a finished run: its denarii (win or lose), the records, the totals, the codex, and every unlock it earned.
func record_run(sim: Sim) -> void:
	data.denarii = int(data.denarii) + sim.denarii
	data.totals.runs = int(data.totals.runs) + 1
	data.totals.kills = int(data.totals.kills) + sim.kills
	var rec: Dictionary = record_of(sim.province)
	rec.longest = maxf(float(rec.longest), sim.time)
	if sim.victory:
		data.totals.wins = int(data.totals.wins) + 1
		if sim.hard:
			rec.hard_won = true
		else:
			rec.won = true
		if float(rec.best_time) <= 0.0 or sim.time < float(rec.best_time):
			rec.best_time = sim.time
	if sim.endless:
		rec.endless_best = maxf(float(rec.endless_best), sim.time)
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
	_unlock(sim)
	save()


func _unlock(sim: Sim) -> void:
	var content: Content = sim.content
	var provinces: Array = content.provinces.keys()
	var all_won := true
	for p in provinces:
		if not bool(record_of(p).won):
			all_won = false
	for i in provinces.size() - 1:
		if bool(record_of(provinces[i]).won) and not province_unlocked(provinces[i + 1]):
			data.unlocked.provinces.append(provinces[i + 1])
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
				earned = sim.victory and sim.time >= float(rule.get("seconds", 0)) and sim.peak_soldiers <= int(rule.get("max_soldiers", 0))
			"win_all":
				earned = all_won
		if earned:
			data.unlocked.commanders.append(id)
