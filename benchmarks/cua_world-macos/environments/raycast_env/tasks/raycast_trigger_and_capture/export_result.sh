#!/bin/bash
# post_task hook for raycast_trigger_and_capture.
#
# Produces /tmp/raycast_trigger_and_capture_result.json with:
#   - task_start (unix epoch)
#   - initial_wal_size_bytes (from setup_task.sh)
#   - screenshot_path (the target deliverable path)
#   - screenshot_exists (bool)
#   - screenshot_mtime (unix epoch, 0 if missing)
#   - screenshot_size_bytes (int)
#   - screenshot_is_screencapture (bool — kMDItemIsScreenCapture xattr present?)
#   - wal_size_bytes (int — current size of activity SQLite WAL)
#   - wal_size_delta_bytes (int — wal_size - initial_wal_size)
#   - raycast_still_running (bool)

set -u   # NOT set -e \u2014 individual stages should continue on error.

TARGET_SCREENSHOT="/Users/lume/Desktop/raycast_screenshot.png"
ACTIVITY_WAL="/Users/lume/Library/Application Support/com.raycast.macos/raycast-activities-enc.sqlite-wal"

echo "=== Exporting raycast_trigger_and_capture results ==="

TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
INITIAL_WAL_SIZE=$(cat /tmp/raycast_initial_wal_size 2>/dev/null || echo "0")
echo "task_start_unix=$TASK_START"
echo "initial_wal_size_bytes=$INITIAL_WAL_SIZE"

# Make sure Raycast has had a moment to flush its activity log to the WAL
# before we measure size. Raycast uses SQLite with WAL mode; flushes are
# typically prompt but a small settle helps in fast post_task hooks.
sleep 2

# Drive the rest from a Python heredoc \u2014 every block has try/except so a
# single failure never produces unparseable JSON (Anti-Pattern #12).
/usr/bin/python3 - "$TASK_START" "$INITIAL_WAL_SIZE" "$TARGET_SCREENSHOT" "$ACTIVITY_WAL" << 'PYEOF'
import json
import os
import plistlib
import subprocess
import sys

TASK_START = int(sys.argv[1] or "0")
INITIAL_WAL_SIZE = int(sys.argv[2] or "0")
SCREENSHOT_PATH = sys.argv[3]
WAL_PATH = sys.argv[4]

result = {
    "task_start": TASK_START,
    "initial_wal_size_bytes": INITIAL_WAL_SIZE,
    "screenshot_path": SCREENSHOT_PATH,
    "screenshot_exists": False,
    "screenshot_mtime": 0,
    "screenshot_size_bytes": 0,
    "screenshot_is_screencapture": False,
    "wal_size_bytes": 0,
    "wal_size_delta_bytes": 0,
    "raycast_still_running": False,
}

# --- Screenshot file checks -----------------------------------------------
try:
    if os.path.isfile(SCREENSHOT_PATH):
        result["screenshot_exists"] = True
        st = os.stat(SCREENSHOT_PATH)
        result["screenshot_mtime"] = int(st.st_mtime)
        result["screenshot_size_bytes"] = int(st.st_size)
except Exception as exc:
    result["screenshot_stat_error"] = f"{type(exc).__name__}: {exc}"

# --- Screencapture xattr (com.apple.metadata:kMDItemIsScreenCapture) ------
# `/usr/sbin/screencapture` writes a binary-plist-encoded `true` to this
# xattr. Reading with `xattr -px` returns the hex-encoded bytes; we then
# parse via plistlib. The presence + True value is what proves the file
# was made by the screencapture utility (not a hand-crafted PNG).
if result["screenshot_exists"]:
    try:
        r = subprocess.run(
            ["/usr/bin/xattr", "-px",
             "com.apple.metadata:kMDItemIsScreenCapture", SCREENSHOT_PATH],
            capture_output=True, text=True, timeout=10,
        )
        if r.returncode == 0 and r.stdout.strip():
            hex_blob = "".join(r.stdout.split())
            try:
                val = plistlib.loads(bytes.fromhex(hex_blob))
                result["screenshot_is_screencapture"] = bool(val)
            except Exception as exc:
                result["screencap_xattr_parse_error"] = f"{type(exc).__name__}: {exc}"
    except Exception as exc:
        result["screencap_xattr_read_error"] = f"{type(exc).__name__}: {exc}"

# --- Raycast activity WAL size + delta ------------------------------------
try:
    if os.path.isfile(WAL_PATH):
        wal_size = int(os.path.getsize(WAL_PATH))
        result["wal_size_bytes"] = wal_size
        result["wal_size_delta_bytes"] = wal_size - INITIAL_WAL_SIZE
except Exception as exc:
    result["wal_stat_error"] = f"{type(exc).__name__}: {exc}"

# --- Raycast process state -------------------------------------------------
try:
    r = subprocess.run(
        ["/usr/bin/pgrep", "-x", "Raycast"],
        capture_output=True, text=True, timeout=5,
    )
    result["raycast_still_running"] = (r.returncode == 0 and bool(r.stdout.strip()))
except Exception as exc:
    result["pgrep_error"] = f"{type(exc).__name__}: {exc}"

with open("/tmp/raycast_trigger_and_capture_result.json", "w") as f:
    json.dump(result, f, indent=2)
print(json.dumps(result, indent=2, default=str))
PYEOF

echo "=== Export complete ==="
