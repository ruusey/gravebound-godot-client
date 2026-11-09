extends GutTest

## Where content is read from. The desktop reads the data repo off disk; a
## browser has no filesystem and must fetch the same files from the data
## service. Both have to resolve a name to the same bytes.

const FIXTURE := "res://tests/fixtures/datadir"


func _root() -> String:
	return ProjectSettings.globalize_path(FIXTURE)


# --- disk -------------------------------------------------------------------

func test_json_is_found_under_the_data_directory():
	var source := FileContentSource.new(_root())
	var result: Array = await source.read("tiles.json")
	assert_eq(result[0], OK)
	assert_gt(result[1].size(), 0)


func test_a_sheet_is_found_under_entity():
	var source := FileContentSource.new(_root())
	assert_eq((await source.read("atlas.png"))[0], OK)


func test_a_sheet_key_carrying_a_directory_is_reduced_to_its_filename():
	# Content writes both "atlas.png" and "entity/atlas.png" for the same
	# sheet. The namespace is flat, so both have to resolve.
	var source := FileContentSource.new(_root())
	assert_eq((await source.read("entity/atlas.png"))[0], OK)


func test_something_that_is_not_there_is_reported():
	var source := FileContentSource.new(_root())
	assert_eq((await source.read("nope.json"))[0], ERR_FILE_NOT_FOUND)


func test_a_missing_checkout_is_named_once():
	# Rather than as an identical missing-file error for every content file.
	var source := FileContentSource.new("/no/such/place")
	assert_string_contains(source.unavailable(), "data root not found")


func test_a_real_checkout_is_usable():
	assert_eq(FileContentSource.new(_root()).unavailable(), "")
	assert_eq(FileContentSource.new(_root()).describe(), _root())


# --- http -------------------------------------------------------------------

func test_the_endpoint_is_one_flat_level():
	# /game-data/*.png is a one-level matcher on the service; a nested path
	# falls through to the catch-all and 404s.
	var source := HttpContentSource.new("http://d:8080", FakeHttpBackend.new())
	assert_eq(source.url_for("entity/atlas.png"), "http://d:8080/game-data/atlas.png")
	assert_eq(source.url_for("tiles.json"), "http://d:8080/game-data/tiles.json")


func test_a_fetched_file_comes_back_as_bytes():
	var backend := FakeHttpBackend.new()
	backend.push_raw(HTTPRequest.RESULT_SUCCESS, 200, "[]")
	var source := HttpContentSource.new("http://d:8080", backend)
	var result: Array = await source.read("tiles.json")
	assert_eq(result[0], OK)
	assert_eq(PackedByteArray(result[1]).get_string_from_utf8(), "[]")
	assert_eq(backend.requests[0]["url"], "http://d:8080/game-data/tiles.json")


func test_content_is_fetched_without_a_token():
	# It has to load before anyone has logged in, so the endpoint is public and
	# sending an Authorization header would be wrong as well as useless.
	var backend := FakeHttpBackend.new()
	backend.push_raw(HTTPRequest.RESULT_SUCCESS, 200, "[]")
	await HttpContentSource.new("http://d:8080", backend).read("tiles.json")
	assert_eq(backend.requests[0]["headers"], PackedStringArray())


func test_a_missing_file_is_reported():
	var backend := FakeHttpBackend.new()
	backend.push_raw(HTTPRequest.RESULT_SUCCESS, 404, "")
	var source := HttpContentSource.new("http://d:8080", backend)
	assert_eq((await source.read("gone.json"))[0], ERR_FILE_NOT_FOUND)


func test_a_service_that_is_not_up_is_reported():
	var backend := FakeHttpBackend.new()
	backend.push_raw(HTTPRequest.RESULT_CANT_CONNECT, 0, "")
	var source := HttpContentSource.new("http://d:8080", backend)
	assert_eq((await source.read("tiles.json"))[0], ERR_CANT_CONNECT)


func test_a_source_with_no_backend_fails_rather_than_crashing():
	assert_eq((await HttpContentSource.new("http://d:8080").read("tiles.json"))[0],
		ERR_UNAVAILABLE)


func test_http_describes_its_endpoint():
	assert_eq(HttpContentSource.new("http://d:8080").describe(), "http://d:8080/game-data/")


func test_the_base_source_reads_nothing():
	assert_eq((await ContentSource.new().read("tiles.json"))[0], ERR_UNAVAILABLE)
	assert_eq(ContentSource.new().unavailable(), "")
	assert_eq(ContentSource.new().describe(), "nowhere")


# --- the same content, through the service ----------------------------------

func test_the_whole_content_set_loads_over_http():
	# The browser's path, end to end: every JSON file and every sheet the
	# content names, served the way the data service serves them. Proves the
	# two sources are interchangeable rather than merely similar.
	var disk := FileContentSource.new(_root())
	var backend := _serving(disk)
	var data := GameData.new()

	assert_true(await data.load_from(HttpContentSource.new("http://d:8080", backend)))
	assert_eq(data.tiles.size(), 12)
	assert_eq(data.enemies.size(), 2)
	assert_not_null(data.tile_texture(1), "a sheet fetched over HTTP is usable art")
	assert_eq(data.tile_texture(1).region, Rect2(24, 16, 8, 8))


func test_content_over_http_asks_for_each_sheet_once():
	var disk := FileContentSource.new(_root())
	var backend := _serving(disk)
	var data := GameData.new()
	await data.load_from(HttpContentSource.new("http://d:8080", backend))

	var sheets := {}
	for request in backend.requests:
		var name: String = String(request["url"]).get_file()
		if name.ends_with(".png"):
			sheets[name] = int(sheets.get(name, 0)) + 1
	assert_gt(sheets.size(), 0, "sheets were fetched at all")
	for name in sheets:
		assert_eq(sheets[name], 1, "%s was fetched more than once" % name)


## A backend that answers every request from the fixture directory, the way
## the data service answers from its own.
func _serving(disk: FileContentSource) -> FakeHttpBackend:
	var backend := ServingHttpBackend.new()
	backend.disk = disk
	return backend


class ServingHttpBackend extends FakeHttpBackend:
	var disk: FileContentSource

	func perform(method: int, url: String, headers: PackedStringArray, body: String) -> Array:
		requests.append({"method": method, "url": url, "headers": headers, "body": body})
		var result: Array = await disk.read(String(url).get_file())
		if result[0] != OK:
			return [HTTPRequest.RESULT_SUCCESS, 404, PackedByteArray()]
		return [HTTPRequest.RESULT_SUCCESS, 200, result[1]]


# --- preloading -------------------------------------------------------------

func test_bytes_that_are_not_an_image_are_reported_not_accepted():
	# A service can answer 200 with an error page. Handing those bytes to a
	# draw call would be worse than having no sheet at all.
	var cache := SpriteCache.new()
	await cache.preload_sheets(CannedSource.new("<html>not a png</html>"), ["broken.png"])
	assert_null(cache.texture("broken.png"))
	assert_eq(cache.errors, ["sprite sheet not found: broken.png"])


func test_a_sheet_already_held_is_not_read_again():
	var source := CountingSource.new()
	source.disk = FileContentSource.new(_root())
	var cache := SpriteCache.new()
	await cache.preload_sheets(source, ["atlas.png", "atlas.png"])
	await cache.preload_sheets(source, ["atlas.png"])
	assert_eq(source.reads, 1, "named three times, fetched once")


func test_an_empty_sheet_key_is_skipped():
	var source := CountingSource.new()
	source.disk = FileContentSource.new(_root())
	var cache := SpriteCache.new()
	await cache.preload_sheets(source, ["", "atlas.png"])
	assert_eq(source.reads, 1, "the blank is not requested")
	assert_eq(cache.errors, [] as Array[String], "nor reported as missing")


class CannedSource extends ContentSource:
	var body := ""

	func _init(text: String) -> void:
		body = text

	func read(_name: String) -> Array:
		return [OK, body.to_utf8_buffer()]


class CountingSource extends ContentSource:
	var disk: FileContentSource
	var reads := 0

	func read(name: String) -> Array:
		reads += 1
		return await disk.read(name)


# --- known content gaps -----------------------------------------------------

func after_each():
	ContentGaps.sheets = ContentGaps.MISSING_SHEETS.duplicate()


func test_a_known_gap_is_not_reported_every_launch():
	# The client cannot fix a sheet gravebound-data never shipped; it can only
	# decide whether to warn about it on every start. It still resolves to
	# nothing, so the sprite draws as a fallback block either way.
	ContentGaps.sheets = {"gap.png": "enemy 999 (Test) placeholder; sheet never shipped"}
	var cache := SpriteCache.new()
	await cache.preload_sheets(FileContentSource.new(_root()), ["gap.png"])
	assert_null(cache.texture("gap.png"), "still unresolved")
	assert_eq(cache.errors, [] as Array[String], "but not news")


func test_an_unlisted_gap_is_still_reported():
	# Otherwise the list becomes a way to stop noticing new breakage.
	var cache := SpriteCache.new()
	await cache.preload_sheets(FileContentSource.new(_root()), ["not-listed.png"])
	assert_eq(cache.errors, ["sprite sheet not found: not-listed.png"])


func test_every_gap_carries_its_reason():
	# Removing an entry later should not require re-deriving why it is there.
	assert_true(ContentGaps.MISSING_SHEETS.values().all(
		func(why: Variant) -> bool: return String(why).length() > 20), "an entry with no reason")


func test_an_entry_nothing_needs_any_more_is_stale():
	ContentGaps.sheets = {"gone.png": "was enemy 1's", "fixed.png": "was enemy 2's",
		"still.png": "enemy 3's, still missing"}
	var stale := ContentGaps.stale(["fixed.png", "still.png"],
		func(key: String) -> bool: return key == "fixed.png")
	assert_eq(stale, PackedStringArray([
		"gone.png is listed in ContentGaps but nothing names it any more -- remove it",
		"fixed.png is listed in ContentGaps but now resolves -- remove it"]))


func test_anything_else_is_unknown():
	assert_false(ContentGaps.is_known("realm-misc.png"))
	assert_eq(ContentGaps.reason("realm-misc.png"), "")
