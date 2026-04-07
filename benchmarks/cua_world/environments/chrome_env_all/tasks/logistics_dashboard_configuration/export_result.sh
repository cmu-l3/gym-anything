#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Logistics Dashboard Task Result ==="

# Record end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot BEFORE closing Chrome (to capture UI state for debugging)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# ── Gracefully close Chrome to flush SQLite and JSON preferences to disk ───
echo "Gracefully closing Chrome to flush data to disk..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
# Force kill any stragglers
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

echo "Task artifacts successfully exported and data flushed to disk."
echo "=== Export Complete ==="