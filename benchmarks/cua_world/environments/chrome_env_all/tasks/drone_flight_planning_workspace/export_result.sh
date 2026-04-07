#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Drone Flight Planning Workspace Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush all internal SQLite DBs and JSON files to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3

# Force kill if still lingering
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 2

echo "=== Export Complete ==="