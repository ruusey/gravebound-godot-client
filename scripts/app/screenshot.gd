class_name Screenshot
extends RefCounted

## The ` key (tilde, top-left): the frame on screen, as a PNG, wherever this build can put one.
##
## On the desktop it is written under user://screenshots and the path
## printed; a browser has no filesystem the player can reach, so there the
## bytes go out as a download through the page. Both take the viewport as
## drawn -- the world, every panel and the overlay -- which is what a report
## of "it looks wrong" needs to show.

const FOLDER := "user://screenshots"


## Returns where the image went, or "" when there was nothing to take -- the
## texture reads back null headless.
static func take(viewport: Viewport, on_web := OS.has_feature("web"),
		download: Callable = Callable()) -> String:
	var image: Image = viewport.get_texture().get_image()
	if image == null:
		return ""
	# 2026-09-22_16-27-04: no colon, which a filesystem may refuse, and no
	# space, which a download prompt would mangle.
	var name := "gravebound-%s.png" % Time.get_datetime_string_from_system(false, false) \
		.replace(":", "-").replace("T", "_")
	if on_web:
		var sender: Callable = download if download.is_valid() \
			else JavaScriptBridge.download_buffer
		sender.call(image.save_png_to_buffer(), name, "image/png")
		return name
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(FOLDER))
	var path := "%s/%s" % [FOLDER, name]
	if image.save_png(path) != OK:
		return ""
	return ProjectSettings.globalize_path(path)
