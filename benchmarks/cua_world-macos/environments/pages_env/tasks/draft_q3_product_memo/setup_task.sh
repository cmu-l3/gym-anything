#!/bin/bash
# pre_task hook for draft_q3_product_memo on Apple Pages / macOS.
#
# Responsibilities:
#   1. Delete any pre-existing .pages file at the target path so a do-nothing
#      agent cannot claim credit for a leftover file from a prior run.
#   2. Snapshot the set of .pages files under ~/Documents BEFORE the task
#      runs (filename + mtime). The export script diffs against this snapshot
#      to detect "agent saved a doc with the wrong filename" wrong-target
#      cases.
#   3. Record an authoritative task-start Unix timestamp.
#   4. Launch Pages, wait for the window to register, then `make new document`
#      via AppleScript to bypass the Template Chooser modal.
#
# Intentionally NOT killing any prior Pages instance: the launch_pages smoke
# task's setup_task.sh (no kill) produces consistently-visible window
# screenshots, while a quit+pkill+relaunch sequence here previously left
# `screencapture` racing a not-yet-rendered window (lsappinfo says registered
# but the window frame isn't on screen yet). The rm -rf below and the
# pre-snapshot file provide all the clean-state guarantees the verifier
# needs without the kill latency.
set -eu

TARGET_PATH="/Users/lume/Documents/Q3 Product Strategy Memo.pages"

echo "=== Setting up draft_q3_product_memo ==="

# 1) Remove any pre-existing target file. .pages files are bundle directories
# (Pages 09 format is a zip; modern Pages uses a flat package directory) so
# rm -rf handles both shapes. Belt and suspenders against a stale leftover
# from a prior run satisfying the verifier's C1.
rm -rf "$TARGET_PATH" 2>/dev/null || true
mkdir -p "$(dirname "$TARGET_PATH")"

# 2) Snapshot the pre-task state of ~/Documents/*.pages. Format: one line per
# file, "<basename>\t<mtime-epoch>". The export script reads this and computes
# "files modified after task_start that don't match the target path" \u2014 those
# are wrong-target candidates.
SNAPSHOT="/tmp/draft_q3_product_memo_pre_snapshot.tsv"
: > "$SNAPSHOT"
# `find` enumerates real .pages bundles; -prune is required so we don't
# descend into them (they're package directories). Tolerate empty ~/Documents.
if [ -d "/Users/lume/Documents" ]; then
  find /Users/lume/Documents -maxdepth 1 -name '*.pages' -print0 2>/dev/null \
    | while IFS= read -r -d '' f; do
        mtime=$(/usr/bin/stat -f %m "$f" 2>/dev/null || echo "0")
        printf '%s\t%s\n' "$(basename "$f")" "$mtime" >> "$SNAPSHOT"
      done
fi
echo "pre_snapshot entries: $(wc -l < "$SNAPSHOT" | tr -d ' ')"

# 3) Record task start (Unix epoch, seconds). The export script compares
# .pages file mtimes against this to decide "fresh" vs "pre-existing".
date +%s > /tmp/task_start_timestamp
echo "task_start_unix=$(cat /tmp/task_start_timestamp)"

# 4) Launch Pages, wait for window registration, open a fresh blank doc.
# Idempotent: if Pages is already running (unlikely on fresh sandbox; possible
# on cached/restarted ones), `open -a` is a no-op and the lsappinfo poll
# returns immediately.
open -a Pages
for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qF 'bundleID="com.apple.iWork.Pages"'; then
    echo "Pages window registered after ${i}s"
    break
  fi
  sleep 1
done
sleep 2

# `make new document` bypasses the Template Chooser modal that fresh-launched
# Pages shows. Without this, the agent sees a 'Choose a Template' panel
# blocking the document area on first launch.
/usr/bin/osascript -e 'tell application "Pages" to make new document' 2>&1 || true
sleep 2

# Intentionally NOT calling /usr/sbin/screencapture here: on the use.computer
# base-macos sandbox, /usr/sbin/screencapture run over SSH captures only the
# wallpaper + menu bar and misses the Pages window, while
# sb.screenshot.take_full_screen() (the SDK path) renders the full desktop
# including app windows. The SDK screenshot is what the agent actually
# observes via the runner, so we let the framework's per-step capture be the
# authoritative trajectory artifact and skip the misleading SSH-context
# screencapture side-channel. Same fix as
# apple_notes_env/tasks/create_meeting_agenda/setup_task.sh.

echo "=== draft_q3_product_memo setup complete ==="
echo "Pages is running with a blank document. Agent must type 3 priority lines and save to:"
echo "  $TARGET_PATH"
