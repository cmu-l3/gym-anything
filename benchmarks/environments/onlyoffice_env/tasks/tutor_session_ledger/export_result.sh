#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Tutoring Session Ledger Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    focus_onlyoffice_window || true
    save_document ga :1
    sleep 2

    # Second save attempt to ensure data is written
    save_document ga :1
    sleep 1

    # Close ONLYOFFICE
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    kill_onlyoffice ga
    sleep 1
fi

# Wait a moment for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/session_ledger.xlsx"

if [ -f "$SHEET_PATH" ]; then
    FILE_SIZE=$(stat -c%s "$SHEET_PATH" 2>/dev/null || stat -f%z "$SHEET_PATH" 2>/dev/null || echo "0")
    echo "✅ Session ledger saved: $SHEET_PATH"
    echo "   File size: $FILE_SIZE bytes"
    ls -lh "$SHEET_PATH" 2>/dev/null || true
    
    if [ "$FILE_SIZE" -lt 5000 ]; then
        echo "⚠️ Warning: File seems small, may not be complete"
    fi
else
    echo "❌ Session ledger not found: $SHEET_PATH"
    exit 1
fi

echo "=== Export Complete ==="