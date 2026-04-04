#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Coworking Optimizer Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    
    # Save document (Ctrl+S)
    save_document ga :1
    sleep 2
    
    # Try saving again to be sure
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
sleep 2

SHEET_PATH="/home/ga/Documents/Spreadsheets/coworking_comparison.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
else
    echo "⚠️ Spreadsheet not found at expected location: $SHEET_PATH"
    echo "Searching for any XLSX files in Spreadsheets directory:"
    find /home/ga/Documents/Spreadsheets -name "*.xlsx" -type f -ls 2>/dev/null || echo "No XLSX files found"
fi

echo "=== Export Complete ==="