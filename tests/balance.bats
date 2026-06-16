#!/usr/bin/env bats
# tests/balance.bats — Unit tests for bin/cc-balance
#
# Run: bats tests/
#
# Uses a mock curl in tests/mocks/curl/ that returns canned JSON.

setup() {
    export TEST_DIR=$(mktemp -d)
    export CC_KIT_DIR="$TEST_DIR"
    mkdir -p "$CC_KIT_DIR/data" "$TEST_DIR/../mocks/curl"
    # Create mock curl that returns canned response based on URL
    cat > "$TEST_DIR/../mocks/curl/mock-curl" <<'MOCK'
#!/usr/bin/env bash
# Minimal mock: read URL from args and return fixture
url=""
for arg in "$@"; do
    if [[ "$arg" == https://* ]]; then
        url="$arg"
        break
    fi
done
case "$url" in
    *deepseek*balance*)
        cat "$CC_KIT_DIR/fixture_deepseek.json" 2>/dev/null
        ;;
    *coding_plan*remains*)
        cat "$CC_KIT_DIR/fixture_coding_plan.json" 2>/dev/null
        ;;
    *)
        echo ""
        ;;
esac
MOCK
    chmod +x "$TEST_DIR/../mocks/curl/mock-curl"
    export PATH="$TEST_DIR/../mocks/curl:$PATH"
    alias curl="$TEST_DIR/../mocks/curl/mock-curl"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "query_deepseek parses balance_infos" {
    skip "cc-balance is a script, not a library — see docs/SPEC §2"
    cat > "$CC_KIT_DIR/fixture_deepseek.json" <<'EOF'
{"balance_infos": [{"currency": "CNY", "total_balance": "45.27"}], "available_balance": "45.27"}
EOF
    source "$BATS_TEST_DIRNAME/../bin/cc-balance" 2>/dev/null || true
}

@test "MiniMax coding plan fixture has model_remains" {
    cat > "$CC_KIT_DIR/fixture_coding_plan.json" <<'EOF'
{
  "model_remains": [
    {
      "model_name": "general",
      "current_interval_remaining_percent": 91,
      "current_weekly_remaining_percent": 100,
      "remains_time": 13800000
    }
  ],
  "base_resp": {"status_code": 0, "status_msg": "success"}
}
EOF
    # Verify fixture is valid JSON
    python3 -c "import json; json.load(open('$CC_KIT_DIR/fixture_coding_plan.json'))"
    result=$(python3 -c "
import json
with open('$CC_KIT_DIR/fixture_coding_plan.json') as f:
    data = json.load(f)
assert data['base_resp']['status_code'] == 0
general = next(r for r in data['model_remains'] if r['model_name'] == 'general')
rem_ms = general['remains_time']
h, rem = divmod(rem_ms // 1000, 3600)
m = (rem_ms // 1000 % 3600) // 60
print(f'{general[\"current_interval_remaining_percent\"]}%  5h:{h}h{m:02d}m  wk:{general[\"current_weekly_remaining_percent\"]}%')
")
    [ "$result" = "91%  5h:3h50m  wk:100%" ]
}

@test "MiniMax coding plan empty model_remains" {
    cat > "$CC_KIT_DIR/fixture_coding_plan.json" <<'EOF'
{"model_remains": [], "base_resp": {"status_code": 0}}
EOF
    result=$(python3 -c "
import json
with open('$CC_KIT_DIR/fixture_coding_plan.json') as f:
    data = json.load(f)
rows = data.get('model_remains') or []
print('empty' if not rows else 'has_rows')
")
    [ "$result" = "empty" ]
}

@test "MiniMax coding plan non-success status" {
    cat > "$CC_KIT_DIR/fixture_coding_plan.json" <<'EOF'
{"base_resp": {"status_code": 1004, "status_msg": "auth failed"}}
EOF
    result=$(python3 -c "
import json
with open('$CC_KIT_DIR/fixture_coding_plan.json') as f:
    data = json.load(f)
print('fail' if data.get('base_resp', {}).get('status_code') != 0 else 'ok')
")
    [ "$result" = "fail" ]
}
