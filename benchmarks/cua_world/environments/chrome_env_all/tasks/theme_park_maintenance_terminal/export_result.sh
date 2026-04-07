#!/bin/bash
echo "=== Exporting Theme Park Maintenance Terminal Result ==="

# Record final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# We must gracefully close Chrome so that it flushes memory DBs (Bookmarks, History, Web Data, Preferences) to disk
echo "Closing Chrome to flush data to disk..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Mark completion
date +%s > /tmp/export_timestamp

echo "=== Export Complete ==="