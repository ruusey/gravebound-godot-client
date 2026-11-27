class_name LocalPlayer
extends RefCounted

## How much of a correction can be hidden, and how fast the rest unwinds. The cap
## is generous enough to absorb a slow/speed transition's few-px drift without a
## visible snap, and the half-life eases it back over a handful of frames rather
## than one abrupt pop.
const SMOOTHING_CAP_PX := 12.0
const SMOOTHING_HALF_LIFE := 0.09
## The status effects the server's movement step reads (StatusEffectType).
const PARALYZED := 2
const SPEEDY := 4
const SLOWED := 21

## Everything the client knows about the player it controls.
##
## Position lives here rather than in MovementPredictor so that "where am I"
## has one obvious home; the predictor writes to it each tick.

var id := 0
var name := ""
var class_id := 0
## Body size in world px. Defaults to the standard player size; the /size command
## changes it and it arrives on the wire (NetPlayer.size), driving both the shot
## origin (centre) and the rendered scale.
var size := float(GameConstants.PLAYER_SIZE)
## Setting it also settles the slide (below) on the new place, so a spawn, a
## realm change or a test that puts the player somewhere draws it there
## outright; only the predictor, which sets previous_position afterwards,
## slides.
var position := Vector2.ZERO:
	set(value):
		position = value
		previous_position = value
## Where the last 64Hz tick started, and how far the frame is into the next
## one: the predictor keeps both so a frame can be drawn between ticks. Read
## by render_position() only; prediction and collision use `position`.
var previous_position := Vector2.ZERO
var tick_alpha := 0.0
var health := 0
var mana := 0
var stats := {}
## The server's isStatMaxed per stat as bits, in MAXED_BITS order.
var maxed_stats := 0
## What we carry, in the server's slot order. Fed from UpdatePacket here;
## the panel and the item actions read it.
var inventory := Inventory.new()
var facing := "front"
## Which way a side-facing sprite is mirrored. The sheet only has a
## right-facing side clip, so walking left is that clip flipped. Kept here
## rather than read from live Input so a scripted render can reproduce it.
var facing_left := false
var moving := false
## Render-only offset that unwinds a correction over a few frames, so the
## sprite eases back instead of snapping. Never consulted by prediction or
## collision -- those always use the authoritative `position`.
var smooth_offset := Vector2.ZERO
## Walk animation state, advanced by distance travelled.
var walk := WalkCycle.new()
var attack := AttackPose.new()
## Status effect ids currently on us, from PlayerStatePacket, and how many
## times each is stacked, in the same order.
var effects: Array = []
var effect_stacks: Array = []


func reset() -> void:
	id = 0
	name = ""
	position = Vector2.ZERO
	inventory.clear()


func is_present() -> bool:
	return id != 0


func centre() -> Vector2:
	return position + Vector2(size, size) * 0.5


## Where the player is drawn: between the last two ticks, plus whatever is
## left of the last correction.
##
## The predictor steps at the server's 64Hz whatever the frame rate, so a
## 60Hz display sees one step on most frames and two on every sixteenth, and
## a frame that ran long sees several at once. Drawn at the tick position
## that reads as a stutter in time with the frame rate; drawn at the point
## between ticks the frame actually falls on, motion is even. The web client
## draws the tick position and has the same beat. Costs under a tick of
## latency on what is seen, never on what is sent.
func render_position() -> Vector2:
	return interpolated() + smooth_offset


func render_centre() -> Vector2:
	return render_position() + Vector2(size, size) * 0.5


func interpolated() -> Vector2:
	return previous_position.lerp(position, clampf(tick_alpha, 0.0, 1.0))


## A correction larger than the cap is only partly absorbed -- the rest is a
## visible jump, which is the honest outcome for a big disagreement.
func set_smoothing(offset: Vector2) -> void:
	smooth_offset = offset.limit_length(SMOOTHING_CAP_PX)


## Half-life decay, so the offset is frame-rate independent.
func decay_smoothing(delta: float) -> void:
	if smooth_offset == Vector2.ZERO:
		return
	smooth_offset *= pow(0.5, delta / SMOOTHING_HALF_LIFE)
	if smooth_offset.length() < 0.05:
		smooth_offset = Vector2.ZERO


## The heavy per-player update: stats, inventory, name.
func apply_update(data: Dictionary) -> void:
	if int(data.get("playerId", 0)) != id:
		return
	name = data.get("playerName", "")
	stats = data.get("stats", {})
	maxed_stats = int(data.get("maxedStats", 0))
	health = int(data.get("health", 0))
	mana = int(data.get("mana", 0))
	effects = data.get("effectIds", [])
	effect_stacks = data.get("effectStacks", [])
	inventory.apply_update(data)


## The light, frequent HP/MP packet.
func apply_player_state(data: Dictionary) -> void:
	if int(data.get("playerId", 0)) != id:
		return
	health = int(data.get("health", 0))
	mana = int(data.get("mana", 0))
	effects = data.get("effectIds", [])
	effect_stacks = data.get("effectStacks", [])


func enter_realm(response: Dictionary) -> void:
	id = int(response.get("playerId", 0))
	class_id = int(response.get("classId", 0))
	position = Vector2(response.get("spawnX", 0.0), response.get("spawnY", 0.0))


## Equipment slot 0 is the weapon in the post-rework slot order
## (0 weapon, 1 armor, 2 gauntlets, 3 boots, 4 ring).
func equipped_weapon() -> Dictionary:
	return inventory.item_at(0)


func face_toward(direction: Vector2) -> void:
	if direction.length_squared() <= 0.0001:
		return
	facing_left = Facing.mirrored(direction, facing_left)
	facing = Facing.of(direction, facing)
