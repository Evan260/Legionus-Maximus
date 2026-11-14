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


func draw(c: CanvasItem, ui: Ui) -> void:
	var content: Content = main.content
	var r := ui.frame(c, "MAP", "Arrows or WASD move     Space choose     Esc back")
	var setup: Dictionary = main.run_setup
	var big := Ui.scale > 1
	var h := 68.0 if not big else 118.0
	var step := h + 6.0
	var ids: Array = []
	for id in content.provinces:
		if content.ready("provinces", id) and Profile.province_unlocked(id) and Game.province_allowed(id, main.balance):
			ids.append(id)
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
			ui.text(c, "MARCHING HERE", Vector2(0, y), Ui.BROWN, HORIZONTAL_ALIGNMENT_RIGHT, row.end.x - 8)
		y += Ui.leading() + 1.0
		ui.text(c, ui.clip(info.text, row.size.x - 16), Vector2(row.position.x + 8, y), Ui.BROWN)
		y += Ui.leading() + 1.0
		var results: Array = ["Best time " + clock(rec.best_time) if rec.best_time > 0.0 else "Not won yet"]
		results.append("Won" if rec.won else "Not won")
		results.append("Hard won" if rec.hard_won else "Hard not won")
		if rec.endless_best > 0.0:
			results.append("Endless " + clock(rec.endless_best))
		ui.text(c, ui.clip("     ".join(results) if not big else "  ".join(results), row.size.x - 16), Vector2(row.position.x + 8, y), Ui.INK)
		y += 6.0
		var bw := 106.0 if not big else 178.0
		for k in MODES.size():
			var on: bool = setup[MODES[k][0]] and chosen
			var label: String = ("[x] " if on else "[ ] ") + MODES[k][1]
			ui.button(c, Rect2(row.position.x + 8 + k * (bw + 6.0), y, bw, 16 if not big else 24), "%s:%s" % [MODES[k][0], id], label, "", rec.won, null, true)
		if not rec.won:
			ui.text(c, "Win here to open these", Vector2(0, row.end.y - 6), Ui.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, row.end.x - 8)
