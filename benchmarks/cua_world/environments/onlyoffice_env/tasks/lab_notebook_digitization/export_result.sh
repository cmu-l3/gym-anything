#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Lab Notebook Digitization Result ==="

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

# Close gedit if still running
GEDIT_PID=$(pgrep -u ga gedit || true)
if [ -n "$GEDIT_PID" ]; then
    echo "Closing text editor..."
    sudo -u ga pkill gedit || true
    sleep 1
fi

# Wait a moment for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/lab_notebook_digitization/growth_data_cleaned.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
    
    # Quick check of file size (should be > 5KB if properly filled)
    FILE_SIZE=$(stat -f%z "$SHEET_PATH" 2>/dev/null || stat -c%s "$SHEET_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 5000 ]; then
        echo "✅ File size looks reasonable: ${FILE_SIZE} bytes"
    else
        echo "⚠️ File size seems small: ${FILE_SIZE} bytes (expected > 5KB)"
    fi
else
    echo "⚠️ Spreadsheet not found: $SHEET_PATH"
    echo "Checking if file exists with similar name..."
    ls -la /home/ga/Documents/lab_notebook_digitization/ || true
fi

echo "=== Export Complete ==="