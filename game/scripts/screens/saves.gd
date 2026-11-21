class_name SavesScreen
extends RefCounted
## The load list: one row for each of the three save slots, saying what game is in it, with Play and Delete, and a question before a game is deleted.

var main: Node
## The slot whose deletion is being asked about, or 0.
var confirming := 0


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
			# The question opens on Cancel, so a second press of the confirm key never deletes a game.
			main.ui.focus = "no"
		"no":
			back()
		"yes":
			_delete(confirming)


## Leaves the question for the list, or the list for the title; false when the screen itself should close.
func back() -> bool:
	if confirming == 0:
		return false
	main.ui.focus = "delete:%d" % confirming
	confirming = 0
	return true


func _delete(n: int) -> void:
	confirming = 0
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
			ui.fit_text(c, played_on(float(info.saved_at)), room - Ui.width_at(name, Ui.px) - 16.0, Vector2(0, y), Ui.MUTED, HORIZONTAL_ALIGNMENT_RIGHT, x0 + room)
			var lines := summary(info, main.content, main.balance)
			for i in lines.size():
				ui.fit_text(c, lines[i], room, Vector2(x0, y + (i + 1) * Ui.leading()), Ui.INK)
		var x := row.end.x - bw - 8.0
		var mid := row.get_center().y
		ui.button(c, Rect2(x, mid - bh - 2.0, bw, bh), "play:%d" % n, tr("Play").to_upper(), "", not info.is_empty(), null, true)
		ui.button(c, Rect2(x, mid + 2.0, bw, bh), "delete:%d" % n, tr("Delete").to_upper(), "", true, null, true)


## Asks before a game is deleted, saying what is in it, since a deleted game cannot be brought back.
func _draw_question(c: CanvasItem, ui: Ui) -> void:
	var r := ui.frame(c, tr("Delete a game").to_upper(), Controls.hint("pick"))
	var info := Profile.slot_info(confirming)
	var said: Array = summary(info, main.content, main.balance) if not info.is_empty() else [tr("This game could not be read.")]
	said.append(tr("It will be gone for good."))
	var width := r.size.x - 80.0
	var bh := 24.0 if Ui.scale == 1 else 30.0
	var y := r.get_center().y - ((said.size() + 1) * Ui.leading() + 18.0 + bh) / 2.0 + Ui.px
	ui.text(c, (tr("Delete slot %d?") % confirming).to_upper(), Vector2(r.position.x, y), Ui.BROWN, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	y += 6.0
	for i in said.size():
		y += Ui.leading()
		ui.fit_text(c, said[i], width, Vector2(r.position.x, y), Ui.RED if i == said.size() - 1 else Ui.INK, HORIZONTAL_ALIGNMENT_CENTER, r.size.x)
	var bw := 140.0 if Ui.scale == 1 else 200.0
	var cx := r.get_center().x
	ui.button(c, Rect2(cx - bw - 6.0, y + 12.0, bw, bh), "yes", tr("Delete").to_upper(), "", true, null, true)
	ui.button(c, Rect2(cx + 6.0, y + 12.0, bw, bh), "no", tr("Cancel").to_upper(), "", true, null, true)
