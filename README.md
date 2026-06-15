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

```bash
curl -fsSL https://raw.githubusercontent.com/Huadous/cc-kit/main/install.sh | bash
```

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

In Claude Code, all commands are also available with the `!` prefix to run them without consuming tokens:
- `!cc-help`
- `!cc-switch deepseek pro`
- `!cc-balance`

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

## Installation troubleshooting

If you hit issues, see [docs/INSTALL.md](docs/INSTALL.md) for:
- bash 4 vs macOS 3.2
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
