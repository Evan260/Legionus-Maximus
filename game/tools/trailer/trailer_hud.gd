extends Hud
## The interface as the trailer shows it: only the gods' names and the triumph's VICTORY over the field, and the screens.


func _scene() -> void:
	var sim: Sim = main.sim
	if main.screens.has(main.state):
		ui.begin()
		draw_set_transform(Ui.offset)
		main.screens[main.state].draw(self, ui)
		ui.end()
		return
	_god_banner(sim)
	_victory_banner(sim)
