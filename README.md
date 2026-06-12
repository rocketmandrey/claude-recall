# claude-recall

[Russian / Русский](docs/README_RU.md) | [Chinese / 中文](docs/README_ZH.md)

![Claude Code](https://img.shields.io/badge/Claude_Code-skill+CLI-orange?style=flat-square)
![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)
![Version](https://img.shields.io/badge/version-0.2.0-blue?style=flat-square)
![Zero deps](https://img.shields.io/badge/dependencies-0-blue?style=flat-square)
![macOS](https://img.shields.io/badge/platform-macOS-lightgrey?style=flat-square)

Your hundreds of past Claude Code sessions stop being a graveyard: say *"find the
session where I exported that client's deals"* — and in a second you have the project,
the method, the link to the finished artifact, and three ways to act on it.

**How it works:** every finished session is distilled by a small LLM (haiku) into a
recap card; all cards roll up into one greppable INDEX.md — the single touchpoint for
you and your agents. A bundled skill teaches any Claude Code session to search it and
resume past work.

**Zero dependencies** — one Python file, no API keys (uses your existing `claude` auth).

```
SESSION ENDS        → SessionEnd hook        → transcript .jsonl
RECAPPER (haiku)    → distills into a card   → ~/.claude/session-recaps/<id>.md
INDEX               → one line per session   → INDEX.md  ← the single touchpoint
ORCHESTRATOR (skill)→ find → show → finish | handoff | spawn
```

A recap card is ten lines of YAML:

```yaml
id: c2631a96-...
project: ~/Documents/Cursor/my-crm
task: Export deals of dismissed logist Ivanova to a Google Sheet for the sales lead
status: done
method: skill export-dismissed + Sheets API
entities: [Ivanova, Bitrix]
artifacts: [https://docs.google.com/spreadsheets/d/...]
next: null
```

## Three interaction modes

| mode | you say | what happens |
|------|---------|--------------|
| **finish** | "do that export again, for client X" | Claude finds the past session, extracts project + method, redoes the task right here |
| **handoff** | "give me the command" | `recall cmd <id>` → `cd "<project>" && claude --resume <id>` |
| **spawn** | "open that session" | `recall open <id>` — a new terminal window opens with the session restored |

When several sessions match, the orchestrator doesn't guess — it shows a selector
(project folder + date + task context per candidate, plus a "dig deeper" option).

## Installation

Paste this into Claude Code:

> Clone github.com/rocketmandrey/claude-recall and run ./install.sh. Show me what it
> changed, then ask me whether to run `recall backfill` (one small-LLM call per past
> session, ~20–40 min for a few hundred).

Or manually:

```bash
git clone https://github.com/rocketmandrey/claude-recall.git && cd claude-recall
./install.sh              # CLI + skill + SessionEnd hook + permissions
recall backfill           # optional: index your past sessions
```

`install.sh` merges into `~/.claude/settings.json` (never overwrites): the SessionEnd
hook and `Bash(recall *)` permissions, so agents can call recall in any new session
without prompts. From then on every finished session (≥15 events) is indexed
automatically. Verify anytime with `recall doctor`.

## Usage

Just say in Claude Code:

**English:**
- "find the session where I exported those deals"
- "we've done this before — do it again for client X"
- "open the session where we built the dashboard"
- "what do I have unfinished?"

**Русский:**
- «найди сессию, где я выгружал сделки»
- «мы это уже делали — сделай ещё раз по клиенту X»
- «открой сессию, где мы пилили дашборд»
- «что у меня висит недоделанного?»

**中文:**
- "找到我导出交易数据的那个会话"
- "我们以前做过这个 — 再为客户X做一次"
- "打开我们做仪表盘的那个会话"
- "我还有哪些没做完的任务？"

### Examples

**EN — repeat a past task:**
> Do that dismissed-employees export again, but for Svetlana's regulars

**RU — открыть прошлую сессию в новом окне:**
> Открой сессию, где мы настраивали деплой welly — прям окошком

**ZH — 查询过去的决定:**
> 我们当时关于部署方案是怎么决定的？

## Repository structure

```
claude-recall/
├── bin/recall              ← the whole product: one Python file, zero deps
├── skill/SKILL.md          ← session-orchestrator skill for Claude Code
├── install.sh              ← installer: CLI + skill + hook + permissions
└── docs/                   ← README translations (RU, ZH)
```

## CLI

| command | what it does |
|---------|--------------|
| `recall find <query...>` | search the index (case-insensitive OR; search by word STEM) |
| `recall show <id8>` | print a session's recap card |
| `recall cmd <id8>` | print the resume command (handoff) |
| `recall open <id8>` | open the session in a new terminal window (spawn) |
| `recall remove <id8>` | forget a session: card + index line + tombstone |
| `recall backfill` | index existing sessions `[--days N] [--min-events N] [--jobs N]` |
| `recall index` | index stats |
| `recall doctor` | check installation |

Env: `RECALL_DATA` (default `~/.claude/session-recaps`), `RECALL_MODEL` (default haiku),
`RECALL_TERMINAL` (`Terminal`\|`iTerm`), `RECALL_MIN_EVENTS` (default 15).

## Requirements & notes

- macOS (`recall open` uses AppleScript; Linux PRs welcome), python3 ≥ 3.9, logged-in `claude` CLI.
- **Local-first**: cards and the index never leave your machine. They do contain
  distilled session content — don't commit or share the data dir.
- Recap calls go through `claude -p` — your existing auth, no API key. Worker sessions
  are marked and never index themselves.
- `recall remove` tombstones a session so hook/backfill won't resurrect it
  (undo: `recall recap <transcript> --force`).
- Pairs well with [codbash](https://www.npmjs.com/package/codbash-app) as full-text
  fallback and web dashboard; not required.

## License

MIT
