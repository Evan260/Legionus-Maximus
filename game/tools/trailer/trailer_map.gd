extends MapScreen
## The map as the trailer shows it: the painted map, the road and the provinces' names, without the panel or the key hints.


func draw(c: CanvasItem, ui: Ui) -> void:
	var ids := road()
	if selected == "" or not ids.has(selected):
		selected = main.run_setup.province if ids.has(main.run_setup.province) else ids[0]
	var now := Time.get_ticks_msec() / 1000.0
	Ui.veil(c, 0.85)
	if _picture == null:
		_picture = load("res://assets/map.png")
	c.draw_texture_rect(_picture, picture_rect(), false)
	_road(c, ids, now)
	for id in ids:
		_node(c, ui, id, now)
	_fog(c, ids, now)
	_labels(c, ui, ids)
