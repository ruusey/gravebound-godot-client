class_name UpdateChecker
extends Node

## Desktop auto-updater, mirroring the native client's UpdateChecker.
##
## On launch (desktop only) it asks GitHub for the latest release; if that tag is
## newer than this build's application/config/version, it prompts with the release
## notes. On accept it downloads this platform's zip, extracts the single
## executable, and spawns a tiny helper that waits for this process to exit,
## overwrites the running binary, and relaunches it -- then quits.
##
## Everything is best-effort: any failure (offline, no asset, bad zip) is logged
## and swallowed so the game still starts. Web and dev builds skip the check; the
## web client is always latest (served from /play).

const OWNER := "ruusey"
const REPO := "openrealm-godot-client"
const LATEST_URL := "https://api.github.com/repos/%s/%s/releases/latest" % [OWNER, REPO]
const USER_AGENT := "GraveBound-Godot-Client"
const SKIP_PATH := "user://skip_update.txt"

var _http: HTTPRequest
var _download: HTTPRequest
var _dialog: AcceptDialog
var _progress: AcceptDialog
var _latest := {}


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
	if _skipped_version() == latest_ver:
		print("[UPDATE] user previously skipped %s" % latest_ver)
		return
	var asset := _asset_for_platform(release)
	if asset.is_empty():
		print("[UPDATE] release %s has no asset for this platform" % tag)
		return
	_latest = {
		"tag": tag,
		"version": latest_ver,
		"notes": String(release.get("body", "")),
		"url": String(asset.get("browser_download_url", "")),
		"name": String(asset.get("name", "")),
	}
	print("[UPDATE] new version available: %s (current %s)" % [latest_ver, current])
	_prompt(current)


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


func _prompt(current: String) -> void:
	_dialog = AcceptDialog.new()
	_dialog.title = "GraveBound Update Available"
	_dialog.dialog_text = "GraveBound %s is available. You're on %s.\n\n%s" % [
		_latest["version"], current, _trim_notes(String(_latest["notes"]))]
	_dialog.ok_button_text = "Update now"
	_dialog.add_cancel_button("Later")
	_dialog.add_button("Skip this version", true, "skip")
	_dialog.confirmed.connect(_start_update)
	_dialog.custom_action.connect(func(action: StringName) -> void:
		if action == "skip":
			_write_skip(String(_latest["version"]))
		_dialog.hide())
	get_tree().root.add_child(_dialog)
	_dialog.popup_centered(Vector2i(560, 320))


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


func _skipped_version() -> String:
	if not FileAccess.file_exists(SKIP_PATH):
		return ""
	var f := FileAccess.open(SKIP_PATH, FileAccess.READ)
	if f == null:
		return ""
	var v := f.get_as_text().strip_edges()
	f.close()
	return v


func _write_skip(version: String) -> void:
	var f := FileAccess.open(SKIP_PATH, FileAccess.WRITE)
	if f != null:
		f.store_string(version)
		f.close()


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
