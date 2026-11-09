class_name FileContentSource
extends ContentSource

## Content read from the data repo on disk.
##
## The default for a desktop build: gravebound-data is a separate repo checked
## out beside this one, so working on the client needs no service running.

## Searched in order. JSON lives under data/, sprite sheets under entity/ or
## ui/, sound effects under audio/, with a few at the root. These are the same
## locations the data service serves /game-data from, which is what makes the
## two sources interchangeable.
const SUBDIRECTORIES := ["data", "entity", "ui", "audio", ""]

var root := ""


func _init(content_root := "") -> void:
	root = content_root


func read(name: String) -> Array:
	# A sheet key may carry a directory of its own ("entity/atlas.png"), but
	# the namespace is flat, so only the filename is looked up -- exactly as
	# the HTTP endpoint treats it.
	var file := name.get_file()
	for subdirectory in SUBDIRECTORIES:
		var path := root.path_join(subdirectory).path_join(file) if subdirectory != "" \
			else root.path_join(file)
		if FileAccess.file_exists(path):
			return [OK, FileAccess.get_file_as_bytes(path)]
	return [ERR_FILE_NOT_FOUND, PackedByteArray()]


## A mistyped or missing checkout is worth saying once, rather than as seven
## identical missing-file errors.
func unavailable() -> String:
	if DirAccess.dir_exists_absolute(root):
		return ""
	return "data root not found: %s" % root


func describe() -> String:
	return root
