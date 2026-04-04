#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Gig Income Reconciliation Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "Focusing ONLYOFFICE window..."
    focus_onlyoffice_window || true
    sleep 1
    
    echo "Saving document..."
    save_document ga :1
    sleep 3
    
    # Try saving again to be sure
    save_document ga :1
    sleep 2

    # Close ONLYOFFICE
    echo "Closing ONLYOFFICE..."
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is fully closed
if is_onlyoffice_running; then
    echo "Force closing ONLYOFFICE..."
    kill_onlyoffice ga
fi

# Wait for file to be fully written
sleep 2

SHEET_PATH="/home/ga/Documents/Spreadsheets/gig_income_analysis.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
    
    # Verify file is not empty
    FILE_SIZE=$(stat -c%s "$SHEET_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 5000 ]; then
        echo "✅ Spreadsheet file size: $FILE_SIZE bytes (looks good)"
    else
        echo "⚠️ WARNING: Spreadsheet file size is only $FILE_SIZE bytes (might be empty)"
    fi
else
    echo "❌ ERROR: Spreadsheet not found: $SHEET_PATH"
    echo "Checking directory contents:"
    ls -la /home/ga/Documents/Spreadsheets/ || true
fi

# Close any text editor windows that might be open
pkill -u ga gedit || true
pkill -u ga xed || true
pkill -u ga mousepad || true

echo "=== Export Complete ==="