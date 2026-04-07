#!/bin/bash
echo "=== Exporting osw_enable_do_not_track results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot BEFORE killing Chrome
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush Preferences to disk
echo "Closing Chrome to flush settings to disk..."
pkill -f "google-chrome" 2>/dev/null || true
pkill -f "chrome.*remote-debugging-port" 2>/dev/null || true
sleep 4

# Force kill any remaining Chrome processes
pkill -9 -f chrome 2>/dev/null || true
sleep 1

echo "=== Export complete ==="
