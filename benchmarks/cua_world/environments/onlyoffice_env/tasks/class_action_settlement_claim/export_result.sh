#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Exporting Class Action Settlement Claim Result ==="

# Focus ONLYOFFICE and save
if is_onlyoffice_running; then
    echo "Focusing ONLYOFFICE window..."
    focus_onlyoffice_window || true
    sleep 1
    
    echo "Saving document..."
    save_document ga :1
    sleep 2

    # Close ONLYOFFICE
    echo "Closing ONLYOFFICE..."
    close_onlyoffice ga :1
    sleep 2
fi

# Ensure ONLYOFFICE is closed
if is_onlyoffice_running; then
    echo "Force closing ONLYOFFICE..."
    kill_onlyoffice ga
fi

# Wait a moment for file to be fully written
sleep 1

SHEET_PATH="/home/ga/Documents/Spreadsheets/class_action_claims.xlsx"

if [ -f "$SHEET_PATH" ]; then
    echo "✅ Spreadsheet saved: $SHEET_PATH"
    ls -lh "$SHEET_PATH"
else
    echo "⚠️ Spreadsheet not found: $SHEET_PATH"
fi

echo "=== Export Complete ==="