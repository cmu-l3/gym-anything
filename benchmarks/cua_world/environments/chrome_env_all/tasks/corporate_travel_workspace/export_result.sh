#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Corporate Travel Workspace Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot BEFORE killing Chrome
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Gracefully close Chrome to flush Preferences, Bookmarks, and Web Data (SQLite) to disk
echo "Closing Chrome to flush SQLite and JSON data..."
pkill -15 -f "chrome" 2>/dev/null || true
sleep 3

# Force kill if still running to release SQLite locks
pkill -9 -f "chrome" 2>/dev/null || true
sleep 2

# Export timestamps to a JSON for the verifier
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(cat /tmp/task_end_time.txt 2>/dev/null || echo "0")

cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="