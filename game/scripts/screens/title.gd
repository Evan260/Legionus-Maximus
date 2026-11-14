class_name TitleScreen
extends RefCounted
## The title: the logo, how to play, and the buttons that start the camp or open the settings.

var main: Node
var logo: Texture2D


func _init(owner_node: Node) -> void:
	main = owner_node
	logo = load("res://assets/logo.png")


func activate(id: String) -> void:
	if id == "march":
		main.go_to_camp()
	elif id == "settings":
		main.open_settings("title")


## The first key of each marching action, for the how-to-play line.
func _march_keys() -> String:
	var saved: Dictionary = Profile.setting("bindings")
	var names: Array = []
	for a in ["up", "left", "down", "right"]:
		names.append(Controls.slot_text(saved, a, "keys", 0))
	return " ".join(names)


func draw(c: CanvasItem, ui: Ui) -> void:
	var big := Ui.scale > 1
	var saved: Dictionary = Profile.setting("bindings")
	c.draw_texture(logo, Vector2((Ui.W - logo.get_width()) / 2.0, 12.0 if big else 40.0))
	if big:
		ui.panel(c, Rect2(Ui.W / 2 - 210, 108, 420, 64))
		ui.text(c, "Your soldiers fight on their own.", Vector2(0, 134), Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, Ui.W)
		ui.text(c, "Kill the chieftain to win.", Vector2(0, 158), Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, Ui.W)
	else:
		ui.panel(c, Rect2(Ui.W / 2 - 130, 140, 260, 92))
		var lines := [
			"%s  march" % _march_keys(),
			"%s  testudo: shields up, 80%% less harm" % Controls.slot_text(saved, "testudo", "keys", 0),
			"%s  pause" % Controls.slot_text(saved, "pause", "keys", 0),
			"",
			"Your soldiers fight on their own.",
			"Survive 10 minutes and kill the chieftain.",
		]
		for i in lines.size():
			ui.text(c, lines[i], Vector2(0, 156 + i * 11), Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, Ui.W)
	var top := 190.0 if big else 250.0
	var h := 34.0 if big else 24.0
	ui.button(c, Rect2(Ui.W / 2 - 100, top, 200, h), "march", "MARCH", "", true, null, true)
	ui.button(c, Rect2(Ui.W / 2 - 100, top + h + 10, 200, h), "settings", "SETTINGS", "", true, null, true)
