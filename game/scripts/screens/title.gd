class_name TitleScreen
extends RefCounted
## The title: the logo, how to play, and the buttons that continue the game, start a new one, load one or open the settings.

var main: Node
var logo: Texture2D


func _init(owner_node: Node) -> void:
	main = owner_node
	logo = load("res://assets/logo.png")


func activate(id: String) -> void:
	match id:
		"continue":
			main.go_to_camp()
		"new":
			# A game is never written over, so with every slot taken one has to be deleted first.
			if Profile.new_game() > 0:
				main.use_profile()
				main.go_to_camp()
		"load":
			main.open_saves()
		"settings":
			main.open_settings("title")
		"wishlist":
			Steamworks.open_store()


## The title's buttons as [id, label, enabled]: Continue with a game open, New game, Load while any slot holds a game, and the settings.
static func buttons(balance: Dictionary) -> Array:
	var out: Array = []
	if Profile.slot > 0:
		out.append(["continue", TranslationServer.translate("Continue"), true])
	out.append(["new", TranslationServer.translate("New game"), Profile.free_slot() > 0])
	if range(1, Profile.SLOTS + 1).any(Profile.slot_taken):
		out.append(["load", TranslationServer.translate("Load"), true])
	out.append(["settings", TranslationServer.translate("Settings"), true])
	if Game.is_demo() and int(balance.demo.store_app_id) > 0:
		out.append(["wishlist", TranslationServer.translate("Wishlist on Steam"), true])
	return out


## The how-to-play lines: each key the player has bound and what it does, then how the run is won.
static func how_to_play(balance: Dictionary) -> Array:
	var key := func(action: String) -> String: return Controls.key_of(action) + "  "
	return [
		Controls.march_keys() + "  " + TranslationServer.translate("march"),
		key.call("testudo") + TranslationServer.translate("testudo: 80% less harm, stops boss charges"),
		key.call("build") + TranslationServer.translate("palisade: %d timber from felled trees") % int(balance.palisade.cost),
		key.call("wall") + TranslationServer.translate("wall behind the legion: %d timber, the enemy slowly breaks it") % int(balance.wall.cost),
		key.call("bridge") + TranslationServer.translate("bridge over a ravine: %d timber") % int(balance.bridge.cost),
		key.call("pray") + TranslationServer.translate("call the gods when the wreath is full"),
		key.call("pause") + TranslationServer.translate("pause"),
		TranslationServer.translate("Your soldiers fight on their own."),
		Game.goal_text(balance),
	]


## The how-to-play lines as drawn at a size (the text size when 0): one too long for the box goes on two lines rather than shrinking alone.
static func how_to_play_lines(balance: Dictionary, size := 0) -> Array:
	var sz := size if size > 0 else Ui.px
	var out: Array = []
	for line in how_to_play(balance):
		if Ui.width_at(line, sz) > line_width():
			out.append_array(Ui.lines_of(line, line_width(), sz))
		else:
			out.append(line)
	return out


## The width the how-to-play lines have inside their box.
static func line_width() -> float:
	return (Ui.W - 40.0 if Ui.scale > 1 else 360.0) - 12.0


func draw(c: CanvasItem, ui: Ui) -> void:
	var big := Ui.scale > 1
	var logo_pos := Vector2((Ui.W - logo.get_width()) / 2.0, 6.0 if big else 26.0)
	c.draw_texture(logo, logo_pos)
	if Game.is_demo():
		var tag := Rect2(logo_pos.x + logo.get_width() - 56.0, logo_pos.y + logo.get_height() - 8.0, 56.0, 8.0 + 8.0 * Ui.scale)
		ui.panel(c, tag)
		ui.text(c, tr("Demo").to_upper(), Vector2(tag.position.x, tag.end.y - 4.0 - Ui.px * 3 / 8), Ui.RED, HORIZONTAL_ALIGNMENT_CENTER, tag.size.x)
	var size := Ui.px
	var lines := how_to_play_lines(main.balance)
	var top := logo_pos.y + logo.get_height() + 3.0
	# Large text in a wordy language steps the how-to-play box down to the smallest size, so the buttons below stay on the screen.
	if big and top + lines.size() * Ui.leading() + 10.0 + 6.0 + 30.0 > Ui.H - 2.0:
		size = Ui.small_px()
		lines = how_to_play_lines(main.balance, size)
	var step := Ui.lead_for(size) + (0.0 if big else 1.0)
	var box := Rect2(20.0 if big else Ui.W / 2 - 180, top, Ui.W - 40.0 if big else 360.0, lines.size() * step + 10.0)
	ui.panel(c, box)
	for i in lines.size():
		ui.fit_text(c, lines[i], line_width(), Vector2(box.position.x, box.position.y + 5.0 + size + i * step), Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, box.size.x, false, size)
	var ids := buttons(main.balance)
	var rects: Array = []
	if big:
		# Large text sets the buttons side by side under the taller how-to-play box.
		var bw := minf(200.0, (Ui.W - 40.0 - (ids.size() - 1) * 10.0) / ids.size())
		var x0 := (Ui.W - ids.size() * bw - (ids.size() - 1) * 10.0) / 2.0
		var y := box.end.y + 6.0
		for i in ids.size():
			rects.append(Rect2(x0 + i * (bw + 10.0), y, bw, clampf(Ui.H - 2.0 - y, 22.0, 30.0)))
	else:
		# Two to a row, the last one centred when it is alone.
		for i in ids.size():
			var alone: bool = i == ids.size() - 1 and i % 2 == 0
			var x := Ui.W / 2 - 85.0 if alone else Ui.W / 2 - 175.0 + (i % 2) * 180.0
			rects.append(Rect2(x, box.end.y + 10.0 + (i / 2) * 30.0, 170.0, 24.0))
	for i in ids.size():
		ui.button(c, rects[i], ids[i][0], str(ids[i][1]).to_upper(), "", ids[i][2], null, true)
	if ui.focus == "new" and not ui.is_enabled("new"):
		_full_note(c, ui, rects[ids.map(func(b: Array) -> String: return b[0]).find("new")])


## The note over a refused New game: every slot holds a game, and one has to be deleted first.
func _full_note(c: CanvasItem, ui: Ui, under: Rect2) -> void:
	var note := tr("You already keep three games. Delete one in Load to start another.")
	var w := minf(Ui.W - 40.0, 320.0 if Ui.scale == 1 else 480.0)
	var lines := Ui.lines_of(note, w - 12.0)
	var h := lines.size() * Ui.leading() + 8.0
	var box := Rect2(clampf(under.get_center().x - w / 2.0, 20.0, Ui.W - 20.0 - w), under.position.y - h - 4.0, w, h)
	ui.panel(c, box, Ui.CREAM)
	for i in lines.size():
		ui.text(c, lines[i], Vector2(box.position.x, box.position.y + 4.0 + Ui.px + i * Ui.leading()), Ui.RED, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
