#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Ham Radio Contest Log Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    
    # Save with Ctrl+S
    save_document ga :1
    sleep 2
    
    # Try to close with Ctrl+Q first
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "Force closing ONLYOFFICE..."
    kill_onlyoffice ga
    sleep 1
fi

# Wait a moment for file to be fully written
sleep 1

RESULT_PATH="/home/ga/Documents/Spreadsheets/fieldday_score.xlsx"

if [ -f "$RESULT_PATH" ]; then
    echo "✅ Scored log saved: $RESULT_PATH"
    ls -lh "$RESULT_PATH"
else
    echo "⚠️ Scored log not found at: $RESULT_PATH"
    echo "Checking if raw log was modified instead..."
    RAW_PATH="/home/ga/Documents/Spreadsheets/fieldday_raw_log.xlsx"
    if [ -f "$RAW_PATH" ]; then
        echo "📄 Raw log exists: $RAW_PATH"
        ls -lh "$RAW_PATH"
    fi
fi

echo "=== Export Complete ==="