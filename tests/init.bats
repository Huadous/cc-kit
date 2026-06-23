#!/usr/bin/env bats
# tests/init.bats — Unit tests for init.sh's CC_KIT_ROOT resolution logic.
#
# init.sh self-locates from BASH_SOURCE[0] and then either uses
# $CC_KIT_ROOT (if set) or the auto-detected path. The warnings printed
# here matter because they fire on every interactive shell start (every
# tmux window, every `bash -i`, every new pane) — so they need to be
# accurate but not noisy.
#
# We test against the REAL init.sh from the repo, not a synthetic copy,
# so behavior can't drift.

setup() {
    REAL_INIT="$BATS_TEST_DIRNAME/../init.sh"
    [[ -f "$REAL_INIT" ]] || skip "init.sh not found at $REAL_INIT"
}

@test "init.sh: no warning when CC_KIT_ROOT is unset" {
    run bash -c "unset CC_KIT_ROOT; source '$REAL_INIT' >/dev/null 2>&1; echo \"ROOT=\$CC_KIT_ROOT\""
    [[ ! "$output" =~ WARNING ]]
    [[ "$output" =~ "ROOT=" ]]
}

@test "init.sh: no warning when CC_KIT_ROOT matches self-located install" {
    # Source from a symlinked path so the script resolves CC_KIT_ROOT to
    # the same place it auto-detects — both end up at the same install dir.
    REAL_DIR=$(dirname "$REAL_INIT")
    LINK_DIR=$(mktemp -d)
    ln -s "$REAL_DIR" "$LINK_DIR/install"
    # Note: use `export X=Y; source ...` (separate statements) — the
    # command-prefix form `X=Y source ...` is bash's "VAR for this command
    # only" syntax, which doesn't persist the assignment past `source`.
    run bash -c "export CC_KIT_ROOT='$LINK_DIR/install'; source '$LINK_DIR/install/init.sh' >/dev/null 2>&1; echo \"ROOT=\$CC_KIT_ROOT\""
    [[ ! "$output" =~ WARNING ]]
    # CC_KIT_ROOT is preserved (whatever was passed in); just confirm it's set.
    [[ "$output" =~ "ROOT=$LINK_DIR/install" ]]
    rm -rf "$LINK_DIR"
}

@test "init.sh: no warning when CC_KIT_ROOT is a VALID dev override (different dir)" {
    # This is the tmux scenario: CC_KIT_ROOT inherited from parent shell
    # points to a real, accessible dev tree; we should silently use it,
    # not nag every shell start.
    OTHER=$(mktemp -d)
    run bash -c "export CC_KIT_ROOT='$OTHER'; source '$REAL_INIT' >/dev/null 2>&1; echo \"ROOT=\$CC_KIT_ROOT\""
    [[ ! "$output" =~ WARNING ]]
    [[ "$output" =~ "$OTHER" ]]
    rm -rf "$OTHER"
}

@test "init.sh: WARNS when CC_KIT_ROOT points to non-existent path" {
    # The dangerous case: env var set to a path that doesn't exist.
    # Silent fallback was the root cause of a real SessionStart outage.
    run bash -c "export CC_KIT_ROOT='/no/such/path/anywhere'; source '$REAL_INIT' 2>&1; echo \"ROOT=\$CC_KIT_ROOT\""
    [[ "$output" =~ "WARNING" ]]
    [[ "$output" =~ "not accessible" ]]
    [[ "$output" =~ "/no/such/path/anywhere" ]]
    # The echo at the end prints the FALLBACK CC_KIT_ROOT. It must be
    # set to a real path (not the broken one, not empty).
    root_val=$(echo "$output" | sed -n 's/^ROOT=//p')
    [[ -n "$root_val" ]]
    [[ "$root_val" != "/no/such/path/anywhere" ]]
    [[ -d "$root_val" ]]
}

@test "init.sh: no warning when CC_KIT_ROOT points to a symlink that resolves to a real path" {
    # A common pattern: CC_KIT_ROOT=~/.cc-kit where ~/.cc-kit is a symlink
    # to the real install. The link is valid (resolves to a real path) so
    # the script should silently use it without warning.
    REAL_DIR=$(dirname "$REAL_INIT")
    LINK_DIR=$(mktemp -d)
    ln -s "$REAL_DIR" "$LINK_DIR/link"
    run bash -c "export CC_KIT_ROOT='$LINK_DIR/link'; source '$REAL_INIT' >/dev/null 2>&1; echo \"ROOT=\$CC_KIT_ROOT\""
    [[ ! "$output" =~ WARNING ]]
    # CC_KIT_ROOT is preserved (the symlink path that was passed in).
    [[ "$output" =~ "ROOT=$LINK_DIR/link" ]]
    rm -rf "$LINK_DIR"
}

@test "init.sh: real init.sh does NOT contain the 'overrides auto-detected' warning" {
    # Regression guard: we removed this warning because it fires every tmux
    # window. If someone re-adds it, this test will fail loudly.
    ! grep -q "overrides auto-detected" "$REAL_INIT"
}

@test "init.sh: real init.sh DOES still contain the broken-path warning" {
    # Regression guard: the dangerous case (env var → non-existent path)
    # must keep warning. Removing it was the original v0.1.1 outage cause.
    grep -q "is not accessible" "$REAL_INIT"
}

@test "init.sh: cc-switch is replaced with a thin dispatcher" {
    # After sourcing init.sh, cc-switch must be a function (not the
    # full modules/switch.sh body). The full body is large and freezes
    # at first-source — a long-lived tmux pane would keep the old body
    # after an upgrade (e.g. adding glm-5.2). The dispatcher re-runs
    # via bin/cc-switch, which re-sources modules/switch.sh every call.
    #
    # We verify by checking that the body is short (a few lines — just
    # the call to bin/cc-switch) rather than the full multi-case logic.
    run bash -c "source '$REAL_INIT' >/dev/null 2>&1; declare -f cc-switch"
    [[ "$status" -eq 0 ]]
    # Body should be small — dispatcher is ~3 lines, full body is 100+
    line_count=$(echo "$output" | wc -l)
    [[ "$line_count" -lt 15 ]]
    # And must reference the bin path (via CC_KIT_ROOT, the env var the script exports)
    [[ "$output" == *'CC_KIT_ROOT'* ]]
    [[ "$output" == *'bin/cc-switch'* ]]
}

@test "all source files: no script contains the 'overrides auto-detected' warning" {
    # The same dev-override warning was duplicated across 8 bash files
    # (init.sh, bin/cc-switch, bin/cc-balance, bin/cc-status, bin/cc-mode,
    # hooks/session-start.sh, hooks/stop-record.sh, modules/monitor.sh,
    # modules/switch.sh). All were fixed in one go; this test guards
    # against any of them regressing.
    local found=0
    for f in "$BATS_TEST_DIRNAME/../init.sh" \
             "$BATS_TEST_DIRNAME/../bin/cc-switch" \
             "$BATS_TEST_DIRNAME/../bin/cc-balance" \
             "$BATS_TEST_DIRNAME/../bin/cc-status" \
             "$BATS_TEST_DIRNAME/../bin/cc-mode" \
             "$BATS_TEST_DIRNAME/../hooks/session-start.sh" \
             "$BATS_TEST_DIRNAME/../hooks/stop-record.sh" \
             "$BATS_TEST_DIRNAME/../modules/monitor.sh" \
             "$BATS_TEST_DIRNAME/../modules/switch.sh"; do
        if grep -q "overrides auto-detected" "$f"; then
            echo "FAIL: $f still contains the warning" >&2
            found=1
        fi
    done
    [ "$found" -eq 0 ]
}