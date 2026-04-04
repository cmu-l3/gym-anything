#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Medical EOB Decoder Result ==="

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

# Wait a moment for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/EOB_Decoded_2024.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
    
    # Quick check of file size (should be more than initial blank if user added content)
    FILE_SIZE=$(stat -f%z "$SHEET_PATH" 2>/dev/null || stat -c%s "$SHEET_PATH" 2>/dev/null || echo "0")
    if [ "$FILE_SIZE" -gt 8000 ]; then
        echo "✅ File size: ${FILE_SIZE} bytes (contains substantial content)"
    else
        echo "⚠️ File size: ${FILE_SIZE} bytes (may be incomplete)"
    fi
else
    echo "❌ Spreadsheet not found: $SHEET_PATH"
fi

echo "=== Export Complete ==="