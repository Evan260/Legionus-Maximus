class_name PauseScreen
extends RefCounted
## Pause: resume, open the settings, or give up the run.

var main: Node
# Giving up asks twice, so a stray Q or click does not end the run.
var confirming := false


func _init(owner_node: Node) -> void:
	main = owner_node


func activate(id: String) -> void:
	match id:
		"resume":
			confirming = false
			main.state = "play"
			main.ui.focus = ""
		"settings":
			main.open_settings("pause")
		"giveup":
			if not confirming:
				confirming = true
				return
			main.sim.over = true
			main._finish_run()


func draw(c: CanvasItem, ui: Ui) -> void:
	Ui.veil(c, 0.45)
	var h := 32.0 if Ui.scale > 1 else 22.0
	var w := 260.0 if Ui.scale > 1 else 180.0
	var top := Ui.H / 2 - (3 * h + 2 * 8) / 2 - 8
	ui.text(c, tr("Paused").to_upper(), Vector2(0, top - 8), Ui.CREAM, HORIZONTAL_ALIGNMENT_CENTER, Ui.W, true)
	ui.button(c, Rect2(Ui.W / 2 - w / 2, top, w, h), "resume", tr("Resume").to_upper(), "", true, null, true)
	ui.button(c, Rect2(Ui.W / 2 - w / 2, top + h + 8, w, h), "settings", tr("Settings").to_upper(), "", true, null, true)
	ui.button(c, Rect2(Ui.W / 2 - w / 2, top + 2 * (h + 8), w, h), "giveup", tr("Give up the run").to_upper(), "", true, null, true)
	if confirming:
		ui.fit_text(c, tr("Give up the run? %s again to confirm") % Controls.key_of("quit"), Ui.W - 16.0, Vector2(0, top + 3 * (h + 8) + 8), Ui.GOLD, HORIZONTAL_ALIGNMENT_CENTER, Ui.W, true)
