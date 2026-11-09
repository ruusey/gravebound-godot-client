class_name InventoryInput
extends RefCounted

## The keys that reach into the bag without pointing at it.
##
## The web client's bindings: F picks up, Z and X drink, and Shift with a
## digit uses or equips one of the first eight backpack slots -- Shift
## because a bare digit casts the ability in that hotbar slot, and before the
## gate, pressing 1 to cast also swapped the weapon mid-fight. Tab shows and
## hides the panel, which is ours: both references keep theirs up always.
##
## Nothing here acts outside a realm. Tab is how a player moves from the
## email field to the password field on the login screen, and a Tab there
## once hid the bag before they had ever seen it.

const QUICK_SLOTS := 8

var client: GraveBoundClient
var actions: InventoryActions
var panel: InventoryPanel
## F is the tile in reach first and the loot bag second, as the web client
## orders it.
var shop: ShopActions
## C summons or recalls your one deployable companion. Both set in main once the
## companion panel + state exist; left null the key is simply a no-op.
var companion_actions: CompanionActions
var companions: CompanionState
## Whether the chat line has the keyboard; a key then is a letter.
var keyboard_captured: Callable = func() -> bool: return false

var _held := {}


func _init(net_client: GraveBoundClient, inventory_actions: InventoryActions,
		inventory_panel: InventoryPanel) -> void:
	client = net_client
	actions = inventory_actions
	panel = inventory_panel


func tick(_delta: float) -> void:
	if not client.is_in_game() or keyboard_captured.call():
		_held.clear()
		return
	if _pressed("toggle_inventory"):
		panel.toggle()
	if _pressed("pick_up") and (shop == null or not shop.interact_nearby()):
		actions.pick_up_first()
	if _pressed("drink_hp"):
		actions.drink(true)
	if _pressed("drink_mp"):
		actions.drink(false)
	if _pressed("summon_companion") and companion_actions != null and companions != null:
		companion_actions.toggle_summon(companions)
	for n in QUICK_SLOTS:
		if _pressed("quick_slot_%d" % (n + 1)):
			actions.activate(Inventory.BACKPACK_START + n)


## True on the frame the key goes down, not while it is held -- the same
## edge PortalInput tracks, for the same reason. Exact, so that the digit
## actions fire only with Shift held: a bare 1 is an ability cast.
func _pressed(action: String) -> bool:
	var down := Input.is_action_pressed(action, true)
	var edge: bool = down and not _held.get(action, false)
	_held[action] = down
	return edge
