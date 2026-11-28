class_name ProjectileKind
extends RefCounted

## Projectile flags and the motion-type predicates derived from them.
##
## Flag ids are the server's ProjectileFlag enum. Orbital and parametric
## motion are selected the way the working web client does it -- by the
## presence of the parameters, not only the flag -- because content sets
## amplitude/frequency on projectiles that omit the flag.

const PLAYER_PROJECTILE := 10
## A player-owned ally's bullet (a Codex summon): server-authoritative, but it carries
## the owner's id for kill credit, so this flag is what tells the client it is NOT a local
## prediction to claim/cull. Must match ProjectileFlag.ALLY_PROJECTILE on the server.
const ALLY_PROJECTILE := 11
const PARAMETRIC := 12
const INVERTED_PARAMETRIC := 13
const ORBITAL := 20
const ARMOR_PIERCING := 23
const PASS_THROUGH_TERRAIN := 24
const PASS_THROUGH_ENEMIES := 25
## v0.9.0 added these. LINE_SEGMENT and ANCHORED are the common ones -- 101
## and 56 projectiles in the shipped content -- so leaving them unmodelled
## visibly desyncs a realm rather than being an edge case.
const LINE_SEGMENT := 30
const ANCHORED := 31
const SPEED_DECAY := 32
const SPEED_RAMP := 33
const HOMING := 34
const MELEE_SWING := 40
const CRITICAL := 50

## Everything the per-frame loops ask of a bullet, derived once from its flags and
## motion parameters (neither changes in flight) and cached on it as `traits`.
const TRAIT_ORBITAL := 1
const TRAIT_PARAMETRIC := 2
const TRAIT_SPINS := 4
const TRAIT_SPEED_CURVE := 8
const TRAIT_HOMING := 16
const TRAIT_ANCHORED := 32
const TRAIT_LINE_SEGMENT := 64
## PASS_THROUGH_TERRAIN: crosses solid props and trees, never walls.
const TRAIT_PASSES_TERRAIN := 128
const TRAIT_PIERCES := 256
const TRAIT_MELEE_SWING := 512
const TRAIT_ALLY := 1024
const TRAIT_PLAYER_SHOT := 2048
const TRAIT_PREDICTED := 4096
## Set by ProjectileSystem, which knows who the local player is.
const TRAIT_OWNER_RESOLVED := 8192
const TRAIT_OWN := 16384
const TRAIT_CONSUMED := 32768


static func has_flag(bullet: Projectile, flag: int) -> bool:
	return bullet.flag_bits & (1 << flag) != 0


## Whether a content definition (flags as parsed, often floats) carries a flag.
static func definition_has_flag(definition: Dictionary, flag: int) -> bool:
	for value in definition.get("flags", []):
		if int(value) == flag:
			return true
	return false


## The predicates below, as bit tests on the flags rather than calls to them:
## every bullet that arrives is worked out once, and in a burst that adds up.
static func traits(bullet: Projectile) -> int:
	if bullet.traits >= 0:
		return bullet.traits
	var flags := bullet.flag_bits
	var bits := 0
	if flags & (1 << ORBITAL):
		bits |= TRAIT_ORBITAL
	elif flags & ((1 << PARAMETRIC) | (1 << INVERTED_PARAMETRIC)) \
			or (bullet.amplitude != 0.0 and bullet.frequency != 0.0):
		bits |= TRAIT_PARAMETRIC
	if flags & (1 << LINE_SEGMENT):
		bits |= TRAIT_LINE_SEGMENT
		if bullet.frequency != 0.0:
			bits |= TRAIT_SPINS
	if flags & ((1 << SPEED_DECAY) | (1 << SPEED_RAMP)):
		bits |= TRAIT_SPEED_CURVE
	if flags & (1 << HOMING):
		bits |= TRAIT_HOMING
	if flags & (1 << ANCHORED):
		bits |= TRAIT_ANCHORED
	if flags & (1 << PASS_THROUGH_TERRAIN):
		bits |= TRAIT_PASSES_TERRAIN
	if flags & (1 << PASS_THROUGH_ENEMIES):
		bits |= TRAIT_PIERCES
	if flags & (1 << MELEE_SWING):
		bits |= TRAIT_MELEE_SWING
	if flags & (1 << ALLY_PROJECTILE):
		bits |= TRAIT_ALLY
	if flags & (1 << PLAYER_PROJECTILE):
		bits |= TRAIT_PLAYER_SHOT
	if bullet.predicted:
		bits |= TRAIT_PREDICTED
	bullet.traits = bits
	return bits


static func is_orbital(bullet: Projectile) -> bool:
	return has_flag(bullet, ORBITAL)


static func is_parametric(bullet: Projectile) -> bool:
	if is_orbital(bullet):
		return false
	if has_flag(bullet, PARAMETRIC) or has_flag(bullet, INVERTED_PARAMETRIC):
		return true
	# The flag is not required: 16 projectiles in the shipped content set
	# amplitude and frequency without it, and the web client waves those too.
	return bullet.amplitude != 0.0 and bullet.frequency != 0.0


## A LINE_SEGMENT wall given a frequency sweeps around its anchor instead of
## travelling, so its angle advances every tick.
static func spins(bullet: Projectile) -> bool:
	return has_flag(bullet, LINE_SEGMENT) and bullet.frequency != 0.0


static func is_anchored(bullet: Projectile) -> bool:
	return has_flag(bullet, ANCHORED)


static func is_homing(bullet: Projectile) -> bool:
	return has_flag(bullet, HOMING)


static func has_speed_curve(bullet: Projectile) -> bool:
	return has_flag(bullet, SPEED_DECAY) or has_flag(bullet, SPEED_RAMP)


static func is_player_shot(bullet: Projectile) -> bool:
	return has_flag(bullet, PLAYER_PROJECTILE)
