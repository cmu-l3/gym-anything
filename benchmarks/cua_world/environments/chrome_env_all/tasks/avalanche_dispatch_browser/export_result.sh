#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Avalanche Dispatch Browser Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot for visual reference
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# IMPORTANT: Gracefully close Chrome to flush Bookmarks and Preferences to disk
echo "Closing Chrome to flush profile data..."
pkill -f "chrome" 2>/dev/null || true
pkill -f "chromium" 2>/dev/null || true
sleep 3

# Force kill if still hanging
pkill -9 -f "chrome" 2>/dev/null || true

echo "Data flushed. Verification will process the JSON files directly."
echo "=== Export Complete ==="