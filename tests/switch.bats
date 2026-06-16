#!/usr/bin/env bats
# tests/switch.bats — Unit tests for modules/switch.sh
#
# Run: bats tests/

setup() {
    export CC_KIT_DIR="$BATS_TEST_DIRNAME/.."
    # Use a private test config dir, not real ~/.cc-kit/
    export TEST_DIR=$(mktemp -d)
    export CC_KIT_DIR="$TEST_DIR"  # override for the module
    export BASHRC_FILE="$TEST_DIR/.bashrc"
    export CONFIG_FILE="$TEST_DIR/data/provider.env"
    export SECRETS_FILE="$TEST_DIR/data/secrets.env"
    mkdir -p "$TEST_DIR/data"
    source "$BATS_TEST_DIRNAME/../modules/switch.sh"
}

teardown() {
    rm -rf "$TEST_DIR"
}

@test "mask_value: short value" {
    result=$(mask_value "abc")
    [ "$result" = "****" ]
}

@test "mask_value: long value" {
    result=$(mask_value "sk-1234567890abcdef")
    [ "$result" = "sk-1****cdef" ]
}

@test "mask_value: empty value" {
    result=$(mask_value "")
    [ "$result" = "" ]
}

@test "mask_value: 8-char value" {
    result=$(mask_value "12345678")
    [ "$result" = "****" ]
}

@test "save_secret + get_saved_key round-trip" {
    save_secret "deepseek" "sk-test-1234567890"
    result=$(get_saved_key "deepseek")
    [ "$result" = "sk-test-1234567890" ]
    # Check file permissions
    perms=$(stat -c %a "$SECRETS_FILE" 2>/dev/null || stat -f %p "$SECRETS_FILE" | tail -c 4)
    # Should be 600
    [[ "$perms" == "600" ]] || [[ "$perms" =~ 600$ ]]
}

@test "save_secret: updates existing key" {
    save_secret "deepseek" "sk-old-1234567890"
    save_secret "deepseek" "sk-new-9876543210"
    result=$(get_saved_key "deepseek")
    [ "$result" = "sk-new-9876543210" ]
    # Should not have duplicate lines
    count=$(grep -c "^export DEEPSEEK_API_KEY=" "$SECRETS_FILE")
    [ "$count" = "1" ]
}

@test "cc-switch deepseek pro writes provider.env" {
    # Pre-populate secrets
    save_secret "deepseek" "sk-test-1234567890"
    # Suppress stdout noise
    cc-switch deepseek pro >/dev/null 2>&1
    [ -f "$CONFIG_FILE" ]
    grep -q 'ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"' "$CONFIG_FILE"
    grep -q 'ANTHROPIC_MODEL="deepseek-v4-pro' "$CONFIG_FILE"
    grep -q 'ANTHROPIC_DEFAULT_HAIKU_MODEL="deepseek-v4-flash"' "$CONFIG_FILE"
}

@test "cc-switch deepseek flash writes flash model" {
    save_secret "deepseek" "sk-test-1234567890"
    cc-switch deepseek flash >/dev/null 2>&1
    grep -q 'ANTHROPIC_MODEL="deepseek-v4-flash"' "$CONFIG_FILE"
}

@test "cc-switch minimax m3 writes MiniMax-M3" {
    save_secret "minimax" "sk-test-minimax-1234567890"
    cc-switch minimax m3 >/dev/null 2>&1
    grep -q 'ANTHROPIC_BASE_URL="https://api.minimaxi.com/anthropic"' "$CONFIG_FILE"
    grep -q 'ANTHROPIC_MODEL="MiniMax-M3"' "$CONFIG_FILE"
    grep -q 'API_TIMEOUT_MS="3000000"' "$CONFIG_FILE"
}

@test "cc-switch minimax highspeed writes highspeed" {
    save_secret "minimax" "sk-test-minimax-1234567890"
    cc-switch minimax highspeed >/dev/null 2>&1
    grep -q 'ANTHROPIC_MODEL="MiniMax-M2.7-highspeed"' "$CONFIG_FILE"
}

@test "cc-switch anthropic unsets env vars" {
    cc-switch anthropic >/dev/null 2>&1
    grep -q '^unset ANTHROPIC_BASE_URL' "$CONFIG_FILE"
    grep -q '^unset ANTHROPIC_AUTH_TOKEN' "$CONFIG_FILE"
}

@test "cc-switch with unknown provider fails" {
    run cc-switch foobar
    [ "$status" -ne 0 ]
}

@test "ensure_bashrc_source: adds marker block once" {
    ensure_bashrc_source
    ensure_bashrc_source  # idempotent
    # ensure_bashrc_source writes a header comment '# cc-kit — Claude Code
    # provider switcher' followed by an if/source/fi block. Check that the
    # header appears exactly once after two calls (idempotent).
    count=$(grep -cF "# cc-kit — Claude Code provider switcher" "$BASHRC_FILE" 2>/dev/null || echo 0)
    [ "$count" = "1" ]
}

@test "cc-switch --new-key forces re-prompt" {
    save_secret "deepseek" "sk-old-1234567890"
    # Simulate a key prompt via stdin
    echo "sk-new-9876543210" | cc-switch deepseek --new-key >/dev/null 2>&1
    result=$(get_saved_key "deepseek")
    [ "$result" = "sk-new-9876543210" ]
}

@test "prompt_secret: reads from piped stdin (non-TTY)" {
    # Regression: ! cc-switch from Claude Code runs in non-TTY
    # subprocess. Old code used stty + char-by-char read which
    # silently returned empty.
    run bash -c "source '$BATS_TEST_DIRNAME/../modules/switch.sh' && \
                 printf 'sk-piped-12345678' | prompt_secret 'Enter: '"
    [ "$status" -eq 0 ]
    # $output merges stdout+stderr in bats; the secret is the last line.
    [ "${lines[-1]}" = "sk-piped-12345678" ]
}

@test "prompt_secret: empty non-TTY stdin errors clearly" {
    # Regression: Claude Code `! cc-switch` provides empty stdin
    # with no TTY. Should fail with a helpful message, not silent.
    run bash -c "source '$BATS_TEST_DIRNAME/../modules/switch.sh' && \
                 prompt_secret 'Enter: ' </dev/null"
    [ "$status" -eq 1 ]
    [[ "$output" == *"API key cannot be empty"* ]]
    [[ "$output" == *"MINIMAX_API_KEY"* ]]
    [[ "$output" == *"real terminal"* ]]
}
