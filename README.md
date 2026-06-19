# cc-kit

**Claude Code extensions toolkit** — multi-provider switching, token & cost monitoring, and a customizable status line.

[中文文档 →](docs/README.zh.md)

---

## Why cc-kit?

Anthropic's Claude Code is excellent, but it ships with assumptions:
- One provider (Anthropic)
- One currency (USD)
- One status line (none visible to user)

cc-kit makes Claude Code work the way **you** work:
- 🪄 **Switch providers mid-session** — DeepSeek Pro/Flash, MiniMax M2.7/M3, Anthropic, all from one command
- 📊 **See your real costs** — token usage, cache hit rate, ¥ or $ per session
- 🎨 **Three status-line modes** — `single` (compact), `wide` (2-line), `full` (3-line dashboard)
- 💰 **Balance at a glance** — DeepSeek account balance, MiniMax coding-plan quota
- 🔌 **Zero external dependencies** — pure bash + Python stdlib, ~1500 lines total

No telemetry. No cloud. Your data stays on your machine.

---

## Quick start

Requires `bash ≥ 3.2` and `python3 ≥ 3.8`. Everything else is pre-installed on
modern macOS / Ubuntu.

```bash
curl -fsSL https://raw.githubusercontent.com/Huadous/cc-kit/main/install.sh | bash
```

> Note: use `bash install.sh`, never `sh install.sh` — on Ubuntu/Debian,
> `/bin/sh` is `dash`, which doesn't support bash-only constructs.
> The one-liner above pipes into `bash` so this is automatic.

Then:

```bash
cc-switch deepseek    # or minimax / anthropic
# restart Claude Code for the new provider to take effect
```

That's it. Your status line will start showing real-time token usage and cost.

---

## Commands

| Command | What it does |
|---|---|
| `cc-switch deepseek [pro\|flash]` | Switch to DeepSeek (default: pro) |
| `cc-switch minimax [m2.7\|m3\|highspeed]` | Switch to MiniMax (default: m2.7) |
| `cc-switch anthropic` | Restore Anthropic default |
| `cc-switch show` | Show current provider/model |
| `cc-mode single\|wide\|full` | Change status-line layout |
| `cc-balance` | Refresh account balance / coding-plan quota |
| `cc-help` | Show this help inside Claude Code (zero tokens) |
| `cc-dash` | Standalone dashboard (separate terminal) |
| `cc-doctor` | Diagnose config drift / broken installs / env-var overrides |

In Claude Code, all commands are also available with the `!` prefix to run them without consuming tokens:
- `!cc-help`
- `!cc-switch deepseek pro`
- `!cc-balance`
- `!cc-doctor`

---

## Status line modes

**`single`** (default fallback, 1 line)
```
◆ DS-pro │ ███▅ 26% ctx │ ⬇1.2M ⬆365k │ ↯99% hit │ ¥22.89 │ ¥30.77
```

**`wide`** (2 lines)
```
◆ MM-m3  MiniMax-M3  ·  ¥22.89/¥68.14  ·  91% 5h
  ⬇1.2M input  ⬆365.2k output  1.5M total  ↯99%  ████▂ 58%
```

**`full`** (3-line boxed dashboard — renders in a separate Python script for proper box alignment)

Switch with `cc-mode wide`.

---

## Diagnostics — `cc-doctor`

When something feels off (status line rendering wrong, hooks silently failing, banner showing the wrong provider), run `cc-doctor`:

```bash
cc-doctor          # human-readable report
cc-doctor --json   # machine-readable (for scripting)
cc-doctor --fix    # apply safe auto-fixes (stale rc-file exports, missing ~/.local/bin symlinks)
```

It checks 11 things and reports each as `OK`, `WARN`, or `FAIL`:

| Check | What it looks at |
|---|---|
| `env_override` | stale `CC_KIT_DIR`/`CC_KIT_ROOT`/`MONITOR_DATA_DIR` exports in `~/.bashrc` and `~/.zshrc` |
| `duplicate_sources` | multiple `source init.sh` or `source provider.env` lines in rc files |
| `install_path` | `bin/`, `modules/`, `hooks/`, `init.sh`, `install.sh` all present |
| `provider_env` | `data/provider.env` has a valid `ANTHROPIC_BASE_URL` and `ANTHROPIC_MODEL` |
| `key_*` | API keys in `data/secrets.env` are present and the file is `chmod 600` (values are masked) |
| `balance_cache` | `.balance_cache` is fresh (< 10 min old) |
| `settings_json` | `~/.claude/settings.json` has `statusLine` + `SessionStart` + `Stop` hooks |
| `symlinks` | every `bin/cc-*` is symlinked into `~/.local/bin` |
| `self_locate` | every path-aware bash script uses `BASH_SOURCE[0]` |
| `env_selflocate` | `$CC_KIT_DIR` env (if set) matches the self-located install dir |

Exit codes: `0` = no FAIL findings, `1` = at least one FAIL. The tool is **read-only by default** — `--fix` only touches rc files (delete stale exports) and `~/.local/bin/` (create missing symlinks). It never edits `secrets.env`, `provider.env`, or `settings.json`.

---

## Supported providers

| Provider | Endpoint | Currency | Notes |
|---|---|---|---|
| DeepSeek | `https://api.deepseek.com/anthropic` | ¥ | Pro / Flash, fast & cheap |
| MiniMax | `https://api.minimaxi.com/anthropic` | ¥ | M2.7 / M3 / highspeed |
| Anthropic | `https://api.anthropic.com` (default) | $ | Opus / Sonnet / Haiku |

API keys are stored in `~/.cc-kit/data/secrets.env` (mode 0600). They are never logged or transmitted.

---

## How it works

1. **install.sh** copies the toolkit to `~/.cc-kit/`, then merges hooks + statusLine into `~/.claude/settings.json`
2. **cc-switch** writes `ANTHROPIC_BASE_URL` / `ANTHROPIC_MODEL` / etc. to `~/.cc-kit/data/provider.env`, which `~/.bashrc` sources
3. **cc-status** runs on every Claude Code prompt (5-second refresh) and reads the live JSONL session log to compute tokens & cost
4. **Stop hook** records session totals to `~/.cc-kit/data/usage.db` for cumulative tracking
5. **SessionStart hook** shows a one-line status banner (zero tokens)

See [docs/](docs/) for details.

---

## Platform support

| OS | Bash | Status |
|---|---|---|
| **Ubuntu 24.04** (and most modern Linux) | bash 5.x | ✅ Fully tested in CI (lint + 39 bats tests + install smoke test on every push) |
| **Ubuntu 20.04 / 22.04 / Debian** | bash 4.x / 5.x | ✅ Should work — no GNU-only utilities in hot paths |
| **macOS 14 Sonoma / 15 Sequoia** | bash 3.2 (Apple's default) | ⚠️ Best-effort — scripts are written defensively (no `${var//pat/rep}`, no `stat -c`, no `find -printf`, `date -r FILE` instead of `stat -c %Y`) but no CI runner is available to the maintainer to verify every path. **If you hit an issue on macOS, please open an issue with the output of `bash -x ./install.sh` and the failing command.** |

If you specifically need macOS CI coverage, see [`docs/INSTALL.md`](docs/INSTALL.md#macos-specifics) for the full list of intentional portability workarounds and [`CONTRIBUTING.md`](docs/CONTRIBUTING.md) for how to add a macOS verification path (a maintainer with a Mac is the only way to make this green).

---

## Installation troubleshooting

If you hit issues, see [docs/INSTALL.md](docs/INSTALL.md) for:
- bash 3.2 vs bash 5 (cc-kit works on both — no need to upgrade)
- BSD grep vs GNU grep
- PATH not picking up `~/.local/bin`
- Manual `settings.json` edit

For provider-specific setup: [docs/PROVIDERS.md](docs/PROVIDERS.md).

---

## Contributing

See [CONTRIBUTING.md](docs/CONTRIBUTING.md). PRs welcome — keep the design simple, ship small.

Found a security issue? Email or open a private advisory — see [SECURITY.md](docs/SECURITY.md).

---

## License

[Apache 2.0](LICENSE) — commercial use, modification, and distribution permitted.
