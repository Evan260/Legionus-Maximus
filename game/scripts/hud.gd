class_name Hud
extends Node2D
## Everything drawn over the field: the top bar, the testudo charge, the favour of the gods, the chieftain's health and the level-up and god choices.
## The title, pause, summary, settings and camp are screens drawn through the shared Ui.

const LAUREL := preload("res://assets/icons/laurel.png")
const W := 640.0
const H := 360.0
const INK := Color(0.16, 0.1, 0.08)
const CREAM := Color(1.0, 0.95, 0.82)
const PARCH := Color(0.96, 0.9, 0.76)
const PARCH_DARK := Color(0.82, 0.7, 0.52)
const GOLD := Color(0.91, 0.69, 0.25)
const GOLD_LIGHT := Color(1.0, 0.89, 0.59)
const RED := Color(0.72, 0.18, 0.14)
const BROWN_TEXT := Color(0.5, 0.36, 0.22)
const MUTED := Color(0.7, 0.66, 0.6)

const EDGE := 26.0
## How wide the run's line at the top left may be, so it ends before the chieftain's name and health bar in the middle.
const RUN_LINE_ROOM := 200.0
## How far above its foot an objective's name is written when it is on screen, clear of its sprite.
const LABEL_RISE := {"camp": 56.0, "column": 50.0, "grove": 40.0, "fort": 76.0}
## The build panel on the left of the level-up and pause screens: its left edge, its top and foot between the top bar and the testudo, its width at each text size, its inner margin, and the icon sides it tries, largest first, until everything fits.
const BUILD_X := 8.0
const BUILD_TOP := 30.0
const BUILD_FOOT := 316.0
const BUILD_W := 144.0
const BUILD_W_BIG := 172.0
const BUILD_PAD := 4.0
const BUILD_ICONS := [24.0, 22.0, 20.0, 18.0, 16.0]
const PIP_DARK := Color(0.32, 0.26, 0.2)
## The choice panel on the right of the level-up: the icon sides and the room between its lines it tries, roomiest first, its buttons' height and the gap between them, the room for the arrow between a number now and next, and the colour of its history.
const PANEL_ROOMS := [[48.0, 2.0], [40.0, 1.0], [32.0, 0.0]]
const PANEL_BUTTON_H := 16.0
const PANEL_BUTTON_GAP := 3.0
const ARROW_W := 9.0
const HISTORY := Color(0.84, 0.78, 0.66)
## The level-up's rows at the normal text size: their width, the gap between them, the top of the first, and the height of each when there are three or four.
const ROW_W := 320.0
const ROW_GAP := 5.0
const ROW_TOP := 72.0
const ROW_H3 := 62.0
const ROW_H4 := 56.0
const ROW_ICON := 32.0
## Large text: the rows run across the screen's safe area between the top bar and the corners, each with its icon, name, level and description. Their widest and tallest, the gap between them, the room inside them, the icon sides they try, largest first, and the share of the text size a capital stands above its line.
const BIG_ROW_W := 760.0
const BIG_ROW_H := 88.0
const BIG_ROW_GAP := 4.0
const BIG_ROW_PAD := 3.0
const BIG_ICONS := [64.0, 48.0, 32.0]
const BIG_GLYPH := 0.75
## A phone's buttons under the large rows: their widest, and the narrowest that still sits between the testudo and the favour before the row moves up above them.
const BIG_BUTTON_W := 210.0
const BIG_BUTTON_LOW := 80.0
## The icon of each supply cart reward.
const SUPPLY_ICONS := {"free_choice": "glory", "heal": "medicus", "magnet": "magnet"}

var main: Node
var ui: Ui
var icons := {}
var choice_rects: Array = []
## The buttons under a choice on a phone, which stand in for its keys, as {id: rect}.
var touch_buttons := {}


## The level-up icon of an id, loaded the first time it is drawn.
func icon_of(id: String) -> Texture2D:
	if not icons.has(id):
		var path := "res://assets/icons/%s.png" % main.sim.content.icon_key(id)
		icons[id] = load(path) if ResourceLoader.exists(path) else null
	return icons[id]


## A supply cart reward's icon, loaded the first time it is drawn.
func supply_icon(id: String) -> Texture2D:
	var key := "supply:" + id
	if not icons.has(key):
		icons[key] = load("res://assets/icons/%s.png" % SUPPLY_ICONS[id])
	return icons[key]


func _process(_dt: float) -> void:
	queue_redraw()


func text(s: String, pos: Vector2, col: Color = CREAM, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, shade := true, size := 0) -> void:
	var sz := size if size > 0 else Ui.px
	if shade:
		draw_string(Ui.font(), pos + Vector2(Ui.scale, Ui.scale), s, align, width, sz, INK)
	draw_string(Ui.font(), pos, s, align, width, sz, col)


## A text on a dim plate, for the corner labels that sit over snow, sand and dark trees alike.
func plated_text(s: String, pos: Vector2, col: Color = CREAM, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, size := 0) -> void:
	var sz := size if size > 0 else Ui.px
	var w := Ui.width_at(s, sz)
	var x := pos.x
	if align == HORIZONTAL_ALIGNMENT_RIGHT:
		x = pos.x + width - w
	elif align == HORIZONTAL_ALIGNMENT_CENTER:
		x = pos.x + (width - w) / 2.0
	draw_rect(Rect2(x - 3.0, pos.y - sz - 1.0, w + 6.0, Ui.lead_for(sz) + 1.0), Color(0.08, 0.05, 0.04, 0.55))
	text(s, pos, col, align, width, true, sz)


func wrap_text(s: String, pos: Vector2, width: float, col: Color) -> void:
	var y := pos.y
	for line in Ui.lines_of(s, width):
		text(line, Vector2(pos.x, y), col, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
		y += Ui.leading()


func panel(r: Rect2, fill: Color = PARCH) -> void:
	draw_rect(r.grow(1), INK)
	draw_rect(r, fill)
	draw_rect(Rect2(r.position + Vector2(2, 2), r.size - Vector2(4, 4)), PARCH_DARK, false, 1.0)


func _draw() -> void:
	if main == null:
		return
	Ui.fit_view(get_viewport_rect().size)
	_scene()
	draw_set_transform(Vector2.ZERO)
	_card()


## An achievement card sliding in at the top right, a parchment panel with a laurel, over whatever is on screen.
func _card() -> void:
	var card: Dictionary = Steamworks.card
	if not Steamworks.card_visible(main.state):
		return
	var big := Ui.scale > 1
	var W := Ui.view.x
	var w := 190.0 if not big else 280.0
	var room := w - 40.0
	# A long name takes a second line, and the card grows to hold it.
	var name_lines := mini(Ui.block(str(card.name).to_upper(), room, 2).lines, 2)
	var h := 16.0 + (1.0 + name_lines) * Ui.leading() + (4.0 if big else 0.0)
	var slide := Steamworks.card_slide()
	var top := 44.0 if not big else 68.0
	var pause: Dictionary = touch_layout().get("pause", {})
	if not pause.is_empty():
		top = maxf(top, pause.centre.y + pause.radius + 6.0)
	var r := Rect2(lerpf(W + 2.0, W - 6.0 - Touch.inset_br.x - w, slide), top, w, h)
	panel(r)
	var wreath: Texture2D = LAUREL
	draw_texture(wreath, (r.position + Vector2(18.0, h / 2.0) - wreath.get_size() / 2.0).round())
	var tx := r.position.x + 34.0
	ui.fit_text(self, tr("Achievement").to_upper(), room, Vector2(tx, r.position.y + 6.0 + Ui.px * 3 / 4), BROWN_TEXT)
	ui.wrap_fit(self, str(card.name).to_upper(), Vector2(tx, r.position.y + 6.0 + Ui.px * 3 / 4 + Ui.leading()), room, INK, 2)


## A small wreath of gold leaves around a dot.
func _laurel(c: Vector2) -> void:
	for side in [-1.0, 1.0]:
		for i in 6:
			var a := deg_to_rad(120.0 + 20.0 * i)
			var p := c + Vector2(cos(a) * side, -sin(a)) * 8.0
			draw_rect(Rect2(floorf(p.x) - 1.0, floorf(p.y) - 1.0, 3, 3), GOLD if i % 2 == 0 else GOLD_LIGHT)
			draw_rect(Rect2(floorf(p.x) - 1.0, floorf(p.y) + 2.0, 3, 1), INK)
	draw_rect(Rect2(c.x - 2.0, c.y - 2.0, 4, 4), RED)


func _scene() -> void:
	var sim: Sim = main.sim
	if main.screens.has(main.state):
		# The summary's frame covers the middle of the top bar but not its ends, so only the pause screen keeps it.
		if main.state == "pause":
			_top_bar(sim)
		ui.begin()
		draw_set_transform(Ui.offset)
		main.screens[main.state].draw(self, ui)
		ui.end()
		return
	var white := sim.flash()
	if white > 0.0:
		draw_rect(Rect2(Vector2.ZERO, Ui.view), Color(1, 1, 1, white * float(sim.b.chief_death.flash)))
	_top_bar(sim)
	var choosing := Game.choosing(main.state)
	# The boss names and objective badges would sit on the choice's heading and cards, so they wait until it is made.
	if not choosing:
		var bosses := boss_names(sim)
		for b in bosses:
			text(b.name, Vector2(b.rect.position.x, b.rect.position.y + Ui.px), GOLD_LIGHT)
		if sim.triumph_left <= 0.0:
			# The names' shading and the badges' glow reach past their rects, so the names keep a margin.
			var avoid: Array = bosses.map(func(b: Dictionary) -> Rect2: return b.rect.grow(4.0))
			var chief := chieftain_rect(sim)
			if chief.has_area():
				avoid.append(chief)
			for banner in [god_banner_rect(sim), chief_banner_rect(sim)]:
				if banner.has_area():
					avoid.append(banner)
			_objective_arrows(sim, avoid)
	_god_banner(sim)
	_chief_banner(sim)
	_victory_banner(sim)
	if choosing:
		_choices(sim)


## The top bar and the corners, drawn inside the part of the screen clear of a phone's rounded corners and camera.
func _top_bar(sim: Sim) -> void:
	var safe := Ui.view - Touch.inset_tl - Touch.inset_br
	draw_set_transform(Touch.inset_tl)
	_top_bar_in(sim, safe.x, safe.y)
	draw_set_transform(Vector2.ZERO)


## The touch buttons laid out this frame, or none off a phone.
func touch_layout() -> Dictionary:
	return main.touch_pad.layout if main.touch_pad != null else {}


## Where the right-hand words of the top bar end, left of a phone's pause button.
func _right_edge(W: float) -> float:
	var pause: Dictionary = touch_layout().get("pause", {})
	if pause.is_empty() or main.state != "play":
		return W - 10.0
	return minf(W - 10.0, pause.centre.x - pause.radius - 6.0 - Touch.inset_tl.x)


## The province and difficulty of the run, as the top bar writes them under the level.
static func run_line(sim: Sim) -> String:
	return ("%s, %s" % [sim.content.provinces[sim.province].name, TranslationServer.translate(sim.difficulty.capitalize())]).to_upper()


func _top_bar_in(sim: Sim, W: float, H: float) -> void:
	var big := Ui.scale > 1
	draw_rect(Rect2(8, 6, W - 16, 7), INK)
	var fill := (W - 18) * clampf(float(sim.xp) / sim.xp_next, 0.0, 1.0)
	draw_rect(Rect2(9, 7, fill, 5), GOLD)
	draw_rect(Rect2(9, 7, fill, 1), GOLD_LIGHT)
	var secs := int(sim.time)
	var y1 := 16.0 + 8.0 * Ui.scale
	var y2 := y1 + (11.0 if not big else 20.0)
	# A choice on screen keeps only the level and the legion up here; its cards and heading take the rest.
	var choosing := Game.choosing(main.state)
	plated_text((tr("Level %d") % sim.level).to_upper(), Vector2(10, y1))
	if not (choosing and big):
		plated_text("%02d:%02d" % [secs / 60, secs % 60], Vector2(0, y1), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W)
	var right := _right_edge(W)
	plated_text((tr("Legion %d") % (sim.soldiers.size() + 1)).to_upper(), Vector2(0, y1), CREAM, HORIZONTAL_ALIGNMENT_RIGHT, right)
	if not choosing:
		plated_text((tr("Kills %d") % sim.kills).to_upper(), Vector2(0, y2), CREAM, HORIZONTAL_ALIGNMENT_RIGHT, right)
		if not main.screens.has(main.state):
			var line := run_line(sim)
			var size := Ui.fit_size(line, RUN_LINE_ROOM)
			plated_text(ui.clip(line, RUN_LINE_ROOM, size), Vector2(10, y2), MUTED, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size)
	# The pause and summary screens write their key hints along the bottom, so the bottom row is left to them.
	if main.screens.has(main.state):
		_chieftain_line(sim, W, y1, big)
		return
	# The testudo charge sits bottom left, gold when it is ready.
	var ready := sim.testudo_charge >= 1.0 and sim.testudo_left <= 0.0
	var shield := icon_of("testudo")
	if shield != null:
		draw_texture(shield, Vector2(8, H - 42), Color.WHITE if ready or sim.testudo_left > 0.0 else Color(0.5, 0.5, 0.5))
	draw_rect(Rect2(8, H - 9, 34, 4), INK)
	var charge := 1.0 if sim.testudo_left > 0.0 else sim.testudo_charge
	draw_rect(Rect2(9, H - 8, 32 * charge, 2), GOLD if ready or sim.testudo_left > 0.0 else PARCH_DARK)
	# A large choice keeps only the testudo's and the favour's pictures down here, so its buttons and hints fit between them.
	var bare := choosing and big
	if not bare:
		plated_text((tr("Testudo") if sim.testudo_left <= 0.0 else tr("Hold!")).to_upper(), Vector2(46, H - 6), GOLD_LIGHT if ready or sim.testudo_left > 0.0 else Color(0.7, 0.66, 0.6))
		_timber(sim, W, H)
	_favour(sim, W, H, bare)
	_timber_keys(sim, W, H)
	if choosing:
		return
	_health(sim, Vector2(W, H))
	_chieftain_line(sim, W, y1, big)


## The baseline of the chieftain's line: under the clock, or with large text on a row of its own under the run line.
static func chieftain_y(y1: float, big: bool) -> float:
	return y1 + (11.0 if not big else 20.0 + Ui.leading())


## Whether the chieftain's line shows anything: his health, the time won in endless mode or the warning that he is coming.
static func chieftain_line_shown(sim: Sim) -> bool:
	return sim.horde.chieftain_index() >= 0 or (sim.endless and sim.endless_since >= 0.0) or (sim.time > float(sim.b.chieftain_at) - 30.0 and sim.horde.chieftain_id == -1)


## How far down the edge badges keep, clear of the top bar and the chieftain's line.
static func badges_top(sim: Sim) -> float:
	var y1 := 16.0 + 8.0 * Ui.scale
	if chieftain_line_shown(sim):
		return chieftain_y(y1, Ui.scale > 1) + 12.0 + Touch.inset_tl.y
	return y1 + (22.0 if Ui.scale > 1 else 11.0) + Touch.inset_tl.y


## The chieftain's health under the clock, the time won in endless mode, or the warning that he is coming.
func _chieftain_line(sim: Sim, W: float, y1: float, big: bool) -> void:
	var ci := sim.horde.chieftain_index()
	var y3 := chieftain_y(y1, big)
	if ci >= 0:
		text(chief_name(sim).to_upper(), Vector2(0, y3), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)
		draw_rect(Rect2(W / 2 - 101, y3 + 4, 202, 6), INK)
		draw_rect(Rect2(W / 2 - 100, y3 + 5, 200 * clampf(sim.horde.e_hp[ci] / sim.horde.e_max[ci], 0, 1), 4), RED)
	elif sim.endless and sim.endless_since >= 0.0:
		var extra := int(sim.endless_seconds())
		text((tr("Endless  +%d:%02d") % [extra / 60, extra % 60]).to_upper(), Vector2(0, y3), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)
	elif sim.time > float(sim.b.chieftain_at) - 30.0 and sim.horde.chieftain_id == -1:
		text((tr("The %s is coming") % chief_name(sim)).to_upper(), Vector2(0, y3), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)


## The logs of timber the legion carries, above the testudo's name, gold once there are enough for a palisade, and the notice when there are not.
func _timber(sim: Sim, W: float, H: float) -> void:
	var atlas: Atlas = main.world.atlas
	var cost := int(sim.b.palisade.cost)
	var enough := sim.timber >= cost
	var y := H - 8.0 - Ui.leading() - 4.0
	if atlas != null and atlas.props.has("timber"):
		var f := atlas.prop_frame("timber")
		var r: Rect2 = f[0]
		draw_texture_rect_region(atlas.texture, Rect2(Vector2(46, y - r.size.y + 2.0), r.size), r, Color.WHITE if enough else Color(0.75, 0.72, 0.68))
	text(str(sim.timber), Vector2(66, y), GOLD_LIGHT if enough else CREAM)
	var bridge_cost := int(sim.b.bridge.cost)
	if sim.ravine_near:
		_bridge_cost(Vector2(66.0 + Ui.width_at(str(sim.timber), Ui.px) + 6.0, y), bridge_cost, sim.timber >= bridge_cost)
	var line := ""
	var refused: Dictionary = sim.bridge_refused
	if not refused.is_empty() and sim.time - float(refused.at) < float(sim.b.bridge.notice_seconds) and float(refused.at) >= sim.palisade_refused_at:
		line = tr("No ravine ahead to bridge") if refused.why == "ravine" else tr("Not enough timber: %d needed") % int(sim.b.bridge.cost)
	elif sim.wall_refused_at > sim.palisade_refused_at and sim.time - sim.wall_refused_at < float(sim.b.wall.notice_seconds):
		line = tr("Not enough timber: %d needed") % int(sim.b.wall.cost)
	elif sim.palisade_refused_at >= 0.0 and sim.time - sim.palisade_refused_at < float(sim.b.palisade.notice_seconds):
		line = tr("Not enough timber: %d needed") % cost
	if line != "":
		text(line.to_upper(), Vector2(0, H * 0.7), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W)
	if sim.bridge_here and main.state == "play":
		var hint := bridge_hint(sim.timber, bridge_cost)
		var r: Rect2 = bottom_layout(Vector2(W, H)).bridge
		var said := str(hint.text).to_upper()
		var w := Ui.width_at(said, Ui.px)
		draw_rect(Rect2((W - w) / 2.0 - 4.0, r.position.y - 1.0, w + 8.0, r.size.y + 2.0), Color(0.08, 0.05, 0.04, 0.55))
		text(said, Vector2(0, r.position.y + Ui.px), GOLD_LIGHT if hint.enough else MUTED, HORIZONTAL_ALIGNMENT_CENTER, W)


## The hint at a ravine's lip: the key and the cost, or with too little timber the cost and what the legion has.
static func bridge_hint(timber: int, cost: int) -> Dictionary:
	if timber >= cost:
		return {"text": Controls.hint("bridge") + "  " + TranslationServer.translate("(%d timber)") % cost, "enough": true}
	return {"text": Controls.hint("bridge") + ": " + TranslationServer.translate("%d timber, you have %d") % [cost, timber], "enough": false}


## A small plank bridge and the timber a bridge costs, beside the legion's timber while a ravine is on screen.
func _bridge_cost(at: Vector2, cost: int, enough: bool) -> void:
	var wood := Color(0.62, 0.42, 0.24) if enough else Color(0.5, 0.45, 0.4)
	var k := float(Ui.scale)
	var top := at.y - Ui.px * 0.5 - 3.5 * k
	draw_rect(Rect2(at.x - 1, top - 1, 12 * k + 2, 7 * k + 2), INK)
	for n in 4:
		draw_rect(Rect2(at.x + n * 3.0 * k, top, 2 * k, 7 * k), wood)
	draw_rect(Rect2(at.x, top + k, 12 * k, k), wood.lightened(0.3))
	draw_rect(Rect2(at.x, top + 5 * k, 12 * k, k), wood.darkened(0.3))
	text(str(cost), Vector2(at.x + 12 * k + 4.0, at.y), GOLD_LIGHT if enough else CREAM)


## The keys that spend timber, listed at the bottom right above the favour, each lit once the legion has its cost.
func _timber_keys(sim: Sim, W: float, H: float) -> void:
	# A phone's buttons show what each work costs and whether there is timber enough.
	if main.state != "play" or Touch.phone:
		return
	for spot in timber_key_spots(sim, W, H):
		var line: Dictionary = spot[0]
		plated_text(str(line.text).to_upper(), Vector2(0, spot[1].position.y + Ui.px + 1.0), GOLD_LIGHT if line.enough else MUTED, HORIZONTAL_ALIGNMENT_RIGHT, W - 8.0)


## Where the palisade, wall and bridge keys are written at the bottom right, from the bottom up, as [line, plate rect].
static func timber_key_spots(sim: Sim, W: float, H: float) -> Array:
	var out: Array = []
	var y := H - 46.0
	var lines := timber_keys(sim.b, sim.timber)
	lines.reverse()
	for line in lines:
		var w := Ui.width_at(str(line.text).to_upper(), Ui.px)
		out.append([line, Rect2(W - 8.0 - w - 3.0, y - Ui.px - 1.0, w + 6.0, Ui.leading() + 1.0)])
		y -= Ui.leading() + 2.0
	return out


## The palisade, wall and bridge keys with the timber each costs, and whether the legion has that much.
static func timber_keys(balance: Dictionary, timber: int) -> Array:
	var out: Array = []
	for row in [["build", "palisade", balance.palisade], ["wall", "wall", balance.wall], ["bridge", "bridge", balance.bridge]]:
		var cost := int(row[2].cost)
		out.append({"text": Controls.part(Controls.shown(row[0]), row[1]) + "  (%d)" % cost, "enough": timber >= cost})
	return out


## The favour of the gods at the bottom right: a wreath over a bar that fills with kills, glowing with the key to call them once full.
func _favour(sim: Sim, W: float, H: float, bare := false) -> void:
	var gods := sim.gods
	var ready := gods.full(sim.b)
	var share := clampf(float(gods.favour) / maxf(1.0, gods.need(sim.b)), 0.0, 1.0)
	var c := Vector2(W - 25.0, H - 24.0)
	if ready:
		var pulse := 0.5 + 0.5 * sin(sim.time * 6.0)
		draw_circle(c, 14.0 + 3.0 * pulse, Color(1.0, 0.85, 0.4, 0.18 + 0.2 * pulse))
		draw_circle(c, 9.0, Color(1.0, 0.95, 0.7, 0.35 + 0.3 * pulse))
	_laurel(c)
	draw_rect(Rect2(W - 42, H - 9, 34, 4), INK)
	draw_rect(Rect2(W - 41, H - 8, 32 * share, 2), GOLD_LIGHT if ready else GOLD)
	if bare:
		return
	plated_text(tr("Favour").to_upper(), Vector2(0, H - 6), GOLD_LIGHT if ready else Color(0.7, 0.66, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, W - 46)
	if ready and main.state == "play":
		text(Controls.hint("pray").to_upper(), Vector2(0, H - 6 - Ui.leading()), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_RIGHT, W - 46)


## Where each thing along the bottom of the screen stands, with the commander's health bar between them all.
static func bottom_layout(view: Vector2) -> Dictionary:
	var W := view.x
	var H := view.y
	var px := float(Ui.px)
	var lead := Ui.leading()
	var testudo_w := maxf(Ui.width_at(TranslationServer.translate("Testudo").to_upper(), Ui.px), Ui.width_at(TranslationServer.translate("Hold!").to_upper(), Ui.px))
	var testudo := Rect2(8, H - 42, 38 + testudo_w, 42)
	var timber_y := H - 8.0 - lead - 4.0
	var timber := Rect2(46, timber_y - 14.0, 30 + 12 * Ui.scale + Ui.width_at("999", Ui.px) + Ui.width_at("99", Ui.px), 16)
	var favour_w := Ui.width_at(TranslationServer.translate("Favour").to_upper(), Ui.px)
	var favour := Rect2(W - 46 - favour_w, H - 42, 38 + favour_w, 42)
	var pray_w := Ui.width_at(Controls.hint("pray").to_upper(), Ui.px)
	var pray := Rect2(W - 46 - pray_w, H - 6 - lead - px, pray_w, px + 2)
	var notice := Rect2(0, H * 0.7 - px, W, lead)
	var left_end := maxf(testudo.end.x, timber.end.x)
	var room := minf(W / 2.0 - left_end, favour.position.x - W / 2.0) - 10.0
	var half := minf(110.0 if Ui.scale == 1 else 150.0, room)
	var bar_h := px + 2.0
	var health := Rect2(W / 2.0 - half, H - 3.0 - bar_h, half * 2.0, bar_h)
	var bridge := Rect2(0, pray.position.y - lead - 2.0, W, px + 2)
	return {"health": health, "testudo": testudo, "timber": timber, "favour": favour, "pray": pray, "notice": notice, "bridge": bridge}


## The colour of the health bar: a flash of bright red just after a blow, red below a quarter of his health, green otherwise.
static func health_colour(share: float, since_hit: float) -> Color:
	if since_hit < 0.2:
		return Color(1.0, 0.42, 0.36)
	if share < 0.25:
		return RED
	return Color(0.42, 0.66, 0.28)


var _last_hp := -1.0
var _hit_at := -1e9


## The commander's health in a big bar along the bottom of the screen, with the numbers on it.
func _health(sim: Sim, safe: Vector2) -> void:
	var c: Dictionary = sim.commander
	# A clock behind the last blow is a new run's, so the last run's blow does not flash the bar.
	if sim.time < _hit_at:
		_hit_at = -1e9
	elif c.hp < _last_hp:
		_hit_at = sim.time
	_last_hp = c.hp
	var since := sim.time - _hit_at
	var share := clampf(c.hp / maxf(1.0, c.max_hp), 0.0, 1.0)
	var r: Rect2 = bottom_layout(safe).health
	var low := share < 0.25
	var flashing := since < 0.2
	draw_rect(r.grow(1), RED if flashing or (low and fmod(sim.time, 0.8) < 0.4) else INK)
	draw_rect(r, Color(0.2, 0.08, 0.06))
	var fill := health_colour(share, since)
	draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * share), r.size.y)), fill)
	draw_rect(Rect2(r.position, Vector2(roundf(r.size.x * share), 1)), fill.lightened(0.35))
	var label := "%d / %d" % [ceili(c.hp), ceili(c.max_hp)]
	text(label, Vector2(r.position.x, r.end.y - 2.0), CREAM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## The name of this province's last enemy (the war chief, a king, the shah or the queen), as the HUD calls him.
## The places the edge badges point to: the objectives and the fort, and the chieftain while he lives, as
## [kind, position, name, unit], the last two set only for the chieftain.
static func targets_of(sim: Sim) -> Array:
	var out: Array = sim.objectives.targets()
	# The desert's grove is a sacred well, named and pictured as one on its badge.
	if sim.objectives.well():
		for k in out.size():
			if out[k][0] == "grove":
				out[k] = ["grove", out[k][1], TranslationServer.translate(objective_name("grove", sim)).to_upper(), "", "well"]
	var ci := sim.chieftain_index()
	if ci >= 0:
		out.append(["chieftain", sim.horde.e_pos[ci], chief_name(sim).to_upper(), sim.horde.kind_ids[sim.horde.e_kind[ci]]])
	return out


static func chief_name(sim: Sim) -> String:
	var kind: String = sim.horde.chief_kind if sim.horde.chief_kind != "" else "chieftain"
	return str(sim.content.enemies[kind].name)


## The chieftain's sprite on screen in screen pixels, so the objective badges stand clear of him; empty when he is not alive.
func chieftain_rect(sim: Sim) -> Rect2:
	var h: Horde = sim.horde
	var ci := h.chieftain_index()
	if ci < 0:
		return Rect2()
	var atlas: Atlas = main.world.atlas
	var type: String = h.kind_ids[h.e_kind[ci]]
	var size := Vector2(112, 112)
	if atlas != null and atlas.units.has(type):
		var f: Array = atlas.units[type].idle.south.frames[0]
		size = Vector2(f[2], f[3])
	var p: Vector2 = h.e_pos[ci] - sim.commander.pos + Ui.view / 2.0
	return Rect2(p - Vector2(size.x / 2.0, size.y), size).intersection(Rect2(Vector2.ZERO, Ui.view))


## Each elite's name over his head, as {name, rect} in screen pixels, drawn here so it follows the text size.
func boss_names(sim: Sim) -> Array:
	var out: Array = []
	var h: Horde = sim.horde
	var atlas: Atlas = main.world.atlas
	var screen := Rect2(Vector2.ZERO, Ui.view)
	for id in h.elite_ids:
		var i := h.e_id.find(id)
		if i < 0 or h.e_tag[i] == Horde.CHIEF:
			continue
		var type: String = h.kind_ids[h.e_kind[i]]
		var tall: float = (atlas.units[type].idle.south.frames[0][3] if atlas != null and atlas.units.has(type) else 40.0) * float(sim.content.enemies[type].get("scale", 1.0))
		var p: Vector2 = h.e_pos[i] - sim.commander.pos + Ui.view / 2.0
		var name := str(sim.content.enemies[type].name).to_upper()
		var w := Ui.width_at(name, Ui.px)
		var r := Rect2((p + Vector2(-w / 2.0, -tall - 6.0 - Ui.px)).round(), Vector2(w, Ui.leading()))
		if screen.intersects(r):
			out.append({"name": name, "rect": r})
	return out


## Whether the name of the god just called is on screen.
func _god_banner_shown(sim: Sim) -> bool:
	var last: Dictionary = sim.gods.last
	return not last.is_empty() and main.state == "play" and sim.time - float(last.at) <= float(sim.b.gods.banner_seconds) and sim.content.gods.has(last.id)


## The screen rect the god's name covers while it shows, so the objective badges stand clear of it; empty otherwise.
func god_banner_rect(sim: Sim) -> Rect2:
	if not _god_banner_shown(sim):
		return Rect2()
	var size := Ui.px * 3
	var w := Ui.font().get_string_size(str(sim.content.gods[sim.gods.last.id].name).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	return Rect2((Ui.view.x - w) / 2.0, Ui.view.y * 0.24 - size, w + 3.0, size * 1.2 + 3.0).grow(4.0)


## The name of the god just called, written large across the screen as his power lands.
func _god_banner(sim: Sim) -> void:
	if not _god_banner_shown(sim):
		return
	var last: Dictionary = sim.gods.last
	var age := sim.time - float(last.at)
	var secs := float(sim.b.gods.banner_seconds)
	var a := clampf(minf(age * 4.0, (secs - age) * 2.0), 0.0, 1.0)
	var size := Ui.px * 3
	var name := str(sim.content.gods[last.id].name).to_upper()
	var y := Ui.view.y * 0.24
	draw_string(Ui.font(), Vector2(3, y + 3), name, HORIZONTAL_ALIGNMENT_CENTER, Ui.view.x, size, Color(INK, a))
	draw_string(Ui.font(), Vector2(0, y), name, HORIZONTAL_ALIGNMENT_CENTER, Ui.view.x, size, Color(GOLD_LIGHT, a))


## The great VICTORY across the field while the legion holds its triumph, between two laurels, with the province's name below.
func _victory_banner(sim: Sim) -> void:
	if sim.triumph_left <= 0.0 or main.state != "play":
		return
	var a := clampf(sim.triumph_t * 3.0, 0.0, 1.0)
	var grow := 1.0 + 0.25 * (1.0 - clampf(sim.triumph_t * 2.5, 0.0, 1.0))
	var size := int(Ui.px * 5 * grow)
	var word := tr("Victory").to_upper()
	var y := Ui.view.y * 0.3
	var w := Ui.font().get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_rect(Rect2(0, y - size * 1.1, Ui.view.x, size * 1.6 + Ui.leading()), Color(INK, 0.45 * a))
	draw_string(Ui.font(), Vector2(4, y + 4), word, HORIZONTAL_ALIGNMENT_CENTER, Ui.view.x, size, Color(INK, a))
	draw_string(Ui.font(), Vector2(0, y), word, HORIZONTAL_ALIGNMENT_CENTER, Ui.view.x, size, Color(GOLD_LIGHT, a))
	for side in [-1.0, 1.0]:
		_laurel(Vector2(Ui.view.x / 2.0 + side * (w / 2.0 + 22.0), y - size * 0.35))
	var line := tr("%s is won") % str(sim.content.provinces[sim.province].name)
	draw_string(Ui.font(), Vector2(0, y + Ui.leading() + Ui.px * 0.6), line.to_upper(), HORIZONTAL_ALIGNMENT_CENTER, Ui.view.x, Ui.px, Color(CREAM, a))


## Whether the chieftain's fall is written across the screen.
static func chief_banner_shown(sim: Sim) -> bool:
	return sim.chief_fallen_at >= 0.0 and sim.triumph_left <= 0.0 and sim.time - sim.chief_fallen_at < float(sim.b.chief_death.banner_seconds)


static func chief_banner_line(sim: Sim) -> String:
	return TranslationServer.translate("The %s has fallen") % chief_name(sim)


## The size the chieftain's banner is written at: as large as a god's name, smaller for a long name.
static func _chief_banner_size(line: String) -> int:
	var size := Ui.px * 3
	while size > Ui.px and Ui.width_at(line, size) > Ui.view.x - 24.0:
		size -= 1
	return size


## The dark band the chieftain's banner lies on, so the objective badges stand clear of it; empty when it is not shown.
func chief_banner_rect(sim: Sim) -> Rect2:
	if not chief_banner_shown(sim):
		return Rect2()
	var size := _chief_banner_size(chief_banner_line(sim).to_upper())
	var y := Ui.view.y * 0.3
	return Rect2(0, y - size * 1.2, Ui.view.x, size * 1.7)


## The chieftain's fall written large across the field over a dark band.
func _chief_banner(sim: Sim) -> void:
	if not chief_banner_shown(sim) or main.state != "play":
		return
	var age := sim.time - sim.chief_fallen_at
	var secs := float(sim.b.chief_death.banner_seconds)
	var a := clampf(minf(age * 6.0, (secs - age) * 2.0), 0.0, 1.0)
	var line := chief_banner_line(sim).to_upper()
	var size := _chief_banner_size(line)
	var y := Ui.view.y * 0.3
	draw_rect(chief_banner_rect(sim), Color(INK, 0.5 * a))
	draw_string(Ui.font(), Vector2(3, y + 3), line, HORIZONTAL_ALIGNMENT_CENTER, Ui.view.x, size, Color(INK, a))
	draw_string(Ui.font(), Vector2(0, y), line, HORIZONTAL_ALIGNMENT_CENTER, Ui.view.x, size, Color(GOLD_LIGHT, a))


func _notice_text(kind: String, sim: Sim) -> String:
	return notice_line(kind, sim)


## The words of a notice, translated; the desert's sacred well is seized where an altar is burnt.
static func notice_line(kind: String, sim: Sim) -> String:
	var well := sim.objectives.well()
	match kind:
		"camp":
			return TranslationServer.translate("The eagle is ours again")
		"column":
			return TranslationServer.translate("The column joins the legion")
		"grove":
			if well:
				return TranslationServer.translate("The sacred well is ours: fewer barbarians for a minute")
			return TranslationServer.translate("The sacred grove burns: fewer barbarians for a minute")
		"cart_tip":
			return TranslationServer.translate("A supply cart: march into it to choose a free level-up, healing or every coin pulled in")
		"grove_tip":
			if well:
				return TranslationServer.translate("Stand at the sacred well to seize it: a free level-up and fewer barbarians for a minute")
			return TranslationServer.translate("Stand at the grove's altar to burn it: a free level-up and fewer barbarians for a minute")
		"chieftain":
			return TranslationServer.translate("The %s falls: now hold the fort") % chief_name(sim)
		"roar":
			return TranslationServer.translate("The %s roars in fury") % chief_name(sim)
		"testudo":
			return TranslationServer.translate("Raise the testudo!")
		"ambush":
			return TranslationServer.translate("Ambush: war bands close in on both flanks")
		"feint":
			return TranslationServer.translate("The %s turns and runs: beware a trick") % chief_name(sim)
		"feint_turn":
			return TranslationServer.translate("A feint: his warriors turn and rush back")
		"volleys":
			return TranslationServer.translate("The %s raises his hand: step out of the marked rings") % chief_name(sim)
		"javelins":
			return TranslationServer.translate("Hidden men hurl javelins: step out of the marked rings")
		"sluice":
			return TranslationServer.translate("The %s opens the sluices: the marked ground floods") % chief_name(sim)
		"lancers":
			return TranslationServer.translate("The %s sends his lancers: get out of the marked lane") % chief_name(sim)
		"steppe_fire":
			return TranslationServer.translate("The %s sets the steppe alight: get out of the marked ground") % chief_name(sim)
		"canal":
			return TranslationServer.translate("Cross the canals by their bridges, or fell palms for timber to bridge them")
		"ravine":
			return TranslationServer.translate("Fell trees for timber, then bridge the ravine at its edge")
		"fort_barred":
			return TranslationServer.translate("The fort is yours once the %s falls") % chief_name(sim)
	if sim.chieftain_index() >= 0:
		return TranslationServer.translate("A Roman fort is in sight: slay the %s, then hold it") % chief_name(sim)
	return TranslationServer.translate("A Roman fort is in sight: hold it")

## The sprite drawn inside each target's badge.
const BADGE_ICON := {"camp": "eagle_standard", "grove": "altar", "column": "supply_cart", "fort": "fort_gate"}


## The radius of the dark disc an edge arrow carries its target's picture on.
static func badge_radius() -> float:
	return 14.0 if Ui.scale == 1 else 17.0


## The strip along the bottom of the screen that the arrows keep out of, for the testudo, timber, favour and health bar.
static func bottom_band(view: Vector2) -> float:
	var parts := bottom_layout(view)
	return view.y - minf(parts.bridge.position.y, minf(parts.testudo.position.y, parts.favour.position.y)) + 2.0


## How far an edge arrow's point stands out from its disc.
static func tip_length() -> float:
	return 10.0 if Ui.scale == 1 else 12.0


## The room a badge's centre may stand in so its disc and its pulsing point both stay inside `area`.
static func badge_room(area: Rect2, dir: Vector2) -> Rect2:
	var radius := badge_radius()
	var reach := (radius + tip_length() * 1.15 + 3.0) * dir
	var lo := Vector2(maxf(radius, -reach.x), maxf(radius, -reach.y)) + Vector2.ONE * 3.0
	var hi := Vector2(maxf(radius, reach.x), maxf(radius, reach.y)) + Vector2.ONE * 3.0
	return Rect2(area.position + lo, area.size - lo - hi)


## The middle of the screen, where the legion stands, which the arrows' labels keep out of.
static func centre_keep_out(view: Vector2) -> Rect2:
	return Rect2(view / 2.0 - Vector2(60, 45), Vector2(120, 90))


## Where each target's edge badge and label go, or just its name over it when on screen, every one clear of the others,
## of the middle of the screen and of the `avoid` rects (the bosses' names).
static func arrow_layout(targets: Array, cpos: Vector2, view: Vector2, top: float, metre := 16.0, avoid: Array = []) -> Array:
	var radius := badge_radius()
	var low := bottom_band(view)
	var out: Array = []
	var placed: Array = avoid.duplicate()
	placed.append(centre_keep_out(view))
	# The badges go down first, so the labels written after them step round every badge.
	for t in targets:
		var off: Vector2 = t[1] - cpos
		var extra := {"title": str(t[2]) if t.size() > 2 else "", "unit": str(t[3]) if t.size() > 3 else "", "icon": str(t[4]) if t.size() > 4 else ""}
		if Rect2(Vector2.ZERO, view).grow(-EDGE).has_point(view / 2.0 + off):
			# The chieftain on screen needs no label, since his health bar under the clock names him.
			if t[0] != "chieftain":
				out.append({"kind": t[0], "off": off, "on_screen": true, "badge": Rect2(), "foot": view / 2.0 + off - Vector2(0, LABEL_RISE.get(t[0], 50.0))}.merged(extra))
			continue
		# The badge and its point stay below the top bar and above the bridge hint and the rest of the bottom row.
		var room := badge_room(Rect2(0, top, view.x, view.y - top - low), off.normalized())
		var c := _on_room_edge(room, view / 2.0, off)
		var box := Rect2(c - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
		# A badge that would cover another moves to the nearest clear spot along the edge of the screen.
		c = _clear_spot(room, c, radius, placed)
		box.position = c - Vector2.ONE * radius
		var along := Vector2(0, 1) if absf(c.x - room.position.x) < 0.5 or absf(c.x - room.end.x) < 0.5 else Vector2(1, 0)
		c = box.get_center()
		placed.append(box)
		var dir := off.normalized()
		var tip_at := c + dir * (radius + tip_length() * 0.7)
		placed.append(Rect2(tip_at, Vector2.ZERO).grow(radius * 0.5))
		out.append({"kind": t[0], "off": off, "on_screen": false, "centre": c, "dir": dir, "badge": box, "along": along}.merged(extra))
	for l in out:
		var name: String = l.title if l.title != "" else TranslationServer.translate(_name_key(l.kind)).to_upper()
		var dist := "" if l.on_screen else TranslationServer.translate("%d m") % int(l.off.length() / metre)
		if l.on_screen:
			var nw := Ui.width_at(name, Ui.px)
			l.label = _free_spot(Rect2(l.foot.x - nw / 2.0, l.foot.y - Ui.px, nw, Ui.leading()), placed, view, top, low, 2)
		else:
			var nw := Ui.width_at(name, Ui.px)
			var spot := _beside_badge(l, maxf(nw, Ui.width_at(dist, Ui.px)), 2, placed, view, top, low)
			if spot.is_empty():
				# With no room for two lines beside the badge the name goes alone, as close to the badge as it fits.
				dist = ""
				spot = _beside_badge(l, nw, 1, placed, view, top, low)
			if spot.is_empty():
				var b: Rect2 = l.badge
				l.label = _free_spot(Rect2(b.get_center() - Vector2(nw / 2.0, b.size.y / 2.0 + Ui.leading() + 2.0), Vector2(nw, Ui.leading())), placed, view, top, low, 12, true)
			else:
				placed.append(spot.rect)
				l.label = spot.rect
		l.name = name
		l.dist = dist
	return out


## The point on the edge of `room` nearest `c` where a badge of `radius` covers nothing already placed, or `c` when there is none.
static func _clear_spot(room: Rect2, c: Vector2, radius: float, placed: Array) -> Vector2:
	var spots: Array = [c]
	var edge := 2.0 * (room.size.x + room.size.y)
	var d := 0.0
	while d < edge:
		var x := room.position.x + clampf(d, 0.0, room.size.x) - clampf(d - room.size.x - room.size.y, 0.0, room.size.x)
		var y := room.position.y + clampf(d - room.size.x, 0.0, room.size.y) - clampf(d - 2.0 * room.size.x - room.size.y, 0.0, room.size.y)
		spots.append(Vector2(x, y))
		d += 6.0
	spots.sort_custom(func(a: Vector2, b: Vector2) -> bool: return a.distance_squared_to(c) < b.distance_squared_to(c))
	for p in spots:
		var box := Rect2(p - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)
		var clash := false
		for r in placed:
			clash = clash or r.grow(2.0).intersects(box)
		if not clash:
			return p
	return c


## A spot of `lines` lines right beside an edge badge, along the edge it stands on and on the side its point does not face
## first; empty when no side of the badge is clear.
static func _beside_badge(l: Dictionary, w: float, lines: int, placed: Array, view: Vector2, top: float, low: float) -> Dictionary:
	var b: Rect2 = l.badge
	var c := b.get_center()
	var dir: Vector2 = l.dir
	var h := Ui.leading() * lines
	var gap := 9.0
	var right := Rect2(b.end.x + gap, c.y - h / 2.0, w, h)
	var left := Rect2(b.position.x - gap - w, c.y - h / 2.0, w, h)
	var below := Rect2(c.x - w / 2.0, b.end.y + gap, w, h)
	var above := Rect2(c.x - w / 2.0, b.position.y - gap - h, w, h)
	var tries: Array
	if l.along == Vector2(1, 0):
		tries = [left, right] if dir.x > 0.0 else [right, left]
		tries.append_array([below, above] if dir.y < 0.0 else [above, below])
	else:
		tries = [above, below] if dir.y > 0.0 else [below, above]
		tries.append_array([left, right] if dir.x > 0.0 else [right, left])
	# When every side is taken, the label slides along each side towards a corner of the badge.
	for shift in [0.5, 1.0]:
		for r in tries.slice(0, 4):
			var slide := Vector2(0, (b.size.y / 2.0 + h / 2.0) * shift) if r == left or r == right else Vector2((b.size.x / 2.0 + w / 2.0) * shift, 0)
			tries.append_array([Rect2(r.position + slide, r.size), Rect2(r.position - slide, r.size)])
	for r in tries:
		r.position.x = clampf(r.position.x, 4.0, view.x - r.size.x - 4.0)
		if r.position.y < top or r.end.y > view.y - low:
			continue
		var clash := false
		for p in placed:
			clash = clash or p.intersects(r)
		if not clash:
			return {"rect": r}
	return {}


## Where the line from the middle of the screen towards `off` meets the edge of `room`.
static func _on_room_edge(room: Rect2, centre: Vector2, off: Vector2) -> Vector2:
	var t := INF
	if off.x > 0.0:
		t = (room.end.x - centre.x) / off.x
	elif off.x < 0.0:
		t = (room.position.x - centre.x) / off.x
	if off.y > 0.0:
		t = minf(t, (room.end.y - centre.y) / off.y)
	elif off.y < 0.0:
		t = minf(t, (room.position.y - centre.y) / off.y)
	return (centre + off * t).clamp(room.position, room.end)


## The English name of an objective or the fort, translated where it is drawn.
## The English name of an objective as the HUD shows it, the desert's grove being its sacred well.
static func objective_name(kind: String, sim: Sim) -> String:
	return "Sacred well" if kind == "grove" and sim.objectives.well() else _name_key(kind)


static func _name_key(kind: String) -> String:
	match kind:
		"camp":
			return "Barbarian camp"
		"column":
			return "Stranded column"
		"grove":
			return "Sacred grove"
	return "Roman fort"


## What the edge badges keep off besides the bosses' names: a phone's corners and buttons, or a computer's timber keys.
static func badge_avoid(sim: Sim, view: Vector2, state: String, buttons: Dictionary) -> Array:
	var out: Array = []
	if not Touch.phone and state == "play":
		for spot in timber_key_spots(sim, view.x, view.y):
			out.append(spot[1].grow(2.0))
	if Touch.phone:
		var parts := bottom_layout(view - Touch.inset_tl - Touch.inset_br)
		out = [Rect2(parts.testudo.position + Touch.inset_tl, parts.testudo.size), Rect2(parts.favour.position + Touch.inset_tl, parts.favour.size)]
		for id in buttons:
			out.append(Rect2(buttons[id].centre - Vector2.ONE * buttons[id].radius, Vector2.ONE * buttons[id].radius * 2.0).grow(3.0))
	return out


## Badges at the screen's edge pointing to each objective not yet done and to the fort, and a notice when one is done.
func _objective_arrows(sim: Sim, avoid: Array) -> void:
	var view := Ui.view
	var top := badges_top(sim)
	avoid = avoid + badge_avoid(sim, view, main.state, touch_layout())
	var note: Dictionary = sim.objectives.notice
	var lines: Array = []
	var spot := Rect2()
	if not note.is_empty() and sim.time >= float(note.at) and sim.time - float(note.at) < float(note.get("seconds", sim.b.objectives.notice_seconds)):
		lines = Ui.lines_of(_notice_text(note.kind, sim).to_upper(), view.x - 24.0)
		var nw := 0.0
		for line in lines:
			nw = maxf(nw, Ui.width_at(line, Ui.px))
		var h := Ui.leading() * lines.size()
		spot = Rect2((view.x - nw) / 2.0, minf(view.y * 0.7 - Ui.px, view.y - bottom_band(view) - h - 2.0), nw, h)
		# The notice keeps its place under the legion and the badges and labels step round it.
		avoid = avoid + [spot]
	var laid := arrow_layout(targets_of(sim), sim.commander.pos, view, top, float(sim.b.objectives.metre_px), avoid)
	var atlas: Atlas = main.world.atlas
	var radius := badge_radius()
	# The point pulses so it catches the eye at the edge of a busy screen.
	var reach := tip_length() * (1.0 + 0.15 * sin(sim.time * 5.0))
	for l in laid:
		if not l.on_screen:
			_badge(l, atlas, radius, reach, sim.time)
	for k in lines.size():
		text(lines[k], Vector2(spot.position.x, spot.position.y + Ui.px + Ui.leading() * k), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, spot.size.x)
	for l in laid:
		var r: Rect2 = l.label
		if l.on_screen:
			text(l.name, Vector2(r.position.x, r.position.y + Ui.px), GOLD_LIGHT)
			continue
		if r.size.x == 0.0:
			continue
		draw_rect(r.grow(2.0), Color(0.08, 0.05, 0.04, 0.55))
		text(l.name, Vector2(r.position.x, r.position.y + Ui.px), GOLD_LIGHT if l.kind != "fort" and l.kind != "chieftain" else CREAM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		text(l.dist, Vector2(r.position.x, r.position.y + Ui.px + Ui.leading()), CREAM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## One edge badge: a thick outlined arrow head pointing at the target, and a bright ringed disc carrying its picture.
func _badge(l: Dictionary, atlas: Atlas, radius: float, reach: float, now: float) -> void:
	var c: Vector2 = l.centre
	var dir: Vector2 = l.dir
	var fort: bool = l.kind == "fort" or l.kind == "chieftain"
	var rim := Color(0.86, 0.22, 0.16) if fort else GOLD
	var bright := Color(1.0, 0.55, 0.42) if fort else Color(1.0, 0.95, 0.62)
	var side := dir.orthogonal()
	var tip := c + dir * (radius + reach)
	var base := c + dir * (radius * 0.55)
	var half := radius * 0.7
	var head := PackedVector2Array([tip, base + side * half, base - side * half])
	# A dark shadow under the whole badge lifts it off the grass.
	draw_colored_polygon(PackedVector2Array([tip + Vector2(2, 2), base + side * half + Vector2(2, 2), base - side * half + Vector2(2, 2)]), Color(0, 0, 0, 0.35))
	draw_circle(c + Vector2(2, 2), radius + 1.0, Color(0, 0, 0, 0.35))
	var outline := PackedVector2Array([tip + dir * 2.5, base + side * (half + 2.5) - dir * 1.5, base - side * (half + 2.5) - dir * 1.5])
	draw_colored_polygon(outline, INK)
	draw_colored_polygon(head, rim)
	draw_colored_polygon(PackedVector2Array([tip - dir * 3.0, base + side * half * 0.45 + dir * 2.0, base + dir * 2.0]), bright)
	var glow := 0.5 + 0.5 * sin(now * 5.0)
	draw_circle(c, radius + 2.5, Color(rim, 0.2 + 0.2 * glow))
	draw_circle(c, radius + 1.0, INK)
	draw_circle(c, radius, rim)
	draw_arc(c, radius - 0.5, PI * 1.05, PI * 1.7, 10, bright, 1.0)
	draw_circle(c, radius - 2.0, INK)
	draw_circle(c, radius - 3.0, Color(0.2, 0.14, 0.1))
	draw_circle(c, radius - 7.0, Color(0.26, 0.19, 0.13))
	var unit: String = l.get("unit", "")
	if atlas != null and unit != "" and atlas.units.has(unit):
		# The chieftain's badge carries the man himself, facing out of the disc.
		var uf: Rect2 = atlas.unit_frame(unit, "idle" if atlas.units[unit].has("idle") else "move", "south", 0.0)[0]
		var room := (radius - 3.0) * 2.0
		var uk := minf(room / uf.size.x, room / uf.size.y)
		var usize := (uf.size * uk).round()
		draw_texture_rect_region(atlas.texture, Rect2((c - usize / 2.0).round(), usize), uf)
		return
	var key: String = l.icon if l.get("icon", "") != "" else BADGE_ICON.get(l.kind, "")
	if atlas != null and atlas.props.has(key):
		var f: Rect2 = atlas.prop_frame(key)[0]
		var inner := (radius - 4.0) * 2.0
		var k := minf(inner / f.size.x, inner / f.size.y)
		var size := (f.size * k).round()
		draw_texture_rect_region(atlas.texture, Rect2((c - size / 2.0).round(), size), f)


## Moves a label to the nearest free spot within `reach` steps; with none free it stays put, or with `or_none` becomes an empty rect.
static func _free_spot(r: Rect2, placed: Array, view: Vector2, top: float, low := 4.0, reach := 6, or_none := false) -> Rect2:
	r.position.x = clampf(r.position.x, 4.0, view.x - r.size.x - 4.0)
	r.position.y = clampf(r.position.y, top, view.y - r.size.y - low)
	var tries: Array = []
	var step := Vector2(r.size.x / 2.0 + 4.0, r.size.y + 2.0)
	for dx in range(-mini(reach, 4), mini(reach, 4) + 1):
		for dy in range(-reach, reach + 1):
			tries.append(Vector2(dx, dy))
	tries.sort_custom(func(a: Vector2, b: Vector2) -> bool: return (a * step).length_squared() < (b * step).length_squared())
	for d in tries:
		var tried := r
		tried.position += d * step
		if tried.position.x < 4.0 or tried.end.x > view.x - 4.0 or tried.position.y < top or tried.end.y > view.y - low:
			continue
		var clash := false
		for p in placed:
			clash = clash or p.intersects(tried)
		if not clash:
			placed.append(tried)
			return tried
	if or_none:
		return Rect2()
	placed.append(r)
	return r


## The choices as rows stacked down the middle of the screen, as their rects.
static func choice_rows(n: int, big: bool) -> Array:
	if big:
		return big_layout(n, Ui.view, Touch.inset_tl, Touch.inset_br, Touch.phone, Touch.fingertip).rows
	var out: Array = []
	for i in n:
		out.append(Rect2((W - ROW_W) / 2.0, ROW_TOP + i * ((ROW_H3 if n <= 3 else ROW_H4) + ROW_GAP), ROW_W, ROW_H3 if n <= 3 else ROW_H4))
	return out


## Large text on a screen of `view` with insets `tl` and `br`, in the centred box's coordinates: the rows, their icon side and lines of description, the testudo's and favour's corners they keep clear of, and a phone's buttons (one of three, centred, as `buttons`) or a computer's key hint line (`hint_y`). A phone's buttons sit between the corners when three fit there, and above them otherwise.
static func big_layout(n: int, view: Vector2, tl: Vector2, br: Vector2, phone: bool, tip: float) -> Dictionary:
	var safe := Rect2(tl - ((view - Vector2(W, H)) / 2.0).floor(), view - tl - br)
	var top := safe.position.y + 16.0 + 8.0 * Ui.scale - Ui.px + Ui.leading() + 4.0
	var left := Rect2(safe.position.x + 8.0, safe.end.y - 42.0, 34.0, 42.0)
	var right := Rect2(safe.end.x - 42.0, safe.end.y - 42.0, 34.0, 42.0)
	var corner_top := left.position.y
	var out := {"corners": [left, right]}
	var cx := safe.get_center().x
	var foot: float
	if phone:
		var h := clampf(tip, 30.0, 38.0)
		var half := minf(cx - left.end.x, right.position.x - cx) - 8.0
		var w := minf(BIG_BUTTON_W, floorf((2.0 * half - 16.0) / 3.0))
		var y := safe.end.y - 4.0 - h
		if w < BIG_BUTTON_LOW:
			w = minf(BIG_BUTTON_W, floorf((safe.size.x - 32.0) / 3.0))
			y = corner_top - 4.0 - h
		out.buttons = Rect2(cx - w / 2.0, y, w, h)
		foot = minf(corner_top, y) - 4.0
	else:
		out.hint_y = corner_top - 6.0
		foot = out.hint_y - Ui.px - 6.0
		# The mouse's reroll and banish buttons sit low between the corners, under the key hint.
		var bh := 24.0
		var room := minf(cx - left.end.x, right.position.x - cx) - 8.0
		var bw := minf(BIG_BUTTON_W, floorf(room - 4.0))
		out.buttons = Rect2(cx - bw / 2.0, safe.end.y - 4.0 - bh, bw, bh)
	var room := foot - top
	var rh := minf(BIG_ROW_H, floorf((room - (n - 1) * BIG_ROW_GAP) / n))
	var rw := minf(BIG_ROW_W, safe.size.x - 16.0)
	var x := safe.position.x + floorf((safe.size.x - rw) / 2.0)
	var y0 := top + floorf((room - n * rh - (n - 1) * BIG_ROW_GAP) / 2.0)
	var rows: Array = []
	for i in n:
		rows.append(Rect2(x, y0 + i * (rh + BIG_ROW_GAP), rw, rh))
	out.rows = rows
	out.icon = big_icon(rh)
	out.lines = row_lines(rows[0], true) if n > 0 else 0
	return out


## The largest icon a large row of height `h` holds with room around it.
static func big_icon(h: float) -> float:
	for side in BIG_ICONS:
		if side + 12.0 <= h:
			return side
	return BIG_ICONS[-1]


## The height of a capital above its line at the text size.
static func big_glyph() -> float:
	return roundf(Ui.px * BIG_GLYPH)


## Where a row's name, level and description are written: right of its icon, inside its margin.
static func row_text(r: Rect2, big: bool) -> Rect2:
	var left := 8.0 + big_icon(r.size.y) + 10.0 if big else 8.0 + ROW_ICON + 8.0
	return Rect2(r.position.x + left, r.position.y, r.size.x - left - 8.0, r.size.y)


## The baseline of a normal row's name and level, and of the first line of its description under them.
static func row_name_y(r: Rect2) -> float:
	return r.position.y + 4.0 + Ui.px


static func row_text_y(r: Rect2) -> float:
	return row_name_y(r) + Ui.leading() + 2.0


## How many lines of description a row holds under its name, the last one clear of its foot.
static func row_lines(r: Rect2, big := false) -> int:
	if big:
		return floori((r.size.y - 2.0 * BIG_ROW_PAD - big_glyph()) / Ui.leading())
	return floori((r.end.y - 4.0 - row_text_y(r)) / Ui.leading()) + 1


## The build panel's room, taller than the level-up's rows; large text shows it only on the pause screen, where it is wider and starts below the larger top bar.
static func build_rect() -> Rect2:
	# On a phone the top bar keeps in from the camera and the corners, so the panel starts lower to stay clear of the level.
	var top := maxf(BUILD_TOP + (10.0 if Ui.scale > 1 else 0.0), 16.0 + 8.0 * Ui.scale + Touch.inset_tl.y + 4.0 - Ui.offset.y)
	return Rect2(BUILD_X, top, BUILD_W_BIG if Ui.scale > 1 else BUILD_W, BUILD_FOOT - top)


## The build panel sits beside a level-up's rows at the normal text size; large text needs the whole width, and the gods' and the supply cart's choices are not about the build.
static func shows_build(other: bool, big: bool) -> bool:
	return not other and not big


## The legion's build as [part, [[id, count or rank, most ranks], ...]]: every kind of soldier, then every arm with the forged ones after, then every drill, with none for one not yet taken.
static func build_sections(sim: Sim) -> Array:
	var parts := {"soldiers": [], "arms": [], "drills": []}
	for kind in ["recruits", "arms", "forged", "drills"]:
		var group: Dictionary = sim.content.get(kind)
		for id in group:
			if not group[id].get("implemented", false) or not sim.content.ready(kind, id):
				continue
			if kind == "recruits":
				parts.soldiers.append([id, sim.count(id), 0])
			else:
				parts["drills" if kind == "drills" else "arms"].append([id, sim.rank(id), int(group[id].max)])
	return [["soldiers", parts.soldiers], ["arms", parts.arms], ["drills", parts.drills]].filter(func(part: Array) -> bool: return not part[1].is_empty())


## Where each piece of the build panel goes inside `r`, as [kind, rect, id, number, most, icon side]: a soldier's icon with his count under it, an arm or drill's icon with its rank in pips under it, and a line between the parts; the icons are as large as lets everything fit.
static func build_items(sim: Sim, r: Rect2) -> Array:
	var items: Array = []
	for side in BUILD_ICONS:
		items = _build_items_at(sim, r, side)
		if items.is_empty() or items[-1][1].end.y <= r.end.y - BUILD_PAD:
			break
	return items


static func _build_items_at(sim: Sim, r: Rect2, side: float) -> Array:
	var items: Array = []
	var inner := r.size.x - 2.0 * BUILD_PAD
	var y := r.position.y + BUILD_PAD
	for sec in build_sections(sim):
		if not items.is_empty():
			items.append(["line", Rect2(r.position.x + BUILD_PAD, y + 1.0, inner, 1.0), "", 0, 0, 0])
			y += 4.0
		var soldiers: bool = sec[0] == "soldiers"
		var cell := Vector2(maxf(side, Ui.width_at("100", Ui.px)) + 2.0, side + Ui.px + 3.0) if soldiers else Vector2(side + 2.0, side + 4.0)
		var per_row := maxi(1, floori((inner + 2.0) / cell.x))
		var list: Array = sec[1]
		# Each part's grid is centred across the panel, so a short last row does not leave the panel lopsided.
		var x0 := r.position.x + BUILD_PAD + floorf((inner - (mini(per_row, list.size()) * cell.x - 2.0)) / 2.0)
		for k in list.size():
			var e: Array = list[k]
			var at := Vector2(x0 + (k % per_row) * cell.x, y + (k / per_row) * cell.y)
			items.append(["soldier" if soldiers else "rank", Rect2(at, cell - Vector2(2.0, 1.0)), e[0], e[1], e[2], side])
		y += ceili(float(list.size()) / per_row) * cell.y
	return items


## The legion's soldiers, arms and drills on a dark plate, so a choice can be made knowing what the legion already has.
func draw_build(sim: Sim, r: Rect2) -> void:
	draw_rect(r, Color(0.08, 0.05, 0.04, 0.7))
	draw_rect(r, Color(GOLD, 0.6), false, 1.0)
	for it in build_items(sim, r):
		var at: Vector2 = it[1].position
		if it[0] == "line":
			draw_rect(it[1], Color(GOLD, 0.45))
			continue
		# What the legion has none of yet is shown faded, so the whole set reads at a glance.
		var none: bool = int(it[3]) == 0
		var side := float(it[5])
		var cell: Rect2 = it[1]
		var icon := icon_of(it[2])
		if icon != null:
			draw_texture_rect(icon, Rect2(Vector2(at.x + floorf((cell.size.x - side) / 2.0), at.y), Vector2(side, side)), false, Color(1, 1, 1, 0.35) if none else Color.WHITE)
		if it[0] == "soldier":
			text(str(it[3]), Vector2(at.x, at.y + side + Ui.px), MUTED if none else CREAM, HORIZONTAL_ALIGNMENT_CENTER, cell.size.x)
			continue
		var pips := int(it[4])
		var px0 := at.x + floorf((cell.size.x - (pips * 3.0 - 1.0)) / 2.0)
		for k in pips:
			draw_rect(Rect2(px0 + k * 3.0, at.y + side + 1.0, 2.0, 2.0), GOLD if k < int(it[3]) else PIP_DARK)


func _choices(sim: Sim) -> void:
	if main.choices.is_empty():
		return
	var big := Ui.scale > 1
	draw_set_transform(Ui.offset)
	Ui.veil(self, 0.5)
	var praying: bool = main.state == "pray"
	var supply: bool = main.state == "supply"
	var n: int = main.choices.size()
	var lay := big_layout(n, Ui.view, Touch.inset_tl, Touch.inset_br, Touch.phone, Touch.fingertip) if big else {}
	var rows: Array = lay.rows if big else choice_rows(n, false)
	if shows_build(praying or supply, big):
		draw_build(sim, build_rect())
	var side_panel := shows_choice_panel(praying or supply, big)
	if side_panel:
		draw_choice_panel(sim, main.choices[clampi(main.selected, 0, n - 1)])
	# With large text the heading takes the clock's place in the top bar, which already says the level.
	var head_y := Touch.inset_tl.y + 16.0 + 8.0 * Ui.scale - Ui.offset.y if big else ROW_TOP - 22.0
	if praying:
		ui.fit_text(self, tr("The gods hear you").to_upper(), 300.0 if big else W - 16.0, Vector2(0, head_y), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W, true)
	elif supply or not big or sim.pending_levels == 0:
		ui.fit_text(self, (tr("Level %d") % sim.level if sim.pending_levels > 0 and not supply else tr("Supplies")).to_upper(), 300.0 if big else W - 16.0, Vector2(0, head_y), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W, true)
	if not big:
		text(tr("Call one") if praying else tr("Choose one"), Vector2(0, ROW_TOP - 10.0), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W)
	choice_rects.clear()
	# The row under the mouse lights up, but only a click picks it out.
	var under := -1
	if not Touch.phone:
		var mouse := get_local_mouse_position() - Ui.offset
		for i in n:
			if rows[i].has_point(mouse):
				under = i
	for i in n:
		var id: String = main.choices[i]
		var r: Rect2 = rows[i]
		choice_rects.append(r)
		var picked: bool = i == main.selected
		if picked:
			draw_rect(r.grow(3), GOLD)
		panel(r, CREAM if picked or i == under else PARCH)
		var info: Dictionary = sim.content.gods[id] if praying else (supply_row(sim, id) if supply else sim.content.upgrade(id))
		var icon := supply_icon(id) if supply else icon_of(id)
		var side: float = lay.icon if big else ROW_ICON
		if icon != null:
			draw_texture_rect(icon, Rect2(r.position.x + 8.0, roundf(r.get_center().y - side / 2.0), side, side), false)
		var area := row_text(r, big)
		var words := _description(sim, id, praying)
		var right := tr("God").to_upper() if praying else ("" if supply else Upgrades.level_text(sim, id))
		var name_y: float
		if big:
			var fit := Ui.block(words, area.size.x, lay.lines)
			var used := mini(int(fit.lines), int(lay.lines))
			# The name and description sit as one block in the middle of the row beside the icon.
			var tall := big_glyph() + Ui.leading() + (used - 1) * Ui.lead_for(fit.size)
			name_y = r.position.y + floorf((r.size.y - tall) / 2.0) + big_glyph()
			ui.wrap_fit(self, words, Vector2(area.position.x, name_y + Ui.leading()), area.size.x, INK, lay.lines)
		else:
			# A short description leaves lines empty, so the name and text sit in the middle of the row beside the icon.
			var spare := roundf(maxf(0.0, (row_lines(r) - Ui.lines_of(words, area.size.x).size()) * Ui.leading() / 2.0))
			name_y = row_name_y(r) + spare
			wrap_text(words, Vector2(area.position.x, row_text_y(r) + spare), area.size.x, INK)
		text(str(info.name).to_upper(), Vector2(area.position.x, name_y), INK, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
		text(right, Vector2(area.position.x, name_y), BROWN_TEXT if praying else RED, HORIZONTAL_ALIGNMENT_RIGHT, area.size.x, false)
	touch_buttons.clear()
	if Touch.phone:
		if big:
			_touch_choice_buttons(sim, praying, lay.buttons)
		else:
			var w := touch_button_width(3)
			_touch_choice_buttons(sim, praying, Rect2((W - w) / 2.0, rows[-1].end.y + 8.0, w, 24.0))
		return
	var hint_y: float = lay.hint_y if big else rows[-1].end.y + 16.0
	if praying:
		_centred_hint(Controls.hint("gods"), hint_y, CREAM)
		return
	var level := Controls.hint("level")
	var extras: Array = []
	if big and not supply:
		_big_choice_buttons(sim)
	elif not (side_panel or supply):
		if sim.rerolls > 0:
			extras.append(Controls.hint("reroll", sim.rerolls))
		if sim.banishes > 0:
			extras.append(Controls.hint("banish", sim.banishes))
	# Large text has room for one line of hints above the corners, so the rerolls and banishes follow the level's hint on it.
	if big and not extras.is_empty():
		_centred_hint("     ".join([level] + extras), hint_y, CREAM)
		return
	_centred_hint(level, hint_y, CREAM)
	if not extras.is_empty():
		_centred_hint("     ".join(extras), hint_y + 13.0, GOLD_LIGHT)


## A row of buttons under a phone's choice: take or call the one picked out, then reroll and banish, or not now, each the size of `one` and the row centred where it is.
func _touch_choice_buttons(sim: Sim, praying: bool, one: Rect2) -> void:
	var ids: Array = [["call", tr("call")], ["not_now", tr("not now")]] if praying else [["take", tr("take it")]]
	var levelling: bool = main.state == "choose"
	if levelling and sim.rerolls > 0:
		ids.append(["reroll", "%s (%d)" % [tr("reroll"), sim.rerolls]])
	if levelling and sim.banishes > 0:
		ids.append(["banish", "%s (%d)" % [tr("banish"), sim.banishes]])
	var w := one.size.x
	var h := one.size.y
	var row := button_row(ids.map(func(pair: Array) -> String: return pair[0]), one)
	for k in ids.size():
		var r: Rect2 = row[ids[k][0]]
		touch_buttons[ids[k][0]] = r
		if k == 0:
			draw_rect(r.grow(3), GOLD)
		panel(r, CREAM if k == 0 else PARCH)
		ui.fit_text(self, str(ids[k][1]).to_upper(), w - 12.0, Vector2(r.position.x, r.position.y + h / 2.0 + Ui.px * 3 / 8), INK, HORIZONTAL_ALIGNMENT_CENTER, w)


## A row of buttons, one for each id, each the size of `one` and the row centred where `one` is, as {id: rect}.
static func button_row(ids: Array, one: Rect2) -> Dictionary:
	var gap := 8.0
	var x0 := roundf(one.get_center().x - (ids.size() * one.size.x + (ids.size() - 1) * gap) / 2.0)
	var out := {}
	for k in ids.size():
		out[ids[k]] = Rect2(x0 + k * (one.size.x + gap), one.position.y, one.size.x, one.size.y)
	return out


## The reroll and banish buttons under large rows on a computer, for the ones with a use left, as {id: rect}.
static func big_choice_buttons(sim: Sim) -> Dictionary:
	var ids: Array = []
	if sim.rerolls > 0:
		ids.append("reroll")
	if sim.banishes > 0:
		ids.append("banish")
	return button_row(ids, big_layout(3, Ui.view, Touch.inset_tl, Touch.inset_br, false, 0.0).buttons)


## The reroll and banish buttons under large rows on a computer, labelled with their keys as the choice panel's are.
func _big_choice_buttons(sim: Sim) -> void:
	var buttons := big_choice_buttons(sim)
	var over := get_local_mouse_position() - Ui.offset
	for id in buttons:
		var r: Rect2 = buttons[id]
		if r.has_point(over):
			draw_rect(r.grow(2), GOLD)
		panel(r, PARCH)
		ui.fit_text(self, choice_button_label(sim, id), r.size.x - 12.0, Vector2(r.position.x, r.position.y + r.size.y / 2.0 + Ui.px * 3 / 8), INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## The width of each of `n` buttons in the row under a phone's choice at the normal text size.
static func touch_button_width(n: int) -> float:
	return minf(130.0, (W - 32.0 - (n - 1) * 8.0) / n)


## The phone button under a choice at a point, or "".
func touch_button_at(p: Vector2) -> String:
	for id in touch_buttons:
		if touch_buttons[id].has_point(p):
			return id
	return ""


## A supply cart's row for the reward `id`, read from the run as it stands.
static func supply_row(sim: Sim, id: String) -> Dictionary:
	return supply_text(id, sim.legion_health(), sim.c_pos.size())


## A supply cart's row as {name, line}: what the reward is, and a line that tells the state it answers.
static func supply_text(id: String, health: Dictionary, coins: int) -> Dictionary:
	match id:
		"heal":
			return {"name": TranslationServer.translate("Heal the legion"),
				"line": TranslationServer.translate("%d wounded, legion at %d%% health, commander at %d%%") % [health.wounded, health.share, health.commander]}
		"magnet":
			return {"name": TranslationServer.translate("Every coin pulled in"),
				"line": TranslationServer.translate("%d coins lie on the field") % coins}
	return {"name": TranslationServer.translate("A free level-up"), "line": TranslationServer.translate("One more choice of arms, drills or recruits")}


func _description(sim: Sim, id: String, praying: bool) -> String:
	if main.state == "supply":
		return supply_row(sim, id).line
	return str(sim.content.gods[id].text) if praying else Upgrades.describe(sim, id)


func _centred_hint(s: String, y: float, col: Color) -> void:
	ui.fit_text(self, s, W - 16.0, Vector2(0, y), col, HORIZONTAL_ALIGNMENT_CENTER, W, true)


func choice_at(p: Vector2) -> int:
	for i in choice_rects.size():
		if choice_rects[i].has_point(p):
			return i
	return -1



## The panel on the right of a level-up that tells of the choice picked out: the build panel mirrored across the middle of the screen.
static func choice_panel_rect() -> Rect2:
	var left := build_rect()
	return Rect2(W - left.end.x, left.position.y, left.size.x, left.size.y)


## The choice panel shows where the build panel does, except on a phone, whose buttons under the rows do its work.
static func shows_choice_panel(other: bool, big: bool) -> bool:
	return shows_build(other, big) and not Touch.phone


## The reroll and banish buttons at the foot of the choice panel, as {id: rect}, the lower one level with the foot of the build panel.
static func choice_panel_buttons() -> Dictionary:
	var r := choice_panel_rect()
	var w := r.size.x - 2.0 * BUILD_PAD
	var foot := r.end.y - BUILD_PAD
	return {"reroll": Rect2(r.position.x + BUILD_PAD, foot - 2.0 * PANEL_BUTTON_H - PANEL_BUTTON_GAP, w, PANEL_BUTTON_H),
		"banish": Rect2(r.position.x + BUILD_PAD, foot - PANEL_BUTTON_H, w, PANEL_BUTTON_H)}


## A button's words: its key or pad button, what it does and how many are left, as the key hints write them.
static func choice_button_label(sim: Sim, id: String) -> String:
	return Controls.hint(id, sim.rerolls if id == "reroll" else sim.banishes).to_upper()


## The choice panel's button at a point that has a use left, or "".
static func choice_button_at(sim: Sim, p: Vector2) -> String:
	var buttons := choice_panel_buttons()
	for id in buttons:
		if buttons[id].has_point(p) and (sim.rerolls if id == "reroll" else sim.banishes) > 0:
			return id
	return ""


## Where each piece of the choice panel goes inside `r` for the choice `id`, as [kind, rect, ...]: its icon, its name and group, a line, what it does now and next as a name and its numbers, how it forges, another line and its history. Text lines carry their words and look, and numbers their now and next.
static func choice_panel_items(sim: Sim, id: String, r: Rect2) -> Array:
	var room: float = choice_panel_buttons().reroll.position.y - PANEL_BUTTON_GAP
	var items: Array = []
	for each in PANEL_ROOMS:
		items = _choice_panel_at(sim, id, r, each[0], each[1])
		if items[-1][1].end.y <= room:
			break
	return items


static func _choice_panel_at(sim: Sim, id: String, r: Rect2, side: float, gap: float) -> Array:
	var items: Array = []
	var lead := Ui.leading()
	var x := r.position.x + BUILD_PAD + 2.0
	var inner := r.size.x - 2.0 * BUILD_PAD - 4.0
	var y := r.position.y + BUILD_PAD + 2.0
	var info: Dictionary = sim.content.upgrade(id)
	var name := str(info.name).to_upper()
	var group := TranslationServer.translate(sim.content.group_of(id)).to_upper()
	# The name stands beside the icon when it fits in two lines there, and under it, across the panel, when it does not.
	var beside := inner - side - 6.0
	var lines := Ui.lines_of(name, beside)
	var fits := lines.size() <= 2 and Ui.width_at(group, Ui.px) <= beside
	for line in lines:
		fits = fits and Ui.width_at(line, Ui.px) <= beside
	if fits:
		var block := (lines.size() + 1) * lead
		var h := maxf(side, block)
		items.append(["icon", Rect2(x, y + floorf((h - side) / 2.0), side, side), id])
		var ty := y + floorf((h - block) / 2.0)
		for line in lines:
			items.append(["text", Rect2(x + side + 6.0, ty, beside, lead), line, "name"])
			ty += lead
		items.append(["text", Rect2(x + side + 6.0, ty, beside, lead), group, "group"])
		y += h + 3.0 + gap
	else:
		items.append(["icon", Rect2(x + floorf((inner - side) / 2.0), y, side, side), id])
		y += side + 3.0
		for line in Ui.lines_of(name, inner):
			items.append(["text", Rect2(x, y, inner, lead), line, "name"])
			y += lead
		items.append(["text", Rect2(x, y, inner, lead), group, "group"])
		y += lead + 3.0 + gap
	items.append(["line", Rect2(x, y, inner, 1.0)])
	y += 4.0 + gap
	for s in Upgrades.stat_lines(sim, id):
		var vw: float = value_width(s[1], s[2])
		var lw: float = Ui.width_at(s[0], Ui.px)
		# A long name puts its numbers on the line under it, written from the right.
		var two := lw + 6.0 + vw > inner
		items.append(["text", Rect2(x, y, minf(lw, inner) if not two else inner, lead), s[0], "label"])
		if two:
			y += lead
		items.append(["value", Rect2(x + inner - vw, y, vw, lead), s[1], s[2]])
		y += lead + gap / 2.0
	# Closing punctuation in Chinese and Japanese may run one glyph past the width it wraps at, so they wrap that much narrower.
	var wrap: float = inner - (Ui.px if Lang.is_han() else 0.0)
	var forge := Upgrades.forge_lines(sim, id)
	if not forge.is_empty():
		y += 2.0 + gap
		for f in forge:
			for line in Ui.lines_of(f, wrap):
				items.append(["text", Rect2(x, y, inner, lead), line, "forge"])
				y += lead
	var history := str(info.get("history", ""))
	if history != "":
		y += 1.0 + gap
		items.append(["line", Rect2(x, y, inner, 1.0)])
		y += 4.0 + gap
		for line in Ui.lines_of(history, wrap):
			items.append(["text", Rect2(x, y, inner, lead), line, "history"])
			y += lead
	return items


## How wide a stat's numbers are written: now, an arrow and next, or only one of them.
static func value_width(now: String, next: String) -> float:
	if now == "" or next == "":
		return Ui.width_at(now + next, Ui.px)
	return Ui.width_at(now, Ui.px) + ARROW_W + Ui.width_at(next, Ui.px)


## The choice picked out on a dark plate on the right, with the reroll and banish buttons at its foot.
func draw_choice_panel(sim: Sim, id: String) -> void:
	var r := choice_panel_rect()
	draw_rect(r, Color(0.08, 0.05, 0.04, 0.7))
	draw_rect(r, Color(GOLD, 0.6), false, 1.0)
	var colours := {"name": GOLD_LIGHT, "group": MUTED, "label": MUTED, "forge": GOLD, "history": HISTORY}
	for it in choice_panel_items(sim, id, r):
		var at: Rect2 = it[1]
		var base := at.position.y + Ui.px
		match it[0]:
			"icon":
				var icon := icon_of(it[2])
				if icon != null:
					draw_texture_rect(icon, at, false)
			"line":
				draw_rect(at, Color(GOLD, 0.45))
			"text":
				text(it[2], Vector2(at.position.x, base), colours[it[3]], HORIZONTAL_ALIGNMENT_LEFT, -1, it[3] == "name")
			"value":
				var now: String = it[2]
				var next: String = it[3]
				if next == "":
					text(now, Vector2(at.position.x, base), CREAM, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
					continue
				var vx := at.position.x
				if now != "":
					text(now, Vector2(vx, base), CREAM, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
					vx += Ui.width_at(now, Ui.px)
					_arrow(Vector2(vx + ARROW_W / 2.0, at.position.y + floorf(Ui.leading() / 2.0)))
					vx += ARROW_W
				text(next, Vector2(vx, base), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_LEFT, -1, false)
	var buttons := choice_panel_buttons()
	var over := get_local_mouse_position() - Ui.offset
	for b in buttons:
		var br: Rect2 = buttons[b]
		var live := choice_button_at(sim, br.get_center()) != ""
		if live and br.has_point(over):
			draw_rect(br.grow(2), GOLD)
		panel(br, PARCH if live else Color(PARCH_DARK, 0.45))
		text(choice_button_label(sim, b), Vector2(br.position.x, br.position.y + floorf((br.size.y + Ui.px) / 2.0) - 1.0), INK if live else Color(INK, 0.5), HORIZONTAL_ALIGNMENT_CENTER, br.size.x, false)


## A small gold arrow pointing right from a stat's number now to its next.
func _arrow(c: Vector2) -> void:
	for k in 3:
		draw_rect(Rect2(floorf(c.x) - 1.0 + k, floorf(c.y) - 2.0 + k, 1.0, 5.0 - 2.0 * k), GOLD)
