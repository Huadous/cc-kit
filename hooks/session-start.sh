#!/usr/bin/env bash
# cc-kit SessionStart hook — show status at session start (zero user tokens)
source "__CC_KIT_DIR__/modules/monitor.sh" 2>/dev/null || exit 0

label=$(monitor_provider_label 2>/dev/null || echo "CC")
bal=$(monitor_cached_balance 2>/dev/null | awk '{print $1}' || echo "")
cur=$(monitor_currency 2>/dev/null || echo '$')
mode=$(cat "__CC_KIT_DIR__/data/.display_mode" 2>/dev/null || echo "full")

cat <<EOF


  ◈  cc-kit active   │   ${label}   │   ${cur}${bal:-—} balance   │   mode: ${mode}

  Commands:  /cc-help  (help)  ·  /cc-switch  (change model)  ·  !cc-balance  (refresh balance)

EOF
