#!/usr/bin/env bash
# cc-kit Stop hook — records token usage + refreshes balance cache at session end
#
# Self-locates the install root. Falls back to $CC_KIT_DIR env var if set
# (for dev override) but warns to stderr on mismatch or bad path — silent
# overrides were the root cause of a real user outage.
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

source "$CC_KIT_DIR/modules/monitor.sh" 2>/dev/null || exit 0
monitor_record
# Refresh balance silently
bash "$CC_KIT_DIR/bin/cc-balance" auto &>/dev/null &
