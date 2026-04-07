#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush all JSON and SQLite data to disk
echo "Closing Chrome to flush settings to disk..."
pkill -f "chrome" 2>/dev/null || true
pkill -f "google-chrome" 2>/dev/null || true
sleep 4

# Force kill if still running
pkill -9 -f "chrome" 2>/dev/null || true

echo "=== Export Complete ==="