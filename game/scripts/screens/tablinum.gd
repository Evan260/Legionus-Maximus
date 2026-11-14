class_name TablinumScreen
extends RefCounted
## The tablinum: every recruit, weapon, forged form and enemy that is drawn. Found ones show their picture and a line of history, the rest a dark silhouette.

const KINDS := [["recruits", "Recruit"], ["arms", "Arms"], ["forged", "Forged"], ["enemies", "Enemy"]]
const CELL := 34.0
const STEP := 38.0
const COLS := 11
const SILHOUETTE := Color(0.14, 0.1, 0.08)

var main: Node


func _init(owner_node: Node) -> void:
	main = owner_node


func activate(_id: String) -> void:
	pass


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
	var r := ui.frame(c, "TABLINUM", "Arrows or WASD move     Esc back")
	ui.text(c, "%d of %d found" % [found, list.size()], Vector2(0, r.position.y + 16), Ui.INK, HORIZONTAL_ALIGNMENT_RIGHT, r.end.x - 12)
	var origin := r.position + Vector2(12, 28)
	for i in list.size():
		var e: Array = list[i]
		var rect := Rect2(origin + Vector2((i % COLS) * STEP, (i / COLS) * STEP), Vector2(CELL, CELL))
		ui.button(c, rect, "e:" + e[0], "", "", true, null, true)
		_picture(c, ui, e[0], e[2], Profile.data.seen.has(e[0]), rect.grow(-3))
	var box := Rect2(r.position.x + 12 + COLS * STEP + 4, r.position.y + 28, r.size.x - 24 - COLS * STEP - 4, r.size.y - 40)
	ui.panel(c, box, Ui.CREAM)
	for e in list:
		if "e:" + e[0] == ui.focus:
			var known: bool = Profile.data.seen.has(e[0])
			var x := box.position.x + 8
			ui.text(c, (e[2].name if known else "Not found yet").to_upper(), Vector2(x, box.position.y + 16), Ui.INK if known else Ui.MUTED)
			ui.text(c, e[1], Vector2(x, box.position.y + 28), Ui.BROWN)
			if known:
				ui.wrap(c, e[2].text, Vector2(x, box.position.y + 46), box.size.x - 16, Ui.INK)
			else:
				ui.wrap(c, "Meet it in a run to learn its history.", Vector2(x, box.position.y + 46), box.size.x - 16, Ui.MUTED)


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
