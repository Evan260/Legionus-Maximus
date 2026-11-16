extends Hud
## The interface as the trailer shows it: only the gods' names, the triumph's VICTORY, the level-up and gods' choices,
## and the screens.


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
	if main.state == "choose" or main.state == "pray":
		_choices(sim)
