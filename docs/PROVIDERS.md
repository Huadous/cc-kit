# Provider configuration

cc-kit ships with four providers. Each has its own pricing, limits, and
quirks.

## Quick reference

| Provider | Apply for API key | Coding plan? | Currency | Models |
|---|---|---|---|---|
| [DeepSeek](#deepseek) | https://platform.deepseek.com | No (pay-as-you-go) | ¥ | pro, flash |
| [MiniMax](#minimax) | https://platform.MiniMax.io | **Yes** — 5h + weekly windows | ¥ | M2.7, M3, highspeed |
| [GLM / Zhipu](#glm) | https://open.bigmodel.cn | **Yes** — 5h + weekly windows | ¥ | 5.1, 4.7, flash |
| [Anthropic](#anthropic) | https://console.anthropic.com | No (pay-as-you-go) | $ | opus, sonnet, haiku |

---

## DeepSeek

**Endpoint:** `https://api.deepseek.com/anthropic`
**Pricing** (per 1M tokens, cache_read = 1/10 of input):

| Model | Input | Cache read | Output |
|---|---|---|---|
| `deepseek-v4-pro` | ¥2.00 | ¥0.20 | ¥8.00 |
| `deepseek-v4-flash` | ¥1.00 | ¥0.10 | ¥4.00 |

**Setup:**

```bash
cc-switch deepseek         # defaults to pro
# or
cc-switch deepseek flash   # cheaper, slightly less capable
```

You'll be prompted for an API key the first time. The key is stored in
`~/.cc-kit/data/secrets.env` (mode 0600) as `DEEPSEEK_API_KEY=...`.

**Balance:**

```bash
cc-balance          # queries https://api.deepseek.com/user/balance
```

Shows as `¥XX.XX` in the status line.

---

## MiniMax

**Endpoint:** `https://api.minimaxi.com/anthropic`

**Two account types:**

1. **Pay-as-you-go** — balance decreases per token (like DeepSeek)
2. **Coding plan** — flat-fee subscription, two quotas:
   - **5-hour window**: per-model request count
   - **Weekly window**: per-model request count

cc-kit detects coding plan automatically (via the
`/v1/api/openplatform/coding_plan/remains` endpoint) and shows the 5h window
as `XX% 5h` in the status line. The full detail (5h time remaining + weekly
percent) appears in `!cc-balance` output.

**Pricing** (per 1M tokens; applies only if you have pay-as-you-go balance
on top of the coding plan):

| Model | Input | Cache read | Output |
|---|---|---|---|
| `MiniMax-M3` | ¥2.00 | ¥0.20 | ¥8.00 |
| `MiniMax-M2.7` | ¥2.00 | ¥0.20 | ¥8.00 |
| `MiniMax-M2.7-highspeed` | ¥2.00 | ¥0.20 | ¥8.00 |

**Setup:**

```bash
cc-switch minimax            # defaults to M2.7
cc-switch minimax m3         # newest, best quality
cc-switch minimax highspeed  # fastest M2.7 variant
```

**Balance / coding plan query:**

```bash
cc-balance
# Output: 91%  5h:3h41m  wk:100%
#         ^ 5h window remaining%  ^ time until reset  ^ weekly remaining%
```

---

## GLM (Zhipu AI)

**Endpoint:** `https://open.bigmodel.cn/api/anthropic`

GLM (智谱 AI) supports both pay-as-you-go and coding plan. cc-kit uses the
Anthropic-compatible endpoint — the same protocol DeepSeek and MiniMax
implement.

**Pricing** (per 1M tokens, RMB):

| Model | Input | Cache read | Output |
|---|---|---|---|
| `glm-5.1` (<32K input) | ¥6.00 | ¥1.30 | ¥24.00 |
| `glm-5.1` (≥32K input) | ¥8.00 | ¥2.00 | ¥28.00 |
| `glm-4.7` (<32K input) | ¥2.00 | ¥0.40 | ¥8.00 |
| `glm-4.7-flash` | Free | Free | Free |

**Setup:**

```bash
cc-switch glm            # defaults to 4.7 (best value)
cc-switch glm 5.1        # flagship, highest quality
cc-switch glm flash      # free tier
```

You'll be prompted for an API key the first time. The key is stored in
`~/.cc-kit/data/secrets.env` (mode 0600) as `ZHIPU_API_KEY=...`.

Get an API key at https://open.bigmodel.cn (控制台 → API Keys).

**Coding plan:**

GLM has a coding plan subscription similar to MiniMax — a 5-hour window
and a weekly window. cc-kit queries the monitoring API and shows the
5h window as `XX% 5h` in the status line:

```bash
cc-balance
# Output: 85%  5h:2h30m  wk:100%
#         ^ 5h window remaining%  ^ time until reset  ^ weekly remaining%
```

---

## Anthropic

**Endpoint:** default (https://api.anthropic.com)
**No special configuration needed** — `cc-switch anthropic` unsets the
override env vars and lets Claude Code use its built-in config.

```bash
cc-switch anthropic
```

The status line shows `AN` as the provider label. Balance checking is not
supported (use https://console.anthropic.com for usage & billing).

---

## Adding a new provider

To add (say) OpenRouter:

1. Edit `modules/switch.sh` — add a new branch in the `case` statement
2. Add a pricing entry in `modules/monitor.sh`'s `monitor_pricing()`
3. Add a `query_<provider>` function in `bin/cc-balance`
4. Add a `monitor_provider_label` case in `modules/monitor.sh`
5. Add docs to `docs/PROVIDERS.md`
6. Add a bats test in `tests/switch.bats`

Open a PR. See [CONTRIBUTING.md](CONTRIBUTING.md).

---

## Known issues

- **MiniMax connection drops**: set `API_TIMEOUT_MS=3000000` and
  `CLAUDE_CODE_AUTO_COMPACT_WINDOW=512000` in `provider.env`. The
  `cc-switch minimax` command writes these automatically.
- **DeepSeek rate limits**: 60 requests/min on Pro. If you hit them, switch
  to Flash via `cc-switch deepseek flash`.
- **Anthropic: not all models in status line**: `monitor_provider_label`
  only shows `AN`. The exact model comes from `ANTHROPIC_MODEL` and is
  displayed verbatim.
