# Changelog

All notable changes to cc-kit are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.4] - 2026-06-19

### Fixed
- **Wrong currency prefix on coding-plan percentage**:
  `monitor_balance_label` was prepending the currency symbol (¥/$)
  to *every* cached balance string, including the MiniMax coding-plan
  format `"91%  5h:4h02m  wk:100%"`. Result: `¥91%  4h02m` — semantically
  wrong, since the percentage is a quota utilization, not a monetary
  amount. Currency is now only prepended for pay-as-you-go balances
  (`¥30.77 CNY`); the coding-plan shape renders as `91%  4h02m`.
- **Octal parse crash on `08`/`09` minute values**: the helper
  `monitor_coding_plan_remaining` did `total_s=$(( h*3600 + m*60 ))`
  and bash interpreted a leading-zero `m` like `"08"` as octal — then
  died with `08: value too great for base (error token is "08")`
  because 8/9 aren't valid octal digits. Today the cache format
  happened to land on `4h08m`, so the helper silently returned empty
  and the banner fell back to the static `5h` label. Fix: force
  base-10 with `10#$h` and `10#$m`. Also covers `0h08m → 8m`.
- **Stale bats test that codified the wrong behavior**:
  `monitor_balance_label: coding-plan format with currency + remaining`
  was asserting `¥91%  4h02m` — i.e. locking in the bug. Renamed to
  `...with remaining` and corrected to expect `91%  4h02m` (no ¥).
  New `monitor_coding_plan_remaining: handles minutes with leading
  zero (08/09)` test guards the octal regression.

## [0.1.3] - 2026-06-17

### Fixed
- **Status-line refresh actually shows up**: v0.1.2's `monitor_coding_plan_remaining`
  helper was correctly added to `monitor.sh` and consumed by `cc-status`, but the
  SessionStart hook banner and `cc-status` were both still stripping the cached
  balance down to its first whitespace-separated field (`awk '{print $1}'`),
  which for the MiniMax coding-plan format `"85%  5h:4h01m  wk:100%"` left only
  `"85%"` for the helper to chew on. With no `5h:HHhMMm` fragment, the helper
  always returned empty, so the user saw the static `5h` fallback label
  forever — same as the pre-v0.1.2 behavior. Removed the awk truncation; both
  paths now pass the full cached string to the helper.
- **Refactor: balance rendering moved to a single helper**. `monitor_balance_label`
  in `modules/monitor.sh` is now the one place that turns a cached balance
  string into a renderable label. `bin/cc-status` and `hooks/session-start.sh`
  both call it, so the banner and the status line can't drift again.

## [0.1.2] - 2026-06-17

### Added
- **Coding-plan remaining time in status line**: the MiniMax coding-plan
  section (`91%  5h`) now shows the actual time left in the current 5h
  window instead of the static `5h` label. Two new helpers in
  `modules/monitor.sh`:
  - `monitor_coding_plan_remaining` extracts the `5h:HHhMMm` fragment from
    the cache and subtracts elapsed time since the cache was written,
    so the value stays up-to-the-minute even when the cache TTL (10 min)
    hasn't elapsed.
  - `monitor_coding_plan_fmt` formats seconds as `HhMMm` (drops the `0h`
    prefix when the window is under 1 hour, so `42m` not `0h42m`).
  The status line auto-kicks off a background `cc-balance auto` refresh
  when the cached value has already expired (window reset or very stale
  cache), so the next render has fresh data without blocking the current
  one. Falls back gracefully to `5h` for older cache formats.

## [0.1.1] - 2026-06-17

### Fixed
- **SessionStart hook outage**: `~/.claude/settings.json` could end up
  pointing to a non-existent path (e.g., the test install dir from
  `make install-local`), causing every Claude Code start to fail with
  `bash: /home/.../.cc-kit-test/hooks/session-start.sh: No such file or
  directory`. Two changes that together make this impossible:
  - `install.sh` settings merger now path-boundary-anchors the regex
    that detects existing cc-kit hooks (was a substring search that
    could over-match), and removes all of them before adding fresh
    entries pointing at the current install dir.
  - `Makefile` `install-local` target now snapshots
    `~/.claude/settings.json` and restores it on `EXIT` trap, so
    CI testing with `CC_KIT_ROOT=~/.cc-kit-test` can never pollute
    the user's real settings.
- **Nested directory corruption on reinstall**: `install.sh` used
  `cp -r SRC DST` where DST already existed as a directory, which
  creates `DST/SRC/`. After 3 reinstalls this produced
  `~/.cc-kit/bin/bin/bin/` (with a circular self-symlink) plus
  `modules/modules/` and `hooks/hooks/` siblings. Now each target
  dir is `rm -rf`'d before the copy.
- **`.bashrc` silent truncation**: the awk state machine in
  `install.sh`'s bashrc-update step would skip everything after
  `# BEGIN cc-kit` forever if the `# END cc-kit` marker was missing
  (e.g., a user hand-edited the block). The rest of the rc file
  was silently lost. Now: only use the awk when both markers
  exist; otherwise append a fresh complete block. The awk also
  has an `END { }` guard that fails non-zero if `printing` is
  still 1 at EOF.
- **No `.bashrc` backup**: `install.sh` backed up `settings.json`
  to `~/.cc-kit/.backup/` but never backed up `.bashrc`. If any
  rewrite corrupted it, the user had no recovery. Now both are
  backed up before modification.

### Changed
- **Env-var override warnings** in 9 self-locating scripts
  (`bin/cc-switch`, `bin/cc-balance`, `bin/cc-mode`, `bin/cc-status`,
  `modules/switch.sh`, `modules/monitor.sh`,
  `hooks/session-start.sh`, `hooks/stop-record.sh`, `init.sh`):
  when `$CC_KIT_DIR` / `$CC_KIT_ROOT` is set in the environment
  and doesn't match the auto-detected install path, the script
  writes a `WARNING:` line to stderr. When the env var points to
  a non-existent path, the script falls back to auto-detection
  instead of silently using an empty path. Dev override is
  preserved — this is purely an alert.
- **`install.sh` warns on rc-file CC_KIT_DIR exports**: scans
  `~/.bashrc` and `~/.zshrc` for `export CC_KIT_DIR=` /
  `export CC_KIT_ROOT=` lines at install time and prints a clear
  hint to remove them. Same root cause as the SessionStart outage
  — these exports silently override self-location and were the
  actual trigger.
- **Zsh support**: `$BASHRC_FILE` is now picked from `$SHELL`
  (zsh → `~/.zshrc`, bash → `~/.bashrc`). Previously zsh users
  (macOS default) were silently excluded — the cc-kit block was
  written to `.bashrc` which their shell never sources.
- **CI runs Ubuntu only**: `macos-latest` was dropped from the
  matrix. Scripts are still written defensively for bash 3.2 and
  no GNU-only utilities, but no macOS runner is available to the
  maintainer for verification. See `README.md` "Platform support".

### Security
- **Path-boundary-anchored regex** in `settings.json` merger (both
  the jq and python3 branches): was `test("/cc-kit|/\.cc-kit")`
  (substring search) — would over-match unrelated paths like
  `~/mywork/cc-kit-test/` or `~/.cc-kit-cache/`. Now
  `test("(^|/)cc-kit(/|$)|(^|/)\\.cc-kit(/|$)")` — only matches
  actual cc-kit install paths. The two branches share a single
  source-of-truth regex (jq `def` / python module-level constant)
  so they can't drift apart.

## [0.1.0] - 2026-06-16

### Added
- Open-source release with Apache 2.0 license
- `install.sh` / `uninstall.sh` with configurable install path
- `__CC_KIT_DIR__` / `__CC_KIT_ROOT__` placeholders for portable installs
- Backup + restore of `~/.claude/settings.json` during install
- `~/.local/bin/cc-*` symlinks auto-created
- Bilingual README (English / 中文)
- Support docs: INSTALL, PROVIDERS, CONTRIBUTING, SECURITY, FAQ
- Bats unit tests for monitor / switch / balance (37 tests)
- GitHub Actions CI on ubuntu-latest + macos-latest
- Provider switcher refreshes balance cache automatically

### Fixed
- `prompt_secret` now works in non-TTY environments (Claude Code `!` prefix)
- StatusLine model name refreshes from disk after `cc-switch`
- Balance cache refreshes when switching providers
- `install.sh` / `uninstall.sh` compatible with both bash and dash
- 4 bin scripts (`cc-mode`, `cc-status`, `cc-balance`, `cc-switch`) now use
  the `__CC_KIT_DIR__` placeholder instead of hardcoded dev path
- `(( expr ))` constructs replaced with `[ ... -gt ... ]` so `set -e`
  doesn't exit on falsy comparisons
- `grep ... | wc -l` pipelines no longer trip `pipefail` on empty match

## [0.0.1] - 2026-06-15

### Added
- Initial working toolkit (pre-open-source)
- Provider switcher: DeepSeek (pro/flash), MiniMax (M2.7/M3/highspeed), Anthropic
- Token/cost monitor: parse Claude Code session JSONL
- Status line: single / wide / full modes
- Balance query: DeepSeek account, MiniMax coding-plan quota
- SessionStart / Stop hooks

[Unreleased]: https://github.com/Huadous/cc-kit/compare/v0.1.4...HEAD
[0.1.4]: https://github.com/Huadous/cc-kit/releases/tag/v0.1.4
[0.1.3]: https://github.com/Huadous/cc-kit/releases/tag/v0.1.3
[0.1.2]: https://github.com/Huadous/cc-kit/releases/tag/v0.1.2
[0.1.1]: https://github.com/Huadous/cc-kit/releases/tag/v0.1.1
[0.1.0]: https://github.com/Huadous/cc-kit/releases/tag/v0.1.0
[0.0.1]: https://github.com/Huadous/cc-kit/releases/tag/v0.0.1
