extends Node2D

## Every effect drawer side by side, for choosing which effect fits a moment
## in the game -- a boss's wind-up, a phase change, a hit -- and for seeing
## which drawers still need fleshing out.
##
## Live, each effect loops in a labelled grid:
##   godot --path . res://tests/visual/fx_gallery.tscn
## T tier colour, R radius, [ and ] duration, Space pause, Left/Right scrub
## while paused, wheel zoom, right-drag pan, click an effect to focus it and
## Esc to go back.
##
## --sheet writes contact sheets instead -- every effect caught at five
## points through its life, a page of rows at a time -- and quits:
##   godot --path . res://tests/visual/fx_gallery.tscn -- --sheet <out_dir> [radius] [tier]
## --check draws every effect across its whole life at every radius, naming
## each case first, so an engine error in the log points at its drawer:
##   godot --path . res://tests/visual/fx_gallery.tscn -- --check
## All three need a window: the headless driver has no device to render with.

const TIERS := [0, 1, 2, 3, 4, 5, 6, 10, 11, 12]
const RADII := [32.0, 48.0, 96.0, 150.0]
const SHEET_PROGRESS := [0.1, 0.3, 0.5, 0.7, 0.9]
## Tall enough for a page to fit a 1080p screen when viewed whole.
const SHEET_PAGE_HEIGHT := 960.0
const LABEL_WIDTH := 220.0
const HEADER := 26.0
const CHECK_STEPS := 50
## The idle beat between loops, so an effect's end reads as an end.
const LOOP_GAP_MS := 350
const BACKDROP := Color("101410")
const GROUND := Color("1c2418")
const GROUND_LINE := Color("2c3826")
const LABEL := Color("e8dcc0")
const NOTE := Color("9a9078")
## A player's 32px body, for scale.
const PLAYER_MARK := Color(1.0, 1.0, 1.0, 0.16)
## Effects drawn from where they start to a target. Their radius is a beam's
## half-width, or 0 for a throw, rather than an area, so they keep their own.
const LINE_RADIUS := {
	EffectType.BEAM_WARNING: 8.0, EffectType.CHAIN_LIGHTNING: 0.0, EffectType.KNIGHT_SHOCKWAVE: 40.0,
	EffectType.MELEE_SWING: 40.0, EffectType.NINJA_DASH: 20.0, EffectType.POISON_SPLASH: 0.0,
	EffectType.TRAP_THROW: 0.0,
}

var types: Array = []
var tier := 0
var radius := 48.0
var duration_ms := 900
var paused := false
var paused_progress := 0.3
var focus := -1
var started_ms := 0
var dragging := false
var font: Font = ThemeDB.fallback_font
var camera := Camera2D.new()
var hud := Label.new()
var grid := Node2D.new()
var cells: Array[Control] = []


func _ready() -> void:
	types = EffectType.NAMES.keys()
	types.sort()
	var args := OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--sheet":
		if args.size() > 2:
			radius = args[2].to_float()
		if args.size() > 3:
			tier = args[3].to_int()
		await write_sheets(args[1])
		get_tree().quit()
		return
	if args.size() >= 1 and args[0] == "--check":
		await check_all()
		get_tree().quit()
		return
	add_child(grid)
	add_child(camera)
	var layer := CanvasLayer.new()
	hud.position = Vector2(10, 8)
	hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	layer.add_child(hud)
	add_child(layer)
	started_ms = Time.get_ticks_msec()
	build_grid()


func _process(_delta: float) -> void:
	if cells.is_empty():
		return
	hud.text = "tier %d (T)   radius %d (R)   %d ms ([ ])   %s   wheel zoom, right-drag pan, click to focus" % [
		tier, int(radius), duration_ms, "paused %.2f (Left/Right)" % paused_progress if paused else "Space pause"]
	for cell in cells:
		if cell.visible:
			cell.queue_redraw()


## Where the shared loop is: every live effect plays in step, so they can be
## compared beat for beat. Past 1 is the idle gap.
func live_progress() -> float:
	if paused:
		return paused_progress
	return float((Time.get_ticks_msec() - started_ms) % (duration_ms + LOOP_GAP_MS)) / float(duration_ms)


func cell_span() -> float:
	return maxf(170.0, radius * 2.6 + 30.0)


func grid_columns() -> int:
	return ceili(sqrt(types.size() * 1.6))


## A cell that clips what it draws, so an effect that overshoots its radius
## stays in its own square.
func new_cell(size: Vector2, paint: Callable) -> Control:
	var cell := Control.new()
	cell.size = size
	cell.clip_contents = true
	cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.draw.connect(paint.bind(cell))
	return cell


func build_grid() -> void:
	for cell in cells:
		cell.queue_free()
	cells.clear()
	var span := cell_span()
	var columns := grid_columns()
	for i in types.size():
		var kind: int = types[i]
		var cell := new_cell(Vector2(span, span), func(canvas: Control) -> void:
			draw_cell(canvas, kind, live_progress(), true))
		cell.position = Vector2(i % columns, i / columns) * span
		cell.visible = focus < 0 or focus == i
		grid.add_child(cell)
		cells.append(cell)
	frame_camera()


## One effect in its cell: ground, a player-sized mark for scale, the effect
## and, when titled, its name. Draws no effect in the idle gap past 1.
func draw_cell(canvas: Control, kind: int, progress: float, titled: bool) -> void:
	var rect := Rect2(Vector2.ZERO, canvas.size)
	canvas.draw_rect(rect, GROUND)
	canvas.draw_rect(rect, GROUND_LINE, false, 1.0)
	var centre := rect.get_center() + Vector2(0.0, 8.0)
	canvas.draw_arc(centre, 16.0, 0.0, TAU, 24, PLAYER_MARK, 1.0)
	if progress <= 1.0:
		draw_effect(canvas, kind, centre, rect.size.x, progress)
	if titled:
		canvas.draw_string(font, Vector2(6.0, 16.0), "%d %s" % [kind, EffectType.NAMES[kind]],
			HORIZONTAL_ALIGNMENT_LEFT, rect.size.x - 12.0, 13, LABEL)
		var note := note_for(kind)
		if note != "":
			canvas.draw_string(font, Vector2(6.0, 30.0), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, NOTE)


func draw_effect(canvas: CanvasItem, kind: int, centre: Vector2, span: float, progress: float) -> void:
	var drawer := Fx.for_type(kind)
	if not drawer.is_valid():
		drawer = FxGeneric.draw
	var colour: Color = EffectRenderer.TIER_COLOURS[clampi(tier, 0, EffectRenderer.TIER_COLOURS.size() - 1)]
	drawer.call(canvas, effect(kind, centre, span), progress, colour, int(progress * duration_ms))


func note_for(kind: int) -> String:
	if not Fx.for_type(kind).is_valid():
		return "generic"
	return "line" if LINE_RADIUS.has(kind) else ""


## The effect as the wire would deliver it, as a boss would send it: no
## player owner. A line effect runs across the cell instead of sitting in it.
func effect(kind: int, centre: Vector2, span: float) -> Dictionary:
	var fx := {"type": kind, "pos": centre, "target": Vector2.ZERO, "radius": radius, "tier": tier,
		"owner": 0, "duration_ms": duration_ms, "started": 0}
	if LINE_RADIUS.has(kind):
		fx["pos"] = centre - Vector2(span * 0.34, -span * 0.08)
		fx["target"] = centre + Vector2(span * 0.34, -span * 0.08)
		fx["radius"] = LINE_RADIUS[kind]
	return fx


func frame_camera() -> void:
	var span := cell_span()
	var view := get_viewport_rect().size
	if focus >= 0:
		camera.position = cells[focus].position + Vector2(span, span) * 0.5
		camera.zoom = Vector2.ONE * (view.y * 0.8 / span)
		return
	var size := Vector2(grid_columns(), ceili(types.size() / float(grid_columns()))) * span
	camera.position = size * 0.5
	camera.zoom = Vector2.ONE * minf(view.x / size.x, view.y / size.y) * 0.98


func _unhandled_input(event: InputEvent) -> void:
	if cells.is_empty():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_T:
				tier = TIERS[(TIERS.find(tier) + 1) % TIERS.size()]
			KEY_R:
				radius = RADII[(RADII.find(radius) + 1) % RADII.size()]
				build_grid()
			KEY_BRACKETLEFT:
				duration_ms = maxi(300, duration_ms - 150)
			KEY_BRACKETRIGHT:
				duration_ms = mini(4000, duration_ms + 150)
			KEY_SPACE:
				paused_progress = clampf(live_progress(), 0.0, 1.0)
				paused = not paused
				started_ms = Time.get_ticks_msec() - int(paused_progress * duration_ms)
			KEY_LEFT:
				paused_progress = maxf(0.0, paused_progress - 0.05)
			KEY_RIGHT:
				paused_progress = minf(1.0, paused_progress + 0.05)
			KEY_ESCAPE:
				set_focus(-1)
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				camera.zoom *= 1.1
			MOUSE_BUTTON_WHEEL_DOWN:
				camera.zoom /= 1.1
			MOUSE_BUTTON_RIGHT:
				dragging = event.pressed
			MOUSE_BUTTON_LEFT:
				if event.pressed:
					set_focus(-1 if focus >= 0 else cell_under(get_global_mouse_position()))
	elif event is InputEventMouseMotion and dragging:
		camera.position -= event.relative / camera.zoom


func set_focus(index: int) -> void:
	focus = index
	for i in cells.size():
		cells[i].visible = focus < 0 or focus == i
	frame_camera()


func cell_under(at: Vector2) -> int:
	var cell := (at / cell_span()).floor()
	var index := int(cell.y) * grid_columns() + int(cell.x)
	if cell.x < 0 or cell.x >= grid_columns() or index < 0 or index >= types.size():
		return -1
	return index


## Renders pages of effects, one per row with SHEET_PROGRESS across, into an
## offscreen viewport -- so a page can be larger than the window -- and saves
## each as <out_dir>/fx_r<radius>_t<tier>_<page>.png.
func write_sheets(out_dir: String) -> void:
	var span := cell_span()
	var rows := maxi(2, int((SHEET_PAGE_HEIGHT - HEADER) / span))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(int(LABEL_WIDTH + span * SHEET_PROGRESS.size()), int(HEADER + span * rows))
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	DirAccess.make_dir_recursive_absolute(out_dir)
	for index in ceili(types.size() / float(rows)):
		var page := Control.new()
		page.size = Vector2(viewport.size)
		var shown := types.slice(index * rows, (index + 1) * rows)
		page.draw.connect(func() -> void: draw_sheet_labels(page, shown, span))
		for row in shown.size():
			for column in SHEET_PROGRESS.size():
				var kind: int = shown[row]
				var progress: float = SHEET_PROGRESS[column]
				var cell := new_cell(Vector2(span, span), func(canvas: Control) -> void:
					draw_cell(canvas, kind, progress, false))
				cell.position = Vector2(LABEL_WIDTH + span * column, HEADER + span * row)
				page.add_child(cell)
		viewport.add_child(page)
		for frame in 3:
			await RenderingServer.frame_post_draw
		var path := "%s/fx_r%d_t%d_%02d.png" % [out_dir, int(radius), tier, index + 1]
		viewport.get_texture().get_image().save_png(path)
		print("captured ", path)
		page.free()
	viewport.free()


func draw_sheet_labels(canvas: Control, shown: Array, span: float) -> void:
	canvas.draw_rect(Rect2(Vector2.ZERO, canvas.size), BACKDROP)
	canvas.draw_string(font, Vector2(6.0, 18.0), "radius %d  tier %d  %d ms" % [int(radius), tier, duration_ms],
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, NOTE)
	for column in SHEET_PROGRESS.size():
		canvas.draw_string(font, Vector2(LABEL_WIDTH + span * column + 6.0, 18.0),
			"%d%%" % int(SHEET_PROGRESS[column] * 100.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, NOTE)
	for row in shown.size():
		var kind: int = shown[row]
		var top := HEADER + span * row + span * 0.5
		canvas.draw_string(font, Vector2(8.0, top), "%d %s" % [kind, EffectType.NAMES[kind]],
			HORIZONTAL_ALIGNMENT_LEFT, LABEL_WIDTH - 12.0, 13, LABEL)
		var note := note_for(kind)
		if note != "":
			canvas.draw_string(font, Vector2(8.0, top + 16.0), note, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, NOTE)


## Each case is printed before it is drawn, so an engine error in the log
## sits right after the effect, radius and progress that raised it.
func check_all() -> void:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(512, 512)
	add_child(viewport)
	var canvas := Control.new()
	canvas.size = Vector2(viewport.size)
	viewport.add_child(canvas)
	var cases := []
	for size in RADII:
		for kind in types:
			for step in CHECK_STEPS + 1:
				cases.append([size, kind, float(step) / CHECK_STEPS])
	canvas.draw.connect(func() -> void:
		for case in cases:
			radius = case[0]
			print("check %s r%d p%.2f" % [EffectType.NAMES[case[1]], int(radius), case[2]])
			draw_effect(canvas, case[1], Vector2(256, 256), 512.0, case[2]))
	canvas.queue_redraw()
	await RenderingServer.frame_post_draw
	print("checked %d cases" % cases.size())
	viewport.free()
