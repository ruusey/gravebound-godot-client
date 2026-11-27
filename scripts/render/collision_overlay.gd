class_name CollisionOverlay
extends Node2D

## The collision debug view: every solid cell in the camera's view, tinted, and
## the hit body of every player, enemy and projectile as the server tests it.
## Two outlines touching is a hit: bodies are circles of size * HIT_RADIUS_FACTOR
## about their centres, a LINE_SEGMENT wall is a capsule along its length, and a
## melee swing is a cone of its range (RealmManagerServer circleHit, lineHit and
## coneHit).
##
## Its own layer, last in the world, rather than drawn with the tiles: the
## wall tops are stamped above the tile layer, so anything drawn down there
## is hidden by them. F2 toggles it.

const PLAYER_COLOUR := Color(0.3, 1.0, 0.4)
const ENEMY_COLOUR := Color(1.0, 0.55, 0.1)
const PLAYER_SHOT_COLOUR := Color(0.3, 0.8, 1.0)
const ENEMY_SHOT_COLOUR := Color(1.0, 0.3, 0.9)
const LINE_WIDTH := 1.0
const SEGMENTS := 24
## The server's GlobalConstants.MELEE_CONE_HALF_ANGLE.
const MELEE_CONE_HALF_ANGLE := 0.6

var state: RealmState
var content: GameData
var show_collision := false


func _draw() -> void:
	if not show_collision or state == null or content == null:
		return
	var view := ViewRect.of(self)
	var size := GameConstants.TILE_SIZE
	var cells: Dictionary = state.tiles.layers.get(GameConstants.COLLISION_LAYER, {})
	var first := Vector2i(floori(view.position.x / size), floori(view.position.y / size))
	var last := Vector2i(ceili(view.end.x / size), ceili(view.end.y / size))
	for x in range(first.x, last.x + 1):
		for y in range(first.y, last.y + 1):
			var tile_id: int = cells.get(Vector2i(x, y), -1)
			if tile_id >= 0 and content.tile_has_collision(tile_id):
				draw_rect(Rect2(x * size, y * size, size, size), Color(1, 0, 0, 0.25), true)
	_draw_bodies(view)
	_draw_shots(view)


func _draw_bodies(view: Rect2) -> void:
	for id in state.entities.players:
		var player: Dictionary = state.entities.players[id]
		var is_local: bool = id == state.local.id
		var position: Vector2 = state.local.render_position() if is_local 			else state.entities.render_position(player)
		var body: float = float(state.local.size) if is_local 			else float(player.get("size", GameConstants.PLAYER_SIZE))
		_circle(view, position, body, PLAYER_COLOUR)
	for id in state.entities.enemies:
		var enemy: Dictionary = state.entities.enemies[id]
		_circle(view, state.entities.render_position(enemy),
			float(enemy.get("size", EntityQueue.SIMPLE_SIZE)), ENEMY_COLOUR)


func _draw_shots(view: Rect2) -> void:
	var visibility := BulletVisibility.of(state)
	for bullet: Projectile in state.projectiles.bullets.values():
		if visibility.hides(bullet):
			continue
		var colour := PLAYER_SHOT_COLOUR if state.entities.players.has(bullet.src_entity_id) 			else ENEMY_SHOT_COLOUR
		var half := bullet.size * 0.5
		var centre := bullet.pos + Vector2(half, half)
		var radius := bullet.size * ProjectileSystem.HIT_RADIUS_FACTOR
		if ProjectileKind.has_flag(bullet, ProjectileKind.MELEE_SWING):
			if view.grow(bullet.range).has_point(centre):
				_cone(centre, bullet.angle, bullet.range, colour)
		elif ProjectileKind.has_flag(bullet, ProjectileKind.LINE_SEGMENT) and bullet.length > 0.0:
			if view.grow(bullet.length).has_point(centre):
				var axis := Vector2(cos(bullet.angle), -sin(bullet.angle)) * bullet.length * 0.5
				_capsule(centre - axis, centre + axis, radius, colour)
		elif view.grow(radius).has_point(centre):
			draw_arc(centre, radius, 0.0, TAU, SEGMENTS, colour, LINE_WIDTH)


## A body whose top-left is `position`: its hit circle and a dot at its centre.
func _circle(view: Rect2, position: Vector2, size: float, colour: Color) -> void:
	var centre := position + Vector2(size, size) * 0.5
	var radius := size * ProjectileSystem.HIT_RADIUS_FACTOR
	if not view.grow(radius).has_point(centre):
		return
	draw_arc(centre, radius, 0.0, TAU, SEGMENTS, colour, LINE_WIDTH)
	draw_circle(centre, 1.0, colour)


func _capsule(from: Vector2, to: Vector2, radius: float, colour: Color) -> void:
	var side := (to - from).orthogonal().normalized() * radius
	draw_line(from + side, to + side, colour, LINE_WIDTH)
	draw_line(from - side, to - side, colour, LINE_WIDTH)
	draw_arc(from, radius, 0.0, TAU, SEGMENTS, colour, LINE_WIDTH)
	draw_arc(to, radius, 0.0, TAU, SEGMENTS, colour, LINE_WIDTH)


## The swing's facing is (sin, cos) of its angle, as the server reads it.
func _cone(apex: Vector2, angle: float, reach: float, colour: Color) -> void:
	var facing := atan2(cos(angle), sin(angle))
	var points := PackedVector2Array([apex])
	for i in SEGMENTS + 1:
		var turn := facing - MELEE_CONE_HALF_ANGLE + 2.0 * MELEE_CONE_HALF_ANGLE * float(i) / SEGMENTS
		points.append(apex + Vector2(cos(turn), sin(turn)) * reach)
	points.append(apex)
	draw_polyline(points, colour, LINE_WIDTH)
