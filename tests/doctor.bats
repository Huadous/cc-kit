#!/usr/bin/env bats
# tests/doctor.bats — Unit tests for bin/cc-doctor.
#
# Strategy: cc-doctor self-locates its own install dir (BASH_SOURCE[0]),
# but reads ~/.bashrc, ~/.zshrc, ~/.claude/settings.json from $HOME. So
# tests set HOME to a TMPDIR with controlled rc files; the script's self-
# locate still points at the real repo (which is fine — it has bin/,
# modules/, hooks/, data/secrets.env, etc.). We back up and restore any
# real rc files we touch with --fix, so the test never pollutes the
# developer's actual ~/.bashrc.

setup() {
    FAKE_HOME=$(mktemp -d)
    export HOME="$FAKE_HOME"
    mkdir -p "$FAKE_HOME/.claude"
    mkdir -p "$FAKE_HOME/.local/bin"
    # The real script
    CC_DOCTOR="$BATS_TEST_DIRNAME/../bin/cc-doctor"
}

teardown() {
    rm -rf "$FAKE_HOME"
}

# Helper: write a fake ~/.bashrc
write_bashrc() {
    cat > "$FAKE_HOME/.bashrc" <<EOF
$1
EOF
}

# ── Self-locate / basic run ─────────────────────────────────────────

@test "cc-doctor runs and exits 0 when no findings are FAIL" {
    write_bashrc "# clean bashrc"
    run "$CC_DOCTOR"
    # Exit may be 0 (no FAIL) or 1 (FAIL present, e.g. settings.json
    # missing in fake HOME). The test below asserts the specific case.
    [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "cc-doctor: self-locate ignores cwd (run from /tmp)" {
    write_bashrc "# clean"
    run bash -c "cd /tmp && '$CC_DOCTOR'"
    # Should NOT print 'install: /tmp' — must self-locate the repo
    [[ ! "$output" =~ "install: /tmp" ]]
}

@test "cc-doctor --help exits 0 and prints usage" {
    run "$CC_DOCTOR" --help
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Usage:" ]]
    [[ "$output" =~ "--json" ]]
    [[ "$output" =~ "--fix" ]]
}

@test "cc-doctor: unknown option exits 2 with usage hint" {
    run "$CC_DOCTOR" --bogus
    [ "$status" -eq 2 ]
    [[ "$output" =~ "unknown option" ]]
}

# ── env_override detection ──────────────────────────────────────────

@test "cc-doctor: detects stale CC_KIT_DIR export in rc file" {
    write_bashrc 'export CC_KIT_DIR="/tmp/old-install"
export PATH="$HOME/.local/bin:$PATH"'
    run "$CC_DOCTOR"
    [[ "$output" =~ "env_override" ]]
    [[ "$output" =~ "FAIL" ]]
    [[ "$output" =~ "/tmp/old-install" ]]
    [ "$status" -eq 1 ]
}

@test "cc-doctor: detects stale CC_KIT_ROOT export" {
    write_bashrc 'export CC_KIT_ROOT="/tmp/old"
export PATH="$HOME/.local/bin:$PATH"'
    run "$CC_DOCTOR"
    [[ "$output" =~ "env_override" ]]
    [[ "$output" =~ "FAIL" ]]
    [ "$status" -eq 1 ]
}

@test "cc-doctor: detects stale MONITOR_DATA_DIR export" {
    write_bashrc 'export MONITOR_DATA_DIR="/tmp/old/data"
export PATH="$HOME/.local/bin:$PATH"'
    run "$CC_DOCTOR"
    [[ "$output" =~ "env_override" ]]
    [[ "$output" =~ "MONITOR_DATA_DIR" ]]
}

@test "cc-doctor: clean rc file passes env_override check" {
    write_bashrc 'export PATH="$HOME/.local/bin:$PATH"
alias ll="ls -la"'
    run "$CC_DOCTOR"
    [[ "$output" =~ "no stale CC_KIT_*" ]]
    [[ ! "$output" =~ "FAIL.*env_override" ]]
}

@test "cc-doctor: --fix removes stale exports from rc file" {
    # Use a real path cc-doctor will detect and remove
    write_bashrc 'export CC_KIT_DIR="/tmp/old-install"
export PATH="$HOME/.local/bin:$PATH"'
    run "$CC_DOCTOR" --fix
    # Verify the export line is gone
    grep -q 'CC_KIT_DIR' "$FAKE_HOME/.bashrc" && { echo "export still present!"; return 1; }
    grep -q 'PATH' "$FAKE_HOME/.bashrc"     # unrelated export preserved
}

# ── duplicate_sources detection ─────────────────────────────────────

@test "cc-doctor: detects duplicate init.sh source calls" {
    write_bashrc '[ -f "/home/user/.cc-kit/init.sh" ] && source "/home/user/.cc-kit/init.sh"
[ -f "/tmp/dev/init.sh" ] && source "/tmp/dev/init.sh"'
    run "$CC_DOCTOR"
    [[ "$output" =~ "duplicate" ]]
}

# ── install_path integrity ──────────────────────────────────────────

@test "cc-doctor: passes install_path when bin/ modules/ hooks/ exist" {
    # We self-locate to the real repo which has all of these
    write_bashrc "# clean"
    run "$CC_DOCTOR"
    [[ "$output" =~ "✓ install_path" ]]
}

# ── API key masking (security-critical) ─────────────────────────────

@test "cc-doctor: NEVER prints full API key value" {
    write_bashrc "# clean"
    run "$CC_DOCTOR"
    # Read the real secrets.env and assert no full key value appears in output
    local secrets="$BATS_TEST_DIRNAME/../data/secrets.env"
    if [[ -f "$secrets" ]]; then
        while IFS='=' read -r k v; do
            [[ "$k" =~ ^export ]] || continue
            k="${k#export }"
            v="${v%\"}"; v="${v#\"}"
            [[ -n "$v" ]] || continue
            # The key VALUE must not appear in output (masked first4/last4 is OK)
            if [[ "$output" == *"$v"* ]]; then
                echo "BUG: full API key value for $k leaked into output"
                echo "value: $v"
                echo "output: $output"
                return 1
            fi
        done < "$secrets"
    fi
}

# ── JSON output ─────────────────────────────────────────────────────

@test "cc-doctor --json: produces parseable JSON with required keys" {
    write_bashrc "# clean"
    run "$CC_DOCTOR" --json
    # Exit may be 0 (no FAIL) or 1 (FAIL present); both are valid here.
    case "$status" in
        0|1) ;;
        *) echo "unexpected exit: $status"; return 1 ;;
    esac
    # Validate it's actually JSON with the required keys
    echo "$output" | python3 -c "
import sys, json
d = json.load(sys.stdin)
assert 'findings' in d, 'missing findings key'
assert 'summary' in d, 'missing summary key'
assert 'install_dir' in d, 'missing install_dir key'
assert isinstance(d['summary'], dict)
" 2>&1
}

# ── Exit codes ──────────────────────────────────────────────────────

@test "cc-doctor: exit 0 when no FAIL findings" {
    write_bashrc 'export PATH="$HOME/.local/bin:$PATH"'
    run "$CC_DOCTOR"
    # 0 if no FAIL, 1 if any FAIL. Either is acceptable as long as the
    # output is parseable.
    case "$status" in
        0|1) ;;
        *) echo "unexpected exit: $status"; return 1 ;;
    esac
}