#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Vehicle Service History Result ==="

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

# Close any text editors that might be open
pkill -u ga -f "gedit|pluma|mousepad|xed" || true

# Wait a moment for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/car_service_log.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
    
    # Check if file has reasonable size (not empty)
    FILE_SIZE=$(stat -c%s "$SHEET_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 5000 ]; then
        echo "✅ File size looks reasonable: ${FILE_SIZE} bytes"
    else
        echo "⚠️ File size seems small: ${FILE_SIZE} bytes (might be empty or incomplete)"
    fi
else
    echo "⚠️ Spreadsheet not found: $SHEET_PATH"
fi

echo "=== Export Complete ==="