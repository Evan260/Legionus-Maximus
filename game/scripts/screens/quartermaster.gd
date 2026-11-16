class_name QuartermasterScreen
extends RefCounted
## The quartermaster: permanent upgrades and the camp's works bought with denarii, in two columns so every one is on screen.

const ROWS := 11

var main: Node


func _init(owner_node: Node) -> void:
	main = owner_node


func activate(id: String) -> void:
	if id.begins_with("buy:"):
		Profile.buy(id.trim_prefix("buy:"), main.content)


## The widest price a row shows, so every name is fitted to the room left beside it.
func price_width(content: Content) -> float:
	var widest := Ui.width_at(tr("Max").to_upper(), Ui.px)
	for id in content.quartermaster:
		var info: Dictionary = content.quartermaster[id]
		for cost in info.costs + [Profile.next_cost(id, content)]:
			widest = maxf(widest, Ui.width_at(str(int(cost)), Ui.px))
	return widest + Ui.width_at("0", Ui.px) * 2.0


func draw(c: CanvasItem, ui: Ui) -> void:
	var content: Content = main.content
	var r := ui.frame(c, tr("Quartermaster").to_upper(), Controls.hint("buy"))
	ui.text(c, (tr("%d denarii") % int(Profile.data.denarii)).to_upper(), Vector2(0, r.position.y + 8 + 8 * Ui.scale), Ui.INK, HORIZONTAL_ALIGNMENT_RIGHT, r.end.x - 12)
	var reserve := price_width(content)
	var big := Ui.scale > 1
	var pitch := 22.0 if not big else 21.0
	var i := 0
	for id in content.quartermaster:
		var info: Dictionary = content.quartermaster[id]
		var rect := Rect2(r.position.x + 12 + (i / ROWS) * 292, r.position.y + 28 + (i % ROWS) * pitch, 280, pitch - 2.0)
		var cost := Profile.next_cost(id, content)
		var waiting := Profile.waiting_for(id, content) != ""
		var can := cost >= 0 and cost <= int(Profile.data.denarii)
		var tone := Ui.BROWN if cost < 0 else (Color(0.2, 0.45, 0.15) if can else Ui.RED)
		var right := "" if waiting else (tr("Max").to_upper() if cost < 0 else str(cost))
		ui.button(c, rect, "buy:" + id, _label(info, id), right, not waiting, _icon_of(info), false, tone, reserve - Ui.width_at(right, Ui.px) - 6.0 if right != "" else reserve)
		i += 1
	var focus_id := ui.focus.trim_prefix("buy:")
	if content.quartermaster.has(focus_id):
		var info: Dictionary = content.quartermaster[focus_id]
		var box := Rect2(r.position.x + 12, r.end.y - 48, r.size.x - 24, 42) if not big else Rect2(r.position.x + 12, r.end.y - 55, r.size.x - 24, 50)
		ui.panel(c, box, Ui.CREAM)
		ui.text(c, info.name.to_upper(), Vector2(box.position.x + 8, box.position.y + 6 + Ui.px), Ui.INK)
		ui.fit_text(c, note(focus_id), box.size.x - 24.0 - ui.width_of(info.name.to_upper()), Vector2(0, box.position.y + 6 + Ui.px), Ui.BROWN, HORIZONTAL_ALIGNMENT_RIGHT, box.end.x - 8)
		ui.wrap_fit(c, info.text, Vector2(box.position.x + 8, box.position.y + 8 + Ui.px + Ui.leading()), box.size.x - 16, Ui.INK, 1 if big else 2)


## The line beside a focused entry's name: what the next rank costs, that it is done, or what it waits for.
func note(id: String) -> String:
	var content: Content = main.content
	var needs := Profile.waiting_for(id, content)
	if needs != "":
		return tr("Finish the %s first.") % content.quartermaster[needs].name
	var cost := Profile.next_cost(id, content)
	if cost < 0:
		return tr("Fully upgraded.")
	return tr("Next rank costs %d denarii.") % cost


## The name and rank; with large text the rank leads so a long name is the part that is cut. A repeating purchase shows how many were made.
func _label(info: Dictionary, id: String) -> String:
	if info.get("repeat", false):
		return "%s  %d" % [info.name, Profile.rank(id)] if Ui.scale == 1 else "%d %s" % [Profile.rank(id), info.name]
	if Ui.scale > 1:
		return "%d/%d %s" % [Profile.rank(id), int(info.ranks), info.name]
	return "%s  %d/%d" % [info.name, Profile.rank(id), int(info.ranks)]


## The entry's icon when it names one that is drawn; otherwise the row is text only.
func _icon_of(info: Dictionary) -> Texture2D:
	for key in info.get("art", []):
		if key.begins_with("icon:") and main.content.available.has(key):
			return main.ui.icon(key.trim_prefix("icon:"))
	return null
