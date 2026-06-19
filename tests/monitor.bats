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

@test "monitor_provider_label: GLM 4.7" {
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/provider.env" <<'EOF'
export ANTHROPIC_BASE_URL="https://open.bigmodel.cn/api/anthropic"
export ANTHROPIC_MODEL="glm-4.7"
EOF
    MONITOR_DATA_DIR="$TMPDIR"
    result=$(monitor_provider_label)
    [ "$result" = "GLM-4.7" ]
    rm -rf "$TMPDIR"
}

@test "monitor_provider_label: GLM 5.1" {
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/provider.env" <<'EOF'
export ANTHROPIC_BASE_URL="https://open.bigmodel.cn/api/anthropic"
export ANTHROPIC_MODEL="glm-5.1"
EOF
    MONITOR_DATA_DIR="$TMPDIR"
    result=$(monitor_provider_label)
    [ "$result" = "GLM-5.1" ]
    rm -rf "$TMPDIR"
}

@test "monitor_provider_label: GLM flash" {
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/provider.env" <<'EOF'
export ANTHROPIC_BASE_URL="https://open.bigmodel.cn/api/anthropic"
export ANTHROPIC_MODEL="glm-4.7-flash"
EOF
    MONITOR_DATA_DIR="$TMPDIR"
    result=$(monitor_provider_label)
    [ "$result" = "GLM-flash" ]
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

@test "monitor_coding_plan_remaining: extracts from 5h cache format" {
    # "5h:4h02m" → "4h02m" (no cache file → no mtime adjustment)
    result=$(monitor_coding_plan_remaining "91%  5h:4h02m  wk:100%" "")
    [ "$result" = "4h02m" ]
}

@test "monitor_coding_plan_remaining: empty when no 5h fragment" {
    # DeepSeek-style pay-as-you-go (no time window) → empty
    result=$(monitor_coding_plan_remaining "30.77 CNY" "")
    [ -z "$result" ]
}

@test "monitor_coding_plan_remaining: empty for non-coding-plan pct format" {
    # Coding plan with stale or unknown format → empty (falls back to "5h" label)
    result=$(monitor_coding_plan_remaining "91%  something_weird  wk:100%" "")
    [ -z "$result" ]
}

@test "monitor_coding_plan_remaining: subtracts cache age" {
    # Cache file written 60 seconds ago, value says "4h02m" remaining →
    # real remaining is 4h02m - 60s = 4h01m. Pass the cache file path so
    # the helper can read mtime.
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/cache" <<'EOF'
91%  5h:4h02m  wk:100%
EOF
    # Sleep 2s so mtime is reliably "in the past" (BATS mtime resolution)
    sleep 2
    result=$(monitor_coding_plan_remaining "91%  5h:4h02m  wk:100%" "$TMPDIR/cache")
    # Result should be 4h01m or 4h00m depending on timing; the point is
    # it's NOT 4h02m (which would mean we ignored cache age).
    [[ "$result" =~ ^4h0[01]m$ ]]
    rm -rf "$TMPDIR"
}

@test "monitor_coding_plan_remaining: returns 0m when window has expired" {
    # Cache says "0h01m" remaining but the cache is 5 minutes old, so
    # real remaining is negative → clamp to 0m.
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/cache" <<'EOF'
91%  5h:0h01m  wk:100%
EOF
    sleep 2
    result=$(monitor_coding_plan_remaining "91%  5h:0h01m  wk:100%" "$TMPDIR/cache")
    [ "$result" = "0m" ]
    rm -rf "$TMPDIR"
}

@test "monitor_coding_plan_remaining: drops h prefix when under 1h" {
    # 0h42m → "42m" (more compact for short windows)
    result=$(monitor_coding_plan_remaining "91%  5h:0h42m  wk:100%" "")
    [ "$result" = "42m" ]
}

@test "monitor_balance_label: coding-plan format with remaining" {
    TMPDIR=$(mktemp -d)
    cat > "$TMPDIR/cache" <<'EOF'
91%  5h:4h02m  wk:100%
EOF
    # No ¥ prefix — the percentage IS the unit, not a monetary amount.
    result=$(monitor_balance_label "91%  5h:4h02m  wk:100%" "¥" "$TMPDIR/cache")
    [ "$result" = "91%  4h02m" ]
    rm -rf "$TMPDIR"
}

@test "monitor_balance_label: pay-as-you-go format" {
    result=$(monitor_balance_label "30.77 CNY" "¥")
    [ "$result" = "¥30.77 CNY" ]
}

@test "monitor_balance_label: empty when no balance" {
    result=$(monitor_balance_label "" "¥")
    [ -z "$result" ]
}

@test "monitor_balance_label: empty when balance is 0.00" {
    result=$(monitor_balance_label "0.00" "¥")
    [ -z "$result" ]
}

@test "monitor_balance_label: coding-plan falls back to 5h when no remaining fragment" {
    # Older cache format: just "91%  wk:100%" without a 5h:HHhMMm fragment
    result=$(monitor_balance_label "91%  wk:100%" "¥")
    [ "$result" = "91% 5h" ]
}

@test "monitor_balance_label: respects currency override on pay-as-you-go only" {
    # Pay-as-you-go with $ override
    result=$(monitor_balance_label "10.00 USD" "\$")
    [ "$result" = "\$10.00 USD" ]
}

@test "monitor_coding_plan_remaining: handles minutes with leading zero (08/09)" {
    # Regression: bash treats "08"/"09" as octal and dies with
    # "value too great for base (error token is "08")" because
    # 8/9 are not valid octal digits. The fix forces base 10 with 10#.
    result=$(monitor_coding_plan_remaining "91%  5h:4h08m  wk:100%" "")
    [ "$result" = "4h08m" ]
    result=$(monitor_coding_plan_remaining "91%  5h:4h09m  wk:100%" "")
    [ "$result" = "4h09m" ]
    result=$(monitor_coding_plan_remaining "91%  5h:0h08m  wk:100%" "")
    [ "$result" = "8m" ]
}
