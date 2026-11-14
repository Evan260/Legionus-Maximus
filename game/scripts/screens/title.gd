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
	elif id == "wishlist":
		Steamworks.open_store()


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
	var logo_pos := Vector2((Ui.W - logo.get_width()) / 2.0, 12.0 if big else 40.0)
	c.draw_texture(logo, logo_pos)
	if Game.is_demo():
		var tag := Rect2(logo_pos.x + logo.get_width() - 56.0, logo_pos.y + logo.get_height() - 8.0, 56.0, 8.0 + 8.0 * Ui.scale)
		ui.panel(c, tag)
		ui.text(c, tr("Demo").to_upper(), Vector2(tag.position.x, tag.end.y - 4.0 - Ui.px * 3 / 8), Ui.RED, HORIZONTAL_ALIGNMENT_CENTER, tag.size.x)
	if big:
		ui.panel(c, Rect2(Ui.W / 2 - 210, 108, 420, 64))
		ui.text(c, tr("Your soldiers fight on their own."), Vector2(0, 134), Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, Ui.W)
		ui.text(c, tr("Kill the chieftain to win.") if not Game.is_demo() else Game.goal_text(main.balance), Vector2(0, 158), Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, Ui.W)
	else:
		ui.panel(c, Rect2(Ui.W / 2 - 130, 140, 260, 92))
		var lines := [
			tr("%s  march") % _march_keys(),
			tr("%s  testudo: shields up, 80%% less harm") % Controls.slot_text(saved, "testudo", "keys", 0),
			tr("%s  pause") % Controls.slot_text(saved, "pause", "keys", 0),
			"",
			tr("Your soldiers fight on their own."),
			Game.goal_text(main.balance),
		]
		for i in lines.size():
			ui.text(c, lines[i], Vector2(0, 156 + i * 11), Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, Ui.W)
	var top := 190.0 if big else 250.0
	var h := 34.0 if big else 24.0
	ui.button(c, Rect2(Ui.W / 2 - 100, top, 200, h), "march", tr("March").to_upper(), "", true, null, true)
	ui.button(c, Rect2(Ui.W / 2 - 100, top + h + 10, 200, h), "settings", tr("Settings").to_upper(), "", true, null, true)
	if Game.is_demo() and int(main.balance.demo.store_app_id) > 0:
		ui.button(c, Rect2(Ui.W / 2 - 100, top + 2.0 * (h + 10), 200, h), "wishlist", tr("Wishlist on Steam").to_upper(), "", true, null, true)
