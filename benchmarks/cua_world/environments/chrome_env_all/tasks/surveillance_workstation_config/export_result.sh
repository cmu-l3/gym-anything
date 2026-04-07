#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Disease Surveillance Browser Configuration Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

# Check if Chrome is running
CHROME_RUNNING=$(pgrep -f "google-chrome" > /dev/null && echo "true" || echo "false")

# Gracefully close Chrome to ensure all Preferences, Web Data, and Local State DBs are flushed to disk
echo "Closing Chrome to flush data to disk..."
if [ "$CHROME_RUNNING" = "true" ]; then
    pkill -15 -f "google-chrome" 2>/dev/null || true
    sleep 3
    # Force kill if still lingering
    pkill -9 -f "google-chrome" 2>/dev/null || true
    sleep 1
fi

echo "Data flushed. Verification ready."
echo "=== Export complete ==="