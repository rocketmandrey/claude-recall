# claude-recall

[Russian / Русский](docs/README_RU.md) | [Chinese / 中文](docs/README_ZH.md)

![Claude Code](https://img.shields.io/badge/Claude_Code-skill+CLI-orange?style=flat-square)
![License: MIT](https://img.shields.io/badge/License-MIT-green?style=flat-square)
![Version](https://img.shields.io/badge/version-0.5.0-blue?style=flat-square)
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
SESSION ENDS        → SessionEnd hook        → recap card (+ handoff if enabled)
RECAPPER (haiku)    → distills into a card   → ~/.claude/session-recaps/<id>.md
INDEX               → one line per session   → INDEX.md  ← the single touchpoint
ORCHESTRATOR (skill)→ find → show → finish | handoff | spawn

OPT-IN: CONTINUITY  → PreCompact hook writes a fresh HANDOFF (task / done /
LOOP                  in flight / next / gotchas) → SessionStart re-injects it —
                      the session wakes up knowing exactly where it left off
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

## Sessions name themselves

Every recap (and every handoff, if the loop is on) also titles the session
**`folder/project · task`** — via the exact mechanism `/rename` uses — so the
`claude --resume` picker stops being a wall of "no name". The title refreshes as
the task evolves. Names you set by hand are never overwritten; set one explicitly
with `recall rename <id8> <title>`; disable with `RECALL_AUTONAME=0`.

## Status line: every tab gets an address

The installer also drops in a Claude Code status line built for running a *fleet* of
sessions. Each bar looks like this:

```
• claude-recall [s034] | 5h:63% 2h0m 7d:18% 2d7h | ctx:45% | e:xh | opus4.8 1M
```

- **`[s034]`** — the killer feature: the tab's **address**. It's the iTerm tty of that
  session. Say *"go to s034"* and the orchestrator injects context straight into that
  exact tab (`osascript … write text`) — no hunting for the right window. The script
  finds the tty by walking **up** the process tree from itself (the status line runs on
  a pipe with no tty of its own) to the `claude` process that owns the real terminal;
  if nothing is found it falls back to the first 8 chars of the session id.
- **`5h:63% 2h0m` / `7d:18% 2d7h`** — your Pro/Max rate limits as **percent remaining**
  plus time until reset, color-coded green / yellow / red (needs Claude Code ≥ 2.1.80).
- **`ctx:45%`** — context-window usage. **`e:xh`** — effort level from
  `settings.json` `.effortLevel` (`xh`/`hi`/`md`/`lo`). **`opus4.8 1M`** — the model,
  compact, with a `1M` suffix for the 1M-context variant.

So a fleet of tabs becomes individually addressable: glance at the bars, pick the tab
by its `[s0NN]`, and the orchestrator drives that session directly.

## Installation

Paste this into Claude Code:

> Clone github.com/rocketmandrey/claude-recall and run ./install.sh. Ask me whether to
> enable the optional handoff loop, show me what it changed, then ask me whether to run
> `recall backfill` (one small-LLM call per past session, ~20–40 min for a few hundred).

Or manually:

```bash
git clone https://github.com/rocketmandrey/claude-recall.git && cd claude-recall
./install.sh              # CLI + skill + SessionEnd hook + permissions
recall backfill           # optional: index your past sessions
```

`install.sh` merges into `~/.claude/settings.json` (never overwrites): the SessionEnd
hook, `Bash(recall *)` permissions, and the `statusLine` command, so agents can call
recall in any new session without prompts. From then on every finished session
(≥15 events) is indexed automatically. The status line merge is idempotent and
**never clobbers a foreign one** — if you already point `statusLine` at a different
command, the installer keeps yours and just prints how to switch.

The **handoff continuity loop is opt-in** — the installer offers it (and never
forces it): before every context compaction a small LLM writes a state card,
re-injected after compact/resume, so the session wakes up knowing where it left
off. Cost: one haiku call per compaction. Flags: `./install.sh --with-handoff` /
`--no-handoff` (no flag → the installer asks; a previous choice is kept on
reinstall). Verify anytime with `recall doctor`.

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
> Открой сессию, где мы настраивали деплой — прям окошком

**ZH — 查询过去的决定:**
> 我们当时关于部署方案是怎么决定的？

## Repository structure

```
claude-recall/
├── bin/recall                  ← the whole product: one Python file, zero deps
├── bin/statusline-command.sh   ← fleet status line: project [s0NN] | limits | ctx | model
├── skill/SKILL.md              ← session-orchestrator skill for Claude Code
├── install.sh                  ← installer: CLI + skill + status line + hook + permissions
└── docs/                       ← README translations (RU, ZH)
```

## CLI

| command | what it does |
|---------|--------------|
| `recall find <query...>` | search the index (case-insensitive OR; search by word STEM) |
| `recall grep <query...>` | full-text search across raw transcripts (fallback when the index is silent) |
| `recall show <id8>` | print a session's recap card |
| `recall cmd <id8>` | print the resume command (handoff) |
| `recall open <id8> [--fast] [--tab]` | open the session in a new terminal window (spawn); writes its missing handoff card first unless `--fast`; `--tab` opens a tab instead |
| `recall remove <id8>` | forget a session: card + index line + tombstone |
| `recall rename <id8> <title...>` | set a session's display name by hand (auto-naming then leaves it alone) |
| `recall handoff <file.jsonl>` | write a handoff card (in-flight state) for a session |
| `recall handoff --all` | retro-sweep: handoff cards for recent sessions lacking one `[--days N] [--jobs N]` |
| `recall backfill` | index existing sessions `[--days N] [--min-events N] [--jobs N]` |
| `recall index` | index stats |
| `recall doctor` | check installation |

Env: `RECALL_DATA` (default `~/.claude/session-recaps`), `RECALL_MODEL` (default haiku),
`RECALL_TERMINAL` (`Terminal`\|`iTerm`), `RECALL_MIN_EVENTS` (default 15),
`RECALL_HANDOFF_DAYS` (default 30 — handoff retention),
`RECALL_AUTONAME` (default 1 — auto-title sessions; `0` to disable),
`RECALL_TAB` (`1` — `recall open` defaults to tabs; per-call override: `--window`).

## Requirements & notes

- macOS (`recall open` uses AppleScript; Linux PRs welcome), python3 ≥ 3.9, logged-in `claude` CLI.
- **Local-first**: cards and the index never leave your machine. They do contain
  distilled session content — don't commit or share the data dir.
- Recap calls go through `claude -p` — your existing auth, no API key. Worker sessions
  are marked and never index themselves.
- `recall remove` tombstones a session so hook/backfill won't resurrect it
  (undo: `recall recap <transcript> --force`).
- Handoff cards (if the loop is enabled) are a few KB each and auto-pruned after
  30 days; long-term memory lives in the recap cards. A session resumed via
  `recall open` gets its handoff re-injected automatically — it wakes up knowing
  its next steps. Older sessions without a card get one written on open (~30s;
  `--fast` to skip), or retro-sweep them all: `recall handoff --all --days 14`.
- If the index draws a blank, `recall grep` does full-text search over your raw
  transcripts in `~/.claude/projects/` — no extra tools needed.
- Tabs: in iTerm `recall open --tab` is native and reliable, and each tab is
  **colored by project** (iTerm OSC-6) so a vertical tab bar groups same-project
  sessions by stripe — put the tab bar on the left via iTerm → Settings →
  Appearance → Tab bar location. Terminal.app has no tab API, so recall emulates
  ⌘T via System Events (best-effort: needs the Accessibility permission, and
  scripted ⌘T can still be dropped depending on focus) — it verifies a tab
  actually appeared and otherwise opens a window, so it never injects the command
  into a busy tab. For guaranteed, color-coded tabs, use iTerm.

## Acknowledgements

recall grew out of daily use of [codbash](https://github.com/vakovalskii/codbash) by
Valerii Kovalskii — a dashboard + full-text search across AI coding sessions. recall
contains none of its code and doesn't depend on it, but the idea of treating past
sessions as a searchable asset comes from living with codbash, and `recall grep` is
a deliberately minimal nod to what codbash does at full scale (web dashboard,
cross-agent session sync). For the full experience, get codbash. Respect, Valera.

## License

MIT
