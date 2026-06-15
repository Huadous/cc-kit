# Installation troubleshooting

If `./install.sh` failed or something looks off, check this list first.

## Pre-flight checks

`install.sh` refuses to run if these are missing. Output is a clear list of
failures — fix the first one and re-run.

| Check | Fix |
|---|---|
| `bash ≥ 4` | macOS users: `brew install bash` and add to `/etc/shells`, then `chsh -s /opt/homebrew/bin/bash` |
| `python3 ≥ 3.8` | macOS users: `brew install python@3.11` |
| `curl` | `apt install curl` / `brew install curl` |
| `bc` | `apt install bc` / `brew install bc` |
| `awk` | ships with bash; if missing, install `gawk` |
| `grep` | macOS ships BSD grep — see below |
| `~/.claude/` exists | install Claude Code and run it once |

---

## macOS specifics

### BSD grep vs GNU grep

cc-kit uses `grep -oE` (Perl regex). macOS ships BSD grep, which behaves
slightly differently for some edge cases. **Most users won't hit issues**,
but if you see weird output:

```bash
brew install grep
export PATH="/opt/homebrew/opt/grep/libexec/gnubin:$PATH"
```

### bash 3.2 is the macOS default

Anthropic's Claude Code requires bash ≥ 4. Install via Homebrew:

```bash
brew install bash
# add /opt/homebrew/bin/bash to /etc/shells
echo /opt/homebrew/bin/bash | sudo tee -a /etc/shells
chsh -s /opt/homebrew/bin/bash
```

Then open a new terminal and re-run `./install.sh`.

---

## PATH issues

If you get `cc-switch: command not found` after install:

```bash
echo $PATH | tr ':' '\n' | grep local
# If empty:
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

---

## settings.json didn't update

If the status line doesn't appear after restarting Claude Code:

1. Open `~/.claude/settings.json`
2. Verify these are present:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/home/YOU/.cc-kit/bin/cc-status",
    "padding": 0
  },
  "statusLineRefreshInterval": 5,
  "hooks": {
    "Stop": [
      { "matcher": "*", "hooks": [
        { "type": "command", "command": "bash /home/YOU/.cc-kit/hooks/stop-record.sh", "timeout": 10 }
      ]}
    ],
    "SessionStart": [
      { "matcher": "*", "hooks": [
        { "type": "command", "command": "bash /home/YOU/.cc-kit/hooks/session-start.sh", "timeout": 5 }
      ]}
    ]
  }
}
```

If you see a `statusLine` from another tool, **install.sh will refuse to
overwrite** (per spec §2.2). Manually merge the two configs.

---

## Custom install path

```bash
CC_KIT_ROOT=~/my/custom/path ./install.sh
```

The placeholder `__CC_KIT_DIR__` in all scripts is replaced with this path.
The `~/.bashrc` block is rewritten to match.

To uninstall from a custom path:

```bash
CC_KIT_ROOT=~/my/custom/path ./uninstall.sh
```

---

## Reinstalling

`install.sh` detects an existing install and asks before overwriting. Your
`data/` directory (API keys, usage history) is preserved by default.

If you want a clean slate:

```bash
./uninstall.sh   # choose "n" to remove data/ too
./install.sh
```

---

## Sandbox / cloud sync warning

If your home directory syncs to a cloud service (iCloud Drive, Dropbox,
OneDrive), the secrets file `~/.cc-kit/data/secrets.env` may be uploaded
in the clear. cc-kit sets permissions to 0600 but cannot prevent the
sync client from copying the file.

**Recommendation:** install cc-kit outside the synced directory:

```bash
CC_KIT_ROOT=~/Code/cc-kit ./install.sh
```

---

## Still stuck?

- Run `./install.sh` with `set -x` for verbose tracing: `bash -x ./install.sh`
- Check the session-start banner when Claude Code starts — if cc-kit
  shows "active", basic install is good; if not, the init.sh source is broken
- Open an issue: include the output of `./install.sh` and your
  `~/.claude/settings.json` (with API keys redacted)
