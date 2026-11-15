extends SceneTree
## Runs the game with no interface over the field, no damage numbers and no screen shake, and saves one picture, for the
## Steam capsules. Every flag the game takes works as usual; this script adds two of its own.
##   Godot --path game --resolution WxH --script PATH_TO_THIS -- --autoplay ... --store-shot=PATH --store-at=SECONDS

var main: Node
var shot_path := ""
var shot_at := 3.0
var clock := 0.0
var saving := false


func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--store-shot="):
			shot_path = a.split("=", true, 1)[1]
		elif a.begins_with("--store-at="):
			shot_at = float(a.split("=", true, 1)[1])
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)


func _process(dt: float) -> bool:
	clock += dt
	if main.sim != null:
		main.sim.show_numbers = false
	main.world.shake_on = false
	main.get_node("UI").visible = false
	if clock >= shot_at and not saving:
		saving = true
		_save()
	return false


func _save() -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(shot_path)
	quit()
