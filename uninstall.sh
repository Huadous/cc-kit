#!/usr/bin/env bash
# cc-kit uninstall.sh — remove cc-kit installation cleanly
#
# Per docs/superpowers/specs/2026-06-16-cc-kit-opensource-design.md §2.3:
#   1. Restore ~/.claude/settings.json from backup
#   2. Remove the # BEGIN/END cc-kit block from ~/.bashrc
#   3. Delete ~/.local/bin/cc-* symlinks
#   4. Ask before removing data/ (default: keep — preserves API keys + history)
# See install.sh for why this is conditional.
set -eu
[ -n "${BASH_VERSION:-}" ] && set -o pipefail

CC_KIT_ROOT="${CC_KIT_ROOT:-$HOME/.cc-kit}"
BASHRC_FILE="$HOME/.bashrc"
SETTINGS_FILE="$HOME/.claude/settings.json"
BACKUP_DIR="$CC_KIT_ROOT/.backup"
LOCAL_BIN="$HOME/.local/bin"

echo ""
echo "  ◈  CC-KIT UNINSTALLER"
echo "  ─────────────────────"
echo "  Install location: $CC_KIT_ROOT"
echo ""

if [[ ! -d "$CC_KIT_ROOT" ]]; then
  echo "  ! $CC_KIT_ROOT does not exist. Nothing to uninstall."
  exit 0
fi

# ── Step 1: Restore settings.json ───────────────────────────────────
echo "→ Restoring ~/.claude/settings.json..."
if [[ -d "$BACKUP_DIR" ]]; then
  latest=$(ls -t "$BACKUP_DIR"/settings.json.* 2>/dev/null | head -1 || true)
  if [[ -n "$latest" && -f "$latest" ]]; then
    if [[ -f "$SETTINGS_FILE" ]]; then
      cp "$latest" "$SETTINGS_FILE"
      echo "  ✓ restored from $latest"
    else
      echo "  - $SETTINGS_FILE not present, skipping restore"
    fi
  else
    echo "  ! no backup found in $BACKUP_DIR — you'll need to restore manually"
  fi
else
  echo "  ! no backup dir — settings.json untouched, please review manually"
fi

# ── Step 2: Remove bashrc block ────────────────────────────────────
echo "→ Cleaning ~/.bashrc..."
if grep -Fq "# BEGIN cc-kit" "$BASHRC_FILE" 2>/dev/null; then
  tmp=$(mktemp)
  awk '
    /^# BEGIN cc-kit$/ { inblock=1; next }
    /^# END cc-kit$/   { inblock=0; next }
    !inblock           { print }
  ' "$BASHRC_FILE" > "$tmp" && mv "$tmp" "$BASHRC_FILE"
  echo "  ✓ removed cc-kit block from $BASHRC_FILE"
else
  echo "  - no cc-kit block in $BASHRC_FILE"
fi

# ── Step 3: Remove symlinks ────────────────────────────────────────
echo "→ Removing ~/.local/bin/cc-* symlinks..."
removed=0
for f in "$LOCAL_BIN"/cc-*; do
  if [[ -L "$f" ]] && readlink "$f" | grep -q "$CC_KIT_ROOT"; then
    rm -f "$f"
    removed=$((removed + 1))
  fi
done
echo "  ✓ removed $removed symlink(s)"

# ── Step 4: Remove install dir (ask about data/) ───────────────────
echo ""
read -rp "  Keep data directory (API keys + usage history)? [Y/n] " keep_ans
if [[ "$keep_ans" =~ ^[Nn]$ ]]; then
  rm -rf "$CC_KIT_ROOT"
  echo "  ✓ removed $CC_KIT_ROOT (including data/)"
else
  # Keep data/, remove the rest
  find "$CC_KIT_ROOT" -mindepth 1 -maxdepth 1 \
    ! -name 'data' -exec rm -rf {} +
  echo "  ✓ kept $CC_KIT_ROOT/data/ (API keys + history preserved)"
  echo "    Reinstall later with: CC_KIT_ROOT=$CC_KIT_ROOT ./install.sh"
fi

echo ""
echo "  ✓ cc-kit uninstalled"
echo "  Restart your shell: exec bash"
echo ""
