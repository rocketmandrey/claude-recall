#!/usr/bin/env python3
"""recall iTerm2 bridge — runs INSIDE iTerm2 (AutoLaunch) and holds the Python API
connection, servicing a local job queue so the `recall` CLI can address individual
Claude Code sessions by tty (read screen, send text) WITHOUT the CLI needing API auth.

Install:  recall iterm-install   (copies this into iTerm2's AutoLaunch dir)
Enable:   iTerm2 → Settings → General → Magic → Enable Python API, then restart iTerm2.

Why a daemon + queue: only a script LAUNCHED BY iTerm2 is auto-authorized for the API
(and gets the `iterm2` package from iterm2env). The CLI just drops job files into a
0700 queue; this daemon does all API work and writes results back.

Security (matches the spec):
  • never broadcasts — a job targets exactly ONE tty; ambiguous/absent tty => refused
  • `send` requires `claude` actually running on that tty
  • session must still be open
  • every send is appended to an audit log (0600)
"""
import asyncio
import glob
import json
import os
import re
import subprocess
import time

import iterm2  # provided by iterm2env when run from AutoLaunch

HOME = os.path.expanduser("~")
QDIR = os.path.join(HOME, ".claude", "recall", "itermq")          # job/result queue (0700)
AUDIT = os.path.join(HOME, ".claude", "recall", "iterm-audit.log")  # 0600
POLL = 0.4          # queue poll interval, seconds
LOG = "/tmp/recall-iterm-bridge.log"


def _log(msg):
    try:
        with open(LOG, "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} {msg}\n")
    except OSError:
        pass


def _ensure_q():
    os.makedirs(QDIR, mode=0o700, exist_ok=True)
    try:
        os.chmod(QDIR, 0o700)
    except OSError:
        pass


def _short(tty):
    """/dev/ttys034 -> s034 ; ttys034 -> s034 ; s034 -> s034"""
    b = os.path.basename(tty or "")
    if b.startswith("ttys"):
        return b[3:]
    if b.startswith("tty"):
        return b[3:]
    return b


def _claude_on_tty(tty):
    """Inspect processes on a tty. Return (claude_running: bool, claude_session_id|None)."""
    base = os.path.basename(tty or "")  # ttys034
    if not base:
        return False, None
    try:
        out = subprocess.run(["ps", "-t", base, "-o", "command="],
                             capture_output=True, text=True, timeout=5).stdout
    except Exception as e:
        _log(f"ps failed for {base}: {e}")
        return False, None
    running, sid = False, None
    for line in out.splitlines():
        if "claude" in line and "grep" not in line and "iterm_bridge" not in line:
            running = True
            m = re.search(r"--resume\s+([0-9a-fA-F-]{8,})", line)
            if m:
                sid = m.group(1)
    return running, sid


async def _index(app):
    """tty-short -> session record for every open session."""
    idx = {}
    for w in app.terminal_windows:
        for t in w.tabs:
            for s in t.sessions:
                try:
                    tty = await s.async_get_variable("tty")
                except Exception:
                    tty = None
                if not tty:
                    continue
                short = _short(tty)
                cwd = ""
                for var in ("path", "pwd"):
                    try:
                        cwd = await s.async_get_variable(var)
                    except Exception:
                        cwd = ""
                    if cwd:
                        break
                title = ""
                for var in ("autoName", "name", "jobName"):
                    try:
                        title = await s.async_get_variable(var)
                    except Exception:
                        title = ""
                    if title:
                        break
                running, sid = _claude_on_tty(tty)
                idx[short] = {"session": s, "session_id": s.session_id, "tty": tty,
                              "short": short, "cwd": cwd or "", "title": title or "",
                              "claude": running, "claude_sid": sid}
    return idx


async def _screen(connection, session, nlines):
    """Return the last `nlines` rows of the visible screen as text."""
    async with iterm2.Transaction(connection):
        li = await session.async_get_line_info()
        lines = await session.async_get_contents(li.overflow, li.mutable_area_height)
    rows = [ln.string for ln in lines]
    rows = [r for r in rows]  # keep as-is
    return "\n".join(rows[-nlines:]).rstrip()


def _audit(op, rec, text):
    entry = {"ts": time.strftime("%Y-%m-%d %H:%M:%S"), "op": op, "tty": rec["short"],
             "cwd": rec.get("cwd"), "claude_sid": rec.get("claude_sid"), "text": text}
    try:
        with open(AUDIT, "a", encoding="utf-8") as f:
            f.write(json.dumps(entry, ensure_ascii=False) + "\n")
        os.chmod(AUDIT, 0o600)
    except OSError:
        pass


def _resolve(idx, tty):
    """Return (record, error). Enforce unambiguous single match; never broadcast."""
    short = _short(tty)
    matches = [d for k, d in idx.items() if k == short]
    if not matches:
        return None, f"no open session with tty '{short}'"
    if len(matches) > 1:
        return None, f"ambiguous tty '{short}' ({len(matches)} matches) — refusing"
    return matches[0], None


async def _handle(connection, app, job):
    op = job.get("op")
    if op == "ps":
        idx = await _index(app)
        rows = [{k: v for k, v in d.items() if k != "session"} for d in idx.values()]
        return {"ok": True, "sessions": rows}

    if op in ("peek", "send", "wait"):
        idx = await _index(app)
        rec, err = _resolve(idx, job.get("tty", ""))
        if err:
            return {"ok": False, "error": err}
        session = rec["session"]

        if op == "peek":
            screen = await _screen(connection, session, int(job.get("lines", 40)))
            return {"ok": True, "tty": rec["short"], "claude": rec["claude"],
                    "claude_sid": rec["claude_sid"], "cwd": rec["cwd"], "screen": screen}

        if op == "send":
            if not rec["claude"]:
                return {"ok": False, "error": f"no claude running on {rec['short']} — refusing to send"}
            text = job.get("text", "")
            _audit("send", rec, text)
            await session.async_send_text(text if text.endswith("\n") else text + "\n")
            return {"ok": True, "tty": rec["short"], "sent": True, "claude_sid": rec["claude_sid"]}

        if op == "wait":
            # heuristic idle-detect: screen unchanged for `stable` consecutive polls
            timeout = float(job.get("timeout", 300))
            stable_needed, stable, prev, screen = 3, 0, None, ""
            t0 = time.time()
            while time.time() - t0 < timeout:
                screen = await _screen(connection, session, 60)
                h = hash(screen)
                if h == prev:
                    stable += 1
                    if stable >= stable_needed:
                        return {"ok": True, "tty": rec["short"], "idle": True, "screen": screen[-2000:]}
                else:
                    stable, prev = 0, h
                await asyncio.sleep(2)
            return {"ok": True, "tty": rec["short"], "idle": False, "timeout": True, "screen": screen[-2000:]}

    return {"ok": False, "error": f"unknown op '{op}'"}


async def main(connection):
    _ensure_q()
    app = await iterm2.async_get_app(connection)
    _log("bridge up")
    while True:
        for jf in sorted(glob.glob(os.path.join(QDIR, "*.job.json"))):
            try:
                with open(jf) as f:
                    job = json.load(f)
            except Exception:
                try:
                    os.remove(jf)
                except OSError:
                    pass
                continue
            try:
                res = await _handle(connection, app, job)
            except Exception as e:
                _log(f"handle error: {e}")
                res = {"ok": False, "error": f"bridge error: {e}"}
            rf = jf[:-len(".job.json")] + ".result.json"
            tmp = rf + ".tmp"
            try:
                with open(tmp, "w", encoding="utf-8") as f:
                    json.dump(res, f, ensure_ascii=False)
                os.replace(tmp, rf)
            except OSError as e:
                _log(f"result write error: {e}")
            try:
                os.remove(jf)
            except OSError:
                pass
        await asyncio.sleep(POLL)


iterm2.run_forever(main)
