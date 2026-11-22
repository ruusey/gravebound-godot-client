extends GutTest

## Every content file asked for at once, then answered from memory.

## A source that answers nothing until told to, so the order of asking and
## the order of answering can both be seen.
class LatchedSource extends ContentSource:
	signal answered(key: String)
	var asked: Array = []
	var bodies := {}

	func read(name: String) -> Array:
		asked.append(name)
		while true:
			var key: String = await answered
			if key == name:
				break
		return [OK, bodies[name]] if bodies.has(name) else [ERR_FILE_NOT_FOUND, PackedByteArray()]

	func answer(key: String) -> void:
		answered.emit(key)


func test_every_file_is_asked_for_before_any_is_answered():
	var inner := LatchedSource.new()
	inner.bodies = {"a.json": "[1]".to_utf8_buffer(), "b.json": "[2]".to_utf8_buffer()}
	var source := PrefetchingContentSource.new(inner)
	var done: Array = []
	Callable(self, "_prefetch").call(source, ["a.json", "b.json", "gone.json"], done)
	assert_eq(inner.asked, ["a.json", "b.json", "gone.json"], "all three in flight at once")
	assert_true(done.is_empty(), "the prefetch is still waiting")

	inner.answer("b.json")
	inner.answer("gone.json")
	inner.answer("a.json")
	await wait_process_frames(1)
	assert_false(done.is_empty(), "the prefetch returned once the last landed")

	var a: Array = await source.read("a.json")
	assert_eq(a[0], OK)
	assert_eq(PackedByteArray(a[1]).get_string_from_utf8(), "[1]")
	var gone: Array = await source.read("gone.json")
	assert_eq(gone[0], ERR_FILE_NOT_FOUND, "a failed read is answered as it failed")
	assert_eq(inner.asked.size(), 3, "answered from memory, not read again")


func test_a_read_during_the_prefetch_waits_for_its_file():
	var inner := LatchedSource.new()
	inner.bodies = {"a.json": "[1]".to_utf8_buffer()}
	var source := PrefetchingContentSource.new(inner)
	Callable(self, "_prefetch").call(source, ["a.json"], [])
	var got: Array = []
	Callable(self, "_read_into").call(source, "a.json", got)
	assert_true(got.is_empty())
	inner.answer("a.json")
	await wait_process_frames(1)
	assert_eq(got.size(), 1)
	assert_eq(got[0][0], OK)
	assert_eq(inner.asked, ["a.json"])


func test_a_name_not_prefetched_passes_through():
	var inner := LatchedSource.new()
	inner.bodies = {"late.json": "{}".to_utf8_buffer()}
	var source := PrefetchingContentSource.new(inner)
	var got: Array = []
	Callable(self, "_read_into").call(source, "late.json", got)
	assert_eq(inner.asked, ["late.json"])
	inner.answer("late.json")
	await wait_process_frames(1)
	assert_eq(got[0][0], OK)


func test_off_disk_the_prefetch_finishes_inside_the_call():
	var source := PrefetchingContentSource.new(
		FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	var done: Array = []
	Callable(self, "_prefetch").call(source, ["tiles.json"], done)
	assert_false(done.is_empty())


func test_content_still_loads_through_it():
	var content := ContentLibrary.new()
	var loaded: bool = await content.load_from(
		FileContentSource.new(ProjectSettings.globalize_path("res://tests/fixtures/datadir")))
	assert_true(loaded, "\n".join(content.errors))
	assert_gt(content.tiles.size(), 0)


func _prefetch(source: PrefetchingContentSource, names: Array, done: Array) -> void:
	await source.prefetch(names)
	done.append(true)


func _read_into(source: ContentSource, name: String, got: Array) -> void:
	got.append(await source.read(name))
