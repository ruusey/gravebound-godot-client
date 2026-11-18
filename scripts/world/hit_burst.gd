class_name HitBurst
extends RefCounted

## The little cloud of pixels that sprays off whatever a shot just hit.
##
## Driven by the same TextEffectPacket that floats the damage number, so it
## fires on every confirmed hit -- anyone's shot on an enemy, an enemy's shot
## on us -- and never on a shot the server did not score (no fake hits). Each
## particle is a chip of the target's own sprite, sampled once per enemy/class
## and reused, falling back to blood when the sheet can't be read.
##
## Drawn over the body and centred on it, spraying radially out, so a hit reads
## as a clear pop of the target's own colour. A short per-target cooldown caps
## how often one enemy can throw a burst, so high-rate-of-fire focus-fire from
## several players doesn't stack into a solid smear.

## Which textEffectIds count as "a hit landed" -- the same two the hit SFX uses.
const HIT_EFFECTS := [Sfx.DAMAGE_EFFECT, Sfx.ARMOR_BREAK_EFFECT]
## One target can throw at most one burst this often, so focus-fire doesn't bury it.
const COOLDOWN_MS := 45
## Chips per burst, all drawn over the sprite.
const CHIP_COUNT := 12
## Chip travel, world px/s; the field's drag slows them within ~25px of the hit.
const SPEED_MIN := 40.0
const SPEED_MAX := 120.0
const LIFE_MIN := 0.32
const LIFE_MAX := 0.55
## Chip edge in world px, scaled off the body so a big enemy throws bigger chips.
const PIXEL_MIN := 3.0
const PIXEL_MAX := 7.0
const PIXEL_PER_BODY := 0.12
## Up to this many colours sampled from a sprite; the spray picks among them.
const SAMPLE_MAX := 10
## Blood, for when a sheet can't be read (or an unknown target). A static var, not
## a const: Color.html/Color(hex) is a runtime call, so the array isn't const-foldable.
static var BLOOD := PackedColorArray([
	Color("c81212"), Color("9e0d0d"), Color("7a0a0a"), Color("e8382a")])

var chips := ParticleField.new()

var _content: GameData
var rng := RandomNumberGenerator.new()
## Sampled sprite colours, by "e:<enemyId>" / "p:<classId>:<dye>"; built once each.
var _palettes := {}
## Target entity id -> last burst time (ms), for the per-target cooldown.
var _last_ms := {}
var _no_bullets := {}


func _init(content: GameData = null) -> void:
	_content = content


func clear() -> void:
	chips.clear()
	_last_ms.clear()


## Steps the pool; it only moves and ages (no emission of its own).
func advance(delta: float) -> void:
	chips.advance(delta, _no_bullets)


## Looks at a TextEffectPacket and throws a burst when it is a hit landing on an
## entity and the option is on. Mirrors DamageText's own gating and anchoring so
## the chips land where the number does.
func consider(data: Dictionary, entities: EntityRegistry, projectiles: ProjectileSystem,
		local: LocalPlayer, settings: GameSettings) -> void:
	if _content == null or settings == null or not settings.is_on("hit_particles"):
		return
	var effect_id := int(data.get("textEffectId", 0))
	if not HIT_EFFECTS.has(effect_id):
		return
	var entity_type := int(data.get("entityType", 0))
	if entity_type != GameConstants.ENTITY_ENEMY and entity_type != GameConstants.ENTITY_PLAYER:
		return
	var target_id := int(data.get("targetEntityId", 0))
	var now := Time.get_ticks_msec()
	var last: int = _last_ms.get(target_id, -COOLDOWN_MS)
	if now - last < COOLDOWN_MS:
		return
	_last_ms[target_id] = now
	if _last_ms.size() > 512:
		_prune(now)

	var at := Vector2(data.get("posX", 0.0), data.get("posY", 0.0))
	if at == Vector2.ZERO:
		at = TextAnchor.of(entity_type, target_id, entities, projectiles, local)

	var entity: Dictionary = {}
	var body := float(GameConstants.PLAYER_SIZE)
	if entity_type == GameConstants.ENTITY_ENEMY:
		entity = entities.enemies.get(target_id, {})
		body = float(entity.get("size", GameConstants.TILE_SIZE))
	else:
		entity = entities.players.get(target_id, {})
		body = float(entity.get("size", GameConstants.PLAYER_SIZE))

	# Centre the burst on the body, not on the exact impact point, so the pop
	# reads as "this thing got hit" rather than a speck at its edge. Falls back to
	# the packet's point when the entity has already been unloaded.
	var centre := at
	if not entity.is_empty():
		centre = entities.render_position(entity) + Vector2(body, body) * 0.5

	var palette := _palette(entity_type, entity)
	var pixel := clampf(body * PIXEL_PER_BODY, PIXEL_MIN, PIXEL_MAX)
	for i in CHIP_COUNT:
		_spray(chips, centre, body, pixel, palette)


## One chip: picked colour, flung out from the body centre in any direction,
## spawned on the centre with a little jitter and set to shrink slightly as it
## fades.
func _spray(field: ParticleField, centre: Vector2, body: float, pixel: float,
		palette: PackedColorArray) -> void:
	var angle := rng.randf_range(0.0, TAU)
	var velocity := Vector2(cos(angle), sin(angle)) * rng.randf_range(SPEED_MIN, SPEED_MAX)
	var colour: Color = palette[rng.randi() % palette.size()]
	if rng.randf() < 0.4:
		colour = colour.darkened(rng.randf_range(0.1, 0.35))
	var jitter := body * 0.12
	var spawn_at := centre + Vector2(rng.randf_range(-jitter, jitter), rng.randf_range(-jitter, jitter))
	field.spawn(spawn_at, velocity, rng.randf_range(LIFE_MIN, LIFE_MAX), pixel,
		pixel * rng.randf_range(0.65, 1.0), colour)


## The target's sprite colours, sampled once and kept. Enemies use their static
## sprite; players their class frame. Anything unreadable falls back to blood.
func _palette(entity_type: int, entity: Dictionary) -> PackedColorArray:
	var key: String
	var texture: Texture2D = null
	if entity_type == GameConstants.ENTITY_ENEMY:
		var enemy_id := int(entity.get("enemy_id", -1))
		key = "e:%d" % enemy_id
		if not _palettes.has(key):
			texture = _content.enemy_texture(enemy_id)
	else:
		var class_id := int(entity.get("class_id", 0))
		var dye := int(entity.get("dye_id", 0))
		key = "p:%d:%d" % [class_id, dye]
		if not _palettes.has(key):
			texture = _content.classes_art.frame(class_id, "idle", "side", 0, dye)
	if not _palettes.has(key):
		_palettes[key] = _sample(texture)
	return _palettes[key]


## Up to SAMPLE_MAX opaque colours stepped across a sprite's atlas region, or
## blood when the region can't be read (compressed/absent texture, or all clear).
static func _sample(texture: Texture2D) -> PackedColorArray:
	var out := PackedColorArray()
	var atlas := texture as AtlasTexture
	if atlas != null and atlas.atlas != null:
		var image := atlas.atlas.get_image()
		if image != null:
			var region := atlas.region
			var x0 := int(region.position.x)
			var y0 := int(region.position.y)
			var step_x := maxi(1, int(region.size.x) / 8)
			var step_y := maxi(1, int(region.size.y) / 8)
			var py := y0
			while py < y0 + int(region.size.y) and out.size() < SAMPLE_MAX:
				var px := x0
				while px < x0 + int(region.size.x) and out.size() < SAMPLE_MAX:
					if px >= 0 and py >= 0 and px < image.get_width() and py < image.get_height():
						var colour := image.get_pixel(px, py)
						if colour.a >= 0.5:
							out.append(Color(colour.r, colour.g, colour.b, 1.0))
					px += step_x
				py += step_y
	return out if not out.is_empty() else BLOOD


## Drop cooldown stamps older than a few cooldowns so the map can't grow without
## bound in a long fight; recent targets (the ones that matter) are kept.
func _prune(now: int) -> void:
	for id in _last_ms.keys():
		if now - int(_last_ms[id]) > COOLDOWN_MS * 8:
			_last_ms.erase(id)
