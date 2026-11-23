class_name SummaryScreen
extends RefCounted
## The summary after a run: the numbers, the damage each weapon did as bars, what the run unlocked, and the legion's size over the run as a line.

const BARS := 8
## Seconds between one unlock appearing and the next.
const UNLOCK_STEP := 0.35
## Seconds the victory reveal plays before the summary panel, and when its denarii count starts and ends.
const REVEAL := 5.0
const COUNT_FROM := 1.2
const COUNT_TO := 3.0
## How many coins rain down the victory reveal.
const RAIN := 46

var main: Node
var _ticked := 0.0


func _init(owner_node: Node) -> void:
	main = owner_node


## Whether a run ended in a victory that earns the reveal before the panel; the demo's time limit does not.
static func reveals(sim: Sim) -> bool:
	return sim.victory and not sim.demo_over


## Seconds since the summary opened, less the reveal for a victory, so the panel's own animations start when it shows.
func panel_age() -> float:
	var age: float = main.clock - main.opened_at
	return age - REVEAL if reveals(main.sim) else age


func revealing() -> bool:
	return reveals(main.sim) and main.clock - main.opened_at < REVEAL


## Jumps from the reveal to the panel.
func skip() -> void:
	main.opened_at = main.clock - REVEAL


## The denarii the reveal's count shows `age` seconds in, rising from none to the run's total.
static func counted(total: int, age: float) -> int:
	return int(round(total * clampf((age - COUNT_FROM) / (COUNT_TO - COUNT_FROM), 0.0, 1.0)))


## Clinks a coin now and then while the reveal's count rises.
func tick(_dt: float) -> void:
	var age: float = main.clock - main.opened_at
	if not revealing() or age < COUNT_FROM or age > COUNT_TO:
		return
	# A new reveal starts its count again, so the clinks do too.
	if age - _ticked >= 0.09 or age < _ticked:
		_ticked = age
		Audio.play("tally")


func activate(id: String) -> void:
	if id == "camp":
		main.go_to_camp()
	elif id == "title":
		main.go_to_title()
	elif id == "wishlist":
		Steamworks.open_store()


static func clock(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


## The line on how long an endless run lasted after it was won, or "" for any other run.
static func held_line(sim: Sim) -> String:
	if not sim.endless or sim.endless_since < 0.0:
		return ""
	if sim.horde.chief_dead:
		return TranslationServer.translate("Held out %s after the chieftain") % clock(sim.endless_seconds())
	var extra := int(sim.endless_seconds())
	return TranslationServer.translate("Endless  +%d:%02d") % [extra / 60, extra % 60]


## What the run unlocked, from the profile at its start and now: new provinces, the modes of a province won for the first time,
## new commanders and new achievements, each as {kind, id, text}.
static func unlocks(before: Dictionary, after: Dictionary, content: Content, province: String) -> Array:
	var out: Array = []
	for id in after.unlocked.provinces:
		if not before.unlocked.provinces.has(id) and content.ready("provinces", id):
			out.append({"kind": "province", "id": id, "text": TranslationServer.translate("%s is open") % str(content.provinces[id].name)})
	var was: Dictionary = before.records.get(province, {})
	var now: Dictionary = after.records.get(province, {})
	if bool(now.get("won", false)) and not bool(was.get("won", false)) and content.provinces.has(province):
		out.append({"kind": "modes", "id": province, "text": TranslationServer.translate("Endless and Decimatio in %s") % str(content.provinces[province].name)})
	for id in after.unlocked.commanders:
		if not before.unlocked.commanders.has(id) and content.commanders.has(id):
			out.append({"kind": "commander", "id": id, "text": TranslationServer.translate("%s joins the camp") % str(content.commanders[id].name)})
	for id in after.achievements:
		if not before.achievements.has(id) and content.achievements.has(id):
			out.append({"kind": "achievement", "id": id, "text": str(content.achievements[id].name)})
	return out


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


## The width of the stats column: the usual one, or wider when the longest label and a five digit number need it.
static func stats_width(labels: Array) -> float:
	var widest := 0.0
	for s in labels:
		widest = maxf(widest, Ui.width_at(s, Ui.px))
	return clampf(widest + Ui.width_at("99999", Ui.px) + 12.0, 212.0, 260.0)


## The width of the names column of the damage bars, wide enough for the longest source name up to a limit.
static func names_width(names: Array) -> float:
	var widest := 0.0
	for s in names:
		widest = maxf(widest, Ui.width_at(s, Ui.px))
	return clampf(widest + 6.0, 110.0 if Ui.scale == 1 else 150.0, 170.0 if Ui.scale == 1 else 200.0)


## The width of the camp and title buttons: the usual one, or wider when the longer of the two words needs it.
static func button_width() -> float:
	var widest := maxf(Ui.width_at(TranslationServer.translate("Camp").to_upper(), Ui.px), Ui.width_at(TranslationServer.translate("Title").to_upper(), Ui.px))
	return maxf(100.0 if Ui.scale > 1 else 80.0, widest + 14.0)


static func wide_button_width() -> float:
	return maxf(150.0 if Ui.scale > 1 else 120.0, Ui.width_at(TranslationServer.translate("Wishlist").to_upper(), Ui.px) + 14.0)


func draw(c: CanvasItem, ui: Ui) -> void:
	var sim: Sim = main.sim
	var s := Ui.scale
	if revealing():
		_reveal(c, ui, sim, main.clock - main.opened_at)
		return
	var title := tr("Victory").to_upper() if sim.victory else tr("The commander has fallen").to_upper()
	var modes: Array = []
	if sim.difficulty != "medium":
		modes.append(tr(sim.difficulty.capitalize()))
	for mode in ["endless", "decimatio"]:
		if sim.get(mode):
			modes.append(tr(mode.capitalize()))
	var held := held_line(sim)
	var hint := held if held != "" else Controls.hint("summary")
	if sim.demo_over:
		hint = tr("The full game continues past %d minutes") % (int(main.balance.demo.seconds) / 60)
	if sim.demo_over:
		title = tr("The demo ends here").to_upper()
	var r := ui.frame(c, title, hint, false)
	if not modes.is_empty():
		var room := r.size.x - 36.0 - ui.width_of(title)
		ui.fit_text(c, " + ".join(modes), room, Vector2(0, r.position.y + 8 + 8 * s), Ui.INK, HORIZONTAL_ALIGNMENT_RIGHT, r.end.x - 12)
	var top := r.position.y + 24.0 + 8.0 * s
	var srow := 13.0 if s == 1 else 20.0
	var brow := 12.0 if s == 1 else 18.0
	var lx := r.position.x + 12.0
	var stats := [[tr("Time"), clock(sim.time)], [tr("Kills"), str(sim.kills)], [tr("Level"), str(sim.level)], [tr("Legion"), str(sim.soldiers.size() + 1)],
		[tr("Denarii"), str(sim.banked_denarii())], [tr("Banked"), str(int(Profile.data.denarii))]]
	var left_w := stats_width([tr("Time"), tr("Kills"), tr("Level"), tr("Legion"), tr("Denarii"), tr("Banked")])
	for i in stats.size():
		ui.fit_text(c, stats[i][0], left_w - ui.width_of("99999") - 8.0, Vector2(lx, top + i * srow), Ui.INK)
		ui.text(c, stats[i][1], Vector2(0, top + i * srow), Ui.RED, HORIZONTAL_ALIGNMENT_RIGHT, lx + left_w)
	var bar_rows := BARS + 1
	if Touch.phone:
		bar_rows = maxi(stats.size(), top_sources(sim).size() + 1)
	_bars(c, ui, sim, Rect2(lx + left_w + 16.0, top, r.end.x - 12.0 - (lx + left_w + 16.0), brow * bar_rows), brow)
	var cap_y := maxf(top + brow * bar_rows, top + srow * (stats.size() - 1) + 4.0) + 8.0
	var gained: Array = unlocks(main.profile_at_start, Profile.data, main.content, sim.province) if not main.profile_at_start.is_empty() else []
	if not gained.is_empty():
		var room := r.end.y - (30.0 if s > 1 else 22.0) - 14.0 - 6.0 - (40.0 if s == 1 else 0.0) - (cap_y - 2.0) - 8.0
		cap_y = _unlocked(c, ui, gained, Rect2(lx, cap_y - 2.0, r.size.x - 24.0, room)) + 8.0
	var h := 30.0 if s > 1 else 22.0
	var chart := Rect2(lx, cap_y + 6.0, r.size.x - 24.0, r.end.y - h - 14.0 - (cap_y + 6.0))
	# With large text and a long unlock list there is no room left for the chart, so it is left out rather than crushed.
	if chart.size.y >= 30.0 * s:
		_chart(c, ui, sim, chart, cap_y)
	var bw := button_width()
	ui.button(c, Rect2(r.end.x - 12.0 - 2.0 * bw - 8.0, r.end.y - h - 6.0, bw, h), "camp", tr("Camp").to_upper(), "", true, null, true)
	ui.button(c, Rect2(r.end.x - 12.0 - bw, r.end.y - h - 6.0, bw, h), "title", tr("Title").to_upper(), "", true, null, true)
	if sim.demo_over and int(main.balance.demo.store_app_id) > 0 and not Touch.phone:
		var wide := wide_button_width()
		ui.button(c, Rect2(r.end.x - 12.0 - 2.0 * bw - 16.0 - wide, r.end.y - h - 6.0, wide, h), "wishlist", tr("Wishlist").to_upper(), "", true, null, true)
	if Profile.last_save_failed:
		var room := r.end.x - 12.0 - 2.0 * bw - 16.0 - lx
		if sim.demo_over and int(main.balance.demo.store_app_id) > 0 and not Touch.phone:
			room -= wide_button_width() + 8.0
		ui.fit_text(c, tr("Your progress could not be saved"), room, Vector2(lx, r.end.y - 6.0 - h / 2.0 + Ui.px / 2.0 - 1.0), Ui.RED)


## The victory reveal over the darkened field: gold rays turning behind a great VICTORY between laurels, coins raining,
## the denarii won counting up, and the province the legion marches to next.
func _reveal(c: CanvasItem, ui: Ui, sim: Sim, age: float) -> void:
	# The reveal fills the whole window, which reaches past the centred box when the window is wider or taller.
	c.draw_set_transform(Vector2.ZERO)
	_reveal_in_window(c, ui, sim, age)
	c.draw_set_transform(Ui.offset)


func _reveal_in_window(c: CanvasItem, ui: Ui, sim: Sim, age: float) -> void:
	var view: Vector2 = Ui.view
	var centre := Vector2(view.x / 2.0, view.y * 0.36)
	c.draw_rect(Rect2(Vector2.ZERO, view), Color(0.05, 0.03, 0.02, 0.8 * clampf(age * 2.0, 0.0, 1.0)))
	var glow := clampf(age * 1.5, 0.0, 1.0)
	var tip := view.length() * 0.55
	for k in 18:
		var a0 := age * 0.2 + TAU * k / 18.0
		var core := Color(Ui.GOLD_LIGHT, 0.22 * glow)
		var edge := Color(Ui.GOLD, 0.0)
		c.draw_polygon(PackedVector2Array([centre, centre + Vector2.from_angle(a0) * tip, centre + Vector2.from_angle(a0 + 0.12) * tip]),
			PackedColorArray([core, edge, edge]))
	_rain(c, view, age)
	# The word lands large and settles, with a flash of light as it does.
	var land := clampf(age / 0.5, 0.0, 1.0)
	var word := tr("Victory").to_upper()
	# The word and a laurel either side keep within the screen, whatever the text size and language.
	var settled := float(Ui.px * 6)
	settled = minf(settled, settled * (view.x - 24.0) / (Ui.width_at(word, int(settled)) + 3.25 * settled))
	var size := int(settled * (1.0 + 1.2 * pow(1.0 - land, 2.0)))
	var w := Ui.font().get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if age > 0.4 and age < 0.9:
		c.draw_rect(Rect2(Vector2.ZERO, view), Color(1.0, 0.92, 0.6, 0.35 * (1.0 - (age - 0.4) / 0.5)))
	var y := centre.y + size * 0.35
	c.draw_string(Ui.font(), Vector2(5, y + 5), word, HORIZONTAL_ALIGNMENT_CENTER, view.x, size, Color(Ui.INK, land))
	c.draw_string(Ui.font(), Vector2(0, y), word, HORIZONTAL_ALIGNMENT_CENTER, view.x, size, Color(Ui.GOLD_LIGHT, land))
	var wreath := clampf((age - 0.3) / 0.5, 0.0, 1.0)
	if wreath > 0.0:
		var lsize := Vector2(size, size) * 1.3 * (1.0 + 0.4 * (1.0 - wreath))
		for side in [-1.0, 1.0]:
			var at := Vector2(centre.x + side * (w / 2.0 + lsize.x * 0.75 + 40.0 * (1.0 - wreath)), centre.y)
			c.draw_texture_rect(Hud.LAUREL, Rect2(at - lsize / 2.0, lsize), false, Color(1, 1, 1, wreath))
	var line_a := clampf((age - 0.7) * 3.0, 0.0, 1.0)
	var won := tr("%s is won") % str(sim.content.provinces[sim.province].name)
	ui.text(c, won.to_upper(), Vector2(0, y + Ui.leading() * 1.6), Color(Ui.CREAM, line_a), HORIZONTAL_ALIGNMENT_CENTER, view.x, true)
	if age >= COUNT_FROM:
		var total := sim.banked_denarii()
		var shown := counted(total, age)
		var pop := 1.0 + 0.25 * clampf(1.0 - (age - COUNT_TO) * 4.0, 0.0, 1.0) * (1.0 if age >= COUNT_TO else 0.0)
		var big := int(Ui.px * 2 * pop)
		var money := tr("+%d denarii") % shown
		var my := y + Ui.leading() * 3.6
		var mw := Ui.font().get_string_size(money, HORIZONTAL_ALIGNMENT_LEFT, -1, big).x
		_coin(c, Vector2(view.x / 2.0 - mw / 2.0 - 12.0 * Ui.scale, my - big * 0.35), 5.0 * Ui.scale)
		c.draw_string(Ui.font(), Vector2(3, my + 3), money, HORIZONTAL_ALIGNMENT_CENTER, view.x, big, Ui.INK)
		c.draw_string(Ui.font(), Vector2(0, my), money, HORIZONTAL_ALIGNMENT_CENTER, view.x, big, Ui.GOLD_LIGHT)
	var next: String = main.run_setup.province
	if age >= COUNT_TO + 0.3 and next != sim.province and sim.content.provinces.has(next):
		var na := clampf((age - COUNT_TO - 0.3) * 3.0, 0.0, 1.0)
		var on := tr("The legion marches on to %s") % str(sim.content.provinces[next].name)
		ui.text(c, on, Vector2(0, y + Ui.leading() * 5.4), Color(Ui.CREAM, na), HORIZONTAL_ALIGNMENT_CENTER, view.x, true)
	if age >= 1.0:
		ui.text(c, Controls.hint("victory"), Vector2(0, view.y - 10), Color(Ui.CREAM, 0.8), HORIZONTAL_ALIGNMENT_CENTER, view.x, true)


## Gold coins tumbling down the screen, each on its own column, speed and spin, the same every time for the same moment.
func _rain(c: CanvasItem, view: Vector2, age: float) -> void:
	for i in RAIN:
		var seed_x := fposmod(sin(i * 12.9898) * 43758.5453, 1.0)
		var seed_v := fposmod(sin(i * 78.233) * 12543.123, 1.0)
		var start := fposmod(sin(i * 3.71) * 9157.77, 1.0) * 1.2
		var t := age - start
		if t < 0.0:
			continue
		var fall := 70.0 + 90.0 * seed_v
		var p := Vector2(seed_x * view.x + sin(t * 2.0 + i) * 6.0, -12.0 + fposmod(t * fall, view.y + 24.0))
		var spin := absf(cos(t * (3.0 + 4.0 * seed_v) + i))
		_coin(c, p, (2.5 + 1.5 * seed_v) * Ui.scale, spin)


## A pixel coin, narrowed by `spin` as it turns edge-on.
func _coin(c: CanvasItem, at: Vector2, r: float, spin := 1.0) -> void:
	var w := maxf(1.0, r * spin)
	c.draw_rect(Rect2(at.x - w - 1.0, at.y - r - 1.0, 2.0 * w + 2.0, 2.0 * r + 2.0), Color(0.36, 0.2, 0.05))
	c.draw_rect(Rect2(at.x - w, at.y - r, 2.0 * w, 2.0 * r), Ui.GOLD)
	c.draw_rect(Rect2(at.x - w, at.y - r, maxf(1.0, w * 0.7), 2.0 * r), Ui.GOLD_LIGHT)


## The gold band of what the run unlocked, each with its picture, appearing one after another, kept within `area`'s height; returns the y below it.
func _unlocked(c: CanvasItem, ui: Ui, gained: Array, area: Rect2) -> float:
	var s := Ui.scale
	var pic := 16.0 * s
	var row_h := pic + 4.0
	var fit_rows := maxi(1, floori((area.size.y - Ui.leading() - 8.0) / row_h))
	# A long list spreads into three columns, and past that the last place says how many more there are.
	var cols := 2 if gained.size() <= fit_rows * 2 else 3
	var col_w := floorf(area.size.x / cols)
	var shown := gained
	var more := 0
	if gained.size() > fit_rows * cols:
		shown = gained.slice(0, fit_rows * cols - 1)
		more = gained.size() - shown.size()
	var rows := ceili((shown.size() + (1 if more > 0 else 0)) / float(cols))
	var band := Rect2(area.position.x, area.position.y, area.size.x, Ui.leading() + rows * row_h + 8.0)
	c.draw_rect(band.grow(1), Ui.GOLD)
	c.draw_rect(band, Color(0.24, 0.15, 0.1))
	c.draw_rect(Rect2(band.position, Vector2(band.size.x, 1)), Ui.GOLD_LIGHT)
	ui.text(c, tr("Unlocked").to_upper(), Vector2(band.position.x + 6.0, band.position.y + 2.0 + Ui.px), Ui.GOLD_LIGHT)
	var age := panel_age()
	if more > 0:
		var k_more := shown.size()
		var at_more := Vector2(band.position.x + 6.0 + (k_more % cols) * col_w, band.position.y + Ui.leading() + 4.0 + (k_more / cols) * row_h)
		var a_more := clampf((age - k_more * UNLOCK_STEP) * 4.0, 0.0, 1.0)
		ui.fit_text(c, tr("And %d more") % more, col_w - 10.0, at_more + Vector2(0, pic / 2.0 + Ui.px * 0.4), Color(Ui.GOLD_LIGHT, a_more))
	var size := Ui.list_size(shown.map(func(u: Dictionary) -> Array: return [str(u.text), col_w - pic - 14.0]))
	for k in shown.size():
		var a := clampf((age - k * UNLOCK_STEP) * 4.0, 0.0, 1.0)
		if a <= 0.0:
			continue
		var at := Vector2(band.position.x + 6.0 + (k % cols) * col_w, band.position.y + Ui.leading() + 4.0 + (k / cols) * row_h)
		# Each one lands with a short rise and a flash of gold, so the list reads as a reward.
		var lift := (1.0 - a) * 4.0
		var box := Rect2(at + Vector2(0, lift), Vector2(pic, pic))
		c.draw_rect(box.grow(1), Color(Ui.GOLD, a))
		_unlock_picture(c, ui, shown[k], box, a)
		ui.fit_text(c, str(shown[k].text), col_w - pic - 14.0, Vector2(box.end.x + 5.0, box.position.y + pic / 2.0 + Ui.px * 0.4), Color(Ui.CREAM, a), HORIZONTAL_ALIGNMENT_LEFT, -1.0, false, size)
	return band.end.y


## The picture for one unlock: the province's ground, a laurel for its modes or an achievement, or the new commander's man.
func _unlock_picture(c: CanvasItem, ui: Ui, u: Dictionary, box: Rect2, a: float) -> void:
	var tint := Color(1, 1, 1, a)
	match u.kind:
		"province":
			# The province shows the last prop of its own, such as a Gaulish village.
			c.draw_rect(box, Color(0.42, 0.5, 0.28, a))
			var atlas: Atlas = main.world.atlas
			var prop := ""
			for key in main.content.provinces[u.id].get("art", []):
				if str(key).begins_with("prop:"):
					prop = str(key).trim_prefix("prop:")
			if atlas != null and atlas.props.has(prop):
				var f := atlas.prop_frame(prop)
				var src: Rect2 = f[0]
				var k := minf(box.size.x / src.size.x, box.size.y / src.size.y)
				var size := src.size * k
				c.draw_texture_rect_region(atlas.texture, Rect2(box.get_center() - size / 2.0, size), src, tint)
		"commander":
			var atlas: Atlas = main.world.atlas
			var unit := "commander"
			for key in main.content.commanders[u.id].get("art", []):
				if str(key).begins_with("unit:"):
					unit = str(key).trim_prefix("unit:")
				elif str(key).begins_with("icon:") and ui.icon(str(key).trim_prefix("icon:")) != null:
					c.draw_rect(box, Ui.PARCH)
					c.draw_texture_rect(ui.icon(str(key).trim_prefix("icon:")), box, false, tint)
					return
			c.draw_rect(box, Ui.PARCH)
			if atlas != null and atlas.units.has(unit):
				var f: Array = atlas.unit_frame(unit, "idle" if atlas.units[unit].has("idle") else "move", "south", 0.0)
				var src: Rect2 = f[0]
				var k := minf(box.size.x / src.size.x, box.size.y / src.size.y) * 1.3
				var size := src.size * k
				c.draw_texture_rect_region(atlas.texture, Rect2(box.get_center() - size / 2.0 + Vector2(0, -1), size), src, tint)
		_:
			c.draw_rect(box, Color(0.36, 0.22, 0.12, a))
			c.draw_texture_rect(Hud.LAUREL, box, false, tint)


func _bars(c: CanvasItem, ui: Ui, sim: Sim, area: Rect2, row: float) -> void:
	ui.text(c, tr("Damage by source").to_upper(), Vector2(area.position.x, area.position.y), Ui.BROWN)
	var rows := top_sources(sim)
	if rows.is_empty():
		ui.text(c, tr("None recorded"), Vector2(area.position.x, area.position.y + row), Ui.MUTED)
		return
	var name_w := names_width(rows.map(func(row): return str(row[0])))
	var val_w := 38.0 if Ui.scale == 1 else 66.0
	var bar_x := area.position.x + name_w + 8.0
	var bar_w := area.end.x - val_w - bar_x
	var most: float = rows[0][1]
	for i in rows.size():
		var y := area.position.y + row * (i + 1)
		var top := y - Ui.px * 3 / 4
		ui.fit_text(c, rows[i][0], name_w, Vector2(area.position.x, y), Ui.INK)
		var fill := maxf(1.0, floorf(bar_w * rows[i][1] / most))
		c.draw_rect(Rect2(bar_x - 1, top - 1, bar_w + 2, Ui.px * 3 / 4 + 3), Ui.INK)
		c.draw_rect(Rect2(bar_x, top, bar_w, Ui.px * 3 / 4 + 1), Ui.PARCH_DARK)
		c.draw_rect(Rect2(bar_x, top, fill, Ui.px * 3 / 4 + 1), Ui.GOLD)
		c.draw_rect(Rect2(bar_x, top, fill, 1), Ui.GOLD_LIGHT)
		ui.text(c, short(rows[i][1]), Vector2(0, y), Ui.INK, HORIZONTAL_ALIGNMENT_RIGHT, area.end.x)


func _chart(c: CanvasItem, ui: Ui, sim: Sim, area: Rect2, cap_y: float) -> void:
	ui.text(c, tr("Legion size over time").to_upper(), Vector2(area.position.x, cap_y), Ui.BROWN)
	var pts := chart_points(sim)
	if pts.size() < 2:
		c.draw_rect(area, Ui.PARCH_DARK, false, 1.0)
		ui.text(c, tr("The run was too short to chart"), Vector2(area.position.x + 8, area.get_center().y + 3), Ui.MUTED)
		return
	var most := 1
	for p in pts:
		most = maxi(most, int(p.legion))
	ui.text(c, tr("Largest %d") % most, Vector2(0, cap_y), Ui.INK, HORIZONTAL_ALIGNMENT_RIGHT, area.end.x)
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
