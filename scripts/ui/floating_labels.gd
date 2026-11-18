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

var captions := 0
var texts := 0
var tile_captions := 0

var _captions: ControlPool
var _tile_captions: ControlPool
var _numbers: ControlPool


func _init(root: Control) -> void:
	_captions = ControlPool.new(root, func() -> Control: return _label(TagStyles.caption_label()))
	_tile_captions = ControlPool.new(root, func() -> Control: return _label(TagStyles.caption_label()))
	_numbers = ControlPool.new(root, func() -> Control: return _label(TagStyles.damage_label()), true)


func show_all(state: RealmState, content: GameData, to_screen: Transform2D, view: Rect2,
		project_3d := false) -> void:
	captions = 0
	texts = 0
	tile_captions = 0
	if state != null:
		_show_captions(state, to_screen, view, project_3d)
		_show_tile_labels(state, content, to_screen, view, project_3d)
		_show_numbers(state, to_screen, view)
	_captions.sweep()
	_tile_captions.sweep()
	_numbers.sweep()


static func number_scale(fade: float) -> float:
	return 0.8 + 0.4 * fade


## What a portal leads to, under it: the realm's name and its badge, and
## for the one you are standing on the web client's whole card, boxed.
## targetLabel is empty on a portal with no realm behind it (the vault, an
## exit), and those get no caption at all.
func _show_captions(state: RealmState, to_screen: Transform2D, view: Rect2, project_3d: bool) -> void:
	var world_tile := float(GameConstants.TILE_SIZE)
	var tile := world_tile * to_screen.get_scale().x
	for id in state.entities.portals:
		var portal: Dictionary = state.entities.portals[id]
		var position := state.entities.render_position(portal)
		var focused := state.local.is_present() and PortalCard.focused(position, state.local.render_centre())
		var caption := PortalCard.card(portal) if focused else PortalCard.caption(portal)
		if caption == "" or not view.has_point(position):
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
		# In 3D the projector rotates, so anchor on the portal's world CENTRE (its
		# billboard) rather than the top-left, which would swing on orbit.
		if project_3d:
			var centre := EntityOverlay.screen(to_screen, position + Vector2(world_tile, world_tile) * 0.5)
			label.position = Vector2(centre.x - label.size.x * 0.5, centre.y + tile * 0.5 + 4.0).round()
		else:
			var at := EntityOverlay.screen(to_screen, position)
			label.position = Vector2(at.x + tile * 0.5 - label.size.x * 0.5, at.y + tile + 4.0).round()
		captions += 1


## The caption floated under an interactive tile (its `label`), like a portal's.
## A view-bounded scan each frame; tiles are static so this stays cheap. Skipped in
## the 3D prototype, where a flat-screen anchor would swing as the projector orbits.
func _show_tile_labels(state: RealmState, content: GameData, to_screen: Transform2D,
		view: Rect2, project_3d: bool) -> void:
	if project_3d or content == null or state.tiles == null:
		return
	var size := float(GameConstants.TILE_SIZE)
	var tile := size * to_screen.get_scale().x
	var x0 := maxi(0, floori(view.position.x / size))
	var y0 := maxi(0, floori(view.position.y / size))
	var x1 := floori(view.end.x / size)
	var y1 := floori(view.end.y / size)
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			var text := _tile_label(state, content, tx, ty)
			if text == "":
				continue
			var label: Label = _tile_captions.acquire(ty * 100003 + tx)
			if label.text != text:
				label.text = text
				label.reset_size()
			var at := EntityOverlay.screen(to_screen, Vector2(tx * size, ty * size))
			label.position = Vector2(at.x + tile * 0.5 - label.size.x * 0.5, at.y + tile + 4.0).round()
			tile_captions += 1


## The `label` of the interactive tile at (tx, ty), collision layer first, or "".
func _tile_label(state: RealmState, content: GameData, tx: int, ty: int) -> String:
	for layer in [GameConstants.COLLISION_LAYER, TileMapState.BASE_LAYER]:
		var definition: Dictionary = content.tiles.get(state.tiles.tile_at(layer, tx, ty), {})
		if str(definition.get("interactionType", "")) == "":
			continue
		var text := str(definition.get("label", ""))
		if text != "":
			return text
	return ""


func _show_numbers(state: RealmState, to_screen: Transform2D, view: Rect2) -> void:
	if not state.settings.is_on("show_damage_numbers"):
		return
	for text in state.texts.texts:
		var at := DamageText.render_position(text)
		if not view.has_point(at):
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
		label.position = (EntityOverlay.screen(to_screen, at) - label.size * 0.5).round()
		texts += 1


static func _label(style: LabelSettings) -> Label:
	var label := Label.new()
	label.label_settings = style
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label
