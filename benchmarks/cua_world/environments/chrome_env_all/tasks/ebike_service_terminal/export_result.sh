#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting E-Bike Service Terminal task results ==="

# Record task end time
date +%s > /tmp/export_timestamp.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush all preferences/bookmarks to disk
echo "Closing Chrome to flush data..."
pkill -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Ensure permissions on Chrome files so verifier can copy them
chmod -R 755 /home/ga/.config/google-chrome/Default 2>/dev/null || true

echo "=== Export complete ==="