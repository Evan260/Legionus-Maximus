extends Node
## The trailer's edit, cut from the recorded shots under the game's own music; tools/trailer/make_trailer.py renders it.

const FPS := 30.0
## One beat of the music at 90 beats a minute, in seconds; every cut lands on a beat.
const BEAT := 0.6667
const HARP := "res://assets/audio/music/calm.ogg"
const DRUMS := "res://assets/audio/music/drums.ogg"
const MUSIC_DB := -3.0
const SILENT_DB := -60.0
## How fast the drums come in and go out, in decibels a second.
const DRUMS_FADE := 120.0
## The fighting is recorded beside the music, so it sits a little under it.
const SOUND_DB := -4.0
## Screen pixels to the game pixel, as the game draws its 640 by 360 view in a 1920 by 1080 frame.
const PIXEL := 3
const SIZE := Vector2(1920, 1080)
const INK := Color(0.16, 0.1, 0.08)
const CREAM := Color(0.99, 0.95, 0.86)
const CAPTION_Y := 292
const LOGO_Y := 60
const SCROLL_Y := 223
## Where the scroll's line of text sits, from the top of its picture, so it is centred on the sheet between the rolls.
const SCROLL_TEXT_TOP := 2
const SCROLL_TEXT_HEIGHT := 51
## The store badges, in screen pixels: their height, the gap between them and their top.
const BADGE_HEIGHT := 96.0
const BADGE_GAP := 40.0
const BADGE_Y := 891.0
## The Google Play picture has clear margins round its badge, this share of its height above and below.
const GOOGLE_MARGIN := 41.0 / 250.0
## The story, close in first and wider as it goes: the commander and a handful of men in a small fight, a level-up that
## brings a ballista crew and a mixed legion at work, the forest felled and a gorge bridged, the bosses read and beaten
## in Germania and Dacia, a crowd held in Parthia, Gaul, the gods called on in the snow, the one great horde under
## Jupiter's lightning, the fort held in Britannia to the triumph and the map of the five provinces. A shot plays from `from` seconds into its recording; a card is black with one line of text; `drums: false`
## keeps the drums out; `zoom` shows a shot a whole number of times larger around `centre`, in screen pixels.
const TRAILER := [
	{"card": "Germania, AD 9.", "beats": 4, "drums": false},
	{"shot": "skirmish", "from": 1.0, "beats": 7, "caption": "Lead the legion.", "drums": false, "fade_in": 0.6, "zoom": 2.0, "centre": Vector2(1050, 540)},
	{"shot": "levelup", "from": 0.8, "beats": 6, "caption": "Choose your men.", "drums": false},
	{"shot": "archers", "from": 1.0, "beats": 7, "caption": "Every man fights.", "zoom": 2.0, "centre": Vector2(1150, 540)},
	{"shot": "fell", "from": 1.5, "beats": 6, "caption": "Fell the forest."},
	{"shot": "bridge", "from": 0.3, "beats": 6, "caption": "Bridge the gorge."},
	{"shot": "whirl", "from": 0.2, "beats": 7, "caption": "Step out of the ring.", "zoom": 2.0, "centre": Vector2(1170, 560)},
	{"shot": "onrush", "from": 0.5, "beats": 7, "caption": "Read the charge."},
	{"shot": "ravine", "from": 0.2, "beats": 6, "caption": "Shove them over."},
	{"shot": "hold", "from": 1.0, "beats": 6, "caption": "Hold the line."},
	{"shot": "field", "from": 1.0, "beats": 6, "caption": "March on Gaul."},
	{"shot": "gods", "from": 0.8, "beats": 5, "caption": "Call on the gods."},
	{"shot": "reveal", "from": 1.6, "beats": 6},
	{"shot": "fort", "from": 1.0, "beats": 8, "caption": "Hold the fort."},
	{"shot": "map", "from": 0.8, "beats": 5, "caption": "Five provinces."},
	{"end": "endcard", "from": 1.0, "beats": 10, "dim": 0.3, "drums": false},
]

var _shots_dir := ""
var _frame := 0
var _starts: Array = []
var _total_frames := 0
var _picture: TextureRect
var _texture: ImageTexture
var _overlay: SubViewport
var _black: ColorRect
var _shade: ColorRect
var _card_text: Label
var _caption: Label
var _logo: TextureRect
var _scroll: TextureRect
var _wishlist: Label
var _badges: Array[TextureRect] = []
var _vignette: TextureRect
var _harp: AudioStreamPlayer
var _drums: AudioStreamPlayer
var _sound: AudioStreamPlayer
var _current := -1
## The drums' level before the closing fade.
var _drums_level := SILENT_DB


func _ready() -> void:
	# The game's own music and sounds start with this scene too; only the trailer's play.
	RenderingServer.set_default_clear_color(Color.BLACK)
	for bus in ["Music", "Effects"]:
		AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), true)
	var from := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--from="):
			from = float(arg.trim_prefix("--from="))
	var t := 0
	for seg in TRAILER:
		_starts.append(t)
		t += int(round(float(seg["beats"]) * BEAT * FPS))
	_total_frames = t
	_build()
	_harp = _music_player(HARP)
	_drums = _music_player(DRUMS)
	_sound = AudioStreamPlayer.new()
	add_child(_sound)
	# A preview can start part way through, to look at one moment without rendering the whole trailer.
	_frame = int(from * FPS)
	_harp.play(fmod(from, _harp.stream.get_length()))
	_drums.play(fmod(from, _drums.stream.get_length()))
	_drums_level = MUSIC_DB if _segment_at(_frame).get("drums", true) else SILENT_DB
	_process(0.0)
	_frame -= 1


func _music_player(path: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	var stream: AudioStreamOggVorbis = load(path).duplicate()
	stream.loop = true
	p.stream = stream
	p.volume_db = MUSIC_DB
	add_child(p)
	return p


## A picture kept beside the scripts that make it, outside the game's own files.
static func _outside(name: String) -> Texture2D:
	var path := ProjectSettings.globalize_path("res://").path_join("../tools/trailer/" + name)
	return ImageTexture.create_from_image(Image.load_from_file(path))


func _build() -> void:
	# The shots are recorded at the game's own 640 by 360 and shown three times larger in whole pixels, as the game is.
	_texture = ImageTexture.create_from_image(Image.create(int(SIZE.x) / PIXEL, int(SIZE.y) / PIXEL, false, Image.FORMAT_RGB8))
	_picture = TextureRect.new()
	_picture.texture = _texture
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.size = SIZE
	add_child(_picture)
	# A soft dark oval behind the end card's logo and scroll, so the lettering reads over the field.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.03, 0.02, 0.02, 0.6))
	gradient.set_color(1, Color(0.03, 0.02, 0.02, 0.0))
	var oval := GradientTexture2D.new()
	oval.gradient = gradient
	oval.fill = GradientTexture2D.FILL_RADIAL
	oval.fill_from = Vector2(0.5, 0.5)
	oval.fill_to = Vector2(1.0, 0.5)
	oval.width = 256
	oval.height = 128
	_vignette = TextureRect.new()
	_vignette.texture = oval
	_vignette.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_vignette.stretch_mode = TextureRect.STRETCH_SCALE
	_vignette.position = Vector2(260, 60)
	_vignette.size = Vector2(1400, 860)
	add_child(_vignette)
	# Cards, captions and the end card are drawn in the game's own pixels and scaled up, like the game.
	var area := SIZE / float(PIXEL)
	_overlay = SubViewport.new()
	_overlay.size = Vector2i(area)
	_overlay.transparent_bg = true
	_overlay.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_overlay.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_overlay)
	var shown := TextureRect.new()
	shown.texture = _overlay.get_texture()
	shown.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shown.size = SIZE
	shown.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(shown)
	_shade = ColorRect.new()
	_shade.color = Color(0.05, 0.04, 0.03, 0.0)
	_shade.size = area
	_overlay.add_child(_shade)
	_black = ColorRect.new()
	_black.color = Color.BLACK
	_black.size = area
	_overlay.add_child(_black)
	# The text is the game's own pixel font at twice its size, still whole pixels, to read at a glance.
	_card_text = _label(Vector2(20, area.y / 2.0 - 40.0), area.x - 40.0, 80, 16)
	_caption = _label(Vector2(10, CAPTION_Y), area.x - 20.0, 24, 16)
	_caption.add_theme_color_override("font_outline_color", INK)
	_caption.add_theme_constant_override("outline_size", 4)
	_logo = TextureRect.new()
	_logo.texture = load("res://assets/logo.png")
	_logo.position = Vector2(roundf((area.x - _logo.texture.get_width()) / 2.0), LOGO_Y)
	_overlay.add_child(_logo)
	_scroll = TextureRect.new()
	_scroll.texture = _outside("scroll.png")
	_scroll.position = Vector2(roundf((area.x - _scroll.texture.get_width()) / 2.0), SCROLL_Y)
	_overlay.add_child(_scroll)
	_wishlist = _label(_scroll.position + Vector2(0, SCROLL_TEXT_TOP), _scroll.texture.get_width(), SCROLL_TEXT_HEIGHT, 16)
	_wishlist.text = "Wishlist now on Steam"
	_wishlist.add_theme_color_override("font_color", Color(0.29, 0.18, 0.14))
	# The store badges are drawn at the frame's own resolution, as the stores supply them, side by side under the scroll.
	var apple := _badge("badge_app_store.png", BADGE_HEIGHT)
	var google := _badge("badge_google_play.png", BADGE_HEIGHT / (1.0 - 2.0 * GOOGLE_MARGIN))
	var margin := google.size.y * GOOGLE_MARGIN
	var google_seen := google.size.x - 2.0 * margin
	var left := roundf((SIZE.x - apple.size.x - BADGE_GAP - google_seen) / 2.0)
	apple.position = Vector2(left, BADGE_Y)
	google.position = Vector2(left + apple.size.x + BADGE_GAP - margin, BADGE_Y - margin)


func _badge(file: String, height: float) -> TextureRect:
	var r := TextureRect.new()
	r.texture = _outside(file)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	r.size = Vector2(roundf(r.texture.get_width() * height / r.texture.get_height()), roundf(height))
	add_child(r)
	_badges.append(r)
	return r


func _label(at: Vector2, width: float, height: float, size: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", Ui.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", CREAM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.position = at
	l.size = Vector2(width, height)
	_overlay.add_child(l)
	return l


func _segment_at(frame: int) -> Dictionary:
	var k := _starts.size() - 1
	while k > 0 and _starts[k] > frame:
		k -= 1
	return TRAILER[k]


func _process(delta: float) -> void:
	if _frame >= _total_frames:
		get_tree().quit()
		return
	var k := _starts.size() - 1
	while _starts[k] > _frame:
		k -= 1
	var seg: Dictionary = TRAILER[k]
	var local := float(_frame - _starts[k]) / FPS
	var length := float(seg["beats"]) * BEAT
	if k != _current:
		_current = k
		_start_segment(seg)
	_draw_segment(seg, local, length)
	# The drums come in with the fighting, and all the music fades away over the end card's last seconds.
	var fade := linear_to_db(clampf(float(_total_frames - _frame) / FPS / 3.0, 0.0001, 1.0))
	_drums_level = move_toward(_drums_level, MUSIC_DB if seg.get("drums", true) else SILENT_DB, DRUMS_FADE * delta)
	_drums.volume_db = _drums_level + fade
	_harp.volume_db = MUSIC_DB + fade
	_frame += 1


func _start_segment(seg: Dictionary) -> void:
	_sound.stop()
	var name := String(seg.get("shot", seg.get("end", "")))
	if name == "":
		return
	var wav := _shots_dir.path_join(name).path_join("f.wav")
	if FileAccess.file_exists(wav):
		_sound.stream = AudioStreamWAV.load_from_file(wav)
		_sound.play(float(seg["from"]))


func _draw_segment(seg: Dictionary, local: float, length: float) -> void:
	var is_card := seg.has("card")
	var is_end := seg.has("end")
	_black.visible = is_card
	_card_text.visible = is_card
	_logo.visible = is_end
	_scroll.visible = is_end
	_wishlist.visible = is_end
	_shade.visible = is_end
	_vignette.visible = is_end
	for b in _badges:
		b.visible = is_end
	_caption.visible = seg.has("caption")
	if is_card:
		_card_text.text = String(seg["card"])
		# The line fades in and out on the black, so cards never jump.
		_card_text.modulate.a = clampf(minf(local / 0.35, (length - local) / 0.35), 0.0, 1.0)
		return
	var name := String(seg.get("shot", seg.get("end", "")))
	var index := int(round((float(seg["from"]) + local) * FPS))
	var path := _shots_dir.path_join(name).path_join("f%08d.png" % index)
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		img.convert(Image.FORMAT_RGB8)
		_texture.update(img)
	# A small moment is shown a whole number of times larger, so the pixels stay square.
	var zoom := float(seg.get("zoom", 1.0))
	var centre: Vector2 = seg.get("centre", SIZE / 2.0)
	_picture.scale = Vector2(zoom, zoom)
	_picture.position = (SIZE / 2.0 - centre * zoom).round().clamp(SIZE * (1.0 - zoom), Vector2.ZERO)
	var fade_in := float(seg.get("fade_in", 0.0))
	_picture.modulate = Color.WHITE * (clampf(local / fade_in, 0.0, 1.0) if fade_in > 0.0 else 1.0)
	_picture.modulate.a = 1.0
	if seg.has("caption"):
		_caption.text = String(seg["caption"])
		# A caption comes up just after the cut and fades out as the shot ends.
		_caption.modulate.a = minf(clampf((local - 0.15) / 0.3, 0.0, 1.0), clampf((length - local) / 0.3, 0.0, 1.0))
	if is_end:
		# The field darkens a little behind the logo, which settles in first, then the scroll and the badges beneath it.
		_shade.color.a = clampf(local / 0.8, 0.0, 1.0) * float(seg.get("dim", 0.0))
		_vignette.modulate.a = clampf(local / 0.8, 0.0, 1.0)
		_logo.modulate.a = clampf((local - 0.4) / 0.8, 0.0, 1.0)
		_logo.position.y = LOGO_Y + roundf(4.0 * (1.0 - _logo.modulate.a))
		var s := clampf((local - 1.6) / 0.6, 0.0, 1.0)
		_scroll.modulate.a = s
		_wishlist.modulate.a = s
		for b in _badges:
			b.modulate.a = clampf((local - 2.2) / 0.6, 0.0, 1.0)
	# Sound from each shot fades in and out quickly at its cuts, so cuts never click.
	_sound.volume_db = SOUND_DB + linear_to_db(clampf(minf(local / 0.08, (length - local) / 0.08), 0.0001, 1.0))
