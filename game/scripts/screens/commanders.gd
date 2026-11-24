class_name CommandersScreen
extends RefCounted
## The commanders: pick an unlocked one, and see how to unlock the rest or buy them with denarii. A commander whose art is not drawn is not listed.

var main: Node
var scroll := 0
var _visible := 1
var _count := 0
var _step := 44.0
var _seen_focus := ""


func _init(owner_node: Node) -> void:
	main = owner_node


func activate(id: String) -> void:
	if id.begins_with("pick:"):
		main.run_setup.commander = id.trim_prefix("pick:")
		Profile.data.choices.commander = main.run_setup.commander
		Profile.save()
	elif id.begins_with("see:") and Profile.buy_commander(id.trim_prefix("see:"), main.content):
		main.ui.focus = "pick:" + id.trim_prefix("see:")
		activate(main.ui.focus)


func row_step() -> float:
	return _step


func scroll_by(rows: int) -> void:
	scroll = clampi(scroll + rows, 0, maxi(0, _count - _visible))


## Brings the focus on screen when it moves to `row`, and otherwise leaves the list where the wheel or a finger scrolled it.
func follow(focus: String, row: int) -> void:
	if focus != _seen_focus:
		_seen_focus = focus
		scroll = Ui.scroll_for(row, _count, _visible, scroll)
	scroll_by(0)


## The tag of a locked commander: how he is earned, and his price when he can be bought.
static func locked_tag(info: Dictionary, content: Content) -> String:
	var how := Profile.unlock_text(info, content)
	var price := Profile.commander_price(info)
	if price > 0:
		how = TranslationServer.translate("%s, or %d denarii") % [how, price]
	return TranslationServer.translate("Locked: %s") % how


func draw(c: CanvasItem, ui: Ui) -> void:
	var content: Content = main.content
	var r := ui.frame(c, tr("Commanders").to_upper(), Controls.hint("pick"))
	var ids := Game.commanders(content, main.balance)
	var text_w: float = r.size.x - 40.0
	var tag_line := needs_tag_line(ids, content, r.size.x)
	var h := row_height(ids, content, r.size.x)
	var step := h + 4.0
	var visible := int((r.size.y - 36.0) / step)
	var focused := ids.find(ui.focus.get_slice(":", 1))
	_visible = visible
	_count = ids.size()
	_step = step
	follow(ui.focus, maxi(focused, 0))
	_scroll_marks(c, r, scroll > 0, scroll + visible < ids.size())
	for i in ids.size():
		var id: String = ids[i]
		var info: Dictionary = content.commanders[id]
		var open := Profile.commander_unlocked(id)
		var rect := Rect2(r.position.x + 12, r.position.y + 28 + (i - scroll) * step, r.size.x - 24, h)
		var button_id := ("pick:" if open else "see:") + id
		var price := Profile.commander_price(info)
		var affordable := not open and price > 0 and price <= int(Profile.data.denarii)
		if i < scroll or i >= scroll + visible:
			ui.register(rect, button_id, open or affordable, false)
			continue
		ui.button(c, rect, button_id, "", "", open or affordable)
		var tone := Ui.INK if open else Ui.MUTED
		ui.text(c, info.name.to_upper(), Vector2(rect.position.x + 8, rect.position.y + 8 + 8 * Ui.scale), tone)
		# The description sits under the name, and under the lock tag when the tag has a line of its own, so a short one leaves room at the foot rather than a gap.
		var text_y: float = rect.position.y + 8 + 8 * Ui.scale + Ui.leading() + (Ui.leading() if tag_line and not open else 0.0) + 2.0
		ui.wrap_fit(c, info.text, Vector2(rect.position.x + 8, text_y), text_w, tone, 2)
		var tag := locked_tag(info, content).to_upper()
		if open:
			tag = tr("Chosen").to_upper() if main.run_setup.commander == id else ""
		if tag != "":
			var tag_col: Color = (Color(0.2, 0.45, 0.15) if affordable else Ui.RED) if not open else Ui.BROWN
			var name_y: float = rect.position.y + 8 + 8 * Ui.scale
			if tag_line and not open:
				ui.fit_text(c, tag, rect.size.x - 16, Vector2(rect.position.x + 8, name_y + Ui.leading()), tag_col)
			else:
				ui.fit_text(c, tag, tag_room(info, r.size.x), Vector2(0, name_y), tag_col, HORIZONTAL_ALIGNMENT_RIGHT, rect.end.x - 8)


## Whether a lock tag is too long for its name's line even at the smallest size, so it takes a line of its own under the name.
static func needs_tag_line(ids: Array, content: Content, frame_w: float) -> bool:
	for id in ids:
		var info: Dictionary = content.commanders[id]
		if not Profile.commander_unlocked(id) and Ui.width_at(locked_tag(info, content).to_upper(), Ui.small_px()) > tag_room(info, frame_w):
			return true
	return false


## The room for a lock tag beside the commander's name on a row of a frame `frame_w` wide.
static func tag_room(info: Dictionary, frame_w: float) -> float:
	return frame_w - 24.0 - Ui.width_at(str(info.name).to_upper(), Ui.px) - 32.0


## The height of every row: as tall as the longest description needs, so the list stays even, with a line for the lock tags when one needs it.
static func row_height(ids: Array, content: Content, frame_w: float) -> float:
	var extra := 0.0
	for id in ids:
		var b: Dictionary = Ui.block(content.commanders[id].text, frame_w - 40.0, 2)
		extra = maxf(extra, (mini(b.lines, 2) - 1) * Ui.lead_for(b.size))
	if needs_tag_line(ids, content, frame_w):
		extra += Ui.leading()
	return (40.0 if Ui.scale == 1 else 58.0) + extra


## Small gold arrows at the top and foot of the list's frame while more commanders lie above or below.
static func _scroll_marks(c: CanvasItem, r: Rect2, above: bool, below: bool) -> void:
	var x := r.get_center().x
	for mark in [[above, r.position.y + 24.0, -1.0], [below, r.end.y, 1.0]]:
		if not mark[0]:
			continue
		var y: float = mark[1]
		var d: float = mark[2]
		var tri := PackedVector2Array([Vector2(x - 8, y - 4 * d), Vector2(x + 8, y - 4 * d), Vector2(x, y + 4 * d)])
		c.draw_colored_polygon(PackedVector2Array([tri[0] + Vector2(-2, -d), tri[1] + Vector2(2, -d), tri[2] + Vector2(0, 2 * d)]), Ui.INK)
		c.draw_colored_polygon(tri, Ui.GOLD)
