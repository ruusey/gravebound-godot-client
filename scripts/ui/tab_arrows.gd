class_name TabArrows
extends RefCounted

## A clipped TabBar's scroll arrows switch tabs instead of only scrolling
## the strip, so one click shows the next page instead of an arrow then a tab.
##
## TabBar has no signal for its arrows. Its gui_input signal fires before the
## bar handles the click, so the tab and scroll offset are read then and
## compared after: the offset moved while the tab stayed put means an arrow.


static func select_on_scroll(bar: TabBar) -> void:
	bar.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_follow.call_deferred(bar, bar.current_tab, bar.get_tab_offset()))


## The tab an arrow click should land on, or -1 when the click was not an
## arrow (the offset held still, or a tab was picked directly).
static func step_target(tab_before: int, offset_before: int, tab_after: int,
		offset_after: int, tab_count: int) -> int:
	if offset_after == offset_before or tab_after != tab_before:
		return -1
	return clampi(tab_before + signi(offset_after - offset_before), 0, tab_count - 1)


static func _follow(bar: TabBar, tab_before: int, offset_before: int) -> void:
	if not is_instance_valid(bar):
		return
	var target := step_target(tab_before, offset_before, bar.current_tab, bar.get_tab_offset(), bar.tab_count)
	if target >= 0:
		bar.current_tab = target
