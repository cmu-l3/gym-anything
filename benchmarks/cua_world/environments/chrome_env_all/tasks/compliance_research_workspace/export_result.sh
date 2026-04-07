#!/bin/bash
# Export script for Compliance Research Workspace
# Ensures Chrome data is flushed to disk for verification

echo "=== Exporting Compliance Research Workspace Result ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

# Gracefully close Chrome to flush all data to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3

# Force kill if still running
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Record export timestamp
date +%s > /tmp/export_timestamp

echo "=== Export Complete ==="
