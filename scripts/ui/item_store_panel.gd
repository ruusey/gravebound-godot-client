class_name ItemStorePanel
extends CanvasLayer

## The potion storage a shelf opens, the vault's or the guild hall's:
## thirty-two slots in two grids, beside the bag, until the Close button.
##
## Godot's own controls, like the bag; the slots are ItemSlots with store
## indices, so a drag between here and the bag is the same gesture as one
## inside the bag, and lands in InventoryActions.move, which knows a store
## index when it sees one. A click on a shelf item takes it into the first
## free backpack slot, as the web client's does.

const TITLES := {ItemStore.KIND_POTION: "POTION STORAGE", ItemStore.KIND_GUILD_POTION: "GUILD POTION STORAGE"}
const COLUMNS := 4
const HALF := ItemStore.SIZE / 2

var state: RealmState
var content: GameData
var actions: InventoryActions
var shop: ShopActions

var _root: Container
var _title: Label
var _slots: Array = []
var _tooltip: ItemTooltip
var _drawn := -1


func setup(realm_state: RealmState, game_data: GameData, inventory_actions: InventoryActions,
		shop_actions: ShopActions) -> void:
	state = realm_state
	content = game_data
	actions = inventory_actions
	shop = shop_actions


func _ready() -> void:
	# Over the bag and the bar, under the transition cover.
	layer = 14
	visible = false
	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)
	# A drop on the panel's own background is a change of mind, not a throw.
	_root = InventoryLayout.DropSink.new()
	centre.add_child(_root)
	var column := InventoryLayout.column(_root)
	var bar := HBoxContainer.new()
	column.add_child(bar)
	_title = InventoryLayout.heading(bar, title(ItemStore.KIND_POTION))
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close := Button.new()
	close.text = "Close"
	close.pressed.connect(func() -> void: state.store.close())
	bar.add_child(close)
	var grids := HBoxContainer.new()
	grids.add_theme_constant_override("separation", 12)
	column.add_child(grids)
	_slots = InventoryLayout.grid(grids, HALF, ItemStore.SLOT_BASE, COLUMNS)
	_slots.append_array(InventoryLayout.grid(grids, HALF, ItemStore.SLOT_BASE + HALF, COLUMNS))
	for slot in _slots:
		_wire(slot)
	_tooltip = ItemTooltip.of(state, content)
	add_child(_tooltip)
	TouchFrame.adopt(self)


func _process(_delta: float) -> void:
	visible = state != null and state.store.is_open and state.local.is_present()
	if not visible:
		_tooltip.hide_card()
		return
	PanelFit.shrink(_root)
	if state.store.version != _drawn:
		refresh()
	if _tooltip.visible:
		_tooltip.follow(_root.get_global_mouse_position())


## The heading for a store of `kind`.
static func title(kind: int) -> String:
	return String(TITLES.get(kind, TITLES[ItemStore.KIND_POTION]))


func refresh() -> void:
	_drawn = state.store.version
	_title.text = title(state.store.kind)
	for i in _slots.size():
		_slots[i].show_from(state.store.item_at(i), content)


func captures_mouse() -> bool:
	return visible and _root.get_global_rect().has_point(_root.get_global_mouse_position())


func _wire(slot: ItemSlot) -> void:
	slot.hovered.connect(_on_hover)
	if actions != null:
		slot.dropped.connect(actions.move)
	if shop != null:
		slot.activated.connect(shop.take)
		slot.secondary.connect(func(index: int, _split: bool) -> void: shop.take(index))


func _on_hover(index: int, over: bool) -> void:
	var item := shop.item_in(index) if over and shop != null else {}
	if Inventory.holds(item):
		_tooltip.show_for(item, _root.get_global_mouse_position())
	else:
		_tooltip.hide_card()
