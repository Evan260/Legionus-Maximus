class_name Controls
extends RefCounted
## The game's input actions: their default keys and pad buttons, and the player's own bindings laid over them.
## A saved binding is {"keys": [physical keycodes], "pads": [button numbers]}; an action with none saved keeps its defaults.

# The actions the settings screen lets the player rebind, with their names.
const ACTIONS := [["up", "March up"], ["down", "March down"], ["left", "March left"], ["right", "March right"],
	["testudo", "Testudo"], ["build", "Build a palisade"], ["wall", "Build a wall behind"], ["bridge", "Lay a bridge"], ["pray", "Call the gods"], ["reroll", "Reroll"], ["banish", "Banish"], ["pause", "Pause"], ["confirm", "Confirm"], ["back", "Back"]]
const KEYS := {
	"left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT], "up": [KEY_W, KEY_UP], "down": [KEY_S, KEY_DOWN],
	"testudo": [KEY_SPACE], "build": [KEY_E], "wall": [KEY_F], "bridge": [KEY_C], "pray": [KEY_G], "reroll": [KEY_R], "banish": [KEY_B], "confirm": [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER], "pause": [KEY_ESCAPE], "quit": [KEY_Q],
	"fullscreen": [KEY_F11], "back": [KEY_ESCAPE],
}
const PADS := {"back": JOY_BUTTON_B, "reroll": JOY_BUTTON_Y, "banish": JOY_BUTTON_X, "testudo": JOY_BUTTON_A, "build": JOY_BUTTON_X, "wall": JOY_BUTTON_LEFT_SHOULDER, "bridge": JOY_BUTTON_RIGHT_SHOULDER, "pray": JOY_BUTTON_Y, "confirm": JOY_BUTTON_A, "pause": JOY_BUTTON_START,
	"left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT, "up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN}
const STICK := [["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0], ["up", JOY_AXIS_LEFT_Y, -1.0], ["down", JOY_AXIS_LEFT_Y, 1.0]]
const PAD_NAMES := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_DPAD_UP: "Dpad up", JOY_BUTTON_DPAD_DOWN: "Dpad down",
	JOY_BUTTON_DPAD_LEFT: "Dpad left", JOY_BUTTON_DPAD_RIGHT: "Dpad right", JOY_BUTTON_LEFT_STICK: "L stick", JOY_BUTTON_RIGHT_STICK: "R stick"}
# The keys whose names are words, translated where they are drawn; every other key is named by its letter or symbol.
const KEY_NAMES := {KEY_UP: "Up", KEY_DOWN: "Down", KEY_LEFT: "Left", KEY_RIGHT: "Right", KEY_SPACE: "Space", KEY_ESCAPE: "Escape",
	KEY_ENTER: "Enter", KEY_TAB: "Tab", KEY_BACKSPACE: "Backspace"}
# Actions read on the same screen: on the field, on the menus, at a level-up, on the pause screen and at the gods' choice. No key or button stands for two actions of one group.
const GROUPS := [["up", "down", "left", "right", "testudo", "build", "wall", "bridge", "pray", "pause"], ["up", "down", "left", "right", "confirm", "back"],
	["up", "down", "left", "right", "confirm", "reroll", "banish"], ["confirm", "pause"], ["confirm", "pray"]]
# The display servers that know the keyboard's layout; elsewhere a key keeps its US name.
const LAYOUT_SERVERS := ["Windows", "macOS", "X11", "Wayland"]
# The words of the key hints, each translated on its own so no translation has to keep a key in its place.
const HINT_WORDS := ["move", "choose", "back", "buy a rank", "take it", "call", "not now", "reroll", "banish",
	"call the gods", "bridge", "palisade", "wall", "cancel", "delete", "change a key or button", "change a volume", "continue", "hold to delete"]


## The keys and pad buttons an action has: the saved ones, or the defaults when none are saved or the saved list is empty.
static func effective(saved: Dictionary, action: String) -> Dictionary:
	var mine: Dictionary = saved.get(action, {})
	var keys: Array = mine.get("keys", []).duplicate()
	var pads: Array = mine.get("pads", []).duplicate()
	if keys.is_empty():
		keys = KEYS.get(action, []).duplicate()
	if pads.is_empty():
		pads = [PADS[action]] if PADS.has(action) else []
	return {"keys": keys, "pads": pads}


## Makes every action and puts its keys and buttons in the input map, replacing what was there.
static func install(saved: Dictionary) -> void:
	var names := {}
	for a in KEYS:
		names[a] = true
	for a in PADS:
		names[a] = true
	for action in names:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.25)
		for e in InputMap.action_get_events(action):
			if e is InputEventKey or e is InputEventJoypadButton:
				InputMap.action_erase_event(action, e)
		var mine := effective(saved, action)
		for k in mine.keys:
			var e := InputEventKey.new()
			e.physical_keycode = k
			InputMap.action_add_event(action, e)
		for p in mine.pads:
			var e := InputEventJoypadButton.new()
			e.button_index = p
			InputMap.action_add_event(action, e)
	for pair in STICK:
		var has_stick := false
		for e in InputMap.action_get_events(pair[0]):
			has_stick = has_stick or e is InputEventJoypadMotion
		if not has_stick:
			var m := InputEventJoypadMotion.new()
			m.axis = pair[1]
			m.axis_value = pair[2]
			InputMap.action_add_event(pair[0], m)


## Replaces one slot of an action, "keys" or "pads", with a new code, in `saved` and in the input map.
## The code is taken out of the action's other slots, so one key is never listed twice for one action and a list is never left empty.
## An action read on the same screen that holds the code gives it up and takes this slot's old code instead; false, with nothing changed,
## when that would leave it with no key or button at all.
static func rebind(saved: Dictionary, action: String, kind: String, slot: int, code: int) -> bool:
	var trial := saved.duplicate(true)
	var mine := effective(trial, action)
	var list: Array = mine[kind]
	var old: int = int(list[slot]) if slot < list.size() else -1
	var at := slot
	if slot < list.size():
		list[slot] = code
	else:
		list.append(code)
		at = list.size() - 1
	for i in range(list.size() - 1, -1, -1):
		if i != at and list[i] == code:
			list.remove_at(i)
	trial[action] = mine
	for other in clashing(action):
		var theirs := effective(trial, other)
		var held: Array = theirs[kind]
		var i := held.find(code)
		if i < 0:
			continue
		if old >= 0 and old != code and not held.has(old) and _free_for(trial, other, kind, old):
			held[i] = old
		else:
			held.remove_at(i)
		if held.is_empty():
			return false
		trial[other] = theirs
	saved.clear()
	saved.merge(trial)
	install(saved)
	return true


## The actions read on the same screen as `action`.
static func clashing(action: String) -> Array:
	var out: Array = []
	for group in GROUPS:
		if action in group:
			for other in group:
				if other != action and not other in out:
					out.append(other)
	return out


## Whether no action read on the same screen as `action` holds the code.
static func _free_for(saved: Dictionary, action: String, kind: String, code: int) -> bool:
	for other in clashing(action):
		if effective(saved, other)[kind].has(code):
			return false
	return true


## A physical key's name as its cap reads on the player's own keyboard layout, so an AZERTY keyboard's Z is not called W.
static func key_name(code: int) -> String:
	if KEY_NAMES.has(code):
		return TranslationServer.translate(KEY_NAMES[code])
	var label := DisplayServer.keyboard_get_label_from_physical(code) if DisplayServer.get_name() in LAYOUT_SERVERS else KEY_NONE
	var s := OS.get_keycode_string(label if label != KEY_NONE else code)
	return s if s != "" else "?"


static func pad_name(button: int) -> String:
	return TranslationServer.translate(PAD_NAMES[button]) if PAD_NAMES.has(button) else TranslationServer.translate("Button %d") % button


## The names of one slot's key or button, "-" when it has none.
static func slot_text(saved: Dictionary, action: String, kind: String, slot: int) -> String:
	var list: Array = effective(saved, action)[kind]
	if slot >= list.size():
		return "-"
	return key_name(list[slot]) if kind == "keys" else pad_name(list[slot])


## Whether the player last used a gamepad, so the hints name its buttons instead of the keys.
static var pad_in_use := false


## Notes which device the player just used; a stick has to move well off centre so a resting stick's drift does not count.
static func note_input(event: InputEvent) -> void:
	if event is InputEventJoypadButton and event.pressed:
		pad_in_use = true
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		pad_in_use = true
	elif (event is InputEventKey or event is InputEventMouseButton) and event.pressed:
		pad_in_use = false


## The key of an action, or its button while the player is on a gamepad.
static func shown(action: String) -> String:
	return pad_of(action) if pad_in_use else key_of(action)


## The first key of an action in the player's own bindings.
static func key_of(action: String) -> String:
	return slot_text(Profile.setting("bindings"), action, "keys", 0)


## The first pad button of an action in the player's own bindings.
static func pad_of(action: String) -> String:
	return slot_text(Profile.setting("bindings"), action, "pads", 0)


## The four marching keys, or the stick while the player is on a gamepad, for the hints that say how to move.
static func march_keys() -> String:
	if pad_in_use:
		return pad_name(JOY_BUTTON_LEFT_STICK)
	return " ".join(["up", "left", "down", "right"].map(key_of))


## One part of a key hint: the keys, then the translated word for what they do.
static func part(keys: String, word: String) -> String:
	return keys + "  " + TranslationServer.translate(word)


## The key hint at the foot of a screen, naming the player's current keys; `count` is the rerolls or banishes left.
static func hint(kind: String, count := 0) -> String:
	if Touch.phone:
		return TranslationServer.translate("Lay a bridge") if kind == "bridge" else ""
	var stick := pad_name(JOY_BUTTON_LEFT_STICK)
	var sides := stick if pad_in_use else key_of("left") + " / " + key_of("right")
	# The level-up and the gods' choice are rows, worked up and down.
	var rows := stick if pad_in_use else key_of("up") + " / " + key_of("down")
	var confirm := shown("confirm")
	var back := shown("back")
	var parts: Array = []
	match kind:
		"pick":
			parts = [part(march_keys(), "move"), part(confirm, "choose"), part(back, "back")]
		"buy":
			parts = [part(march_keys(), "move"), part(confirm, "buy a rank"), part(back, "back")]
		"look":
			parts = [part(march_keys(), "move"), part(back, "back")]
		"volume":
			parts = [part(march_keys(), "move"), part(sides, "change a volume"), part(back, "back")]
		"keys":
			parts = [part(confirm, "change a key or button"), part(back, "back")]
		"press":
			parts = [TranslationServer.translate("Press the new key or button"), part(key_name(KEY_ESCAPE), "cancel")]
		"press_key":
			parts = [TranslationServer.translate("Press the new key or button"), part(pad_of("back") if pad_in_use else key_name(KEY_ESCAPE), "cancel")]
		"type":
			parts = [part(key_name(KEY_ENTER), "delete"), part(key_name(KEY_ESCAPE), "cancel")]
		"hold":
			parts = [part(pad_of("confirm"), "hold to delete"), part(pad_of("back"), "cancel")]
		"level":
			parts = [part(rows, "choose"), part(confirm, "take it")]
		"reroll":
			parts = [part(shown("reroll"), "reroll") + " (%d)" % count]
		"banish":
			parts = [part(shown("banish"), "banish") + " (%d)" % count]
		"summary":
			parts = [part(confirm, "choose"), part(back, "Camp")]
		"victory":
			parts = [part(confirm, "continue")]
		"title":
			parts = [part(back, "Title")]
		"pray":
			parts = [part(shown("pray"), "call the gods")]
		"bridge":
			parts = [part(shown("bridge"), "bridge")]
		"gods":
			parts = [part(rows, "choose"), part(confirm, "call"), part(back, "not now")]
	return "     ".join(parts)
