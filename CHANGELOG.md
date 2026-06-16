# Changelog

All notable changes to cc-kit are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/Huadous/cc-kit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/Huadous/cc-kit/releases/tag/v0.1.0
[0.0.1]: https://github.com/Huadous/cc-kit/releases/tag/v0.0.1
