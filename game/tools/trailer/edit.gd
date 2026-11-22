extends Node
## The trailer's edit, cut from the recorded shots on the beat of the war theme; tools/trailer/make_trailer.py renders it.

const FPS := 30.0
## One beat of the war theme, at 103.36 beats a minute, and where its first beat falls in the track, in seconds.
const BEAT := 0.5805
const FIRST_BEAT := 0.0697
const MUSIC := "res://assets/audio/music/battle_war_theme.ogg"
## From the trailer's beat on the left the music plays from the track's beat on the right: the track's opening, then the
## quiet bars before its big return, the return itself as Jupiter's lightning strikes, and the track's own last bars.
const MUSIC_CUTS := [[0, 0], [87, 271], [95, 279], [119, 471]]
const MUSIC_DB := -1.0
## The fighting recorded with each shot plays under the music.
const SOUND_DB := -7.0
## Sounds laid over the edit, as [trailer beat, sound, decibels]: the logo's landing, the drop into the quiet bars and
## the end card's horn.
const STINGS := [[7, "boom_1", 0.0], [87, "boom_2", -8.0], [119, "horn_1", -5.0]]
## Screen pixels to the game pixel, as the game draws its 640 by 360 view in a 1920 by 1080 frame.
const PIXEL := 3
const SIZE := Vector2(1920, 1080)
const INK := Color(0.16, 0.1, 0.08)
const GOLD := Color(1.0, 0.86, 0.5)
const CREAM := Color(0.99, 0.95, 0.86)
## Where the captions sit, in game pixels from the top: the line's middle, and the province's name above it.
const CAPTION_Y := 290.0
const LABEL_Y := 266.0
const CAPTION_SIZE := 24
const LABEL_SIZE := 16
## A caption lands larger and settles to its size over this many seconds.
const POP := 0.16
const POP_SCALE := 1.6
const LOGO_Y := 134.0
const END_LOGO_Y := 60.0
const SCROLL_Y := 223.0
## Where the scroll's line of text sits, from the top of its picture, so it is centred on the sheet between the rolls.
const SCROLL_TEXT_TOP := 2
const SCROLL_TEXT_HEIGHT := 51
## The store badges, in screen pixels: their height, the gap between them and their top.
const BADGE_HEIGHT := 96.0
const BADGE_GAP := 40.0
const BADGE_Y := 891.0
## The Google Play picture has clear margins round its badge, this share of its height above and below.
const GOOGLE_MARGIN := 41.0 / 250.0
## How far the picture shakes when the logo lands, in screen pixels, and how long the shake lasts.
const SHAKE := 12.0
const SHAKE_TIME := 0.4
## The story, from the end of a run to its start and back: a gold legion in a sea of barbarians and the logo landing
## over it, then a handful of men, a level-up, a legion of a hundred, its archers, its armour going from
## iron to gold, a boss's blow stepped out of, the forest, the gorge and the cliff, a quick cut through all eight provinces, the gods' choice in the
## music's quiet bars, Jupiter's lightning on its return, a chieftain's fall, the fort's victory and the end card.
## A shot plays from `from` seconds into its recording, or `follows` the one before it on without a cut; `caption`
## is the line in large letters and `label` the province above it; `logo` lands the logo over the shot and `flash`
## opens it on a flash of white.
const TRAILER := [
	{"shot": "hook", "from": 1.0, "beats": 7},
	{"shot": "hook", "follows": true, "beats": 8, "logo": true},
	{"shot": "skirmish", "from": 1.5, "beats": 8, "caption": "START WITH A FEW MEN"},
	{"shot": "levelup", "from": 0.6, "beats": 8},
	{"shot": "march", "from": 1.0, "beats": 8, "caption": "GROW A LEGION OF 100"},
	{"shot": "archers", "from": 1.4, "beats": 4, "caption": "YOU MARCH. THEY FIGHT."},
	{"shot": "dodge", "from": 0.3, "beats": 4, "caption": "DODGE BOSS ATTACKS"},
	{"shot": "livery0", "from": 1.0, "beats": 2, "caption": "IRON"},
	{"shot": "livery1", "from": 2.161, "beats": 2, "caption": "BRONZE"},
	{"shot": "livery2", "from": 3.322, "beats": 4, "caption": "GOLD"},
	{"shot": "fell", "from": 1.5, "beats": 4, "caption": "FELL FORESTS"},
	{"shot": "bridge", "from": 0.3, "beats": 4, "caption": "BRIDGE GORGES"},
	{"shot": "ravine", "from": 0.2, "beats": 8, "caption": "SHOVE THEM OFF CLIFFS"},
	{"shot": "p_germania", "from": 1.0, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "GERMANIA"},
	{"shot": "p_gaul", "from": 1.0, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "GAUL"},
	{"shot": "p_britannia", "from": 1.0, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "BRITANNIA"},
	{"shot": "p_hispania", "from": 1.0, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "HISPANIA"},
	{"shot": "p_aegyptus", "from": 1.0, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "AEGYPTUS"},
	{"shot": "p_parthia", "from": 1.2, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "PARTHIA"},
	{"shot": "p_dacia", "from": 0.6, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "DACIA"},
	{"shot": "p_sarmatia", "from": 1.0, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "SARMATIA"},
	{"shot": "gods", "from": 0.9, "beats": 8},
	{"shot": "reveal", "from": 2.0, "beats": 8, "flash": true},
	{"shot": "chief", "from": 1.0, "beats": 8, "caption": "TOPPLE THEIR WARLORDS"},
	# The VICTORY lands 4.0 seconds into the fort's recording, on the fifth beat of the shot.
	{"shot": "fort", "from": 1.68, "beats": 8},
	{"end": "endcard", "from": 1.0, "beats": 14},
]

var _shots_dir := ""
var _frame := 0
## Each segment's first frame and the second of its recording it starts from.
var _starts: Array[int] = []
var _froms: Array[float] = []
var _total_frames := 0
var _picture: TextureRect
var _texture: ImageTexture
var _overlay: SubViewport
var _shade: ColorRect
var _white: ColorRect
var _band: TextureRect
var _caption: Label
var _label: Label
var _logo: TextureRect
var _scroll: TextureRect
var _wishlist: Label
var _badges: Array[TextureRect] = []
var _vignette: TextureRect
var _music: Array[AudioStreamPlayer] = []
var _piece := -1
var _sound: AudioStreamPlayer
var _current := -1
## The music piece just left, faded out over a few frames so the jump never clicks.
var _leaving: AudioStreamPlayer
var _leaving_frames := 0


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
	var beats := 0.0
	for seg in TRAILER:
		var start := _beat_frame(beats)
		_froms.append(_froms[-1] + float(start - _starts[-1]) / FPS if seg.get("follows", false) else float(seg.get("from", 0.0)))
		_starts.append(start)
		beats += float(seg["beats"])
	_total_frames = _beat_frame(beats)
	_build()
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.stream = load(MUSIC)
		p.volume_db = MUSIC_DB
		add_child(p)
		_music.append(p)
	_sound = AudioStreamPlayer.new()
	add_child(_sound)
	# A preview can start part way through, to look at one moment without rendering the whole trailer.
	_frame = int(from * FPS)
	_process(0.0)
	_frame -= 1


## The frame a beat of the trailer falls on; the first cut is the very first frame, before the music's first beat.
static func _beat_frame(beat: float) -> int:
	return 0 if beat <= 0.0 else int(round((FIRST_BEAT + beat * BEAT) * FPS))


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
	# A soft dark oval behind the logo, so the lettering reads over the field.
	var gradient := Gradient.new()
	gradient.set_color(0, Color(0.03, 0.02, 0.02, 0.65))
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
	_vignette.size = Vector2(1500, 900)
	add_child(_vignette)
	# Captions, the logo and the end card are drawn in the game's own pixels and scaled up, like the game.
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
	# A dark band fading out above and below keeps the caption readable over a crowd.
	var fade := Gradient.new()
	fade.offsets = PackedFloat32Array([0.0, 0.3, 0.7, 1.0])
	fade.colors = PackedColorArray([Color(0, 0, 0, 0), Color(0.04, 0.02, 0.02, 0.55), Color(0.04, 0.02, 0.02, 0.55), Color(0, 0, 0, 0)])
	var strip := GradientTexture2D.new()
	strip.gradient = fade
	strip.fill_from = Vector2(0, 0)
	strip.fill_to = Vector2(0, 1)
	strip.width = 4
	strip.height = 64
	_band = TextureRect.new()
	_band.texture = strip
	_band.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_band.stretch_mode = TextureRect.STRETCH_SCALE
	_band.size = Vector2(area.x, 76)
	_overlay.add_child(_band)
	# The text is the game's own pixel font in whole multiples of its size, so it stays as crisp as the game.
	_label = _text(LABEL_SIZE, CREAM, 4)
	_caption = _text(CAPTION_SIZE, GOLD, 6)
	_logo = TextureRect.new()
	_logo.texture = load("res://assets/logo.png")
	_logo.pivot_offset = _logo.texture.get_size() / 2.0
	_overlay.add_child(_logo)
	_scroll = TextureRect.new()
	_scroll.texture = _outside("scroll.png")
	_scroll.position = Vector2(roundf((area.x - _scroll.texture.get_width()) / 2.0), SCROLL_Y)
	_overlay.add_child(_scroll)
	_wishlist = Label.new()
	_wishlist.add_theme_font_override("font", Ui.font())
	_wishlist.add_theme_font_size_override("font_size", 16)
	_wishlist.add_theme_color_override("font_color", Color(0.29, 0.18, 0.14))
	_wishlist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_wishlist.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wishlist.position = _scroll.position + Vector2(0, SCROLL_TEXT_TOP)
	_wishlist.size = Vector2(_scroll.texture.get_width(), SCROLL_TEXT_HEIGHT)
	_wishlist.text = "Wishlist now on Steam"
	_overlay.add_child(_wishlist)
	_white = ColorRect.new()
	_white.color = Color(1, 1, 1, 0)
	_white.size = area
	_overlay.add_child(_white)
	# The store badges are drawn at the frame's own resolution, as the stores supply them, side by side under the scroll.
	var apple := _badge("badge_app_store.png", BADGE_HEIGHT)
	var google := _badge("badge_google_play.png", BADGE_HEIGHT / (1.0 - 2.0 * GOOGLE_MARGIN))
	var margin := google.size.y * GOOGLE_MARGIN
	var google_seen := google.size.x - 2.0 * margin
	var left := roundf((SIZE.x - apple.size.x - BADGE_GAP - google_seen) / 2.0)
	apple.position = Vector2(left, BADGE_Y)
	google.position = Vector2(left + apple.size.x + BADGE_GAP - margin, BADGE_Y - margin)


func _text(size: int, colour: Color, outline: int) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", Ui.font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(INK, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(_overlay.size.x, size * 2)
	_overlay.add_child(l)
	return l


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


func _segment_index(frame: int) -> int:
	var k := _starts.size() - 1
	while k > 0 and _starts[k] > frame:
		k -= 1
	return k


func _process(_delta: float) -> void:
	if _frame >= _total_frames:
		get_tree().quit()
		return
	var k := _segment_index(_frame)
	var seg: Dictionary = TRAILER[k]
	var now := float(_frame) / FPS
	var local := float(_frame - _starts[k]) / FPS
	var end_frame := _starts[k + 1] if k + 1 < _starts.size() else _total_frames
	var length := float(end_frame - _starts[k]) / FPS
	if k != _current:
		var resumed := _current == -1
		_current = k
		_start_segment(k, local, resumed)
	_play_music(now)
	_play_stings()
	_draw_segment(k, seg, now, local, length)
	# The music rings out over the end card's last second and a half.
	var fade := linear_to_db(clampf(float(_total_frames - _frame) / FPS / 1.5, 0.0001, 1.0))
	_music[_piece % 2].volume_db = MUSIC_DB + fade
	if _leaving != null:
		_leaving_frames -= 1
		_leaving.volume_db = MUSIC_DB + linear_to_db(maxf(_leaving_frames / 3.0, 0.0001))
		if _leaving_frames <= 0:
			_leaving.stop()
			_leaving = null
	_frame += 1


## Starts the music piece the moment falls in, from the matching point of the track, and lets the one before it go.
func _play_music(now: float) -> void:
	var k := MUSIC_CUTS.size() - 1
	while k > 0 and float(_beat_frame(MUSIC_CUTS[k][0])) / FPS > now:
		k -= 1
	if k == _piece:
		return
	if _piece >= 0:
		_leaving = _music[_piece % 2]
		_leaving_frames = 3
	_piece = k
	var track_beat := int(MUSIC_CUTS[k][1])
	var track_from := 0.0 if track_beat == 0 else FIRST_BEAT + track_beat * BEAT
	_music[k % 2].play(track_from + now - float(_beat_frame(MUSIC_CUTS[k][0])) / FPS)


func _play_stings() -> void:
	for s in STINGS:
		if _beat_frame(float(s[0])) == _frame:
			var p := AudioStreamPlayer.new()
			p.stream = load("res://assets/audio/sfx/%s.ogg" % s[1])
			p.volume_db = float(s[2])
			add_child(p)
			p.play()
			p.finished.connect(p.queue_free)


## Plays the shot's own sound from the point of the recording the segment opens on, unless the segment carries on the one before.
func _start_segment(k: int, local: float, resumed: bool) -> void:
	var seg: Dictionary = TRAILER[k]
	if seg.get("follows", false) and not resumed:
		return
	_sound.stop()
	var name := String(seg.get("shot", seg.get("end", "")))
	var wav := _shots_dir.path_join(name).path_join("f.wav")
	if FileAccess.file_exists(wav):
		_sound.stream = AudioStreamWAV.load_from_file(wav)
		_sound.play(_froms[k] + local)


func _draw_segment(k: int, seg: Dictionary, now: float, local: float, length: float) -> void:
	var is_end := seg.has("end")
	var name := String(seg.get("shot", seg.get("end", "")))
	var index := int(round((_froms[k] + local) * FPS))
	var path := _shots_dir.path_join(name).path_join("f%08d.png" % index)
	if FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		img.convert(Image.FORMAT_RGB8)
		_texture.update(img)
	var logo := bool(seg.get("logo", false)) or is_end
	var since := local
	# The logo lands with a flash and a jolt of the picture.
	var shake := 0.0
	if logo and since < SHAKE_TIME and not is_end:
		shake = SHAKE * (1.0 - since / SHAKE_TIME)
	_picture.position = Vector2(roundf(sin(since * 61.0) * shake), roundf(cos(since * 47.0) * shake))
	var white := 0.0
	if (logo or seg.get("flash", false)) and since < 0.3:
		white = 0.75 * (1.0 - since / 0.3)
	_white.color.a = white
	_shade.visible = logo
	_shade.color.a = clampf(since / 0.2, 0.0, 1.0) * (0.35 if is_end else 0.45)
	_vignette.visible = logo
	_vignette.modulate.a = clampf(since / 0.2, 0.0, 1.0)
	_logo.visible = logo
	if logo:
		var y := END_LOGO_Y if is_end else LOGO_Y
		_logo.position = Vector2(roundf((_overlay.size.x - _logo.texture.get_width()) / 2.0), y)
		_vignette.position = Vector2(SIZE.x / 2.0 - _vignette.size.x / 2.0, (y + _logo.texture.get_height() / 2.0) * PIXEL - _vignette.size.y / 2.0)
		var s := lerpf(POP_SCALE, 1.0, _ease(since / POP))
		_logo.scale = Vector2(s, s)
	_scroll.visible = is_end
	_wishlist.visible = is_end
	for b in _badges:
		b.visible = is_end
	if is_end:
		var scroll := clampf((local - 1.2) / 0.4, 0.0, 1.0)
		_scroll.modulate.a = scroll
		_wishlist.modulate.a = scroll
		for b in _badges:
			b.modulate.a = clampf((local - 1.8) / 0.4, 0.0, 1.0)
	_draw_caption(k, seg, now)
	# The shot's own sound fades in and out quickly at its cuts, so cuts never click.
	var next_follows: bool = k + 1 < TRAILER.size() and TRAILER[k + 1].get("follows", false)
	var fade_in := 1.0 if seg.get("follows", false) else clampf(local / 0.05, 0.0, 1.0)
	var fade_out := 1.0 if next_follows else clampf((length - local) / 0.05, 0.0, 1.0)
	_sound.volume_db = SOUND_DB + linear_to_db(maxf(minf(fade_in, fade_out), 0.0001))


## The caption lands larger and settles to its size; a caption kept across cuts lands once, with the first of them.
func _draw_caption(k: int, seg: Dictionary, now: float) -> void:
	var text := String(seg.get("caption", ""))
	var shown := text != ""
	_caption.visible = shown
	_band.visible = shown
	_label.visible = shown and seg.has("label")
	if not shown:
		return
	var first := k
	while first > 0 and String(TRAILER[first - 1].get("caption", "")) == text:
		first -= 1
	var age := now - float(_starts[first]) / FPS
	_caption.text = text
	_pop(_caption, age, CAPTION_Y)
	_band.position = Vector2(0, CAPTION_Y - _band.size.y / 2.0 - (8.0 if seg.has("label") else 0.0))
	_band.modulate.a = clampf(age / 0.1, 0.0, 1.0)
	if seg.has("label"):
		_label.text = String(seg["label"])
		_pop(_label, now - float(_starts[k]) / FPS, LABEL_Y)


## Lands a line of text larger and brighter than it settles to, centred on the height `y`.
func _pop(l: Label, age: float, y: float) -> void:
	var s := lerpf(POP_SCALE, 1.0, _ease(age / POP))
	l.pivot_offset = l.size / 2.0
	l.scale = Vector2(s, s)
	l.position = Vector2(0, y - l.size.y / 2.0)
	l.modulate = Color(1.6, 1.6, 1.6) if age < 0.07 else Color.WHITE


## Eases out with a small overshoot, so a landing word or logo settles with a bounce.
static func _ease(t: float) -> float:
	t = clampf(t, 0.0, 1.0)
	var c := 1.70158
	return 1.0 + (c + 1.0) * pow(t - 1.0, 3.0) + c * pow(t - 1.0, 2.0)
