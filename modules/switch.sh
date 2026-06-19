#!/usr/bin/env bash
# switch.sh — Provider/model switcher (cc-kit) provider switcher (bash function)
# Source this file from ~/.bashrc to make the "cc-switch" command available.
#
# Everything lives under $CC_KIT_DIR/data/
#   cc-switch       — this file (sourced by ~/.bashrc)
#   provider.env    — active provider config (sourced by ~/.bashrc)
#   secrets.env     — persisted API keys per provider (chmod 600)

# Self-locate the install root. switch.sh lives at <root>/modules/, so the
# install root is one level up. Falls back to $CC_KIT_DIR env var (for dev
# override) but warns to stderr on mismatch or bad path — silent overrides
# were the root cause of a real user outage.
_cc_self="${BASH_SOURCE[0]:-$0}"
while [ -L "$_cc_self" ]; do _cc_self="$(readlink -f "$_cc_self")"; done
_cc_self_dir="$(cd "$(dirname "$_cc_self")" && pwd)"
_cc_auto_root="$(cd "$_cc_self_dir/.." 2>/dev/null && pwd)"
if [ -n "${CC_KIT_DIR:-}" ]; then
  _cc_resolved="$(cd "$CC_KIT_DIR" 2>/dev/null && pwd)"
  if [ -z "$_cc_resolved" ]; then
    echo "cc-kit: WARNING: CC_KIT_DIR=$CC_KIT_DIR is not accessible; falling back to auto-detected ($_cc_auto_root)" >&2
    CC_KIT_DIR="$_cc_auto_root"
  else
    CC_KIT_DIR="$_cc_resolved"
  fi
else
  CC_KIT_DIR="$_cc_auto_root"
fi
unset _cc_self _cc_self_dir _cc_auto_root _cc_resolved

CONFIG_FILE="$CC_KIT_DIR/data/provider.env"
CONFIG_FILE="$CC_KIT_DIR/data/provider.env"
SECRETS_FILE="$CC_KIT_DIR/data/secrets.env"
# Honor BASHRC_FILE from the environment so bats tests can redirect the
# "user bashrc" into a private temp file. Without this fallback, ensure_bashrc_source
# would pollute the developer's real ~/.bashrc every time tests run.
BASHRC_FILE="${BASHRC_FILE:-$HOME/.bashrc}"

mkdir -p "$CC_KIT_DIR"

mask_value() {
  local value="${1:-}"
  if [[ -z "$value" ]]; then
    echo ""
  elif [[ ${#value} -le 8 ]]; then
    echo "****"
  else
    echo "${value:0:4}****${value: -4}"
  fi
}

ensure_bashrc_source() {
  local old_marker='source "$HOME/.claude/model-provider.env"'
  local header='# cc-kit — Claude Code provider switcher'

  # Migrate old-style block (if present) — single shot, then it never returns.
  if grep -Fq "$old_marker" "$BASHRC_FILE" 2>/dev/null; then
    sed -i "\|$old_marker|d" "$BASHRC_FILE"
    sed -i '/^# Claude Code model provider switcher$/d' "$BASHRC_FILE"
    sed -i '/^if \[ -f "\$HOME\/.claude\/model-provider.env" \]; then$/d' "$BASHRC_FILE"
    sed -i '/^  source "\$HOME\/.claude\/model-provider.env"$/d' "$BASHRC_FILE"
    sed -i '/^fi$/d' "$BASHRC_FILE"
  fi

  # Dedupe by header comment, not by path. Earlier versions checked for the
  # exact source-line marker, which didn't catch blocks from prior cc-switch
  # invocations against other CC_KIT_ROOT / MONITOR_DATA_DIR values (e.g. test
  # runs). Result: a brand-new block was appended on every switch, accumulating
  # dozens of stale entries pointing at deleted /tmp/tmp.XXXX paths.
  #
  # Strategy: delete EVERY existing cc-kit provider-switcher block (header +
  # the 3-line if/source/fi body), then append exactly one fresh block. Idempotent.
  if grep -Fq "$header" "$BASHRC_FILE" 2>/dev/null; then
    local tmpfile
    tmpfile="$(mktemp)"
    awk -v hdr="$header" '
      $0 == hdr { skip = 3; next }   # skip header + next 3 lines (the block body)
      skip > 0    { skip--; next }    # ...continuing to skip
                { print }
    ' "$BASHRC_FILE" > "$tmpfile" && mv "$tmpfile" "$BASHRC_FILE"
  fi

  # Append exactly one fresh block pointing at the current install dir.
  {
    echo ""
    echo "$header"
    echo "if [ -f \"${CC_KIT_DIR}/data/provider.env\" ]; then"
    echo "  source \"${CC_KIT_DIR}/data/provider.env\""
    echo "fi"
  } >> "$BASHRC_FILE"
}

load_secrets() {
  if [[ -f "$SECRETS_FILE" ]]; then
    source "$SECRETS_FILE"
  fi
}

save_secret() {
  local provider="$1"
  local key="$2"
  local var_name
  var_name="$(echo "$provider" | tr '[:lower:]' '[:upper:]')_API_KEY"

  if [[ -f "$SECRETS_FILE" ]]; then
    if grep -q "^export ${var_name}=" "$SECRETS_FILE" 2>/dev/null; then
      local tmpfile
      tmpfile="$(mktemp)"
      # Escape forward slashes for sed's s/.../.../ delimiter. We pipe the
      # key through sed (rather than using bash's ${key//\//\\/} expansion)
      # because the latter is bash 4+ syntax; macOS still ships bash 3.2 by
      # default and we want this to work on Ubuntu (bash 5.x) AND macOS (3.2).
      local escaped_key
      escaped_key="$(printf '%s' "$key" | sed 's:/:\\/:g')"
      sed "s|^export ${var_name}=.*|export ${var_name}=\"${escaped_key}\"|" "$SECRETS_FILE" > "$tmpfile"
      mv "$tmpfile" "$SECRETS_FILE"
    else
      echo "export ${var_name}=\"$key\"" >> "$SECRETS_FILE"
    fi
  else
    echo "# cc-switch persisted API keys" > "$SECRETS_FILE"
    echo "export ${var_name}=\"$key\"" >> "$SECRETS_FILE"
  fi

  chmod 600 "$SECRETS_FILE"
}

get_saved_key() {
  local provider="$1"
  local var_name
  var_name="$(echo "$provider" | tr '[:lower:]' '[:upper:]')_API_KEY"

  load_secrets
  echo "${!var_name:-}"
}

prompt_secret() {
  local prompt="$1"
  local secret=""

  printf '%s' "$prompt" >&2

  # Two read paths, picked by environment:
  #
  # 1. stdin is a TTY (interactive terminal)
  #    → masked char-by-char prompt with stty echo control
  #
  # 2. stdin is not a TTY (e.g. `printf KEY | cc-switch ...`,
  #    or Claude Code `! cc-switch` which gives an empty pipe)
  #    → silent line read with `read -r -s`. Works in both
  #    pipe-with-data and pipe-empty cases; the latter will leave
  #    $secret empty and we error with a clear message below.
  #
  # Note: we deliberately do NOT fall back to /dev/tty. Claude Code's
  # `!` commands run with no controlling terminal, so /dev/tty opens
  # with ENXIO. Worse, `[ -r /dev/tty ]` returns true even when the
  # open would fail — using it as a guard is misleading.
  if [ -t 0 ]; then
    local char
    stty -echo
    while IFS= read -r -n1 char; do
      if [[ -z "$char" ]]; then
        break
      fi
      if [[ "$char" == $'\x7f' || "$char" == $'\b' ]]; then
        if [[ -n "$secret" ]]; then
          secret="${secret%?}"
          printf '\b \b' >&2
        fi
        continue
      fi
      secret+="$char"
      printf '*' >&2
    done
    stty echo
    printf '\n' >&2
  else
    # Non-interactive: read whatever's on stdin, silently. If stdin
    # is empty (Claude Code `! cc-switch`), $secret will be empty
    # and the message below tells the user how to provide the key.
    read -r -s secret || true
    printf '\n' >&2
  fi

  if [[ -z "$secret" ]]; then
    echo "API key cannot be empty." >&2
    echo "Set the API key via one of:" >&2
    echo "  export MINIMAX_API_KEY='...your-key...'" >&2
    echo "  printf '%s' '...your-key...' | cc-switch minimax" >&2
    echo "Or run cc-switch from a real terminal." >&2
    return 1
  fi
  printf '%s' "$secret"
}

resolve_key() {
  local provider="$1"
  local force_new="${2:-false}"
  local saved_key

  saved_key="$(get_saved_key "$provider")"

  if [[ "$force_new" != "true" && -n "$saved_key" ]]; then
    echo "Using saved ${provider} API key: $(mask_value "$saved_key")" >&2
    printf '%s' "$saved_key"
    return 0
  fi

  if [[ "$force_new" == "true" && -n "$saved_key" ]]; then
    echo "Replacing saved ${provider} API key: $(mask_value "$saved_key")" >&2
  fi

  local key
  key="$(prompt_secret "Enter ${provider} API key: ")" || return 1
  save_secret "$provider" "$key"
  printf '%s' "$key"
}

cc-switch() {
  local provider="${1:-}"
  local force_new="false"
  local key
  local model="" main_model sub_model model_label

  # Parse extra args: model name or --new-key (order doesn't matter)
  for arg in "${@:2}"; do
    case "$arg" in
      --new-key|-n) force_new="true" ;;
      pro|flash|m2.7|m2-7|highspeed|m3) model="$arg" ;;
      *)
        echo "Unknown option: $arg" >&2
        return 1
        ;;
    esac
  done

  # Resolve model defaults & map to actual model IDs
  case "$provider" in
    deepseek)
      case "${model:-pro}" in
        pro)    main_model="deepseek-v4-pro[1m]"; sub_model="deepseek-v4-flash";  model_label="pro" ;;
        flash)  main_model="deepseek-v4-flash";    sub_model="deepseek-v4-flash"; model_label="flash" ;;
      esac
      ;;
    minimax)
      case "${model:-m2.7}" in
        m2.7|m2-7) main_model="MiniMax-M2.7";           sub_model="MiniMax-M2.7-highspeed"; model_label="M2.7" ;;
        highspeed)  main_model="MiniMax-M2.7-highspeed"; sub_model="MiniMax-M2.7-highspeed"; model_label="M2.7-highspeed" ;;
        m3)         main_model="MiniMax-M3";             sub_model="MiniMax-M2.7-highspeed"; model_label="M3" ;;
      esac
      ;;
  esac

  case "$provider" in
    deepseek)
      key="$(resolve_key "deepseek" "$force_new")" || return 1
      cat > "$CONFIG_FILE" <<EOF
# Generated by cc-switch
# Provider: DeepSeek  Model: ${model_label}
export ANTHROPIC_BASE_URL="https://api.deepseek.com/anthropic"
export ANTHROPIC_AUTH_TOKEN="$key"
export ANTHROPIC_MODEL="$main_model"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$main_model"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$main_model"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$sub_model"
export CLAUDE_CODE_SUBAGENT_MODEL="$sub_model"
export CLAUDE_CODE_EFFORT_LEVEL="max"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
EOF
      chmod 600 "$CONFIG_FILE"
      ensure_bashrc_source
      echo "✓ Switched to DeepSeek (${model_label})."
      # Refresh balance cache so statusLine shows fresh number, not the
      # previous provider's stale balance.
      _cc_switch_refresh_balance
      ;;

    minimax)
      key="$(resolve_key "minimax" "$force_new")" || return 1
      cat > "$CONFIG_FILE" <<EOF
# Generated by cc-switch
# Provider: MiniMax  Model: ${model_label}
export ANTHROPIC_BASE_URL="https://api.minimaxi.com/anthropic"
export ANTHROPIC_AUTH_TOKEN="$key"
export ANTHROPIC_MODEL="$main_model"
export ANTHROPIC_DEFAULT_OPUS_MODEL="$main_model"
export ANTHROPIC_DEFAULT_SONNET_MODEL="$main_model"
export ANTHROPIC_DEFAULT_HAIKU_MODEL="$sub_model"
export CLAUDE_CODE_SUBAGENT_MODEL="$sub_model"
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC="1"
export API_TIMEOUT_MS="3000000"
export CLAUDE_CODE_AUTO_COMPACT_WINDOW="512000"
EOF
      chmod 600 "$CONFIG_FILE"
      ensure_bashrc_source
      echo "✓ Switched to MiniMax (${model_label})."
      _cc_switch_refresh_balance
      ;;

    anthropic)
      cat > "$CONFIG_FILE" <<'EOF'
# Generated by cc-switch
# Provider: Anthropic default
unset ANTHROPIC_BASE_URL
unset ANTHROPIC_AUTH_TOKEN
unset ANTHROPIC_MODEL
unset ANTHROPIC_DEFAULT_OPUS_MODEL
unset ANTHROPIC_DEFAULT_SONNET_MODEL
unset ANTHROPIC_DEFAULT_HAIKU_MODEL
unset CLAUDE_CODE_SUBAGENT_MODEL
unset CLAUDE_CODE_EFFORT_LEVEL
unset CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC
EOF
      chmod 600 "$CONFIG_FILE"
      ensure_bashrc_source
      echo "✓ Restored to Anthropic default."
      ;;

    show)
      if [[ -f "$CONFIG_FILE" ]]; then
        source "$CONFIG_FILE"
      fi
      echo "Current Claude Code provider environment:"
      echo "ANTHROPIC_BASE_URL=${ANTHROPIC_BASE_URL:-}"
      echo "ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-}"
      echo "ANTHROPIC_DEFAULT_OPUS_MODEL=${ANTHROPIC_DEFAULT_OPUS_MODEL:-}"
      echo "ANTHROPIC_DEFAULT_SONNET_MODEL=${ANTHROPIC_DEFAULT_SONNET_MODEL:-}"
      echo "ANTHROPIC_DEFAULT_HAIKU_MODEL=${ANTHROPIC_DEFAULT_HAIKU_MODEL:-}"
      echo "CLAUDE_CODE_SUBAGENT_MODEL=${CLAUDE_CODE_SUBAGENT_MODEL:-}"
      echo "CLAUDE_CODE_EFFORT_LEVEL=${CLAUDE_CODE_EFFORT_LEVEL:-}"
      echo "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=${CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC:-}"
      echo "ANTHROPIC_AUTH_TOKEN=$(mask_value "${ANTHROPIC_AUTH_TOKEN:-}")"
      echo "Config file: $CONFIG_FILE"
      if [[ -f "$SECRETS_FILE" ]]; then
        echo ""
        echo "Saved API keys:"
        load_secrets
        echo "  DeepSeek: $(mask_value "${DEEPSEEK_API_KEY:-}")"
        echo "  MiniMax:  $(mask_value "${MINIMAX_API_KEY:-}")"
      fi
      return 0
      ;;

    -h|--help|help|"")
      cat <<'EOF'
Usage:
  cc-switch deepseek [pro|flash]           Switch to DeepSeek (default: pro)
  cc-switch minimax [m2.7|highspeed|m3]    Switch to MiniMax (default: m2.7)
  cc-switch anthropic                      Restore official Anthropic default
  cc-switch show                           Show current provider config
  cc-switch <provider> <model> --new-key   Force re-enter API key

DeepSeek models:
  pro     deepseek-v4-pro[1m] (main)  + deepseek-v4-flash (subagent)
  flash   deepseek-v4-flash (main)    + deepseek-v4-flash (subagent)

MiniMax models:
  m2.7       MiniMax-M2.7 (main)          + MiniMax-M2.7-highspeed (subagent)
  highspeed  MiniMax-M2.7-highspeed (main) + MiniMax-M2.7-highspeed (subagent)
  m3         MiniMax-M3 (main)            + MiniMax-M2.7-highspeed (subagent)

Notes:
  - API keys persist in \$CC_KIT_DIR/data/secrets.env
  - Switching back to a used provider reuses the saved key
  - Use --new-key to replace a saved key
  - bashrc is sourced automatically after switching
EOF
      return 0
      ;;

    *)
      echo "Unknown provider: $provider" >&2
      echo "Usage: cc-switch [deepseek|minimax|anthropic|show]" >&2
      return 1
      ;;
  esac

  # Auto-source bashrc to apply changes immediately
  if [[ -f "$BASHRC_FILE" ]]; then
    source "$BASHRC_FILE"
  fi
}

# Refresh balance for the current provider (called after cc-switch).
# Always invokes cc-balance in the background; never blocks the switch.
_cc_switch_refresh_balance() {
  local bin="$CC_KIT_DIR/bin/cc-balance"
  if [[ -x "$bin" ]]; then
    ( "$bin" auto >/dev/null 2>&1 & )
  fi
}
