#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting College Essay Tracker Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "ONLYOFFICE is running, attempting to save..."
    focus_onlyoffice_window || true
    sleep 1
    
    # Save document multiple times to ensure it's persisted
    save_document ga :1
    sleep 2
    save_document ga :1
    sleep 1

    # Close ONLYOFFICE gracefully
    echo "Closing ONLYOFFICE..."
    close_onlyoffice ga :1
    sleep 3
fi

# Ensure ONLYOFFICE is fully closed
if is_onlyoffice_running; then
    echo "ONLYOFFICE still running, force killing..."
    kill_onlyoffice ga
    sleep 2
fi

# Wait a moment for file to be fully written to disk
sleep 2

TRACKER_PATH="/home/ga/Documents/Applications/essay_tracker.docx"

if [ -f "$TRACKER_PATH" ]; then
    echo "✅ Essay tracker saved: $TRACKER_PATH"
    ls -lh "$TRACKER_PATH"
    
    # Check file size to ensure it's not empty
    FILE_SIZE=$(stat -f%z "$TRACKER_PATH" 2>/dev/null || stat -c%s "$TRACKER_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 10000 ]; then
        echo "✅ File size looks good: $FILE_SIZE bytes"
    else
        echo "⚠️  Warning: File size is small: $FILE_SIZE bytes (expected > 10KB)"
    fi
else
    echo "⚠️  Essay tracker not found at expected location: $TRACKER_PATH"
    echo "Searching for any .docx files in Applications directory..."
    find /home/ga/Documents/Applications/ -name "*.docx" -ls || true
fi

echo "=== Export Complete ==="