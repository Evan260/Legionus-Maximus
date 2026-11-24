class_name Game
extends RefCounted
## What the build is: the free demo or the full game, and the limits the demo puts on the map, the commanders and the run.


## Set by the tests to play as the demo without a command-line flag.
static var demo_forced := false

## The commanders the demo lists, which the demo hands out as unlocked; filled by commanders().
static var demo_open: Array = []

## Written into the demo's own export by tools/demo_stage.py, so the demo stays the demo whatever its feature tags say.
const DEMO_MARK := "res://data/demo_build.json"
static var _marked := FileAccess.file_exists(DEMO_MARK)

## Whether this is a phone that has not bought the full game, kept equal to FullGame.locked() so the demo check reads a bool.
static var store_locked := false


## How many steps a frame of `dt` seconds is played in, so that no step is longer than a sixtieth of a second
## and the crowd presses on the legion as it does at 60 frames a second, however slow the computer.
static func steps_for(dt: float) -> int:
	return maxi(1, ceili(dt * 60.0 - 0.001))


## Whether this is the demo: its own export, the "demo" feature, --as-demo, or a phone that has not bought the full game.
static func is_demo() -> bool:
	return demo_forced or _marked or store_locked or OS.has_feature("demo") or "--as-demo" in OS.get_cmdline_user_args()


## Keeps store_locked equal to FullGame.locked() from now on.
static func follow_store() -> void:
	store_locked = FullGame.locked()
	FullGame.changed.connect(func() -> void: store_locked = FullGame.locked())


## The commanders this build lists: every one whose art is drawn, and in the demo only the first few of them.
static func commanders(content: Content, balance: Dictionary) -> Array:
	var ids: Array = []
	for id in content.commanders:
		var province := str(content.commanders[id].get("unlock", {}).get("province", ""))
		# A commander unlocked by winning in a province that is not playable yet is left out.
		if content.ready("commanders", id) and (province == "" or content.ready("provinces", province)):
			ids.append(id)
	if is_demo():
		ids = ids.slice(0, int(balance.demo.commanders))
		demo_open = ids
	return ids


## Whether this build can play the province.
static func province_allowed(id: String, balance: Dictionary) -> bool:
	return not is_demo() or id == str(balance.demo.province)


## The first province after `from` on the road that is drawn, open and allowed in this build, or "" when there is none.
static func next_province(content: Content, balance: Dictionary, from: String) -> String:
	var ids: Array = content.provinces.keys()
	for k in range(ids.find(from) + 1, ids.size()):
		var id: String = ids[k]
		if content.ready("provinces", id) and Profile.province_unlocked(id) and province_allowed(id, balance):
			return id
	return ""


## The run's length limit in seconds, or 0 for none.
static func run_cap(balance: Dictionary) -> float:
	return float(balance.demo.seconds) if is_demo() else 0.0


## Whether a confirm press counts. Space is also the testudo key, so a tap just as a choice or the summary opens must not take it.
static func confirm_allowed(state: String, opened_at: float, now: float, balance: Dictionary) -> bool:
	return not (choosing(state) or state == "over") or now - opened_at >= float(balance.confirm_delay)


## Whether a choice of rows is open over the run: a level-up, the gods or a supply cart.
static func choosing(state: String) -> bool:
	return state in ["choose", "pray", "supply"]


## The title's goal line: the minutes to survive, and the fort in the full game; the demo ends at its time limit and has no chieftain.
static func goal_text(balance: Dictionary) -> String:
	if is_demo():
		return TranslationServer.translate("Survive %d minutes.") % int(float(balance.demo.seconds) / 60.0)
	return TranslationServer.translate("Survive %d minutes, kill the chieftain, then hold the fort.") % int(float(balance.chieftain_at) / 60.0)


## Whether the run counts as under way: on the field, at a choice, paused, or in the settings opened from the pause.
static func in_run(state: String, settings_from: String) -> bool:
	return state in ["play", "choose", "pray", "supply", "pause"] or (state == "settings" and settings_from == "pause")


## Losing the window's focus while playing pauses the run, but not an autoplay left to run for a look.
static func pauses_on_focus_loss(state: String, autoplay: bool) -> bool:
	return state == "play" and not autoplay
