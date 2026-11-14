class_name MapScreen
extends RefCounted
## The map: every province that is drawn, its best time and results, and the modes that open once it is won.

const MODES := [["hard", "Hard"], ["endless", "Endless"], ["decimatio", "Decimatio"]]

var main: Node


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
	var i := 0
	for id in content.provinces:
		if not content.ready("provinces", id) or not Profile.province_unlocked(id):
			continue
		var info: Dictionary = content.provinces[id]
		var rec := Profile.record_of(id)
		var row := Rect2(r.position.x + 12, r.position.y + 28 + i * 74, r.size.x - 24, 68)
		var chosen: bool = setup.province == id
		ui.button(c, row, "prov:" + id, "")
		ui.text(c, info.name.to_upper(), Vector2(row.position.x + 8, row.position.y + 15), Ui.INK)
		if chosen:
			ui.text(c, "MARCHING HERE", Vector2(0, row.position.y + 15), Ui.BROWN, HORIZONTAL_ALIGNMENT_RIGHT, row.end.x - 8)
		ui.text(c, ui.clip(info.text, row.size.x - 16), Vector2(row.position.x + 8, row.position.y + 26), Ui.BROWN)
		var results: Array = ["Best time " + clock(rec.best_time) if rec.best_time > 0.0 else "Not won yet"]
		results.append("Won" if rec.won else "Not won")
		results.append("Hard won" if rec.hard_won else "Hard not won")
		if rec.endless_best > 0.0:
			results.append("Endless " + clock(rec.endless_best))
		ui.text(c, "     ".join(results), Vector2(row.position.x + 8, row.position.y + 38), Ui.INK)
		for k in MODES.size():
			var on: bool = setup[MODES[k][0]] and chosen
			var label: String = ("[x] " if on else "[ ] ") + MODES[k][1]
			ui.button(c, Rect2(row.position.x + 8 + k * 112, row.position.y + 45, 106, 16), "%s:%s" % [MODES[k][0], id], label, "", rec.won, null, true)
		if not rec.won:
			ui.text(c, "Win here to open these", Vector2(0, row.position.y + 57), Ui.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, row.end.x - 8)
		i += 1
