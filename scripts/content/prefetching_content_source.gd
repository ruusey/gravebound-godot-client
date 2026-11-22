class_name PrefetchingContentSource
extends ContentSource

## Reads a known set of files all at once, then answers from what landed.
##
## ContentLibrary reads its JSON one file after another, each read awaited
## before the next starts. Over HTTP that is one round trip per file back to
## back before the login screen; prefetching first makes the cost the slowest
## file instead of the sum, without the library's reads changing shape. A
## name that was not prefetched passes through to the wrapped source.

signal landed

var _inner: ContentSource
var _results := {}   # name -> [Error, PackedByteArray] once landed
var _in_flight := 0


func _init(inner: ContentSource) -> void:
	_inner = inner


func prefetch(names: Array) -> void:
	for name in names:
		if _results.has(name):
			continue
		_results[name] = []
		_in_flight += 1
		# Started, not awaited -- see SheetPreloader.run.
		Callable(self, "_fetch").call(name)
	while _in_flight > 0:
		await landed


func read(name: String) -> Array:
	if _results.has(name):
		while _results[name].is_empty():
			await landed
		return _results[name]
	return await _inner.read(name)


func unavailable() -> String:
	return _inner.unavailable()


func describe() -> String:
	return _inner.describe()


func _fetch(name: String) -> void:
	_results[name] = await _inner.read(name)
	_in_flight -= 1
	landed.emit()
