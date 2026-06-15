# Frequently asked questions

## General

### What is cc-kit?

A local-only toolkit that extends Anthropic's Claude Code with:
multi-provider switching, real-time token & cost monitoring, and a
configurable status line.

### Does it work without Claude Code?

No. cc-kit is a Claude Code add-on. It needs `~/.claude/` to exist.

### Is my data sent anywhere?

**No.** cc-kit makes API calls only to the provider you configure
(DeepSeek, MiniMax, Anthropic). The only outbound calls are:
- `cc-balance` → provider's balance API
- LLM traffic from Claude Code itself (via `ANTHROPIC_BASE_URL`)

There is **no telemetry, no phone-home, no analytics**. The
`usage.db` and `provider.env` stay on your machine.

---

## Installation

### `install.sh` says "pre-flight failed"

Read the failed checks. Most common:
- macOS with bash 3.2 → `brew install bash`
- `~/.claude/` missing → run Claude Code once

See [INSTALL.md](INSTALL.md) for full troubleshooting.

### Can I install to a custom path?

```bash
CC_KIT_ROOT=~/my/path ./install.sh
```

### Will it overwrite my existing settings.json?

**No.** install.sh backs up to `~/.cc-kit/.backup/settings.json.<timestamp>`
before any change, and refuses to overwrite a `statusLine` field already
present from another tool.

### How do I uninstall?

```bash
./uninstall.sh
```

It restores the backup, removes the bashrc block, deletes symlinks, and
asks before removing `data/` (your API keys + history).

---

## Provider switching

### `cc-switch` saved my key, can I see it?

No — it's stored in `~/.cc-kit/data/secrets.env` (mode 0600). The
`cc-switch` command shows only a masked form like `sk-5****dfd5`.

To replace a key: `cc-switch deepseek --new-key`.

### Will the new provider take effect immediately?

**The env vars do. The Claude Code session does not.**

`cc-switch` writes new env vars to `provider.env`. The next Claude Code
session will use them. The current session is still using whatever was
loaded at process start.

Workaround: restart Claude Code after switching.

### Why does the status line still show the old model name?

Same reason as above. Once you restart Claude Code, the new model
appears in the status line within 5 seconds (the refresh interval).

---

## Cost & tokens

### Is the cost calculation accurate?

For the listed providers (DeepSeek, MiniMax, Anthropic), yes, using the
official pricing. The `cache_read` cost is **1/10** of input cost, as
charged by DeepSeek and MiniMax.

For other providers, edit `modules/monitor.sh` -> `monitor_pricing()`.

### My actual bill is different. Why?

Possible reasons:
- cc-kit only counts **this** Claude Code session's tokens. It doesn't see
  what curl / your other tools are doing.
- Promotional credits, refunds, and tax aren't modeled.
- Provider pricing changes — please open an issue if the listed rates are
  outdated.

### What is "cache hit rate"?

`cache_read_input_tokens / (input_tokens + cache_read_input_tokens)`.
A high hit rate (90%+) means most of your prompt is being served from
cache, which is much cheaper. The status line shows session-level and
global rates.

---

## Status line

### My status line is missing

1. Check `~/.claude/settings.json` has the `statusLine` block from
   [INSTALL.md](INSTALL.md)
2. Restart Claude Code
3. If still missing: `cat ~/.claude/settings.json | python3 -m json.tool`
   to confirm it's valid JSON

### The wide layout has weird spacing

The wide mode uses bash `printf` to align columns. If you have a very
narrow terminal (< 80 cols), it wraps. Resize the terminal or use
`cc-mode single`.

### Color codes look broken

Your terminal doesn't support 256-color ANSI. Try:

```bash
echo $TERM
# should be xterm-256color, screen-256color, or similar
export TERM=xterm-256color
```

---

## Coding plan (MiniMax)

### Why does my balance show "91% 5h" instead of ¥?

You have a **MiniMax coding plan subscription**, not pay-as-you-go.
Coding plan quotas are not monetary — they're request-count windows.
`91% 5h` means "5-hour window is 91% unused, 3h41m until reset".

### Can I see the raw coding plan response?

Run `cc-balance` (not `!cc-balance`) — it prints the full
`general/5h/weekly` numbers.

### I have BOTH coding plan AND pay-as-you-go balance

cc-kit currently queries the coding plan endpoint only. To check your
pay-as-you-go balance, log into https://platform.MiniMax.io.

Support for combined display is on the v0.2 roadmap.

---

## Development

### How do I run tests?

```bash
make test
```

Needs `bats-core` (`brew install bats-core` or `apt install bats`).

### Where's the design doc?

`docs/superpowers/specs/2026-06-16-cc-kit-opensource-design.md`. It's
written in the format the maintainers use internally.
