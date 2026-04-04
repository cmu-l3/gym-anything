#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Creek Monitoring Dataset Result ==="

# Close the text editor if it's still open
pkill -u ga mousepad || true
sleep 1

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "ONLYOFFICE is running, attempting to save..."
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 3

    # Close ONLYOFFICE
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "Force closing ONLYOFFICE..."
    kill_onlyoffice ga
    sleep 2
fi

# Wait a moment for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/mill_creek_data.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
    
    # Quick sanity check on file size (should be > 5KB if data was entered)
    FILE_SIZE=$(stat -c%s "$SHEET_PATH")
    if [ "$FILE_SIZE" -gt 5000 ]; then
        echo "✅ File size looks reasonable: $FILE_SIZE bytes"
    else
        echo "⚠️ File size seems small: $FILE_SIZE bytes (might be empty)"
    fi
else
    echo "⚠️ Spreadsheet not found: $SHEET_PATH"
    echo "Checking if file exists elsewhere..."
    find /home/ga/Documents -name "mill_creek_data.xlsx" -ls || true
fi

echo "=== Export Complete ==="