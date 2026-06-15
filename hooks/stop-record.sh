#!/usr/bin/env bash
# cc-kit Stop hook — records token usage + refreshes balance cache at session end
source "__CC_KIT_DIR__/modules/monitor.sh" 2>/dev/null || exit 0
monitor_record
# Refresh balance silently
bash "__CC_KIT_DIR__/bin/cc-balance" auto &>/dev/null &
