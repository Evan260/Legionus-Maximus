class_name Game
extends RefCounted
## What the build is: the free demo or the full game, and the limits the demo puts on the map, the commanders and the run.


## Set by the tests to play as the demo without a command-line flag.
static var demo_forced := false

## The commanders the demo lists, which the demo hands out as unlocked; filled by commanders().
static var demo_open: Array = []


## Whether this is the demo: the project exported with the "demo" feature, or started with --as-demo.
static func is_demo() -> bool:
	return demo_forced or OS.has_feature("demo") or "--as-demo" in OS.get_cmdline_user_args()


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
	return not (state == "choose" or state == "pray" or state == "over") or now - opened_at >= float(balance.confirm_delay)


## The title's goal line: the minutes to survive, and the fort in the full game; the demo ends at its time limit and has no chieftain.
static func goal_text(balance: Dictionary) -> String:
	if is_demo():
		return TranslationServer.translate("Survive %d minutes.") % int(float(balance.demo.seconds) / 60.0)
	return TranslationServer.translate("Survive %d minutes, then kill the chieftain.") % int(float(balance.chieftain_at) / 60.0)


## Whether the run counts as under way: on the field, at a choice, paused, or in the settings opened from the pause.
static func in_run(state: String, settings_from: String) -> bool:
	return state in ["play", "choose", "pray", "pause"] or (state == "settings" and settings_from == "pause")


## Losing the window's focus while playing pauses the run, but not an autoplay left to run for a look.
static func pauses_on_focus_loss(state: String, autoplay: bool) -> bool:
	return state == "play" and not autoplay
