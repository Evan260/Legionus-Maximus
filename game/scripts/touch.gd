class_name Touch
extends RefCounted
## A phone or tablet's touch screen as plain decisions the tests can check: the stick, the buttons, the back gesture and fingertip sizes.

## The run's actions that have a button, in the order they are laid out.
const ACTIONS := ["testudo", "pray", "build", "wall", "bridge", "pause"]
## Shares of the stick's radius: inside DEAD the legion stands, past FULL it marches at full speed, as on a gamepad's stick.
const DEAD := 0.2
const FULL := 0.8
## The part of the screen, from its left edge, where a touch takes the stick.
const STICK_SHARE := 0.5
## The stick's radius and the testudo's width, in fingertips.
const STICK_RADIUS := 1.4
const TESTUDO_SIZE := 1.4
## The room left between two buttons, in fingertips.
const GAP := 0.2
## Android reports each back gesture twice; a second report this soon after the first is the same gesture.
const BACK_REPEAT_MS := 300
## A fingertip, in millimetres, and how far one may slide, in millimetres, while it still counts as a tap.
const FINGERTIP_MM := 7.0
const SLOP_MM := 2.0
## Below this many millimetres to a game pixel the normal text is too small to read, so a phone starts on large text.
const LARGE_TEXT_BELOW_MM := 0.25
## How far a phone's rounded corners reach in, as a share of the screen's short side.
const CORNER_SHARE := 0.035
## The short side, in inches, of the screen the preview stands for: a 2424 by 1080 phone at 420 dpi, or a tablet.
const PHONE_INCHES := 1080.0 / 420.0
const TABLET_INCHES := 6.0

## True on a phone or tablet, and with --phone on a computer.
static var phone := OS.has_feature("mobile") or "--phone" in OS.get_cmdline_user_args()
## True for --phone on a computer, where the mouse stands in for a finger.
static var preview := phone and not OS.has_feature("mobile")
## How far the HUD keeps in from the top-left and the bottom-right, in game pixels, clear of rounded corners and the camera.
static var inset_tl := Vector2.ZERO
static var inset_br := Vector2.ZERO
## A fingertip's width in game pixels, 0 on a computer.
static var fingertip := 0.0
## How far a finger may slide, in game pixels, while it still counts as a tap.
static var slop := 6.0
## Game pixels in a millimetre of the screen.
static var px_per_mm := 0.0
## Whether the normal text is too small to read on this screen.
static var wants_large := false


## Works out the insets and the fingertip for a window of `window` screen pixels showing a game view of `view` pixels.
static func fit(window: Vector2i, view: Vector2i) -> void:
	if not phone or view.x <= 0 or view.y <= 0:
		return
	var scale := Vector2(window) / Vector2(view)
	var dpi := screen_dpi(window)
	var insets := insets_for(window, safe_area(window), scale)
	inset_tl = insets[0]
	inset_br = insets[1]
	fingertip = fingertip_for(dpi, scale.y)
	slop = fingertip_for(dpi, scale.y, SLOP_MM)
	px_per_mm = fingertip / FINGERTIP_MM
	wants_large = large_text(dpi, scale.y)


## The screen's pixels per inch; the preview counts its window as a phone or tablet screen of the same shape.
static func screen_dpi(window: Vector2i) -> float:
	if preview:
		return preview_dpi(window)
	return float(DisplayServer.screen_get_dpi())


## The part of the screen clear of the camera; the preview takes it from `--phone-insets=L,T,R,B` in screen pixels.
static func safe_area(window: Vector2i) -> Rect2i:
	if not preview:
		return DisplayServer.get_display_safe_area()
	var cut := [0, 0, 0, 0]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--phone-insets="):
			var parts := arg.trim_prefix("--phone-insets=").split(",")
			for i in mini(4, parts.size()):
				cut[i] = int(parts[i])
	return Rect2i(cut[0], cut[1], window.x - cut[0] - cut[2], window.y - cut[1] - cut[3])


## The dpi a preview window of this size stands for: a wide window is a phone, a squarer one a tablet held further off.
static func preview_dpi(window: Vector2i) -> float:
	var short := float(mini(window.x, window.y))
	var wide := float(maxi(window.x, window.y)) / maxf(1.0, short) >= 1.7
	return short / (PHONE_INCHES if wide else TABLET_INCHES)


## How many game pixels `mm` millimetres take on a screen of `dpi` drawing each game pixel `scale` screen pixels wide.
static func fingertip_for(dpi: float, scale: float, mm := FINGERTIP_MM) -> float:
	return mm / 25.4 * dpi / maxf(0.01, scale)


## Whether the normal text would be too small to read, so the game starts on large text.
static func large_text(dpi: float, scale: float) -> bool:
	return 25.4 * scale / maxf(1.0, dpi) < LARGE_TEXT_BELOW_MM


## The insets from the top-left and bottom-right in game pixels: clear of the camera, and of rounded corners the safe area leaves in.
static func insets_for(window: Vector2i, safe: Rect2i, scale: Vector2) -> Array:
	var corner := ceilf(mini(window.x, window.y) * CORNER_SHARE)
	var tl := Vector2(maxf(safe.position.x, corner), maxf(safe.position.y, corner))
	var br := Vector2(maxf(window.x - safe.end.x, corner), maxf(window.y - safe.end.y, corner))
	return [(tl / scale).ceil(), (br / scale).ceil()]


## The march a thumb `offset` from the stick's centre asks for: nothing inside the dead zone, rising to full speed near the rim.
static func stick_vector(offset: Vector2, radius: float) -> Vector2:
	var reach := offset.length() / maxf(1.0, radius)
	if reach <= DEAD:
		return Vector2.ZERO
	return offset.normalized() * clampf((reach - DEAD) / (FULL - DEAD), 0.0, 1.0)


## Where the stick's centre goes as the finger moves: it stays put while the finger is inside the rim and is dragged along past it.
static func stick_follow(base: Vector2, finger: Vector2, radius: float) -> Vector2:
	var off := finger - base
	if off.length() <= radius:
		return base
	return finger - off.normalized() * radius


## Whether a touch at `p` takes the stick: anywhere on the left part of the screen.
static func in_stick_zone(p: Vector2, view: Vector2) -> bool:
	return p.x < view.x * STICK_SHARE


## Each action's round button as {id: {centre, radius}}: the testudo above the favour, the others round it, pause at the top right.
static func button_layout(view: Vector2, tl: Vector2, br: Vector2, tip: float, favour_top: float, top: float) -> Dictionary:
	var big := tip * TESTUDO_SIZE / 2.0
	var r := tip / 2.0
	var gap := tip * GAP
	var margin := maxf(3.0, tip * 0.1)
	var c := Vector2(view.x - br.x - margin - big, favour_top - margin - big)
	var d := big + gap + r
	var slant := Vector2.from_angle(deg_to_rad(222.0)) * d
	var out := {
		"testudo": {"centre": c, "radius": big},
		"pray": {"centre": c + Vector2(-d, big - r), "radius": r},
		"build": {"centre": c + slant, "radius": r},
		"wall": {"centre": c + Vector2(0, -d), "radius": r},
		"bridge": {"centre": c + Vector2(0, -d - 2.0 * r - gap), "radius": r},
		"pause": {"centre": Vector2(view.x - br.x - margin - r, maxf(top, tl.y) + margin + r), "radius": r},
	}
	return out


## The button a touch at `p` lands on, the nearest when it lands between two, or "" for none.
static func button_at(layout: Dictionary, p: Vector2) -> String:
	var best := ""
	var nearest := INF
	for id in layout:
		var d: float = p.distance_to(layout[id].centre)
		if d <= layout[id].radius + 2.0 and d < nearest:
			nearest = d
			best = id
	return best


## What the back gesture does in a state: "pause", "not_now", "skip", "back", "background" or "none" while a level-up or a supply cart waits.
static func back_step(state: String, revealing: bool) -> String:
	match state:
		"play":
			return "pause"
		"pray":
			return "not_now"
		"choose", "supply":
			return "none"
		"title":
			return "background"
		"over":
			return "skip" if revealing else "back"
		"camp", "quartermaster", "tablinum", "map", "commanders", "settings", "saves", "pause":
			return "back"
	return "none"


## Whether a back gesture at `now_ms` counts, or is Android's second report of the one at `last_ms`.
static func back_counts(now_ms: int, last_ms: int) -> bool:
	return now_ms - last_ms > BACK_REPEAT_MS


## Whether a tap acts at once; one that spends denarii or takes a choice acts only once the last tap (`picked`) picked it out, so it is read first.
static func tap_acts(state: String, id: String, picked: String) -> bool:
	if id.begins_with("buy:") or id.begins_with("see:") or id.begins_with("choice:"):
		return id == picked
	return true


## Whether a finger lifted after sliding `moved` game pixels was a tap rather than a drag.
static func is_tap(moved: float, slop_px: float) -> bool:
	return moved <= slop_px
