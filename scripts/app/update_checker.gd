class_name UpdateChecker
extends Node

## Desktop auto-updater, mirroring the native client's UpdateChecker.
##
## On launch (desktop only) it asks GitHub for the latest release; if that tag is
## newer than this build's application/config/version, updating is MANDATORY: the
## player is locked behind a modal they cannot dismiss into the game, offering an
## in-place auto-update (download this platform's zip, swap the running binary via a
## detached helper, relaunch) and a browser button to the releases page.
##
## The lock only fires when GitHub is reached AND the build is genuinely behind, so
## an offline launch, a parse failure, a dev build or the web client all fail OPEN
## and start normally. A client left open past a release is caught at its next
## login instead: the server refuses it and require_update() locks it here.

const OWNER := "ruusey"
const REPO := "gravebound-godot-client"
const LATEST_URL := "https://api.github.com/repos/%s/%s/releases/latest" % [OWNER, REPO]
## Where the "Open download page" button sends the player.
const RELEASES_PAGE := "https://github.com/%s/%s/releases/latest" % [OWNER, REPO]
const USER_AGENT := "GraveBound-Godot-Client"

var _http: HTTPRequest
var _download: HTTPRequest
var _dialog: AcceptDialog
var _progress: AcceptDialog
var _latest := {}
## True while the mandatory lock is up, so closing its window just re-opens it.
var _locked := false


## Kick off the check. Safe to call unconditionally -- it self-gates on web/dev.
func check() -> void:
	if OS.has_feature("web"):
		return
	var current := String(ProjectSettings.get_setting("application/config/version", ""))
	if current.is_empty() or current == "dev":
		print("[UPDATE] dev build (version=%s), skipping check" % current)
		return
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_latest)
	var err := _http.request(LATEST_URL,
		["User-Agent: " + USER_AGENT, "Accept: application/vnd.github+json"])
	if err != OK:
		print("[UPDATE] release request failed to start: %d" % err)


## The server refused our login as out of date. The web build updates by
## reloading the page (every /play file is served no-cache, so the reload is the
## new build); a desktop build runs the release check, which locks on finding it.
func require_update(reason: String) -> void:
	if _locked:
		return
	if not OS.has_feature("web"):
		check()
		return
	_dialog = AcceptDialog.new()
	_dialog.title = "Update required"
	_dialog.dialog_text = "%s\n\nReload to get the new version." % reason
	_dialog.exclusive = true
	_dialog.unresizable = true
	_dialog.dialog_close_on_escape = false
	_dialog.get_ok_button().text = "Reload"
	_dialog.confirmed.connect(func() -> void: JavaScriptBridge.eval("window.location.reload()"))
	# There is nothing to go back to: closing it just shows it again.
	_dialog.close_requested.connect(func() -> void: _dialog.popup_centered(Vector2i(480, 220)))
	_locked = true
	get_tree().root.add_child(_dialog)
	_dialog.popup_centered(Vector2i(480, 220))


func _on_latest(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if _http != null:
		_http.queue_free()
		_http = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		print("[UPDATE] latest-release check failed (result=%d http=%d)" % [result, code])
		return
	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not (json.data is Dictionary):
		print("[UPDATE] could not parse release JSON")
		return
	var release: Dictionary = json.data
	var tag := String(release.get("tag_name", ""))
	var latest_ver := _strip_v(tag)
	var current := _strip_v(String(ProjectSettings.get_setting("application/config/version", "")))
	if _compare(latest_ver, current) <= 0:
		print("[UPDATE] already on latest (current=%s latest=%s)" % [current, latest_ver])
		return
	# Out of date -> updating is mandatory. The in-place auto-update is offered only
	# when an asset for this platform exists, but the player is locked out either way
	# and can always fall back to the browser download.
	var asset := _asset_for_platform(release)
	_latest = {
		"tag": tag,
		"version": latest_ver,
		"notes": String(release.get("body", "")),
		"url": String(asset.get("browser_download_url", "")),
		"name": String(asset.get("name", "")),
	}
	print("[UPDATE] out of date (current=%s latest=%s) -- locking" % [current, latest_ver])
	_lock(current)


## The release asset zip built for the running OS, or {} if none.
func _asset_for_platform(release: Dictionary) -> Dictionary:
	var want := ""
	match OS.get_name():
		"Windows": want = "windows"
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD": want = "linux"
		_: return {}
	var assets: Variant = release.get("assets", [])
	if not (assets is Array):
		return {}
	for a in assets:
		if a is Dictionary and String(a.get("name", "")).to_lower().contains(want) \
				and String(a.get("name", "")).to_lower().ends_with(".zip"):
			return a
	return {}


## Mandatory lock: the player cannot reach the game until they update. Offers an
## in-place auto-update (when a platform asset exists), a browser download, a
## re-check, and quit. There is deliberately no "Later"/"Skip" -- closing the window
## re-opens it, so an out-of-date build cannot be played.
func _lock(current: String) -> void:
	_dialog = AcceptDialog.new()
	_dialog.title = "Update required"
	_dialog.dialog_text = "GraveBound %s is out -- you're on %s.\nUpdate to keep playing.\n\n%s" % [
		_latest["version"], current, _trim_notes(String(_latest["notes"]))]
	_dialog.exclusive = true
	_dialog.unresizable = true
	_dialog.dialog_close_on_escape = false
	# No default OK -- there is no "continue into the game" path.
	_dialog.get_ok_button().visible = false
	_dialog.add_button("Open download page", true, "download")
	if not String(_latest.get("url", "")).is_empty():
		_dialog.add_button("Update now", false, "auto")
	_dialog.add_button("Re-check", true, "retry")
	_dialog.add_button("Quit", true, "quit")
	_dialog.custom_action.connect(_on_lock_action)
	# Closing the window (X, the OS) just re-opens it while locked.
	_dialog.close_requested.connect(func() -> void:
		if _locked and _dialog != null:
			_dialog.popup_centered(Vector2i(560, 360)))
	_locked = true
	get_tree().root.add_child(_dialog)
	_dialog.popup_centered(Vector2i(560, 360))


func _on_lock_action(action: StringName) -> void:
	match String(action):
		"download":
			OS.shell_open(RELEASES_PAGE)
		"auto":
			_locked = false
			_dialog.hide()
			_start_update()
		"retry":
			_locked = false
			if _dialog != null:
				_dialog.queue_free()
				_dialog = null
			check()
		"quit":
			get_tree().quit()


func _start_update() -> void:
	_progress = AcceptDialog.new()
	_progress.title = "Updating GraveBound"
	_progress.dialog_text = "Downloading %s..." % _latest["name"]
	_progress.get_ok_button().disabled = true
	get_tree().root.add_child(_progress)
	_progress.popup_centered(Vector2i(420, 140))

	var zip_path := OS.get_cache_dir().path_join(String(_latest["name"]))
	_download = HTTPRequest.new()
	add_child(_download)
	_download.download_file = zip_path
	_download.request_completed.connect(_on_downloaded.bind(zip_path))
	var err := _download.request(String(_latest["url"]), ["User-Agent: " + USER_AGENT])
	if err != OK:
		_fail("Download could not start (%d)." % err)


func _on_downloaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray,
		zip_path: String) -> void:
	if _download != null:
		_download.queue_free()
		_download = null
	if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
		_fail("Download failed (result=%d http=%d)." % [result, code])
		return
	var exe_path := _extract_executable(zip_path)
	if exe_path.is_empty():
		_fail("Could not extract the update.")
		return
	if not _launch_swap(exe_path):
		_fail("Could not launch the updater.")
		return
	# The helper waits for us to exit, swaps the binary, and relaunches it.
	get_tree().quit()


## Reads the single embedded executable out of the downloaded zip and writes it
## to a sibling temp file. Returns its absolute path, or "" on failure.
func _extract_executable(zip_path: String) -> String:
	var reader := ZIPReader.new()
	if reader.open(zip_path) != OK:
		return ""
	var files := reader.get_files()
	if files.is_empty():
		reader.close()
		return ""
	var entry := files[0]
	var bytes := reader.read_file(entry)
	reader.close()
	if bytes.is_empty():
		return ""
	var out_path := OS.get_cache_dir().path_join("GraveBound-update-" + entry.get_file())
	var f := FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_buffer(bytes)
	f.close()
	return ProjectSettings.globalize_path(out_path)


## Spawns the detached wait-swap-relaunch helper for the running OS.
func _launch_swap(new_exe: String) -> bool:
	var target := OS.get_executable_path()
	var pid := OS.get_process_id()
	if OS.get_name() == "Windows":
		var cmd := "$p=%d; while(Get-Process -Id $p -ErrorAction SilentlyContinue){Start-Sleep -Milliseconds 300}; Copy-Item -LiteralPath '%s' -Destination '%s' -Force; Start-Process -FilePath '%s'" % [
			pid, new_exe, target, target]
		return OS.create_process("powershell",
			["-NoProfile", "-WindowStyle", "Hidden", "-Command", cmd]) > 0
	# Linux / BSD: replacing the on-disk binary while it runs is fine (the running
	# process keeps its own inode); the helper waits, copies, and relaunches.
	var sh := "p=%d; while kill -0 $p 2>/dev/null; do sleep 0.3; done; cp -f '%s' '%s'; chmod +x '%s'; nohup '%s' >/dev/null 2>&1 &" % [
		pid, new_exe, target, target, target]
	return OS.create_process("/bin/sh", ["-c", sh]) > 0


func _fail(reason: String) -> void:
	print("[UPDATE] " + reason)
	if _progress != null:
		_progress.queue_free()
		_progress = null
	var msg := AcceptDialog.new()
	msg.title = "Update failed"
	msg.dialog_text = "%s\n\nDownload manually from:\nhttps://github.com/%s/%s/releases/latest" % [
		reason, OWNER, REPO]
	get_tree().root.add_child(msg)
	msg.popup_centered()
	msg.confirmed.connect(msg.queue_free)
	msg.canceled.connect(msg.queue_free)


func _trim_notes(notes: String) -> String:
	if notes.length() <= 1200:
		return notes
	return notes.substr(0, 1200) + "\n..."


func _strip_v(s: String) -> String:
	s = s.strip_edges()
	if s.begins_with("v") or s.begins_with("V"):
		return s.substr(1)
	return s


## Numeric-part semver compare. Returns >0 if a>b, <0 if a<b, 0 if equal.
func _compare(a: String, b: String) -> int:
	var av := _parts(a)
	var bv := _parts(b)
	var n: int = max(av.size(), bv.size())
	for i in n:
		var x: int = av[i] if i < av.size() else 0
		var y: int = bv[i] if i < bv.size() else 0
		if x != y:
			return x - y
	return 0


func _parts(v: String) -> Array:
	var core := _strip_v(v)
	var dash := core.find("-")
	if dash >= 0:
		core = core.substr(0, dash)
	var out := []
	for p in core.split("."):
		out.append(int(p) if p.is_valid_int() else 0)
	return out
