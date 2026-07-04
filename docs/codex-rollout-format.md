# Codex CLI rollout format — spec for recall integration

Source: `~/.codex/sessions/YYYY/MM/DD/rollout-<local-ts>-<uuid>.jsonl`, 1728 files,
2025-07-14 .. 2026-07-03, 4.8G total. `<uuid>` in the filename == `session_id`.

## Line shape (current format, cli_version 0.142.5)

Each line is one JSON object. Common envelope: `{"timestamp": ISO8601Z, "type": T, "payload": {...}}`.

- `session_meta` (line 0; **может повторяться** — по одной на каждый resume/рестарт,
  id/cwd совпадают, брать первую): `payload.session_id` (== `payload.id`, duplicated),
  `cwd`, `originator`, `cli_version`, `source`, `thread_source`, `model_provider`,
  `git.{commit_hash,branch,repository_url}`, `base_instructions.text` (huge system prompt).
- `event_msg`: UI-level events. `payload.type` ∈ `user_message`, `agent_message`,
  `task_started`, `task_complete`, `token_count`, `agent_reasoning`, `turn_aborted`,
  `image_generation_end`, ... `user_message.message` = plain string, **already clean**
  (does not include AGENTS.md auto-injection, see trap below).
- `response_item`: raw model I/O log. `payload.type` ∈ `message` (has `role`:
  `user`/`assistant`), `reasoning`, `function_call`, `function_call_output`,
  `custom_tool_call(_output)`, `image_generation_call`. This is the *complete* wire
  history — includes system-injected content that never shows up in `event_msg`.
- `turn_context`: one per turn. `payload.model`, `.effort`, `.sandbox_policy`, `.cwd`,
  `.approval_policy`, `.summary`, `.turn_id`. **This is the only place the model name
  lives** (`payload.model`, e.g. `gpt-5-codex`, `gpt-5.1-codex-max`, `gpt-5.3-codex`,
  `gpt-5.4`, `gpt-5.5`). Not in `session_meta`.

## Trap: AGENTS.md injection

When cwd has an `AGENTS.md`, Codex auto-injects it as a `response_item`
(`role:user, content[0].text` starts with `"# AGENTS.md instructions for <path>..."`)
before the real first user turn. Confirmed: this shows up in `response_item` but is
**absent from `event_msg:user_message`** — the UI event stream is already clean.
Prefer `event_msg:user_message`; only fall back to `response_item/message/role=user`
for pre-`event_msg` formats, skipping any text starting with that injection prefix.

## Resume semantics (verified on live data, 2026-07-03)

`codex resume <id>` **дописывает в ТОТ ЖЕ rollout-файл с тем же session_id** —
не создаёт нового файла. Каждый resume/рестарт добавляет в файл ЕЩЁ ОДНУ строку
`session_meta` (проверено: `019f2adc-c5cc...` содержит 3 `session_meta` —
02:02Z, 02:31:38Z, 02:31:54Z — и непрерывную ленту `user_message` между ними;
id во всех трёх одинаковый). История при resume сохраняется полностью.

Родительских ссылок (`parent_session_id`, `resumed_from`, ...) в корпусе нет
нигде — они и не нужны: цепочек файлов не существует, файл = сессия навсегда.

**Conclusion for recall**: один файл = одна сессия = одна строка индекса;
resume лишь обновляет mtime уже проиндексированного файла. Парсер обязан
переживать несколько `session_meta` в одном файле (id/cwd/ts_start — из первой).

## Pустышки (empty/junk sessions)

Two cheap-to-detect empty patterns:

1. **Legacy 2-line format**: file ≤2 lines, first line has no `"type"` key
   (`{"id":..., "timestamp":...}`), second is one raw `message` object. 3 in the
   whole corpus (213B/233B/8KB), all top-level (no `YYYY/MM/DD` nesting) — from
   `codex exec` one-shot calls where the prompt got logged but the reply didn't
   (reply went to the caller's stdout instead).
2. **No assistant reply at all**: normal `session_meta` structure, zero
   `event_msg:agent_message` and zero `response_item role:assistant` — process
   died before any reply. 9/1728 files (some still 35-70KB of tool-call activity
   with no final text).

Rule: `is_empty(file) := first_real_user_message(file) is None OR no_assistant_content(file)`
— same extraction function used for indexing, no separate detector needed.

## Format evolution (sampled 2025-10 alpha .. 2026-07 stable)

| era | cli_version | id field | `source`/`model_provider`/`thread_source` |
|---|---|---|---|
| 2025-10 | 0.42.0-alpha.3 | `payload.id` only, no `session_id` | none of the three |
| 2026-03 | 0.115.0-alpha.27 | `payload.id` only | has `source`, `model_provider`; no `thread_source` |
| 2026-06 | 0.130.0 | `payload.id` only | has `source`, `model_provider`; no `thread_source` |
| 2026-07 | 0.142.5 | both `session_id` and `id` (identical) | all three present |

Line types and the `event_msg:user_message` / `turn_context.model` locations are
stable across every sampled era back to 2025-10. Always read
`payload.get("session_id") or payload.get("id")` (older eras lack `session_id`),
falling back to the filename UUID if both are missing.

The 3 top-level flat files (no `YYYY/MM/DD` nesting) are the oldest format
generation of all — no envelope, no `session_meta`, no `event_msg`. Treat "first
line has no `type` key" as the signal to switch to that minimal parser branch.

## mtime = last activity (confirmed)

Checked 2 files: file mtime (local tz) exactly equals the last line's
`timestamp` field converted from UTC to local (+3h, Moscow). Safe to use mtime
as "last activity" without opening the file.

## Distribution

- 1728 rollout files total, 4.8G on disk.
- 1421/1728 (82%) modified in the last 30 days — history is recency-heavy.
- 2 truly-empty (legacy 2-line) files, 9 no-assistant-reply files — junk rate ~0.6%.
- Span: 2025-07-14 to 2026-07-03 (today).

## Parsing recipe (pseudocode)

```python
AGENTS_PREFIX = "# AGENTS.md instructions for"

def parse_rollout(path):
    lines = [json.loads(l) for l in open(path)]
    first = lines[0]
    if "type" not in first:                      # ancient flat format, no envelope
        sid, ts, cwd = first["id"], first["timestamp"], None   # cwd not recorded
        texts = [l["content"][0]["text"] for l in lines[1:]
                 if l.get("type") == "message" and l.get("role") == "user"]
        first_real = next((t for t in texts if not t.startswith(AGENTS_PREFIX)), None)
        return dict(session_id=sid, ts=ts, cwd=cwd, model=None,
                     first_user_message=first_real, empty=first_real is None)

    meta = first["payload"]                       # session_meta / event_msg / response_item / turn_context
    sid = meta.get("session_id") or meta.get("id") or uuid_from_filename(path)
    model = next((l["payload"]["model"] for l in lines
                  if l.get("type") == "turn_context" and l["payload"].get("model")), None)

    user_events = [l["payload"]["message"] for l in lines
                   if l.get("type") == "event_msg" and l["payload"].get("type") == "user_message"]
    if user_events:
        first_real = user_events[0]               # already AGENTS.md-clean
    else:                                          # pre-event_msg era: fall back, skip injection
        cands = [l["payload"]["content"][0].get("text", "") for l in lines
                 if l.get("type") == "response_item" and l["payload"].get("type") == "message"
                 and l["payload"].get("role") == "user"]
        first_real = next((c for c in cands if not c.startswith(AGENTS_PREFIX)), None)

    has_reply = any(
        (l.get("type") == "event_msg" and l["payload"].get("type") == "agent_message")
        or (l.get("type") == "response_item" and l["payload"].get("type") == "message"
            and l["payload"].get("role") == "assistant")
        for l in lines)

    return dict(session_id=sid, ts=meta.get("timestamp"), cwd=meta.get("cwd"), model=model,
                 first_user_message=first_real, empty=(first_real is None) or not has_reply)
```

`mtime(path)` doubles as "last activity" — no need to open the file to sort by recency.
