class_name SavesScreen
extends RefCounted
## The load list: one row for each of the three save slots, saying what game is in it, with Play and Delete, and a question before a game is deleted
## that is answered by typing the word "delete", as in the other Slow Sunday games, so no stray press can delete a game.

## How long a gamepad, which cannot type the word, holds confirm on Delete to delete a game.
const HOLD_SECONDS := 2.0

var main: Node
## The slot whose deletion is being asked about, or 0.
var confirming := 0
## What has been typed into the question so far.
var typed := ""
## How long confirm has been held on Delete.
var held := 0.0


func _init(owner_node: Node) -> void:
	main = owner_node


func activate(id: String) -> void:
	var parts := id.split(":")
	match parts[0]:
		"play":
			if Profile.load_slot(int(parts[1])):
				main.use_profile()
				main.go_to_camp()
		"delete":
			confirming = int(parts[1])
			typed = ""
			held = 0.0
			# The question opens on Cancel, so a second press of the confirm key never deletes a game.
			main.ui.focus = "no"
			_keyboard(true)
		"field":
			_keyboard(true)
		"no":
			back()
		"yes":
			if word_typed():
				_delete(confirming)


## Deletes the game once a gamepad has held confirm on Delete for HOLD_SECONDS; letting go starts the hold again.
func hold(dt: float, pressed: bool, focus: String) -> void:
	if confirming == 0 or not Controls.pad_in_use or not pressed or focus != "yes":
		held = 0.0
		return
	held += dt
	if held >= HOLD_SECONDS:
		held = 0.0
		_delete(confirming)


## Shows or hides a phone's own keyboard for the word.
func _keyboard(up: bool) -> void:
	if not Touch.phone or not DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		return
	if up:
		DisplayServer.virtual_keyboard_show(typed, Rect2(), DisplayServer.KEYBOARD_TYPE_DEFAULT, 20)
	else:
		DisplayServer.virtual_keyboard_hide()


## Whether the word that deletes a game has been typed; the English word works in every language too, for a keyboard that cannot easily type the translated one.
func word_typed() -> bool:
	return typed.strip_edges().to_lower() in [tr("delete").to_lower(), "delete"]


## Takes every key pressed while the question is open, so letters go into the word and never move the menu; returns true when the event was used.
func capture(event: InputEvent) -> bool:
	if confirming == 0 or not event is InputEventKey or not event.pressed:
		return false
	match event.keycode:
		KEY_ESCAPE:
			if not event.echo:
				Audio.play("back")
				back()
		KEY_BACKSPACE:
			typed = typed.left(-1)
		KEY_ENTER, KEY_KP_ENTER:
			if not event.echo and word_typed():
				_delete(confirming)
		_:
			if event.unicode >= 32 and typed.length() < 20:
				typed += char(event.unicode)
	return true


## Leaves the question for the list, or the list for the title; false when the screen itself should close.
func back() -> bool:
	if confirming == 0:
		return false
	main.ui.focus = "delete:%d" % confirming
	confirming = 0
	_keyboard(false)
	return true


func _delete(n: int) -> void:
	confirming = 0
	_keyboard(false)
	Profile.delete_slot(n)
	# With the open game deleted, Continue goes on to the game saved last of those left.
	if Profile.slot == 0 and Profile.load_slot(Profile.latest_slot()):
		main.use_profile()
	if not range(1, Profile.SLOTS + 1).any(Profile.slot_taken):
		main.go_to_title("new")
		return
	main.ui.focus = ""


## A slot's game in two lines: the provinces won of those this build can play, and the denarii.
static func summary(info: Dictionary, content: Content, balance: Dictionary) -> Array:
	var playable: Array = content.provinces.keys().filter(func(p: String) -> bool: return content.ready("provinces", p) and Game.province_allowed(p, balance))
	var won: int = playable.filter(func(p: String) -> bool: return info.won.has(p)).size()
	return [TranslationServer.translate("{won} of {total} provinces won").format({"won": won, "total": playable.size()}),
		TranslationServer.translate("%d denarii") % int(info.denarii)]


## When a slot was last saved, as the day on this computer's clock.
static func played_on(saved_at: float) -> String:
	var local := int(saved_at) + int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var d := Time.get_datetime_dict_from_unix_time(local)
	return TranslationServer.translate("Last played %s") % ("%04d-%02d-%02d" % [d.year, d.month, d.day])


func draw(c: CanvasItem, ui: Ui) -> void:
	if confirming > 0:
		_draw_question(c, ui)
		return
	var r := ui.frame(c, tr("Load a game").to_upper(), Controls.hint("pick"))
	var top := r.position.y + Ui.below_title()
	var h := (r.end.y - 6.0 - top) / Profile.SLOTS - 4.0
	var bw := 110.0 if Ui.scale == 1 else 150.0
	var bh := 24.0 if Ui.scale == 1 else 30.0
	for n in range(1, Profile.SLOTS + 1):
		var row := Rect2(r.position.x + 12.0, top + (n - 1) * (h + 4.0), r.size.x - 24.0, h)
		ui.panel(c, row)
		var room := row.size.x - bw - 24.0
		var x0 := row.position.x + 8.0
		var y := row.position.y + 8.0 + 8.0 * Ui.scale
		var name := (tr("Slot %d") % n).to_upper()
		ui.text(c, name, Vector2(x0, y), Ui.BROWN)
		if not Profile.slot_taken(n):
			ui.text(c, tr("Empty"), Vector2(x0, y + Ui.leading()), Ui.MUTED)
			continue
		var info := Profile.slot_info(n)
		if info.is_empty():
			ui.fit_text(c, tr("This game could not be read."), room, Vector2(x0, y + Ui.leading()), Ui.RED)
		else:
			var newer: bool = info.get("newer", false)
			var when := tr("Saved by a newer version") if newer else played_on(float(info.saved_at))
			ui.fit_text(c, when, room - Ui.width_at(name, Ui.px) - 16.0, Vector2(0, y), Ui.RED if newer else Ui.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, x0 + room)
			var lines := summary(info, main.content, main.balance)
			for i in lines.size():
				ui.fit_text(c, lines[i], room, Vector2(x0, y + (i + 1) * Ui.leading()), Ui.INK)
		var x := row.end.x - bw - 8.0
		var mid := row.get_center().y
		ui.button(c, Rect2(x, mid - bh - 2.0, bw, bh), "play:%d" % n, tr("Play").to_upper(), "", not info.is_empty() and not info.get("newer", false), null, true)
		ui.button(c, Rect2(x, mid + 2.0, bw, bh), "delete:%d" % n, tr("Delete").to_upper(), "", true, null, true)


## Asks before a game is deleted, saying what is in it, since a deleted game cannot be brought back.
func _draw_question(c: CanvasItem, ui: Ui) -> void:
	var pad := Controls.pad_in_use and not Touch.phone
	var r := ui.frame(c, tr("Delete a game").to_upper(), Controls.hint("hold" if pad else "type"))
	var info := Profile.slot_info(confirming)
	var said: Array = summary(info, main.content, main.balance) if not info.is_empty() else [tr("This game could not be read.")]
	if pad:
		said.append(tr("It will be gone for good. Hold the Delete button to delete it."))
	else:
		said.append(tr("It will be gone for good. Type \"%s\" to delete it.") % tr("delete"))
	var width := r.size.x - 80.0
	var bh := 24.0 if Ui.scale == 1 else 30.0
	if Touch.phone:
		_draw_touch_question(c, ui, r, said, bh)
		return
	var y := r.get_center().y - ((said.size() + 1) * Ui.leading() + 30.0 + 2.0 * bh) / 2.0 + Ui.px
	ui.text(c, (tr("Delete slot %d?") % confirming).to_upper(), Vector2(r.position.x, y), Ui.BROWN, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	y += 6.0
	for i in said.size():
		y += Ui.leading()
		ui.fit_text(c, said[i], width, Vector2(r.position.x, y), Ui.RED if i == said.size() - 1 else Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var bw := 140.0 if Ui.scale == 1 else 200.0
	var cx := r.get_center().x
	var field := Rect2(cx - bw - 6.0, y + 12.0, 2.0 * bw + 12.0, bh)
	# A sunken box with a blinking cursor, so it reads as the place to type and not as another button.
	_field(c, ui, field)
	y += bh + 6.0
	var yes := Rect2(cx - bw - 6.0, y + 12.0, bw, bh)
	ui.button(c, yes, "yes", tr("Delete").to_upper(), "", word_typed() or pad, null, true)
	if held > 0.0:
		c.draw_rect(Rect2(yes.position, Vector2(yes.size.x * held / HOLD_SECONDS, yes.size.y)), Color(Ui.RED, 0.4))
	ui.button(c, Rect2(cx + 6.0, y + 12.0, bw, bh), "no", tr("Cancel").to_upper(), "", true, null, true)


## A phone's question, high in the frame with the word's box and both buttons on one row, above the keyboard.
func _draw_touch_question(c: CanvasItem, ui: Ui, r: Rect2, said: Array, bh: float) -> void:
	var y := r.position.y + Ui.below_title() + Ui.px
	ui.text(c, (tr("Delete slot %d?") % confirming).to_upper(), Vector2(r.position.x, y), Ui.BROWN, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	for i in said.size():
		y += Ui.leading()
		ui.fit_text(c, said[i], r.size.x - 24.0, Vector2(r.position.x, y), Ui.RED if i == said.size() - 1 else Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var bw := 120.0 if Ui.scale > 1 else 100.0
	var top := y + 10.0
	var field := Rect2(r.position.x + 12.0, top, r.size.x - 24.0 - 2.0 * bw - 16.0, bh)
	ui.register(field, "field")
	_field(c, ui, field)
	ui.button(c, Rect2(field.end.x + 8.0, top, bw, bh), "yes", tr("Delete").to_upper(), "", word_typed(), null, true)
	ui.button(c, Rect2(field.end.x + 16.0 + bw, top, bw, bh), "no", tr("Cancel").to_upper(), "", true, null, true)


## The sunken box the word is typed into, with a blinking cursor, so it reads as the place to type and not as another button.
func _field(c: CanvasItem, ui: Ui, field: Rect2) -> void:
	c.draw_rect(field.grow(1), Ui.INK)
	c.draw_rect(field, Ui.CREAM)
	c.draw_rect(Rect2(field.position, Vector2(field.size.x, 2)), Ui.PARCH_DARK)
	c.draw_rect(Rect2(field.position, Vector2(2, field.size.y)), Ui.PARCH_DARK)
	var at := Vector2(field.position.x + 8.0, field.get_center().y + Ui.px / 2.0 - 1.0)
	if typed == "":
		ui.text(c, tr("delete").to_upper(), at, Ui.MUTED)
	else:
		ui.fit_text(c, typed.to_upper(), field.size.x - 24.0, at, Ui.INK)
	if int(Time.get_ticks_msec() / 500) % 2 == 0:
		var x := at.x + (Ui.width_at(typed.to_upper(), Ui.px) + 2.0 if typed != "" else 0.0)
		c.draw_rect(Rect2(x, field.position.y + 5.0, 2.0, field.size.y - 10.0), Ui.INK)

