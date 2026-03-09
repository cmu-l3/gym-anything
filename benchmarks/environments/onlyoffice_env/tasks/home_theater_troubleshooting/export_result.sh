#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Home Theater Troubleshooting Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    
    # Give agent a moment to finish any final edits
    sleep 1
    
    # Send Ctrl+S to save
    save_document ga :1
    sleep 3
    
    # Close ONLYOFFICE
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "ONLYOFFICE still running, force closing..."
    kill_onlyoffice ga
    sleep 1
fi

# Close gedit if still open
pkill -u ga gedit 2>/dev/null || true

# Wait a moment for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/theater_troubleshooting.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Troubleshooting log saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
    
    # Quick sanity check - file size should be reasonable
    FILE_SIZE=$(stat -f%z "$SHEET_PATH" 2>/dev/null || stat -c%s "$SHEET_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 5000 ]; then
        echo "✅ File size looks reasonable: ${FILE_SIZE} bytes"
    else
        echo "⚠️ Warning: File size seems small: ${FILE_SIZE} bytes"
    fi
else
    echo "⚠️ Troubleshooting log not found at expected path: $SHEET_PATH"
    echo "Searching for any .xlsx files created by user..."
    find /home/ga/Documents -name "*.xlsx" -type f 2>/dev/null || true
fi

echo "=== Export Complete ==="