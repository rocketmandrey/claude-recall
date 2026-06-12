#!/bin/bash
# claude-recall installer: CLI + Claude Code skill + SessionEnd hook.
# Usage: ./install.sh [--backfill]
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
RECALL_HOME="$HOME/.claude/recall"
SKILL_DIR="$HOME/.claude/skills/session-orchestrator"
SETTINGS="$HOME/.claude/settings.json"
BIN_LINK="$HOME/.local/bin/recall"

echo "claude-recall installer"

command -v python3 >/dev/null || { echo "✗ python3 required"; exit 1; }
command -v claude  >/dev/null || { echo "✗ claude CLI required (https://code.claude.com)"; exit 1; }

# 1. CLI
mkdir -p "$RECALL_HOME/bin" "$HOME/.local/bin" "$HOME/.claude/session-recaps"
cp "$REPO_DIR/bin/recall" "$RECALL_HOME/bin/recall"
chmod +x "$RECALL_HOME/bin/recall"
ln -sf "$RECALL_HOME/bin/recall" "$BIN_LINK"
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) echo "  note: add ~/.local/bin to PATH (export PATH=\"\$HOME/.local/bin:\$PATH\")" ;;
esac
echo "  ✓ CLI -> $BIN_LINK"

# 2. Skill (the touchpoint for every Claude Code session)
mkdir -p "$SKILL_DIR"
cp "$REPO_DIR/skill/SKILL.md" "$SKILL_DIR/SKILL.md"
echo "  ✓ skill -> $SKILL_DIR"

# 3. SessionEnd hook + permissions (merge into settings.json, idempotent)
python3 - "$SETTINGS" "$RECALL_HOME/bin/recall hook" <<'PY'
import json, os, sys
settings_path, hook_cmd = sys.argv[1], sys.argv[2]
settings = {}
if os.path.exists(settings_path):
    settings = json.load(open(settings_path))
hooks = settings.setdefault("hooks", {})
entries = hooks.setdefault("SessionEnd", [])
# drop stale recall/session-recap hooks, keep everything else
def is_ours(entry):
    return any("recall hook" in h.get("command", "") or "session_end_hook.sh" in h.get("command", "")
               for h in entry.get("hooks", []) if h.get("type") == "command")
entries[:] = [e for e in entries if not is_ours(e)]
entries.append({"hooks": [{"type": "command", "command": hook_cmd, "timeout": 15}]})
# permissions: let any session run recall without a prompt
allow = settings.setdefault("permissions", {}).setdefault("allow", [])
for rule in ("Bash(recall)", "Bash(recall *)"):
    if rule not in allow:
        allow.append(rule)
json.dump(settings, open(settings_path, "w"), indent=2, ensure_ascii=False)
print("  ✓ SessionEnd hook + permissions (Bash(recall *)) -> " + settings_path)
PY

# 4. Verify
echo
"$RECALL_HOME/bin/recall" doctor || true

# 5. Optional backfill
if [[ "${1:-}" == "--backfill" ]]; then
  echo; echo "backfilling past sessions (this calls a small LLM per session, takes a while)..."
  "$RECALL_HOME/bin/recall" backfill
else
  echo
  echo "next: recall backfill   # index your past sessions (~20-40 min, runs LLM per session)"
fi
echo "done. restart Claude Code sessions to activate the hook."
