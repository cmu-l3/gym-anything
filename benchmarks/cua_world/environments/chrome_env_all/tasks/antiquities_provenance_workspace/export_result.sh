#!/usr/bin/env bash
echo "=== Exporting Antiquities Provenance Workspace Result ==="

DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Close Chrome gracefully to flush Preferences and Bookmarks memory to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

date +%s > /tmp/export_timestamp

echo "=== Export Complete ==="