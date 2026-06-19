#!/usr/bin/env bats
# tests/install.bats — Unit tests for the install.sh rc-cleanup helper.
#
# We can't run install.sh itself under bats (it's interactive and touches
# the real filesystem), so we extract the cleanup logic into a small
# helper that this file sources. The helper lives in install.sh; this
# test verifies the regex+delete behavior.

setup() {
    # Source just the helper. We do this by extracting the function
    # definition from install.sh so the test fails loudly if install.sh
    # gets restructured in a way that breaks the helper extraction.
    TEST_DIR=$(mktemp -d)
    INSTALL_SH="$BATS_TEST_DIRNAME/../install.sh"
    # Pull the function block out of install.sh and eval it. The pattern
    # we rely on is the comment line `_cc_kit_clean_rc_exports <file> ...`
    # above the function and the `}` that closes the function. The next
    # top-level statement begins with `_removed_rc_exports=0`, which we
    # use as a sentinel.
    _helper=$(awk '/^_cc_kit_clean_rc_exports\(\) \{$/,/^}$/' "$INSTALL_SH")
    eval "$_helper"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "rc cleanup: removes CC_KIT_DIR / CC_KIT_ROOT / MONITOR_DATA_DIR exports" {
    cat > "$TEST_DIR/.bashrc" <<'EOF'
# my custom comment
export CC_KIT_DIR="$HOME/projects/cc-kit"
export CC_KIT_ROOT="$HOME/projects/cc-kit"
export MONITOR_DATA_DIR="$HOME/projects/cc-kit/data"
# unrelated
export PATH="$HOME/.local/bin:$PATH"
EOF
    _cc_kit_clean_rc_exports "$TEST_DIR/.bashrc" 1
    run cat "$TEST_DIR/.bashrc"
    [ "${lines[0]}" = "# my custom comment" ]
    [ "${lines[1]}" = "# unrelated" ]
    [ "${lines[2]}" = 'export PATH="$HOME/.local/bin:$PATH"' ]
    [ "${#lines[@]}" -eq 3 ]
}

@test "rc cleanup: keeps non-matching exports (PATH, OTHER_VAR)" {
    cat > "$TEST_DIR/.bashrc" <<'EOF'
export PATH="$HOME/.local/bin:$PATH"
export EDITOR="vim"
export CC_KIT_ROOT="/tmp/old"
EOF
    _cc_kit_clean_rc_exports "$TEST_DIR/.bashrc" 1
    run cat "$TEST_DIR/.bashrc"
    [ "${lines[0]}" = 'export PATH="$HOME/.local/bin:$PATH"' ]
    [ "${lines[1]}" = 'export EDITOR="vim"' ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "rc cleanup: ignores commented-out exports" {
    cat > "$TEST_DIR/.bashrc" <<'EOF'
# export CC_KIT_DIR="/tmp/old"  (commented out, must stay)
# export CC_KIT_ROOT="/tmp/old"
export CC_KIT_ROOT="/tmp/active"
EOF
    _cc_kit_clean_rc_exports "$TEST_DIR/.bashrc" 1
    run cat "$TEST_DIR/.bashrc"
    [ "${lines[0]}" = '# export CC_KIT_DIR="/tmp/old"  (commented out, must stay)' ]
    [ "${lines[1]}" = '# export CC_KIT_ROOT="/tmp/old"' ]
    [ "${#lines[@]}" -eq 2 ]
}

@test "rc cleanup: returns 1 when no matching lines (nothing to do)" {
    cat > "$TEST_DIR/.bashrc" <<'EOF'
export PATH="$HOME/.local/bin:$PATH"
EOF
    run _cc_kit_clean_rc_exports "$TEST_DIR/.bashrc" 1
    [ "$status" -eq 1 ]
}

@test "rc cleanup: returns 1 when file does not exist" {
    run _cc_kit_clean_rc_exports "/nonexistent/file" 1
    [ "$status" -eq 1 ]
}

@test "rc cleanup: word-boundary prevents false matches (CC_KIT_DIR_TEST)" {
    # `\<` in the regex should prevent matching `CC_KIT_DIR_TEST=...`.
    # If the boundary is broken, this test will delete the unrelated line.
    cat > "$TEST_DIR/.bashrc" <<'EOF'
export CC_KIT_DIR_TEST="/tmp/something"
export CC_KIT_ROOT="/tmp/old"
EOF
    _cc_kit_clean_rc_exports "$TEST_DIR/.bashrc" 1
    run cat "$TEST_DIR/.bashrc"
    [ "${lines[0]}" = 'export CC_KIT_DIR_TEST="/tmp/something"' ]
    [ "${#lines[@]}" -eq 1 ]
}
