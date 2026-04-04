#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Relationship Contact Log Result ==="

# Close any text editors that might be open
pkill -u ga gedit 2>/dev/null || true
sleep 1

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 3

    # Close ONLYOFFICE
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    kill_onlyoffice ga
fi

# Wait a moment for file to be fully written
sleep 2

SHEET_PATH="/home/ga/Documents/Spreadsheets/martha_contact_log.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Contact log spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
    
    # Check if file size is reasonable (more than just the starter template)
    FILE_SIZE=$(stat -c%s "$SHEET_PATH")
    if [ "$FILE_SIZE" -gt 8000 ]; then
        echo "✅ File size: $FILE_SIZE bytes (contains data)"
    else
        echo "⚠️ File size: $FILE_SIZE bytes (possibly incomplete)"
    fi
else
    echo "⚠️ Contact log spreadsheet not found: $SHEET_PATH"
fi

echo "=== Export Complete ==="