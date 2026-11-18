class_name GameSettings
extends RefCounted

## What the player has switched on and off, and where it is kept.
##
## The web client's graphics settings (game.js DEFAULT_SETTINGS), each wired
## to the one place it governs, plus the desktop's vsync. Defaults are the
## web's except where this client's look differs: the wall side-bands, which
## the web calls its 'fancy' wall mode, are on here because they are how the
## walls have always been drawn. Kept in a ConfigFile under user://, which a
## browser keeps in the page's IndexedDB. The path is empty until Main sets
## it from the config, and an empty path reads and writes nothing, so a test
## or a scripted render always sees the defaults and never touches the file.

signal changed

const DEFAULT_PATH := "user://settings.cfg"
const SECTION := "settings"
## The keys (KeyBindings), kept beside the switches; only those changed.
const KEYS := "bindings"
## Which panels are folded (PanelFold), by the panel's key; only those chosen.
const PANELS := "panels"
## Key -> [label, default], in the order the options panel lists them.
const DISPLAY := {"vsync": ["VSync", true]}
const GRAPHICS := {
	"show_other_players": ["Show other players", true],
	"show_other_bullets": ["Show other players' bullets", true],
	"show_ally_effects": ["Show other players' ability effects", true],
	"ability_animations": ["Play ability animations", true],
	"show_names": ["Show player names", true],
	"show_status_chips": ["Show status effects", true],
	"show_chat_bubbles": ["Show chat bubbles", true],
	"show_damage_numbers": ["Show damage numbers", true],
	"hit_particles": ["Hit impact particles", true],
	"sprite_outlines": ["Sprite outlines", true],
	"loot_preview": ["Loot bag preview", true],
	"wall_bands": ["Wall side-bands", true],
	"lighting": ["Dynamic lighting", true],
	"bloom": ["Light bloom", true],
	"projectile_lighting": ["Projectile lighting", true],
	"animated_liquids": ["Animated water & lava", true],
	"show_transition_screen": ["Show the realm transition screen", true],
}
## The sound switches, each flipping one gate in Sfx. Volume is a float, kept
## beside them (sound_volume), not a switch.
const AUDIO := {
	"sound": ["Sound effects", true],
	"sound_others": ["Other players' sounds", true],
	"sound_hits": ["Hit & damage sounds", true],
}

var path := ""
## Master sound-effect volume, 0..1; Sfx reads it per play. The oggs are already
## loudness-normalized quiet, so this starts low.
var sound_volume := 0.5
## The player's UI scale and world zoom from the options, each 0 for
## automatic (DisplayScale); ScaleRow names them by these keys.
var ui_scale := 0.0
var world_zoom := 0.0
var _values := {}
var _panels := {}


func _init() -> void:
	for table in [DISPLAY, GRAPHICS, AUDIO]:
		for key in table:
			_values[key] = table[key][1]
	# Mobile GPUs can't afford the dynamic lights (20-30 fps in testing), so the
	# setting starts off there. A returning player's saved choice still wins, since
	# load_from overwrites these defaults.
	if _mobile_default_off():
		_values["lighting"] = false
		_values["bloom"] = false


## True on a phone/tablet (native or a touch web build), where lighting defaults off.
static func _mobile_default_off() -> bool:
	return OS.has_feature("android") or OS.has_feature("ios") \
		or (OS.has_feature("web") and DisplayServer.is_touchscreen_available())


func is_on(key: String) -> bool:
	return bool(_values.get(key, true))


func set_on(key: String, on: bool) -> void:
	if not _values.has(key) or _values[key] == on:
		return
	_values[key] = on
	apply()
	save()
	changed.emit()


## Reads what was kept at `file_path` and keeps later changes there;
## anything missing or unknown keeps its default. An empty path keeps nothing.
func load_from(file_path: String) -> void:
	path = file_path
	var file := ConfigFile.new()
	var keys := {}
	if path != "" and file.load(path) == OK:
		for key in _values:
			_values[key] = bool(file.get_value(SECTION, key, _values[key]))
		ui_scale = float(file.get_value(SECTION, "ui_scale", 0.0))
		world_zoom = float(file.get_value(SECTION, "world_zoom", 0.0))
		sound_volume = float(file.get_value(SECTION, "sound_volume", sound_volume))
		for action in file.get_section_keys(KEYS) if file.has_section(KEYS) else []:
			keys[action] = int(file.get_value(KEYS, action, 0))
		for panel in file.get_section_keys(PANELS) if file.has_section(PANELS) else []:
			_panels[panel] = bool(file.get_value(PANELS, panel, false))
	KeyBindings.apply(keys)
	apply()


func save() -> void:
	if path == "":
		return
	var file := ConfigFile.new()
	for key in _values:
		file.set_value(SECTION, key, _values[key])
	file.set_value(SECTION, "ui_scale", ui_scale)
	file.set_value(SECTION, "world_zoom", world_zoom)
	file.set_value(SECTION, "sound_volume", sound_volume)
	var keys := KeyBindings.custom()
	for action in keys:
		file.set_value(KEYS, action, keys[action])
	for panel in _panels:
		file.set_value(PANELS, panel, _panels[panel])
	file.save(path)


## Whether a panel was folded by choice; `otherwise` when nothing was chosen.
func panel_folded(key: String, otherwise: bool) -> bool:
	return bool(_panels.get(key, otherwise))


func set_panel_folded(key: String, folded: bool) -> void:
	if _panels.get(key) == folded:
		return
	_panels[key] = folded
	save()


## "ui_scale" or "world_zoom", 0 for automatic.
func set_scale(key: String, scale: float) -> void:
	if is_equal_approx(scale, scale_of(key)):
		return
	set(key, scale)
	save()
	changed.emit()


func scale_of(key: String) -> float:
	return float(get(key))


## The master SFX volume, 0..1; kept for next time.
func set_sound_volume(volume: float) -> void:
	volume = clampf(volume, 0.0, 1.0)
	if is_equal_approx(volume, sound_volume):
		return
	sound_volume = volume
	save()
	changed.emit()


## A key for an action, kept; see KeyBindings.rebind for the swap.
func rebind(action: String, key: int) -> void:
	if not KeyBindings.rebind(action, key).is_empty():
		save()
		changed.emit()


func reset_keys() -> void:
	KeyBindings.apply({})
	save()
	changed.emit()


## What is not read at the point of drawing: the window's vsync, and the
## outline every sprite pass stamps.
func apply() -> void:
	SpriteOutline.enabled = is_on("sprite_outlines")
	WallBandPass.enabled = is_on("wall_bands")
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if is_on("vsync") else DisplayServer.VSYNC_DISABLED)
