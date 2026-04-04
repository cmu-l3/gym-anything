#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Prescription Price Comparison Result ==="

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

# Close any text editors that might be open
pkill -u ga -f "xdg-open.*pharmacy_quotes.txt" || true
pkill -u ga gedit || true
pkill -u ga xed || true

# Wait a moment for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/medication_costs.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
    
    # Quick sanity check - file should be larger than the blank template
    FILE_SIZE=$(stat -c%s "$SHEET_PATH")
    if [ "$FILE_SIZE" -gt 8000 ]; then
        echo "✅ Spreadsheet appears to have content (size: $FILE_SIZE bytes)"
    else
        echo "⚠️ Spreadsheet may be empty (size: $FILE_SIZE bytes)"
    fi
else
    echo "⚠️ Spreadsheet not found: $SHEET_PATH"
fi

echo "=== Export Complete ==="