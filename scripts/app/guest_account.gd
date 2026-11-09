class_name GuestAccount
extends RefCounted

## "Play as Guest": a throwaway account made fresh on every press.
##
## A guest is an ordinary account made on the spot -- guest_<8 hex>@grave-bound.com,
## a sixteen-hex password, a name off the web client's list -- registered with
## `guest: true`, which the data service answers with the DEMO provision and an
## empty account. The credentials are SHOWN to the player once (account_form) and
## NEVER stored: every press makes a brand-new guest, and any guest a prior build
## cached is cleared on the way. To keep a guest, the player saves the shown
## credentials and signs in with them like any other account.

const DEFAULT_PATH := "user://guest.cfg"
const SECTION := "guest"
## main.js GUEST_NAMES.
const NAMES := ["Utanu", "Gharr", "Yimi", "Idrae", "Odaru", "Scheev", "Zhiar", "Itani",
	"Serl", "Oeti", "Tiar", "Issz", "Oshyu", "Deyst", "Oalei", "Vorv",
	"Iatho", "Uoro", "Urake", "Eashy", "Queq", "Rayr", "Tal", "Drac",
	"Yangu", "Eango", "Rilr", "Ehoni", "Risrr", "Sek", "Eati", "Laen",
	"Eendi", "Ril", "Darq", "Seus", "Radph", "Orothi", "Vorck", "Saylt",
	"Iawa", "Iri", "Lauk", "Lorz"]

var path := DEFAULT_PATH
var rng := RandomNumberGenerator.new()


## A fresh set: {email, password, name}.
func make() -> Dictionary:
	return {"email": "guest_%s@grave-bound.com" % _hex(), "password": _hex() + _hex(),
		"name": NAMES[rng.randi_range(0, NAMES.size() - 1)]}


## Drop any guest credentials a previous build persisted, so "Play as Guest" never
## resurrects an old guest (and its characters).
func forget() -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


## A brand-new guest, registered and never stored. Returns {success, email,
## password, created}, or {success: false, result: reason}.
func obtain(service: DataService) -> Dictionary:
	forget()
	var fresh := make()
	var registered: Dictionary = await service.register(fresh["email"], fresh["password"], fresh["name"], true)
	if not registered["success"]:
		return {"success": false, "result": registered["result"]}
	return {"success": true, "email": fresh["email"], "password": fresh["password"], "created": true}


## Eight lowercase hex digits, as the web's Math.random().toString(16).slice(2, 10).
func _hex() -> String:
	return "%08x" % rng.randi()
