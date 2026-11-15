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


## The how-to-play lines: each key the player has bound and what it does, then how the run is won.
static func how_to_play(balance: Dictionary) -> Array:
	var key := func(action: String) -> String: return Controls.key_of(action) + "  "
	return [
		Controls.march_keys() + "  " + TranslationServer.translate("march"),
		key.call("testudo") + TranslationServer.translate("testudo: 80% less harm"),
		key.call("build") + TranslationServer.translate("palisade: %d timber from felled trees") % int(balance.palisade.cost),
		key.call("bridge") + TranslationServer.translate("bridge over a ravine: %d timber") % int(balance.bridge.cost),
		key.call("pray") + TranslationServer.translate("call the gods when the wreath is full"),
		key.call("pause") + TranslationServer.translate("pause"),
		TranslationServer.translate("Your soldiers fight on their own."),
		Game.goal_text(balance),
	]


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
	var lines := how_to_play(main.balance)
	var step := Ui.leading() + (0.0 if big else 1.0)
	var box := Rect2(20.0 if big else Ui.W / 2 - 180, logo_pos.y + logo.get_height() + 3.0, Ui.W - 40.0 if big else 360.0, lines.size() * step + 10.0)
	ui.panel(c, box)
	for i in lines.size():
		ui.fit_text(c, lines[i], line_width(), Vector2(box.position.x, box.position.y + 5.0 + Ui.px + i * step), Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, box.size.x)
	var ids := [["march", tr("March")], ["settings", tr("Settings")]]
	if Game.is_demo() and int(main.balance.demo.store_app_id) > 0:
		ids.append(["wishlist", tr("Wishlist on Steam")])
	if big:
		# Large text sets the buttons side by side under the taller how-to-play box.
		var bw := minf(200.0, (Ui.W - 40.0 - (ids.size() - 1) * 10.0) / ids.size())
		var x0 := (Ui.W - ids.size() * bw - (ids.size() - 1) * 10.0) / 2.0
		for i in ids.size():
			ui.button(c, Rect2(x0 + i * (bw + 10.0), box.end.y + 10.0, bw, 30.0), ids[i][0], str(ids[i][1]).to_upper(), "", true, null, true)
		return
	for i in ids.size():
		ui.button(c, Rect2(Ui.W / 2 - 100, 250.0 + i * 34.0, 200, 24), ids[i][0], str(ids[i][1]).to_upper(), "", true, null, true)
