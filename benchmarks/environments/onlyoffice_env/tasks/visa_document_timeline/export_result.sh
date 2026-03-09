#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Visa Document Timeline Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "ONLYOFFICE is running, attempting to save..."
    focus_onlyoffice_window || true
    sleep 1
    save_document ga :1
    sleep 2

    # Close ONLYOFFICE
    echo "Closing ONLYOFFICE..."
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "ONLYOFFICE still running, force closing..."
    kill_onlyoffice ga
    sleep 1
fi

# Wait a moment for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/visa_tracker.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
    
    # Try to get a quick peek at file size to ensure it's not empty
    FILESIZE=$(stat -c%s "$SHEET_PATH" 2>/dev/null || echo "0")
    if [ "$FILESIZE" -gt 5000 ]; then
        echo "✅ File size looks good: ${FILESIZE} bytes"
    else
        echo "⚠️  File might be empty or minimal: ${FILESIZE} bytes"
    fi
else
    echo "❌ Spreadsheet not found: $SHEET_PATH"
fi

echo "=== Export Complete ==="