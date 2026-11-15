class_name Atlas
extends RefCounted
## Every sprite in the game lives in one texture, so the whole horde is drawn in a single batch.

## Frames a second of an attack, so a strike is over in half a second, before the quickest soldier strikes again.
const ATTACK_FPS := 16.0
const ATTACK_FRAMES := 8.0

var texture: Texture2D
var units := {}
var props := {}


func _init() -> void:
	texture = load("res://assets/atlas.png")
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/atlas.json"))
	units = meta.units
	props = meta.props


## The frame to draw and where its top-left corner goes for a unit standing at pos.
func unit_frame(type: String, action: String, dir: String, t: float) -> Array:
	var anim: Dictionary = units[type][action][dir]
	var frames: Array = anim.frames
	var f: Array = frames[int(t) % frames.size()]
	return [Rect2(f[0], f[1], f[2], f[3]), Vector2(anim.anchor[0], anim.anchor[1])]


## The attack frame `since` seconds into a strike, played once, or an empty array when the strike is over or the unit has no attack.
func attack_frame(type: String, dir: String, since: float) -> Array:
	var unit: Dictionary = units[type]
	if since < 0.0 or not unit.has("attack"):
		return []
	var anim: Dictionary = unit.attack[dir]
	var i := int(since * ATTACK_FPS)
	if i >= anim.frames.size():
		return []
	var f: Array = anim.frames[i]
	return [Rect2(f[0], f[1], f[2], f[3]), Vector2(anim.anchor[0], anim.anchor[1])]


func prop_frame(name: String) -> Array:
	var p: Dictionary = props[name]
	var f: Array = p.frames[0]
	return [Rect2(f[0], f[1], f[2], f[3]), Vector2(p.anchor[0], p.anchor[1])]
