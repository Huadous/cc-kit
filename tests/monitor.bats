#!/usr/bin/env bats
# tests/monitor.bats — Unit tests for modules/monitor.sh
#
# Run: bats tests/

setup() {
    export CC_KIT_DIR="$BATS_TEST_DIRNAME/.."
    # Source the module fresh for each test
    source "$CC_KIT_DIR/modules/monitor.sh"
}

@test "monitor_fmt_num formats small numbers" {
    result=$(monitor_fmt_num 42)
    [ "$result" = "42" ]
}

@test "monitor_fmt_num formats thousands" {
    result=$(monitor_fmt_num 1234)
    [ "$result" = "1.2k" ]
}

@test "monitor_fmt_num formats millions" {
    result=$(monitor_fmt_num 1234567)
    [ "$result" = "1.2M" ]
}

@test "monitor_fmt_num handles zero" {
    result=$(monitor_fmt_num 0)
    [ "$result" = "0" ]
}

@test "monitor_provider_label: deepseek pro" {
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/provider.env" <<'EOF'
export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
export ANTHROPIC_MODEL="deepseek-v4-pro"
EOF
    MONITOR_DATA_DIR="$TMPDIR"
    result=$(monitor_provider_label)
    [ "$result" = "DS-pro" ]
    rm -rf "$TMPDIR"
}

@test "monitor_provider_label: deepseek flash" {
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/provider.env" <<'EOF'
export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
export ANTHROPIC_MODEL="deepseek-v4-flash"
EOF
    MONITOR_DATA_DIR="$TMPDIR"
    result=$(monitor_provider_label)
    [ "$result" = "DS-flash" ]
    rm -rf "$TMPDIR"
}

@test "monitor_provider_label: minimax M3" {
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/provider.env" <<'EOF'
export ANTHROPIC_BASE_URL="https://api.minimaxi.com/anthropic"
export ANTHROPIC_MODEL="MiniMax-M3"
EOF
    MONITOR_DATA_DIR="$TMPDIR"
    result=$(monitor_provider_label)
    [ "$result" = "MM-m3" ]
    rm -rf "$TMPDIR"
}

@test "monitor_provider_label: minimax highspeed" {
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/provider.env" <<'EOF'
export ANTHROPIC_BASE_URL="https://api.minimaxi.com/anthropic"
export ANTHROPIC_MODEL="MiniMax-M2.7-highspeed"
EOF
    MONITOR_DATA_DIR="$TMPDIR"
    result=$(monitor_provider_label)
    [ "$result" = "MM-hs" ]
    rm -rf "$TMPDIR"
}

@test "monitor_provider_label: anthropic default" {
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/provider.env" <<'EOF'
unset ANTHROPIC_BASE_URL
export ANTHROPIC_MODEL="claude-opus-4-8"
EOF
    MONITOR_DATA_DIR="$TMPDIR"
    result=$(monitor_provider_label)
    [ "$result" = "AN" ]
    rm -rf "$TMPDIR"
}

@test "monitor_currency: chinese provider" {
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/provider.env" <<'EOF'
export ANTHROPIC_BASE_URL="https://api.minimaxi.com/anthropic"
EOF
    MONITOR_DATA_DIR="$TMPDIR"
    result=$(monitor_currency)
    [ "$result" = "¥" ]
    rm -rf "$TMPDIR"
}

@test "monitor_currency: anthropic default" {
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/provider.env" <<'EOF'
unset ANTHROPIC_BASE_URL
EOF
    MONITOR_DATA_DIR="$TMPDIR"
    result=$(monitor_currency)
    [ "$result" = "\$" ]
    rm -rf "$TMPDIR"
}

@test "monitor_pricing: deepseek pro" {
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/provider.env" <<'EOF'
export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
export ANTHROPIC_MODEL="deepseek-v4-pro"
EOF
    MONITOR_DATA_DIR="$TMPDIR"
    result=$(monitor_pricing)
    [ "$result" = "2.0 0.2 8.0" ]
    rm -rf "$TMPDIR"
}

@test "monitor_pricing: deepseek flash" {
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/provider.env" <<'EOF'
export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
export ANTHROPIC_MODEL="deepseek-v4-flash"
EOF
    MONITOR_DATA_DIR="$TMPDIR"
    result=$(monitor_pricing)
    [ "$result" = "1.0 0.1 4.0" ]
    rm -rf "$TMPDIR"
}

@test "monitor_parse_session: sums tokens from JSONL" {
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/session.jsonl" <<'EOF'
{"type":"assistant","message":{"usage":{"input_tokens":100,"output_tokens":50}}}
{"type":"assistant","message":{"usage":{"input_tokens":200,"output_tokens":75,"cache_read_input_tokens":1000}}}
EOF
    result=$(monitor_parse_session "$TMPDIR/session.jsonl")
    # input=300 output=125 cache_read=1000 cache_creation=0 total=425
    expected="300 125 1000 0 425"
    [ "$result" = "$expected" ]
    rm -rf "$TMPDIR"
}

@test "monitor_parse_session: missing file returns zeros" {
    result=$(monitor_parse_session "/nonexistent/file.jsonl")
    [ "$result" = "0 0 0 0 0" ]
}

@test "monitor_find_session: uses CLAUDE_CODE_SESSION_ID when set" {
    TMPDIR=$(mktemp -d)
    mkdir -p "$HOME/.claude/projects/-test"
    SESSION="abc12345-6789-0abc-def0-123456789abc"
    echo '{}' > "$HOME/.claude/projects/-test/${SESSION}.jsonl"
    CLAUDE_CODE_SESSION_ID="$SESSION" result=$(CLAUDE_CODE_SESSION_ID="$SESSION" monitor_find_session)
    [ "$result" = "$HOME/.claude/projects/-test/${SESSION}.jsonl" ]
    rm -f "$HOME/.claude/projects/-test/${SESSION}.jsonl"
    rmdir "$HOME/.claude/projects/-test" 2>/dev/null || true
    rm -rf "$TMPDIR"
}

@test "monitor_hit_rate: 100% when all cached" {
    # input=0 cache_read=100 → 100% hit
    awk 'BEGIN { printf "0 0 100 0 100\n" }' > /tmp/stats_test
    result=$(monitor_stats_line() { cat /tmp/stats_test; }; monitor_hit_rate)
    [ "$result" = "100" ]
    rm -f /tmp/stats_test
}

@test "monitor_cached_balance: returns cached value when fresh" {
    TMPDIR=$(mktemp -d)
    MONITOR_DATA_DIR="$TMPDIR" echo "50.00 CNY" > "$TMPDIR/.balance_cache"
    MONITOR_DATA_DIR="$TMPDIR" result=$(MONITOR_DATA_DIR="$TMPDIR" monitor_cached_balance)
    [ "$result" = "50.00 CNY" ]
    rm -rf "$TMPDIR"
}

@test "monitor_cached_balance: empty when no cache file" {
    TMPDIR=$(mktemp -d)
    MONITOR_DATA_DIR="$TMPDIR" result=$(MONITOR_DATA_DIR="$TMPDIR" monitor_cached_balance)
    [ -z "$result" ]
    rm -rf "$TMPDIR"
}
