class_name MapScreen
extends RefCounted
## The map: every province that is drawn, its best time and results, and the modes that open once it is won.

const MODES := [["hard", "Hard"], ["endless", "Endless"], ["decimatio", "Decimatio"]]

var main: Node
var scroll := 0


func _init(owner_node: Node) -> void:
	main = owner_node


func activate(id: String) -> void:
	var parts := id.split(":")
	var setup: Dictionary = main.run_setup
	if parts[0] == "prov":
		if parts[1] != setup.province:
			setup.province = parts[1]
			for m in MODES:
				setup[m[0]] = false
		Profile.data.settings.province = setup.province
		Profile.save()
	elif Profile.record_of(parts[1]).won:
		if parts[1] != setup.province:
			activate("prov:" + parts[1])
		setup[parts[0]] = not setup[parts[0]]


static func clock(seconds: float) -> String:
	return "%d:%02d" % [int(seconds) / 60, int(seconds) % 60]


## The longest each part of a province's results line can be, for sizing the rows.
func worst_results() -> Array:
	var out: Array = [tr("Best time %s") % "99:59"]
	for pair in [[tr("Won"), tr("Not won")], [tr("Hard won"), tr("Hard not won")]]:
		out.append(pair[0] if Ui.width_at(pair[0], Ui.px) > Ui.width_at(pair[1], Ui.px) else pair[1])
	out.append(tr("Endless %s") % "99:59")
	return out


## The width of a mode button: the usual one, or wider when the longest mode name needs it, up to a third of the row.
func mode_width(room: float) -> float:
	var widest := 0.0
	for m in MODES:
		widest = maxf(widest, Ui.width_at("[x] " + tr(m[1]), Ui.px))
	return clampf(widest + 14.0, 106.0 if Ui.scale == 1 else 178.0, (room - 12.0) / 3.0)


func draw(c: CanvasItem, ui: Ui) -> void:
	var content: Content = main.content
	var r := ui.frame(c, tr("Map").to_upper(), Controls.hint("pick"))
	var setup: Dictionary = main.run_setup
	var big := Ui.scale > 1
	var ids: Array = []
	for id in content.provinces:
		if content.ready("provinces", id) and Profile.province_unlocked(id) and Game.province_allowed(id, main.balance):
			ids.append(id)
	var text_w := r.size.x - 40.0
	# Rows are as tall as the longest description and results line need, so the list stays even.
	var extra := 0.0
	for id in ids:
		var b: Dictionary = Ui.block(content.provinces[id].text, text_w, 2)
		extra = maxf(extra, (mini(b.lines, 2) - 1) * Ui.lead_for(b.size))
	extra += (mini(Ui.pack(worst_results(), "  " if big else "     ", text_w).size(), 2) - 1) * Ui.leading()
	var h := (68.0 if not big else 118.0) + extra + Ui.leading()
	var step := h + 6.0
	var bw := mode_width(text_w)
	var visible := int((r.size.y - 36.0) / step)
	scroll = Ui.scroll_for(maxi(ids.find(ui.focus.get_slice(":", 1)), 0), ids.size(), visible, scroll)
	for i in ids.size():
		var id: String = ids[i]
		var info: Dictionary = content.provinces[id]
		var rec := Profile.record_of(id)
		var row := Rect2(r.position.x + 12, r.position.y + 28 + (i - scroll) * step, r.size.x - 24, h)
		if i < scroll or i >= scroll + visible:
			ui.register(row, "prov:" + id)
			continue
		var chosen: bool = setup.province == id
		var y := row.position.y + 8.0 + 8.0 * Ui.scale
		ui.button(c, row, "prov:" + id, "")
		ui.text(c, info.name.to_upper(), Vector2(row.position.x + 8, y), Ui.INK)
		if chosen:
			ui.text(c, tr("Marching here").to_upper(), Vector2(0, y), Ui.BROWN, HORIZONTAL_ALIGNMENT_RIGHT, row.end.x - 8)
		y += Ui.leading() + 1.0
		y = ui.wrap_fit(c, info.text, Vector2(row.position.x + 8, y), text_w, Ui.BROWN, 2) + 1.0
		var results: Array = [tr("Best time %s") % clock(rec.best_time) if rec.best_time > 0.0 else tr("Not won yet")]
		results.append(tr("Won") if rec.won else tr("Not won"))
		results.append(tr("Hard won") if rec.hard_won else tr("Hard not won"))
		if rec.endless_best > 0.0:
			results.append(tr("Endless %s") % clock(rec.endless_best))
		for line in Ui.pack(results, "  " if big else "     ", text_w).slice(0, 2):
			ui.text(c, line, Vector2(row.position.x + 8, y), Ui.INK)
			y += Ui.leading()
		y += 6.0 - Ui.leading()
		for k in MODES.size():
			var on: bool = setup[MODES[k][0]] and chosen
			var label: String = ("[x] " if on else "[ ] ") + tr(MODES[k][1])
			ui.button(c, Rect2(row.position.x + 8 + k * (bw + 6.0), y, bw, 16 if not big else 24), "%s:%s" % [MODES[k][0], id], label, "", rec.won, null, true)
		if not rec.won:
			ui.fit_text(c, tr("Win here to open these"), text_w, Vector2(row.position.x + 8, row.end.y - 6), Ui.MUTED)
