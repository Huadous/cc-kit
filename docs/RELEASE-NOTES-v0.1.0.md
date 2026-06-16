# cc-kit v0.1.0 — first open-source release

First public release of cc-kit under Apache 2.0.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Huadous/cc-kit/main/install.sh | bash
```

Then: `cc-switch deepseek` (or `minimax` / `anthropic`).

## What's in the box

- **Provider switcher** — DeepSeek (pro/flash), MiniMax (M2.7/M3/highspeed), Anthropic
- **Token/cost monitor** — parses Claude Code session JSONL, shows usage in status line
- **Status line** — single / wide / full layouts
- **Balance query** — DeepSeek account, MiniMax coding-plan quota
- **SessionStart / Stop hooks** — auto-record usage, refresh balance cache
- **Install path configurable** — install anywhere via `__CC_KIT_DIR__` placeholder
- **Backup + restore** — `install.sh` backs up `~/.claude/settings.json`, `uninstall.sh` restores it

## What's fixed in v0.1.0 vs v0.0.1

- `prompt_secret` works in non-TTY (Claude Code `!` prefix) — was silently failing before
- StatusLine model name refreshes from disk after `cc-switch` (was showing stale model)
- Balance cache refreshes on provider switch (was showing wrong provider's balance)
- `install.sh` / `uninstall.sh` now dash-compatible (failed under `sh` on Ubuntu/Debian)
- Hardcoded `$HOME/projects/cc-kit` paths in 4 bin scripts replaced with `__CC_KIT_DIR__` placeholder
- `(( expr ))` arithmetic replaced with `[ ... -gt ... ]` (was exiting under `set -e` on falsy comparisons)
- `grep ... | wc -l` pipelines no longer trip `pipefail` on empty match

## What's added in v0.1.0 vs v0.0.1

- Open-source release with Apache 2.0 license
- Bilingual README (English / 中文)
- INSTALL / PROVIDERS / CONTRIBUTING / SECURITY / FAQ docs
- 37 bats unit tests
- GitHub Actions CI on ubuntu-latest + macos-latest
- Auto-refresh balance cache after `cc-switch`

## Verification

- 37/37 bats tests pass
- shellcheck + pyflakes clean
- `bash install.sh` works; `sh install.sh` gives a clear "use bash" error
- Bats tests cover the non-TTY prompt path

## Links

- Repo: https://github.com/Huadous/cc-kit
- Docs: https://github.com/Huadous/cc-kit/tree/main/docs
- Issues: https://github.com/Huadous/cc-kit/issues