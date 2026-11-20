#!/usr/bin/env bash
# Renders each visual scenario and compares it to the accepted references.
#
#   ./capture-visuals.sh            capture, then check against references
#   ./capture-visuals.sh --update   capture and accept the result as the new
#                                   reference (review the images first)
#
# Capture runs WINDOWED on purpose: Godot's headless display driver has no
# rendering device, so get_texture().get_image() returns null. A window
# comes up once for the whole run; nothing interactive happens in it. The
# comparison step renders nothing and runs headless.
set -euo pipefail

GODOT="${GODOT:-/Applications/Godot_mono_v4.7.2.app/Contents/MacOS/Godot}"
cd "$(dirname "$0")"

OUT_DIR="reports/visual"
REF_DIR="tests/visual/reference"
SCENARIOS=(terrain entities ysort bullets collision overlap walk_left walk_right walk_up walk_down walls feather effects walldepth shadows attack_left attack_right attack_up spin portals transition transition_named damage damage_fading chat chat_typing chat_bubbles death wading inventory abilities potion_storage fame_store forge minimap trails login exchange_market wall_bands effects_cast effects_generic effects_holy effects_dark effects_arcane effects_knight effects_rogue effects_trapper effects_heavy trade player_hud party nearby item_card options options_controls masteries dev_overlay blind dyes quests quest_stars login_delete login_stats terms how_to leaderboard loot_preview minimap_hop billboards chunk_seams tall_walls shores vault touch_phone quest_complete companions phone_play phone_bag phone_menu phone_chat phone_map phone_loot phone_loot_bag login_account wall_plus buy_fame buy_fame_waiting)

mkdir -p "$OUT_DIR" "$REF_DIR"
rm -f "$OUT_DIR"/*.png

# Every scenario is captured by ONE Godot process (capture.gd --all), so the
# window comes up once for the whole run -- about fifteen seconds -- rather
# than once a scenario. It keeps the foreground for that time on purpose: a
# window that is fully covered stops rendering on macOS, and each capture
# then reads the previous scenario's frame.
LOG="$(mktemp -t capture.XXXXXX)"
trap 'rm -f "$LOG"' EXIT

echo "== capturing =="
# The class cache first, as run-tests.sh does: in a fresh checkout nothing is
# imported yet, every class_name fails to resolve and each scenario errors.
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --path . --resolution 1280x960 \
	res://tests/visual/capture.tscn -- --all "$OUT_DIR" "${SCENARIOS[@]}" \
	>"$LOG" 2>&1 || true
grep -E "captured|ERROR" "$LOG" || true

# A scenario that raised a script error drew something wrong, or nothing --
# a dyed player typed as an AtlasTexture vanished from the draw that way --
# and the image can still match its reference, or with --update become
# one. So any SCRIPT ERROR fails the run before anything is compared or
# accepted, as in run-tests.sh.
errors=$(grep -c "SCRIPT ERROR" "$LOG" || true)
if [[ "$errors" != "0" ]]; then
	grep -A2 "SCRIPT ERROR" "$LOG" | head -30 >&2
	echo "FAIL: $errors SCRIPT ERROR(s) while capturing -- nothing compared or accepted" >&2
	exit 1
fi

if [[ "${1:-}" == "--update" ]]; then
	cp "$OUT_DIR"/*.png "$REF_DIR"/
	echo
	echo "Accepted $(ls -1 "$REF_DIR"/*.png | wc -l | tr -d ' ') images as references in $REF_DIR/"
	exit 0
fi

echo
echo "== comparing against $REF_DIR =="
"$GODOT" --headless --path . --script tests/visual/compare.gd -- "$REF_DIR" "$OUT_DIR"
