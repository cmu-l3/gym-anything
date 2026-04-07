#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Tax Season Workspace Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Capture final visual state before closing Chrome
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush SQLite WAL and Preferences to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Export timestamp
date +%s > /tmp/export_timestamp.txt

echo "=== Export Complete ==="