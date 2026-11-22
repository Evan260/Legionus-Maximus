class_name Livery
extends RefCounted
## The legion's upgrades shown on its soldiers: iron, bronze or gold armour with defence, red, white or purple cloth with attack.

## Alpha values marking armour and cloth pixels in the atlas, as build_atlas.py writes them.
const ARMOUR_ALPHA := 254
const CLOTH_ALPHA := 253
## Added to the red of a soldier's tint so the shader knows the sprite is one of the legion's; no tint comes near it.
const MARK := 16.0
## The colours a part takes, dark to light, by tier; the first tier keeps the art's own colours.
const ARMOUR := [[], [Color(0.20, 0.10, 0.04), Color(0.62, 0.38, 0.16), Color(1.0, 0.86, 0.60)],
	[Color(0.24, 0.15, 0.02), Color(0.80, 0.60, 0.12), Color(1.0, 0.97, 0.72)]]
const CLOTH := [[], [Color(0.16, 0.13, 0.14), Color(0.74, 0.71, 0.66), Color(1.0, 0.99, 0.94)],
	[Color(0.10, 0.02, 0.12), Color(0.42, 0.08, 0.38), Color(0.86, 0.42, 0.80)]]
## Red cloth is dark for its brightness, so it is lifted before it is laid on the ramp.
const CLOTH_LIFT := 1.9


## The armour tier (x) and cloth tier (y) of the legion, from the quartermaster's ranks and the run's drills.
static func tiers(sim: Sim) -> Vector2i:
	var cfg: Dictionary = sim.b.livery
	return Vector2i(_tier(sim, cfg.defence), _tier(sim, cfg.offence))


static func _tier(sim: Sim, aspect: Dictionary) -> int:
	var points := 0
	for id in aspect.quartermaster:
		points += int(sim.bonuses.get(id, 0))
	for id in aspect.drills:
		points += sim.rank(id)
	var tier := 0
	for need in aspect.tiers:
		if points >= int(need):
			tier += 1
	return tier


## A pixel of a soldier as livery.gdshader draws it at these tiers.
static func recolour(c: Color, armour: int, cloth: int) -> Color:
	var tag := c.a8
	if tag != ARMOUR_ALPHA and tag != CLOTH_ALPHA:
		return c
	var lum := c.r * 0.299 + c.g * 0.587 + c.b * 0.114
	if tag == ARMOUR_ALPHA and armour > 0:
		return _ramp(ARMOUR[armour], lum)
	if tag == CLOTH_ALPHA and cloth > 0:
		return _ramp(CLOTH[cloth], minf(1.0, lum * CLOTH_LIFT))
	return Color(c, 1.0)


static func _ramp(stops: Array, lum: float) -> Color:
	var c: Color = stops[0].lerp(stops[1], lum * 2.0) if lum < 0.5 else stops[1].lerp(stops[2], lum * 2.0 - 1.0)
	return Color(c, 1.0)


## A soldier's tint with the legion's mark on it, and the tint the shader takes back off.
static func mark(mod: Color) -> Color:
	return Color(mod.r + MARK, mod.g, mod.b, mod.a)


static func unmark(mod: Color) -> Color:
	return Color(mod.r - MARK, mod.g, mod.b, mod.a)


## Sets the shader's colours for these tiers.
static func apply(mat: ShaderMaterial, t: Vector2i) -> void:
	mat.set_shader_parameter("armour_on", t.x > 0)
	mat.set_shader_parameter("cloth_on", t.y > 0)
	if t.x > 0:
		for i in 3:
			mat.set_shader_parameter("armour_%d" % i, _vec(ARMOUR[t.x][i]))
	if t.y > 0:
		for i in 3:
			mat.set_shader_parameter("cloth_%d" % i, _vec(CLOTH[t.y][i]))
	mat.set_shader_parameter("cloth_lift", CLOTH_LIFT)
	mat.set_shader_parameter("mark", MARK)


static func _vec(c: Color) -> Vector3:
	return Vector3(c.r, c.g, c.b)
