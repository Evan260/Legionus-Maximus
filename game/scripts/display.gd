class_name Display
extends SubViewportContainer
## Shows the 640 by 360 view in the window, blown up by whole pixels and smoothed down so each game pixel keeps its width.

const VIEW := Vector2(640, 360)

var game: SubViewport


## The view Godot's "expand" stretch gives a window: 640 by 360 widened or deepened to the window's shape.
static func base_size(window: Vector2i) -> Vector2i:
	var aspect := float(window.x) / float(window.y)
	var view := VIEW
	if not is_equal_approx(aspect, VIEW.aspect()):
		view = Vector2(VIEW.y * aspect, VIEW.y) if aspect > VIEW.aspect() else Vector2(VIEW.x, VIEW.x / aspect)
	return Vector2i(view.floor())


static func _whole(s: float) -> bool:
	return absf(s - roundf(s)) < 0.01


## The whole scale each axis is drawn from before it is smoothed down to the window.
static func prescale(scale: Vector2) -> Vector2:
	var k := Vector2.ZERO
	for i in 2:
		k[i] = maxf(1.0, roundf(scale[i]) if _whole(scale[i]) else ceilf(scale[i]))
	return k


## Whether the view fills the window at exactly a whole scale, so plain nearest filtering keeps every pixel the same width.
static func is_whole(scale: Vector2) -> bool:
	return scale == scale.round()


# The view is sized before the game inside it is ready, so the game starts with the size it keeps.
func _enter_tree() -> void:
	game = $Game
	var root := get_tree().root
	# A recorded movie and a headless run keep Godot's own stretch, so the movie still records the 640 by 360 view.
	if Engine.get_write_movie_path() == "" and DisplayServer.get_name() != "headless":
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size_changed.connect(_fit)
	_fit()


func _fit() -> void:
	var root := get_tree().root
	if root.content_scale_mode != Window.CONTENT_SCALE_MODE_DISABLED:
		game.size = Vector2i(root.get_visible_rect().size)
		size = game.size
		scale = Vector2.ONE
		material = null
		return
	if root.size.x <= 0 or root.size.y <= 0:
		return
	game.size = base_size(root.size)
	size = game.size
	scale = Vector2(root.size) / Vector2(game.size)
	Touch.fit(root.size, game.size)
	if is_whole(scale):
		material = null
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	else:
		if material == null:
			material = ShaderMaterial.new()
			material.shader = preload("res://scripts/sharp_scale.gdshader")
		material.set_shader_parameter("prescale", prescale(scale))
		texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
