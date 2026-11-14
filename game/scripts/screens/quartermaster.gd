class_name QuartermasterScreen
extends RefCounted
## The quartermaster: permanent upgrades bought with denarii, in two columns so every one is on screen.

const ROWS := 10

var main: Node


func _init(owner_node: Node) -> void:
	main = owner_node


func activate(id: String) -> void:
	if id.begins_with("buy:"):
		Profile.buy(id.trim_prefix("buy:"), main.content)


func draw(c: CanvasItem, ui: Ui) -> void:
	var content: Content = main.content
	var r := ui.frame(c, tr("Quartermaster").to_upper(), tr("Arrows or WASD move     Space buy a rank     Esc back"))
	ui.text(c, (tr("%d denarii") % int(Profile.data.denarii)).to_upper(), Vector2(0, r.position.y + 16), Ui.INK, HORIZONTAL_ALIGNMENT_RIGHT, r.end.x - 12)
	var i := 0
	for id in content.quartermaster:
		var info: Dictionary = content.quartermaster[id]
		var rect := Rect2(r.position.x + 12 + (i / ROWS) * 292, r.position.y + 28 + (i % ROWS) * 24, 280, 21)
		var cost := Profile.next_cost(id, content)
		var can := cost >= 0 and cost <= int(Profile.data.denarii)
		var tone := Ui.BROWN if cost < 0 else (Color(0.2, 0.45, 0.15) if can else Ui.RED)
		ui.button(c, rect, "buy:" + id, _label(info, id), tr("Max").to_upper() if cost < 0 else str(cost), true, _icon_of(info), false, tone)
		i += 1
	var focus_id := ui.focus.trim_prefix("buy:")
	if content.quartermaster.has(focus_id):
		var info: Dictionary = content.quartermaster[focus_id]
		var box := Rect2(r.position.x + 12, r.end.y - 52, r.size.x - 24, 44)
		ui.panel(c, box, Ui.CREAM)
		ui.text(c, info.name.to_upper(), Vector2(box.position.x + 8, box.position.y + 15), Ui.INK)
		var cost := Profile.next_cost(focus_id, content)
		var note := tr("Fully upgraded.") if cost < 0 else tr("Next rank costs %d denarii.") % cost
		ui.text(c, note, Vector2(0, box.position.y + 15), Ui.BROWN, HORIZONTAL_ALIGNMENT_RIGHT, box.end.x - 8)
		ui.text(c, ui.clip(info.text, box.size.x - 16), Vector2(box.position.x + 8, box.position.y + 30), Ui.INK)


## The name and rank; with large text the rank leads so a long name is the part that is cut.
func _label(info: Dictionary, id: String) -> String:
	if Ui.scale > 1:
		return "%d/%d %s" % [Profile.rank(id), int(info.ranks), info.name]
	return "%s  %d/%d" % [info.name, Profile.rank(id), int(info.ranks)]


## The entry's icon when it names one that is drawn; otherwise the row is text only.
func _icon_of(info: Dictionary) -> Texture2D:
	for key in info.get("art", []):
		if key.begins_with("icon:") and main.content.available.has(key):
			return main.ui.icon(key.trim_prefix("icon:"))
	return null
