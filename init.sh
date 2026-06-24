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

# Bash tab completion for cc-* commands
if [[ -f "$CC_KIT_ROOT/completions/cc.bash" ]]; then
  # shellcheck disable=SC1090
  source "$CC_KIT_ROOT/completions/cc.bash"
fi

# Wrap cc-switch so every call re-sources modules/switch.sh first. This keeps
# the parser fresh: after an upgrade that adds a model (e.g. glm-5.2), a
# long-lived tmux pane picks up the new parser on the next call instead of
# staying frozen at whatever switch.sh looked like when the shell first started.
#
# CRITICAL: the wrapper must run IN-PROCESS (source + call), NOT via a
# subprocess (bin/cc-switch). switch.sh's real cc-switch ends by sourcing
# ~/.bashrc, which re-sources data/provider.env and applies the new provider
# env vars (ANTHROPIC_MODEL, etc.) to THIS shell. That in-process update is
# how the switch actually takes effect for the next `claude` launch. A
# subprocess wrapper would write provider.env correctly but leave this shell's
# env stale — so `cc-switch glm 5.2` would silently "not take effect".
#
# The depth guard prevents infinite recursion if switch.sh is missing or
# malformed and fails to redefine cc-switch: `source ... || return` covers a
# missing/unreadable file; the guard covers a file that sources cleanly but
# doesn't (re)define cc-switch.
if [[ -f "$CC_KIT_ROOT/modules/switch.sh" ]]; then
  cc-switch() {
    if [[ "${_CC_SWITCH_DEPTH:-0}" -gt 0 ]]; then
      echo "cc-switch: failed to load $CC_KIT_ROOT/modules/switch.sh" >&2
      return 1
    fi
    # shellcheck disable=SC1090
    source "$CC_KIT_ROOT/modules/switch.sh" || return 1
    _CC_SWITCH_DEPTH=1 cc-switch "$@"
  }
fi
