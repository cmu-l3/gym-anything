#!/bin/bash
# post_task hook for draft_q3_product_memo on Apple Pages / macOS.
#
# Produces /tmp/draft_q3_product_memo_result.json with:
#   - task_start (unix epoch)
#   - target_path (echo of expected save path)
#   - target_exists (bool: target_path is a directory \u2014 .pages bundle)
#   - target_mtime (mtime epoch of the target; 0 if missing)
#   - target_fresh (bool: target_mtime > task_start)
#   - body_text_target (body text of the *saved-target* document if Pages
#     has it open; falls back to "front document" if the saved name doesn't
#     match anything currently open)
#   - body_text_front (body text of the currently front document as a
#     secondary signal, in case the agent typed but never saved)
#   - phrase_ai, phrase_date, phrase_nps, phrase_p0 (booleans)
#   - other_post_start_pages (list of .pages filenames in ~/Documents whose
#     mtime is > task_start AND aren't the target \u2014 wrong-target signal)
#   - total_pages_post_start (count of .pages files modified after start)
#
# Every Python heredoc has try/except around its main logic and writes a
# safe default if anything fails, so the verifier always reads valid JSON
# (Anti-Pattern #12 in 14_task_design_antipatterns.md).

set -u   # NOT set -e \u2014 individual stages should continue on error.

TARGET_PATH="/Users/lume/Documents/Q3 Product Strategy Memo.pages"

echo "=== Exporting draft_q3_product_memo results ==="

# Intentionally NOT calling /usr/sbin/screencapture: SSH-context screencapture
# on base-macos captures only wallpaper + menu bar, missing the Pages window.
# The SDK's panel_view_final.png (taken by pages_session.py finalize) is the
# authoritative end-state screenshot. Same skip as setup_task.sh and
# apple_notes_env/tasks/create_meeting_agenda/export_result.sh.

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

# Make sure Pages is running so AppleScript can talk to it. If the agent
# quit Pages (or never relaunched it after pre_task), AppleScript queries
# for body text return empty. open -a is idempotent.
if ! pgrep -x Pages >/dev/null; then
  echo "Pages was not running; relaunching for export"
  open -a Pages
  for i in $(seq 1 20); do
    /usr/bin/lsappinfo list 2>/dev/null | grep -qF 'bundleID="com.apple.iWork.Pages"' && break
    sleep 1
  done
  sleep 2
fi

# Drive the rest with Python: easier quoting around the spaces in the
# target path, easier JSON emission, and try/except per stage.
/usr/bin/python3 - "$TASK_START" "$TARGET_PATH" << 'PYEOF'
import json
import os
import re
import subprocess
import sys


TASK_START = int(sys.argv[1] or "0")
TARGET_PATH = sys.argv[2]
# Pages document `name` is the basename without the .pages extension.
TARGET_DOC_NAME = os.path.splitext(os.path.basename(TARGET_PATH))[0]


def osa(script: str, timeout: int = 30) -> tuple[str, int]:
    """Run AppleScript, return (stdout, return_code). Captures stderr for
    visibility in hook logs."""
    try:
        r = subprocess.run(
            ["/usr/bin/osascript", "-e", script],
            capture_output=True, text=True, timeout=timeout,
        )
        if r.returncode != 0 and r.stderr.strip():
            print(f"[osa stderr] {r.stderr.strip()}", file=sys.stderr)
        return r.stdout.rstrip("\n"), r.returncode
    except Exception as exc:
        print(f"[osa exception] {exc}", file=sys.stderr)
        return "", -1


def applescript_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


result: dict = {
    "task_start": TASK_START,
    "target_path": TARGET_PATH,
    "target_doc_name": TARGET_DOC_NAME,
    "target_exists": False,
    "target_mtime": 0,
    "target_fresh": False,
    "body_text_target": "",
    "body_text_front": "",
    "phrase_ai": False,
    "phrase_date": False,
    "phrase_nps": False,
    "phrase_p0": False,
    "other_post_start_pages": [],
    "total_pages_post_start": 0,
}

# ---------------------------------------------------------------------------
# Step 1: filesystem check on the target path. .pages is a directory bundle
# in modern Pages; os.path.isdir is the right test (a plain file at that
# path would be a Pages-09 single-file zip, also acceptable, so we accept
# isdir OR isfile).
# ---------------------------------------------------------------------------
try:
    exists = os.path.isdir(TARGET_PATH) or os.path.isfile(TARGET_PATH)
    result["target_exists"] = exists
    if exists:
        mt = int(os.stat(TARGET_PATH).st_mtime)
        result["target_mtime"] = mt
        result["target_fresh"] = mt > TASK_START
except Exception as exc:
    print(f"[fs check exception] {exc}", file=sys.stderr)

# ---------------------------------------------------------------------------
# Step 2: scan ~/Documents for .pages files modified after task_start, and
# build the "other_post_start_pages" list for wrong-target detection. We
# don't care about pre-existing files \u2014 only those the agent created or
# modified after task_start.
# ---------------------------------------------------------------------------
try:
    docs_dir = "/Users/lume/Documents"
    other = []
    total_post = 0
    if os.path.isdir(docs_dir):
        for name in os.listdir(docs_dir):
            if not name.endswith(".pages"):
                continue
            full = os.path.join(docs_dir, name)
            try:
                mt = int(os.stat(full).st_mtime)
            except Exception:
                continue
            if mt > TASK_START:
                total_post += 1
                if os.path.abspath(full) != os.path.abspath(TARGET_PATH):
                    other.append(name)
    result["total_pages_post_start"] = total_post
    # Only surface "other_post_start_pages" when the target is MISSING; the
    # verifier's wrong-target gate fires only in that case, and emitting these
    # otherwise just bloats the result JSON.
    if not result["target_exists"]:
        result["other_post_start_pages"] = sorted(other)
    else:
        result["other_post_start_pages"] = []
except Exception as exc:
    print(f"[docs scan exception] {exc}", file=sys.stderr)

# ---------------------------------------------------------------------------
# Step 3: get body text from Pages via AppleScript. Two queries:
#   a) `document <target_name>` \u2014 the agent's saved doc, if it's open.
#   b) `front document`        \u2014 fallback for "agent typed content but
#                                  never saved (or saved+closed)" cases.
# We tolerate both queries failing \u2014 the verifier handles empty body text.
# ---------------------------------------------------------------------------
escaped_name = applescript_escape(TARGET_DOC_NAME)
# Probe by document name. AppleScript Pages indexes documents by their `name`
# property which is the saved filename without extension. If no such doc is
# open, this raises an AppleScript error which `try` traps.
script_by_name = (
    f'tell application "Pages"\n'
    f'  try\n'
    f'    return body text of document "{escaped_name}"\n'
    f'  on error errMsg\n'
    f'    return ""\n'
    f'  end try\n'
    f'end tell'
)
body_target, rc_target = osa(script_by_name, timeout=30)
result["body_text_target"] = body_target

# Front-document fallback. If there are no open documents at all, this also
# raises AppleScript-side; trap and return empty.
script_front = (
    'tell application "Pages"\n'
    '  try\n'
    '    return body text of front document\n'
    '  on error errMsg\n'
    '    return ""\n'
    '  end try\n'
    'end tell'
)
body_front, rc_front = osa(script_front, timeout=30)
result["body_text_front"] = body_front

# ---------------------------------------------------------------------------
# Step 4: phrase checks. The verifier wants to score body content even if
# the agent saved-and-closed (no open doc). To handle that, we also try
# reading the saved .pages bundle directly for text content as a third
# fallback. The .pages bundle's preview.jpg + index.xml store rendered text;
# strings of the bundle's binary index will surface body text.
# ---------------------------------------------------------------------------
combined = (body_target or "") + "\n" + (body_front or "")
combined = combined.strip()

# Third fallback: if both AppleScript reads were empty but the file exists,
# try to extract strings from the .pages bundle. Modern .pages packages
# include preview.jpg + Index.zip / Data subdir; strings on the package
# surfaces typed text in the Index. This is best-effort \u2014 if it works it
# strengthens C2/C3/C4, if it fails we just keep the AppleScript-only signal.
if not combined and result["target_exists"]:
    try:
        if os.path.isdir(TARGET_PATH):
            sp = subprocess.run(
                ["/usr/bin/find", TARGET_PATH, "-type", "f"],
                capture_output=True, text=True, timeout=10,
            )
            collected = []
            for path in sp.stdout.splitlines():
                try:
                    s = subprocess.run(
                        ["/usr/bin/strings", path],
                        capture_output=True, text=True, timeout=10,
                    )
                    collected.append(s.stdout)
                except Exception:
                    pass
            combined = "\n".join(collected)
        else:
            # Single-file zip fallback for Pages-09 format.
            s = subprocess.run(
                ["/usr/bin/strings", TARGET_PATH],
                capture_output=True, text=True, timeout=15,
            )
            combined = s.stdout
    except Exception as exc:
        print(f"[bundle strings exception] {exc}", file=sys.stderr)

body_norm = re.sub(r"\s+", " ", combined).strip()
body_lower = body_norm.lower()

# Phrase checks (case-insensitive on the content; the verifier description
# specifies the literal phrases, but a real agent's typing may differ in
# case for words at line-start, so we accept case-insensitive).
result["phrase_ai"] = "ai-assisted onboarding" in body_lower
result["phrase_date"] = "2026-09-30" in body_lower
result["phrase_nps"] = ("nps from 42 to 55" in body_lower) or (
    "nps" in body_lower and "42" in body_lower and "55" in body_lower
)
result["phrase_p0"] = ("p0 incident rate" in body_lower) and ("30%" in body_lower or "30 %" in body_lower)

with open("/tmp/draft_q3_product_memo_result.json", "w") as f:
    json.dump(result, f, indent=2)

# Echo a trimmed version for hook logs (body_text fields can be huge).
trimmed = dict(result)
trimmed["body_text_target"] = (result["body_text_target"][:300] + "...") if len(result["body_text_target"]) > 300 else result["body_text_target"]
trimmed["body_text_front"] = (result["body_text_front"][:300] + "...") if len(result["body_text_front"]) > 300 else result["body_text_front"]
print(json.dumps(trimmed, indent=2, default=str))
PYEOF

echo "=== Export complete ==="
