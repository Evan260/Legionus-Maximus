class_name Controls
extends RefCounted
## The game's input actions: their default keys and pad buttons, and the player's own bindings laid over them.
## A saved binding is {"keys": [physical keycodes], "pads": [button numbers]}; an action with none saved keeps its defaults.

# The actions the settings screen lets the player rebind, with their names.
const ACTIONS := [["up", "March up"], ["down", "March down"], ["left", "March left"], ["right", "March right"],
	["testudo", "Testudo"], ["build", "Build a palisade"], ["bridge", "Lay a bridge"], ["pray", "Call the gods"], ["pause", "Pause"], ["confirm", "Confirm"], ["back", "Back"]]
const KEYS := {
	"left": [KEY_A, KEY_LEFT], "right": [KEY_D, KEY_RIGHT], "up": [KEY_W, KEY_UP], "down": [KEY_S, KEY_DOWN],
	"testudo": [KEY_SPACE], "build": [KEY_E], "bridge": [KEY_C], "pray": [KEY_F], "reroll": [KEY_R], "banish": [KEY_B], "confirm": [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER], "pause": [KEY_ESCAPE], "quit": [KEY_Q],
	"fullscreen": [KEY_F11], "back": [KEY_ESCAPE],
}
const PADS := {"back": JOY_BUTTON_B, "reroll": JOY_BUTTON_Y, "banish": JOY_BUTTON_X, "testudo": JOY_BUTTON_A, "build": JOY_BUTTON_X, "bridge": JOY_BUTTON_RIGHT_SHOULDER, "pray": JOY_BUTTON_Y, "confirm": JOY_BUTTON_A, "pause": JOY_BUTTON_START,
	"left": JOY_BUTTON_DPAD_LEFT, "right": JOY_BUTTON_DPAD_RIGHT, "up": JOY_BUTTON_DPAD_UP, "down": JOY_BUTTON_DPAD_DOWN}
const STICK := [["left", JOY_AXIS_LEFT_X, -1.0], ["right", JOY_AXIS_LEFT_X, 1.0], ["up", JOY_AXIS_LEFT_Y, -1.0], ["down", JOY_AXIS_LEFT_Y, 1.0]]
const PAD_NAMES := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y", JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start",
	JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_DPAD_UP: "Dpad up", JOY_BUTTON_DPAD_DOWN: "Dpad down",
	JOY_BUTTON_DPAD_LEFT: "Dpad left", JOY_BUTTON_DPAD_RIGHT: "Dpad right", JOY_BUTTON_LEFT_STICK: "L stick", JOY_BUTTON_RIGHT_STICK: "R stick"}


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
static func rebind(saved: Dictionary, action: String, kind: String, slot: int, code: int) -> void:
	var mine := effective(saved, action)
	var list: Array = mine[kind]
	var at := slot
	if slot < list.size():
		list[slot] = code
	else:
		list.append(code)
		at = list.size() - 1
	for i in range(list.size() - 1, -1, -1):
		if i != at and list[i] == code:
			list.remove_at(i)
	saved[action] = mine
	install(saved)


## The saved bindings with the defaults of one action put back.
static func reset(saved: Dictionary, action: String) -> void:
	saved.erase(action)
	install(saved)


static func key_name(code: int) -> String:
	var s := OS.get_keycode_string(code)
	return s if s != "" else "?"


static func pad_name(button: int) -> String:
	return TranslationServer.translate(PAD_NAMES[button]) if PAD_NAMES.has(button) else TranslationServer.translate("Button %d") % button


## The names of one slot's key or button, "-" when it has none.
static func slot_text(saved: Dictionary, action: String, kind: String, slot: int) -> String:
	var list: Array = effective(saved, action)[kind]
	if slot >= list.size():
		return "-"
	return key_name(list[slot]) if kind == "keys" else pad_name(list[slot])


## The first key of an action in the player's own bindings.
static func key_of(action: String) -> String:
	return slot_text(Profile.setting("bindings"), action, "keys", 0)


## The first pad button of an action in the player's own bindings.
static func pad_of(action: String) -> String:
	return slot_text(Profile.setting("bindings"), action, "pads", 0)


## The four marching keys, for the hints that say how to move.
static func march_keys() -> String:
	return " ".join(["up", "left", "down", "right"].map(key_of))


## The key hint at the foot of a screen, naming the player's current keys; `count` is the rerolls or banishes left.
static func hint(kind: String, count := 0) -> String:
	match kind:
		"pick":
			return TranslationServer.translate("%s move     %s choose     %s back") % [march_keys(), key_of("confirm"), key_of("back")]
		"buy":
			return TranslationServer.translate("%s move     %s buy a rank     %s back") % [march_keys(), key_of("confirm"), key_of("back")]
		"look":
			return TranslationServer.translate("%s move     %s back") % [march_keys(), key_of("back")]
		"level":
			return TranslationServer.translate("%s / %s to choose     %s to take it") % [key_of("left"), key_of("right"), key_of("confirm")]
		"reroll":
			return TranslationServer.translate("%s / %s  reroll (%d)") % [key_of("reroll"), pad_of("reroll"), count]
		"banish":
			return TranslationServer.translate("%s / %s  banish (%d)") % [key_of("banish"), pad_of("banish"), count]
		"summary":
			return TranslationServer.translate("%s camp     %s title") % [key_of("confirm"), key_of("back")]
		"title":
			return TranslationServer.translate("%s  title") % key_of("back")
		"pray":
			return TranslationServer.translate("%s / %s  call the gods") % [key_of("pray"), pad_of("pray")]
		"bridge":
			return TranslationServer.translate("%s / %s  bridge the ravine") % [key_of("bridge"), pad_of("bridge")]
		"gods":
			return TranslationServer.translate("%s / %s to choose     %s to call     %s not now") % [key_of("left"), key_of("right"), key_of("confirm"), key_of("back")]
	return ""
