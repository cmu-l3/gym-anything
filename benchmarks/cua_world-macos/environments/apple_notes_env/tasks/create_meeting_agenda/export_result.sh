#!/bin/bash
# post_task hook for create_meeting_agenda on Apple Notes/macOS.
#
# Produces /tmp/create_meeting_agenda_result.json with:
#   - task_start (unix epoch)
#   - target_title (echo of the expected title)
#   - matching_count (notes whose name == target_title)
#   - total_notes_post_start (notes created after task_start, across all folders)
#   - other_post_start_titles (titles of post-start notes that DON'T match target;
#     populated only when matching_count == 0, so the verifier can detect
#     "agent wrote a note but with wrong title" \u2014 strict wrong-target gate)
#   - note_title, note_body_html, note_body_text (when matching_count >= 1)
#   - line_hire, line_okr, line_launch (boolean phrase-presence flags)
#
# We query the live Notes app via AppleScript (direct app scripting, not
# System Events \u2014 works over SSH per 12_macos_environments.md), then write
# JSON from a Python heredoc so quoting is honest.

set -u   # NOT set -e \u2014 individual stages should continue on error.

TARGET_TITLE="Q3 Planning Kickoff"

echo "=== Exporting create_meeting_agenda results ==="

# Skip /usr/sbin/screencapture here: see the matching comment in
# setup_task.sh \u2014 on the use.computer base-macos sandbox this command
# captures only the wallpaper and misses app windows, so it produces a
# misleading artifact. The framework's per-step screenshot (SDK path) is
# the authoritative trajectory record.

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"

# Make sure Notes is running so AppleScript can talk to it. If pre_task quit
# Notes and the agent never re-launched it, our export still needs the app
# alive to enumerate notes via AppleScript. open -a is idempotent.
if ! pgrep -x Notes >/dev/null; then
  echo "Notes was not running; relaunching for export"
  open -a Notes
  for i in $(seq 1 20); do
    /usr/bin/lsappinfo list 2>/dev/null | grep -qF 'bundleID="com.apple.Notes"' && break
    sleep 1
  done
  sleep 2
fi

# Use Python to drive osascript: easier quoting, easier JSON, easier error
# isolation. Every block has a try/except so a single AppleScript failure
# never produces unparseable JSON (Anti-Pattern #12).
/usr/bin/python3 - "$TASK_START" "$TARGET_TITLE" << 'PYEOF'
import json
import re
import subprocess
import sys
from html.parser import HTMLParser


TASK_START = int(sys.argv[1] or "0")
TARGET_TITLE = sys.argv[2]


def osa(script: str, timeout: int = 30) -> tuple[str, int]:
    """Run an AppleScript snippet, return (stdout, return_code). Captures
    stderr too so AppleScript exceptions are visible in hook logs."""
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


class _HTMLToText(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self._chunks: list[str] = []

    def handle_data(self, data: str) -> None:
        self._chunks.append(data)

    def handle_starttag(self, tag, attrs) -> None:
        # Newline on block-level tags so bullet lists become line-separated text.
        if tag.lower() in {"br", "p", "div", "li", "ul", "ol", "h1", "h2", "h3", "h4"}:
            self._chunks.append("\n")

    def handle_endtag(self, tag) -> None:
        if tag.lower() in {"p", "div", "li", "ul", "ol", "h1", "h2", "h3", "h4"}:
            self._chunks.append("\n")

    def text(self) -> str:
        return "".join(self._chunks)


def html_to_text(html: str) -> str:
    if not html:
        return ""
    p = _HTMLToText()
    try:
        p.feed(html)
    except Exception:
        return re.sub(r"<[^>]+>", "", html)
    # Collapse runs of whitespace inside lines but preserve line breaks.
    lines = [re.sub(r"[ \t]+", " ", ln).strip() for ln in p.text().splitlines()]
    return "\n".join(ln for ln in lines if ln)


def applescript_escape(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"')


title_for_as = applescript_escape(TARGET_TITLE)
result: dict = {
    "task_start": TASK_START,
    "target_title": TARGET_TITLE,
    "matching_count": 0,
    "note_title": "",
    "note_body_html": "",
    "note_body_text": "",
    "line_hire": False,
    "line_okr": False,
    "line_launch": False,
    "total_notes_post_start": 0,
    "other_post_start_titles": [],
}

# ---------------------------------------------------------------------------
# Step 1: count notes whose name == target_title
# ---------------------------------------------------------------------------
count_script = (
    f'tell application "Notes" to return (count of (notes whose name is "{title_for_as}"))'
)
count_out, count_rc = osa(count_script)
try:
    result["matching_count"] = int(count_out.strip() or "0")
except ValueError:
    result["matching_count"] = 0

# ---------------------------------------------------------------------------
# Step 2: if a matching note exists, fetch title + body
# ---------------------------------------------------------------------------
if result["matching_count"] >= 1:
    title_script = (
        f'tell application "Notes" to return (name of item 1 of '
        f'(notes whose name is "{title_for_as}"))'
    )
    title_out, _ = osa(title_script)
    result["note_title"] = title_out.strip()

    body_script = (
        f'tell application "Notes" to return (body of item 1 of '
        f'(notes whose name is "{title_for_as}"))'
    )
    body_out, _ = osa(body_script, timeout=60)
    result["note_body_html"] = body_out
    result["note_body_text"] = html_to_text(body_out)

# ---------------------------------------------------------------------------
# Step 3: enumerate post-task-start notes so the verifier can detect the
# "agent wrote a note but with the wrong title" wrong-target case.
#
# Mac absolute time = Unix - 978307200.  AppleScript's `date` comparison
# wants a real date object; building one from a Unix epoch in pure AS is
# tedious, so we filter Python-side after pulling (name, mac-creation)
# tuples for all notes.  Cheap: a fresh sandbox has at most a handful of
# notes, and the agent typically only creates one or two.
# ---------------------------------------------------------------------------
enum_script = (
    'tell application "Notes"\n'
    '  set output to ""\n'
    '  set allNotes to every note\n'
    '  repeat with n in allNotes\n'
    '    set output to output & (name of n) & character id 9 & '
    '((creation date of n) as «class isot» as string) & character id 30\n'
    '  end repeat\n'
    '  return output\n'
    'end tell'
)
enum_out, enum_rc = osa(enum_script, timeout=60)
post_start_titles: list[str] = []
total_post_start = 0
RS = "\x1e"   # record separator (character id 30)

for entry in (enum_out or "").split(RS):
    entry = entry.strip()
    if not entry or "\t" not in entry:
        continue
    name, dt_raw = entry.split("\t", 1)
    name = name.strip()
    dt_raw = dt_raw.strip()
    # AppleScript ISO 8601 form via «class isot» is "YYYY-MM-DDTHH:MM:SS" in
    # local time; parse permissively. Fall back to "definitely post-start" if
    # we can't parse it (so we don't accidentally exonerate a wrong-target).
    note_unix = TASK_START + 1
    try:
        # Strip any timezone suffix; parse naive local-time ISO.
        clean = re.sub(r"[+\-]\d\d:?\d\d$", "", dt_raw).rstrip("Z")
        from datetime import datetime as _dt
        parsed = _dt.fromisoformat(clean)
        # Best-effort: treat naive as local; convert to epoch via mktime.
        import time as _time
        note_unix = int(_time.mktime(parsed.timetuple()))
    except Exception:
        pass
    if note_unix >= TASK_START:
        total_post_start += 1
        if name != TARGET_TITLE and name not in post_start_titles:
            post_start_titles.append(name)

result["total_notes_post_start"] = total_post_start
# Only surface "other_post_start_titles" when the target note is MISSING; the
# verifier's wrong-target gate fires only in that case, and emitting these
# names otherwise just bloats the result JSON.
if result["matching_count"] == 0:
    result["other_post_start_titles"] = post_start_titles
else:
    result["other_post_start_titles"] = []

# ---------------------------------------------------------------------------
# Step 4: phrase checks on the body text. Each check is permissive on
# whitespace and case-insensitive so list-style formatting variants ("- "
# vs "\u2022 " vs no prefix) don't break the verifier. The exact phrases come
# from the task description.
# ---------------------------------------------------------------------------
body_norm = re.sub(r"\s+", " ", result["note_body_text"]).strip().lower()
result["line_hire"] = "hire 3 senior engineers" in body_norm
result["line_okr"] = ("q3 okr" in body_norm) and (
    "$5m" in body_norm or "5m revenue" in body_norm or "$5 m" in body_norm
)
result["line_launch"] = "2026-08-15" in body_norm

with open("/tmp/create_meeting_agenda_result.json", "w") as f:
    json.dump(result, f, indent=2)

print(json.dumps(result, indent=2, default=str))
PYEOF

echo "=== Export complete ==="
