#!/bin/sh
# Runs the test suites. Gameplay and editor tests run headless (no windows).
#   ./run_tests.sh            Rust + headless Godot tests
#   ./run_tests.sh --visual   also the screenshot tests (opens a window briefly)
# Screenshots go to $SHOTS (default /tmp/terraria3d-shots).
set -u
cd "$(dirname "$0")"
SHOTS=${SHOTS:-/tmp/terraria3d-shots}
mkdir -p "$SHOTS"
FAIL=0
GODOT="godot --audio-driver Dummy --path game"

echo "== Rust"
cargo test --release --manifest-path rust/voxel_core/Cargo.toml 2>&1 | grep "test result" | head -1 | grep -q " 0 failed" || FAIL=1

echo "== Script check"
# Compile every script (tests included) before running anything: a test that
# fails to parse would otherwise sit idle until its timeout.
godot --headless --path game --import >/dev/null 2>&1
check=$(timeout -k 5 60 godot --headless --audio-driver Dummy --path game res://tests/compile_check.tscn 2>&1)
if ! echo "$check" | grep -q "COMPILE OK"; then
	echo "$check" | grep -E "SCRIPT ERROR|at: |COMPILE" | head -20
	echo "script errors; not running Godot tests"
	exit 1
fi

run() {  # run <scene> <seconds> [--headless]
	name=$1; secs=$2; shift 2
	# timeout -k kills a hung run; windowed runs also get a frame-count backstop
	# (--quit-after) so a stuck window closes itself.
	case " $* " in
		*" --headless "*) backstop="" ;;
		*) backstop="--quit-after $((secs * 70))" ;;
	esac
	out=$(timeout -k 5 "$secs" $GODOT "$@" $backstop "res://tests/$name.tscn" -- "$SHOTS" 2>&1)
	result=$(echo "$out" | grep "RESULT" | tail -1)
	echo "$name: ${result:-no result (crashed or timed out)}"
	echo "$out" | grep -E "^FAIL|SCRIPT ERROR" | head -10
	case "$result" in *"0 failures"*|*"ok"*) ;; *) FAIL=1 ;; esac
	# A shader that doesn't compile draws with a fallback material and nothing
	# else complains, so it fails the run.
	if echo "$out" | grep -q "SHADER ERROR"; then
		echo "$name: SHADER ERROR"
		echo "$out" | grep -A3 "SHADER ERROR" | head -12
		FAIL=1
	fi
}

echo "== Godot (headless)"
run game_test 240 --headless --fixed-fps 60
run editor_test 90 --headless --fixed-fps 60
run test_world_test 120 --headless --fixed-fps 60
run test_world_kinds_test 120 --headless --fixed-fps 60
run placeables_test 240 --headless --fixed-fps 60
run sprite_editor_test 90 --headless --fixed-fps 60
run npc_scale_editor_test 90 --headless --fixed-fps 60
run npc_picker_test 120 --headless --fixed-fps 60
run model_sculptor_test 180 --headless --fixed-fps 60
run menu_world_test 60 --headless --fixed-fps 60
run player_test 240 --headless --fixed-fps 60
run creative_test 120 --headless --fixed-fps 60

if [ "${1:-}" = "--visual" ]; then
	echo "== Godot (visual, screenshots in $SHOTS)"
	run render_test 180
	run viewmodel_test 60
	run menu_test 60
	run waterfall_test 60
fi
exit $FAIL
