class_name DamageText
extends RefCounted

## The numbers that float off whatever just got hit.
##
## Driven entirely by TextEffectPacket: the server decides what the text says
## and, for a bullet hit, exactly where it struck -- so the number lands where
## the shot connected even though the enemy has moved by the time the packet
## arrives. A zero position means "wherever the target is now", which is what
## heals, status feedback and AoE pulses send.

## The web client counts frames at 60fps; these are the same numbers in
## seconds. Its renderer fades against a shorter life than its model decays
## by -- the two drifted apart upstream -- which leaves a fresh number at full
## alpha for its first fifth of a second and then fades it.
const LIFE := 92.0 / 60.0
const FADE_LIFE := 70.0 / 60.0
## How far apart two numbers can be and still be the same hit.
const MERGE_PX := 24.0
## And how fresh the older one has to be. Past this they are separate hits.
const MERGE_WINDOW := 6.0 / 60.0
## Stacking keeps a burst legible: same-lane numbers within this horizontal
## distance step upward instead of covering each other.
const STACK_PX := 20.0
## The native client's step, not the web client's 8. The two differ because
## the web draws its text in SCREEN space, where 8 world units is 16 px at
## this zoom and clears a 14 px glyph; we draw in world space, like the native
## does, so the step has to be measured in the same units as the text -- at 8
## a burst renders on top of itself.
const STACK_STEP := 14.0
const MAX_STACK := 4
## Status labels ride a lane above the damage, so a shot's number and the
## status it applies never overlap.
const INFO_LANE := 20.0
const INFO_EFFECT := 4
## Rise rate in world pixels per second. The web client floats its text in
## screen space at 0.66px per frame; at the 2x zoom the client runs, that is
## this in world units.
const RISE_PX_PER_SEC := 19.8

## By textEffectId: damage, heal, armor pierce, environment, player info, immune.
## The first five match both older references; IMMUNE (5) is new -- a vivid
## electric violet that reads nothing like a hit, heal or debuff, so "X Immune"
## pops as clearly "nothing happened, on purpose" when a boss shrugs off CC.
const COLORS := [
	Color(1.0, 0.25, 0.25), Color(0.25, 1.0, 0.25), Color(0.30, 0.55, 1.0),
	Color(0.25, 0.50, 1.0), Color(1.0, 0.50, 0.25), Color(0.80, 0.30, 1.0),
]
## textEffectId for IMMUNE -- also the colour the overhead immune pills use.
const IMMUNE_EFFECT := 5
const IMMUNE_COLOUR := Color(0.80, 0.30, 1.0)

var texts: Array = []
var _next_id := 0


static func colour_of(effect_id: int) -> Color:
	if effect_id < 0 or effect_id >= COLORS.size():
		return Color.WHITE
	return COLORS[effect_id]


func clear() -> void:
	texts.clear()


## Applies a TextEffectPacket, given the entities it might be anchored to.
func apply_text_effect(data: Dictionary, entities: EntityRegistry,
		projectiles: ProjectileSystem, local: LocalPlayer = null) -> void:
	var effect_id := int(data.get("textEffectId", 0))
	var label := String(data.get("text", ""))
	var at := Vector2(data.get("posX", 0.0), data.get("posY", 0.0))
	if at == Vector2.ZERO:
		at = TextAnchor.of(int(data.get("entityType", 0)),
			int(data.get("targetEntityId", 0)), entities, projectiles, local)

	# A damage number on an enemy is a hit landing -- anyone's. Positional, so a
	# fight across the map is quieter than one at your feet.
	if (effect_id == Sfx.DAMAGE_EFFECT or effect_id == Sfx.ARMOR_BREAK_EFFECT) \
			and int(data.get("entityType", 0)) == GameConstants.ENTITY_ENEMY:
		Sfx.hit("enemy_hit")

	var info := effect_id == INFO_EFFECT
	var colour := colour_of(effect_id)
	if _merged_into_a_neighbour(label, at, colour):
		return
	_next_id += 1
	texts.append({"id": _next_id, "base": label, "text": label, "pos": at - Vector2(0.0, _lane(at, info)),
		"colour": colour, "life": LIFE, "count": 1, "info": info, "rise": 0.0})


func advance(delta: float) -> void:
	for i in range(texts.size() - 1, -1, -1):
		var text: Dictionary = texts[i]
		text["life"] -= delta
		text["rise"] += RISE_PX_PER_SEC * delta
		if text["life"] <= 0.0:
			texts.remove_at(i)


## Where a number is drawn: its anchor, less however far it has floated.
static func render_position(text: Dictionary) -> Vector2:
	return text["pos"] - Vector2(0.0, text["rise"])


static func alpha_of(text: Dictionary) -> float:
	return clampf(float(text["life"]) / FADE_LIFE, 0.0, 1.0)


## Eight shots landing together read as one number, not eight.
##
## The web client compares against the text it has already rewritten to carry
## the count, so in practice it merges once and then starts a new number --
## which its own comment ("8 wizard shots -> one big number") says is not what
## it means to do. Keeping the original text to compare against is that
## comment's behaviour.
## The web client also compares lanes here. That cannot decide anything: the
## colour is a function of the effect id and all five differ, so a status
## label and a damage number are already separated by the colour test above
## it. Left out rather than carried as a condition no input can reach.
func _merged_into_a_neighbour(label: String, at: Vector2, colour: Color) -> bool:
	for i in range(texts.size() - 1, -1, -1):
		var text: Dictionary = texts[i]
		if text["base"] != label or text["colour"] != colour:
			continue
		if text["life"] <= LIFE - MERGE_WINDOW:
			continue
		var apart: Vector2 = (text["pos"] - at).abs()
		if apart.x >= MERGE_PX or apart.y >= MERGE_PX:
			continue
		text["count"] += 1
		text["text"] = "%s x%d" % [label, text["count"]]
		text["life"] = LIFE
		return true
	return false


## How far above the anchor this one sits, so a burst stacks instead of
## overlapping. Counts only numbers still in their first stretch of life --
## a fading one is nearly gone and should not push a fresh one off the top.
func _lane(at: Vector2, info: bool) -> float:
	var stacked := 0
	for text in texts:
		if text["info"] == info and absf(text["pos"].x - at.x) < STACK_PX \
				and text["life"] > LIFE * 0.4:
			stacked += 1
	return (INFO_LANE if info else 0.0) + mini(stacked, MAX_STACK) * STACK_STEP
