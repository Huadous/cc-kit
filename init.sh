#!/usr/bin/env bash
# cc-kit init — sourced by ~/.bashrc
CC_KIT_ROOT="${CC_KIT_ROOT:-__CC_KIT_ROOT__}"

# Load module functions
for mod in monitor switch; do
  if [[ -f "$CC_KIT_ROOT/modules/$mod.sh" ]]; then
    source "$CC_KIT_ROOT/modules/$mod.sh"
  fi
done

# Source provider env if present
if [[ -f "$CC_KIT_ROOT/data/provider.env" ]]; then
  source "$CC_KIT_ROOT/data/provider.env"
fi
