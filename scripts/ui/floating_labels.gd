class_name FloatingLabels
extends RefCounted

## The labels pinned to the world that belong to no character: portal
## captions, and the combat numbers that float off a hit.
##
## Pooled Labels under the overlay's root -- captions by portal id, numbers
## by slot, as the web client's `_damageTextSlots` -- placed on whole screen
## pixels. A number is centred on the hit, fading and shrinking as it goes,
## which is what both references do: alpha from the life left, scale
## 0.8 + 0.4 of it.

const DAMAGE_SIZE := 24
const CAPTION_SIZE := 14

## Interaction types whose floated caption reads differently from the
## capitalized type name. Anything absent falls back to `type.capitalize()`.
const TILE_CAPTIONS := {"display_text": "Read"}

var captions := 0
var texts := 0
var tile_captions := 0

var _captions: ControlPool
var _graves: ControlPool
var _tile_captions: ControlPool
var _numbers: ControlPool


## Screen pixels between a caption and what it names.
const CAPTION_GAP := 4.0

func _init(root: Control) -> void:
	_captions = ControlPool.new(root, func() -> Control: return _label(TagStyles.caption_label()))
	_graves = ControlPool.new(root, func() -> Control: return _label(TagStyles.caption_label()))
	_tile_captions = ControlPool.new(root, func() -> Control: return _label(TagStyles.caption_label()))
	_numbers = ControlPool.new(root, func() -> Control: return _label(TagStyles.damage_label()), true)


## `exact` places the numbers (world point -> screen point, or null behind the
## camera) and `ground` the captions under portals, graves and tiles the same way,
## each in place of to_screen when given (the 2.5D view).
func show_all(state: RealmState, content: GameData, to_screen: Transform2D, view: Rect2,
		exact := Callable(), ground := Callable()) -> void:
	captions = 0
	texts = 0
	tile_captions = 0
	if state != null:
		_show_captions(state, to_screen, view, ground)
		_show_graves(state, content, to_screen, view, ground)
		_show_tile_labels(state, content, to_screen, view, ground)
		_show_numbers(state, to_screen, view, exact)
	_captions.sweep()
	_graves.sweep()
	_tile_captions.sweep()
	_numbers.sweep()


static func number_scale(fade: float) -> float:
	return 0.8 + 0.4 * fade


## What a portal leads to, under it: the realm's name and its badge, and
## for the one you are standing on the web client's whole card, boxed.
## targetLabel is empty on a portal with no realm behind it (the vault, an
## exit), and those get no caption at all.
func _show_captions(state: RealmState, to_screen: Transform2D, view: Rect2, ground: Callable) -> void:
	for id in state.entities.portals:
		var portal: Dictionary = state.entities.portals[id]
		var position := state.entities.render_position(portal)
		var focused := state.local.is_present() and PortalCard.focused(position, state.local.render_centre())
		var caption := PortalCard.card(portal) if focused else PortalCard.caption(portal)
		if caption == "" or not view.has_point(position):
			continue
		var under: Variant = _under(to_screen, ground, position)
		if under == null:
			continue
		var label: Label = _captions.acquire(id)
		# Each of these re-lays the label out when set, so only a change is set.
		if label.text != caption:
			label.text = caption
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var colour := PortalCard.colour(portal)
		if label.label_settings.font_color != colour:
			label.label_settings.font_color = colour
		if focused != label.has_theme_stylebox_override("normal"):
			if focused:
				label.add_theme_stylebox_override("normal", PortalCard.box())
			else:
				label.remove_theme_stylebox_override("normal")
		label.reset_size()
		label.position = Vector2(under.x - label.size.x * 0.5, under.y).round()
		captions += 1


## Under a grave, who fell there; standing on it, the whole card, boxed as a
## portal's is.
func _show_graves(state: RealmState, content: GameData, to_screen: Transform2D, view: Rect2,
		ground: Callable) -> void:
	var now := GraveCard.now_ms()
	for id in state.entities.containers:
		var bag: Dictionary = state.entities.containers[id]
		var grave: Dictionary = bag.get("grave", {})
		if grave.is_empty():
			continue
		var position := state.entities.render_position(bag)
		if not view.has_point(position):
			continue
		var under: Variant = _under(to_screen, ground, position)
		if under == null:
			continue
		var focused := state.local.is_present() and PortalCard.focused(position, state.local.render_centre())
		var text := GraveCard.card(grave, content, now) if focused else GraveCard.caption(grave)
		var label: Label = _graves.acquire(id)
		if label.text != text:
			label.text = text
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if label.label_settings.font_color != GraveCard.COLOUR:
			label.label_settings.font_color = GraveCard.COLOUR
		if focused != label.has_theme_stylebox_override("normal"):
			if focused:
				label.add_theme_stylebox_override("normal", PortalCard.box())
			else:
				label.remove_theme_stylebox_override("normal")
		label.reset_size()
		label.position = Vector2(under.x - label.size.x * 0.5, under.y).round()
		captions += 1


## The caption floated under an interactive tile (its `label`), like a portal's.
## A view-bounded scan each frame; tiles are static so this stays cheap.
func _show_tile_labels(state: RealmState, content: GameData, to_screen: Transform2D,
		view: Rect2, ground: Callable) -> void:
	if content == null or state.tiles == null:
		return
	var size := float(GameConstants.TILE_SIZE)
	var x0 := maxi(0, floori(view.position.x / size))
	var y0 := maxi(0, floori(view.position.y / size))
	var x1 := floori(view.end.x / size)
	var y1 := floori(view.end.y / size)
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			var text := _tile_label(state, content, tx, ty)
			if text == "":
				continue
			var under: Variant = _under(to_screen, ground, Vector2(tx * size, ty * size))
			if under == null:
				continue
			var label: Label = _tile_captions.acquire(ty * 100003 + tx)
			if label.text != text:
				label.text = text
				label.reset_size()
			label.position = Vector2(under.x - label.size.x * 0.5, under.y).round()
			tile_captions += 1


## Where a caption's top-centre goes under the tile-sized thing at world_topleft: its
## bottom edge flat, or in 2.5D just below the ground point its sprite stands on.
## Null when that point is behind the camera.
static func _under(to_screen: Transform2D, ground: Callable, world_topleft: Vector2) -> Variant:
	var tile := float(GameConstants.TILE_SIZE)
	if not ground.is_valid():
		var at := EntityOverlay.screen(to_screen, world_topleft)
		var screen_tile := tile * to_screen.get_scale().x
		return Vector2(at.x + screen_tile * 0.5, at.y + screen_tile + CAPTION_GAP)
	var feet: Variant = ground.call(world_topleft + Vector2(tile, tile) * 0.5)
	if not feet is Vector2:
		return null
	return feet + Vector2(0.0, CAPTION_GAP)


## The `label` of the interactive tile at (tx, ty), collision layer first, or "".
func _tile_label(state: RealmState, content: GameData, tx: int, ty: int) -> String:
	for layer in [GameConstants.COLLISION_LAYER, TileMapState.BASE_LAYER]:
		var definition: Dictionary = content.tiles.get(state.tiles.tile_at(layer, tx, ty), {})
		# Every tile carries `interactionType`, null on all but the interactive few,
		# and str(null) is "<null>" (not ""), so the key must be null-checked.
		var type_value: Variant = definition.get("interactionType")
		if type_value == null:
			continue
		var kind := str(type_value)
		if kind == "":
			continue
		# `label` is often present-but-null (the model serializes the empty field),
		# and str(null) is "<null>", so guard the null before falling back.
		var override: Variant = definition.get("label")
		if override != null and str(override) != "":
			return str(override)
		# "fame_store" -> "Fame Store", "arena" -> "Arena"; overrides win.
		return str(TILE_CAPTIONS.get(kind, kind.capitalize()))
	return ""


func _show_numbers(state: RealmState, to_screen: Transform2D, view: Rect2, exact: Callable) -> void:
	if not state.settings.is_on("show_damage_numbers"):
		return
	for text in state.texts.texts:
		var at := DamageText.render_position(text)
		if not view.has_point(at):
			continue
		var on_screen: Variant = exact.call(at) if exact.is_valid() else EntityOverlay.screen(to_screen, at)
		if not on_screen is Vector2:
			continue
		# Pooled by the number's own id, so a label keeps its text (and its shaped
		# glyphs) for its whole rise rather than taking the next one's as others expire.
		var label: Label = _numbers.acquire(int(text.get("id", 0)))
		var shown: String = text["text"]
		if label.text != shown:
			label.text = shown
			label.reset_size()
		var fade := DamageText.alpha_of(text)
		label.modulate = Color(text["colour"], fade)
		label.pivot_offset = label.size * 0.5
		label.scale = Vector2.ONE * number_scale(fade)
		label.position = (on_screen - label.size * 0.5).round()
		texts += 1


static func _label(style: LabelSettings) -> Label:
	var label := Label.new()
	label.label_settings = style
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
