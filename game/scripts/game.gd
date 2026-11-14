class_name Game
extends RefCounted
## What the build is: the free demo or the full game, and the limits the demo puts on the map, the commanders and the run.


## Set by the tests to play as the demo without a command-line flag.
static var demo_forced := false


## Whether this is the demo: the project exported with the "demo" feature, or started with --as-demo.
static func is_demo() -> bool:
	return demo_forced or OS.has_feature("demo") or "--as-demo" in OS.get_cmdline_user_args()


## The commanders this build lists: every one whose art is drawn, and in the demo only the first few of them.
static func commanders(content: Content, balance: Dictionary) -> Array:
	var ids: Array = []
	for id in content.commanders:
		if content.ready("commanders", id):
			ids.append(id)
	if is_demo():
		ids = ids.slice(0, int(balance.demo.commanders))
	return ids


## Whether this build can play the province.
static func province_allowed(id: String, balance: Dictionary) -> bool:
	return not is_demo() or id == str(balance.demo.province)


## The run's length limit in seconds, or 0 for none.
static func run_cap(balance: Dictionary) -> float:
	return float(balance.demo.seconds) if is_demo() else 0.0
