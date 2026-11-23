extends SceneTree
## Plays headless runs and counts barbarians who try to walk but stay put for over a second with no Roman in reach, sorted by what holds them.
## Flags after `--`: --province=ID, --seeds=N, --seconds=S, --mode=circle|face|straight.

const SAMPLE := 0.25
const WINDOW := 4
const STILL_PX := 4.0


func _class(sim: Sim, i: int) -> String:
	var h := sim.horde
	var p: Vector2 = h.e_pos[i]
	var r: float = h.k_radius[h.e_kind[i]]
	var tag := ("boss " if h.e_tag[i] != Horde.ORDINARY else "") + ("" if sim.terrain.is_open(p) else "closed ")
	if sim.terrain.ravine_edge(p, 300.0) < r + 6.0:
		return tag + "ravine"
	if sim.terrain.in_field(p, r + 6.0):
		return tag + "wheat"
	for pr in sim.terrain.props_in(Rect2(p - Vector2(60, 60), Vector2(120, 120))):
		if pr[2] > 0.0 and p.distance_to(pr[1]) < pr[2] + r + 6.0:
			return tag + ("blocker" if pr[0] == "" else str(pr[0]))
	for post in sim.terrain.posts:
		if p.distance_to(post[1]) < post[2] + r + 6.0:
			return tag + "post"
	var d: float = p.distance_to(sim.commander.pos)
	if d < sim.legion_reach + 40.0:
		return tag + "crowd at legion"
	var near := 0
	for t in h.e_pos.size():
		if t != i and h.e_pos[t].distance_to(p) < r * 2.5:
			near += 1
	return tag + ("crowd" if near >= 3 else "open")


func probe(balance: Dictionary, content: Content, seed: int, province: String, seconds: float, mode: String) -> Dictionary:
	var sim := Sim.new(balance, content, {"seed": seed, "province": province})
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var dt := 1.0 / 30.0
	var hist := {}
	var counted := {}
	var found := {}
	var next := SAMPLE
	while not sim.over and sim.time < seconds:
		var move := Vector2(cos(sim.time * 0.4), sin(sim.time * 0.4))
		if mode == "straight":
			move = Vector2.RIGHT
		elif mode == "face":
			var sum := Vector2.ZERO
			for t in sim.horde.e_pos.size():
				var off: Vector2 = sim.horde.e_pos[t] - sim.commander.pos
				if off.length() < 140.0:
					sum += off.normalized()
			move = Vector2.ZERO
			if sum.length() > 0.5:
				var want := sum.normalized()
				move = want * 0.3 if Vector2.from_angle(sim.facing_angle).dot(want) < 0.9 else -want * 0.25
		# The commander keeps full health so the probe sees the whole span.
		sim.commander.hp = sim.commander.max_hp
		sim.update(dt, move, false)
		while not sim.supplies.is_empty():
			sim.take_supply(sim.bot_supply())
		while sim.pending_levels > 0 or sim.free_choices > 0:
			var picks := Upgrades.next_choices(sim)
			if picks.is_empty():
				break
			Upgrades.apply(sim, picks[rng.randi_range(0, picks.size() - 1)])
		if sim.time < next:
			continue
		next += SAMPLE
		var h := sim.horde
		for i in h.e_pos.size():
			var id: int = h.e_id[i]
			var p: Vector2 = h.e_pos[i]
			var r: float = h.k_radius[h.e_kind[i]]
			var reach := false
			for u in sim.units:
				if (u.pos - p).length() < r + Sim.UNIT_RADIUS + 10.0:
					reach = true
					break
			var ok: bool = h.e_fighting[i] == 0 and h.e_guard[i] == Vector2.ZERO and not reach and h.e_stun[i] <= 0.0
			var list: Array = hist.get(id, [])
			if not ok:
				list.clear()
			else:
				list.append(p)
				if list.size() > WINDOW + 1:
					list.pop_front()
			hist[id] = list
			if list.size() == WINDOW + 1:
				var spread := 0.0
				for q in list:
					spread = maxf(spread, q.distance_to(list[0]))
				if spread < STILL_PX and not counted.get(id, false):
					counted[id] = true
					var c := _class(sim, i)
					if OS.get_environment("PROBE_DETAIL") != "" and found.size() < 40:
						var near := []
						for pr in sim.terrain.props_in(Rect2(p - Vector2(40, 40), Vector2(80, 80))):
							if pr[2] > 0.0 and p.distance_to(pr[1]) < 40.0:
								near.append("%s@%s r%.0f" % [pr[0], (pr[1] - p).round(), pr[2]])
						print("  t=%.1f %s p=%s r=%.0f to=%s flow=%s det=%.2f way=%s stuck=%.2f pace=%.1f kind=%s open=%s age=%d near=%s" % [sim.time, c, p.round(), r, (sim.commander.pos - p).round(), sim.terrain.flow_at(p), h.e_detour[i], h.e_way[i], h.e_stuck[i], h.e_pace[i], h.kind_ids[h.e_kind[i]], sim.terrain.is_open(p), id, near])
					found[c] = int(found.get(c, 0)) + 1
				elif spread >= STILL_PX:
					counted[id] = false
	return found


func _init() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv: PackedStringArray = a.trim_prefix("--").split("=")
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var balance: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/balance.json"))
	var content := Content.load_all(Content.available_art())
	var province: String = args.get("province", "germania")
	var total := {}
	for seed in range(1, int(args.get("seeds", "8")) + 1):
		var f := probe(balance, content, seed, province, float(args.get("seconds", "240")), args.get("mode", "circle"))
		print("seed %d %s" % [seed, f])
		for k in f:
			total[k] = int(total.get(k, 0)) + f[k]
	var sum := 0
	for k in total:
		sum += total[k]
	print("TOTAL %s %d %s" % [province, sum, total])
	quit()
