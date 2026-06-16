#!/usr/bin/env bash
# monitor.sh — Fast token usage parser for Claude Code session JSONL files

# Self-locate the install root. monitor.sh lives at <root>/modules/, so the
# install root is one level up. Falls back to $CC_KIT_DIR env var so the
# user's dev override (set in ~/.bashrc) still works.
_cc_self="${BASH_SOURCE[0]:-$0}"
while [ -L "$_cc_self" ]; do _cc_self="$(readlink -f "$_cc_self")"; done
_cc_self_dir="$(cd "$(dirname "$_cc_self")" && pwd)"
CC_KIT_DIR="${CC_KIT_DIR:-$_cc_self_dir/..}"
CC_KIT_DIR="$(cd "$CC_KIT_DIR" && pwd)"
unset _cc_self _cc_self_dir

MONITOR_DATA_DIR="${MONITOR_DATA_DIR:-$CC_KIT_DIR/data}"
MONITOR_USAGE_FILE="$MONITOR_DATA_DIR/usage.db"

mkdir -p "$MONITOR_DATA_DIR"

# Find the current session JSONL.
# Resolution order (best → worst):
#   1. $CLAUDE_CODE_SESSION_ID — Claude Code sets this in its subprocess
#      env, so the statusLine can find *its own* session even with many
#      concurrent sessions running.
#   2. cwd-derived path — works for hooks and CLI invocations from
#      inside a project directory.
#   3. Freshest JSONL across all projects — last-resort fallback.
monitor_find_session() {
  local sid="${CLAUDE_CODE_SESSION_ID:-}"
  if [[ -n "$sid" ]]; then
    local found
    found=$(find "$HOME/.claude/projects" -name "${sid}.jsonl" -type f 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
      echo "$found"
      return
    fi
  fi

  local project_dir
  project_dir="$HOME/.claude/projects/$(printf '%s' "$(pwd)" | tr '/' '-')"
  if [[ -d "$project_dir" ]]; then
    local pj
    pj=$(ls -t "$project_dir"/*.jsonl 2>/dev/null | head -1)
    if [[ -n "$pj" ]]; then
      echo "$pj"
      return
    fi
  fi

  # Fallback: newest jsonl across all projects
  find "$HOME/.claude/projects" -name '*.jsonl' -type f -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | head -1 | cut -d' ' -f2-
}

# Fast single-pass parse: grep extracts all token fields, awk sums
# Output: input output cache_read cache_write total
monitor_parse_session() {
  local jsonl_file="${1:-$(monitor_find_session)}"
  if [[ -z "$jsonl_file" || ! -f "$jsonl_file" ]]; then
    echo "0 0 0 0 0"; return
  fi
  grep -oE '"(input_tokens|output_tokens|cache_read_input_tokens|cache_creation_input_tokens)":[0-9]+' "$jsonl_file" 2>/dev/null | \
  awk -F: '
    $1 ~ /^"input_tokens"$/          { input += $2 }
    $1 ~ /^"output_tokens"$/         { output += $2 }
    $1 ~ /"cache_read_input_tokens"/  { cr += $2 }
    $1 ~ /"cache_creation_input_tokens"/ { cc += $2 }
    END { printf "%d %d %d %d %d\n", input+0, output+0, cr+0, cc+0, input+output+0 }
  '
}

# Get current session stats as space-separated values
monitor_stats_line() {
  monitor_parse_session "$(monitor_find_session)"
}

# Format number: 1234 → 1.2k, 1234567 → 1.2M
monitor_fmt_num() {
  local n=${1:-0}
  if (( n >= 1000000 )); then
    awk "BEGIN { printf \"%.1fM\", $n/1000000 }"
  elif (( n >= 1000 )); then
    awk "BEGIN { printf \"%.1fk\", $n/1000 }"
  else
    echo "$n"
  fi
}

# Provider short label
monitor_provider_label() {
  if [[ -f "$MONITOR_DATA_DIR/provider.env" ]]; then
    # shellcheck disable=SC1090
    source "$MONITOR_DATA_DIR/provider.env"
    case "${ANTHROPIC_BASE_URL:-}" in
      *deepseek*)
        case "${ANTHROPIC_MODEL:-}" in
          *flash*) echo "DS-flash" ;;
          *)       echo "DS-pro" ;;
        esac ;;
      *minimax*)
        case "${ANTHROPIC_MODEL:-}" in
          *M3*)        echo "MM-m3" ;;
          *highspeed*) echo "MM-hs" ;;
          *)           echo "MM" ;;
        esac ;;
      *) echo "AN" ;;
    esac
  else
    echo "AN"
  fi
}

# ── Cost & pricing ──────────────────────────────────────────────────
# Pricing per 1M tokens, stored as "input cache_hit output"
# Chinese providers (deepseek/minimax) in CNY, Anthropic in USD
monitor_pricing() {
  if [[ -f "$MONITOR_DATA_DIR/provider.env" ]]; then
    source "$MONITOR_DATA_DIR/provider.env"
    case "${ANTHROPIC_BASE_URL:-}" in
      *deepseek*)
        case "${ANTHROPIC_MODEL:-}" in
          *flash*) echo "1.0 0.1 4.0" ;;     # DeepSeek flash: ¥1/¥0.1/¥4 per 1M
          *)       echo "2.0 0.2 8.0" ;;     # DeepSeek pro:  ¥2/¥0.2/¥8 per 1M
        esac ;;
      *minimax*)
        case "${ANTHROPIC_MODEL:-}" in
          *M3*)        echo "2.0 0.2 8.0" ;;
          *highspeed*) echo "2.0 0.2 8.0" ;;
          *)           echo "2.0 0.2 8.0" ;;
        esac ;;
      *) echo "3.00 3.00 15.00" ;;  # Anthropic USD
    esac
  else
    echo "3.00 3.00 15.00"
  fi
}

# Currency symbol for current provider
monitor_currency() {
  if [[ -f "$MONITOR_DATA_DIR/provider.env" ]]; then
    source "$MONITOR_DATA_DIR/provider.env"
    case "${ANTHROPIC_BASE_URL:-}" in
      *deepseek*|*minimax*) echo "¥" ;;
      *) echo "$" ;;
    esac
  else
    echo "$"
  fi
}

# Cache hit rate: cache_read / (input_tokens_uncached + cache_read) × 100
monitor_hit_rate() {
  local stats input cache_read
  stats=$(monitor_stats_line 2>/dev/null || echo "0 0 0 0 0")
  read -r input _ cache_read _ _ <<< "$stats"
  local total_input=$((input + cache_read))
  if (( total_input > 0 )); then
    awk "BEGIN { printf \"%.0f\", ($cache_read/$total_input)*100 }"
  else
    echo "0"
  fi
}

# Estimated session cost in USD (uses python3 for reliable float math)
monitor_session_cost() {
  local stats input output cache_read cache_create
  stats=$(monitor_stats_line 2>/dev/null || echo "0 0 0 0 0")
  read -r input output cache_read cache_create <<< "$stats"

  local pricing price_in price_ch price_out
  pricing=$(monitor_pricing)
  read -r price_in price_ch price_out <<< "$pricing"

  local full_price_input=$((input - cache_read))
  if (( full_price_input < 0 )); then full_price_input=0; fi

  python3 -c "
fpi = $full_price_input
cr  = $cache_read
out = $output
pin = $price_in
pch = $price_ch
pout = $price_out
cost = (fpi/1000000)*pin + (cr/1000000)*pch + (out/1000000)*pout
print(f'{cost:.2f}')
" 2>/dev/null || echo "0.00"
}

# Global hit rate from usage.db (all sessions)
monitor_global_hit_rate() {
  if [[ ! -f "$MONITOR_USAGE_FILE" ]]; then
    echo ""
    return
  fi
  local provider
  if [[ -f "$MONITOR_DATA_DIR/provider.env" ]]; then
    source "$MONITOR_DATA_DIR/provider.env"
    case "${ANTHROPIC_BASE_URL:-}" in
      *deepseek*) provider="deepseek" ;;
      *minimax*)  provider="minimax" ;;
      *)          provider="anthropic" ;;
    esac
  fi
  awk -v p="$provider" '
    $2 == p {
      input += $4
      cache += $6
    }
    END {
      total = input + cache
      if (total > 0)
        printf "%.0f", (cache/total)*100
    }
  ' "$MONITOR_USAGE_FILE" 2>/dev/null
}

# Global total cost from usage.db
monitor_global_cost() {
  if [[ ! -f "$MONITOR_USAGE_FILE" ]]; then
    echo ""
    return
  fi
  local provider pricing price_in price_ch price_out
  if [[ -f "$MONITOR_DATA_DIR/provider.env" ]]; then
    source "$MONITOR_DATA_DIR/provider.env"
    case "${ANTHROPIC_BASE_URL:-}" in
      *deepseek*) provider="deepseek" ;;
      *minimax*)  provider="minimax" ;;
      *)          provider="anthropic" ;;
    esac
  fi
  pricing=$(monitor_pricing)
  read -r price_in price_ch price_out <<< "$pricing"
  awk -v p="$provider" -v pin="$price_in" -v pch="$price_ch" -v pout="$price_out" '
    $2 == p {
      input += $4
      output += $5
      cache += $6
    }
    END {
      fpi = input - cache
      if (fpi < 0) fpi = 0
      cost = (fpi/1000000)*pin + (cache/1000000)*pch + (output/1000000)*pout
      printf "%.2f", cost
    }
  ' "$MONITOR_USAGE_FILE" 2>/dev/null
}

# Cached balance (from cc-balance updates, valid for 10 min)
monitor_balance_cache_file() {
  echo "$MONITOR_DATA_DIR/.balance_cache"
}
monitor_cached_balance() {
  local cache_file
  cache_file=$(monitor_balance_cache_file)
  if [[ -f "$cache_file" ]]; then
    local cache_age now mtime
    now=$(date +%s)
    # `date -r FILE +%s` works on both GNU coreutils and BSD/macOS date,
    # unlike `stat -c %Y` (GNU only) / `stat -f %m` (BSD only). Fall back
    # to 0 if the file vanishes between the [[ -f ]] check and now.
    mtime=$(date -r "$cache_file" +%s 2>/dev/null || echo 0)
    cache_age=$(( now - mtime ))
    if [ "$cache_age" -lt 600 ]; then  # 10 min TTL
      cat "$cache_file"
      return
    fi
  fi
  # Cache missing or stale: kick off a background refresh so the
  # next statusLine render has data. Don't block this one — return
  # empty now and let the refresh happen asynchronously.
  if [ -x "${CC_KIT_DIR:-}/bin/cc-balance" ]; then
    ( "${CC_KIT_DIR}/bin/cc-balance" auto >/dev/null 2>&1 & )
  fi
  echo ""
}

# Record session to usage.db (called by Stop hook)
monitor_record() {
  local jsonl_file stats input output cache_read cache_create
  jsonl_file=$(monitor_find_session)
  [[ -z "$jsonl_file" ]] && return
  stats=$(monitor_parse_session "$jsonl_file")
  read -r input output cache_read cache_create _ <<< "$stats"

  local provider="anthropic" model="unknown"
  if [[ -f "$MONITOR_DATA_DIR/provider.env" ]]; then
    source "$MONITOR_DATA_DIR/provider.env"
    case "${ANTHROPIC_BASE_URL:-}" in
      *deepseek*) provider="deepseek" ;;
      *minimax*)  provider="minimax" ;;
    esac
    model="${ANTHROPIC_MODEL:-unknown}"
  fi

  echo "$(date +%s) $provider $model $input $output $cache_read $cache_create" >> "$MONITOR_USAGE_FILE"
}
