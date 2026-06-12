# 🧠 claude-recall

**Session memory & orchestration layer for Claude Code.** One searchable index of
everything you've ever done in your AI coding sessions — and three ways to act on it.
Single-file Python, zero dependencies, zero API keys.

[Русская версия → README.md](README.md)

This repo is as much for agents as for you: give your agent the link, say
"read START_HERE.md" — it sets everything up step by step.

## The problem

You've run hundreds of Claude Code sessions. Somewhere in there you already solved
today's task — but `--resume` pickers show cryptic titles, and full-text search finds
words, not *tasks*. You need: *"find the session where I exported that client's deals,
and pick it up from there."*

## How it works

```
SESSION ENDS        → SessionEnd hook        → transcript .jsonl
RECAPPER (haiku)    → distills into a card   → ~/.claude/session-recaps/<id>.md
INDEX               → one line per session   → INDEX.md  ← the single touchpoint
ORCHESTRATOR (skill)→ find → show → finish | handoff | spawn
```

Every finished session is distilled by a small LLM (haiku) into a **recap card**:

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

All cards roll up into **one INDEX.md** — a single greppable line per session.
That index is the touchpoint for both you and your agents.

## Three interaction modes

Ask the orchestrator (any Claude Code session — the bundled skill teaches it):

| mode | you say | what happens |
|------|---------|--------------|
| **finish** | "do that export again, for client X" | Claude finds the past session, extracts project + method, redoes the task with new params right here |
| **handoff** | "give me the command" | `recall cmd <id>` → `cd "<project>" && claude --resume <id>` |
| **spawn** | "open that session" | `recall open <id>` — a new terminal window opens with the session restored, full context |

When several sessions match, the orchestrator doesn't guess — it shows a selector:
project folder + date + task context per candidate, plus a "dig deeper" option.

## Install

```bash
git clone https://github.com/rocketmandrey/claude-recall && cd claude-recall
./install.sh              # CLI + skill + SessionEnd hook + permissions
recall backfill           # index your past sessions (LLM call per session)
```

`install.sh` merges into `~/.claude/settings.json` (never overwrites): the SessionEnd
hook and `Bash(recall *)` permissions, so agents can call recall in any new session
without prompts. From then on every finished session (≥15 events) is indexed
automatically.

## CLI

```
recall find <query...>     search the index (case-insensitive OR; search by word STEM)
recall show <id8>          print a session's recap card
recall cmd <id8>           print the resume command (handoff)
recall open <id8>          open the session in a new terminal window (spawn, macOS)
recall remove <id8>        forget a session: card + index line + tombstone
recall backfill            index existing sessions [--days N] [--min-events N] [--jobs N]
recall index               index stats
recall doctor              check installation
```

Env: `RECALL_DATA` (default `~/.claude/session-recaps`), `RECALL_MODEL` (default haiku),
`RECALL_TERMINAL` (`Terminal`|`iTerm`), `RECALL_MIN_EVENTS` (default 15).

## Notes

- **Local-first**: cards and index never leave your machine. They do contain distilled
  session content — treat the data dir accordingly (don't commit or share it).
- Recap LLM calls go through `claude -p` (your existing auth, no API key needed).
  Worker sessions are marked and never re-indexed.
- `recall remove` tombstones the session so hook/backfill won't resurrect it;
  undo with `recall recap <transcript> --force`.
- Pairs well with [codbash](https://www.npmjs.com/package/codbash-app) as a full-text
  fallback and web dashboard; not required.
- macOS today (`recall open` uses AppleScript). Linux PRs welcome.

## License

MIT
