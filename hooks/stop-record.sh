#!/usr/bin/env bash
# cc-kit Stop hook — records token usage + refreshes balance cache at session end
#
# Self-locates the install root.
_cc_self="${BASH_SOURCE[0]:-$0}"
while [ -L "$_cc_self" ]; do _cc_self="$(readlink -f "$_cc_self")"; done
_cc_self_dir="$(cd "$(dirname "$_cc_self")" && pwd)"
CC_KIT_DIR="${CC_KIT_DIR:-$_cc_self_dir/..}"
CC_KIT_DIR="$(cd "$CC_KIT_DIR" && pwd)"
unset _cc_self _cc_self_dir

source "$CC_KIT_DIR/modules/monitor.sh" 2>/dev/null || exit 0
monitor_record
# Refresh balance silently
bash "$CC_KIT_DIR/bin/cc-balance" auto &>/dev/null &
