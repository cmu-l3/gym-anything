#!/bin/bash
set -euo pipefail

echo "=== Exporting Financial Forensics Workspace result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Close Chrome gracefully to flush SQLite DBs and JSON files to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Record export timestamp
date +%s > /tmp/export_timestamp.txt

echo "=== Export Complete ==="