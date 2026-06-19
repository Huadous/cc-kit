#!/usr/bin/env bash
# monitor.sh — Fast token usage parser for Claude Code session JSONL files

# Self-locate the install root. monitor.sh lives at <root>/modules/, so the
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

  # Fallback: newest jsonl across all projects. Use `find ... -exec stat` so
  # the mtime lookup works on both GNU (stat -c %Y) and BSD/macOS (stat -f %m).
  # GNU find's `-printf '%T@'` is shorter but BSD find doesn't have `-printf`.
  find "$HOME/.claude/projects" -name '*.jsonl' -type f 2>/dev/null \
    | while IFS= read -r f; do
        # Print "<mtime_epoch> <path>" for sorting; mtime command picks the
        # portable form (works on Linux + macOS).
        mtime=$(stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null || echo 0)
        printf '%s %s\n' "$mtime" "$f"
      done \
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
      *bigmodel*|*z.ai*)
        case "${ANTHROPIC_MODEL:-}" in
          *glm-5.1*)      echo "GLM-5.1" ;;
          *glm-4.7-flash*) echo "GLM-flash" ;;
          *glm-4.7*)      echo "GLM-4.7" ;;
          *)              echo "GLM" ;;
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
      *bigmodel*|*z.ai*)
        case "${ANTHROPIC_MODEL:-}" in
          *glm-5.1*)      echo "6.0 1.3 24.0" ;;
          *glm-4.7-flash*) echo "0 0 0" ;;
          *)              echo "2.0 0.4 8.0" ;;
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
      *deepseek*|*minimax*|*bigmodel*|*z.ai*) echo "¥" ;;
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
      *bigmodel*|*z.ai*) provider="glm" ;;
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
      *bigmodel*|*z.ai*) provider="glm" ;;
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

# Extract the MiniMax coding-plan 5h-window remaining time from a cached
# balance value (the format produced by bin/cc-balance: "5h:HHh:MMm" inside
# a larger "<pct>%  5h:HHhMMm  wk:NN%" string). Adjusts for elapsed time
# since the cache was written so the value is up-to-the-minute, not up to
# 10 min stale (the cache TTL in monitor_cached_balance). Returns just the
# duration in compact form ("4h02m", "42m", "0m") or empty if not present.
#
# Args:
#   $1 — cached balance value (e.g. "91%  5h:4h02m  wk:100%")
#   $2 — path to the balance cache file (for mtime adjustment); optional
monitor_coding_plan_remaining() {
  local bal="$1"
  local cache_file="${2:-}"
  # Extract the "5h:HHhMMm" fragment; head -1 in case of multiple matches.
  local fragment
  fragment=$(printf '%s' "$bal" | grep -oE '5h:[0-9]+h[0-9]+m' | head -1)
  if [[ -z "$fragment" ]]; then
    echo ""
    return
  fi
  local cached_remaining="${fragment#5h:}"  # strip "5h:" prefix
  # Parse the snapshot into seconds so we can both reformat (drop 0h)
  # and adjust for cache age. The `10#` prefix forces base-10 — without it,
  # bash interprets a leading-zero `m` like "08" or "09" as octal and dies
  # with "value too great for base" (8/9 are not valid octal digits).
  local h m total_s
  h=$(printf '%s' "$cached_remaining" | grep -oE '^[0-9]+h' | tr -d 'h')
  m=$(printf '%s' "$cached_remaining" | grep -oE '[0-9]+m$' | tr -d 'm')
  h="${h:-0}"; m="${m:-0}"
  total_s=$(( 10#$h*3600 + 10#$m*60 ))
  # If we don't have a cache file, use the snapshot as-is.
  if [[ -z "$cache_file" || ! -f "$cache_file" ]]; then
    monitor_coding_plan_fmt "$total_s"
    return
  fi
  # Subtract elapsed time since the cache was written.
  local now mtime age_s remaining_s
  now=$(date +%s)
  mtime=$(date -r "$cache_file" +%s 2>/dev/null || echo 0)
  age_s=$(( now - mtime ))
  remaining_s=$(( total_s - age_s ))
  if [ "$remaining_s" -le 0 ]; then
    # Either the 5h window just reset, or the cache is so old it's no
    # longer meaningful. Force a refresh in the background so the next
    # statusLine render has a fresh value, and return "0m" for now.
    if [ -x "${CC_KIT_DIR:-}/bin/cc-balance" ]; then
      ( "${CC_KIT_DIR}/bin/cc-balance" auto >/dev/null 2>&1 & )
    fi
    echo "0m"
    return
  fi
  monitor_coding_plan_fmt "$remaining_s"
}

# Internal: format a remaining-seconds value as "HhMMm" (drops the "0h" when
# the hours component is zero, so 42 minutes renders as "42m" not "0h42m").
monitor_coding_plan_fmt() {
  local total_s="$1"
  local h=$(( total_s / 3600 ))
  local m=$(( (total_s % 3600) / 60 ))
  if [ "$h" -gt 0 ]; then
    echo "${h}h$(printf '%02d' "$m")m"
  else
    echo "${m}m"
  fi
}

# Render the full balance label (currency + amount / pct + remaining time)
# from a cached balance value. Two shapes:
#   "30.77 CNY" (DeepSeek pay-as-you-go)        → "¥30.77 CNY"
#   "91%  5h:4h02m  wk:100%" (MiniMax coding plan) → "91%  4h02m"
# Falls back to:
#   "91% 5h" when the cache has the coding-plan pct shape but lacks a
#   remaining-time fragment (older cache format from a pre-v0.1.2 install).
#   "" (empty) when there's no cache at all.
# Single source of truth so cc-status and the session-start banner can't
# drift.
#
# Currency is only prepended for pay-as-you-go amounts. The coding-plan
# percentage is a quota utilization (no monetary value attached), so the
# ¥/$ prefix would be semantically wrong — it would read like "91% of
# ¥something" when really it's "91% of the 5h window used".
monitor_balance_label() {
  local bal="${1:-}"
  local cur="${2:-$(monitor_currency 2>/dev/null || echo '$')}"
  if [[ -z "$bal" ]]; then
    echo ""
    return
  fi
  if [[ "$bal" == *%* ]]; then
    # Coding plan: show interval pct + 5h remaining time (no currency prefix)
    local interval_pct remaining
    interval_pct=$(printf '%s' "$bal" | grep -oE '^[0-9]+%' | tr -d '%')
    remaining=$(monitor_coding_plan_remaining "$bal" "${3:-}")
    if [[ -n "$remaining" ]]; then
      echo "${interval_pct}%  ${remaining}"
    else
      echo "${interval_pct}% 5h"
    fi
  elif [[ "$bal" != "0.00" ]]; then
    echo "${cur}${bal}"
  else
    echo ""
  fi
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
      *bigmodel*|*z.ai*) provider="glm" ;;
    esac
    model="${ANTHROPIC_MODEL:-unknown}"
  fi

  echo "$(date +%s) $provider $model $input $output $cache_read $cache_create" >> "$MONITOR_USAGE_FILE"
}
