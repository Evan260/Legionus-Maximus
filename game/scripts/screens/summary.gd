class_name SummaryScreen
extends RefCounted
## The summary after a run: the numbers, the damage each weapon did as bars, and the legion's size over the run as a line.

const BARS := 8

var main: Node


func _init(owner_node: Node) -> void:
	main = owner_node


func activate(id: String) -> void:
	if id == "camp":
		main.go_to_camp()
	elif id == "title":
		main.go_to_title()
	elif id == "wishlist":
		Steamworks.open_store()


static func clock(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


static func short(n: float) -> String:
	return "%.1fk" % (n / 1000.0) if n >= 10000.0 else str(roundi(n))


## The sources that did damage, biggest first, as [name, total]; at most `BARS` of them.
static func top_sources(sim: Sim) -> Array:
	var rows: Array = []
	for id in sim.damage_by_source:
		var name := sim.content.source_name(id)
		if name != "" and float(sim.damage_by_source[id]) > 0.0:
			rows.append([name, float(sim.damage_by_source[id])])
	rows.sort_custom(func(a, b): return a[1] > b[1])
	return rows.slice(0, BARS)


## The history with the run's last moment added, so the line reaches the end.
static func chart_points(sim: Sim) -> Array:
	var pts: Array = sim.history.duplicate()
	if not pts.is_empty() and sim.time > float(pts[-1].t):
		pts.append({"t": sim.time, "legion": sim.soldiers.size() + 1, "kills": sim.kills})
	return pts


func draw(c: CanvasItem, ui: Ui) -> void:
	var sim: Sim = main.sim
	var s := Ui.scale
	var title := "VICTORY" if sim.victory else "THE COMMANDER HAS FALLEN"
	var modes: Array = []
	for mode in ["hard", "endless", "decimatio"]:
		if sim.get(mode):
			modes.append(mode.capitalize())
	var held := ""
	if sim.endless and sim.endless_since >= 0.0:
		held = "Held out %s after the chieftain" % clock(sim.endless_seconds())
	var hint := held if held != "" else "Space camp     Esc title"
	if sim.demo_over:
		hint = "The full game continues past %d minutes" % (int(main.balance.demo.seconds) / 60)
	var r := ui.frame(c, title, hint)
	if not modes.is_empty():
		var room := r.size.x - 36.0 - ui.width_of(title)
		ui.text(c, ui.clip(" + ".join(modes), room), Vector2(0, r.position.y + 8 + 8 * s), Ui.INK, HORIZONTAL_ALIGNMENT_RIGHT, r.end.x - 12)
	var top := r.position.y + 24.0 + 8.0 * s
	var srow := 13.0 if s == 1 else 20.0
	var brow := 12.0 if s == 1 else 18.0
	var lx := r.position.x + 12.0
	var left_w := 212.0
	var stats := [["Time", clock(sim.time)], ["Kills", str(sim.kills)], ["Level", str(sim.level)], ["Legion", str(sim.soldiers.size() + 1)],
		["Denarii", str(sim.denarii)], ["Banked", str(int(Profile.data.denarii))]]
	for i in stats.size():
		ui.text(c, stats[i][0], Vector2(lx, top + i * srow), Ui.INK)
		ui.text(c, stats[i][1], Vector2(0, top + i * srow), Ui.RED, HORIZONTAL_ALIGNMENT_RIGHT, lx + left_w)
	_bars(c, ui, sim, Rect2(lx + left_w + 16.0, top, r.end.x - 12.0 - (lx + left_w + 16.0), brow * (BARS + 1)), brow)
	var cap_y := top + brow * (BARS + 1) + 8.0
	var h := 30.0 if s > 1 else 22.0
	var chart := Rect2(lx, cap_y + 6.0, r.size.x - 24.0, r.end.y - h - 14.0 - (cap_y + 6.0))
	_chart(c, ui, sim, chart, cap_y)
	var bw := 100.0 if s > 1 else 80.0
	ui.button(c, Rect2(r.end.x - 12.0 - 2.0 * bw - 8.0, r.end.y - h - 6.0, bw, h), "camp", "CAMP", "", true, null, true)
	ui.button(c, Rect2(r.end.x - 12.0 - bw, r.end.y - h - 6.0, bw, h), "title", "TITLE", "", true, null, true)
	if sim.demo_over and int(main.balance.demo.store_app_id) > 0:
		var wide := 150.0 if s > 1 else 120.0
		ui.button(c, Rect2(r.end.x - 12.0 - 2.0 * bw - 16.0 - wide, r.end.y - h - 6.0, wide, h), "wishlist", "WISHLIST", "", true, null, true)


func _bars(c: CanvasItem, ui: Ui, sim: Sim, area: Rect2, row: float) -> void:
	ui.text(c, "DAMAGE BY SOURCE", Vector2(area.position.x, area.position.y), Ui.BROWN)
	var rows := top_sources(sim)
	if rows.is_empty():
		ui.text(c, "None recorded", Vector2(area.position.x, area.position.y + row), Ui.MUTED)
		return
	var name_w := 110.0 if Ui.scale == 1 else 150.0
	var val_w := 38.0 if Ui.scale == 1 else 66.0
	var bar_x := area.position.x + name_w + 8.0
	var bar_w := area.end.x - val_w - bar_x
	var most: float = rows[0][1]
	for i in rows.size():
		var y := area.position.y + row * (i + 1)
		var top := y - Ui.px * 3 / 4
		ui.text(c, ui.clip(rows[i][0], name_w), Vector2(area.position.x, y), Ui.INK)
		var fill := maxf(1.0, floorf(bar_w * rows[i][1] / most))
		c.draw_rect(Rect2(bar_x - 1, top - 1, bar_w + 2, Ui.px * 3 / 4 + 3), Ui.INK)
		c.draw_rect(Rect2(bar_x, top, bar_w, Ui.px * 3 / 4 + 1), Ui.PARCH_DARK)
		c.draw_rect(Rect2(bar_x, top, fill, Ui.px * 3 / 4 + 1), Ui.GOLD)
		c.draw_rect(Rect2(bar_x, top, fill, 1), Ui.GOLD_LIGHT)
		ui.text(c, short(rows[i][1]), Vector2(0, y), Ui.INK, HORIZONTAL_ALIGNMENT_RIGHT, area.end.x)


func _chart(c: CanvasItem, ui: Ui, sim: Sim, area: Rect2, cap_y: float) -> void:
	ui.text(c, "LEGION SIZE OVER TIME", Vector2(area.position.x, cap_y), Ui.BROWN)
	var pts := chart_points(sim)
	if pts.size() < 2:
		c.draw_rect(area, Ui.PARCH_DARK, false, 1.0)
		ui.text(c, "The run was too short to chart", Vector2(area.position.x + 8, area.get_center().y + 3), Ui.MUTED)
		return
	var most := 1
	for p in pts:
		most = maxi(most, int(p.legion))
	ui.text(c, "Largest %d" % most, Vector2(0, cap_y), Ui.INK, HORIZONTAL_ALIGNMENT_RIGHT, area.end.x)
	c.draw_rect(Rect2(area.position - Vector2(1, 1), area.size + Vector2(2, 2)), Ui.INK)
	c.draw_rect(area, Ui.CREAM)
	for g in 3:
		c.draw_rect(Rect2(area.position.x, area.position.y + floorf(area.size.y * (g + 1) / 4.0), area.size.x, 1), Ui.PARCH_DARK)
	var tmax := float(pts[-1].t)
	var last := Vector2.ZERO
	for i in pts.size():
		var x := area.position.x + floorf((area.size.x - 3.0) * float(pts[i].t) / tmax)
		var y := area.end.y - 3.0 - floorf((area.size.y - 6.0) * float(pts[i].legion) / most)
		if i > 0:
			_pixel_line(c, last, Vector2(x, y))
		last = Vector2(x, y)


## A line drawn as 2 by 2 pixel squares, one per column.
func _pixel_line(c: CanvasItem, a: Vector2, b: Vector2) -> void:
	var steps := int(maxf(absf(b.x - a.x), absf(b.y - a.y)))
	for i in steps + 1:
		var p := a.lerp(b, float(i) / maxf(1.0, steps))
		c.draw_rect(Rect2(floorf(p.x), floorf(p.y), 2, 2), Ui.RED)
