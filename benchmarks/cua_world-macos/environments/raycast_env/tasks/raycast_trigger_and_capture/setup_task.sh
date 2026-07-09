#!/bin/bash
# pre_task hook for raycast_trigger_and_capture.
#
# Responsibilities:
#   1. Launch Raycast (idempotent).
#   2. Delete any pre-existing screenshot at the deliverable path so a
#      stale file from a previous run cannot satisfy the verifier.
#   3. Record an authoritative task-start Unix timestamp.
#   4. Record the initial size of Raycast's encrypted activity SQLite WAL.
#      The verifier's wrong-target gate fires when this size hasn't grown
#      after task start \u2014 i.e., the agent never actually triggered Raycast.
set -eu

TARGET_SCREENSHOT="/Users/lume/Desktop/raycast_screenshot.png"
ACTIVITY_WAL="/Users/lume/Library/Application Support/com.raycast.macos/raycast-activities-enc.sqlite-wal"

echo "=== Setting up raycast_trigger_and_capture ==="

# 1) Launch Raycast (idempotent). Mirrors launch_raycast/setup_task.sh.
if ! pgrep -x "Raycast" >/dev/null; then
  echo "[pre_task] launching Raycast"
  if ! open -a "Raycast" 2>/dev/null; then
    echo "[pre_task] 'open -a Raycast' failed, falling back to bundle path"
    open /Applications/Raycast.app
  fi
fi
for i in $(seq 1 45); do
  if /usr/bin/lsappinfo list 2>/dev/null | grep -qE 'Raycast\.app'; then
    echo "[pre_task] Raycast registered after ${i}s"
    break
  fi
  sleep 1
done

# 2) Delete any pre-existing screenshot file at the deliverable path. This
# is anti-gaming belt-and-suspenders: the verifier's freshness check
# (mtime > task_start) is the primary guard, but deleting up front makes
# do-nothing produce a clean "file does not exist" rather than relying on
# the freshness gate alone.
rm -f "$TARGET_SCREENSHOT" 2>/dev/null || true
mkdir -p /Users/lume/Desktop

# 3) Record task start (Unix epoch, seconds).
date +%s > /tmp/task_start_timestamp
echo "task_start_unix=$(cat /tmp/task_start_timestamp)"

# 4) Record initial activity-WAL size so the verifier can compute a growth
# delta. Raycast does some background activity that may touch this file
# even when the agent is idle, but the URL-scheme trigger causes a much
# larger spike than background ticks (≥1 KB observed in probes). The
# verifier uses a 1024-byte growth threshold as the wrong-target gate.
#
# We let Raycast settle for a couple seconds after launch so background
# init writes finish before we snapshot.
sleep 3
if [ -f "$ACTIVITY_WAL" ]; then
  INITIAL_WAL_SIZE=$(/usr/bin/stat -f %z "$ACTIVITY_WAL" 2>/dev/null || echo 0)
else
  INITIAL_WAL_SIZE=0
fi
echo "$INITIAL_WAL_SIZE" > /tmp/raycast_initial_wal_size
echo "initial_wal_size_bytes=$INITIAL_WAL_SIZE"

echo "=== raycast_trigger_and_capture setup complete ==="
echo "Agent must trigger Raycast via an extension-path URL scheme (e.g., from Terminal:"
echo "  open 'raycast://extensions/raycast/clipboard-history/clipboard-history')"
echo "then capture a screenshot via /usr/sbin/screencapture to $TARGET_SCREENSHOT."
echo "(Visible-only URLs like raycast://confetti will NOT satisfy the activity-WAL gate.)"
