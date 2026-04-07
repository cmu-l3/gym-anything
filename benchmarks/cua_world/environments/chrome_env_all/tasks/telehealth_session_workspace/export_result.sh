#!/usr/bin/env bash
set -euo pipefail

echo "=== Exporting Telehealth Session Workspace Result ==="

# Record task end time
date +%s > /tmp/task_end_time.txt

# Take final screenshot BEFORE closing Chrome (to capture UI state)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Check if completion file exists and record stat info before stopping
FILE_CREATED_DURING_TASK="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

if [ -f "/home/ga/Desktop/setup_complete.txt" ]; then
    OUTPUT_MTIME=$(stat -c %Y "/home/ga/Desktop/setup_complete.txt" 2>/dev/null || echo "0")
    if [ "$OUTPUT_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
fi

# Gracefully close Chrome to flush SQLite WAL files and JSON Preferences to disk
echo "Flushing Chrome data..."
pkill -15 -f "google-chrome" 2>/dev/null || true
sleep 3
pkill -9 -f "google-chrome" 2>/dev/null || true
sleep 1

# Export metadata about the file creation
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "file_created_during_task": $FILE_CREATED_DURING_TASK
}
EOF
chmod 666 /tmp/task_result.json

echo "=== Export Complete ==="