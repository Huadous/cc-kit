#!/usr/bin/env bash
# cc-kit init — sourced by ~/.bashrc
#
# Self-locates: works whether sourced from install copy (~/.cc-kit),
# from a symlink, or from a dev checkout (~/.projects/cc-kit).
# Honors $CC_KIT_ROOT env var if set so the user's dev override still works.

# Resolve our own location
_cc_self="${BASH_SOURCE[0]:-$0}"
while [ -L "$_cc_self" ]; do _cc_self="$(readlink -f "$_cc_self")"; done
_cc_self_dir="$(cd "$(dirname "$_cc_self")" && pwd)"
# init.sh lives at the install root, so its directory IS the install root
export CC_KIT_ROOT="${CC_KIT_ROOT:-$_cc_self_dir}"
unset _cc_self _cc_self_dir

# Load module functions
for mod in monitor switch; do
  if [[ -f "$CC_KIT_ROOT/modules/$mod.sh" ]]; then
    # shellcheck disable=SC1090
    source "$CC_KIT_ROOT/modules/$mod.sh"
  fi
done

# Source provider env if present (sets ANTHROPIC_BASE_URL, ANTHROPIC_MODEL, etc.)
if [[ -f "$CC_KIT_ROOT/data/provider.env" ]]; then
  # shellcheck disable=SC1090
  source "$CC_KIT_ROOT/data/provider.env"
fi
