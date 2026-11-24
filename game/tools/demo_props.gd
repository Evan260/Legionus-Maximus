extends SceneTree
## Fails when the demo's copy of the game lacks a picture the demo needs: its province, that province's enemies and the
## commanders it lists must all be drawn, and every prop the province's field and fort place must be in the atlas.
## tools/demo_stage.py runs it on the copy it makes.
##   Godot --headless --path COPY --script res://tools/demo_props.gd

const SEEDS := 8
const FIELD := Rect2(-2500, -2500, 5000, 5000)


func _init() -> void:
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var content := Content.load_all(Content.available_art())
	var atlas: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/atlas.json"))
	var province := str(balance.demo.province)
	var info: Dictionary = content.provinces.get(province, {})
	var missing: Array = []
	var needed := [["provinces", province]]
	for id in info.get("ordinary", []) + info.get("elites", []) + [info.get("chieftain", "")]:
		needed.append(["enemies", id])
	for id in content.commanders:
		needed.append(["commanders", id])
	for n in needed:
		if not content.ready(n[0], n[1]):
			missing.append("%s %s" % n)
	for seed in SEEDS:
		var s := Sim.new(balance, content, {"seed": seed + 1, "province": province})
		s.objectives.raise_fort(s)
		var kinds: Array = s.terrain.props_in(FIELD).map(func(p: Array) -> String: return str(p[0]))
		kinds.append_array(s.objectives.list.map(func(o: Dictionary) -> String: return str(o.get("centre", ""))))
		for k in kinds:
			if k != "" and not atlas.props.has(k) and not missing.has("prop " + k):
				missing.append("prop " + k)
	for m in missing:
		printerr("the demo lacks the picture of ", m)
	quit(0 if missing.is_empty() else 1)
