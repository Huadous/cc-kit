# Changelog

All notable changes to cc-kit are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Planned for v0.1.0
- Install path configurable via `__CC_KIT_DIR__` placeholder
- Default install to `~/.cc-kit/`
- `install.sh` / `uninstall.sh` with proper backup + restore
- Apache 2.0 LICENSE
- Bilingual README (English / 中文)
- Support docs: INSTALL, PROVIDERS, CONTRIBUTING, SECURITY, FAQ
- Bats unit tests for monitor / switch / balance
- CI on ubuntu-latest + macos-latest

## [0.0.1] - 2026-06-15

### Added
- Initial working toolkit (pre-open-source)
- Provider switcher: DeepSeek (pro/flash), MiniMax (M2.7/M3/highspeed), Anthropic
- Token/cost monitor: parse Claude Code session JSONL
- Status line: single / wide / full modes
- Balance query: DeepSeek account, MiniMax coding-plan quota
- SessionStart / Stop hooks

[Unreleased]: https://github.com/Huadous/cc-kit/compare/v0.0.1...HEAD
[0.0.1]: https://github.com/Huadous/cc-kit/releases/tag/v0.0.1
