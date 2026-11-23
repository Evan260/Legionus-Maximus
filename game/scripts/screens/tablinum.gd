class_name TablinumScreen
extends RefCounted
## The tablinum: every recruit, weapon, forged form, enemy and god that is drawn. Found ones show their picture and a line of history, the rest a dark silhouette.

const KINDS := [["recruits", "Recruit"], ["arms", "Arms"], ["forged", "Forged"], ["enemies", "Enemy"], ["gods", "God"]]
const CELL := 40.0
const STEP := 44.0
const COLS := 9
# The space between one group's rows and the next.
const GROUP_GAP := 4.0
const SILHOUETTE := Color(0.14, 0.1, 0.08)

var main: Node
var scroll := 0
var _visible := 1
var _count := 0
var _seen_focus := ""


func _init(owner_node: Node) -> void:
	main = owner_node


func activate(_id: String) -> void:
	pass


func row_step() -> float:
	return STEP


func scroll_by(rows: int) -> void:
	scroll = clampi(scroll + rows, 0, maxi(0, _count - _visible))


## Brings the focus on screen when it moves to `row`, and otherwise leaves the list where the wheel or a finger scrolled it.
func follow(focus: String, row: int) -> void:
	if focus != _seen_focus:
		_seen_focus = focus
		scroll = Ui.scroll_for(row, _count, _visible, scroll)
	scroll_by(0)


## Every entry that is drawn, as [id, group, entry].
func entries() -> Array:
	var out: Array = []
	for k in KINDS:
		for id in main.content.get(k[0]):
			if main.content.ready(k[0], id):
				out.append([id, k[1], main.content.get(k[0])[id]])
	return out


func draw(c: CanvasItem, ui: Ui) -> void:
	var list := entries()
	var found := 0
	for e in list:
		if Profile.data.seen.has(e[0]):
			found += 1
	var r := ui.frame(c, tr("Tablinum").to_upper(), Controls.hint("look"))
	ui.text(c, tr("%d of %d found") % [found, list.size()], Vector2(0, r.position.y + 16), Ui.INK, HORIZONTAL_ALIGNMENT_RIGHT, r.end.x - 12)
	var origin := r.position + Vector2(12, Ui.below_title())
	var rows := grid_rows(list)
	var room := r.end.y - 6.0 - origin.y
	var visible := maxi(1, int((room + GROUP_GAP) / (STEP + GROUP_GAP)))
	var focus_row := 0
	for k in rows.size():
		for i in rows[k]:
			if "e:" + list[i][0] == ui.focus:
				focus_row = k
	_visible = visible
	_count = rows.size()
	follow(ui.focus, focus_row)
	var row_y := origin.y
	var lifted := rows_height(rows, list, scroll)
	for k in rows.size():
		if k > 0 and list[rows[k][0]][1] != list[rows[k - 1][0]][1]:
			row_y += GROUP_GAP
		var shown := k >= scroll and k < scroll + visible
		for col in rows[k].size():
			var e: Array = list[rows[k][col]]
			var rect := Rect2(origin.x + col * STEP, row_y - lifted, CELL, CELL)
			if not shown:
				ui.register(rect, "e:" + e[0], true, false)
				continue
			ui.button(c, rect, "e:" + e[0], "", "", true, null, true)
			_picture(c, ui, e[0], e[2], Profile.data.seen.has(e[0]), rect.grow(-3))
		row_y += STEP
	CommandersScreen._scroll_marks(c, Rect2(origin.x, origin.y - 24.0, COLS * STEP - 4.0, r.end.y - origin.y + 24.0), scroll > 0, scroll + visible < rows.size())
	var box := box_of(r)
	ui.panel(c, box, Ui.CREAM)
	for e in list:
		if "e:" + e[0] == ui.focus:
			var known: bool = Profile.data.seen.has(e[0])
			var x := box.position.x + 8
			var name: String = (e[2].name if known else tr("Not found yet")).to_upper()
			var y := ui.wrap(c, name, Vector2(x, box.position.y + 8.0 + 8.0 * Ui.scale), box.size.x - 16, Ui.INK if known else Ui.MUTED)
			ui.text(c, tr(e[1]), Vector2(x, y), Ui.BROWN)
			var below := history_room(box, name)
			var words: String = e[2].history if known else tr("Meet it in a run to learn its history.")
			ui.wrap_fit(c, words, Vector2(x, below.y), box.size.x - 16, Ui.INK if known else Ui.MUTED, below.lines)


## The box beside the grid that tells of the entry in focus, inside the frame `r`.
static func box_of(r: Rect2) -> Rect2:
	var top := r.position.y + Ui.below_title()
	return Rect2(r.position.x + 12 + COLS * STEP + 4, top, r.size.x - 24 - COLS * STEP - 4, r.end.y - 6.0 - top)


## Where a found entry's history starts in the box, under its name wrapped to the box and its group, and how many lines it has room for.
static func history_room(box: Rect2, name: String) -> Dictionary:
	var y := box.position.y + 8.0 + 8.0 * Ui.scale + Ui.lines_of(name, box.size.x - 16).size() * Ui.leading() + Ui.leading() + 6.0
	return {"y": y, "lines": maxi(1, floori((box.end.y - 4.0 - y) / Ui.leading()) + 1)}


## The entries cut into rows of the grid, as lists of indices, each group starting a row of its own.
static func grid_rows(list: Array) -> Array:
	var rows: Array = []
	for i in list.size():
		if rows.is_empty() or rows[-1].size() >= COLS or list[rows[-1][0]][1] != list[i][1]:
			rows.append([])
		rows[-1].append(i)
	return rows


## How far down the rows above the first one shown reach, gaps between groups included.
static func rows_height(rows: Array, list: Array, first: int) -> float:
	var h := 0.0
	for k in first:
		h += STEP
		if list[rows[k + 1][0]][1] != list[rows[k][0]][1]:
			h += GROUP_GAP
	return h


## The icon of an entry, or its idle sprite; unseen ones are drawn as a dark shape.
func _picture(c: CanvasItem, ui: Ui, id: String, info: Dictionary, known: bool, area: Rect2) -> void:
	var tint := Color.WHITE if known else SILHOUETTE
	var icon_key: String = main.content.icon_key(id)
	if icon_key != "" and ui.icon(icon_key) != null:
		c.draw_texture_rect(ui.icon(icon_key), area, false, tint)
		return
	var atlas: Atlas = main.world.atlas
	if not atlas.units.has(id):
		return
	var action := "idle" if atlas.units[id].has("idle") else "move"
	var f: Array = atlas.unit_frame(id, action, "south", 0.0)
	var src: Rect2 = f[0]
	var scale := minf(area.size.x / src.size.x, area.size.y / src.size.y)
	var size := src.size * scale
	c.draw_texture_rect_region(atlas.texture, Rect2(area.get_center() - size / 2.0, size), src, tint)
