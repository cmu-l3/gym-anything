#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Backcountry Permit Desk Setup Result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Gracefully close Chrome to flush Preferences, Bookmarks, History, and Local State to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3

# Force kill if still running
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 2

# Record export timestamp
date +%s > /tmp/export_timestamp

echo "=== Export Complete ==="