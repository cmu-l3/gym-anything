#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Basement Flood Claim Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "Focusing ONLYOFFICE window..."
    focus_onlyoffice_window || true
    sleep 1
    
    echo "Saving document..."
    save_document ga :1
    sleep 3
    
    # Try saving again to ensure it's saved
    save_document ga :1
    sleep 2

    echo "Closing ONLYOFFICE..."
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "Force-closing ONLYOFFICE..."
    kill_onlyoffice ga
    sleep 2
fi

# Wait for file to be fully written
sleep 2

SHEET_PATH="/home/ga/Documents/Spreadsheets/basement_flood_claim.xlsx"

if [ -f "$SHEET_PATH" ]; then
    FILE_SIZE=$(stat -c%s "$SHEET_PATH" 2>/dev/null || echo "0")
    echo "✅ Flood claim spreadsheet saved: $SHEET_PATH"
    echo "   File size: $FILE_SIZE bytes"
    ls -lh "$SHEET_PATH"
    
    # Verify it's a valid zip file (XLSX is a zip container)
    if file "$SHEET_PATH" | grep -q "Zip\|Microsoft Excel"; then
        echo "✅ File format appears valid (XLSX)"
    else
        echo "⚠️  Warning: File may not be valid XLSX format"
    fi
else
    echo "❌ Flood claim spreadsheet not found: $SHEET_PATH"
    echo "Checking directory contents:"
    ls -la /home/ga/Documents/Spreadsheets/ || echo "Directory does not exist"
    exit 1
fi

echo "=== Export Complete ==="