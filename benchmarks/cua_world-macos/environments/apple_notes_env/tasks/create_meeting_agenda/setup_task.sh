#!/bin/bash
# pre_task hook for create_meeting_agenda on Apple Notes/macOS.
#
# Convention note: per 12_macos_environments.md the canonical pre_task is just
# "launch the app and wait for the window". This script DELIBERATELY deviates
# by first quitting Notes before relaunching it. Reason: the AppleScript
# `delete note` step below modifies the live CoreData NoteStore, and Notes'
# in-memory cache can race with that delete if the app was running across the
# previous task's lifetime (a stale model can re-materialize the note). Quit +
# relaunch flushes the cache. The end state matches the convention (Notes is
# running, window registered) before the agent gets control. For tasks that
# don't need a state reset, prefer the idempotent launch in
# launch_apple_notes/setup_task.sh.
#
# Responsibilities:
#   1. Force-quit any prior Notes (so the NoteStore starts in a known state
#      and our delete step below cannot race the app's autosave).
#   2. Record an authoritative task-start Unix timestamp.
#   3. Launch Notes, wait for the window to register.
#   4. Delete any pre-existing note whose title matches the task target so
#      the verifier's existence check cannot be satisfied by leftover state.
#      This also doubles as the "freshness" guarantee \u2014 anything matching
#      the title after the task ran must have been created by the agent.
set -eu

TARGET_TITLE="Q3 Planning Kickoff"

echo "=== Setting up create_meeting_agenda ==="

# 1) Clean slate. Quitting via AppleScript first lets Notes flush its
# CoreData store cleanly; pkill is a belt-and-suspenders fallback.
osascript -e 'tell application "Notes" to quit' 2>/dev/null || true
sleep 2
pkill -x Notes 2>/dev/null || true
sleep 1

# 2) Record task start (Unix epoch, seconds).
date +%s > /tmp/task_start_timestamp
echo "task_start_unix=$(cat /tmp/task_start_timestamp)"

# 3) Launch Notes, wait for the window to register.
open -a Notes
for i in $(seq 1 30); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qF 'bundleID="com.apple.Notes"'; then
    echo "Notes window registered after ${i}s"
    break
  fi
  sleep 1
done
sleep 3

# 4) Delete any pre-existing note with the target title. Apple Notes' AppleScript
# dictionary supports `delete note` by reference; the `whose name is X` filter
# matches case-sensitively. We tolerate failure (note may not exist; the app
# may not yet have surfaced an account folder).
osascript <<APPLESCRIPT 2>&1 || true
tell application "Notes"
  try
    set matchingNotes to (notes whose name is "$TARGET_TITLE")
    set deletedCount to 0
    repeat with n in matchingNotes
      delete n
      set deletedCount to deletedCount + 1
    end repeat
    return "deleted " & (deletedCount as text) & " pre-existing note(s) titled '$TARGET_TITLE'"
  on error errMsg
    return "delete step skipped: " & errMsg
  end try
end tell
APPLESCRIPT

# Intentionally NOT calling /usr/sbin/screencapture here: on the use.computer
# base-macos sandbox, /usr/sbin/screencapture captures only the wallpaper +
# menu bar and misses the Notes window, while sb.screenshot.take_full_screen()
# (the SDK path) renders the full desktop including app windows. The SDK
# screenshot is what the agent actually observes via the runner, so we let
# the framework's per-step capture be the authoritative trajectory artifact
# and skip the misleading screencapture side-channel.

echo "=== create_meeting_agenda setup complete ==="
echo "Notes is running. Agent must create a note titled '$TARGET_TITLE' with three required body lines."
