extends Hud
## The interface as the trailer shows it: the top bar with the moment's level, clock and kills, the bosses' names, the
## chieftain's health, the banners, the level-up and gods' choices and the screens, without the objective markers or
## the bottom row of key hints.


func _scene() -> void:
	var sim: Sim = main.sim
	if main.screens.has(main.state):
		ui.begin()
		draw_set_transform(Ui.offset)
		main.screens[main.state].draw(self, ui)
		ui.end()
		return
	var white := sim.flash()
	if white > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Ui.view), Color(1, 1, 1, white * float(sim.b.chief_death.flash)))
	var choosing: bool = main.state == "choose" or main.state == "pray"
	var staged: Node = main.get_node_or_null("TrailerShots")
	if staged != null and staged.hud_shown():
		if Touch.phone:
			_phone_bar(sim, staged)
		else:
			_staged_bar(sim, staged, choosing)
	# The names are placed for the field at its own size, so a field drawn larger leaves them out.
	if not choosing and (staged == null or not staged.zoomed()):
		for b in boss_names(sim):
			text(b.name, Vector2(b.rect.position.x, b.rect.position.y + Ui.px), GOLD_LIGHT)
	_god_banner(sim)
	_chief_banner(sim)
	_victory_banner(sim)
	if choosing:
		_choices(sim)


## A phone's own top bar and bottom row, which keep clear of its buttons, showing the staged moment's level, clock and kills.
func _phone_bar(sim: Sim, staged: Node) -> void:
	var run := [sim.level, sim.time, sim.kills]
	var shown := [staged.level(sim), staged.seconds(sim), staged.kills(sim)]
	sim.level = shown[0]
	sim.time = shown[1]
	sim.kills = shown[2]
	_top_bar(sim)
	sim.level = run[0]
	sim.time = run[1]
	sim.kills = run[2]


## The top bar as a run at the staged moment shows it: experience, level, clock, legion and kills, and the chieftain's health.
func _staged_bar(sim: Sim, staged: Node, choosing: bool) -> void:
	var W := Ui.view.x
	var big := Ui.scale > 1
	draw_rect(Rect2(8, 6, W - 16, 7), INK)
	var fill := (W - 18) * clampf(float(sim.xp) / sim.xp_next, 0.0, 1.0)
	draw_rect(Rect2(9, 7, fill, 5), GOLD)
	draw_rect(Rect2(9, 7, fill, 1), GOLD_LIGHT)
	var y1 := 16.0 + 8.0 * Ui.scale
	var y2 := y1 + (11.0 if not big else 20.0)
	var secs := int(staged.seconds(sim))
	plated_text((tr("Level %d") % staged.level(sim)).to_upper(), Vector2(10, y1))
	plated_text("%02d:%02d" % [secs / 60, secs % 60], Vector2(0, y1), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W)
	plated_text((tr("Legion %d") % (sim.soldiers.size() + 1)).to_upper(), Vector2(0, y1), CREAM, HORIZONTAL_ALIGNMENT_RIGHT, W - 10)
	if choosing:
		return
	plated_text((tr("Kills %d") % staged.kills(sim)).to_upper(), Vector2(0, y2), CREAM, HORIZONTAL_ALIGNMENT_RIGHT, W - 10)
	_chieftain_line(sim, W, y1, big)
