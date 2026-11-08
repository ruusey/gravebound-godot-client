class_name EntityOverlay
extends CanvasLayer

## The UI pinned to the world: every character's tag (name, bars, chips,
## bubble), the portal captions, the combat numbers, the grid of what each
## loot bag holds (LootPreviews), and the dark around a blinded player
## (BlindVignette).
##
## Godot Controls, not draw calls, because they are UI -- the house rule --
## and because a Label keeps its shaped text and only moves, where a string
## redrawn inside the zoomed world was re-laid out at a new fraction of a
## pixel every frame and wobbled. Kept on a CanvasLayer of its own outside
## the camera, exactly the web client's `uiLayer`, so the text is its own
## size at the web client's sizes. Every anchor is a world position pushed
## through the camera's transform and rounded -- `worldToScreen` and
## `Math.round` -- and the Controls are pooled by entity, acquired each
## frame and freed when nothing acquired them, as the web client pools its
## PIXI.Text.

const LOCAL_NAME := Color(0.6, 1.0, 0.6)
const NO_EFFECTS: Array = []
const NO_BUBBLE := {}

var state: RealmState
var content: GameData
## What the last frame showed, after culling.
var chips := 0
var bubbles := 0
var previews: int:
	get: return _loot.shown
var captions: int:
	get: return _labels.captions
var texts: int:
	get: return _labels.texts

var _root: Control
## Players and enemies pool separately, each keyed by the raw entity id, so an
## acquire is a plain int hash with no per-entity ["kind", id] Array built and
## deep-hashed every frame for every visible character.
var _player_tags: ControlPool
var _enemy_tags: ControlPool
var _bars: EnemyBars
var _labels: FloatingLabels
var _loot: LootPreviews
var _vignette: BlindVignette
var _melee: MeleeReticle
## Supplies the aim point (mouse's world position): the 3D ground raycast, or the
## 2D camera's global mouse. Returns a Vector2, or anything else for "no aim".
## Wired by Main; only the melee reticle reads it.
var world_aim: Callable = func() -> Variant: return null

## The 3D view drives these: with project_3d on, the overlay places its tags
## through world_projector (an affine world->screen fit to the 3D camera at the
## player) and culls to world_view, instead of the 2D camera's own transform.
## So names, bars, damage numbers, bubbles and loot pin to the 3D bodies without
## any of it being re-drawn for 3D.
var project_3d := false
var world_projector := Transform2D()
var world_view := Rect2()


func setup(realm_state: RealmState, game_data: GameData = null) -> void:
	state = realm_state
	content = game_data


func _ready() -> void:
	layer = 1
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	# Under every tag, as each tag's own bar was under its name and chips.
	_bars = EnemyBars.new()
	_root.add_child(_bars)
	_player_tags = ControlPool.new(_root, func() -> Control: return EntityTag.new())
	_enemy_tags = ControlPool.new(_root, func() -> Control: return EntityTag.new())
	_labels = FloatingLabels.new(_root)
	_melee = MeleeReticle.new()
	_root.add_child(_melee)
	# Over the names and numbers, under the dark: where the web keeps it.
	var loot_root := Control.new()
	loot_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	loot_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(loot_root)
	_loot = LootPreviews.new(loot_root)
	# Last, so it darkens the names and bars too, as the web's tops its uiLayer.
	_vignette = BlindVignette.new()
	add_child(_vignette)


func _process(_delta: float) -> void:
	refresh()


## Split out so a test can drive a frame without waiting for one.
func refresh() -> void:
	chips = 0
	bubbles = 0
	var to_screen := world_projector if project_3d else get_viewport().get_canvas_transform()
	var view := world_view if project_3d else ViewRect.of(_root)
	_bars.begin()
	if state != null:
		_show_players(to_screen, view)
		_show_enemies(to_screen, view)
	_player_tags.sweep()
	_enemy_tags.sweep()
	_bars.finish()
	_melee.place(state, content, to_screen, world_aim.call())
	_labels.show_all(state, to_screen, view, project_3d)
	_loot.show_all(state, content, to_screen, _root.size)
	_vignette.follow(state, to_screen, _root.size)


## A world point on the pixel it lands on. `snap` off keeps the sub-pixel screen
## point, so a tag can glide with a body drawn sub-pixel (remote players).
static func screen(to_screen: Transform2D, world: Vector2, snap := true) -> Vector2:
	var at := to_screen * world
	return at.round() if snap else at


## The top-left screen point to hand a size×size tag so it centres on the entity.
## In 2D the world top-left projects straight through (the transform is axis
## aligned). In 3D the projector rotates, so a top-left anchor swings the tag
## around the body as the view orbits -- instead project the entity's world CENTRE
## (where the billboard sits) and back off half the tag's screen size.
## `snap` off (remote players) keeps the tag on the body's sub-pixel position so the
## two glide together instead of the tag stair-stepping over a smoothly-moving body.
func _anchor(to_screen: Transform2D, world_topleft: Vector2, world_size: float,
		screen_size: float, snap := true) -> Vector2:
	if not project_3d:
		return screen(to_screen, world_topleft, snap)
	var centre := world_topleft + Vector2(world_size, world_size) * 0.5
	var anchored := screen(to_screen, centre, snap) - Vector2(screen_size, screen_size) * 0.5
	return anchored.round() if snap else anchored


func tag_count() -> int:
	return _player_tags.size() + _enemy_tags.size()


## Hurt enemies' health bars drawn last frame.
func bar_count() -> int:
	return _bars.count()


func _show_players(to_screen: Transform2D, view: Rect2) -> void:
	var scale := to_screen.get_scale().x
	var local := state.local
	var on: GameSettings = state.settings
	# Settings read once a frame, not once a player.
	var others_on := on.is_on("show_other_players")
	var chips_on := on.is_on("show_status_chips")
	var names_on := on.is_on("show_names")
	var bubbles_on := on.is_on("show_chat_bubbles")
	for id in state.entities.players:
		var player: Dictionary = state.entities.players[id]
		var is_local: bool = id == local.id
		if not is_local and not others_on:
			continue
		var position: Vector2 = local.render_position() if is_local \
			else state.entities.render_position(player)
		if not is_local and not view.has_point(position):
			continue
		var label: String = player.get("name", "")
		if is_local and label == "":
			label = local.name
		# Scale the tag to the player's body (/size), matching EntityQueue's render
		# size, so the name/bars stay pinned below a resized player.
		var body_size: float = local.size if is_local else float(player.get("size", GameConstants.PLAYER_SIZE))
		var render_world := float(GameConstants.PLAYER_RENDER_SIZE) * (body_size / float(GameConstants.PLAYER_SIZE))
		var size := render_world * scale
		var tag: EntityTag = _player_tags.acquire(id)
		# Local player's tag stays snapped (crisp, camera-aligned); a remote player's
		# glides sub-pixel with its body so the two don't drift apart at low speed.
		tag.show_player(_anchor(to_screen, position, render_world, size, is_local),
			size, label if names_on else "",
			NameColours.over_head(String(player.get("chat_role", "")), is_local, LOCAL_NAME),
			local.health if is_local else int(player.get("health", 0)),
			int(local.stats.get("hp", 0)) if is_local else int(player.get("max_health", 0)),
			local.mana if is_local else int(player.get("mana", 0)),
			int(local.stats.get("mp", 0)) if is_local else int(player.get("max_mana", 0)),
			(local.effects if is_local else player.get("effects", [])) if chips_on else [],
			(local.effect_stacks if is_local else player.get("effect_stacks", [])) if chips_on else [],
			state.bubbles.over(label) if bubbles_on else NO_BUBBLE, int(player.get("stars", 0)))
		chips += tag.chip_count()
		if tag.has_bubble():
			bubbles += 1


func _show_enemies(to_screen: Transform2D, view: Rect2) -> void:
	var zoom := to_screen.get_scale().x
	var chips_on := state.settings.is_on("show_status_chips")
	var blind := Blind.active(state)
	for id in state.entities.enemies:
		var enemy: Dictionary = state.entities.enemies[id]
		var position := state.entities.render_position(enemy)
		if not view.has_point(position) or (blind and Blind.hides(state, position, float(enemy.get("size", 16)))):
			continue
		var maximum: int = maxi(enemy.get("max_health", 1), 1)
		var health: int = enemy.get("health", maximum)
		var effects: Array = enemy.get("effects", NO_EFFECTS) if chips_on else NO_EFFECTS
		if health >= maximum and effects.is_empty():
			continue
		var enemy_size := float(enemy.get("size", 16))
		var width := enemy_size * zoom
		var at := _anchor(to_screen, position, enemy_size, width)
		# The bar is the wound, not the creature: only a hurt enemy has one.
		if health < maximum:
			_bars.add(at, width, EntityTag.fraction(health, maximum))
		# A tag only for the chips; it draws no bar of its own (full health passed).
		if not effects.is_empty():
			var tag: EntityTag = _enemy_tags.acquire(id)
			tag.show_enemy(at, width, maximum, maximum, effects, enemy.get("effect_stacks", NO_EFFECTS))
			chips += tag.chip_count()
