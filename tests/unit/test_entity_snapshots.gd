extends GutTest

## EntitySnapshots.hit_position: the position client bullet-hit prediction tests
## against. It must equal the drawn (sampled) position while interpolating, but must
## NOT follow the forward extrapolation the draw path uses once snapshots go stale --
## the server confirms a hit only where the enemy really was, so predicting against an
## extrapolated guess is what made bullets vanish on an enemy with no damage dealt.

const INTERP := 100.0


func _enemy(snaps: Array) -> Dictionary:
	return {"kind": GameConstants.ENTITY_ENEMY, "size": 8, "snaps": snaps}


func test_while_interpolating_it_matches_the_drawn_position():
	# Two fresh snapshots bracket the render time (now - INTERP), so both the draw
	# path and the hit path read the same interpolated point.
	var enemy := _enemy([
		{"t": 0.0, "pos": Vector2(0, 0), "vel": Vector2(10, 0)},
		{"t": 50.0, "pos": Vector2(10, 0), "vel": Vector2(10, 0)},
	])
	var now := 130.0   # target = 30, between the two snapshots
	assert_eq(EntitySnapshots.hit_position(enemy, now), Vector2(6, 0), "interpolated 0.6 of the way")
	assert_eq(EntitySnapshots.hit_position(enemy, now), EntitySnapshots.sampled(enemy, now),
		"same as the drawn position when there is a newer snapshot to interpolate to")


func test_when_snapshots_go_stale_it_clamps_instead_of_extrapolating():
	# The newest snapshot is older than the render time, so the DRAW path projects the
	# enemy forward along its last velocity. The HIT path must stay on the last real
	# position instead -- the divergence that the server will never confirm.
	var enemy := _enemy([
		{"t": 0.0, "pos": Vector2(0, 0), "vel": Vector2(10, 0)},
		{"t": 50.0, "pos": Vector2(10, 0), "vel": Vector2(10, 0)},
	])
	var now := 300.0   # target = 200, past the newest snapshot at t = 50
	assert_eq(EntitySnapshots.hit_position(enemy, now), Vector2(10, 0),
		"clamped to the last recorded position, not guessed ahead")
	assert_gt(EntitySnapshots.sampled(enemy, now).x, 100.0,
		"the draw path meanwhile extrapolates far ahead")


func test_before_the_first_snapshot_it_holds_the_oldest():
	var enemy := _enemy([
		{"t": 500.0, "pos": Vector2(4, 4), "vel": Vector2.ZERO},
		{"t": 550.0, "pos": Vector2(6, 4), "vel": Vector2.ZERO},
	])
	var now := 540.0   # target = 440, before the oldest snapshot
	assert_eq(EntitySnapshots.hit_position(enemy, now), Vector2(4, 4), "holds the oldest")


func test_no_snapshots_is_the_origin_not_an_error():
	assert_eq(EntitySnapshots.hit_position(_enemy([]), 1000.0), Vector2.ZERO)
