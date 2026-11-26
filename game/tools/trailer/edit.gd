extends Node
## The edits of the trailer and the Google Play video, cut from the recorded shots on the beat of the war theme.

const FPS := 30.0
## One beat of the war theme, at 103.36 beats a minute, and where its first beat falls in the track, in seconds.
const BEAT := 0.5805
const FIRST_BEAT := 0.0697
const MUSIC := "res://assets/audio/music/battle_war_theme.ogg"
## From the trailer's beat on the left the music plays from the track's beat on the right: the track's opening, then the
## quiet bars before its big return, the return itself as Jupiter's lightning strikes, and the track's own last bars.
const MUSIC_CUTS := [[0, 0], [63, 275], [67, 279], [87, 471]]
const MUSIC_DB := -1.0
## The fighting recorded with each shot plays under the music.
const SOUND_DB := -7.0
## Sounds laid over the edit, as [trailer beat, sound, decibels]: the logo's landing, the drop into the quiet bars and
## the end card's horn.
const STINGS := [[7, "boom_1", 0.0], [63, "boom_2", -8.0], [87, "horn_1", -5.0]]
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
## The story, a minute long: a gold legion in a sea of barbarians and the logo landing over it, then a handful of
## men, a level-up, a legion of a hundred, its archers, a boss's blow stepped out of, its armour going from iron to
## gold, the forest and the cliff, a quick cut through all eight provinces, the gods' choice in the music's quiet bars,
## Jupiter's lightning on its return, a chieftain's fall, the fort's victory and the end card.
## A shot plays from `from` seconds into its recording, or `follows` the one before it on without a cut; `caption`
## is the line in large letters and `label` the province above it; `logo` lands the logo over the shot and `flash`
## opens it on a flash of white.
const TRAILER := [
	# By three seconds into the recording the horde has begun to close in from every side.
	{"shot": "hook", "from": 3.0, "beats": 7},
	{"shot": "hook", "follows": true, "beats": 4, "logo": true},
	{"shot": "skirmish", "from": 1.5, "beats": 4, "caption": "START WITH A FEW MEN"},
	{"shot": "levelup", "from": 0.85, "beats": 4},
	{"shot": "march", "from": 1.0, "beats": 4, "caption": "GROW A LEGION OF 100"},
	{"shot": "archers", "from": 1.4, "beats": 4, "caption": "YOU MARCH. THEY FIGHT."},
	{"shot": "dodge", "from": 0.3, "beats": 4, "caption": "DODGE BOSS ATTACKS"},
	{"shot": "livery0", "from": 1.0, "beats": 2, "caption": "IRON"},
	{"shot": "livery1", "from": 2.161, "beats": 2, "caption": "BRONZE"},
	{"shot": "livery2", "from": 3.322, "beats": 4, "caption": "GOLD"},
	{"shot": "fell", "from": 1.5, "beats": 4, "caption": "FELL FORESTS"},
	{"shot": "ravine", "from": 0.2, "beats": 4, "caption": "SHOVE THEM OFF CLIFFS"},
	{"shot": "p_germania", "from": 1.0, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "GERMANIA"},
	{"shot": "p_gaul", "from": 1.0, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "GAUL"},
	{"shot": "p_britannia", "from": 1.0, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "BRITANNIA"},
	{"shot": "p_hispania", "from": 1.0, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "HISPANIA"},
	{"shot": "p_aegyptus", "from": 1.0, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "AEGYPTUS"},
	{"shot": "p_parthia", "from": 1.2, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "PARTHIA"},
	{"shot": "p_dacia", "from": 0.6, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "DACIA"},
	{"shot": "p_sarmatia", "from": 1.0, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "SARMATIA"},
	{"shot": "gods", "from": 0.9, "beats": 4},
	{"shot": "reveal", "from": 2.0, "beats": 6, "flash": true},
	{"shot": "chief", "from": 0.6, "beats": 6, "caption": "TOPPLE THEIR WARLORDS"},
	# The VICTORY lands on the cut and the victory screen comes up 6.2 seconds into the recording, on the shot's fifth beat.
	{"shot": "fort", "from": 3.878, "beats": 8},
	{"end": "endcard", "from": 1.0, "beats": 14},
]
## The Google Play video, with the phone's touch controls; the gods are called with taps in the music's quiet bar.
const PLAY_STORE := [
	{"shot": "hook", "from": 3.0, "beats": 7},
	{"shot": "hook", "follows": true, "beats": 4, "logo": true},
	{"shot": "skirmish", "from": 1.5, "beats": 4, "caption": "START WITH A FEW MEN"},
	{"shot": "march", "from": 1.0, "beats": 4, "caption": "GROW A LEGION OF 100"},
	{"shot": "archers", "from": 1.4, "beats": 4, "caption": "YOU MARCH. THEY FIGHT."},
	{"shot": "dodge", "from": 0.3, "beats": 4, "caption": "DODGE BOSS ATTACKS"},
	{"shot": "ravine", "from": 0.2, "beats": 4, "caption": "SHOVE THEM OFF CLIFFS"},
	{"shot": "p_gaul", "from": 1.0, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "GAUL"},
	{"shot": "p_aegyptus", "from": 1.0, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "AEGYPTUS"},
	{"shot": "p_parthia", "from": 1.2, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "PARTHIA"},
	{"shot": "p_dacia", "from": 0.6, "beats": 2, "caption": "CONQUER 8 PROVINCES", "label": "DACIA"},
	{"shot": "gods", "from": 0.6, "beats": 4},
	{"shot": "reveal", "from": 2.0, "beats": 6, "flash": true},
	{"shot": "chief", "from": 0.6, "beats": 6, "caption": "TOPPLE THEIR WARLORDS"},
	{"end": "endcard", "from": 1.0, "beats": 14},
]
## The shorts, each in a tall frame. A quiz asks its question over the track's opening, waits in the quiet bar before the
## track's big return and answers on the return. A caption's {stat} is read from the shot's stats.jsonl at the frame shown,
## {stat@S} at second S of the recording and {stat@} at the segment's first frame, plus or minus a number after it;
## `count` counts its numbers up as it lands, `choices` are revealed one at a time and `answer` lights the right one.
const QUIZ_MUSIC := [[0, 0], [16, 275], [20, 279], [28, 475]]
const QUIZ_STINGS := [[20, "boom_1", -3.0], [28, "horn_1", -5.0]]
const HOW_MANY := [
	{"shot": "how_many", "from": 1.0, "beats": 8, "caption": "GUESS HOW MANY\nBARBARIANS"},
	{"shot": "how_many", "follows": true, "beats": 8, "caption": "GUESS HOW MANY\nBARBARIANS", "sub": "VS {men@+1} ROMANS"},
	{"shot": "how_many", "follows": true, "beats": 4, "caption": "ANY GUESSES?"},
	{"shot": "how_many", "follows": true, "beats": 8, "caption": "{seen@}", "size": 48, "count": true, "sub": "BARBARIANS"},
	{"end": "endcard", "from": 1.0, "beats": 10},
]
const JUPITER := [
	{"shot": "storm", "from": 1.0, "beats": 6, "caption": "SURROUNDED"},
	{"shot": "storm", "follows": true, "beats": 10, "caption": "WHAT DO YOU DO?", "choices": ["RUN", "RAISE SHIELDS", "PRAY"]},
	{"shot": "storm", "follows": true, "beats": 4, "caption": "WHAT DO YOU DO?", "choices": ["RUN", "RAISE SHIELDS", "PRAY"]},
	{"shot": "storm", "follows": true, "beats": 8, "caption": "PRAY TO JUPITER", "choices": ["RUN", "RAISE SHIELDS", "PRAY"], "answer": 2,
		"counter": "{seen} LEFT ON SCREEN"},
	{"end": "endcard", "from": 1.0, "beats": 10},
]
const CLIFF := [
	{"shot": "whirl", "from": 0.2, "beats": 4, "caption": "HOW DO YOU BEAT\nA BERSERKER?"},
	{"shot": "cliff", "from": 3.4, "beats": 12, "caption": "HOW DO YOU BEAT\nA BERSERKER?", "choices": ["ARROWS", "SWORDS", "A CLIFF"]},
	{"shot": "cliff", "follows": true, "beats": 4, "caption": "HOW DO YOU BEAT\nA BERSERKER?", "choices": ["ARROWS", "SWORDS", "A CLIFF"]},
	{"shot": "cliff", "follows": true, "beats": 8, "caption": "PUSH HIM\nOFF A CLIFF", "choices": ["ARROWS", "SWORDS", "A CLIFF"], "answer": 2},
	{"end": "endcard", "from": 1.0, "beats": 10},
]
const VOLLEY := [
	{"shot": "volley", "from": 0.3, "beats": 6, "caption": "{seen@} BARBARIANS\nCHARGE {men@}\nARCHERS"},
	{"shot": "volley", "follows": true, "beats": 8, "caption": "HOW MANY\nREACH THEM?", "choices": ["ALL OF THEM", "HALF", "NONE"]},
	{"shot": "volley", "follows": true, "beats": 4, "caption": "HOW MANY\nREACH THEM?", "choices": ["ALL OF THEM", "HALF", "NONE"]},
	{"shot": "volley", "follows": true, "beats": 8, "caption": "{reached@}", "size": 48, "choices": ["ALL OF THEM", "HALF", "NONE"], "answer": 2,
		"sub": "ALL {kills@} SHOT DOWN"},
	{"end": "endcard", "from": 1.0, "beats": 10},
]
const TESTUDO := [
	{"shot": "trample", "from": 0.2, "beats": 10, "caption": "WAR ELEPHANT\nVS ROMAN LEGION"},
	{"shot": "trample_testudo", "from": 0.13, "beats": 3, "caption": "RAISE THE\nTESTUDO!"},
	{"shot": "trample_testudo", "follows": true, "beats": 8, "caption": "STOPPED DEAD", "flash": true},
	{"end": "endcard", "from": 1.0, "beats": 10},
]
const FIRST_LAST := [
	{"shot": "first", "from": 0.5, "beats": 8, "label": "GERMANIA", "caption": "MY FIRST\nPROVINCE", "counter": "{men} MEN"},
	{"shot": "last", "from": 1.0, "beats": 14, "label": "SARMATIA", "caption": "MY LAST\nPROVINCE", "counter": "{men} MEN"},
	{"end": "endcard", "from": 1.0, "beats": 10},
]
const CLOSE_CALL := [
	{"shot": "close", "from": 1.0, "beats": 6, "caption": "{men@} MEN\nSURROUNDED", "counter": "{men} LEFT"},
	# Apollo is called 14.9 seconds into the recording, on the track's return.
	{"shot": "close", "from": 9.1, "beats": 6, "caption": "THEY'RE FALLING", "counter": "{men} LEFT"},
	{"shot": "close", "follows": true, "beats": 4, "caption": "ALMOST GONE", "counter": "{men} LEFT"},
	{"shot": "close", "follows": true, "beats": 8, "caption": "CALL APOLLO!", "sub": "THE FALLEN\nRISE AGAIN", "counter": "BACK TO {men} MEN"},
	{"end": "endcard", "from": 1.0, "beats": 10},
]
## Each cut's edit, the music's stretches and the sounds laid over it, the end card's line and whether the badges show;
## the shorts' badges are drawn when make_trailer.py passes --badges.
const CUTS := {
	"trailer": {"edit": TRAILER, "music": MUSIC_CUTS, "stings": STINGS, "line": "Wishlist now on Steam", "badges": true},
	"play_store": {"edit": PLAY_STORE, "music": [[0, 0], [39, 275], [43, 279], [55, 471]],
		"stings": [[7, "boom_1", 0.0], [39, "boom_2", -8.0], [55, "horn_1", -5.0]], "line": "Lead a Roman legion", "badges": false},
	"how_many": {"edit": HOW_MANY, "music": QUIZ_MUSIC, "stings": QUIZ_STINGS, "line": "Wishlist now on Steam", "badges": false, "tall": true},
	"jupiter": {"edit": JUPITER, "music": QUIZ_MUSIC, "stings": QUIZ_STINGS, "line": "Wishlist now on Steam", "badges": false, "tall": true},
	"cliff": {"edit": CLIFF, "music": QUIZ_MUSIC, "stings": QUIZ_STINGS, "line": "Wishlist now on Steam", "badges": false, "tall": true},
	"archers": {"edit": VOLLEY, "music": [[0, 0], [14, 275], [18, 279], [26, 475]], "stings": [[18, "boom_1", -3.0], [26, "horn_1", -5.0]],
		"line": "Wishlist now on Steam", "badges": false, "tall": true},
	"testudo": {"edit": TESTUDO, "music": [[0, 0], [10, 276], [13, 279], [21, 475]], "stings": [[13, "boom_1", -3.0], [21, "horn_1", -5.0]],
		"line": "Wishlist now on Steam", "badges": false, "tall": true},
	"first_vs_last": {"edit": FIRST_LAST, "music": [[0, 0], [8, 279], [22, 475]], "stings": [[8, "boom_1", -3.0], [22, "horn_1", -5.0]],
		"line": "Wishlist now on Steam", "badges": false, "tall": true},
	"close_call": {"edit": CLOSE_CALL, "music": [[0, 0], [12, 275], [16, 279], [24, 475]], "stings": [[16, "boom_1", -3.0], [24, "horn_1", -5.0]],
		"line": "Wishlist now on Steam", "badges": false, "tall": true},
}
## The shorts' frame and layout, in the game pixels of their 360 by 640 view: the top of the text, below the bar a phone's
## video app lays over a video, the gap between its lines, and the end card's logo, scroll and store badges.
const TALL := Vector2(1080, 1920)
const STACK_TOP := 64.0
const STACK_GAP := 6.0
const SUB_SIZE := 24
## A choice appears this many seconds after the question, then one more every CHOICE_EVERY seconds.
const CHOICE_FIRST := 0.6
const CHOICE_EVERY := 1.161
## A caption's numbers count up from nothing over this many seconds as it lands.
const COUNT_TIME := 0.6
const TALL_LOGO_Y := 100.0
const TALL_SCROLL_Y := 215.0
const TALL_BADGE_Y := 900.0
const TALL_BADGE_HEIGHT := 110.0

var _shots_dir := ""
var _cut: Dictionary = CUTS["trailer"]
var _edit: Array = TRAILER
var _size := SIZE
var _tall := false
var _badges_on := true
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
var _line: Label
var _badges: Array[TextureRect] = []
var _sub: Label
var _counter: Label
var _choices: Array[Label] = []
## Each shot's stats.jsonl, a dictionary per recorded frame, read once.
var _stats := {}
var _token := RegEx.create_from_string("\\{(\\w+)(@[\\d.]*)?([+-]\\d+)?\\}")
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
		if AudioServer.get_bus_index(bus) >= 0:
			AudioServer.set_bus_mute(AudioServer.get_bus_index(bus), true)
	var from := 0.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--shots="):
			_shots_dir = arg.trim_prefix("--shots=")
		elif arg.begins_with("--from="):
			from = float(arg.trim_prefix("--from="))
		elif arg.begins_with("--cut="):
			_cut = CUTS[arg.trim_prefix("--cut=")]
	_edit = _cut["edit"]
	_tall = _cut.get("tall", false)
	_size = TALL if _tall else SIZE
	_badges_on = _cut["badges"] or "--badges" in OS.get_cmdline_user_args()
	var beats := 0.0
	for seg in _edit:
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
	# The shots are recorded at the game's own 640 by 360, or 360 by 640 for the shorts, and shown three times larger in
	# whole pixels, as the game is.
	_texture = ImageTexture.create_from_image(Image.create(int(_size.x) / PIXEL, int(_size.y) / PIXEL, false, Image.FORMAT_RGB8))
	_picture = TextureRect.new()
	_picture.texture = _texture
	_picture.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_picture.stretch_mode = TextureRect.STRETCH_SCALE
	_picture.size = _size
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
	_vignette.size = Vector2(1100, 660) if _tall else Vector2(1500, 900)
	add_child(_vignette)
	# Captions, the logo and the end card are drawn in the game's own pixels and scaled up, like the game.
	var area := _size / float(PIXEL)
	_overlay = SubViewport.new()
	_overlay.size = Vector2i(area)
	_overlay.transparent_bg = true
	_overlay.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_overlay.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	add_child(_overlay)
	var shown := TextureRect.new()
	shown.texture = _overlay.get_texture()
	shown.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	shown.size = _size
	shown.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(shown)
	_shade = ColorRect.new()
	_shade.color = Color(0.05, 0.04, 0.03, 0.0)
	_shade.size = area
	_overlay.add_child(_shade)
	# A dark band fading out above and below keeps the caption readable over a crowd.
	var fade := Gradient.new()
	# A short's band holds several lines, so it darkens more of its height.
	fade.offsets = PackedFloat32Array([0.0, 0.18, 0.82, 1.0] if _tall else [0.0, 0.3, 0.7, 1.0])
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
	_sub = _text(SUB_SIZE, CREAM, 6)
	if _tall:
		_label.add_theme_constant_override("outline_size", 6)
	_counter = _text(CAPTION_SIZE, CREAM, 6)
	for k in 3:
		_choices.append(_text(CAPTION_SIZE, CREAM, 6))
	_logo = TextureRect.new()
	_logo.texture = load("res://assets/logo.png")
	_logo.pivot_offset = _logo.texture.get_size() / 2.0
	_overlay.add_child(_logo)
	_scroll = TextureRect.new()
	_scroll.texture = _outside("scroll.png")
	_scroll.position = Vector2(roundf((area.x - _scroll.texture.get_width()) / 2.0), TALL_SCROLL_Y if _tall else SCROLL_Y)
	_overlay.add_child(_scroll)
	_line = Label.new()
	_line.add_theme_font_override("font", Ui.font())
	_line.add_theme_font_size_override("font_size", 16)
	_line.add_theme_color_override("font_color", Color(0.29, 0.18, 0.14))
	_line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_line.position = _scroll.position + Vector2(0, SCROLL_TEXT_TOP)
	_line.size = Vector2(_scroll.texture.get_width(), SCROLL_TEXT_HEIGHT)
	_line.text = String(_cut["line"])
	_overlay.add_child(_line)
	_white = ColorRect.new()
	_white.color = Color(1, 1, 1, 0)
	_white.size = area
	_overlay.add_child(_white)
	# The store badges are drawn at the frame's own resolution, as the stores supply them, side by side under the scroll.
	var height := TALL_BADGE_HEIGHT if _tall else BADGE_HEIGHT
	var top := TALL_BADGE_Y if _tall else BADGE_Y
	var apple := _badge("badge_app_store.png", height)
	var google := _badge("badge_google_play.png", height / (1.0 - 2.0 * GOOGLE_MARGIN))
	var margin := google.size.y * GOOGLE_MARGIN
	var google_seen := google.size.x - 2.0 * margin
	var left := roundf((_size.x - apple.size.x - BADGE_GAP - google_seen) / 2.0)
	apple.position = Vector2(left, top)
	google.position = Vector2(left + apple.size.x + BADGE_GAP - margin, top - margin)


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
	var seg: Dictionary = _edit[k]
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
	var cuts: Array = _cut["music"]
	var k := cuts.size() - 1
	while k > 0 and float(_beat_frame(cuts[k][0])) / FPS > now:
		k -= 1
	if k == _piece:
		return
	if _piece >= 0:
		_leaving = _music[_piece % 2]
		_leaving_frames = 3
	_piece = k
	var track_beat := int(cuts[k][1])
	var track_from := 0.0 if track_beat == 0 else FIRST_BEAT + track_beat * BEAT
	_music[k % 2].play(track_from + now - float(_beat_frame(cuts[k][0])) / FPS)


func _play_stings() -> void:
	for s in _cut["stings"]:
		if _beat_frame(float(s[0])) == _frame:
			var p := AudioStreamPlayer.new()
			p.stream = load("res://assets/audio/sfx/%s.ogg" % s[1])
			p.volume_db = float(s[2])
			add_child(p)
			p.play()
			p.finished.connect(p.queue_free)


## Plays the shot's own sound from the point of the recording the segment opens on, unless the segment carries on the one before.
func _start_segment(k: int, local: float, resumed: bool) -> void:
	var seg: Dictionary = _edit[k]
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
		var y := (TALL_LOGO_Y if _tall else END_LOGO_Y) if is_end else LOGO_Y
		_logo.position = Vector2(roundf((_overlay.size.x - _logo.texture.get_width()) / 2.0), y)
		_vignette.position = Vector2(_size.x / 2.0 - _vignette.size.x / 2.0, (y + _logo.texture.get_height() / 2.0) * PIXEL - _vignette.size.y / 2.0)
		var s := lerpf(POP_SCALE, 1.0, _ease(since / POP))
		_logo.scale = Vector2(s, s)
	_scroll.visible = is_end
	_line.visible = is_end
	for b in _badges:
		b.visible = is_end and _badges_on
	if is_end:
		var scroll := clampf((local - 1.2) / 0.4, 0.0, 1.0)
		_scroll.modulate.a = scroll
		_line.modulate.a = scroll
		for b in _badges:
			b.modulate.a = clampf((local - 1.8) / 0.4, 0.0, 1.0)
	if _tall:
		_draw_stack(k, seg, now, local)
	else:
		_draw_caption(k, seg, now)
	# The shot's own sound fades in and out quickly at its cuts, so cuts never click.
	var next_follows: bool = k + 1 < _edit.size() and _edit[k + 1].get("follows", false)
	var fade_in := 1.0 if seg.get("follows", false) else clampf(local / 0.05, 0.0, 1.0)
	var fade_out := 1.0 if next_follows else clampf((length - local) / 0.05, 0.0, 1.0)
	_sound.volume_db = SOUND_DB + linear_to_db(maxf(minf(fade_in, fade_out), 0.0001))


## The caption lands larger and settles to its size; a caption kept across cuts lands once, with the first of them.
func _draw_caption(k: int, seg: Dictionary, now: float) -> void:
	_sub.visible = false
	_counter.visible = false
	for c in _choices:
		c.visible = false
	var text := String(seg.get("caption", ""))
	var shown := text != ""
	_caption.visible = shown
	_band.visible = shown
	_label.visible = shown and seg.has("label")
	if not shown:
		return
	var first := k
	while first > 0 and String(_edit[first - 1].get("caption", "")) == text:
		first -= 1
	var age := now - float(_starts[first]) / FPS
	_caption.text = text
	_pop(_caption, age, CAPTION_Y)
	_band.position = Vector2(0, CAPTION_Y - _band.size.y / 2.0 - (8.0 if seg.has("label") else 0.0))
	_band.modulate.a = clampf(age / 0.1, 0.0, 1.0)
	if seg.has("label"):
		_label.text = String(seg["label"])
		_pop(_label, now - float(_starts[k]) / FPS, LABEL_Y)


## A short's text, stacked down from the top of the frame over one dark band: the province, the caption, the line under
## it, the choices and the live count. Each lands once, with the first of the segments in a row that show it.
func _draw_stack(k: int, seg: Dictionary, now: float, local: float) -> void:
	var shot := String(seg.get("shot", seg.get("end", "")))
	var index := int(round((_froms[k] + local) * FPS))
	var first := int(round(_froms[k] * FPS))
	var y := STACK_TOP
	_label.visible = seg.has("label")
	if _label.visible:
		_label.text = String(seg["label"])
		y = _stack(_label, CAPTION_SIZE, _age(k, "label", now), y)
	_caption.visible = seg.has("caption")
	if _caption.visible:
		var age := _age(k, "caption", now)
		var grow := clampf(age / COUNT_TIME, 0.0, 1.0) if seg.get("count", false) else 1.0
		_caption.text = _fill(String(seg["caption"]), shot, index, first, grow)
		y = _stack(_caption, int(seg.get("size", CAPTION_SIZE)), age, y)
	_sub.visible = seg.has("sub")
	if _sub.visible:
		_sub.text = _fill(String(seg["sub"]), shot, index, first, 1.0)
		y = _stack(_sub, SUB_SIZE, _age(k, "sub", now), y)
	var choices: Array = seg.get("choices", [])
	var asked := float(_starts[_first_with(k, "choices")]) / FPS
	for j in _choices.size():
		var c := _choices[j]
		c.visible = j < choices.size()
		if not c.visible:
			continue
		c.text = "%s) %s" % ["ABC"[j], choices[j]]
		var shown := asked + CHOICE_FIRST + j * CHOICE_EVERY
		if seg.has("answer"):
			var right: bool = j == int(seg["answer"])
			c.add_theme_color_override("font_color", GOLD if right else CREAM)
			y = _stack(c, CAPTION_SIZE, now - float(_starts[k]) / FPS if right else 1.0, y, 1.0 if right else 0.35)
		else:
			c.add_theme_color_override("font_color", CREAM)
			c.visible = now >= shown
			y = _stack(c, CAPTION_SIZE, now - shown, y)
	_counter.visible = seg.has("counter")
	if _counter.visible:
		_counter.text = _fill(String(seg["counter"]), shot, index, first, 1.0)
		y = _stack(_counter, CAPTION_SIZE, _age(k, "counter", now), y)
	_band.visible = y > STACK_TOP
	_band.position = Vector2(0, STACK_TOP - 24.0)
	_band.size = Vector2(_overlay.size.x, y - STACK_TOP + 48.0)
	_band.modulate.a = clampf(_age(k, "caption", now) / 0.1, 0.0, 1.0) if seg.has("caption") else 1.0


## Lays a line of the stack at the height `y`, landing larger and brighter as it appears; returns the height below it.
func _stack(l: Label, size: int, age: float, y: float, alpha := 1.0) -> float:
	l.add_theme_font_size_override("font_size", size)
	l.size = Vector2(_overlay.size.x, 0.0)
	var h := l.get_minimum_size().y
	l.size = Vector2(_overlay.size.x, h)
	var s := lerpf(POP_SCALE, 1.0, _ease(age / POP))
	l.pivot_offset = l.size / 2.0
	l.scale = Vector2(s, s)
	l.position = Vector2(0, y)
	l.modulate = Color(1.6, 1.6, 1.6, alpha) if age < 0.07 else Color(1, 1, 1, alpha)
	return y + h + STACK_GAP


## Seconds since the first of the segments in a row up to k that show the same `key`.
func _age(k: int, key: String, now: float) -> float:
	return now - float(_starts[_first_with(k, key)]) / FPS


func _first_with(k: int, key: String) -> int:
	var first := k
	while first > 0 and _edit[first - 1].get(key) == _edit[k].get(key):
		first -= 1
	return first


## The text with each {stat} filled in from the shot's stats: at the frame shown, at second S with @S or at the segment's
## first frame with a bare @, plus or minus a number after it. `grow` below 1 counts the numbers up from nothing.
func _fill(text: String, shot: String, index: int, first: int, grow: float) -> String:
	var out := text
	for m in _token.search_all(text):
		var at := index
		var when := m.get_string(2)
		if when == "@":
			at = first
		elif when != "":
			at = int(round(float(when.substr(1)) * FPS))
		var v := _stat(shot, at, m.get_string(1)) + float(m.get_string(3).to_int())
		out = out.replace(m.get_string(0), str(int(round(v * grow))))
	return out


## A number from the stats a shot's recording wrote beside its frames, one line per frame.
func _stat(shot: String, index: int, key: String) -> float:
	if not _stats.has(shot):
		var rows: Array = []
		var f := FileAccess.open(_shots_dir.path_join(shot).path_join("stats.jsonl"), FileAccess.READ)
		while f != null and not f.eof_reached():
			var line := f.get_line()
			if line != "":
				rows.append(JSON.parse_string(line))
		_stats[shot] = rows
	var rows: Array = _stats[shot]
	if rows.is_empty():
		return 0.0
	return float(rows[clampi(index, 0, rows.size() - 1)].get(key, 0))


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
