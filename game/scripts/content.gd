class_name Content
extends RefCounted
## Every recruit, weapon, drill, enemy and province, read from content.json. An entry whose art is not drawn yet stays hidden.

const KINDS := ["recruits", "enemies", "arms", "forged", "drills", "provinces", "commanders", "quartermaster", "achievements", "gods"]
const GROUPS := {"recruits": "Recruit", "arms": "Arms", "forged": "Forged", "drills": "Drill"}

var recruits := {}
var enemies := {}
var arms := {}
var forged := {}
var drills := {}
var provinces := {}
var commanders := {}
var quartermaster := {}
var achievements := {}
var gods := {}
var base_commander := {}
var available := {}
# The English words as the file has them, which the translations are laid over by localize().
var _english := {}
## The fields of an entry that the player reads; the others are data.
const WORDS := ["name", "text", "history", "more"]


## The art keys that exist: "unit:<name>" and "prop:<name>" from the atlas, "icon:<name>" from the icons folder.
static func available_art() -> Dictionary:
	var out := {}
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/atlas.json"))
	for name in meta.units:
		out["unit:" + name] = true
	for name in meta.props:
		out["prop:" + name] = true
	for file in ResourceLoader.list_directory("res://assets/icons/"):
		if file.ends_with(".png"):
			out["icon:" + file.get_basename()] = true
	for file in ResourceLoader.list_directory("res://assets/grounds/"):
		if file.ends_with(".png"):
			out["ground:" + file.get_basename()] = true
	return out


static func load_all(available_keys: Dictionary) -> Content:
	var c := Content.new()
	c.available = available_keys
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))
	c.base_commander = data.base_commander
	for kind in KINDS:
		c.set(kind, data[kind])
	c._english = data.duplicate(true)
	c.localize()
	return c


## The translation key of an entry's field, such as "content.recruits.legionary.name"; tools/extract_strings.py builds the same keys.
static func key_of(kind: String, id: String, field: String) -> String:
	return "content.%s.%s.%s" % [kind, id, field]


## Puts the words of the language showing into every entry, keeping the English where a language has no translation.
func localize() -> void:
	var cmd: Dictionary = _english.base_commander
	base_commander.name = _words("base_commander", "", "name", cmd.name)
	for kind in KINDS:
		var entries: Dictionary = get(kind)
		for id in entries:
			var english: Dictionary = _english[kind][id]
			for field in WORDS:
				if english.has(field):
					entries[id][field] = _words(kind, id, field, english[field])


func _words(kind: String, id: String, field: String, english: String) -> String:
	var key := key_of(kind, id, field) if id != "" else "content.%s.%s" % [kind, field]
	var out := TranslationServer.translate(key)
	return english if out == key or out == "" else out


## Content with every art key counted as drawn, for tests and the bench that need enemies and props that have no art yet.
static func with_all_art() -> Content:
	var c := load_all({})
	for kind in KINDS:
		for id in c.get(kind):
			var entry: Variant = c.get(kind)[id]
			if entry is Dictionary:
				for key in entry.get("art", []):
					c.available[key] = true
	c.available["prop:chest"] = true
	c.available["prop:supply_cart"] = true
	return c


## The ground texture of a province, falling back to Germania's when a province has none.
static func ground_path(province: String) -> String:
	var path := "res://assets/grounds/%s.png" % province
	return path if ResourceLoader.exists(path) else "res://assets/grounds/germania.png"


## True when every art key of the entry exists.
func ready(kind: String, id: String) -> bool:
	var entry: Dictionary = get(kind).get(id, {})
	if entry.is_empty():
		return false
	for key in entry.get("art", []):
		if not available.has(key):
			return false
	return true


## The drawn province before `id` in the list, which must be won to open it; empty when no drawn province comes before it.
func province_before(id: String) -> String:
	var ids: Array = provinces.keys()
	for k in range(ids.find(id) - 1, -1, -1):
		if ready("provinces", ids[k]):
			return ids[k]
	return ""


## The ordinary enemies of a province that are drawn.
func province_enemies(province: String) -> Array:
	var out: Array = []
	for id in provinces[province].ordinary:
		if ready("enemies", id):
			out.append(id)
	return out


## Base stats of a soldier type, or of the commander.
func unit(type: String) -> Dictionary:
	return base_commander if type == "commander" else recruits[type]


## The level-up entry (recruit, weapon or drill) for an id, or an empty one.
func upgrade(id: String) -> Dictionary:
	for kind in GROUPS:
		if get(kind).has(id):
			return get(kind)[id]
	return {}


func group_of(id: String) -> String:
	for kind in GROUPS:
		if get(kind).has(id):
			return GROUPS[kind]
	return ""


## The player-facing name of a damage source: a soldier type, a weapon, or the commander. Empty when unknown.
func source_name(id: String) -> String:
	if id == "commander":
		return str(base_commander.get("name", ""))
	if gods.has(id):
		return str(gods[id].name)
	return str(upgrade(id).get("name", ""))


func icon_key(id: String) -> String:
	for key in (gods[id] if gods.has(id) else upgrade(id)).get("art", []):
		if key.begins_with("icon:"):
			return key.trim_prefix("icon:")
	return ""
