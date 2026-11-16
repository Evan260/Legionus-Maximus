class_name CampScreen
extends RefCounted
## The camp between runs: the legion stands idle on the field behind four boards and the march button.

const BOARDS := [["quartermaster", "Quartermaster"], ["tablinum", "Tablinum"], ["map", "Map"], ["commanders", "Commanders"]]

## Where the gilded statues of the triumphs stand: on the arch's top in the arch picture's pixels, then on the ground to its left.
const STATUE_SPOTS := [Vector2(30, 22), Vector2(52, 18), Vector2(74, 22), Vector2(-16, 117), Vector2(-40, 117), Vector2(-28, 100), Vector2(-52, 100)]

var main: Node
var _arch: Texture2D
var _statue: Texture2D


func _init(owner_node: Node) -> void:
	main = owner_node


func sub_line(id: String) -> String:
	var content: Content = main.content
	match id:
		"quartermaster":
			return tr("%d denarii") % int(Profile.data.denarii)
		"tablinum":
			return tr("%d found") % Profile.data.seen.size()
		"map":
			return content.provinces[main.run_setup.province].name
		"commanders":
			return content.commanders[main.run_setup.commander].name
	return ""


func draw(c: CanvasItem, ui: Ui) -> void:
	var big := Ui.scale > 1
	_monument(c, Vector2(96, 192 if not big else 186))
	var plate := Color(0.12, 0.08, 0.06, 0.78)
	var title := tr("The camp").to_upper()
	var tw := Ui.width_at(title, Ui.px)
	c.draw_rect(Rect2(Ui.W / 2 - tw / 2 - 10, 8, tw + 20, 30 if big else 22), plate)
	ui.text(c, title, Vector2(0, 31 if big else 23), Ui.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, Ui.W, true)
	var money := (tr("%d denarii") % int(Profile.data.denarii)).to_upper()
	var mw := Ui.width_at(money, Ui.px)
	var coin_r := 5.0 if not big else 7.0
	var money_box := Rect2(Ui.W - 20 - mw - coin_r * 2 - 14, 8, mw + coin_r * 2 + 20, 30 if big else 22)
	c.draw_rect(money_box, plate)
	var coin_at := Vector2(money_box.position.x + 6 + coin_r, money_box.get_center().y)
	c.draw_circle(coin_at, coin_r + 1.0, Color(0.16, 0.1, 0.08))
	c.draw_circle(coin_at, coin_r, Ui.GOLD)
	c.draw_circle(coin_at + Vector2(-1, -1), coin_r * 0.45, Ui.GOLD_LIGHT)
	ui.text(c, money, Vector2(0, 31 if big else 23), Ui.GOLD_LIGHT, HORIZONTAL_ALIGNMENT_RIGHT, Ui.W - 24, true)
	var setup: Dictionary = main.run_setup
	var modes: Array = []
	for key in ["hard", "endless", "decimatio"]:
		if setup[key]:
			modes.append(tr(key.capitalize()))
	var line: String = "%s, %s" % [main.content.provinces[setup.province].name, main.content.commanders[setup.commander].name]
	if not modes.is_empty():
		line += ", " + " + ".join(modes)
	ui.fit_text(c, line, Ui.W - 16.0, Vector2(0, 198 if big else 252), Ui.CREAM, HORIZONTAL_ALIGNMENT_CENTER, Ui.W, true)
	ui.button(c, Rect2(Ui.W / 2 - 80, 204 if big else 258, 160, 28 if big else 24), "march", tr("March").to_upper(), "", true, null, true)
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
		ui.text(c, tr(BOARDS[i][1]).to_upper(), Vector2(r.position.x, r.position.y + 16), Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, bw)
		ui.fit_text(c, sub_line(id), bw - 12, Vector2(r.position.x, r.position.y + 30), Ui.BROWN, HORIZONTAL_ALIGNMENT_CENTER, bw)
	ui.text(c, Controls.hint("title"), Vector2(10, Ui.H - 8), Ui.CREAM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)


## Two rows of two boards, each with its name over a line of detail, for the large text.
func _boards_large(c: CanvasItem, ui: Ui) -> void:
	var bw := 296.0
	for i in BOARDS.size():
		var r := Rect2(20.0 + (i % 2) * (bw + 8.0), 240.0 + (i / 2) * 48.0, bw, 44)
		var id: String = BOARDS[i][0]
		ui.button(c, r, id, "", "", true, null, true)
		ui.text(c, tr(BOARDS[i][1]).to_upper(), Vector2(r.position.x, r.position.y + 18), Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, bw)
		ui.fit_text(c, sub_line(id), bw - 12, Vector2(r.position.x, r.position.y + 38), Ui.BROWN, HORIZONTAL_ALIGNMENT_CENTER, bw)
	ui.text(c, Controls.hint("title"), Vector2(10, Ui.H - 4), Ui.CREAM, HORIZONTAL_ALIGNMENT_LEFT, -1, true)


## The triumphal arch risen as far as its bought stages, scaffolded until done, with a gilded statue per triumph; `foot` is its bottom left.
func _monument(c: CanvasItem, foot: Vector2) -> void:
	var info: Dictionary = main.content.quartermaster.get("triumphal_arch", {})
	var stages := Profile.rank("triumphal_arch")
	if info.is_empty() or stages <= 0:
		return
	if _arch == null:
		_arch = load("res://assets/arch.png")
		_statue = load("res://assets/statue.png")
	var size := _arch.get_size()
	var share := clampf(float(stages) / float(info.ranks), 0.0, 1.0)
	var built := roundf(size.y * share)
	var top := foot + Vector2(0, -size.y)
	c.draw_texture_rect_region(_arch, Rect2(top + Vector2(0, size.y - built), Vector2(size.x, built)), Rect2(0, size.y - built, size.x, built))
	if share < 1.0:
		var y := top.y + size.y - built
		var wood := Color(0.45, 0.3, 0.16)
		for x in [6.0, size.x / 2.0, size.x - 6.0]:
			c.draw_line(Vector2(top.x + x, y - 14.0), Vector2(top.x + x, y + 10.0), Ui.INK, 3.0)
			c.draw_line(Vector2(top.x + x, y - 14.0), Vector2(top.x + x, y + 10.0), wood, 1.0)
		c.draw_line(Vector2(top.x + 2.0, y - 10.0), Vector2(top.x + size.x - 2.0, y - 10.0), Ui.INK, 3.0)
		c.draw_line(Vector2(top.x + 2.0, y - 10.0), Vector2(top.x + size.x - 2.0, y - 10.0), wood, 1.0)
		return
	var shown := mini(Profile.rank("triumph"), STATUE_SPOTS.size())
	var s_size := _statue.get_size()
	for k in shown:
		var at: Vector2 = top + STATUE_SPOTS[k]
		c.draw_texture(_statue, (at - Vector2(s_size.x / 2.0, s_size.y)).round())
