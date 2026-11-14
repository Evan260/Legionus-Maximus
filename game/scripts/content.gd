class_name Content
extends RefCounted
## Every recruit, weapon, drill, enemy and province, read from content.json. An entry whose art is not drawn yet stays hidden.

const KINDS := ["recruits", "enemies", "arms", "forged", "drills", "provinces", "commanders", "quartermaster", "achievements"]
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
var base_commander := {}
var available := {}


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
	return out


static func load_all(available_keys: Dictionary) -> Content:
	var c := Content.new()
	c.available = available_keys
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/content.json"))
	c.base_commander = data.base_commander
	for kind in KINDS:
		c.set(kind, data[kind])
	return c


## True when every art key of the entry exists.
func ready(kind: String, id: String) -> bool:
	var entry: Dictionary = get(kind).get(id, {})
	if entry.is_empty():
		return false
	for key in entry.get("art", []):
		if not available.has(key):
			return false
	return true


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


func icon_key(id: String) -> String:
	for key in upgrade(id).get("art", []):
		if key.begins_with("icon:"):
			return key.trim_prefix("icon:")
	return ""
