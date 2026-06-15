# cc-kit — Claude Code 增强工具集

> **多 provider 切换 · 实时 token/成本监控 · 可定制 statusLine**
>
> [English →](../README.md)

---

## 为什么要用 cc-kit？

Anthropic 的 Claude Code 本身很好用，但它有几个默认假设：
- 单一 provider（Anthropic）
- 单一货币（USD）
- 没有可见的 status line

cc-kit 让 Claude Code 适配**你**的实际工作流：
- 🪄 **session 中随时切换 provider** — DeepSeek Pro/Flash、MiniMax M2.7/M3、Anthropic，一条命令搞定
- 📊 **真实成本可视化** — token 用量、cache 命中率、¥ 或 $ 单价
- 🎨 **三种 status-line 模式** — `single`（紧凑）、`wide`（双行）、`full`（三行仪表盘）
- 💰 **余额一目了然** — DeepSeek 账户余额、MiniMax coding plan 配额
- 🔌 **零外部依赖** — 纯 bash + Python 标准库，总共 ~1500 行

无遥测。无云端。数据全部留在本地。

---

## 快速开始

需要 `bash ≥ 4` 和 `python3 ≥ 3.8`，其他依赖现代 macOS / Ubuntu 都自带。

```bash
curl -fsSL https://raw.githubusercontent.com/Huadous/cc-kit/main/install.sh | bash
```

> 注意：用 `bash install.sh`，不要用 `sh install.sh` —— Ubuntu/Debian 的
> `/bin/sh` 是 `dash`，不支持脚本里的 bash 特有语法。上面这行命令已经
> 管道到 `bash`，无需关心。

然后：

```bash
cc-switch deepseek    # 或 minimax / anthropic
# 重启 Claude Code 让新 provider 生效
```

完成。status line 会立刻开始显示实时 token 用量和成本。

---

## 命令一览

| 命令 | 作用 |
|---|---|
| `cc-switch deepseek [pro\|flash]` | 切到 DeepSeek（默认 pro） |
| `cc-switch minimax [m2.7\|m3\|highspeed]` | 切到 MiniMax（默认 m2.7） |
| `cc-switch anthropic` | 还原 Anthropic 默认 |
| `cc-switch show` | 显示当前 provider/model |
| `cc-mode single\|wide\|full` | 切换 status-line 布局 |
| `cc-balance` | 刷新账户余额 / coding plan 配额 |
| `cc-help` | Claude Code 内看帮助（不消耗 token） |
| `cc-dash` | 独立仪表盘（另一个终端） |

在 Claude Code 内，所有命令也支持 `!` 前缀零 token 调用：
- `!cc-help`
- `!cc-switch deepseek pro`
- `!cc-balance`

---

## Status line 模式

**`single`**（默认回退，单行）
```
◆ DS-pro │ ███▅ 26% ctx │ ⬇1.2M ⬆365k │ ↯99% hit │ ¥22.89 │ ¥30.77
```

**`wide`**（双行）
```
◆ MM-m3  MiniMax-M3  ·  ¥22.89/¥68.14  ·  91% 5h
  ⬇1.2M input  ⬆365.2k output  1.5M total  ↯99%  ████▂ 58%
```

**`full`**（三行 boxed 仪表盘 — 用 Python 脚本渲染，保证 box 字符对齐）

切换：`cc-mode wide`

---

## 支持的 provider

| Provider | 端点 | 货币 | 备注 |
|---|---|---|---|
| DeepSeek | `https://api.deepseek.com/anthropic` | ¥ | Pro / Flash，便宜快速 |
| MiniMax | `https://api.minimaxi.com/anthropic` | ¥ | M2.7 / M3 / highspeed |
| Anthropic | `https://api.anthropic.com`（默认） | $ | Opus / Sonnet / Haiku |

API key 存放在 `~/.cc-kit/data/secrets.env`（权限 0600），永不打印或外传。

---

## 工作原理

1. **install.sh** 把工具集复制到 `~/.cc-kit/`，并把 hooks + statusLine 合并进 `~/.claude/settings.json`
2. **cc-switch** 写 `ANTHROPIC_BASE_URL` / `ANTHROPIC_MODEL` 等到 `~/.cc-kit/data/provider.env`，由 `~/.bashrc` source
3. **cc-status** 在每次 Claude Code prompt 时跑（5 秒刷新），读 JSONL session log 算 token/成本
4. **Stop hook** 把 session 累计写到 `~/.cc-kit/data/usage.db` 用于全期统计
5. **SessionStart hook** 显示一行状态横幅（零 token）

详细见 [docs/](docs/)。

---

## 安装故障排查

出问题看 [docs/INSTALL.md](INSTALL.md)，覆盖：
- bash 4 vs macOS 3.2
- BSD grep vs GNU grep
- PATH 没加 `~/.local/bin`
- 手动编辑 settings.json

Provider 特定配置：[docs/PROVIDERS.md](PROVIDERS.md)。

---

## 贡献

见 [CONTRIBUTING.md](CONTRIBUTING.md)。欢迎 PR — 保持设计简单，小步快跑。

发现安全问题：邮件或私下 advisory，详见 [SECURITY.md](SECURITY.md)。

---

## License

[Apache 2.0](../LICENSE) — 允许商用、修改、分发。
