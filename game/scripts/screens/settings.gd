class_name SettingsScreen
extends RefCounted
## The settings: volumes, full screen, screen shake, damage numbers, text size, language, and the key and button bindings.
## Changes apply at once; they are saved when the screen is left.

const VOLUMES := ["master", "music", "effects"]
const VOLUME_NAMES := {"master": "Master volume", "music": "Music volume", "effects": "Effects volume"}
const BUSES := {"master": "Master", "music": "Music", "effects": "Effects"}
const TOGGLES := [["fullscreen", "Full screen"], ["shake", "Screen shake"], ["numbers", "Damage numbers"]]

var main: Node
var page := "main"
# The slot being rebound as {"action", "kind", "slot"}, empty when none is.
var waiting := {}


func _init(owner_node: Node) -> void:
	main = owner_node


func enter() -> void:
	page = "main"
	waiting = {}


## Makes the audio buses a later sound plays through and sets each one's volume from the 0 to 1 settings.
static func apply_audio(cfg: Dictionary) -> void:
	for key in VOLUMES:
		var idx := AudioServer.get_bus_index(BUSES[key])
		if idx < 0:
			AudioServer.add_bus()
			idx = AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, BUSES[key])
		var v := float(cfg[key])
		AudioServer.set_bus_mute(idx, v <= 0.0)
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))


func _put(key: String, value: Variant) -> void:
	Profile.settings[key] = value
	main.apply_settings()


## Left or right on a volume row changes it by a tenth; returns true when the row used the key.
func adjust(id: String, dir: int) -> bool:
	if page != "main" or not VOLUMES.has(id):
		return false
	_put(id, clampf(snappedf(float(Profile.setting(id)) + 0.1 * dir, 0.1), 0.0, 1.0))
	return true


## Leaves the controls page for the main one; false when the screen itself should close.
func back() -> bool:
	if not waiting.is_empty():
		waiting = {}
		return true
	if page != "main":
		main.ui.focus = page
		page = "main"
		return true
	return false


func activate(id: String) -> void:
	if VOLUMES.has(id):
		var next := float(Profile.setting(id)) + 0.1
		_put(id, 0.0 if next > 1.0001 else snappedf(next, 0.1))
	elif id == "music_folder":
		Audio.open_music_folder()
	elif id == "text_size":
		_put("text_size", 2 if int(Profile.setting("text_size")) == 1 else 1)
	elif id == "language":
		page = "language"
		main.ui.focus = ""
	elif id.begins_with("lang:"):
		_put("language", id.trim_prefix("lang:"))
		Lang.apply(id.trim_prefix("lang:"))
	elif id == "controls":
		page = "controls"
		main.ui.focus = ""
	elif id == "back":
		if not back():
			main.close_settings()
	elif id == "reset":
		Profile.settings.bindings = {}
		Controls.install({})
	elif id.begins_with("bind:"):
		var parts := id.split(":")
		waiting = {"action": parts[1], "kind": parts[2], "slot": int(parts[3])}
	else:
		for t in TOGGLES:
			if t[0] == id:
				_put(id, not bool(Profile.setting(id)))


## Takes the next key or pad button for the slot being rebound; returns true when the event was used.
func capture(event: InputEvent) -> bool:
	if waiting.is_empty():
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE:
			waiting = {}
		elif waiting.kind == "keys":
			_bind(int(event.physical_keycode))
		return true
	if event is InputEventJoypadButton and event.pressed:
		if waiting.kind == "pads":
			_bind(int(event.button_index))
		return true
	if event is InputEventMouseButton and event.pressed:
		waiting = {}
		return true
	return false


func _bind(code: int) -> void:
	var saved: Dictionary = Profile.settings.get("bindings", {})
	Controls.rebind(saved, waiting.action, waiting.kind, waiting.slot, code)
	Profile.settings.bindings = saved
	waiting = {}


func draw(c: CanvasItem, ui: Ui) -> void:
	if page == "controls":
		_draw_controls(c, ui)
	elif page == "language":
		_draw_language(c, ui)
	else:
		_draw_main(c, ui)


func _draw_main(c: CanvasItem, ui: Ui) -> void:
	var r := ui.frame(c, tr("Settings").to_upper(), Controls.hint("volume"))
	var h := 26.0 if Ui.scale > 1 else 21.0
	var step := h + 1.0 if Ui.scale > 1 else h + 3.0
	var w := 440.0
	var x := (Ui.W - w) / 2.0
	var y := r.position.y + Ui.below_title() + 4.0
	# Volumes, the music folder, the switches, text size, language, keys and back all fit inside the frame.
	var rows := VOLUMES.size() + TOGGLES.size() + 5
	var fit := floorf((r.end.y - 6.0 - y) / rows)
	if fit < step:
		h -= step - fit
		step = fit
	for key in VOLUMES:
		var rect := Rect2(x, y, w, h)
		var v := float(Profile.setting(key))
		var pct := "%d%%" % roundi(v * 100.0)
		var bar_w := 80.0
		var bx := rect.end.x - 12.0 - ui.width_of("100%") - bar_w
		ui.button(c, rect, key, tr(VOLUME_NAMES[key]), pct, true, null, false, Ui.RED, rect.end.x - bx - ui.width_of(pct) - 6.0)
		c.draw_rect(Rect2(bx - 1, rect.position.y + h / 2 - 3, bar_w + 2, 7), Ui.INK)
		c.draw_rect(Rect2(bx, rect.position.y + h / 2 - 2, bar_w, 5), Ui.PARCH_DARK)
		c.draw_rect(Rect2(bx, rect.position.y + h / 2 - 2, bar_w * v, 5), Ui.GOLD)
		y += step
	ui.button(c, Rect2(x, y, w, h), "music_folder", tr("Your own music"), tr("Open folder"))
	y += step
	for t in TOGGLES:
		ui.button(c, Rect2(x, y, w, h), t[0], tr(t[1]), tr("On") if bool(Profile.setting(t[0])) else tr("Off"))
		y += step
	ui.button(c, Rect2(x, y, w, h), "text_size", tr("Text size"), tr("Large") if int(Profile.setting("text_size")) == 2 else tr("Normal"))
	y += step
	var lang := tr("Automatic") if Profile.setting("language") == "" else str(Lang.NATIVE_NAMES.get(Profile.setting("language"), ""))
	Ui.draw_in("" if Profile.setting("language") == "" else str(Profile.setting("language")))
	ui.button(c, Rect2(x, y, w, h), "language", "", lang)
	Ui.draw_in("")
	ui.text(c, tr("Language"), Vector2(x + 6.0, y + h / 2.0 + Ui.px * 3 / 8), Ui.INK)
	y += step
	ui.button(c, Rect2(x, y, w, h), "controls", tr("Keys and buttons"), "")
	y += step
	ui.button(c, Rect2(x, y, w, h), "back", tr("Back").to_upper(), "", true, null, true)


## The height of each row on the key page and the step between rows, so every action and the buttons below fit the room.
static func controls_rows(room: float) -> Dictionary:
	var step := minf(25.0 if Ui.scale > 1 else 21.0, floorf((room - 4.0) / (Controls.ACTIONS.size() + 1)))
	return {"step": step, "h": step - 2.0}


## The width of the action names column, wide enough for the longest name in the language, and of each of the three buttons beside it.
static func controls_metrics(frame_w: float) -> Dictionary:
	var widest := 0.0
	for a in Controls.ACTIONS:
		widest = maxf(widest, Ui.width_at(TranslationServer.translate(a[1]), Ui.px))
	var name_w := maxf(150.0 if Ui.scale > 1 else 110.0, widest + 12.0)
	return {"name_w": name_w, "bw": (frame_w - 24.0 - name_w - 3 * 4.0) / 3.0}


func _draw_controls(c: CanvasItem, ui: Ui) -> void:
	var hint := Controls.hint("press" if not waiting.is_empty() else "keys")
	var r := ui.frame(c, tr("Keys and buttons").to_upper(), hint)
	var saved: Dictionary = Profile.settings.get("bindings", {})
	var metrics := controls_metrics(r.size.x)
	var name_w: float = metrics.name_w
	var bw: float = metrics.bw
	var y := r.position.y + Ui.below_title()
	var rows := controls_rows(r.end.y - 4.0 - y)
	var h: float = rows.h
	var step: float = rows.step
	var slots := [["keys", 0], ["keys", 1], ["pads", 0]]
	for a in Controls.ACTIONS:
		ui.text(c, tr(a[1]), Vector2(r.position.x + 12, y + h / 2 + Ui.px * 3 / 8), Ui.INK)
		for k in slots.size():
			var is_waiting: bool = waiting.get("action", "") == a[0] and waiting.kind == slots[k][0] and waiting.slot == slots[k][1]
			var label := tr("Press...") if is_waiting else Controls.slot_text(saved, a[0], slots[k][0], slots[k][1])
			var rect := Rect2(r.position.x + 12 + name_w + k * (bw + 4.0), y, bw, h)
			ui.button(c, rect, "bind:%s:%s:%d" % [a[0], slots[k][0], slots[k][1]], label, "", true, null, true)
		y += step
	y += 4.0
	var half := (r.size.x - 24.0 - 8.0) / 2.0
	ui.button(c, Rect2(r.position.x + 12, y, half, h), "reset", tr("Use defaults").to_upper(), "", true, null, true)
	ui.button(c, Rect2(r.position.x + 20 + half, y, half, h), "back", tr("Back").to_upper(), "", true, null, true)


## Every language named in its own words and letters, with the computer's own language first.
func _draw_language(c: CanvasItem, ui: Ui) -> void:
	var r := ui.frame(c, tr("Language").to_upper(), Controls.hint("pick"))
	var choices: Array = [""]
	choices.append_array(Lang.languages())
	var h := 24.0 if Ui.scale > 1 else 21.0
	var step := h + 3.0
	var w := (r.size.x - 24.0 - 8.0) / 2.0
	var rows := int(ceil(choices.size() / 2.0))
	var current: String = Profile.setting("language")
	for i in choices.size():
		var loc: String = choices[i]
		var rect := Rect2(r.position.x + 12.0 + (i / rows) * (w + 8.0), r.position.y + Ui.below_title() + (i % rows) * step, w, h)
		var mark := "[x] " if loc == current else "[ ] "
		if loc == "":
			ui.button(c, rect, "lang:", mark + tr("Automatic"))
		else:
			Ui.draw_in(loc)
			ui.button(c, rect, "lang:" + loc, mark + str(Lang.NATIVE_NAMES[loc]))
			Ui.draw_in("")
