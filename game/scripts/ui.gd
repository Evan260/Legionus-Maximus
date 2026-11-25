class_name Ui
extends RefCounted
## Shared drawing and focus for the camp screens: parchment panels, buttons, wrapped text, and a focus cursor that
## keyboard, pad and mouse all move. A screen draws its buttons every frame; the buttons of the last finished frame are the ones focus moves between.

const W := 640.0
const H := 360.0
## Marks that Chinese and Japanese never put at the start of a line.
const NO_LINE_START := "。、，．！？）」』：；・…ー.,!?):;"
## Letters that stand for a line of words when a label is set in the middle of a box: capitals and figures, and in Chinese, Japanese and Korean one of their characters, which reach a little below the line.
const BODY := "H0"
const HAN_BODY := {"ja": "H0国", "zh_CN": "H0国", "zh_TW": "H0國", "ko": "H0가"}
const INK := Color(0.16, 0.1, 0.08)
const CREAM := Color(1.0, 0.95, 0.82)
const PARCH := Color(0.96, 0.9, 0.76)
const PARCH_DARK := Color(0.82, 0.7, 0.52)
const GOLD := Color(0.91, 0.69, 0.25)
const GOLD_LIGHT := Color(1.0, 0.89, 0.59)
const RED := Color(0.72, 0.18, 0.14)
const BROWN := Color(0.5, 0.36, 0.22)
const MUTED := Color(0.55, 0.45, 0.34)

# The text size setting: 1 draws at 8 px, 2 at 16 px (the sizes are in balance.json).
static var scale := 1
static var px := 8
# A language whose text is drawn in its own font, for the picker that names every language in its own letters.
static var _own: Font
static var _own_loc := ""
static var _balance_px := 8
# The rows each letter fills, by font and then by letter and size, read once from the font's own picture of it.
static var _ink := {}
# The window shows at least 640 by 360 and more on whichever side it is longer; menus stay in a centred 640 by 360 box.
static var view := Vector2(W, H)
static var offset := Vector2.ZERO

var items: Array = []
var focus := ""
## Whether the focus was last moved by the pointer resting over a button, rather than by keys or a gamepad.
var pointer_focus := false
## Where a key moves focus from a button when the screen sets it, in place of the nearest button that way.
var links := {}
var _next: Array = []
var _after: Array = []
var _next_links := {}
var _icons := {}


## The text size setting in the language's own font: its base size times the scale, so 10 px fonts draw at 10 and 20.
static func set_text_size(size: int, balance: Dictionary) -> void:
	scale = clampi(size, 1, 2)
	_balance_px = int(balance.text_px[scale - 1])
	px = _px_for(Lang.code)


## The 10 px Latin font is drawn at 10 and, for large text, at 16 like the 8 px fonts' double, so one layout fits every language.
static func _px_for(loc: String) -> int:
	return _balance_px if Lang.base_px(loc) == 8 or scale > 1 else 10


## The font of the language showing, or of the one chosen by `draw_in`.
static func font() -> Font:
	return _own if _own != null else Lang.font()


## Draws the text that follows in a language's own font and size until `draw_in("")` puts the showing language back.
static func draw_in(loc: String) -> void:
	_own = Lang.font(loc) if loc != "" else null
	_own_loc = loc
	px = _px_for(loc if loc != "" else Lang.code)


## The distance between two lines of text of a size: a quarter more than the size, so 8 gives 10, 10 gives 12 and 16 gives 20.
static func lead_for(size: int) -> float:
	return float(size * 5 / 4)


static func leading() -> float:
	return lead_for(px)


## The smallest size the language's font is drawn at, which a label steps down to when it does not fit at the text size.
static func small_px() -> int:
	return mini(px, Lang.base_px(Lang.code))


static func width_at(s: String, size: int) -> float:
	return font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x


## The rows a text's letters fill when the font draws them at a size (the text size when 0), measured down from the baseline.
static func ink_rows(s: String, size := 0) -> Vector2:
	var sz := size if size > 0 else px
	var f := font()
	var known: Dictionary = _ink.get_or_add(f, {})
	var out := Vector2(INF, -INF)
	for i in s.length():
		var code := s.unicode_at(i)
		var key := code * 1024 + sz
		if not known.has(key):
			known[key] = _glyph_rows(f, code, sz)
		var rows: Vector2 = known[key]
		out = Vector2(minf(out.x, rows.x), maxf(out.y, rows.y))
	return out


# The rows a letter's pixels fill in the font's own picture of it, taken from the first of the font and its fallbacks that has it.
static func _glyph_rows(f: Font, code: int, size: int) -> Vector2:
	var ts := TextServerManager.get_primary_interface()
	for rid in f.get_rids():
		if not ts.font_has_char(rid, code):
			continue
		var at := Vector2i(size, 0)
		var glyph := ts.font_get_glyph_index(rid, size, code, 0)
		ts.font_render_glyph(rid, at, glyph)
		var page := ts.font_get_glyph_texture_idx(rid, at, glyph)
		var out := Vector2(INF, -INF)
		if page < 0:
			return out
		var img := ts.font_get_texture_image(rid, at, page)
		var uv := ts.font_get_glyph_uv_rect(rid, at, glyph)
		var top := ts.font_get_glyph_offset(rid, at, glyph).y
		# Without the picture, the glyph's box less the one pixel of margin round it is the nearest guess.
		if img == null or img.is_empty():
			return Vector2(top + 1.0, top + uv.size.y - 1.0)
		for y in int(uv.size.y):
			for x in int(uv.size.x):
				if img.get_pixel(int(uv.position.x) + x, int(uv.position.y) + y).a > 0.5:
					out = Vector2(minf(out.x, top + y), maxf(out.y, top + y + 1.0))
		return out
	return Vector2(INF, -INF)


## The rows a label's letters stand in, measured down from the baseline, as it is set in a box: its own rows within those of the capitals, figures and characters.
static func letter_rows(s: String, size := 0) -> Vector2:
	var own := ink_rows(s, size)
	# Only the rows of the capitals, figures and characters count, so an accent or a tail never moves a label off its neighbours' line.
	var body := ink_rows(HAN_BODY.get(_own_loc if _own != null else Lang.code, BODY), size)
	var rows := Vector2(maxf(own.x, body.x), minf(own.y, body.y))
	return rows if rows.x < rows.y else body


## The baseline that sets a label's letters in the middle of `height` rows from `top`, any odd row going under them, where their shading falls.
static func middle(top: float, height: float, s: String, size := 0) -> float:
	var rows := letter_rows(s, size)
	return top + floorf((height - (rows.y - rows.x)) / 2.0) - rows.x


## The size a label is drawn at to fit the width: the text size, or the smallest one when it does not fit.
static func fit_size(s: String, width: float) -> int:
	return px if width_at(s, px) <= width else small_px()


## One size for a whole list of [label, room] pairs: the text size when every label fits it, else the smallest, so a list never mixes sizes.
static func list_size(labels: Array) -> int:
	for pair in labels:
		if width_at(str(pair[0]), px) > float(pair[1]):
			return small_px()
	return px


## Text cut into lines no wider than the width at a size (the text size when 0), breaking at spaces, or between any two letters in languages written without them or in a word too long for a line.
static func lines_of(s: String, width: float, size := 0) -> Array:
	var sz := size if size > 0 else px
	var out: Array = []
	var line := ""
	var f := font()
	if Lang.is_han():
		for ch in s:
			# Closing punctuation never starts a line, so it stays on the line before even when that runs one glyph over.
			if line != "" and not ch in NO_LINE_START and f.get_string_size(line + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > width:
				var cut := _word_start(line, ch)
				out.append(line.left(cut))
				line = line.substr(cut)
			if not (line == "" and ch == " "):
				line += ch
	else:
		for w in s.split(" "):
			var trial: String = w if line == "" else line + " " + w
			if f.get_string_size(trial, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > width and line != "":
				out.append(line)
				line = w
			else:
				line = trial
			# A word wider than the whole line is broken between letters, with a hyphen at each break.
			while line.length() > 1 and f.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > width:
				var cut := line.length() - 1
				while cut > 1 and f.get_string_size(line.left(cut) + "-", HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > width:
					cut -= 1
				# At least three letters go down to the next line, so no line holds a lone letter.
				if line.length() >= 6:
					cut = mini(cut, line.length() - 3)
				out.append(line.left(cut) + "-")
				line = line.substr(cut)
	if line != "":
		out.append(line)
	return out


## Whether Japanese may break a line between two characters: not inside a run of kanji, which is usually one word.
static func can_break(before: String, after: String) -> bool:
	return Lang.code != "ja" or not (_kanji(before) and _kanji(after))


static func _kanji(ch: String) -> bool:
	var c := ch.unicode_at(0) if ch != "" else 0
	return (c >= 0x4E00 and c <= 0x9FFF) or (c >= 0x3400 and c <= 0x4DBF) or c == 0x3005


## Where a full `line` is cut so `next` can start the next line: at its end, or in Japanese before the run of kanji that `next` would split, when the line has more before it.
static func _word_start(line: String, next: String) -> int:
	if can_break(line.right(1), next):
		return line.length()
	var i := line.length() - 1
	while i > 0 and not can_break(line[i - 1], line[i]):
		i -= 1
	return i if i > 0 else line.length()


## How a paragraph is laid out in at most `max_lines` lines: the size it is drawn at (the smallest when the text size
## needs more lines) and the lines it takes at that size.
static func block(s: String, width: float, max_lines: int) -> Dictionary:
	var size := px
	var lines := lines_of(s, width, size).size()
	if lines > max_lines and small_px() < px:
		size = small_px()
		lines = lines_of(s, width, size).size()
	return {"size": size, "lines": lines}


## The first row of a list of `visible` rows to show so the row at `index` is on screen, moving as little as it can.
static func scroll_for(index: int, count: int, visible: int, current: int) -> int:
	return clampi(clampi(current, index - visible + 1, index), 0, maxi(0, count - visible))


func begin() -> void:
	_next = []
	_after = []
	_next_links = {}


## Ends a frame; focus falls back to the first button when its own has gone.
func end() -> void:
	items = _next + _after
	links = _next_links
	if not items.is_empty() and not has_item(focus):
		focus = items[0].id


func has_item(id: String) -> bool:
	for it in items:
		if it.id == id:
			return true
	return false


func width_of(s: String) -> float:
	return font().get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


## The text cut with dots so it fits the width.
static func clip(s: String, width: float, size := 0) -> String:
	var sz := size if size > 0 else px
	if width_at(s, sz) <= width:
		return s
	while s.length() > 1 and width_at(s + "..", sz) > width:
		s = s.left(s.length() - 1)
	return s + ".."


func text(c: CanvasItem, s: String, pos: Vector2, col: Color = INK, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, shade := false, size := 0) -> void:
	var sz := size if size > 0 else px
	if shade:
		c.draw_string(font(), pos + Vector2(scale, scale), s, align, width, sz, INK)
	c.draw_string(font(), pos, s, align, width, sz, col)


## A label that stays inside `avail` pixels: drawn at the smallest size when it does not fit at the text size, and only then cut with dots.
func fit_text(c: CanvasItem, s: String, avail: float, pos: Vector2, col: Color = INK, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, shade := false, size := 0) -> void:
	if size <= 0:
		size = fit_size(s, avail)
	text(c, clip(s, avail, size), pos, col, align, width, shade, size)


## A paragraph of at most `max_lines` lines, centred in `box` when given; returns the y of the line after the last one.
func wrap_fit(c: CanvasItem, s: String, pos: Vector2, width: float, col: Color, max_lines: int, align := HORIZONTAL_ALIGNMENT_LEFT, box := -1.0) -> float:
	var size: int = block(s, width, max_lines).size
	var lines := lines_of(s, width, size)
	var y := pos.y
	for i in mini(lines.size(), max_lines):
		var line: String = lines[i]
		if i == max_lines - 1 and lines.size() > max_lines:
			line = clip(" ".join(lines.slice(i)), width, size)
		text(c, line, Vector2(pos.x, y), col, align, box, false, size)
		y += lead_for(size)
	return y


## Words wrapped to the width; returns the y of the line after the last one.
func wrap(c: CanvasItem, s: String, pos: Vector2, width: float, col: Color = INK, max_lines := 99) -> float:
	var y := pos.y
	var lines := lines_of(s, width)
	for i in mini(lines.size(), max_lines):
		text(c, lines[i], Vector2(pos.x, y), col)
		y += leading()
	return y


func panel(c: CanvasItem, r: Rect2, fill: Color = PARCH) -> void:
	c.draw_rect(r.grow(1), INK)
	c.draw_rect(r, fill)
	c.draw_rect(Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 4)), PARCH_DARK, false, 1.0)


## The sunken box a word is typed into, with a blinking cursor, so it reads as the place to type and not as another button.
func field(c: CanvasItem, r: Rect2, typed: String, placeholder: String) -> void:
	c.draw_rect(r.grow(1), INK)
	c.draw_rect(r, CREAM)
	c.draw_rect(Rect2(r.position, Vector2(r.size.x, 2)), PARCH_DARK)
	c.draw_rect(Rect2(r.position, Vector2(2, r.size.y)), PARCH_DARK)
	var at := Vector2(r.position.x + 8.0, label_y(r, placeholder))
	if typed == "":
		text(c, placeholder, at, MUTED)
	else:
		var size := fit_size(typed, r.size.x - 24.0)
		fit_text(c, typed, r.size.x - 24.0, Vector2(at.x, label_y(r, typed, size)), INK, HORIZONTAL_ALIGNMENT_LEFT, -1.0, false, size)
	if int(Time.get_ticks_msec() / 500) % 2 == 0:
		var x := at.x + (width_at(typed, px) + 2.0 if typed != "" else 0.0)
		c.draw_rect(Rect2(x, r.position.y + 5.0, 2.0, r.size.y - 10.0), INK)


## Shows a phone's own keyboard holding `typed`, or hides it.
static func keyboard(up: bool, typed := "") -> void:
	if not Touch.phone or not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	if up:
		DisplayServer.virtual_keyboard_show(typed, Rect2(), DisplayServer.KEYBOARD_TYPE_DEFAULT, 20)
	else:
		DisplayServer.virtual_keyboard_hide()


static func fit_view(size: Vector2) -> void:
	view = size
	Horde.view = size
	offset = ((size - Vector2(W, H)) / 2.0).floor()


## A dimming veil over the whole window, drawn from inside the centred box.
static func veil(c: CanvasItem, alpha: float) -> void:
	c.draw_rect(Rect2(-offset, view), Color(0, 0, 0, alpha))


## The y, below a frame's top, where the first row under its title goes.
static func below_title() -> float:
	return 20.0 + 8.0 * scale


## The big panel of a screen's frame, taller on a phone, which has no key hints under it.
static func frame_rect() -> Rect2:
	return Rect2(16, 12, W - 32, H - (26 if Touch.phone else 40))


## A dimmed backdrop, a big panel, a title and a footer of key hints; a phone has a back button by the title instead of hints.
func frame(c: CanvasItem, title: String, hint: String, back := true) -> Rect2:
	veil(c, 0.5)
	var r := frame_rect()
	# A phone's frame is taller for having no key hints, so a line shown under it, such as where the demo ends, takes that room back.
	if Touch.phone and hint != "":
		r.size.y = H - 40
	panel(c, r)
	var tx := r.position.x + 12
	if Touch.phone and back and corner_room():
		corner_back(c)
	elif Touch.phone and back:
		var side := 14.0 + 4.0 * scale
		var b := Rect2(r.position.x + 5, r.position.y + 4, side + 4.0, side)
		back_button(c, b, Rect2(-offset, b.end + offset + Vector2(4, 3)))
		tx = b.end.x + 8.0
	text(c, title, Vector2(tx, r.position.y + 8 + 8 * scale), BROWN)
	if hint == "":
		return r
	# A long hint steps down to the smallest size, and only then loses its first parts until the rest fits the screen.
	var parts: Array = hint.split("     ")
	var size := fit_size("     ".join(parts), W - 16.0)
	while parts.size() > 1 and width_at("     ".join(parts), size) > W - 16.0:
		parts.remove_at(0)
	text(c, "     ".join(parts), Vector2(0, H - 10), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W, true, size)
	return r


## Adds a button to this frame's list; one scrolled out of sight is kept for the keys to reach but is not `hit` by a tap.
func register(r: Rect2, id: String, enabled := true, hit := true) -> void:
	_next.append({"id": id, "rect": r, "on": enabled, "hit": hit})


## A small button with a leftward arrow that steps back one screen, taking taps anywhere in `reach`.
func back_button(c: CanvasItem, r: Rect2, reach: Rect2) -> void:
	# It goes after the screen's own buttons, so a screen still opens with its first button picked out.
	_after.append({"id": "touch_back", "rect": reach, "on": true, "hit": true})
	if focus == "touch_back":
		c.draw_rect(r.grow(2), GOLD)
	panel(c, r, CREAM if focus == "touch_back" else PARCH)
	var mid := r.get_center()
	var k := maxf(3.0, roundf(r.size.y * 0.22))
	var arrow := PackedVector2Array([mid + Vector2(k * 0.6, -k), mid + Vector2(-k * 0.6, 0), mid + Vector2(k * 0.6, k)])
	c.draw_polyline(arrow, INK, 2.0 if r.size.y < 22.0 else 3.0)


## The back button in the corner of the whole window, clear of a phone's corners.
func corner_back(c: CanvasItem) -> void:
	var b := corner_back_rect()
	back_button(c, b, b.grow(6))


static func corner_back_rect() -> Rect2:
	var side := maxf(14.0 + 4.0 * scale, minf(Touch.fingertip * 0.75, 30.0))
	return Rect2(-offset + Touch.inset_tl + Vector2(6, 6), Vector2(side + 4.0, side))


## Whether the window's corner has room for the back button beside or above the frame, as a wide phone or a squarer tablet has.
static func corner_room() -> bool:
	var b := corner_back_rect()
	return b.end.x + 4.0 <= 16.0 or b.end.y + 4.0 <= 12.0


## A button: a panel with a label on the left, an optional value on the right and an optional icon. Focus gets a gold frame.
func button(c: CanvasItem, r: Rect2, id: String, label: String, right := "", enabled := true, icon: Texture2D = null, centered := false, right_col := RED, right_reserve := 0.0, label_size := 0) -> void:
	register(r, id, enabled)
	var focused := id == focus
	if focused:
		c.draw_rect(r.grow(3), GOLD)
	panel(c, r, CREAM if focused else PARCH)
	var ink := INK if enabled else MUTED
	var x := r.position.x + 6.0
	if icon != null:
		var side := icon_side(r)
		c.draw_texture_rect(icon, Rect2(x - 2.0, r.position.y + (r.size.y - side) / 2.0, side, side), false)
		x += side + 2.0
	if right != "":
		text(c, right, Vector2(r.end.x - width_of(right) - 6.0, label_y(r, right)), right_col if enabled else MUTED)
	var room := r.size.x - 12.0 if centered else label_room(r, right, icon != null, right_reserve)
	var size := label_size if label_size > 0 else fit_size(label, room)
	if centered:
		fit_text(c, label, room, Vector2(r.position.x, label_y(r, label, size)), ink, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, false, size)
	else:
		fit_text(c, label, room, Vector2(x, label_y(r, label, size)), ink, HORIZONTAL_ALIGNMENT_LEFT, -1.0, false, size)


## The baseline of a label in the middle of a box, at the size it is drawn at (the text size when 0).
static func label_y(r: Rect2, s: String, size := 0) -> float:
	return middle(r.position.y, r.size.y, s, size)


## The words of a phone's button that buys the full game, with the store's price once the store has said it.
static func unlock_label() -> String:
	if FullGame.price() == "":
		return TranslationServer.translate("Unlock the full game")
	return TranslationServer.translate("Unlock the full game: %s") % FullGame.price()


static func icon_side(r: Rect2) -> float:
	return minf(r.size.y - 6.0, 16.0)


## The width a button's label has beside its icon and the text on its right.
static func label_room(r: Rect2, right: String, has_icon: bool, right_reserve := 0.0) -> float:
	var x := r.position.x + 6.0 + (icon_side(r) + 2.0 if has_icon else 0.0)
	var right_w := (width_at(right, px) + 6.0 if right != "" else 0.0) + right_reserve
	return r.end.x - x - right_w - 6.0


## The icon image of a level-up id or an icon key, or null when it is not drawn.
func icon(key: String) -> Texture2D:
	if key == "":
		return null
	if not _icons.has(key):
		var path := "res://assets/icons/%s.png" % key
		_icons[key] = load(path) if ResourceLoader.exists(path) else null
	return _icons[key]


## Sends focus from the button `id` to `to` when the key for `dir` is pressed.
func link(id: String, dir: Vector2, to: String) -> void:
	_next_links["%s|%s" % [id, dir]] = to


## Moves focus where the screen linked it, or to the nearest button in the direction, preferring ones that line up with the current one.
func move(dir: Vector2) -> void:
	pointer_focus = false
	var linked: String = links.get("%s|%s" % [focus, dir], "")
	if linked != "" and has_item(linked):
		focus = linked
		return
	var cur := Rect2()
	var found := false
	for it in items:
		if it.id == focus:
			cur = it.rect
			found = true
	if not found:
		return
	var from := cur.get_center()
	var best := ""
	var best_score := INF
	for it in items:
		if it.id == focus:
			continue
		var d: Vector2 = it.rect.get_center() - from
		var along := d.dot(dir)
		var across := absf(d.dot(Vector2(-dir.y, dir.x)))
		if along < 1.0:
			continue
		var score := along + across * 2.5
		if score < best_score:
			best_score = score
			best = it.id
	if best != "":
		focus = best


## The id of the button under a point, or "".
func at(p: Vector2) -> String:
	for it in items:
		if it.get("hit", true) and it.rect.has_point(p):
			return it.id
	return ""


func hover(p: Vector2) -> void:
	var id := at(p)
	if id != "":
		pointer_focus = true
		focus = id


func is_enabled(id: String) -> bool:
	for it in items:
		if it.id == id:
			return it.on
	return false
