#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Subscription Audit Calculator Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "OnlyOffice is running, attempting to save..."
    focus_onlyoffice_window || true
    sleep 1
    save_document ga :1
    sleep 2

    # Close ONLYOFFICE
    echo "Closing OnlyOffice..."
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "Force killing OnlyOffice..."
    kill_onlyoffice ga
    sleep 1
fi

# Wait a moment for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/subscriptions_raw.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
    
    # Quick sanity check on file size (should be > 5KB for valid XLSX)
    FILE_SIZE=$(stat -c%s "$SHEET_PATH")
    if [ "$FILE_SIZE" -gt 5000 ]; then
        echo "✅ File size looks valid: ${FILE_SIZE} bytes"
    else
        echo "⚠️ Warning: File size seems small: ${FILE_SIZE} bytes"
    fi
else
    echo "❌ ERROR: Spreadsheet not found: $SHEET_PATH"
    echo "Checking directory contents:"
    ls -la /home/ga/Documents/Spreadsheets/ || echo "Directory does not exist"
fi

echo "=== Export Complete ==="