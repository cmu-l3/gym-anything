#!/bin/bash
set -euo pipefail

echo "=== Exporting task results ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush SQLite DBs and JSON files to disk
echo "Closing Chrome to flush data to disk..."
pkill -15 -f "chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "chrome" 2>/dev/null || true
sleep 2

# We will let the python verifier copy the files directly using copy_from_env.
# Ensure the Chrome files have read permissions just in case.
chmod -R 755 /home/ga/.config/google-chrome/Default || true

echo "=== Export complete ==="