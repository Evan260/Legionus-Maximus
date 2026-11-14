class_name CommandersScreen
extends RefCounted
## The commanders: pick an unlocked one, and see how to unlock the rest. A commander whose art is not drawn is not listed.

var main: Node
var scroll := 0


func _init(owner_node: Node) -> void:
	main = owner_node


func activate(id: String) -> void:
	if id.begins_with("pick:"):
		main.run_setup.commander = id.trim_prefix("pick:")
		Profile.data.settings.commander = main.run_setup.commander
		Profile.save()


func draw(c: CanvasItem, ui: Ui) -> void:
	var content: Content = main.content
	var r := ui.frame(c, tr("Commanders").to_upper(), Controls.hint("pick"))
	var ids := Game.commanders(content, main.balance)
	var text_w: float = r.size.x - 40.0
	# Every row is as tall as the longest description needs, so the list stays even.
	var extra := 0.0
	for id in ids:
		var b: Dictionary = Ui.block(content.commanders[id].text, text_w, 2)
		extra = maxf(extra, (mini(b.lines, 2) - 1) * Ui.lead_for(b.size))
	var h := (40.0 if Ui.scale == 1 else 58.0) + extra
	var step := h + 4.0
	var visible := int((r.size.y - 36.0) / step)
	var focused := ids.find(ui.focus.get_slice(":", 1))
	scroll = Ui.scroll_for(maxi(focused, 0), ids.size(), visible, scroll)
	for i in ids.size():
		var id: String = ids[i]
		var info: Dictionary = content.commanders[id]
		var open := Profile.commander_unlocked(id)
		var rect := Rect2(r.position.x + 12, r.position.y + 28 + (i - scroll) * step, r.size.x - 24, h)
		var button_id := ("pick:" if open else "see:") + id
		if i < scroll or i >= scroll + visible:
			ui.register(rect, button_id, open)
			continue
		ui.button(c, rect, button_id, "", "", open)
		var tone := Ui.INK if open else Ui.MUTED
		ui.text(c, info.name.to_upper(), Vector2(rect.position.x + 8, rect.position.y + 8 + 8 * Ui.scale), tone)
		var b: Dictionary = Ui.block(info.text, text_w, 2)
		ui.wrap_fit(c, info.text, Vector2(rect.position.x + 8, rect.end.y - 8 - (mini(b.lines, 2) - 1) * Ui.lead_for(b.size)), text_w, tone, 2)
		var tag := (tr("Locked: %s") % Profile.unlock_text(info, content)).to_upper()
		if open:
			tag = tr("Chosen").to_upper() if main.run_setup.commander == id else ""
		if tag != "":
			ui.fit_text(c, tag, rect.size.x - 150, Vector2(0, rect.position.y + 8 + 8 * Ui.scale), Ui.RED if not open else Ui.BROWN, HORIZONTAL_ALIGNMENT_RIGHT, rect.end.x - 8)
