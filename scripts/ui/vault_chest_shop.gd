class_name VaultChestShop
extends CanvasLayer

## What the vault's "vault_chest" tile opens: a confirm showing the chest count,
## the price and the player's fame, then the purchase through the data service,
## which spends the fame and caps the count (1 for a guest, 50 otherwise). The
## new chest is written to the account and appears on the next vault entry.

var data_service: DataService
## Set by Main: where the purchase result is shown.
var text_popup: TextPopup

var _confirm: ConfirmPopup
var _busy := false


func setup(service: DataService) -> void:
	data_service = service


func _ready() -> void:
	layer = 11
	_confirm = ConfirmPopup.new()
	add_child(_confirm)


## Re-reads the account first so the count and fame in the prompt are current.
func offer() -> void:
	if _busy or data_service == null:
		return
	_busy = true
	await data_service.refresh_account()
	_busy = false
	VaultChestPurchase.confirm(_confirm, data_service, _buy)


func _buy() -> void:
	if _busy:
		return
	_busy = true
	var result := await data_service.create_chest()
	_busy = false
	var message := "Chest added (now %d). Re-enter the vault to use it." % data_service.chest_count() \
		if result["success"] else str(result["result"])
	if text_popup != null:
		text_popup.show_text("Vault Chest", message)


func captures_mouse() -> bool:
	return _confirm != null and _confirm.captures_mouse()
