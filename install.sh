#!/bin/bash
# claude-recall installer: CLI + Claude Code skill + hooks.
# Usage: ./install.sh [--backfill] [--with-handoff|--no-handoff]
#   --with-handoff   enable the optional handoff continuity loop (PreCompact + SessionStart)
#   --no-handoff     skip it (core index/orchestrator works fine without)
#   neither          keep current state if already installed; otherwise ask (TTY) / skip
set -euo pipefail

HANDOFF=""
BACKFILL=0
for arg in "$@"; do
  case "$arg" in
    --with-handoff) HANDOFF=1 ;;
    --no-handoff)   HANDOFF=0 ;;
    --backfill)     BACKFILL=1 ;;
  esac
done

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
RECALL_HOME="$HOME/.claude/recall"
SKILL_DIR="$HOME/.claude/skills/session-orchestrator"
SETTINGS="$HOME/.claude/settings.json"
BIN_LINK="$HOME/.local/bin/recall"
STATUSLINE="$HOME/.claude/statusline-command.sh"

echo "claude-recall installer"

command -v python3 >/dev/null || { echo "✗ python3 required"; exit 1; }
command -v claude  >/dev/null || { echo "✗ claude CLI required (https://code.claude.com)"; exit 1; }

# 1. CLI
mkdir -p "$RECALL_HOME/bin" "$HOME/.local/bin" "$HOME/.claude/session-recaps"
cp "$REPO_DIR/bin/recall" "$RECALL_HOME/bin/recall"
cp "$REPO_DIR/bin/iterm_bridge.py" "$RECALL_HOME/bin/iterm_bridge.py"   # iTerm2 API bridge (install into AutoLaunch via: recall iterm-install)
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

# 2b. Status line — shows each tab's address [s0NN] (its iTerm tty) so the
# orchestrator can inject context straight into a named tab ("go to s053").
cp "$REPO_DIR/bin/statusline-command.sh" "$STATUSLINE"
chmod +x "$STATUSLINE"
echo "  ✓ status line -> $STATUSLINE"

# 3. Handoff loop is opt-in: offer it, don't force it
if [[ -z "$HANDOFF" ]]; then
  if grep -q "recall restore-hook" "$SETTINGS" 2>/dev/null; then
    HANDOFF=1   # already enabled earlier — keep it
  elif [[ -t 0 ]]; then
    echo
    echo "Optional: handoff continuity loop. Before every context compaction a small LLM"
    echo "writes a state card (task / done / in flight / next), re-injected after"
    echo "compact/resume — the session wakes up knowing where it left off."
    echo "Cost: one haiku call per compaction. Enable later anytime: ./install.sh --with-handoff"
    read -r -p "Enable the handoff loop? [y/N] " ans
    if [[ "$ans" =~ ^[YyДд] ]]; then HANDOFF=1; else HANDOFF=0; fi
  else
    HANDOFF=0   # non-interactive, no flag: core only
  fi
fi

# 4. Hooks + permissions — merged into settings.json, idempotent, never overwrites yours
python3 - "$SETTINGS" "$RECALL_HOME/bin/recall" "$HANDOFF" <<'PY'
import json, os, sys
settings_path, rbin, handoff = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
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

# Stop hook: transcript backup after EVERY turn — sessions that die dirty
# (power loss, hard kill) lose at most the last unfinished turn.
stops = scrub("Stop", "recall backup-hook")
stops.append({"hooks": [{"type": "command", "command": f"{rbin} backup-hook", "timeout": 15}]})

pre = scrub("PreCompact", "recall handoff-hook")
ss = scrub("SessionStart", "recall restore-hook")
if handoff:
    for m in ("auto", "manual"):
        pre.append({"matcher": m, "hooks": [{"type": "command",
                    "command": f"{rbin} handoff-hook", "timeout": 200}]})
    for m in ("compact", "resume"):
        ss.append({"matcher": m, "hooks": [{"type": "command",
                   "command": f"{rbin} restore-hook", "timeout": 10}]})
for ev in ("PreCompact", "SessionStart", "SessionEnd", "Stop"):
    if ev in hooks and not hooks[ev]:
        del hooks[ev]

allow = settings.setdefault("permissions", {}).setdefault("allow", [])
for rule in ("Bash(recall)", "Bash(recall *)"):
    if rule not in allow:
        allow.append(rule)

json.dump(settings, open(settings_path, "w"), indent=2, ensure_ascii=False)
state = "ON" if handoff else "off (optional; ./install.sh --with-handoff)"
print("  ✓ SessionEnd hook + permissions -> " + settings_path)
print("  ✓ handoff loop: " + state)
PY

# 4b. Status line in settings.json — idempotent, never clobbers a foreign one.
python3 - "$SETTINGS" <<'PY'
import json, os, sys, time
settings_path = sys.argv[1]
ours = "bash ~/.claude/statusline-command.sh"
settings = {}
if os.path.exists(settings_path):
    settings = json.load(open(settings_path))
sl = settings.get("statusLine")
cur = sl.get("command", "") if isinstance(sl, dict) else ""
if isinstance(sl, dict) and cur and "statusline-command.sh" not in cur:
    # A different status line is already configured — keep it, just note it.
    print("  • status line: kept your existing one (" + cur + ")")
    print("    to switch: set statusLine.command to \"" + ours + "\" in " + settings_path)
else:
    if isinstance(sl, dict) and cur and cur != ours:
        # Ours but stale path/wording — back up the old value before rewriting.
        bak = settings_path + ".statusline.bak." + time.strftime("%Y%m%d%H%M%S")
        json.dump(sl, open(bak, "w"), indent=2, ensure_ascii=False)
        print("  • status line: backed up previous -> " + bak)
    settings["statusLine"] = {"type": "command", "command": ours}
    json.dump(settings, open(settings_path, "w"), indent=2, ensure_ascii=False)
    print("  ✓ status line -> " + settings_path)
PY

# 4c. LaunchAgent (macOS): 30-min `recall sweep` — crash-first registry upkeep.
# Sessions that die dirty (power loss) never fire SessionEnd; the sweep archives
# transcripts, gives every unindexed session a zero-LLM [new] index line, and
# catches up stale recaps/handoffs (capped). Идемпотентно: перезаписывает свой plist.
if [[ "$(uname)" == "Darwin" ]]; then
  PLIST="$HOME/Library/LaunchAgents/com.andrey.recall-archive.plist"
  mkdir -p "$HOME/Library/LaunchAgents"
  cat > "$PLIST" <<PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.andrey.recall-archive</string>
    <key>ProgramArguments</key>
    <array>
        <string>$HOME/.local/bin/recall</string>
        <string>sweep</string>
        <string>--quiet</string>
    </array>
    <key>StartInterval</key><integer>1800</integer>
    <key>RunAtLoad</key><true/>
    <key>StandardOutPath</key><string>$HOME/.claude/recall/sweep.log</string>
    <key>StandardErrorPath</key><string>$HOME/.claude/recall/sweep.log</string>
</dict>
</plist>
PLISTEOF
  launchctl unload "$PLIST" 2>/dev/null || true
  launchctl load "$PLIST" 2>/dev/null && echo "  ✓ LaunchAgent: recall sweep every 30 min" \
    || echo "  • LaunchAgent written ($PLIST); load manually: launchctl load $PLIST"
fi

# 5. Verify
echo
"$RECALL_HOME/bin/recall" doctor || true

# 6. Optional backfill
if [[ "$BACKFILL" == "1" ]]; then
  echo; echo "backfilling past sessions (this calls a small LLM per session, takes a while)..."
  "$RECALL_HOME/bin/recall" backfill
else
  echo
  echo "next: recall backfill   # index your past sessions (~20-40 min, runs LLM per session)"
fi
echo "done. restart Claude Code sessions to activate the hook."
