extends SceneTree
## Runs the game as a phone shows it, for the phone stores' screenshots: the display, the phone's interface and its touch
## controls. Every flag the game takes works as usual, so --shot and --at save the picture. The achievement cards a
## skipped run earns are left out, as the trailer leaves them out, since they would cover the top corner, and so is the
## tip a first run gets at its first ravine. This script adds flags of its own:
##   Godot --path game --resolution WxH --script PATH_TO_THIS -- --phone ... --thumb --shot=PATH --at=SECONDS
##   --thumb                 a thumb holds the stick where it rests at the start of a run, pushed the way the legion marches
##   --objectives-done=K,K   the camp, column or grove named (all three with no names) taken already, so their badges are gone
##   --boss-shift=X,Y        moves the elites and the chieftain that --boss brought by X,Y game pixels before they act

var main: Node
var thumb := false
var done := PackedStringArray()
var shift := Vector2.ZERO
var staged := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--thumb":
			thumb = true
		elif a.begins_with("--objectives-done"):
			done = a.trim_prefix("--objectives-done").trim_prefix("=").split(",", false)
			if done.is_empty():
				done = PackedStringArray(["camp", "column", "grove"])
		elif a.begins_with("--boss-shift="):
			var xy := a.trim_prefix("--boss-shift=").split(",")
			shift = Vector2(float(xy[0]), float(xy[1]))
	root.add_child(load("res://scenes/display.tscn").instantiate())
	main = root.get_node("Display/Game/Main")


func _process(_dt: float) -> bool:
	var steam := root.get_node("Steamworks")
	steam.queue.clear()
	steam.card = {}
	if main.sim == null or main.state != "play":
		return false
	var sim = main.sim
	if not staged:
		staged = true
		_stage(sim)
	var pad = main.touch_pad
	if not thumb or pad == null:
		return false
	# The march the look holds to, worked out as main.gd's autoplay does, so the stick leans the way the legion goes.
	var march: Vector2 = main.look_march
	if march == Vector2.INF:
		march = Vector2(cos(sim.time * 0.4), sin(sim.time * 0.4))
	var r: float = pad.radius()
	var view: Vector2 = pad.get_viewport_rect().size
	pad._stick = 0
	pad._base = Vector2(Touch.inset_tl.x + r * 1.5, view.y - Touch.inset_br.y - r * 1.9)
	pad._finger = pad._base + march.limit_length(1.0) * r * 0.75
	return false


## Runs before the game's first step of the look, so a boss moved here marks his lane from where he stands.
func _stage(sim) -> void:
	# A player past the first few runs no longer gets the tip on crossing ravines and canals.
	sim.ravine_tip = false
	for o in sim.objectives.list:
		if o.kind in done:
			o.done = true
			o.done_at = -100.0
	var h = sim.horde
	for i in h.e_pos.size():
		if h.elite_ids.has(h.e_id[i]) or h.e_tag[i] == Horde.CHIEF:
			h.e_pos[i] += shift
