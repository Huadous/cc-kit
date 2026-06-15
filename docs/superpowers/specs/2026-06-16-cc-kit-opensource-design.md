# cc-kit 开源化设计文档

**日期**：2026-06-16
**状态**：草案 v1（待用户审核）
**目标**：把私人项目 `~/projects/cc-kit/` 重构为可分发的开源项目

---

## 0. 项目元信息

| 项 | 值 |
|---|---|
| 项目名 | `cc-kit`（沿用） |
| 一句话定位 | Claude Code 的增强工具集 — 多 provider 切换、token/成本监控、可定制 statusLine |
| License | Apache 2.0 |
| 托管 | GitHub |
| README 语言 | 双语（中文表 / 英文里） |
| CLI 错误信息 | 中英双语 |
| 默认安装路径 | `~/.cc-kit/` |
| 数据存放 | 项目内 `data/` 目录 |
| 系统依赖 | bash ≥ 4、python3 ≥ 3.8、curl、bc、awk、grep |
| 第三方 Python 包 | 无（仅 stdlib） |

**目标用户**：Claude Code 用户，重点服务使用 DeepSeek / MiniMax 等中国/低成本 provider 的人。

---

## 1. 整体架构

```
cc-kit/
├── .github/
│   ├── workflows/ci.yml          # shellcheck + pyflakes + bats
│   ├── ISSUE_TEMPLATE/bug.md
│   ├── ISSUE_TEMPLATE/feature.md
│   └── PULL_REQUEST_TEMPLATE.md
├── bin/                          # 可执行脚本
│   ├── cc-status                 # 主 statusLine (single/wide/full)
│   ├── cc-status-full.py         # full 模式 Python 渲染
│   ├── cc-dash.py                # 独立 dashboard
│   ├── cc-switch                 # 切换 provider/model
│   ├── cc-balance                # 查余额/coding plan 配额
│   ├── cc-mode                   # 切换 statusLine 布局
│   └── cc-help                   # 帮助
├── modules/                      # 内部 bash 库（仅 source）
│   ├── monitor.sh                # token/成本解析
│   └── switch.sh                 # provider/model 切换逻辑
├── hooks/                        # Claude Code 钩子
│   ├── stop-record.sh
│   └── session-start.sh
├── tests/                        # bats 单元测试
│   ├── monitor.bats
│   ├── switch.bats
│   └── balance.bats
├── install.sh                    # 入口：一键安装
├── uninstall.sh                  # 入口：一键卸载
├── init.sh                       # bash 入口（被 ~/.bashrc source）
├── Makefile                      # make test / make lint / make install-local
├── data/                         # 运行时状态（全部 gitignored）
│   ├── .gitignore                # * + !*.example + !.gitignore
│   ├── .gitkeep                  # 占位
│   ├── provider.env.example      # 模板（提交）
│   ├── secrets.env.example       # 模板（提交）
│   ├── provider.env              # 实际配置（不提交，chmod 600）
│   ├── secrets.env               # 实际密钥（不提交，chmod 600）
│   ├── .display_mode             # 当前显示模式
│   ├── .balance_cache            # 10min TTL 余额缓存
│   └── usage.db                  # 累计使用统计
├── docs/
│   ├── README.zh.md
│   ├── INSTALL.md                # 故障排查
│   ├── PROVIDERS.md              # 各 provider 配置
│   ├── CONTRIBUTING.md
│   ├── SECURITY.md
│   ├── FAQ.md
│   └── superpowers/specs/        # 设计文档（本文件）
├── .gitignore                    # 顶层
├── .editorconfig
├── .shellcheckrc
├── .pre-commit-config.yaml       # 可选 gitleaks
├── LICENSE                       # Apache 2.0
├── README.md                     # 英文为主
└── CHANGELOG.md
```

**核心抽象**：

- `install.sh` 是用户唯一入口
- `bin/*` 是用户唯一交互界面
- `modules/*` 是实现细节（其他目录不允许 source 它们之外的）
- `data/` 是唯一可变状态区，**和代码严格分离**（`.gitignore` + `data/.gitignore` 嵌套保护）

**文件职责（按层）**：

| 层 | 谁可以调 | 谁可以改 |
|---|---|---|
| 用户 CLI | `bin/*` | 用户 |
| 库 | `modules/*`（被 bin 和 hooks source） | 项目维护者 |
| 钩子 | `hooks/*`（被 settings.json 引用） | 项目维护者 |
| 状态 | `data/*`（运行时生成） | cc-kit 自己 |

---

## 2. Install 机制 + 路径重写

### 2.1 `__CC_KIT_DIR__` 占位符

**问题**：当前 16 处硬编码 `~/projects/cc-kit/`，无法在其他机器运行。

**方案**：源码中所有需要 `CC_KIT_DIR` 的位置统一使用占位符：

```bash
CC_KIT_DIR="${CC_KIT_DIR:-__CC_KIT_DIR__}"
```

- 默认值是 `__CC_KIT_DIR__`，install 时 `sed` 替换为真实路径
- 测试时可临时 `CC_KIT_DIR=/tmp/test bash bin/cc-status`

**源码中需要改的位置**（已 grep 确认）：

```
init.sh:2
hooks/session-start.sh:3,8
hooks/stop-record.sh:3,6
install.sh:30,47,106
bin/cc-dash.py:20
bin/cc-help:30
bin/cc-balance:5
bin/cc-switch:3
bin/cc-status:13,154
bin/cc-status-full.py:6
bin/cc-mode:6
```

### 2.2 `install.sh` 流程

1. **预检**：
   - 检查 `bash ≥ 4`（用 `BASH_VERSINFO`）
   - 检查 `python3 ≥ 3.8`（用 `python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3,8) else 1)'`）
   - 检查 `curl`、`bc`、`awk`、`grep` 存在
   - 检查 `~/.claude/` 存在
   - 检查 `~/.cc-kit/` 不存在（否则提示先 uninstall）
2. **路径决策**：
   - 默认 `CC_KIT_ROOT=~/.cc-kit/`
   - 接受 `CC_KIT_ROOT=/custom/path ./install.sh` 覆盖
3. **复制代码**：
   - `cp -r bin modules hooks init.sh install.sh uninstall.sh Makefile "$CC_KIT_ROOT/"`
   - `mkdir -p "$CC_KIT_ROOT/data"`
   - 复制 `data/*.example` → `data/*`（去 `.example` 后缀）
   - `chmod 600 "$CC_KIT_ROOT/data/secrets.env"`
4. **路径重写**：
   - `sed -i "s|__CC_KIT_DIR__|$CC_KIT_ROOT|g" $CC_KIT_ROOT/bin/* $CC_KIT_ROOT/modules/* $CC_KIT_ROOT/hooks/* $CC_KIT_ROOT/init.sh`
5. **配置 Claude Code**：
   - 备份 `~/.claude/settings.json` → `~/.cc-kit/.backup/settings.json`
   - 用 `jq`（fallback `python3`）合并写入 `statusLine`、`statusLineRefreshInterval`、`hooks`
   - **冲突检测**：如果 `statusLine` 字段已存在（被别的工具占用），abort 并提示用户手动合并；不强制覆盖
   - 如果 `jq` 和 `python3` 都没有，提示用户手动操作
6. **配置 PATH**：
   - 创建 `~/.local/bin/cc-*` symlink 指向 `$CC_KIT_ROOT/bin/cc-*`
   - 检查 `~/.local/bin` 在 `$PATH`；如果不在，追加 `export PATH="$HOME/.local/bin:$PATH"` 到 `~/.bashrc`
7. **配置 bashrc**：
   - 追加到 `~/.bashrc`：
     ```bash
     # cc-kit — Claude Code extensions toolkit
     [ -f "$HOME/.cc-kit/init.sh" ] && source "$HOME/.cc-kit/init.sh"
     ```
   - 用 cc-kit 标记（`# BEGIN cc-kit` / `# END cc-kit`）包裹，便于卸载
8. **首次运行**：
   - 提示用户运行 `exec bash` 或重开终端
   - 提示运行 `cc-switch <provider>` 第一次配置

### 2.3 `uninstall.sh` 流程

1. 读取 `~/.cc-kit/.backup/settings.json` → 恢复 `~/.claude/settings.json`
2. 从 `~/.bashrc` 移除 `cc-kit` 标记段
3. 删除 `~/.local/bin/cc-*` symlinks
4. 询问用户：`Keep data directory? [Y/n]` — 默认 Y（保留 API key + usage 统计），输入 n 才 `rm -rf` 整个目录

### 2.4 错误处理

- 预检失败：`exit 1` + 明确错误信息
- 路径已存在：询问 `reinstall? [y/N]`，不输入默认 N
- settings.json 合并失败：保留原始文件 + 打印 jq/python 手动修复命令
- PATH 不在 bashrc：自动追加，但提示用户重开 shell

### 2.5 数据迁移（如果用户从 `~/projects/cc-kit/` 升级）

`install.sh` 检测到旧路径存在时，提供：
- 自动 `mv ~/projects/cc-kit/data ~/.cc-kit/data` 迁移状态
- 提示用户 `rm -rf ~/projects/cc-kit` 清理旧代码

---

## 3. 密钥处理 + 安全模型

### 3.1 威胁模型

| 资产 | 威胁 | 缓解 |
|---|---|---|
| API key | 误提交 git | 双层 `.gitignore` + 可选 gitleaks |
| API key | `ps` 输出泄露 | 仅在 `secrets.env` 文件里 |
| usage.db | session 内容摘要 | 全部 gitignored |
| 用户 prompt | cc-kit 不收集 | 零 telemetry，纯本地 |
| 第三方依赖 | supply chain | 0 第三方包（仅 stdlib） |
| install.sh curl pipe | MITM | 文档建议 `curl -fsSL` + 用户验证 GPG 签名（v0.2+） |

### 3.2 `.gitignore` 顶层

```
data/provider.env
data/secrets.env
data/.balance_cache
data/.display_mode
data/usage.db
data/.backup/
.DS_Store
*.swp
*.bak
.idea/
.vscode/
__pycache__/
```

### 3.3 `data/.gitignore` 嵌套（防御性）

```
# 忽略本目录除示例和自身之外的所有内容
*
!.gitignore
!.gitkeep
!*.example
```

### 3.4 密钥掩码

`mask_value()`（已存在）统一处理：
- 长度 ≤ 8：`****`
- 长度 > 8：`前4****后4`

**应用到所有**：
- `cc-switch` 输出
- 任何错误回显的 key
- 调试日志（如果加 verbose 模式）

### 3.5 错误信息清洗

- 任何 curl 响应失败：只回显 HTTP 状态码
- JSON 解析失败：只说"parse failed"，不回显 raw JSON（避免其中意外包含 key）
- 使用 `set -u` 避免未定义变量泄露

### 3.6 依赖透明

- `requirements.txt` 空文件（仅声明无依赖）
- `INSTALL.md` 列出所有系统包
- macOS 特殊说明：BSD `grep -oE` 与 GNU 略有差异，文档建议 `brew install grep` 后设置 `PATH`

### 3.7 Pre-commit hook（可选）

`.pre-commit-config.yaml`：
```yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

`install.sh` 询问用户是否启用。不强制。

---

## 4. 测试 + CI

### 4.1 静态检查（PR 必跑）

- `shellcheck -S warning bin/* modules/* hooks/* install.sh init.sh`
- `python3 -m pyflakes3 bin/*.py`
- `bash -n` 全部 `.sh` 文件
- 占位符检查：`! grep -r "__CC_KIT_DIR__" bin/ modules/ hooks/ init.sh` 必须 0 命中

### 4.2 Bats 单元测试

`tests/monitor.bats`：测试 token 解析、cache hit rate、成本计算（用 fixture JSONL 文件）

`tests/switch.bats`：测试 `cc-switch` 的 case 分支（deepseek/minimax/anthropic + 各 model）

`tests/balance.bats`：用 mock curl（`tests/mocks/curl`）喂假 JSON

**目标**：核心逻辑覆盖 70%+。`bin/cc-status` 的渲染部分只做 smoke test（手动验证）。

### 4.3 Makefile

```makefile
.PHONY: test lint install-local clean

test:
	bats tests/

lint:
	shellcheck -S warning bin/* modules/* hooks/* install.sh init.sh
	python3 -m pyflakes3 bin/*.py
	bash -n install.sh init.sh
	@if grep -r "__CC_KIT_DIR__" bin/ modules/ hooks/ init.sh 2>/dev/null; then \
		echo "ERROR: __CC_KIT_DIR__ placeholder not replaced"; exit 1; \
	fi

install-local:
	CC_KIT_ROOT=$$HOME/.cc-kit-test ./install.sh

clean:
	rm -rf $$HOME/.cc-kit-test/
```

### 4.4 CI 工作流 (`.github/workflows/ci.yml`)

- OS matrix：`ubuntu-latest`, `macos-latest`
- 步骤：`checkout` → `install bats` → `make lint` → `make test`
- 不调用真实 API（避免 secret 暴露）

---

## 5. 文档

### 5.1 README 策略

- **`README.md`**（英文，GitHub 默认）：
  - 1 张 statusLine 截图/GIF
  - 6 个 feature bullet
  - Quick Start：`curl ... | bash` 一行
  - 链接到 `docs/README.zh.md`、`docs/INSTALL.md`、`docs/PROVIDERS.md`
- **`docs/README.zh.md`**：完整中文版（README.md 的镜像 + 本地化）
- **`docs/INSTALL.md`**：故障排查
  - PATH 问题
  - bash 4 vs 3.2（macOS 默认）
  - macOS BSD grep 差异
  - settings.json 手动修复步骤
- **`docs/PROVIDERS.md`**：DeepSeek / MiniMax / Anthropic 三家详细配置
  - 申请 key 链接
  - 价格表
  - 各 model ID 含义
  - 限额说明（MiniMax coding plan 5h/周窗口）
- **`docs/CONTRIBUTING.md`**：PR 流程、本地开发、code style
- **`docs/SECURITY.md`**：如何负责任地报漏洞（GitHub Security Advisories）
- **`docs/FAQ.md`**：常见问题

### 5.2 截图

- README 顶部的 GIF：用一个真 session 录 30 秒
- 三种 statusLine 模式各一张
- 放在 `docs/images/`

### 5.3 文档同步

- CHANGELOG.md 跟随 semver 手动更新
- 不自动生成（cc-kit 没有 standard library 那么大）

---

## 6. 首次发布清单

按顺序：

1. 拆出独立 git repo
   - 当前 `~/projects/cc-kit/` → 新 `~/projects/cc-kit-oss/`
   - 第一次 commit 包含所有源码（不包含 data/）
2. 代码层所有改动
   - 路径占位符替换（16 处）
   - `.gitignore` / `data/.gitignore`
   - `install.sh` 完善（5 个失败兜底）
   - `uninstall.sh` 新建
   - `Makefile` 新建
   - bats 测试新建
   - CI workflow 新建
3. 跨平台验证
   - 在自己的另一台机器 / Docker container 跑 install.sh
   - macOS + Linux 各验证一次
4. 文档
   - LICENSE (Apache 2.0)
   - README.md + docs/README.zh.md
   - INSTALL.md / PROVIDERS.md / CONTRIBUTING.md / SECURITY.md / FAQ.md
   - 3 张截图
5. 第一次 release
   - commit + tag `v0.1.0`
   - GitHub 创建 repo + push
   - 启用 Issues + Discussions
6. 推广（可选）
   - 推特 / X
   - V2EX
   - 少数派
   - awesome-claude-code 列表

---

## 7. 非目标（明确不做）

- 不做 Windows 原生支持（WSL2 可用，但不做 win32 路径处理）
- 不做 GUI（保持 CLI + statusLine）
- 不做云端 dashboard（一切本地）
- 不做 plugin marketplace（保持单 repo 简单分发）
- 不做 OAuth/SSO 流程（API key 模式足够）
- 不做 i18n 切换（README 双语即够，CLI 错误中英双语硬编码）

---

## 8. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 用户从 DeepSeek/MiniMax 切到 Anthropic 时余额不显示 | statusLine 检测 `AN` 标签时不显示余额 |
| macOS bash 3.2 不支持 `${var,,}` 之类 | 不使用 bash 4+ 特性，或明确要求 `brew install bash` |
| `secrets.env` 文件被同步到云盘（iCloud/Dropbox） | 文档提醒；不在云盘目录下默认安装 |
| 路径 sed 替换出错（如包含 `/`） | 用 `|` 作为 sed 分隔符；CC_KIT_ROOT 强制 normalize |
| `jq` 不存在 | fallback 到 `python3` 内联 |
| `~/.local/bin` 已有同名二进制 | 提示用户冲突，覆盖需 `--force` |
| cc-kit 升级破坏用户 settings.json | install 检测 schema 兼容性；v0.x 期间明确 breaking change 在 CHANGELOG |
| Claude Code 自身更新改变 statusLine 协议 | 文档说明；测试覆盖 JSON stdin 解析 |
| MiniMax/DeepSeek API 字段变化 | `query_minimax/query_deepseek` 函数化 + 单元测试用 mock |

---

## 9. 未来扩展（v1.x+）

- [ ] v0.2：GPG 签名 install.sh
- [ ] v0.3：`cc-web` 子命令 — 起一个本地 HTTP server，看 dashboard
- [ ] v0.4：OpenAI/Google provider 支持
- [ ] v0.5：插件系统（用户写自己的 provider 适配器）
- [ ] v1.0：稳定 API，向后兼容承诺
- [ ] v1.x：i18n 完整支持（i18n 目录 + gettext）

---

## 10. 决策日志

| 决策 | 选项 | 选定 | 原因 |
|---|---|---|---|
| 定位 | 4 种 | Claude Code 增强工具集 | 用户选择 |
| 语言 | 4 种 | 中英双语 | 用户选择 |
| 托管 | 3 种 | GitHub | 用户选择 |
| 密钥 | 4 种 | 本地 .env + chmod 600 | 用户选择 |
| License | 4 种 | Apache 2.0 | 用户选择 |
| 安装路径 | 3 种 | `~/.cc-kit/` | 用户选择 |
| 数据目录 | 3 种 | 项目内 `data/` | 用户选择 |
| 路径重写方案 | 3 种 (sed 占位符 / 动态解析 / Makefile) | sed 占位符 | 最简单 |
