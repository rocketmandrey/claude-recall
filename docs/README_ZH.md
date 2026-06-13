# claude-recall

[English](../README.md) | [Russian / Русский](README_RU.md)

让你成百上千的 Claude Code 历史会话不再是一座坟场：只需说"找到我导出那个客户交易数据
的会话"——一秒钟内你就能得到项目路径、解决方法、成品链接，以及三种继续工作的方式。

**工作原理：** 每个结束的会话由小模型（haiku）压缩成一张 recap 卡片；所有卡片汇总到
一个 INDEX.md——每个会话一行，瞬间可检索。这是你和所有智能体的唯一接触点。附带的
skill 让任何 Claude Code 会话都能搜索索引并恢复过去的工作。

**零依赖**——单个 Python 文件，无需 API 密钥（使用你现有的 `claude` 登录授权）。

```
会话结束           → SessionEnd 钩子      → recap 卡片（+ handoff，如已启用）
压缩器 (haiku)     → 提炼成卡片           → ~/.claude/session-recaps/<id>.md
索引               → 每个会话一行         → INDEX.md  ← 唯一接触点
编排器 (skill)     → find → show → finish | handoff | spawn

可选: handoff 循环 → PreCompact 钩子写入最新 HANDOFF（当前任务 / 已完成 /
                     进行中 / 下一步 / 注意事项）→ SessionStart 重新注入 ——
                     会话醒来时清楚知道刚才做到哪里
```

recap 卡片是十行 YAML：

```yaml
id: c2631a96-...
project: ~/Documents/Cursor/my-crm
task: 将离职物流专员 Ivanova 的交易导出到 Google Sheet
status: done
method: skill export-dismissed + Sheets API
entities: [Ivanova, Bitrix]
artifacts: [https://docs.google.com/spreadsheets/d/...]
next: null
```

## 三种交互模式

| 模式 | 你说 | 发生什么 |
|------|------|----------|
| **finish** | "再做一次那个导出，这次是客户X" | Claude 找到过去的会话，提取项目+方法，就地重做任务 |
| **handoff** | "给我命令" | `recall cmd <id>` → `cd "<project>" && claude --resume <id>` |
| **spawn** | "打开那个会话" | `recall open <id>` —— 新终端窗口打开，会话完整恢复 |

匹配到多个会话时，编排器不会瞎猜——它会显示一个选择器（每个候选：项目文件夹 + 日期 +
任务上下文，外加"深入挖掘"选项）。

## 会话自动命名

每次 recap（以及每次 handoff，如循环已启用）都会顺带给会话命名为
**`文件夹/项目 · 任务`**——使用与 `/rename` 完全相同的机制——让 `claude --resume`
选择器不再是一片 "no name"。标题随任务演进自动刷新。手动设置的名称绝不会被覆盖；
显式命名：`recall rename <id8> <标题>`；关闭：`RECALL_AUTONAME=0`。

## 安装

在 Claude Code 中粘贴：

> 克隆 github.com/rocketmandrey/claude-recall 并运行 ./install.sh。先问我是否启用
> 可选的 handoff 循环，展示它做了哪些更改，然后问我是否运行 `recall backfill`
> （每个历史会话一次小模型调用，几百个会话约 20–40 分钟）。

或手动安装：

```bash
git clone https://github.com/rocketmandrey/claude-recall.git && cd claude-recall
./install.sh              # CLI + skill + SessionEnd 钩子 + 权限
recall backfill           # 可选：索引历史会话
```

`install.sh` 合并写入 `~/.claude/settings.json`（绝不覆盖）：SessionEnd 钩子和
`Bash(recall *)` 权限——智能体在任何新会话中调用 recall 都无需弹窗确认。此后每个
结束的会话（≥15 个事件）都会自动索引。

**handoff 持续性循环是可选的（opt-in）**——安装器会提议，但绝不强制：每次上下文
压缩前，小模型写入一张状态卡片，压缩/恢复后重新注入——会话醒来时清楚知道刚才做到
哪里。成本：每次压缩一次 haiku 调用。参数：`./install.sh --with-handoff` /
`--no-handoff`（不带参数时安装器会询问；重新安装时保留之前的选择）。随时用
`recall doctor` 检查。

## 使用方法

在 Claude Code 中直接说：

- "找到我导出交易数据的那个会话"
- "我们以前做过这个 —— 再为客户X做一次"
- "打开我们做仪表盘的那个会话"
- "我还有哪些没做完的任务？"

### 示例

**重复过去的任务：**
> 再做一次那个离职员工导出，这次是 Svetlana 的常客

**在新窗口打开过去的会话：**
> 打开我们配置部署的那个会话 —— 直接开个窗口

**查询过去的决定：**
> 我们当时关于部署方案是怎么决定的？

## 仓库结构

```
claude-recall/
├── bin/recall              ← 整个产品：单个 Python 文件，零依赖
├── skill/SKILL.md          ← Claude Code 的 session-orchestrator skill
├── install.sh              ← 安装器：CLI + skill + 钩子 + 权限
└── docs/                   ← README 翻译（RU、ZH）
```

## CLI

| 命令 | 功能 |
|------|------|
| `recall find <查询...>` | 搜索索引（不区分大小写，OR；按词干搜索） |
| `recall grep <查询...>` | 对原始转录文件全文检索（索引无结果时的后备） |
| `recall show <id8>` | 打印会话的 recap 卡片 |
| `recall cmd <id8>` | 打印恢复命令（handoff） |
| `recall open <id8> [--fast] [--tab]` | 在新终端窗口打开会话（spawn）；如缺少 handoff 卡片会先生成（`--fast` 跳过）；`--tab` 改为新标签页 |
| `recall remove <id8>` | 遗忘会话：卡片 + 索引行 + 墓碑标记 |
| `recall rename <id8> <标题...>` | 手动设置会话显示名（自动命名不再触碰它） |
| `recall handoff <file.jsonl>` | 为会话写入 handoff 卡片（进行中状态） |
| `recall handoff --all` | 回扫：为缺少卡片的近期会话补写 `[--days N] [--jobs N]` |
| `recall backfill` | 索引现有会话 `[--days N] [--min-events N] [--jobs N]` |
| `recall index` | 索引统计 |
| `recall doctor` | 检查安装 |

环境变量：`RECALL_DATA`（默认 `~/.claude/session-recaps`）、`RECALL_MODEL`（默认
haiku）、`RECALL_TERMINAL`（`Terminal`\|`iTerm`）、`RECALL_MIN_EVENTS`（默认 15）、
`RECALL_HANDOFF_DAYS`（默认 30 —— handoff 保留期）、
`RECALL_AUTONAME`（默认 1 —— 会话自动命名；设 `0` 关闭）、
`RECALL_TAB`（`1` —— `recall open` 默认开标签页；单次改窗口：`--window`）。

## 要求与说明

- macOS（`recall open` 使用 AppleScript；欢迎 Linux PR）、python3 ≥ 3.9、已登录的
  `claude` CLI。
- **本地优先**：卡片和索引永不离开你的机器。但它们包含会话内容的提炼——不要提交或
  分享数据目录。
- recap 调用通过 `claude -p` 进行——使用你现有的授权，无需 API 密钥。工作会话已做
  标记，绝不会索引自身。
- `recall remove` 会设置墓碑标记，钩子/backfill 不会复活它
  （撤销：`recall recap <transcript> --force`）。
- handoff 卡片（如已启用循环）每个仅几 KB，30 天后自动清理；长期记忆存于 recap
  卡片。通过 `recall open` 恢复的会话会自动收到自己的 handoff——醒来即知下一步。
  没有卡片的旧会话会在打开时现场生成（约 30 秒；`--fast` 跳过），或一次性回扫：
  `recall handoff --all --days 14`。
- 如索引无结果，`recall grep` 会对 `~/.claude/projects/` 中的原始转录文件做全文
  检索——无需任何额外工具。
- 标签页：iTerm 中 `recall open --tab` 原生且可靠，且每个标签**按项目着色**
  （iTerm OSC-6）——垂直标签栏中同项目的会话以色条分组（标签栏置左：iTerm →
  Settings → Appearance → Tab bar location）。Terminal.app 无标签页 API，recall
  通过 System Events 模拟 ⌘T（尽力而为：需辅助功能权限，且即便有权限，脚本化
  ⌘T 仍可能因焦点丢失而失败）。recall 会校验标签页是否真的出现，否则改开新
  窗口——绝不会把命令注入到忙碌的标签页。需要可靠的彩色标签页请用 iTerm。

## 致谢

recall 源于对 Valerii Kovalskii 的 [codbash](https://github.com/vakovalskii/codbash)
（AI 编码会话仪表盘 + 全文检索）的日常使用。recall 不包含其任何代码、也不依赖它，
但"把过去的会话当作可检索资产"这一理念正来自与 codbash 共处的日子；`recall grep`
则是对 codbash 完整能力（网页仪表盘、跨智能体会话同步）的刻意极简致敬。想要完整
体验，请安装 codbash。Respect, Valera!

## 许可证

MIT
