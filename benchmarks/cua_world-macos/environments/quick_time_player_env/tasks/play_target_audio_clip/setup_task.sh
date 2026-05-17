#!/bin/bash
# pre_task hook for play_target_audio_clip.
#
# Responsibilities:
#   1. Force-quit any prior QuickTime so the document list starts clean (the
#      "front document" check would otherwise be ambiguous if a stale clip
#      from a previous reset is still loaded).
#   2. Re-stage the target audio file from /System/Library/Sounds/Funk.aiff
#      to ~/Documents/qtp_target_audio.aiff. Always copy fresh so an earlier
#      task that modified the file can't bleed state. Anti-gaming Pattern #6:
#      deleting and re-creating gives a clean mtime baseline.
#   3. Record an authoritative task-start Unix timestamp.
#   4. Open QuickTime Player with the target file via `open -a`. This loads
#      the file into a paused document at current_time=0.0 — confirmed via
#      AppleScript probe (2026-05-17). No autoplay.
#   5. Poll lsappinfo until the bundle re-registers, then briefly settle so
#      AppleScript queries don't race with window-creation events.
#
# NOTE on agent-visible state: the staged filename `qtp_target_audio.aiff`
# IS visible to the agent — it appears both in task.json's `description`
# field (intended; the task pins the verified document by name) and in
# QuickTime Player's window title bar after the file is opened. What is
# kept OFF the agent's perceptual channel is the *source* of the staged
# file (`/System/Library/Sounds/Funk.aiff`) — the agent never sees that
# path, only the writeable copy under ~/Documents/. The echoes below in
# this script land in `/Users/lume/task_pre_task.log` (host-visible for
# debugging) and are not surfaced to the agent through screenshots or
# UI tree observations.
set -eu

echo "=== Setting up play_target_audio_clip ==="

# 1) Clean slate for QuickTime
osascript -e 'tell application "QuickTime Player" to quit' 2>/dev/null || true
sleep 2
pkill -x "QuickTime Player" 2>/dev/null || true
sleep 1

# 2) Re-stage the audio file. Source is a small Apple system sound (~2.16s)
#    shipped on every macOS. Copying gives a fresh mtime baseline and lets
#    the verifier detect file-replacement adversarial scenarios.
SRC="/System/Library/Sounds/Funk.aiff"
DEST="$HOME/Documents/qtp_target_audio.aiff"
mkdir -p "$HOME/Documents"
rm -f "$DEST"
cp "$SRC" "$DEST"
echo "staged: $DEST ($(/usr/bin/stat -f %z "$DEST") bytes)"

# 3) Record task start (Unix epoch). export_result.sh re-reads this to
#    detect "file modified after task start" (anti-replacement signal).
date +%s > /tmp/task_start_timestamp
echo "task_start_unix=$(cat /tmp/task_start_timestamp)"

# 4) Open with QuickTime — single `open -a` will both launch and load the
#    file because we just killed QuickTime above.
open -a "QuickTime Player" "$DEST"

# 5) Wait for the bundle to register
for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qF 'bundleID="com.apple.QuickTimePlayerX"'; then
    echo "QuickTime Player registered after ${i}s"
    break
  fi
  sleep 1
done

# Settle so AppleScript document queries don't race a half-open document.
sleep 3

# Probe the loaded state and log it (useful when a future debug session
# needs to know what the start state actually looked like).
LOADED_NAME=$(osascript -e 'tell application "QuickTime Player" to get name of front document' 2>/dev/null || echo "<no document>")
LOADED_TIME=$(osascript -e 'tell application "QuickTime Player" to get current time of front document' 2>/dev/null || echo "0.0")
echo "loaded document: $LOADED_NAME"
echo "current_time at start: $LOADED_TIME"

# Optional start-state screenshot for the trajectory archive (no-op safe).
/usr/sbin/screencapture -x /tmp/task_start.png 2>/dev/null || true

echo "=== play_target_audio_clip setup complete ==="
echo "QuickTime Player is running with qtp_target_audio.aiff paused at 0:00."
