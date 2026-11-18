class_name Hud
extends Node2D
## Everything drawn over the field: the top bar, the testudo charge, the favour of the gods, the chieftain's health and the level-up and god choices.
## The title, pause, summary, settings and camp are screens drawn through the shared Ui.

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
## How far above its foot an objective's name is written when it is on screen, clear of its sprite.
const LABEL_RISE := {"camp": 56.0, "column": 50.0, "grove": 40.0, "fort": 76.0}

var main: Node
var ui: Ui
var icons := {}
var choice_rects: Array = []


## The level-up icon of an id, loaded the first time it is drawn.
func icon_of(id: String) -> Texture2D:
	if not icons.has(id):
		var path := "res://assets/icons/%s.png" % main.sim.content.icon_key(id)
		icons[id] = load(path) if ResourceLoader.exists(path) else null
	return icons[id]


func _process(_dt: float) -> void:
	queue_redraw()


func text(s: String, pos: Vector2, col: Color = CREAM, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, shade := true) -> void:
	if shade:
		draw_string(Ui.font(), pos + Vector2(Ui.scale, Ui.scale), s, align, width, Ui.px, INK)
	draw_string(Ui.font(), pos, s, align, width, Ui.px, col)


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
	var r := Rect2(lerpf(W + 2.0, W - 6.0 - w, slide), 44.0 if not big else 68.0, w, h)
	panel(r)
	_laurel(r.position + Vector2(18.0, h / 2.0))
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
		if main.state == "pause" or main.state == "over":
			_top_bar(sim)
		ui.begin()
		draw_set_transform(Ui.offset)
		main.screens[main.state].draw(self, ui)
		ui.end()
		return
	_top_bar(sim)
	var choosing: bool = main.state == "choose" or main.state == "pray"
	# The boss names and objective badges would sit on the choice's heading and cards, so they wait until it is made.
	if not choosing:
		var bosses := boss_names(sim)
		for b in bosses:
			text(b.name, Vector2(b.rect.position.x, b.rect.position.y + Ui.px), GOLD_LIGHT)
		if sim.triumph_left <= 0.0:
			var avoid: Array = bosses.map(func(b: Dictionary) -> Rect2: return b.rect)
			var chief := chieftain_rect(sim)
			if chief.has_area():
				avoid.append(chief)
			_objective_arrows(sim, avoid)
	_god_banner(sim)
	_victory_banner(sim)
	if choosing:
		_choices(sim)


func _top_bar(sim: Sim) -> void:
	var W := Ui.view.x
	var H := Ui.view.y
	var big := Ui.scale > 1
	draw_rect(Rect2(8, 6, W - 16, 7), INK)
	var fill := (W - 18) * clampf(float(sim.xp) / sim.xp_next, 0.0, 1.0)
	draw_rect(Rect2(9, 7, fill, 5), GOLD)
	draw_rect(Rect2(9, 7, fill, 1), GOLD_LIGHT)
	var secs := int(sim.time)
	var y1 := 16.0 + 8.0 * Ui.scale
	var y2 := y1 + (11.0 if not big else 20.0)
	# A choice on screen keeps only the level and the legion up here; its cards and heading take the rest.
	var choosing: bool = main.state == "choose" or main.state == "pray"
	text((tr("Level %d") % sim.level).to_upper(), Vector2(10, y1))
	if not (choosing and big):
		text("%02d:%02d" % [secs / 60, secs % 60], Vector2(0, y1), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W)
	text((tr("Legion %d") % (sim.soldiers.size() + 1)).to_upper(), Vector2(0, y1), CREAM, HORIZONTAL_ALIGNMENT_RIGHT, W - 10)
	if not choosing:
		text((tr("Kills %d") % sim.kills).to_upper(), Vector2(0, y2), CREAM, HORIZONTAL_ALIGNMENT_RIGHT, W - 10)
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
	text((tr("Testudo") if sim.testudo_left <= 0.0 else tr("Hold!")).to_upper(), Vector2(46, H - 6), GOLD_LIGHT if ready or sim.testudo_left > 0.0 else Color(0.7, 0.66, 0.6))
	_timber(sim, H)
	_favour(sim, W, H)
	if choosing:
		return
	_health(sim)
	_chieftain_line(sim, W, y1, big)


## The chieftain's health under the clock, the time won in endless mode, or the warning that he is coming.
func _chieftain_line(sim: Sim, W: float, y1: float, big: bool) -> void:
	var ci := sim.horde.chieftain_index()
	var y3 := y1 + (11.0 if not big else 22.0)
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
func _timber(sim: Sim, H: float) -> void:
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
	elif sim.palisade_refused_at >= 0.0 and sim.time - sim.palisade_refused_at < float(sim.b.palisade.notice_seconds):
		line = tr("Not enough timber: %d needed") % cost
	if line != "":
		text(line.to_upper(), Vector2(0, Ui.view.y * 0.7), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, Ui.view.x)
	if sim.bridge_here and main.state == "play":
		var hint := bridge_hint(sim.timber, bridge_cost)
		var r: Rect2 = bottom_layout(Ui.view).bridge
		var said := str(hint.text).to_upper()
		var w := Ui.width_at(said, Ui.px)
		draw_rect(Rect2((Ui.view.x - w) / 2.0 - 4.0, r.position.y - 1.0, w + 8.0, r.size.y + 2.0), Color(0.08, 0.05, 0.04, 0.55))
		text(said, Vector2(0, r.position.y + Ui.px), GOLD_LIGHT if hint.enough else MUTED, HORIZONTAL_ALIGNMENT_CENTER, Ui.view.x)


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


## The favour of the gods at the bottom right: a wreath over a bar that fills with kills, glowing with the key to call them once full.
func _favour(sim: Sim, W: float, H: float) -> void:
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
	text(tr("Favour").to_upper(), Vector2(0, H - 6), GOLD_LIGHT if ready else Color(0.7, 0.66, 0.6), HORIZONTAL_ALIGNMENT_RIGHT, W - 46)
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
func _health(sim: Sim) -> void:
	var c: Dictionary = sim.commander
	if c.hp < _last_hp:
		_hit_at = sim.time
	_last_hp = c.hp
	var since := sim.time - _hit_at
	var share := clampf(c.hp / maxf(1.0, c.max_hp), 0.0, 1.0)
	var r: Rect2 = bottom_layout(Ui.view).health
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
func chief_name(sim: Sim) -> String:
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


## The name of the god just called, written large across the screen as his power lands.
func _god_banner(sim: Sim) -> void:
	var last: Dictionary = sim.gods.last
	if last.is_empty() or main.state != "play":
		return
	var age := sim.time - float(last.at)
	var secs := float(sim.b.gods.banner_seconds)
	if age > secs or not sim.content.gods.has(last.id):
		return
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


func _notice_text(kind: String, sim: Sim) -> String:
	match kind:
		"camp":
			return tr("The eagle is ours again")
		"column":
			return tr("The column joins the legion")
		"grove":
			return tr("The sacred grove burns")
		"chieftain":
			return tr("The %s falls: now hold the fort") % chief_name(sim)
		"roar":
			return tr("The %s roars in fury") % chief_name(sim)
		"ravine":
			return tr("Fell trees for timber, then bridge the ravine at its edge")
	return tr("A Roman fort is in sight: hold it")


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
		if Rect2(Vector2.ZERO, view).grow(-EDGE).has_point(view / 2.0 + off):
			out.append({"kind": t[0], "off": off, "on_screen": true, "badge": Rect2(), "foot": view / 2.0 + off - Vector2(0, LABEL_RISE.get(t[0], 50.0))})
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
		out.append({"kind": t[0], "off": off, "on_screen": false, "centre": c, "dir": dir, "badge": box, "along": along})
	for l in out:
		var name := TranslationServer.translate(_name_key(l.kind)).to_upper()
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
static func _name_key(kind: String) -> String:
	match kind:
		"camp":
			return "Barbarian camp"
		"column":
			return "Stranded column"
		"grove":
			return "Sacred grove"
	return "Roman fort"


## Badges at the screen's edge pointing to each objective not yet done and to the fort, and a notice when one is done.
func _objective_arrows(sim: Sim, avoid: Array) -> void:
	var view := Ui.view
	var big := Ui.scale > 1
	var top := 16.0 + 8.0 * Ui.scale + (22.0 if big else 11.0)
	# The chieftain's name and health bar run under the clock, so the badges start below them.
	if sim.horde.chieftain_index() >= 0:
		top += 12.0
	var note: Dictionary = sim.objectives.notice
	var lines: Array = []
	var spot := Rect2()
	if not note.is_empty() and sim.time - float(note.at) < float(note.get("seconds", sim.b.objectives.notice_seconds)):
		lines = Ui.lines_of(_notice_text(note.kind, sim).to_upper(), view.x - 24.0)
		var nw := 0.0
		for line in lines:
			nw = maxf(nw, Ui.width_at(line, Ui.px))
		var h := Ui.leading() * lines.size()
		spot = Rect2((view.x - nw) / 2.0, minf(view.y * 0.7 - Ui.px, view.y - bottom_band(view) - h - 2.0), nw, h)
		# The notice keeps its place under the legion and the badges and labels step round it.
		avoid = avoid + [spot]
	var laid := arrow_layout(sim.objectives.targets(), sim.commander.pos, view, top, float(sim.b.objectives.metre_px), avoid)
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
		text(l.name, Vector2(r.position.x, r.position.y + Ui.px), GOLD_LIGHT if l.kind != "fort" else CREAM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
		text(l.dist, Vector2(r.position.x, r.position.y + Ui.px + Ui.leading()), CREAM, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)


## One edge badge: a thick outlined arrow head pointing at the target, and a bright ringed disc carrying its picture.
func _badge(l: Dictionary, atlas: Atlas, radius: float, reach: float, now: float) -> void:
	var c: Vector2 = l.centre
	var dir: Vector2 = l.dir
	var fort: bool = l.kind == "fort"
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
	var key: String = BADGE_ICON.get(l.kind, "")
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


func _choices(sim: Sim) -> void:
	if main.choices.is_empty():
		return
	var big := Ui.scale > 1
	draw_set_transform(Ui.offset)
	Ui.veil(self, 0.5)
	# With large text the heading takes the clock's place in the top bar, which already says the level.
	var head_y := 16.0 + 8.0 * Ui.scale if big else 74.0
	var praying: bool = main.state == "pray"
	if praying:
		ui.fit_text(self, tr("The gods hear you").to_upper(), 300.0 if big else W - 16.0, Vector2(0, head_y), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W, true)
	elif not big or sim.pending_levels == 0:
		ui.fit_text(self, (tr("Level %d") % sim.level if sim.pending_levels > 0 else tr("Supplies")).to_upper(), 300.0 if big else W - 16.0, Vector2(0, head_y), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W, true)
	if not big:
		text(tr("Call one") if praying else tr("Choose one"), Vector2(0, 86), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W)
	choice_rects.clear()
	var n: int = main.choices.size()
	var gap := 8.0 if n > 3 else 12.0
	var bw := minf(176.0 if not big else 200.0, (W - 24.0 - (n - 1) * gap) / n)
	var x0 := (W - n * bw - (n - 1) * gap) / 2.0
	var top := 44.0 if big else 100.0
	var card_h := 236.0 if big else 170.0
	var icon_px := 40.0 if big else 64.0
	var step := 20.0 if big else 11.0
	for i in n:
		var id: String = main.choices[i]
		var r := Rect2(x0 + i * (bw + gap), top, bw, card_h)
		choice_rects.append(r)
		var picked: bool = i == main.selected
		if picked:
			draw_rect(r.grow(3), GOLD)
		panel(r, CREAM if picked else PARCH)
		var info: Dictionary = sim.content.gods[id] if praying else sim.content.upgrade(id)
		var icon := icon_of(id)
		if icon != null:
			draw_texture_rect(icon, Rect2(r.position.x + bw / 2 - icon_px / 2, r.position.y + 8, icon_px, icon_px), false)
		var y := r.position.y + (icon_px + 22.0 if big else 86.0)
		ui.fit_text(self, (tr("God") if praying else tr(sim.content.group_of(id))).to_upper(), bw - 8, Vector2(r.position.x, y), Color(0.5, 0.36, 0.22), HORIZONTAL_ALIGNMENT_CENTER, bw)
		# A long name takes two lines, and the level and description move down by the extra one.
		var shown := mini(Ui.block(info.name.to_upper(), bw - 8, 2).lines, 2)
		ui.wrap_fit(self, info.name.to_upper(), Vector2(r.position.x, y + step + 1), bw - 8, INK, 2, HORIZONTAL_ALIGNMENT_CENTER, bw)
		var extra_y := (shown - 1) * step
		if praying:
			wrap_text(info.text, Vector2(r.position.x + 9, y + 2 * step + 6 + extra_y), bw - 18, INK)
			continue
		text(Upgrades.level_text(sim, id), Vector2(r.position.x, y + 2 * step + 2 + extra_y), RED, HORIZONTAL_ALIGNMENT_CENTER, bw, false)
		wrap_text(Upgrades.describe(sim, id), Vector2(r.position.x + 9, y + 3 * step + 6 + extra_y), bw - 18, INK)
	var hint_y := top + card_h + (20.0 if big else 16.0)
	if praying:
		ui.fit_text(self, Controls.hint("gods"), W - 16.0, Vector2(0, hint_y), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W, true)
		return
	ui.fit_text(self, Controls.hint("level"), W - 16.0, Vector2(0, hint_y), CREAM, HORIZONTAL_ALIGNMENT_CENTER, W, true)
	var extras: Array = []
	if sim.rerolls > 0:
		extras.append(Controls.hint("reroll", sim.rerolls))
	if sim.banishes > 0:
		extras.append(Controls.hint("banish", sim.banishes))
	if not extras.is_empty():
		ui.fit_text(self, "     ".join(extras), W - 16.0, Vector2(0, hint_y + (20.0 if big else 13.0)), GOLD_LIGHT, HORIZONTAL_ALIGNMENT_CENTER, W, true)


func choice_at(p: Vector2) -> int:
	for i in choice_rects.size():
		if choice_rects[i].has_point(p):
			return i
	return -1


## Where the arrow to a target `off` from the screen centre stands, on the edge of the room below `top`, or INF when it is on screen.
static func edge_point(view: Vector2, off: Vector2, top: float) -> Vector2:
	var room := Rect2(EDGE, top, view.x - 2.0 * EDGE, view.y - top - EDGE)
	var centre := view / 2.0
	if room.has_point(centre + off):
		return Vector2.INF
	var t := INF
	if off.x > 0.0:
		t = (room.end.x - centre.x) / off.x
	elif off.x < 0.0:
		t = (room.position.x - centre.x) / off.x
	if off.y > 0.0:
		t = minf(t, (room.end.y - centre.y) / off.y)
	elif off.y < 0.0:
		t = minf(t, (room.position.y - centre.y) / off.y)
	return centre + off * t
