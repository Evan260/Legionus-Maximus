class_name CampScreen
extends RefCounted
## The camp between runs: the legion stands idle on the field behind four boards and the march button.

const BOARDS := [["quartermaster", "Quartermaster"], ["tablinum", "Tablinum"], ["map", "Map"], ["commanders", "Commanders"]]

var main: Node


func _init(owner_node: Node) -> void:
	main = owner_node


func sub_line(id: String) -> String:
	var content: Content = main.content
	match id:
		"quartermaster":
			return "%d denarii" % int(Profile.data.denarii)
		"tablinum":
			return "%d found" % Profile.data.seen.size()
		"map":
			return content.provinces[main.run_setup.province].name
		"commanders":
			return content.commanders[main.run_setup.commander].name
	return ""


func draw(c: CanvasItem, ui: Ui) -> void:
	var big := Ui.scale > 1
	ui.panel(c, Rect2(Ui.W / 2 - 80, 8, 160, 30 if big else 22))
	ui.text(c, "THE CAMP", Vector2(0, 31 if big else 23), Ui.BROWN, HORIZONTAL_ALIGNMENT_CENTER, Ui.W)
	ui.text(c, "%d DENARII" % int(Profile.data.denarii), Vector2(0, 28 if big else 20), Ui.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_RIGHT, Ui.W - 12, true)
	var setup: Dictionary = main.run_setup
	var modes: Array = []
	for key in ["hard", "endless", "decimatio"]:
		if setup[key]:
			modes.append(key.capitalize())
	var line: String = "%s, %s" % [main.content.provinces[setup.province].name, main.content.commanders[setup.commander].name]
	if not modes.is_empty():
		line += ", " + " + ".join(modes)
	ui.text(c, ui.clip(line, Ui.W - 16.0), Vector2(0, 198 if big else 252), Ui.CREAM, HORIZONTAL_ALIGNMENT_CENTER, Ui.W, true)
	ui.button(c, Rect2(Ui.W / 2 - 80, 204 if big else 258, 160, 28 if big else 24), "march", "MARCH", "", true, null, true)
	if big:
		_boards_large(c, ui)
		return
	var bw := 140.0
	var gap := 12.0
	var x0 := (Ui.W - 4 * bw - 3 * gap) / 2.0
	for i in BOARDS.size():
		var r := Rect2(x0 + i * (bw + gap), 300, bw, 40)
		var id: String = BOARDS[i][0]
		ui.button(c, r, id, "", "", true, null, true)
		ui.text(c, BOARDS[i][1].to_upper(), Vector2(r.position.x, r.position.y + 16), Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, bw)
		ui.text(c, ui.clip(sub_line(id), bw - 12), Vector2(r.position.x, r.position.y + 30), Ui.BROWN, HORIZONTAL_ALIGNMENT_CENTER, bw)
	ui.text(c, "Esc  title", Vector2(10, Ui.H - 8), Ui.CREAM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)


## Two rows of two boards, each with its name over a line of detail, for the large text.
func _boards_large(c: CanvasItem, ui: Ui) -> void:
	var bw := 296.0
	for i in BOARDS.size():
		var r := Rect2(20.0 + (i % 2) * (bw + 8.0), 240.0 + (i / 2) * 48.0, bw, 44)
		var id: String = BOARDS[i][0]
		ui.button(c, r, id, "", "", true, null, true)
		ui.text(c, BOARDS[i][1].to_upper(), Vector2(r.position.x, r.position.y + 18), Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, bw)
		ui.text(c, ui.clip(sub_line(id), bw - 12), Vector2(r.position.x, r.position.y + 38), Ui.BROWN, HORIZONTAL_ALIGNMENT_CENTER, bw)
	ui.text(c, "Esc  title", Vector2(10, Ui.H - 4), Ui.CREAM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)
