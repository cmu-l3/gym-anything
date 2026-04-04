#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Job Hunt Tracker Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "ONLYOFFICE is running, attempting to save..."
    focus_onlyoffice_window || true
    sleep 1
    
    # Save document
    save_document ga :1
    sleep 2
    
    # Try to save again (sometimes first save doesn't register)
    save_document ga :1
    sleep 2

    # Close ONLYOFFICE gracefully
    echo "Closing ONLYOFFICE..."
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "ONLYOFFICE still running, force killing..."
    kill_onlyoffice ga
    sleep 2
fi

# Wait for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/job_applications.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Job tracker spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
    
    # Quick validation that file is readable
    file "$SHEET_PATH"
else
    echo "⚠️ Job tracker spreadsheet not found: $SHEET_PATH"
    echo "Searching for any .xlsx files in Documents..."
    find /home/ga/Documents -name "*.xlsx" -type f 2>/dev/null || true
fi

echo "=== Export Complete ==="