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

# 3. Hooks (SessionEnd recap+handoff, PreCompact handoff, SessionStart restore)
#    + permissions — merged into settings.json, idempotent, never overwrites yours
python3 - "$SETTINGS" "$RECALL_HOME/bin/recall" <<'PY'
import json, os, sys
settings_path, rbin = sys.argv[1], sys.argv[2]
settings = {}
if os.path.exists(settings_path):
    settings = json.load(open(settings_path))
hooks = settings.setdefault("hooks", {})

def scrub(event, *needles):
    """Drop our stale entries for this event, keep everything else."""
    entries = hooks.setdefault(event, [])
    def ours(e):
        return any(any(n in h.get("command", "") for n in needles)
                   for h in e.get("hooks", []) if h.get("type") == "command")
    entries[:] = [e for e in entries if not ours(e)]
    return entries

ends = scrub("SessionEnd", "recall hook", "session_end_hook.sh")
ends.append({"hooks": [{"type": "command", "command": f"{rbin} hook", "timeout": 15}]})

pre = scrub("PreCompact", "recall handoff-hook")
for m in ("auto", "manual"):
    pre.append({"matcher": m, "hooks": [{"type": "command",
                "command": f"{rbin} handoff-hook", "timeout": 120}]})

ss = scrub("SessionStart", "recall restore-hook")
for m in ("compact", "resume"):
    ss.append({"matcher": m, "hooks": [{"type": "command",
               "command": f"{rbin} restore-hook", "timeout": 10}]})

allow = settings.setdefault("permissions", {}).setdefault("allow", [])
for rule in ("Bash(recall)", "Bash(recall *)"):
    if rule not in allow:
        allow.append(rule)

json.dump(settings, open(settings_path, "w"), indent=2, ensure_ascii=False)
print("  ✓ hooks (SessionEnd, PreCompact, SessionStart) + permissions -> " + settings_path)
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
