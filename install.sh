#!/usr/bin/env bash
# cc-kit install.sh — One-click setup for the Claude Code extensions toolkit
#
# Usage:
#   ./install.sh                       # install to ~/.cc-kit/ (default)
#   CC_KIT_ROOT=~/my/path ./install.sh # install to custom path
#
# What it does (per docs/superpowers/specs/2026-06-16-cc-kit-opensource-design.md §2.2):
#   1. Pre-flight checks (bash, python3, curl, bc, awk, grep, ~/.claude)
#   2. Copy code to $CC_KIT_ROOT (default ~/.cc-kit)
#   3. Substitute __CC_KIT_DIR__ / __CC_KIT_ROOT__ placeholders with the real path
#   4. Copy data/*.example templates into data/* (chmod 600 secrets.env)
#   5. Back up ~/.claude/settings.json, merge statusLine + Stop/SessionStart hooks
#   6. Symlink bin/cc-* into ~/.local/bin
#   7. Append a marked block to ~/.bashrc to source init.sh
# Strict mode: -e (exit on error) and -u (unset variable) are POSIX-safe.
# `-o pipefail` is a bash extension; under `dash` (Ubuntu's /bin/sh) it errors
# out, so we enable it only when bash is the actual interpreter.
set -eu
[ -n "${BASH_VERSION:-}" ] && set -o pipefail

# Bash-only constructs are used throughout the rest of this script
# (BASH_VERSINFO, [[ ]], arrays). Detect dash/posh and bail with a clear
# message instead of failing on the first bash-only line.
if [ -z "${BASH_VERSION:-}" ]; then
  echo ""
  echo "  ✗ install.sh requires bash." >&2
  echo "    You invoked it with: $(ps -o comm= -p $$ 2>/dev/null || echo 'sh')" >&2
  echo "    Re-run with:        bash install.sh" >&2
  echo "" >&2
  exit 1
fi

# ── Resolve install path ────────────────────────────────────────────
CC_KIT_ROOT="${CC_KIT_ROOT:-$HOME/.cc-kit}"
SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
# Pick the user's actual shell rc file. macOS default is zsh; writing to
# .bashrc there means cc-kit is silently never initialized. Fall back to
# .bashrc for unknown shells.
case "${SHELL:-}" in
  */zsh) BASHRC_FILE="${ZDOTDIR:-$HOME}/.zshrc" ;;
  *)     BASHRC_FILE="$HOME/.bashrc" ;;
esac
SETTINGS_FILE="$HOME/.claude/settings.json"
LOCAL_BIN="$HOME/.local/bin"
BACKUP_DIR="$CC_KIT_ROOT/.backup"

# Warn — and offer to remove — CC_KIT_DIR / CC_KIT_ROOT / MONITOR_DATA_DIR
# exports in the user's rc file. These silently override cc-kit's self-
# location and were the root cause of a real user outage (SessionStart hook
# pointed at a non-existent path, and the status line rendered against the
# wrong provider.env). Just printing a warning isn't enough: users tend to
# scroll past, the rc file stays broken, and the next reinstall looks fine
# but keeps hitting the override. Offer to delete the lines now.
#
# The matching regex and delete command live in a small helper so bats
# tests can exercise them in isolation. Install-time code below just
# wires the helper to the prompt.
#
# _cc_kit_clean_rc_exports <file> <auto_yes>
#   auto_yes=1 → delete without prompting; 0 → print lines and ask
#   Echoes offending lines (with line numbers). If deleted, prints a
#   confirmation. Returns 0 if any lines were removed, 1 otherwise.
_cc_kit_clean_rc_exports() {
  local rc_file="$1"
  local auto_yes="${2:-0}"
  [[ -f "$rc_file" ]] || return 1
  # `^[^#]*` ensures the line isn't a comment; `\<` word boundary
  # prevents false matches on `CC_KIT_DIR_TEST=...` and similar.
  local matches
  matches=$(grep -nE '^[^#]*\<export[[:space:]]+(CC_KIT_DIR|CC_KIT_ROOT|MONITOR_DATA_DIR)=' "$rc_file" 2>/dev/null)
  [[ -z "$matches" ]] && return 1
  echo "$matches" | sed 's/^/      /'
  if [[ "$auto_yes" != "1" ]]; then
    read -rp "    Remove these lines? [Y/n] " _ans
    case "$_ans" in
      [Nn]*) echo "    ! kept (remove manually later)"; return 1 ;;
    esac
  fi
  sed -i -E '/^[^#]*\<export[[:space:]]+(CC_KIT_DIR|CC_KIT_ROOT|MONITOR_DATA_DIR)=/d' "$rc_file"
  echo "    ✓ removed"
  return 0
}

_removed_rc_exports=0
for _rc in "$HOME/.bashrc" "$HOME/.zshrc" "${ZDOTDIR:-$HOME}/.zshrc"; do
  if [[ -f "$_rc" ]] && grep -qE '^[^#]*\<export[[:space:]]+(CC_KIT_DIR|CC_KIT_ROOT|MONITOR_DATA_DIR)=' "$_rc" 2>/dev/null; then
    echo ""
    echo "  ! Detected cc-kit path override(s) in $_rc:"
    if _cc_kit_clean_rc_exports "$_rc" 0; then
      _removed_rc_exports=$(( _removed_rc_exports + 1 ))
    fi
  fi
done
unset _rc
if [[ "$_removed_rc_exports" -gt 0 ]]; then
  echo "  → $CC_KIT_ROOT will be picked up on next shell start (run: source $BASHRC_FILE)"
fi

echo ""
echo "  ◈  CC-KIT INSTALLER"
echo "  ───────────────────"
echo "  Source:  $SRC_DIR"
echo "  Install: $CC_KIT_ROOT"
echo ""

# ── Step 1: Pre-flight checks ───────────────────────────────────────
echo "→ Pre-flight checks..."
fail=0

check_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    printf '  ✓ %s\n' "$cmd"
  else
    printf '  ✗ %s (missing)\n' "$cmd"
    fail=1
  fi
}

check_cmd bash
check_cmd python3
check_cmd curl
check_cmd bc
check_cmd awk
check_cmd grep

# bash ≥ 4
if [ "${BASH_VERSINFO[0]}" -ge 4 ]; then
  echo "  ✓ bash ≥ 4 (${BASH_VERSION})"
else
  echo "  ✗ bash ≥ 4 required (have ${BASH_VERSION})"
  fail=1
fi

# python3 ≥ 3.8
if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)' 2>/dev/null; then
  echo "  ✓ python3 ≥ 3.8"
else
  echo "  ✗ python3 ≥ 3.8 required"
  fail=1
fi

# ~/.claude exists
if [[ -d "$HOME/.claude" ]]; then
  echo "  ✓ ~/.claude/ exists"
else
  echo "  ✗ ~/.claude/ not found — install Claude Code first"
  fail=1
fi

# Refuse to overwrite
if [[ -d "$CC_KIT_ROOT" ]]; then
  echo ""
  echo "  ! $CC_KIT_ROOT already exists."
  read -rp "    Reinstall? This will overwrite code (data/ is preserved) [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || { echo "  Aborted."; exit 1; }
fi

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "  Pre-flight failed. Install missing dependencies and retry."
  exit 1
fi

# ── Step 2: Copy code ───────────────────────────────────────────────
echo ""
echo "→ Copying code to $CC_KIT_ROOT..."
mkdir -p "$CC_KIT_ROOT"

# Always copy fresh — code is meant to be replaced on reinstall.
# IMPORTANT: `cp -r SRC DST` where DST exists as a directory copies SRC *into*
# DST, creating DST/SRC/. On repeated installs this would build
# ~/.cc-kit/bin/bin/bin/bin/...  Wipe each target dir first so the copy is
# always a clean top-level replacement (data/ is preserved separately above).
for d in bin modules hooks completions; do
  rm -rf "${CC_KIT_ROOT:?}/$d"
  cp -r "$SRC_DIR/$d" "$CC_KIT_ROOT/$d"
done
rm -f "$CC_KIT_ROOT/init.sh"
cp "$SRC_DIR/init.sh" "$CC_KIT_ROOT/init.sh"
chmod +x "$CC_KIT_ROOT/bin/"* 2>/dev/null || true
chmod +x "$CC_KIT_ROOT/hooks/"* 2>/dev/null || true
echo "  ✓ code copied"

# ── Step 3: data/ directory (preserve on reinstall) ────────────────
if [[ ! -d "$CC_KIT_ROOT/data" ]]; then
  mkdir -p "$CC_KIT_ROOT/data"
  # Copy .example templates → real files
  for tmpl in "$SRC_DIR"/data/*.example; do
    [[ -f "$tmpl" ]] || continue
    dest="$CC_KIT_ROOT/data/$(basename "${tmpl%.example}")"
    cp "$tmpl" "$dest"
  done
  [[ -f "$CC_KIT_ROOT/data/secrets.env" ]] && chmod 600 "$CC_KIT_ROOT/data/secrets.env"
  echo "  ✓ data/ initialized from templates"
else
  echo "  ✓ data/ preserved"
fi
mkdir -p "$BACKUP_DIR"
[[ ! -f "$CC_KIT_ROOT/data/.display_mode" ]] && echo "full" > "$CC_KIT_ROOT/data/.display_mode"

# ── Step 4: (no placeholder substitution needed — scripts self-locate) ─
# Scripts now self-locate their install dir at runtime via BASH_SOURCE /
# __file__ resolution, so no sed substitution is required. This was a
# source of subtle bugs in earlier versions (dev override pointing at the
# source tree would silently fail because placeholders stayed unsubstituted).
echo "→ Path resolution: scripts self-locate (no substitution needed)"

# ── Step 5: Configure Claude Code settings.json ────────────────────
echo "→ Configuring Claude Code settings.json..."
if [[ ! -f "$SETTINGS_FILE" ]]; then
  echo "  ! $SETTINGS_FILE not found — skipping (run Claude Code once to create it)"
else
  # Back up
  bak="$BACKUP_DIR/settings.json.$(date +%Y%m%d-%H%M%S)"
  cp "$SETTINGS_FILE" "$bak"
  echo "  ✓ backed up to $bak"

  # Use jq if available, else python3
  merger="python3"
  command -v jq >/dev/null 2>&1 && merger="jq"

  if [[ "$merger" == "jq" ]]; then
    tmp=$(mktemp)
    jq --arg cmd "$CC_KIT_ROOT/bin/cc-status" \
       --arg stop "bash $CC_KIT_ROOT/hooks/stop-record.sh" \
       --arg sess "bash $CC_KIT_ROOT/hooks/session-start.sh" '
      # Path-boundary-anchored regex: match `/cc-kit/`, `/cc-kit$`,
      # `/.cc-kit/`, `/.cc-kit$`, and the `^/cc-kit/` start-of-path case,
      # but NOT substrings like `/mycc-kittens/` or `/.cc-kit-cache/`.
      # This regex is the source of truth — the python3 fallback below
      # MUST use the same anchors.
      def is_cc_kit_path: test("(^|/)cc-kit(/|$)|(^|/)\\.cc-kit(/|$)");
      # Replace statusLine if it points to any cc-kit install path (across
      # all historical CC_KIT_ROOT values: ~/projects/cc-kit, ~/.cc-kit,
      # ~/.cc-kit-test, etc.). Otherwise leave the user'"'"'s custom line alone.
      if (.statusLine?.command // "") | is_cc_kit_path then
        .statusLine = {type:"command", command:$cmd, padding:0}
      else . end
      | .statusLineRefreshInterval //= 5
      | .hooks //= {}
      | .hooks.Stop //= []
      | .hooks.SessionStart //= []
      # Remove ALL matcher entries whose hook command points to any cc-kit
      # install path. This cleans up entries from previous installs/tests
      # even when they used a different CC_KIT_ROOT.
      | .hooks.Stop          |= [.[] | select((.hooks[]?.command // "") | is_cc_kit_path | not)]
      | .hooks.SessionStart |= [.[] | select((.hooks[]?.command // "") | is_cc_kit_path | not)]
      # Add fresh entries pointing at the current install dir.
      | .hooks.Stop          += [{matcher:"*", hooks:[{type:"command", command:$stop, timeout:10}]}]
      | .hooks.SessionStart  += [{matcher:"*", hooks:[{type:"command", command:$sess, timeout:5}]}]
    ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
    echo "  ✓ settings.json updated (via jq)"
  else
    # python3 fallback
    SETTINGS_FILE="$SETTINGS_FILE" CC_KIT_ROOT="$CC_KIT_ROOT" python3 - <<'PYEOF' && echo "  ✓ settings.json updated (via python3)" || echo "  ! failed to update settings.json"
import json, os, re
# Same path-boundary-anchored regex as the jq branch above. Keep these
# in sync — this is the source of truth for "is this a cc-kit path?".
_CC_KIT_RE = re.compile(r"(^|/)cc-kit(/|$)|(^|/)\.cc-kit(/|$)")
path = os.environ["SETTINGS_FILE"]
root = os.environ["CC_KIT_ROOT"]
with open(path) as f:
    cfg = json.load(f)
# Replace statusLine only if it points to a cc-kit install (any path).
sl_cmd = cfg.get("statusLine", {}).get("command", "") if isinstance(cfg.get("statusLine"), dict) else ""
if _CC_KIT_RE.search(sl_cmd):
    cfg["statusLine"] = {"type": "command", "command": f"{root}/bin/cc-status", "padding": 0}
cfg.setdefault("statusLineRefreshInterval", 5)
cfg.setdefault("hooks", {})
cfg["hooks"].setdefault("Stop", [])
cfg["hooks"].setdefault("SessionStart", [])
# Remove all matcher entries whose hook command points to a cc-kit install.
def is_cc_kit(entry):
    return any(_CC_KIT_RE.search(h.get("command",""))
               for h in entry.get("hooks", []))
cfg["hooks"]["Stop"]         = [e for e in cfg["hooks"]["Stop"]         if not is_cc_kit(e)]
cfg["hooks"]["SessionStart"] = [e for e in cfg["hooks"]["SessionStart"] if not is_cc_kit(e)]
# Add fresh entries.
stop_cmd = f"bash {root}/hooks/stop-record.sh"
sess_cmd = f"bash {root}/hooks/session-start.sh"
cfg["hooks"]["Stop"].append({"matcher":"*", "hooks":[{"type":"command","command":stop_cmd,"timeout":10}]})
cfg["hooks"]["SessionStart"].append({"matcher":"*", "hooks":[{"type":"command","command":sess_cmd,"timeout":5}]})
with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
PYEOF
  fi
fi

# ── Step 6: Symlink bin/ → ~/.local/bin ────────────────────────────
echo "→ Setting up command symlinks..."
mkdir -p "$LOCAL_BIN"
# Case-insensitive matching for cc-dash.py → cc-dash
for src in "$CC_KIT_ROOT"/bin/*; do
  name=$(basename "$src")
  # Strip .py extension for the symlink name (cc-dash.py → cc-dash)
  link_name="${name%.py}"
  ln -sf "$src" "$LOCAL_BIN/$link_name"
done
echo "  ✓ symlinked: $(find "$LOCAL_BIN" -maxdepth 1 -name 'cc-*' -printf '%f ' 2>/dev/null)"

# Ensure ~/.local/bin is in PATH
if ! echo "$PATH" | tr ':' '\n' | grep -qx "$LOCAL_BIN"; then
  if ! grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$BASHRC_FILE" 2>/dev/null; then
    {
      echo ""
      echo '# cc-kit — ensure ~/.local/bin is in PATH'
      echo 'export PATH="$HOME/.local/bin:$PATH"'
    } >> "$BASHRC_FILE"
    echo "  ✓ added ~/.local/bin to PATH in $BASHRC_FILE"
  fi
fi

# ── Step 7: bashrc marker block ────────────────────────────────────
echo "→ Configuring $BASHRC_FILE..."
marker="# BEGIN cc-kit"
endmarker="# END cc-kit"
# Back up $BASHRC_FILE before any modification so a buggy awk (or any
# other script-level error) can be recovered. settings.json is already
# backed up at line ~165; the rc file needs the same safety net.
if [[ -f "$BASHRC_FILE" ]]; then
  cp "$BASHRC_FILE" "$BACKUP_DIR/$(basename "$BASHRC_FILE").$(date +%Y%m%d-%H%M%S)"
fi
if grep -Fq "$marker" "$BASHRC_FILE" 2>/dev/null; then
  if grep -Fq "$endmarker" "$BASHRC_FILE" 2>/dev/null; then
    # Both markers present — safe to use the awk state machine to replace
    # the block in place. The `next` on BEGIN sets printing=1; we MUST see
    # the END marker later or printing stays 1 forever and the rest of
    # the file is silently lost. END block guards against a future bug
    # that drops the END marker.
    tmp=$(mktemp)
    awk -v m="$marker" -v e="$endmarker" -v body="[ -f \"${CC_KIT_ROOT}/init.sh\" ] && source \"${CC_KIT_ROOT}/init.sh\"" '
      $0 ~ m { printing=1; print m; print body; next }
      $0 ~ e { printing=0; print e; next }
      !printing { print }
      END { if (printing) { print "cc-kit: awk ended with printing=1 (END marker missing in $BASHRC_FILE); aborting" > "/dev/stderr"; exit 1 } }
    ' "$BASHRC_FILE" > "$tmp" && mv "$tmp" "$BASHRC_FILE" || {
      echo "  ! awk failed (END marker missing?); preserving $BASHRC_FILE as-is"
      rm -f "$tmp"
    }
    echo "  ✓ updated existing cc-kit block in $BASHRC_FILE"
  else
    # BEGIN exists but no matching END — user hand-edited and removed the
    # END marker. The awk state machine would skip everything after BEGIN
    # forever, silently truncating the rest of the rc file. Treat the
    # block as malformed: append a fresh, complete block.
    echo "  ! existing cc-kit block is missing END marker; appending a fresh complete block"
    {
      echo ""
      echo "$marker"
      echo "[ -f \"${CC_KIT_ROOT}/init.sh\" ] && source \"${CC_KIT_ROOT}/init.sh\""
      echo "$endmarker"
    } >> "$BASHRC_FILE"
  fi
else
  {
    echo ""
    echo "$marker"
    echo "[ -f \"${CC_KIT_ROOT}/init.sh\" ] && source \"${CC_KIT_ROOT}/init.sh\""
    echo "$endmarker"
  } >> "$BASHRC_FILE"
  echo "  ✓ appended cc-kit block to $BASHRC_FILE"
fi

# ── Done ────────────────────────────────────────────────────────────
echo ""
echo "  ✓ cc-kit installed to $CC_KIT_ROOT"
echo "  ─────────────────────────────────────"
echo ""
echo "  Next steps:"
echo "    1. Restart your shell (or run: source ~/.bashrc)"
echo "    2. Configure a provider:  cc-switch deepseek"
echo "                          or: cc-switch minimax"
echo "                          or: cc-switch glm"
echo "    3. Restart Claude Code for new env vars to take effect"
echo ""
echo "  Commands available:  cc-switch, cc-status, cc-mode, cc-balance,"
echo "                       cc-help, cc-dash"
echo "  Status line is active automatically in Claude Code."
echo ""
