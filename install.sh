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
BASHRC_FILE="$HOME/.bashrc"
SETTINGS_FILE="$HOME/.claude/settings.json"
LOCAL_BIN="$HOME/.local/bin"
BACKUP_DIR="$CC_KIT_ROOT/.backup"

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
  REINSTALL=1
else
  REINSTALL=0
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

# Always copy fresh — code is meant to be replaced on reinstall
for d in bin modules hooks; do
  cp -r "$SRC_DIR/$d" "$CC_KIT_ROOT/$d"
done
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

# ── Step 4: Substitute __CC_KIT_DIR__ placeholders ──────────────────
echo "→ Substituting path placeholders..."
sed -i "s|__CC_KIT_DIR__|$CC_KIT_ROOT|g" \
  "$CC_KIT_ROOT"/bin/* \
  "$CC_KIT_ROOT"/modules/* \
  "$CC_KIT_ROOT"/hooks/* \
  "$CC_KIT_ROOT"/init.sh
sed -i "s|__CC_KIT_ROOT__|$CC_KIT_ROOT|g" "$CC_KIT_ROOT/init.sh"
# Replace any leftover literal (shouldn't be any, but just in case)
sed -i "s|~/projects/cc-kit|$CC_KIT_ROOT|g" \
  "$CC_KIT_ROOT"/bin/* \
  "$CC_KIT_ROOT"/modules/* \
  "$CC_KIT_ROOT"/hooks/* \
  "$CC_KIT_ROOT"/init.sh 2>/dev/null || true
remaining=$(grep -rln "__CC_KIT_DIR__\|__CC_KIT_ROOT__\|~/projects/cc-kit" \
  "$CC_KIT_ROOT"/bin "$CC_KIT_ROOT"/modules "$CC_KIT_ROOT"/hooks "$CC_KIT_ROOT"/init.sh 2>/dev/null | wc -l; true)
if [ "$remaining" -gt 0 ]; then
  echo "  ✗ WARNING: $remaining files still have unsubstituted placeholders"
  grep -rln "__CC_KIT_DIR__\|__CC_KIT_ROOT__\|~/projects/cc-kit" \
    "$CC_KIT_ROOT"/bin "$CC_KIT_ROOT"/modules "$CC_KIT_ROOT"/hooks "$CC_KIT_ROOT"/init.sh
else
  echo "  ✓ all placeholders substituted"
fi

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
      .statusLine //= {type:"command", command:$cmd, padding:0}
      | .statusLineRefreshInterval //= 5
      | .hooks //= {}
      | .hooks.Stop //= []
      | .hooks.SessionStart //= []
      | (if (.hooks.Stop | map(.hooks[]?.command // "") | index($stop)) then . else .hooks.Stop += [{matcher:"*", hooks:[{type:"command", command:$stop, timeout:10}]}] end)
      | (if (.hooks.SessionStart | map(.hooks[]?.command // "") | index($sess)) then . else .hooks.SessionStart += [{matcher:"*", hooks:[{type:"command", command:$sess, timeout:5}]}] end)
    ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
    echo "  ✓ settings.json updated (via jq)"
  else
    # python3 fallback
    SETTINGS_FILE="$SETTINGS_FILE" CC_KIT_ROOT="$CC_KIT_ROOT" python3 - <<'PYEOF' && echo "  ✓ settings.json updated (via python3)" || echo "  ! failed to update settings.json"
import json, os
path = os.environ["SETTINGS_FILE"]
root = os.environ["CC_KIT_ROOT"]
with open(path) as f:
    cfg = json.load(f)
cfg.setdefault("statusLine", {"type": "command", "command": f"{root}/bin/cc-status", "padding": 0})
cfg.setdefault("statusLineRefreshInterval", 5)
cfg.setdefault("hooks", {})
cfg["hooks"].setdefault("Stop", [])
cfg["hooks"].setdefault("SessionStart", [])
def has(entries, cmd):
    return any(cmd in (h.get("command","") for h in e.get("hooks", [])) for e in entries)
stop_cmd = f"bash {root}/hooks/stop-record.sh"
sess_cmd = f"bash {root}/hooks/session-start.sh"
if not has(cfg["hooks"]["Stop"], stop_cmd):
    cfg["hooks"]["Stop"].append({"matcher":"*", "hooks":[{"type":"command","command":stop_cmd,"timeout":10}]})
if not has(cfg["hooks"]["SessionStart"], sess_cmd):
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
echo "  ✓ symlinked: $(ls "$LOCAL_BIN"/cc-* 2>/dev/null | xargs -n1 basename | tr '\n' ' ')"

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
echo "→ Configuring ~/.bashrc..."
marker="# BEGIN cc-kit"
endmarker="# END cc-kit"
if grep -Fq "$marker" "$BASHRC_FILE" 2>/dev/null; then
  # Replace existing block
  tmp=$(mktemp)
  awk -v m="$marker" -v e="$endmarker" -v body="[ -f \"${CC_KIT_ROOT}/init.sh\" ] && source \"${CC_KIT_ROOT}/init.sh\"" '
    $0 ~ m { printing=1; print m; print body; next }
    $0 ~ e { printing=0; print e; next }
    !printing { print }
  ' "$BASHRC_FILE" > "$tmp" && mv "$tmp" "$BASHRC_FILE"
  echo "  ✓ updated existing cc-kit block in $BASHRC_FILE"
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
echo "    3. Restart Claude Code for new env vars to take effect"
echo ""
echo "  Commands available:  cc-switch, cc-status, cc-mode, cc-balance,"
echo "                       cc-help, cc-dash"
echo "  Status line is active automatically in Claude Code."
echo ""
