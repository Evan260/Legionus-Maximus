extends SceneTree
## Plays whole runs headless with four bots (standing still, marching straight, circling, turning to face the crowd, and facing with recruits first until the legion has 30)
## and prints when each dies, for tuning balance.json. Optional overrides go in tests/balance_overrides.json.

func run(balance: Dictionary, content: Content, seed: int, mode: String) -> String:
	var sim := Sim.new(balance, content, {"seed": seed})
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var dt := 1.0 / 30.0
	var hp_at := {}
	var low_late := 9999.0
	while not sim.over and sim.time < 1200.0:
		var move := Vector2.ZERO
		if mode == "face" or mode == "smart":
			# Turn the front to the thickest crowd close by, then step back so the shields meet it.
			var sum := Vector2.ZERO
			for t in sim.horde.e_pos.size():
				var off: Vector2 = sim.horde.e_pos[t] - sim.commander.pos
				if off.length() < 140.0:
					sum += off.normalized()
			if sum.length() > 0.5:
				var want := sum.normalized()
				var ahead := Vector2.from_angle(sim.facing_angle)
				move = want * 0.3 if ahead.dot(want) < 0.9 else -want * 0.25
		elif mode == "straight":
			move = Vector2.RIGHT
		elif mode == "circle":
			move = Vector2(cos(sim.time * 0.4), sin(sim.time * 0.4))
		sim.update(dt, move, mode != "idle" and sim.testudo_charge >= 1.0 and sim.commander.hp < sim.commander.max_hp * 0.5)
		while sim.pending_levels > 0 or sim.free_choices > 0:
			var picks := Upgrades.next_choices(sim)
			if picks.is_empty():
				break
			var pick: String = picks[rng.randi_range(0, picks.size() - 1)]
			if mode == "smart":
				for id in picks:
					if sim.content.recruits.has(id) and sim.soldiers.size() < 30:
						pick = id
			Upgrades.apply(sim, pick)
		if sim.time > 300.0:
			low_late = minf(low_late, sim.commander.hp / sim.commander.max_hp)
		var m := int(sim.time / 60.0)
		if not hp_at.has(m):
			hp_at[m] = "%d:%d/%d/%d" % [m, sim.commander.hp, sim.soldiers.size(), sim.horde.e_pos.size()]
	return ("low_late=%.2f " % low_late) + "%-6s seed %d %s t=%4d lvl=%2d kills=%5d  %s" % [mode, seed, "WIN " if sim.victory else "dead", sim.time, sim.level, sim.kills, " ".join(hp_at.values().slice(0, 12))]


func _init() -> void:
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var over: Dictionary = {}
	if FileAccess.file_exists("res://tests/balance_overrides.json"):
		over = JSON.parse_string(FileAccess.get_file_as_string("res://tests/balance_overrides.json"))
	balance.merge(over.get("balance", {}), true)
	var content := Content.load_all(Content.available_art())
	content.base_commander.merge(over.get("commander", {}), true)
	for k in over.get("enemies", {}):
		content.enemies[k].merge(over.enemies[k], true)
	for mode in over.get("modes", ["idle", "straight", "circle", "face", "smart"]):
		for seed in over.get("seeds", [1, 2, 3, 4, 5]):
			print(run(balance, content, seed, mode))
	quit()
