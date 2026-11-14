class_name Atlas
extends RefCounted
## Every sprite in the game lives in one texture, so the whole horde is drawn in a single batch.

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


func prop_frame(name: String) -> Array:
	var p: Dictionary = props[name]
	var f: Array = p.frames[0]
	return [Rect2(f[0], f[1], f[2], f[3]), Vector2(p.anchor[0], p.anchor[1])]
