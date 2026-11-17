extends SceneTree
## Plays whole runs headless with four bots (standing still, marching straight, circling, turning to face the crowd, and facing with recruits first until the legion has 30)
## and prints when each dies, for tuning balance.json. Optional overrides go in tests/balance_overrides.json.
## `"upgrades": "two_thirds"` (or --upgrades=two_thirds) plays with every quartermaster upgrade at two-thirds of its ranks, as a player well into the game.
## `--upgrades=full` plays with every upgrade at its last rank and three triumphs, as the most upgraded player.
## `--until=SECONDS` ends each run there (default 1200), so a round that only asks who reaches 12:00 can stop at 720.

func run(balance: Dictionary, content: Content, seed: int, mode: String, province := "germania", bonuses := {}, until := 1200.0) -> String:
	var sim := Sim.new(balance, content, {"seed": seed, "province": province, "profile_bonuses": bonuses})
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var dt := 1.0 / 30.0
	var hp_at := {}
	var low_late := 9999.0
	while not sim.over and sim.time < until:
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
		# Every bot but the one standing still calls a god as soon as the favour fills.
		if mode != "idle" and sim.gods.full(sim.b):
			var gods := Gods.offers(sim)
			if not gods.is_empty():
				sim.gods.invoke(sim, gods[rng.randi_range(0, gods.size() - 1)])
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
			hp_at[m] = "%d:%d/%d/%d/p%.2f/k%.1f/v%d" % [m, sim.commander.hp, sim.soldiers.size(), sim.horde.e_pos.size(), sim.horde.pursuit, sim.horde.kill_rate, sim.horde.march_speed]
	return ("low_late=%.2f " % low_late) + "%-6s seed %d %s t=%4d lvl=%2d kills=%5d gods=%d  %s" % [mode, seed, "WIN " if sim.victory else "dead", sim.time, sim.level, sim.kills, sim.gods.calls, " ".join(hp_at.values().slice(0, 12))]


func _init() -> void:
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var over: Dictionary = {}
	# --overrides=PATH reads another file in place of balance_overrides.json, so rounds trying different numbers can run at once.
	var over_path := "res://tests/balance_overrides.json"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--overrides="):
			over_path = a.trim_prefix("--overrides=")
	if FileAccess.file_exists(over_path):
		over = JSON.parse_string(FileAccess.get_file_as_string(over_path))
	balance.merge(over.get("balance", {}), true)
	var content := Content.load_all(Content.available_art())
	content.base_commander.merge(over.get("commander", {}), true)
	for k in over.get("enemies", {}):
		content.enemies[k].merge(over.enemies[k], true)
	# Flags after `--` (--province=gaul --modes=face,smart --seeds=1,2,3) take the place of the file's keys, so several runs can go at once.
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=")
		if kv.size() == 2 and kv[0] == "province":
			over.province = kv[1]
		elif kv.size() == 2 and kv[0] == "modes":
			over.modes = Array(kv[1].split(","))
		elif kv.size() == 2 and kv[0] == "upgrades":
			over.upgrades = kv[1]
		elif kv.size() == 2 and kv[0] == "until":
			over.until = float(kv[1])
		elif kv.size() == 2 and kv[0] == "seeds":
			over.seeds = Array(kv[1].split(",")).map(func(x: String) -> int: return int(x))
	var bonuses := {}
	if over.get("upgrades", "") == "two_thirds":
		for id in content.quartermaster:
			if not content.quartermaster[id].get("repeat", false):
				bonuses[id] = roundi(int(content.quartermaster[id].ranks) * 2.0 / 3.0)
	elif over.get("upgrades", "") == "full":
		for id in content.quartermaster:
			bonuses[id] = 3 if content.quartermaster[id].get("repeat", false) else int(content.quartermaster[id].ranks)
	for mode in over.get("modes", ["idle", "straight", "circle", "face", "smart"]):
		for seed in over.get("seeds", [1, 2, 3, 4, 5, 6]):
			print(run(balance, content, seed, mode, str(over.get("province", "germania")), bonuses, float(over.get("until", 1200.0))))
	quit()
