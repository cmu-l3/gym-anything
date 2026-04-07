#!/bin/bash
set -euo pipefail

echo "=== Exporting QA Shopfloor Terminal Result ==="

# 1. Take final screenshot before doing anything
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Record end time
date +%s > /tmp/task_end_time.txt

# 3. Gracefully close Chrome to ensure Preferences, Bookmarks, and Local State flush to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

echo "Data flushed. Verification will proceed using copy_from_env."
echo "=== Export Complete ==="