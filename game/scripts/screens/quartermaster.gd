class_name QuartermasterScreen
extends RefCounted
## The quartermaster: permanent upgrades and the camp's works bought with denarii, in two columns so every one is on screen.

const ROWS := 11
## A phone's list of upgrades: its width, and how wide its rows are beside the panel.
const TOUCH_LIST_W := 336.0

var main: Node
## The first row shown in a phone's list, and how many it shows.
var scroll := 0
var _visible := 1
var _count := 0
var _seen_focus := ""
## The upgrade a phone's panel describes: the last row tapped, kept while the buy button has focus.
var selected := ""


func _init(owner_node: Node) -> void:
	main = owner_node


func activate(id: String) -> void:
	if id == "buy_shown":
		id = "buy:" + selected
	if id.begins_with("buy:"):
		if Profile.buy(id.trim_prefix("buy:"), main.content) and main.camp_sim:
			# The camp's legion behind the screen puts on its new armour at once.
			main.camp_sim.bonuses = Profile.bonuses()


## The widest price a row shows, so every name is fitted to the room left beside it.
func price_width(content: Content) -> float:
	var widest := Ui.width_at(tr("Max").to_upper(), Ui.px)
	for id in content.quartermaster:
		var info: Dictionary = content.quartermaster[id]
		for cost in info.costs + [Profile.next_cost(id, content)]:
			widest = maxf(widest, Ui.width_at(str(int(cost)), Ui.px))
	return widest + Ui.width_at("0", Ui.px) * 2.0


## The height of a phone's row and the step from one to the next.
static func touch_row() -> Vector2:
	var h := clampf(Touch.fingertip * 0.75, 22.0, 30.0 if Ui.scale > 1 else 24.0)
	return Vector2(h, h + 3.0)


func row_step() -> float:
	return touch_row().y


func scroll_by(rows: int) -> void:
	scroll = clampi(scroll + rows, 0, maxi(0, _count - _visible))


func draw(c: CanvasItem, ui: Ui) -> void:
	if Touch.phone:
		_draw_touch(c, ui)
		return
	var content: Content = main.content
	var r := ui.frame(c, tr("Quartermaster").to_upper(), Controls.hint("buy"))
	ui.text(c, (tr("%d denarii") % int(Profile.data.denarii)).to_upper(), Vector2(0, r.position.y + 8 + 8 * Ui.scale), Ui.INK, HORIZONTAL_ALIGNMENT_RIGHT, r.end.x - 12)
	var reserve := price_width(content)
	var big := Ui.scale > 1
	var pitch := 22.0 if not big else 21.0
	var rows: Array = []
	var i := 0
	for id in content.quartermaster:
		var info: Dictionary = content.quartermaster[id]
		var rect := Rect2(r.position.x + 12 + (i / ROWS) * 292, r.position.y + 28 + (i % ROWS) * pitch, 280, pitch - 2.0)
		var cost := Profile.next_cost(id, content)
		var waiting := Profile.waiting_for(id, content) != ""
		var right := "" if waiting else (tr("Max").to_upper() if cost < 0 else str(cost))
		var spare := reserve - Ui.width_at(right, Ui.px) - 6.0 if right != "" else reserve
		rows.append({"id": id, "info": info, "rect": rect, "cost": cost, "waiting": waiting, "right": right, "spare": spare, "icon": _icon_of(info)})
		i += 1
	var size := Ui.list_size(rows.map(func(row: Dictionary) -> Array: return [_label(row.info, row.id), Ui.label_room(row.rect, row.right, row.icon != null, row.spare)]))
	for row in rows:
		var can: bool = row.cost >= 0 and row.cost <= int(Profile.data.denarii)
		var tone := Ui.BROWN if row.cost < 0 else (Color(0.2, 0.45, 0.15) if can else Ui.RED)
		ui.button(c, row.rect, "buy:" + row.id, _label(row.info, row.id), row.right, not row.waiting, row.icon, false, tone, row.spare, size)
	var focus_id := ui.focus.trim_prefix("buy:")
	if content.quartermaster.has(focus_id):
		var info: Dictionary = content.quartermaster[focus_id]
		var box := Rect2(r.position.x + 12, r.end.y - 48, r.size.x - 24, 42) if not big else Rect2(r.position.x + 12, r.end.y - 55, r.size.x - 24, 50)
		ui.panel(c, box, Ui.CREAM)
		ui.text(c, info.name.to_upper(), Vector2(box.position.x + 8, box.position.y + 6 + Ui.px), Ui.INK)
		ui.fit_text(c, note(focus_id), box.size.x - 24.0 - ui.width_of(info.name.to_upper()), Vector2(0, box.position.y + 6 + Ui.px), Ui.BROWN, HORIZONTAL_ALIGNMENT_RIGHT, box.end.x - 8)
		ui.wrap_fit(c, info.text, Vector2(box.position.x + 8, box.position.y + 8 + Ui.px + Ui.leading()), box.size.x - 16, Ui.INK, 1 if big else 2)


## A phone's quartermaster: the upgrades in one column that scrolls, and beside it the one picked out with its buy button.
func _draw_touch(c: CanvasItem, ui: Ui) -> void:
	var content: Content = main.content
	var r := ui.frame(c, tr("Quartermaster").to_upper(), "")
	ui.text(c, (tr("%d denarii") % int(Profile.data.denarii)).to_upper(), Vector2(0, r.position.y + 8 + 8 * Ui.scale), Ui.INK, HORIZONTAL_ALIGNMENT_RIGHT, r.end.x - 12)
	var ids: Array = content.quartermaster.keys()
	if ui.focus.begins_with("buy:") and ids.has(ui.focus.trim_prefix("buy:")):
		selected = ui.focus.trim_prefix("buy:")
	if not ids.has(selected):
		selected = ids[0]
	var top := r.position.y + Ui.below_title()
	var size_of := touch_row()
	_count = ids.size()
	_visible = maxi(1, floori((r.end.y - 6.0 - top + 3.0) / size_of.y))
	# The list follows the keys' focus, and is otherwise left where a finger scrolled it.
	if ui.focus != _seen_focus:
		_seen_focus = ui.focus
		if ui.focus.begins_with("buy:"):
			scroll = Ui.scroll_for(ids.find(selected), _count, _visible, scroll)
	scroll_by(0)
	var reserve := price_width(content)
	var rows: Array = []
	for k in ids.size():
		var id: String = ids[k]
		var info: Dictionary = content.quartermaster[id]
		var rect := Rect2(r.position.x + 12, top + (k - scroll) * size_of.y, TOUCH_LIST_W, size_of.x)
		var cost := Profile.next_cost(id, content)
		var waiting := Profile.waiting_for(id, content) != ""
		var right := "" if waiting else (tr("Max").to_upper() if cost < 0 else str(cost))
		var spare := reserve - Ui.width_at(right, Ui.px) - 6.0 if right != "" else reserve
		rows.append({"id": id, "info": info, "rect": rect, "cost": cost, "waiting": waiting, "right": right, "spare": spare, "icon": _icon_of(info), "shown": k >= scroll and k < scroll + _visible})
	var size := Ui.list_size(rows.map(func(row: Dictionary) -> Array: return [_label(row.info, row.id), Ui.label_room(row.rect, row.right, row.icon != null, row.spare)]))
	for row in rows:
		if not row.shown:
			ui.register(row.rect, "buy:" + row.id, not row.waiting, false)
			continue
		var can: bool = row.cost >= 0 and row.cost <= int(Profile.data.denarii)
		var tone := Ui.BROWN if row.cost < 0 else (Color(0.2, 0.45, 0.15) if can else Ui.RED)
		ui.button(c, row.rect, "buy:" + row.id, _label(row.info, row.id), row.right, not row.waiting, row.icon, false, tone, row.spare, size)
		# The row the panel describes keeps a mark while the buy button has the focus.
		if row.id == selected and ui.focus != "buy:" + row.id:
			c.draw_rect(Rect2(row.rect.position - Vector2(3, 0), Vector2(2, row.rect.size.y)), Ui.GOLD)
	CommandersScreen._scroll_marks(c, Rect2(r.position.x + 12, top - 24.0, TOUCH_LIST_W, r.end.y - top + 24.0), scroll > 0, scroll + _visible < _count)
	Ui.scroll_bar(c, Rect2(r.position.x + 14 + TOUCH_LIST_W, top, 4, (_visible - 1) * size_of.y + size_of.x), scroll, _visible, _count)
	var box := Rect2(r.position.x + 20 + TOUCH_LIST_W, top, r.end.x - 12 - (r.position.x + 20 + TOUCH_LIST_W), r.end.y - 6.0 - top)
	ui.panel(c, box, Ui.CREAM)
	var info: Dictionary = content.quartermaster[selected]
	var x := box.position.x + 8
	var w := box.size.x - 16
	var y := box.position.y + 6 + Ui.px
	y = ui.wrap_fit(c, info.name.to_upper(), Vector2(x, y), w, Ui.INK, 2)
	y = ui.wrap_fit(c, note(selected), Vector2(x, y), w, Ui.BROWN, 2) + 4.0
	var bh := size_of.x + 4.0
	var room := floori((box.end.y - 10.0 - bh - (y - Ui.px)) / Ui.leading())
	ui.wrap_fit(c, info.text, Vector2(x, y), w, Ui.INK, maxi(1, room))
	var cost := Profile.next_cost(selected, content)
	var can := cost >= 0 and cost <= int(Profile.data.denarii) and Profile.waiting_for(selected, content) == ""
	ui.button(c, Rect2(x, box.end.y - bh - 6.0, w, bh), "buy_shown", tr("upgrade").to_upper(), str(cost) if cost >= 0 else "", can, null, false, Color(0.2, 0.45, 0.15))


## The line beside a focused entry's name: what the next rank costs, that it is done, or what it waits for.
func note(id: String) -> String:
	var content: Content = main.content
	var needs := Profile.waiting_for(id, content)
	if needs != "":
		return tr("Finish the %s first.") % content.quartermaster[needs].name
	var cost := Profile.next_cost(id, content)
	if cost < 0:
		return tr("Fully upgraded.")
	return tr("Next upgrade costs %d denarii.") % cost


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
