class_name Horde
extends RefCounted
## The enemy side of a run: every barbarian as packed arrays on a flat grid, their behaviours, elites, the chieftain, thrown spears, chests and supply carts.

const CELL := 32.0
const GW := 48
const MELEE := 0
const RANGED := 1
const CHARGER := 2
const BEAST := 3
const LOBBER := 4
const FLANKER := 5
const DRIVER := 6
const BEHAVIOURS := {"melee": MELEE, "ranged": RANGED, "charger": CHARGER, "beast": BEAST, "lobber": LOBBER, "flanker": FLANKER, "driver": DRIVER}
## What a supply cart offers, in the order its choice lists them.
const CART_REWARDS := ["free_choice", "heal", "magnet"]
## Below this real speed in pixels a second a barbarian counts as standing still.
const STILL_PACE := 8.0
## How long a barbarian locked in melee keeps facing one way before he turns to another foe, in seconds.
const TURN_HOLD := 0.6
const ORDINARY := 0
const ELITE := 1
const CHIEF := 2

var b: Dictionary
var content: Content
var rng: RandomNumberGenerator
var commander: Dictionary
var province: String
## The size of the view in world pixels, which Ui.fit_view keeps up to date, so the headless bots that cannot load Ui still spawn beyond the screen.
static var view := Vector2(640, 360)
var time := 0.0

# Per kind, indexed by e_kind. Every enemy in content.json has a slot, whether or not it is drawn yet.
var kind_ids: Array = []
var kind_of := {}
var k_radius := PackedFloat32Array()
var k_speed := PackedFloat32Array()
var k_dps := PackedFloat32Array()
var k_beh := PackedByteArray()
var k_range := PackedFloat32Array()
var k_dash_every := PackedFloat32Array()
var k_dash_mult := PackedFloat32Array()
## The fastest an enemy of the kind can go on his own: his walk, or his charge where he has one.
var k_top := PackedFloat32Array()
var k_dash_secs := PackedFloat32Array()
var k_burst := PackedFloat32Array()
var k_flank_cos := PackedFloat32Array()
var k_flank_gap := PackedFloat32Array()
# A swordsman's wide slash: seconds between slashes (0 for kinds without one), damage as a multiple of dps, arc and reach.
var k_slash_every := PackedFloat32Array()
var k_slash_mult := PackedFloat32Array()
var k_slash_arc := PackedFloat32Array()
var k_slash_reach := PackedFloat32Array()
# How far beside the legion, as a share of its reach, a flank rider aims his charge; 0 for a straight charge.
var k_flank_off := PackedFloat32Array()
# An archer's volley: the radius of the ring his arrows fall in (0 for kinds that throw), its delay and damage share.
var k_volley_r := PackedFloat32Array()
var k_volley_delay := PackedFloat32Array()
var k_volley_mult := PackedFloat32Array()
# Seconds a rushing beast is stunned when its rush hits a solid prop; 0 for kinds that do not rush.
var k_rush_stun := PackedFloat32Array()
# 1 for a lobber that throws pots; a horn blower stands off like one but throws nothing.
var k_lob := PackedByteArray()
var k_flee_mult := PackedFloat32Array()
# Seconds between an ordinary enemy's own blows or calls: the falx warrior's chop, the bear's maul, the draco bearer's howl; 0 for the rest.
var k_beat := PackedFloat32Array()
# 1 for a falx warrior, whose blows cut through shields and armour, and his heavy chop as a multiple of dps.
var k_falx := PackedByteArray()
var k_falx_mult := PackedFloat32Array()
# A bear's maul: damage as a multiple of dps, the reach round the soldier it strikes and how far it throws them.
var k_maul_mult := PackedFloat32Array()
var k_maul_r := PackedFloat32Array()
var k_maul_throw := PackedFloat32Array()
# 1 for a draco bearer, who howls instead of fighting with a beat of his own.
var k_howl := PackedByteArray()
# Arrows each archer looses in a salvo (0 for kinds that do not), and how far apart they spread.
var k_salvo := PackedInt32Array()
var k_salvo_spread := PackedFloat32Array()
# A horse archer rides away while soldiers are this close beyond the legion's edge, at this multiple of his pace; 0 for kinds that stand and fight.
var k_kite := PackedFloat32Array()
var k_kite_mult := PackedFloat32Array()
# 1 for a cataphract, whose dash is a lowered lance, and the share of an arrow's harm his armour turns.
var k_lance := PackedByteArray()
var k_armour := PackedFloat32Array()
# Stones each slinger looses at once (0 for kinds that do not) and how far apart they spread.
var k_sling := PackedInt32Array()
var k_sling_spread := PackedFloat32Array()
# A painted warrior's charge goes straight through the crowd and ends in a battle cry.
var k_fearless := PackedByteArray()
# Throwers whose salvo is sling stones instead of arrows.
var k_salvo_stone := PackedByteArray()
# How often a druid acolyte tends the wounded round him, how far he reaches and the share of health he gives back.
var k_tend := PackedFloat32Array()
var k_tend_r := PackedFloat32Array()
var k_tend_share := PackedFloat32Array()
# A chariot's pass beside the legion: how far out it passes, how fast it turns, how near it holds its line, how far past it runs before turning,
# how often its javelins fly and from how far, and the chance it carries warriors to set down.
var k_pass_gap := PackedFloat32Array()
var k_pass_turn := PackedFloat32Array()
var k_pass_lock := PackedFloat32Array()
var k_pass_far := PackedFloat32Array()
var k_pass_every := PackedFloat32Array()
var k_pass_range := PackedFloat32Array()
var k_drop := PackedFloat32Array()
# 1 for a kind that fights on foot, whose pace is held below the legion's march; beasts, riders, chariots and bosses are not.
var k_foot := PackedByteArray()
## 1 for chariots and riders, whose passes carry them far out and back, so they never give up the chase.
var k_rides := PackedByteArray()
# How far out from the legion's ranks a foot warrior starts his charge or sprint, so it is a lunge and never a way to run the legion down; -1 for the rest.
var k_dash_reach := PackedFloat32Array()
# How often a kind is picked from the later stream against the others (1 by default), how many of it may be alive at once (0 for no limit), and how many are.
var k_share := PackedFloat32Array()
var k_most := PackedInt32Array()
var k_alive := PackedInt32Array()
## The radius of the biggest kind of enemy, so searches by edge reach far enough while one that size is on the field.
var max_radius := 0.0
## How many enemies wider than Terrain.MAX_UNIT are on the field.
var big_alive := 0

# Per enemy.
var e_id := PackedInt32Array()
var e_pos := PackedVector2Array()
var e_face := PackedVector2Array()
var e_hp := PackedFloat32Array()
var e_max := PackedFloat32Array()
var e_kind := PackedInt32Array()
var e_burn := PackedFloat32Array()
var e_burn_dps := PackedFloat32Array()
var e_burn_src := PackedInt32Array()
var e_flash := PackedFloat32Array()
var e_phase := PackedInt32Array()
var e_fighting := PackedByteArray()
# 1 while a horse archer rides away from soldiers who closed in, until he is `kite_out` px clear of where he turned.
var e_kiting := PackedByteArray()
# When each enemy last turned to face another way, so one locked in melee does not turn again too soon.
var e_turned := PackedFloat32Array()
# When each enemy last threw, lobbed or struck a single blow, for its attack animation.
var e_strike := PackedFloat32Array()
var e_stun := PackedFloat32Array()
var e_slow := PackedFloat32Array()
var e_push := PackedVector2Array()
## How far the men between a barbarian and the legion overlap him, which stops him walking on into them.
var e_block := PackedFloat32Array()
var e_tag := PackedByteArray()
var e_cd := PackedFloat32Array()
var e_dash := PackedFloat32Array()
# Throws left before a ranged enemy closes in to fight hand to hand.
var e_ammo := PackedInt32Array()
# Seconds left walking round an obstacle, which way round (1 or -1), and the outward face of what he last touched.
var e_detour := PackedFloat32Array()
var e_side := PackedInt32Array()
var e_way := PackedVector2Array()
var e_dir := PackedVector2Array()
var e_haste := PackedFloat32Array()
# How much faster each hastened barbarian runs while his `e_haste` lasts.
var e_haste_mult := PackedFloat32Array()
# A bodyguard's place beside the chieftain, or zero for everyone else.
var e_guard := PackedVector2Array()
# Seconds spent failing to make headway (counting up), or, below zero, seconds left slipping through the trees to get free.
var e_stuck := PackedFloat32Array()
# Seconds left running away from the legion, for a horn blower whom soldiers have reached.
var e_flee := PackedFloat32Array()
# 1 while a barbarian is trying to walk somewhere this update, and his real speed over the last moments in pixels a second, so one held in place shows his stance.
var e_want := PackedByteArray()
var e_pace := PackedFloat32Array()
var next_id := 1
var chieftain_id := -1

# The horde is sorted into a flat grid of cells around the commander, rebuilt every update.
var g_origin := Vector2i.ZERO
var g_start := PackedInt32Array()
var g_items := PackedInt32Array()
# The radius of each enemy in g_items, in the same order, so spacing reads it without going through its kind.
var g_rad := PackedFloat32Array()
var _g_cell := PackedInt32Array()
var _g_fill := PackedInt32Array()

var ordinary: Array = []
var elites: Array = []
var chief_kind := ""
var spawn_acc := 0.0
var cart_tip_shown := false
## Ordinary enemies on the screen or just off it, counted at the start of each spawn step and raised by every newcomer.
var crowd := 0
var next_surge := 0.0
var next_cart := 0.0
var next_band := 0.0
## Where the commander stood each of the last seconds, oldest first, to see whether he is marching round in a loop.
var trail := PackedVector2Array()
var next_trail := 0.0
var frame := 0
var cleave_cd := 0.0
var cry_cd := 0.0
# When the pack may next be heard biting.
var bite_cd := 0.0
var charge_cd := 0.0
var slam_cd := 0.0
var horn_cd := 0.0
var summon_cd := 0.0
var siege_cd := 0.0
# The chieftain's sworn guards still alive, and the share of harm they turn from him while at least sworn_min stand.
var guards_alive := 0
var sworn_min := 0
var sworn_cut := 0.0
# Seconds left of a carnyx blast's slowing of the legion's blows, and how much it slows them.
var blast_left := 0.0
var blast_slow := 0.0
var charge_warn := 0.0
var charge_total := 0.0
var charge_from := Vector2.ZERO
var charge_dir := Vector2.ZERO
var charge_len := 0.0
var charge_width := 0.0
var charging := false
var charge_n := 0
var chief_hold := 0.0
var hold_pos := Vector2.ZERO
var sp_pos := PackedVector2Array()
var sp_vel := PackedVector2Array()
var sp_dmg := PackedFloat32Array()
var sp_life := PackedFloat32Array()
# 0 for a thrown axe, 1 for an arrow, 2 for a sling stone.
var sp_kind := PackedByteArray()
# How long a sling stone leaves the soldier it strikes reeling.
var sling_stun := 0.0
# The archers' salvo drum: seconds between salvos (0 where no archer looses them), seconds to the next, and whether it beats this update.
var salvo_every := 0.0
var salvo_cd := 0.0
var salvo_now := false
var _salvo_fired := 0
# When a draco's howl may next be heard.
var howl_cd := 0.0
# When a painted warrior's battle cry or an acolyte's chant was last heard, so a crowd of them sounds as one.
var cry_heard := 0.0
var tend_heard := 0.0
# Blizzards called by the priests, each {pos, radius, t, life, slow, dps}, and how much the one the commander stands in slows the march.
var storms: Array = []
var frost_slow := 0.0
# The Dacian king's timers, the sweep he is winding up ({pos, dir, t, dur, reach, arc, dmg} or empty), and his leap ({from, to, t, dur} or empty).
var sweep_cd := 0.0
var rockfall_cd := 0.0
var leap_cd := 0.0
var sweep := {}
var leap := {}
# The king's wall of guards, from content.json: how many must stand, the arc they hold before him, the share of a blow from in front they turn and how far out they stand.
var king_wall := {}
# The shah's arrow storm: {left, quiver, next, riders, train, waiting} while it rages, or empty; and when the next may start.
var arrow_storm := {}
var storm_cd := 0.0
## The warrior queen's sweeping chariot drive round the legion: its path, the time since it was marked, the warning, its speed and its count.
var drive := {}
var drive_cd := 0.0
var drive_n := 0
var tribes_cd := 0.0
var burn_cd := 0.0
## The shepherd general's ambush: when the next is called, and the seconds left before the bands it warned of break cover.
var ambush_cd := 0.0
var ambush_wait := 0.0
## His feigned flight while he runs, as {left, from: where the commander stood, dir: the way he runs}, and when the next may start.
var feint := {}
var feint_cd := 0.0
## When his hidden men next hurl javelins on marked rings.
var javelins_cd := 0.0
## The Egyptian general's timers for his marked arrow volleys and for opening the sluices.
var volleys_cd := 0.0
var sluice_cd := 0.0
## The flooded band he opens across the legion's path, {pos, dir: along the band, half_len, half_w, t, warn, seconds, slow, open}, or empty;
## and how much the water the commander stands in slows the march.
var flood := {}
var flood_slow := 0.0
var chests: Array = []
var elite_ids: Array = []
## The elites that came on the boss timer, as opposed to an objective's defenders.
var timed_ids: Array = []
var chief_dead := false
# How many rockfalls and marked volleys have come down, so each soldier is struck once by each at most.
var volley_ids := 0
# The ids of the barbarians who gave up the chase this update, taken away once the legion has fought.
var _gave_up: Array = []
## The run's difficulty: "easy", "medium" or "hard".
var run_difficulty := "medium"
var sim_ref: WeakRef
var carts: Array = []
# Burning pots thrown by war priests: each lands where a red ring marks it and hurts every Roman inside.
var foe_lobs: Array = []
# Seconds until each rallying elite, by enemy id, shouts again.
var rally_cd := {}
var next_boss := 0.0
# Telegraphs of the war priests' mending and curses, each resolving when it has filled.
var marks: Array = []
# Seconds left of a war priest's curse on the legion, and how much it slows the march.
var curse_left := 0.0
var curse_slow := 0.0
var chief_fury := false
# How much faster a raging boss moves; 1 for everyone else.
var e_fury := PackedFloat32Array()
# How hard an elite hits: softer for those who come early, harder in a rage; 1 for everyone else.
var e_power := PackedFloat32Array()
## 1 for a hunter sent after a running legion, who carries no coins.
var e_bare := PackedByteArray()
## When each enemy was last tended by a druid acolyte, so several acolytes round one warrior heal him no faster than one.
var e_tended := PackedFloat32Array()
## Until when each warrior is hardened by a priest of Sobek's blessing, and the share of each blow it turns.
var e_ward := PackedFloat32Array()
# Which way the last blow that reached each enemy was travelling, or zero, so he falls away from it.
var e_hit := PackedVector2Array()
var ward_cut := 0.0
## The Roxolani king's timers for his lancer sweep and for setting the steppe alight.
var lancers_cd := 0.0
var fire_cd := 0.0
## His lancers' sweep while it is marked or running, {from, dir, length, width, t, warn, seconds, riders: [[id, place across the lane]], n, damage, throw}, or empty.
var wave := {}
var wave_n := 0
## The band of grass he sets alight, {pos: the edge it starts from, dir: the way it spreads, half_len, depth, t, warn, seconds, burn, dps, lit}, or empty.
var steppe_fire := {}
## The lassos being swung, as {id: the rider, unit: the soldier he aims at, t, dur}.
var lassos: Array = []
# Seconds between a lasso rider's throws and how far he throws, 0 for the rest; 1 for a kind the crowd cannot shove aside.
var k_lasso := PackedFloat32Array()
var k_lasso_reach := PackedFloat32Array()
var k_heavy := PackedByteArray()
# Each elite's own ability timers and state, by enemy id, since there are only ever a few of them.
var boss := {}
## How hard the horde hunts a legion that keeps marching without fighting, or never moves: 1 brings hunters from all round, and it climbs on to `cap`.
var pursuit := 0.0
## The kills a second and the march speed, each averaged over the last few seconds, and the way the legion is heading.
var kill_rate := 0.0
var march_speed := 0.0
var heading := Vector2.ZERO
var _p_next := 0.0
var _p_from := Vector2.INF
var _p_kills := 0
## Hunters killed, left out of the kill rate so killing them never calls the hunt off.
var bare_kills := 0
var next_hunt := 0.0


func _init(balance: Dictionary, game_content: Content, random: RandomNumberGenerator, commander_unit: Dictionary, province_id: String) -> void:
	b = balance
	content = game_content
	rng = random
	commander = commander_unit
	province = province_id
	var ch: Dictionary = b.charger
	for id in content.enemies:
		var info: Dictionary = content.enemies[id]
		kind_of[id] = kind_ids.size()
		kind_ids.append(id)
		var beh: int = BEHAVIOURS.get(info.behaviour, MELEE)
		k_radius.append(float(info.radius))
		max_radius = maxf(max_radius, float(info.radius))
		k_speed.append(float(info.speed) * float(b.get("enemy_speed_mult", 1.0)))
		k_dps.append(float(info.dps))
		k_beh.append(beh)
		k_range.append(float(info.get("range", 0.0)))
		var every := 0.0
		var mult := 1.0
		var secs := 0.0
		var burst := 0.0
		if info.has("attacks") and info.attacks.has("charge"):
			var c: Dictionary = info.attacks.charge
			every = float(c.every)
			mult = float(c.speed_mult)
			secs = float(c.seconds)
			burst = float(info.dps) * float(c.burst_mult)
		elif info.has("lance"):
			every = float(info.lance.every)
			mult = float(info.lance.speed_mult)
			secs = float(info.lance.seconds)
			burst = float(info.dps) * float(info.lance.burst_mult)
		elif info.has("rush"):
			every = float(info.rush.every)
			mult = float(info.rush.speed_mult)
			secs = float(info.rush.seconds)
			burst = float(info.dps) * float(info.rush.burst_mult)
		elif info.has("fearless"):
			every = float(info.fearless.every)
			mult = float(info.fearless.speed_mult)
			secs = float(info.fearless.seconds)
			burst = float(info.dps) * float(info.fearless.burst_mult)
		elif info.has("sprint"):
			every = float(info.sprint.every)
			mult = float(info.sprint.speed_mult)
			secs = float(info.sprint.seconds)
		elif beh == CHARGER:
			every = float(ch.every)
			mult = float(ch.speed_mult)
			secs = float(ch.seconds)
			burst = float(info.dps) * float(ch.burst_seconds)
		k_dash_every.append(every)
		k_dash_mult.append(mult)
		k_top.append(float(info.speed) * maxf(1.0, mult))
		k_dash_secs.append(secs)
		k_burst.append(burst)
		var flank: Dictionary = info.get("flank", {})
		k_flank_cos.append(cos(float(flank.get("arrive", 0.0))))
		k_flank_gap.append(float(flank.get("gap", 1.0)))
		# A camel rider's spear thrust is a narrow, long slash.
		var slash: Dictionary = info.get("slash", info.get("thrust", {}))
		k_slash_every.append(float(slash.get("every", 0.0)))
		k_slash_mult.append(float(slash.get("damage_mult", 0.0)))
		k_slash_arc.append(float(slash.get("arc", 0.0)))
		k_slash_reach.append(float(slash.get("reach", 0.0)))
		k_flank_off.append(float(info.get("flank_charge", {}).get("offset", 0.0)))
		var volley: Dictionary = info.get("volley", {})
		k_volley_r.append(float(volley.get("radius", 0.0)))
		k_volley_delay.append(float(volley.get("delay", 0.0)))
		k_volley_mult.append(float(volley.get("damage_mult", 0.0)))
		k_rush_stun.append(float(info.get("rush", {}).get("stun", 0.0)))
		k_lob.append(1 if info.has("lob") else 0)
		k_flee_mult.append(float(info.get("flee", info.get("attacks", {}).get("feint", {})).get("speed_mult", 1.0)))
		var falx: Dictionary = info.get("falx", {})
		var maul: Dictionary = info.get("maul", {})
		var howl: Dictionary = info.get("howl", {})
		var salvo: Dictionary = info.get("salvo", {})
		k_beat.append(float(falx.get("every", maul.get("every", howl.get("every", 0.0)))))
		k_falx.append(1 if not falx.is_empty() else 0)
		k_falx_mult.append(float(falx.get("damage_mult", 0.0)))
		k_maul_mult.append(float(maul.get("damage_mult", 0.0)))
		k_maul_r.append(float(maul.get("radius", 0.0)))
		k_maul_throw.append(float(maul.get("throw", 0.0)))
		k_howl.append(1 if not howl.is_empty() else 0)
		k_salvo.append(int(salvo.get("arrows", 0)))
		k_salvo_spread.append(float(salvo.get("spread", 0.0)))
		var kite: Dictionary = info.get("kite", {})
		k_kite.append(float(kite.get("near", 0.0)))
		k_kite_mult.append(float(kite.get("speed_mult", 1.0)))
		k_lance.append(1 if info.has("lance") else 0)
		k_armour.append(float(info.get("armour", {}).get("arrows", 0.0)))
		var sling: Dictionary = info.get("sling", {})
		k_sling.append(int(sling.get("stones", 0)))
		k_sling_spread.append(float(sling.get("spread", 0.0)))
		k_fearless.append(1 if info.has("fearless") else 0)
		k_salvo_stone.append(1 if salvo.get("missile", "") == "stone" else 0)
		var tend: Dictionary = info.get("tend", {})
		k_tend.append(float(tend.get("every", 0.0)))
		k_tend_r.append(float(tend.get("radius", 0.0)))
		k_tend_share.append(float(tend.get("share", 0.0)))
		var pass_cfg: Dictionary = info.get("drive", {}) if beh == DRIVER else {}
		k_pass_gap.append(float(pass_cfg.get("gap", 0.0)))
		k_pass_turn.append(float(pass_cfg.get("turn", 0.0)))
		k_pass_lock.append(float(pass_cfg.get("lock", 0.0)))
		k_pass_far.append(float(pass_cfg.get("far", 0.0)))
		k_pass_every.append(float(pass_cfg.get("every", 1.0)))
		k_pass_range.append(float(pass_cfg.get("range", 0.0)))
		k_drop.append(float(info.get("drop", {}).get("chance", 0.0)))
		k_rides.append(1 if beh == DRIVER or beh == CHARGER or info.get("mounted", false) else 0)
		k_foot.append(1 if (beh == MELEE or beh == RANGED) and not info.get("mounted", false) and not info.get("elite", false) and not info.get("chieftain", false) else 0)
		var dash: Dictionary = info.get("fearless", info.get("sprint", info.get("rush", {})))
		k_dash_reach.append(float(dash.get("reach", -1.0)) if k_foot[k_foot.size() - 1] == 1 or beh == BEAST else -1.0)
		k_share.append(float(info.get("share", 1.0)))
		k_most.append(int(info.get("most", 0)))
		k_alive.append(0)
		k_lasso.append(float(info.get("lasso", {}).get("every", 0.0)))
		k_lasso_reach.append(float(info.get("lasso", {}).get("reach", 0.0)))
		k_heavy.append(1 if info.get("heavy", false) else 0)
	ordinary = content.province_enemies(province)
	for id in ordinary:
		if content.enemies[id].has("salvo"):
			salvo_every = float(content.enemies[id].salvo.every)
			salvo_cd = salvo_every
		if content.enemies[id].has("sling"):
			sling_stun = float(content.enemies[id].sling.stun)
	for id in content.provinces[province].elites:
		if content.ready("enemies", id):
			elites.append(id)
	var chief: String = content.provinces[province].chieftain
	chief_kind = chief if content.ready("enemies", chief) else ""
	next_surge = float(b.surge_every)
	next_band = float(b.war_band.first)
	next_boss = float(b.bosses.first)
	next_cart = float(b.cart.every)
	var attacks: Dictionary = content.enemies[chief].get("attacks", {})
	cleave_cd = float(attacks.get("cleave", {}).get("every", 5.0)) * 0.5
	cry_cd = float(attacks.get("war_cry", {}).get("every", 18.0)) * 0.5
	charge_cd = float(attacks.get("charge", {}).get("every", 11.0)) * 0.5
	slam_cd = float(attacks.get("slam", {}).get("every", 9.0)) * 0.5
	horn_cd = float(attacks.get("horn", {}).get("every", 30.0)) * 0.5
	summon_cd = float(attacks.get("summon", {}).get("every", 16.0)) * 0.5
	siege_cd = float(attacks.get("siege", {}).get("every", 22.0)) * 0.5
	sweep_cd = float(attacks.get("sweep", {}).get("every", 7.0)) * 0.5
	rockfall_cd = float(attacks.get("rockfall", {}).get("every", 14.0)) * 0.5
	leap_cd = float(attacks.get("leap", {}).get("every", 9.0)) * 0.5
	storm_cd = float(attacks.get("storm", {}).get("every", 16.0)) * 0.5
	drive_cd = float(attacks.get("drive", {}).get("every", 12.0)) * 0.5
	tribes_cd = float(attacks.get("tribes", {}).get("every", 30.0)) * 0.5
	burn_cd = float(attacks.get("burn", {}).get("every", 8.0)) * 0.5
	ambush_cd = float(attacks.get("ambush", {}).get("every", 28.0)) * 0.5
	feint_cd = float(attacks.get("feint", {}).get("every", 18.0)) * 0.5
	javelins_cd = float(attacks.get("javelins", {}).get("every", 13.0)) * 0.5
	volleys_cd = float(attacks.get("volleys", {}).get("every", 11.0)) * 0.5
	sluice_cd = float(attacks.get("sluice", {}).get("every", 20.0)) * 0.5
	lancers_cd = float(attacks.get("lancers", {}).get("every", 13.0)) * 0.5
	fire_cd = float(attacks.get("steppe_fire", {}).get("every", 19.0)) * 0.5
	king_wall = content.enemies[chief].get("wall", {})
	var sworn: Dictionary = content.enemies[chief].get("sworn", {})
	sworn_min = int(sworn.get("min", 0))
	sworn_cut = float(sworn.get("cut", 0.0))


## Adds an enemy and returns its index. Elites grow tougher through the run on their own curve; the chieftain keeps his listed health.
func spawn(kind_id: String, pos: Vector2, elite := false) -> int:
	var kind: int = kind_of[kind_id]
	var info: Dictionary = content.enemies[kind_id]
	var tag := ORDINARY
	if info.get("chieftain", false):
		tag = CHIEF
		chieftain_id = next_id
	elif elite or info.get("elite", false):
		tag = ELITE
		elite_ids.append(next_id)
	var hp := float(info.hp)
	var power := 1.0
	if tag == ORDINARY:
		hp *= (1.0 + float(b.enemy_health_growth) * time + float(b.get("enemy_health_curve", 0.0)) * pow(time / 60.0, 2.0)) * difficulty("health")
		power = difficulty("damage")
	if tag == ELITE:
		power = early_boss_mult() * difficulty("elites")
		hp *= early_boss_health() * (1.0 + float(b.bosses.health_growth) * time)
	hp *= level_mult("health_mult")
	power *= level_mult("damage_mult")
	var owner_sim: Sim = sim_ref.get_ref() if sim_ref != null else null
	var since: float = owner_sim.endless_since if owner_sim != null else -1.0
	if since >= 0.0 and tag != CHIEF:
		hp *= 1.0 + float(b.endless.health_per_minute) * floorf((time - since) / float(b.endless.step_seconds))
	if owner_sim != null:
		pos = owner_sim.terrain.out_of_fields(pos, k_radius[kind])
	e_id.append(next_id)
	next_id += 1
	e_pos.append(pos)
	e_face.append((commander.pos - pos).normalized())
	e_hp.append(hp)
	e_max.append(hp)
	e_kind.append(kind)
	if k_radius[kind] > Terrain.MAX_UNIT:
		big_alive += 1
	k_alive[kind] += 1
	e_burn.append(0.0)
	e_burn_dps.append(0.0)
	e_burn_src.append(-1)
	e_flash.append(0.0)
	e_phase.append(rng.randi_range(0, 7))
	e_fighting.append(0)
	e_kiting.append(0)
	e_turned.append(-1e9)
	e_strike.append(-1e9)
	e_stun.append(0.0)
	e_slow.append(1.0)
	e_push.append(Vector2.ZERO)
	e_block.append(0.0)
	e_tag.append(tag)
	if tag == ORDINARY:
		crowd += 1
	var beh := k_beh[kind]
	var wait := 0.0
	if tag == CHIEF:
		# The chieftain charges only after showing his path, which _chieftain starts.
		wait = INF
	elif k_dash_every[kind] > 0.0:
		wait = k_dash_every[kind] * rng.randf()
	elif k_beat[kind] > 0.0:
		wait = k_beat[kind] * rng.randf()
	elif beh == RANGED:
		wait = float(b.ranged.every) * (0.5 + 0.5 * rng.randf())
	e_cd.append(wait)
	e_dash.append(0.0)
	e_ammo.append(int(b.ranged.get("throws", 1 << 30)))
	e_detour.append(0.0)
	e_side.append(1)
	e_way.append(Vector2.ZERO)
	e_dir.append(Vector2.ZERO)
	e_haste.append(0.0)
	e_haste_mult.append(1.0)
	e_guard.append(Vector2.ZERO)
	e_stuck.append(0.0)
	e_flee.append(0.0)
	e_want.append(0)
	e_pace.append(k_speed[kind])
	e_fury.append(1.0)
	e_power.append(power)
	e_bare.append(0)
	e_tended.append(-INF)
	e_ward.append(-INF)
	e_hit.append(Vector2.ZERO)
	if beh == DRIVER:
		# A chariot comes in heading for the legion, and only some carry warriors to set down.
		var last := e_id.size() - 1
		e_dir[last] = (commander.pos - pos).normalized() if commander.pos != pos else Vector2.RIGHT
		e_ammo[last] = 1 if rng.randf() < k_drop[kind] else 0
		e_cd[last] = k_pass_every[kind] * rng.randf()
	return e_id.size() - 1


## The chieftain with his bodyguard in a ring round him; returns his index.
func spawn_chieftain(pos: Vector2) -> int:
	var ci := spawn(chief_kind, pos)
	var kind: String = content.enemies[chief_kind].get("guard", "")
	if kind == "" or not content.ready("enemies", kind):
		if ordinary.is_empty():
			return ci
		kind = ordinary[0]
	var cfg: Dictionary = b.chieftain_guard
	var n := int(cfg.count)
	for k in n:
		var off := Vector2.from_angle(TAU * k / n) * float(cfg.radius)
		var j := spawn(kind, pos + off)
		e_guard[j] = off
	guards_alive = n
	_place_wall(ci)
	return ci


## The Dacian king's guards stand in an arc between him and the legion, turning with it.
func _place_wall(ci: int) -> void:
	if king_wall.is_empty() or guards_alive <= 0:
		return
	var ahead: Vector2 = (commander.pos - e_pos[ci]).normalized() if commander.pos != e_pos[ci] else Vector2.RIGHT
	var arc := float(king_wall.arc)
	var k := 0
	for j in e_guard.size():
		if e_guard[j] != Vector2.ZERO:
			var a := -arc / 2.0 + arc * (float(k) / float(maxi(1, guards_alive - 1)))
			e_guard[j] = ahead.rotated(a) * float(king_wall.radius)
			k += 1


func ring_point() -> Vector2:
	var a := rng.randf() * TAU
	return open_point(commander.pos + Vector2(cos(a) * 1.15, sin(a) * 0.75) * b.spawn_radius)


## Where a newcomer at p arrives: p itself on open ground, or the nearest open spot round the legion when p is inside the forest.
func open_point(p: Vector2) -> Vector2:
	var owner: Sim = sim_ref.get_ref() if sim_ref != null else null
	if owner == null:
		return p
	p = beyond_screen(p)
	var at := p
	for k in 8:
		if owner.terrain.is_open(at):
			return at
		at = beyond_screen(commander.pos + (p - commander.pos).rotated(0.2 * (k / 2 + 1) * (1 if k % 2 == 0 else -1)))
	return owner.terrain.out_of_fields(p, Terrain.MAX_UNIT)


## Moves p out along its line from the commander until it stands beyond the edge of the screen with room for a body, so newcomers never appear in view.
func beyond_screen(p: Vector2) -> Vector2:
	var off: Vector2 = p - commander.pos
	if off.length_squared() < 1.0:
		return p
	var half := view / 2.0 + Vector2(48.0, 64.0)
	var t := minf(half.x / maxf(absf(off.x), 0.001), half.y / maxf(absf(off.y), 0.001))
	return commander.pos + off * maxf(1.0, t)


## An ordinary enemy for the stream: the first in the province's list most often, the rest more often as the run goes on.
## An enemy with an "arrives" time in content.json joins the stream only from that second.
func _pick_ordinary() -> String:
	var open: Array = []
	var weight := 0.0
	for k in range(1, ordinary.size()):
		var id: String = ordinary[k]
		var kind: int = kind_of[id]
		if float(content.enemies[id].get("arrives", 0.0)) <= time and (k_most[kind] == 0 or k_alive[kind] < k_most[kind]):
			open.append(id)
			weight += k_share[kind]
	var later := float(b.spawn_mix.later_start) + time / float(b.spawn_mix.later_seconds)
	if open.is_empty() or rng.randf() >= later:
		return ordinary[0]
	var roll := rng.randf() * weight
	for id in open:
		roll -= k_share[kind_of[id]]
		if roll < 0.0:
			return id
	return open[open.size() - 1]


## A number from the run's difficulty block in balance.json (`easy` or `hard`), 1 on Medium.
func level_mult(key: String) -> float:
	return float(b.get(run_difficulty, {}).get(key, 1.0)) if run_difficulty in Sim.DIFFICULTIES else 1.0


## How hard the chieftain's abilities hit: their numbers are tuned on Medium, so each difficulty scales them by its damage_mult against Medium's.
func chief_power() -> float:
	return level_mult("damage_mult") / float(b.get("medium", {}).get("damage_mult", 1.0))


## A number from this province's `difficulty` block in balance.json, 1 where it sets none.
func difficulty(key: String) -> float:
	return float(b.get("difficulty", {}).get(province, {}).get(key, 1.0))


func cidx(p: Vector2) -> int:
	var cx := floori(p.x / CELL) - g_origin.x
	var cy := floori(p.y / CELL) - g_origin.y
	if cx < 0 or cy < 0 or cx >= GW or cy >= GW:
		return -1
	return cx + cy * GW


func rebuild_grid() -> void:
	frame += 1
	var n := e_pos.size()
	g_origin = Vector2i(floori(commander.pos.x / CELL) - GW / 2, floori(commander.pos.y / CELL) - GW / 2)
	g_start.resize(GW * GW + 1)
	g_start.fill(0)
	_g_cell.resize(n)
	var ox := g_origin.x
	var oy := g_origin.y
	for i in n:
		var p := e_pos[i]
		var cx := floori(p.x / CELL) - ox
		var cy := floori(p.y / CELL) - oy
		var c := cx + cy * GW if cx >= 0 and cy >= 0 and cx < GW and cy < GW else -1
		_g_cell[i] = c
		if c >= 0:
			g_start[c + 1] += 1
	for c in range(1, GW * GW + 1):
		g_start[c] += g_start[c - 1]
	var total := g_start[GW * GW]
	g_items.resize(total)
	g_rad.resize(total)
	_g_fill = g_start.duplicate()
	for i in n:
		var c := _g_cell[i]
		if c >= 0:
			var t := _g_fill[c]
			g_items[t] = i
			var rad := k_radius[e_kind[i]]
			g_rad[t] = rad
			_g_fill[c] = t + 1


func update(dt: float, sim: Sim) -> void:
	# The sim can swap in a changed balance table, so the horde reads the current one.
	b = sim.b
	time = sim.time
	if time >= next_trail:
		next_trail = time + 1.0
		trail.append(commander.pos)
		if trail.size() > int(b.war_band.get("loop_samples", 0)):
			trail.remove_at(0)
	_spawn(dt, sim)
	_pursue(sim)
	_chieftain(dt, sim)
	_rally(dt, sim)
	_bosses(dt, sim)
	salvo_now = false
	_salvo_fired = 0
	if salvo_every > 0.0:
		salvo_cd -= dt
		if salvo_cd <= 0.0:
			salvo_cd = salvo_every
			salvo_now = true
	_move(dt, sim)
	if _salvo_fired > 0:
		sim.event("arrow", commander.pos)
	_chieftain_after(sim)
	_keep_chief_out(sim)
	_bosses_after()
	_foe_lobs(dt, sim)
	_marks(dt, sim)
	_storms(dt, sim)
	_arrow_storm(dt, sim)
	_sluice_on(dt, sim)
	_fire_on(dt, sim)
	_lassos(dt, sim)
	_spears(dt, sim)
	_carts(dt, sim)
	_chests(sim)


func _spawn(dt: float, sim: Sim) -> void:
	crowd = _count_crowd()
	spawn_acc += (b.spawn_per_second_start + b.spawn_per_second_growth * time) * level_mult("spawn_mult") * sim.objectives.spawn_mult(time) * difficulty("spawn") * crowd_ease() * dt
	while spawn_acc >= 1.0:
		spawn_acc -= 1.0
		if not full() and not ordinary.is_empty():
			spawn(_pick_ordinary(), ring_point())
	if time >= next_band:
		next_band += float(b.war_band.every)
		_war_band(sim)
	if time >= next_surge:
		next_surge += b.surge_every
		sim.event("surge", commander.pos)
		# A surge comes from one side as a crowd, so the legion can see it coming and turn.
		var side := rng.randf() * TAU
		var n := int((b.surge_size_start + b.surge_size_growth * time) * difficulty("spawn"))
		for i in n:
			if full() or ordinary.is_empty():
				break
			var a := side + rng.randf_range(-0.6, 0.6)
			var r: float = b.spawn_radius + rng.randf_range(0.0, 80.0)
			spawn(_pick_ordinary(), open_point(commander.pos + Vector2(cos(a) * 1.15, sin(a) * 0.75) * r))
	next_boss -= dt * minf(1.0, pursuit) * float(b.get("pursuit", {}).get("boss_haste", 0.0))
	if time >= next_boss:
		next_boss += float(b.bosses.every)
		_boss_arrival(sim)
	if chieftain_id == -1 and chief_kind != "" and time >= b.chieftain_at:
		spawn_chieftain(sim.objectives.chieftain_point(sim))
	if time >= next_cart:
		next_cart += float(b.cart.every)
		if content.available.has("prop:supply_cart"):
			spawn_cart()


## How many ordinary enemies the run lets gather round the legion, from the `crowd` block in balance.json.
func crowd_limit() -> int:
	var cfg: Dictionary = b.get("crowd", {})
	return int(cfg.get(run_difficulty, cfg.get("medium", 1 << 30)))


## True when no more enemies may join: the field is at its total or the crowd round the legion is at its limit.
func full() -> bool:
	return e_pos.size() >= int(b.max_enemies) or crowd >= crowd_limit()


## The share of the stream that still arrives: all of it until the crowd is half its limit, then less and less, none at the limit.
func crowd_ease() -> float:
	var most := float(crowd_limit())
	var from := float(b.get("crowd", {}).get("ease_from", 0.5))
	return clampf((most - crowd) / maxf(1.0, most * (1.0 - from)), 0.0, 1.0)


func _count_crowd() -> int:
	var half := view / 2.0 + Vector2.ONE * float(b.get("crowd", {}).get("margin", 160.0))
	var n := 0
	for i in e_pos.size():
		var off: Vector2 = e_pos[i] - commander.pos
		if e_tag[i] == ORDINARY and absf(off.x) <= half.x and absf(off.y) <= half.y:
			n += 1
	return n


## Once a second, weighs how much the legion marches against how much it kills, and sends hunters after one that runs.
func _pursue(sim: Sim) -> void:
	var cfg: Dictionary = b.get("pursuit", {})
	if cfg.is_empty() or time < _p_next:
		return
	var step := float(cfg.tick)
	_p_next = time + step
	if _p_from == Vector2.INF:
		_p_from = commander.pos
		_p_kills = sim.kills - bare_kills
		return
	var k := step / float(cfg.window)
	var moved: Vector2 = (commander.pos - _p_from) / step
	_p_from = commander.pos
	kill_rate = lerpf(kill_rate, float(sim.kills - bare_kills - _p_kills) / step, k)
	_p_kills = sim.kills - bare_kills
	march_speed = lerpf(march_speed, moved.length(), k)
	heading = heading.lerp(moved, k)
	if time < float(cfg.from):
		return
	# Ground marched for each kill tells a legion that holds and fights from one that runs while its arms do the killing.
	var per_kill := march_speed / maxf(kill_rate, 0.1)
	if march_speed > float(cfg.moving) and per_kill > float(cfg.per_kill):
		pursuit = minf(float(cfg.cap), pursuit + float(cfg.rise) * step * minf(1.0, per_kill / float(cfg.per_kill) - 1.0))
	elif march_speed < float(cfg.still_speed):
		pursuit = minf(float(cfg.cap), pursuit + float(cfg.still_rise) * step)
	else:
		pursuit = maxf(0.0, pursuit - float(cfg.fall) * step)
	if pursuit >= float(cfg.hunt_min) and time >= next_hunt:
		next_hunt = time + float(cfg.hunt_every)
		_hunt(sim, cfg, moved)


## Beasts and sprinters that come in ahead of the legion's march and, as the pursuit grows, from all round it, running at first and tougher and fiercer the longer the hunt goes on.
func _hunt(sim: Sim, cfg: Dictionary, moved: Vector2) -> void:
	var fast := hunters()
	if fast.is_empty():
		return
	var n := int(minf(pursuit, 1.0) * (float(cfg.hunt_start) + float(cfg.hunt_growth) * time) * float(cfg.province_mult.get(province, 1.0)))
	# The pack grows tougher as the hunt goes on, never larger than `most` alive at once, so a legion that fights on the move is pressed, not buried.
	var alive := 0
	for i in e_bare.size():
		alive += e_bare[i]
	n = mini(n, int(cfg.get("most", 1 << 30)) - alive)
	var ahead := moved.angle() if moved.length() > 1.0 else rng.randf() * TAU
	var spread := lerpf(float(cfg.spread_min), PI, minf(1.0, pursuit))
	var first := e_pos.size()
	var tough := 1.0 + float(cfg.tough) * maxf(0.0, pursuit - 1.0)
	var fierce := 1.0 + float(cfg.fierce) * maxf(0.0, pursuit - 1.0)
	for k in n:
		if full():
			break
		var wide := spread if k % 2 == 1 else float(cfg.spread_min)
		var a := ahead + rng.randf_range(-wide, wide)
		var r := float(b.spawn_radius) + rng.randf_range(0.0, 60.0)
		spawn(fast[rng.randi_range(0, fast.size() - 1)], open_point(commander.pos + Vector2(cos(a) * 1.15, sin(a) * 0.75) * r))
	# Hunters come at full strength in every province, so an easier province is no safer to run through.
	tough /= difficulty("health")
	fierce /= difficulty("damage")
	for i in range(first, e_pos.size()):
		e_slow[i] = float(b.war_band.get("rush", 1.0))
		e_bare[i] = 1
		e_hp[i] *= tough
		e_max[i] *= tough
		e_power[i] *= fierce
	if e_pos.size() > first:
		sim.event("surge", commander.pos)


## The ordinary enemies already on the field that can be sent hunting: beasts, sprinters and riders marked `hunts`, or the first kind when there are none.
func hunters() -> Array:
	var fast: Array = []
	for id in ordinary:
		var info: Dictionary = content.enemies[id]
		if float(info.get("arrives", 0.0)) <= time and (info.behaviour == "beast" or info.has("sprint") or info.get("hunts", false)):
			fast.append(id)
	if fast.is_empty() and not ordinary.is_empty():
		fast.append(ordinary[0])
	return fast


## The extra bosses let loose on a legion the horde is hunting, one more for each step of the pursuit past the first.
func hunted_bosses() -> int:
	return int(maxf(0.0, pursuit - 1.0) * float(b.get("pursuit", {}).get("bosses", 0.0)))


## Early bosses hit with part of their strength, growing from the first boss's arrival to the full by `early_until`, so only the opening is gentle.
func early_boss_mult() -> float:
	var cfg: Dictionary = b.bosses
	return lerpf(float(cfg.early_mult), 1.0, _boss_ramp())


## How far the bosses' opening has gone, from 0 when the first comes to 1 at `early_until`.
func _boss_ramp() -> float:
	var cfg: Dictionary = b.bosses
	return clampf((time - float(cfg.first)) / maxf(1.0, float(cfg.early_until) - float(cfg.first)), 0.0, 1.0)


## Early bosses also come with part of their health, on their own curve so they stay tough while hitting softer.
func early_boss_health() -> float:
	var cfg: Dictionary = b.bosses
	return lerpf(float(cfg.early_health), 1.0, clampf(time / float(cfg.early_health_until), 0.0, 1.0))


## How fast early bosses use their abilities, rising to full pace by `early_until`.
func early_pace() -> float:
	var cfg: Dictionary = b.bosses
	return lerpf(float(cfg.early_pace), 1.0, _boss_ramp())


## Bosses come from one side on their own timer, more of them at once as the run goes on.
func _boss_arrival(sim: Sim) -> void:
	if elites.is_empty():
		return
	var cfg: Dictionary = b.bosses
	var n := mini(int(cfg.count_max), int(float(cfg.count_start) + float(cfg.count_growth) * time))
	var side := rng.randf() * TAU
	# A marching legion meets its bosses ahead, since it would outpace any that came from behind.
	if sim.moving:
		side = sim.facing_angle + rng.randf_range(-1.0, 1.0)
	var came := false
	# Only the bosses that came on this timer count against its limit, not an objective's defender.
	timed_ids = timed_ids.filter(func(id: int) -> bool: return elite_ids.has(id))
	for k in n:
		if timed_ids.size() >= mini(int(cfg.max_alive), int(float(cfg.max_alive_start) + float(cfg.max_alive_growth) * time)) + hunted_bosses():
			break
		var a := side + rng.randf_range(-0.5, 0.5)
		var at := spawn(elites[rng.randi_range(0, elites.size() - 1)], open_point(commander.pos + Vector2(cos(a) * 1.15, sin(a) * 0.75) * b.spawn_radius), true)
		timed_ids.append(e_id[at])
		came = true
	if came:
		sim.event("boss", commander.pos)


## A tight band gathers in the legion's path or closes in from behind, so marching straight on is never safe for long.
func _war_band(sim: Sim, behind := false) -> void:
	var ahead := Vector2.from_angle(sim.facing_angle)
	var dir := -ahead if behind else (ahead if rng.randf() < 0.5 else -ahead)
	var first := e_pos.size()
	var loop := loop_centre()
	if not behind and loop != Vector2.INF and time >= float(b.war_band.get("loop_from", 0.0)):
		# A legion marching round and round in one place meets a band coming in across the middle of its loop.
		var across: Vector2 = (loop - commander.pos).normalized()
		war_band_at(sim, open_point(commander.pos + across * Vector2(1.15, 0.75) * float(b.spawn_radius)), float(b.war_band.get("loop_mult", 1.0)))
	else:
		war_band_at(sim, open_point(commander.pos + dir.rotated(rng.randf_range(-0.4, 0.4)) * Vector2(1.15, 0.75) * float(b.spawn_radius)))
	# A timed band runs at the legion for a while, so one that keeps marching cannot simply leave it behind.
	if time < float(b.war_band.get("rush_from", 0.0)):
		return
	for i in range(first, e_pos.size()):
		e_slow[i] = float(b.war_band.get("rush", 1.0))


## The middle of the loop the commander has been marching round, or INF when he has been standing, fighting in place or marching on.
func loop_centre() -> Vector2:
	var cfg: Dictionary = b.war_band
	if trail.size() < int(cfg.get("loop_samples", 1 << 30)):
		return Vector2.INF
	var mid := Vector2.ZERO
	for p in trail:
		mid += p
	mid /= trail.size()
	var walked := 0.0
	for k in range(1, trail.size()):
		walked += trail[k].distance_to(trail[k - 1])
	var spread := 0.0
	for p in trail:
		spread = maxf(spread, p.distance_to(mid))
	if spread > float(cfg.loop_spread) or walked < float(cfg.loop_walk) or commander.pos.distance_to(mid) < float(cfg.loop_spread) * 0.3:
		return Vector2.INF
	return mid


## A war band gathered round a given point, such as the defenders of an objective; `mult` scales its size.
func war_band_at(sim: Sim, centre: Vector2, mult := 1.0) -> void:
	if ordinary.is_empty():
		return
	var wb: Dictionary = b.war_band
	var n := int((float(wb.size_start) + float(wb.size_growth) * time) * mult * difficulty("spawn"))
	var turn := rng.randf() * TAU
	var first := e_pos.size()
	for i in n:
		if full():
			break
		# The band stands in a loose spiral, `spread` apart, so it walks in as a crowd and never as one pile, and within reach of the legion so none is sent round again at once.
		var at := beyond_screen(centre + Vector2.from_angle(turn + i * 2.39996) * float(wb.spread) * 0.55 * sqrt(i + 0.5))
		var held: Vector2 = commander.pos + (at - commander.pos).limit_length(float(b.give_up_radius) - 10.0)
		at = held if beyond_screen(held) == held else at
		spawn(_pick_ordinary(), at if sim.terrain.is_open(at) else _open_near(at, first, sim))
	sim.event("surge", commander.pos)


## Open ground near p for a band member whose own place is closed, beyond the screen, within the chase and clear of the men placed since index `first`; p itself when none is near.
func _open_near(p: Vector2, first: int, sim: Sim) -> Vector2:
	var room := float(b.war_band.spread) * 0.5
	var most := float(b.give_up_radius) - 10.0
	for ring in range(1, 5):
		for k in 8:
			var q: Vector2 = p + Vector2.from_angle(k * TAU / 8.0 + ring * 0.4) * ring * 24.0
			q = commander.pos + (q - commander.pos).limit_length(most)
			if beyond_screen(q) != q or not sim.terrain.is_open(q):
				continue
			var free := true
			for j in range(first, e_pos.size()):
				if e_pos[j].distance_squared_to(q) < room * room:
					free = false
					break
			if free:
				return q
	return p


func chieftain_index() -> int:
	return e_id.find(chieftain_id) if chieftain_id != -1 and not chief_dead else -1


## The chieftain's attacks, each on its own timer: the cleave, war cry, charge, slam and war horn in Germania, the cleave, charge, summons and siege lines in Gaul.
func _chieftain(dt: float, sim: Sim) -> void:
	var ci := chieftain_index()
	if ci < 0:
		return
	var atk: Dictionary = content.enemies[kind_ids[e_kind[ci]]].get("attacks", {})
	if atk.is_empty():
		return
	var fury: Dictionary = content.enemies[kind_ids[e_kind[ci]]].get("fury", {})
	if not fury.is_empty() and not chief_fury and e_hp[ci] < e_max[ci] * float(fury.below):
		_roar(ci, sim)
	_place_wall(ci)
	if e_stun[ci] > 0.0:
		# A stun holds his timers and calls off a charge, sweep, leap, ambush or flood he was warning of or running.
		charge_warn = 0.0
		charging = false
		chief_hold = 0.0
		e_dash[ci] = 0.0
		sweep = {}
		leap = {}
		drive = {}
		feint = {}
		e_flee[ci] = 0.0
		ambush_wait = 0.0
		_drop_unopened_flood()
		_end_wave()
		_drop_unlit_fire()
		return
	var rate := float(fury.rate_mult) if chief_fury else 1.0
	cleave_cd -= dt * rate
	cry_cd -= dt * rate
	charge_cd -= dt * rate
	slam_cd -= dt * rate
	horn_cd -= dt * rate
	summon_cd -= dt * rate
	siege_cd -= dt * rate
	sweep_cd -= dt * rate
	rockfall_cd -= dt * rate
	leap_cd -= dt * rate
	if arrow_storm.is_empty():
		storm_cd -= dt * rate
	if drive.is_empty():
		drive_cd -= dt * rate
	tribes_cd -= dt * rate
	burn_cd -= dt * rate
	ambush_cd -= dt * rate
	if feint.is_empty():
		feint_cd -= dt * rate
	volleys_cd -= dt * rate
	javelins_cd -= dt * rate
	if flood.is_empty():
		sluice_cd -= dt * rate
	if wave.is_empty():
		lancers_cd -= dt * rate
	if steppe_fire.is_empty():
		fire_cd -= dt * rate
	chief_hold = maxf(0.0, chief_hold - dt)
	_feint_on(ci, dt, sim)
	if ambush_wait > 0.0:
		ambush_wait -= dt
		if ambush_wait <= 0.0:
			spring_ambush(ci, sim)
	if ambush_cd <= 0.0 and atk.has("ambush") and ambush_wait <= 0.0:
		ambush_cd = float(atk.ambush.every)
		warn_ambush(ci, sim)
	if feint_cd <= 0.0 and atk.has("feint") and feint.is_empty() and chief_hold <= 0.0 and not charging:
		feint_cd = float(atk.feint.every) if start_feint(ci, sim) else 1.0
	var gap: float = (commander.pos - e_pos[ci]).length()
	if volleys_cd <= 0.0 and atk.has("volleys"):
		volleys_cd = float(atk.volleys.every) if gap < float(atk.volleys.range) else 1.0
		if gap < float(atk.volleys.range):
			volleys(ci, sim)
	if javelins_cd <= 0.0 and atk.has("javelins"):
		javelins_cd = float(atk.javelins.every) if gap < float(atk.javelins.range) else 1.0
		if gap < float(atk.javelins.range):
			volleys(ci, sim, "javelins")
	if sluice_cd <= 0.0 and atk.has("sluice") and flood.is_empty():
		sluice_cd = float(atk.sluice.every) if gap < float(atk.sluice.range) else 1.0
		if gap < float(atk.sluice.range):
			open_sluices(ci, sim)
	_lancers_on(dt, sim)
	if lancers_cd <= 0.0 and atk.has("lancers") and wave.is_empty():
		lancers_cd = float(atk.lancers.every) if start_lancers(ci, sim) else 1.0
	if fire_cd <= 0.0 and atk.has("steppe_fire") and steppe_fire.is_empty():
		fire_cd = float(atk.steppe_fire.every) if gap < float(atk.steppe_fire.range) else 1.0
		if gap < float(atk.steppe_fire.range):
			set_fire(ci, sim)
	_sweep_and_leap(ci, dt, sim)
	_drive_on(ci, dt, sim)
	if drive_cd <= 0.0 and atk.has("drive") and drive.is_empty() and chief_hold <= 0.0:
		drive_cd = float(atk.drive.every) if start_drive(ci, sim) else 1.0
	if tribes_cd <= 0.0 and atk.has("tribes"):
		tribes_cd = float(atk.tribes.every)
		call_tribes(ci, sim)
	# She sets the land on fire only in her second phase.
	if burn_cd <= 0.0 and atk.has("burn") and chief_fury:
		burn_cd = float(atk.burn.every)
		burn_land(ci, sim)
	if cleave_cd <= 0.0 and atk.has("cleave"):
		cleave_cd = float(atk.cleave.every) if cleave(ci, sim) else float(atk.cleave.retry)
	if sweep_cd <= 0.0 and atk.has("sweep") and chief_hold <= 0.0:
		sweep_cd = float(atk.sweep.every) if start_sweep(ci, sim) else float(atk.sweep.retry)
	if rockfall_cd <= 0.0 and atk.has("rockfall"):
		rockfall_cd = float(atk.rockfall.every)
		rockfall(ci, sim)
	# The leap is his second phase's attack, once his wall has gone in.
	if leap_cd <= 0.0 and atk.has("leap") and chief_fury and chief_hold <= 0.0:
		leap_cd = float(atk.leap.every) if start_leap(ci, sim) else 1.0
	if storm_cd <= 0.0 and atk.has("storm") and arrow_storm.is_empty():
		storm_cd = float(atk.storm.every)
		start_storm(ci, sim)
	if cry_cd <= 0.0 and atk.has("war_cry"):
		war_cry(ci, sim)
		cry_cd = float(atk.war_cry.every)
	if summon_cd <= 0.0 and atk.has("summon"):
		summon_cd = float(atk.summon.every)
		summon(ci, sim)
	# In his second phase the king no longer stops to drive stakes.
	if siege_cd <= 0.0 and atk.has("siege") and not chief_fury:
		siege_cd = float(atk.siege.every)
		siege(ci, sim)
	if charge_warn > 0.0:
		charge_warn -= dt
		if charge_warn <= 0.0:
			e_dir[ci] = charge_dir
			e_dash[ci] = k_dash_secs[e_kind[ci]]
			charging = true
			sim.event("charge", e_pos[ci])
			charge_n += 1
			chief_hold = 0.0
	elif atk.has("charge") and charge_cd <= 0.0 and chief_hold <= 0.0 and not charging and (commander.pos - e_pos[ci]).length() < sim.legion_reach + float(atk.charge.range):
		_warn_charge(ci, atk.charge)
	if slam_cd <= 0.0 and chief_hold <= 0.0 and not charging and atk.has("slam"):
		slam_cd = float(atk.slam.every) if slam(ci, sim) else float(atk.slam.retry)
	if horn_cd <= 0.0 and atk.has("horn"):
		horn_cd = float(atk.horn.every)
		for k in (int(fury.bands) if chief_fury else 1):
			_war_band(sim, k == 0)


## The chieftain's second phase: below half health he roars and fights faster from then on.
func _roar(ci: int, sim: Sim) -> void:
	chief_fury = true
	sim.shake = maxf(sim.shake, float(sim.b.shake.roar))
	sim.objectives.notice = {"kind": "roar", "at": time}
	sim.event("bellow", e_pos[ci])
	sim.effects.append({"kind": "cry", "pos": e_pos[ci], "t": 0.0, "radius": 120.0})
	var fury: Dictionary = content.enemies[kind_ids[e_kind[ci]]].get("fury", {})
	if fury.get("release", false):
		release_guards()
	if fury.has("call"):
		call_in(ci, fury.call, sim)


## Hastens barbarian j for that long at that speed; one still hastened keeps the faster of the two and the longer time.
func hasten(j: int, seconds: float, mult: float) -> void:
	if e_haste[j] > 0.0:
		e_haste_mult[j] = maxf(e_haste_mult[j], mult)
		e_haste[j] = maxf(e_haste[j], seconds)
	else:
		e_haste_mult[j] = mult
		e_haste[j] = seconds


## The king's sworn guards leave their places round him and run at the legion.
func release_guards() -> void:
	for j in e_guard.size():
		if e_guard[j] != Vector2.ZERO:
			e_guard[j] = Vector2.ZERO
			hasten(j, float(b.guard_release.seconds), float(b.guard_release.speed_mult))
	guards_alive = 0


## The king calls horsemen in from the edge of the field on one side, more of them in his second phase.
func summon(ci: int, sim: Sim) -> void:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.summon
	var kind := str(cfg.kind)
	if not content.ready("enemies", kind):
		return
	var n := int(cfg.fury_count) if chief_fury else int(cfg.count)
	var side := rng.randf() * TAU
	for k in n:
		if full():
			break
		var a := side + rng.randf_range(-0.5, 0.5)
		spawn(kind, open_point(commander.pos + Vector2(cos(a) * 1.15, sin(a) * 0.75) * float(b.spawn_radius)))
	e_strike[ci] = time
	sim.event("summon", e_pos[ci])


## The king rings the front of the legion with stakes that nobody can cross until they rot, so it must turn or wait.
func siege(ci: int, sim: Sim) -> void:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.siege
	var r := sim.legion_reach + float(cfg.gap)
	var ahead := sim.facing_angle
	var half := float(cfg.arc) / 2.0
	var n := maxi(2, int(r * float(cfg.arc) / float(cfg.step)))
	var until := time + float(cfg.seconds)
	for k in n + 1:
		var a := ahead - half + float(cfg.arc) * k / n
		var at: Vector2 = commander.pos + Vector2.from_angle(a) * r
		if not sim.terrain.over_ravine(at):
			sim.terrain.add_post(at, float(cfg.radius), until)
	e_strike[ci] = time
	sim.event("siege", commander.pos)
	sim.effects.append({"kind": "cry", "pos": commander.pos, "t": 0.0, "radius": r})


## The Dacian king raises his blade over a cone of ground before him, which fills and then is cut; false when nobody is near enough.
func start_sweep(ci: int, sim: Sim) -> bool:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.sweep
	var p := e_pos[ci]
	var reach := float(cfg.reach) + k_radius[e_kind[ci]]
	if (commander.pos - p).length() > sim.legion_reach + reach:
		return false
	var near_one := false
	for u in sim.units:
		if (u.pos - p).length() < reach + Sim.UNIT_RADIUS:
			near_one = true
			break
	if not near_one:
		return false
	var dir: Vector2 = (commander.pos - p).normalized() if commander.pos != p else Vector2.RIGHT
	sweep = {"pos": p, "dir": dir, "t": 0.0, "dur": float(cfg.windup), "reach": reach, "arc": float(cfg.arc), "dmg": k_dps[e_kind[ci]] * float(cfg.damage_mult) * chief_power()}
	e_face[ci] = dir
	_hold(ci, float(cfg.windup))
	# The blow is timed to land as the cone fills.
	e_strike[ci] = time + float(cfg.windup) - Atlas.ATTACK_FRAMES / Atlas.ATTACK_FPS
	sim.event("shield", p)
	return true


## Rocks come down from the heights on rings round the legion, one on the commander and the rest scattered near him.
func rockfall(ci: int, sim: Sim) -> void:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.rockfall
	var n := int(cfg.fury_count) if chief_fury else int(cfg.count)
	volley_ids += 1
	for k in n:
		var at: Vector2 = commander.pos
		if k > 0:
			at += Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(float(cfg.radius), float(cfg.spread) + sim.legion_reach * 0.5)
		foe_lobs.append({"from": at, "to": at, "t": 0.0, "dur": float(cfg.delay) + 0.12 * k, "radius": float(cfg.radius), "dmg": float(cfg.damage) * chief_power(), "slam": true, "rock": true, "volley_id": volley_ids})
	e_strike[ci] = time
	sim.event("bellow", e_pos[ci])


## In his second phase the king crouches, then leaps onto the ring marked where the commander stood; false when the commander is out of range.
func start_leap(ci: int, sim: Sim) -> bool:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.leap
	var p := e_pos[ci]
	if (commander.pos - p).length() > float(cfg.range):
		return false
	var to: Vector2 = commander.pos
	leap = {"from": p, "to": to, "t": 0.0, "dur": float(cfg.windup)}
	foe_lobs.append({"from": p, "to": to, "t": 0.0, "dur": float(cfg.windup), "radius": float(cfg.radius), "dmg": k_dps[e_kind[ci]] * float(cfg.damage_mult) * chief_power(), "slam": true, "by": e_id[ci]})
	_hold(ci, float(cfg.windup) + 0.1)
	e_face[ci] = (to - p).normalized() if to != p else e_face[ci]
	e_strike[ci] = time + float(cfg.windup) - Atlas.ATTACK_FRAMES / Atlas.ATTACK_FPS
	sim.event("roar", p)
	return true


## Counts down the king's sweep, cutting the cone when it has filled, and carries him through the air at the end of his leap.
func _sweep_and_leap(ci: int, dt: float, sim: Sim) -> void:
	if not sweep.is_empty():
		sweep.t += dt
		if sweep.t >= sweep.dur:
			var half: float = sweep.arc / 2.0
			var hit_any := false
			for u in sim.units:
				var to: Vector2 = u.pos - sweep.pos
				if to.length() > sweep.reach + Sim.UNIT_RADIUS or absf(sweep.dir.angle_to(to)) > half:
					continue
				var target: Dictionary = sim.legion.shield(u)
				target.hp -= sweep.dmg * sim.frenzy_guard() * sim.front_guard(target)
				u.flash = 0.12
				hit_any = true
			sim.effects.append({"kind": "cleave", "pos": sweep.pos, "dir": sweep.dir, "t": 0.0, "radius": sweep.reach, "arc": sweep.arc})
			sim.event("slam", sweep.pos)
			if hit_any:
				sim.shake = maxf(sim.shake, float(sim.b.shake.chieftain))
				sim.legion.remove_fallen(sim)
			sweep = {}
	if not leap.is_empty():
		leap.t += dt
		# He stays crouched for most of the wind-up and covers the ground in its last moments.
		var k := clampf((leap.t - (leap.dur - 0.4)) / 0.4, 0.0, 1.0)
		hold_pos = leap.from.lerp(leap.to, k)
		if leap.t >= leap.dur:
			hold_pos = sim.terrain.push_out_wide(leap.to, k_radius[e_kind[ci]])
			e_pos[ci] = hold_pos
			chief_hold = 0.0
			sim.shake = maxf(sim.shake, float(sim.b.shake.roar))
			leap = {}


## The warrior queen marks a path that runs in to the legion and sweeps round it through its outer ranks, then drives her chariot along it;
## false when the legion is out of her range.
func start_drive(ci: int, sim: Sim) -> bool:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.drive
	var p := e_pos[ci]
	var c: Vector2 = commander.pos
	if (c - p).length() > float(cfg.range):
		return false
	var rr := sim.legion_reach * float(cfg.inner) + float(cfg.outer)
	var a0 := (p - c).angle() if p != c else 0.0
	var way := 1.0 if rng.randf() < 0.5 else -1.0
	var pts := PackedVector2Array([p])
	var n := 24
	for k in n + 1:
		pts.append(c + Vector2.from_angle(a0 + way * float(cfg.arc) * k / n) * rr)
	var last := pts[pts.size() - 1]
	pts.append(last + (last - pts[pts.size() - 2]).normalized() * float(cfg.exit))
	var lens := PackedFloat32Array([0.0])
	for k in range(1, pts.size()):
		lens.append(lens[k - 1] + pts[k].distance_to(pts[k - 1]))
	drive_n += 1
	drive = {"pts": pts, "lens": lens, "total": lens[lens.size() - 1], "t": 0.0, "warn": float(cfg.warn), "speed": float(cfg.speed), "n": drive_n,
		"started": false, "width": k_radius[e_kind[ci]] * 2.0 + Sim.UNIT_RADIUS * 2.0}
	_hold(ci, float(cfg.warn) + drive.total / float(cfg.speed))
	e_face[ci] = (pts[1] - p).normalized() if pts[1] != p else e_face[ci]
	sim.event("rage", p)
	return true


## Carries the queen along her marked path once its warning is over, riding down every Roman she reaches.
func _drive_on(ci: int, dt: float, sim: Sim) -> void:
	if drive.is_empty():
		return
	drive.t += dt
	var run: float = drive.t - drive.warn
	if run < 0.0:
		return
	if not drive.started:
		drive.started = true
		e_strike[ci] = time
		sim.event("charge", e_pos[ci])
	var dist: float = run * drive.speed
	if dist >= drive.total:
		drive = {}
		chief_hold = 0.0
		return
	var lens: PackedFloat32Array = drive.lens
	var pts: PackedVector2Array = drive.pts
	var k := 1
	while k < lens.size() - 1 and lens[k] < dist:
		k += 1
	var seg := maxf(lens[k] - lens[k - 1], 0.001)
	var kind := e_kind[ci]
	var path := pts[k - 1].lerp(pts[k], clampf((dist - lens[k - 1]) / seg, 0.0, 1.0))
	var at := sim.terrain.push_out_wide(path, k_radius[kind])
	# A wall, tree or rock that pushes her back against her path ends the drive where she stands, since the steps beyond would come out on its far side.
	if (at - path).dot(pts[k] - pts[k - 1]) < -0.5:
		drive = {}
		chief_hold = 0.0
		e_pos[ci] = sim.terrain.push_out_wide(e_pos[ci], k_radius[kind])
		return
	if _shields_stop(ci, at, k_radius[kind], sim):
		drive = {}
		chief_hold = 0.0
		return
	hold_pos = at
	e_pos[ci] = at
	e_face[ci] = (pts[k] - pts[k - 1]).normalized()
	var cfg: Dictionary = content.enemies[kind_ids[kind]].attacks.drive
	var dmg := k_dps[kind] * float(cfg.damage_mult) * chief_power() * sim.frenzy_guard()
	# Her marks count down from -1000 so they never match an elite's charge or a soldier never ridden down.
	if _ride_down(at, k_radius[kind], e_face[ci], -1000 - int(drive.n), dmg, float(cfg.throw), sim):
		sim.shake = maxf(sim.shake, float(sim.b.shake.chieftain))
		sim.legion.remove_fallen(sim)


## The queen calls the tribes: a war band falls on the legion from each of several sides at once, more of them in her second phase.
func call_tribes(ci: int, sim: Sim) -> void:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.tribes
	var n := int(cfg.fury_sides) if chief_fury else int(cfg.sides)
	var turn := rng.randf() * TAU
	for k in n:
		var a := turn + TAU * k / n
		war_band_at(sim, open_point(commander.pos + Vector2(cos(a) * 1.15, sin(a) * 0.75) * float(b.spawn_radius)), float(cfg.mult))
	e_strike[ci] = time
	sim.event("carnyx", e_pos[ci])
	sim.effects.append({"kind": "cry", "pos": e_pos[ci], "t": 0.0, "radius": 120.0})


## The shepherd general sounds his horn and a notice warns that an ambush is coming; the bands break cover once the warning is over.
func warn_ambush(ci: int, sim: Sim) -> void:
	ambush_wait = float(content.enemies[kind_ids[e_kind[ci]]].attacks.ambush.warn)
	e_strike[ci] = time
	sim.objectives.notice = {"kind": "ambush", "at": time}
	sim.event("carnyx", e_pos[ci])


## War bands burst out on both flanks of the legion's march at once and run at it, larger in his second phase.
func spring_ambush(ci: int, sim: Sim) -> void:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.ambush
	var side := Vector2.from_angle(sim.facing_angle).orthogonal()
	var first := e_pos.size()
	for s in [-1.0, 1.0]:
		war_band_at(sim, open_point(commander.pos + side * s * Vector2(1.15, 0.75) * float(b.spawn_radius)), float(cfg.fury_mult) if chief_fury else float(cfg.mult))
	for i in range(first, e_pos.size()):
		e_slow[i] = float(b.war_band.get("rush", 1.0))


## The shepherd general turns and runs from the legion; false when it is out of his range.
func start_feint(ci: int, sim: Sim) -> bool:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.feint
	var p := e_pos[ci]
	if commander.pos.distance_to(p) > float(cfg.range):
		return false
	feint = {"left": float(cfg.seconds), "from": commander.pos, "dir": (p - commander.pos).normalized() if p != commander.pos else Vector2.RIGHT}
	e_flee[ci] = float(cfg.seconds)
	sim.objectives.notice = {"kind": "feint", "at": time}
	sim.event("rage", p)
	return true


## At the end of his flight he turns: if the legion followed him, he, his guard and the warriors round him rush back in.
func _feint_on(ci: int, dt: float, sim: Sim) -> void:
	if feint.is_empty():
		return
	feint.left -= dt
	if feint.left > 0.0:
		return
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.feint
	var followed: bool = (commander.pos - feint.from).dot(feint.dir) >= float(cfg.follow)
	feint = {}
	e_flee[ci] = 0.0
	if not followed:
		return
	var p := e_pos[ci]
	hasten(ci, float(cfg.rush_seconds), float(cfg.rush_mult))
	for j in near(p, float(cfg.radius)):
		if e_tag[j] == ORDINARY:
			hasten(j, float(cfg.rush_seconds), float(cfg.rush_mult))
	e_face[ci] = (commander.pos - p).normalized() if commander.pos != p else e_face[ci]
	e_strike[ci] = time
	sim.objectives.notice = {"kind": "feint_turn", "at": time}
	sim.event("bellow", p)
	sim.effects.append({"kind": "cry", "pos": p, "t": 0.0, "radius": float(cfg.radius)})


## A general's marked volley: rings over the legion, one on the commander, where missiles thrown from behind him (or from `hidden` px off the flanks) fall once the warning is over.
func volleys(ci: int, sim: Sim, key := "volleys") -> void:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks[key]
	var n := int(cfg.fury_rings) if chief_fury else int(cfg.rings)
	var from := e_pos[ci]
	var hidden := float(cfg.get("hidden", 0.0))
	var side := Vector2.from_angle(sim.facing_angle).orthogonal()
	volley_ids += 1
	for k in n:
		var at: Vector2 = commander.pos
		if k > 0:
			at += Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(float(cfg.radius), float(cfg.spread) + sim.legion_reach * 0.5)
		var thrower := from
		if hidden > 0.0:
			thrower = at + side * (hidden if k % 2 == 0 else -hidden)
		foe_lobs.append({"from": thrower + Vector2(rng.randf_range(-40.0, 40.0), rng.randf_range(-30.0, 30.0)), "to": at, "t": 0.0, "dur": float(cfg.delay),
			"radius": float(cfg.radius), "dmg": float(cfg.damage) * chief_power(), "volley": true, "volley_id": volley_ids, "javelin": hidden > 0.0})
	e_strike[ci] = time
	e_face[ci] = (commander.pos - from).normalized() if commander.pos != from else e_face[ci]
	sim.objectives.notice = {"kind": key, "at": time}
	sim.event("summon", from)


## The general opens the sluices: a band of ground across the legion's path is marked, then floods for a while.
func open_sluices(ci: int, sim: Sim) -> void:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.sluice
	var ahead := Vector2.from_angle(sim.facing_angle)
	flood = {"pos": commander.pos + ahead * float(cfg.ahead), "dir": ahead.orthogonal(), "half_len": float(cfg.length) / 2.0, "half_w": float(cfg.width) / 2.0,
		"t": 0.0, "warn": float(cfg.warn), "seconds": float(cfg.seconds), "slow": float(cfg.slow), "open": false,
		"radius": float(cfg.radius), "rush_seconds": float(cfg.rush_seconds), "rush_mult": float(cfg.rush_mult)}
	e_strike[ci] = time
	sim.objectives.notice = {"kind": "sluice", "at": time}
	sim.event("carnyx", e_pos[ci])


## A band still only marked is called off with the general who marked it; water already flowing drains in its own time.
func _drop_unopened_flood() -> void:
	if not flood.is_empty() and not flood.open:
		flood = {}


## Whether p stands in the band the general floods.
func in_flood(p: Vector2) -> bool:
	if flood.is_empty():
		return false
	var off: Vector2 = p - flood.pos
	return absf(off.dot(flood.dir)) <= flood.half_len and absf(off.dot(flood.dir.orthogonal())) <= flood.half_w


## Fills the marked band once its warning is over, sending the warriors near the legion in as it floods, and drains it when its time is up.
func _sluice_on(dt: float, sim: Sim) -> void:
	flood_slow = 0.0
	if flood.is_empty():
		return
	flood.t += dt
	if flood.t < flood.warn:
		return
	if flood.t >= flood.warn + flood.seconds:
		flood = {}
		return
	if not flood.open:
		flood.open = true
		for j in near(commander.pos, flood.radius):
			if e_tag[j] == ORDINARY:
				hasten(j, flood.rush_seconds, flood.rush_mult)
		sim.event("whirl", flood.pos)
	if in_flood(commander.pos):
		flood_slow = flood.slow


## The Roxolani king marks a lane across the legion and lines his lancers up at its end; false when the legion is out of his range.
func start_lancers(ci: int, sim: Sim) -> bool:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.lancers
	var kind := str(cfg.kind)
	var p := e_pos[ci]
	var c: Vector2 = commander.pos
	if c.distance_to(p) > float(cfg.range) or not content.ready("enemies", kind):
		return false
	# The lane crosses the line from the king to the legion, so the riders come from the side he is not on.
	var dir: Vector2 = (c - p).normalized().orthogonal() if c != p else Vector2.DOWN
	if rng.randf() < 0.5:
		dir = -dir
	wave_n += 1
	var width := float(cfg.width)
	wave = {"from": c - dir * float(cfg.length) / 2.0, "dir": dir, "length": float(cfg.length), "width": width, "t": 0.0, "warn": float(cfg.warn),
		"seconds": float(cfg.seconds), "riders": [], "n": wave_n, "damage": float(cfg.damage) * chief_power(), "throw": float(cfg.throw)}
	var n := int(cfg.riders)
	for k in n:
		if full():
			break
		var across := (k - (n - 1) / 2.0) * width * 0.8 / maxf(1.0, n - 1.0)
		var j := spawn(kind, wave.from + dir.orthogonal() * across)
		e_cd[j] = INF
		e_face[j] = dir
		wave.riders.append([e_id[j], across])
	e_strike[ci] = time
	sim.objectives.notice = {"kind": "lancers", "at": time}
	sim.event("carnyx", p)
	return true


## Holds the lancers at the end of their lane while it is marked, then sweeps them down it, riding down every Roman they reach.
func _lancers_on(dt: float, sim: Sim) -> void:
	if wave.is_empty():
		return
	wave.t += dt
	var run: float = (wave.t - wave.warn) / wave.seconds
	var k := clampf(run, 0.0, 1.0)
	var dir: Vector2 = wave.dir
	var side := dir.orthogonal()
	var kept: Array = []
	var hit_any := false
	var dmg: float = wave.damage * sim.frenzy_guard()
	for w in wave.riders:
		var j := e_id.find(w[0])
		if j < 0:
			continue
		var r := k_radius[e_kind[j]]
		var lane: Vector2 = wave.from + dir * wave.length * k + side * float(w[1])
		var at := _clear_of(lane, r, sim)
		if run > 0.0:
			# A wall, tree or rock in a rider's way ends his charge where he meets it.
			if at.distance_squared_to(lane) > 0.25:
				e_pos[j] = _clear_of(e_pos[j], r, sim)
				_free_rider(j)
				continue
			hit_any = _ride_down(at, r, dir, -2000 - int(wave.n), dmg, wave.throw, sim, 0.5) or hit_any
		e_pos[j] = at
		e_face[j] = dir
		kept.append(w)
	wave.riders = kept
	if hit_any:
		sim.shake = maxf(sim.shake, float(sim.b.shake.chieftain))
		sim.legion.remove_fallen(sim)
	if run >= 1.0 or kept.is_empty():
		_end_wave()


## The lancers of a spent or called off sweep ride on as ordinary lancers.
func _end_wave() -> void:
	for w in wave.get("riders", []):
		var j := e_id.find(w[0])
		if j >= 0:
			_free_rider(j)
	wave = {}


func _free_rider(j: int) -> void:
	e_cd[j] = k_dash_every[e_kind[j]] * rng.randf()


## Where a rider of radius r at p stands once moved out of the trees, rocks, walls, wheat and gorges there.
func _clear_of(p: Vector2, r: float, sim: Sim) -> Vector2:
	return sim.terrain.push_out_wide(p, r) if r > Terrain.MAX_UNIT else sim.terrain.push_out(p, r)


## The king sets the grass alight on one side of the legion: a band is marked across it, and once the warning is over the fire spreads over it towards the legion.
func set_fire(ci: int, sim: Sim) -> void:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.steppe_fire
	var dir := Vector2.from_angle(rng.randf() * TAU)
	steppe_fire = {"pos": commander.pos - dir * float(cfg.back), "dir": dir, "half_len": float(cfg.length) / 2.0, "depth": float(cfg.depth), "t": 0.0,
		"warn": float(cfg.warn), "seconds": float(cfg.seconds), "burn": float(cfg.burn), "dps": float(cfg.dps) * chief_power(), "lit": false}
	e_strike[ci] = time
	sim.objectives.notice = {"kind": "steppe_fire", "at": time}
	sim.event("bellow", e_pos[ci])


## Whether p lies in the band the king marked for burning.
func in_fire_band(p: Vector2) -> bool:
	if steppe_fire.is_empty():
		return false
	var off: Vector2 = p - steppe_fire.pos
	var along: float = off.dot(steppe_fire.dir)
	return along >= 0.0 and along <= steppe_fire.depth and absf(off.dot(steppe_fire.dir.orthogonal())) <= steppe_fire.half_len


## How far across the band the fire has spread, and how far behind it the grass has burnt out, in px from its starting edge.
func fire_span() -> Vector2:
	if steppe_fire.is_empty():
		return Vector2.ZERO
	var lit: float = steppe_fire.t - steppe_fire.warn
	var front: float = steppe_fire.depth * clampf(lit / steppe_fire.seconds, 0.0, 1.0)
	var back: float = steppe_fire.depth * clampf((lit - steppe_fire.burn) / steppe_fire.seconds, 0.0, 1.0)
	return Vector2(back, front)


## Spreads the fire over its band once the warning is over, burning every Roman in the strip alight, until the last of the grass burns out.
func _fire_on(dt: float, sim: Sim) -> void:
	if steppe_fire.is_empty():
		return
	steppe_fire.t += dt
	if steppe_fire.t < steppe_fire.warn:
		return
	if not steppe_fire.lit:
		steppe_fire.lit = true
		sim.event("fire", steppe_fire.pos)
	if steppe_fire.t >= steppe_fire.warn + steppe_fire.seconds + steppe_fire.burn:
		steppe_fire = {}
		return
	var span := fire_span()
	var guard := sim.frenzy_guard()
	var side: Vector2 = steppe_fire.dir.orthogonal()
	for u in sim.units:
		var off: Vector2 = u.pos - steppe_fire.pos
		var along: float = off.dot(steppe_fire.dir)
		if along >= span.x and along <= span.y and absf(off.dot(side)) <= steppe_fire.half_len:
			u.hp -= steppe_fire.dps * dt * guard * sim.front_guard(u)
	sim.legion.remove_fallen(sim)


## Grass only marked is called off with the king who marked it; a fire already burning burns out in its own time.
func _drop_unlit_fire() -> void:
	if not steppe_fire.is_empty() and not steppe_fire.lit:
		steppe_fire = {}


## A lasso rider swings his rope at the soldier nearest him; false when none is in reach.
func _swing_lasso(i: int, sim: Sim) -> bool:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[i]]].lasso
	var p := e_pos[i]
	var best: Dictionary = {}
	var near_d := float(cfg.reach) + Sim.UNIT_RADIUS
	for u in sim.soldiers:
		var d: float = u.pos.distance_to(p)
		if d < near_d:
			near_d = d
			best = u
	if best.is_empty() or lassos.any(func(l: Dictionary) -> bool: return is_same(l.unit, best)):
		return false
	lassos.append({"id": e_id[i], "unit": best, "t": 0.0, "dur": float(cfg.windup)})
	e_strike[i] = time
	e_face[i] = (best.pos - p).normalized() if best.pos != p else e_face[i]
	sim.event("ride", p)
	return true


## Once a lasso's wind-up is over it drags its soldier out of the ranks towards the rider, unless he carries a shield and the testudo holds him in place.
func _lassos(dt: float, sim: Sim) -> void:
	if lassos.is_empty():
		return
	var left: Array = []
	var pulled := false
	for l in lassos:
		l.t += dt
		var i := e_id.find(l.id)
		if i < 0 or not sim.soldiers.any(func(so: Dictionary) -> bool: return is_same(so, l.unit)):
			continue
		if l.t < l.dur:
			left.append(l)
			continue
		var u: Dictionary = l.unit
		if sim.testudo_left > 0.0 and Sim.shielded(u):
			sim.event("shield", u.pos)
			continue
		var cfg: Dictionary = content.enemies[kind_ids[e_kind[i]]].lasso
		var to: Vector2 = e_pos[i] - u.pos
		var gap := to.length() - k_radius[e_kind[i]] - Sim.UNIT_RADIUS
		if gap > 0.0:
			u.pos += to.normalized() * minf(float(cfg.pull), gap)
		u.hp -= float(cfg.damage) * e_power[i] * sim.frenzy_guard() * sim.front_guard(u)
		u.flash = 0.12
		pulled = true
	lassos = left
	if pulled:
		sim.units_moved()
		sim.legion.remove_fallen(sim)


## In her second phase the queen burns the land: rings are marked round the legion, one on the commander, and each catches fire and burns a while.
func burn_land(ci: int, sim: Sim) -> void:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.burn
	for k in int(cfg.rings):
		var at: Vector2 = commander.pos
		if k > 0:
			at += Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(float(cfg.radius), float(cfg.spread) + sim.legion_reach * 0.5)
		marks.append({"kind": "fire", "id": e_id[ci], "pos": at, "t": 0.0, "dur": float(cfg.warn), "radius": float(cfg.radius), "seconds": float(cfg.seconds), "dps": float(cfg.dps) * chief_power()})
	e_strike[ci] = time
	sim.event("bellow", e_pos[ci])


## Marks the chieftain's charge on the ground and holds him still until it starts.
func _warn_charge(ci: int, cfg: Dictionary) -> void:
	var kind := e_kind[ci]
	charge_cd = float(cfg.every)
	charge_warn = float(cfg.warn)
	charge_total = charge_warn
	charge_from = e_pos[ci]
	charge_dir = (commander.pos - e_pos[ci]).normalized()
	charge_len = k_speed[kind] * k_dash_mult[kind] * k_dash_secs[kind]
	charge_width = k_radius[kind] * 2.0
	_hold(ci, charge_warn)


func _hold(ci: int, seconds: float) -> void:
	chief_hold = maxf(chief_hold, seconds)
	hold_pos = e_pos[ci]


## A red ring round the chieftain that strikes everyone inside when it has filled; false when nobody is in it.
func slam(ci: int, sim: Sim) -> bool:
	var kind := e_kind[ci]
	var atk: Dictionary = content.enemies[kind_ids[kind]].attacks.slam
	var p := e_pos[ci]
	var r := float(atk.radius)
	var reach := (r + Sim.UNIT_RADIUS) * (r + Sim.UNIT_RADIUS)
	for u in sim.units:
		if (u.pos - p).length_squared() < reach:
			foe_lobs.append({"from": p, "to": p, "t": 0.0, "dur": float(atk.windup), "radius": r, "dmg": k_dps[kind] * float(atk.damage_mult) * chief_power(), "slam": true, "by": e_id[ci]})
			_hold(ci, float(atk.windup))
			# The chop is timed to come down as the ring fills.
			e_strike[ci] = time + float(atk.windup) - Atlas.ATTACK_FRAMES / Atlas.ATTACK_FPS
			return true
	return false


## Keeps the chieftain where he stands while he winds up, and throws aside the soldiers his charge runs into.
## The fort is the legion's to hold, so a chieftain shoved or charging through its gate is put back outside the nearest wall.
func _keep_chief_out(sim: Sim) -> void:
	var ci := chieftain_index()
	var fort: Dictionary = sim.objectives.fort
	if ci < 0 or fort.is_empty() or not Legion._in_yard(e_pos[ci], fort):
		return
	var off: Vector2 = e_pos[ci] - fort.centre
	var half := float(fort.half) + k_radius[e_kind[ci]] + 2.0
	var p := e_pos[ci]
	# Out through whichever wall is nearest, the gate's side counting like the others.
	var to_side := half - absf(off.x)
	var to_end := half - absf(off.y)
	if to_side < to_end:
		p.x = fort.centre.x + signf(off.x if off.x != 0.0 else 1.0) * half
	else:
		p.y = fort.centre.y + signf(off.y if off.y != 0.0 else 1.0) * half
	e_pos[ci] = p
	if chief_hold > 0.0:
		hold_pos = p


func _chieftain_after(sim: Sim) -> void:
	var ci := chieftain_index()
	if ci < 0:
		return
	if chief_hold > 0.0:
		e_pos[ci] = hold_pos
	if not charging:
		return
	if e_dash[ci] <= 0.0:
		charging = false
		return
	var kind := e_kind[ci]
	if _shields_stop(ci, e_pos[ci], k_radius[kind], sim):
		charging = false
		e_dash[ci] = 0.0
		return
	var throw := float(content.enemies[kind_ids[kind]].attacks.charge.throw)
	var reach := k_radius[kind] + Sim.UNIT_RADIUS + 2.0
	var side := charge_dir.orthogonal()
	var p := e_pos[ci]
	var hit_any := false
	for u in sim.units:
		var off: Vector2 = u.pos - p
		if off.length_squared() > reach * reach or u.get("thrown", -1) == charge_n:
			continue
		u.thrown = charge_n
		u.hp -= k_burst[kind] * chief_power() * sim.frenzy_guard() * sim.front_guard(u)
		u.flash = 0.12
		hit_any = true
		if not is_same(u, sim.commander):
			u.pos += side * (throw if off.dot(side) >= 0.0 else -throw)
			sim.units_moved()
	if hit_any:
		sim.shake = maxf(sim.shake, float(sim.b.shake.chieftain))
		sim.legion.remove_fallen(sim)


## Turns an enemy to face `dir`; one locked in melee holds his facing a moment, so a man hemmed in on every side does not spin from foe to foe.
func _turn(i: int, dir: Vector2) -> void:
	var way := Sim.dir_index(dir)
	if way != Sim.dir_index(e_face[i]):
		if e_fighting[i] == 1 and time - e_turned[i] < TURN_HOLD:
			return
		e_turned[i] = time
	e_face[i] = dir


## Hurts every soldier in an arc in front of the chieftain; false when nobody is in it.
func cleave(ci: int, sim: Sim) -> bool:
	var kind := e_kind[ci]
	var atk: Dictionary = content.enemies[kind_ids[kind]].attacks.cleave
	var reach := float(atk.reach) + k_radius[kind]
	var dir := e_face[ci]
	var half := float(atk.arc) / 2.0
	var dmg := k_dps[kind] * float(atk.damage_mult) * chief_power()
	var hit_any := false
	for u in sim.units:
		var to: Vector2 = u.pos - e_pos[ci]
		if to.length() > reach + 7.0 or absf(dir.angle_to(to)) > half:
			continue
		var target: Dictionary = sim.legion.shield(u)
		target.hp -= dmg * sim.frenzy_guard() * sim.front_guard(target)
		u.flash = 0.12
		hit_any = true
	if hit_any:
		e_strike[ci] = time
		sim.effects.append({"kind": "cleave", "pos": e_pos[ci], "dir": dir, "t": 0.0, "radius": reach, "arc": float(atk.arc)})
		sim.shake = maxf(sim.shake, float(sim.b.shake.chieftain))
		sim.legion.remove_fallen(sim)
	return hit_any


## A rallying elite shouts every so often, and the barbarians around him move faster for a few seconds.
func _rally(dt: float, sim: Sim) -> void:
	var paced := dt * early_pace()
	for id in elite_ids:
		var i := e_id.find(id)
		if i < 0 or e_stun[i] > 0.0:
			continue
		var info: Dictionary = content.enemies[kind_ids[e_kind[i]]]
		if not info.has("rally"):
			continue
		var cfg: Dictionary = info.rally
		var left: float = rally_cd.get(id, float(cfg.every) * 0.5) - paced
		if left <= 0.0:
			left = float(cfg.every)
			var r2 := float(cfg.radius) * float(cfg.radius)
			var heal := float(cfg.get("heal", 0.0))
			for j in e_pos.size():
				if (e_pos[j] - e_pos[i]).length_squared() <= r2:
					hasten(j, float(cfg.seconds), float(cfg.speed_mult))
					if heal > 0.0 and e_tag[j] == ORDINARY:
						e_hp[j] = minf(e_max[j], e_hp[j] + e_max[j] * heal)
			sim.effects.append({"kind": "cry", "pos": e_pos[i], "t": 0.0, "radius": float(cfg.radius)})
			# The horn blower's rally is a call on his carnyx, so it sounds and he raises the horn.
			if heal > 0.0:
				e_strike[i] = time
				sim.event("carnyx", e_pos[i])
		rally_cd[id] = left


const ABILITY_TIMERS := {"whirlwind": "whirl_cd", "shield_wall": "shield_cd", "call_band": "band_cd", "mend": "mend_cd", "curse": "curse_cd", "blink": "blink_cd",
	"duel": "duel_cd", "blast": "blast_cd", "onrush": "onrush_cd", "blizzard": "blizzard_cd", "wedge": "wedge_cd", "trample": "trample_cd", "tower": "tower_cd",
	"scythe": "scythe_cd", "sky_fire": "fire_cd", "rouse": "rouse_cd", "harden": "harden_cd"}


## The timers and state of elite i, made the first time he is asked for, each timer starting half way so a new boss acts soon.
func boss_state(i: int) -> Dictionary:
	var id := e_id[i]
	if boss.has(id):
		return boss[id]
	var info: Dictionary = content.enemies[kind_ids[e_kind[i]]]
	var st := {"hold": 0.0, "at": e_pos[i], "shield": 0.0, "shield_dir": Vector2.ZERO, "duel": 0.0, "duel_at": Vector2.ZERO, "duel_r": 0.0, "scorned": false,
		"rush_warn": 0.0, "rush_total": 0.0, "rush_left": 0.0, "rush_from": Vector2.ZERO, "rush_dir": Vector2.ZERO, "rush_n": 0, "rush_len": 0.0, "rush_width": 0.0, "wedge": [], "passes": 0}
	for key in ABILITY_TIMERS:
		if info.has(key):
			st[ABILITY_TIMERS[key]] = float(info[key].every) * 0.5
	boss[id] = st
	return st


## Every elite's abilities on their own timers: the berserker's whirlwind and rage, the war band leader's shield and band, the war priest's mending, curse and blink,
## the champion's duel and the horn blower's blast and flight.
func _bosses(dt: float, sim: Sim) -> void:
	curse_left = maxf(0.0, curse_left - dt)
	blast_left = maxf(0.0, blast_left - dt)
	var paced := dt * early_pace()
	for id in elite_ids:
		var i := e_id.find(id)
		if i < 0:
			continue
		var info: Dictionary = content.enemies[kind_ids[e_kind[i]]]
		var st := boss_state(i)
		st.hold = maxf(0.0, st.hold - dt)
		st.shield = maxf(0.0, st.shield - dt)
		var p := e_pos[i]
		var gap: float = (commander.pos - p).length()
		if info.has("rage") and e_fury[i] == 1.0 and e_hp[i] < e_max[i] * float(info.rage.below):
			e_fury[i] = float(info.rage.mult)
			e_power[i] *= float(info.rage.mult)
			sim.event("rage", p)
			sim.effects.append({"kind": "cry", "pos": p, "t": 0.0, "radius": 50.0})
		if e_stun[i] > 0.0:
			continue
		if st.has("whirl_cd"):
			st.whirl_cd -= paced
			if st.whirl_cd <= 0.0 and st.hold <= 0.0:
				st.whirl_cd = _whirl(i, info.whirlwind, sim)
		if st.has("shield_cd"):
			st.shield_cd -= paced
			var cfg: Dictionary = info.shield_wall
			if st.shield_cd <= 0.0 and st.hold <= 0.0 and gap < sim.legion_reach + float(cfg.range):
				st.shield_cd = float(cfg.every)
				st.shield = float(cfg.seconds)
				st.shield_dir = (commander.pos - p).normalized()
				_hold_boss(st, p, float(cfg.seconds))
				sim.event("shield", p)
		if st.has("band_cd"):
			st.band_cd -= paced
			if st.band_cd <= 0.0:
				st.band_cd = float(info.call_band.every)
				war_band_at(sim, p, float(info.call_band.size_mult))
		if st.has("mend_cd"):
			st.mend_cd -= paced
			var cfg: Dictionary = info.mend
			if st.mend_cd <= 0.0 and st.hold <= 0.0:
				st.mend_cd = float(cfg.every)
				marks.append({"kind": "mend", "id": id, "pos": p, "t": 0.0, "dur": float(cfg.windup), "radius": float(cfg.radius), "share": float(cfg.share)})
				_hold_boss(st, p, float(cfg.windup))
		if st.has("curse_cd"):
			st.curse_cd -= paced
			var cfg: Dictionary = info.curse
			if st.curse_cd <= 0.0 and gap < float(cfg.range):
				st.curse_cd = float(cfg.every)
				marks.append({"kind": "curse", "id": id, "pos": commander.pos, "t": 0.0, "dur": float(cfg.windup), "radius": float(cfg.radius), "seconds": float(cfg.seconds), "slow": float(cfg.slow)})
				e_strike[i] = time
		if st.has("blink_cd"):
			st.blink_cd -= paced
			if st.blink_cd <= 0.0 and _blink(i, info.blink, sim):
				st.blink_cd = float(info.blink.every)
		if st.has("duel_cd"):
			var cfg: Dictionary = info.duel
			if st.duel > 0.0:
				st.duel = maxf(0.0, st.duel - dt)
				if (commander.pos - st.duel_at).length() > st.duel_r:
					st.duel = 0.0
					_scorn(i, st, cfg.scorn, sim)
			else:
				st.duel_cd -= paced
				if st.duel_cd <= 0.0 and gap < float(cfg.range):
					duel(i, st, cfg, sim)
		if st.has("onrush_cd"):
			_onrush(i, st, info.onrush, "onrush_cd", dt, paced, gap, sim)
		if st.has("wedge_cd"):
			_onrush(i, st, info.wedge, "wedge_cd", dt, paced, gap, sim)
		if st.has("trample_cd"):
			_onrush(i, st, info.trample, "trample_cd", dt, paced, gap, sim)
		if st.has("scythe_cd"):
			_onrush(i, st, info.scythe, "scythe_cd", dt, paced, gap, sim)
		if st.has("fire_cd"):
			st.fire_cd -= paced
			if st.fire_cd <= 0.0 and gap < float(info.sky_fire.range):
				st.fire_cd = float(info.sky_fire.every)
				sky_fire(i, info.sky_fire, sim)
		if st.has("rouse_cd"):
			st.rouse_cd -= paced
			if st.rouse_cd <= 0.0:
				st.rouse_cd = float(info.rouse.every)
				rouse(i, info.rouse, sim)
		if st.has("harden_cd"):
			st.harden_cd -= paced
			if st.harden_cd <= 0.0:
				st.harden_cd = float(info.harden.every)
				harden(i, info.harden, sim)
		if st.has("tower_cd"):
			st.tower_cd -= paced
			if st.tower_cd <= 0.0 and gap < sim.legion_reach + float(info.tower.range):
				st.tower_cd = float(info.tower.every)
				_tower(i, info.tower, sim)
		if st.has("blizzard_cd"):
			st.blizzard_cd -= paced
			var cfg: Dictionary = info.blizzard
			if st.blizzard_cd <= 0.0 and gap < float(cfg.range):
				st.blizzard_cd = float(cfg.every)
				marks.append({"kind": "blizzard", "id": id, "pos": commander.pos, "t": 0.0, "dur": float(cfg.windup), "radius": float(cfg.radius), "seconds": float(cfg.seconds), "slow": float(cfg.slow), "dps": float(cfg.dps) * e_power[i]})
				e_strike[i] = time
				e_face[i] = (commander.pos - p).normalized()
				sim.event("curse", p)
		if st.has("blast_cd"):
			st.blast_cd -= paced
			var cfg: Dictionary = info.blast
			if st.blast_cd <= 0.0 and gap < sim.legion_reach + float(cfg.range):
				st.blast_cd = float(cfg.every)
				blast(i, cfg, sim)
		if info.has("flee") and e_flee[i] <= 0.0:
			var near := float(info.flee.near) + k_radius[e_kind[i]]
			for u in sim.units:
				if (u.pos - p).length_squared() < near * near:
					e_flee[i] = float(info.flee.seconds)
					break


## A charge down a marked lane to the legion: the falx band leader's, with the warriors round him rushing in beside him,
## the cataphract leader's, at the head of a wedge of riders, and the war elephant's trample, which shakes the ground.
func _onrush(i: int, st: Dictionary, cfg: Dictionary, timer: String, dt: float, paced: float, gap: float, sim: Sim) -> void:
	var p := e_pos[i]
	if st.rush_left > 0.0:
		st.rush_left = maxf(0.0, st.rush_left - dt)
		var k: float = 1.0 - st.rush_left / float(cfg.seconds)
		var lane: Vector2 = st.rush_from + st.rush_dir * float(cfg.length) * k
		var at: Vector2 = sim.terrain.push_out_wide(lane, k_radius[e_kind[i]])
		# A wall, tree or rock that pushes the lane back against the charge ends it where it stands, since the steps beyond would come out on its far side.
		if (at - lane).dot(st.rush_dir) < -0.5:
			st.rush_left = 0.0
			at = sim.terrain.push_out_wide(p, k_radius[e_kind[i]])
		if _shields_stop(i, at, k_radius[e_kind[i]] + float(cfg.get("blade", 0.0)), sim):
			st.rush_left = 0.0
			_hold_boss(st, p, 0.0)
			_end_rush(i, st, cfg, sim, true)
			return
		_hold_boss(st, at, st.rush_left)
		e_pos[i] = at
		e_face[i] = st.rush_dir
		var mark := e_id[i] * 1000 + int(st.rush_n)
		var dmg := k_dps[e_kind[i]] * float(cfg.damage_mult) * e_power[i] * sim.frenzy_guard()
		var hit_any := _ride_down(at, k_radius[e_kind[i]] + float(cfg.get("blade", 0.0)), st.rush_dir, mark, dmg, float(cfg.throw), sim)
		var riding: Array = []
		for w in st.wedge:
			var j := e_id.find(w[0])
			if j < 0:
				continue
			var r := k_radius[e_kind[j]]
			var spot := _in_wedge(at, st.rush_dir, w[1])
			# A rider whose place in the wedge runs into a tree, wall or gorge stops there and leaves the wedge.
			if _clear_of(spot, r, sim).distance_squared_to(spot) > 0.25:
				e_pos[j] = _clear_of(e_pos[j], r, sim)
				_free_rider(j)
				continue
			riding.append(w)
			e_pos[j] = spot
			e_face[j] = st.rush_dir
			hit_any = _ride_down(spot, r, st.rush_dir, mark, dmg * float(cfg.rider_mult), float(cfg.throw), sim) or hit_any
		st.wedge = riding
		if cfg.has("shake"):
			sim.shake = maxf(sim.shake, float(cfg.shake) * 0.5)
		if hit_any:
			sim.shake = maxf(sim.shake, float(cfg.get("shake", sim.b.shake.chieftain)))
			sim.legion.remove_fallen(sim)
		if st.rush_left <= 0.0:
			_end_rush(i, st, cfg, sim, false)
		return
	if st.rush_warn > 0.0:
		st.rush_warn -= dt
		if st.rush_warn <= 0.0:
			st.rush_left = float(cfg.seconds)
			st.rush_n += 1
			e_strike[i] = time
			_hold_boss(st, p, st.rush_left)
			if cfg.has("band_radius"):
				var r2 := float(cfg.band_radius) * float(cfg.band_radius)
				for j in e_pos.size():
					if e_tag[j] == ORDINARY and (e_pos[j] - p).length_squared() <= r2:
						e_slow[j] = maxf(e_slow[j], float(cfg.band_rush))
				sim.effects.append({"kind": "cry", "pos": p, "t": 0.0, "radius": float(cfg.band_radius)})
			if cfg.has("shake"):
				sim.shake = maxf(sim.shake, float(cfg.shake))
				sim.event("slam", p)
			sim.event("charge", p)
		return
	st[timer] -= paced
	if st[timer] <= 0.0 and st.hold <= 0.0 and gap < sim.legion_reach + float(cfg.range):
		st[timer] = float(cfg.every)
		_warn_rush(i, st, cfg, float(cfg.warn), sim)


## Marks the lane of a coming charge from where the elite stands to the legion and holds him still for the warning.
func _warn_rush(i: int, st: Dictionary, cfg: Dictionary, warn: float, sim: Sim) -> void:
	var p := e_pos[i]
	st.rush_warn = warn
	st.rush_total = warn
	st.rush_from = p
	st.rush_dir = (commander.pos - p).normalized() if commander.pos != p else Vector2.RIGHT
	st.rush_len = float(cfg.length)
	st.rush_width = float(cfg.width)
	e_face[i] = st.rush_dir
	_hold_boss(st, p, warn)
	if cfg.has("riders"):
		_form_wedge(i, st, cfg)
	sim.event("rage", p)


## The druid calls fire from the sky onto a line of marked rings across the legion, each falling a moment after the last.
func sky_fire(i: int, cfg: Dictionary, sim: Sim) -> void:
	var p := e_pos[i]
	var dir: Vector2 = (commander.pos - p).normalized() if commander.pos != p else Vector2.RIGHT
	var n := int(cfg.count)
	for k in n:
		var at: Vector2 = commander.pos + dir * float(cfg.step) * (k - (n - 1) / 2.0)
		foe_lobs.append({"from": at, "to": at, "t": 0.0, "dur": float(cfg.delay) + float(cfg.stagger) * k, "radius": float(cfg.radius), "dmg": float(cfg.damage) * e_power[i], "sky": true, "ward": true})
	e_strike[i] = time
	e_face[i] = dir
	sim.event("curse", p)


## The druid's chant heals the warriors round him and sends them running at the legion.
func rouse(i: int, cfg: Dictionary, sim: Sim) -> void:
	var p := e_pos[i]
	for j in near(p, float(cfg.radius)):
		if e_tag[j] == ORDINARY:
			e_hp[j] = minf(e_max[j], e_hp[j] + e_max[j] * float(cfg.share))
			e_slow[j] = maxf(e_slow[j], float(cfg.rush))
	e_strike[i] = time
	sim.event("mend", p)
	sim.effects.append({"kind": "mend", "pos": p, "t": 0.0, "radius": float(cfg.radius)})
	sim.effects.append({"kind": "cry", "pos": p, "t": 0.0, "radius": float(cfg.radius) * 0.6})


## The priest of Sobek blesses the warriors round him, and for a few seconds blows hurt them less.
func harden(i: int, cfg: Dictionary, sim: Sim) -> void:
	var p := e_pos[i]
	ward_cut = float(cfg.cut)
	for j in near(p, float(cfg.radius)):
		if e_tag[j] == ORDINARY:
			e_ward[j] = time + float(cfg.seconds)
	e_strike[i] = time
	sim.event("mend", p)
	sim.effects.append({"kind": "ward", "pos": p, "t": 0.0, "radius": float(cfg.radius)})


## Riders fall in behind the cataphract leader in a wedge, two to a row, each row wider than the last.
func _form_wedge(i: int, st: Dictionary, cfg: Dictionary) -> void:
	var kind := str(cfg.kind)
	if not content.ready("enemies", kind):
		return
	var gap := float(cfg.spacing)
	st.wedge = []
	for k in int(cfg.riders):
		if full():
			break
		var row := k / 2 + 1
		var off := Vector2(-row * gap, row * gap * 0.8 * (1.0 if k % 2 == 0 else -1.0))
		var j := spawn(kind, _in_wedge(e_pos[i], st.rush_dir, off))
		e_cd[j] = INF
		e_face[j] = st.rush_dir
		st.wedge.append([e_id[j], off])


## Where a rider at `off` (behind, beside) in a wedge stands when its point is at `at` heading along `dir`.
func _in_wedge(at: Vector2, dir: Vector2, off: Vector2) -> Vector2:
	return at + dir * off.x + dir.orthogonal() * off.y


## Whether the legion's testudo meets a charging boss whose body of `radius` at p reaches a shield-bearer; if it does, the
## charge breaks on the shields and leaves him dazed for a moment.
func _shields_stop(i: int, p: Vector2, radius: float, sim: Sim) -> bool:
	if sim.testudo_left <= 0.0:
		return false
	var reach := radius + Sim.UNIT_RADIUS + 2.0
	for u in sim.units:
		if Sim.shielded(u) and (u.pos - p).length_squared() <= reach * reach:
			e_stun[i] = maxf(e_stun[i], float(b.testudo_block_stun))
			sim.event("shield", p)
			return true
	return false


## Ends a charge: the spent wedge breaks up into ordinary riders, each soon ready to charge again on his own,
## and a scythed chariot turns to mark a new lane back at the legion, unless the shields stopped it.
func _end_rush(i: int, st: Dictionary, cfg: Dictionary, sim: Sim, stopped: bool) -> void:
	for w in st.wedge:
		var j := e_id.find(w[0])
		if j >= 0:
			e_cd[j] = k_dash_every[e_kind[j]] * rng.randf()
	st.wedge = []
	if cfg.has("passes"):
		st.passes += 1
		if st.passes < int(cfg.passes) and not stopped:
			_warn_rush(i, st, cfg, float(cfg.again_warn), sim)
		else:
			st.passes = 0


## Rides down the Romans a charging rider at p reaches: each is hurt once per charge (`mark`) and thrown to the side,
## a shield-bearer taking only `shield_cut` of the blow while the testudo is up.
func _ride_down(p: Vector2, radius: float, dir: Vector2, mark: int, dmg: float, throw: float, sim: Sim, shield_cut := 1.0) -> bool:
	var reach := radius + Sim.UNIT_RADIUS + 2.0
	var side: Vector2 = dir.orthogonal()
	var hit_any := false
	var up := sim.testudo_left > 0.0
	for u in sim.units:
		var off: Vector2 = u.pos - p
		if off.length_squared() > reach * reach or u.get("rushed", -1) == mark:
			continue
		u.rushed = mark
		u.hp -= dmg * (shield_cut if up and Sim.shielded(u) else 1.0) * sim.front_guard(u)
		u.flash = 0.12
		hit_any = true
		if not is_same(u, sim.commander):
			u.pos += side * (throw if off.dot(side) >= 0.0 else -throw)
			sim.units_moved()
	return hit_any


## The archers in a war elephant's tower shoot at the nearest Romans while it fights or tramples.
func _tower(i: int, cfg: Dictionary, sim: Sim) -> void:
	var p := e_pos[i] + Vector2(0, -k_radius[e_kind[i]] * 0.8)
	var aim: Vector2 = commander.pos - p
	var best := aim.length_squared()
	for u in sim.units:
		var off: Vector2 = u.pos - p
		if off.length_squared() < best:
			best = off.length_squared()
			aim = off
	var n := int(cfg.arrows)
	for a in n:
		_throw(p, aim.normalized().rotated((a - (n - 1) / 2.0) * float(cfg.spread)), float(cfg.damage) * e_power[i], 1)
	sim.tally(3, p)


## The shah's arrow storm: horse archers ride in to ring the legion, and while their quivers last their volleys fall on marked ground round it.
func start_storm(ci: int, sim: Sim) -> void:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.storm
	var kind := str(cfg.kind)
	if not content.ready("enemies", kind):
		return
	var riders: Array = []
	var n := int(cfg.riders)
	var turn := rng.randf() * TAU
	for k in n:
		if full():
			break
		var a := turn + TAU * k / n
		var j := spawn(kind, open_point(commander.pos + Vector2(cos(a) * 1.15, sin(a) * 0.75) * float(cfg.ring) * 1.6))
		riders.append(e_id[j])
	arrow_storm = {"left": float(cfg.seconds), "quiver": int(cfg.quiver), "next": float(cfg.delay), "riders": riders, "train": [], "waiting": false}
	e_strike[ci] = time
	sim.event("summon", e_pos[ci])
	sim.effects.append({"kind": "cry", "pos": e_pos[ci], "t": 0.0, "radius": 120.0})


## Runs the arrow storm: volleys fall on rings near the legion, fewer as the riders die. When the quivers run low a camel train
## comes in with fresh arrows, and the storm ends when its time runs out, every rider is down or the train is cut down before it arrives.
func _arrow_storm(dt: float, sim: Sim) -> void:
	if arrow_storm.is_empty():
		return
	var ci := chieftain_index()
	if ci < 0:
		arrow_storm = {}
		return
	var st := arrow_storm
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.storm
	st.left -= dt
	var riders: Array = []
	for id in st.riders:
		if e_id.has(id):
			riders.append(id)
	st.riders = riders
	var train: Array = []
	for id in st.train:
		var j := e_id.find(id)
		if j < 0:
			continue
		train.append(id)
		if (e_pos[j] - commander.pos).length() < float(cfg.resupply):
			# The train has reached the riders' ring with fresh arrows.
			st.quiver = int(cfg.quiver)
			st.waiting = false
			train = []
			sim.event("summon", e_pos[j])
			sim.effects.append({"kind": "cry", "pos": e_pos[j], "t": 0.0, "radius": 60.0})
			break
	st.train = train
	if st.waiting and train.is_empty():
		st.waiting = false
		st.cut = true
	if st.left <= 0.0 or riders.is_empty() or (st.quiver <= 0 and not st.waiting):
		arrow_storm = {}
		return
	if st.quiver <= int(cfg.train_at) and not st.waiting and not st.get("cut", false):
		_send_train(cfg)
	st.next -= dt
	if st.next > 0.0 or st.quiver <= 0:
		return
	st.next = float(cfg.volley_every)
	st.quiver -= 1
	var zones := mini(int(cfg.zones), (riders.size() + 1) / 2)
	volley_ids += 1
	for k in zones:
		var from := e_pos[e_id.find(riders[rng.randi_range(0, riders.size() - 1)])]
		var at: Vector2 = commander.pos
		if k > 0:
			at += Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(float(cfg.radius), float(cfg.spread) + sim.legion_reach * 0.5)
		foe_lobs.append({"from": from, "to": at, "t": 0.0, "dur": float(cfg.delay), "radius": float(cfg.radius), "dmg": float(cfg.damage) * chief_power(), "volley": true, "volley_id": volley_ids})
	sim.event("arrow", commander.pos)


## A camel train rides in from the edge of the field with fresh arrows for the storm.
func _send_train(cfg: Dictionary) -> void:
	var kind := str(cfg.train_kind)
	if not content.ready("enemies", kind):
		return
	arrow_storm.waiting = true
	var side := rng.randf() * TAU
	var at := open_point(commander.pos + Vector2(cos(side) * 1.15, sin(side) * 0.75) * float(b.spawn_radius))
	var n := int(cfg.train)
	for k in n:
		if full():
			break
		var j := spawn(kind, at + Vector2.from_angle(side).orthogonal() * (k - (n - 1) / 2.0) * 22.0)
		arrow_storm.train.append(e_id[j])


## In his second phase the shah calls in his war elephants from the edge of the field.
func call_in(ci: int, cfg: Dictionary, sim: Sim) -> void:
	var kind := str(cfg.kind)
	if not content.ready("enemies", kind):
		return
	var side := rng.randf() * TAU
	var n := int(cfg.count)
	for k in n:
		var a := side + (k - (n - 1) / 2.0) * 0.5
		spawn(kind, open_point(commander.pos + Vector2(cos(a) * 1.15, sin(a) * 0.75) * float(b.spawn_radius)), true)
	sim.event("boss", e_pos[ci])


## The champion calls out the commander: a ring stands round them both, inside which blows on him land harder.
func duel(i: int, st: Dictionary, cfg: Dictionary, sim: Sim) -> void:
	var p := e_pos[i]
	st.duel_cd = float(cfg.every)
	st.duel = float(cfg.seconds)
	st.duel_at = (p + commander.pos) / 2.0
	st.duel_r = maxf(float(cfg.radius), (commander.pos - p).length() / 2.0 + 40.0)
	e_strike[i] = time
	sim.event("duel", p)
	sim.effects.append({"kind": "cry", "pos": st.duel_at, "t": 0.0, "radius": st.duel_r})


## A commander who walks out of the champion's ring shames him: he hits harder from then on and the warriors round him rush in.
func _scorn(i: int, st: Dictionary, cfg: Dictionary, sim: Sim) -> void:
	var p := e_pos[i]
	if not st.scorned:
		st.scorned = true
		e_power[i] *= float(cfg.power_mult)
	var r2 := float(cfg.radius) * float(cfg.radius)
	for j in e_pos.size():
		if (e_pos[j] - p).length_squared() <= r2:
			hasten(j, float(cfg.seconds), float(cfg.speed_mult))
	sim.event("rage", p)
	sim.effects.append({"kind": "cry", "pos": p, "t": 0.0, "radius": float(cfg.radius)})


## The horn blower's blast: soldiers near enough are hurt and thrown back a step, and the whole legion strikes slower for a few seconds.
func blast(i: int, cfg: Dictionary, sim: Sim) -> void:
	var p := e_pos[i]
	var reach := sim.legion_reach + float(cfg.range)
	var push := float(cfg.push)
	var dmg := float(cfg.get("damage", 0.0)) * e_power[i] * sim.frenzy_guard()
	for u in sim.soldiers:
		var off: Vector2 = u.pos - p
		if off.length_squared() < reach * reach and off.length_squared() > 0.0001:
			u.pos += off.normalized() * push
			u.hp -= dmg * sim.front_guard(u)
	sim.units_moved()
	sim.legion.remove_fallen(sim)
	blast_left = float(cfg.seconds)
	blast_slow = float(cfg.slow)
	e_strike[i] = time
	e_face[i] = (commander.pos - p).normalized()
	sim.event("carnyx", p)
	sim.effects.append({"kind": "trumpet", "pos": p, "t": 0.0, "radius": (commander.pos - p).length() + 30.0})


## Starts the berserker's whirlwind when a Roman is in reach and returns the seconds until he tries again.
func _whirl(i: int, cfg: Dictionary, sim: Sim) -> float:
	var p := e_pos[i]
	var r := float(cfg.radius)
	var reach := (r + Sim.UNIT_RADIUS) * (r + Sim.UNIT_RADIUS)
	for u in sim.units:
		if (u.pos - p).length_squared() < reach:
			var dur := float(cfg.windup)
			foe_lobs.append({"from": p, "to": p, "t": 0.0, "dur": dur, "radius": r, "dmg": k_dps[e_kind[i]] * float(cfg.damage_mult) * e_power[i], "slam": true, "whirl": true, "ward": true, "by": e_id[i]})
			_hold_boss(boss[e_id[i]], p, dur)
			e_strike[i] = time + dur - Atlas.ATTACK_FRAMES / Atlas.ATTACK_FPS
			sim.event("whirl", p)
			_testudo_notice(sim)
			return float(cfg.every)
	return float(cfg.retry)


## Tells the player to raise the testudo, unless another notice is still showing.
func _testudo_notice(sim: Sim) -> void:
	var note: Dictionary = sim.objectives.notice
	if note.is_empty() or note.get("kind", "") == "testudo" or time - float(note.at) >= float(note.get("seconds", b.objectives.notice_seconds)):
		sim.objectives.notice = {"kind": "testudo", "at": time, "seconds": float(b.bosses.testudo_notice)}


## The war priest vanishes from a soldier at his elbow and comes out further from the legion; false when nobody is that close.
func _blink(i: int, cfg: Dictionary, sim: Sim) -> bool:
	var p := e_pos[i]
	var near := float(cfg.near) + k_radius[e_kind[i]]
	var close := false
	for u in sim.units:
		if (u.pos - p).length_squared() < near * near:
			close = true
			break
	if not close:
		return false
	var cpos: Vector2 = commander.pos
	var away := (p - cpos).normalized() if p != cpos else Vector2.RIGHT
	# He always comes out beyond the legion's outer rank, however deep in it he stood.
	var out := maxf(p.distance_to(cpos) + float(cfg.distance), sim.legion_reach + k_radius[e_kind[i]] + Sim.UNIT_RADIUS + 24.0)
	var to := sim.terrain.push_out(cpos + away.rotated(rng.randf_range(-0.6, 0.6)) * out, k_radius[e_kind[i]])
	sim.event("blink", p)
	sim.event("blink", to)
	sim.effects.append({"kind": "smoke", "pos": p, "t": 0.0})
	sim.effects.append({"kind": "smoke", "pos": to, "t": 0.0})
	e_pos[i] = to
	boss[e_id[i]].at = to
	return true


func _hold_boss(st: Dictionary, at: Vector2, seconds: float) -> void:
	st.hold = maxf(st.hold, seconds)
	st.at = at


## Keeps an elite where he stands while he winds up or holds his shield, facing the way his shield points.
func _bosses_after() -> void:
	var owner_sim: Sim = sim_ref.get_ref() if sim_ref != null else null
	for id in elite_ids:
		var st: Dictionary = boss.get(id, {})
		if st.is_empty() or st.hold <= 0.0:
			continue
		var i := e_id.find(id)
		if i < 0:
			continue
		e_pos[i] = st.at
		# The wedge's riders keep their places behind their leader while he waits and while he charges.
		for w in st.wedge:
			var j := e_id.find(w[0])
			if j >= 0:
				var spot := _in_wedge(st.at, st.rush_dir, w[1])
				e_pos[j] = _clear_of(spot, k_radius[e_kind[j]], owner_sim) if owner_sim != null else spot
				e_face[j] = st.rush_dir
		if st.shield > 0.0:
			e_face[i] = st.shield_dir


## The share of a blow from `from` that reaches enemy i: a war band leader's raised shield stops most of a blow from in front,
## the champion's ring makes blows from inside it land harder and stops most from outside, and the king's sworn guard turns harm from him.
func guard_mult(i: int, from: Vector2) -> float:
	if e_ward[i] > time:
		return 1.0 - ward_cut
	if e_tag[i] == CHIEF:
		if not king_wall.is_empty():
			if guards_alive < int(king_wall.min) or not from.is_finite() or from == e_pos[i]:
				return 1.0
			return 1.0 - float(king_wall.cut) if absf((commander.pos - e_pos[i]).angle_to(from - e_pos[i])) <= float(king_wall.arc) / 2.0 else 1.0
		return 1.0 - sworn_cut if sworn_cut > 0.0 and guards_alive >= sworn_min else 1.0
	if e_tag[i] != ELITE or not from.is_finite():
		return 1.0
	var st: Dictionary = boss.get(e_id[i], {})
	if st.is_empty():
		return 1.0
	if st.duel > 0.0:
		var duel_cfg: Dictionary = content.enemies[kind_ids[e_kind[i]]].duel
		return float(duel_cfg.inside_mult) if (from - st.duel_at).length() <= st.duel_r else 1.0 - float(duel_cfg.cut)
	if st.shield <= 0.0:
		return 1.0
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[i]]].shield_wall
	var to := from - e_pos[i]
	if to.length_squared() < 0.0001 or absf(st.shield_dir.angle_to(to)) > float(cfg.arc) / 2.0:
		return 1.0
	return 1.0 - float(cfg.cut)


## The war priests' green and purple rings: mending heals those round him, and a curse slows the legion if the commander is still in it.
func _marks(dt: float, sim: Sim) -> void:
	if marks.is_empty():
		return
	var left: Array = []
	for m in marks:
		m.t += dt
		if m.t < m.dur:
			left.append(m)
			continue
		if m.kind == "mend":
			var pi := e_id.find(m.id)
			if pi < 0:
				continue
			var c := e_pos[pi]
			var r2: float = m.radius * m.radius
			for j in e_pos.size():
				if j != pi and (e_pos[j] - c).length_squared() <= r2:
					e_hp[j] = minf(e_max[j], e_hp[j] + e_max[j] * m.share)
			sim.event("mend", c)
			sim.effects.append({"kind": "mend", "pos": c, "t": 0.0, "radius": m.radius})
		elif m.kind == "fire":
			storms.append({"pos": m.pos, "radius": m.radius, "t": 0.0, "life": m.seconds, "slow": 0.0, "dps": m.dps, "fire": true})
			sim.event("fire", m.pos)
		elif m.kind == "blizzard":
			storms.append({"pos": m.pos, "radius": m.radius, "t": 0.0, "life": m.seconds, "slow": m.slow, "dps": m.dps})
			sim.event("whirl", m.pos)
		elif m.kind == "curse":
			if (commander.pos - m.pos).length() < m.radius:
				curse_left = m.seconds
				curse_slow = m.slow
			sim.event("curse", m.pos)
			sim.effects.append({"kind": "curse", "pos": m.pos, "t": 0.0, "radius": m.radius})
	marks = left


## The priests' blizzards: the commander inside one slows the whole legion's march, and every Roman inside it freezes a little.
func _storms(dt: float, sim: Sim) -> void:
	frost_slow = 0.0
	if storms.is_empty():
		return
	var left: Array = []
	var guard := sim.frenzy_guard()
	for st in storms:
		st.t += dt
		if st.t >= st.life:
			continue
		left.append(st)
		var r2: float = (st.radius + Sim.UNIT_RADIUS) * (st.radius + Sim.UNIT_RADIUS)
		if (commander.pos - st.pos).length_squared() < r2:
			frost_slow = maxf(frost_slow, st.slow)
		for u in sim.units:
			if (u.pos - st.pos).length_squared() < r2:
				u.hp -= st.dps * dt * guard * sim.front_guard(u)
	storms = left
	sim.legion.remove_fallen(sim)


## A war priest throws a burning pot at the thickest knot of Romans and returns the seconds until his next throw.
func _lob_at_ranks(i: int, sim: Sim) -> float:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[i]]].lob
	var best: Vector2 = commander.pos
	var most := -1
	for k in mini(12, sim.units.size()):
		var u: Dictionary = sim.units[rng.randi_range(0, sim.units.size() - 1)]
		var near := 0
		for o in sim.units:
			if (o.pos - u.pos).length_squared() < float(cfg.radius) * float(cfg.radius):
				near += 1
		if near > most:
			most = near
			best = u.pos
	foe_lobs.append({"from": e_pos[i], "to": best, "t": 0.0, "dur": float(cfg.flight), "radius": float(cfg.radius), "dmg": float(cfg.damage) * e_power[i], "ward": true})
	e_strike[i] = time
	sim.event("potthrow", e_pos[i])
	if best != e_pos[i]:
		e_face[i] = (best - e_pos[i]).normalized()
	return float(cfg.every) / early_pace()


func _foe_lobs(dt: float, sim: Sim) -> void:
	if foe_lobs.is_empty():
		return
	var flying: Array = []
	var guard := sim.frenzy_guard()
	for l in foe_lobs:
		# A blow from the caster's own body is called off when he is stunned or falls before it lands.
		if l.has("by"):
			var by := e_id.find(l.by)
			if by < 0 or e_stun[by] > 0.0:
				continue
		l.t += dt
		if l.t < l.dur:
			flying.append(l)
			continue
		var ward: bool = l.get("ward", false)
		for u in sim.units:
			if (u.pos - l.to).length() < l.radius + Sim.UNIT_RADIUS:
				# The rings of one fall or volley overlap, so each soldier is struck by only one of them.
				if l.has("volley_id"):
					if u.get("rocked", -1) == l.volley_id:
						continue
					u.rocked = l.volley_id
				var cut := sim.testudo_guard(u)
				# An elite's marked blow breaks on the raised shields.
				if ward and cut < 1.0:
					cut = 0.0
				u.hp -= l.dmg * cut * guard * sim.front_guard(u)
				u.flash = 0.12
		if l.get("sky", false):
			sim.event("boom", l.to)
			sim.effects.append({"kind": "skyfire", "pos": l.to, "t": 0.0, "radius": l.radius})
			sim.shake = maxf(sim.shake, float(sim.b.shake.hurt))
			continue
		if l.get("volley", false):
			sim.tally(3, l.to)
			sim.effects.append({"kind": "volley", "pos": l.to, "t": 0.0, "radius": l.radius})
			continue
		if not l.get("whirl", false):
			sim.event("slam" if l.get("slam", false) else "potland", l.to)
		sim.effects.append({"kind": "whirl" if l.get("whirl", false) else "boom", "pos": l.to, "t": 0.0, "radius": l.radius})
		sim.shake = maxf(sim.shake, float(sim.b.shake.hurt))
	foe_lobs = flying
	sim.legion.remove_fallen(sim)


## The chieftain's shout: every enemy near him moves faster for a few seconds.
func war_cry(ci: int, sim: Sim) -> void:
	var atk: Dictionary = content.enemies[kind_ids[e_kind[ci]]].attacks.war_cry
	var r2 := float(atk.radius) * float(atk.radius)
	var centre := e_pos[ci]
	for i in e_pos.size():
		if (e_pos[i] - centre).length_squared() <= r2:
			hasten(i, float(atk.seconds), float(atk.speed_mult))
	sim.effects.append({"kind": "cry", "pos": centre, "t": 0.0, "radius": float(atk.radius)})
	sim.event("chieftain", centre)
	sim.shake = maxf(sim.shake, float(sim.b.shake.chieftain))


func _move(dt: float, sim: Sim) -> void:
	var give_up: float = b.give_up_radius
	var gone: Array = []
	var cpos: Vector2 = commander.pos
	var legion_reach := sim.legion_reach
	var reach2 := legion_reach * legion_reach
	var shield: float = b.testudo_damage_taken if sim.testudo_left > 0.0 else 1.0
	var phase := frame % 3
	var slow_recover: float = b.slow_recover
	var rush_fade: float = (float(b.war_band.get("rush", 1.0)) - 1.0) / float(b.war_band.get("rush_seconds", 1.0))
	var heading := Vector2.from_angle(sim.facing_angle)
	var throw_every: float = b.ranged.every
	var strike_secs := Atlas.ATTACK_FRAMES / Atlas.ATTACK_FPS
	# An elite's own calls and charges keep the slow pace of the first bosses, as his other abilities do.
	var elite_dt := dt * early_pace()
	var bare := sim.frenzy_guard()
	var dash_min: float = b.charger.min_distance
	var dash_max: float = b.charger.max_distance
	var foot_cap := float(b.get("foot_pace", INF)) * sim.base_pace()
	var hunt_pace := float(b.get("pursuit", {}).get("pace", 0.0)) * sim.base_pace()
	var sep_range: float = b.separation_range
	var crowd_give: float = b.get("crowd_give", 0.3)
	var crowd_pace: float = b.get("crowd_pace", 1.0)
	var spacing: float = b.get("crowd_spacing", 1.0)
	var units := sim.units
	var ug_near := sim.ug_near
	var ug_head := sim.ug_head
	var ug_next := sim.ug_next
	var ug_all_in := sim.ug_all_in
	var ox := g_origin.x
	var oy := g_origin.y
	var t_origin := sim.terrain.origin
	var t_start := sim.terrain.start
	var t_items := sim.terrain.items
	var t_solid := sim.terrain.solid
	var t_tree := sim.terrain.solid_tree
	var wall_hold := float(sim.b.wall.hold)
	var wall_boss := float(sim.b.wall.boss_batter)
	var rv_start := sim.terrain.rv_start
	var fd_start := sim.terrain.fd_start
	var fields_near := not sim.terrain.fd_rect.is_empty()
	var chop_rate: float = b.felling.barbarian_rate * dt
	var t_cell := Terrain.CELL
	var t_n := Terrain.GN
	var f_dir := sim.terrain.flow_dir
	var f_ready := not f_dir.is_empty()
	var f_origin := sim.terrain.flow_origin
	var f_cell := Terrain.FLOW_CELL
	var f_n := Terrain.FN
	var f_closed := sim.terrain.blocked
	var held := 0
	var solid_range: float = b.solid_range
	var detour_seconds: float = b.detour.seconds
	var stuck_after: float = b.detour.stuck_after
	var stuck_slip: float = b.detour.stuck_slip
	var pace_k := minf(1.0, dt * 18.0)
	var route_range: float = b.detour.get("route_range", solid_range)
	# Everyone on the screen or just off it is spaced and kept out of the trees, however wide the window, so no crowd stands piled on one spot in view.
	var seen_x := view.x / 2.0 + 64.0
	var seen_y := view.y / 2.0 + 64.0
	var slide_until := detour_seconds - float(b.detour.get("slide", 0.0))
	var kite_out := float(b.ranged.kite_out)
	var rear := -Vector2.from_angle(sim.facing_angle)
	var ci := chieftain_index()
	var chief_pos := e_pos[ci] if ci >= 0 else Vector2.ZERO
	var through := ci if charging else -1
	var gs := g_start
	var gi := g_items
	var gr := g_rad
	for i in e_pos.size():
		var kind := e_kind[i]
		var p := e_pos[i]
		var to := cpos - p
		var d := to.length()
		if d > give_up and e_tag[i] != CHIEF and k_rides[kind] == 0 and e_guard[i] == Vector2.ZERO and (absf(to.x) >= seen_x or absf(to.y) >= seen_y):
			# A barbarian the legion has left far behind gives up the chase, so marching away is a real escape.
			gone.append(i)
			continue
		if e_stun[i] > 0.0:
			e_stun[i] -= dt
			e_fighting[i] = 0
			e_want[i] = 0
			e_pace[i] = 0.0
			if e_flash[i] > 0.0:
				e_flash[i] -= dt
			# A throw that stuns him still lands him outside trees and wheat; an ordinary one carried over a lip falls in, and one still at it is left to the throw.
			if d < solid_range or (absf(to.x) < seen_x and absf(to.y) < seen_y):
				if e_tag[i] != ORDINARY:
					e_pos[i] = _clear_of(p, k_radius[kind], sim)
				elif sim.terrain.over_ravine(p, 4.0):
					sim.plunge(i)
				elif sim.terrain.ravine_push(p, k_radius[kind]) == p:
					e_pos[i] = _clear_of(p, k_radius[kind], sim)
			continue
		var r := k_radius[kind]
		var slow := e_slow[i]
		# A slow above 1 is a war band's rush, which fades back to a walk.
		if slow < 1.0:
			e_slow[i] = minf(1.0, slow + dt * slow_recover)
		elif slow > 1.0:
			e_slow[i] = maxf(1.0, slow - dt * rush_fade)
		# A hunter sent after a running legion keeps up with its march.
		var spd := (maxf(k_speed[kind], hunt_pace) if e_bare[i] == 1 else k_speed[kind]) * slow * e_fury[i]
		var power := e_power[i]
		if e_haste[i] > 0.0:
			e_haste[i] -= dt
			spd *= e_haste_mult[i]
		# However hastened, a warrior on foot never outpaces the legion's march; hunters sent after a running legion may.
		if k_foot[kind] == 1 and e_tag[i] == ORDINARY and e_bare[i] == 0:
			spd = minf(spd, foot_cap)
		var v := to / maxf(d, 0.001) * spd
		var beh := k_beh[kind]
		if k_lasso[kind] > 0.0:
			e_cd[i] -= dt
			if e_cd[i] <= 0.0 and d < legion_reach + k_lasso_reach[kind]:
				e_cd[i] = k_lasso[kind] if _swing_lasso(i, sim) else 0.5
		if k_howl[kind] == 1:
			e_cd[i] -= elite_dt if e_tag[i] == ELITE else dt
			if e_cd[i] <= 0.0:
				e_cd[i] = k_beat[kind]
				if d < sep_range:
					_howl(i, sim)
		var circling := false
		if beh == FLANKER:
			var n := -to / maxf(d, 0.001)
			if n.dot(rear) < k_flank_cos[kind]:
				# A flanker walks round the legion just outside its reach, turning the shorter way towards its rear.
				circling = true
				var gap := k_flank_gap[kind]
				var turn := 1.0 if n.x * rear.y - n.y * rear.x > 0.0 else -1.0
				var radial := clampf((legion_reach + gap - d) / gap, -2.0, 1.0)
				v = (Vector2(-n.y, n.x) * turn + n * radial).normalized() * spd
		var g := e_guard[i]
		if g != Vector2.ZERO:
			var gto := chief_pos + g - p
			var gl := gto.length()
			v = gto * (minf(spd, gl / dt) / gl) if gl > 0.5 else Vector2.ZERO
		var dashing := false
		var lobber := beh == LOBBER
		var driver := beh == DRIVER
		var throwing := (beh == RANGED and e_ammo[i] > 0) or lobber or driver
		if driver:
			v = _pass(i, p, to, d, spd, legion_reach, dt, sim)
			circling = true
		elif throwing:
			if d <= k_range[kind] + legion_reach:
				var kite := k_kite[kind]
				# He turns to ride off once soldiers come within `kite`, and keeps riding until he is clear by more, so he never wavers on the line.
				if kite > 0.0 and d < legion_reach + kite + (kite_out if e_kiting[i] == 1 else 0.0):
					e_kiting[i] = 1
					# The Parthian shot: with soldiers closing in he rides straight away, still shooting back over his shoulder,
					# so he faces the way he rides except while he looses an arrow.
					circling = time - e_strike[i] >= strike_secs
					v = -to / maxf(d, 0.001) * spd * k_kite_mult[kind]
				else:
					e_kiting[i] = 0
					# Between throws he circles the legion rather than standing still, so he never looks stuck; a horse archer rides his circles at full pace.
					v = Vector2(-to.y, to.x) / maxf(d, 0.001) * spd * (1.0 if kite > 0.0 else 0.5) * (1.0 if e_id[i] % 2 == 0 else -1.0)
				e_cd[i] -= dt
				if lobber:
					if e_cd[i] <= 0.0 and k_lob[kind] == 1:
						e_cd[i] = _lob_at_ranks(i, sim)
				elif k_tend[kind] > 0.0:
					if e_cd[i] <= 0.0:
						e_cd[i] = k_tend[kind]
						_tend(i, sim)
				elif (e_cd[i] <= 0.0 and k_salvo[kind] == 0) or (salvo_now and k_salvo[kind] > 0):
					e_cd[i] = throw_every
					# A thrower aims at the nearest Roman, so the outer ranks take the axes before the commander does.
					var aim := to
					var best := d * d
					for u in units:
						var off: Vector2 = u.pos - p
						if off.length_squared() < best:
							best = off.length_squared()
							aim = off
					if k_volley_r[kind] > 0.0:
						_volley(i, p + aim, k_dps[kind] * throw_every * power)
					elif k_salvo[kind] > 0:
						# Archers loose together on the drum, each a few arrows fanned round his mark.
						var n := k_salvo[kind]
						for a in n:
							_throw(p, aim.normalized().rotated((a - (n - 1) / 2.0) * k_salvo_spread[kind]), k_dps[kind] * salvo_every / n * power, 2 if k_salvo_stone[kind] == 1 else 1)
						_salvo_fired += 1
					elif k_sling[kind] > 0:
						var n := k_sling[kind]
						for a in n:
							_throw(p, aim.normalized().rotated((a - (n - 1) / 2.0) * k_sling_spread[kind]), k_dps[kind] * throw_every / n * power, 2)
					else:
						_throw(p, aim.normalized(), k_dps[kind] * throw_every * power, 1 if kite > 0.0 and k_rides[kind] == 1 else 0)
					e_ammo[i] -= 1
					e_strike[i] = time
					e_face[i] = aim.normalized()
		# A raider already in melee leaves e_cd to his slash, which counts down the same timer.
		elif k_dash_every[kind] > 0.0 and g == Vector2.ZERO and not (k_slash_every[kind] > 0.0 and e_fighting[i] == 1 and e_dash[i] <= 0.0):
			if e_dash[i] > 0.0:
				e_dash[i] -= dt
				dashing = true
				# The chieftain charges at his own pace, neither hastened nor slowed, so he stops where his marked line ends.
				v = e_dir[i] * (k_speed[kind] if e_tag[i] == CHIEF else spd) * k_dash_mult[kind]
			else:
				e_cd[i] -= elite_dt if e_tag[i] == ELITE else dt
				if e_cd[i] <= 0.0 and d > dash_min and d < (legion_reach + k_dash_reach[kind] if k_dash_reach[kind] >= 0.0 and e_bare[i] == 0 else dash_max) and not circling:
					e_cd[i] = k_dash_every[kind]
					e_dir[i] = to / maxf(d, 0.001)
					e_dash[i] = k_dash_secs[kind]
					if d < 300.0:
						if beh == BEAST:
							_bite(p, sim)
						elif k_flank_off[kind] > 0.0 or k_lance[kind] == 1:
							sim.event("ride", p)
					if k_flank_off[kind] > 0.0:
						# A flank rider aims beside the legion, each on his own side, so his charge runs along its ranks.
						var across := Vector2(-to.y, to.x) / maxf(d, 0.001)
						if e_id[i] % 2 == 1:
							across = -across
						e_dir[i] = (to + across * legion_reach * k_flank_off[kind]).normalized()
		var fleeing := e_flee[i] > 0.0
		if fleeing:
			e_flee[i] -= dt
			v = -to / maxf(d, 0.001) * spd * k_flee_mult[kind]
		var push := e_push[i]
		var seen := absf(to.x) < seen_x and absf(to.y) < seen_y
		# Spacing from neighbours is worked out for a third of the horde each update, in turn.
		# Enemies beyond the screen are not spaced apart, since nobody can see them bunch up.
		if i % 3 == phase and (d < sep_range or seen):
			push = Vector2.ZERO
			var block := 0.0
			var c := cidx(p)
			if c >= 0:
				var kx := c % GW
				var ky := c / GW
				# A boss wider than a grid square looks further for the barbarians he would overlap.
				var ring := 1 if (r + r) * spacing <= CELL else 2
				var x0 := maxi(0, kx - ring)
				var x1 := mini(GW, kx + ring + 1)
				for cy in range(maxi(0, ky - ring), mini(GW, ky + ring + 1)):
					# The grid keeps a row's cells next to each other, so one span covers the row's neighbours.
					# The enemy himself is in the list too, but at no distance he fails the test below.
					for t in range(gs[x0 + cy * GW], gs[x1 + cy * GW]):
						var away := p - e_pos[gi[t]]
						var dd := away.length_squared()
						var min_d := (r + gr[t]) * spacing
						if dd < min_d * min_d and dd > 0.0001:
							var dl := sqrt(dd)
							push += away / dl * (min_d - dl)
							var ahead := -away.dot(to)
							if ahead > 0.0:
								block += (min_d - dl) * ahead / (dl * d)
			e_push[i] = push
			e_block[i] = block
		elif i % 3 == phase:
			# A push worked out earlier is dropped once the enemy is beyond the spacing range.
			e_push[i] = Vector2.ZERO
			e_block[i] = 0.0
			push = Vector2.ZERO
		e_fighting[i] = 0
		var shoved := Vector2.ZERO
		if not throwing and i != through and d < legion_reach + r and (to.length_squared() < reach2 or e_tag[i] == CHIEF):
			var target_unit := -1
			var span := 1 if r + Sim.UNIT_RADIUS + 2.0 <= CELL else ceili((r + Sim.UNIT_RADIUS + 2.0) / CELL)
			var kx := floori(p.x / CELL) - ox
			var ky := floori(p.y / CELL) - oy
			if not ug_all_in:
				target_unit = _nearest_unit(p, r, span, sim)
			elif r > Sim.NEAR_RADIUS or kx < 0 or ky < 0 or kx >= GW or ky >= GW or ug_near[kx + ky * GW] == 1:
				# Only the cells within striking reach of p can hold the unit he strikes.
				var hit_r := Sim.UNIT_RADIUS + r + 2.0
				var best := INF
				for cx in range(maxi(0, maxi(kx - span, floori((p.x - hit_r) / CELL) - ox)), mini(GW, mini(kx + span, floori((p.x + hit_r) / CELL) - ox) + 1)):
					for cy in range(maxi(0, maxi(ky - span, floori((p.y - hit_r) / CELL) - oy)), mini(GW, mini(ky + span, floori((p.y + hit_r) / CELL) - oy) + 1)):
						var ui := ug_head[cx + cy * GW]
						while ui >= 0:
							var dd: float = (units[ui].pos - p).length()
							if dd < hit_r and dd < best:
								best = dd
								target_unit = ui
							ui = ug_next[ui]
			if target_unit >= 0:
				var falx := k_falx[kind] == 1
				# A falx cuts past the shield of a man covering his neighbour, and neither the testudo nor the shield wall turns it.
				var u: Dictionary = units[target_unit] if falx else sim.legion.shield(units[target_unit])
				var guard := bare if falx else bare * (shield if u.get("shield", false) else 1.0)
				var front := 1.0 if falx else sim.front_guard(u)
				u.hp -= k_dps[kind] * dt * guard * front * power
				if dashing:
					u.hp -= k_burst[kind] * guard * front * power
					e_dash[i] = 0.0
					if k_fearless[kind] == 1:
						_battle_cry(i, sim)
					if k_flank_off[kind] > 0.0 or k_lance[kind] == 1:
						e_strike[i] = time
				elif k_slash_every[kind] > 0.0:
					e_cd[i] -= dt
					if e_cd[i] <= 0.0:
						e_cd[i] = k_slash_every[kind]
						_slash(i, units[target_unit].pos - p, guard * power, sim)
				elif k_beat[kind] > 0.0 and k_howl[kind] == 0:
					e_cd[i] -= dt
					if e_cd[i] <= 0.0:
						e_cd[i] = k_beat[kind]
						if falx:
							u.hp -= k_dps[kind] * k_falx_mult[kind] * guard * power
							e_strike[i] = time
							sim.tally(0, p)
						else:
							_maul(i, units[target_unit], guard * power, sim)
				u.flash = 0.08
				if beh == BEAST and bite_cd <= time:
					_bite(p, sim)
				e_fighting[i] = 1
				var foe: Vector2 = units[target_unit].pos - p
				if foe.length_squared() > 0.000001:
					_turn(i, foe.normalized())
				# Only a man fighting ahead of the commander stands in the legion's way; one at its back or side cannot hold it as it marches on.
				if (p - cpos).dot(heading) > 0.0:
					held += 1
				# The crowd behind cannot shove a man locked in melee in among the Romans, so it spreads round the legion instead of filling it.
				var inward := push.dot(to)
				if inward > 0.0 and d > 0.001:
					push -= to * (inward / (d * d))
				var out: Vector2 = p - u.pos
				if out.length() > 0.001:
					shoved = out.normalized() * maxf(0.0, Sim.UNIT_RADIUS + r - out.length()) * 2.0
					push += shoved
				v = Vector2.ZERO
		if (i + frame) % 6 == 0 and (d < route_range or seen) and e_detour[i] <= 0.0 and v != Vector2.ZERO and f_ready and not (dashing or circling or fleeing) and g == Vector2.ZERO:
			# A barbarian about to walk into a wood or a gorge takes the route map round it before he touches it.
			var ahead := p + v * (f_cell / spd) - f_origin
			var ax := floori(ahead.x / f_cell)
			var ay := floori(ahead.y / f_cell)
			if ax >= 0 and ay >= 0 and ax < f_n and ay < f_n and f_closed[ax + ay * f_n] == 1:
				e_detour[i] = detour_seconds * 0.5
		var flow := Vector2.ZERO
		if e_detour[i] > 0.0:
			e_detour[i] -= dt
			if v != Vector2.ZERO:
				var fx := floori((p.x - f_origin.x) / f_cell)
				var fy := floori((p.y - f_origin.y) / f_cell)
				if f_ready and fx >= 0 and fy >= 0 and fx < f_n and fy < f_n:
					flow = f_dir[fx + fy * f_n]
				var w := flow if flow != Vector2.ZERO else v / spd
				if e_detour[i] > slide_until and e_stuck[i] >= 0.0:
					# Against the obstacle he keeps only the part of his way that runs along it, since the coarse route map can point into a rock.
					var n := e_way[i]
					var into := w.dot(n)
					if into < 0.0:
						w -= n * into
						w = Vector2(-n.y, n.x) * e_side[i] if w.length_squared() < 0.09 else w.normalized()
				v = w * spd
		if e_block[i] > 0.0 and v != Vector2.ZERO and not dashing and k_heavy[kind] == 0:
			# A barbarian already pressed into the man ahead stops walking into him and only slides past, so the press does not pile up through the rows.
			var into := v.dot(to)
			if into > 0.0:
				v -= to * (into / (d * d) * minf(1.0, e_block[i] / (r * crowd_give)))
				if v.length_squared() < spd * spd * 0.09:
					# A barbarian with nobody to slide past sidesteps round the crowd to find a gap, rather than waiting behind it.
					v += Vector2(-to.y, to.x) / maxf(d, 0.001) * spd * 0.6 * (1.0 if e_id[i] % 2 == 0 else -1.0)
		var np := p + v * dt
		# A painted warrior's charge carries him through the crowd without being shoved aside.
		if push != Vector2.ZERO and not (dashing and k_fearless[kind] == 1):
			# However many neighbours he overlaps, the crowd never carries a boss faster than his charge, nor a barbarian past `crowd_pace` times his.
			# The chieftain walks on through his own bodyguard instead of being held back by the ring round him.
			# A war wagon rolls on through the crowd instead of being held back by it.
			var step := v * dt + ((push - shoved) * 0.6 if e_tag[i] != CHIEF and k_heavy[kind] == 0 else Vector2.ZERO)
			var most := maxf(v.length(), k_top[kind] * (crowd_pace if e_tag[i] == ORDINARY else 1.0)) * dt
			if step.length_squared() > most * most:
				step *= most / step.length()
			np = p + step + shoved * 0.6
		# Trees and rocks push the barbarian back out, read straight from the terrain grid since this runs for the whole horde.
		# Barbarians well off the screen pass through, since nobody sees them and the check is costly for a full horde.
		var gx := floori((np.x - t_origin.x) / t_cell)
		var gy := floori((np.y - t_origin.y) / t_cell)
		var battering := false
		if (d < solid_range or seen) and e_stuck[i] >= 0.0 and gx >= 0 and gy >= 0 and gx < t_n and gy < t_n:
			var gc := gx + gy * t_n
			var touched := false
			for t in range(t_start[gc], t_start[gc + 1]):
				var so := t_solid[t_items[t]]
				var ax := np.x - so.x
				var ay := np.y - so.y
				var reach := so.z + r
				var d2 := ax * ax + ay * ay
				if d2 < reach * reach and d2 > 0.000001:
					var dl := sqrt(d2)
					np = Vector2(so.x + ax / dl * reach, so.y + ay / dl * reach)
					if dashing and k_rush_stun[kind] > 0.0:
						# A boar cannot turn in its rush, so running into a hedge or stake knocks it senseless.
						e_dash[i] = 0.0
						e_stun[i] = k_rush_stun[kind]
					if v != Vector2.ZERO and t_tree[t_items[t]] == 1:
						sim.terrain.horde_chop(Vector2(so.x, so.y), chop_rate)
					elif v != Vector2.ZERO and t_tree[t_items[t]] == Terrain.WALL:
						battering = true
						sim.terrain.batter(Vector2(so.x, so.y), dt * (wall_boss if e_tag[i] != ORDINARY else 1.0), wall_hold)
					# A barbarian walking into a tree or rock slides along it on the side that leads towards the legion, and keeps that side a while.
					if v != Vector2.ZERO:
						touched = true
						e_way[i] = Vector2(ax, ay) / dl
						if e_detour[i] <= 0.0:
							e_side[i] = 1 if Vector2(-ay, ax).dot(_route(p, to, sim)) >= 0.0 else -1
						e_detour[i] = detour_seconds
			if r > Terrain.MAX_UNIT:
				np = sim.terrain.push_out_wide(np, r)
			elif touched and not battering and e_tag[i] == ORDINARY and not sim.terrain.is_open(p):
				# Inside a wood there is no gap to slide through, so he slips between the trunks along the route map out to open ground.
				e_stuck[i] = -stuck_slip
				e_detour[i] = maxf(e_detour[i], stuck_slip)
		# Wheat holds everyone in the grid, near or far and even while slipping through trees, since a field is too wide to pop out of unseen.
		if fields_near and gx >= 0 and gy >= 0 and gx < t_n and gy < t_n and fd_start[gx + gy * t_n] < fd_start[gx + gy * t_n + 1]:
			var kept := sim.terrain.field_push(np, r)
			if kept != np:
				if dashing and k_rush_stun[kind] > 0.0:
					e_dash[i] = 0.0
					e_stun[i] = k_rush_stun[kind]
				if v != Vector2.ZERO:
					var out_of := (kept - np).normalized()
					if e_detour[i] <= 0.0:
						e_side[i] = 1 if Vector2(-out_of.y, out_of.x).dot(_route(p, to, sim)) >= 0.0 else -1
					e_way[i] = out_of
					e_detour[i] = detour_seconds
				np = kept
		# Every barbarian in the grid is held at a ravine's lip every other update, which is enough since one step is shorter than his radius.
		if (i + frame) % 2 == 0 and gx >= 0 and gy >= 0 and gx < t_n and gy < t_n and rv_start[gx + gy * t_n] < rv_start[gx + gy * t_n + 1]:
			var kept := sim.terrain.ravine_push(np, r, r > Terrain.MAX_UNIT)
			if kept != np and e_tag[i] == ORDINARY and sim.shoved_over(np, kept, shoved):
				sim.plunge(i)
			elif kept != np:
				if v != Vector2.ZERO:
					var out_of := (kept - np).normalized()
					if e_detour[i] <= 0.0:
						e_side[i] = 1 if Vector2(-out_of.y, out_of.x).dot(_route(p, to, sim)) >= 0.0 else -1
					e_way[i] = out_of
					e_detour[i] = detour_seconds
				np = kept
		# A barbarian wedged among trees who makes no headway for a while slips through them for a moment to get free; a boss never does, since he would seem to teleport.
		if e_tag[i] != ORDINARY:
			pass
		elif battering:
			# A barbarian held by a wall batters it down rather than slipping through it.
			e_stuck[i] = 0.0
		elif e_stuck[i] < 0.0:
			e_stuck[i] = minf(0.0, e_stuck[i] + dt)
		elif v != Vector2.ZERO and (np - p).length_squared() < v.length_squared() * dt * dt * 0.0625:
			e_stuck[i] += dt
			if e_stuck[i] > stuck_after:
				e_stuck[i] = -stuck_slip
				e_detour[i] = maxf(e_detour[i], stuck_slip)
		elif e_stuck[i] > 0.0:
			e_stuck[i] = maxf(0.0, e_stuck[i] - dt)
		e_pos[i] = np
		if i % 3 == phase and (d < route_range or seen):
			e_want[i] = 1 if v != Vector2.ZERO else 0
			e_pace[i] += ((np - p).length() / dt - e_pace[i]) * pace_k
		if v != Vector2.ZERO:
			_turn(i, e_dir[i] if dashing else (v.normalized() if circling or fleeing else to / maxf(d, 0.001)))
		if e_flash[i] > 0.0:
			e_flash[i] -= dt
	for k in gone:
		_gave_up.append(e_id[k])
	sim.pressing = held
	sim.legion.remove_fallen(sim)


## A chariot's pass: it steers to run beside the legion just outside its ranks, holds its line as it passes, throwing javelins at the nearest
## Romans, runs on past and swings round for another pass. A chariot carrying warriors sets them down the first time it comes close.
func _pass(i: int, p: Vector2, to: Vector2, d: float, spd: float, reach: float, dt: float, sim: Sim) -> Vector2:
	var kind := e_kind[i]
	var dir := e_dir[i]
	if dir == Vector2.ZERO:
		dir = to / maxf(d, 0.001)
	var ahead := to.dot(dir)
	if (ahead > 0.0 and d > reach + k_pass_lock[kind]) or (ahead <= 0.0 and d > reach + k_pass_far[kind]):
		var side := dir.orthogonal()
		var s := 1.0 if to.dot(side) >= 0.0 else -1.0
		var mark: Vector2 = commander.pos - side * s * (reach + k_pass_gap[kind])
		var want := (mark - p).normalized()
		var swing := dir.angle_to(want)
		# Heading straight away, either way round looks the same and the choice would flip each update, so each chariot keeps to one side.
		if absf(swing) > PI - 0.3:
			swing = PI if e_id[i] % 2 == 0 else -PI
		dir = dir.rotated(clampf(swing, -k_pass_turn[kind] * dt, k_pass_turn[kind] * dt))
	e_dir[i] = dir
	e_cd[i] -= dt
	if e_cd[i] <= 0.0 and d < reach + k_pass_range[kind]:
		e_cd[i] = k_pass_every[kind]
		var aim := to
		var best := d * d
		for u in sim.units:
			var off: Vector2 = u.pos - p
			if off.length_squared() < best:
				best = off.length_squared()
				aim = off
		_throw(p, aim.normalized(), k_dps[kind] * k_pass_every[kind] * e_power[i])
		e_strike[i] = time
	if e_ammo[i] > 0 and d < reach + k_pass_gap[kind] + 30.0:
		e_ammo[i] = 0
		_set_down(i, sim)
	return dir * spd


## Warriors leap down from a passing chariot beside it, ready to fight.
func _set_down(i: int, sim: Sim) -> void:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[i]]].drop
	var kind := str(cfg.kind)
	if not content.ready("enemies", kind):
		return
	var side := e_dir[i].orthogonal()
	var at := e_pos[i]
	var n := int(cfg.count)
	for k in n:
		if full():
			break
		spawn(kind, at + side * (k - (n - 1) / 2.0) * 16.0 - e_dir[i] * 10.0)
	sim.effects.append({"kind": "shout", "pos": at, "t": 0.0, "radius": 24.0})


## A painted warrior's battle cry as his charge strikes home: the soldiers round him are frightened and strike more slowly for a moment.
func _battle_cry(i: int, sim: Sim) -> void:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[i]]].fearless
	var p := e_pos[i]
	var r := float(cfg.cry_radius)
	for u in sim.soldiers:
		if (u.pos - p).length_squared() < r * r:
			u.afraid = float(cfg.cry_seconds)
			u.fear = float(cfg.cry_slow)
	e_strike[i] = time
	sim.effects.append({"kind": "cry", "pos": p, "t": 0.0, "radius": r})
	if time >= cry_heard:
		cry_heard = time + 1.5
		sim.event("rage", p)


## A druid acolyte tends the warriors round him, giving back a share of their health.
func _tend(i: int, sim: Sim) -> void:
	var kind := e_kind[i]
	var p := e_pos[i]
	var healed := false
	for j in near(p, k_tend_r[kind]):
		if j != i and e_tag[j] == ORDINARY and e_hp[j] < e_max[j] and time - e_tended[j] >= k_tend[kind]:
			e_hp[j] = minf(e_max[j], e_hp[j] + e_max[j] * k_tend_share[kind])
			e_tended[j] = time
			healed = true
	if not healed:
		return
	e_strike[i] = time
	sim.effects.append({"kind": "mend", "pos": p, "t": 0.0, "radius": k_tend_r[kind]})
	if time >= tend_heard:
		tend_heard = time + 2.0
		sim.event("mend", p)


## A beast's quiet bite, heard at most once every `bite_every` seconds for the whole pack.
func _bite(p: Vector2, sim: Sim) -> void:
	if time >= bite_cd:
		bite_cd = time + float(b.get("bite_every", 1.0))
		sim.event("bite", p)


## The way the route map leads from p, or straight at the legion where it has none.
func _route(p: Vector2, to: Vector2, sim: Sim) -> Vector2:
	var way := sim.terrain.flow_at(p)
	return to if way == Vector2.ZERO else way


## The index in sim.units of the nearest unit close enough for an enemy at p of radius r to strike, or -1, from the cells the units stood in when the grids were built.
func _nearest_unit(p: Vector2, r: float, span: int, sim: Sim) -> int:
	var units := sim.units
	var target_unit := -1
	var best := INF
	var k := Vector2i(floori(p.x / CELL), floori(p.y / CELL))
	var cells := sim.unit_cells()
	for cx in range(k.x - span, k.x + span + 1):
		for cy in range(k.y - span, k.y + span + 1):
			var ucell: Variant = cells.get(Vector2i(cx, cy))
			if ucell == null:
				continue
			for ui in ucell:
				var dd: float = (units[ui].pos - p).length()
				if dd < Sim.UNIT_RADIUS + r + 2.0 and dd < best:
					best = dd
					target_unit = ui
	return target_unit


## An archer's volley: arrows rise over the horde and fall after a delay on a ring near `at`, harming every Roman in it.
func _volley(i: int, at: Vector2, dmg: float) -> void:
	var kind := e_kind[i]
	var spot := at + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, k_volley_r[kind] * 0.5)
	foe_lobs.append({"from": e_pos[i], "to": spot, "t": 0.0, "dur": k_volley_delay[kind], "radius": k_volley_r[kind], "dmg": dmg * k_volley_mult[kind], "volley": true})


## A draco bearer's howl: the warriors round him run faster for a few seconds.
func _howl(i: int, sim: Sim) -> void:
	var cfg: Dictionary = content.enemies[kind_ids[e_kind[i]]].howl
	var p := e_pos[i]
	var riders: bool = cfg.get("riders", false)
	for j in near(p, float(cfg.radius)):
		if e_tag[j] == ORDINARY and (not riders or k_rides[e_kind[j]] == 1):
			hasten(j, float(cfg.seconds), float(cfg.speed_mult))
	e_strike[i] = time
	sim.effects.append({"kind": "cry", "pos": p, "t": 0.0, "radius": float(cfg.radius)})
	# Several bearers howling at once are heard as one.
	if time >= howl_cd:
		howl_cd = time + 2.0
		sim.event("carnyx", p)


## A bear rears and mauls the soldier in front of it, catching those beside him and throwing them all back a step.
func _maul(i: int, struck: Dictionary, guard: float, sim: Sim) -> void:
	var kind := e_kind[i]
	var p := e_pos[i]
	var r := k_maul_r[kind]
	var dmg := k_dps[kind] * k_maul_mult[kind] * guard
	for u in sim.units:
		var off: Vector2 = u.pos - struck.pos
		if not is_same(u, struck) and off.length_squared() > r * r:
			continue
		var target: Dictionary = sim.legion.shield(u)
		target.hp -= (dmg if is_same(u, struck) else dmg * 0.5) * sim.front_guard(target)
		u.flash = 0.12
		if not is_same(u, sim.commander):
			var away: Vector2 = u.pos - p
			u.pos += (away.normalized() if away.length_squared() > 0.0001 else Vector2.RIGHT) * k_maul_throw[kind]
	sim.units_moved()
	e_strike[i] = time
	e_face[i] = (struck.pos - p).normalized() if struck.pos != p else e_face[i]
	sim.effects.append({"kind": "cleave", "pos": p, "dir": e_face[i], "t": 0.0, "radius": k_radius[kind] + r, "arc": 1.6})
	_bite(p, sim)


## A swordsman's wide slash at the soldier in front of him, which also cuts the next soldier in its arc.
func _slash(i: int, at: Vector2, guard: float, sim: Sim) -> void:
	var kind := e_kind[i]
	var p := e_pos[i]
	var reach := k_slash_reach[kind] + k_radius[kind] + Sim.UNIT_RADIUS
	var half := k_slash_arc[kind] / 2.0
	var dmg := k_dps[kind] * k_slash_mult[kind] * guard
	var cut := 0
	for u in sim.units:
		var off: Vector2 = u.pos - p
		if off.length_squared() > reach * reach or absf(at.angle_to(off)) > half:
			continue
		var target: Dictionary = sim.legion.shield(u)
		target.hp -= dmg * sim.front_guard(target)
		u.flash = 0.12
		cut += 1
		if cut >= 2:
			break
	e_strike[i] = time
	sim.tally(0, p)
	sim.effects.append({"kind": "cleave", "pos": p, "dir": at.normalized(), "t": 0.0, "radius": reach, "arc": k_slash_arc[kind]})


func _throw(from: Vector2, dir: Vector2, dmg: float, kind := 0) -> void:
	var cfg: Dictionary = b.ranged
	sp_pos.append(from + dir * 6.0)
	sp_vel.append(dir * float(cfg.spear_speed) * (float(cfg.get("arrow_mult", 1.0)) if kind == 1 else 1.0))
	sp_dmg.append(dmg)
	sp_life.append(float(cfg.spear_life))
	sp_kind.append(kind)


## Thrown spears fly straight and hurt the first soldier they touch, unless the testudo is up and he carries a shield, which stops them.
func _spears(dt: float, sim: Sim) -> void:
	var n := sp_pos.size()
	if n == 0:
		return
	var reach: float = sim.legion_reach
	var cpos: Vector2 = commander.pos
	var hit_radius := Sim.UNIT_RADIUS + float(b.ranged.spear_radius)
	var scan := reach + hit_radius
	var scan2 := scan * scan
	var struck := false
	var i := n - 1
	while i >= 0:
		var p := sp_pos[i] + sp_vel[i] * dt
		sp_pos[i] = p
		var life := sp_life[i] - dt
		sp_life[i] = life
		var gone := life <= 0.0
		var gap2 := (p - cpos).length_squared()
		if not gone and gap2 <= scan2:
			var ui := _spear_target(p, hit_radius, sim)
			if ui >= 0:
				var u: Dictionary = sim.units[ui]
				var target: Dictionary = sim.legion.shield(u)
				if sim.testudo_guard(target) < 1.0:
					sim.effects.append({"kind": "spark", "pos": p, "t": 0.0})
					gone = true
				else:
					target.hp -= sp_dmg[i] * sim.frenzy_guard() * sim.front_guard(target)
					u.flash = 0.08
					# A sling stone leaves the soldier it strikes reeling for a moment; the commander keeps his head.
					if sp_kind[i] == 2 and not is_same(target, sim.commander):
						target.dazed = sling_stun
					gone = true
					struck = true
		if gone:
			var last := sp_pos.size() - 1
			sp_pos[i] = sp_pos[last]; sp_pos.resize(last)
			sp_vel[i] = sp_vel[last]; sp_vel.resize(last)
			sp_dmg[i] = sp_dmg[last]; sp_dmg.resize(last)
			sp_life[i] = sp_life[last]; sp_life.resize(last)
			sp_kind[i] = sp_kind[last]; sp_kind.resize(last)
		i -= 1
	if struck:
		sim.legion.remove_fallen(sim)


## The first unit, in grid order, within hit_radius of a spear at p, or -1.
func _spear_target(p: Vector2, hit_radius: float, sim: Sim) -> int:
	var kx := floori(p.x / CELL) - g_origin.x
	var ky := floori(p.y / CELL) - g_origin.y
	if sim.ug_all_in:
		for cx in range(maxi(0, kx - 1), mini(GW, kx + 2)):
			for cy in range(maxi(0, ky - 1), mini(GW, ky + 2)):
				var ui := sim.ug_head[cx + cy * GW]
				while ui >= 0:
					if (sim.units[ui].pos - p).length() < hit_radius:
						return ui
					ui = sim.ug_next[ui]
		return -1
	var cells := sim.unit_cells()
	for cx in range(kx + g_origin.x - 1, kx + g_origin.x + 2):
		for cy in range(ky + g_origin.y - 1, ky + g_origin.y + 2):
			var ucell: Variant = cells.get(Vector2i(cx, cy))
			if ucell == null:
				continue
			for ui in ucell:
				if (sim.units[ui].pos - p).length() < hit_radius:
					return ui
	return -1


## A supply cart rolls across the field in a straight line, passing near the commander.
## A stranded supply cart stands somewhere on screen for the legion to reach before it is plundered.
func spawn_cart() -> void:
	var cfg: Dictionary = b.cart
	var owner_sim: Sim = sim_ref.get_ref() if sim_ref != null else null
	var r := float(cfg.radius)
	var reach: float = owner_sim.legion_reach if owner_sim != null else 0.0
	var half: Vector2 = view / 2.0 - Vector2(r, r) * 2.0
	var at := Vector2.INF
	var last: Vector2 = commander.pos
	var clearest := -1.0
	# A cart in a wood or over a gorge could never be reached and one among the men is taken at once, so the open spot of a few tries farthest from them is kept.
	for k in 24:
		var off := Vector2.from_angle(rng.randf() * TAU) * (Vector2(1.6, 1.0) * rng.randf_range(float(cfg.near), float(cfg.far)) + Vector2.ONE * reach)
		last = commander.pos + off.clamp(-half, half)
		if owner_sim == null:
			at = last
			break
		last = owner_sim.terrain.push_out(last, r)
		if not owner_sim.terrain.is_open(last) or owner_sim.terrain.ravine_edge(last) < r:
			continue
		var gap := INF
		for u in owner_sim.units:
			gap = minf(gap, u.pos.distance_to(last))
		if gap > clearest:
			clearest = gap
			at = last
		if gap >= float(cfg.near):
			break
	if at == Vector2.INF:
		at = last
	carts.append({"pos": at, "t": 0.0})
	if owner_sim != null and not cart_tip_shown:
		cart_tip_shown = true
		owner_sim.objectives.notice = {"kind": "cart_tip", "at": owner_sim.time, "seconds": float(cfg.tip_seconds)}


## How solid a supply cart is drawn: whole, fading out over its last seconds.
func cart_alpha(cart: Dictionary) -> float:
	var cfg: Dictionary = b.cart
	return clampf((float(cfg.life) - float(cart.t)) / float(cfg.get("fade", 1.0)), 0.0, 1.0)


func _carts(dt: float, sim: Sim) -> void:
	if carts.is_empty():
		return
	var cfg: Dictionary = b.cart
	var keep: Array = []
	for cart in carts:
		cart.t += dt
		if cart.t > float(cfg.life):
			continue
		var touched := false
		for u in sim.units:
			if (u.pos - cart.pos).length() < float(cfg.radius):
				touched = true
				break
		if touched:
			open_cart(sim)
		else:
			keep.append(cart)
	carts = keep


## Breaking a cart opens a choice of its rewards; the quartermaster's cart rewards let a share of carts be chosen from twice.
func open_cart(sim: Sim) -> void:
	sim.add_supply(2 if rng.randf() < sim.bonus_amount("cart_rewards") else 1)


func cart_reward(sim: Sim, reward: String) -> void:
	match reward:
		"free_choice":
			sim.free_choices += 1
		"heal":
			heal_legion(sim)
		"magnet":
			sim.c_pull.fill(1)


func heal_legion(sim: Sim) -> void:
	for u in [sim.commander] + sim.soldiers:
		u.hp = u.max_hp
	sim.effects.append({"kind": "heal", "pos": commander.pos, "t": 0.0})


## An elite leaves a chest when the chest is drawn.
func drop_chest(pos: Vector2) -> void:
	if content.available.has("prop:chest"):
		chests.append({"pos": pos})


func _chests(sim: Sim) -> void:
	if chests.is_empty():
		return
	var r: float = b.chest.radius
	var keep: Array = []
	for ch in chests:
		if sim.units.any(func(u) -> bool: return (u.pos - ch.pos).length() < r):
			sim.free_choices += 1
		else:
			keep.append(ch)
	chests = keep


## Ends the horde's missiles, marked rings and lasting spells with the battle, since the horde does not move again during the triumph.
func stand_down() -> void:
	sp_pos.clear()
	sp_vel.clear()
	sp_dmg.clear()
	sp_life.clear()
	sp_kind.clear()
	foe_lobs = []
	marks = []
	storms = []
	lassos = []
	_end_wave()
	flood = {}
	steppe_fire = {}
	arrow_storm = {}
	sweep = {}
	leap = {}
	drive = {}
	charge_warn = 0.0
	charging = false
	curse_left = 0.0
	blast_left = 0.0
	frost_slow = 0.0
	flood_slow = 0.0


func nearest(p: Vector2, reach: float) -> int:
	var c := cidx(p)
	if c < 0:
		return -1
	var kx := c % GW
	var ky := c / GW
	var rings := ceili(reach / CELL)
	var best := -1
	var best_d := reach * reach
	var x0 := maxi(0, kx - rings)
	var x1 := mini(GW, kx + rings + 1)
	# The cells of one row lie side by side in g_items, so each row is read as one run.
	for cy in range(maxi(0, ky - rings), mini(GW, ky + rings + 1)):
		for t in range(g_start[x0 + cy * GW], g_start[x1 + cy * GW]):
			var j := g_items[t]
			var dd := (e_pos[j] - p).length_squared()
			if dd < best_d and e_hp[j] > 0.0:
				best_d = dd
				best = j
	return best


## The living enemy whose edge is nearest p within reach, so a soldier pressed against a big boss can strike him.
func nearest_edge(p: Vector2, reach: float) -> int:
	var c := cidx(p)
	if c < 0:
		return -1
	var kx := c % GW
	var ky := c / GW
	# Melee soldiers search every update, so the wide search is kept for while a boss is on the field.
	var rings := ceili((reach + (max_radius if big_alive > 0 else 6.0)) / CELL)
	var best := -1
	var best_d := reach
	var x0 := maxi(0, kx - rings)
	var x1 := mini(GW, kx + rings + 1)
	for cy in range(maxi(0, ky - rings), mini(GW, ky + rings + 1)):
		for t in range(g_start[x0 + cy * GW], g_start[x1 + cy * GW]):
			var j := g_items[t]
			var dd := (e_pos[j] - p).length() - k_radius[e_kind[j]]
			if dd < best_d and e_hp[j] > 0.0:
				best_d = dd
				best = j
	return best


## Indexes of the living enemies within r of p.
func near(p: Vector2, r: float) -> Array:
	var out: Array = []
	var c := cidx(p)
	if c < 0:
		return out
	var kx := c % GW
	var ky := c / GW
	var rings := ceili(r / CELL)
	var r2 := r * r
	var x0 := maxi(0, kx - rings)
	var x1 := mini(GW, kx + rings + 1)
	for cy in range(maxi(0, ky - rings), mini(GW, ky + rings + 1)):
		for t in range(g_start[x0 + cy * GW], g_start[x1 + cy * GW]):
			var j := g_items[t]
			if e_hp[j] > 0.0 and (e_pos[j] - p).length_squared() <= r2:
				out.append(j)
	return out


## Takes away the barbarians who gave up the chase this update. They wait until the legion has fought, since the soldiers
## find their targets through the grid built at the start of the update and removing anyone earlier would shift its places.
func drop_gave_up() -> void:
	if _gave_up.is_empty():
		return
	var i := e_id.size() - 1
	while i >= 0:
		if _gave_up.has(e_id[i]):
			remove_at(i)
		i -= 1
	_gave_up.clear()


## Takes enemy i out by moving the last one into its place, array by array.
func remove_at(i: int) -> void:
	if e_id[i] == chieftain_id:
		chief_dead = true
		e_guard.fill(Vector2.ZERO)
		guards_alive = 0
		# What he was warning of or running dies with him, so no marked path, ambush or flood outlives him.
		charge_warn = 0.0
		charging = false
		sweep = {}
		leap = {}
		drive = {}
		feint = {}
		ambush_wait = 0.0
		_drop_unopened_flood()
		_end_wave()
		_drop_unlit_fire()
	elif e_guard[i] != Vector2.ZERO:
		guards_alive -= 1
	if e_tag[i] == ELITE:
		elite_ids.erase(e_id[i])
		# A wedge whose leader falls breaks up into ordinary riders, as it does when his charge is spent.
		for w in boss.get(e_id[i], {}).get("wedge", []):
			var j := e_id.find(w[0])
			if j >= 0:
				e_cd[j] = k_dash_every[e_kind[j]] * rng.randf()
		boss.erase(e_id[i])
		rally_cd.erase(e_id[i])
	if k_radius[e_kind[i]] > Terrain.MAX_UNIT:
		big_alive -= 1
	k_alive[e_kind[i]] -= 1
	var last := e_pos.size() - 1
	e_id[i] = e_id[last]; e_id.resize(last)
	e_pos[i] = e_pos[last]; e_pos.resize(last)
	e_face[i] = e_face[last]; e_face.resize(last)
	e_hp[i] = e_hp[last]; e_hp.resize(last)
	e_max[i] = e_max[last]; e_max.resize(last)
	e_kind[i] = e_kind[last]; e_kind.resize(last)
	e_burn[i] = e_burn[last]; e_burn.resize(last)
	e_burn_dps[i] = e_burn_dps[last]; e_burn_dps.resize(last)
	e_burn_src[i] = e_burn_src[last]
	e_burn_src.resize(last)
	e_flash[i] = e_flash[last]; e_flash.resize(last)
	e_phase[i] = e_phase[last]; e_phase.resize(last)
	e_fighting[i] = e_fighting[last]; e_fighting.resize(last)
	e_kiting[i] = e_kiting[last]; e_kiting.resize(last)
	e_turned[i] = e_turned[last]; e_turned.resize(last)
	e_strike[i] = e_strike[last]; e_strike.resize(last)
	e_stun[i] = e_stun[last]; e_stun.resize(last)
	e_slow[i] = e_slow[last]; e_slow.resize(last)
	e_push[i] = e_push[last]; e_push.resize(last)
	e_block[i] = e_block[last]; e_block.resize(last)
	e_tag[i] = e_tag[last]; e_tag.resize(last)
	e_cd[i] = e_cd[last]; e_cd.resize(last)
	e_dash[i] = e_dash[last]; e_dash.resize(last)
	e_ammo[i] = e_ammo[last]; e_ammo.resize(last)
	e_detour[i] = e_detour[last]; e_detour.resize(last)
	e_side[i] = e_side[last]; e_side.resize(last)
	e_way[i] = e_way[last]; e_way.resize(last)
	e_dir[i] = e_dir[last]; e_dir.resize(last)
	e_haste[i] = e_haste[last]; e_haste.resize(last)
	e_haste_mult[i] = e_haste_mult[last]; e_haste_mult.resize(last)
	e_guard[i] = e_guard[last]; e_guard.resize(last)
	e_stuck[i] = e_stuck[last]; e_stuck.resize(last)
	e_flee[i] = e_flee[last]; e_flee.resize(last)
	e_want[i] = e_want[last]; e_want.resize(last)
	e_pace[i] = e_pace[last]; e_pace.resize(last)
	e_fury[i] = e_fury[last]; e_fury.resize(last)
	e_power[i] = e_power[last]; e_power.resize(last)
	e_bare[i] = e_bare[last]; e_bare.resize(last)
	e_tended[i] = e_tended[last]; e_tended.resize(last)
	e_ward[i] = e_ward[last]; e_ward.resize(last)
	e_hit[i] = e_hit[last]; e_hit.resize(last)
