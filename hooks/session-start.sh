#!/usr/bin/env bash
# cc-kit SessionStart hook — show status at session start (zero user tokens)
#
# Self-locates the install root.
_cc_self="${BASH_SOURCE[0]:-$0}"
while [ -L "$_cc_self" ]; do _cc_self="$(readlink -f "$_cc_self")"; done
_cc_self_dir="$(cd "$(dirname "$_cc_self")" && pwd)"
CC_KIT_DIR="${CC_KIT_DIR:-$_cc_self_dir/..}"
CC_KIT_DIR="$(cd "$CC_KIT_DIR" && pwd)"
unset _cc_self _cc_self_dir

source "$CC_KIT_DIR/modules/monitor.sh" 2>/dev/null || exit 0

label=$(monitor_provider_label 2>/dev/null || echo "CC")
bal=$(monitor_cached_balance 2>/dev/null | awk '{print $1}' || echo "")
cur=$(monitor_currency 2>/dev/null || echo '$')
mode=$(cat "$CC_KIT_DIR/data/.display_mode" 2>/dev/null || echo "full")

cat <<EOF


  ◈  cc-kit active   │   ${label}   │   ${cur}${bal:-—} balance   │   mode: ${mode}

  Commands:  /cc-help  (help)  ·  /cc-switch  (change model)  ·  !cc-balance  (refresh balance)

EOF
