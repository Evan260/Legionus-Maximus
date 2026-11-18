class_name Ui
extends RefCounted
## Shared drawing and focus for the camp screens: parchment panels, buttons, wrapped text, and a focus cursor that
## keyboard, pad and mouse all move. A screen draws its buttons every frame; the buttons of the last finished frame are the ones focus moves between.

const W := 640.0
const H := 360.0
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
static var _balance_px := 8
# The window shows at least 640 by 360 and more on whichever side it is longer; menus stay in a centred 640 by 360 box.
static var view := Vector2(W, H)
static var offset := Vector2.ZERO

var items: Array = []
var focus := ""
## Where a key moves focus from a button when the screen sets it, in place of the nearest button that way.
var links := {}
var _next: Array = []
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


## The size a label is drawn at to fit the width: the text size, or the smallest one when it does not fit.
static func fit_size(s: String, width: float) -> int:
	return px if width_at(s, px) <= width else small_px()


## True when the label fits the width at the text size or the smallest size, so nothing is cut.
static func fits(s: String, width: float) -> bool:
	return width_at(s, fit_size(s, width)) <= width


## Text cut into lines no wider than the width at a size (the text size when 0), breaking at spaces, or between any two letters in languages written without them or in a word too long for a line.
static func lines_of(s: String, width: float, size := 0) -> Array:
	var sz := size if size > 0 else px
	var out: Array = []
	var line := ""
	var f := font()
	if Lang.is_han():
		for ch in s:
			if line != "" and f.get_string_size(line + ch, HORIZONTAL_ALIGNMENT_LEFT, -1, sz).x > width:
				out.append(line)
				line = ""
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


## Items joined by a separator into lines no wider than the width at the text size.
static func pack(items: Array, sep: String, width: float) -> Array:
	var out: Array = []
	var line := ""
	for item in items:
		var trial: String = str(item) if line == "" else line + sep + str(item)
		if line != "" and width_at(trial, px) > width:
			out.append(line)
			line = str(item)
		else:
			line = trial
	if line != "":
		out.append(line)
	return out


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
	_next_links = {}


## Ends a frame; focus falls back to the first button when its own has gone.
func end() -> void:
	items = _next
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
func clip(s: String, width: float, size := 0) -> String:
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
func fit_text(c: CanvasItem, s: String, avail: float, pos: Vector2, col: Color = INK, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, shade := false) -> void:
	var size := fit_size(s, avail)
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


## A dimmed backdrop, a big panel, a title and a footer of key hints.
func frame(c: CanvasItem, title: String, hint: String) -> Rect2:
	veil(c, 0.5)
	var r := Rect2(16, 12, W - 32, H - 40)
	panel(c, r)
	text(c, title, Vector2(r.position.x + 12, r.position.y + 8 + 8 * scale), BROWN)
	# A long hint steps down to the smallest size, and only then loses its first parts until the rest fits the screen.
	var parts: Array = hint.split("     ")
	var size := fit_size("     ".join(parts), W - 16.0)
	while parts.size() > 1 and width_at("     ".join(parts), size) > W - 16.0:
		parts.remove_at(0)
	text(c, "     ".join(parts), Vector2(0, H - 10), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W, true, size)
	return r


func register(r: Rect2, id: String, enabled := true) -> void:
	_next.append({"id": id, "rect": r, "on": enabled})


## A button: a panel with a label on the left, an optional value on the right and an optional icon. Focus gets a gold frame.
func button(c: CanvasItem, r: Rect2, id: String, label: String, right := "", enabled := true, icon: Texture2D = null, centered := false, right_col := RED, right_reserve := 0.0) -> void:
	register(r, id, enabled)
	var focused := id == focus
	if focused:
		c.draw_rect(r.grow(3), GOLD)
	panel(c, r, CREAM if focused else PARCH)
	var ink := INK if enabled else MUTED
	var x := r.position.x + 6.0
	if icon != null:
		var side := minf(r.size.y - 6.0, 16.0)
		c.draw_texture_rect(icon, Rect2(x - 2.0, r.position.y + (r.size.y - side) / 2.0, side, side), false)
		x += side + 2.0
	var y := r.position.y + r.size.y / 2.0 + px * 3 / 8
	var right_w := (width_of(right) + 6.0 if right != "" else 0.0) + right_reserve
	if right != "":
		text(c, right, Vector2(r.end.x - width_of(right) - 6.0, y), right_col if enabled else MUTED)
	if centered:
		fit_text(c, label, r.size.x - 12.0, Vector2(r.position.x, y), ink, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	else:
		fit_text(c, label, r.end.x - x - right_w - 6.0, Vector2(x, y), ink)


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
		if it.rect.has_point(p):
			return it.id
	return ""


func hover(p: Vector2) -> void:
	var id := at(p)
	if id != "":
		focus = id


func is_enabled(id: String) -> bool:
	for it in items:
		if it.id == id:
			return it.on
	return false
