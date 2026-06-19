#!/usr/bin/env bash
# cc-kit init — sourced by ~/.bashrc
#
# Self-locates: works whether sourced from install copy (~/.cc-kit),
# from a symlink, or from a dev checkout (~/.projects/cc-kit).
# Honors $CC_KIT_ROOT env var if set so the user's dev override still works.

# Resolve our own location. init.sh lives at the install root, so its dir
# IS the root. Falls back to $CC_KIT_ROOT env var (for dev override).
#
# We ONLY warn when the env var points to a broken path (e.g. someone
# installed via `CC_KIT_ROOT=/srv/cc-kit ./install.sh` and then later
# deleted that dir) — silently using a non-existent root caused a real
# SessionStart outage. A *valid* dev override is intentional and we
# respect it without nagging; every tmux window / new shell would
# otherwise reprint the same warning the user has already seen.
_cc_self="${BASH_SOURCE[0]:-$0}"
while [ -L "$_cc_self" ]; do _cc_self="$(readlink -f "$_cc_self")"; done
_cc_self_dir="$(cd "$(dirname "$_cc_self")" && pwd)"
_cc_auto_root="$_cc_self_dir"
if [ -n "${CC_KIT_ROOT:-}" ]; then
  _cc_resolved="$(cd "$CC_KIT_ROOT" 2>/dev/null && pwd)"
  if [ -z "$_cc_resolved" ]; then
    # Path is broken — this is the dangerous case, warn loudly.
    echo "cc-kit: WARNING: CC_KIT_ROOT=$CC_KIT_ROOT is not accessible; falling back to auto-detected ($_cc_auto_root)" >&2
    export CC_KIT_ROOT="$_cc_auto_root"
  else
    # Either matches self-locate or is a valid dev override. Both fine.
    export CC_KIT_ROOT="$_cc_resolved"
  fi
else
  export CC_KIT_ROOT="$_cc_auto_root"
fi
unset _cc_self _cc_self_dir _cc_auto_root _cc_resolved

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
