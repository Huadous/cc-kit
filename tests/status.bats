#!/usr/bin/env bats
# tests/status.bats — Unit tests for cc-status (single / wide / full modes)
# and cc-status-full.py (the Python 3-line boxed dashboard).
#
# The full-mode bug we caught: cc-status-full.py read
# `data["remaining_percentage"]` at the top level, but Claude Code's
# actual statusLine payload nests the value under `context_window`.
# Result: full mode always rendered `context 0%` even when context was
# actually visible (single/wide modes worked because the bash script
# grep'd for the key string regardless of nesting).

setup() {
    CC_STATUS="$BATS_TEST_DIRNAME/../bin/cc-status"
    CC_STATUS_FULL="$BATS_TEST_DIRNAME/../bin/cc-status-full.py"
    # ensure HOME has a settings.json or cc-status may complain; not strictly
    # needed for rendering tests, but matches the real environment.
    [[ -d "$HOME" ]] || mkdir -p "$HOME"
}

@test "cc-status-full.py: nested context_window.remaining_percentage renders correctly" {
    JSON='{"hookEventName":"Status","context_window":{"total_tokens":200000,"used_percentage":35,"remaining_percentage":65}}'
    run bash -c "echo '$JSON' | python3 '$CC_STATUS_FULL' 2>/dev/null"
    [ "$status" -eq 0 ]
    # 65% remaining = bar + "65%"
    [[ "$output" =~ "65%" ]]
}

@test "cc-status-full.py: top-level remaining_percentage still works (legacy / test scripts)" {
    JSON='{"remaining_percentage":42}'
    run bash -c "echo '$JSON' | python3 '$CC_STATUS_FULL' 2>/dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "42%" ]]
}

@test "cc-status-full.py: empty stdin → context label without bar (no crash)" {
    run bash -c "echo '' | python3 '$CC_STATUS_FULL' 2>/dev/null"
    [ "$status" -eq 0 ]
    # Should still render the box and "context" label, just no bar/percentage.
    [[ "$output" =~ "context" ]]
}

@test "cc-status-full.py: malformed JSON → context label without bar (no crash)" {
    run bash -c "echo 'not json' | python3 '$CC_STATUS_FULL' 2>/dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "context" ]]
}

@test "cc-status: wide mode renders context bar from nested JSON" {
    JSON='{"context_window":{"remaining_percentage":75}}'
    run bash -c "echo '$JSON' | '$CC_STATUS' wide 2>/dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "75%" ]]
    # Wide mode shows the bar (block chars) + percentage; no "ctx" label
    # (unlike single mode which adds the suffix for compactness).
    [[ "$output" =~ "▁" || "$output" =~ "█" ]]
}

@test "cc-status: single mode renders context bar from nested JSON" {
    JSON='{"context_window":{"remaining_percentage":12}}'
    run bash -c "echo '$JSON' | '$CC_STATUS' single 2>/dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "12%" ]]
    [[ "$output" =~ "ctx" ]]
}

@test "cc-status: full mode (dispatched via Python) handles nested JSON" {
    JSON='{"context_window":{"remaining_percentage":88}}'
    run bash -c "echo '$JSON' | '$CC_STATUS' full 2>/dev/null"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "88%" ]]
}

@test "cc-status: --help exits 0 and lists modes" {
    run "$CC_STATUS" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "single" ]]
    [[ "$output" =~ "wide" ]]
    [[ "$output" =~ "full" ]]
}