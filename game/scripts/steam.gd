extends Node
## Steam and the achievements: earned ones are kept in the profile and handed to Steam whenever it is running, and what friends
## see (rich presence) is sent only on a change. Outside Steam, in tests and in screenshots, nothing here calls Steam.

const HIDING_STATES := ["choose", "pray", "supply", "over", "pause", "settings"]
const STORE_URL := "https://store.steampowered.com/app/%d"

## Sent when the player opens the Steam overlay, which draws over the game while its window keeps the focus.
signal overlay_opened

var steam: Object = null
var balance: Dictionary
var content: Content
## Cards waiting to slide in, then the one on show with its age in seconds.
var queue: Array = []
var card: Dictionary = {}
var card_age := 0.0
## True while a choice, the summary, the pause menu or the settings are open, so no card covers them.
var blocked := false
var _presence := {}
var _sent_at := -1000.0
var _clock := 0.0


func _ready() -> void:
	balance = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	if not may_start(Profile.disabled, DisplayServer.get_name(), Engine.has_singleton("Steam")):
		return
	var found := Engine.get_singleton("Steam")
	var started: Dictionary = found.call("steamInitEx")
	# Status 0 is a running Steam client that owns the game; any other leaves everything in the profile.
	if int(started.get("status", -1)) == 0:
		steam = found
		steam.connect("overlay_toggled", _overlay_toggled)
		sync()
	else:
		print_verbose("Steam is not available: ", started.get("verbal", ""))


func _process(dt: float) -> void:
	_clock += dt
	if steam:
		steam.call("run_callbacks")
	if card.is_empty():
		if not queue.is_empty() and not blocked:
			card = queue.pop_front()
			card_age = 0.0
		return
	if not blocked:
		card_age += dt
		if card_age >= card_total():
			card = {}


## Whether the card on show is drawn in this state of the game.
func card_visible(state: String) -> bool:
	return not card.is_empty() and not state in HIDING_STATES


func card_total() -> float:
	return float(balance.steam.card_hold) + 2.0 * float(balance.steam.card_slide)


## How far the card on show is in, 0 off the screen edge to 1 fully in.
func card_slide() -> float:
	var slide := float(balance.steam.card_slide)
	return clampf(minf(card_age, card_total() - card_age) / slide, 0.0, 1.0)


## Whether Steam is called at all: never in a look or a test (which keep the saves shut), headless, or in a build without GodotSteam.
static func may_start(looking: bool, display: String, has_steam: bool) -> bool:
	return not looking and display != "headless" and has_steam


func running() -> bool:
	return steam != null


func _overlay_toggled(active: bool, _user_initiated := false, _app_id := 0) -> void:
	if active:
		overlay_opened.emit()


## Sends every earned achievement to Steam, so ones earned before it was running still count.
func sync() -> void:
	for id in Profile.data.achievements:
		_send(str(id))


func _send(id: String) -> void:
	if steam:
		steam.call("setAchievement", id)
		steam.call("storeStats")


## Earns an achievement: kept in the profile, queued as a card and sent to Steam. Does nothing when it is already earned.
func unlock(id: String) -> bool:
	if Profile.data.achievements.has(id) or not content_of().achievements.has(id):
		return false
	Profile.data.achievements.append(id)
	var info: Dictionary = content_of().achievements[id]
	queue.append({"id": id, "name": info.name, "text": info.text})
	_send(id)
	return true


func content_of() -> Content:
	if content == null:
		content = Content.load_all(Content.available_art())
	return content


## Whether the run, with the profile as it stands, meets an achievement's condition. `banked` says the run is already in the totals.
func met(info: Dictionary, sim: Sim, banked: bool) -> bool:
	var target: Variant = info.get("target")
	match info.get("kind", ""):
		"province":
			return bool(Profile.record_of(str(target)).won)
		"commander":
			# The demo lends some commanders without unlocking them, so only a real unlock counts.
			return Profile.data.unlocked.commanders.has(str(target))
		"commander_win":
			return sim.victory and not sim.demo_over and sim.commander_id == str(target)
		"forged":
			return sim.rank(str(target)) > 0
		"kills":
			return int(Profile.data.totals.kills) + (0 if banked else sim.kills) >= int(target)
		"legion":
			return maxi(sim.peak_soldiers, sim.soldiers.size()) + 1 >= int(target)
		"maxed":
			var group: Dictionary = sim.content.get(str(info.group))
			var done := 0
			for id in group:
				if sim.rank(id) >= int(group[id].max):
					done += 1
			return not group.is_empty() and done >= int(info.get("target", group.size()))
	return false


## Earns every achievement the run has met, live or once it has ended, and returns the ids newly earned.
func check(sim: Sim, banked := false) -> Array:
	var earned: Array = []
	for id in content_of().achievements:
		if not Profile.data.achievements.has(id) and met(content_of().achievements[id], sim, banked) and unlock(id):
			earned.append(id)
	if not earned.is_empty():
		Profile.save()
	return earned


## Shows an achievement's card without earning it, for looking at the card.
func show_card(id: String) -> void:
	var info: Dictionary = content_of().achievements[id]
	queue.append({"id": id, "name": info.name, "text": info.text})


## What Steam shows friends: a token from tools/steam/rich_presence.vdf and the words it fills in. The province is its id, which the
## vdf names in each friend's own language, and an empty one means the camp.
static func presence_of(province: String, minute: int, legion: int) -> Dictionary:
	if province == "":
		return {"steam_display": "#Status_Camp"}
	return {"steam_display": "#Status_Marching", "province": province, "minute": str(minute), "legion": str(legion)}


## Tells Steam what the player is doing, only when it changed and at most once per interval.
func presence(province: String, minute: int, legion: int) -> void:
	if steam == null or _clock - _sent_at < float(balance.steam.presence_every):
		return
	var now := presence_of(province, minute, legion)
	if now == _presence:
		return
	_presence = now
	_sent_at = _clock
	steam.call("clearRichPresence")
	for key in now:
		steam.call("setRichPresence", key, now[key])


## Opens the game's store page, in Steam when it is running.
func open_store() -> void:
	var id := int(balance.demo.store_app_id)
	if id > 0:
		OS.shell_open(("steam://store/%d" if running() else STORE_URL) % id)
