#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Yard Sale Tracker Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2

    # Close ONLYOFFICE
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    kill_onlyoffice ga
fi

# Wait a moment for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/yard_sale_tracker.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Yard sale tracker saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
    
    # Quick validation that file is not just the template
    FILE_SIZE=$(stat -c%s "$SHEET_PATH" 2>/dev/null || stat -f%z "$SHEET_PATH" 2>/dev/null || echo 0)
    if [ "$FILE_SIZE" -gt 7000 ]; then
        echo "✅ File size looks reasonable ($FILE_SIZE bytes)"
    else
        echo "⚠️ File size seems small ($FILE_SIZE bytes) - may not have enough content"
    fi
else
    echo "⚠️ Yard sale tracker not found: $SHEET_PATH"
fi

echo "=== Export Complete ==="