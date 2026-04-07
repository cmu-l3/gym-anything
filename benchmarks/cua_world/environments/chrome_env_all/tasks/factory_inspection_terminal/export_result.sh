#!/bin/bash
# set -euo pipefail

echo "=== Exporting Factory Inspection Terminal Configuration Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot before doing anything else
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush all SQLite DBs and JSON data to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome-browser" 2>/dev/null || true
sleep 3

# Force kill if still running
pkill -9 -f "google-chrome" 2>/dev/null || true
pkill -9 -f "chrome-browser" 2>/dev/null || true
sleep 1

echo "=== Export Complete ==="