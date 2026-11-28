extends GutTest

## Interactive tiles' captions: indexed as the tiles arrive, collision layer first,
## and floated only for the captioned cells in view.

var content: GameData
var state: RealmState


func before_each():
	content = GameData.new()
	await content.load_from(FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	state = RealmState.new(content, func() -> int: return 0)


func _tile(tile_id: int, x: int, y: int, layer := 1) -> void:
	state.apply_packet("LoadMapPacket", {"realmId": 1, "tiles": [WireHelper.tile(tile_id, layer, x, y)]})


func test_a_caption_is_the_interaction_types_name_unless_labelled():
	assert_eq(content.tile_caption(301), "Fame Store")
	assert_eq(content.tile_caption(1), "", "a null interactionType is no caption")
	assert_eq(content.tile_caption(-1), "")


func test_only_captioned_cells_are_indexed():
	_tile(1, 4, 4, 0)
	_tile(300, 5, 5)
	_tile(301, 7, 5, 0)
	assert_eq(state.tiles.captions, {Vector2i(5, 5): "Forge", Vector2i(7, 5): "Fame Store"})


func test_the_collision_layer_wins_and_the_ground_shows_once_it_goes():
	_tile(301, 5, 5, 0)
	_tile(300, 5, 5)
	assert_eq(state.tiles.captions[Vector2i(5, 5)], "Forge")
	_tile(0, 5, 5)
	assert_eq(state.tiles.captions[Vector2i(5, 5)], "Fame Store")
	_tile(1, 5, 5, 0)
	assert_false(state.tiles.captions.has(Vector2i(5, 5)))


func test_a_new_map_drops_the_captions():
	_tile(300, 5, 5)
	state.apply_packet("LoadMapPacket", {"realmId": 2, "tiles": [WireHelper.tile(1, 0, 5, 5)]})
	assert_true(state.tiles.captions.is_empty())


func test_only_captions_in_view_are_floated():
	_tile(300, 5, 5)
	_tile(301, 40, 5, 0)
	var root := Control.new()
	add_child_autofree(root)
	var labels := FloatingLabels.new(root)
	labels.show_all(state, content, Transform2D.IDENTITY, Rect2(0, 0, 640, 360))
	assert_eq(labels.tile_captions, 1)
